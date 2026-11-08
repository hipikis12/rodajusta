import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'servicos/api.dart';
import 'tema.dart';
import 'telas/aprovacoes.dart';
import 'telas/entregadores.dart';
import 'telas/financeiro.dart';
import 'telas/incentivos.dart';
import 'telas/painel.dart';
import 'telas/parametros.dart';
import 'widgets/comum.dart';

const _usarEmulador = bool.fromEnvironment('USAR_EMULADOR');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!DefaultFirebaseOptions.configurado) {
    runApp(MaterialApp(
      theme: temaRodaJusta(Brightness.light),
      home: const Scaffold(body: Vazio('Firebase não configurado. Rode "flutterfire configure" nesta pasta.')),
    ));
    return;
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (_usarEmulador) {
    const host = String.fromEnvironment('EMULADOR_HOST', defaultValue: '10.0.2.2');
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    funcoes.useFunctionsEmulator(host, 5001);
  }
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RodaJusta Admin',
        debugShowCheckedModeBanner: false,
        theme: temaRodaJusta(Brightness.light),
        darkTheme: temaRodaJusta(Brightness.dark),
        home: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.idTokenChanges(),
          builder: (context, s) {
            if (s.connectionState == ConnectionState.waiting) return const Scaffold(body: Carregando());
            if (s.data == null) return const _Login();
            return FutureBuilder<Map<String, dynamic>>(
              future: claims(),
              builder: (context, c) {
                if (!c.hasData) return const Scaffold(body: Carregando());
                return c.data!['papel'] == 'admin' ? const Inicio() : const _NaoAdmin();
              },
            );
          },
        ),
      );
}

class _Login extends StatelessWidget {
  const _Login();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Marca(tamanho: 120),
            const SizedBox(height: 12),
            Text('RodaJusta Admin', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Entrar com Google'),
              onPressed: () async {
                try {
                  await FirebaseAuth.instance.signInWithProvider(GoogleAuthProvider());
                } on FirebaseAuthException catch (e) {
                  if (context.mounted) avisar(context, e.message ?? 'Não foi possível entrar.');
                }
              },
            ),
          ]),
        ),
      );
}

class _NaoAdmin extends StatelessWidget {
  const _NaoAdmin();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Conta: ${FirebaseAuth.instance.currentUser?.email ?? ''}'),
              const SizedBox(height: 8),
              const Text('Esta conta ainda não é administradora.', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => executar(context, () async {
                  await chamar('reivindicarAdmin');
                  await claims(renovar: true);
                }),
                child: const Text('Sou o administrador'),
              ),
              TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Sair')),
            ]),
          ),
        ),
      );
}

class Inicio extends StatefulWidget {
  const Inicio({super.key});
  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  int _secao = 0;

  static const _secoes = <(IconData, String, Widget)>[
    (Icons.dashboard_outlined, 'Painel ao vivo', Painel()),
    (Icons.how_to_reg_outlined, 'Aprovações', Aprovacoes()),
    (Icons.two_wheeler, 'Entregadores', Entregadores()),
    (Icons.receipt_long_outlined, 'Financeiro', Financeiro()),
    (Icons.umbrella_outlined, 'Incentivos e rodízio', Incentivos()),
    (Icons.tune, 'Parâmetros e zonas', Parametros()),
  ];

  @override
  Widget build(BuildContext context) {
    final atual = _secoes[_secao];
    return Scaffold(
      appBar: AppBar(title: Text(atual.$2)),
      drawer: NavigationDrawer(
        selectedIndex: _secao,
        onDestinationSelected: (i) {
          setState(() => _secao = i);
          Navigator.pop(context);
        },
        children: [
          const Padding(padding: EdgeInsets.all(16), child: Row(children: [Marca(tamanho: 36), SizedBox(width: 8), Text('RodaJusta Admin')])),
          for (final s in _secoes) NavigationDrawerDestination(icon: Icon(s.$1), label: Text(s.$2)),
          const Divider(),
          ListTile(leading: const Icon(Icons.logout), title: const Text('Sair'), onTap: () => FirebaseAuth.instance.signOut()),
        ],
      ),
      body: atual.$3,
    );
  }
}
