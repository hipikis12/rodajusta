import 'dart:convert';

/// Converte os bytes que o PDV mandou para a "impressora" em texto,
/// descartando comandos ESC/POS (negrito, corte, imagem, QR code...).
String decodificarEscPos(List<int> bytes) {
  final texto = <int>[];
  var i = 0;
  int at(int k) => k < bytes.length ? bytes[k] : 0;

  while (i < bytes.length) {
    final b = bytes[i];
    if (b == 0x1B) {
      // ESC
      final cmd = at(i + 1);
      switch (cmd) {
        case 0x40: // ESC @ (inicializar)
        case 0x32: // ESC 2
        case 0x3C: // ESC <
          i += 2;
        case 0x70: // ESC p m t1 t2 (gaveta)
          i += 5;
        case 0x2A: // ESC * m nL nH dados (imagem em colunas)
          final m = at(i + 2);
          final n = at(i + 3) + at(i + 4) * 256;
          i += 5 + n * ((m == 32 || m == 33) ? 3 : 1);
        case 0x44: // ESC D n1..nk NUL (tabulações)
          i += 2;
          while (i < bytes.length && bytes[i] != 0) {
            i++;
          }
          i++;
        default: // a maioria: ESC x n
          i += 3;
      }
      continue;
    }
    if (b == 0x1D) {
      // GS
      final cmd = at(i + 1);
      switch (cmd) {
        case 0x56: // GS V m [n] (corte)
          final m = at(i + 2);
          i += (m == 65 || m == 66) ? 4 : 3;
        case 0x76: // GS v 0 m xL xH yL yH dados (imagem raster)
          final x = at(i + 4) + at(i + 5) * 256;
          final y = at(i + 6) + at(i + 7) * 256;
          i += 8 + x * y;
        case 0x28: // GS ( fn pL pH ... (QR code e afins)
          final p = at(i + 3) + at(i + 4) * 256;
          i += 5 + p;
        case 0x6B: // GS k m ... (código de barras)
          final m = at(i + 2);
          if (m <= 6) {
            i += 3;
            while (i < bytes.length && bytes[i] != 0) {
              i++;
            }
            i++;
          } else {
            i += 4 + at(i + 3);
          }
        case 0x4C: // GS L nL nH
        case 0x57: // GS W nL nH
          i += 4;
        default: // GS x n
          i += 3;
      }
      continue;
    }
    if (b == 0x1C) {
      // FS: comandos de caracteres chineses etc.
      i += 2;
      continue;
    }
    if (b == 0x10 || b == 0x0C || b == 0x0D || b == 0x00) {
      i += b == 0x10 ? 3 : 1; // DLE EOT n; FF; CR; NUL
      continue;
    }
    if (b == 0x09) {
      texto.add(0x20);
    } else {
      texto.add(b);
    }
    i++;
  }
  return _decodificarTexto(texto);
}

String _decodificarTexto(List<int> b) {
  try {
    return utf8.decode(b);
  } on FormatException {
    // Impressoras no Brasil costumam usar CP850; senão, Latin-1.
    // Bytes 0x80–0xA7 são letras acentuadas no CP850 e quase nunca
    // aparecem num texto Latin-1; as letras do português em Latin-1
    // ficam em 0xC0–0xFA.
    final evidenciaCp850 = b.where((x) => x >= 0x80 && x <= 0xA7).length;
    final evidenciaLatin1 = b.where(_letrasLatin1.contains).length;
    final pareceCp850 = evidenciaCp850 > evidenciaLatin1;
    return String.fromCharCodes(
      b.map((x) => x < 0x80 ? x : (pareceCp850 ? (_cp850[x] ?? 0x3F) : x)),
    );
  }
}

/// Letras acentuadas do português em Latin-1 (À Á Â Ã Ç É Ê Í Ó Ô Õ Ú e minúsculas).
const Set<int> _letrasLatin1 = {
  0xC0, 0xC1, 0xC2, 0xC3, 0xC7, 0xC9, 0xCA, 0xCD, 0xD3, 0xD4, 0xD5, 0xDA,
  0xE0, 0xE1, 0xE2, 0xE3, 0xE7, 0xE9, 0xEA, 0xED, 0xF3, 0xF4, 0xF5, 0xFA,
};

/// Parte da página de código 850 usada em português.
const Map<int, int> _cp850 = {
  0x80: 0xC7, 0x81: 0xFC, 0x82: 0xE9, 0x83: 0xE2, 0x84: 0xE4, 0x85: 0xE0,
  0x87: 0xE7, 0x88: 0xEA, 0x89: 0xEB, 0x8A: 0xE8, 0x8B: 0xEF, 0x8C: 0xEE,
  0x8D: 0xEC, 0x90: 0xC9, 0x93: 0xF4, 0x94: 0xF6, 0x95: 0xF2, 0x96: 0xFB,
  0x97: 0xF9, 0xA0: 0xE1, 0xA1: 0xED, 0xA2: 0xF3, 0xA3: 0xFA, 0xA4: 0xF1,
  0xA5: 0xD1, 0xA6: 0xAA, 0xA7: 0xBA, 0xB5: 0xC1, 0xB6: 0xC2, 0xB7: 0xC0,
  0xC6: 0xE3, 0xC7: 0xC3, 0xD2: 0xCA, 0xD6: 0xCD, 0xE0: 0xD3, 0xE2: 0xD4,
  0xE4: 0xF5, 0xE5: 0xD5, 0xE9: 0xDA, 0xF8: 0xB0,
};
