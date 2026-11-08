// Testes das regras do Firestore. Rodam no emulador:
//   firebase emulators:exec --only firestore "npm --prefix rules-tests test"

import { after, before, beforeEach, test } from "node:test";
import { readFileSync } from "node:fs";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import type { RulesTestEnvironment } from "@firebase/rules-unit-testing";
import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from "firebase/firestore";

let env: RulesTestEnvironment;

const LOJA = { papel: "lojista", aprovado: true };
const ENT = { papel: "entregador", aprovado: true };

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "rodajusta-teste",
    firestore: { rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8") },
  });
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "lojistas/loja1"), {
      nomeFantasia: "Pizzaria Sol",
      config: { valorModo: "fixo", valorFixoCentavos: 700, faixas: [], destinoPadrao: "geral", envioAutomatico: false },
    });
    await setDoc(doc(db, "entregadores/ent1"), { nome: "Ana", disponibilidade: "disponivel", aprovado: true });
    await setDoc(doc(db, "entregadores/ent2"), { nome: "Bia", disponibilidade: "offline", aprovado: true });
    await setDoc(doc(db, "lotes/lote1"), { lojistaId: "loja1", entregadorId: "ent1", status: "aceito" });
    await setDoc(doc(db, "lotes/lote1/privado/pin"), { pin: "1234", lojistaId: "loja1" });
    await setDoc(doc(db, "pedidos/p1"), { lojistaId: "loja1", entregadorId: "ent1", status: "aceito" });
    await setDoc(doc(db, "pedidos/p2"), { lojistaId: "loja1", entregadorId: null, status: "buscando" });
    await setDoc(doc(db, "ofertas/lote2_ent2"), { entregadorId: "ent2", bairros: ["Centro"], status: "pendente" });
    await setDoc(doc(db, "faturas/ent1_2026-11"), { entregadorId: "ent1", entregas: 3 });
    await setDoc(doc(db, "config/parametros"), { taxa: { porEntregaCentavos: 80 } });
  });
});

const como = (uid: string, claims: object) => env.authenticatedContext(uid, claims).firestore();

test("visitante não lê nada", async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, "config/parametros")));
  await assertFails(getDoc(doc(db, "pedidos/p1")));
});

test("loja lê os próprios pedidos e o PIN; não altera status", async () => {
  const db = como("loja1", LOJA);
  await assertSucceeds(getDocs(query(collection(db, "pedidos"), where("lojistaId", "==", "loja1"))));
  await assertSucceeds(getDoc(doc(db, "lotes/lote1/privado/pin")));
  await assertFails(updateDoc(doc(db, "pedidos/p1"), { status: "entregue" }));
  await assertFails(setDoc(doc(db, "pedidos/novo"), { lojistaId: "loja1", status: "buscando" }));
});

test("entregador não vê o PIN nem pedido que ainda não aceitou", async () => {
  const db = como("ent1", ENT);
  await assertSucceeds(getDoc(doc(db, "pedidos/p1")));
  await assertFails(getDoc(doc(db, "lotes/lote1/privado/pin")));
  await assertFails(getDoc(doc(db, "pedidos/p2")));
});

test("oferta só é visível para o entregador dela", async () => {
  await assertSucceeds(getDoc(doc(como("ent2", ENT), "ofertas/lote2_ent2")));
  await assertFails(getDoc(doc(como("ent1", ENT), "ofertas/lote2_ent2")));
});

test("entregador envia localização válida enquanto disponível", async () => {
  const db = como("ent1", ENT);
  await assertSucceeds(
    updateDoc(doc(db, "entregadores/ent1"), {
      localizacao: { lat: -9.91, lng: -63.04, geohash: "6qz8m4", em: serverTimestamp(), precisao: 8, mock: false },
    }),
  );
});

