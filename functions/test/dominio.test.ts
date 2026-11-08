import { test } from "node:test";
import assert from "node:assert/strict";

import { PADRAO, mesclarParametros } from "../src/dominio/parametros.ts";
import { distanciaKm, ordemVizinhoMaisProximo } from "../src/dominio/geo.ts";
import { entregasPorHora, gini, penalidadeRecusas, pontuar, ranquear } from "../src/dominio/score.ts";
import type { Candidato } from "../src/dominio/score.ts";
import { planejarOnda } from "../src/dominio/ondas.ts";
import { desvioKm, sugerirAgrupamentos, validarLote } from "../src/dominio/lote.ts";
import {
  calcularFatura,
  creditoBonusSemanal,
  creditoDesconto,
  entregasParaCompensarMensal,
  situacaoFatura,
} from "../src/dominio/fatura.ts";
import { calcularAcerto } from "../src/dominio/acerto.ts";
import { linkRota, rotaDoLote } from "../src/dominio/rota.ts";
import { avaliarGatilhos } from "../src/dominio/incentivos.ts";

const AGORA = Date.UTC(2026, 10, 7, 20, 0, 0);
// Ariquemes (centro aproximado) e pontos em volta
const LOJA = { lat: -9.9133, lng: -63.0408 };
const norte = (km: number) => ({ lat: LOJA.lat + km / 111.2, lng: LOJA.lng });
const leste = (km: number) => ({ lat: LOJA.lat, lng: LOJA.lng + km / (111.2 * Math.cos((LOJA.lat * Math.PI) / 180)) });

const cand = (id: string, p: Partial<Candidato> = {}): Candidato => ({
  id,
  distanciaKm: 1,
  minutosEsperando: 0,
  entregasPorHora: 0,
  noTurno: false,
  recusas: [],
  ...p,
});

test("distância: 1 km ao norte mede ~1 km", () => {
  assert.ok(Math.abs(distanciaKm(LOJA, norte(1)) - 1) < 0.01);
});

test("parâmetros: mescla salvo sobre padrão e ignora lixo", () => {
  const p = mesclarParametros({ pesos: { distancia: 0.6 }, taxa: { porEntregaCentavos: 100 }, ondas: [] } as never);
  assert.equal(p.pesos.distancia, 0.6);
  assert.equal(p.pesos.espera, PADRAO.pesos.espera);
  assert.equal(p.taxa.porEntregaCentavos, 100);
  assert.equal(p.taxa.mensalCentavos, 8000);
  assert.deepEqual(p.ondas, PADRAO.ondas);
  assert.equal(mesclarParametros(null).maxEntregasPorLote, 3);
});

test("score: mais perto ganha quando o resto é igual", () => {
  const r = ranquear([cand("longe", { distanciaKm: 2.5 }), cand("perto", { distanciaKm: 0.5 })], 3, PADRAO.pesos, AGORA);
  assert.deepEqual(r.map((x) => x.id), ["perto", "longe"]);
});

test("score: quem espera há 1 hora passa na frente de quem está um pouco mais perto", () => {
  const r = ranquear(
    [cand("perto_recem", { distanciaKm: 0.8 }), cand("esperando", { distanciaKm: 1.6, minutosEsperando: 60 })],
    3,
    PADRAO.pesos,
    AGORA,
  );
  assert.equal(r[0].id, "esperando");
});

test("score: quem fez menos entregas por hora sobe", () => {
  const r = ranquear(
    [cand("muitas", { entregasPorHora: 4 }), cand("poucas", { entregasPorHora: 1 })],
    3,
    PADRAO.pesos,
    AGORA,
  );
  assert.equal(r[0].id, "poucas");
});

test("score: fora do raio não entra", () => {
  assert.equal(ranquear([cand("x", { distanciaKm: 3.1 })], 3, PADRAO.pesos, AGORA).length, 0);
});

