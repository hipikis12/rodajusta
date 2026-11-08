import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import '../servicos/api.dart';
import '../widgets/comum.dart';

/// Pedidos ativos, parados e entregadores online.
class Painel extends StatefulWidget {
  const Painel({super.key});
  @override
  State<Painel> createState() => _PainelState();
}

class _PainelState extends State<Painel> {
  String _filtro = 'ativos';

  Query<Map<String, dynamic>> get _consulta {
    final lotes = db.collection('lotes');
    final Query<Map<String, dynamic>> q = switch (_filtro) {
      'ativos' => lotes.where('status', whereIn: ['buscando', 'aceito', 'coletado']),
      'sem_entregador' => lotes.where('status', isEqualTo: 'sem_entregador'),
      _ => lotes.orderBy('criadoEm', descending: true),
    };
    return q.limit(50);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(child: _Contador('Entregadores online', db.collection('entregadores').where('disponibilidade', whereIn: ['disponivel', 'em_entrega']))),
          const SizedBox(width: 12),
          Expanded(child: _Contador('Buscando entregador', db.collection('lotes').where('status', isEqualTo: 'buscando'))),
          const SizedBox(width: 12),
          Expanded(child: _Contador('Sem entregador', db.collection('lotes').where('status', isEqualTo: 'sem_entregador'), alerta: true)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'ativos', label: Text('Em andamento')),
            ButtonSegment(value: 'sem_entregador', label: Text('Parados')),
            ButtonSegment(value: 'todos', label: Text('Recentes')),
          ],
          selected: {_filtro},
          onSelectionChanged: (s) => setState(() => _filtro = s.first),
        ),
      ),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _consulta.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Padding(padding: EdgeInsets.all(32), child: Carregando());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Vazio('Nada aqui agora.');
          return Column(children: [
            for (final d in docs)
              Card(
                child: ListTile(
                  title: Text('${d.data()['lojaNome']} → ${(d.data()['bairros'] as List?)?.join(', ') ?? ''}'),
                  subtitle: Text('${rotulo(rotulosStatusLote, d.data()['status'] as String?)}'
                      '${d.data()['entregadorNome'] != null ? ' · ${d.data()['entregadorNome']}' : ''}'
                      ' · ${dataHora(d.data()['criadoEm'])}'),
                  trailing: Text(formatarReais((d.data()['valorTotalCentavos'] as num? ?? 0).toInt())),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DetalheLote(id: d.id))),
                ),
              ),
          ]);
        },
      ),
    ]);
  }
}

class _Contador extends StatelessWidget {
  const _Contador(this.rotulo, this.consulta, {this.alerta = false});
  final String rotulo;
  final Query<Map<String, dynamic>> consulta;
  final bool alerta;
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: consulta.snapshots(),
        builder: (context, s) {
          final n = s.data?.size ?? 0;
          return Card(
            margin: EdgeInsets.zero,
            color: alerta && n > 0 ? Theme.of(context).colorScheme.errorContainer : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(rotulo, maxLines: 2),
                Text('$n', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
          );
        },
      );
}

/// Um lote: pedidos, ofertas com a pontuação de cada entregador e ações.
class DetalheLote extends StatelessWidget {
  const DetalheLote({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalhe do pedido')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.doc('lotes/$id').snapshots(),
        builder: (context, ls) {
          if (!ls.hasData) return const Carregando();
          final l = ls.data!.data() ?? {};
          final status = l['status'] as String? ?? '';
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('${l['lojaNome']}', style: Theme.of(context).textTheme.titleLarge),
            Text(rotulo(rotulosStatusLote, status)),
            const SizedBox(height: 8),
            LinhaValor('Entregas', '${(l['pedidoIds'] as List?)?.length ?? 0}'),
            LinhaValor('Valor total', formatarReais((l['valorTotalCentavos'] as num? ?? 0).toInt())),
            LinhaValor('Percurso aproximado', '${l['distanciaTotalKm']} km'),
            LinhaValor('Destino', '${l['modo']}'),
            Wrap(spacing: 8, children: [
              if (status == 'sem_entregador')
                FilledButton(onPressed: () => executar(context, () => chamar('reenviarLote', {'loteId': id})), child: const Text('Reenviar')),
              if (['buscando', 'aceito', 'sem_entregador'].contains(status))
                OutlinedButton(onPressed: () => executar(context, () => chamar('cancelarLote', {'loteId': id})), child: const Text('Cancelar')),
            ]),
            const SizedBox(height: 16),
            Text('Ofertas (quem recebeu e por quê)', style: Theme.of(context).textTheme.titleMedium),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db.collection('ofertas').where('loteId', isEqualTo: id).snapshots(),
              builder: (context, os) {
                final ofertas = [...?os.data?.docs]..sort((a, b) => (a.data()['onda'] as num).compareTo(b.data()['onda'] as num));
                return Column(children: [
                  for (final o in ofertas)
                    ListTile(
                      dense: true,
                      title: Text('Onda ${(o.data()['onda'] as num).toInt() + 1} · ${o.data()['entregadorId']} · ${o.data()['status']}'),
                      subtitle: Text(_componentes(o.data())),
                      trailing: Text('${o.data()['score']}'),
                    ),
                ]);
              },
            ),
          ]);
        },
      ),
    );
  }

  static String _componentes(Map<String, dynamic> o) {
    final c = o['componentes'] as Map? ?? {};
    String f(String k) => ((c[k] as num?) ?? 0).toStringAsFixed(2);
    return 'distância ${f('distancia')} · espera ${f('espera')} · equidade ${f('equidade')} · '
        'rodízio ${f('rodizio')} · recusas −${f('penalidade')} · ${o['distanciaLojaKm']} km';
  }
}
