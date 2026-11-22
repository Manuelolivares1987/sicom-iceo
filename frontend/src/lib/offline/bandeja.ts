// ============================================================================
// Bandeja de salida de terreno (F3, 20-11-2026) — el «reloj ⏱» de WhatsApp
// ----------------------------------------------------------------------------
// Toda acción que se hace sin señal queda acá con su identificador (el mismo
// que recibe el servidor: reintentar nunca duplica). Se sube sola cuando hay
// señal y sesión. Reglas:
//   · sin señal / sin sesión / error de red o de permisos de sesión → espera
//     y reintenta (1, 2, 5, 15, 30 min). Nunca se marca «rechazado» por eso.
//   · el servidor dice que ya existía (23505) → se da por subido.
//   · el servidor la rechaza por una regla de negocio → «rechazada», a la vista
//     en «Pendientes» con el motivo, para que alguien decida.
// Las colas que ya existían (pauta, despacho, bodega, bitácora, entrega) siguen
// con su lógica; «Pendientes» las muestra todas juntas.
// ============================================================================

import Dexie, { type Table } from 'dexie'
import { haySesionServidor, leerSesionPersistida } from '@/lib/supabase'
import { estaEnLinea } from '@/lib/conectividad'

export type EstadoEnvio = 'pendiente' | 'enviando' | 'rechazada'

export type OperacionBandeja = {
  id: string                       // identificador = client_uuid que va al servidor
  tipo: string                     // 'franke-carga', …
  resumen: string                  // lo que ve la persona en «Pendientes»
  payload: Record<string, unknown>
  blobs?: Record<string, Blob>     // fotos/firmas; se suben antes del registro
  subidas?: Record<string, string> // url de cada blob ya subido (no se re-sube)
  estado: EstadoEnvio
  intentos: number
  proximo_at: number               // epoch ms del próximo intento
  error?: string | null
  usuario_id: string | null
  creado_at: string
}

class BandejaDB extends Dexie {
  ops!: Table<OperacionBandeja, string>
  constructor() {
    super('sicom-bandeja')
    this.version(1).stores({ ops: 'id, tipo, estado, proximo_at, creado_at' })
  }
}
let _db: BandejaDB | null = null
const db = () => (_db ??= new BandejaDB())

/** Lo que sabe hacer cada tipo: subir sus blobs (si tiene) y registrar. */
export type Manejador = (op: OperacionBandeja, subirBlob: (clave: string, subir: (b: Blob) => Promise<string>) => Promise<string | null>) => Promise<void>
const manejadores = new Map<string, Manejador>()
export function registrarTipo(tipo: string, m: Manejador) { manejadores.set(tipo, m) }

const ESPERAS_MIN = [1, 2, 5, 15, 30]
const EVENTO = 'sicom:bandeja'
export const EVENTO_BANDEJA = EVENTO
const avisar = () => { try { window.dispatchEvent(new Event(EVENTO)) } catch { /* sin window */ } }

export async function encolar(op: Pick<OperacionBandeja, 'id' | 'tipo' | 'resumen' | 'payload' | 'blobs'>): Promise<void> {
  const ya = await db().ops.get(op.id)
  if (ya) return // mismo identificador = misma acción: no se duplica
  await db().ops.put({
    ...op, estado: 'pendiente', intentos: 0, proximo_at: 0, error: null, subidas: {},
    usuario_id: leerSesionPersistida()?.user.id ?? null, creado_at: new Date().toISOString(),
  })
  avisar()
}

export async function listarBandeja(tipo?: string): Promise<OperacionBandeja[]> {
  try {
    const todas = await db().ops.orderBy('creado_at').toArray()
    return tipo ? todas.filter((o) => o.tipo === tipo) : todas
  } catch { return [] }
}

export async function contarBandeja(): Promise<number> {
  try { return await db().ops.count() } catch { return 0 }
}

export async function descartar(id: string): Promise<void> { await db().ops.delete(id); avisar() }

