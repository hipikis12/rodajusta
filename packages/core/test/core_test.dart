import 'dart:convert';

import 'package:rodajusta_core/rodajusta_core.dart';
import 'package:test/test.dart';

void main() {
  group('dinheiro', () {
    test('formata', () {
      expect(formatarReais(0), 'R\$ 0,00');
      expect(formatarReais(80), 'R\$ 0,80');
      expect(formatarReais(123456), 'R\$ 1.234,56');
      expect(formatarReais(-700), '-R\$ 7,00');
    });
    test('lê', () {
      expect(lerReais('R\$ 1.234,56'), 123456);
      expect(lerReais('7'), 700);
      expect(lerReais('7,5'), 750);
      expect(lerReais('7.50'), 750);
      expect(lerReais('1.234'), 123400);
      expect(lerReais(''), null);
      expect(lerReais('abc'), null);
    });
  });

  group('ESC/POS', () {
    test('remove comandos e mantém o texto', () {
      final bytes = <int>[
        0x1B, 0x40, // inicializa
        0x1B, 0x61, 0x01, // centraliza
        0x1B, 0x45, 0x01, // negrito
        ...latin1.encode('PEDIDO 482\n'),
        0x1B, 0x45, 0x00,
        ...latin1.encode('Endereço: Rua A, 10\n'),
        0x1D, 0x56, 0x41, 0x03, // corte
      ];
      expect(decodificarEscPos(bytes), 'PEDIDO 482\nEndereço: Rua A, 10\n');
    });
    test('pula imagem raster e QR code', () {
      final bytes = <int>[
        ...ascii.encode('A\n'),
        0x1D, 0x76, 0x30, 0x00, 0x02, 0x00, 0x02, 0x00, 1, 2, 3, 4, // 2x2 bytes
        0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x05, // QR: tamanho
        ...ascii.encode('B\n'),
      ];
      expect(decodificarEscPos(bytes), 'A\nB\n');
    });
    test('decodifica CP850', () {
      // "Endereço São" em CP850: ç = 0x87, ã = 0xC6
      final bytes = [...ascii.encode('Endere'), 0x87, ...ascii.encode('o S'), 0xC6, ...ascii.encode('o')];
      expect(decodificarEscPos(bytes), 'Endereço São');
    });
    test('aceita UTF-8', () {
      expect(decodificarEscPos(utf8.encode('Açaí')), 'Açaí');
    });
  });

  group('comanda', () {
    const exemplo = '''
      PIZZARIA SOL
    ------------------------------
    PEDIDO Nº 482      07/11 19:42
    Cliente: Maria Souza
    Tel: (69) 99999-1234
    Endereço: Rua Tiradentes, 1520 - Setor 03
    Complemento: Casa dos fundos
    Ref: Próximo à escola
    ------------------------------
    2x Pizza Calabresa G      89,80
    1 x Refrigerante 2L       12,00
    Subtotal                 101,80
    Taxa de entrega            7,00
    TOTAL                R\$ 108,80
    Pagamento: Dinheiro - troco para R\$ 150,00
    ''';

    test('extrai os campos principais', () {
      final c = extrairComanda(exemplo);
      expect(c.numero, '482');
      expect(c.cliente, 'Maria Souza');
      expect(c.telefone, '69999991234');
      expect(c.endereco, 'Rua Tiradentes, 1520');
      expect(c.bairro, 'Setor 03');
      expect(c.complemento, 'Casa dos fundos');
      expect(c.referencia, 'Próximo à escola');
      expect(c.itens, ['2x Pizza Calabresa G', '1x Refrigerante 2L']);
      expect(c.taxaEntregaCentavos, 700);
      expect(c.totalCentavos, 10880);
      expect(c.cobrar, isTrue);
      expect(c.trocoParaCentavos, 15000);
      expect(c.confianca, greaterThanOrEqualTo(0.9));
      expect(c.descricao, '#482 · Maria · 2x Pizza Calabresa G +1 · R\$ 108,80');
    });

    test('bairro em linha própria e pedido pago', () {
      final c = extrairComanda('''
Comanda 17
Nome: João
Av. Canaã, 2000
Bairro: Jardim Jorge Teixeira
Total: 45,00
Pago no app
''');
      expect(c.numero, '17');
      expect(c.endereco, 'Av. Canaã, 2000');
      expect(c.bairro, 'Jardim Jorge Teixeira');
      expect(c.totalCentavos, 4500);
      expect(c.cobrar, isFalse);
    });

    test('sem endereço tem confiança baixa', () {
      expect(extrairComanda('Mesa 4\n1x Café 5,00').confianca, lessThan(0.5));
    });
  });

  group('geo', () {
    test('geohash conhecido', () {
      // valor de referência do algoritmo padrão
      expect(geohash(57.64911, 10.40744, precisao: 11), 'u4pruydqqvj');
    });
    test('distância de 1 km', () {
      const a = Ponto(-9.9133, -63.0408);
      final b = Ponto(-9.9133 + 1 / 111.2, -63.0408);
      expect((distanciaKm(a, b) - 1).abs(), lessThan(0.01));
    });
    test('agrupa a mesma direção', () {
      const loja = Ponto(-9.9133, -63.0408);
      Ponto norte(double km) => Ponto(loja.lat + km / 111.2, loja.lng);
      final g = sugerirAgrupamentos(loja, {'n2': norte(2), 'n3': norte(3), 's2': norte(-2)});
      expect(g, [
        ['n3', 'n2'],
        ['s2'],
      ]);
    });
  });

  group('valor da entrega', () {
    test('fixo, faixas e manual', () {
      expect(valorSugerido({'valorModo': 'fixo', 'valorFixoCentavos': 700}, 5), 700);
      final faixas = {
        'valorModo': 'faixas',
        'faixas': [
          {'ateKm': 6, 'valorCentavos': 900},
          {'ateKm': 3, 'valorCentavos': 600},
        ],
      };
      expect(valorSugerido(faixas, 2), 600);
      expect(valorSugerido(faixas, 4), 900);
      expect(valorSugerido(faixas, 10), 900);
      expect(valorSugerido({'valorModo': 'manual'}, 2), isNull);
    });
  });
}
