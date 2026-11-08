import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import 'api.dart';
import 'localizacao.dart';

/// O celular da loja vira uma impressora Bluetooth (perfil SPP): o PDV
/// "imprime" a comanda aqui, o app lê o texto e cria uma comanda pendente.
/// A parte Bluetooth é nativa (Kotlin): ver ImpressoraVirtual.kt.
class ImpressoraVirtual {
  ImpressoraVirtual._();
  static final instancia = ImpressoraVirtual._();

  static const _metodos = MethodChannel('rodajusta/impressora');
  static const _comandas = EventChannel('rodajusta/impressora/comandas');

  StreamSubscription<dynamic>? _sub;
  final _estado = StreamController<String>.broadcast();

  /// 'parada', 'aguardando', 'conectada' ou mensagem de erro.
  Stream<String> get estado => _estado.stream;

  Future<void> iniciar({String? repassarPara}) async {
    _sub ??= _comandas.receiveBroadcastStream().listen((evento) {
      if (evento is Uint8List) {
        _aoReceber(evento);
      } else if (evento is String) {
        _estado.add(evento);
      }
    });
    await _metodos.invokeMethod<void>('iniciar', {'repassarPara': repassarPara});
  }

  Future<void> parar() async {
    await _metodos.invokeMethod<void>('parar');
    await _sub?.cancel();
    _sub = null;
    _estado.add('parada');
  }

  Future<void> ficarVisivel() => _metodos.invokeMethod<void>('ficarVisivel');

  /// Impressoras já pareadas (nome e endereço), para escolher onde repassar.
  Future<List<Map<String, String>>> pareadas() async {
    final r = await _metodos.invokeListMethod<dynamic>('pareadas') ?? [];
    return r.map((e) => Map<String, String>.from(e as Map)).toList();
  }

  Future<void> _aoReceber(Uint8List bytes) async {
    final texto = decodificarEscPos(bytes);
    if (texto.trim().length < 10) return; // ruído / teste de impressão vazio
    await criarComandaDoTexto(texto, origem: 'comanda');
  }
}

/// Extrai os dados, tenta achar a coordenada e grava a comanda pendente.
Future<String> criarComandaDoTexto(String texto, {required String origem}) async {
  final c = extrairComanda(texto);
  Ponto? ponto;
  if (c.endereco.isNotEmpty) {
    ponto = await geocodificar([c.endereco, c.bairro].where((s) => s.isNotEmpty).join(' - '));
  }
  final ref = db.collection('lojistas/$uid/comandas').doc();
  await ref.set({
    'origem': origem,
    'status': 'pendente',
    'textoBruto': texto,
    'descricao': c.descricao.isEmpty ? 'Comanda ${DateTime.now().hour}:${DateTime.now().minute}' : c.descricao,
    'cliente': c.cliente,
    'telefone': c.telefone,
    'endereco': {'texto': c.endereco, 'bairro': c.bairro, 'complemento': c.complemento, 'referencia': c.referencia},
    'lat': ponto?.lat,
    'lng': ponto?.lng,
    'totalCentavos': c.totalCentavos,
    'taxaEntregaCentavos': c.taxaEntregaCentavos,
    'pagamento': {
      'tipo': c.cobrar ? 'cobrar' : 'pago',
      'valorCobrarCentavos': c.cobrar ? (c.totalCentavos ?? 0) : 0,
      'trocoParaCentavos': c.trocoParaCentavos ?? 0,
    },
    'confianca': ponto == null ? c.confianca * 0.5 : c.confianca,
    'criadoEm': FieldValue.serverTimestamp(),
  });
  return ref.id;
}
