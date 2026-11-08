// Fatura mensal do entregador com a plataforma (baixa manual pelo Admin).

import { onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import {
  FUSO,
  FieldValue,
  HttpsError,
  Timestamp,
  auditar,
  dados,
  db,
  exigir,
  logger,
  mesAnterior,
  mesLocal,
  ms,
  notificar,
  parametros,
  semanaIso,
  texto,
  umDe,
} from "./comum.ts";
import { calcularFatura, creditoBonusSemanal, situacaoFatura } from "./dominio/fatura.ts";
import type { Plano } from "./dominio/fatura.ts";

const reais = (c: number) => `R$ ${(c / 100).toFixed(2).replace(".", ",")}`;

/** Dia 1º, 03:00: fecha as faturas do mês anterior. */
export const fecharFaturas = onSchedule({ schedule: "0 3 1 * *", timeZone: FUSO }, async () => {
  const p = await parametros();
  const mes = mesAnterior(mesLocal());
  const abertas = await db.collection("faturas").where("mes", "==", mes).where("status", "==", "aberta").get();
  const vencimento = Timestamp.fromMillis(Date.now() + p.taxa.diasVencimento * 86400000);

  for (const f of abertas.docs) {
    const r = calcularFatura({
      plano: f.get("plano") as Plano,
      entregas: f.get("entregas") ?? 0,
      creditosCentavos: f.get("creditosCentavos") ?? 0,
      porEntregaCentavos: p.taxa.porEntregaCentavos,
      mensalCentavos: p.taxa.mensalCentavos,
      isento: f.get("isento") === true,
    });
    const nada = r.totalCentavos === 0;
    await f.ref.update({
      ...r,
      porEntregaCentavos: p.taxa.porEntregaCentavos,
      mensalCentavos: p.taxa.mensalCentavos,
      status: nada ? "paga" : "fechada",
      vencimento: nada ? null : vencimento,
      fechadaEm: FieldValue.serverTimestamp(),
    });
    const uid = f.get("entregadorId") as string;
    // troca de plano pedida vale a partir deste mês
    const e = await db.doc(`entregadores/${uid}`).get();
    if (e.get("planoProximoMes")) {
      await e.ref.update({ plano: e.get("planoProximoMes"), planoProximoMes: FieldValue.delete() });
    }
    if (!nada) {
      await notificar(uid, "Fatura do mês fechada", `${f.get("entregas")} entregas · total ${reais(r.totalCentavos)}.`, {
        tipo: "fatura",
        faturaId: f.id,
      });
    }
  }
  logger.info("faturas fechadas", { mes, quantidade: abertas.size });
});

/** Todo dia: marca vencidas e bloqueia quem passou do prazo. */
export const verificarFaturas = onSchedule({ schedule: "0 6 * * *", timeZone: FUSO }, async () => {
  const p = await parametros();
  const agora = Date.now();
  const snap = await db.collection("faturas").where("status", "in", ["fechada", "vencida"]).get();
  const bloquear = new Set<string>();
  for (const f of snap.docs) {
    const sit = situacaoFatura(f.get("status"), ms(f.get("vencimento")), agora, p.taxa.diasAtrasoBloqueio);
    if (sit.vencida && f.get("status") === "fechada") {
      await f.ref.update({ status: "vencida" });
      await notificar(f.get("entregadorId"), "Fatura vencida", "Pague para continuar recebendo entregas.", { tipo: "fatura" });
    }
    if (sit.bloqueia) bloquear.add(f.get("entregadorId"));
  }
  for (const uid of bloquear) await db.doc(`entregadores/${uid}`).update({ faturaBloqueada: true });
});

/** Admin dá baixa: o entregador pagou por fora. */
export const marcarFaturaPaga = onCall(async (req) => {
  const s = exigir(req, ["admin"]);
  const d = dados(req);
  const faturaId = texto(d.faturaId, "fatura", { max: 120 });
  const forma = umDe(d.forma, "forma", ["pix", "dinheiro", "transferencia", "outro"] as const);
  const ref = db.doc(`faturas/${faturaId}`);
  const f = (await ref.get()).data();
  if (!f) throw new HttpsError("not-found", "Fatura não encontrada.");
  if (!["fechada", "vencida"].includes(f.status)) throw new HttpsError("failed-precondition", "Fatura não está em aberto.");
  await ref.update({ status: "paga", pagaEm: FieldValue.serverTimestamp(), forma, marcadaPor: s.uid });

  const pendentes = await db
    .collection("faturas")
    .where("entregadorId", "==", f.entregadorId)
    .where("status", "==", "vencida")
    .get();
  const p = await parametros();
  const aindaBloqueia = pendentes.docs.some(
    (x) => x.id !== faturaId && situacaoFatura("vencida", ms(x.get("vencimento")), Date.now(), p.taxa.diasAtrasoBloqueio).bloqueia,
  );
  if (!aindaBloqueia) await db.doc(`entregadores/${f.entregadorId}`).update({ faturaBloqueada: false });
  await auditar(s.uid, "fatura_paga", `faturas/${faturaId}`, { forma, totalCentavos: f.totalCentavos });
  await notificar(f.entregadorId, "Fatura paga", "Pagamento registrado. Obrigado!", { tipo: "fatura" });
  return { ok: true };
});

/** Entregador pede troca de plano; vale no próximo mês. */
export const trocarPlano = onCall(async (req) => {
  const s = exigir(req, ["entregador"], false);
  const plano = umDe(dados(req).plano, "plano", ["por_entrega", "mensal"] as const);
  const ref = db.doc(`entregadores/${s.uid}`);
  const e = await ref.get();
  if (e.get("plano") === plano) {
    await ref.update({ planoProximoMes: FieldValue.delete() });
  } else {
    await ref.update({ planoProximoMes: plano });
  }
  return { ok: true };
});

/** Admin: isenção é exceção rara, sempre com motivo. */
export const definirIsencao = onCall(async (req) => {
  const s = exigir(req, ["admin"]);
  const d = dados(req);
  const uid = texto(d.entregadorId, "entregador", { max: 80 });
  const isento = d.isento === true;
  const motivo = texto(d.motivo, "motivo", { min: 5, max: 300 });
  await db.doc(`entregadores/${uid}`).update({ isento, motivoIsencao: isento ? motivo : FieldValue.delete() });
  await db.doc(`faturas/${uid}_${mesLocal()}`).set({ isento }, { merge: true });
  await auditar(s.uid, isento ? "isencao_ligada" : "isencao_desligada", `entregadores/${uid}`, { motivo });
  return { ok: true };
});

/** Segunda, 04:00: credita os bônus semanais na fatura. */
export const processarBonusSemanal = onSchedule({ schedule: "0 4 * * 1", timeZone: FUSO }, async () => {
  const p = await parametros();
  const semanaPassada = semanaIso(new Date(Date.now() - 3 * 86400000));
  const incs = await db
    .collection("incentivos")
    .where("modo", "==", "bonus")
    .where("status", "in", ["ativo", "encerrado"])
    .where("processado", "==", false)
    .get();
  for (const inc of incs.docs) {
    const fim = ms(inc.get("fim")) ?? 0;
    if (fim > Date.now()) continue;
    const minimo = inc.get("minimoEntregas") ?? 1;
    // filtro do campo dinâmico em código: evita um índice por incentivo
    const semanas = await db.collection("semanas").where("semana", "==", semanaIso(new Date(fim))).get();
    for (const sem of semanas.docs) {
      if ((sem.get(`porIncentivo.${inc.id}`) ?? 0) < minimo) continue;
      const valor = creditoBonusSemanal({
        plano: sem.get("plano"),
        percentual: inc.get("percentual"),
        entregasNaJanela: sem.get(`porIncentivo.${inc.id}`),
        minimoEntregas: minimo,
        entregasNaSemana: sem.get("entregas"),
        porEntregaCentavos: p.taxa.porEntregaCentavos,
        mensalCentavos: p.taxa.mensalCentavos,
      });
      if (valor <= 0) continue;
      const uid = sem.get("entregadorId") as string;
      const faturaRef = db.doc(`faturas/${uid}_${mesLocal(new Date(fim))}`);
      await faturaRef.set({ creditosCentavos: FieldValue.increment(valor) }, { merge: true });
      await faturaRef.collection("creditos").add({ incentivoIds: [inc.id], valorCentavos: valor, em: FieldValue.serverTimestamp() });
      await notificar(uid, "Bônus conquistado", `${reais(valor)} de desconto na sua fatura.`, { tipo: "fatura" });
    }
    await inc.ref.update({ processado: true, processadoSemana: semanaPassada });
  }
});
