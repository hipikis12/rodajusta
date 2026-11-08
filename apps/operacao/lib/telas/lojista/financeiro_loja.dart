import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import '../../servicos/api.dart';
import '../../widgets/comum.dart';

/// Quanto a loja deve a cada entregador, pagamentos e extrato.
class FinanceiroLoja extends StatelessWidget {
  const FinanceiroLoja({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Extrato'),
          bottom: const TabBar(tabs: [Tab(text: 'A pagar'), Tab(text: 'Lançamentos')]),
        ),
        body: const TabBarView(children: [_Acertos(), ExtratoLancamentos(campo: 'lojistaId')]),
      ),
    );
  }
}

class _Acertos extends StatelessWidget {
  const _Acertos();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('acertos').where('lojistaId', isEqualTo: uid).orderBy('atualizadoEm', descending: true).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Carregando();
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Vazio('Quando as entregas forem concluídas, o total de cada entregador aparece aqui.');
        final total = docs.fold<int>(0, (s, d) => s + (d.data()['saldoCentavos'] as num? ?? 0).toInt());
        return ListView(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: LinhaValor('Total a pagar aos entregadores', formatarReais(total), destaque: true),
          ),
          for (final d in docs) _CartaoAcerto(a: d.data()),
        ]);
      },
    );
  }
}

class _CartaoAcerto extends StatelessWidget {
  const _CartaoAcerto({required this.a});
  final Map<String, dynamic> a;

  int _v(String k) => (a[k] as num? ?? 0).toInt();

  Future<void> _registrar(BuildContext context) async {
    final valor = TextEditingController(text: _v('saldoCentavos') > 0 ? formatarReais(_v('saldoCentavos')).replaceAll('R\$ ', '') : '');
    var forma = 'pix';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Pagamento para ${a['entregadorNome']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: valor, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Valor pago (R\$)')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: forma,
              decoration: const InputDecoration(labelText: 'Forma'),
              items: const [
                DropdownMenuItem(value: 'pix', child: Text('Pix')),
                DropdownMenuItem(value: 'dinheiro', child: Text('Dinheiro')),
                DropdownMenuItem(value: 'transferencia', child: Text('Transferência')),
                DropdownMenuItem(value: 'outro', child: Text('Outro')),
              ],
              onChanged: (v) => set(() => forma = v ?? 'pix'),
            ),
            const SizedBox(height: 8),
            const Text('O entregador confirma o recebimento no app dele.'),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Registrar')),
          ],
        ),
      ),
    );
    final centavos = lerReais(valor.text);
    if (ok != true || centavos == null || centavos <= 0 || !context.mounted) return;
    await executar(context, () => chamar('registrarPagamento', {
          'entregadorId': a['entregadorId'],
          'valorCentavos': centavos,
          'forma': forma,
        }));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(a['entregadorNome'] as String? ?? '', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          LinhaValor('${_v('qtdEntregas')} entregas', formatarReais(_v('entregasCentavos'))),
          LinhaValor('Pago (confirmado)', formatarReais(-_v('pagosCentavos'))),
          if (_v('repassesCentavos') > 0) LinhaValor('Cobrado de clientes pelo entregador', formatarReais(-_v('repassesCentavos'))),
          if (_v('pendentesCentavos') > 0) LinhaValor('Aguardando confirmação', formatarReais(_v('pendentesCentavos'))),
          if (_v('contestadosCentavos') > 0) LinhaValor('Contestado', formatarReais(_v('contestadosCentavos'))),
          const Divider(),
          LinhaValor(_v('saldoCentavos') >= 0 ? 'A pagar' : 'Entregador deve à loja', formatarReais(_v('saldoCentavos').abs()), destaque: true),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(onPressed: () => _registrar(context), child: const Text('Registrar pagamento')),
          ),
        ]),
      ),
    );
  }
}

/// Extrato de lançamentos por período (usado pela loja e pelo entregador).
class ExtratoLancamentos extends StatefulWidget {
  const ExtratoLancamentos({super.key, required this.campo});
  final String campo; // 'lojistaId' ou 'entregadorId'
  @override
  State<ExtratoLancamentos> createState() => _ExtratoLancamentosState();
}

