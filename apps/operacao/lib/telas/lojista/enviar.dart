import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import '../../servicos/api.dart';
import '../../servicos/impressora.dart';
import '../../servicos/localizacao.dart';
import '../../widgets/comum.dart';
import 'home_lojista.dart';

/// Comandas pendentes (Bluetooth, iFood ou digitadas) e o botão Enviar.
class TelaEnviar extends StatefulWidget {
  const TelaEnviar({super.key});
  @override
  State<TelaEnviar> createState() => _TelaEnviarState();
}

class _TelaEnviarState extends State<TelaEnviar> {
  final _selecionadas = <String>{};

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.doc('lojistas/$uid').snapshots(),
      builder: (context, lojaSnap) {
        final loja = lojaSnap.data?.data() ?? {};
        final config = Map<String, dynamic>.from(loja['config'] as Map? ?? {});
        final pontoLoja = pontoDe(loja['lat'], loja['lng']);
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db
              .collection('lojistas/$uid/comandas')
              .where('status', isEqualTo: 'pendente')
              .orderBy('criadoEm', descending: true)
              .snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            _selecionadas.removeWhere((id) => !docs.any((d) => d.id == id));
            final itens = {for (final d in docs) d.id: d.data()};

            int? valorDe(String id) {
              final c = itens[id]!;
              final manual = (c['valorEntregaCentavos'] as num?)?.toInt();
              if (manual != null) return manual;
              final p = pontoDe(c['lat'], c['lng']);
              if (p == null || pontoLoja == null) return null;
              return valorSugerido(config, distanciaKm(pontoLoja, p));
            }

            bool prontaParaEnviar(String id) {
              final c = itens[id]!;
              final end = c['endereco'] as Map? ?? {};
              return c['lat'] != null && (end['bairro'] as String? ?? '').length >= 2 && valorDe(id) != null;
            }

            return Scaffold(
              appBar: AppBar(
                title: Text(loja['nomeFantasia'] as String? ?? 'Enviar'),
                bottom: const PreferredSize(preferredSize: Size.fromHeight(40), child: _BarraImpressora()),
              ),
              floatingActionButton: _selecionadas.isEmpty
                  ? FloatingActionButton.extended(
                      onPressed: () => _abrirComanda(context, null, null),
                      icon: const Icon(Icons.add),
                      label: const Text('Novo pedido'),
                    )
                  : null,
              body: docs.isEmpty
                  ? const Vazio(
                      'Nenhuma comanda pendente.\nImprima pelo seu sistema na impressora "RodaJusta", receba pelo iFood ou toque em Novo pedido.',
                      icone: Icons.receipt_outlined,
                    )
                  : ListView(padding: const EdgeInsets.only(bottom: 120), children: [
                      if (docs.length >= 2 && pontoLoja != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.alt_route),
                            label: const Text('Sugerir entregas juntas'),
                            onPressed: () => _sugerir(context, pontoLoja, itens, prontaParaEnviar),
                          ),
                        ),
                      for (final d in docs)
                        _CartaoComanda(
                          id: d.id,
                          dados: d.data(),
                          valor: valorDe(d.id),
                          pronta: prontaParaEnviar(d.id),
                          selecionada: _selecionadas.contains(d.id),
                          aoSelecionar: (v) => setState(() => v ? _selecionadas.add(d.id) : _selecionadas.remove(d.id)),
                          aoAbrir: () => _abrirComanda(context, d.id, d.data()),
                        ),
                    ]),
              bottomNavigationBar: _selecionadas.isEmpty
                  ? null
                  : SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          if (_selecionadas.length >= 2)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _enviar(context, itens, valorDe, juntas: false),
                                child: const Text('Enviar separadas'),
                              ),
                            ),
                          if (_selecionadas.length >= 2) const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.send),
                              onPressed: () => _enviar(context, itens, valorDe, juntas: _selecionadas.length >= 2),
                              label: Text(_selecionadas.length >= 2 ? 'Enviar juntas (${_selecionadas.length})' : 'Enviar'),
                            ),
                          ),
                        ]),
                      ),
                    ),
            );
          },
        );
      },
    );
  }

  void _sugerir(BuildContext context, Ponto loja, Map<String, Map<String, dynamic>> itens, bool Function(String) pronta) {
    final destinos = <String, Ponto>{
      for (final e in itens.entries)
        if (pronta(e.key)) e.key: pontoDe(e.value['lat'], e.value['lng'])!,
    };
    final grupo = sugerirAgrupamentos(loja, destinos).firstWhere((g) => g.length > 1, orElse: () => const []);
    if (grupo.isEmpty) {
      avisar(context, 'As comandas prontas vão para direções diferentes. Envie separadas.');
      return;
    }
    setState(() {
      _selecionadas
        ..clear()
        ..addAll(grupo);
    });
  }

  Future<void> _enviar(
    BuildContext context,
    Map<String, Map<String, dynamic>> itens,
    int? Function(String) valorDe, {
    required bool juntas,
  }) async {
    final faltando = _selecionadas.where((id) {
      final c = itens[id]!;
      return c['lat'] == null || valorDe(id) == null;
    });
    if (faltando.isNotEmpty) {
      avisar(context, 'Abra as comandas marcadas e confira endereço e valor da entrega.');
      return;
    }
    final lista = [for (final id in _selecionadas) itemDeComanda(id, itens[id]!, valorDe(id)!)];
    final r = await executar(context, () => chamar('enviarPedidos', {'itens': lista, 'juntas': juntas}));
    if (r != null && context.mounted) {
      setState(_selecionadas.clear);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(juntas ? 'Enviado como lote. Buscando entregador…' : 'Enviado. Buscando entregador…')),
      );
    }
  }

  void _abrirComanda(BuildContext context, String? id, Map<String, dynamic>? dados) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EditarComanda(id: id, dados: dados)));
  }
}

