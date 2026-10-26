// Lógica offline-first de la app de terreno ENEX.
// - Cache de pendientes por período y de los ítems de cada pauta.
// - Cola de ejecuciones (resultados + fotos + firmas) que sube al reconectar.
// - Overlay: refleja lo pendiente sobre la cache para la UI.

import {
  getTerrenoPendientes, getPautaItems, ejecutarPauta, getEjecucionItems, getPendientePorId,
  subirEvidenciaEnex, subirFirmaEnex, getPlanTareasDia, guardarRepuestosEnex,
  terrenoCamion, terrenoServicio, porReprogramar, zonaTerreno, getTerrenoInstalaciones, getLugarItemsTodas,
  type EnexPendiente, type EnexPautaItem, type EnexItemResultado, type EnexPlanTarea,
  type EnexTerrenoInstalacion, type EnexLugarItem, type TipoServicio,
} from '@/lib/services/enex'
import { withTimeout } from '@/lib/upload/with-timeout'
import { enexDB, newId, type EnexPending, type EnexPendItem, type EnexDraft, type EnexRepuesto } from './enex-db'

const isOnline = () => (typeof navigator === 'undefined' ? true : navigator.onLine)
const keyPend = (a: number, m: number) => `pend:${a}-${m}`
const keyItems = (pautaId: string) => `items:${pautaId}`

/**
 * Techo de espera para leer del servidor antes de conformarse con lo
 * descargado.
 *
 * `navigator.onLine` dice "en línea" también cuando el teléfono está pegado a
 * una antena que no cursa datos —lo habitual en faena—, y ahí la petición no
 * falla: se queda esperando. Sin este techo la pantalla se quedaba en
 * "Cargando…" para siempre teniendo la información en el equipo.
 */
const LECTURA_TIMEOUT_MS = 8000

function conTimeout<T>(p: Promise<T>, ms = LECTURA_TIMEOUT_MS): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout de red')), ms)
    p.then((v) => { clearTimeout(t); resolve(v) }, (e) => { clearTimeout(t); reject(e) })
  })
}

// ── Pendientes por período ───────────────────────────────────────────────
export async function getPendientesOffline(anio: number, mes: number): Promise<EnexPendiente[]> {
  let base: EnexPendiente[]
  if (isOnline()) {
    try {
      base = await conTimeout(getTerrenoPendientes(anio, mes))
      await enexDB().cache.put({ key: keyPend(anio, mes), value: base, updated_at: new Date().toISOString() })
    } catch { base = await getCachedPend(anio, mes) }
  } else {
    base = await getCachedPend(anio, mes)
  }
  // [MIG651] Lo hecho en terreno que todavía no llega: servicios nuevos,
  // patentes anotadas y «no se hizo».
  base = await aplicarCambiosTerreno(base, { anio, mes })
  // Overlay: marcar como ejecutada/cumplida lo que está en cola local
  const pend = await enexDB().pending.toArray()
  if (pend.length === 0) return base
  const porProg = new Map(pend.map((p) => [p.programacion_id, p]))
  return base.map((r) => {
    const p = porProg.get(r.programacion_id)
    if (!p) return r
    return { ...r, estado: p.con_mandante ? 'cumplida' : 'ejecutada', cumplida: r.cumplida || p.con_mandante }
  })
}
async function getCachedPend(anio: number, mes: number): Promise<EnexPendiente[]> {
  const row = await enexDB().cache.get(keyPend(anio, mes))
  return (row?.value as EnexPendiente[]) ?? []
}

/**
 * Un servicio por su id, venga del mes que venga: primero en las caches de
 * cualquier período, después al servidor. La pantalla de ejecución solo miraba
 * el mes en curso, así que un trabajo de julio a medias quedaba inalcanzable
 * el 1 de agosto.
 */
export async function getPendienteOffline(programacionId: string): Promise<EnexPendiente | null> {
  const aplicarCola = async (r: EnexPendiente): Promise<EnexPendiente> => {
    const p = await enexDB().pending.where('programacion_id').equals(programacionId).first()
    if (!p) return r
    return { ...r, estado: p.con_mandante ? 'cumplida' : 'ejecutada', cumplida: r.cumplida || p.con_mandante }
  }
  const conCambios = async (r: EnexPendiente) => aplicarCola((await aplicarCambiosTerreno([r]))[0])
  if (isOnline()) {
    try {
      const r = await conTimeout(getPendientePorId(programacionId))
      if (r) return conCambios(r)
    } catch { /* cae a la cache */ }
  }
  const cacheados = await enexDB().cache.where('key').startsWith('pend:').toArray()
  for (const row of cacheados) {
    const hit = ((row.value as EnexPendiente[]) ?? []).find((r) => r.programacion_id === programacionId)
    if (hit) return conCambios(hit)
  }
  // Creado en terreno y todavía sin llegar al servidor.
  const local = await enexDB().cache.get(keyLocal(programacionId))
  if (local) return conCambios(local.value as EnexPendiente)
  return null
}

// ── Plan del día ─────────────────────────────────────────────────────────
// [MIG274] El plan que publica el planificador. Antes solo se leía con señal:
// sin ella desaparecía y el técnico no sabía qué actividades tocaban.
const keyPlan = (fecha: string) => `plan:${fecha}`

export async function getPlanDiaOffline(fecha: string): Promise<EnexPlanTarea[]> {
  if (isOnline()) {
    try {
      const plan = await conTimeout(getPlanTareasDia(fecha))
      await enexDB().cache.put({ key: keyPlan(fecha), value: plan, updated_at: new Date().toISOString() })
      return plan
    } catch { /* cae a la cache */ }
  }
  const row = await enexDB().cache.get(keyPlan(fecha))
  return (row?.value as EnexPlanTarea[]) ?? []
}

