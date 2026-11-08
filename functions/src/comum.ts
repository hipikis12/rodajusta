import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { getFunctions } from "firebase-admin/functions";
import { HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { logger, setGlobalOptions } from "firebase-functions/v2";

import { mesclarParametros } from "./dominio/parametros.ts";
import type { Parametros } from "./dominio/parametros.ts";
import { distanciaKm } from "./dominio/geo.ts";

if (!getApps().length) initializeApp();

export const db = getFirestore();
export { FieldValue, Timestamp, HttpsError, logger };

export const REGIAO = "southamerica-east1";
// definido aqui (e não no index) porque em ESM os módulos carregam antes do index
setGlobalOptions({ region: REGIAO, maxInstances: 10 });
export const FUSO = "America/Porto_Velho";

export type Papel = "lojista" | "entregador" | "admin";

export interface Sessao {
  uid: string;
  papel: Papel;
  aprovado: boolean;
  email?: string;
}

export function sessao(req: CallableRequest<unknown>): Sessao {
  if (!req.auth) throw new HttpsError("unauthenticated", "Faça login para continuar.");
  const t = req.auth.token as Record<string, unknown>;
  return {
    uid: req.auth.uid,
    papel: t.papel as Papel,
    aprovado: t.aprovado === true,
    email: typeof t.email === "string" ? t.email : undefined,
  };
}

export function exigir(req: CallableRequest<unknown>, papeis: Papel[], aprovado = true): Sessao {
  const s = sessao(req);
  if (!s.papel || !papeis.includes(s.papel)) {
    throw new HttpsError("permission-denied", "Seu perfil não pode fazer isso.");
  }
  if (aprovado && s.papel !== "admin" && !s.aprovado) {
    throw new HttpsError("failed-precondition", "Cadastro ainda não aprovado.");
  }
  return s;
}

export function dados(req: CallableRequest<unknown>): Record<string, unknown> {
  return (req.data && typeof req.data === "object" ? req.data : {}) as Record<string, unknown>;
}

// ---------- validação de entrada ----------

export function texto(
  v: unknown,
  campo: string,
  o: { min?: number; max?: number; opcional?: boolean } = {},
): string {
  if ((v === undefined || v === null || v === "") && o.opcional) return "";
  if (typeof v !== "string") throw new HttpsError("invalid-argument", `Campo ${campo} inválido.`);
  const s = v.trim();
  if (s.length < (o.min ?? 1) || s.length > (o.max ?? 300)) {
    throw new HttpsError("invalid-argument", `Campo ${campo} com tamanho inválido.`);
  }
  return s;
}

export function numero(v: unknown, campo: string, min: number, max: number): number {
  if (typeof v !== "number" || !Number.isFinite(v) || v < min || v > max) {
    throw new HttpsError("invalid-argument", `Campo ${campo} inválido.`);
  }
  return v;
}

export function inteiro(v: unknown, campo: string, min: number, max: number): number {
  const n = numero(v, campo, min, max);
  if (!Number.isInteger(n)) throw new HttpsError("invalid-argument", `Campo ${campo} deve ser inteiro.`);
  return n;
}

export function umDe<T extends string>(v: unknown, campo: string, opcoes: readonly T[], padrao?: T): T {
  if ((v === undefined || v === null) && padrao !== undefined) return padrao;
  if (typeof v !== "string" || !opcoes.includes(v as T)) {
    throw new HttpsError("invalid-argument", `Campo ${campo} inválido.`);
  }
  return v as T;
}

export function soDigitos(s: string): string {
  return s.replace(/\D/g, "");
}

export function cpfValido(cpf: string): boolean {
  const c = soDigitos(cpf);
  if (c.length !== 11 || /^(\d)\1{10}$/.test(c)) return false;
  const dv = (n: number) => {
    let soma = 0;
    for (let i = 0; i < n; i++) soma += Number(c[i]) * (n + 1 - i);
    const r = (soma * 10) % 11;
    return r === 10 ? 0 : r;
  };
  return dv(9) === Number(c[9]) && dv(10) === Number(c[10]);
}

// ---------- parâmetros ----------

let cacheParametros: { p: Parametros; em: number } | null = null;

export async function parametros(): Promise<Parametros> {
  if (cacheParametros && Date.now() - cacheParametros.em < 60_000) return cacheParametros.p;
  const snap = await db.doc("config/parametros").get();
  const p = mesclarParametros(snap.exists ? (snap.data() as never) : null);
  cacheParametros = { p, em: Date.now() };
  return p;
}

// ---------- datas no fuso local ----------

function partes(d: Date): Record<string, string> {
  const f = new Intl.DateTimeFormat("en-CA", {
    timeZone: FUSO,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
    weekday: "short",
  });
  return Object.fromEntries(f.formatToParts(d).map((p) => [p.type, p.value]));
}

export const diaLocal = (d = new Date()) => {
  const p = partes(d);
  return `${p.year}-${p.month}-${p.day}`;
};

export const mesLocal = (d = new Date()) => {
  const p = partes(d);
  return `${p.year}-${p.month}`;
};

export function mesAnterior(mes: string): string {
  const [a, m] = mes.split("-").map(Number);
  return m === 1 ? `${a - 1}-12` : `${a}-${String(m - 1).padStart(2, "0")}`;
}

/** Semana ISO (ex.: 2026-W45) da data no fuso local. */
export function semanaIso(d = new Date()): string {
  const [a, m, dia] = diaLocal(d).split("-").map(Number);
  const t = new Date(Date.UTC(a, m - 1, dia));
  const diaSemana = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - diaSemana);
  const inicioAno = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  const semana = Math.ceil(((t.getTime() - inicioAno.getTime()) / 86400000 + 1) / 7);
  return `${t.getUTCFullYear()}-W${String(semana).padStart(2, "0")}`;
}

