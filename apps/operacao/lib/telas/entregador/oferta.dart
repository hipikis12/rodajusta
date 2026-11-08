import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import '../../servicos/api.dart';
import '../../widgets/comum.dart';

/// Oferta em tela cheia: loja, bairros, distância e valor. 30 s para responder.
/// Com várias entregas (lote), o aceite vale para todas.
class TelaOferta extends StatefulWidget {
  const TelaOferta({super.key, required this.id, required this.oferta});
  final String id;
  final Map<String, dynamic> oferta;
  @override
  State<TelaOferta> createState() => _TelaOfertaState();
}

class _TelaOfertaState extends State<TelaOferta> {
  late final DateTime _expira = (widget.oferta['expiraEm'] as Timestamp).toDate();
  late final int _total = _expira.difference(DateTime.now()).inSeconds.clamp(1, 600);
  Timer? _timer;
  int _restante = 0;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _restante = _total;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final r = _expira.difference(DateTime.now()).inSeconds;
      if (r <= 0) {
        _fechar();
      } else {
        setState(() => _restante = r);
      }
    });
    // se outro entregador aceitar antes, a oferta expira e a tela fecha
    _sub = db.doc('ofertas/${widget.id}').snapshots().listen((s) {
      if (s.data()?['status'] != 'pendente') _fechar();
    });
  }

  bool _fechada = false;

  void _fechar() {
    _timer?.cancel();
    if (_fechada || !mounted) return;
    _fechada = true;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.oferta;
    final qtd = (o['qtdEntregas'] as num? ?? 1).toInt();
    final bairros = (o['bairros'] as List? ?? []).cast<String>();
    final valores = (o['valores'] as List? ?? []).map((v) => (v as num).toInt()).toList();
    final cor = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: qtd > 1 ? cor.secondaryContainer : cor.primaryContainer,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LinearProgressIndicator(value: _restante / _total, minHeight: 8, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 8),
            Text('$_restante s', textAlign: TextAlign.right),
            const SizedBox(height: 8),
            if (qtd > 1)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: cor.secondary, borderRadius: BorderRadius.circular(12)),
                child: Text('$qtd ENTREGAS', textAlign: TextAlign.center,
                    style: t.headlineMedium?.copyWith(color: cor.onSecondary, fontWeight: FontWeight.w900)),
              ),
            const SizedBox(height: 16),
            Text(o['lojaNome'] as String? ?? '', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text('${o['distanciaLojaKm']} km até a loja · ${o['lojaEndereco'] ?? ''}'),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(children: [
                for (var i = 0; i < bairros.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(bairros[i], style: t.titleMedium),
                    trailing: i < valores.length ? Text(formatarReais(valores[i]), style: t.titleMedium) : null,
                  ),
                const Divider(),
                LinhaValor('Percurso total aproximado', '${o['distanciaTotalKm']} km'),
                LinhaValor('Você recebe da loja', formatarReais((o['valorTotalCentavos'] as num? ?? 0).toInt()), destaque: true),
                if (qtd > 1)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Ao aceitar, você leva todas as entregas deste lote.'),
                  ),
                const SizedBox(height: 4),
                const Text('O endereço completo aparece depois do aceite.'),
              ]),
            ),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    _timer?.cancel();
                    await executar(context, () => chamar('recusarOferta', {'ofertaId': widget.id}));
                    _fechar();
                  },
                  child: const Text('Recusar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () async {
                    final r = await executar(context, () => chamar('aceitarOferta', {'ofertaId': widget.id}));
                    if (r != null) _fechar();
                  },
                  child: Text(qtd > 1 ? 'Aceitar as $qtd' : 'Aceitar'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