export async function reintentarYa(id: string): Promise<void> {
  await db().ops.update(id, { estado: 'pendiente', proximo_at: 0, error: null })
  avisar()
  void sincronizarBandeja(true)
}

// ── Clasificación de errores ────────────────────────────────────────────────
const msg = (e: unknown) => (e instanceof Error ? e.message
  : typeof e === 'object' && e && 'message' in e ? String((e as { message: unknown }).message) : String(e))
const codigo = (e: unknown) => (typeof e === 'object' && e && 'code' in e ? String((e as { code: unknown }).code ?? '') : '')

/** Señal, sesión o servidor caído: se arregla esperando. */
export function esTransitorio(e: unknown): boolean {
  const c = codigo(e), m = msg(e).toLowerCase()
  return !c || c === '42501' || c.startsWith('PGRST3') || c === '401' || c === '403' || c.startsWith('5')
    || /fetch|network|timeout|tiempo|jwt|token|abort|failed to|load failed|conexi|no autorizado|not authorized|permission/.test(m)
}
export const esDuplicado = (e: unknown) => codigo(e) === '23505'

/** [22-11-2026] Solo la red caída o lenta (más estricto que esTransitorio: un
 *  error sin código armado por la app —p. ej. «falta la foto»— NO es señal). */
export function esFallaDeRed(e: unknown): boolean {
  const c = codigo(e), m = msg(e).toLowerCase()
  return /^5\d\d$/.test(c) || c.startsWith('PGRST3') || c === '401' || c === '408'
    || /failed to fetch|fetch failed|networkerror|network|timeout|tiempo|abort|load failed|conexi|jwt|token|sin señal/.test(m)
}

// ── Envío ───────────────────────────────────────────────────────────────────
let enCurso: Promise<number> | null = null
let otraVuelta = false

/** Sube lo que toca. Un solo envío a la vez; lo que llega mientras, en la vuelta siguiente. */
export function sincronizarBandeja(forzar = false): Promise<number> {
  if (enCurso) { otraVuelta = true; return enCurso }
  enCurso = (async () => {
    let ok = 0
    do {
      otraVuelta = false
      ok += await vuelta(forzar)
    } while (otraVuelta)
    return ok
  })().finally(() => { enCurso = null })
  return enCurso
}

async function vuelta(forzar: boolean): Promise<number> {
  if (!estaEnLinea() || !haySesionServidor()) return 0
  let ok = 0
  const ahora = Date.now()
  const ops = (await listarBandeja()).filter((o) => o.estado !== 'rechazada' && (forzar || o.proximo_at <= ahora))
  for (const op of ops) {
    const m = manejadores.get(op.tipo)
    if (!m) continue // el tipo se registra al cargar su pantalla o el sincronizador
    if (!estaEnLinea() || !haySesionServidor()) break
    await db().ops.update(op.id, { estado: 'enviando' })
    const subidas: Record<string, string> = { ...(op.subidas ?? {}) }
    const subirBlob = async (clave: string, subir: (b: Blob) => Promise<string>) => {
      if (subidas[clave]) return subidas[clave]
      const b = op.blobs?.[clave]
      if (!b) return null
      const url = await subir(b)
      subidas[clave] = url
      await db().ops.update(op.id, { subidas })
      return url
    }
    try {
      await m({ ...op, subidas }, subirBlob)
      await db().ops.delete(op.id)
      ok++
    } catch (e) {
      if (esDuplicado(e)) { await db().ops.delete(op.id); ok++; continue }
      const intentos = op.intentos + 1
      if (esTransitorio(e)) {
        const espera = ESPERAS_MIN[Math.min(intentos - 1, ESPERAS_MIN.length - 1)] * 60_000
        await db().ops.update(op.id, { estado: 'pendiente', intentos, proximo_at: Date.now() + espera, error: msg(e) })
        if (!estaEnLinea()) break
      } else {
        await db().ops.update(op.id, { estado: 'rechazada', intentos, error: msg(e) })
      }
    }
  }
  avisar()
  return ok
}
