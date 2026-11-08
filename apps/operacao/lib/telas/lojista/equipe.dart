import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../servicos/api.dart';
import '../../widgets/comum.dart';

/// Entregadores próprios da loja.
class EquipeLoja extends StatelessWidget {
  const EquipeLoja({super.key});

  Future<void> _convidar(BuildContext context) async {
    final codigo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Convidar entregador'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Peça o código de convite que aparece no perfil do app do entregador.'),
          const SizedBox(height: 12),
          TextField(
            controller: codigo,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Código (6 letras)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Convidar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final r = await executar(context, () => chamar('convidarEntregador', {'codigo': codigo.text.trim()}));
    if (r != null && context.mounted) avisar(context, 'Convite enviado para ${r['entregadorNome']}.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Minha equipe')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _convidar(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Convidar'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('lojistas/$uid/equipe').snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Carregando();
          final docs = snap.data!.docs;
          return ListView(children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Seus pedidos vão primeiro para a equipe (ajuste em Ajustes → Destino dos pedidos). '
                'Se ninguém dela estiver online ou aceitar a tempo, o pedido segue para o sistema geral.',
              ),
            ),
            if (docs.isEmpty) const Vazio('Nenhum entregador na equipe ainda.', icone: Icons.groups_outlined),
            for (final d in docs) _Membro(id: d.id, nome: d.data()['nome'] as String? ?? ''),
          ]);
        },
      ),
    );
  }
}

class _Membro extends StatelessWidget {
  const _Membro({required this.id, required this.nome});
  final String id;
  final String nome;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.doc('entregadores/$id').snapshots(),
      builder: (context, s) {
        final e = s.data?.data() ?? {};
        final disp = e['disponibilidade'] as String? ?? 'offline';
        final onde = switch (e['trabalhaEm']) { 'loja' => 'só para você', 'geral' => 'no sistema geral hoje', _ => 'você e sistema geral' };
        final online = disp == 'disponivel' || disp == 'em_entrega';
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: online ? Colors.green : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(online ? Icons.two_wheeler : Icons.bedtime_outlined, color: online ? Colors.white : null),
            ),
            title: Text(nome),
            subtitle: Text(online ? (disp == 'em_entrega' ? 'Em entrega · $onde' : 'Online · $onde') : 'Offline'),
            trailing: PopupMenuButton<String>(
              onSelected: (_) => executar(context, () => chamar('sairDaEquipe', {'entregadorId': id})),
              itemBuilder: (_) => const [PopupMenuItem(value: 'remover', child: Text('Remover da equipe'))],
            ),
          ),
        );
      },
    );
  }
}
