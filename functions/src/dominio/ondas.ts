// Planejamento das ondas de oferta de um lote.

import type { Onda } from "./parametros.ts";
import type { Candidato, Pontuado } from "./score.ts";
import type { Pesos } from "./parametros.ts";
import { ranquear } from "./score.ts";

export type ModoDespacho = "geral" | "equipe" | "equipe_primeiro";

export interface PlanoOnda {
  /** número da onda (0 = equipe, quando existir) */
  numero: number;
  tipo: "equipe" | "geral" | "fim";
  ofertar: Pontuado[];
  raioKm: number;
  segundos: number;
}

export interface EntradaOnda {
  numero: number;
  modo: ModoDespacho;
  /** candidatos do sistema geral (já filtrados por disponibilidade) */
  geral: Candidato[];
  /** candidatos da equipe própria da loja que estão online */
  equipe: Candidato[];
  jaOfertados: Set<string>;
  ondas: Onda[];
  pesos: Pesos;
  segundosPorOnda: number;
  esperaEquipeSeg: number;
  agoraMs: number;
}

/**
 * Decide quem recebe a oferta na onda `numero`.
 * - modo "equipe": só a equipe, uma onda com todos ao mesmo tempo.
 * - modo "equipe_primeiro": onda 0 é a equipe; depois as ondas gerais.
 *   Se não há ninguém da equipe online, pula direto para as gerais.
 * - modo "geral": só as ondas gerais.
 * Ondas sem candidato novo são puladas; acabou a lista, tipo "fim".
 */
export function planejarOnda(e: EntradaOnda): PlanoOnda {
  const usaEquipe = e.modo !== "geral";
  const offset = usaEquipe ? 1 : 0;

  if (usaEquipe && e.numero === 0) {
    const equipe = ranquear(e.equipe, Number.POSITIVE_INFINITY, e.pesos, e.agoraMs).filter(
      (p) => !e.jaOfertados.has(p.id),
    );
    if (equipe.length) {
      return { numero: 0, tipo: "equipe", ofertar: equipe, raioKm: Infinity, segundos: e.esperaEquipeSeg };
    }
    if (e.modo === "equipe") return fim(0);
    return planejarOnda({ ...e, numero: 1 });
  }
  if (e.modo === "equipe") return fim(e.numero);

  for (let n = e.numero; n - offset < e.ondas.length; n++) {
    const onda = e.ondas[n - offset];
    const novos = ranquear(e.geral, onda.raioKm, e.pesos, e.agoraMs).filter(
      (p) => !e.jaOfertados.has(p.id),
    );
    if (novos.length) {
      return {
        numero: n,
        tipo: "geral",
        ofertar: novos.slice(0, onda.tamanho),
        raioKm: onda.raioKm,
        segundos: e.segundosPorOnda,
      };
    }
  }
  return fim(e.numero);
}

function fim(numero: number): PlanoOnda {
  return { numero, tipo: "fim", ofertar: [], raioKm: 0, segundos: 0 };
}

/** Maior raio usado pelas ondas: define até onde buscar candidatos. */
export function raioMaximoKm(ondas: Onda[]): number {
  return ondas.reduce((m, o) => Math.max(m, o.raioKm), 0);
}