test("localização: recusa offline, campos extras e mexer em outros campos", async () => {
  const loc = { lat: -9.91, lng: -63.04, geohash: "6qz8m4", em: serverTimestamp(), precisao: 8, mock: false };
  await assertFails(updateDoc(doc(como("ent2", ENT), "entregadores/ent2"), { localizacao: loc }));
  await assertFails(updateDoc(doc(como("ent1", ENT), "entregadores/ent1"), { localizacao: { ...loc, extra: 1 } }));
  await assertFails(updateDoc(doc(como("ent1", ENT), "entregadores/ent1"), { aprovado: true }));
  await assertFails(updateDoc(doc(como("ent1", ENT), "entregadores/ent2"), { localizacao: loc }));
});

test("loja salva configuração válida e não salva inválida", async () => {
  const db = como("loja1", LOJA);
  const ok = { valorModo: "fixo", valorFixoCentavos: 800, faixas: [], destinoPadrao: "equipe_primeiro", envioAutomatico: true, esperaEquipeSeg: 60 };
  await assertSucceeds(updateDoc(doc(db, "lojistas/loja1"), { config: ok }));
  await assertFails(updateDoc(doc(db, "lojistas/loja1"), { config: { ...ok, valorFixoCentavos: -5 } }));
  await assertFails(updateDoc(doc(db, "lojistas/loja1"), { config: ok, aprovado: true }));
});

test("loja liga a recepção de comandas (Bluetooth, BLE, rede) e o repasse por IP", async () => {
  const db = como("loja1", LOJA);
  const cfg = {
    valorModo: "fixo", valorFixoCentavos: 700, faixas: [], destinoPadrao: "geral", envioAutomatico: false,
    impressoraAtiva: true, receberBluetooth: true, receberBle: false, receberRede: true, repassarPara: "192.168.100.200:9100",
  };
  await assertSucceeds(updateDoc(doc(db, "lojistas/loja1"), { config: cfg }));
  await assertFails(updateDoc(doc(db, "lojistas/loja1"), { config: { ...cfg, receberRede: "sim" } }));
});

test("amostras de comanda: loja grava a sua, só o admin lê", async () => {
  const amostra = { lojistaId: "loja1", textoBruto: "PEDIDO 1", extraido: {}, corrigido: {}, em: serverTimestamp() };
  await assertSucceeds(setDoc(doc(como("loja1", LOJA), "amostrasComanda/a1"), amostra));
  await assertFails(setDoc(doc(como("loja2", LOJA), "amostrasComanda/a2"), amostra));
  await assertFails(getDoc(doc(como("loja1", LOJA), "amostrasComanda/a1")));
  await assertSucceeds(getDoc(doc(como("adm", { papel: "admin", aprovado: true }), "amostrasComanda/a1")));
});

test("comandas: loja cria e descarta as suas", async () => {
  const db = como("loja1", LOJA);
  await assertSucceeds(setDoc(doc(db, "lojistas/loja1/comandas/c1"), { origem: "comanda", status: "pendente", descricao: "x" }));
  await assertSucceeds(updateDoc(doc(db, "lojistas/loja1/comandas/c1"), { status: "descartada" }));
  await assertFails(setDoc(doc(db, "lojistas/loja1/comandas/c2"), { origem: "ifood", status: "pendente" }));
  await assertFails(setDoc(doc(como("loja2", LOJA), "lojistas/loja1/comandas/c3"), { origem: "comanda", status: "pendente" }));
});

test("fatura só para o dono; parâmetros para qualquer logado", async () => {
  await assertSucceeds(getDoc(doc(como("ent1", ENT), "faturas/ent1_2026-11")));
  await assertFails(getDoc(doc(como("ent2", ENT), "faturas/ent1_2026-11")));
  await assertSucceeds(getDoc(doc(como("ent2", ENT), "config/parametros")));
});

test("admin lê tudo, mas não escreve pelo app", async () => {
  const db = como("adm", { papel: "admin", aprovado: true });
  await assertSucceeds(getDoc(doc(db, "pedidos/p2")));
  await assertSucceeds(getDoc(doc(db, "lotes/lote1/privado/pin")));
  await assertFails(updateDoc(doc(db, "pedidos/p2"), { status: "cancelado" }));
});
