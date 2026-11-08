import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:rodajusta_core/rodajusta_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../servicos/api.dart';
import '../../servicos/localizacao.dart';
import '../../widgets/comum.dart';

/// Entrega em andamento: ir à loja → PIN → rota no Google Maps → finalizar cada uma.
class LoteAtivo extends StatelessWidget {
  const LoteAtivo({super.key, required this.loteId});
  final String loteId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.doc('lotes/$loteId').snapshots(),
      builder: (context, ls) {
        if (!ls.hasData) return const Carregando();
        final l = ls.data!.data() ?? {};
        final status = l['status'] as String? ?? '';
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db
              .collection('pedidos')
              .where('entregadorId', isEqualTo: uid)
              .where('loteId', isEqualTo: loteId)
              .snapshots(),
          builder: (context, ps) {
            final pedidos = {for (final d in ps.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) d.id: d.data()};
            final ordem = (l['ordem'] as List?)?.cast<String>() ?? pedidos.keys.toList();
            return ListView(padding: const EdgeInsets.all(16), children: [
              if (l['inclusaoPendente'] != null) _Inclusao(loteId: loteId, inc: Map<String, dynamic>.from(l['inclusaoPendente'] as Map)),
              if (status == 'aceito') _IrParaLoja(loteId: loteId, l: l, qtd: pedidos.length),
              if (status == 'coletado') ...[
                FilledButton.icon(
                  icon: const Icon(Icons.map),
                  label: Text(pedidos.length > 1 ? 'Abrir rota com ${pedidos.length} paradas' : 'Abrir rota no Google Maps'),
                  onPressed: () => launchUrl(Uri.parse(l['rotaUrl'] as String), mode: LaunchMode.externalApplication),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < ordem.length; i++)
                  if (pedidos[ordem[i]] != null) _CartaoPedido(id: ordem[i], p: pedidos[ordem[i]]!, numero: i + 1),
              ],
            ]);
          },
        );
      },
    );
  }
}

class _IrParaLoja extends StatefulWidget {
  const _IrParaLoja({required this.loteId, required this.l, required this.qtd});
  final String loteId;
  final Map<String, dynamic> l;
  final int qtd;
  @override
  State<_IrParaLoja> createState() => _IrParaLojaState();
}

class _IrParaLojaState extends State<_IrParaLoja> {
  final _pin = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final loja = widget.l['loja'] as Map? ?? {};
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Vá até a loja', style: t.headlineSmall),
      const SizedBox(height: 4),
      Text('${widget.l['lojaNome']}\n${loja['endereco'] ?? ''}', style: t.titleMedium),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        icon: const Icon(Icons.navigation),
        label: const Text('Navegar até a loja'),
        onPressed: () => launchUrl(
          Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${loja['lat']},${loja['lng']}&travelmode=driving'),
          mode: LaunchMode.externalApplication,
        ),
      ),
      const SizedBox(height: 24),
      Text(widget.qtd > 1 ? 'Na loja, confira as ${widget.qtd} comandas e peça o PIN.' : 'Na loja, peça o PIN de coleta.'),
      const SizedBox(height: 8),
      TextField(
        controller: _pin,
        keyboardType: TextInputType.number,
        maxLength: 4,
        textAlign: TextAlign.center,
        style: t.headlineMedium?.copyWith(letterSpacing: 12),
        decoration: const InputDecoration(labelText: 'PIN da loja', counterText: ''),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: () => executar(context, () => chamar('confirmarColeta', {'loteId': widget.loteId, 'pin': _pin.text})),
        child: const Text('Confirmar coleta'),
      ),
    ]);
  }
}

class _CartaoPedido extends StatelessWidget {
  const _CartaoPedido({required this.id, required this.p, required this.numero});
  final String id;
  final Map<String, dynamic> p;
  final int numero;

