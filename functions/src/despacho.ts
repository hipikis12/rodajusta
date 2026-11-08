// Envio de pedidos, lotes e ofertas em ondas.

import { onCall } from "firebase-functions/v2/https";
import { onTaskDispatched } from "firebase-functions/v2/tasks";
import { distanceBetween, geohashQueryBounds } from "geofire-common";
import type { DocumentData, Transaction, WriteBatch } from "firebase-admin/firestore";

import {
  FieldValue,
  HttpsError,
  Timestamp,
  agendar,
  dados,
  db,
  exigir,
  inteiro,
  logger,
  ms,
  notificar,
  numero,
  parametros,
  texto,
  umDe,
} from "./comum.ts";
import type { Parametros } from "./dominio/parametros.ts";
import { distanciaKm } from "./dominio/geo.ts";
import type { Ponto } from "./dominio/geo.ts";
import { entregasPorHora } from "./dominio/score.ts";
import type { Candidato } from "./dominio/score.ts";
import { planejarOnda, raioMaximoKm } from "./dominio/ondas.ts";
import type { ModoDespacho } from "./dominio/ondas.ts";
import { desvioKm, validarLote } from "./dominio/lote.ts";

const MODOS = ["geral", "equipe", "equipe_primeiro"] as const;
const TRES_HORAS = 3 * 3600_000;

// ---------------- candidatos ----------------

function paraCandidato(id: string, e: DocumentData, loja: Ponto, agora: number, hoje: string): Candidato {
  const loc = e.localizacao as { lat: number; lng: number };
  const stats = (e.statsHoje ?? {}) as { dia?: string; entregas?: number; minutosOnline?: number; onlineDesde?: Timestamp };
  const doDia = stats.dia === hoje;
  const sessaoMin = stats.onlineDesde ? (agora - stats.onlineDesde.toMillis()) / 60000 : 0;
  const minutosOnline = (doDia ? stats.minutosOnline ?? 0 : 0) + Math.max(0, sessaoMin);
  const desde = ms(e.disponivelDesde) ?? agora;
  return {
    id,
    distanciaKm: distanciaKm(loja, loc),
    minutosEsperando: Math.max(0, (agora - desde) / 60000),
    entregasPorHora: entregasPorHora(doDia ? stats.entregas ?? 0 : 0, minutosOnline),
    noTurno: (ms(e.noTurnoAte) ?? 0) > agora,
    recusas: ((e.recusas ?? []) as number[]).filter((t) => agora - t < TRES_HORAS),
  };
}

function apto(e: DocumentData, p: Parametros, agora: number): boolean {
  const loc = e.localizacao;
  return (
    e.aprovado === true &&
    e.bloqueado !== true &&
    e.faturaBloqueada !== true &&
    !e.loteAtivoId &&
    e.disponibilidade === "disponivel" &&
    loc &&
    loc.mock !== true &&
    agora - (ms(loc.em) ?? 0) <= p.localizacaoValidaSeg * 1000
  );
}

async function candidatosGerais(loja: Ponto, p: Parametros, agora: number, hoje: string): Promise<Candidato[]> {
  const raioM = raioMaximoKm(p.ondas) * 1000;
  const limites = geohashQueryBounds([loja.lat, loja.lng], raioM);
  const snaps = await Promise.all(
    limites.map(([ini, fim]) =>
      db
        .collection("entregadores")
        .where("disponibilidade", "==", "disponivel")
        .orderBy("localizacao.geohash")
        .startAt(ini)
        .endAt(fim)
        .get(),
    ),
  );
  const vistos = new Map<string, Candidato>();
  for (const snap of snaps) {
    for (const doc of snap.docs) {
      const e = doc.data();
      if (vistos.has(doc.id) || !apto(e, p, agora)) continue;
      if (e.trabalhaEm === "loja") continue;
      const km = distanceBetween([e.localizacao.lat, e.localizacao.lng], [loja.lat, loja.lng]);
      if (km * 1000 > raioM) continue;
      vistos.set(doc.id, paraCandidato(doc.id, e, loja, agora, hoje));
    }
  }
  return [...vistos.values()];
}