// ── Ítems de pauta ────────────────────────────────────────────────────────
export async function getPautaItemsOffline(pautaId: string): Promise<EnexPautaItem[]> {
  if (isOnline()) {
    try {
      const items = await conTimeout(getPautaItems(pautaId))
      await enexDB().cache.put({ key: keyItems(pautaId), value: items, updated_at: new Date().toISOString() })
      return items
    } catch { /* cae a cache */ }
  }
  const row = await enexDB().cache.get(keyItems(pautaId))
  return (row?.value as EnexPautaItem[]) ?? []
}

// ── Ítems ya registrados de una ejecución (para reabrir un trabajo) ────────
// [MIG265] También se cachean: sin esto, reabrir un servicio sin señal perdía
// de vista lo ya marcado y las fotos ya subidas.
export type EnexEjecucionItemRow = {
  pauta_item_id: string
  resultado: string | null
  valor_medicion: number | null
  observacion: string | null
  foto_url: string | null
  foto_antes_url: string | null
  foto_despues_url: string | null
  fotos_antes: string[] | null
  fotos_despues: string[] | null
}
const keyEjec = (ejecucionId: string) => `ejec:${ejecucionId}`

export async function getEjecucionItemsOffline(ejecucionId: string): Promise<EnexEjecucionItemRow[]> {
  if (isOnline()) {
    try {
      const rows = (await conTimeout(getEjecucionItems(ejecucionId))) as unknown as EnexEjecucionItemRow[]
      await enexDB().cache.put({ key: keyEjec(ejecucionId), value: rows, updated_at: new Date().toISOString() })
      return rows
    } catch { /* cae a cache */ }
  }
  const row = await enexDB().cache.get(keyEjec(ejecucionId))
  return (row?.value as EnexEjecucionItemRow[]) ?? []
}

// Pre-descargar todo lo del período para operar sin señal: pendientes, ítems de
// cada pauta y lo ya ejecutado de cada servicio. También el mes anterior (un
// trabajo a medias de fin de mes) y el siguiente (la cuadrilla sale el 30 y
// trabaja el 1), el plan de hoy y los dos días que vienen, y las pantallas.
const DESCARGA_MS = 30_000

async function bajarPeriodo(anio: number, mes: number): Promise<EnexPendiente[]> {
  const pend = await conTimeout(getTerrenoPendientes(anio, mes), DESCARGA_MS)
  await enexDB().cache.put({ key: keyPend(anio, mes), value: pend, updated_at: new Date().toISOString() })
  return pend
}

export async function prepararEnexOffline(anio: number, mes: number): Promise<number> {
  // Las pantallas primero: sin ellas lo demás no se puede abrir sin señal.
  await guardarPantallasOffline()
  const pend = await bajarPeriodo(anio, mes)
  const vecinos: EnexPendiente[] = []
  for (const d of [-1, 1]) {
    let m = mes + d, a = anio
    if (m < 1) { m = 12; a-- } else if (m > 12) { m = 1; a++ }
    try { vecinos.push(...(await bajarPeriodo(a, m)).filter((p) => !p.cumplida)) } catch { /* sigue */ }
  }
  const todos = [...pend, ...vecinos]
  // [MIG651] Puntos y zonas, para abrir sin señal un servicio no planificado.
  const puntos = await bajarParaCambios().catch(() => [] as EnexTerrenoInstalacion[])
  const pautas = Array.from(new Set([
    ...todos.map((p) => p.pauta_id),
    ...puntos.flatMap((i) => [i.pauta_mantencion_id, i.pauta_calibracion_id]),
  ].filter(Boolean))) as string[]
  for (const pid of pautas) { try { await getPautaItemsOffline(pid) } catch { /* sigue */ } }
  const ejecuciones = todos.map((p) => p.ejecucion_id).filter(Boolean) as string[]
  for (const eid of ejecuciones) { try { await getEjecucionItemsOffline(eid) } catch { /* sigue */ } }
  for (let i = 0; i < 3; i++) {
    const d = new Date(); d.setDate(d.getDate() + i)
    const iso = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
    try { await getPlanDiaOffline(iso) } catch { /* sigue */ }
  }
  await enexDB().cache.put({
    key: `descarga:${anio}-${mes}`, value: { at: new Date().toISOString(), servicios: pend.length },
    updated_at: new Date().toISOString(),
  })
  return pend.length
}

/** Cuándo se bajó por última vez el período (para avisarlo en pantalla). */
export async function ultimaDescargaEnex(anio: number, mes: number): Promise<string | null> {
  const row = await enexDB().cache.get(`descarga:${anio}-${mes}`)
  return (row?.value as { at?: string } | undefined)?.at ?? null
}

// ── Borrador del trabajo en curso ─────────────────────────────────────────
// [MIG265] En terreno la pauta casi nunca se hace completa de una vez. Si el
// mantenedor cerraba la app o se le apagaba el teléfono antes de «Guardar
// avance», perdía todo lo marcado. Ahora cada cambio queda en el teléfono.

/** Guarda una foto recién capturada como blob local y devuelve su id. */
export async function guardarFotoLocal(file: File | Blob): Promise<string> {
  const id = newId()
  await enexDB().blobs.put({ blob_id: id, blob: file, mime: (file as File).type || 'image/jpeg' })
  return id
}

export async function getFotoLocal(blobId: string): Promise<Blob | null> {
  const b = await enexDB().blobs.get(blobId)
  return b?.blob ?? null
}

/** La foto local y, si ya llegó al servidor, su URL. */
export async function getFotoLocalInfo(blobId: string): Promise<{ blob: Blob; url: string | null } | null> {
  const b = await enexDB().blobs.get(blobId)
  return b ? { blob: b.blob, url: b.url ?? null } : null
}

