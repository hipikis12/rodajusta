// Jornada do entregador: ficar online, coletar, entregar.

import { onCall } from "firebase-functions/v2/https";
import { geohashForLocation } from "geofire-common";
import type { DocumentData } from "firebase-admin/firestore";

import {
  FieldValue,
  HttpsError,
  Timestamp,
  dados,
  db,
  diaLocal,
  exigir,
  mesLocal,
  ms,
  notificar,
  numero,
  parametros,
  semanaIso,
  texto,
  umDe,
} from "./comum.ts";
import { distanciaKm } from "./dominio/geo.ts";
import { rotaDoLote } from "./dominio/rota.ts";
import { creditoDesconto } from "./dominio/fatura.ts";

function minutosDaSessao(e: DocumentData, agora: number): number {
  const desde = ms(e.statsHoje?.onlineDesde);
  return desde ? Math.max(0, (agora - desde) / 60000) : 0;
}

// ---------------- online / pausa / offline ----------------

export const ficarOnline = onCall(async (req) => {
  const s = exigir(req, ["entregador"]);
  const d = dados(req);
  const lat = numero(d.lat, "lat", -90, 90);
  const lng = numero(d.lng, "lng", -180, 180);
  if (d.mock === true) {
    throw new HttpsError("failed-precondition", "Localização falsa detectada. Desative apps de GPS falso.", { motivo: "mock" });
  }
  const ref = db.doc(`entregadores/${s.uid}`);
  const agora = Date.now();
  const hoje = diaLocal(new Date(agora));

  const turnos = await db
    .collection("turnos")
    .where("reservados", "array-contains", s.uid)
    .where("fim", ">", Timestamp.fromMillis(agora))
    .get();
  const turnoAgora = turnos.docs.find((t) => (ms(t.get("inicio")) ?? Infinity) <= agora);

  return db.runTransaction(async (tx) => {
    const e = (await tx.get(ref)).data();
    if (!e) throw new HttpsError("not-found", "Cadastro não encontrado.");
    const bloqueio =
      e.cadastroCompleto !== true ? "cadastro_incompleto"
      : e.aprovado !== true ? "aguardando_aprovacao"
      : e.bloqueado === true ? "bloqueado"
      : e.faturaBloqueada === true ? "fatura_atrasada"
      : null;
    if (bloqueio) throw new HttpsError("failed-precondition", "Não é possível ficar online.", { motivo: bloqueio });
    if (e.loteAtivoId) return { ok: true, disponibilidade: "em_entrega" };

    const trabalhaEm = e.lojaEquipeId
      ? umDe(d.trabalhaEm, "onde trabalhar", ["loja", "geral", "ambos"] as const, "ambos")
      : "geral";
    const statsHoje = e.statsHoje?.dia === hoje ? e.statsHoje : { dia: hoje, entregas: 0, minutosOnline: 0 };
    const minutos = (statsHoje.minutosOnline ?? 0) + (e.statsHoje?.dia === hoje ? minutosDaSessao(e, agora) : 0);
    tx.update(ref, {
      disponibilidade: "disponivel",
      // a espera recomeça do zero a cada vez que fica disponível
      disponivelDesde: Timestamp.fromMillis(agora),
      trabalhaEm,
      statsHoje: { ...statsHoje, minutosOnline: minutos, onlineDesde: Timestamp.fromMillis(agora) },
      noTurnoAte: turnoAgora ? turnoAgora.get("fim") : null,
      localizacao: {
        lat,
        lng,
        geohash: geohashForLocation([lat, lng]),
        em: Timestamp.fromMillis(agora),
        precisao: typeof d.precisao === "number" ? d.precisao : null,
        mock: false,
      },
    });
    return { ok: true, disponibilidade: "disponivel" };
  });
});

async function sairDaFila(uid: string, para: "pausado" | "offline") {
  const ref = db.doc(`entregadores/${uid}`);
  const agora = Date.now();
  const hoje = diaLocal(new Date(agora));
  return db.runTransaction(async (tx) => {
    const e = (await tx.get(ref)).data();
    if (!e) throw new HttpsError("not-found", "Cadastro não encontrado.");
    if (e.loteAtivoId) throw new HttpsError("failed-precondition", "Finalize a entrega em andamento primeiro.");
    const doDia = e.statsHoje?.dia === hoje;
    const stats = {
      dia: hoje,
      entregas: doDia ? e.statsHoje.entregas ?? 0 : 0,
      minutosOnline: (doDia ? e.statsHoje.minutosOnline ?? 0 : 0) + minutosDaSessao(e, agora),
      onlineDesde: null,
    };
    tx.update(ref, { disponibilidade: para, statsHoje: stats, noTurnoAte: null });
    return stats;
  });
}