async function candidatosEquipe(
  lojistaId: string,
  loja: Ponto,
  p: Parametros,
  agora: number,
  hoje: string,
): Promise<Candidato[]> {
  const snap = await db
    .collection("entregadores")
    .where("lojaEquipeId", "==", lojistaId)
    .where("disponibilidade", "==", "disponivel")
    .get();
  return snap.docs
    .filter((d) => apto(d.data(), p, agora) && d.get("trabalhaEm") !== "geral")
    .map((d) => paraCandidato(d.id, d.data(), loja, agora, hoje));
}

// ---------------- ondas ----------------

/**
 * Avança o lote da onda `deOnda` (null = início) para a próxima.
 * Só uma chamada vence: a transação confere que a onda atual ainda é `deOnda`.
 */
export async function executarOnda(loteId: string, deOnda: number | null): Promise<void> {
  const ref = db.doc(`lotes/${loteId}`);
  const snap = await ref.get();
  const lote = snap.data();
  if (!lote || lote.status !== "buscando" || (lote.onda ?? null) !== deOnda) return;

  const p = await parametros();
  const agora = Date.now();
  const hoje = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Porto_Velho" }).format(new Date(agora));
  const loja: Ponto = { lat: lote.loja.lat, lng: lote.loja.lng };
  const modo = lote.modo as ModoDespacho;

  const [geral, equipe] = await Promise.all([
    modo === "equipe" ? Promise.resolve([]) : candidatosGerais(loja, p, agora, hoje),
    modo === "geral" ? Promise.resolve([]) : candidatosEquipe(lote.lojistaId, loja, p, agora, hoje),
  ]);

  const plano = planejarOnda({
    numero: deOnda === null ? 0 : deOnda + 1,
    modo,
    geral,
    equipe,
    jaOfertados: new Set<string>(lote.ofertados ?? []),
    ondas: p.ondas,
    pesos: p.pesos,
    segundosPorOnda: p.segundosPorOnda,
    esperaEquipeSeg: lote.esperaEquipeSeg ?? p.esperaEquipeSeg,
    agoraMs: agora,
  });

  const venceu = await db.runTransaction(async (tx) => {
    const atual = (await tx.get(ref)).data();
    if (!atual || atual.status !== "buscando" || (atual.onda ?? null) !== deOnda) return false;

    if (plano.tipo === "fim") {
      tx.update(ref, { status: "sem_entregador", onda: plano.numero, semEntregadorEm: FieldValue.serverTimestamp() });
      for (const pid of atual.pedidoIds as string[]) {
        tx.update(db.doc(`pedidos/${pid}`), {
          status: "sem_entregador",
          historico: FieldValue.arrayUnion({ status: "sem_entregador", em: Timestamp.now() }),
        });
      }
      return true;
    }

    const expira = Timestamp.fromMillis(agora + plano.segundos * 1000);
    for (const o of plano.ofertar) {
      const cand = [...geral, ...equipe].find((c) => c.id === o.id)!;
      tx.set(db.doc(`ofertas/${loteId}_${o.id}`), {
        loteId,
        entregadorId: o.id,
        lojistaId: atual.lojistaId,
        lojaNome: atual.lojaNome,
        lojaEndereco: atual.loja.endereco ?? "",
        onda: plano.numero,
        tipo: plano.tipo,
        score: o.score,
        componentes: o.componentes,
        qtdEntregas: (atual.pedidoIds as string[]).length,
        bairros: atual.bairros,
        valores: atual.valores,
        valorTotalCentavos: atual.valorTotalCentavos,
        distanciaLojaKm: Math.round(cand.distanciaKm * 10) / 10,
        distanciaTotalKm: atual.distanciaTotalKm,
        status: "pendente",
        expiraEm: expira,
        criadoEm: FieldValue.serverTimestamp(),
      });
    }
    tx.update(ref, {
      onda: plano.numero,
      ofertados: FieldValue.arrayUnion(...plano.ofertar.map((o) => o.id)),
    });
    return true;
  });

  if (!venceu) return;

  if (plano.tipo === "fim") {
    await notificar(lote.lojistaId, "Nenhum entregador aceitou", `${lote.bairros.join(", ")}: toque para reenviar.`, {
      tipo: "sem_entregador",
      loteId,
    });
    return;
  }

  const qtd = (lote.pedidoIds as string[]).length;
  const titulo = qtd > 1 ? `${qtd} entregas · ${lote.lojaNome}` : `Nova entrega · ${lote.lojaNome}`;
  const corpo = `${lote.bairros.join(", ")} · R$ ${(lote.valorTotalCentavos / 100).toFixed(2).replace(".", ",")}`;
  await Promise.all(
    plano.ofertar.map((o) => notificar(o.id, titulo, corpo, { tipo: "oferta", loteId, ofertaId: `${loteId}_${o.id}` }, true)),
  );
  await agendar("avancarOnda", { loteId, onda: plano.numero }, plano.segundos + 2);
}