export async function guardarDraft(draft: Omit<EnexDraft, 'updated_at'>): Promise<void> {
  await enexDB().drafts.put({ ...draft, updated_at: new Date().toISOString() })
}

export async function getDraft(programacionId: string): Promise<EnexDraft | null> {
  return (await enexDB().drafts.get(programacionId)) ?? null
}

/** Al cerrar cumplida: se borra el borrador y sus fotos ya encoladas. */
export async function borrarDraft(programacionId: string): Promise<void> {
  await enexDB().drafts.delete(programacionId)
}

// ── Encolar una ejecución ─────────────────────────────────────────────────
export async function queueEjecucion(params: {
  programacionId: string
  conMandante: boolean
  otNumero?: string | null
  ejecutor?: string | null
  tecnicoNombre?: string | null
  observacion?: string | null
  firmanteMandante?: string | null
  items: Array<{
    pauta_item_id: string; resultado?: string | null; valor_medicion?: string | null
    observacion?: string | null; file?: File | null; fotoUrl?: string | null
    // [MIG265] Antes/después en TODO ítem, con varias fotos cada uno: las
    // nuevas viajan como File o como blob ya guardado por el borrador, y las
    // que ya están en el servidor, como URL.
    antesFiles?: File[]; despuesFiles?: File[]
    antesBlobIds?: string[]; despuesBlobIds?: string[]
    fotosAntesUrls?: string[]; fotosDespuesUrls?: string[]
  }>
  firmaTecFile?: Blob | null
  firmaMandFile?: Blob | null
  // [MIG265] Tiempo del trabajo en terreno.
  inicioAt?: string | null
  finAt?: string | null
  duracionSegundos?: number | null
  // [MIG267] `items` trae el estado completo de la pantalla, incluidas las
  // actividades que quedaron vacías a propósito.
  reemplazar?: boolean
  // [MIG649] Lista completa del pedido de repuestos.
  repuestos?: EnexRepuesto[]
}): Promise<{ synced: boolean; error?: string | null }> {
  const db = enexDB()
  // Guardar blobs de fotos + firmas
  const items: EnexPendItem[] = []
  const guardarBlobs = async (files: File[] | undefined): Promise<string[]> => {
    const ids: string[] = []
    for (const f of files ?? []) {
      const id = newId()
      await db.blobs.put({ blob_id: id, blob: f, mime: f.type || 'image/jpeg' })
      ids.push(id)
    }
    return ids
  }
  for (const it of params.items) {
    let blobId: string | null = null
    if (it.file) { blobId = newId(); await db.blobs.put({ blob_id: blobId, blob: it.file, mime: it.file.type || 'image/jpeg' }) }
    // Los blobs del borrador ya están en IndexedDB: se reutilizan tal cual en
    // vez de duplicarlos.
    const antesIds = [...(it.antesBlobIds ?? []), ...(await guardarBlobs(it.antesFiles))]
    const despuesIds = [...(it.despuesBlobIds ?? []), ...(await guardarBlobs(it.despuesFiles))]
    items.push({
      pauta_item_id: it.pauta_item_id, resultado: it.resultado ?? null,
      valor_medicion: it.valor_medicion ?? null, observacion: it.observacion ?? null,
      foto_blob_id: blobId,
      fotos_antes_blob_ids: antesIds, fotos_despues_blob_ids: despuesIds,
      // las que ya estaban subidas viajan como URL y se conservan
      fotos_antes_urls: it.fotosAntesUrls ?? [], fotos_despues_urls: it.fotosDespuesUrls ?? [],
      ...(it.fotoUrl && !blobId ? { foto_url_existente: it.fotoUrl } as unknown as object : {}),
    })
  }
  let firmaTecId: string | null = null
  if (params.firmaTecFile) { firmaTecId = newId(); await db.blobs.put({ blob_id: firmaTecId, blob: params.firmaTecFile, mime: 'image/png' }) }
  let firmaMandId: string | null = null
  if (params.firmaMandFile) { firmaMandId = newId(); await db.blobs.put({ blob_id: firmaMandId, blob: params.firmaMandFile, mime: 'image/png' }) }

  const row: EnexPending = {
    local_id: newId(), client_uuid: newId(), programacion_id: params.programacionId,
    con_mandante: params.conMandante, ot_numero: params.otNumero ?? null,
    ejecutor: params.ejecutor ?? null, tecnico_nombre: params.tecnicoNombre ?? null,
    observacion: params.observacion ?? null, firmante_mandante: params.firmanteMandante ?? null,
    items, firma_tec_blob_id: firmaTecId, firma_mand_blob_id: firmaMandId,
    inicio_at: params.inicioAt ?? null, fin_at: params.finAt ?? null,
    duracion_segundos: params.duracionSegundos ?? null,
    reemplazar: params.reemplazar === true,
    repuestos: params.repuestos,
    sync_status: 'pending', retries: 0, last_error: null, created_at: new Date().toISOString(),
  }
  // Reemplazar cualquier pendiente previo de la misma programación (última gana)
  await db.pending.where('programacion_id').equals(params.programacionId).delete()
  await db.pending.put(row)

  // Guardar NUNCA espera a la red. Lo guardado ya está en el teléfono; si hay
  // señal se intenta enviar, pero el botón se libera a los pocos segundos y el
  // envío sigue solo. Antes, con antena sin datos, «Guardar» quedaba girando y
  // el mantenedor creía que había perdido el trabajo.
  if (isOnline()) {
    await Promise.race([
      syncEnexPending().catch(() => undefined),
      new Promise((r) => setTimeout(r, ESPERA_GUARDAR_MS)),
    ])
    const after = await db.pending.get(row.local_id)
    if (!after) return { synced: true }
    return { synced: false, error: after.sync_status === 'error' ? after.last_error : null }
  }
  return { synced: false }
}

