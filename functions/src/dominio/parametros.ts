// Parâmetros do sistema. Os valores padrão abaixo valem até o Admin
// salvar outros em config/parametros (o documento é mesclado por cima).

export interface Pesos {
  distancia: number;
  espera: number;
  equidade: number;
  rodizio: number;
  penalidade: number;
}

export interface Onda {
  tamanho: number; // quantos entregadores recebem a oferta ao mesmo tempo
  raioKm: number;
}

export interface Parametros {
  pesos: Pesos;
  ondas: Onda[];
  segundosPorOnda: number;
  esperaEquipeSeg: number;
  localizacaoValidaSeg: number;
  maxEntregasPorLote: number;
  desvioMaxLoteKm: number;
  raioEntregaM: number;
  segundosInclusao: number;
  taxa: {
    porEntregaCentavos: number;
    mensalCentavos: number;
    diasVencimento: number;
    diasAtrasoBloqueio: number;
  };
  gatilhos: {
    chuvaMmH: number;
    chuvaDescontoPct: number;
    faltaRazao: number;
    faltaAceiteSeg: number;
    faltaDescontoPct: number;
    diaFracoBonusPct: number;
    diaFracoMinEntregas: number;
    excessoRazao: number;
  };
}

export const PADRAO: Parametros = {
  pesos: { distancia: 0.45, espera: 0.25, equidade: 0.2, rodizio: 0.1, penalidade: 0.15 },
  ondas: [
    { tamanho: 1, raioKm: 3 },
    { tamanho: 3, raioKm: 3 },
    { tamanho: 5, raioKm: 5 },
    { tamanho: 5, raioKm: 8 },
  ],
  segundosPorOnda: 30,
  esperaEquipeSeg: 60,
  localizacaoValidaSeg: 120,
  maxEntregasPorLote: 3,
  desvioMaxLoteKm: 2,
  raioEntregaM: 150,
  segundosInclusao: 30,
  taxa: {
    porEntregaCentavos: 80,
    mensalCentavos: 8000,
    diasVencimento: 5,
    diasAtrasoBloqueio: 3,
  },
  gatilhos: {
    chuvaMmH: 2,
    chuvaDescontoPct: 50,
    faltaRazao: 1.5,
    faltaAceiteSeg: 180,
    faltaDescontoPct: 30,
    diaFracoBonusPct: 20,
    diaFracoMinEntregas: 5,
    excessoRazao: 0.3,
  },
};

type Parcial<T> = { [K in keyof T]?: T[K] extends object ? (T[K] extends unknown[] ? T[K] : Parcial<T[K]>) : T[K] };

/** Mescla o documento salvo pelo Admin sobre os padrões, ignorando lixo. */
export function mesclarParametros(salvo: Parcial<Parametros> | undefined | null): Parametros {
  const s = salvo ?? {};
  const num = (v: unknown, d: number) => (typeof v === "number" && Number.isFinite(v) ? v : d);
  const ondasValidas = Array.isArray(s.ondas)
    ? s.ondas.filter((o) => o && num(o.tamanho, 0) >= 1 && num(o.raioKm, 0) > 0)
    : [];
  return {
    pesos: {
      distancia: num(s.pesos?.distancia, PADRAO.pesos.distancia),
      espera: num(s.pesos?.espera, PADRAO.pesos.espera),
      equidade: num(s.pesos?.equidade, PADRAO.pesos.equidade),
      rodizio: num(s.pesos?.rodizio, PADRAO.pesos.rodizio),
      penalidade: num(s.pesos?.penalidade, PADRAO.pesos.penalidade),
    },
    ondas: ondasValidas.length ? ondasValidas : PADRAO.ondas,
    segundosPorOnda: num(s.segundosPorOnda, PADRAO.segundosPorOnda),
    esperaEquipeSeg: num(s.esperaEquipeSeg, PADRAO.esperaEquipeSeg),
    localizacaoValidaSeg: num(s.localizacaoValidaSeg, PADRAO.localizacaoValidaSeg),
    maxEntregasPorLote: Math.max(1, Math.floor(num(s.maxEntregasPorLote, PADRAO.maxEntregasPorLote))),
    desvioMaxLoteKm: num(s.desvioMaxLoteKm, PADRAO.desvioMaxLoteKm),
    raioEntregaM: num(s.raioEntregaM, PADRAO.raioEntregaM),
    segundosInclusao: num(s.segundosInclusao, PADRAO.segundosInclusao),
    taxa: {
      porEntregaCentavos: num(s.taxa?.porEntregaCentavos, PADRAO.taxa.porEntregaCentavos),
      mensalCentavos: num(s.taxa?.mensalCentavos, PADRAO.taxa.mensalCentavos),
      diasVencimento: num(s.taxa?.diasVencimento, PADRAO.taxa.diasVencimento),
      diasAtrasoBloqueio: num(s.taxa?.diasAtrasoBloqueio, PADRAO.taxa.diasAtrasoBloqueio),
    },
    gatilhos: {
      chuvaMmH: num(s.gatilhos?.chuvaMmH, PADRAO.gatilhos.chuvaMmH),
      chuvaDescontoPct: num(s.gatilhos?.chuvaDescontoPct, PADRAO.gatilhos.chuvaDescontoPct),
      faltaRazao: num(s.gatilhos?.faltaRazao, PADRAO.gatilhos.faltaRazao),
      faltaAceiteSeg: num(s.gatilhos?.faltaAceiteSeg, PADRAO.gatilhos.faltaAceiteSeg),
      faltaDescontoPct: num(s.gatilhos?.faltaDescontoPct, PADRAO.gatilhos.faltaDescontoPct),
      diaFracoBonusPct: num(s.gatilhos?.diaFracoBonusPct, PADRAO.gatilhos.diaFracoBonusPct),
      diaFracoMinEntregas: num(s.gatilhos?.diaFracoMinEntregas, PADRAO.gatilhos.diaFracoMinEntregas),
      excessoRazao: num(s.gatilhos?.excessoRazao, PADRAO.gatilhos.excessoRazao),
    },
  };
}
