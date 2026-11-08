import 'package:admin/telas/entregadores.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gini: todos iguais = 0; um leva tudo = alto', () {
    expect(Entregadores.gini([2, 2, 2, 2]), 0);
    expect(Entregadores.gini([0, 0, 0, 8]), closeTo(0.75, 1e-9));
    expect(Entregadores.gini([]), 0);
  });
}
