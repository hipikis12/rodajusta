// Métricas por zona, clima, gatilhos de incentivo e turnos de rodízio.

import { onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import type { DocumentData } from "firebase-admin/firestore";

import {
  FUSO,
  FieldValue,
  HttpsError,
  Timestamp,
  auditar,
  dados,
  db,
  exigir,
  inteiro,
  logger,
  ms,
  notificarTopico,
  numero,
  parametros,
  texto,
  umDe,
} from "./comum.ts";
import { avaliarGatilhos } from "./dominio/incentivos.ts";
import type { Medicao, Sugestao } from "./dominio/incentivos.ts";

const QUINZE_MIN = 15 * 60_000;

/** Chuva (mm) prevista para a próxima hora pela Open-Meteo (gratuita). */
async function chuvaProximaHora(lat: number, lng: number): Promise<number | null> {
  try {
    const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lng}&hourly=precipitation&forecast_hours=2&timezone=UTC`;
    const r = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!r.ok) return null;
    const j = (await r.json()) as { hourly?: { precipitation?: number[] } };
    const v = j.hourly?.precipitation ?? [];
    return v.length ? Math.max(...v.slice(0, 2)) : null;
  } catch {
    return null;
  }
}

async function medirZona(zonaId: string, z: DocumentData, agora: number): Promise<Medicao> {
  const desde = Timestamp.fromMillis(agora - QUINZE_MIN);
  const [pedidos, online, lotes, chuva] = await Promise.all([
    db.collection("pedidos").where("zonaId", "==", zonaId).where("criadoEm", ">=", desde).count().get(),
    db.collection("entregadores").where("zonaId", "==", zonaId).where("disponibilidade", "in", ["disponivel", "em_entrega"]).count().get(),
    db.collection("lotes").where("zonaId", "==", zonaId).where("aceitoEm", ">=", desde).get(),
    chuvaProximaHora(z.lat, z.lng),
  ]);
  const tempos = lotes.docs
    .map((l) => ((ms(l.get("aceitoEm")) ?? 0) - (ms(l.get("criadoEm")) ?? 0)) / 1000)
    .filter((t) => t > 0);
  return {
    pedidos: pedidos.data().count,
    entregadoresOnline: online.data().count,
    aceiteMedioSeg: tempos.length ? tempos.reduce((s, t) => s + t, 0) / tempos.length : null,
    chuvaProximaHoraMm: chuva,
  };
}

function janela(s: Sugestao, agora: number): { inicio: Timestamp; fim: Timestamp } {
  if (s.tipo === "dia_fraco" || s.tipo === "rodizio") {
    // amanhã, 18h às 22h no horário local (UTC-4)
    const amanha = new Date(agora + 86400000);
    const dia = new Intl.DateTimeFormat("en-CA", { timeZone: FUSO }).format(amanha);
    return {
      inicio: Timestamp.fromDate(new Date(`${dia}T18:00:00-04:00`)),
      fim: Timestamp.fromDate(new Date(`${dia}T22:00:00-04:00`)),
    };
  }
  return { inicio: Timestamp.fromMillis(agora), fim: Timestamp.fromMillis(agora + 2 * 3600_000) };
}

async function registrarSugestoes(sugestoes: Sugestao[], agora: number) {
  for (const s of sugestoes) {
    const existentes = await db
      .collection("incentivos")
      .where("zonaId", "==", s.zonaId)
      .where("tipo", "==", s.tipo)
      .where("status", "in", ["sugerido", "ativo"])
      .get();
    if (existentes.docs.some((i) => (ms(i.get("fim")) ?? 0) > agora)) continue;
    await db.collection("incentivos").add({
      ...s,
      ...janela(s, agora),
      origem: "auto",
      status: "sugerido",
      processado: false,
      criadoEm: FieldValue.serverTimestamp(),
    });
  }
}

/** A cada 15 minutos: mede cada zona e sugere incentivos. */
export const coletarMetricas = onSchedule({ schedule: "*/15 * * * *", timeZone: FUSO }, async () => {
  const p = await parametros();
  const agora = Date.now();

  // encerra incentivos vencidos
  const ativos = await db.collection("incentivos").where("status", "==", "ativo").get();
  for (const i of ativos.docs) {
    if ((ms(i.get("fim")) ?? 0) < agora) await i.ref.update({ status: "encerrado" });
  }

  const zonas = await db.collection("zonas").where("ativa", "==", true).get();
  for (const z of zonas.docs) {
    const atual = await medirZona(z.id, z.data(), agora);
    const ultimas = await db.collection("metricas").where("zonaId", "==", z.id).orderBy("em", "desc").limit(1).get();
    const ant = ultimas.docs[0]?.data();
    const razao = atual.entregadoresOnline > 0 ? atual.pedidos / atual.entregadoresOnline : atual.pedidos > 0 ? 99 : 0;
    const emExcesso = atual.entregadoresOnline > 0 && razao <= p.gatilhos.excessoRazao ? (ant?.medicoesEmExcesso ?? 0) + 1 : 0;

    await db.collection("metricas").add({
      zonaId: z.id,
      em: Timestamp.fromMillis(agora),
      ...atual,
      razao,
      medicoesEmExcesso: emExcesso,
      diaSemana: new Date(agora).getUTCDay(),
    });

    const sugestoes = avaliarGatilhos({
      zonaId: z.id,
      atual,
      anterior: ant
        ? { pedidos: ant.pedidos, entregadoresOnline: ant.entregadoresOnline, aceiteMedioSeg: ant.aceiteMedioSeg, chuvaProximaHoraMm: ant.chuvaProximaHoraMm }
        : null,
      previsaoAmanha: null,
      medicoesEmExcesso: emExcesso,
      gatilhos: p.gatilhos,
    });
    await registrarSugestoes(sugestoes, agora);
  }
});

/** Todo dia às 18:05: compara pedidos e entregadores das últimas 4 semanas para amanhã. */
export const preverDiaSeguinte = onSchedule({ schedule: "5 18 * * *", timeZone: FUSO }, async () => {
  const p = await parametros();
  const agora = Date.now();
  const zonas = await db.collection("zonas").where("ativa", "==", true).get();
  for (const z of zonas.docs) {
    let pedidos = 0;
    let entregadores = 0;
    let amostras = 0;
    for (let semana = 1; semana <= 4; semana++) {
      // mesma janela (18h–22h) do dia equivalente a amanhã, semanas atrás
      const inicio = agora + 86400000 - semana * 7 * 86400000;
      const snap = await db
        .collection("metricas")
        .where("zonaId", "==", z.id)
        .where("em", ">=", Timestamp.fromMillis(inicio))
        .where("em", "<", Timestamp.fromMillis(inicio + 4 * 3600_000))
        .get();
      if (snap.empty) continue;
      amostras++;
      pedidos += snap.docs.reduce((s, m) => s + (m.get("pedidos") ?? 0), 0);
      entregadores += snap.docs.reduce((s, m) => s + (m.get("entregadoresOnline") ?? 0), 0) / snap.size;
    }
    if (amostras < 2) continue; // pouco histórico ainda
    const sugestoes = avaliarGatilhos({
      zonaId: z.id,
      atual: { pedidos: 0, entregadoresOnline: 1, aceiteMedioSeg: null, chuvaProximaHoraMm: null },
      anterior: null,
      previsaoAmanha: { pedidos: pedidos / amostras / 4, entregadores: entregadores / amostras },
      medicoesEmExcesso: 0,
      gatilhos: p.gatilhos,
    });
    await registrarSugestoes(sugestoes, agora);
  }
  logger.info("previsão do dia seguinte concluída", { zonas: zonas.size });
});

// ---------------- incentivos (Admin) ----------------

export const decidirIncentivo = onCall(async (req) => {
  const s = exigir(req, ["admin"]);
  const d = dados(req);
  const id = texto(d.incentivoId, "incentivo", { max: 80 });
  const aprovar = d.aprovar === true;
  const ref = db.doc(`incentivos/${id}`);
  const inc = (await ref.get()).data();
  if (!inc || inc.status !== "sugerido") throw new HttpsError("failed-precondition", "Incentivo não está aguardando decisão.");
  const percentual = d.percentual === undefined ? inc.percentual : inteiro(d.percentual, "percentual", 0, 100);
  await ref.update({ status: aprovar ? "ativo" : "recusado", percentual, decididoPor: s.uid, decididoEm: FieldValue.serverTimestamp() });
  await auditar(s.uid, aprovar ? "incentivo_aprovado" : "incentivo_recusado", `incentivos/${id}`, { percentual });
  if (aprovar) await anunciar({ ...inc, percentual });
  return { ok: true };
});

export const criarIncentivo = onCall(async (req) => {
  const s = exigir(req, ["admin"]);
  const d = dados(req);
  const modo = umDe(d.modo, "modo", ["desconto", "bonus"] as const);
  const inc = {
    tipo: umDe(d.tipo, "tipo", ["chuva", "baixa_oferta", "dia_fraco", "manual"] as const, "manual"),
    modo,
    zonaId: texto(d.zonaId, "zona", { max: 60 }),
    percentual: inteiro(d.percentual, "percentual", 1, 100),
    minimoEntregas: modo === "bonus" ? inteiro(d.minimoEntregas, "mínimo de entregas", 1, 100) : 0,
    inicio: Timestamp.fromMillis(numero(d.inicioMs, "início", 0, 9e15)),
    fim: Timestamp.fromMillis(numero(d.fimMs, "fim", 0, 9e15)),
    motivo: texto(d.motivo, "motivo", { min: 3, max: 200 }),
    origem: "admin",
    status: "ativo",
    processado: false,
    criadoPor: s.uid,
    criadoEm: FieldValue.serverTimestamp(),
  };
  if (inc.fim.toMillis() <= inc.inicio.toMillis()) throw new HttpsError("invalid-argument", "O fim precisa ser depois do início.");
  const ref = await db.collection("incentivos").add(inc);
  await auditar(s.uid, "incentivo_criado", `incentivos/${ref.id}`, { percentual: inc.percentual, modo });
  await anunciar(inc);
  return { id: ref.id };
});

async function anunciar(inc: DocumentData) {
  const topico = inc.zonaId === "todas" ? "entregadores" : `zona_${inc.zonaId}`;
  const titulo = inc.modo === "bonus" ? `Bônus de ${inc.percentual}%` : `${inc.percentual}% de desconto na taxa`;
  await notificarTopico(topico, titulo, inc.motivo ?? "Incentivo ativo na sua região.");
}

// ---------------- turnos de rodízio ----------------

export const criarTurno = onCall(async (req) => {
  const s = exigir(req, ["admin"]);
  const d = dados(req);
  const inicio = numero(d.inicioMs, "início", 0, 9e15);
  const fim = numero(d.fimMs, "fim", 0, 9e15);
  if (fim <= inicio) throw new HttpsError("invalid-argument", "O fim precisa ser depois do início.");
  const ref = await db.collection("turnos").add({
    zonaId: texto(d.zonaId, "zona", { max: 60 }),
    inicio: Timestamp.fromMillis(inicio),
    fim: Timestamp.fromMillis(fim),
    vagas: inteiro(d.vagas, "vagas", 1, 500),
    reservados: [],
    criadoPor: s.uid,
  });
  return { id: ref.id };
});

export const reservarTurno = onCall(async (req) => {
  const s = exigir(req, ["entregador"]);
  const d = dados(req);
  const id = texto(d.turnoId, "turno", { max: 80 });
  const cancelar = d.cancelar === true;
  const ref = db.doc(`turnos/${id}`);
  await db.runTransaction(async (tx) => {
    const t = (await tx.get(ref)).data();
    if (!t) throw new HttpsError("not-found", "Turno não encontrado.");
    const reservados = (t.reservados ?? []) as string[];
    if (cancelar) {
      tx.update(ref, { reservados: FieldValue.arrayRemove(s.uid) });
      return;
    }
    if (reservados.includes(s.uid)) return;
    if (reservados.length >= t.vagas) throw new HttpsError("resource-exhausted", "Turno lotado.");
    tx.update(ref, { reservados: FieldValue.arrayUnion(s.uid) });
  });
  return { ok: true };
});
