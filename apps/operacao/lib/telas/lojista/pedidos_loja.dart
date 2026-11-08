import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import '../../servicos/api.dart';
import '../../widgets/comum.dart';
import '../../servicos/comandas.dart';

/// Lotes enviados: status ao vivo, PIN de coleta, reenviar e cancelar.
class PedidosLoja extends StatelessWidget {
  const PedidosLoja({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pedidos')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db
            .collection('lotes')
            .where('lojistaId', isEqualTo: uid)
            .orderBy('criadoEm', descending: true)
            .limit(40)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Carregando();
          if (snap.data!.docs.isEmpty) return const Vazio('Nenhum pedido enviado ainda.');
          return ListView(children: [for (final d in snap.data!.docs) _CartaoLote(id: d.id, l: d.data())]);
        },
      ),
    );
  }
}

class _CartaoLote extends StatelessWidget {
  const _CartaoLote({required this.id, required this.l});
  final String id;
  final Map<String, dynamic> l;

  @override
  Widget build(BuildContext context) {
    final status = l['status'] as String? ?? '';
    final qtd = (l['pedidoIds'] as List?)?.length ?? 1;
    final bairros = (l['bairros'] as List?)?.join(', ') ?? '';
    final cor = Theme.of(context).colorScheme;
    final ativo = status == 'buscando' || status == 'aceito';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(qtd > 1 ? '$qtd entregas · $bairros' : bairros,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Text(formatarReais((l['valorTotalCentavos'] as num? ?? 0).toInt())),
          ]),
          const SizedBox(height: 4),
          Text('${rotulo(rotulosStatusLote, status)}'
              '${l['entregadorNome'] != null && status != 'buscando' ? ' · ${l['entregadorNome']}' : ''}'
              ' · ${dataHora(l['criadoEm'])}'),
          if (status == 'buscando') ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(color: cor.secondary),
            const SizedBox(height: 4),
            Text('Onda ${(l['onda'] as num? ?? 0).toInt() + 1} · ofertado a ${(l['ofertados'] as List?)?.length ?? 0} entregador(es)'),
          ],
          if (status == 'aceito') _Pin(loteId: id),
          if (l['inclusaoPendente'] != null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Aguardando o entregador aceitar a comanda extra…'),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            if (status == 'sem_entregador')
              FilledButton.tonal(
                onPressed: () => executar(context, () => chamar('reenviarLote', {'loteId': id})),
                child: const Text('Reenviar'),
              ),
            if (status == 'aceito' && l['inclusaoPendente'] == null)
              OutlinedButton(onPressed: () => _incluir(context), child: const Text('Incluir comanda')),
            if (ativo || status == 'sem_entregador')
              TextButton(
                onPressed: () async {
                  final sim = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Cancelar pedido?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
                        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancelar pedido')),
                      ],
                    ),
                  );
                  if (sim == true && context.mounted) {
                    await executar(context, () => chamar('cancelarLote', {'loteId': id}));
                  }
                },
                child: const Text('Cancelar'),
              ),
          ]),
        ]),
      ),
    );
  }

  /// Pede ao entregador para levar mais uma comanda pendente neste lote.
  Future<void> _incluir(BuildContext context) async {
    final pend = await db.collection('lojistas/$uid/comandas').where('status', isEqualTo: 'pendente').get();
    final loja = (await db.doc('lojistas/$uid').get()).data() ?? {};
    final config = Map<String, dynamic>.from(loja['config'] as Map? ?? {});
    final candidatas = pend.docs.where((d) => d.data()['lat'] != null).toList();
    if (!context.mounted) return;
    if (candidatas.isEmpty) {
      avisar(context, 'Nenhuma comanda pendente com endereço localizado.');
      return;
    }
    final escolhida = await showModalBottomSheet<QueryDocumentSnapshot<Map<String, dynamic>>>(
      context: context,
      builder: (c) => ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Qual comanda incluir?')),
        for (final d in candidatas)
          ListTile(
            title: Text(d.data()['descricao'] as String? ?? ''),
            subtitle: Text((d.data()['endereco'] as Map?)?['bairro'] as String? ?? ''),
            onTap: () => Navigator.pop(c, d),
          ),
      ]),
    );
    if (escolhida == null || !context.mounted) return;
    final c = escolhida.data();
    final valor = (c['valorEntregaCentavos'] as num?)?.toInt() ?? valorSugerido(config, 0) ?? 0;
    if (valor == 0) {
      avisar(context, 'Defina o valor da entrega nesta comanda antes de incluir.');
      return;
    }
    final r = await executar(context, () => chamar('incluirNoLote', {'loteId': id, 'item': itemDeComanda(escolhida.id, c, valor)}));
    if (r != null) {
      await db.doc('lojistas/$uid/comandas/${escolhida.id}').update({'status': 'descartada'});
    }
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.loteId});
  final String loteId;
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: db.doc('lotes/$loteId/privado/pin').get(),
      builder: (context, s) {
        final pin = s.data?.data()?['pin'] as String? ?? '····';
        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            const Expanded(child: Text('Na coleta, informe ao entregador o PIN:')),
            Text(pin, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 4)),
          ]),
        );
      },
    );
  }
}
