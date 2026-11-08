import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../servicos/api.dart';
import '../tema.dart';
import '../widgets/comum.dart';

class TelaLogin extends StatefulWidget {
  const TelaLogin({super.key});
  @override
  State<TelaLogin> createState() => _TelaLoginState();
}

class _TelaLoginState extends State<TelaLogin> {
  bool _entrando = false;

  Future<void> _entrarComGoogle() async {
    setState(() => _entrando = true);
    try {
      final provedor = GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});
      await FirebaseAuth.instance.signInWithProvider(provedor);
    } on FirebaseAuthException catch (e) {
      if (mounted && e.code != 'web-context-canceled') avisar(context, e.message ?? 'Não foi possível entrar.');
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            const Marca(tamanho: 120),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Roda', style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: Cores.verde)),
                TextSpan(text: 'Justa', style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: Cores.ambar)),
              ]),
            ),
            const SizedBox(height: 8),
            Text('Entregas divididas de um jeito justo.', style: t.bodyLarge, textAlign: TextAlign.center),
            const Spacer(),
            FilledButton.icon(
              onPressed: _entrando ? null : _entrarComGoogle,
              icon: const Icon(Icons.login),
              label: Text(_entrando ? 'Entrando...' : 'Entrar com Google'),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}

/// Primeira etapa: escolher o perfil e informar o telefone.
class TelaPerfil extends StatefulWidget {
  const TelaPerfil({super.key});
  @override
  State<TelaPerfil> createState() => _TelaPerfilState();
}

class _TelaPerfilState extends State<TelaPerfil> {
  String? _papel;
  final _telefone = TextEditingController();
  final _nome = TextEditingController(text: FirebaseAuth.instance.currentUser?.displayName ?? '');

  Future<void> _continuar() async {
    final ok = await executar(context, () async {
      await chamar('definirPerfil', {'papel': _papel, 'telefone': _telefone.text, 'nome': _nome.text});
      await claims(renovar: true);
      return true;
    });
    if (ok == true && mounted) setState(() {});
  }

  Widget _opcao(String papel, IconData icone, String titulo, String texto) {
    final sel = _papel == papel;
    final cor = Theme.of(context).colorScheme;
    return Card(
      color: sel ? cor.primaryContainer : null,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(icone, size: 36, color: sel ? cor.primary : null),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(texto),
        onTap: () => setState(() => _papel = papel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Como você vai usar?'),
        actions: [TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Sair'))],
      ),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        _opcao('lojista', Icons.storefront, 'Sou lojista', 'Envio pedidos para entregadores.'),
        _opcao('entregador', Icons.two_wheeler, 'Sou entregador', 'Recebo e faço entregas.'),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(controller: _nome, decoration: const InputDecoration(labelText: 'Seu nome')),
            const SizedBox(height: 12),
            TextField(
              controller: _telefone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefone (WhatsApp) com DDD', hintText: '69 99999-0000'),
            ),
            const SizedBox(height: 8),
            const Text('Só isso para começar. O restante do cadastro vem depois.'),
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: _papel == null ? null : _continuar, child: const Text('Continuar')),
        ),
      ),
    );
  }
}

class TelaAguardando extends StatelessWidget {
  const TelaAguardando({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('RodaJusta'),
          actions: [TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Sair'))],
        ),
        body: const Vazio(
          'Cadastro enviado!\nEstamos conferindo seus dados. Você recebe um aviso assim que for aprovado.',
          icone: Icons.hourglass_top,
        ),
      );
}
