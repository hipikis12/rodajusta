import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../servicos/api.dart';

/// Mostra o erro numa barra, sem derrubar a tela.
void avisar(BuildContext context, Object erro) {
  final msg = erro is ErroApi ? erro.mensagem : erro is String ? erro : 'Algo deu errado: $erro';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Executa uma ação mostrando carregando e tratando erro.
Future<T?> executar<T>(BuildContext context, Future<T> Function() acao) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final r = await acao();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    return r;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      avisar(context, e);
    }
    return null;
  }
}

class Carregando extends StatelessWidget {
  const Carregando({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class Vazio extends StatelessWidget {
  const Vazio(this.texto, {super.key, this.icone = Icons.inbox_outlined});
  final String texto;
  final IconData icone;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icone, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(texto, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          ]),
        ),
      );
}

class Marca extends StatelessWidget {
  const Marca({super.key, this.tamanho = 96});
  final double tamanho;
  @override
  Widget build(BuildContext context) => Image.asset('assets/marca.png', width: tamanho, height: tamanho);
}

/// Linha "rótulo .... valor" usada em resumos e extratos.
class LinhaValor extends StatelessWidget {
  const LinhaValor(this.rotulo, this.valor, {super.key, this.destaque = false});
  final String rotulo;
  final String valor;
  final bool destaque;
  @override
  Widget build(BuildContext context) {
    final estilo = destaque
        ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(rotulo, style: estilo)), Text(valor, style: estilo)]),
    );
  }
}

String dataHora(Object? ts) {
  if (ts is! Timestamp) return '';
  final d = ts.toDate();
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.day)}/${dois(d.month)} ${dois(d.hour)}:${dois(d.minute)}';
}
