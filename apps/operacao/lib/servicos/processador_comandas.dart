import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import 'api.dart';
import 'comandas.dart';

/// Roda no motor Flutter sem tela, dentro do serviço Android: pega os
/// trabalhos de impressão da fila, lê as comandas e grava no Firebase.
class ProcessadorComandas {
  static const _fila = MethodChannel('rodajusta/fila');

  bool _ocupado = false;
  bool _denovo = false;
  Map<String, dynamic>? _loja;
  DateTime _lojaLidaEm = DateTime.fromMillisecondsSinceEpoch(0);
  String? _cidadeLoja;

  Future<void> iniciar() async {
    _fila.setMethodCallHandler((chamada) async {
      if (chamada.method == 'processar') unawaited(_processar());
      return null;
    });
    await _fila.invokeMethod<void>('pronto');
    await _processar();
  }

  Future<void> _processar() async {
    if (_ocupado) {
      _denovo = true;
      return;
    }
    _ocupado = true;
    try {
      do {
        _denovo = false;
        final lista = await _fila.invokeListMethod<dynamic>('pendentes') ?? [];
        for (final item in lista) {
          final m = Map<String, dynamic>.from(item as Map);
          final ok = await _umTrabalho(m['id'] as String, m['bytes'] as Uint8List, m['origem'] as String? ?? '');
          if (!ok) return; // sem login ou sem internet: tenta na próxima comanda
        }
        if (lista.length >= 10) _denovo = true;
      } while (_denovo);
    } finally {
      _ocupado = false;
    }
  }