// ── Sync ────────────────────────────────────────────────────────────────
// Como Kizeo: cada foto viaja por separado y queda anotada al llegar, y la
// bandeja «Por enviar» muestra cuántas van. Un corte a la mitad ya no obliga a
// partir de cero.

/** Techo por foto: ~400 KB comprimida pasa holgado incluso con 2G. */
export const SUBIDA_FOTO_MS = 90_000
/** Techo para registrar la ejecución en el servidor. */
export const REGISTRO_MS = 45_000
/** Lo que «Guardar» espera al envío antes de liberar el botón. */
export const ESPERA_GUARDAR_MS = 15_000

type SyncResult = { ok: number; failed: number }
let enCurso: Promise<SyncResult> | null = null
let otraVuelta = false

/**
 * Un solo envío a la vez. El reintento periódico, el evento «online» y el
 * botón Guardar llaman todos acá: si ya hay un envío corriendo, se pide otra
 * vuelta al terminar (para lo que se encoló mientras tanto) en vez de subir
 * las mismas fotos dos veces en paralelo.
 */
export function syncEnexPending(): Promise<SyncResult> {
  if (!isOnline()) return Promise.resolve({ ok: 0, failed: 0 })
  if (enCurso) { otraVuelta = true; return enCurso }
  enCurso = (async () => {
    const total: SyncResult = { ok: 0, failed: 0 }
    do {
      otraVuelta = false
      const r = await enviarCola()
      total.ok += r.ok; total.failed += r.failed
    } while (otraVuelta && isOnline())
    await limpiarBlobsSubidos().catch(() => undefined)
    return total
  })().finally(() => { enCurso = null })
  return enCurso
}

/** ¿Hay un envío corriendo ahora? (para la bandeja) */
export function enexEnviando(): boolean {
  return enCurso !== null
}

/** Todas las fotos y firmas de una ejecución encolada. */
function blobIdsDe(p: EnexPending): string[] {
  const ids: string[] = []
  for (const it of p.items) {
    if (it.foto_blob_id) ids.push(it.foto_blob_id)
    if (it.foto_antes_blob_id) ids.push(it.foto_antes_blob_id)
    if (it.foto_despues_blob_id) ids.push(it.foto_despues_blob_id)
    ids.push(...(it.fotos_antes_blob_ids ?? []), ...(it.fotos_despues_blob_ids ?? []))
  }
  if (p.firma_tec_blob_id) ids.push(p.firma_tec_blob_id)
  if (p.con_mandante && p.firma_mand_blob_id) ids.push(p.firma_mand_blob_id)
  return ids
}

