/// Valor da entrega a partir da configuração da loja.
/// Devolve null quando a loja escolheu digitar o valor a cada envio.
int? valorSugerido(Map<String, dynamic>? config, double distanciaKm) {
  if (config == null) return null;
  switch (config['valorModo']) {
    case 'fixo':
      return (config['valorFixoCentavos'] as num?)?.toInt();
    case 'faixas':
      final faixas = ((config['faixas'] as List?) ?? [])
          .whereType<Map>()
          .map((f) => (ateKm: (f['ateKm'] as num).toDouble(), valor: (f['valorCentavos'] as num).toInt()))
          .toList()
        ..sort((a, b) => a.ateKm.compareTo(b.ateKm));
      for (final f in faixas) {
        if (distanciaKm <= f.ateKm) return f.valor;
      }
      return faixas.isEmpty ? null : faixas.last.valor;
    default:
      return null;
  }
}