/** Tarefa agendada ao fim de cada onda: expira as ofertas e chama a próxima. */
export const avancarOnda = onTaskDispatched(
  { retryConfig: { maxAttempts: 3, minBackoffSeconds: 5 } },
  async (req) => {
    const { loteId, onda } = req.data as { loteId: string; onda: number };
    await expirarOfertas(loteId, onda);
    await executarOnda(loteId, onda);
  },
);

async function expirarOfertas(loteId: string, onda?: number): Promise<void> {
  let q = db.collection("ofertas").where("loteId", "==", loteId).where("status", "==", "pendente");
  if (onda !== undefined) q = q.where("onda", "==", onda);
  const snap = await q.get();
  if (snap.empty) return;
  const b = db.batch();
  snap.docs.forEach((d) => b.update(d.ref, { status: "expirada" }));
  await b.commit();
}

// ---------------- envio de pedidos ----------------

interface ItemEnvio {
  comandaId: string;
  descricao: string;
  cliente: string;
  telefoneCliente: string;
  destino: { endereco: string; bairro: string; complemento: string; referencia: string; lat: number; lng: number };
  valorEntregaCentavos: number;
  pagamento: { tipo: "pago" | "cobrar"; valorCobrarCentavos: number; trocoParaCentavos: number; forma: string };
  origem: "manual" | "comanda" | "ifood";
  ifoodOrderId: string;
}

function lerItem(v: unknown): ItemEnvio {
  const d = (v ?? {}) as Record<string, unknown>;
  const pg = (d.pagamento ?? {}) as Record<string, unknown>;
  const tipoPg = umDe(pg.tipo, "pagamento", ["pago", "cobrar"] as const, "pago");
  return {
    comandaId: texto(d.comandaId, "comanda", { opcional: true, max: 80 }),
    descricao: texto(d.descricao, "descrição", { min: 1, max: 140 }),
    cliente: texto(d.cliente, "cliente", { opcional: true, max: 80 }),
    telefoneCliente: texto(d.telefoneCliente, "telefone do cliente", { opcional: true, max: 20 }),
    destino: {
      endereco: texto(d.endereco, "endereço", { min: 5, max: 200 }),
      bairro: texto(d.bairro, "bairro", { min: 2, max: 80 }),
      complemento: texto(d.complemento, "complemento", { opcional: true, max: 120 }),
      referencia: texto(d.referencia, "referência", { opcional: true, max: 160 }),
      lat: numero(d.lat, "lat", -90, 90),
      lng: numero(d.lng, "lng", -180, 180),
    },
    valorEntregaCentavos: inteiro(d.valorEntregaCentavos, "valor da entrega", 0, 100_000),
    pagamento: {
      tipo: tipoPg,
      valorCobrarCentavos: tipoPg === "cobrar" ? inteiro(pg.valorCobrarCentavos, "valor a cobrar", 1, 10_000_000) : 0,
      trocoParaCentavos: tipoPg === "cobrar" && pg.trocoParaCentavos ? inteiro(pg.trocoParaCentavos, "troco", 0, 10_000_000) : 0,
      // para o entregador saber se leva maquininha
      forma: tipoPg === "cobrar" && pg.forma ? umDe(pg.forma, "forma de cobrança", ["dinheiro", "cartao", "pix", "outro"] as const) : "",
    },
    origem: umDe(d.origem, "origem", ["manual", "comanda", "ifood"] as const, "manual"),
    ifoodOrderId: texto(d.ifoodOrderId, "pedido iFood", { opcional: true, max: 80 }),
  };
}