async function enviarCola(): Promise<SyncResult> {
  const db = enexDB()
  // [MIG651] Primero los cambios de programa: el servicio nuevo y la patente
  // tienen que existir en el servidor antes que su ejecución.
  const previos = await enviarCambiosTerreno()
  const rows = (await db.pending.toArray()).sort((a, b) => a.created_at.localeCompare(b.created_at))
  let ok = previos.ok, failed = previos.failed
  for (const p of rows) {
    if (!isOnline()) break
    try {
      const ids = blobIdsDe(p)
      const yaSubidas = (await db.blobs.bulkGet(ids)).filter((b) => b?.url).length
      let subidas = yaSubidas
      await db.pending.update(p.local_id, {
        sync_status: 'sending', fotos_total: ids.length, fotos_subidas: subidas,
        last_try_at: new Date().toISOString(),
      })

      /** Sube un blob una sola vez: si ya llegó, devuelve su URL anotada. */
      const subir = async (id: string, nombre: string, firma = false): Promise<string | null> => {
        const b = await db.blobs.get(id)
        if (!b) return null
        if (b.url) return b.url
        const url = await withTimeout(
          firma ? subirFirmaBlob(b.blob) : subirEvidenciaEnex(new File([b.blob], nombre + '.jpg', { type: b.mime })),
          SUBIDA_FOTO_MS, nombre)
        await db.blobs.update(id, { url })
        subidas++
        await db.pending.update(p.local_id, { fotos_subidas: subidas })
        return url
      }

      // subir fotos de ítems (única + antes/después)
      const itemsPayload: EnexItemResultado[] = []
      for (const it of p.items) {
        const ex = it as unknown as { foto_url_existente?: string; foto_antes_url_existente?: string; foto_despues_url_existente?: string }
        let fotoUrl: string | null = ex.foto_url_existente ?? null
        if (it.foto_blob_id) fotoUrl = (await subir(it.foto_blob_id, 'foto')) ?? fotoUrl
        // [MIG265] Galerías: primero lo ya subido, después lo capturado offline.
        const subirGaleria = async (galeria: string[] | undefined, nombre: string): Promise<string[]> => {
          const urls: string[] = []
          for (const id of galeria ?? []) {
            const u = await subir(id, nombre)
            if (u) urls.push(u)
          }
          return urls
        }
        const antesPrev = it.fotos_antes_urls
          ?? (ex.foto_antes_url_existente ? [ex.foto_antes_url_existente] : [])
        const despuesPrev = it.fotos_despues_urls
          ?? (ex.foto_despues_url_existente ? [ex.foto_despues_url_existente] : [])
        const fotosAntes = [...antesPrev, ...(await subirGaleria(it.fotos_antes_blob_ids, 'antes'))]
        const fotosDespues = [...despuesPrev, ...(await subirGaleria(it.fotos_despues_blob_ids, 'despues'))]

        itemsPayload.push({
          pauta_item_id: it.pauta_item_id, resultado: it.resultado ?? null,
          valor_medicion: it.valor_medicion ?? null, foto_url: fotoUrl,
          foto_antes_url: fotosAntes[0] ?? null, foto_despues_url: fotosDespues[0] ?? null,
          fotos_antes: fotosAntes, fotos_despues: fotosDespues,
          observacion: it.observacion ?? null,
        })
      }
      // firmas
      const firmaTecUrl = p.firma_tec_blob_id ? await subir(p.firma_tec_blob_id, 'firma', true) : null
      const firmaMandUrl = p.con_mandante && p.firma_mand_blob_id ? await subir(p.firma_mand_blob_id, 'firma', true) : null

      // client_uuid hace idempotente el registro: si la respuesta se pierde en
      // el camino y se reintenta, el servidor no duplica la ejecución.
      await withTimeout(ejecutarPauta({
        programacionId: p.programacion_id, items: itemsPayload,
        otNumero: p.ot_numero, ejecutor: p.ejecutor, observacion: p.observacion,
        firmaTecnicoUrl: firmaTecUrl, tecnicoNombre: p.tecnico_nombre,
        firmaMandanteUrl: firmaMandUrl, firmanteMandante: p.firmante_mandante,
        clientUuid: p.client_uuid,
        inicioAt: p.inicio_at ?? null, finAt: p.fin_at ?? null,
        duracionSegundos: p.duracion_segundos ?? null,
        // [MIG267] Lo que va en el payload es el estado completo de la pantalla:
        // lo que viaja vacío se vacía en el servidor. Las ejecuciones encoladas
        // por la app anterior no llevan la marca y siguen siendo aditivas.
        reemplazar: p.reemplazar === true,
      }), REGISTRO_MS, 'registro')

      // [MIG649] El pedido de repuestos va después: necesita la ejecución.
      if (p.repuestos !== undefined) {
        try {
          await withTimeout(guardarRepuestosEnex(p.programacion_id, p.repuestos, p.tecnico_nombre ?? null),
            REGISTRO_MS, 'repuestos')
        } catch (e) {
          // Sin MIG649 en la base la ejecución igual tiene que entrar: no se
          // traba la cola por esto. Cualquier otro error sí se reintenta.
          if (!/rpc_enex_guardar_repuestos|PGRST202|does not exist/i.test(mensajeError(e))) throw e
        }
      }
      // El correo a la jefatura sale aparte (necesita sesión, el informe y
      // red): queda anotado y lo despacha el agente de envío.
      if (p.con_mandante || (p.repuestos?.length ?? 0) > 0) {
        await db.cache.put({ key: `correo:${p.programacion_id}`, value: { programacion_id: p.programacion_id,
          cierre: p.con_mandante, intentos: 0 }, updated_at: new Date().toISOString() })
      }

      // Si mientras se enviaba el mantenedor volvió a guardar, esta fila ya fue
      // reemplazada por la nueva: esa se envía en la vuelta siguiente y reusa
      // las fotos que acabamos de subir.
      if (!(await db.pending.get(p.local_id))) { ok++; continue }

      // El borrador NO se toca: sigue apuntando a las fotos locales, que ahora
      // llevan su URL anotada. Antes se reescribía con las URL y las fotos se
      // borraban del teléfono, pero la pantalla abierta seguía usando sus ids
      // locales: el siguiente «Guardar avance» las mandaba vacías y el servidor
      // las sacaba del informe. Al reabrir, las que ya están en el servidor no
      // se repiten (getFotoLocalInfo).
      await db.pending.delete(p.local_id)
      ok++
    } catch (e) {
      failed++
      await db.pending.update(p.local_id, {
        sync_status: 'error', retries: (p.retries || 0) + 1, last_error: mensajeError(e),
      })
    }
  }
  return { ok, failed }
}

/** El motivo, en palabras de terreno. */
function mensajeError(e: unknown): string {
  const msg = (e as Error)?.message ?? String(e)
  if (/timeout|failed to fetch|network|load failed|networkerror/i.test(msg)) {
    return 'Señal insuficiente para terminar el envío'
  }
  return msg
}

/**
 * Las fotos ya subidas se borran del teléfono cuando nadie las necesita:
 * ni la cola ni el borrador del servicio. Mientras el servicio siga abierto,
 * la pantalla las referencia por su id local; borrarlas antes hacía que el
 * siguiente «Guardar avance» las mandara vacías y el servidor las sacara.
 */
async function limpiarBlobsSubidos(): Promise<void> {
  const db = enexDB()
  const usados = new Set<string>()
  for (const p of await db.pending.toArray()) blobIdsDe(p).forEach((id) => usados.add(id))
  for (const d of await db.drafts.toArray()) {
    for (const di of Object.values(d.items ?? {})) {
      for (const f of [...(di.antes ?? []), ...(di.despues ?? [])]) if (f.blob_id) usados.add(f.blob_id)
    }
  }
  const borrar: string[] = []
  await db.blobs.each((b) => { if (b.url && !usados.has(b.blob_id)) borrar.push(b.blob_id) })
  if (borrar.length) await db.blobs.bulkDelete(borrar)
}

// Sube una firma (blob PNG) al bucket público reutilizando el helper de dataURL.
async function subirFirmaBlob(blob: Blob): Promise<string> {
  const dataUrl: string = await new Promise((resolve, reject) => {
    const fr = new FileReader()
    fr.onload = () => resolve(fr.result as string)
    fr.onerror = reject
    fr.readAsDataURL(blob)
  })
  return subirFirmaEnex(dataUrl)
}

export async function getEnexPendingCount(): Promise<number> {
  const ops = await enexDB().cache.where('key').startsWith('op:').count()
  return (await enexDB().pending.count()) + ops
}

