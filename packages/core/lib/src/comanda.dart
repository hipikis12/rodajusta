import 'dinheiro.dart';

/// Dados que o app conseguiu tirar do texto da comanda. A loja confere e
/// corrige antes de enviar (ou o envio é automático se a confiança for alta).
class ComandaExtraida {
  ComandaExtraida({
    this.numero = '',
    this.cliente = '',
    this.telefone = '',
    this.endereco = '',
    this.bairro = '',
    this.complemento = '',
    this.referencia = '',
    this.totalCentavos,
    this.taxaEntregaCentavos,
    this.cobrar = false,
    this.trocoParaCentavos,
    List<String>? itens,
  }) : itens = itens ?? [];

  String numero;
  String cliente;
  String telefone;
  String endereco;
  String bairro;
  String complemento;
  String referencia;
  int? totalCentavos;
  int? taxaEntregaCentavos;
  bool cobrar;
  int? trocoParaCentavos;
  List<String> itens;

  /// Ex.: "#482 · Maria · 2x X-Burger · R$ 54,00"
  String get descricao {
    final partes = <String>[
      if (numero.isNotEmpty) '#$numero',
      if (cliente.isNotEmpty) cliente.split(' ').first,
      if (itens.isNotEmpty) itens.first + (itens.length > 1 ? ' +${itens.length - 1}' : ''),
      if (totalCentavos != null) formatarReais(totalCentavos!),
    ];
    final d = partes.join(' · ');
    return d.length > 140 ? d.substring(0, 140) : d;
  }

  /// 0 a 1: o que dá para enviar sem a loja mexer.
  double get confianca {
    var c = 0.0;
    if (endereco.isNotEmpty) c += 0.45;
    if (RegExp(r'\d').hasMatch(endereco)) c += 0.15;
    if (bairro.isNotEmpty) c += 0.25;
    if (cliente.isNotEmpty || telefone.isNotEmpty) c += 0.1;
    if (totalCentavos != null) c += 0.05;
    return c > 1 ? 1 : c;
  }

  Map<String, Object?> paraMapa() => {
        'numero': numero,
        'cliente': cliente,
        'telefone': telefone,
        'endereco': endereco,
        'bairro': bairro,
        'complemento': complemento,
        'referencia': referencia,
        'totalCentavos': totalCentavos,
        'taxaEntregaCentavos': taxaEntregaCentavos,
        'cobrar': cobrar,
        'trocoParaCentavos': trocoParaCentavos,
        'itens': itens,
        'descricao': descricao,
      };
}

const _valor = r'(?:R\$\s*)?(\d{1,3}(?:\.\d{3})*,\d{2}|\d+,\d{2})';
final _reValor = RegExp(_valor, caseSensitive: false);

