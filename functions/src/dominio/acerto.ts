// Mini sistema financeiro loja ↔ entregador (só números, sem dinheiro).
// Saldo positivo = a loja deve ao entregador.

export type TipoLancamento = "entrega" | "pagamento" | "repasse" | "estorno" | "ajuste";
export type StatusPagamento = "pendente" | "confirmado" | "contestado";

export interface Lancamento {
  id: string;
  tipo: TipoLancamento;
  /** sempre positivo, exceto em "ajuste" (sinal = efeito no saldo) */
  valorCentavos: number;
  status?: StatusPagamento;
  /** em "estorno", o lançamento desfeito */
  estornaId?: string;
}

export interface Acerto {
  entregasCentavos: number;
  pagosCentavos: number;
  pendentesCentavos: number;
  contestadosCentavos: number;
  repassesCentavos: number;
  ajustesCentavos: number;
  saldoCentavos: number;
}

/** Efeito de um lançamento no saldo (loja → entregador). */
export function efeitoNoSaldo(l: Lancamento): number {
  switch (l.tipo) {
    case "entrega":
      return l.valorCentavos;
    case "pagamento":
      return l.status === "confirmado" ? -l.valorCentavos : 0;
    case "repasse":
      return -l.valorCentavos;
    case "ajuste":
      return l.valorCentavos;
    case "estorno":
      return 0; // tratado em calcularAcerto
  }
}

export function calcularAcerto(lancamentos: Lancamento[]): Acerto {
  const estornados = new Set(
    lancamentos.filter((l) => l.tipo === "estorno" && l.estornaId).map((l) => l.estornaId!),
  );
  const a: Acerto = {
    entregasCentavos: 0,
    pagosCentavos: 0,
    pendentesCentavos: 0,
    contestadosCentavos: 0,
    repassesCentavos: 0,
    ajustesCentavos: 0,
    saldoCentavos: 0,
  };
  for (const l of lancamentos) {
    if (l.tipo === "estorno" || estornados.has(l.id)) continue;
    if (l.tipo === "entrega") a.entregasCentavos += l.valorCentavos;
    if (l.tipo === "repasse") a.repassesCentavos += l.valorCentavos;
    if (l.tipo === "ajuste") a.ajustesCentavos += l.valorCentavos;
    if (l.tipo === "pagamento") {
      if (l.status === "confirmado") a.pagosCentavos += l.valorCentavos;
      else if (l.status === "contestado") a.contestadosCentavos += l.valorCentavos;
      else a.pendentesCentavos += l.valorCentavos;
    }
    a.saldoCentavos += efeitoNoSaldo(l);
  }
  return a;
}
