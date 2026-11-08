import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import 'api.dart';

/// Documento da comanda pendente no Firestore, a partir do que foi lido.
Map<String, dynamic> documentoDaComanda(
  ComandaExtraida c, {
  required String origem,
  String via = '',
  Ponto? ponto,
  String textoBruto = '',
}) {
  return {
    'origem': origem,
    'status': 'pendente',
    'via': via,
    'textoBruto': textoBruto.length > 20000 ? textoBruto.substring(0, 20000) : textoBruto,
    'descricao': c.descricao.isEmpty ? 'Comanda ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}' : c.descricao,
    'numero': c.numero,
    'cliente': c.cliente,
    'telefone': c.telefone,
    'localizador': c.localizador,
    'observacao': c.observacao,
    'endereco': {
      'texto': c.endereco,
      'bairro': c.bairro,
      'complemento': c.complemento,
      'referencia': c.referencia,
      'cidade': c.cidade,
      'uf': c.uf,
      'cep': c.cep,
    },
    'lat': ponto?.lat,
    'lng': ponto?.lng,
    'totalCentavos': c.totalCentavos,
    'taxaEntregaCentavos': c.taxaEntregaCentavos,
    'pagamento': {
      'tipo': c.cobrar ? 'cobrar' : 'pago',
      'valorCobrarCentavos': c.cobrar ? (c.valorCobrarCentavos ?? c.totalCentavos ?? 0) : 0,
      'trocoParaCentavos': c.trocoParaCentavos ?? 0,
      'forma': c.formaCobranca,
    },
    'confianca': ponto == null ? c.confianca * 0.5 : c.confianca,
    'enderecoDoTopo': c.enderecoDoTopo,
    'extraido': c.paraMapa(),
    'criadoEm': FieldValue.serverTimestamp(),
  };
}

/// Item no formato que a função enviarPedidos espera.
Map<String, dynamic> itemDeComanda(String id, Map<String, dynamic> c, int valorCentavos) {
  final end = Map<String, dynamic>.from(c['endereco'] as Map? ?? {});
  final origem = c['origem'] as String? ?? 'manual';
  final pg = Map<String, dynamic>.from(c['pagamento'] as Map? ?? {'tipo': 'pago'});
  return {
    'comandaId': id,
    'descricao': c['descricao'] ?? '',
    'cliente': c['cliente'] ?? '',
    'telefoneCliente': c['telefone'] ?? '',
    'endereco': end['texto'] ?? '',
    'bairro': end['bairro'] ?? '',
    'complemento': end['complemento'] ?? '',
    'referencia': [end['referencia'], if ((c['localizador'] as String? ?? '').isNotEmpty) 'Localizador ${c['localizador']}']
        .where((s) => s != null && '$s'.isNotEmpty)
        .join(' · '),
    'lat': (c['lat'] as num?)?.toDouble(),
    'lng': (c['lng'] as num?)?.toDouble(),
    'valorEntregaCentavos': valorCentavos,
    'pagamento': {
      'tipo': pg['tipo'] ?? 'pago',
      'valorCobrarCentavos': (pg['valorCobrarCentavos'] as num? ?? 0).toInt(),
      'trocoParaCentavos': (pg['trocoParaCentavos'] as num? ?? 0).toInt(),
      'forma': pg['forma'] ?? '',
    },
    'origem': origem == 'ifood' ? 'ifood' : (origem == 'comanda' ? 'comanda' : 'manual'),
    'ifoodOrderId': c['ifoodOrderId'] ?? '',
  };
}

/// Guarda o texto original e o que a loja corrigiu, para melhorar o leitor
/// de comandas com os formatos reais dos PDVs.
Future<void> guardarAmostra(Map<String, dynamic> original, Map<String, dynamic> corrigido) async {
  final texto = original['textoBruto'] as String?;
  if (texto == null || texto.isEmpty) return;
  String chave(Map m) => [
        m['cliente'],
        (m['endereco'] as Map?)?['texto'],
        (m['endereco'] as Map?)?['bairro'],
        (m['pagamento'] as Map?)?['tipo'],
      ].join('|');
  if (chave(original) == chave(corrigido)) return;
  try {
    await db.collection('amostrasComanda').add({
      'lojistaId': uid,
      'textoBruto': texto.length > 20000 ? texto.substring(0, 20000) : texto,
      'extraido': {
        'cliente': original['cliente'] ?? '',
        'endereco': original['endereco'] ?? {},
        'pagamento': original['pagamento'] ?? {},
      },
      'corrigido': {
        'cliente': corrigido['cliente'] ?? '',
        'endereco': corrigido['endereco'] ?? {},
        'pagamento': corrigido['pagamento'] ?? {},
      },
      'em': FieldValue.serverTimestamp(),
    });
  } on FirebaseException {
    // amostra é bônus; não atrapalha a loja
  }
}
