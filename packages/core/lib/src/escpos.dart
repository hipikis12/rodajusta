import 'dart:typed_data';

import 'paginas_codigo.dart';

/// Imagem monocromática recebida do PDV (recibos impressos "como figura").
/// Linha a linha, 1 bit por ponto, bit mais alto = ponto mais à esquerda,
/// 1 = preto (como na impressora).
class ImagemRaster {
  ImagemRaster(this.largura, this.altura, this.bits);
  final int largura;
  final int altura;
  final Uint8List bits;
  int get bytesPorLinha => (largura + 7) >> 3;

  bool ponto(int x, int y) => (bits[y * bytesPorLinha + (x >> 3)] >> (7 - (x & 7))) & 1 == 1;

  /// Fração de pontos pretos (logotipo pequeno x recibo inteiro).
  double get tinta {
    var n = 0;
    for (final b in bits) {
      var v = b;
      while (v != 0) {
        n += v & 1;
        v >>= 1;
      }
    }
    return largura * altura == 0 ? 0 : n / (largura * altura);
  }
}

/// Um pedaço do trabalho de impressão entre dois cortes de papel:
/// normalmente uma comanda (ou uma via dela).
class SegmentoImpressao {
  SegmentoImpressao(this.texto, this.imagens);
  final String texto;
  final List<ImagemRaster> imagens;

  bool get vazio => texto.trim().isEmpty && imagens.isEmpty;
}

class _Segmento {
  final texto = BytesBuilder(copy: false);
  final imagens = <ImagemRaster>[];
  // imagem sendo montada por faixas (ESC * ou GS v 0 consecutivos)
  int _largura = 0;
  final _linhas = <Uint8List>[];
  bool get temConteudo => texto.length > 0 || imagens.isNotEmpty || _linhas.isNotEmpty;

  void anexarLinhas(int largura, List<Uint8List> linhas) {
    if (_linhas.isNotEmpty && largura != _largura) fecharImagem();
    _largura = largura;
    _linhas.addAll(linhas);
  }

  void fecharImagem() {
    if (_linhas.isEmpty) return;
    final bpl = (_largura + 7) >> 3;
    final bits = Uint8List(bpl * _linhas.length);
    for (var y = 0; y < _linhas.length; y++) {
      final l = _linhas[y];
      bits.setRange(y * bpl, y * bpl + (l.length < bpl ? l.length : bpl), l);
    }
    imagens.add(ImagemRaster(_largura, _linhas.length, bits));
    _linhas.clear();
  }
}

