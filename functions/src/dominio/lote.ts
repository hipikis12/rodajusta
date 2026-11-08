// Lotes: várias comandas da mesma loja levadas pelo mesmo entregador.

import type { Ponto } from "./geo.ts";
import { comprimentoPercursoKm, distanciaKm, ordemVizinhoMaisProximo } from "./geo.ts";

export interface PedidoLote {
  id: string;
  lojistaId: string;
  destino: Ponto;
}

export type ErroLote = "vazio" | "lojas_diferentes" | "acima_do_maximo";

export function validarLote(pedidos: PedidoLote[], maximo: number): ErroLote | null {
  if (!pedidos.length) return "vazio";
  if (new Set(pedidos.map((p) => p.lojistaId)).size > 1) return "lojas_diferentes";
  if (pedidos.length > maximo) return "acima_do_maximo";
  return null;
}

/**
 * Desvio de um lote: quanto o percurso completo (loja → destinos na melhor
 * ordem) é maior que ir só até o destino mais distante.
 */
export function desvioKm(loja: Ponto, destinos: Ponto[]): number {
  if (destinos.length <= 1) return 0;
  const ordem = ordemVizinhoMaisProximo(loja, destinos);
  const percurso = comprimentoPercursoKm([loja, ...ordem.map((i) => destinos[i])]);
  const maisLonge = Math.max(...destinos.map((d) => distanciaKm(loja, d)));
  return percurso - maisLonge;
}

/**
 * Sugere agrupamentos para as comandas prontas: começa pelo destino mais
 * distante e vai juntando os que mantêm o desvio dentro do limite.
 * Devolve grupos de ids (grupos de 1 = enviar sozinho).
 */
export function sugerirAgrupamentos(
  loja: Ponto,
  pedidos: PedidoLote[],
  maximo: number,
  desvioMaxKm: number,
): string[][] {
  const restantes = [...pedidos].sort(
    (a, b) => distanciaKm(loja, b.destino) - distanciaKm(loja, a.destino),
  );
  const grupos: string[][] = [];
  while (restantes.length) {
    const base = restantes.shift()!;
    const grupo = [base];
    for (let i = 0; i < restantes.length && grupo.length < maximo; ) {
      const tentativa = [...grupo, restantes[i]];
      if (desvioKm(loja, tentativa.map((p) => p.destino)) <= desvioMaxKm) {
        grupo.push(restantes.splice(i, 1)[0]);
      } else {
        i++;
      }
    }
    grupos.push(grupo.map((p) => p.id));
  }
  return grupos;
}
