import 'dart:math' as math;

class Ponto {
  const Ponto(this.lat, this.lng);
  final double lat;
  final double lng;
}

double distanciaKm(Ponto a, Ponto b) {
  double rad(double g) => g * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * 6371.0088 * math.asin(math.min(1, math.sqrt(h)));
}

const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/// Geohash (mesmo algoritmo do geofire-common usado no servidor).
String geohash(double lat, double lng, {int precisao = 10}) {
  var latMin = -90.0, latMax = 90.0, lngMin = -180.0, lngMax = 180.0;
  final buf = StringBuffer();
  var bit = 0, ch = 0;
  var pareLng = true;
  while (buf.length < precisao) {
    if (pareLng) {
      final meio = (lngMin + lngMax) / 2;
      if (lng >= meio) {
        ch = (ch << 1) | 1;
        lngMin = meio;
      } else {
        ch = ch << 1;
        lngMax = meio;
      }
    } else {
      final meio = (latMin + latMax) / 2;
      if (lat >= meio) {
        ch = (ch << 1) | 1;
        latMin = meio;
      } else {
        ch = ch << 1;
        latMax = meio;
      }
    }
    pareLng = !pareLng;
    if (++bit == 5) {
      buf.write(_base32[ch]);
      bit = 0;
      ch = 0;
    }
  }
  return buf.toString();
}

/// Sugere agrupamentos de comandas na mesma direção (igual ao servidor).
List<List<String>> sugerirAgrupamentos(
  Ponto loja,
  Map<String, Ponto> destinos, {
  int maximo = 3,
  double desvioMaxKm = 2,
}) {
  final restantes = destinos.keys.toList()
    ..sort((a, b) => distanciaKm(loja, destinos[b]!).compareTo(distanciaKm(loja, destinos[a]!)));
  final grupos = <List<String>>[];
  while (restantes.isNotEmpty) {
    final grupo = [restantes.removeAt(0)];
    var i = 0;
    while (i < restantes.length && grupo.length < maximo) {
      final tentativa = [...grupo, restantes[i]];
      if (desvioKm(loja, tentativa.map((id) => destinos[id]!).toList()) <= desvioMaxKm) {
        grupo.add(restantes.removeAt(i));
      } else {
        i++;
      }
    }
    grupos.add(grupo);
  }
  return grupos;
}

double desvioKm(Ponto loja, List<Ponto> destinos) {
  if (destinos.length <= 1) return 0;
  final restantes = [...destinos];
  var atual = loja;
  var percurso = 0.0;
  while (restantes.isNotEmpty) {
    restantes.sort((a, b) => distanciaKm(atual, a).compareTo(distanciaKm(atual, b)));
    final prox = restantes.removeAt(0);
    percurso += distanciaKm(atual, prox);
    atual = prox;
  }
  final maisLonge = destinos.map((d) => distanciaKm(loja, d)).reduce(math.max);
  return percurso - maisLonge;
}