  Future<void> _entregue(BuildContext context) async {
    await executar(context, () async {
      final pos = await posicaoAtual();
      return chamar('concluirEntrega', {'pedidoId': id, 'lat': pos.latitude, 'lng': pos.longitude, 'mock': pos.isMocked});
    });
  }

  Future<void> _naoEntregue(BuildContext context) async {
    final motivo = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('O que aconteceu?')),
          for (final m in const [
            ('cliente_ausente', 'Cliente não atendeu'),
            ('endereco_errado', 'Endereço não encontrado'),
            ('recusado', 'Cliente recusou'),
            ('outro', 'Outro motivo'),
          ])
            ListTile(title: Text(m.$2), onTap: () => Navigator.pop(c, m.$1)),
        ]),
      ),
    );
    if (motivo != null && context.mounted) {
      await executar(context, () => chamar('naoEntregue', {'pedidoId': id, 'motivo': motivo}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = p['destino'] as Map? ?? {};
    final status = p['status'] as String? ?? '';
    final pg = p['pagamento'] as Map? ?? {};
    final cobrar = pg['tipo'] == 'cobrar';
    final finalizado = status == 'entregue' || status == 'nao_entregue';
    final t = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: finalizado ? 0.5 : 1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 14, child: Text('$numero')),
              const SizedBox(width: 8),
              Expanded(child: Text(d['bairro'] as String? ?? '', style: t.titleMedium)),
              Text(rotulo(rotulosStatusPedido, status)),
            ]),
            const SizedBox(height: 8),
            Text('${d['endereco'] ?? ''}${(d['complemento'] as String? ?? '').isNotEmpty ? ' · ${d['complemento']}' : ''}',
                style: t.bodyLarge),
            if ((d['referencia'] as String? ?? '').isNotEmpty) Text('Ref.: ${d['referencia']}'),
            Text('${p['descricao'] ?? ''}${(p['cliente'] as String? ?? '').isNotEmpty ? ' · ${p['cliente']}' : ''}'),
            if (cobrar)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                color: Theme.of(context).colorScheme.errorContainer,
                child: Text(
                  'Cobrar ${formatarReais((pg['valorCobrarCentavos'] as num? ?? 0).toInt())}'
                  '${switch (pg['forma']) { 'cartao' => ' no cartão · levar maquininha', 'pix' => ' no Pix', 'dinheiro' => ' em dinheiro', _ => '' }}'
                  '${(pg['trocoParaCentavos'] as num? ?? 0) > 0 ? ' · troco para ${formatarReais((pg['trocoParaCentavos'] as num).toInt())}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            if (!finalizado) ...[
              const SizedBox(height: 12),
              Row(children: [
                if ((p['telefoneCliente'] as String? ?? '').isNotEmpty)
                  IconButton.outlined(
                    icon: const Icon(Icons.call),
                    onPressed: () => launchUrl(Uri.parse('tel:${p['telefoneCliente']}')),
                  ),
                TextButton(onPressed: () => _naoEntregue(context), child: const Text('Não entregue')),
                const Spacer(),
                FilledButton(onPressed: () => _entregue(context), child: const Text('Entregue')),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Inclusao extends StatelessWidget {
  const _Inclusao({required this.loteId, required this.inc});
  final String loteId;
  final Map<String, dynamic> inc;
  @override
  Widget build(BuildContext context) {
    Future<void> responder(bool aceitar) => executar(
          context,
          () => chamar('responderInclusao', {'loteId': loteId, 'pedidoId': inc['pedidoId'], 'aceitar': aceitar}),
        );
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('A loja quer adicionar 1 entrega', style: Theme.of(context).textTheme.titleMedium),
          Text('${inc['bairro']} · + ${formatarReais((inc['valorCentavos'] as num? ?? 0).toInt())}'),
          const SizedBox(height: 8),
          Row(children: [
            TextButton(onPressed: () => responder(false), child: const Text('Recusar')),
            const Spacer(),
            FilledButton(onPressed: () => responder(true), child: const Text('Aceitar e levar')),
          ]),
        ]),
      ),
    );
  }
}
