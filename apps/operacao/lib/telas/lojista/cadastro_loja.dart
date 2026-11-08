import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import '../../servicos/api.dart';
import '../../servicos/localizacao.dart';
import '../../widgets/comum.dart';

/// Etapa 2 do lojista: dados da loja e onde ela fica.
class CadastroLoja extends StatefulWidget {
  const CadastroLoja({super.key});
  @override
  State<CadastroLoja> createState() => _CadastroLojaState();
}

class _CadastroLojaState extends State<CadastroLoja> {
  final _nome = TextEditingController();
  final _doc = TextEditingController();
  final _endereco = TextEditingController();
  Ponto? _ponto;
  String? _confirmado;

  Future<void> _localizarPeloEndereco() async {
    final p = await executar(context, () => geocodificar(_endereco.text));
    if (!mounted) return;
    if (p == null) {
      avisar(context, 'Endereço não encontrado. Inclua número, bairro e cidade.');
      return;
    }
    final texto = await enderecoDe(p);
    setState(() {
      _ponto = p;
      _confirmado = texto ?? '${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}';
    });
  }

  Future<void> _usarLocalAtual() async {
    final pos = await executar(context, () => posicaoAtual());
    if (pos == null || !mounted) return;
    final p = Ponto(pos.latitude, pos.longitude);
    final texto = await enderecoDe(p);
    setState(() {
      _ponto = p;
      _confirmado = texto;
      if (_endereco.text.isEmpty && texto != null) _endereco.text = texto;
    });
  }

  Future<void> _enviar() async {
    await executar(context, () => chamar('completarCadastroLojista', {
          'nomeFantasia': _nome.text,
          'cpfCnpj': _doc.text,
          'endereco': _endereco.text,
          'lat': _ponto!.lat,
          'lng': _ponto!.lng,
        }));
  }

  @override
  Widget build(BuildContext context) {
    final pronto = _ponto != null && _nome.text.trim().length >= 2 && _doc.text.trim().length >= 11;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dados da loja'),
        actions: [TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Sair'))],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _nome, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Nome da loja')),
        const SizedBox(height: 12),
        TextField(
          controller: _doc,
          onChanged: (_) => setState(() {}),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'CPF ou CNPJ'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _endereco,
          decoration: const InputDecoration(labelText: 'Endereço da loja', hintText: 'Rua, número, bairro, cidade'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _localizarPeloEndereco, child: const Text('Localizar endereço'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: _usarLocalAtual, child: const Text('Estou na loja agora'))),
        ]),
        if (_confirmado != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.place),
              title: const Text('Confira se é aqui'),
              subtitle: Text(_confirmado!),
            ),
          ),
        const SizedBox(height: 8),
        const Text('A localização da loja define quais entregadores recebem seus pedidos primeiro.'),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: pronto ? _enviar : null, child: const Text('Enviar para análise')),
        ),
      ),
    );
  }
}
