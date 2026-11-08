import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import '../../servicos/api.dart';
import '../../widgets/comum.dart';

/// Fatura mensal com a plataforma. O pagamento é por fora; o Admin dá baixa.
class TelaFatura extends StatelessWidget {
  const TelaFatura({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fatura da plataforma')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.doc('entregadores/$uid').snapshots(),
        builder: (context, es) {
          final e = es.data?.data() ?? {};
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: db.doc('config/parametros').snapshots(),
            builder: (context, ps) {
              final taxa = Map<String, dynamic>.from(ps.data?.data()?['taxa'] as Map? ?? {});
              final porEntrega = (taxa['porEntregaCentavos'] as num? ?? 80).toInt();
              final mensal = (taxa['mensalCentavos'] as num? ?? 8000).toInt();
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db.collection('faturas').where('entregadorId', isEqualTo: uid).orderBy('mes', descending: true).limit(12).snapshots(),
                builder: (context, fs) {
                  final faturas = fs.data?.docs ?? [];
                  return ListView(children: [
                    if (e['faturaBloqueada'] == true)
                      Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: const ListTile(
                          leading: Icon(Icons.block),
                          title: Text('Você está sem receber entregas'),
                          subtitle: Text('Há fatura atrasada. Pague e avise o suporte para liberar.'),
                        ),
                      ),
                    _Plano(e: e, porEntrega: porEntrega, mensal: mensal),
                    if (faturas.isEmpty) const Vazio('Sua fatura aparece aqui depois da primeira entrega do mês.'),
                    for (final f in faturas) _CartaoFatura(f: f.data(), porEntrega: porEntrega, mensal: mensal),
                  ]);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _Plano extends StatelessWidget {
  const _Plano({required this.e, required this.porEntrega, required this.mensal});
  final Map<String, dynamic> e;
  final int porEntrega;
  final int mensal;

  @override
  Widget build(BuildContext context) {
    final plano = e['plano'] as String? ?? 'por_entrega';
    final proximo = e['planoProximoMes'] as String?;
    String nome(String p) => p == 'mensal' ? 'Mensal (${formatarReais(mensal)})' : 'Por entrega (${formatarReais(porEntrega)})';
    return Card(
      child: ListTile(
        title: Text('Plano: ${nome(plano)}'),
        subtitle: Text(e['isento'] == true
            ? 'Isento de taxa por decisão da administração.'
            : proximo != null
                ? 'Muda para ${nome(proximo)} no próximo mês.'
                : 'O mensal compensa a partir de ${(mensal / porEntrega).ceil()} entregas no mês.'),
        trailing: TextButton(
          onPressed: () => executar(context, () => chamar('trocarPlano', {'plano': (proximo ?? plano) == 'mensal' ? 'por_entrega' : 'mensal'})),
          child: Text((proximo ?? plano) == 'mensal' ? 'Mudar p/ por entrega' : 'Mudar p/ mensal'),
        ),
      ),
    );
  }
}

class _CartaoFatura extends StatelessWidget {
  const _CartaoFatura({required this.f, required this.porEntrega, required this.mensal});
  final Map<String, dynamic> f;
  final int porEntrega;
  final int mensal;

  @override
  Widget build(BuildContext context) {
    final status = f['status'] as String? ?? 'aberta';
    final entregas = (f['entregas'] as num? ?? 0).toInt();
    final creditos = (f['creditosCentavos'] as num? ?? 0).toInt();
    // fatura aberta: prévia com os valores atuais
    final bruto = (f['brutoCentavos'] as num?)?.toInt() ??
        (f['isento'] == true ? 0 : f['plano'] == 'mensal' ? (entregas > 0 ? mensal : 0) : entregas * porEntrega);
    final aplicados = (f['creditosAplicadosCentavos'] as num?)?.toInt() ?? (creditos > bruto ? bruto : creditos);
    final total = (f['totalCentavos'] as num?)?.toInt() ?? bruto - aplicados;
    final cores = Theme.of(context).colorScheme;
    final (rotuloStatus, corStatus) = switch (status) {
      'aberta' => ('Em andamento', cores.primary),
      'fechada' => ('A pagar até ${dataHora(f['vencimento']).split(' ').first}', cores.tertiary),
      'vencida' => ('Vencida', cores.error),
      'paga' => ('Paga', Colors.green),
      _ => (status, cores.outline),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(f['mes'] as String? ?? '', style: Theme.of(context).textTheme.titleMedium)),
            Text(rotuloStatus, style: TextStyle(color: corStatus, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          LinhaValor('$entregas entregas', formatarReais(bruto)),
          if (aplicados > 0) LinhaValor('Descontos e bônus de incentivo', formatarReais(-aplicados)),
          const Divider(),
          LinhaValor(status == 'aberta' ? 'Prévia do total' : 'Total', formatarReais(total), destaque: true),
          if (status == 'fechada' || status == 'vencida')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Pague pelo Pix informado pela administração. A baixa é feita por ela.'),
            ),
        ]),
      ),
    );
  }
}
