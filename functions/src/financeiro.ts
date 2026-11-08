// Acertos loja ↔ entregador e equipe própria.

import { onCall } from "firebase-functions/v2/https";

import {
  FieldValue,
  HttpsError,
  Timestamp,
  auditar,
  dados,
  db,
  exigir,
  inteiro,
  notificar,
  texto,
  umDe,
} from "./comum.ts";

const reais = (c: number) => `R$ ${(c / 100).toFixed(2).replace(".", ",")}`;

/** A loja informa um pagamento feito por fora (Pix, dinheiro...). */
export const registrarPagamento = onCall(async (req) => {
  const s = exigir(req, ["lojista"]);
  const d = dados(req);
  const entregadorId = texto(d.entregadorId, "entregador", { max: 80 });
  const valor = inteiro(d.valorCentavos, "valor", 1, 10_000_000);
  const forma = umDe(d.forma, "forma", ["pix", "dinheiro", "transferencia", "outro"] as const);
  const observacao = texto(d.observacao, "observação", { opcional: true, max: 200 });
  const acertoRef = db.doc(`acertos/${s.uid}_${entregadorId}`);
  const acerto = await acertoRef.get();
  if (!acerto.exists) throw new HttpsError("not-found", "Este entregador ainda não fez entregas para você.");

  const ref = db.collection("lancamentos").doc();
  const b = db.batch();
  b.set(ref, {
    lojistaId: s.uid,
    lojaNome: acerto.get("lojaNome") ?? "",
    entregadorId,
    entregadorNome: acerto.get("entregadorNome") ?? "",
    tipo: "pagamento",
    valorCentavos: valor,
    forma,
    observacao,
    status: "pendente",
    criadoEm: FieldValue.serverTimestamp(),
    criadoPor: s.uid,
  });
  b.update(acertoRef, { pendentesCentavos: FieldValue.increment(valor), atualizadoEm: FieldValue.serverTimestamp() });
  await b.commit();
  await notificar(entregadorId, "Pagamento informado", `${acerto.get("lojaNome")} informou ${reais(valor)} via ${forma}. Confirme o recebimento.`, {
    tipo: "pagamento",
    lancamentoId: ref.id,
  });
  return { lancamentoId: ref.id };
});

/** O entregador confirma que recebeu ou contesta. */
export const responderPagamento = onCall(async (req) => {
  const s = exigir(req, ["entregador"]);
  const d = dados(req);
  const id = texto(d.lancamentoId, "lançamento", { max: 80 });
  const confirmar = d.confirmar === true;
  const motivo = confirmar ? "" : texto(d.motivo, "motivo", { min: 3, max: 200 });
  const ref = db.doc(`lancamentos/${id}`);

  const l = await db.runTransaction(async (tx) => {
    const lanc = (await tx.get(ref)).data();
    if (!lanc || lanc.entregadorId !== s.uid || lanc.tipo !== "pagamento") throw new HttpsError("not-found", "Pagamento não encontrado.");
    if (lanc.status !== "pendente") throw new HttpsError("failed-precondition", "Este pagamento já foi respondido.");
    const acertoRef = db.doc(`acertos/${lanc.lojistaId}_${s.uid}`);
    const v = lanc.valorCentavos as number;
    tx.update(ref, { status: confirmar ? "confirmado" : "contestado", motivoContestacao: motivo || null, respondidoEm: Timestamp.now() });
    tx.update(acertoRef, confirmar
      ? { pendentesCentavos: FieldValue.increment(-v), pagosCentavos: FieldValue.increment(v), saldoCentavos: FieldValue.increment(-v), atualizadoEm: Timestamp.now() }
      : { pendentesCentavos: FieldValue.increment(-v), contestadosCentavos: FieldValue.increment(v), atualizadoEm: Timestamp.now() });
    return lanc;
  });

  await notificar(
    l.lojistaId,
    confirmar ? "Pagamento confirmado" : "Pagamento contestado",
    confirmar ? `${l.entregadorNome} confirmou ${reais(l.valorCentavos)}.` : `${l.entregadorNome}: ${motivo}`,
    { tipo: "pagamento", lancamentoId: id },
  );
  return { ok: true };
});