function pin4(): string {
  return String(Math.floor(Math.random() * 10000)).padStart(4, "0");
}

interface Loja {
  id: string;
  nome: string;
  ponto: Ponto;
  endereco: string;
  zonaId: string;
}

function pedidoDoc(loja: Loja, item: ItemEnvio, loteId: string | null, status: string): DocumentData {
  return {
    lojistaId: loja.id,
    lojaNome: loja.nome,
    loteId,
    entregadorId: null,
    status,
    descricao: item.descricao,
    cliente: item.cliente,
    telefoneCliente: item.telefoneCliente,
    destino: item.destino,
    distanciaKm: Math.round(distanciaKm(loja.ponto, item.destino) * 10) / 10,
    valorEntregaCentavos: item.valorEntregaCentavos,
    pagamento: item.pagamento,
    origem: item.origem,
    ifoodOrderId: item.ifoodOrderId || null,
    comandaId: item.comandaId || null,
    zonaId: loja.zonaId,
    criadoEm: FieldValue.serverTimestamp(),
    historico: [{ status, em: Timestamp.now() }],
  };
}

function resumoLote(loja: Loja, itens: ItemEnvio[]) {
  const destinos = itens.map((i) => i.destino);
  const maisLonge = Math.max(...destinos.map((d) => distanciaKm(loja.ponto, d)));
  return {
    bairros: itens.map((i) => i.destino.bairro),
    valores: itens.map((i) => i.valorEntregaCentavos),
    valorTotalCentavos: itens.reduce((s, i) => s + i.valorEntregaCentavos, 0),
    distanciaTotalKm: Math.round((maisLonge + desvioKm(loja.ponto, destinos)) * 10) / 10,
  };
}

/** Cria um lote com seus pedidos (escritas em lote) e devolve o id. */
export function criarLote(
  w: WriteBatch,
  loja: Loja,
  itens: ItemEnvio[],
  modo: ModoDespacho,
  esperaEquipeSeg: number | null,
): { loteId: string; pedidoIds: string[] } {
  const loteRef = db.collection("lotes").doc();
  const pedidoIds: string[] = [];
  for (const item of itens) {
    const pRef = db.collection("pedidos").doc();
    pedidoIds.push(pRef.id);
    w.set(pRef, pedidoDoc(loja, item, loteRef.id, "buscando"));
  }
  w.set(loteRef, {
    lojistaId: loja.id,
    lojaNome: loja.nome,
    loja: { lat: loja.ponto.lat, lng: loja.ponto.lng, endereco: loja.endereco },
    zonaId: loja.zonaId,
    pedidoIds,
    ...resumoLote(loja, itens),
    modo,
    esperaEquipeSeg,
    status: "buscando",
    onda: null,
    ofertados: [],
    entregadorId: null,
    criadoEm: FieldValue.serverTimestamp(),
  });
  // o PIN fica num documento que só a loja lê
  w.set(db.doc(`lotes/${loteRef.id}/privado/pin`), { pin: pin4(), lojistaId: loja.id });
  return { loteId: loteRef.id, pedidoIds };
}

export async function carregarLoja(lojistaId: string): Promise<{ loja: Loja; dados: DocumentData }> {
  const snap = await db.doc(`lojistas/${lojistaId}`).get();
  const l = snap.data();
  if (!l || l.cadastroCompleto !== true) {
    throw new HttpsError("failed-precondition", "Complete o cadastro da loja antes de enviar pedidos.");
  }
  return {
    loja: {
      id: lojistaId,
      nome: l.nomeFantasia,
      ponto: { lat: l.lat, lng: l.lng },
      endereco: l.endereco ?? "",
      zonaId: l.zonaId ?? "padrao",
    },
    dados: l,
  };
}

/**
 * Lógica de envio, usada pela tela da loja e pela integração com o iFood.
 * `juntas` = um lote só com todos os itens; senão, um lote por item.
 */
