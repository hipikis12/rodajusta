import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../servicos/api.dart';
import '../widgets/comum.dart';

/// Cadastros completos aguardando aprovação.
class Aprovacoes extends StatelessWidget {
  const Aprovacoes({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        const TabBar(tabs: [Tab(text: 'Entregadores'), Tab(text: 'Lojas')]),
        Expanded(
          child: TabBarView(children: [
            _Fila(colecao: 'entregadores'),
            _Fila(colecao: 'lojistas'),
          ]),
        ),
      ]),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.colecao});
  final String colecao;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection(colecao).where('cadastroCompleto', isEqualTo: true).where('aprovado', isEqualTo: false).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Carregando();
        if (snap.data!.docs.isEmpty) return const Vazio('Nenhum cadastro aguardando.', icone: Icons.task_alt);
        return ListView(children: [for (final d in snap.data!.docs) _Cadastro(id: d.id, d: d.data(), entregador: colecao == 'entregadores')]);
      },
    );
  }
}

class _Cadastro extends StatelessWidget {
  const _Cadastro({required this.id, required this.d, required this.entregador});
  final String id;
  final Map<String, dynamic> d;
  final bool entregador;

  Future<void> _recusar(BuildContext context) async {
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('O que precisa ajustar?'),
        content: TextField(controller: motivo, decoration: const InputDecoration(hintText: 'Ex.: foto da CNH ilegível')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enviar')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await executar(context, () => chamar('aprovarCadastro', {'uid': id, 'aprovar': false, 'motivo': motivo.text}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = d['docs'] as Map? ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(entregador ? (d['nome'] as String? ?? '') : (d['nomeFantasia'] as String? ?? ''),
              style: Theme.of(context).textTheme.titleMedium),
          Text('Telefone: ${d['telefone'] ?? ''}'),
          if (entregador) ...[
            Text('CPF: ${d['cpf'] ?? ''} · ${d['veiculo'] ?? ''} ${d['placa'] ?? ''}'),
            Text('Plano: ${d['plano'] ?? ''} · Zona: ${d['zonaId'] ?? ''}'),
            const SizedBox(height: 8),
            Row(children: [
              for (final caminho in [docs['cnh'], docs['selfie']].whereType<String>().where((s) => s.isNotEmpty))
                Padding(padding: const EdgeInsets.only(right: 8), child: _Foto(caminho: caminho)),
            ]),
          ] else ...[
            Text('CPF/CNPJ: ${d['cpfCnpj'] ?? ''}'),
            Text('${d['endereco'] ?? ''} · zona ${d['zonaId'] ?? ''}'),
          ],
          const SizedBox(height: 8),
          Row(children: [
            TextButton(onPressed: () => _recusar(context), child: const Text('Pedir ajuste')),
            const Spacer(),
            FilledButton(
              onPressed: () => executar(context, () => chamar('aprovarCadastro', {'uid': id, 'aprovar': true})),
              child: const Text('Aprovar'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Foto extends StatelessWidget {
  const _Foto({required this.caminho});
  final String caminho;
  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: FirebaseStorage.instance.ref(caminho).getDownloadURL(),
        builder: (context, s) => s.hasData
            ? GestureDetector(
                onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(s.data!)))),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(s.data!, width: 120, height: 90, fit: BoxFit.cover),
                ),
              )
            : const SizedBox(width: 120, height: 90, child: Carregando()),
      );
}
