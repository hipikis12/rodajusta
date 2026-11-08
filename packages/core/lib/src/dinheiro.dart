/// Valores em centavos (inteiros) para evitar erro de arredondamento.

String formatarReais(int centavos) {
  final negativo = centavos < 0;
  final abs = centavos.abs();
  final reais = abs ~/ 100;
  final cent = (abs % 100).toString().padLeft(2, '0');
  final s = reais.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${negativo ? '-' : ''}R\$ $buf,$cent';
}

/// Lê "R$ 1.234,56", "12,5", "7" ou "7.50" e devolve centavos.
int? lerReais(String texto) {
  var t = texto.replaceAll(RegExp(r'[R$\s]'), '');
  if (t.isEmpty) return null;
  if (t.contains(',')) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t)) {
    t = t.replaceAll('.', ''); // "1.234" = mil duzentos e trinta e quatro
  }
  final v = double.tryParse(t);
  if (v == null || v < 0) return null;
  return (v * 100).round();
}