export async function enviarItens(
  lojistaId: string,
  brutos: unknown[],
  juntas: boolean,
  modoPedido?: ModoDespacho,
): Promise<{ loteIds: string[]; pedidoIds: string[] }> {
  if (!brutos.length || brutos.length > 20) throw new HttpsError("invalid-argument", "Envie de 1 a 20 pedidos.");
  const itens = brutos.map(lerItem);
  const p = await parametros();
  const { loja, dados: l } = await carregarLoja(lojistaId);

  // sem equipe cadastrada, "equipe primeiro" vira sistema geral
  let modo: ModoDespacho = modoPedido ?? l.config?.destinoPadrao ?? "geral";
  if (modo !== "geral") {
    const equipe = await db.collection(`lojistas/${lojistaId}/equipe`).limit(1).get();
    if (equipe.empty) modo = "geral";
  }

  const grupos = juntas ? [itens] : itens.map((i) => [i]);
  if (juntas) {
    const erro = validarLote(
      itens.map((i, k) => ({ id: String(k), lojistaId, destino: i.destino })),
      p.maxEntregasPorLote,
    );
    if (erro === "acima_do_maximo") {
      throw new HttpsError("invalid-argument", `No máximo ${p.maxEntregasPorLote} entregas por lote.`);
    }
  }

  const batch = db.batch();
  const loteIds: string[] = [];
  const pedidoIds: string[] = [];
  for (const g of grupos) {
    const r = criarLote(batch, loja, g, modo, l.config?.esperaEquipeSeg ?? null);
    loteIds.push(r.loteId);
    pedidoIds.push(...r.pedidoIds);
  }
  for (const item of itens) {
    if (item.comandaId) {
      batch.set(
        db.doc(`lojistas/${lojistaId}/comandas/${item.comandaId}`),
        { status: "enviada", enviadaEm: FieldValue.serverTimestamp() },
        { merge: true },
      );
    }
  }
  await batch.commit();
  await Promise.all(loteIds.map((id) => executarOnda(id, null)));
  return { loteIds, pedidoIds };
}

export const enviarPedidos = onCall(async (req) => {
  const s = exigir(req, ["lojista"]);
  const d = dados(req);
  if (!Array.isArray(d.itens)) throw new HttpsError("invalid-argument", "Nenhum pedido.");
  const modo = d.modo ? umDe(d.modo, "destino", MODOS) : undefined;
  return enviarItens(s.uid, d.itens, d.juntas === true, modo);
});

// ---------------- aceite e recusa ----------------

export const aceitarOferta = onCall(async (req) => {
  const s = exigir(req, ["entregador"]);
  const ofertaId = texto(dados(req).ofertaId, "oferta", { max: 200 });
  const ofertaRef = db.doc(`ofertas/${ofertaId}`);

  const lote = await db.runTransaction(async (tx) => {
    const oferta = (await tx.get(ofertaRef)).data();
    if (!oferta || oferta.entregadorId !== s.uid) throw new HttpsError("not-found", "Oferta não encontrada.");
    if (oferta.status !== "pendente" || (ms(oferta.expiraEm) ?? 0) < Date.now()) {
      throw new HttpsError("failed-precondition", "Esta oferta já expirou.");
    }
    const loteRef = db.doc(`lotes/${oferta.loteId}`);
    const entRef = db.doc(`entregadores/${s.uid}`);
    const [loteSnap, entSnap] = await Promise.all([tx.get(loteRef), tx.get(entRef)]);
    const l = loteSnap.data();
    const e = entSnap.data();
    if (!l || l.status !== "buscando") throw new HttpsError("failed-precondition", "Outro entregador já aceitou.");
    if (!e || e.loteAtivoId) throw new HttpsError("failed-precondition", "Você já tem uma entrega em andamento.");

    const agora = Timestamp.now();
    tx.update(ofertaRef, { status: "aceita", respondidaEm: agora });
    tx.update(loteRef, { status: "aceito", entregadorId: s.uid, entregadorNome: e.nome ?? "", aceitoEm: agora });
    for (const pid of l.pedidoIds as string[]) {
      tx.update(db.doc(`pedidos/${pid}`), {
        status: "aceito",
        entregadorId: s.uid,
        entregadorNome: e.nome ?? "",
        historico: FieldValue.arrayUnion({ status: "aceito", em: agora }),
      });
    }
    tx.update(entRef, { disponibilidade: "em_entrega", loteAtivoId: oferta.loteId });
    return { id: oferta.loteId as string, lojistaId: l.lojistaId as string, nome: (e.nome ?? "") as string };
  });

  await expirarOfertas(lote.id);
  await notificar(lote.lojistaId, "Entregador a caminho", `${lote.nome} aceitou e está indo até a loja.`, {
    tipo: "aceito",
    loteId: lote.id,
  });
  return { loteId: lote.id };
});

