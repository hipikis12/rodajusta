import 'package:flutter/material.dart';

import '../../servicos/api.dart';
import '../../servicos/impressora.dart';
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

  @override
  void initState() {
    super.initState();
    _garantirImpressora();
  }

  /// O serviço da impressora roda sozinho (inclusive depois de reiniciar o
  /// celular); ao abrir o app só confere se está como a loja configurou.
  Future<void> _garantirImpressora() async {
    final loja = await db.doc('lojistas/$uid').get();
    final config = Map<String, dynamic>.from(loja.data()?['config'] as Map? ?? {});
    try {
      await ImpressoraVirtual.instancia.aplicar(config);
    } catch (_) {
      // sem Bluetooth ou sem permissão: a barra da aba Enviar mostra o motivo
    }
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
