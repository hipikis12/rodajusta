import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import '../../servicos/api.dart';
import '../../widgets/comum.dart';
import 'recepcao_comandas.dart';

/// Configurações da loja: valor da entrega, destino dos pedidos, impressora, iFood.
class AjustesLoja extends StatelessWidget {
  const AjustesLoja({super.key});

  Future<void> _salvar(BuildContext context, Map<String, dynamic> config) =>
      executar(context, () => db.doc('lojistas/$uid').update({'config': config}));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.doc('lojistas/$uid').snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Carregando();
          final loja = snap.data!.data() ?? {};
          final c = Map<String, dynamic>.from(loja['config'] as Map? ?? {});
          Map<String, dynamic> com(String k, Object? v) => {...c, k: v};
          final modo = c['valorModo'] as String? ?? 'fixo';
          return ListView(children: [
            const _Titulo('Valor da entrega'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'fixo', label: Text('Fixo')),
                  ButtonSegment(value: 'faixas', label: Text('Por distância')),
                  ButtonSegment(value: 'manual', label: Text('Digitar')),
                ],
                selected: {modo},
                onSelectionChanged: (s) => _salvar(context, com('valorModo', s.first)),
              ),
            ),
            if (modo == 'fixo')
              ListTile(
                title: const Text('Valor fixo por entrega'),
                trailing: Text(formatarReais((c['valorFixoCentavos'] as num? ?? 0).toInt()),
                    style: Theme.of(context).textTheme.titleMedium),
                onTap: () async {
                  final v = await _pedirValor(context, 'Valor fixo por entrega');
                  if (v != null && context.mounted) await _salvar(context, com('valorFixoCentavos', v));
                },
              ),
            if (modo == 'faixas') _Faixas(config: c, salvar: (f) => _salvar(context, com('faixas', f))),
            if (modo == 'manual')
              const ListTile(subtitle: Text('Você digita o valor em cada pedido, na hora de enviar.')),
            const ListTile(
              dense: true,
              subtitle: Text('Em qualquer modo, dá para mudar o valor de um pedido antes de enviar.'),
            ),
            const _Titulo('Destino dos pedidos'),
            RadioGroup<String>(
              groupValue: c['destinoPadrao'] as String? ?? 'geral',
              onChanged: (v) => _salvar(context, com('destinoPadrao', v)),
              child: const Column(children: [
                RadioListTile(value: 'equipe_primeiro', title: Text('Minha equipe primeiro, depois o sistema geral')),
                RadioListTile(value: 'equipe', title: Text('Só minha equipe')),
                RadioListTile(value: 'geral', title: Text('Só o sistema geral')),
              ]),
            ),
            ListTile(
              title: const Text('Tempo de espera pela equipe'),
              subtitle: const Text('Depois disso, o pedido vai para o sistema geral.'),
              trailing: DropdownButton<int>(
                value: (c['esperaEquipeSeg'] as num?)?.toInt() ?? 60,
                items: const [30, 60, 90, 120, 180]
                    .map((s) => DropdownMenuItem(value: s, child: Text('$s s')))
                    .toList(),
                onChanged: (v) => _salvar(context, com('esperaEquipeSeg', v)),
              ),
            ),
            SwitchListTile(
              title: const Text('Envio automático'),
              subtitle: const Text('Comandas com endereço bem lido saem sem precisar tocar em Enviar.'),
              value: c['envioAutomatico'] == true,
              onChanged: (v) => _salvar(context, com('envioAutomatico', v)),
            ),
            const _Titulo('Receber comandas do PDV'),
            RecepcaoComandas(config: c, salvar: (novo) => _salvar(context, novo)),
            const _Titulo('iFood'),
            ListTile(
              title: Text(loja['ifoodMerchantId'] == null ? 'Conectar loja do iFood' : 'iFood conectado'),
              subtitle: Text(loja['ifoodMerchantId'] == null
                  ? 'Para pedidos com entrega própria entrarem sozinhos.'
                  : 'ID ${loja['ifoodMerchantId']}'),
              onTap: () => _conectarIfood(context),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sair'),
              onTap: () => FirebaseAuth.instance.signOut(),
            ),
          ]);
        },
      ),
    );
  }

  Future<void> _conectarIfood(BuildContext context) async {
    final id = TextEditingController();
    var automatico = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Conectar iFood'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Informe o ID da sua loja no iFood (Portal do Parceiro). Só pedidos com entrega própria entram.'),
            TextField(controller: id, decoration: const InputDecoration(labelText: 'ID da loja (merchantId)')),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: automatico,
              onChanged: (v) => set(() => automatico = v ?? false),
              title: const Text('Enviar automaticamente aos entregadores'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Conectar')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      await executar(context, () => chamar('vincularIfood', {'merchantId': id.text.trim(), 'envioAutomatico': automatico}));
    }
  }
}

Future<int?> _pedirValor(BuildContext context, String titulo) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(titulo),
      content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: 'R\$ ')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Salvar')),
      ],
    ),
  );
  return ok == true ? lerReais(c.text) : null;
}

class _Faixas extends StatelessWidget {
  const _Faixas({required this.config, required this.salvar});
  final Map<String, dynamic> config;
  final Future<void> Function(List<Map<String, dynamic>>) salvar;

  @override
  Widget build(BuildContext context) {
    final faixas = ((config['faixas'] as List?) ?? []).map((f) => Map<String, dynamic>.from(f as Map)).toList()
      ..sort((a, b) => (a['ateKm'] as num).compareTo(b['ateKm'] as num));
    return Column(children: [
      for (var i = 0; i < faixas.length; i++)
        ListTile(
          title: Text('Até ${faixas[i]['ateKm']} km'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(formatarReais((faixas[i]['valorCentavos'] as num).toInt())),
            IconButton(icon: const Icon(Icons.close), onPressed: () => salvar([...faixas]..removeAt(i))),
          ]),
        ),
      TextButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Adicionar faixa'),
        onPressed: () async {
          final km = TextEditingController();
          final ok = await showDialog<bool>(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text('Até quantos km?'),
              content: TextField(controller: km, keyboardType: TextInputType.number, decoration: const InputDecoration(suffixText: 'km')),
              actions: [FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Próximo'))],
            ),
          );
          final ateKm = double.tryParse(km.text.replaceAll(',', '.'));
          if (ok != true || ateKm == null || !context.mounted) return;
          final valor = await _pedirValor(context, 'Valor até $ateKm km');
          if (valor == null) return;
          await salvar([...faixas, {'ateKm': ateKm, 'valorCentavos': valor}]);
        },
      ),
    ]);
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(texto, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
