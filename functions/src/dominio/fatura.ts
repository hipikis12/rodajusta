// Fatura mensal do entregador com a plataforma. O sistema não movimenta
// dinheiro: só calcula; o pagamento é feito por fora e o Admin dá baixa.

export type Plano = "por_entrega" | "mensal";

export interface EntradaFatura {
  plano: Plano;
  entregas: number;
  creditosCentavos: number;
  porEntregaCentavos: number;
  mensalCentavos: number;
  isento: boolean;
}

export interface ResultadoFatura {
  brutoCentavos: number;
  creditosAplicadosCentavos: number;
  totalCentavos: number;
}

export function calcularFatura(e: EntradaFatura): ResultadoFatura {
  if (e.isento) return { brutoCentavos: 0, creditosAplicadosCentavos: 0, totalCentavos: 0 };
  const bruto =
    e.plano === "mensal" ? (e.entregas > 0 ? e.mensalCentavos : 0) : e.entregas * e.porEntregaCentavos;
  // créditos nunca deixam a fatura negativa (no mensal, no máximo a mensalidade)
  const creditos = Math.max(0, Math.min(Math.round(e.creditosCentavos), bruto));
  return { brutoCentavos: bruto, creditosAplicadosCentavos: creditos, totalCentavos: bruto - creditos };
}

/** A partir de quantas entregas no mês o plano mensal fica mais barato. */
export function entregasParaCompensarMensal(porEntregaCentavos: number, mensalCentavos: number): number {
  if (porEntregaCentavos <= 0) return Infinity;
  return Math.ceil(mensalCentavos / porEntregaCentavos);
}

/** Crédito por uma entrega feita dentro de uma janela de desconto. */
export function creditoDesconto(percentual: number, porEntregaCentavos: number): number {
  const pct = Math.max(0, Math.min(100, percentual));
  return Math.round((porEntregaCentavos * pct) / 100);
}

/**
 * Bônus semanal: quem atingiu o mínimo de entregas na janela ganha X% das
 * taxas que gerou na semana. No mensal a base é um quarto da mensalidade.
 */
export function creditoBonusSemanal(p: {
  plano: Plano;
  percentual: number;
  entregasNaJanela: number;
  minimoEntregas: number;
  entregasNaSemana: number;
  porEntregaCentavos: number;
  mensalCentavos: number;
}): number {
  if (p.entregasNaJanela < p.minimoEntregas) return 0;
  const base =
    p.plano === "mensal" ? p.mensalCentavos / 4 : p.entregasNaSemana * p.porEntregaCentavos;
  const pct = Math.max(0, Math.min(100, p.percentual));
  return Math.round((base * pct) / 100);
}

/** Situação da fatura considerando vencimento e prazo para bloqueio. */
export function situacaoFatura(
  status: "aberta" | "fechada" | "paga" | "vencida",
  vencimentoMs: number | null,
  agoraMs: number,
  diasAtrasoBloqueio: number,
): { vencida: boolean; bloqueia: boolean } {
  if (status === "paga" || status === "aberta" || vencimentoMs === null) {
    return { vencida: false, bloqueia: false };
  }
  const atrasoDias = (agoraMs - vencimentoMs) / 86400000;
  return { vencida: atrasoDias > 0, bloqueia: atrasoDias > diasAtrasoBloqueio };
}