export const pausar = onCall(async (req) => {
  const s = exigir(req, ["entregador"]);
  await sairDaFila(s.uid, "pausado");
  return { ok: true };
});

export const ficarOffline = onCall(async (req) => {
  const s = exigir(req, ["entregador"]);
  const stats = await sairDaFila(s.uid, "offline");
  // resumo do dia: entregas e quanto cada loja deve deste dia
  const inicio = new Date(`${stats.dia}T00:00:00-04:00`);
  const lancs = await db
    .collection("lancamentos")
    .where("entregadorId", "==", s.uid)
    .where("tipo", "==", "entrega")
    .where("criadoEm", ">=", Timestamp.fromDate(inicio))
    .get();
  const porLoja: Record<string, { lojaNome: string; centavos: number; entregas: number }> = {};
  for (const l of lancs.docs) {
    const k = l.get("lojistaId");
    porLoja[k] ??= { lojaNome: l.get("lojaNome") ?? "", centavos: 0, entregas: 0 };
    porLoja[k].centavos += l.get("valorCentavos");
    porLoja[k].entregas += 1;
  }
  return { entregas: stats.entregas, minutosOnline: Math.round(stats.minutosOnline), porLoja: Object.values(porLoja) };
});

// ---------------- coleta ----------------

export const confirmarColeta = onCall(async (req) => {
  const s = exigir(req, ["entregador"]);
  const d = dados(req);
  const loteId = texto(d.loteId, "lote", { max: 80 });
  const pin = texto(d.pin, "PIN", { min: 4, max: 4 });
  const loteRef = db.doc(`lotes/${loteId}`);

  const r = await db.runTransaction(async (tx) => {
    const [ls, ps] = await Promise.all([tx.get(loteRef), tx.get(db.doc(`lotes/${loteId}/privado/pin`))]);
    const l = ls.data();
    if (!l || l.entregadorId !== s.uid) throw new HttpsError("not-found", "Lote não encontrado.");
    if (l.status !== "aceito") throw new HttpsError("failed-precondition", "Este lote não está aguardando coleta.");
    if (l.inclusaoPendente) throw new HttpsError("failed-precondition", "Responda o pedido de inclusão da loja antes.");
    if (ps.get("pin") !== pin) throw new HttpsError("permission-denied", "PIN incorreto. Confira com a loja.");

    const pedidos = await Promise.all((l.pedidoIds as string[]).map((id) => tx.get(db.doc(`pedidos/${id}`))));
    const destinos = pedidos.map((p) => ({ lat: p.get("destino.lat"), lng: p.get("destino.lng") }));
    const rota = rotaDoLote({ lat: l.loja.lat, lng: l.loja.lng }, destinos);
    const agora = Timestamp.now();
    tx.update(loteRef, {
      status: "coletado",
      coletadoEm: agora,
      rotaUrl: rota.url,
      ordem: rota.ordem.map((i) => pedidos[i].id),
    });
    for (const p of pedidos) {
      tx.update(p.ref, {
        status: "coletado",
        // a integração com o iFood avisa o cliente quando vê esta marca
        ...(p.get("origem") === "ifood" ? { ifoodDespacho: "pendente" } : {}),
        historico: FieldValue.arrayUnion({ status: "coletado", em: agora }),
      });
    }
    return { rotaUrl: rota.url, lojistaId: l.lojistaId as string };
  });

  await notificar(r.lojistaId, "Pedido coletado", "O entregador saiu para entrega.", { tipo: "coletado", loteId });
  return { rotaUrl: r.rotaUrl };
});

// ---------------- conclusão ----------------

async function incentivosAtivos(zonaId: string, agora: number) {
  const snap = await db
    .collection("incentivos")
    .where("zonaId", "in", [zonaId, "todas"])
    .where("status", "==", "ativo")
    .get();
  return snap.docs.filter((i) => (ms(i.get("inicio")) ?? 0) <= agora && agora <= (ms(i.get("fim")) ?? 0));
}

