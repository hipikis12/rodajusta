import 'dart:typed_data';

import 'escpos.dart';

/// Converte a imagem do recibo em PNG (1 bit, cinza) para o OCR ler.
/// Feito à mão, sem dependências, para funcionar no Android e na web.
Uint8List pngDaImagem(ImagemRaster img, {int margem = 16}) {
  final largura = img.largura + margem * 2;
  final altura = img.altura + margem * 2;
  final bpl = (largura + 7) >> 3;
  // PNG cinza 1 bit: 1 = branco. Na impressora 1 = preto, então inverte.
  final cru = Uint8List(altura * (bpl + 1));
  for (var y = 0; y < altura; y++) {
    final base = y * (bpl + 1);
    cru[base] = 0; // filtro "nenhum"
    for (var k = 1; k <= bpl; k++) {
      cru[base + k] = 0xFF;
    }
    final yi = y - margem;
    if (yi < 0 || yi >= img.altura) continue;
    for (var x = 0; x < img.largura; x++) {
      if (img.ponto(x, yi)) {
        final xo = x + margem;
        cru[base + 1 + (xo >> 3)] &= ~(0x80 >> (xo & 7)) & 0xFF;
      }
    }
  }

  final ihdr = ByteData(13)
    ..setUint32(0, largura)
    ..setUint32(4, altura)
    ..setUint8(8, 1) // profundidade: 1 bit
    ..setUint8(9, 0) // tipo: cinza
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);

  final saida = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_bloco('IHDR', ihdr.buffer.asUint8List()))
    ..add(_bloco('IDAT', zlibSemCompressao(cru)))
    ..add(_bloco('IEND', Uint8List(0)));
  return saida.toBytes();
}

Uint8List _bloco(String tipo, Uint8List dados) {
  final t = Uint8List.fromList(tipo.codeUnits);
  final b = BytesBuilder()
    ..add((ByteData(4)..setUint32(0, dados.length)).buffer.asUint8List())
    ..add(t)
    ..add(dados);
  final crc = crc32([...t, ...dados]);
  b.add((ByteData(4)..setUint32(0, crc)).buffer.asUint8List());
  return b.toBytes();
}

/// zlib com blocos "stored" (sem compressão): simples e válido.
Uint8List zlibSemCompressao(Uint8List dados) {
  final b = BytesBuilder()..add(const [0x78, 0x01]);
  var pos = 0;
  do {
    final tam = (dados.length - pos).clamp(0, 65535);
    final ultimo = pos + tam >= dados.length;
    b
      ..addByte(ultimo ? 1 : 0)
      ..addByte(tam & 0xFF)
      ..addByte(tam >> 8)
      ..addByte(~tam & 0xFF)
      ..addByte((~tam >> 8) & 0xFF)
      ..add(dados.sublist(pos, pos + tam));
    pos += tam;
  } while (pos < dados.length);
  b.add((ByteData(4)..setUint32(0, adler32(dados))).buffer.asUint8List());
  return b.toBytes();
}

final List<int> _tabelaCrc = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) == 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
});

int crc32(List<int> dados) {
  var c = 0xFFFFFFFF;
  for (final x in dados) {
    c = _tabelaCrc[(c ^ x) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

int adler32(List<int> dados) {
  var a = 1, b = 0;
  for (final x in dados) {
    a = (a + x) % 65521;
    b = (b + a) % 65521;
  }
  return (b << 16) | a;
}
