import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import 'api.dart';

class SemPermissao implements Exception {
  SemPermissao(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

/// Posição atual com as checagens de permissão e GPS ligado.
Future<Position> posicaoAtual({bool precisaSempre = false}) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw SemPermissao('Ligue o GPS do celular.');
  }
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
    throw SemPermissao('Permita o acesso à localização nas configurações do app.');
  }
  if (precisaSempre && p != LocationPermission.always) {
    // Android pede "permitir o tempo todo" numa segunda etapa
    p = await Geolocator.requestPermission();
    if (p != LocationPermission.always) {
      throw SemPermissao('Escolha "Permitir o tempo todo" na localização para receber entregas com a tela apagada.');
    }
  }
  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
  );
}

/// Envia a localização do entregador enquanto ele está online:
/// a cada 50 m ou 30 s (o que vier primeiro). Parado, nada é enviado.
class RastreadorEntregador {
  RastreadorEntregador._();
  static final instancia = RastreadorEntregador._();

  StreamSubscription<Position>? _sub;
  Timer? _timer;
  Position? _ultima;
  DateTime _enviadaEm = DateTime.fromMillisecondsSinceEpoch(0);

  bool get ativo => _sub != null;

  void iniciar({bool emEntrega = false}) {
    if (_sub != null) return;
    final intervalo = Duration(seconds: emEntrega ? 15 : 30);
    final config = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
      intervalDuration: intervalo,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'RodaJusta online',
        notificationText: 'Você está recebendo ofertas de entrega.',
        enableWakeLock: true,
      ),
    );
    _sub = Geolocator.getPositionStream(locationSettings: config).listen((p) {
      _ultima = p;
      _enviar(p);
    });
    _timer = Timer.periodic(intervalo, (_) {
      final p = _ultima;
      if (p != null && DateTime.now().difference(_enviadaEm) >= intervalo) _enviar(p);
    });
  }

  Future<void> _enviar(Position p) async {
    _enviadaEm = DateTime.now();
    try {
      await db.doc('entregadores/$uid').update({
        'localizacao': {
          'lat': p.latitude,
          'lng': p.longitude,
          'geohash': geohash(p.latitude, p.longitude),
          'em': FieldValue.serverTimestamp(),
          'precisao': p.accuracy,
          'mock': p.isMocked,
        },
      });
    } on FirebaseException {
      // offline ou pausado: as regras recusam; tenta de novo na próxima
    }
  }

  void parar() {
    _sub?.cancel();
    _timer?.cancel();
    _sub = null;
    _timer = null;
  }
}

/// Endereço → coordenada pelo geocodificador do próprio Android (sem chave).
Future<Ponto?> geocodificar(String endereco, {String cidade = ''}) async {
  try {
    final r = await locationFromAddress([endereco, if (cidade.isNotEmpty) cidade, 'Brasil'].join(', '));
    if (r.isEmpty) return null;
    return Ponto(r.first.latitude, r.first.longitude);
  } catch (_) {
    return null;
  }
}

/// Coordenada → "Rua, número - Bairro" para a loja conferir.
Future<String?> enderecoDe(Ponto p) async {
  try {
    final r = await placemarkFromCoordinates(p.lat, p.lng);
    if (r.isEmpty) return null;
    final m = r.first;
    return [
      [m.thoroughfare, m.subThoroughfare].where((s) => s != null && s.isNotEmpty).join(', '),
      m.subLocality,
      m.subAdministrativeArea ?? m.locality,
    ].where((s) => s != null && s.isNotEmpty).join(' - ');
  } catch (_) {
    return null;
  }
}

/// Monta um Ponto a partir de valores lidos do Firestore (int ou double).
Ponto? pontoDe(Object? lat, Object? lng) {
  if (lat is! num || lng is! num) return null;
  return Ponto(lat.toDouble(), lng.toDouble());
}
