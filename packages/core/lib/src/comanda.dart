import 'dinheiro.dart';

/// O que a comanda é. Só "entrega" vira pedido para os entregadores.
enum TipoComanda { entrega, retirada, mesa, cozinha, desconhecido }

/// Dados que o app conseguiu tirar do texto da comanda. A loja confere e
/// corrige antes de enviar (ou o envio é automático se a confiança for alta).
class ComandaExtraida {
  ComandaExtraida({this.textoOriginal = ''});

  final String textoOriginal;
  TipoComanda tipo = TipoComanda.desconhecido;
  String numero = '';
  String cliente = '';
  String telefone = '';
  String localizador = '';
  String endereco = '';
  String bairro = '';
  String complemento = '';
  String referencia = '';
  String cidade = '';
  String uf = '';
  String cep = '';
  String observacao = '';
  String agendadoPara = '';
  int? totalCentavos;
  int? taxaEntregaCentavos;
  bool cobrar = false;
  int? valorCobrarCentavos;
  int? trocoParaCentavos;

  /// endereço veio do topo do cupom (pode ser o da própria loja)
  bool enderecoDoTopo = false;

  /// dinheiro, cartao, pix ou '' (para o entregador saber se leva maquininha)
  String formaCobranca = '';
  List<String> itens = [];

  bool get ehEntrega =>
      tipo == TipoComanda.entrega || (tipo == TipoComanda.desconhecido && endereco.isNotEmpty);

  /// Ex.: "#482 · Maria · 2x X-Burger +1 · R$ 54,00"
  String get descricao {
    final partes = <String>[
      if (numero.isNotEmpty) '#$numero',
      if (cliente.isNotEmpty) cliente.split(' ').first,
      if (itens.isNotEmpty) itens.first + (itens.length > 1 ? ' +${itens.length - 1}' : ''),
      if (totalCentavos != null) formatarReais(totalCentavos!),
      if (agendadoPara.isNotEmpty) 'agendado $agendadoPara',
    ];
    final d = partes.join(' · ');
    return d.length > 140 ? d.substring(0, 140) : d;
  }

  /// Texto para achar a coordenada no mapa.
  String get enderecoParaMapa => [
        endereco,
        bairro,
        [cidade, uf].where((s) => s.isNotEmpty).join(' - '),
        cep,
      ].where((s) => s.isNotEmpty).join(', ');

  /// 0 a 1: o quanto dá para confiar sem a loja conferir.
  double get confianca {
    var c = 0.0;
    if (endereco.isNotEmpty) c += 0.45;
    if (RegExp(r'\d|s/n', caseSensitive: false).hasMatch(endereco)) c += 0.15;
    if (bairro.isNotEmpty) c += 0.25;
    if (cliente.isNotEmpty || telefone.isNotEmpty) c += 0.1;
    if (totalCentavos != null) c += 0.05;
    if (tipo != TipoComanda.entrega) c -= 0.1;
    if (enderecoDoTopo && c > 0.5) c = 0.5;
    return c.clamp(0, 1).toDouble();
  }

  Map<String, Object?> paraMapa() => {
        'tipo': tipo.name,
        'numero': numero,
        'cliente': cliente,
        'telefone': telefone,
        'localizador': localizador,
        'endereco': endereco,
        'bairro': bairro,
        'complemento': complemento,
        'referencia': referencia,
        'cidade': cidade,
        'uf': uf,
        'cep': cep,
        'observacao': observacao,
        'agendadoPara': agendadoPara,
        'totalCentavos': totalCentavos,
        'taxaEntregaCentavos': taxaEntregaCentavos,
        'cobrar': cobrar,
        'valorCobrarCentavos': valorCobrarCentavos,
        'trocoParaCentavos': trocoParaCentavos,
        'formaCobranca': formaCobranca,
        'itens': itens,
        'descricao': descricao,
      };
}

// ---------------------------------------------------------------------------
// Normalização: minúsculas e sem acento, caractere por caractere, para que a
// posição no texto normalizado seja a mesma do texto original.

const _com = 'áàâãäåéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÅÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑºª°';
const _sem = 'aaaaaaeeeeiiiiooooouuuucnaaaaaaeeeeiiiiooooouuuucnooo';

String normalizar(String s) {
  final out = StringBuffer();
  for (final cu in s.codeUnits) {
    final ch = String.fromCharCode(cu);
    final k = _com.indexOf(ch);
    if (k >= 0) {
      out.write(_sem[k]);
    } else {
      final l = ch.toLowerCase();
      out.write(l.length == 1 ? l : ch);
    }
  }
  return out.toString();
}

// ---------------------------------------------------------------------------

class _Linha {
  _Linha(this.o) : n = normalizar(o);
  final String o; // original
  final String n; // normalizada
}

