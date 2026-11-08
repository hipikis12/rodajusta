import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../servicos/api.dart';
import '../widgets/comum.dart';

/// Lista de entregadores com o indicador de justiça da distribuição de hoje.
class Entregadores extends StatelessWidget {
  const Entregadores({super.key});

  /// Coeficiente de Gini (0 = todos iguais; perto de 1 = poucos levam tudo).
  static double gini(List<double> v) {
    final x = [...v]..sort();
    final n = x.length;
    final soma = x.fold<double>(0, (s, e) => s + e);
    if (n == 0 || soma == 0) return 0;
    var acum = 0.0;
    for (var i = 0; i < n; i++) {
      acum += (i + 1) * x[i];
    }
    return 2 * acum / (n * soma) - (n + 1) / n;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('entregadores').where('aprovado', isEqualTo: true).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Carregando();
        final hoje = DateTime.now();
        final dia = '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}';
        final docs = snap.data!.docs;
        double porHora(Map<String, dynamic> e) {
          final s = e['statsHoje'] as Map? ?? {};
          if (s['dia'] != dia) return 0;
          final min = (s['minutosOnline'] as num? ?? 0).toDouble();
          return (s['entregas'] as num? ?? 0) / (min < 30 ? 0.5 : min / 60);
        }

        final trabalharam = docs.where((d) => ((d.data()['statsHoje'] as Map?)?['dia'] == dia)).toList();
        final g = gini(trabalharam.map((d) => porHora(d.data())).toList());
        return ListView(children: [
          Card(
            child: ListTile(
              title: const Text('Justiça da distribuição hoje'),
              subtitle: Text('${trabalharam.length} entregadores trabalharam. '
                  '${g < 0.25 ? 'Distribuição equilibrada.' : g < 0.4 ? 'Atenção: concentração moderada.' : 'Concentrada: aumente os pesos de espera/equidade.'}'),
              trailing: Text(g.toStringAsFixed(2), style: Theme.of(context).textTheme.headlineSmall),
            ),
          ),
          for (final d in docs) _Linha(id: d.id, e: d.data(), porHora: porHora(d.data())),
        ]);
      },
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.id, required this.e, required this.porHora});
  final String id;
  final Map<String, dynamic> e;
  final double porHora;

  Future<void> _acao(BuildContext context, String acao) async {
    final bloqueado = e['bloqueado'] == true;
    final isento = e['isento'] == true;
    final motivo = TextEditingController();
    final titulo = switch (acao) {
      'bloquear' => bloqueado ? 'Desbloquear' : 'Bloquear',
      _ => isento ? 'Remover isenção' : 'Isentar de taxa (exceção)',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$titulo: ${e['nome']}'),
        content: TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo (fica na auditoria)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await executar(
      context,
      () => acao == 'bloquear'
          ? chamar('bloquearUsuario', {'uid': id, 'bloquear': !bloqueado, 'motivo': motivo.text})
          : chamar('definirIsencao', {'entregadorId': id, 'isento': !isento, 'motivo': motivo.text}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = e['statsHoje'] as Map? ?? {};
    final disp = e['disponibilidade'] as String? ?? 'offline';
    final online = disp == 'disponivel' || disp == 'em_entrega';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: e['bloqueado'] == true ? Colors.red : (online ? Colors.green : null),
        child: Text(((e['nome'] as String?) ?? '').isEmpty ? '?' : (e['nome'] as String).substring(0, 1).toUpperCase()),
      ),
      title: Text('${e['nome'] ?? ''}${e['isento'] == true ? ' · isento' : ''}${e['faturaBloqueada'] == true ? ' · fatura atrasada' : ''}'),
      subtitle: Text('$disp · hoje ${s['entregas'] ?? 0} entregas · ${porHora.toStringAsFixed(1)}/h · '
          '${(e['recusas'] as List?)?.length ?? 0} recusas · ${e['lojaEquipeNome'] != null ? 'equipe ${e['lojaEquipeNome']}' : 'geral'}'),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (a) => _acao(context, a),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'bloquear', child: Text(e['bloqueado'] == true ? 'Desbloquear' : 'Bloquear')),
          PopupMenuItem(value: 'isencao', child: Text(e['isento'] == true ? 'Remover isenção' : 'Isentar de taxa')),
        ],
      ),
    );
  }
}