  /// Devolve false quando não deu para concluir (fica na fila).
  Future<bool> _umTrabalho(String id, Uint8List bytes, String via) async {
    final user = FirebaseAuth.instance.currentUser ??
        await FirebaseAuth.instance.authStateChanges().first.timeout(const Duration(seconds: 10), onTimeout: () => null);
    if (user == null) {
      await _fila.invokeMethod('falhou', {'id': id, 'mensagem': 'Abra o app e entre na conta da loja para processar comandas'});
      return false;
    }
    final uidLoja = user.uid;

    // 1. bytes → texto (e OCR se o cupom veio como imagem)
    var segmentos = <SegmentoImpressao>[];
    var textos = <String>[];
    try {
      segmentos = decodificarTrabalho(bytes);
      textos = segmentos.map((s) => s.texto).toList();
    } catch (_) {
      // bytes estranhos: segue com o que deu para ler
    }
    var leitura = lerTrabalho(textos);
    if (leitura.entregas.isEmpty && segmentos.any((s) => s.imagens.any((i) => i.altura >= 100))) {
      textos = [
        for (final s in segmentos)
          [s.texto, for (final img in s.imagens.where((i) => i.altura >= 100)) await _ocr(img)].join('\n'),
      ];
      leitura = lerTrabalho(textos);
    }
    final textoBruto = textos.join('\n----- corte -----\n');

    try {
      final loja = await _dadosLoja(uidLoja);
      final config = Map<String, dynamic>.from(loja['config'] as Map? ?? {});
      final pontoLoja = _ponto(loja['lat'], loja['lng']);
      final ignoradas = [...leitura.ignoradas];
      final novas = <String>[];

      for (var k = 0; k < leitura.entregas.length; k++) {
        final c = leitura.entregas[k];
        if (c.numero.isNotEmpty && await _jaRecebida(uidLoja, c.numero)) {
          ignoradas.add('Reimpressão do pedido #${c.numero}');
          continue;
        }
        final ponto = await _localizar(c, pontoLoja);
        if (c.enderecoDoTopo && _ehDaLoja(c, ponto, loja, pontoLoja)) {
          ignoradas.add('Só tinha o endereço da própria loja${c.numero.isEmpty ? '' : ' (#${c.numero})'}');
          continue;
        }
        final ref = db.doc('lojistas/$uidLoja/comandas/bt_${id}_$k');
        final doc = documentoDaComanda(c, origem: 'comanda', via: via, ponto: ponto, textoBruto: c.textoOriginal);
        await ref.set(doc).timeout(const Duration(seconds: 25));
        novas.add(c.descricao.isEmpty ? (c.bairro.isEmpty ? 'Comanda recebida' : c.bairro) : c.descricao);
        await _envioAutomatico(ref.id, doc, c, ponto, pontoLoja, config);
      }

      // nada legível: guarda o texto cru para a loja não perder o pedido
      if (leitura.entregas.isEmpty && leitura.ignoradas.isEmpty && textoBruto.trim().length >= 20) {
        final c = extrairComanda(textoBruto);
        await db
            .doc('lojistas/$uidLoja/comandas/bt_${id}_x')
            .set(documentoDaComanda(c, origem: 'comanda', via: via, textoBruto: textoBruto))
            .timeout(const Duration(seconds: 25));
        novas.add('Comanda sem endereço reconhecido: confira');
      }

      final msg = novas.isNotEmpty
          ? '${novas.length == 1 ? 'Nova comanda' : '${novas.length} comandas'}: ${novas.first}'
          : ignoradas.isNotEmpty
              ? 'Ignorada: ${ignoradas.first}'
              : 'Impressão sem pedido (ignorada)';
      await _fila.invokeMethod('concluir', {'id': id, 'mensagem': msg, 'novas': novas});
      return true;
    } on TimeoutException {
      await _fila.invokeMethod('falhou', {'id': id, 'mensagem': 'Sem internet: a comanda fica guardada e vai assim que voltar'});
      return false;
    } on FirebaseException catch (e) {
      await _fila.invokeMethod('falhou', {'id': id, 'mensagem': 'Erro ao gravar comanda (${e.code}); tentando de novo depois'});
      return false;
    }
  }

  Future<Map<String, dynamic>> _dadosLoja(String uidLoja) async {
    if (_loja == null || DateTime.now().difference(_lojaLidaEm).inMinutes >= 5) {
      final s = await db.doc('lojistas/$uidLoja').get().timeout(const Duration(seconds: 20));
      _loja = s.data() ?? {};
      _lojaLidaEm = DateTime.now();
    }
    return _loja!;
  }

  Ponto? _ponto(Object? lat, Object? lng) =>
      lat is num && lng is num ? Ponto(lat.toDouble(), lng.toDouble()) : null;

  /// O mesmo número de pedido nos últimos 30 minutos = reimpressão.
  Future<bool> _jaRecebida(String uidLoja, String numero) async {
    final q = await db
        .collection('lojistas/$uidLoja/comandas')
        .where('numero', isEqualTo: numero)
        .limit(5)
        .get()
        .timeout(const Duration(seconds: 20));
    final limite = DateTime.now().subtract(const Duration(minutes: 30));
    return q.docs.any((d) => (d.data()['criadoEm'] as Timestamp?)?.toDate().isAfter(limite) ?? true);
  }

  Future<String> _cidade(Ponto? loja) async {
    if (_cidadeLoja != null || loja == null) return _cidadeLoja ?? '';
    try {
      final p = (await placemarkFromCoordinates(loja.lat, loja.lng)).first;
      _cidadeLoja = [p.subAdministrativeArea ?? p.locality, p.administrativeArea].where((s) => s != null && s.isNotEmpty).join(' - ');
    } catch (_) {
      _cidadeLoja = '';
    }
    return _cidadeLoja!;
  }

  /// Endereço → coordenada, preferindo resultados perto da loja (até 60 km).
  Future<Ponto?> _localizar(ComandaExtraida c, Ponto? loja) async {
    if (c.endereco.isEmpty) return null;
    final cidade = c.cidade.isNotEmpty ? '' : await _cidade(loja);
    final tentativas = [
      [c.enderecoParaMapa, cidade].where((s) => s.isNotEmpty).join(', '),
      [c.endereco, c.bairro, cidade].where((s) => s.isNotEmpty).join(', '),
      [c.endereco, cidade].where((s) => s.isNotEmpty).join(', '),
    ];
    for (final t in tentativas.toSet()) {
      try {
        final r = await locationFromAddress('$t, Brasil');
        final pontos = r.map((l) => Ponto(l.latitude, l.longitude)).toList();
        if (pontos.isEmpty) continue;
        if (loja == null) return pontos.first;
        pontos.sort((a, b) => distanciaKm(loja, a).compareTo(distanciaKm(loja, b)));
        if (distanciaKm(loja, pontos.first) <= 60) return pontos.first;
      } catch (_) {
        // endereço não encontrado: tenta a próxima forma
      }
    }
    return null;
  }

  bool _ehDaLoja(ComandaExtraida c, Ponto? ponto, Map<String, dynamic> loja, Ponto? pontoLoja) {
    if (ponto != null && pontoLoja != null && distanciaKm(ponto, pontoLoja) < 0.08) return true;
    final rua = normalizar(c.endereco.split(',').first).trim();
    return rua.length > 4 && normalizar(loja['endereco'] as String? ?? '').contains(rua);
  }

  Future<void> _envioAutomatico(
    String id,
    Map<String, dynamic> doc,
    ComandaExtraida c,
    Ponto? ponto,
    Ponto? loja,
    Map<String, dynamic> config,
  ) async {
    if (config['envioAutomatico'] != true || ponto == null || loja == null) return;
    if (c.confianca < 0.9 || c.enderecoDoTopo || c.tipo != TipoComanda.entrega) return;
    final valor = valorSugerido(config, distanciaKm(loja, ponto));
    if (valor == null) return;
    try {
      await chamar('enviarPedidos', {
        'itens': [itemDeComanda(id, doc, valor)],
        'juntas': false,
      });
    } catch (_) {
      // fica pendente para a loja enviar na mão
    }
  }

  /// Cupom impresso como imagem: reconhece o texto no próprio celular.
  Future<String> _ocr(ImagemRaster img) async {
    final reconhecedor = TextRecognizer(script: TextRecognitionScript.latin);
    final pasta = await Directory.systemTemp.createTemp('rj_ocr');
    final linhas = <String>[];
    try {
      // imagens muito altas são lidas em partes (o OCR reduz imagens grandes)
      const faixa = 900, sobra = 40;
      for (var y = 0; y < img.altura; y += faixa) {
        final ate = (y + faixa + sobra).clamp(0, img.altura);
        final parte = _recortar(img, y, ate);
        final arquivo = File('${pasta.path}/p$y.png')..writeAsBytesSync(pngDaImagem(parte));
        final r = await reconhecedor.processImage(InputImage.fromFilePath(arquivo.path));
        for (final l in _linhasOrdenadas(r)) {
          if (linhas.isEmpty || linhas.last != l) linhas.add(l);
        }
      }
    } finally {
      await reconhecedor.close();
      try {
        await pasta.delete(recursive: true);
      } catch (_) {}
    }
    return linhas.join('\n');
  }

  ImagemRaster _recortar(ImagemRaster img, int de, int ate) {
    final bpl = img.bytesPorLinha;
    return ImagemRaster(img.largura, ate - de, Uint8List.sublistView(img.bits, de * bpl, ate * bpl));
  }

  /// Junta palavras na mesma altura numa linha só ("Cliente:" + "Maria"),
  /// da esquerda para a direita, de cima para baixo.
  List<String> _linhasOrdenadas(RecognizedText r) {
    final todas = [for (final b in r.blocks) ...b.lines]..sort((a, b) => a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));
    final grupos = <List<TextLine>>[];
    for (final l in todas) {
      final g = grupos.isEmpty ? null : grupos.last;
      if (g != null && (l.boundingBox.center.dy - g.first.boundingBox.center.dy).abs() < l.boundingBox.height * 0.6) {
        g.add(l);
      } else {
        grupos.add([l]);
      }
    }
    return [
      for (final g in grupos) (g..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left))).map((l) => l.text).join('   '),
    ];
  }
}