const _uf = r'(?:ac|al|ap|am|ba|ce|df|es|go|ma|mt|ms|mg|pa|pb|pr|pe|pi|rj|rn|rs|ro|rr|sc|sp|se|to)';
const _valor = r'(?:r\$|rs)?\s*(-?\d{1,3}(?:\.\d{3})+,\d{2}|-?\d+,\d{2}|-?\d+\.\d{2})(?![\d,])';
final _reValor = RegExp(_valor);
final _reCep = RegExp(r'\b(\d{5})-?(\d{3})\b');
final _reTelefone = RegExp(r'(?:\+?55\s?)?\(?\b(\d{2})\)?[\s.\-]?(9?\d{4})[\s.\-]?(\d{4})\b');
final _reLogradouro = RegExp(
  r'^(rua|r\.|av\.?|avenida|travessa|tv\.?|trav\.?|alameda|al\.|estrada|estr?\.|rodovia|rod\.|linha|lh\.?|gleba|'
  r'lote|travessao|chacara|sitio|fazenda|km|br[\s\-]?\d|ro[\s\-]?\d|praca|pca\.?|setor|quadra|qd\.?|conjunto|cj\.?|'
  r'condominio|cond\.?|residencial|loteamento|vila|viela|beco|largo|passagem|ladeira|servidao)\b(?! (cozinha|producao|cliente|entregador|loja|balcao))',
);
final _reRural = RegExp(r'^(linha|lh\.?|gleba|lote|travessao|chacara|sitio|fazenda|km|br[\s\-]?\d|ro[\s\-]?\d)\b');
final _reComplemento = RegExp(r'^(apto?\.?|apartamento|bloco|bl\.?|casa|fundos|sala|loja|andar|torre|kitnet|kit|quitinete|edificio|ed\.)\b');
final _reReferencia = RegExp(r'\b(proximo|perto|em frente|frente|ao lado|esquina|depois d|antes d|atras d|portao|muro)\b');
final _reNumeroSozinho = RegExp(r'^(?:n[o.]?\s*)?(\d{1,6}[a-z]?|s/?n)\b');

/// separadores entre rótulo e valor: "Cliente: X", "Cliente....: X",
/// "Cliente - X", "Cliente => X" ou colunas "Cliente      X"
const _sep = r'\s*(?:\.{2,}\s*)?(?:[:=>]+|\.{2,})\s*|\s+-+\s*|\s{2,}';
const _sepLivre = r'(?:' + _sep + r'|\s+)';

class _Rotulo {
  _Rotulo(this.campo, String nomes, {bool livre = false})
      : re = RegExp('^(?:$nomes)\\.?(?:${livre ? _sepLivre : _sep})');
  final String campo;
  final RegExp re;
}

final _rotulos = <_Rotulo>[
  _Rotulo('endereco', r'endereco de entrega|endereco da entrega|endereco do cliente|endereco|ender|end|entregar em|'
      r'local de entrega|local da entrega|logradouro|destino', livre: true),
  _Rotulo('rua', r'rua|avenida|av'),
  _Rotulo('numero', r'numero|num|nro|n\s?o|no|n'),
  _Rotulo('bairro', r'bairro|bairr|b', livre: false),
  _Rotulo('complemento', r'complemento|compl|comp', livre: true),
  _Rotulo('complemento', r'apartamento|apto|ap|bloco|casa'),
  _Rotulo('referencia', r'ponto de referencia|pto\.? de referencia|pto\.? ref|referencia|ref', livre: true),
  _Rotulo('cidade', r'cidade|municipio|cid', livre: true),
  _Rotulo('uf', r'uf|estado'),
  _Rotulo('cep', r'cep', livre: true),
  _Rotulo('cliente', r'nome do cliente|nome cliente|cliente|nome|destinatario|consumidor|comprador|para'),
  _Rotulo('telefone', r'telefone do cliente|telefone|tel\.? cliente|tel|fone|celular|cel|whatsapp|whats|zap|contato',
      livre: true),
  _Rotulo('localizador', r'codigo localizador|localizador|loc'),
  _Rotulo('pagamento', r'forma de pagamento|formas de pagamento|forma pgto|forma pagto|meio de pagamento|pagamento|'
      r'pagto|pgto|pag|pagar com'),
  _Rotulo('observacao', r'observacoes do pedido|observacao do pedido|observacoes|observacao|obs\.? do pedido|obs'),
];

final _reCabecalhoEndereco =
    RegExp(r'^(dados (de|da|para) entrega|endereco (de|da|para) entrega|entrega|delivery|endereco|local de entrega|entregar em)\s*:?$');
final _reCabecalhoCliente = RegExp(r'^(dados do cliente|cliente|consumidor|destinatario)\s*:?$');
final _reCabecalhoItens =
    RegExp(r'^(itens|itens do pedido|produtos|pedido|descricao|item)\s*:?$|\bqt[dy]e?\b.*\b(desc|produto|item)|\b(desc|produto|item).*\bqt[dy]e?\b');
final _reFimItens = RegExp(
  r'^(sub\s*-?\s*total|subtotal|total|taxa|tx\.?|frete|desconto|acrescimo|pagamento|forma de pagamento|pgto|troco|obs|'
  r'observac|entrega|cliente|endereco|valor|dinheiro|cartao|credito|debito|pix|vale|voucher|cupom)',
);
final _reSubitem = RegExp(r'^\s*([+\->*•~]|\(\+\)|obs\b|adicional|adic\.|sabor|borda|1/2|meia|sem |com |retirar |tirar )');

