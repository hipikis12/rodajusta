import 'package:flutter/material.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import '../../servicos/impressora.dart';
import '../../widgets/comum.dart';

/// Ajustes de como o celular recebe as comandas do PDV.
class RecepcaoComandas extends StatefulWidget {
  const RecepcaoComandas({super.key, required this.config, required this.salvar});
  final Map<String, dynamic> config;
  final Future<void> Function(Map<String, dynamic>) salvar;

  @override
  State<RecepcaoComandas> createState() => _RecepcaoComandasState();
}

class _RecepcaoComandasState extends State<RecepcaoComandas> {
  final _imp = ImpressoraVirtual.instancia;
  String? _ip;
  bool _bateriaOk = true;
  String? _nomeBt;

  @override
  void initState() {
    super.initState();
    _atualizarInfo();
  }

  Future<void> _atualizarInfo() async {
    try {
      final ip = await _imp.ipLocal();
      final bat = await _imp.bateriaLiberada();
      final nome = await _imp.nomeBluetooth();
      if (mounted) {
        setState(() {
          _ip = ip;
          _bateriaOk = bat;
          _nomeBt = nome;
        });
      }
    } catch (_) {}
  }

  Future<void> _mudar(String chave, Object? valor) async {
    final novo = {...widget.config, chave: valor};
    await widget.salvar(novo);
    try {
      await _imp.aplicar(novo);
    } catch (e) {
      if (mounted) avisar(context, '$e'.replaceFirst('PlatformException', ''));
    }
    await _atualizarInfo();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.config;
    final ativo = c['impressoraAtiva'] == true;
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(
        title: const Text('Receber comandas do PDV'),
        subtitle: const Text('O celular vira uma impressora. Funciona com o app fechado e liga sozinho quando o celular reinicia.'),
        value: ativo,
        onChanged: (v) => _mudar('impressoraAtiva', v),
      ),
      StreamBuilder<String>(
        stream: _imp.estado,
        builder: (context, s) => ListTile(
          dense: true,
          leading: const Icon(Icons.info_outline),
          title: Text(switch (s.data) {
            null || 'parada' => 'Desligado',
            'aguardando' => 'Pronto, aguardando comandas',
            'conectada' => 'PDV conectado',
            final String m => m,
          }),
        ),
      ),
      if (ativo) ...[
        SwitchListTile(
          secondary: const Icon(Icons.bluetooth),
          title: const Text('Bluetooth (impressora pareada)'),
          subtitle: const Text('PDV no Windows pela porta COM do Bluetooth, ou apps Android que imprimem em impressora pareada.'),
          value: c['receberBluetooth'] != false,
          onChanged: (v) => _mudar('receberBluetooth', v),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.bluetooth_searching),
          title: const Text('Bluetooth BLE'),
          subtitle: const Text('Apps que procuram impressoras portáteis BLE.'),
          value: c['receberBle'] != false,
          onChanged: (v) => _mudar('receberBle', v),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.wifi),
          title: const Text('Wi-Fi / rede (porta 9100)'),
          subtitle: Text(_ip == null
              ? 'Conecte o celular no Wi-Fi da loja.'
              : 'No PDV, cadastre uma impressora de rede no IP $_ip, porta 9100.'),
          value: c['receberRede'] != false,
          onChanged: (v) => _mudar('receberRede', v),
        ),
        if (!_bateriaOk)
          ListTile(
            leading: Icon(Icons.battery_alert, color: Theme.of(context).colorScheme.error),
            title: const Text('Permitir funcionar sem restrição de bateria'),
            subtitle: const Text('Sem isso, alguns celulares desligam a recepção depois de um tempo parado.'),
            onTap: () async {
              await _imp.liberarBateria();
              await Future<void>.delayed(const Duration(seconds: 2));
              await _atualizarInfo();
            },
          ),
        ListTile(
          leading: const Icon(Icons.visibility),
          title: const Text('Deixar visível para parear'),
          subtitle: const Text('Use no primeiro pareamento com o computador ou celular do PDV.'),
          onTap: () => _imp.ficarVisivel(),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.badge_outlined),
          title: const Text('Nome de impressora no Bluetooth'),
          subtitle: Text('Alguns PDVs só mostram aparelhos com "Printer" no nome. Agora: ${_nomeBt ?? '—'}'),
          value: (_nomeBt ?? '').contains('Printer'),
          onChanged: (v) async {
            await _imp.renomearBluetooth(v ? 'RodaJusta Printer' : null);
            await _atualizarInfo();
          },
        ),
        ListTile(
          leading: const Icon(Icons.print_outlined),
          title: const Text('Repassar para a impressora da loja'),
          subtitle: Text(c['repassarPara'] == null ? 'Desligado: a comanda não sai no papel' : 'Imprimindo também em ${c['repassarPara']}'),
          onTap: () => _escolherRepasse(context),
        ),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: const Text('Como configurar no PDV'),
          onTap: () => _ajuda(context, t),
        ),
      ],
      ListTile(
        leading: const Icon(Icons.content_paste),
        title: const Text('Testar leitura / colar pedido'),
        subtitle: const Text('Cole o texto de uma comanda (ou de um pedido do WhatsApp) para ver o que o app entende.'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TestarLeitura())),
      ),
    ]);
  }

  Future<void> _escolherRepasse(BuildContext context) async {
    final lista = await _imp.pareadas();
    if (!context.mounted) return;
    final escolha = await showModalBottomSheet<String>(
      context: context,
      builder: (s) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Onde imprimir o papel?')),
          ListTile(title: const Text('Não repassar'), onTap: () => Navigator.pop(s, '')),
          for (final p in lista)
            ListTile(
              leading: const Icon(Icons.bluetooth),
              title: Text(p['nome'] ?? ''),
              subtitle: Text(p['endereco'] ?? ''),
              onTap: () => Navigator.pop(s, p['endereco']),
            ),
          ListTile(
            leading: const Icon(Icons.lan_outlined),
            title: const Text('Impressora de rede (IP)'),
            onTap: () async {
              final ip = TextEditingController();
              final ok = await showDialog<bool>(
                context: s,
                builder: (d) => AlertDialog(
                  title: const Text('IP da impressora'),
                  content: TextField(
                    controller: ip,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(hintText: '192.168.0.50 ou 192.168.0.50:9100'),
                  ),
                  actions: [FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('OK'))],
                ),
              );
              if (ok == true && s.mounted) Navigator.pop(s, ip.text.trim());
            },
          ),
        ]),
      ),
    );
    if (escolha == null) return;
    await _mudar('repassarPara', escolha.isEmpty ? null : escolha);
  }

  void _ajuda(BuildContext context, TextTheme t) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (s) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (_, controle) => ListView(controller: controle, padding: const EdgeInsets.all(20), children: [
          Text('Como ligar o PDV ao RodaJusta', style: t.titleLarge),
          const SizedBox(height: 16),
          Text('Windows por Bluetooth', style: t.titleMedium),
          const Text(
            '1. Toque em "Deixar visível para parear".\n'
            '2. No Windows: Configurações > Bluetooth > Adicionar dispositivo, escolha este celular.\n'
            '3. Em "Mais opções de Bluetooth" > Portas COM, veja a porta de saída criada para "RodaJusta Impressora".\n'
            '4. No PDV (ou em Impressoras do Windows, driver "Generic / Text Only" ou o driver ESC/POS da sua impressora), '
            'use essa porta COM.',
          ),
          const SizedBox(height: 16),
          Text('Windows ou outro computador pela rede', style: t.titleMedium),
          Text(
            '1. Celular e computador no mesmo Wi-Fi.\n'
            '2. Impressoras do Windows > Adicionar > "A impressora que eu quero não está na lista" > '
            'endereço TCP/IP: ${_ip ?? 'IP do celular'}, porta 9100 (RAW).\n'
            '3. Driver "Generic / Text Only" ou o ESC/POS da sua impressora.\n'
            'Dica: fixe o IP do celular no roteador para ele não mudar.',
          ),
          const SizedBox(height: 16),
          Text('App de pedidos no celular/tablet', style: t.titleMedium),
          const Text(
            'Pareie este celular pelo Bluetooth do outro aparelho e escolha "RodaJusta" (ou "RodaJusta Printer") '
            'como impressora no app. Apps que usam impressora BLE encontram o RodaJusta sem parear.',
          ),
          const SizedBox(height: 16),
          Text('O que o app entende', style: t.titleMedium),
          const Text(
            'Texto em qualquer layout (com ou sem rótulos), cupons impressos como imagem (lidos por OCR no próprio celular), '
            'várias vias de uma vez (a via da cozinha e as repetidas são descartadas) e pedidos de balcão/mesa (ignorados). '
            'Quando você corrige uma comanda, o app guarda o exemplo para melhorar a leitura daquele formato.',
          ),
        ]),
      ),
    );
  }
}