// ── Bandeja «Por enviar» ─────────────────────────────────────────────────
export type EnexBandejaRow = {
  local_id: string
  programacion_id: string
  instalacion: string | null
  con_mandante: boolean
  estado: 'en_espera' | 'enviando' | 'error'
  fotos_total: number
  fotos_subidas: number
  intentos: number
  motivo: string | null
  guardado_at: string
  ultimo_intento_at: string | null
  /** [MIG651] Cambio de programa (patente, «no se hizo», servicio nuevo). */
  etiqueta?: string
}

export async function getBandejaEnex(): Promise<EnexBandejaRow[]> {
  const db = enexDB()
  const rows = (await db.pending.toArray()).sort((a, b) => a.created_at.localeCompare(b.created_at))
  const ops = (await db.cache.where('key').startsWith('op:').toArray()).map((c) => c.value as EnexOp)
  const filasOps: EnexBandejaRow[] = ops.map((o) => ({
    local_id: o.id, programacion_id: o.programacion_id ?? '', instalacion: o.titulo, con_mandante: false,
    estado: o.error ? 'error' : 'en_espera', fotos_total: 0, fotos_subidas: 0, intentos: o.intentos ?? 0,
    motivo: o.error ?? null, guardado_at: o.created_at, ultimo_intento_at: null, etiqueta: ETIQUETA_OP[o.tipo],
  }))
  if (rows.length === 0) return filasOps
  // El nombre de la instalación sale de lo descargado.
  const nombres = new Map<string, string>()
  for (const c of await db.cache.where('key').startsWith('pend:').toArray()) {
    for (const r of (c.value as EnexPendiente[]) ?? []) nombres.set(r.programacion_id, r.instalacion)
  }
  const corriendo = enexEnviando()
  return rows.map((p) => ({
    local_id: p.local_id,
    programacion_id: p.programacion_id,
    instalacion: nombres.get(p.programacion_id) ?? null,
    con_mandante: p.con_mandante,
    estado: p.sync_status === 'sending' && corriendo ? 'enviando' : p.sync_status === 'error' ? 'error' : 'en_espera',
    fotos_total: p.fotos_total ?? blobIdsDe(p).length,
    fotos_subidas: p.fotos_subidas ?? 0,
    intentos: p.retries ?? 0,
    motivo: p.last_error,
    guardado_at: p.created_at,
    ultimo_intento_at: p.last_try_at ?? null,
  } as EnexBandejaRow)).concat(filasOps)
}

// ── Preparado para trabajar sin señal ────────────────────────────────────
// Kizeo pide abrir la app con red antes de salir. Acá la app lo hace sola y
// muestra qué tan lista quedó.

/** Pantallas que tienen que estar guardadas en el teléfono. */
export const PANTALLAS_ENEX = ['/m/enex/', '/m/enex/servicio/']

/**
 * Pide al navegador que no borre lo guardado si falta espacio. Sin esto
 * Android/iPhone pueden vaciar IndexedDB y la cola «Por enviar» con él.
 */
export async function protegerAlmacenamiento(): Promise<{ persistente: boolean; libreMB: number | null }> {
  if (typeof navigator === 'undefined' || !navigator.storage) return { persistente: false, libreMB: null }
  let persistente = false
  try {
    persistente = (await navigator.storage.persisted?.()) ?? false
    if (!persistente) persistente = (await navigator.storage.persist?.()) ?? false
  } catch { /* navegador sin la API */ }
  let libreMB: number | null = null
  try {
    const est = await navigator.storage.estimate()
    if (est.quota != null && est.usage != null) libreMB = Math.round((est.quota - est.usage) / 1_048_576)
  } catch { /* sin estimación */ }
  return { persistente, libreMB }
}

/**
 * Baja las pantallas de la app (HTML y datos de navegación) para que abran
 * sin señal. El service worker las guarda al pasar por él.
 */
export async function guardarPantallasOffline(): Promise<void> {
  if (!isOnline() || typeof fetch === 'undefined') return
  for (const url of PANTALLAS_ENEX) {
    try { await conTimeout(fetch(url, { credentials: 'same-origin' }), 15_000) } catch { /* sigue */ }
    try { await conTimeout(fetch(url, { headers: { RSC: '1' }, credentials: 'same-origin' }), 15_000) } catch { /* sigue */ }
  }
}

/** ¿Las pantallas ya están guardadas en el teléfono? */
export async function pantallasDisponiblesOffline(): Promise<boolean> {
  if (typeof caches === 'undefined') return false
  try {
    for (const url of PANTALLAS_ENEX) {
      if (!(await caches.match(new URL(url, location.origin).toString(), { ignoreSearch: true }))) return false
    }
    return true
  } catch { return false }
}

// ── Cambio de programa en terreno (MIG651) ──────────────────────────────────
// ESM pide otra cosa al llegar (camiones en vez de la EESS, la sala de
// microfiltrado en vez del rack). Todo se anota en el teléfono y viaja por la
// misma cola, antes que las ejecuciones: el servicio nuevo y la patente tienen
// que existir en el servidor cuando llegue el trabajo.

export type EnexOp = {
  id: string
  tipo: 'camion' | 'servicio' | 'por_reprogramar' | 'zona'
  titulo: string
  programacion_id?: string
  patente?: string
  faena_id?: string
  instalacion_id?: string
  tipo_servicio?: TipoServicio
  fecha?: string
  motivo?: string | null
  lugar_id?: string
  hacer?: boolean
  created_at: string
  intentos?: number
  error?: string | null
}