String _limpo(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim().replaceAll(RegExp(r'^[:\-\s]+'), '');

/// Primeiro grupo capturado por algum dos rótulos, numa linha.
String? _depoisDoRotulo(String linha, List<String> rotulos) {
  for (final r in rotulos) {
    final m = RegExp('^\\s*(?:$r)\\s*[:\\-.]?\\s*(.+)\$', caseSensitive: false).firstMatch(linha);
    if (m != null) return _limpo(m.group(1)!);
  }
  return null;
}

final _inicioLogradouro = RegExp(
  r'^\s*(rua|r\.|av\.?|avenida|travessa|tv\.?|alameda|al\.|estrada|est\.|rodovia|rod\.|linha|praça|praca|setor|quadra|qd\.?)\s',
  caseSensitive: false,
);

ComandaExtraida extrairComanda(String texto) {
  final c = ComandaExtraida();
  final linhas = texto
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trimRight())
      .where((l) => l.trim().isNotEmpty && !RegExp(r'^[\s\-=_*.]+$').hasMatch(l))
      .toList();

  for (var i = 0; i < linhas.length; i++) {
    final l = linhas[i];
    final baixa = l.toLowerCase();

    if (c.numero.isEmpty) {
      final m = RegExp(r'(?:pedido|ped\.|comanda|senha|n[º°o]\.?|#)\s*[:#]?\s*(\d{1,8})\b', caseSensitive: false)
          .firstMatch(l);
      if (m != null) c.numero = m.group(1)!;
    }

    final cliente = _depoisDoRotulo(l, ['cliente', 'nome', 'destinat[aá]rio']);
    if (cliente != null && c.cliente.isEmpty) {
      c.cliente = cliente.replaceAll(RegExp(r'\s*(tel|fone|cel).*$', caseSensitive: false), '');
    }

    if (c.telefone.isEmpty) {
      final m = RegExp(r'\(?\b(\d{2})\)?\s?(9?\d{4})[\s\-]?(\d{4})\b').firstMatch(l);
      if (m != null && RegExp(r'tel|fone|cel|whats|contato|\(', caseSensitive: false).hasMatch(l)) {
        c.telefone = '${m.group(1)}${m.group(2)}${m.group(3)}';
      }
    }

    final end = _depoisDoRotulo(l, ['endere[cç]o(?: de entrega)?', 'end\\.?', 'entregar em', 'local de entrega']);
    if (end != null && c.endereco.isEmpty) {
      c.endereco = end;
      // "Rua X, 123 - Bairro" na mesma linha
      final partes = end.split(RegExp(r'\s+-\s+'));
      if (partes.length > 1 && c.bairro.isEmpty && !RegExp(r'^\d').hasMatch(partes.last)) {
        c.endereco = partes.first;
        c.bairro = partes.last;
      }
      // endereço quebrado em duas linhas: a próxima tem só o número
      if (!RegExp(r'\d').hasMatch(c.endereco) && i + 1 < linhas.length && RegExp(r'^\s*(n[º°o]?\.?\s*)?\d+').hasMatch(linhas[i + 1])) {
        c.endereco = '${c.endereco}, ${_limpo(linhas[i + 1]).replaceAll(RegExp(r'^n[º°o]?\.?\s*', caseSensitive: false), '')}';
      }
    } else if (c.endereco.isEmpty && _inicioLogradouro.hasMatch(l)) {
      c.endereco = _limpo(l);
    }

    final bairro = _depoisDoRotulo(l, ['bairro', 'b\\.']);
    if (bairro != null) c.bairro = bairro;

    final compl = _depoisDoRotulo(l, ['complemento', 'compl\\.?', 'apto', 'apartamento', 'bloco']);
    if (compl != null && c.complemento.isEmpty) c.complemento = compl;

    final ref = _depoisDoRotulo(l, ['ponto de refer[eê]ncia', 'refer[eê]ncia', 'ref\\.?', 'obs(?:erva[cç][aã]o)?\\.?']);
    if (ref != null && c.referencia.isEmpty) c.referencia = ref;

    final item = RegExp(r'^\s*(\d+)\s*(?:x|un\.?|und\.?)\s+(.+?)(?:\s+' + _valor + r')?\s*$', caseSensitive: false).firstMatch(l);
    if (item != null) c.itens.add('${item.group(1)}x ${_limpo(item.group(2)!)}');

    if (RegExp(r'taxa\s+de\s+entrega|frete|entrega\s*[:\-]', caseSensitive: false).hasMatch(l)) {
      final v = _reValor.firstMatch(l);
      if (v != null) c.taxaEntregaCentavos = lerReais(v.group(1)!);
    }

    if (RegExp(r'\btotal\b', caseSensitive: false).hasMatch(l) && !baixa.contains('sub')) {
      final v = _reValor.allMatches(l).lastOrNull;
      if (v != null) c.totalCentavos = lerReais(v.group(1)!); // o último "total" vale
    }

    if (RegExp(r'dinheiro|troco|a receber|cobrar|pagar na entrega', caseSensitive: false).hasMatch(l)) {
      c.cobrar = true;
      final t = RegExp(r'troco\s*(?:para|p/)?\s*' + _valor, caseSensitive: false).firstMatch(l);
      if (t != null) c.trocoParaCentavos = lerReais(t.group(1)!);
    }
  }
  if (RegExp(r'\b(pago|pagamento online|pago no app|j[aá] pago)\b', caseSensitive: false).hasMatch(texto) &&
      !RegExp(r'troco|dinheiro', caseSensitive: false).hasMatch(texto)) {
    c.cobrar = false;
  }
  return c;
}