/// Lê o texto de uma comanda impressa por qualquer PDV.
ComandaExtraida extrairComanda(String texto) {
  final c = ComandaExtraida(textoOriginal: texto);
  final linhas = <_Linha>[];
  for (var l in texto.split(RegExp(r'\r?\n|\r'))) {
    l = l.replaceAll(RegExp(r'^[\s|*]+|[\s|*]+$'), '').replaceAll(RegExp(r'\s+$'), '');
    if (l.isEmpty || RegExp(r'^[\-=_~.+#*\s<>]*$').hasMatch(l)) continue;
    linhas.add(_Linha(l));
  }
  if (linhas.isEmpty) return c;
  final largura = linhas.map((l) => l.o.length).reduce((a, b) => a > b ? a : b);

  String secao = '';
  var naListaDeItens = false;
  final enderecoSemRotulo = <String>[];
  int? totalGenerico;
  int? totalForte;
  String linhaPagamento = '';
  var trocoValor = 0;
  // linhas já usadas como valor de um rótulo (não processar de novo)
  final consumidas = <int>{};
  // antes do pedido começar vem o cabeçalho da loja (nome, endereço e
  // telefone da própria loja): nada dali vira dado do cliente
  var noCabecalho = true;
  final doCabecalho = <(String, String)>[];
  const camposDeLugar = {'endereco', 'rua', 'numero', 'bairro', 'complemento', 'referencia', 'cidade', 'uf', 'cep', 'telefone'};

  bool ehRotulo(String n) => _rotulos.any((r) => r.re.hasMatch(n));
  bool ehCabecalho(String n) =>
      _reCabecalhoEndereco.hasMatch(n) || _reCabecalhoCliente.hasMatch(n) || _reCabecalhoItens.hasMatch(n);

  // valor de um rótulo: o resto da linha, ou a linha seguinte se vazio;
  // textos longos quebrados na largura do papel continuam na linha de baixo
  String valorDe(int i, int fimRotulo, {bool continua = false}) {
    var v = _limpo(linhas[i].o.substring(fimRotulo));
    var j = i;
    bool livre(int k) =>
        k < linhas.length && !ehRotulo(linhas[k].n) && !ehCabecalho(linhas[k].n) && !_reValor.hasMatch(linhas[k].n);
    if (v.isEmpty && livre(i + 1)) {
      v = _limpo(linhas[i + 1].o);
      j = i + 1;
      consumidas.add(j);
    }
    if (continua && largura >= 30) {
      // linha que encheu a largura do papel continua na de baixo
      while (linhas[j].o.length >= largura - 8 && livre(j + 1) && !_reLogradouro.hasMatch(linhas[j + 1].n)) {
        final cortada = linhas[j].o.length >= largura - 1;
        j++;
        consumidas.add(j);
        final prox = _limpo(linhas[j].o);
        // palavra cortada no meio ("Kub" + "itschek") emenda sem espaço
        final colar = cortada && RegExp(r'[a-zà-ú]$').hasMatch(v) && RegExp(r'^[a-zà-ú]').hasMatch(prox);
        v = colar ? '$v$prox' : '$v $prox';
      }
    }
    return v;
  }

  int? valorNaLinhaOuProxima(int i) {
    final m = _reValor.allMatches(linhas[i].n).lastOrNull;
    if (m != null) return lerReais(m.group(1)!);
    if (i + 1 < linhas.length) {
      final p = linhas[i + 1].n;
      final mp = RegExp('^$_valor\\s*\$').firstMatch(p.trim());
      if (mp != null) return lerReais(mp.group(1)!);
    }
    return null;
  }

  for (var i = 0; i < linhas.length; i++) {
    if (consumidas.contains(i)) continue;
    final l = linhas[i];
    final n = l.n;
    final temValor = _reValor.hasMatch(n);

    // ------------------------------------------------ número do pedido
    if (c.numero.isEmpty && !temValor && !n.startsWith('total')) {
      final m = RegExp(
        r'(?:pedido|ped\.?|comanda|senha|ticket|venda|delivery|order|codigo do pedido|cod\.? pedido|n\.?o do pedido|numero do pedido)'
        r'\s*(?:n[o.]*|numero|num\.?)?\s*[:#.\-]?\s*#?\s*(\d{1,10})\b(?![/:])',
      ).firstMatch(n);
      final h = RegExp(r'(?:^|\s)#\s?(\d{2,10})\b').firstMatch(n);
      if (m != null && !n.contains('mesa')) {
        c.numero = m.group(1)!;
      } else if (h != null) {
        c.numero = h.group(1)!;
      }
      if (c.numero.isNotEmpty) {
        noCabecalho = false;
        if (!_reCabecalhoEndereco.hasMatch(n)) continue; // linha do número já foi usada
      }
    }

    // ------------------------------------------------ cabeçalhos de seção
    if (ehCabecalho(n) || RegExp(r'^(nome do cliente|cliente|destinatario|consumidor|para)\b').hasMatch(n)) {
      noCabecalho = false;
    }
    if (_reCabecalhoEndereco.hasMatch(n)) {
      secao = 'endereco';
      naListaDeItens = false;
      continue;
    }
    if (_reCabecalhoCliente.hasMatch(n)) {
      secao = 'cliente';
      naListaDeItens = false;
      continue;
    }
    if (_reCabecalhoItens.hasMatch(n)) {
      naListaDeItens = true;
      secao = 'itens';
      continue;
    }

    // ------------------------------------------------ valores (antes dos rótulos)
    if (RegExp(r'^(valor a cobrar|cobrar do cliente|cobrar na entrega|a cobrar|cobrar|valor a receber|a receber|receber do cliente|'
            r'receber|falta pagar|restante|saldo a pagar|total a cobrar|total a receber|total a pagar na entrega)\b')
        .hasMatch(n)) {
      final v = valorNaLinhaOuProxima(i);
      if (v != null) {
        c.valorCobrarCentavos = v;
        c.cobrar = v > 0;
      } else {
        linhaPagamento += ' $n';
      }
      naListaDeItens = false;
      continue;
    }
    if (RegExp(r'^(sub\s*-?\s*total|subtotal|total (de |dos )?(itens|produtos|pecas)|qtd|quantidade)').hasMatch(n)) {
      naListaDeItens = false;
      continue;
    }
    if (RegExp(r'^(total a pagar|total geral|total do pedido|valor total|total liquido|total final|total pedido|vlr\.? total)\b')
        .hasMatch(n)) {
      totalForte = valorNaLinhaOuProxima(i) ?? totalForte;
      naListaDeItens = false;
      continue;
    }
    if (RegExp(r'^total\b').hasMatch(n)) {
      totalGenerico = valorNaLinhaOuProxima(i) ?? totalGenerico;
      naListaDeItens = false;
      if (n.contains('pago')) linhaPagamento += ' pago';
      continue;
    }
    if (RegExp(r'^(taxa de entrega|taxa da entrega|tx\.? de entrega|tx\.? entrega|taxa entrega|frete|valor da entrega|'
            r'entrega|delivery|tele ?entrega)\b')
        .hasMatch(n) &&
        temValor) {
      c.taxaEntregaCentavos = valorNaLinhaOuProxima(i);
      naListaDeItens = false;
      continue;
    }

    // ------------------------------------------------ troco
    if (n.contains('troco')) {
      linhaPagamento += ' $n';
      if (RegExp(r'sem troco|troco\s*:?\s*(nao|n/a|-)|nao (precisa|necessita) (de )?troco').hasMatch(n)) {
        // sem troco
      } else {
        final para = RegExp(r'troco\s*(?:para|pra|p/|p\.|p)\s*:?\s*' + _valor).firstMatch(n);
        final de = RegExp(r'troco\s*(?:de)?\s*:?\s*' + _valor).firstMatch(n);
        if (para != null) {
          c.trocoParaCentavos = lerReais(para.group(1)!);
        } else if (de != null) {
          trocoValor = lerReais(de.group(1)!) ?? 0;
        }
      }
      continue;
    }

    // ------------------------------------------------ campos com rótulo
    _Rotulo? rotulo;
    RegExpMatch? m;
    for (final r in _rotulos) {
      m = r.re.firstMatch(n);
      if (m != null) {
        rotulo = r;
        break;
      }
    }
    if (rotulo != null && m != null) {
      naListaDeItens = false;
      final continua = const {'endereco', 'rua', 'referencia', 'complemento', 'observacao'}.contains(rotulo.campo);
      final v = valorDe(i, m.end, continua: continua);
      if (noCabecalho && camposDeLugar.contains(rotulo.campo)) {
        doCabecalho.add((rotulo.campo, v)); // pode ser a própria loja
        continue;
      }
      noCabecalho = false;
      _aplicarCampo(c, rotulo.campo, v, n);
      if (const {'endereco', 'rua'}.contains(rotulo.campo)) secao = 'endereco';
      if (rotulo.campo == 'cliente' && secao != 'endereco') secao = 'cliente';
      if (rotulo.campo == 'pagamento') linhaPagamento += ' ${normalizar(v)}';
      continue;
    }

    // ------------------------------------------------ pagamento sem rótulo
    final ehPagamento =
        RegExp(r'^(pago|online|dinheiro|especie|cartao|credito|debito|pix|maquin|vale|voucher|cobrar|receber|na entrega)\b').hasMatch(n) ||
            RegExp(r'\b(pago online|pagamento online|nao cobrar|ja pago|levar maquin)').hasMatch(n);
    if (ehPagamento) {
      linhaPagamento += ' $n';
      naListaDeItens = false;
      continue;
    }

    // ------------------------------------------------ itens
    final item = _item(l, naListaDeItens);
    if (item != null) {
      c.itens.add(item);
      noCabecalho = false;
      continue;
    }
    if (naListaDeItens) continue; // sub-itens, observações do item
    if (noCabecalho) {
      // nome, endereço e telefone da própria loja (guardados por garantia)
      if (_reLogradouro.hasMatch(n)) doCabecalho.add(('endereco', l.o));
      final f = _reTelefone.firstMatch(n);
      if (f != null) doCabecalho.add(('telefone', l.o));
      continue;
    }

    // ------------------------------------------------ linhas sem rótulo
    _localizador(c, n);
    final fone = _reTelefone.firstMatch(n);
    final soTelefone = fone != null &&
        RegExp(r'^(tel|telefone|fone|cel|celular|whats|whatsapp|zap|contato)*$')
            .hasMatch(n.replaceAll(_reTelefone, '').replaceAll(RegExp(r'[^a-z]'), ''));
    if (soTelefone) {
      if (c.telefone.isEmpty) c.telefone = '${fone.group(1)}${fone.group(2)}${fone.group(3)}';
      continue;
    }
    if (_reLogradouro.hasMatch(n) && c.endereco.isEmpty) {
      _aplicarEndereco(c, valorDe(i, 0, continua: true));
      secao = 'endereco';
      continue;
    }
    if (secao == 'endereco' && !temValor) {
      enderecoSemRotulo.add(l.o);
      continue;
    }
    if (secao == 'cliente' && c.cliente.isEmpty && !temValor && RegExp(r'^[a-z][a-z .]{2,}$').hasMatch(n)) {
      c.cliente = _limpo(l.o);
      continue;
    }
    if (n.contains(' - ') && _reCep.hasMatch(n) && c.endereco.isEmpty) {
      _aplicarEndereco(c, l.o);
    }
  }

  // linhas soltas na seção de endereço
  for (final o in enderecoSemRotulo) {
    final n = normalizar(o);
    if (c.endereco.isEmpty) {
      _aplicarEndereco(c, o);
    } else if (_reCep.hasMatch(n) && c.cep.isEmpty) {
      final cep = _reCep.firstMatch(n)!;
      c.cep = '${cep.group(1)}-${cep.group(2)}';
      final resto = _limpo(o.replaceAll(_reCep, '').replaceAll(RegExp(r'cep\s*:?', caseSensitive: false), ''));
      if (resto.isNotEmpty) _aplicarCidade(c, resto);
    } else if (RegExp('[\\-/,]\\s*$_uf\\s*\$').hasMatch(n) && c.cidade.isEmpty) {
      _aplicarCidade(c, o);
    } else if (_reNumeroSozinho.hasMatch(n) && !RegExp(r'\d|s/n').hasMatch(normalizar(c.endereco))) {
      c.endereco = '${c.endereco}, ${_limpo(o).replaceAll(RegExp(r'^n[º°o.]?\s*', caseSensitive: false), '')}';
    } else if (_reComplemento.hasMatch(n)) {
      c.complemento = c.complemento.isEmpty ? _limpo(o) : '${c.complemento}, ${_limpo(o)}';
    } else if (_reReferencia.hasMatch(n)) {
      c.referencia = c.referencia.isEmpty ? _limpo(o) : '${c.referencia}; ${_limpo(o)}';
    } else if (c.bairro.isEmpty) {
      c.bairro = _semCidade(c, _limpo(o).replaceFirst(RegExp(r'^bairro\s*:?\s*', caseSensitive: false), ''));
    } else if (c.complemento.isEmpty) {
      c.complemento = _limpo(o);
    }
  }

  // sem endereço no corpo: usa o do topo, mas sem confiar (pode ser da loja)
  if (c.endereco.isEmpty && doCabecalho.any((x) => x.$1 == 'endereco' || x.$1 == 'rua')) {
    for (final (campo, v) in doCabecalho) {
      if (v.isNotEmpty) _aplicarCampo(c, campo, v, normalizar(campo));
    }
    c.enderecoDoTopo = true;
  }

  // ------------------------------------------------ totais e pagamento
  c.totalCentavos = totalForte ?? totalGenerico;
  _pagamento(c, linhaPagamento, texto, trocoValor);
  _agendamento(c, normalizar(texto));
  c.tipo = _tipo(c, normalizar(texto));
  return c;
}

