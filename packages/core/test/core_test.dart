
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

  group('geo', () {
    test('geohash conhecido', () {
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
