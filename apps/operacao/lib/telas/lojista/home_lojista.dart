import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import '../../servicos/api.dart';
import '../../servicos/impressora.dart';
import '../../servicos/localizacao.dart';
import 'ajustes_loja.dart';
import 'enviar.dart';
import 'equipe.dart';
import 'financeiro_loja.dart';
import 'pedidos_loja.dart';

class HomeLojista extends StatefulWidget {
  const HomeLojista({super.key});
  @override
  State<HomeLojista> createState() => _HomeLojistaState();
}

class _HomeLojistaState extends State<HomeLojista> {
  int _aba = 0;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _auto;
  final _jaEnviadas = <String>{};

  @override
  void initState() {
    super.initState();
    _iniciarImpressora();
    _envioAutomatico();
  }

  Future<void> _iniciarImpressora() async {
    final loja = await db.doc('lojistas/$uid').get();
    final config = loja.data()?['config'] as Map? ?? {};
    if (config['impressoraAtiva'] == true) {
      try {
        await ImpressoraVirtual.instancia.iniciar(repassarPara: config['repassarPara'] as String?);
      } catch (_) {/* Bluetooth desligado: a aba Enviar mostra o estado */}
    }
  }

  /// Com "envio automático" ligado, comandas com endereço confiável saem sozinhas.
  void _envioAutomatico() {
    _auto = db
        .collection('lojistas/$uid/comandas')
        .where('status', isEqualTo: 'pendente')
        .snapshots()
        .listen((snap) async {
      final loja = (await db.doc('lojistas/$uid').get()).data() ?? {};
      final config = Map<String, dynamic>.from(loja['config'] as Map? ?? {});
      if (config['envioAutomatico'] != true) return;
      for (final d in snap.docs) {
        final c = d.data();
        if (_jaEnviadas.contains(d.id) || c['lat'] == null || (c['confianca'] as num? ?? 0) < 0.9) continue;
        final dist = distanciaKm(pontoDe(loja['lat'], loja['lng'])!, pontoDe(c['lat'], c['lng'])!);
        final valor = (c['valorEntregaCentavos'] as num?)?.toInt() ?? valorSugerido(config, dist);
        if (valor == null) continue;
        _jaEnviadas.add(d.id);
        try {
          await chamar('enviarPedidos', {
            'itens': [itemDeComanda(d.id, c, valor)],
            'juntas': false,
          });
        } catch (_) {
          _jaEnviadas.remove(d.id); // fica na lista para envio manual
        }
      }
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const telas = [TelaEnviar(), PedidosLoja(), EquipeLoja(), FinanceiroLoja(), AjustesLoja()];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _aba, children: telas)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _aba,
        onDestinationSelected: (i) => setState(() => _aba = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.send_outlined), selectedIcon: Icon(Icons.send), label: 'Enviar'),
          NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'Pedidos'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Equipe'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Extrato'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Ajustes'),
        ],
      ),
    );
  }
}

/// Item no formato que a função enviarPedidos espera.
Map<String, dynamic> itemDeComanda(String id, Map<String, dynamic> c, int valorCentavos) {
  final end = Map<String, dynamic>.from(c['endereco'] as Map? ?? {});
  final origem = c['origem'] as String? ?? 'manual';
  return {
    'comandaId': id,
    'descricao': c['descricao'] ?? '',
    'cliente': c['cliente'] ?? '',
    'telefoneCliente': c['telefone'] ?? '',
    'endereco': end['texto'] ?? '',
    'bairro': end['bairro'] ?? '',
    'complemento': end['complemento'] ?? '',
    'referencia': end['referencia'] ?? '',
    'lat': (c['lat'] as num?)?.toDouble(),
    'lng': (c['lng'] as num?)?.toDouble(),
    'valorEntregaCentavos': valorCentavos,
    'pagamento': c['pagamento'] ?? {'tipo': 'pago'},
    'origem': origem == 'ifood' ? 'ifood' : (origem == 'comanda' ? 'comanda' : 'manual'),
    'ifoodOrderId': c['ifoodOrderId'] ?? '',
  };
}