/// Aplica o valor de um campo com rótulo.
void _aplicarCampo(ComandaExtraida c, String campo, String v, String n) {
  if (v.isEmpty && campo != 'pagamento') return;
  switch (campo) {
    case 'endereco' || 'rua':
      if (c.endereco.isNotEmpty) {
        // um segundo endereço com rótulo: vale o último (o 1º costuma ser da loja)
        c
          ..endereco = ''
          ..bairro = ''
          ..complemento = ''
          ..referencia = ''
          ..cidade = ''
          ..uf = ''
          ..cep = '';
      }
      final rua = campo == 'rua' && !_reLogradouro.hasMatch(normalizar(v)) ? '${n.startsWith('av') ? 'Av.' : 'Rua'} $v' : v;
      _aplicarEndereco(c, rua);
    case 'numero':
      if (_reNumeroSozinho.hasMatch(normalizar(v)) && c.endereco.isNotEmpty && !RegExp(r'\d|s/n').hasMatch(normalizar(c.endereco))) {
        c.endereco = '${c.endereco}, ${v.split(RegExp(r'\s')).first}';
      }
    case 'bairro':
      c.bairro = _semCidade(c, v);
    case 'complemento':
      final prefixo = RegExp(r'^(apartamento|apto|ap|bloco|casa)\b').firstMatch(n)?.group(0);
      final valor = prefixo != null ? '${_capitular(prefixo)} $v' : v;
      c.complemento = c.complemento.isEmpty ? valor : '${c.complemento}, $valor';
    case 'referencia':
      c.referencia = c.referencia.isEmpty ? v : '${c.referencia}; $v';
    case 'cidade':
      _aplicarCidade(c, v);
    case 'uf':
      final u = RegExp('\\b$_uf\\b').firstMatch(normalizar(v));
      if (u != null) c.uf = u.group(0)!.toUpperCase();
    case 'cep':
      final cep = _reCep.firstMatch(v);
      if (cep != null) c.cep = '${cep.group(1)}-${cep.group(2)}';
    case 'cliente':
      if (c.cliente.isEmpty) {
        final semFone =
            v.replaceAll(_reTelefone, '').replaceAll(RegExp(r'\s*(tel|fone|cel)\.?\s*:?\s*$', caseSensitive: false), '');
        c.cliente = _limpo(semFone);
        final f = _reTelefone.firstMatch(v);
        if (f != null && c.telefone.isEmpty) c.telefone = '${f.group(1)}${f.group(2)}${f.group(3)}';
      }
    case 'telefone':
      final f = _reTelefone.firstMatch(v);
      if (f != null && c.telefone.isEmpty) c.telefone = '${f.group(1)}${f.group(2)}${f.group(3)}';
      _localizador(c, v);
    case 'localizador':
      _localizador(c, 'localizador $v');
    case 'observacao':
      c.observacao = c.observacao.isEmpty ? v : '${c.observacao}; $v';
      if (_reReferencia.hasMatch(normalizar(v)) && c.referencia.isEmpty) c.referencia = v;
  }
}

