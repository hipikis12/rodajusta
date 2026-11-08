import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../servicos/api.dart';
import '../widgets/comum.dart';

/// Comandas que as lojas corrigiram: o texto original do PDV e o que
/// estava errado. Servem para melhorar o leitor (packages/core comanda.dart).
class Amostras extends StatelessWidget {
  const Amostras({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('amostrasComanda').orderBy('em', descending: true).limit(50).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Carregando();
        if (snap.data!.docs.isEmpty) {
          return const Vazio('Nenhuma correção ainda. Quando uma loja corrigir uma comanda lida errado, ela aparece aqui.');
        }
        return ListView(children: [
          for (final d in snap.data!.docs) _Amostra(a: d.data()),
        ]);
      },
    );
  }
}

class _Amostra extends StatelessWidget {
  const _Amostra({required this.a});
  final Map<String, dynamic> a;

  String _resumo(Map? m) {
    final e = m?['endereco'] as Map? ?? {};
    return 'Cliente: ${m?['cliente'] ?? ''}\nEndereço: ${e['texto'] ?? ''}\nBairro: ${e['bairro'] ?? ''}\n'
        'Pagamento: ${(m?['pagamento'] as Map?)?['tipo'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text('Loja ${a['lojistaId']} · ${dataHora(a['em'])}'),
        subtitle: Text(_resumo(a['corrigido'] as Map?).split('\n')[1], maxLines: 1, overflow: TextOverflow.ellipsis),
        childrenPadding: const EdgeInsets.all(16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('O app leu', style: TextStyle(fontWeight: FontWeight.w700)),
          Text(_resumo(a['extraido'] as Map?)),
          const SizedBox(height: 8),
          const Text('A loja corrigiu para', style: TextStyle(fontWeight: FontWeight.w700)),
          Text(_resumo(a['corrigido'] as Map?)),
          const SizedBox(height: 8),
          const Text('Texto do PDV', style: TextStyle(fontWeight: FontWeight.w700)),
          SelectableText(a['textoBruto'] as String? ?? '', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ],
      ),
    );
  }
}