test("score: componentes ficam entre 0 e 1", () => {
  const p = pontuar(cand("a", { distanciaKm: 0, minutosEsperando: 500, noTurno: true }), 3, 0, PADRAO.pesos, AGORA);
  for (const v of Object.values(p.componentes)) assert.ok(v >= 0 && v <= 1);
  assert.equal(p.score, 1); // 0.45 + 0.25 + 0.2 + 0.1
});

test("recusas: penalidade decai pela metade em 30 min e tem teto 1", () => {
  const agora = penalidadeRecusas([AGORA], AGORA);
  const meiaHora = penalidadeRecusas([AGORA - 30 * 60000], AGORA);
  assert.ok(Math.abs(meiaHora - agora / 2) < 1e-9);
  assert.equal(penalidadeRecusas([AGORA, AGORA, AGORA, AGORA, AGORA], AGORA), 1);
});

test("entregas por hora usa no mínimo meia hora online", () => {
  assert.equal(entregasPorHora(1, 5), 2);
  assert.equal(entregasPorHora(6, 120), 3);
});

test("gini: igualdade = 0, concentração alta perto de 1", () => {
  assert.equal(gini([2, 2, 2, 2]), 0);
  assert.ok(gini([0, 0, 0, 10]) > 0.7);
});

const baseOnda = {
  geral: [cand("a", { distanciaKm: 0.5 }), cand("b", { distanciaKm: 1 }), cand("c", { distanciaKm: 2 }), cand("d", { distanciaKm: 4 })],
  equipe: [] as Candidato[],
  jaOfertados: new Set<string>(),
  ondas: PADRAO.ondas,
  pesos: PADRAO.pesos,
  segundosPorOnda: 30,
  esperaEquipeSeg: 60,
  agoraMs: AGORA,
};

test("ondas: 1ª onda vai só para o melhor; 2ª para os 3 seguintes", () => {
  const o0 = planejarOnda({ ...baseOnda, numero: 0, modo: "geral" });
  assert.equal(o0.tipo, "geral");
  assert.deepEqual(o0.ofertar.map((x) => x.id), ["a"]);
  const o1 = planejarOnda({ ...baseOnda, numero: 1, modo: "geral", jaOfertados: new Set(["a"]) });
  assert.deepEqual(o1.ofertar.map((x) => x.id), ["b", "c"]); // d está fora de 3 km
  const o2 = planejarOnda({ ...baseOnda, numero: 2, modo: "geral", jaOfertados: new Set(["a", "b", "c"]) });
  assert.deepEqual(o2.ofertar.map((x) => x.id), ["d"]);
  assert.equal(o2.raioKm, 5);
  const fim = planejarOnda({ ...baseOnda, numero: 3, modo: "geral", jaOfertados: new Set(["a", "b", "c", "d"]) });
  assert.equal(fim.tipo, "fim");
});

test("ondas: equipe primeiro oferece a todos da equipe e depois cai no geral", () => {
  const equipe = [cand("e1", { distanciaKm: 5 }), cand("e2", { distanciaKm: 1 })];
  const o0 = planejarOnda({ ...baseOnda, equipe, numero: 0, modo: "equipe_primeiro" });
  assert.equal(o0.tipo, "equipe");
  assert.equal(o0.segundos, 60);
  assert.equal(o0.ofertar.length, 2);
  const o1 = planejarOnda({ ...baseOnda, equipe, numero: 1, modo: "equipe_primeiro", jaOfertados: new Set(["e1", "e2"]) });
  assert.equal(o1.tipo, "geral");
  assert.deepEqual(o1.ofertar.map((x) => x.id), ["a"]);
});

test("ondas: sem equipe online, equipe_primeiro vai direto ao geral", () => {
  const o = planejarOnda({ ...baseOnda, numero: 0, modo: "equipe_primeiro" });
  assert.equal(o.tipo, "geral");
  assert.equal(o.numero, 1);
});

test("ondas: modo só equipe termina sem cair no geral", () => {
  const o = planejarOnda({ ...baseOnda, numero: 1, modo: "equipe" });
  assert.equal(o.tipo, "fim");
});

