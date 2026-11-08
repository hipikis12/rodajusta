// Pontuação de distribuição: proximidade + justiça.
// S = wd(1 - d/R) + we·min(espera/60, 1) + wj(1 - h/hmax) + wr·T - wp·P

import type { Pesos } from "./parametros.ts";

export interface Candidato {
  id: string;
  distanciaKm: number;
  minutosEsperando: number;
  /** entregas por hora online hoje */
  entregasPorHora: number;
  noTurno: boolean;
  /** horários (ms) das recusas recentes */
  recusas: number[];
}

export interface Componentes {
  distancia: number;
  espera: number;
  equidade: number;
  rodizio: number;
  penalidade: number;
}

export interface Pontuado {
  id: string;
  score: number;
  componentes: Componentes;
}

const MEIA_VIDA_RECUSA_MIN = 30;
const PESO_POR_RECUSA = 1 / 3; // três recusas na hora = penalidade cheia

export function penalidadeRecusas(recusas: number[], agoraMs: number): number {
  let soma = 0;
  for (const t of recusas) {
    const idadeMin = Math.max(0, (agoraMs - t) / 60000);
    soma += PESO_POR_RECUSA * Math.pow(0.5, idadeMin / MEIA_VIDA_RECUSA_MIN);
  }
  return Math.min(1, soma);
}

export function entregasPorHora(entregasHoje: number, minutosOnlineHoje: number): number {
  // meia hora mínima para quem acabou de entrar não ficar com taxa inflada
  const horas = Math.max(minutosOnlineHoje, 30) / 60;
  return entregasHoje / horas;
}

const limitar = (v: number) => Math.max(0, Math.min(1, v));

export function pontuar(
  c: Candidato,
  raioKm: number,
  maxEntregasPorHora: number,
  pesos: Pesos,
  agoraMs: number,
): Pontuado {
  const componentes: Componentes = {
    distancia: limitar(1 - c.distanciaKm / raioKm),
    espera: limitar(c.minutosEsperando / 60),
    equidade: maxEntregasPorHora > 0 ? limitar(1 - c.entregasPorHora / maxEntregasPorHora) : 1,
    rodizio: c.noTurno ? 1 : 0,
    penalidade: penalidadeRecusas(c.recusas, agoraMs),
  };
  const score =
    pesos.distancia * componentes.distancia +
    pesos.espera * componentes.espera +
    pesos.equidade * componentes.equidade +
    pesos.rodizio * componentes.rodizio -
    pesos.penalidade * componentes.penalidade;
  return { id: c.id, score: Math.round(score * 10000) / 10000, componentes };
}

/**
 * Ordena os candidatos dentro do raio, do maior para o menor score.
 * Empate: quem espera há mais tempo; depois o id (ordem estável).
 */
export function ranquear(
  candidatos: Candidato[],
  raioKm: number,
  pesos: Pesos,
  agoraMs: number,
): Pontuado[] {
  const dentro = candidatos.filter((c) => c.distanciaKm <= raioKm);
  const maxH = dentro.reduce((m, c) => Math.max(m, c.entregasPorHora), 0);
  const espera = new Map(dentro.map((c) => [c.id, c.minutosEsperando]));
  return dentro
    .map((c) => pontuar(c, raioKm, maxH, pesos, agoraMs))
    .sort(
      (a, b) =>
        b.score - a.score ||
        (espera.get(b.id) ?? 0) - (espera.get(a.id) ?? 0) ||
        a.id.localeCompare(b.id),
    );
}

/** Coeficiente de Gini (0 = todos iguais, 1 = um só leva tudo). */
export function gini(valores: number[]): number {
  const v = valores.filter((x) => x >= 0).sort((a, b) => a - b);
  const n = v.length;
  const soma = v.reduce((s, x) => s + x, 0);
  if (n === 0 || soma === 0) return 0;
  let acumulado = 0;
  for (let i = 0; i < n; i++) acumulado += (i + 1) * v[i];
  return (2 * acumulado) / (n * soma) - (n + 1) / n;
}
