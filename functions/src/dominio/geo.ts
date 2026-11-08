export interface Ponto {
  lat: number;
  lng: number;
}

const RAIO_TERRA_KM = 6371.0088;

export function distanciaKm(a: Ponto, b: Ponto): number {
  const rad = (g: number) => (g * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * RAIO_TERRA_KM * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Comprimento de um percurso que passa pelos pontos na ordem dada. */
export function comprimentoPercursoKm(pontos: Ponto[]): number {
  let total = 0;
  for (let i = 1; i < pontos.length; i++) total += distanciaKm(pontos[i - 1], pontos[i]);
  return total;
}

/**
 * Ordem de visita pelo vizinho mais próximo partindo da origem.
 * Devolve os índices de `destinos`. Para lotes pequenos (até ~5) fica
 * praticamente igual ao ótimo; a Routes API pode refinar depois.
 */
export function ordemVizinhoMaisProximo(origem: Ponto, destinos: Ponto[]): number[] {
  const restantes = destinos.map((_, i) => i);
  const ordem: number[] = [];
  let atual = origem;
  while (restantes.length) {
    let melhor = 0;
    for (let k = 1; k < restantes.length; k++) {
      if (distanciaKm(atual, destinos[restantes[k]]) < distanciaKm(atual, destinos[restantes[melhor]])) {
        melhor = k;
      }
    }
    const idx = restantes.splice(melhor, 1)[0];
    ordem.push(idx);
    atual = destinos[idx];
  }
  return ordem;
}
