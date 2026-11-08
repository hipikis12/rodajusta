import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Erro amigável vindo das Cloud Functions.
class ErroApi implements Exception {
  ErroApi(this.mensagem, {this.codigo = '', this.motivo});
  final String mensagem;
  final String codigo;
  final String? motivo;
  @override
  String toString() => mensagem;
}

final funcoes = FirebaseFunctions.instanceFor(region: 'southamerica-east1');
final db = FirebaseFirestore.instance;

String get uid => FirebaseAuth.instance.currentUser!.uid;

Future<Map<String, dynamic>> chamar(String nome, [Map<String, dynamic>? dados]) async {
  try {
    final r = await funcoes
        .httpsCallable(nome, options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
        .call<dynamic>(dados ?? <String, dynamic>{});
    final d = r.data;
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  } on FirebaseFunctionsException catch (e) {
    final det = e.details;
    throw ErroApi(
      e.message ?? 'Algo deu errado. Tente de novo.',
      codigo: e.code,
      motivo: det is Map ? det['motivo']?.toString() : null,
    );
  }
}

/// Atualiza o token para pegar mudanças de perfil/aprovação feitas no servidor.
Future<Map<String, dynamic>> claims({bool renovar = false}) async {
  final r = await FirebaseAuth.instance.currentUser!.getIdTokenResult(renovar);
  return r.claims ?? {};
}