/// Decodifica um trabalho de impressão ESC/POS (e variantes Bematech,
/// Daruma, Elgin, Epson, clones) em segmentos de texto + imagens.
/// Comandos de formatação são descartados; corte de papel, `ESC @` depois
/// de conteúdo e form feed separam comandas.
List<SegmentoImpressao> decodificarTrabalho(List<int> entrada) {
  final b = entrada is Uint8List ? entrada : Uint8List.fromList(entrada);
  final n = b.length;
  int at(int k) => k < n ? b[k] : 0;
  int u16(int k) => at(k) | (at(k + 1) << 8);

  var atual = _Segmento();
  final segmentos = <_Segmento>[atual];
  PaginaCodigo? anunciada;

  void cortar() {
    atual.fecharImagem();
    if (atual.temConteudo) {
      atual = _Segmento();
      segmentos.add(atual);
    }
  }

  void quebra() {
    atual.texto.addByte(0x0A);
  }

  void texto(int c) {
    atual.fecharImagem();
    atual.texto.addByte(c);
  }

  // ESC * m nL nH d — imagem em colunas (faixas de 8 ou 24 pontos)
  void imagemColunas(int m, int largura, int ini) {
    final alturaFaixa = (m == 32 || m == 33) ? 24 : 8;
    final bytesColuna = alturaFaixa ~/ 8;
    final bpl = (largura + 7) >> 3;
    final linhas = List.generate(alturaFaixa, (_) => Uint8List(bpl));
    for (var x = 0; x < largura; x++) {
      for (var k = 0; k < bytesColuna; k++) {
        final v = at(ini + x * bytesColuna + k);
        for (var bit = 0; bit < 8; bit++) {
          if ((v >> (7 - bit)) & 1 == 1) {
            linhas[k * 8 + bit][x >> 3] |= 0x80 >> (x & 7);
          }
        }
      }
    }
    atual.anexarLinhas(largura, linhas);
  }

  // dados raster linha a linha (GS v 0, GS ( L / GS 8 L)
  void imagemLinhas(int bytesPorLinha, int altura, int ini) {
    if (bytesPorLinha <= 0 || altura <= 0) return;
    final linhas = <Uint8List>[];
    for (var y = 0; y < altura; y++) {
      final s = ini + y * bytesPorLinha;
      if (s >= n) break;
      final e = s + bytesPorLinha;
      linhas.add(Uint8List.fromList(b.sublist(s, e <= n ? e : n)));
    }
    atual.anexarLinhas(bytesPorLinha * 8, linhas);
  }

  /// GS ( L / GS 8 L: só a função 112 (guardar raster) interessa.
  void graficos(int ini, int tamanho) {
    // ini aponta para m (48), fn
    final fn = at(ini + 1);
    if (fn != 112) return;
    final a = at(ini + 2);
    final c = at(ini + 5);
    if (a != 48 || (c != 49 && c != 1)) return; // só monocromático, 1ª cor
    final x = u16(ini + 6);
    final y = u16(ini + 8);
    if (10 + ((x + 7) >> 3) * y > tamanho) return;
    imagemLinhas((x + 7) >> 3, y, ini + 10);
  }

  var i = 0;
  while (i < n) {
    final c = b[i];
    switch (c) {
      case 0x1B: // ESC
        final cmd = at(i + 1);
        switch (cmd) {
          case 0x40: // ESC @ inicializar: começo de outra comanda
            cortar();
            i += 2;
          case 0x69 || 0x6D: // ESC i / ESC m: corte
            cortar();
            i += 2;
          case 0x64 || 0x4A: // ESC d n / ESC J n: avança papel
            quebra();
            i += 3;
          case 0x74: // ESC t n: página de código
            anunciada = paginaDoComandoEscT(at(i + 2)) ?? anunciada;
            i += 3;
          case 0x2A: // ESC * m nL nH d
            final m = at(i + 2);
            final largura = u16(i + 3);
            imagemColunas(m, largura, i + 5);
            i += 5 + largura * ((m == 32 || m == 33) ? 3 : 1);
          case 0x4B: // ESC K nL nH d (imagem antiga, 8 pontos)
            final largura = u16(i + 2);
            imagemColunas(0, largura, i + 4);
            i += 4 + largura;
          case 0x44: // ESC D n1..nk NUL
            i += 2;
            while (i < n && b[i] != 0) {
              i++;
            }
            i++;
          case 0x26: // ESC & y c1 c2 [x d...]: caracteres definidos pelo usuário
            final y = at(i + 2);
            final c1 = at(i + 3), c2 = at(i + 4);
            i += 5;
            for (var k = c1; k <= c2 && i < n; k++) {
              final x = at(i);
              i += 1 + x * y;
            }
          case 0x24 || 0x5C: // ESC $ / ESC \ nL nH (posição)
            i += 4;
          case 0x70: // ESC p m t1 t2 (gaveta)
            i += 5;
          case 0x57: // ESC W: área de página (Epson, 10 bytes) ou largura dupla (Bematech, 3)
            final v = at(i + 2);
            i += (v <= 1 || v == 0x30 || v == 0x31) ? 3 : 10;
          case 0x63: // ESC c 3|4|5 n
            i += 4;
          case 0x0C || 0x32 || 0x3C || 0x4C || 0x53 || 0x76 || 0x46 || 0x0E || 0x0F || 0x12 || 0x14:
            i += 2; // comandos sem parâmetro (inclui variantes Bematech/Star)
          default:
            i += cmd < 0x20 ? 2 : 3; // a grande maioria: ESC x n
        }
      case 0x1D: // GS
        final cmd = at(i + 1);
        switch (cmd) {
          case 0x56: // GS V m [n]: corte
            final m = at(i + 2);
            cortar();
            i += const {65, 66, 97, 98, 103, 104}.contains(m) ? 4 : 3;
          case 0x76: // GS v 0 m xL xH yL yH d: imagem raster
            final x = u16(i + 4), y = u16(i + 6);
            imagemLinhas(x, y, i + 8);
            i += 8 + x * y;
          case 0x28: // GS ( fn pL pH ...
            final p = u16(i + 3);
            if (at(i + 2) == 0x4C) graficos(i + 5, p);
            i += 5 + p;
          case 0x38: // GS 8 L p1 p2 p3 p4 ... (gráficos grandes)
            if (at(i + 2) == 0x4C) {
              final p = u16(i + 3) | (u16(i + 5) << 16);
              graficos(i + 7, p);
              i += 7 + p;
            } else {
              i += 3;
            }
          case 0x2A: // GS * x y d (imagem guardada)
            i += 4 + at(i + 2) * at(i + 3) * 8;
          case 0x6B: // GS k m ... (código de barras)
            final m = at(i + 2);
            if (m <= 6) {
              i += 3;
              while (i < n && b[i] != 0) {
                i++;
              }
              i++;
            } else {
              i += 4 + at(i + 3);
            }
          case 0x24 || 0x4C || 0x50 || 0x57 || 0x5C: // 2 parâmetros
            i += 4;
          case 0x5E || 0x7A: // GS ^ r t m / GS z 0 t1 t2
            i += 5;
          case 0x67: // GS g 0/2 m nL nH
            i += 6;
          case 0x3A || 0x63: // GS : / GS c
            i += 2;
          default:
            i += 3;
        }
      case 0x1C: // FS
        final cmd = at(i + 1);
        switch (cmd) {
          case 0x21 || 0x2D || 0x43 || 0x57: // 1 parâmetro
            i += 3;
          case 0x53 || 0x70: // FS S n1 n2 / FS p n m (logotipo guardado)
            i += 4;
          case 0x28: // FS ( fn pL pH ...
            i += 5 + u16(i + 3);
          case 0x32: // FS 2 c1 c2 d1..d72
            i += 76;
          case 0x71: // FS q n [xL xH yL yH d]...
            final qtd = at(i + 2);
            i += 3;
            for (var k = 0; k < qtd && i < n; k++) {
              final x = u16(i), y = u16(i + 2);
              i += 4 + x * y * 8;
            }
          default:
            i += 2;
        }
      case 0x10: // DLE
        final cmd = at(i + 1);
        if (cmd == 0x04 || cmd == 0x05) {
          i += 3; // DLE EOT n / DLE ENQ n
        } else if (cmd == 0x14) {
          final fn = at(i + 2);
          i += fn == 7 ? 4 : fn == 8 ? 10 : 5;
        } else {
          i += 2;
        }
      case 0x0A:
        quebra();
        i++;
      case 0x0D: // CR: CR LF vira uma quebra; CR sozinho também
        if (at(i + 1) != 0x0A) quebra();
        i++;
      case 0x0C: // form feed: fim de página/trabalho
        cortar();
        i++;
      case 0x09:
        texto(0x20);
        i++;
      default:
        if (c >= 0x20 && c != 0x7F) texto(c);
        i++; // outros controles (SO, SI, DC2...) são formatação
    }
  }
  atual.fecharImagem();

  final todos = BytesBuilder();
  for (final s in segmentos) {
    todos.add(s.texto.toBytes());
  }
  final pagina = escolherPagina(todos.toBytes(), anunciada: anunciada);
  return [
    for (final s in segmentos)
      SegmentoImpressao(_normalizar(decodificarCom(s.texto.toBytes(), pagina)), s.imagens),
  ].where((s) => !s.vazio).toList();
}