class _CartaoComanda extends StatelessWidget {
  const _CartaoComanda({
    required this.id,
    required this.dados,
    required this.valor,
    required this.pronta,
    required this.selecionada,
    required this.aoSelecionar,
    required this.aoAbrir,
  });
  final String id;
  final Map<String, dynamic> dados;
  final int? valor;
  final bool pronta;
  final bool selecionada;
  final ValueChanged<bool> aoSelecionar;
  final VoidCallback aoAbrir;

  @override
  Widget build(BuildContext context) {
    final end = dados['endereco'] as Map? ?? {};
    final origem = dados['origem'] as String? ?? 'manual';
    final cobrar = (dados['pagamento'] as Map?)?['tipo'] == 'cobrar';
    final cor = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: aoAbrir,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
          child: Row(children: [
            Checkbox(value: selecionada, onChanged: (v) => aoSelecionar(v ?? false)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(
                    origem == 'ifood' ? Icons.delivery_dining : origem == 'comanda' ? Icons.print : Icons.edit_note,
                    size: 16,
                    color: cor.outline,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(dados['descricao'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text([end['texto'], end['bairro']].where((s) => s != null && '$s'.isNotEmpty).join(' - ')),
                const SizedBox(height: 4),
                Wrap(spacing: 8, children: [
                  if (cobrar) const Chip(label: Text('Cobrar na entrega'), visualDensity: VisualDensity.compact),
                  if (!pronta)
                    Chip(
                      label: const Text('Conferir'),
                      avatar: Icon(Icons.warning_amber, size: 16, color: cor.error),
                      visualDensity: VisualDensity.compact,
                    ),
                ]),
              ]),
            ),
            Text(valor == null ? 'R\$ ?' : formatarReais(valor!), style: Theme.of(context).textTheme.titleMedium),
          ]),
        ),
      ),
    );
  }
}

class _BarraImpressora extends StatelessWidget {
  const _BarraImpressora();
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: ImpressoraVirtual.instancia.estado,
      builder: (context, s) {
        final estado = s.data ?? 'parada';
        final texto = switch (estado) {
          'aguardando' => 'Impressora RodaJusta pronta para receber comandas',
          'conectada' => 'Recebendo comanda…',
          'parada' => 'Impressora desligada (Ajustes → Impressora)',
          _ => estado,
        };
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: estado == 'aguardando' || estado == 'conectada'
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(children: [
            const Icon(Icons.print, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        );
      },
    );
  }
}

/// Conferir/editar uma comanda, ou digitar um pedido novo.
class EditarComanda extends StatefulWidget {
  const EditarComanda({super.key, this.id, this.dados});
  final String? id;
  final Map<String, dynamic>? dados;
  @override
  State<EditarComanda> createState() => _EditarComandaState();
}

class _EditarComandaState extends State<EditarComanda> {
  late final Map<String, dynamic> d = widget.dados ?? {};
  late final Map end = d['endereco'] as Map? ?? {};
  late final _descricao = TextEditingController(text: d['descricao'] as String? ?? '');
  late final _cliente = TextEditingController(text: d['cliente'] as String? ?? '');
  late final _telefone = TextEditingController(text: d['telefone'] as String? ?? '');
  late final _endereco = TextEditingController(text: end['texto'] as String? ?? '');
  late final _bairro = TextEditingController(text: end['bairro'] as String? ?? '');
  late final _complemento = TextEditingController(text: end['complemento'] as String? ?? '');
  late final _referencia = TextEditingController(text: end['referencia'] as String? ?? '');
  late final _valor = TextEditingController(
    text: d['valorEntregaCentavos'] == null ? '' : formatarReais((d['valorEntregaCentavos'] as num).toInt()).replaceAll('R\$ ', ''),
  );
  late bool _cobrar = (d['pagamento'] as Map?)?['tipo'] == 'cobrar';
  late final _valorCobrar = TextEditingController(
    text: _centavosTexto((d['pagamento'] as Map?)?['valorCobrarCentavos'] ?? d['totalCentavos']),
  );
  late final _troco = TextEditingController(text: _centavosTexto((d['pagamento'] as Map?)?['trocoParaCentavos']));
  late Ponto? _ponto = pontoDe(d['lat'], d['lng']);
  String? _conferido;