test("lote: validação", () => {
  const p = (id: string, loja = "L1") => ({ id, lojistaId: loja, destino: norte(1) });
  assert.equal(validarLote([], 3), "vazio");
  assert.equal(validarLote([p("1"), p("2", "L2")], 3), "lojas_diferentes");
  assert.equal(validarLote([p("1"), p("2"), p("3"), p("4")], 3), "acima_do_maximo");
  assert.equal(validarLote([p("1"), p("2")], 3), null);
});

test("lote: destinos na mesma direção têm desvio pequeno; opostos não", () => {
  assert.ok(desvioKm(LOJA, [norte(2), norte(3)]) < 0.01);
  assert.ok(desvioKm(LOJA, [norte(2), { lat: LOJA.lat - 2 / 111.2, lng: LOJA.lng }]) > 3);
});

test("lote: agrupa os da mesma direção e separa o do lado oposto", () => {
  const grupos = sugerirAgrupamentos(
    LOJA,
    [
      { id: "n2", lojistaId: "L", destino: norte(2) },
      { id: "n3", lojistaId: "L", destino: norte(3) },
      { id: "s2", lojistaId: "L", destino: { lat: LOJA.lat - 2 / 111.2, lng: LOJA.lng } },
    ],
    3,
    2,
  );
  assert.deepEqual(grupos, [["n3", "n2"], ["s2"]]);
});

test("rota: uma entrega gera link só com destino", () => {
  const url = new URL(linkRota([{ lat: -9.9, lng: -63.04 }]));
  assert.equal(url.hostname, "www.google.com");
  assert.equal(url.searchParams.get("destination"), "-9.900000,-63.040000");
  assert.equal(url.searchParams.get("waypoints"), null);
});

test("rota: lote ordena do mais perto ao mais longe e põe paradas em waypoints", () => {
  const { ordem, url } = rotaDoLote(LOJA, [norte(3), norte(1), norte(2)]);
  assert.deepEqual(ordem, [1, 2, 0]);
  const u = new URL(url);
  assert.equal(u.searchParams.get("waypoints")!.split("|").length, 2);
});

test("vizinho mais próximo", () => {
  assert.deepEqual(ordemVizinhoMaisProximo(LOJA, [leste(5), leste(1), leste(3)]), [1, 2, 0]);
});

test("fatura: por entrega e mensal", () => {
  const base = { creditosCentavos: 0, porEntregaCentavos: 80, mensalCentavos: 8000, isento: false };
  assert.equal(calcularFatura({ ...base, plano: "por_entrega", entregas: 50 }).totalCentavos, 4000);
  assert.equal(calcularFatura({ ...base, plano: "mensal", entregas: 50 }).totalCentavos, 8000);
  assert.equal(calcularFatura({ ...base, plano: "mensal", entregas: 0 }).totalCentavos, 0);
  assert.equal(calcularFatura({ ...base, plano: "por_entrega", entregas: 50, isento: true }).totalCentavos, 0);
});

test("fatura: créditos não deixam negativo e no mensal param na mensalidade", () => {
  const base = { porEntregaCentavos: 80, mensalCentavos: 8000, isento: false };
  const f = calcularFatura({ ...base, plano: "por_entrega", entregas: 10, creditosCentavos: 5000 });
  assert.deepEqual(f, { brutoCentavos: 800, creditosAplicadosCentavos: 800, totalCentavos: 0 });
  const m = calcularFatura({ ...base, plano: "mensal", entregas: 300, creditosCentavos: 9000 });
  assert.equal(m.totalCentavos, 0);
});

test("fatura: mensal compensa a partir de 100 entregas com R$0,80 e R$80", () => {
  assert.equal(entregasParaCompensarMensal(80, 8000), 100);
});

test("créditos de incentivo", () => {
  assert.equal(creditoDesconto(50, 80), 40);
  assert.equal(creditoDesconto(150, 80), 80);
  const bonus = { plano: "por_entrega" as const, percentual: 20, minimoEntregas: 5, entregasNaSemana: 40, porEntregaCentavos: 80, mensalCentavos: 8000 };
  assert.equal(creditoBonusSemanal({ ...bonus, entregasNaJanela: 4 }), 0);
  assert.equal(creditoBonusSemanal({ ...bonus, entregasNaJanela: 5 }), 640);
  assert.equal(creditoBonusSemanal({ ...bonus, plano: "mensal", entregasNaJanela: 5 }), 400);
});

