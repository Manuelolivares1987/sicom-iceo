'use client'

// ============================================================================
// Hook orquestador del checklist QR offline-first.
// Maneja: carga template, GPS, fotos blob, trazabilidad por pregunta,
// guardado offline en IndexedDB, sync automatica al volver online.
// ============================================================================

import { useEffect, useRef, useState, useCallback } from 'react'
import {
  obtenerChecklistPublicoPorQR,
  guardarChecklistPublico,
  uploadEvidenciaChecklist,
  isOnline,
} from '@/lib/services/qr-checklist'
import {
  dbSaveChecklist,
  dbGetChecklist,
  dbDeleteChecklist,
  dbListChecklistsPendientes,
  dbSaveBlob,
  dbGetBlob,
  dbDeleteBlob,
  dbIsAvailable,
  generateClienteUuid,
} from '@/lib/offline/qr-checklist-db'
import type {
  ChecklistOfflineRecord,
  ChecklistPayload,
  ChecklistPayloadItem,
  EstadoSyncLocal,
  GuardarChecklistResponse,
  QrChecklistRpcResponse,
  QrTemplate,
  QrTemplateItem,
  RespuestaItemLocal,
  FotoMetadata,
} from '@/lib/offline/qr-checklist-types'

interface UseOfflineChecklistOptions {
  activoId: string
  /** Si se quiere reanudar un checklist existente, pasar su cliente_uuid */
  resumeClienteUuid?: string
}

export interface UseOfflineChecklistReturn {
  // Estado de carga del template
  loading: boolean
  template: QrTemplate | null
  items: QrTemplateItem[]
  itemsAleatorios: QrTemplateItem[]
  activo: QrChecklistRpcResponse['activo'] | null
  errorTemplate: string | null
  // Estado del checklist local
  checklist: ChecklistOfflineRecord | null
  // Resultado server post-sync
  resultado: GuardarChecklistResponse | null
  // Sync
  syncing: boolean
  syncError: string | null
  online: boolean
  // Acciones
  setRespuestaItem: (codigoItem: string, patch: Partial<RespuestaItemLocal>) => void
  attachFotoItem: (codigoItem: string, blob: Blob, origen: 'camera' | 'galeria', mime?: string) => Promise<void>
  setOperador: (data: Partial<Pick<ChecklistOfflineRecord,
    'operador_nombre' | 'operador_telefono' | 'operador_email' | 'operador_empresa' | 'rut_operador'>>) => void
  setLecturas: (km: number | null, horometro: number | null) => void
  setObservacionGeneral: (texto: string) => void
  setFirmaDeclaracion: (texto: string | null) => void
  capturarGpsInicial: () => Promise<void>
  capturarGpsFinal: () => Promise<void>
  submit: () => Promise<{ ok: boolean; data?: GuardarChecklistResponse; error?: string }>
  validarPreEnvio: () => { ok: boolean; faltantes: string[] }
}

// ── Helpers internos ────────────────────────────────────────────────

function getDispositivoInfo(): Record<string, unknown> {
  if (typeof navigator === 'undefined') return {}
  const ua = navigator.userAgent || ''
  return {
    user_agent: ua,
    platform: (navigator as unknown as { platform?: string }).platform || 'unknown',
    language: navigator.language,
    is_mobile: /Mobi|Android|iPhone|iPad/i.test(ua),
    online_at_init: navigator.onLine,
  }
}

async function getGeolocationOnce(): Promise<GeolocationPosition | null> {
  if (typeof navigator === 'undefined' || !navigator.geolocation) return null
  return new Promise<GeolocationPosition | null>((resolve) => {
    let done = false
    const timeout = setTimeout(() => { if (!done) { done = true; resolve(null) } }, 10000)
    navigator.geolocation.getCurrentPosition(
      (pos) => { if (!done) { done = true; clearTimeout(timeout); resolve(pos) } },
      () => { if (!done) { done = true; clearTimeout(timeout); resolve(null) } },
      { enableHighAccuracy: true, timeout: 8000, maximumAge: 30000 }
    )
  })
}