export const recusarOferta = onCall(async (req) => {
  const s = exigir(req, ["entregador"]);
  const ofertaId = texto(dados(req).ofertaId, "oferta", { max: 200 });
  const ref = db.doc(`ofertas/${ofertaId}`);
  const oferta = (await ref.get()).data();
  if (!oferta || oferta.entregadorId !== s.uid) throw new HttpsError("not-found", "Oferta não encontrada.");
  if (oferta.status !== "pendente") return { ok: true };

  await ref.update({ status: "recusada", respondidaEm: FieldValue.serverTimestamp() });
  await db.doc(`entregadores/${s.uid}`).update({ recusas: FieldValue.arrayUnion(Date.now()) });

  // ninguém mais pendente nesta onda: não espera o tempo acabar
  const restantes = await db
    .collection("ofertas")
    .where("loteId", "==", oferta.loteId)
    .where("onda", "==", oferta.onda)
    .where("status", "==", "pendente")
    .limit(1)
    .get();
  if (restantes.empty) await executarOnda(oferta.loteId, oferta.onda);
  return { ok: true };
});

// ---------------- incluir comanda num lote já aceito ----------------

export const incluirNoLote = onCall(async (req) => {
  const s = exigir(req, ["lojista"]);
  const d = dados(req);
  const loteId = texto(d.loteId, "lote", { max: 80 });
  const item = lerItem(d.item);
  const p = await parametros();
  const { loja } = await carregarLoja(s.uid);
  const loteRef = db.doc(`lotes/${loteId}`);
  const pedidoRef = db.collection("pedidos").doc();

  const entregadorId = await db.runTransaction(async (tx) => {
    const l = (await tx.get(loteRef)).data();
    if (!l || l.lojistaId !== s.uid) throw new HttpsError("not-found", "Lote não encontrado.");
    if (l.status !== "aceito") throw new HttpsError("failed-precondition", "Só dá para incluir antes da coleta.");
    if (l.inclusaoPendente) throw new HttpsError("failed-precondition", "Já existe uma inclusão aguardando resposta.");
    if ((l.pedidoIds as string[]).length >= p.maxEntregasPorLote) {
      throw new HttpsError("failed-precondition", "O lote já está no máximo de entregas.");
    }
    tx.set(pedidoRef, pedidoDoc(loja, item, null, "aguardando_inclusao"));
    tx.update(loteRef, {
      inclusaoPendente: {
        pedidoId: pedidoRef.id,
        bairro: item.destino.bairro,
        valorCentavos: item.valorEntregaCentavos,
        expiraEm: Timestamp.fromMillis(Date.now() + p.segundosInclusao * 1000),
      },
    });
    return l.entregadorId as string;
  });

  await notificar(
    entregadorId,
    "A loja quer adicionar 1 entrega",
    `${item.destino.bairro} · + R$ ${(item.valorEntregaCentavos / 100).toFixed(2).replace(".", ",")}`,
    { tipo: "inclusao", loteId },
    true,
  );
  await agendar("expirarInclusao", { loteId, pedidoId: pedidoRef.id }, p.segundosInclusao + 2);
  return { pedidoId: pedidoRef.id };
});