test("fatura: vencida e bloqueio após o prazo", () => {
  const venc = AGORA;
  assert.deepEqual(situacaoFatura("fechada", venc, AGORA - 1000, 3), { vencida: false, bloqueia: false });
  assert.deepEqual(situacaoFatura("fechada", venc, AGORA + 86400000, 3), { vencida: true, bloqueia: false });
  assert.deepEqual(situacaoFatura("vencida", venc, AGORA + 4 * 86400000, 3), { vencida: true, bloqueia: true });
  assert.deepEqual(situacaoFatura("paga", venc, AGORA + 9 * 86400000, 3), { vencida: false, bloqueia: false });
});

test("acerto: entregas, pagamento confirmado, pendente, repasse e estorno", () => {
  const a = calcularAcerto([
    { id: "1", tipo: "entrega", valorCentavos: 700 },
    { id: "2", tipo: "entrega", valorCentavos: 700 },
    { id: "3", tipo: "entrega", valorCentavos: 900 },
    { id: "4", tipo: "pagamento", valorCentavos: 1000, status: "confirmado" },
    { id: "5", tipo: "pagamento", valorCentavos: 500, status: "pendente" },
    { id: "6", tipo: "repasse", valorCentavos: 300 },
    { id: "7", tipo: "estorno", valorCentavos: 900, estornaId: "3" },
    { id: "8", tipo: "pagamento", valorCentavos: 200, status: "contestado" },
  ]);
  assert.equal(a.entregasCentavos, 1400);
  assert.equal(a.pagosCentavos, 1000);
  assert.equal(a.pendentesCentavos, 500);
  assert.equal(a.contestadosCentavos, 200);
  assert.equal(a.repassesCentavos, 300);
  assert.equal(a.saldoCentavos, 100); // 1400 - 1000 - 300
});

const g = PADRAO.gatilhos;
const med = (pedidos: number, ent: number, extra: Partial<{ aceiteMedioSeg: number; chuvaProximaHoraMm: number }> = {}) => ({
  pedidos,
  entregadoresOnline: ent,
  aceiteMedioSeg: extra.aceiteMedioSeg ?? 30,
  chuvaProximaHoraMm: extra.chuvaProximaHoraMm ?? 0,
});

test("gatilhos: chuva gera desconto", () => {
  const s = avaliarGatilhos({ zonaId: "z", atual: med(5, 5, { chuvaProximaHoraMm: 3 }), anterior: null, previsaoAmanha: null, medicoesEmExcesso: 0, gatilhos: g });
  assert.deepEqual(s.map((x) => [x.tipo, x.percentual]), [["chuva", 50]]);
});

test("gatilhos: falta só dispara com duas medições seguidas", () => {
  const uma = avaliarGatilhos({ zonaId: "z", atual: med(10, 4), anterior: med(3, 4), previsaoAmanha: null, medicoesEmExcesso: 0, gatilhos: g });
  assert.equal(uma.length, 0);
  const duas = avaliarGatilhos({ zonaId: "z", atual: med(10, 4), anterior: med(8, 4), previsaoAmanha: null, medicoesEmExcesso: 0, gatilhos: g });
  assert.deepEqual(duas.map((x) => x.tipo), ["baixa_oferta"]);
});

test("gatilhos: dia fraco previsto gera bônus; excesso gera rodízio", () => {
  const s = avaliarGatilhos({ zonaId: "z", atual: med(1, 10), anterior: med(1, 10), previsaoAmanha: { pedidos: 40, entregadores: 25 }, medicoesEmExcesso: 4, gatilhos: g });
  assert.deepEqual(s.map((x) => x.tipo).sort(), ["dia_fraco", "rodizio"]);
  assert.equal(s.find((x) => x.tipo === "dia_fraco")!.minimoEntregas, 5);
});