/** Admin resolve uma contestação: valida o pagamento ou o anula. */
export const resolverContestacao = onCall(async (req) => {
  const s = exigir(req, ["admin"]);
  const d = dados(req);
  const id = texto(d.lancamentoId, "lançamento", { max: 80 });
  const valido = d.valido === true;
  const ref = db.doc(`lancamentos/${id}`);
  await db.runTransaction(async (tx) => {
    const l = (await tx.get(ref)).data();
    if (!l || l.status !== "contestado") throw new HttpsError("failed-precondition", "Nada a resolver.");
    const v = l.valorCentavos as number;
    tx.update(ref, { status: valido ? "confirmado" : "anulado", resolvidoPor: s.uid, resolvidoEm: Timestamp.now() });
    tx.update(db.doc(`acertos/${l.lojistaId}_${l.entregadorId}`), valido
      ? { contestadosCentavos: FieldValue.increment(-v), pagosCentavos: FieldValue.increment(v), saldoCentavos: FieldValue.increment(-v) }
      : { contestadosCentavos: FieldValue.increment(-v) });
  });
  await auditar(s.uid, "resolver_contestacao", `lancamentos/${id}`, { valido });
  return { ok: true };
});

// ---------------- equipe própria ----------------

export const convidarEntregador = onCall(async (req) => {
  const s = exigir(req, ["lojista"]);
  const codigo = texto(dados(req).codigo, "código", { min: 6, max: 6 }).toUpperCase();
  const achados = await db.collection("entregadores").where("codigoConvite", "==", codigo).limit(1).get();
  if (achados.empty) throw new HttpsError("not-found", "Nenhum entregador com este código.");
  const ent = achados.docs[0];
  if (ent.get("lojaEquipeId") === s.uid) throw new HttpsError("already-exists", "Este entregador já é da sua equipe.");
  const loja = await db.doc(`lojistas/${s.uid}`).get();
  await db.doc(`convites/${s.uid}_${ent.id}`).set({
    lojistaId: s.uid,
    lojaNome: loja.get("nomeFantasia") ?? "",
    entregadorId: ent.id,
    entregadorNome: ent.get("nome") ?? "",
    status: "pendente",
    criadoEm: FieldValue.serverTimestamp(),
  });
  await notificar(ent.id, "Convite de equipe", `${loja.get("nomeFantasia")} convidou você para a equipe própria.`, { tipo: "convite" });
  return { entregadorNome: ent.get("nome") ?? "" };
});

export const responderConvite = onCall(async (req) => {
  const s = exigir(req, ["entregador"]);
  const d = dados(req);
  const lojistaId = texto(d.lojistaId, "loja", { max: 80 });
  const aceitar = d.aceitar === true;
  const conviteRef = db.doc(`convites/${lojistaId}_${s.uid}`);
  await db.runTransaction(async (tx) => {
    const c = (await tx.get(conviteRef)).data();
    const e = (await tx.get(db.doc(`entregadores/${s.uid}`))).data();
    if (!c || c.status !== "pendente") throw new HttpsError("not-found", "Convite não encontrado.");
    tx.update(conviteRef, { status: aceitar ? "aceito" : "recusado", respondidoEm: Timestamp.now() });
    if (!aceitar) return;
    if (e?.lojaEquipeId && e.lojaEquipeId !== lojistaId) {
      tx.delete(db.doc(`lojistas/${e.lojaEquipeId}/equipe/${s.uid}`));
    }
    tx.update(db.doc(`entregadores/${s.uid}`), { lojaEquipeId: lojistaId, lojaEquipeNome: c.lojaNome, trabalhaEm: "ambos" });
    tx.set(db.doc(`lojistas/${lojistaId}/equipe/${s.uid}`), {
      nome: c.entregadorNome,
      desde: Timestamp.now(),
      valorCombinadoCentavos: null,
    });
  });
  await notificar(lojistaId, aceitar ? "Convite aceito" : "Convite recusado", "Toque para ver sua equipe.", { tipo: "equipe" });
  return { ok: true };
});

/** Loja remove alguém da equipe, ou o próprio entregador sai. */
export const sairDaEquipe = onCall(async (req) => {
  const s = exigir(req, ["lojista", "entregador"]);
  const d = dados(req);
  const entregadorId = s.papel === "entregador" ? s.uid : texto(d.entregadorId, "entregador", { max: 80 });
  const e = (await db.doc(`entregadores/${entregadorId}`).get()).data();
  const lojistaId = s.papel === "lojista" ? s.uid : e?.lojaEquipeId;
  if (!e || !lojistaId || e.lojaEquipeId !== lojistaId) throw new HttpsError("not-found", "Vínculo não encontrado.");
  const b = db.batch();
  b.delete(db.doc(`lojistas/${lojistaId}/equipe/${entregadorId}`));
  b.update(db.doc(`entregadores/${entregadorId}`), {
    lojaEquipeId: FieldValue.delete(),
    lojaEquipeNome: FieldValue.delete(),
    trabalhaEm: "geral",
  });
  await b.commit();
  return { ok: true };
});
