import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'servicos/api.dart';
import 'servicos/notificacoes.dart';
import 'servicos/processador_comandas.dart';
import 'tema.dart';
import 'telas/entrada.dart';
import 'telas/entregador/cadastro_entregador.dart';
import 'telas/entregador/home_entregador.dart';
import 'telas/lojista/cadastro_loja.dart';
import 'telas/lojista/home_lojista.dart';
import 'widgets/comum.dart';

const _usarEmulador = bool.fromEnvironment('USAR_EMULADOR');

Future<void> _iniciarFirebase() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (_usarEmulador) {
    const host = String.fromEnvironment('EMULADOR_HOST', defaultValue: '10.0.2.2');
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    funcoes.useFunctionsEmulator(host, 5001);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!DefaultFirebaseOptions.configurado) {
    runApp(const _SemConfiguracao());
    return;
  }
  await _iniciarFirebase();
  runApp(const RodaJustaApp());
}

/// Ponto de entrada do motor sem tela usado pelo serviço da impressora
/// (ServicoImpressora.kt): processa comandas com o app fechado.
@pragma('vm:entry-point')
Future<void> processadorDeComandas() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!DefaultFirebaseOptions.configurado) return;
  try {
    await _iniciarFirebase();
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow; // o app já iniciou neste processo
  }
  await ProcessadorComandas().iniciar();
}

class RodaJustaApp extends StatelessWidget {
  const RodaJustaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RodaJusta',
      debugShowCheckedModeBanner: false,
      theme: temaRodaJusta(Brightness.light),
      darkTheme: temaRodaJusta(Brightness.dark),
      home: const PortaDeEntrada(),
    );
  }
}

/// Decide a tela pelo estado da conta: login → perfil → cadastro → análise → início.
class PortaDeEntrada extends StatelessWidget {
  const PortaDeEntrada({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.idTokenChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Scaffold(body: Carregando());
        final user = snap.data;
        if (user == null) return const TelaLogin();
        return FutureBuilder<Map<String, dynamic>>(
          key: ValueKey(user.uid),
          future: claims(),
          builder: (context, c) {
            if (!c.hasData) return const Scaffold(body: Carregando());
            final papel = c.data!['papel'] as String?;
            if (papel == null) return const TelaPerfil();
            if (papel == 'admin') return const _Mensagem('Esta é uma conta de administrador. Use o app RodaJusta Admin.');
            return _PorPerfil(papel: papel, aprovadoNoToken: c.data!['aprovado'] == true);
          },
        );
      },
    );
  }
}

class _PorPerfil extends StatefulWidget {
  const _PorPerfil({required this.papel, required this.aprovadoNoToken});
  final String papel;
  final bool aprovadoNoToken;

  @override
  State<_PorPerfil> createState() => _PorPerfilState();
}

class _PorPerfilState extends State<_PorPerfil> {
  bool _renovando = false;

  @override
  void initState() {
    super.initState();
    Notificacoes.iniciar(widget.papel);
  }

  @override
  Widget build(BuildContext context) {
    final colecao = widget.papel == 'lojista' ? 'lojistas' : 'entregadores';
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.doc('$colecao/$uid').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: Carregando());
        final d = snap.data!.data() ?? {};
        if (d['cadastroCompleto'] != true) {
          return widget.papel == 'lojista' ? const CadastroLoja() : const CadastroEntregador();
        }
        if (d['aprovado'] != true) return const TelaAguardando();
        if (!widget.aprovadoNoToken) {
          // aprovado no banco mas o token ainda é antigo: renova uma vez
          if (!_renovando) {
            _renovando = true;
            claims(renovar: true);
          }
          return const Scaffold(body: Carregando());
        }
        return widget.papel == 'lojista' ? const HomeLojista() : const HomeEntregador();
      },
    );
  }
}

class _Mensagem extends StatelessWidget {
  const _Mensagem(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Vazio(texto, icone: Icons.info_outline),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.all(16),
          child: TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Sair')),
        ),
      );
}

class _SemConfiguracao extends StatelessWidget {
  const _SemConfiguracao();
  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: temaRodaJusta(Brightness.light),
        home: const Scaffold(
          body: Vazio(
            'Firebase não configurado.\nRode "flutterfire configure" nesta pasta ou compile com --dart-define-from-file.',
            icone: Icons.settings_outlined,
          ),
        ),
      );
}