async function finalizarPedido(uid: string, pedidoId: string, resultado: "entregue" | "nao_entregue", extra: DocumentData) {
  const p = await parametros();
  const pedidoRef = db.doc(`pedidos/${pedidoId}`);
  const pre = (await pedidoRef.get()).data();
  if (!pre || pre.entregadorId !== uid) throw new HttpsError("not-found", "Pedido não encontrado.");
  const agora = Date.now();
  const ativos = resultado === "entregue" ? await incentivosAtivos(pre.zonaId ?? "padrao", agora) : [];
  const mes = mesLocal(new Date(agora));
  const semana = semanaIso(new Date(agora));
  const hoje = diaLocal(new Date(agora));

  const fim = await db.runTransaction(async (tx) => {
    const ped = (await tx.get(pedidoRef)).data();
    if (!ped || ped.entregadorId !== uid) throw new HttpsError("not-found", "Pedido não encontrado.");
    if (ped.status !== "coletado") throw new HttpsError("failed-precondition", "Pedido não está em rota.");
    const loteRef = db.doc(`lotes/${ped.loteId}`);
    const entRef = db.doc(`entregadores/${uid}`);
    const faturaRef = db.doc(`faturas/${uid}_${mes}`);
    const semanaRef = db.doc(`semanas/${uid}_${semana}`);
    const [ls, es, fs] = await Promise.all([tx.get(loteRef), tx.get(entRef), tx.get(faturaRef)]);
    const l = ls.data()!;
    const e = es.data()!;
    const outros = await Promise.all(
      (l.pedidoIds as string[]).filter((id) => id !== pedidoId).map((id) => tx.get(db.doc(`pedidos/${id}`))),
    );

    const ts = Timestamp.fromMillis(agora);
    tx.update(pedidoRef, { status: resultado, finalizadoEm: ts, ...extra, historico: FieldValue.arrayUnion({ status: resultado, em: ts }) });

    let entregou = 0;
    if (resultado === "entregue") {
      entregou = 1;
      const base = { lojistaId: ped.lojistaId, lojaNome: ped.lojaNome, entregadorId: uid, entregadorNome: e.nome ?? "", pedidoId, criadoEm: ts };
      tx.set(db.collection("lancamentos").doc(), { ...base, tipo: "entrega", valorCentavos: ped.valorEntregaCentavos, descricao: ped.descricao });
      let repasse = 0;
      if (ped.pagamento?.tipo === "cobrar" && ped.pagamento.valorCobrarCentavos > 0) {
        repasse = ped.pagamento.valorCobrarCentavos;
        tx.set(db.collection("lancamentos").doc(), { ...base, tipo: "repasse", valorCentavos: repasse, descricao: `Cobrado do cliente: ${ped.descricao}` });
      }
      tx.set(
        db.doc(`acertos/${ped.lojistaId}_${uid}`),
        {
          lojistaId: ped.lojistaId,
          lojaNome: ped.lojaNome,
          entregadorId: uid,
          entregadorNome: e.nome ?? "",
          entregasCentavos: FieldValue.increment(ped.valorEntregaCentavos),
          repassesCentavos: FieldValue.increment(repasse),
          saldoCentavos: FieldValue.increment(ped.valorEntregaCentavos - repasse),
          qtdEntregas: FieldValue.increment(1),
          atualizadoEm: ts,
        },
        { merge: true },
      );

      // fatura da plataforma do mês
      const descontos = ativos.filter((i) => i.get("modo") === "desconto");
      const credito = e.isento ? 0 : Math.min(
        p.taxa.porEntregaCentavos,
        descontos.reduce((s, i) => s + creditoDesconto(i.get("percentual"), p.taxa.porEntregaCentavos), 0),
      );
      if (!fs.exists) {
        tx.set(faturaRef, {
          entregadorId: uid,
          entregadorNome: e.nome ?? "",
          mes,
          plano: e.plano ?? "por_entrega",
          isento: e.isento === true,
          entregas: 1,
          creditosCentavos: credito,
          status: "aberta",
        });
      } else {
        tx.update(faturaRef, { entregas: FieldValue.increment(1), creditosCentavos: FieldValue.increment(credito) });
      }
      if (credito > 0) {
        tx.set(faturaRef.collection("creditos").doc(), {
          incentivoIds: descontos.map((i) => i.id),
          pedidoId,
          valorCentavos: credito,
          em: ts,
        });
      }
      const bonus = ativos.filter((i) => i.get("modo") === "bonus");
      tx.set(
        semanaRef,
        {
          entregadorId: uid,
          semana,
          plano: e.plano ?? "por_entrega",
          entregas: FieldValue.increment(1),
          porIncentivo: Object.fromEntries(bonus.map((i) => [i.id, FieldValue.increment(1)])),
        },
        { merge: true },
      );
    }

    const terminados = outros.every((o) => ["entregue", "nao_entregue", "cancelado"].includes(o.get("status")));
    const stats = e.statsHoje?.dia === hoje ? e.statsHoje : { dia: hoje, entregas: 0, minutosOnline: 0, onlineDesde: Timestamp.fromMillis(agora) };
    const novoStats = { ...stats, entregas: (stats.entregas ?? 0) + entregou };
    if (terminados) {
      tx.update(loteRef, { status: "concluido", concluidoEm: ts });
      tx.update(entRef, {
        statsHoje: novoStats,
        loteAtivoId: FieldValue.delete(),
        disponibilidade: "disponivel",
        disponivelDesde: ts,
      });
    } else {
      tx.update(entRef, { statsHoje: novoStats });
    }
    return { terminados, lojistaId: ped.lojistaId as string, descricao: ped.descricao as string };
  });

  await notificar(
    fim.lojistaId,
    resultado === "entregue" ? "Pedido entregue" : "Pedido não entregue",
    resultado === "entregue" ? fim.descricao : `${fim.descricao} — voltando para a loja`,
    { tipo: resultado, pedidoId },
  );
  return { loteConcluido: fim.terminados };
}