function buildEmptyRespuesta(item: QrTemplateItem): RespuestaItemLocal {
  return {
    template_item_id: item.id,
    seccion: item.seccion,
    orden: item.orden,
    codigo_item: item.codigo_item,
    descripcion: item.descripcion,
    respuesta_tipo: item.tipo_respuesta,
    respuesta_valor: null,
    es_falla: false,
    es_observacion: false,
    motivo: null,
    foto_blob_id: null,
    foto_url: null,
    foto_metadata: null,
    respondido_en: null,
    orden_respuesta: null,
    tiempo_desde_inicio_segundos: null,
    cambio_respuesta: false,
    respuesta_original: null,
    es_control_aleatorio: item.es_control_aleatorio,
  }
}

function recordToPayload(rec: ChecklistOfflineRecord): ChecklistPayload {
  const items: ChecklistPayloadItem[] = Object.values(rec.respuestas).map((r) => ({
    template_item_id: r.template_item_id,
    seccion: r.seccion,
    orden: r.orden,
    codigo_item: r.codigo_item,
    descripcion: r.descripcion,
    respuesta_tipo: r.respuesta_tipo,
    respuesta_valor: r.respuesta_valor,
    es_falla: r.es_falla,
    es_observacion: r.es_observacion,
    motivo: r.motivo,
    foto_url: r.foto_url,
    foto_metadata: r.foto_metadata,
    respondido_en: r.respondido_en,
    orden_respuesta: r.orden_respuesta,
    tiempo_desde_inicio_segundos: r.tiempo_desde_inicio_segundos,
    cambio_respuesta: r.cambio_respuesta,
    respuesta_original: r.respuesta_original,
    es_control_aleatorio: r.es_control_aleatorio,
  }))

  return {
    cliente_uuid: rec.cliente_uuid,
    activo_id: rec.activo_id,
    template_id: rec.template_id,
    operador_nombre: rec.operador_nombre,
    operador_telefono: rec.operador_telefono,
    operador_email: rec.operador_email,
    operador_empresa: rec.operador_empresa,
    rut_operador: rec.rut_operador,
    kilometraje_reportado: rec.kilometraje_reportado,
    horometro_reportado: rec.horometro_reportado,
    observacion_general: rec.observacion_general,
    iniciado_en: rec.iniciado_en,
    terminado_en: rec.terminado_en ?? new Date().toISOString(),
    gps_inicial_lat: rec.gps_inicial_lat,
    gps_inicial_lng: rec.gps_inicial_lng,
    gps_inicial_precision_m: rec.gps_inicial_precision_m,
    gps_final_lat: rec.gps_final_lat,
    gps_final_lng: rec.gps_final_lng,
    gps_final_precision_m: rec.gps_final_precision_m,
    gps_no_disponible: rec.gps_no_disponible,
    firma_url: rec.firma_url,
    firma_declaracion: rec.firma_declaracion,
    dispositivo_info: rec.dispositivo_info,
    scan_lat: rec.gps_inicial_lat,
    scan_lng: rec.gps_inicial_lng,
    created_offline_at: rec.iniciado_en,
    items,
  }
}

// ── Sync queue: subir blobs pendientes y enviar al RPC ──────────────
async function tryUploadBlobsAndPatchUrls(
  rec: ChecklistOfflineRecord
): Promise<ChecklistOfflineRecord> {
  const updated = { ...rec, respuestas: { ...rec.respuestas } }
  for (const codigo of Object.keys(updated.respuestas)) {
    const r = updated.respuestas[codigo]
    if (r.foto_blob_id && !r.foto_url) {
      const blobRec = await dbGetBlob(r.foto_blob_id)
      if (!blobRec) continue
      const { data, error } = await uploadEvidenciaChecklist(
        rec.cliente_uuid,
        codigo,
        blobRec.blob,
        blobRec.mime
      )
      if (data && !error) {
        updated.respuestas[codigo] = { ...r, foto_url: data.url }
      }
    }
  }
  return updated
}