const ETIQUETA_OP: Record<EnexOp['tipo'], string> = {
  camion: 'Patente', servicio: 'Servicio nuevo', por_reprogramar: 'No se hizo', zona: 'Zona',
}
const keyLocal = (progId: string) => `local:${progId}`
const keyPatch = (progId: string) => `patch:${progId}`
const keyZonasDia = (fecha: string) => `zonasdia:${fecha}`

type PatchTerreno = Partial<Pick<EnexPendiente, 'patente' | 'instalacion' | 'por_reprogramar_motivo' | 'por_reprogramar_at' | 'es_comodin'>>

async function encolarOp(op: Omit<EnexOp, 'id' | 'created_at'>): Promise<void> {
  const created_at = new Date().toISOString()
  const id = newId()
  await enexDB().cache.put({ key: `op:${created_at}:${id}`, value: { ...op, id, created_at }, updated_at: created_at })
  if (isOnline()) void syncEnexPending().catch(() => undefined)
}

async function parchar(progId: string, cambios: PatchTerreno): Promise<void> {
  const row = await enexDB().cache.get(keyPatch(progId))
  await enexDB().cache.put({ key: keyPatch(progId), value: { ...((row?.value as PatchTerreno) ?? {}), ...cambios },
    updated_at: new Date().toISOString() })
}

/** Encima de lo del servidor: servicios creados acá, patentes y «no se hizo». */
async function aplicarCambiosTerreno(base: EnexPendiente[], periodo?: { anio: number; mes: number }): Promise<EnexPendiente[]> {
  const db = enexDB()
  const patches = await db.cache.where('key').startsWith('patch:').toArray()
  const locales = await db.cache.where('key').startsWith('local:').toArray()
  if (patches.length === 0 && locales.length === 0) return base
  const ids = new Set(base.map((r) => r.programacion_id))
  const extra: EnexPendiente[] = []
  for (const l of locales) {
    const r = l.value as EnexPendiente
    if (ids.has(r.programacion_id)) {
      // Ya llegó al servidor: la copia local sobra.
      if (periodo) await db.cache.delete(l.key)
      continue
    }
    if (!periodo || (r.periodo_anio === periodo.anio && r.periodo_mes === periodo.mes)) extra.push(r)
  }
  const porId = new Map(patches.map((p) => [p.key.slice('patch:'.length), p.value as PatchTerreno]))
  return [...base, ...extra].map((r) => {
    const p = porId.get(r.programacion_id)
    return p ? { ...r, ...p } : r
  })
}

async function enviarCambiosTerreno(): Promise<SyncResult> {
  const db = enexDB()
  const ops = (await db.cache.where('key').startsWith('op:').toArray()).sort((a, b) => a.key.localeCompare(b.key))
  let ok = 0, failed = 0
  for (const row of ops) {
    if (!isOnline()) break
    const o = row.value as EnexOp
    try {
      if (o.tipo === 'camion') {
        await withTimeout(terrenoCamion({ programacionId: o.programacion_id!, patente: o.patente!,
          faenaId: o.faena_id, fecha: o.fecha, motivo: o.motivo }), REGISTRO_MS, 'patente')
      } else if (o.tipo === 'servicio') {
        await withTimeout(terrenoServicio({ programacionId: o.programacion_id!, instalacionId: o.instalacion_id!,
          tipoServicio: o.tipo_servicio!, fecha: o.fecha!, motivo: o.motivo }), REGISTRO_MS, 'servicio')
      } else if (o.tipo === 'por_reprogramar') {
        await withTimeout(porReprogramar(o.programacion_id!, o.motivo ?? null, o.hacer === false), REGISTRO_MS, 'reprogramar')
      } else {
        await withTimeout(zonaTerreno(o.lugar_id!, o.fecha!, o.hacer === true, o.motivo ?? null), REGISTRO_MS, 'zona')
      }
      await db.cache.delete(row.key)
      // Con todo lo de ese servicio ya en el servidor, el parche sobra: la
      // próxima lectura trae la patente o la marca desde allá.
      if (o.programacion_id) {
        const quedan = (await db.cache.where('key').startsWith('op:').toArray())
          .some((r) => (r.value as EnexOp).programacion_id === o.programacion_id)
        if (!quedan) await db.cache.delete(keyPatch(o.programacion_id))
      }
      ok++
    } catch (e) {
      failed++
      await db.cache.put({ ...row, value: { ...o, intentos: (o.intentos ?? 0) + 1, error: mensajeError(e) } })
    }
  }
  return { ok, failed }
}

const keyPuntos = 'terreno:instalaciones'
const keyLugares = 'terreno:lugares'

async function bajarParaCambios(): Promise<EnexTerrenoInstalacion[]> {
  const puntos = await conTimeout(getTerrenoInstalaciones(), DESCARGA_MS)
  await enexDB().cache.put({ key: keyPuntos, value: puntos, updated_at: new Date().toISOString() })
  try {
    const lugares = await conTimeout(getLugarItemsTodas(), DESCARGA_MS)
    await enexDB().cache.put({ key: keyLugares, value: lugares, updated_at: new Date().toISOString() })
  } catch { /* sigue con lo que había */ }
  return puntos
}

/** Puntos de todas las faenas con su pauta (lo bajado; con señal, al día). */
export async function getPuntosOffline(): Promise<EnexTerrenoInstalacion[]> {
  if (isOnline()) { try { return await bajarParaCambios() } catch { /* cache */ } }
  return ((await enexDB().cache.get(keyPuntos))?.value as EnexTerrenoInstalacion[]) ?? []
}

/** Zonas de Lomas (lugar + actividades). */
export async function getLugaresOffline(): Promise<EnexLugarItem[]> {
  return ((await enexDB().cache.get(keyLugares))?.value as EnexLugarItem[]) ?? []
}