export const concluirEntrega = onCall(async (req) => {
  const s = exigir(req, ["entregador"]);
  const d = dados(req);
  const pedidoId = texto(d.pedidoId, "pedido", { max: 80 });
  const lat = numero(d.lat, "lat", -90, 90);
  const lng = numero(d.lng, "lng", -180, 180);
  if (d.mock === true) throw new HttpsError("failed-precondition", "Localização falsa detectada.");
  const p = await parametros();
  const ped = (await db.doc(`pedidos/${pedidoId}`).get()).data();
  if (!ped || ped.entregadorId !== s.uid) throw new HttpsError("not-found", "Pedido não encontrado.");
  const metros = distanciaKm({ lat, lng }, ped.destino) * 1000;
  if (metros > p.raioEntregaM) {
    throw new HttpsError("failed-precondition", `Você está a ${Math.round(metros)} m do destino. Chegue mais perto para finalizar.`, {
      motivo: "longe",
      metros: Math.round(metros),
    });
  }
  return finalizarPedido(s.uid, pedidoId, "entregue", { entregaLocal: { lat, lng, metros: Math.round(metros) } });
});

export const naoEntregue = onCall(async (req) => {
  const s = exigir(req, ["entregador"]);
  const d = dados(req);
  const pedidoId = texto(d.pedidoId, "pedido", { max: 80 });
  const motivo = umDe(d.motivo, "motivo", ["cliente_ausente", "endereco_errado", "recusado", "outro"] as const);
  return finalizarPedido(s.uid, pedidoId, "nao_entregue", { motivoNaoEntrega: motivo });
});

/** Cancela pedidos de um lote antes da coleta. */
export const cancelarLote = onCall(async (req) => {
  const s = exigir(req, ["lojista", "admin"]);
  const loteId = texto(dados(req).loteId, "lote", { max: 80 });
  const ref = db.doc(`lotes/${loteId}`);
  const entregadorId = await db.runTransaction(async (tx) => {
    const l = (await tx.get(ref)).data();
    if (!l || (s.papel === "lojista" && l.lojistaId !== s.uid)) throw new HttpsError("not-found", "Lote não encontrado.");
    if (!["buscando", "aceito", "sem_entregador"].includes(l.status)) {
      throw new HttpsError("failed-precondition", "Depois da coleta não dá para cancelar.");
    }
    const ts = Timestamp.now();
    tx.update(ref, { status: "cancelado", canceladoEm: ts, canceladoPor: s.uid });
    for (const pid of l.pedidoIds as string[]) {
      tx.update(db.doc(`pedidos/${pid}`), { status: "cancelado", historico: FieldValue.arrayUnion({ status: "cancelado", em: ts }) });
    }
    if (l.entregadorId) {
      tx.update(db.doc(`entregadores/${l.entregadorId}`), {
        loteAtivoId: FieldValue.delete(),
        disponibilidade: "disponivel",
        // quem perdeu a corrida não volta para o fim da fila
        disponivelDesde: l.aceitoEm ?? ts,
      });
    }
    return (l.entregadorId as string | null) ?? null;
  });
  if (entregadorId) await notificar(entregadorId, "Entrega cancelada", "A loja cancelou o pedido antes da coleta.", { tipo: "cancelado", loteId });
  return { ok: true };
});
