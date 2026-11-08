import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacao/tema.dart';
import 'package:operacao/widgets/comum.dart';

void main() {
  testWidgets('componentes básicos renderizam com o tema da marca', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: temaRodaJusta(Brightness.light),
      home: const Scaffold(
        body: Column(children: [
          Marca(tamanho: 48),
          LinhaValor('Total a pagar', 'R\$ 12,00', destaque: true),
          Expanded(child: Vazio('Nada por aqui')),
        ]),
      ),
    ));
    expect(find.text('Total a pagar'), findsOneWidget);
    expect(find.text('R\$ 12,00'), findsOneWidget);
    expect(find.text('Nada por aqui'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  test('cor primária é o verde da marca', () {
    expect(temaRodaJusta(Brightness.light).colorScheme.primary, Cores.verde);
  });
}