function hoyIso(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export function normalizarPatente(p: string): string {
  return p.toUpperCase().replace(/[^A-Z0-9]/g, '')
}

/**
 * Servicio que no estaba planificado. Se arma en el teléfono con su propio id
 * (así se puede abrir y trabajar sin señal) y viaja por la cola.
 */
export async function crearServicioTerreno(p: {
  punto: EnexTerrenoInstalacion; tipoServicio: TipoServicio; motivo: string; patente?: string | null
}): Promise<string> {
  const id = newId()
  const fecha = hoyIso()
  const pautaId = p.tipoServicio === 'mantencion' ? p.punto.pauta_mantencion_id : p.punto.pauta_calibracion_id
  const items: EnexPautaItem[] = pautaId ? await getPautaItemsOffline(pautaId).catch(() => []) : []
  const pat = p.patente ? normalizarPatente(p.patente) : null
  const local: EnexPendiente = {
    programacion_id: id, periodo_anio: Number(fecha.slice(0, 4)), periodo_mes: Number(fecha.slice(5, 7)),
    tipo_servicio: p.tipoServicio, fecha_programada: fecha,
    instalacion_id: p.punto.instalacion_id,
    instalacion: pat ? `Aljibe ${pat}` : p.punto.instalacion,
    instalacion_tipo: p.punto.instalacion_tipo, patente: pat ?? p.punto.patente, linea: p.punto.linea,
    faena_id: p.punto.faena_id, faena_codigo: p.punto.faena_codigo, faena: p.punto.faena,
    pauta_id: pautaId, pauta_nombre: null, pauta_borrador: null, pauta_items: items.length,
    ejecucion_id: null, estado: null, cumplida: false, es_recobro: false,
    es_comodin: p.punto.es_comodin && !pat, origen: 'terreno', por_reprogramar_at: null, por_reprogramar_motivo: null,
    local: true,
  }
  await enexDB().cache.put({ key: keyLocal(id), value: local, updated_at: new Date().toISOString() })
  if (p.punto.instalacion_tipo === 'camion' && pat) {
    await encolarOp({ tipo: 'camion', titulo: `Calibración ${pat} · ${p.punto.faena}`, programacion_id: id, patente: pat,
      faena_id: p.punto.faena_id, fecha, motivo: p.motivo })
  } else {
    await encolarOp({ tipo: 'servicio', titulo: `${p.punto.instalacion} · ${p.punto.faena}`, programacion_id: id,
      instalacion_id: p.punto.instalacion_id, tipo_servicio: p.tipoServicio, fecha, motivo: p.motivo })
  }
  return id
}

/** El supervisor anota la patente del camión «por asignar» (o la corrige). */
export async function asignarPatenteTerreno(prog: EnexPendiente, patente: string): Promise<string> {
  const pat = normalizarPatente(patente)
  if (pat.length < 4 || pat.length > 8) throw new Error('Patente inválida: entre 4 y 8 letras/números')
  // Si el servicio nació en este teléfono y todavía no sale, su op de creación
  // lleva la patente: se corrige ahí en vez de encolar otra.
  const ops = await enexDB().cache.where('key').startsWith('op:').toArray()
  const creacion = ops.find((r) => {
    const o = r.value as EnexOp
    return o.programacion_id === prog.programacion_id && o.tipo === 'camion' && !!o.faena_id
  })
  if (creacion) {
    await enexDB().cache.put({ ...creacion, value: { ...(creacion.value as EnexOp), patente: pat, error: null } })
    if (isOnline()) void syncEnexPending().catch(() => undefined)
  } else {
    await encolarOp({ tipo: 'camion', titulo: `Patente ${pat} · ${prog.faena}`, programacion_id: prog.programacion_id, patente: pat })
  }
  await parchar(prog.programacion_id, { patente: pat, instalacion: `Aljibe ${pat}`, es_comodin: false })
  return pat
}

/** «No se hizo»: queda por reprogramar con el motivo (deshacer = volver atrás). */
export async function marcarNoSeHizo(prog: EnexPendiente, motivo: string, deshacer = false): Promise<void> {
  await encolarOp({ tipo: 'por_reprogramar', titulo: `${prog.instalacion} · ${prog.faena}`, programacion_id: prog.programacion_id,
    motivo: deshacer ? null : motivo, hacer: deshacer ? false : undefined })
  await parchar(prog.programacion_id, deshacer
    ? { por_reprogramar_motivo: null, por_reprogramar_at: null }
    : { por_reprogramar_motivo: motivo, por_reprogramar_at: new Date().toISOString() })
}

export type ZonaDia = { lugar_id: string; area: string; lugar: string; hacer: boolean; motivo: string | null }

/** Lomas: la zona del plan no se hizo (hacer=false) o se hace hoy (hacer=true). */
export async function marcarZonaTerreno(z: ZonaDia): Promise<void> {
  const fecha = hoyIso()
  await encolarOp({ tipo: 'zona', titulo: `${z.area} · ${z.lugar}`, lugar_id: z.lugar_id, fecha, hacer: z.hacer, motivo: z.motivo })
  const row = await enexDB().cache.get(keyZonasDia(fecha))
  const lista = ((row?.value as ZonaDia[]) ?? []).filter((x) => x.lugar_id !== z.lugar_id)
  await enexDB().cache.put({ key: keyZonasDia(fecha), value: [...lista, z], updated_at: new Date().toISOString() })
}

/** Lo que el supervisor cambió hoy en las zonas (para pintarlo en «Plan de hoy»). */
export async function getZonasDia(fecha: string): Promise<ZonaDia[]> {
  return ((await enexDB().cache.get(keyZonasDia(fecha)))?.value as ZonaDia[]) ?? []
}