String _limpo(String s) => s
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .replaceAll(RegExp(r'^[:\-=>.\s]+'), '')
    .replaceAll(RegExp(r'[\s|,;]+$'), '');

String _capitular(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

/// "Rua X, 123 - Setor 03, Ariquemes - RO, 76870-000" e variações.
void _aplicarEndereco(ComandaExtraida c, String texto) {
  var t = _limpo(texto);
  final n0 = normalizar(t);

  final cep = _reCep.firstMatch(t);
  if (cep != null) {
    c.cep = '${cep.group(1)}-${cep.group(2)}';
    t = t.replaceRange(cep.start, cep.end, '').replaceAll(RegExp(r'\bcep\s*:?\s*', caseSensitive: false), '');
  }
  // "bairro X" ou "B. X" no meio da linha
  final b = RegExp(r'[,\-\s]+(bairro|b\.)\s*:?\s*', caseSensitive: false).firstMatch(t);
  if (b != null) {
    final resto = t.substring(b.end);
    final fim = RegExp(r'\s*(,|\s-\s)').firstMatch(resto);
    c.bairro = _limpo(fim == null ? resto : resto.substring(0, fim.start));
    t = t.substring(0, b.start) + (fim == null ? '' : resto.substring(fim.start));
  }
  // cidade - UF no fim
  final uf = RegExp('[,\\-/]\\s*($_uf)\\s*[,.]?\\s*\$', caseSensitive: false).firstMatch(t);
  if (uf != null) {
    c.uf = uf.group(1)!.toUpperCase();
    t = t.substring(0, uf.start);
  }

  if (_reRural.hasMatch(n0)) {
    // zona rural: Linha C-75, Lote 12... fica tudo como endereço
    c.endereco = _limpo(t);
    return;
  }

  final partes = t.split(RegExp(r'\s*,\s*|\s+-\s+|\s*;\s*')).map(_limpo).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return;
  if (uf != null && partes.length >= 2 && !RegExp(r'\d').hasMatch(partes.last)) {
    c.cidade = partes.removeLast();
  }
  var rua = partes.removeAt(0);
  // número no fim da rua: "Rua X 123", "Rua X nº 123"
  final numFim = RegExp(r'^(.*?)[\s,]+(?:n[º°o.]?\s*)?(\d{1,6}[a-zA-Z]?|s/?n)$', caseSensitive: false).firstMatch(rua);
  if (numFim != null && RegExp(r'[a-zA-Z]').hasMatch(numFim.group(1)!)) {
    rua = '${numFim.group(1)}, ${numFim.group(2)}';
  } else if (partes.isNotEmpty && _reNumeroSozinho.hasMatch(normalizar(partes.first))) {
    rua = '$rua, ${partes.removeAt(0).replaceAll(RegExp(r'^n[º°o.]?\s*', caseSensitive: false), '')}';
  }
  c.endereco = rua;
  for (final p in partes) {
    final np = normalizar(p);
    if (_reComplemento.hasMatch(np)) {
      c.complemento = c.complemento.isEmpty ? p : '${c.complemento}, $p';
    } else if (_reReferencia.hasMatch(np)) {
      c.referencia = c.referencia.isEmpty ? p : '${c.referencia}; $p';
    } else if (c.bairro.isEmpty) {
      c.bairro = p;
    } else if (c.cidade.isEmpty && uf != null) {
      c.cidade = p;
    } else {
      c.complemento = c.complemento.isEmpty ? p : '${c.complemento}, $p';
    }
  }
}

void _aplicarCidade(ComandaExtraida c, String v) {
  final m = RegExp('^(.*?)\\s*(?:[,\\-/]|\\s)\\s*($_uf)\\s*\$', caseSensitive: false).firstMatch(_limpo(v));
  if (m != null) {
    c.cidade = _limpo(m.group(1)!);
    c.uf = m.group(2)!.toUpperCase();
  } else {
    c.cidade = _limpo(v);
  }
}

/// "Setor 03 - Ariquemes/RO" no campo bairro: separa a cidade.
String _semCidade(ComandaExtraida c, String v) {
  final m = RegExp('^(.*?)\\s*[,\\-]\\s*([^,\\-]+?)\\s*[/\\-]\\s*($_uf)\\s*\$', caseSensitive: false).firstMatch(v);
  if (m == null) return _limpo(v);
  c.cidade = _limpo(m.group(2)!);
  c.uf = m.group(3)!.toUpperCase();
  return _limpo(m.group(1)!);
}

void _localizador(ComandaExtraida c, String n) {
  if (c.localizador.isNotEmpty) return;
  final m = RegExp(r'(?:localizador|loc\.?|id)\s*:?\s*(\d{4})\s?(\d{4})\b', caseSensitive: false).firstMatch(n);
  if (m != null) c.localizador = '${m.group(1)} ${m.group(2)}';
}

String? _item(_Linha l, bool naLista) {
  final n = l.n;
  if (_reSubitem.hasMatch(n)) return null;
  if (_reFimItens.hasMatch(n) || _reLogradouro.hasMatch(n)) return null;
  String? nome;
  String qtd = '1';
  final pref = RegExp(naLista
          ? r'^\(?(\d{1,3})\)?\s*(?:x|un\.?|und\.?|unid\.?|-)?\s*(?=[a-z])'
          : r'^\(?(\d{1,3})\)?\s*(?:x|un\.?|und\.?|unid\.?)\s*(?=[a-z0-9])')
      .firstMatch(n);
  final fiscal = RegExp(r'^\d{1,4}\s+(?:\d{6,14}\s+)?(.+?)\s+(\d+(?:[.,]\d{1,3})?)\s*(?:un|und|kg|pc|x)\b').firstMatch(n);
  final qtdNome = RegExp(r'^(\d{1,3})\s+([a-z].*)$').firstMatch(n);
  final nomeQtd = RegExp(r'^([a-z].*?)\s+(\d{1,3})\s*(?:x|un)?\s+' + _valor).firstMatch(n);
  if (fiscal != null && naLista) {
    qtd = fiscal.group(2)!.replaceAll(RegExp(r'[.,]0+$'), '');
    final ini = n.indexOf(fiscal.group(1)!);
    nome = l.o.substring(ini, ini + fiscal.group(1)!.length);
  } else if (pref != null) {
    qtd = pref.group(1)!;
    nome = l.o.substring(pref.end);
  } else if (qtdNome != null && (naLista || _reValor.hasMatch(n))) {
    qtd = qtdNome.group(1)!;
    nome = l.o.substring(qtdNome.group(1)!.length);
  } else if (nomeQtd != null && naLista) {
    qtd = nomeQtd.group(2)!;
    nome = l.o.substring(0, nomeQtd.group(1)!.length);
  } else if (naLista && RegExp(r'^[a-z]').hasMatch(n) && _reValor.hasMatch(n)) {
    nome = l.o;
  }
  if (nome == null) return null;
  qtd = int.tryParse(qtd)?.toString() ?? qtd;
  // tira preços e colunas do fim
  nome = nome.replaceAll(RegExp(r'(\s+(?:r\$\s*)?-?\d+[.,]\d{2,3}){1,4}\s*$', caseSensitive: false), '');
  nome = _limpo(nome.replaceAll(RegExp(r'\s+(?:un|und|x)\s*$', caseSensitive: false), ''));
  if (nome.length < 2) return null;
  if (nome == nome.toUpperCase() && RegExp(r'[A-Z]').hasMatch(nome)) {
    const minusculas = {'de', 'da', 'do', 'das', 'dos', 'e', 'com', 'sem', 'c/', 's/'};
    nome = nome.split(' ').map((p) {
      if (p.length <= 1 || RegExp(r'\d').hasMatch(p)) return p;
      return minusculas.contains(p.toLowerCase()) ? p.toLowerCase() : _capitular(p);
    }).join(' ');
  }
  return '${qtd}x $nome';
}

void _pagamento(ComandaExtraida c, String linha, String texto, int trocoValor) {
  final p = normalizar(linha);
  final tudo = normalizar(texto);
  final pagoForte = RegExp(
        r'\bpago\b|pagamento online|pago online|pago (no|pelo|via) (app|site|ifood|aplicativo|cardapio|link)|ja pago|'
        r'pedido pago|nao cobrar|nada a cobrar|pagamento realizado|pagamento aprovado|pago via pix|pix pago|pago com pix|'
        r'pagamento antecipado',
      ).hasMatch(tudo) ||
      RegExp(r'\bonline\b').hasMatch(p);
  final dinheiro = RegExp(r'dinheiro|especie|troco').hasMatch(p) || c.trocoParaCentavos != null || trocoValor > 0;
  final cartao = RegExp(r'cartao|credito|debito|maquin|maquina|\bpos\b|vale refeicao|vale alimentacao|\bvr\b|\bva\b|ticket|sodexo|alelo')
      .hasMatch(p);
  final pix = RegExp(r'\bpix\b').hasMatch(p);
  final semNegacao = p.replaceAll(RegExp(r'nao cobrar|nada a cobrar|nao receber'), '');
  final naEntrega =
      RegExp(r'na entrega|no ato|receber|cobrar|levar maquin|levar maquina|pagar ao entregador|pagar na').hasMatch(semNegacao);

  if (c.valorCobrarCentavos != null) {
    // o PDV disse o valor exato a cobrar
  } else if (pagoForte && !dinheiro && !naEntrega) {
    c.cobrar = false;
  } else if (dinheiro || naEntrega || (cartao && !pagoForte)) {
    c.cobrar = true;
  } else if (pix && !pagoForte) {
    c.cobrar = naEntrega;
  }
  if (c.cobrar) {
    c.valorCobrarCentavos ??= c.totalCentavos;
    c.formaCobranca = dinheiro ? 'dinheiro' : cartao ? 'cartao' : pix ? 'pix' : '';
    if (trocoValor > 0 && c.trocoParaCentavos == null && c.valorCobrarCentavos != null) {
      c.trocoParaCentavos = c.valorCobrarCentavos! + trocoValor;
    }
  } else {
    c.trocoParaCentavos = null;
  }
}

void _agendamento(ComandaExtraida c, String n) {
  final m = RegExp(
    r'(?:agendad[oa]|agendamento|entregar (?:as|a partir das|ate as)|horario de entrega|previsao de entrega|entrega prevista)'
    r'\s*(?:para)?\s*:?\s*(?:o dia\s*)?((?:\d{1,2}/\d{1,2}(?:/\d{2,4})?\s*(?:as|-)?\s*)?\d{1,2}(?::|h)\d{2})',
  ).firstMatch(n);
  if (m != null) c.agendadoPara = m.group(1)!.replaceAll(RegExp(r'\s+'), ' ').replaceAll(' as ', ' ');
}

TipoComanda _tipo(ComandaExtraida c, String n) {
  // endereço no corpo do cupom manda; o do topo pode ser o da loja
  if (c.endereco.isNotEmpty && !c.enderecoDoTopo) return TipoComanda.entrega;
  if (RegExp(r'\b(retirada|retirar no local|retira no local|cliente retira|cliente vai buscar|para viagem|balcao|take ?out|'
          r'buscar no local|retirar na loja|retira na loja)\b')
      .hasMatch(n)) {
    return TipoComanda.retirada;
  }
  if (RegExp(r'\bmesa\s*:?\s*n?[o.]?\s*\d+|consumo no local|consumir no local|\bsalao\b').hasMatch(n)) return TipoComanda.mesa;
  if (RegExp(r'via (da |de )?(cozinha|producao)|\bcozinha\b|\bproducao\b|\bpreparo\b|\bchapa\b').hasMatch(n)) {
    return TipoComanda.cozinha;
  }
  if (c.endereco.isNotEmpty) return TipoComanda.entrega;
  if (RegExp(r'\b(delivery|tele ?entrega|motoboy|para entrega|entregar)\b').hasMatch(n)) return TipoComanda.entrega;
  return TipoComanda.desconhecido;
}

// ---------------------------------------------------------------------------

/// Resultado de um trabalho de impressão inteiro.
class LeituraDeImpressao {
  final entregas = <ComandaExtraida>[];

  /// motivo de cada comanda descartada (balcão, cozinha, via repetida...)
  final ignoradas = <String>[];
}

/// Separa um texto com várias comandas coladas (sem corte entre elas):
/// um novo número de pedido depois de um total começa outra comanda.
List<String> separarComandasColadas(String texto) {
  final linhas = texto.split('\n');
  final blocos = <List<String>>[[]];
  var viuTotal = false;
  final reNumero = RegExp(r'^\s*(?:\*+\s*)?(?:pedido|comanda|senha|ticket|delivery|order)\b.*\d|^\s*#\s?\d{2,}');
  for (final l in linhas) {
    final n = normalizar(l);
    if (viuTotal && reNumero.hasMatch(n) && blocos.last.isNotEmpty) {
      blocos.add([]);
      viuTotal = false;
    }
    if (RegExp(r'^\s*total\b').hasMatch(n)) viuTotal = true;
    blocos.last.add(l);
  }
  return blocos.map((b) => b.join('\n')).where((t) => t.trim().isNotEmpty).toList();
}

/// Lê todas as comandas de um trabalho de impressão: separa as coladas,
/// descarta vias repetidas, vias de cozinha, balcão e mesa.
LeituraDeImpressao lerTrabalho(List<String> textosDosSegmentos) {
  final r = LeituraDeImpressao();
  final todas = <ComandaExtraida>[];
  for (final t in textosDosSegmentos) {
    for (final bloco in separarComandasColadas(t)) {
      if (bloco.trim().length < 15) continue;
      todas.add(extrairComanda(bloco));
    }
  }
  final vistas = <String>{};
  for (final c in todas) {
    final chave = normalizar(c.textoOriginal).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (!vistas.add(chave)) {
      r.ignoradas.add('Via repetida${c.numero.isEmpty ? '' : ' do pedido #${c.numero}'}');
      continue;
    }
    if (!c.ehEntrega) {
      // via de cozinha do mesmo pedido de uma via com endereço
      final irma = c.numero.isNotEmpty && todas.any((o) => o != c && o.numero == c.numero && o.ehEntrega);
      r.ignoradas.add(switch (c.tipo) {
        _ when irma => 'Via de cozinha do pedido #${c.numero}',
        TipoComanda.retirada => 'Pedido para retirada${c.numero.isEmpty ? '' : ' #${c.numero}'}',
        TipoComanda.mesa => 'Pedido de mesa${c.numero.isEmpty ? '' : ' #${c.numero}'}',
        TipoComanda.cozinha => 'Via de cozinha${c.numero.isEmpty ? '' : ' #${c.numero}'}',
        _ => 'Impressão sem endereço de entrega',
      });
      continue;
    }
    final k = c.numero.isEmpty ? -1 : r.entregas.indexWhere((e) => e.numero == c.numero);
    if (k >= 0) {
      // duas vias do mesmo pedido: fica a mais completa
      if (c.confianca > r.entregas[k].confianca) r.entregas[k] = c;
      r.ignoradas.add('Segunda via do pedido #${c.numero}');
      continue;
    }
    r.entregas.add(c);
  }
  return r;
}
