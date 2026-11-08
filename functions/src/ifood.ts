// Integração com o iFood (Merchant API) para lojas com ENTREGA PRÓPRIA.
// Recebe pedidos por webhook e avisa o iFood quando o pedido sai para entrega.
//
// Antes de produção: cadastro de integrador e homologação no Portal do
// Desenvolvedor iFood. Confira os nomes de campos e o formato da assinatura
// do webhook na documentação vigente; eles estão isolados neste arquivo.

import { createHmac, timingSafeEqual } from "node:crypto";
import { onCall, onRequest } from "firebase-functions/v2/https";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";

import { FieldValue, HttpsError, dados, db, exigir, logger, texto } from "./comum.ts";
import { enviarItens } from "./despacho.ts";

const IFOOD_CLIENT_ID = defineSecret("IFOOD_CLIENT_ID");
const IFOOD_CLIENT_SECRET = defineSecret("IFOOD_CLIENT_SECRET");
const API = "https://merchant-api.ifood.com.br";

let token: { valor: string; expira: number } | null = null;

async function obterToken(): Promise<string> {
  if (token && token.expira > Date.now() + 60_000) return token.valor;
  const r = await fetch(`${API}/authentication/v1.0/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grantType: "client_credentials",
      clientId: IFOOD_CLIENT_ID.value(),
      clientSecret: IFOOD_CLIENT_SECRET.value(),
    }),
  });
  if (!r.ok) throw new Error(`token iFood: HTTP ${r.status}`);
  const j = (await r.json()) as { accessToken: string; expiresIn: number };
  token = { valor: j.accessToken, expira: Date.now() + j.expiresIn * 1000 };
  return token.valor;
}

async function ifood(caminho: string, init: RequestInit = {}): Promise<Response> {
  const t = await obterToken();
  return fetch(`${API}${caminho}`, {
    ...init,
    headers: { Authorization: `Bearer ${t}`, "Content-Type": "application/json", ...(init.headers ?? {}) },
  });
}

function assinaturaValida(corpo: Buffer, recebida: string | undefined): boolean {
  if (!recebida) return false;
  const esperada = createHmac("sha256", IFOOD_CLIENT_SECRET.value()).update(corpo).digest("hex");
  const a = Buffer.from(esperada);
  const b = Buffer.from(recebida.trim().toLowerCase());
  return a.length === b.length && timingSafeEqual(a, b);
}

interface EventoIfood {
  id: string;
  code?: string;
  fullCode?: string;
  orderId: string;
  merchantId: string;
}

/** Converte o pedido do iFood numa comanda da loja. */
function paraComanda(o: Record<string, any>) {
  const end = o.delivery?.deliveryAddress ?? {};
  const pagamentos = o.payments ?? {};
  const pendente = Math.round(Number(pagamentos.pending ?? 0) * 100);
  const dinheiro = (pagamentos.methods ?? []).find((m: any) => m.method === "CASH");
  const itens = (o.items ?? []).map((i: any) => `${i.quantity}x ${i.name}`).join(", ");
  return {
    origem: "ifood",
    ifoodOrderId: o.id,
    numero: o.displayId ?? "",
    cliente: o.customer?.name ?? "",
    telefone: o.customer?.phone?.number ?? "",
    localizador: o.customer?.phone?.localizer ?? "",
    descricao: `#${o.displayId ?? ""} · ${o.customer?.name ?? ""} · ${itens}`.slice(0, 140),
    endereco: {
      texto: end.formattedAddress ?? `${end.streetName ?? ""}, ${end.streetNumber ?? ""}`,
      bairro: end.neighborhood ?? "",
      complemento: end.complement ?? "",
      referencia: end.reference ?? "",
    },
    lat: end.coordinates?.latitude ?? null,
    lng: end.coordinates?.longitude ?? null,
    totalCentavos: Math.round(Number(o.total?.orderAmount ?? 0) * 100),
    pagamento: pendente > 0
      ? {
          tipo: "cobrar",
          valorCobrarCentavos: pendente,
          trocoParaCentavos: Math.round(Number(dinheiro?.cash?.changeFor ?? 0) * 100),
          forma: dinheiro ? "dinheiro" : "cartao",
        }
      : { tipo: "pago", valorCobrarCentavos: 0, trocoParaCentavos: 0, forma: "" },
    status: "pendente",
    criadoEm: FieldValue.serverTimestamp(),
  };
}

