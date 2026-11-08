import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import '../servicos/api.dart';
import '../widgets/comum.dart';

/// Pesos do algoritmo, taxa da plataforma e zonas.
class Parametros extends StatefulWidget {
  const Parametros({super.key});
  @override
  State<Parametros> createState() => _ParametrosState();
}

class _ParametrosState extends State<Parametros> {
  Map<String, dynamic>? _p;

  @override
  void initState() {
    super.initState();
    db.doc('config/parametros').get().then((s) {
      if (mounted) setState(() => _p = _comPadroes(s.data() ?? {}));
    });
  }

  static Map<String, dynamic> _comPadroes(Map<String, dynamic> p) => <String, dynamic>{
        'pesos': <String, dynamic>{'distancia': 0.45, 'espera': 0.25, 'equidade': 0.2, 'rodizio': 0.1, 'penalidade': 0.15, ...?(p['pesos'] as Map?)?.cast<String, dynamic>()},
        'taxa': <String, dynamic>{'porEntregaCentavos': 80, 'mensalCentavos': 8000, 'diasVencimento': 5, 'diasAtrasoBloqueio': 3, ...?(p['taxa'] as Map?)?.cast<String, dynamic>()},
        'segundosPorOnda': p['segundosPorOnda'] ?? 30,
        'maxEntregasPorLote': p['maxEntregasPorLote'] ?? 3,
        'raioEntregaM': p['raioEntregaM'] ?? 150,
        if (p['ondas'] != null) 'ondas': p['ondas'],
        if (p['gatilhos'] != null) 'gatilhos': p['gatilhos'],
      };

  Widget _numero(String rotulo, String grupo, String chave, {bool dinheiro = false, String? ajuda}) {
    final mapa = grupo.isEmpty ? _p! : (_p![grupo] as Map<String, dynamic>);
    final valor = mapa[chave] as num? ?? 0;
    return ListTile(
      title: Text(rotulo),
      subtitle: ajuda == null ? null : Text(ajuda),
      trailing: Text(dinheiro ? formatarReais(valor.toInt()) : '$valor', style: Theme.of(context).textTheme.titleMedium),
      onTap: () async {
        final c = TextEditingController(text: dinheiro ? formatarReais(valor.toInt()).replaceAll('R\$ ', '') : '$valor');
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(rotulo),
            content: TextField(controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            actions: [FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('OK'))],
          ),
        );
        if (ok != true) return;
        final novo = dinheiro ? lerReais(c.text) : num.tryParse(c.text.replaceAll(',', '.'));
        if (novo != null) setState(() => mapa[chave] = novo);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_p == null) return const Carregando();
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      const _Secao('Taxa da plataforma'),
      _numero('Por entrega', 'taxa', 'porEntregaCentavos', dinheiro: true),
      _numero('Mensalidade', 'taxa', 'mensalCentavos', dinheiro: true),
      _numero('Dias para vencer após o fechamento', 'taxa', 'diasVencimento'),
      _numero('Dias de atraso até bloquear', 'taxa', 'diasAtrasoBloqueio'),
      const _Secao('Pesos da distribuição'),
      _numero('Distância', 'pesos', 'distancia', ajuda: 'Quanto pesa estar perto da loja'),
      _numero('Espera', 'pesos', 'espera', ajuda: 'Quem está parado há mais tempo sobe'),
      _numero('Equidade', 'pesos', 'equidade', ajuda: 'Quem fez menos entregas por hora sobe'),
      _numero('Rodízio', 'pesos', 'rodizio', ajuda: 'Bônus para quem está no turno reservado'),
      _numero('Penalidade por recusa', 'pesos', 'penalidade'),
      const _Secao('Operação'),
      _numero('Segundos por onda de oferta', '', 'segundosPorOnda'),
      _numero('Máximo de entregas por lote', '', 'maxEntregasPorLote'),
      _numero('Raio para finalizar a entrega (m)', '', 'raioEntregaM'),
      Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: () async {
            final r = await executar(context, () => chamar('salvarParametros', {'parametros': _p}));
            if (r != null && mounted) {
              setState(() => _p = _comPadroes(Map<String, dynamic>.from(r['parametros'] as Map)));
              if (context.mounted) avisar(context, 'Parâmetros salvos.');
            }
          },
          child: const Text('Salvar parâmetros'),
        ),
      ),
      const _Secao('Zonas'),
      const _Zonas(),
    ]);
  }
}

class _Zonas extends StatelessWidget {
  const _Zonas();

  Future<void> _editar(BuildContext context, [String? id, Map<String, dynamic>? z]) async {
    final cId = TextEditingController(text: id ?? '');
    final nome = TextEditingController(text: z?['nome'] as String? ?? '');
    final lat = TextEditingController(text: '${z?['lat'] ?? ''}');
    final lng = TextEditingController(text: '${z?['lng'] ?? ''}');
    final raio = TextEditingController(text: '${z?['raioKm'] ?? 8}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(id == null ? 'Nova zona' : 'Editar zona'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: cId, enabled: id == null, decoration: const InputDecoration(labelText: 'Id (ex.: ariquemes)')),
            TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome')),
            TextField(controller: lat, decoration: const InputDecoration(labelText: 'Latitude do centro')),
            TextField(controller: lng, decoration: const InputDecoration(labelText: 'Longitude do centro')),
            TextField(controller: raio, decoration: const InputDecoration(labelText: 'Raio (km)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salvar')),
        ],
      ),
    );
    double? n(TextEditingController t) => double.tryParse(t.text.replaceAll(',', '.'));
    if (ok != true || !context.mounted) return;
    await executar(context, () => chamar('salvarZona', {
          'id': cId.text,
          'nome': nome.text,
          'lat': n(lat),
          'lng': n(lng),
          'raioKm': n(raio),
          'ativa': true,
        }));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('zonas').snapshots(),
      builder: (context, snap) => Column(children: [
        for (final z in snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
          ListTile(
            title: Text('${z.data()['nome']} (${z.id})'),
            subtitle: Text('${z.data()['lat']}, ${z.data()['lng']} · raio ${z.data()['raioKm']} km'),
            onTap: () => _editar(context, z.id, z.data()),
          ),
        TextButton.icon(onPressed: () => _editar(context), icon: const Icon(Icons.add_location_alt), label: const Text('Adicionar zona')),
      ]),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao(this.t);
  final String t;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
