// Funções exclusivas do Admin.

import { getAuth } from "firebase-admin/auth";
import { onCall } from "firebase-functions/v2/https";

import {
  FieldValue,
  HttpsError,
  auditar,
  dados,
  db,
  exigir,
  notificar,
  numero,
  sessao,
  texto,
} from "./comum.ts";
import { mesclarParametros } from "./dominio/parametros.ts";

/**
 * Primeiro acesso do dono: quem estiver na lista ADMIN_EMAILS (arquivo
 * functions/.env) e entrar com Google vira admin.
 */
export const reivindicarAdmin = onCall(async (req) => {
  const s = sessao(req);
  const lista = (process.env.ADMIN_EMAILS ?? "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  const verificado = (req.auth?.token as Record<string, unknown>).email_verified === true;
  if (!s.email || !verificado || !lista.includes(s.email.toLowerCase())) {
    throw new HttpsError("permission-denied", "Esta conta não está autorizada como administradora.");
  }
  await getAuth().setCustomUserClaims(s.uid, { papel: "admin", aprovado: true });
  await db.doc(`users/${s.uid}`).set({ papel: "admin", email: s.email, status: "aprovado" }, { merge: true });
  return { ok: true, renovarToken: true };
});

export const aprovarCadastro = onCall(async (req) => {
  const s = exigir(req, ["admin"]);
  const d = dados(req);
  const uid = texto(d.uid, "usuário", { max: 80 });
  const aprovar = d.aprovar === true;
  const motivo = aprovar ? "" : texto(d.motivo, "motivo", { min: 3, max: 300 });
  const user = await getAuth().getUser(uid);
  const papel = user.customClaims?.papel;
  if (papel !== "lojista" && papel !== "entregador") throw new HttpsError("failed-precondition", "Usuário sem perfil.");
  const colecao = papel === "lojista" ? "lojistas" : "entregadores";
  const perfil = await db.doc(`${colecao}/${uid}`).get();
  if (aprovar && perfil.get("cadastroCompleto") !== true) {
    throw new HttpsError("failed-precondition", "O cadastro ainda está incompleto.");
  }

  await getAuth().setCustomUserClaims(uid, { ...user.customClaims, aprovado: aprovar });
  await db.doc(`users/${uid}`).update({ status: aprovar ? "aprovado" : "recusado", motivo: motivo || FieldValue.delete() });
  await perfil.ref.update({ aprovado: aprovar });
  await auditar(s.uid, aprovar ? "cadastro_aprovado" : "cadastro_recusado", `${colecao}/${uid}`, { motivo });
  await notificar(
    uid,
    aprovar ? "Cadastro aprovado!" : "Cadastro precisa de ajuste",
    aprovar ? "Você já pode usar o RodaJusta." : motivo,
    { tipo: "cadastro" },
  );
  return { ok: true };
});

export const bloquearUsuario = onCall(async (req) => {
  const s = exigir(req, ["admin"]);
  const d = dados(req);
  const uid = texto(d.uid, "usuário", { max: 80 });
  const bloquear = d.bloquear === true;
  const motivo = texto(d.motivo, "motivo", { min: 3, max: 300 });
  await db.doc(`users/${uid}`).update({ status: bloquear ? "bloqueado" : "aprovado" });
  const ent = db.doc(`entregadores/${uid}`);
  if ((await ent.get()).exists) {
    await ent.update({ bloqueado: bloquear, ...(bloquear ? { disponibilidade: "offline" } : {}) });
  }
  if (bloquear) await getAuth().revokeRefreshTokens(uid);
  await auditar(s.uid, bloquear ? "bloqueio" : "desbloqueio", `users/${uid}`, { motivo });
  return { ok: true };
});

/** Salva parâmetros do algoritmo e da taxa, sempre validados. */
export const salvarParametros = onCall(async (req) => {
  const s = exigir(req, ["admin"]);
  const novo = mesclarParametros((dados(req).parametros ?? {}) as never);
  const somaPesos = novo.pesos.distancia + novo.pesos.espera + novo.pesos.equidade + novo.pesos.rodizio;
  if (somaPesos <= 0) throw new HttpsError("invalid-argument", "Os pesos não podem ser todos zero.");
  const ref = db.doc("config/parametros");
  const antes = (await ref.get()).data() ?? null;
  await ref.set(novo);
  await auditar(s.uid, "parametros", "config/parametros", { antes, depois: novo });
  return { parametros: novo };
});

export const salvarZona = onCall(async (req) => {
  const s = exigir(req, ["admin"]);
  const d = dados(req);
  const id = texto(d.id, "id", { min: 2, max: 40 }).toLowerCase().replace(/[^a-z0-9_-]/g, "-");
  const zona = {
    nome: texto(d.nome, "nome", { min: 2, max: 60 }),
    lat: numero(d.lat, "lat", -90, 90),
    lng: numero(d.lng, "lng", -180, 180),
    raioKm: numero(d.raioKm, "raio", 0.5, 100),
    ativa: d.ativa !== false,
  };
  await db.doc(`zonas/${id}`).set(zona, { merge: true });
  await auditar(s.uid, "zona", `zonas/${id}`, zona);
  return { id };
});

export const confirmarVinculoIfood = onCall(async (req) => {
  const s = exigir(req, ["admin"]);
  const merchantId = texto(dados(req).merchantId, "merchant", { max: 80 });
  await db.doc(`ifoodMerchants/${merchantId}`).update({ confirmado: true });
  await auditar(s.uid, "ifood_vinculo", `ifoodMerchants/${merchantId}`);
  return { ok: true };
});

/** Lançamento manual de ajuste num acerto (com motivo, auditado). */
export const lancarAjuste = onCall(async (req) => {
  const s = exigir(req, ["admin"]);
  const d = dados(req);
  const lojistaId = texto(d.lojistaId, "loja", { max: 80 });
  const entregadorId = texto(d.entregadorId, "entregador", { max: 80 });
  const valor = numero(d.valorCentavos, "valor", -10_000_000, 10_000_000);
  if (!Number.isInteger(valor) || valor === 0) throw new HttpsError("invalid-argument", "Valor inválido.");
  const motivo = texto(d.motivo, "motivo", { min: 5, max: 300 });
  const acertoRef = db.doc(`acertos/${lojistaId}_${entregadorId}`);
  const b = db.batch();
  b.set(db.collection("lancamentos").doc(), {
    lojistaId,
    entregadorId,
    tipo: "ajuste",
    valorCentavos: valor,
    motivo,
    criadoEm: FieldValue.serverTimestamp(),
    criadoPor: s.uid,
  });
  b.set(acertoRef, { ajustesCentavos: FieldValue.increment(valor), saldoCentavos: FieldValue.increment(valor) }, { merge: true });
  await b.commit();
  await auditar(s.uid, "ajuste", `acertos/${lojistaId}_${entregadorId}`, { valor, motivo });
  return { ok: true };
});