async function resolverInclusao(loteId: string, pedidoId: string, aceitar: boolean, entregadorId?: string) {
  const loteRef = db.doc(`lotes/${loteId}`);
  const pedidoRef = db.doc(`pedidos/${pedidoId}`);
  const resultado = await db.runTransaction(async (tx: Transaction) => {
    const [ls, ps] = await Promise.all([tx.get(loteRef), tx.get(pedidoRef)]);
    const l = ls.data();
    const pd = ps.data();
    if (!l || !pd || l.inclusaoPendente?.pedidoId !== pedidoId) return "ignorado";
    if (entregadorId && l.entregadorId !== entregadorId) throw new HttpsError("permission-denied", "Lote de outro entregador.");
    const aceitou = aceitar && l.status === "aceito";
    if (!aceitou) {
      tx.update(loteRef, { inclusaoPendente: FieldValue.delete() });
      return "despachar";
    }
    const agora = Timestamp.now();
    tx.update(loteRef, {
      inclusaoPendente: FieldValue.delete(),
      pedidoIds: FieldValue.arrayUnion(pedidoId),
      bairros: [...l.bairros, pd.destino.bairro],
      valores: [...(l.valores ?? []), pd.valorEntregaCentavos],
      valorTotalCentavos: l.valorTotalCentavos + pd.valorEntregaCentavos,
    });
    tx.update(pedidoRef, {
      loteId,
      status: "aceito",
      entregadorId: l.entregadorId,
      entregadorNome: l.entregadorNome ?? "",
      historico: FieldValue.arrayUnion({ status: "aceito", em: agora }),
    });
    return "incluido";
  });

  if (resultado === "despachar") {
    // vira um lote próprio e segue o despacho normal
    const pd = (await pedidoRef.get()).data()!;
    const { loja, dados: l } = await carregarLoja(pd.lojistaId);
    const novoLote = db.collection("lotes").doc();
    const b = db.batch();
    b.update(pedidoRef, { loteId: novoLote.id, status: "buscando" });
    b.set(novoLote, {
      lojistaId: loja.id,
      lojaNome: loja.nome,
      loja: { lat: loja.ponto.lat, lng: loja.ponto.lng, endereco: loja.endereco },
      zonaId: loja.zonaId,
      pedidoIds: [pedidoRef.id],
      bairros: [pd.destino.bairro],
      valores: [pd.valorEntregaCentavos],
      valorTotalCentavos: pd.valorEntregaCentavos,
      distanciaTotalKm: pd.distanciaKm,
      modo: l.config?.destinoPadrao ?? "geral",
      esperaEquipeSeg: l.config?.esperaEquipeSeg ?? null,
      status: "buscando",
      onda: null,
      ofertados: [],
      entregadorId: null,
      criadoEm: FieldValue.serverTimestamp(),
    });
    b.set(db.doc(`lotes/${novoLote.id}/privado/pin`), { pin: pin4(), lojistaId: loja.id });
    await b.commit();
    await executarOnda(novoLote.id, null);
  }
  return resultado;
}

export const responderInclusao = onCall(async (req) => {
  const s = exigir(req, ["entregador"]);
  const d = dados(req);
  const loteId = texto(d.loteId, "lote", { max: 80 });
  const pedidoId = texto(d.pedidoId, "pedido", { max: 80 });
  return { resultado: await resolverInclusao(loteId, pedidoId, d.aceitar === true, s.uid) };
});

export const expirarInclusao = onTaskDispatched({ retryConfig: { maxAttempts: 3 } }, async (req) => {
  const { loteId, pedidoId } = req.data as { loteId: string; pedidoId: string };
  await resolverInclusao(loteId, pedidoId, false);
});

/** Reenviar um lote que ficou sem entregador (loja ou Admin). */
export const reenviarLote = onCall(async (req) => {
  const s = exigir(req, ["lojista", "admin"]);
  const loteId = texto(dados(req).loteId, "lote", { max: 80 });
  const ref = db.doc(`lotes/${loteId}`);
  await db.runTransaction(async (tx) => {
    const l = (await tx.get(ref)).data();
    if (!l || (s.papel === "lojista" && l.lojistaId !== s.uid)) throw new HttpsError("not-found", "Lote não encontrado.");
    if (l.status !== "sem_entregador") throw new HttpsError("failed-precondition", "Este lote não está parado.");
    tx.update(ref, { status: "buscando", onda: null, ofertados: [] });
    for (const pid of l.pedidoIds as string[]) tx.update(db.doc(`pedidos/${pid}`), { status: "buscando" });
  });
  await executarOnda(loteId, null);
  logger.info("lote reenviado", { loteId, por: s.uid });
  return { ok: true };
});
