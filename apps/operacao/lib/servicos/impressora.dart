import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import 'api.dart';
import 'comandas.dart';
import 'localizacao.dart';

/// Controle da "impressora virtual": o serviço Android que recebe as
/// comandas do PDV em segundo plano (ver ServicoImpressora.kt).
class ImpressoraVirtual {
  ImpressoraVirtual._();
  static final instancia = ImpressoraVirtual._();

  static const _metodos = MethodChannel('rodajusta/impressora');
  static const _estado = EventChannel('rodajusta/impressora/estado');

  /// 'parada', 'aguardando', 'conectada' ou uma mensagem.
  late final Stream<String> estado = _estado.receiveBroadcastStream().map((e) => '$e').asBroadcastStream();

  /// Liga/desliga conforme a configuração da loja (idempotente).
  Future<String?> aplicar(Map<String, dynamic> config) => _metodos.invokeMethod<String>('configurar', {
        'ativo': config['impressoraAtiva'] == true,
        'bluetooth': config['receberBluetooth'] != false,
        'ble': config['receberBle'] != false,
        'rede': config['receberRede'] != false,
        'porta': 9100,
        'repassarPara': config['repassarPara'],
      });

  Future<void> ficarVisivel() => _metodos.invokeMethod<void>('ficarVisivel');

  Future<String?> ipLocal() => _metodos.invokeMethod<String>('ipLocal');

  Future<bool> bateriaLiberada() async => await _metodos.invokeMethod<bool>('bateriaLiberada') ?? false;

  Future<void> liberarBateria() => _metodos.invokeMethod<void>('liberarBateria');

  Future<String?> nomeBluetooth() => _metodos.invokeMethod<String>('nomeBluetooth');

  /// null volta ao nome original do celular.
  Future<bool> renomearBluetooth(String? nome) async =>
      await _metodos.invokeMethod<bool>('renomearBluetooth', {'nome': nome}) ?? false;

  /// Impressoras já pareadas (nome e endereço), para escolher onde repassar.
  Future<List<Map<String, String>>> pareadas() async {
    final r = await _metodos.invokeListMethod<dynamic>('pareadas') ?? [];
    return r.map((e) => Map<String, String>.from(e as Map)).toList();
  }
}

/// Texto colado (WhatsApp, e-mail, outro sistema) vira comanda pendente.
Future<int> criarComandasDoTexto(String texto) async {
  final leitura = lerTrabalho([texto]);
  final lista = leitura.entregas.isEmpty ? [extrairComanda(texto)] : leitura.entregas;
  final col = db.collection('lojistas/$uid/comandas');
  for (final c in lista) {
    final ponto = c.endereco.isEmpty ? null : await geocodificar(c.enderecoParaMapa);
    final doc = documentoDaComanda(c, origem: 'manual', ponto: ponto, textoBruto: c.textoOriginal);
    await col.add({...doc, 'criadoEm': FieldValue.serverTimestamp()});
  }
  return lista.length;
}
