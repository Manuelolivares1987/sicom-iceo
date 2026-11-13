'use client'

// ============================================================================
// Inspección de terreno APR — formulario por etapas (MIG685)
// ----------------------------------------------------------------------------
// Sigue el documento de prevención Calama (12-11-26) etapa por etapa. Todo se
// guarda en el teléfono al instante (IndexedDB, fotos incluidas) y se envía
// cuando hay señal. Los puntos «documental» y «fatiga» no se marcan a mano:
// salen del control documental y de la encuesta, y la base los recalcula al
// recibir la inspección.
// ============================================================================

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import {
  AlertTriangle, Ban, Camera, Check, CheckCircle2, ChevronLeft, ChevronRight,
  CircleSlash, CloudUpload, FileDown, FileSearch, Loader2, Minus, Moon, ShieldCheck,
  UserCheck, Users, X,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useToast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import { compressImage } from '@/lib/image/compress'
import {
  ESTADO_REQ_LABEL, PREGUNTAS_FATIGA, evaluarFatiga, guardarInspeccion,
  subirFotoInspeccion, urlEvidencia,
  type FatigaRespuestas, type PuntoPlantilla, type Respuesta,
} from '@/lib/services/prevencion-inspeccion'
import {
  borrarFotoLocal, fotosPendientes, guardarBorrador, guardarFotoLocal, leerFotoLocal,
  respuestaVacia,
  type BorradorInspeccion, type FotoRef, type PersonaLocal, type RespuestaLocal,
} from '@/lib/offline/inspeccion-apr-db'

// ── Resultado automático (misma regla que la base) ───────────────────────────

export function respuestaAutomatica(b: BorradorInspeccion, p: PuntoPlantilla): Respuesta | null | undefined {
  if (p.solo_cruzado && !b.trabajo_cruzado) return 'no_aplica'
  if (p.evidencia === 'documental') {
    const reqs = b.personas.flatMap((pl) => {
      const h = b.habilitacion.personas.find((x) => x.personal_id === pl.personal_id)
      return (h?.requisitos ?? []).filter((r) =>
        r.item_codigo === p.codigo && (r.aplica_a === 'todos' || pl.es_conductor))
    })
    if (!reqs.length) return 'no_aplica'
    return reqs.some((r) => !r.ok) ? 'no_cumple' : 'cumple'
  }
  if (p.evidencia === 'fatiga') {
    const cond = b.personas.filter((x) => x.es_conductor)
    if (!cond.length) return 'no_aplica'
    const ev = cond.map((c) => evaluarFatiga(c.fatiga).resultado)
    if (ev.includes('no_apto')) return 'no_cumple'
    if (ev.includes('incompleta')) return null
    return 'cumple'
  }
  return undefined // lo responde el APR
}

function respuestaFinal(b: BorradorInspeccion, p: PuntoPlantilla): Respuesta | null {
  const auto = respuestaAutomatica(b, p)
  return auto !== undefined ? auto : (b.respuestas[p.codigo]?.respuesta ?? null)
}

export function avanceBorrador(b: BorradorInspeccion) {
  let cumple = 0, noCumple = 0, noAplica = 0, pend = 0
  for (const p of b.plantilla) {
    const r = respuestaFinal(b, p)
    if (r === 'cumple') cumple++
    else if (r === 'no_cumple') noCumple++
    else if (r === 'no_aplica') noAplica++
    else pend++
  }
  const total = b.plantilla.length
  return {
    cumple, noCumple, noAplica, pend, total,
    pct: cumple + noCumple > 0 ? Math.round((1000 * cumple) / (cumple + noCumple)) / 10 : null,
  }
}

// ── Miniatura de foto (local o subida) ───────────────────────────────────────

function FotoThumb({ f, onQuitar }: { f: FotoRef, onQuitar?: () => void }) {
  const [src, setSrc] = useState<string | null>(null)
  useEffect(() => {
    let url: string | null = null
    let vivo = true
    ;(async () => {
      if (f.local_id) {
        const blob = await leerFotoLocal(f.local_id)
        if (blob && vivo) { url = URL.createObjectURL(blob); setSrc(url) }
      } else if (f.subida && navigator.onLine) {
        const s = await urlEvidencia(f.subida.path)
        if (vivo) setSrc(s)
      }
    })()
    return () => { vivo = false; if (url) URL.revokeObjectURL(url) }
  }, [f.local_id, f.subida])
  return (
    <div className="relative h-20 w-20 overflow-hidden rounded-lg border border-gray-200 bg-gray-100">
      {src ? <img src={src} alt={f.nombre} className="h-full w-full object-cover" />
           : <div className="grid h-full w-full place-items-center text-[10px] text-gray-400">foto</div>}
      {!f.subida && (
        <span className="absolute bottom-0 left-0 right-0 bg-amber-500/90 text-center text-[9px] font-bold text-white">
          sin enviar
        </span>
      )}
      {onQuitar && (
        <button type="button" onClick={onQuitar}
                className="absolute right-0.5 top-0.5 rounded-full bg-black/60 p-0.5 text-white">
          <X className="h-3 w-3" />
        </button>
      )}
    </div>
  )
}

// ── Chips de respuesta ───────────────────────────────────────────────────────

const RESP_UI: Record<Respuesta, { label: string, on: string, icon: any }> = {
  cumple:    { label: 'Cumple',    on: 'border-emerald-600 bg-emerald-600 text-white', icon: Check },
  no_cumple: { label: 'No cumple', on: 'border-red-600 bg-red-600 text-white',         icon: X },
  no_aplica: { label: 'No aplica', on: 'border-gray-600 bg-gray-600 text-white',       icon: Minus },
}

function BadgeResp({ r }: { r: Respuesta | null }) {
  if (!r) return <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-bold text-amber-800">Pendiente</span>
  const u = RESP_UI[r]
  return <span className={cn('rounded-full border px-2 py-0.5 text-[11px] font-bold', u.on)}>{u.label}</span>
}

// ── Un punto de la inspección ────────────────────────────────────────────────

function Punto({ b, p, onCambiar, onFoto, onQuitarFoto }: {
  b: BorradorInspeccion
  p: PuntoPlantilla
  onCambiar: (patch: Partial<RespuestaLocal>) => void
  onFoto: (files: FileList) => void
  onQuitarFoto: (idx: number) => void
}) {
  const r = b.respuestas[p.codigo] ?? respuestaVacia()
  const auto = respuestaAutomatica(b, p)
  const fileRef = useRef<HTMLInputElement>(null)
  const final = auto !== undefined ? auto : r.respuesta

  // Detalle de lo automático: quién falla y por qué.
  const fallasDoc = p.evidencia === 'documental'
    ? b.personas.flatMap((pl) => {
        const h = b.habilitacion.personas.find((x) => x.personal_id === pl.personal_id)
        return (h?.requisitos ?? [])
          .filter((q) => q.item_codigo === p.codigo && (q.aplica_a === 'todos' || pl.es_conductor) && !q.ok)
          .map((q) => `${pl.nombre}: ${q.nombre} — ${ESTADO_REQ_LABEL[q.estado] ?? q.estado}`)
      })
    : []

  return (
    <div className={cn(
      'rounded-xl border bg-white p-3',
      final === 'no_cumple' ? 'border-red-300' : final === 'cumple' ? 'border-emerald-300' : 'border-gray-200',
    )}>
      <div className="flex items-start gap-2">
        <span className="mt-0.5 rounded bg-gray-900 px-1.5 py-0.5 text-[10px] font-bold text-white">{p.codigo}</span>
        <p className="min-w-0 flex-1 text-sm font-medium leading-snug text-gray-900">{p.pregunta}</p>
      </div>
      {p.ayuda && <p className="mt-1 pl-8 text-[11px] text-gray-500">{p.ayuda}</p>}

      {auto !== undefined ? (
        <div className="mt-2 space-y-1.5 pl-8">
          <div className="flex items-center gap-2">
            <BadgeResp r={auto} />
            <span className="flex items-center gap-1 text-[11px] text-gray-500">
              {p.evidencia === 'documental' ? <><FileSearch className="h-3 w-3" /> desde el control documental</>
               : p.evidencia === 'fatiga' ? <><Moon className="h-3 w-3" /> desde la encuesta de fatiga</>
               : 'sin trabajo cruzado'}
            </span>
          </div>
          {fallasDoc.length > 0 && (
            <ul className="space-y-0.5 rounded-lg bg-red-50 p-2 text-[11px] text-red-800">
              {fallasDoc.map((t) => <li key={t}>• {t}</li>)}
            </ul>
          )}
          {auto === null && p.evidencia === 'fatiga' && (
            <p className="text-[11px] text-amber-700">Falta completar la encuesta de algún conductor (pestaña Cuadrilla).</p>
          )}
        </div>
      ) : (
        <div className="mt-2 space-y-2 pl-8">
          <div className="grid grid-cols-3 gap-1.5">
            {(Object.keys(RESP_UI) as Respuesta[]).map((k) => {
              const u = RESP_UI[k]; const Icon = u.icon
              return (
                <button key={k} type="button"
                        onClick={() => onCambiar({ respuesta: r.respuesta === k ? null : k })}
                        className={cn('flex items-center justify-center gap-1 rounded-lg border px-1 py-2 text-xs font-semibold',
                          r.respuesta === k ? u.on : 'border-gray-300 bg-white text-gray-700')}>
                  <Icon className="h-3.5 w-3.5" />{u.label}
                </button>
              )
            })}
          </div>

          <div className="flex flex-wrap gap-2">
            {r.fotos.map((f, i) => <FotoThumb key={(f.local_id ?? f.subida?.path ?? '') + i} f={f} onQuitar={() => onQuitarFoto(i)} />)}
            <button type="button" onClick={() => fileRef.current?.click()}
                    className={cn('grid h-20 w-20 place-items-center rounded-lg border-2 border-dashed text-[11px]',
                      p.evidencia === 'foto' && r.respuesta === 'cumple' && r.fotos.length === 0
                        ? 'border-red-400 text-red-600' : 'border-gray-300 text-gray-500')}>
              <span className="flex flex-col items-center gap-0.5">
                <Camera className="h-5 w-5" />
                {p.evidencia === 'foto' ? 'Foto' : 'Foto (opc.)'}
              </span>
            </button>
            <input ref={fileRef} type="file" accept="image/*" capture="environment" multiple hidden
                   onChange={(e) => { if (e.target.files?.length) onFoto(e.target.files); e.target.value = '' }} />
          </div>
          {p.evidencia === 'foto' && r.respuesta === 'cumple' && r.fotos.length === 0 && (
            <p className="text-[11px] font-medium text-red-600">«Cumple» exige foto de respaldo.</p>
          )}

          <textarea
            className="min-h-[44px] w-full rounded-lg border border-gray-300 px-2.5 py-1.5 text-sm"
            placeholder="Observación (opcional)"
            value={r.observacion}
            onChange={(e) => onCambiar({ observacion: e.target.value })}
          />

          {r.respuesta === 'no_cumple' && (
            <div className="space-y-2 rounded-lg border border-red-200 bg-red-50 p-2.5">
              <p className="text-xs font-bold text-red-800">Desviación (obligatoria)</p>
              <textarea
                className="min-h-[44px] w-full rounded-lg border border-red-200 bg-white px-2.5 py-1.5 text-sm"
                placeholder="¿Qué se encontró?"
                value={r.desv_descripcion}
                onChange={(e) => onCambiar({ desv_descripcion: e.target.value })}
              />
              <Input placeholder="Acción correctiva" value={r.desv_accion}
                     onChange={(e) => onCambiar({ desv_accion: e.target.value })} />
              <div className="grid grid-cols-2 gap-2">
                <Input placeholder="Responsable" value={r.desv_responsable}
                       onChange={(e) => onCambiar({ desv_responsable: e.target.value })} />
                <Input type="date" value={r.desv_fecha}
                       onChange={(e) => onCambiar({ desv_fecha: e.target.value })} />
              </div>
              <div className="grid grid-cols-3 gap-1.5">
                {(['alta', 'media', 'baja'] as const).map((c) => (
                  <button key={c} type="button" onClick={() => onCambiar({ desv_criticidad: c })}
                          className={cn('rounded-lg border py-1.5 text-xs font-semibold capitalize',
                            r.desv_criticidad === c
                              ? c === 'alta' ? 'border-red-700 bg-red-700 text-white'
                                : c === 'media' ? 'border-amber-600 bg-amber-600 text-white'
                                : 'border-gray-600 bg-gray-600 text-white'
                              : 'border-gray-300 bg-white text-gray-700')}>
                    {c}
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  )
}

// ── Encuesta de fatiga de un conductor ───────────────────────────────────────

function EncuestaFatiga({ f, onCambiar }: { f: FatigaRespuestas, onCambiar: (f: FatigaRespuestas) => void }) {
  const ev = evaluarFatiga(f)
  const num = (k: keyof FatigaRespuestas) => (
    <Input type="number" inputMode="decimal" min={0} max={48}
           value={f[k] == null ? '' : String(f[k])}
           onChange={(e) => onCambiar({ ...f, [k]: e.target.value === '' ? null : Number(e.target.value) })} />
  )
  return (
    <div className="mt-2 space-y-2 rounded-lg border border-indigo-200 bg-indigo-50/60 p-2.5">
      <p className="flex items-center gap-1 text-xs font-bold text-indigo-900">
        <Moon className="h-3.5 w-3.5" /> Encuesta de fatiga y somnolencia
      </p>
      <div className="grid grid-cols-3 gap-2 text-[11px] text-gray-700">
        <label>Horas dormidas últimas 24 h{num('horas_24')}</label>
        <label>Horas dormidas últimas 48 h{num('horas_48')}</label>
        <label>Horas despierto al iniciar{num('horas_despierto')}</label>
      </div>
      <ul className="space-y-1.5">
        {PREGUNTAS_FATIGA.map((q) => (
          <li key={q.clave} className="flex items-center gap-2">
            <span className="min-w-0 flex-1 text-[12px] text-gray-800">{q.texto}</span>
            {[true, false].map((v) => (
              <button key={String(v)} type="button"
                      onClick={() => onCambiar({ ...f, [q.clave]: v })}
                      className={cn('w-11 rounded-md border py-1 text-xs font-semibold',
                        f[q.clave] === v
                          ? v ? 'border-red-600 bg-red-600 text-white' : 'border-emerald-600 bg-emerald-600 text-white'
                          : 'border-gray-300 bg-white text-gray-700')}>
                {v ? 'Sí' : 'No'}
              </button>
            ))}
          </li>
        ))}
      </ul>
      <div className={cn('rounded-md px-2 py-1.5 text-xs font-semibold',
        ev.resultado === 'apto' ? 'bg-emerald-100 text-emerald-800'
        : ev.resultado === 'apto_observacion' ? 'bg-amber-100 text-amber-800'
        : ev.resultado === 'no_apto' ? 'bg-red-600 text-white'
        : 'bg-gray-100 text-gray-600')}>
        {ev.resultado === 'apto' ? 'APTO para conducir'
         : ev.resultado === 'apto_observacion' ? 'APTO con observación'
         : ev.resultado === 'no_apto' ? 'NO APTO — no conduce'
         : 'Encuesta incompleta'}
        {ev.motivos.length > 0 && <span className="block font-normal">{ev.motivos.join(' · ')}</span>}
      </div>
    </div>
  )
}

// ── Formulario principal ─────────────────────────────────────────────────────

export function InspeccionAprForm({ inicial, onPdf, volver }: {
  inicial: BorradorInspeccion
  onPdf?: (servidorId: string) => void
  volver?: ReactNode
}) {
  const toast = useToast()
  const [b, setB] = useState<BorradorInspeccion>(inicial)
  const [paso, setPaso] = useState(0)
  const [enviando, setEnviando] = useState<string | null>(null)

  // Cada cambio queda en el teléfono al instante: si se cierra la app o se
  // apaga, la inspección sigue ahí.
  const actualizar = useCallback((fn: (prev: BorradorInspeccion) => BorradorInspeccion) => {
    setB((prev) => {
      const next = fn(prev)
      guardarBorrador(next).catch(() => {})
      return next
    })
  }, [])

  const etapas = useMemo(() => {
    const m = new Map<number, { nombre: string, puntos: PuntoPlantilla[] }>()
    for (const p of b.plantilla) {
      if (!m.has(p.etapa_orden)) m.set(p.etapa_orden, { nombre: p.etapa, puntos: [] })
      m.get(p.etapa_orden)!.puntos.push(p)
    }
    return Array.from(m.entries()).sort((a, z) => a[0] - z[0]).map(([, v]) => v)
  }, [b.plantilla])

  // Pasos: 0 Datos · 1 Cuadrilla · 2..N etapas · último Resumen
  const pasos = ['Datos', 'Cuadrilla', ...etapas.map((e) => e.nombre), 'Resumen']
  const ultimo = pasos.length - 1
  const av = avanceBorrador(b)
  const fotosSinEnviar = fotosPendientes(b)

  const setResp = (codigo: string, patch: Partial<RespuestaLocal>) =>
    actualizar((prev) => ({
      ...prev,
      respuestas: { ...prev.respuestas, [codigo]: { ...(prev.respuestas[codigo] ?? respuestaVacia()), ...patch } },
    }))

  const agregarFotos = async (codigo: string, files: FileList) => {
    try {
      const refs: FotoRef[] = []
      for (const file of Array.from(files)) {
        const blob = await compressImage(file)
        const id = await guardarFotoLocal(b.cliente_uuid, blob, file.name || 'foto.jpg')
        refs.push({ local_id: id, nombre: file.name || 'foto.jpg' })
      }
      actualizar((prev) => {
        const r = prev.respuestas[codigo] ?? respuestaVacia()
        // Tomar la foto ya es decir «esto está»: si no había respuesta, se
        // sugiere «cumple» (se puede cambiar).
        return {
          ...prev,
          respuestas: { ...prev.respuestas, [codigo]: { ...r, respuesta: r.respuesta ?? 'cumple', fotos: [...r.fotos, ...refs] } },
        }
      })
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo guardar la foto en el teléfono')
    }
  }

  const quitarFoto = (codigo: string, idx: number) => {
    const f = b.respuestas[codigo]?.fotos[idx]
    if (f?.local_id) borrarFotoLocal(f.local_id).catch(() => {})
    actualizar((prev) => {
      const r = prev.respuestas[codigo] ?? respuestaVacia()
      return { ...prev, respuestas: { ...prev.respuestas, [codigo]: { ...r, fotos: r.fotos.filter((_, i) => i !== idx) } } }
    })
  }

  const togglePersona = (personal_id: string, nombre: string) =>
    actualizar((prev) => prev.personas.some((x) => x.personal_id === personal_id)
      ? { ...prev, personas: prev.personas.filter((x) => x.personal_id !== personal_id) }
      : { ...prev, personas: [...prev.personas, { personal_id, nombre, es_conductor: false, fatiga: {} }] })

  const setPersona = (personal_id: string, patch: Partial<PersonaLocal>) =>
    actualizar((prev) => ({
      ...prev,
      personas: prev.personas.map((x) => x.personal_id === personal_id ? { ...x, ...patch } : x),
    }))

  // ── Validación y envío ──
  const problemas = useMemo(() => {
    const out: string[] = []
    if (!b.trabajo.trim()) out.push('Falta describir el trabajo inspeccionado (Datos).')
    if (!b.personas.length) out.push('Falta la cuadrilla (al menos un trabajador).')
    for (const p of b.plantilla) {
      if (respuestaAutomatica(b, p) !== undefined) continue
      const r = b.respuestas[p.codigo]
      if (!r) continue
      if (r.respuesta === 'cumple' && p.evidencia === 'foto' && !r.fotos.length) {
        out.push(`${p.codigo}: «cumple» sin foto.`)
      }
      if (r.respuesta === 'no_cumple' && !r.desv_descripcion.trim()) {
        out.push(`${p.codigo}: «no cumple» sin desviación descrita.`)
      }
    }
    return out
  }, [b])

  const enviar = async () => {
    if (problemas.length) { setPaso(ultimo); return toast.error(problemas[0]) }
    if (!navigator.onLine) return toast.error('Sin señal. La inspección queda guardada en el teléfono: envíela al tener conexión.')
    let actual = b
    try {
      // 1) Fotos pendientes al bucket, una por una; cada subida queda anotada
      //    en el borrador, así un corte a mitad no repite las ya enviadas.
      const total = fotosPendientes(actual)
      let n = 0
      for (const codigo of Object.keys(actual.respuestas)) {
        const r = actual.respuestas[codigo]
        for (let i = 0; i < r.fotos.length; i++) {
          const f = r.fotos[i]
          if (f.subida || !f.local_id) continue
          n++
          setEnviando(`Subiendo foto ${n} de ${total}…`)
          const blob = await leerFotoLocal(f.local_id)
          if (!blob) continue
          const file = new File([blob], f.nombre.replace(/\.[^.]+$/, '') + '.jpg', { type: blob.type || 'image/jpeg' })
          const ev = await subirFotoInspeccion(file, actual.faena_id, actual.fecha)
          const fotos = actual.respuestas[codigo].fotos.map((x, j) => j === i ? { subida: ev, nombre: x.nombre } : x)
          actual = { ...actual, respuestas: { ...actual.respuestas, [codigo]: { ...actual.respuestas[codigo], fotos } } }
          await guardarBorrador(actual)
          await borrarFotoLocal(f.local_id)
        }
      }
      setB(actual)

      // 2) La inspección completa en una llamada (idempotente).
      setEnviando('Enviando la inspección…')
      const res = await guardarInspeccion({
        cliente_uuid: actual.cliente_uuid,
        faena_id: actual.faena_id,
        fecha: actual.fecha,
        hora_inicio: actual.hora_inicio || null,
        instalacion: actual.instalacion || null,
        area_sector: actual.area_sector || null,
        trabajo: actual.trabajo,
        supervisor: actual.supervisor || null,
        trabajo_cruzado: actual.trabajo_cruzado,
        empresas_cruzadas: actual.empresas_cruzadas || null,
        observacion: actual.observacion || null,
        personas: actual.personas.map((p) => ({
          personal_id: p.personal_id, es_conductor: p.es_conductor,
          fatiga: p.es_conductor ? p.fatiga : undefined,
        })),
        items: actual.plantilla.map((p) => {
          const r = actual.respuestas[p.codigo]
          return {
            item_codigo: p.codigo,
            respuesta: r?.respuesta ?? null,
            observacion: r?.observacion || null,
            evidencias: (r?.fotos ?? []).filter((f) => f.subida).map((f) => f.subida!),
          }
        }),
        desviaciones: actual.plantilla
          .filter((p) => actual.respuestas[p.codigo]?.respuesta === 'no_cumple')
          .map((p) => {
            const r = actual.respuestas[p.codigo]
            return {
              item_codigo: p.codigo,
              descripcion: r.desv_descripcion,
              accion: r.desv_accion || undefined,
              responsable: r.desv_responsable || undefined,
              fecha_compromiso: r.desv_fecha || undefined,
              criticidad: r.desv_criticidad,
            }
          }),
      })
      actual = {
        ...actual,
        servidor_id: res.id,
        ultimo_envio: { at: new Date().toISOString(), estado: res.estado, resultado: res.resultado },
      }
      await guardarBorrador(actual)
      setB(actual)
      toast.success(
        res.estado === 'cerrada' ? 'Inspección cerrada y enviada'
        : res.estado === 'pendiente_cierre_art' ? 'Enviada. Falta el cierre de la ART al volver a Calama'
        : 'Avance enviado',
      )
    } catch (e: any) {
      setB(actual)
      toast.error(e?.message ?? 'No se pudo enviar. Quedó guardada en el teléfono.')
    } finally {
      setEnviando(null)
    }
  }

  const grupoPersonas = b.habilitacion.personas
  const etapaIdx = paso - 2

  return (
    <div className="pb-28">
      {/* Cabecera fija con avance */}
      <div className="sticky top-0 z-10 border-b border-gray-200 bg-white/95 px-4 pb-2 pt-[max(0.75rem,env(safe-area-inset-top))] backdrop-blur">
        <div className="flex items-center gap-2">
          {volver}
          <ShieldCheck className="h-5 w-5 shrink-0 text-pillado-green-500" />
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-bold text-gray-900">{b.trabajo || 'Inspección de terreno APR'}</p>
            <p className="truncate text-[11px] text-gray-500">{b.faena_nombre} · {b.fecha}</p>
          </div>
          {b.ultimo_envio ? (
            <span className="shrink-0 rounded-full bg-blue-100 px-2 py-0.5 text-[10px] font-bold text-blue-700">enviada</span>
          ) : (
            <span className="shrink-0 rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-bold text-amber-800">en teléfono</span>
          )}
        </div>
        <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-gray-100">
          <div className="h-full bg-pillado-green-500 transition-all"
               style={{ width: `${Math.round(100 * (av.total - av.pend) / Math.max(av.total, 1))}%` }} />
        </div>
        <div className="mt-2 flex gap-1 overflow-x-auto pb-1">
          {pasos.map((n, i) => (
            <button key={n} onClick={() => setPaso(i)}
                    className={cn('shrink-0 rounded-full border px-2.5 py-1 text-[11px] font-semibold',
                      paso === i ? 'border-gray-900 bg-gray-900 text-white' : 'border-gray-200 bg-white text-gray-600')}>
              {i >= 2 && i < ultimo ? `${i - 1}. ` : ''}{n}
            </button>
          ))}
        </div>
      </div>

      <main className="space-y-3 px-4 py-4">
        {/* ── Datos ── */}
        {paso === 0 && (
          <div className="space-y-3 rounded-xl border border-gray-200 bg-white p-3">
            <p className="text-xs font-bold uppercase text-gray-500">Datos de la inspección</p>
            <div className="grid grid-cols-2 gap-2">
              <Input label="Fecha" type="date" value={b.fecha}
                     onChange={(e) => actualizar((p) => ({ ...p, fecha: e.target.value }))} />
              <Input label="Hora inicio" type="time" value={b.hora_inicio}
                     onChange={(e) => actualizar((p) => ({ ...p, hora_inicio: e.target.value }))} />
            </div>
            <Input label="Trabajo inspeccionado" value={b.trabajo} placeholder="Ej: Mantención surtidor EDS 3"
                   onChange={(e) => actualizar((p) => ({ ...p, trabajo: e.target.value }))} />
            <div className="grid grid-cols-2 gap-2">
              <Input label="Instalación" value={b.instalacion} placeholder="Ej: EDS Óxido"
                     onChange={(e) => actualizar((p) => ({ ...p, instalacion: e.target.value }))} />
              <Input label="Área / sector" value={b.area_sector}
                     onChange={(e) => actualizar((p) => ({ ...p, area_sector: e.target.value }))} />
            </div>
            <Input label="Supervisor a cargo" value={b.supervisor}
                   onChange={(e) => actualizar((p) => ({ ...p, supervisor: e.target.value }))} />
            <label className="flex items-center gap-2 rounded-lg border border-gray-200 p-3 text-sm">
              <input type="checkbox" className="h-4 w-4" checked={b.trabajo_cruzado}
                     onChange={(e) => actualizar((p) => ({ ...p, trabajo_cruzado: e.target.checked }))} />
              Hay <b>trabajos cruzados</b> con otras empresas
            </label>
            {b.trabajo_cruzado && (
              <Input label="Empresas en el área" value={b.empresas_cruzadas}
                     onChange={(e) => actualizar((p) => ({ ...p, empresas_cruzadas: e.target.value }))} />
            )}
            <div>
              <label className="mb-1 block text-sm font-medium text-gray-700">Observación general</label>
              <textarea className="min-h-[60px] w-full rounded-lg border border-gray-300 px-2.5 py-1.5 text-sm"
                        value={b.observacion}
                        onChange={(e) => actualizar((p) => ({ ...p, observacion: e.target.value }))} />
            </div>
          </div>
        )}

        {/* ── Cuadrilla ── */}
        {paso === 1 && (
          <div className="space-y-2">
            <div className="rounded-xl border border-blue-200 bg-blue-50 p-3 text-[12px] text-blue-900">
              <p className="flex items-center gap-1 font-bold"><Users className="h-4 w-4" /> Marque quiénes trabajan en la tarea</p>
              Lo documental sale del control documental (estado al {new Date(b.habilitacion.generado_at).toLocaleString('es-CL')}).
              Quien no está habilitado no puede ejecutar: queda la desviación sola.
            </div>
            {grupoPersonas.map((h) => {
              const sel = b.personas.find((x) => x.personal_id === h.personal_id)
              const hab = sel?.es_conductor ? h.habilitado_conductor : h.habilitado
              const fallas = h.requisitos.filter((q) => !q.ok && (q.aplica_a === 'todos' || sel?.es_conductor))
              return (
                <div key={h.personal_id}
                     className={cn('rounded-xl border bg-white p-3',
                       sel ? (hab ? 'border-emerald-400' : 'border-red-400') : 'border-gray-200')}>
                  <button type="button" onClick={() => togglePersona(h.personal_id, h.nombre)}
                          className="flex w-full items-center gap-2 text-left">
                    <span className={cn('grid h-6 w-6 shrink-0 place-items-center rounded-md border-2',
                      sel ? 'border-gray-900 bg-gray-900 text-white' : 'border-gray-300')}>
                      {sel && <Check className="h-4 w-4" />}
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-sm font-semibold text-gray-900">{h.nombre}</span>
                      <span className="block text-[11px] text-gray-500">
                        {h.rut_provisorio ? 'RUT pendiente' : h.rut}{h.cargo ? ` · ${h.cargo}` : ''}
                      </span>
                    </span>
                    {sel && (hab
                      ? <span className="flex shrink-0 items-center gap-1 rounded-full bg-emerald-100 px-2 py-0.5 text-[11px] font-bold text-emerald-800"><UserCheck className="h-3 w-3" />Habilitado</span>
                      : <span className="flex shrink-0 items-center gap-1 rounded-full bg-red-600 px-2 py-0.5 text-[11px] font-bold text-white"><Ban className="h-3 w-3" />NO HABILITADO</span>)}
                  </button>
                  {sel && (
                    <div className="mt-2 pl-8">
                      <label className="flex items-center gap-2 text-sm">
                        <input type="checkbox" className="h-4 w-4" checked={sel.es_conductor}
                               onChange={(e) => setPersona(h.personal_id, { es_conductor: e.target.checked })} />
                        Conduce el vehículo al traslado
                      </label>
                      {fallas.length > 0 && (
                        <ul className="mt-1.5 space-y-0.5 rounded-lg bg-red-50 p-2 text-[11px] text-red-800">
                          {fallas.map((q) => (
                            <li key={q.tipo_codigo}>• {q.nombre}: <b>{ESTADO_REQ_LABEL[q.estado] ?? q.estado}</b></li>
                          ))}
                        </ul>
                      )}
                      {sel.es_conductor && (
                        <EncuestaFatiga f={sel.fatiga} onCambiar={(f) => setPersona(h.personal_id, { fatiga: f })} />
                      )}
                    </div>
                  )}
                </div>
              )
            })}
            {!grupoPersonas.length && (
              <p className="rounded-xl border border-dashed border-gray-300 bg-white p-6 text-center text-sm text-gray-500">
                No hay personal cargado en el control documental para este grupo.
              </p>
            )}
          </div>
        )}

        {/* ── Etapas ── */}
        {etapaIdx >= 0 && etapaIdx < etapas.length && (
          <div className="space-y-2">
            <p className="text-xs font-bold uppercase text-gray-500">
              Etapa {etapaIdx + 1} de {etapas.length} · {etapas[etapaIdx].nombre}
            </p>
            {etapas[etapaIdx].puntos.some((p) => p.posterior) && (
              <p className="rounded-lg bg-amber-50 px-3 py-2 text-[12px] text-amber-900">
                Se responde al volver a Calama. Puede enviar la inspección antes y completar esto después:
                queda «Falta cierre ART» hasta entonces.
              </p>
            )}
            {etapas[etapaIdx].puntos.map((p) => (
              <Punto key={p.codigo} b={b} p={p}
                     onCambiar={(patch) => setResp(p.codigo, patch)}
                     onFoto={(files) => agregarFotos(p.codigo, files)}
                     onQuitarFoto={(i) => quitarFoto(p.codigo, i)} />
            ))}
          </div>
        )}

        {/* ── Resumen ── */}
        {paso === ultimo && (
          <div className="space-y-3">
            <div className="grid grid-cols-4 gap-2 text-center">
              {[
                { n: av.cumple, l: 'Cumple', c: 'text-emerald-700' },
                { n: av.noCumple, l: 'No cumple', c: 'text-red-700' },
                { n: av.noAplica, l: 'No aplica', c: 'text-gray-600' },
                { n: av.pend, l: 'Pendientes', c: 'text-amber-700' },
              ].map((k) => (
                <div key={k.l} className="rounded-xl border border-gray-200 bg-white p-2">
                  <p className={cn('text-xl font-bold', k.c)}>{k.n}</p>
                  <p className="text-[10px] text-gray-500">{k.l}</p>
                </div>
              ))}
            </div>
            <div className="rounded-xl border border-gray-200 bg-white p-3 text-center">
              <p className="text-[11px] text-gray-500">Cumplimiento (cumple / evaluados)</p>
              <p className="text-3xl font-bold text-gray-900">{av.pct == null ? '—' : `${av.pct}%`}</p>
            </div>

            {(() => {
              const noHab = b.personas.filter((pl) => {
                const h = grupoPersonas.find((x) => x.personal_id === pl.personal_id)
                return h && !(pl.es_conductor ? h.habilitado_conductor : h.habilitado)
              })
              const noApto = b.personas.filter((pl) => pl.es_conductor && evaluarFatiga(pl.fatiga).resultado === 'no_apto')
              if (!noHab.length && !noApto.length) return null
              return (
                <div className="rounded-xl border-2 border-red-500 bg-red-50 p-3 text-sm text-red-900">
                  <p className="flex items-center gap-1 font-bold"><AlertTriangle className="h-4 w-4" /> Resultado CRÍTICO</p>
                  {noHab.map((x) => <p key={x.personal_id}>• {x.nombre}: no habilitado para ejecutar</p>)}
                  {noApto.map((x) => <p key={x.personal_id + 'f'}>• {x.nombre}: no apto para conducir</p>)}
                </div>
              )
            })()}

            {problemas.length > 0 && (
              <div className="rounded-xl border border-amber-300 bg-amber-50 p-3 text-[12px] text-amber-900">
                <p className="mb-1 font-bold">Antes de enviar:</p>
                {problemas.map((t) => <p key={t}>• {t}</p>)}
              </div>
            )}
            {av.pend > 0 && !problemas.length && (
              <p className="rounded-xl bg-gray-100 p-3 text-[12px] text-gray-700">
                Quedan {av.pend} punto{av.pend === 1 ? '' : 's'} sin responder. Puede enviar el avance y completar después.
              </p>
            )}
            {fotosSinEnviar > 0 && (
              <p className="flex items-center gap-1 text-[12px] text-amber-800">
                <CircleSlash className="h-3.5 w-3.5" /> {fotosSinEnviar} foto{fotosSinEnviar === 1 ? '' : 's'} solo en el teléfono.
              </p>
            )}
            {b.ultimo_envio && (
              <div className="rounded-xl border border-blue-200 bg-blue-50 p-3 text-[12px] text-blue-900">
                <p className="flex items-center gap-1 font-bold"><CheckCircle2 className="h-4 w-4" /> Último envío {new Date(b.ultimo_envio.at).toLocaleString('es-CL')}</p>
                Estado: {b.ultimo_envio.estado.replaceAll('_', ' ')} · Resultado: {b.ultimo_envio.resultado.replaceAll('_', ' ')}
                <span className="mt-1 block text-[11px] text-blue-800/80">
                  Ya cuenta en la reportabilidad del mes como «Inspección» (y «ART» si fotografió la ART):
                  no hay que cargarla de nuevo.
                </span>
              </div>
            )}
            {b.servidor_id && onPdf && (
              <Button variant="outline" className="w-full" onClick={() => onPdf(b.servidor_id!)}>
                <FileDown className="mr-2 h-4 w-4" /> Descargar informe PDF
              </Button>
            )}
          </div>
        )}
      </main>

      {/* Barra inferior: navegar y enviar */}
      <div className="fixed bottom-0 left-1/2 z-20 flex w-full max-w-[480px] -translate-x-1/2 gap-2 border-t border-gray-200 bg-white px-4 pb-[max(0.75rem,env(safe-area-inset-bottom))] pt-3">
        <Button variant="ghost" disabled={paso === 0} onClick={() => setPaso((p) => Math.max(0, p - 1))}>
          <ChevronLeft className="h-4 w-4" />
        </Button>
        {paso < ultimo ? (
          <Button className="flex-1" onClick={() => setPaso((p) => Math.min(ultimo, p + 1))}>
            Siguiente: {pasos[paso + 1]} <ChevronRight className="ml-1 h-4 w-4" />
          </Button>
        ) : (
          <Button className="flex-1" onClick={enviar} disabled={!!enviando}>
            {enviando ? <><Loader2 className="mr-2 h-4 w-4 animate-spin" />{enviando}</>
                      : <><CloudUpload className="mr-2 h-4 w-4" />{b.ultimo_envio ? 'Enviar de nuevo' : 'Enviar inspección'}</>}
          </Button>
        )}
      </div>
    </div>
  )
}

