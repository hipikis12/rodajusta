import 'dart:convert';
import 'dart:typed_data';

import 'package:rodajusta_core/rodajusta_core.dart';
import 'package:test/test.dart';

List<int> _l1(String s) => latin1.encode(s);

void main() {
  group('comandos', () {
    test('remove formatação e mantém o texto', () {
      final bytes = <int>[
        0x1B, 0x40, // inicializa
        0x1B, 0x61, 0x01, // centraliza
        0x1B, 0x45, 0x01, // negrito
        0x1D, 0x21, 0x11, // tamanho
        ..._l1('PEDIDO 482\n'),
        0x1B, 0x45, 0x00,
        0x1B, 0x24, 0x10, 0x00, // ESC $ posição (2 parâmetros)
        ..._l1('Rua A, 10\n'),
        0x1D, 0x56, 0x41, 0x03, // corte com avanço
      ];
      expect(decodificarEscPos(bytes), 'PEDIDO 482\nRua A, 10');
    });

    test('pula imagem raster, QR code, código de barras e logotipo', () {
      final bytes = <int>[
        ..._l1('A\n'),
        0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x05, // QR: tamanho
        0x1D, 0x6B, 0x49, 0x03, 0x41, 0x42, 0x43, // código de barras (m >= 65)
        0x1D, 0x6B, 0x04, 0x31, 0x32, 0x00, // código de barras (NUL)
        0x1C, 0x70, 0x01, 0x00, // FS p: logotipo guardado
        0x1B, 0x70, 0x00, 0x19, 0xFA, // gaveta
        0x10, 0x04, 0x01, // pedido de status
        ..._l1('B\n'),
      ];
      expect(decodificarEscPos(bytes), 'A\nB');
    });

    test('CR sozinho, CR LF e avanço de linhas viram quebras', () {
      final bytes = [..._l1('A\rB\r\nC'), 0x1B, 0x64, 0x02, ..._l1('D')];
      expect(decodificarEscPos(bytes), 'A\nB\nC\nD');
    });

    test('Bematech: SO/SI e ESC W de largura dupla não sujam o texto', () {
      final bytes = [0x0E, ..._l1('TOTAL'), 0x14, 0x1B, 0x57, 0x01, ..._l1(' 10,00'), 0x1B, 0x57, 0x00, 0x0F, ..._l1('\nfim')];
      expect(decodificarEscPos(bytes), 'TOTAL 10,00\nfim');
    });
  });

  group('separação de comandas', () {
    test('corte separa as vias', () {
      final bytes = [
        ..._l1('Via 1\n'),
        0x1D, 0x56, 0x00,
        ..._l1('Via 2\n'),
        0x1B, 0x69,
        ..._l1('Via 3\n'),
      ];
      expect(decodificarTrabalho(bytes).map((s) => s.texto).toList(), ['Via 1', 'Via 2', 'Via 3']);
    });

    test('ESC @ depois de conteúdo começa outra comanda; form feed também', () {
      final bytes = [0x1B, 0x40, ..._l1('A\n'), 0x1B, 0x40, ..._l1('B\n'), 0x0C, ..._l1('C')];
      expect(decodificarTrabalho(bytes).map((s) => s.texto).toList(), ['A', 'B', 'C']);
    });
  });

  group('páginas de código', () {
    test('CP850', () {
      // "Endereço São" em CP850: ç = 0x87, ã = 0xC6
      final bytes = [..._l1('Endere'), 0x87, ..._l1('o S'), 0xC6, ..._l1('o')];
      expect(decodificarEscPos(bytes), 'Endereço São');
    });
    test('CP860 (português) com ESC t 3', () {
      // "Não" e "PÃO" em CP860: ã = 0x84, Ã = 0x8E
      final bytes = [0x1B, 0x74, 0x03, ..._l1('N'), 0x84, ..._l1('o P'), 0x8E, ..._l1('O')];
      expect(decodificarEscPos(bytes), 'Não PÃO');
    });
    test('Windows-1252 / Latin-1', () {
      expect(decodificarEscPos(_l1('Referência: próximo à praça')), 'Referência: próximo à praça');
    });
    test('UTF-8', () {
      expect(decodificarEscPos(utf8.encode('Açaí com granola')), 'Açaí com granola');
    });
    test('anúncio errado: ESC t 2 (850) mas texto em 1252 — vence o que parece português', () {
      final bytes = [0x1B, 0x74, 0x02, ..._l1('Endereço: Avenida Canaã, São José')];
      expect(decodificarEscPos(bytes), 'Endereço: Avenida Canaã, São José');
    });
  });

  group('imagens', () {
    test('GS v 0 vira imagem raster', () {
      // 2 bytes por linha (16 pontos), 3 linhas
      final bytes = [0x1D, 0x76, 0x30, 0x00, 0x02, 0x00, 0x03, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x80, 0x01];
      final seg = decodificarTrabalho(bytes).single;
      final img = seg.imagens.single;
      expect(img.largura, 16);
      expect(img.altura, 3);
      expect(img.ponto(0, 0), isTrue);
      expect(img.ponto(8, 0), isFalse);
      expect(img.ponto(15, 1), isTrue);
      expect(img.ponto(0, 2), isTrue);
    });

    test('faixas seguidas de GS v 0 são emendadas numa imagem só', () {
      final faixa = [0x1D, 0x76, 0x30, 0x00, 0x01, 0x00, 0x02, 0x00, 0xAA, 0x55];
      final seg = decodificarTrabalho([...faixa, 0x0A, ...faixa]).single;
      expect(seg.imagens.single.altura, 4);
    });

    test('ESC * em colunas de 24 pontos', () {
      // 2 colunas; 1ª com o ponto do topo aceso, 2ª com o de baixo
      final bytes = [0x1B, 0x2A, 33, 0x02, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x01];
      final img = decodificarTrabalho(bytes).single.imagens.single;
      expect(img.altura, 24);
      expect(img.ponto(0, 0), isTrue);
      expect(img.ponto(1, 23), isTrue);
      expect(img.ponto(1, 0), isFalse);
    });

    test('GS ( L função 112 (gráfico guardado)', () {
      // m=48 fn=112 a=48 bx=1 by=1 c=49 x=8 y=2 + 2 bytes
      final corpo = [48, 112, 48, 1, 1, 49, 8, 0, 2, 0, 0xF0, 0x0F];
      final bytes = [0x1D, 0x28, 0x4C, corpo.length, 0x00, ...corpo];
      final img = decodificarTrabalho(bytes).single.imagens.single;
      expect(img.largura, 8);
      expect(img.altura, 2);
      expect(img.ponto(0, 0), isTrue);
      expect(img.ponto(7, 1), isTrue);
    });

    test('PNG válido para o OCR', () {
      final img = ImagemRaster(10, 4, Uint8List.fromList(List.filled(8, 0xFF)));
      final png = pngDaImagem(img);
      expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(String.fromCharCodes(png.sublist(12, 16)), 'IHDR');
      // largura 10 + margem 2x16
      expect(png[16] << 24 | png[17] << 16 | png[18] << 8 | png[19], 42);
      expect(String.fromCharCodes(png.sublist(png.length - 8, png.length - 4)), 'IEND');
    });

    test('CRC-32 e Adler-32 conhecidos', () {
      expect(crc32('123456789'.codeUnits), 0xCBF43926);
      expect(adler32('Wikipedia'.codeUnits), 0x11E60398);
    });
  });

  group('respostas de status', () {
    test('DLE EOT, GS I e GS r recebem resposta', () {
      expect(respostasDeStatus([0x10, 0x04, 0x01]), [0x12]);
      expect(respostasDeStatus([0x1D, 0x49, 0x01]), [0x20]);
      expect(respostasDeStatus([0x1D, 0x72, 0x01]), [0x00]);
      expect(respostasDeStatus(_l1('texto comum')), isEmpty);
    });
  });
}