// ── Sync de un checklist: upload fotos + RPC + cleanup ──────────────
async function syncSingleChecklist(
  rec: ChecklistOfflineRecord
): Promise<{ ok: boolean; data?: GuardarChecklistResponse; error?: string }> {
  try {
    const withUrls = await tryUploadBlobsAndPatchUrls(rec)
    await dbSaveChecklist({ ...withUrls, estado: 'sincronizando' })
    const payload = recordToPayload(withUrls)
    const { data, error } = await guardarChecklistPublico(payload)
    if (error || !data) {
      const errMsg = (error as { message?: string })?.message ?? 'Error desconocido'
      await dbSaveChecklist({
        ...withUrls,
        estado: 'error_sync',
        intentos_sync: (rec.intentos_sync ?? 0) + 1,
        ultimo_error_sync: errMsg,
      })
      return { ok: false, error: errMsg }
    }
    // Exito: marcar sincronizado y guardar respuesta server
    await dbSaveChecklist({
      ...withUrls,
      estado: 'sincronizado',
      ultimo_error_sync: null,
      servidor_respuesta_id: data.respuesta_id,
      servidor_semaforo: data.semaforo,
      servidor_score_calidad: data.score_calidad,
      servidor_clasificacion_calidad: data.clasificacion_calidad,
      servidor_sospechoso: data.sospechoso,
      servidor_alertas_tecnicas: data.alertas_tecnicas_generadas,
      servidor_alertas_calidad: data.alertas_calidad_generadas,
    })
    // Limpiar blobs ya subidos (foto_url presente)
    for (const r of Object.values(withUrls.respuestas)) {
      if (r.foto_url && r.foto_blob_id) await dbDeleteBlob(r.foto_blob_id)
    }
    return { ok: true, data }
  } catch (e) {
    const errMsg = e instanceof Error ? e.message : String(e)
    await dbSaveChecklist({
      ...rec,
      estado: 'error_sync',
      intentos_sync: (rec.intentos_sync ?? 0) + 1,
      ultimo_error_sync: errMsg,
    })
    return { ok: false, error: errMsg }
  }
}

export async function sincronizarChecklistsPendientes(): Promise<{
  intentados: number
  ok: number
  fallidos: number
}> {
  if (!dbIsAvailable() || !isOnline()) return { intentados: 0, ok: 0, fallidos: 0 }
  const pendientes = await dbListChecklistsPendientes()
  let ok = 0
  let fallidos = 0
  for (const rec of pendientes) {
    const r = await syncSingleChecklist(rec)
    if (r.ok) ok++
    else fallidos++
  }
  return { intentados: pendientes.length, ok, fallidos }
}

