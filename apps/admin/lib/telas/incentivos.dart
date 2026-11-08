import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../servicos/api.dart';
import '../widgets/comum.dart';

/// Sugestões automáticas (chuva, falta, dia fraco, excesso), incentivos ativos e turnos.
class Incentivos extends StatelessWidget {
  const Incentivos({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _novo(context),
        icon: const Icon(Icons.add),
        label: const Text('Novo'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('incentivos').where('status', whereIn: ['sugerido', 'ativo']).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Carregando();
          final sugeridos = snap.data!.docs.where((d) => d.data()['status'] == 'sugerido').toList();
          final ativos = snap.data!.docs.where((d) => d.data()['status'] == 'ativo').toList();
          return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            const _Titulo('Sugestões do sistema'),
            if (sugeridos.isEmpty) const ListTile(subtitle: Text('Sem sugestões agora. O sistema mede as zonas a cada 15 minutos.')),
            for (final d in sugeridos) _Sugestao(id: d.id, i: d.data()),
            const _Titulo('Ativos'),
            if (ativos.isEmpty) const ListTile(subtitle: Text('Nenhum incentivo ativo.')),
            for (final d in ativos)
              ListTile(
                leading: Icon(d.data()['tipo'] == 'chuva' ? Icons.umbrella : Icons.local_fire_department),
                title: Text(_titulo(d.data())),
                subtitle: Text('Zona ${d.data()['zonaId']} · ${dataHora(d.data()['inicio'])} até ${dataHora(d.data()['fim'])}\n${d.data()['motivo'] ?? ''}'),
                isThreeLine: true,
              ),
            const _Titulo('Turnos de rodízio'),
            const _Turnos(),
          ]);
        },
      ),
    );
  }

  static String _titulo(Map<String, dynamic> i) => switch (i['modo']) {
        'bonus' => 'Bônus de ${i['percentual']}% para quem fizer ${i['minimoEntregas']}+ entregas',
        'rodizio' => 'Abrir turnos de rodízio',
        _ => '${i['percentual']}% de desconto na taxa',
      };

  Future<void> _novo(BuildContext context) async {
    final zona = TextEditingController(text: 'todas');
    final pct = TextEditingController(text: '50');
    final minimo = TextEditingController(text: '5');
    final horas = TextEditingController(text: '3');
    final motivo = TextEditingController();
    var modo = 'desconto';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Novo incentivo (começa agora)'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'desconto', label: Text('Desconto')), ButtonSegment(value: 'bonus', label: Text('Bônus semanal'))],
                selected: {modo},
                onSelectionChanged: (s) => set(() => modo = s.first),
              ),
              TextField(controller: zona, decoration: const InputDecoration(labelText: 'Zona (id ou "todas")')),
              TextField(controller: pct, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Percentual')),
              if (modo == 'bonus')
                TextField(controller: minimo, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Mínimo de entregas na janela')),
              TextField(controller: horas, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Duração (horas)')),
              TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Mensagem para os entregadores')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ativar')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final inicio = DateTime.now();
    final fim = inicio.add(Duration(minutes: ((double.tryParse(horas.text.replaceAll(',', '.')) ?? 1) * 60).round()));
    await executar(context, () => chamar('criarIncentivo', {
          'modo': modo,
          'zonaId': zona.text.trim(),
          'percentual': int.tryParse(pct.text) ?? 0,
          'minimoEntregas': int.tryParse(minimo.text) ?? 1,
          'inicioMs': inicio.millisecondsSinceEpoch,
          'fimMs': fim.millisecondsSinceEpoch,
          'motivo': motivo.text.trim().isEmpty ? 'Incentivo ativo na sua região' : motivo.text.trim(),
        }));
  }
}

class _Sugestao extends StatelessWidget {
  const _Sugestao({required this.id, required this.i});
  final String id;
  final Map<String, dynamic> i;
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Incentivos._titulo(i), style: Theme.of(context).textTheme.titleMedium),
          Text('${i['motivo']}\nZona ${i['zonaId']} · ${dataHora(i['inicio'])} até ${dataHora(i['fim'])}'),
          Row(children: [
            TextButton(
              onPressed: () => executar(context, () => chamar('decidirIncentivo', {'incentivoId': id, 'aprovar': false})),
              child: const Text('Recusar'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => executar(context, () => chamar('decidirIncentivo', {'incentivoId': id, 'aprovar': true})),
              child: const Text('Aprovar e avisar'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Turnos extends StatelessWidget {
  const _Turnos();

  Future<void> _novo(BuildContext context) async {
    final zona = TextEditingController();
    final vagas = TextEditingController(text: '10');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Turno amanhã, 18h às 22h'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: zona, decoration: const InputDecoration(labelText: 'Zona (id)')),
          TextField(controller: vagas, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Vagas')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Criar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final amanha = DateTime.now().add(const Duration(days: 1));
    final inicio = DateTime(amanha.year, amanha.month, amanha.day, 18);
    await executar(context, () => chamar('criarTurno', {
          'zonaId': zona.text.trim(),
          'vagas': int.tryParse(vagas.text) ?? 10,
          'inicioMs': inicio.millisecondsSinceEpoch,
          'fimMs': inicio.add(const Duration(hours: 4)).millisecondsSinceEpoch,
        }));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('turnos').where('fim', isGreaterThan: Timestamp.now()).snapshots(),
      builder: (context, snap) => Column(children: [
        for (final t in snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
          ListTile(
            title: Text('Zona ${t.data()['zonaId']} · ${dataHora(t.data()['inicio'])} até ${dataHora(t.data()['fim'])}'),
            trailing: Text('${(t.data()['reservados'] as List?)?.length ?? 0}/${t.data()['vagas']}'),
          ),
        TextButton.icon(onPressed: () => _novo(context), icon: const Icon(Icons.add), label: const Text('Criar turno')),
      ]),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
