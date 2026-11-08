import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import '../servicos/api.dart';
import '../widgets/comum.dart';

/// Faturas a receber (baixa manual) e contestações entre loja e entregador.
class Financeiro extends StatelessWidget {
  const Financeiro({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        const TabBar(tabs: [Tab(text: 'Faturas a receber'), Tab(text: 'Contestações')]),
        Expanded(child: TabBarView(children: [_Faturas(), _Contestacoes()])),
      ]),
    );
  }
}

class _Faturas extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('faturas').where('status', whereIn: ['fechada', 'vencida']).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Carregando();
        final docs = [...snap.data!.docs]..sort((a, b) => (a.data()['status'] == 'vencida' ? 0 : 1).compareTo(b.data()['status'] == 'vencida' ? 0 : 1));
        if (docs.isEmpty) return const Vazio('Nenhuma fatura em aberto.', icone: Icons.task_alt);
        final total = docs.fold<int>(0, (s, d) => s + (d.data()['totalCentavos'] as num? ?? 0).toInt());
        return ListView(children: [
          Padding(padding: const EdgeInsets.all(16), child: LinhaValor('Total a receber', formatarReais(total), destaque: true)),
          for (final d in docs)
            Card(
              color: d.data()['status'] == 'vencida' ? Theme.of(context).colorScheme.errorContainer : null,
              child: ListTile(
                title: Text('${d.data()['entregadorNome'] ?? d.data()['entregadorId']} · ${d.data()['mes']}'),
                subtitle: Text('${d.data()['entregas']} entregas · plano ${d.data()['plano']} · vence ${dataHora(d.data()['vencimento'])}'),
                trailing: FilledButton.tonal(
                  onPressed: () => _baixa(context, d.id, d.data()),
                  child: Text(formatarReais((d.data()['totalCentavos'] as num? ?? 0).toInt())),
                ),
              ),
            ),
        ]);
      },
    );
  }

  Future<void> _baixa(BuildContext context, String id, Map<String, dynamic> f) async {
    final forma = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('Marcar ${formatarReais((f['totalCentavos'] as num? ?? 0).toInt())} como pago via:')),
          for (final (v, r) in const [('pix', 'Pix'), ('dinheiro', 'Dinheiro'), ('transferencia', 'Transferência'), ('outro', 'Outro')])
            ListTile(title: Text(r), onTap: () => Navigator.pop(c, v)),
        ]),
      ),
    );
    if (forma != null && context.mounted) {
      await executar(context, () => chamar('marcarFaturaPaga', {'faturaId': id, 'forma': forma}));
    }
  }
}

class _Contestacoes extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('lancamentos').where('status', isEqualTo: 'contestado').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Carregando();
        if (snap.data!.docs.isEmpty) return const Vazio('Nenhuma contestação.', icone: Icons.task_alt);
        return ListView(children: [
          for (final d in snap.data!.docs)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${d.data()['lojaNome']} → ${d.data()['entregadorNome']}', style: Theme.of(context).textTheme.titleMedium),
                  Text('${formatarReais((d.data()['valorCentavos'] as num).toInt())} via ${d.data()['forma']} · ${dataHora(d.data()['criadoEm'])}'),
                  Text('Entregador diz: ${d.data()['motivoContestacao'] ?? ''}'),
                  Row(children: [
                    TextButton(
                      onPressed: () => executar(context, () => chamar('resolverContestacao', {'lancamentoId': d.id, 'valido': false})),
                      child: const Text('Anular pagamento'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => executar(context, () => chamar('resolverContestacao', {'lancamentoId': d.id, 'valido': true})),
                      child: const Text('Pagamento válido'),
                    ),
                  ]),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}
