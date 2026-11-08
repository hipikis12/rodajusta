// Link de rota para o Google Maps (Maps URLs, sem chave de API).

import type { Ponto } from "./geo.ts";
import { ordemVizinhoMaisProximo } from "./geo.ts";

const fmt = (p: Ponto) => `${p.lat.toFixed(6)},${p.lng.toFixed(6)}`;

/**
 * Monta o link com as paradas na ordem dada. Sem origem, o Maps parte do
 * GPS atual do entregador. Último ponto = destino; os demais = waypoints.
 */
export function linkRota(paradas: Ponto[], modo: "driving" | "two-wheeler" | "bicycling" = "driving"): string {
  if (!paradas.length) throw new Error("rota sem paradas");
  const destino = paradas[paradas.length - 1];
  const params = new URLSearchParams({ api: "1", destination: fmt(destino), travelmode: modo });
  const meio = paradas.slice(0, -1);
  if (meio.length) params.set("waypoints", meio.map(fmt).join("|"));
  return `https://www.google.com/maps/dir/?${params.toString()}`;
}

/** Ordena as paradas a partir da loja e devolve ordem + link. */
export function rotaDoLote(loja: Ponto, destinos: Ponto[]): { ordem: number[]; url: string } {
  const ordem = ordemVizinhoMaisProximo(loja, destinos);
  return { ordem, url: linkRota(ordem.map((i) => destinos[i])) };
}