/// Cola um texto e mostra o que o leitor entendeu; pode criar a comanda.
class TestarLeitura extends StatefulWidget {
  const TestarLeitura({super.key});
  @override
  State<TestarLeitura> createState() => _TestarLeituraState();
}

class _TestarLeituraState extends State<TestarLeitura> {
  final _texto = TextEditingController();
  LeituraDeImpressao? _r;

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      appBar: AppBar(title: const Text('Testar leitura')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _texto,
          minLines: 8,
          maxLines: 20,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(hintText: 'Cole aqui o texto da comanda'),
          onChanged: (t) => setState(() => _r = t.trim().length < 10 ? null : lerTrabalho([t])),
        ),
        if (r != null) ...[
          const SizedBox(height: 16),
          for (final i in r.ignoradas) ListTile(leading: const Icon(Icons.block), title: Text(i)),
          for (final c in r.entregas)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.descricao, style: Theme.of(context).textTheme.titleMedium),
                  for (final (rotulo, valor) in [
                    ('Cliente', c.cliente),
                    ('Telefone', c.telefone),
                    ('Endereço', c.endereco),
                    ('Bairro', c.bairro),
                    ('Complemento', c.complemento),
                    ('Referência', c.referencia),
                    ('Cidade', [c.cidade, c.uf, c.cep].where((s) => s.isNotEmpty).join(' · ')),
                    ('Total', c.totalCentavos == null ? '' : formatarReais(c.totalCentavos!)),
                    ('Taxa de entrega', c.taxaEntregaCentavos == null ? '' : formatarReais(c.taxaEntregaCentavos!)),
                    (
                      'Pagamento',
                      c.cobrar
                          ? 'Cobrar ${formatarReais(c.valorCobrarCentavos ?? 0)} ${c.formaCobranca}'
                              '${c.trocoParaCentavos == null ? '' : ' · troco para ${formatarReais(c.trocoParaCentavos!)}'}'
                          : 'Já pago',
                    ),
                    ('Itens', c.itens.join(', ')),
                  ])
                    if (valor.isNotEmpty) LinhaValor(rotulo, valor),
                  LinhaValor('Confiança', '${(c.confianca * 100).round()}%'),
                ]),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Criar comanda com este texto'),
            onPressed: () async {
              final n = await executar(context, () => criarComandasDoTexto(_texto.text));
              if (n != null && context.mounted) {
                avisar(context, n == 1 ? 'Comanda criada na aba Enviar.' : '$n comandas criadas na aba Enviar.');
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ]),
    );
  }
}