// ── Hook principal ──────────────────────────────────────────────────
export function useOfflineChecklist(
  options: UseOfflineChecklistOptions
): UseOfflineChecklistReturn {
  const { activoId, resumeClienteUuid } = options

  const [loading, setLoading] = useState(true)
  const [template, setTemplate] = useState<QrTemplate | null>(null)
  const [items, setItems] = useState<QrTemplateItem[]>([])
  const [itemsAleatorios, setItemsAleatorios] = useState<QrTemplateItem[]>([])
  const [activo, setActivo] = useState<QrChecklistRpcResponse['activo'] | null>(null)
  const [errorTemplate, setErrorTemplate] = useState<string | null>(null)
  const [checklist, setChecklist] = useState<ChecklistOfflineRecord | null>(null)
  const [resultado, setResultado] = useState<GuardarChecklistResponse | null>(null)
  const [syncing, setSyncing] = useState(false)
  const [syncError, setSyncError] = useState<string | null>(null)
  const [online, setOnline] = useState(isOnline())

  const ordenRespuestaCounter = useRef(0)
  const iniciadoEnRef = useRef<Date | null>(null)

  // ── Bootstrap: carga template y crea/reanuda checklist local ──
  useEffect(() => {
    let cancelled = false
    ;(async () => {
      setLoading(true)
      setErrorTemplate(null)
      const { data, error } = await obtenerChecklistPublicoPorQR(activoId)
      if (cancelled) return
      if (error || !data || data.error) {
        setErrorTemplate(data?.error ?? (error as { message?: string })?.message ?? 'Error cargando checklist')
        setLoading(false)
        return
      }
      const allItems = [...data.items, ...data.items_aleatorios]
      setTemplate(data.template)
      setItems(data.items)
      setItemsAleatorios(data.items_aleatorios)
      setActivo(data.activo)

      // Reanudar o crear nuevo
      let rec: ChecklistOfflineRecord | undefined
      if (resumeClienteUuid && dbIsAvailable()) {
        rec = await dbGetChecklist(resumeClienteUuid)
      }
      if (!rec) {
        const cliente_uuid = generateClienteUuid()
        const iniciado = new Date()
        iniciadoEnRef.current = iniciado
        const respuestas: Record<string, RespuestaItemLocal> = {}
        for (const it of allItems) respuestas[it.codigo_item] = buildEmptyRespuesta(it)
        rec = {
          cliente_uuid,
          activo_id: data.activo.id,
          template_id: data.template.id,
          template_snapshot: data.template,
          items_snapshot: allItems,
          operador_nombre: null,
          operador_telefono: null,
          operador_email: null,
          operador_empresa: null,
          rut_operador: null,
          kilometraje_reportado: null,
          horometro_reportado: null,
          iniciado_en: iniciado.toISOString(),
          terminado_en: null,
          duracion_segundos: null,
          gps_inicial_lat: null,
          gps_inicial_lng: null,
          gps_inicial_precision_m: null,
          gps_final_lat: null,
          gps_final_lng: null,
          gps_final_precision_m: null,
          gps_no_disponible: false,
          firma_declaracion: null,
          firma_url: null,
          dispositivo_info: getDispositivoInfo(),
          respuestas,
          observacion_general: null,
          estado: 'borrador',
          intentos_sync: 0,
          ultimo_error_sync: null,
          servidor_respuesta_id: null,
          servidor_semaforo: null,
          servidor_score_calidad: null,
          servidor_clasificacion_calidad: null,
          servidor_sospechoso: null,
          servidor_alertas_tecnicas: null,
          servidor_alertas_calidad: null,
          created_at: iniciado.toISOString(),
          updated_at: iniciado.toISOString(),
        }
        if (dbIsAvailable()) await dbSaveChecklist(rec)
      } else {
        iniciadoEnRef.current = new Date(rec.iniciado_en)
      }
      setChecklist(rec)
      setLoading(false)
    })()
    return () => { cancelled = true }
  }, [activoId, resumeClienteUuid])

  // ── Online/offline listener + auto-sync ──
  useEffect(() => {
    if (typeof window === 'undefined') return
    const handleOnline = () => {
      setOnline(true)
      sincronizarChecklistsPendientes().catch(() => undefined)
    }
    const handleOffline = () => setOnline(false)
    window.addEventListener('online', handleOnline)
    window.addEventListener('offline', handleOffline)
    return () => {
      window.removeEventListener('online', handleOnline)
      window.removeEventListener('offline', handleOffline)
    }
  }, [])

  // ── Persistencia con debounce ligero ──
  const persistChecklist = useCallback(async (rec: ChecklistOfflineRecord) => {
    if (dbIsAvailable()) await dbSaveChecklist(rec)
  }, [])

  // ── Acciones ──
  const setRespuestaItem = useCallback((codigoItem: string, patch: Partial<RespuestaItemLocal>) => {
    setChecklist((prev) => {
      if (!prev) return prev
      const prevR = prev.respuestas[codigoItem]
      if (!prevR) return prev
      const yaRespondido = prevR.respuesta_valor !== null || prevR.es_falla || prevR.es_observacion
      const cambio_respuesta = yaRespondido && (
        ('respuesta_valor' in patch && patch.respuesta_valor !== prevR.respuesta_valor) ||
        ('es_falla' in patch && patch.es_falla !== prevR.es_falla)
      )
      const respuesta_original = cambio_respuesta && !prevR.cambio_respuesta
        ? (prevR.respuesta_valor ?? (prevR.es_falla ? 'falla' : prevR.es_observacion ? 'observacion' : 'ok'))
        : prevR.respuesta_original
      const inicio = iniciadoEnRef.current ?? new Date(prev.iniciado_en)
      const tiempo_desde_inicio_segundos = Math.max(0, Math.round((Date.now() - inicio.getTime()) / 1000))
      ordenRespuestaCounter.current = Math.max(ordenRespuestaCounter.current, prevR.orden_respuesta ?? 0) + 1

      const next: RespuestaItemLocal = {
        ...prevR,
        ...patch,
        respondido_en: new Date().toISOString(),
        orden_respuesta: prevR.orden_respuesta ?? ordenRespuestaCounter.current,
        tiempo_desde_inicio_segundos,
        cambio_respuesta: cambio_respuesta || prevR.cambio_respuesta,
        respuesta_original,
      }
      const nextRec: ChecklistOfflineRecord = {
        ...prev,
        respuestas: { ...prev.respuestas, [codigoItem]: next },
        updated_at: new Date().toISOString(),
      }
      void persistChecklist(nextRec)
      return nextRec
    })
  }, [persistChecklist])

  const attachFotoItem = useCallback(async (
    codigoItem: string,
    blob: Blob,
    origen: 'camera' | 'galeria',
    mime?: string
  ) => {
    if (!checklist) return
    const blobId = generateClienteUuid()
    if (dbIsAvailable()) await dbSaveBlob(blobId, checklist.cliente_uuid, codigoItem, blob, mime)
    let lat: number | null = null
    let lng: number | null = null
    const pos = await getGeolocationOnce()
    if (pos) { lat = pos.coords.latitude; lng = pos.coords.longitude }
    const meta: FotoMetadata = {
      timestamp: new Date().toISOString(),
      origen,
      lat, lng,
      item_id: checklist.respuestas[codigoItem]?.template_item_id ?? null,
      activo_id: checklist.activo_id,
      size_bytes: blob.size,
      mime: blob.type || mime,
    }
    setRespuestaItem(codigoItem, {
      foto_blob_id: blobId,
      foto_url: null,
      foto_metadata: meta,
    })
  }, [checklist, setRespuestaItem])

  const setOperador = useCallback((data: Partial<Pick<ChecklistOfflineRecord,
    'operador_nombre' | 'operador_telefono' | 'operador_email' | 'operador_empresa' | 'rut_operador'>>) => {
    setChecklist((prev) => {
      if (!prev) return prev
      const next = { ...prev, ...data, updated_at: new Date().toISOString() }
      void persistChecklist(next)
      return next
    })
  }, [persistChecklist])

  const setLecturas = useCallback((km: number | null, horometro: number | null) => {
    setChecklist((prev) => {
      if (!prev) return prev
      const next = {
        ...prev,
        kilometraje_reportado: km,
        horometro_reportado: horometro,
        updated_at: new Date().toISOString(),
      }
      void persistChecklist(next)
      return next
    })
  }, [persistChecklist])

  const setObservacionGeneral = useCallback((texto: string) => {
    setChecklist((prev) => {
      if (!prev) return prev
      const next = { ...prev, observacion_general: texto, updated_at: new Date().toISOString() }
      void persistChecklist(next)
      return next
    })
  }, [persistChecklist])

  const setFirmaDeclaracion = useCallback((texto: string | null) => {
    setChecklist((prev) => {
      if (!prev) return prev
      const next = { ...prev, firma_declaracion: texto, updated_at: new Date().toISOString() }
      void persistChecklist(next)
      return next
    })
  }, [persistChecklist])

  const capturarGpsInicial = useCallback(async () => {
    const pos = await getGeolocationOnce()
    setChecklist((prev) => {
      if (!prev) return prev
      const next = pos
        ? {
            ...prev,
            gps_inicial_lat: pos.coords.latitude,
            gps_inicial_lng: pos.coords.longitude,
            gps_inicial_precision_m: pos.coords.accuracy,
            gps_no_disponible: false,
          }
        : { ...prev, gps_no_disponible: true }
      const updated = { ...next, updated_at: new Date().toISOString() }
      void persistChecklist(updated)
      return updated
    })
  }, [persistChecklist])

  const capturarGpsFinal = useCallback(async () => {
    const pos = await getGeolocationOnce()
    setChecklist((prev) => {
      if (!prev) return prev
      const next = pos
        ? {
            ...prev,
            gps_final_lat: pos.coords.latitude,
            gps_final_lng: pos.coords.longitude,
            gps_final_precision_m: pos.coords.accuracy,
          }
        : { ...prev, gps_no_disponible: prev.gps_inicial_lat === null }
      const updated = { ...next, updated_at: new Date().toISOString() }
      void persistChecklist(updated)
      return updated
    })
  }, [persistChecklist])

  // ── Validacion pre-envio ──
  const validarPreEnvio = useCallback((): { ok: boolean; faltantes: string[] } => {
    if (!checklist) return { ok: false, faltantes: ['No hay checklist cargado.'] }
    const faltantes: string[] = []
    if (!checklist.firma_declaracion || checklist.firma_declaracion.trim().length < 5) {
      faltantes.push('Aceptar la declaracion responsable.')
    }
    if (!checklist.operador_nombre || checklist.operador_nombre.trim().length < 2) {
      faltantes.push('Nombre del operador.')
    }
    for (const item of checklist.items_snapshot) {
      const r = checklist.respuestas[item.codigo_item]
      if (!r) continue
      const respondido = r.respuesta_valor !== null || r.es_falla || r.es_observacion
      if (item.obligatorio && !respondido) {
        faltantes.push(`Responder: ${item.descripcion}`)
        continue
      }
      if (item.requiere_foto_siempre && !r.foto_blob_id && !r.foto_url) {
        faltantes.push(`Foto obligatoria: ${item.descripcion}`)
      }
      if (r.es_falla && item.requiere_foto_si_falla && !r.foto_blob_id && !r.foto_url) {
        faltantes.push(`Foto requerida por falla: ${item.descripcion}`)
      }
      if (r.es_falla && item.requiere_observacion_si_falla && (!r.motivo || r.motivo.trim().length < 3)) {
        faltantes.push(`Observacion requerida por falla: ${item.descripcion}`)
      }
    }
    return { ok: faltantes.length === 0, faltantes }
  }, [checklist])

  // ── Submit ──
  const submit = useCallback(async (): Promise<{
    ok: boolean
    data?: GuardarChecklistResponse
    error?: string
  }> => {
    if (!checklist) return { ok: false, error: 'no_checklist' }
    setSyncing(true)
    setSyncError(null)
    // Cerrar cronometro + GPS final
    const inicio = iniciadoEnRef.current ?? new Date(checklist.iniciado_en)
    const ahora = new Date()
    const duracion = Math.max(0, Math.round((ahora.getTime() - inicio.getTime()) / 1000))
    let recCierre: ChecklistOfflineRecord = {
      ...checklist,
      terminado_en: ahora.toISOString(),
      duracion_segundos: duracion,
      estado: 'pendiente_sync' as EstadoSyncLocal,
      updated_at: ahora.toISOString(),
    }
    // GPS final si no se capturo aun
    if (recCierre.gps_final_lat === null) {
      const pos = await getGeolocationOnce()
      if (pos) {
        recCierre = {
          ...recCierre,
          gps_final_lat: pos.coords.latitude,
          gps_final_lng: pos.coords.longitude,
          gps_final_precision_m: pos.coords.accuracy,
        }
      } else if (recCierre.gps_inicial_lat === null) {
        recCierre = { ...recCierre, gps_no_disponible: true }
      }
    }
    if (dbIsAvailable()) await dbSaveChecklist(recCierre)
    setChecklist(recCierre)

    if (!isOnline()) {
      setSyncing(false)
      return { ok: true, error: 'offline_guardado_local' }
    }

    const r = await syncSingleChecklist(recCierre)
    setSyncing(false)
    if (r.ok && r.data) {
      setResultado(r.data)
      // Recargar registro actualizado del IDB
      if (dbIsAvailable()) {
        const fresco = await dbGetChecklist(recCierre.cliente_uuid)
        if (fresco) setChecklist(fresco)
      }
      return { ok: true, data: r.data }
    }
    setSyncError(r.error ?? 'error_sync')
    return { ok: false, error: r.error }
  }, [checklist])

  return {
    loading,
    template, items, itemsAleatorios, activo,
    errorTemplate,
    checklist,
    resultado,
    syncing, syncError, online,
    setRespuestaItem,
    attachFotoItem,
    setOperador,
    setLecturas,
    setObservacionGeneral,
    setFirmaDeclaracion,
    capturarGpsInicial,
    capturarGpsFinal,
    submit,
    validarPreEnvio,
  }
}

// ── Hook auxiliar para reintentos manuales del sync queue ──
export function useChecklistSyncQueue() {
  const [syncing, setSyncing] = useState(false)
  const [lastResult, setLastResult] = useState<{ intentados: number; ok: number; fallidos: number } | null>(null)

  const run = useCallback(async () => {
    if (syncing) return
    setSyncing(true)
    const r = await sincronizarChecklistsPendientes()
    setLastResult(r)
    setSyncing(false)
  }, [syncing])

  // Auto-run on mount + on online events
  useEffect(() => {
    if (typeof window === 'undefined') return
    const handler = () => { void run() }
    window.addEventListener('online', handler)
    void run()
    return () => window.removeEventListener('online', handler)
  }, [run])

  return { syncing, lastResult, retry: run }
}