  static String _centavosTexto(Object? v) =>
      v is num && v > 0 ? formatarReais(v.toInt()).replaceAll('R\$ ', '') : '';

  Future<void> _localizar() async {
    final p = await executar(context, () => geocodificar('${_endereco.text} - ${_bairro.text}'));
    if (!mounted) return;
    if (p == null) {
      avisar(context, 'Não achei esse endereço. Confira rua, número e bairro.');
      return;
    }
    final texto = await enderecoDe(p);
    setState(() {
      _ponto = p;
      _conferido = texto;
    });
  }

  Future<void> _salvar() async {
    if (_ponto == null) await _localizar();
    if (!mounted) return;
    final dados = <String, dynamic>{
      'origem': d['origem'] ?? 'manual',
      'status': 'pendente',
      'descricao': _descricao.text.trim().isEmpty ? '${_cliente.text} · ${_bairro.text}' : _descricao.text.trim(),
      'cliente': _cliente.text.trim(),
      'telefone': _telefone.text.trim(),
      'endereco': {
        'texto': _endereco.text.trim(),
        'bairro': _bairro.text.trim(),
        'complemento': _complemento.text.trim(),
        'referencia': _referencia.text.trim(),
      },
      'lat': _ponto?.lat,
      'lng': _ponto?.lng,
      'valorEntregaCentavos': lerReais(_valor.text),
      'pagamento': {
        'tipo': _cobrar ? 'cobrar' : 'pago',
        'valorCobrarCentavos': _cobrar ? (lerReais(_valorCobrar.text) ?? 0) : 0,
        'trocoParaCentavos': _cobrar ? (lerReais(_troco.text) ?? 0) : 0,
      },
      'confianca': 1.0,
      if (widget.id == null) 'criadoEm': FieldValue.serverTimestamp(),
    };
    final col = db.collection('lojistas/$uid/comandas');
    final ok = await executar(context, () async {
      if (widget.id == null) {
        await col.add(dados);
      } else {
        await col.doc(widget.id).set(dados, SetOptions(merge: true));
      }
      return true;
    });
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _descartar() async {
    await db.doc('lojistas/$uid/comandas/${widget.id}').update({'status': 'descartada'});
    if (mounted) Navigator.of(context).pop();
  }

  Widget _campo(TextEditingController c, String rotulo, {TextInputType? teclado, String? dica}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(controller: c, keyboardType: teclado, decoration: InputDecoration(labelText: rotulo, hintText: dica)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? 'Novo pedido' : 'Conferir comanda'),
        actions: [
          if (widget.id != null) IconButton(onPressed: _descartar, icon: const Icon(Icons.delete_outline), tooltip: 'Descartar'),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _campo(_descricao, 'Breve descrição', dica: '#482 · Maria · 2 pizzas'),
        _campo(_cliente, 'Cliente'),
        _campo(_telefone, 'Telefone do cliente', teclado: TextInputType.phone),
        _campo(_endereco, 'Endereço (rua e número)'),
        _campo(_bairro, 'Bairro'),
        _campo(_complemento, 'Complemento'),
        _campo(_referencia, 'Ponto de referência'),
        OutlinedButton.icon(onPressed: _localizar, icon: const Icon(Icons.place), label: const Text('Localizar no mapa')),
        if (_ponto != null)
          ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: Text(_conferido ?? 'Endereço localizado'),
            subtitle: const Text('Se não for aqui, corrija o endereço e localize de novo.'),
          ),
        const SizedBox(height: 12),
        _campo(_valor, 'Valor da entrega (R\$)', teclado: TextInputType.number, dica: 'Vazio = valor das configurações'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Entregador cobra do cliente'),
          value: _cobrar,
          onChanged: (v) => setState(() => _cobrar = v),
        ),
        if (_cobrar) ...[
          _campo(_valorCobrar, 'Valor a cobrar (R\$)', teclado: TextInputType.number),
          _campo(_troco, 'Troco para (R\$)', teclado: TextInputType.number),
        ],
        if (d['textoBruto'] != null)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Comanda original'),
            children: [SelectableText(d['textoBruto'] as String, style: const TextStyle(fontFamily: 'monospace'))],
          ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(padding: const EdgeInsets.all(16), child: FilledButton(onPressed: _salvar, child: const Text('Salvar'))),
      ),
    );
  }
}
