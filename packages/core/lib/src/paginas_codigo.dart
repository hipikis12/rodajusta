import 'dart:convert';

/// Páginas de código usadas por impressoras térmicas no Brasil.
/// Cada tabela traz os caracteres dos bytes 0x80 a 0xFF.
enum PaginaCodigo { utf8, cp437, cp850, cp860, cp1252 }

const _caixa =
    '░▒▓│┤╡╢╖╕╣║╗╝╜╛┐'
    '└┴┬├─┼╞╟╚╔╩╦╠═╬╧'
    '╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀'
    'αßΓπΣσµτΦΘΩδ∞φε∩'
    '≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ ';

const _cp437 = 'ÇüéâäàåçêëèïîìÄÅ'
    'ÉæÆôöòûùÿÖÜ¢£¥₧ƒ'
    'áíóúñÑªº¿⌐¬½¼¡«»'
    '$_caixa';

const _cp860 = 'ÇüéâãàÁçêÊèÍÔìÃÂ'
    'ÉÀÈôõòÚùÌÕÜ¢£Ù₧Ó'
    'áíóúñÑªº¿Ò¬½¼¡«»'
    '$_caixa';

const _cp850 = 'ÇüéâäàåçêëèïîìÄÅ'
    'ÉæÆôöòûùÿÖÜø£Ø×ƒ'
    'áíóúñÑªº¿®¬½¼¡«»'
    '░▒▓│┤ÁÂÀ©╣║╗╝¢¥┐'
    '└┴┬├─┼ãÃ╚╔╩╦╠═╬¤'
    'ðÐÊËÈıÍÎÏ┘┌█▄¦Ì▀'
    'ÓßÔÒõÕµþÞÚÛÙýÝ¯´'
    '­±‗¾¶§÷¸°¨·¹³²■ ';

const _cp1252Alto = '€\u0081‚ƒ„…†‡ˆ‰Š‹Œ\u008DŽ\u008F'
    '\u0090‘’“”•–—˜™š›œ\u009DžŸ';

final Map<PaginaCodigo, List<int>> _tabelas = {
  PaginaCodigo.cp437: _cp437.runes.toList(),
  PaginaCodigo.cp850: _cp850.runes.toList(),
  PaginaCodigo.cp860: _cp860.runes.toList(),
  PaginaCodigo.cp1252: [
    ..._cp1252Alto.runes,
    for (var b = 0xA0; b <= 0xFF; b++) b, // A0–FF = Latin-1
  ],
};

/// Converte o número de `ESC t n` na página correspondente (null = desconhecida).
PaginaCodigo? paginaDoComandoEscT(int n) => switch (n) {
      0 => PaginaCodigo.cp437,
      2 || 19 => PaginaCodigo.cp850, // 19 = CP858 (850 com €)
      3 => PaginaCodigo.cp860,
      16 || 6 => PaginaCodigo.cp1252, // 16 = WPC1252 (Epson); 6 em alguns clones
      _ => null,
    };

String decodificarCom(List<int> bytes, PaginaCodigo pagina) {
  if (pagina == PaginaCodigo.utf8) return utf8.decode(bytes, allowMalformed: true);
  final t = _tabelas[pagina]!;
  return String.fromCharCodes(bytes.map((b) => b < 0x80 ? b : t[b - 0x80]));
}

const _letrasPt = 'áàâãéêíóôõúçÁÀÂÃÉÊÍÓÔÕÚÇ';
final _lixo = RegExp(r'[░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αΓπΣσΦΘΩδ∞φε∩≡⌠⌡≈∙√ⁿ■₧ƒ¤ðÐıþÞ¯´‗¶¸¨¹³ÿ\u0080-\u009F�]');

/// Nota de quanto um texto "parece português": letras acentuadas comuns
/// contam a favor; símbolos de caixa, gregos e trocados contam contra.
int notaPortugues(String s) {
  var nota = 0;
  for (final r in s.runes) {
    if (r < 0x80) continue;
    final c = String.fromCharCode(r);
    if (_letrasPt.contains(c)) {
      nota += 2;
    } else if (_lixo.hasMatch(c)) {
      nota -= 3;
    } else {
      nota -= 1;
    }
  }
  return nota;
}

/// Escolhe a página que dá o texto mais parecido com português.
/// A página anunciada pelo PDV (`ESC t`) ganha um pequeno bônus, mas não
/// manda sozinha: muitos sistemas anunciam uma e mandam outra.
PaginaCodigo escolherPagina(List<int> bytes, {PaginaCodigo? anunciada}) {
  if (!bytes.any((b) => b >= 0x80)) return anunciada ?? PaginaCodigo.cp850;
  try {
    utf8.decode(bytes);
    // UTF-8 válido com bytes altos é praticamente certeza de UTF-8
    return PaginaCodigo.utf8;
  } on FormatException {
    // segue para as páginas de 1 byte
  }
  final candidatas = [PaginaCodigo.cp850, PaginaCodigo.cp860, PaginaCodigo.cp1252, PaginaCodigo.cp437];
  var melhor = candidatas.first;
  var melhorNota = -1 << 30;
  for (final p in candidatas) {
    var n = notaPortugues(decodificarCom(bytes, p));
    if (p == anunciada) n += 3;
    if (n > melhorNota) {
      melhor = p;
      melhorNota = n;
    }
  }
  return melhor;
}