class _ExtratoLancamentosState extends State<ExtratoLancamentos> {
  String _periodo = 'semana';

  DateTime get _inicio {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    return switch (_periodo) {
      'hoje' => hoje,
      'semana' => hoje.subtract(Duration(days: hoje.weekday - 1)),
      _ => DateTime(agora.year, agora.month),
    };
  }

  @override
  Widget build(BuildContext context) {
    final souLoja = widget.campo == 'lojistaId';
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'hoje', label: Text('Hoje')),
            ButtonSegment(value: 'semana', label: Text('Semana')),
            ButtonSegment(value: 'mes', label: Text('Mês')),
          ],
          selected: {_periodo},
          onSelectionChanged: (s) => setState(() => _periodo = s.first),
        ),
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db
              .collection('lancamentos')
              .where(widget.campo, isEqualTo: uid)
              .where('criadoEm', isGreaterThanOrEqualTo: Timestamp.fromDate(_inicio))
              .orderBy('criadoEm', descending: true)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Carregando();
            final docs = snap.data!.docs;
            var entregas = 0, valorEntregas = 0, pagos = 0;
            for (final d in docs) {
              final l = d.data();
              final v = (l['valorCentavos'] as num? ?? 0).toInt();
              if (l['tipo'] == 'entrega') {
                entregas++;
                valorEntregas += v;
              }
              if (l['tipo'] == 'pagamento' && l['status'] == 'confirmado') pagos += v;
            }
            return ListView(children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    LinhaValor('Entregas', '$entregas'),
                    LinhaValor(souLoja ? 'Gasto com entregas' : 'Ganho com entregas', formatarReais(valorEntregas), destaque: true),
                    LinhaValor(souLoja ? 'Pago no período' : 'Recebido no período', formatarReais(pagos)),
                  ]),
                ),
              ),
              for (final d in docs) _LinhaLancamento(l: d.data(), id: d.id, souLoja: souLoja),
            ]);
          },
        ),
      ),
    ]);
  }
}

class _LinhaLancamento extends StatelessWidget {
  const _LinhaLancamento({required this.l, required this.id, required this.souLoja});
  final Map<String, dynamic> l;
  final String id;
  final bool souLoja;

  @override
  Widget build(BuildContext context) {
    final tipo = l['tipo'] as String? ?? '';
    final v = (l['valorCentavos'] as num? ?? 0).toInt();
    final quem = souLoja ? l['entregadorNome'] : l['lojaNome'];
    final (icone, titulo) = switch (tipo) {
      'entrega' => (Icons.check_circle_outline, 'Entrega · ${l['descricao'] ?? ''}'),
      'pagamento' => (Icons.payments_outlined, 'Pagamento (${l['forma'] ?? ''}) · ${l['status'] ?? ''}'),
      'repasse' => (Icons.swap_horiz, 'Cobrado do cliente'),
      'ajuste' => (Icons.tune, 'Ajuste · ${l['motivo'] ?? ''}'),
      _ => (Icons.receipt, tipo),
    };
    final pendenteParaMim = !souLoja && tipo == 'pagamento' && l['status'] == 'pendente';
    return ListTile(
      leading: Icon(icone),
      title: Text(titulo, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${quem ?? ''} · ${dataHora(l['criadoEm'])}'),
      trailing: pendenteParaMim
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Contestar',
                icon: const Icon(Icons.close),
                onPressed: () => _contestar(context),
              ),
              IconButton.filled(
                tooltip: 'Confirmar recebido',
                icon: const Icon(Icons.check),
                onPressed: () => executar(context, () => chamar('responderPagamento', {'lancamentoId': id, 'confirmar': true})),
              ),
            ])
          : Text(formatarReais(v)),
    );
  }

  Future<void> _contestar(BuildContext context) async {
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Contestar ${formatarReais((l['valorCentavos'] as num).toInt())}?'),
        content: TextField(controller: motivo, decoration: const InputDecoration(labelText: 'O que aconteceu?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Contestar')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await executar(context, () => chamar('responderPagamento', {'lancamentoId': id, 'confirmar': false, 'motivo': motivo.text}));
    }
  }
}
