// Gatilhos de incentivo a partir das métricas da zona.

import type { Parametros } from "./parametros.ts";

export interface Medicao {
  pedidos: number;
  entregadoresOnline: number;
  aceiteMedioSeg: number | null;
  chuvaProximaHoraMm: number | null;
}

export interface EntradaGatilhos {
  zonaId: string;
  atual: Medicao;
  anterior: Medicao | null;
  /** média das últimas semanas, mesmo dia da semana e hora (amanhã) */
  previsaoAmanha: { pedidos: number; entregadores: number } | null;
  /** quantas medições seguidas a razão pedidos/entregador ficou baixa */
  medicoesEmExcesso: number;
  gatilhos: Parametros["gatilhos"];
}

export type TipoIncentivo = "chuva" | "baixa_oferta" | "dia_fraco" | "rodizio";

export interface Sugestao {
  tipo: TipoIncentivo;
  modo: "desconto" | "bonus" | "rodizio";
  percentual: number;
  minimoEntregas: number;
  zonaId: string;
  motivo: string;
}

export function razao(m: Medicao): number {
  if (m.entregadoresOnline <= 0) return m.pedidos > 0 ? Infinity : 0;
  return m.pedidos / m.entregadoresOnline;
}

function emFalta(m: Medicao, g: Parametros["gatilhos"]): boolean {
  return razao(m) >= g.faltaRazao || (m.aceiteMedioSeg ?? 0) >= g.faltaAceiteSeg;
}

export function avaliarGatilhos(e: EntradaGatilhos): Sugestao[] {
  const g = e.gatilhos;
  const out: Sugestao[] = [];
  const chuva = e.atual.chuvaProximaHoraMm ?? 0;

  if (chuva >= g.chuvaMmH) {
    out.push({
      tipo: "chuva",
      modo: "desconto",
      percentual: g.chuvaDescontoPct,
      minimoEntregas: 0,
      zonaId: e.zonaId,
      motivo: `Chuva prevista de ${chuva.toFixed(1)} mm/h na próxima hora`,
    });
  }

  // falta de entregadores: duas medições seguidas (evita alarme por pico isolado)
  if (e.anterior && emFalta(e.atual, g) && emFalta(e.anterior, g)) {
    const r = razao(e.atual);
    out.push({
      tipo: "baixa_oferta",
      modo: "desconto",
      percentual: g.faltaDescontoPct,
      minimoEntregas: 0,
      zonaId: e.zonaId,
      motivo: Number.isFinite(r)
        ? `${r.toFixed(1)} pedidos por entregador online`
        : "Pedidos sem nenhum entregador online",
    });
  }

  if (e.previsaoAmanha && e.previsaoAmanha.entregadores < e.previsaoAmanha.pedidos) {
    out.push({
      tipo: "dia_fraco",
      modo: "bonus",
      percentual: g.diaFracoBonusPct,
      minimoEntregas: g.diaFracoMinEntregas,
      zonaId: e.zonaId,
      motivo: `Previsão para amanhã: ${Math.round(e.previsaoAmanha.pedidos)} pedidos para ${Math.round(e.previsaoAmanha.entregadores)} entregadores`,
    });
  }

  // excesso de entregadores por 1 hora (4 medições de 15 min)
  if (e.medicoesEmExcesso >= 4 && razao(e.atual) <= g.excessoRazao) {
    out.push({
      tipo: "rodizio",
      modo: "rodizio",
      percentual: 0,
      minimoEntregas: 0,
      zonaId: e.zonaId,
      motivo: "Muitos entregadores para poucos pedidos há 1 hora: abrir turnos de rodízio",
    });
  }
  return out;
}