export function horaLocal(d = new Date()): number {
  return Number(partes(d).hour);
}

// ---------- notificações ----------

export async function notificar(
  uid: string,
  titulo: string,
  corpo: string,
  extra: Record<string, string> = {},
  urgente = false,
): Promise<void> {
  try {
    const u = await db.doc(`users/${uid}`).get();
    const token = u.get("fcmToken") as string | undefined;
    if (!token) return;
    await getMessaging().send({
      token,
      notification: { title: titulo, body: corpo },
      data: extra,
      android: {
        priority: "high",
        notification: { channelId: urgente ? "ofertas" : "geral", defaultSound: true },
      },
    });
  } catch (e) {
    logger.warn("notificação falhou", { uid, erro: String(e) });
  }
}

export async function notificarTopico(topico: string, titulo: string, corpo: string): Promise<void> {
  try {
    await getMessaging().send({ topic: topico, notification: { title: titulo, body: corpo } });
  } catch (e) {
    logger.warn("notificação de tópico falhou", { topico, erro: String(e) });
  }
}

// ---------- fila de tarefas (atrasos de 30 s) ----------

export async function agendar(funcao: string, dadosTarefa: Record<string, unknown>, segundos: number) {
  const fila = getFunctions().taskQueue(`locations/${REGIAO}/functions/${funcao}`);
  await fila.enqueue(dadosTarefa, { scheduleDelaySeconds: Math.max(1, Math.ceil(segundos)) });
}

// ---------- auditoria ----------

export async function auditar(
  quem: string,
  acao: string,
  alvo: string,
  detalhes: Record<string, unknown> = {},
): Promise<void> {
  await db.collection("auditoria").add({ quem, acao, alvo, detalhes, em: FieldValue.serverTimestamp() });
}

// ---------- zonas ----------

export async function zonaDoPonto(lat: number, lng: number): Promise<string> {
  const zonas = await db.collection("zonas").where("ativa", "==", true).get();
  let melhor = { id: "padrao", d: Infinity };
  for (const z of zonas.docs) {
    const d = distanciaKm({ lat, lng }, { lat: z.get("lat"), lng: z.get("lng") });
    if (d <= (z.get("raioKm") ?? 10) && d < melhor.d) melhor = { id: z.id, d };
  }
  return melhor.id;
}

export function ms(v: unknown): number | null {
  if (v instanceof Timestamp) return v.toMillis();
  if (typeof v === "number") return v;
  return null;
}
