// Cadastro em etapas: Google → perfil + telefone → dados completos → aprovação.

import { getAuth } from "firebase-admin/auth";
import { onCall } from "firebase-functions/v2/https";
import { geohashForLocation } from "geofire-common";

import {
  FieldValue,
  HttpsError,
  cpfValido,
  dados,
  db,
  exigir,
  numero,
  sessao,
  soDigitos,
  texto,
  umDe,
  zonaDoPonto,
} from "./comum.ts";

const ALFABETO = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
function codigoConvite(): string {
  let s = "";
  for (let i = 0; i < 6; i++) s += ALFABETO[Math.floor(Math.random() * ALFABETO.length)];
  return s;
}

/** Etapa 1: escolhe o perfil e informa o telefone. */
export const definirPerfil = onCall(async (req) => {
  const s = sessao(req);
  const d = dados(req);
  const papel = umDe(d.papel, "papel", ["lojista", "entregador"] as const);
  const telefone = soDigitos(texto(d.telefone, "telefone", { min: 10, max: 20 }));
  if (telefone.length < 10 || telefone.length > 13) {
    throw new HttpsError("invalid-argument", "Telefone inválido.");
  }
  const user = await getAuth().getUser(s.uid);
  const atuais = user.customClaims ?? {};
  if (atuais.papel && atuais.papel !== papel) {
    throw new HttpsError("already-exists", "Esta conta já tem outro perfil.");
  }
  const nome = texto(d.nome ?? user.displayName ?? "", "nome", { min: 2, max: 80 });

  await db.doc(`users/${s.uid}`).set(
    {
      papel,
      nome,
      email: user.email ?? null,
      telefone,
      status: "pendente",
      criadoEm: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  if (papel === "entregador") {
    await db.doc(`entregadores/${s.uid}`).set(
      {
        nome,
        telefone,
        cadastroCompleto: false,
        aprovado: false,
        bloqueado: false,
        faturaBloqueada: false,
        isento: false,
        plano: "por_entrega",
        disponibilidade: "offline",
        trabalhaEm: "geral",
        codigoConvite: codigoConvite(),
        recusas: [],
      },
      { merge: true },
    );
  } else {
    await db.doc(`lojistas/${s.uid}`).set(
      {
        nome,
        telefone,
        cadastroCompleto: false,
        aprovado: false,
        config: {
          valorModo: "fixo",
          valorFixoCentavos: 700,
          faixas: [],
          destinoPadrao: "equipe_primeiro",
          envioAutomatico: false,
        },
      },
      { merge: true },
    );
  }
  await getAuth().setCustomUserClaims(s.uid, { ...atuais, papel, aprovado: false });
  return { ok: true, renovarToken: true };
});

/** Etapa 2 do lojista: dados da loja. */
export const completarCadastroLojista = onCall(async (req) => {
  const s = exigir(req, ["lojista"], false);
  const d = dados(req);
  const nomeFantasia = texto(d.nomeFantasia, "nome da loja", { min: 2, max: 80 });
  const doc = soDigitos(texto(d.cpfCnpj, "CPF/CNPJ", { min: 11, max: 20 }));
  if (doc.length !== 11 && doc.length !== 14) throw new HttpsError("invalid-argument", "CPF/CNPJ inválido.");
  const endereco = texto(d.endereco, "endereço", { min: 5, max: 200 });
  const lat = numero(d.lat, "lat", -90, 90);
  const lng = numero(d.lng, "lng", -180, 180);
  const zonaId = await zonaDoPonto(lat, lng);
  await db.doc(`lojistas/${s.uid}`).set(
    {
      nomeFantasia,
      cpfCnpj: doc,
      endereco,
      lat,
      lng,
      geohash: geohashForLocation([lat, lng]),
      zonaId,
      cadastroCompleto: true,
      enviadoEm: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { ok: true, zonaId };
});

/** Etapa 2 do entregador: documentos e plano. CPF é único no sistema. */
export const completarCadastroEntregador = onCall(async (req) => {
  const s = exigir(req, ["entregador"], false);
  const d = dados(req);
  const cpf = soDigitos(texto(d.cpf, "CPF", { min: 11, max: 14 }));
  if (!cpfValido(cpf)) throw new HttpsError("invalid-argument", "CPF inválido.");
  const veiculo = umDe(d.veiculo, "veículo", ["moto", "bike", "carro"] as const);
  const placa = veiculo === "bike" ? "" : texto(d.placa, "placa", { min: 7, max: 8 }).toUpperCase();
  const plano = umDe(d.plano, "plano", ["por_entrega", "mensal"] as const);
  const cnh = veiculo === "bike" ? "" : texto(d.cnhPath, "foto da CNH", { max: 300 });
  const selfie = texto(d.selfiePath, "selfie", { max: 300 });
  for (const p of [cnh, selfie]) {
    if (p && !p.startsWith(`docs/${s.uid}/`)) throw new HttpsError("invalid-argument", "Arquivo inválido.");
  }
  const zonaId = texto(d.zonaId, "zona", { min: 1, max: 60, opcional: true }) || "padrao";

  await db.runTransaction(async (tx) => {
    const ref = db.doc(`cpfs/${cpf}`);
    const existente = await tx.get(ref);
    if (existente.exists && existente.get("uid") !== s.uid) {
      throw new HttpsError("already-exists", "Este CPF já está cadastrado em outra conta.");
    }
    tx.set(ref, { uid: s.uid });
    tx.set(
      db.doc(`entregadores/${s.uid}`),
      {
        cpf,
        veiculo,
        placa,
        plano,
        docs: { cnh, selfie },
        zonaId,
        cadastroCompleto: true,
        enviadoEm: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
  return { ok: true };
});