async function processarEvento(ev: EventoIfood): Promise<void> {
  // idempotência: cada evento só é tratado uma vez
  const marca = db.doc(`eventosIfood/${ev.id}`);
  try {
    await marca.create({ code: ev.code ?? ev.fullCode ?? "", orderId: ev.orderId, em: FieldValue.serverTimestamp() });
  } catch {
    return;
  }
  const codigo = ev.code ?? "";
  if (codigo !== "PLC" && ev.fullCode !== "PLACED") return;

  const vinculo = await db.doc(`ifoodMerchants/${ev.merchantId}`).get();
  if (!vinculo.exists) return;
  const lojistaId = vinculo.get("lojistaId") as string;

  const r = await ifood(`/order/v1.0/orders/${ev.orderId}`);
  if (!r.ok) throw new Error(`pedido ${ev.orderId}: HTTP ${r.status}`);
  const pedido = (await r.json()) as Record<string, any>;
  if (pedido.orderType !== "DELIVERY" || pedido.delivery?.deliveredBy !== "MERCHANT") return;

  const comanda = paraComanda(pedido);
  const ref = db.doc(`lojistas/${lojistaId}/comandas/ifood_${ev.orderId}`);
  await ref.set(comanda);

  if (vinculo.get("envioAutomatico") === true && comanda.lat !== null && comanda.lng !== null && comanda.endereco.bairro) {
    const loja = await db.doc(`lojistas/${lojistaId}`).get();
    const valor = loja.get("config.valorModo") === "fixo" ? loja.get("config.valorFixoCentavos") ?? 0 : null;
    if (valor === null) return; // sem valor fixo, a loja confere na tela de envio
    await enviarItens(lojistaId, [
      {
        comandaId: ref.id,
        descricao: comanda.descricao,
        cliente: comanda.cliente,
        telefoneCliente: comanda.telefone,
        endereco: comanda.endereco.texto,
        bairro: comanda.endereco.bairro,
        complemento: comanda.endereco.complemento,
        referencia: comanda.endereco.referencia,
        lat: comanda.lat,
        lng: comanda.lng,
        valorEntregaCentavos: valor,
        pagamento: comanda.pagamento,
        origem: "ifood",
        ifoodOrderId: ev.orderId,
      },
    ], false);
  }
}

export const ifoodWebhook = onRequest({ secrets: [IFOOD_CLIENT_ID, IFOOD_CLIENT_SECRET] }, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).end();
    return;
  }
  if (!assinaturaValida(req.rawBody, req.get("X-IFood-Signature") ?? undefined)) {
    res.status(401).end();
    return;
  }
  const corpo = req.body;
  const eventos: EventoIfood[] = Array.isArray(corpo) ? corpo : [corpo];
  // responde rápido; erros de um evento não derrubam os outros
  res.status(202).end();
  for (const ev of eventos) {
    try {
      await processarEvento(ev);
    } catch (e) {
      logger.error("evento iFood falhou", { evento: ev.id, erro: String(e) });
    }
  }
});

/** Quando o entregador confirma a coleta, avisa o iFood que o pedido saiu. */
export const ifoodDespachar = onDocumentUpdated(
  { document: "pedidos/{id}", secrets: [IFOOD_CLIENT_ID, IFOOD_CLIENT_SECRET] },
  async (event) => {
    const depois = event.data?.after.data();
    const antes = event.data?.before.data();
    if (!depois || depois.ifoodDespacho !== "pendente" || antes?.ifoodDespacho === "pendente") return;
    try {
      const r = await ifood(`/order/v1.0/orders/${depois.ifoodOrderId}/dispatch`, { method: "POST", body: JSON.stringify({ deliveredBy: "MERCHANT" }) });
      await event.data!.after.ref.update({ ifoodDespacho: r.ok ? "enviado" : `erro_${r.status}` });
    } catch (e) {
      logger.error("dispatch iFood falhou", { pedido: event.params.id, erro: String(e) });
      await event.data!.after.ref.update({ ifoodDespacho: "erro" });
    }
  },
);

/** A loja informa o merchantId do iFood que é dela. O Admin confirma o vínculo. */
export const vincularIfood = onCall(async (req) => {
  const s = exigir(req, ["lojista"]);
  const d = dados(req);
  const merchantId = texto(d.merchantId, "ID da loja no iFood", { min: 8, max: 80 });
  const atual = await db.doc(`ifoodMerchants/${merchantId}`).get();
  if (atual.exists && atual.get("lojistaId") !== s.uid) {
    throw new HttpsError("already-exists", "Esta loja do iFood já está vinculada a outra conta.");
  }
  await db.doc(`ifoodMerchants/${merchantId}`).set({
    lojistaId: s.uid,
    envioAutomatico: d.envioAutomatico === true,
    confirmado: false,
    criadoEm: FieldValue.serverTimestamp(),
  });
  await db.doc(`lojistas/${s.uid}`).update({ ifoodMerchantId: merchantId });
  return { ok: true };
});