String _normalizar(String t) => t
    .split('\n')
    .map((l) => l.replaceAll(RegExp(r'[\u0000-\u0008\u000B-\u001F\u007F]'), '').trimRight())
    .join('\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

/// Texto de todo o trabalho (todas as comandas juntas).
String decodificarEscPos(List<int> bytes) => decodificarTrabalho(bytes).map((s) => s.texto).join('\n');

/// Procura pedidos de status no que chegou, para a "impressora" responder
/// como uma de verdade (alguns PDVs não imprimem se ninguém responde).
/// Devolve os bytes de resposta, na ordem.
List<int> respostasDeStatus(List<int> b) {
  final r = <int>[];
  for (var i = 0; i + 2 < b.length; i++) {
    if (b[i] == 0x10 && b[i + 1] == 0x04) {
      r.add(0x12); // DLE EOT n: tudo OK (bits fixos 1 e 4)
      i += 2;
    } else if (b[i] == 0x1D && b[i + 1] == 0x49) {
      final k = b[i + 2]; // GS I n: identificação
      if (k == 1 || k == 49) {
        r.add(0x20);
      } else if (k == 2 || k == 50) {
        r.add(0x02);
      } else if (k == 3 || k == 51) {
        r.add(0x01);
      } else if (k >= 65 && k <= 69) {
        r.addAll([0x5F, ...'RodaJusta'.codeUnits, 0x00]);
      }
      i += 2;
    } else if (b[i] == 0x1D && b[i + 1] == 0x72) {
      r.add(0x00); // GS r n: papel e gaveta OK
      i += 2;
    } else if (b[i] == 0x1B && (b[i + 1] == 0x76 || b[i + 1] == 0x75)) {
      r.add(0x00); // ESC v / ESC u: sensores OK
      i += 1;
    }
  }
  return r;
}
