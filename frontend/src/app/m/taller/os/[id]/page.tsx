'use client'

// [MIG508/509] La página de UNA Orden de Servicio en el teléfono — EJECUTABLE.
//
// Manuel (04-09): «al hacer clic para ejecutar, debe aparecer como checklist
// las actividades que me encomendaron, donde pueda colocar foto y comentario;
// además volver a pedir repuestos (pasa por el ciclo anterior) y hacer
// comentarios que el jefe vuelve a evaluar».
//
// Cada actividad es una NC, y su canal de ejecución es el ÍTEM del checklist
// del que nació: la foto y el comentario se escriben ahí (mismo canal offline
// de siempre), así se ven también en la OT y en la bandeja del jefe. El pedido
// de repuesto va amarrado al hallazgo y lo evalúa el jefe (ciclo MIG197/497).
// La nota general va a las notas de la OT, que el jefe puede convertir en NC.

import { useRef, useState } from 'react'
import Link from 'next/link'
import { useParams } from 'next/navigation'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  ArrowLeft, Play, Pause, CheckCircle2, Clock, CalendarDays, Users,
  ImageOff, ChevronRight, AlertTriangle, Camera, Package, StickyNote, Loader2, X, Check,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import {
  useNetworkStatus, useMarcarItem, useSolicitarRecurso, useAgregarNota,
} from '@/hooks/use-taller-mecanico'
import {
  getOSDetalle, getMisOS, getMiTecnicoId, iniciarOS, pausarOS, finalizarOS,
  ESTADO_OS_LABEL, type OSActividad,
} from '@/lib/services/taller-os'

const SEV_CLS: Record<string, string> = {
  critica: 'bg-red-100 text-red-700',
  alta: 'bg-orange-100 text-orange-700',
  media: 'bg-amber-100 text-amber-800',
  baja: 'bg-gray-100 text-gray-600',
}

function fechaLegible(f: string): { texto: string; atrasada: boolean } {
  const hoy = new Date(); hoy.setHours(0, 0, 0, 0)
  const d = new Date(`${f}T00:00:00`)
  const dias = Math.round((d.getTime() - hoy.getTime()) / 86_400_000)
  if (dias === 0) return { texto: 'HOY', atrasada: false }
  if (dias === 1) return { texto: 'mañana', atrasada: false }
  const txt = d.toLocaleDateString('es-CL', { weekday: 'long', day: '2-digit', month: '2-digit' })
  return { texto: txt, atrasada: dias < 0 }
}

// ── Una actividad, ejecutable: foto + comentario + pedir repuesto ───────────
function ActividadCard({ a, otId, onCambio }: {
  a: OSActividad
  otId: string
  onCambio: () => void
}) {
  const marcar = useMarcarItem(otId)
  const solicitar = useSolicitarRecurso(otId)
  const fotoRef = useRef<HTMLInputElement | null>(null)
  const [comentario, setComentario] = useState(a.observacion ?? '')
  const [pidiendo, setPidiendo] = useState(false)
  const [repDesc, setRepDesc] = useState('')
  const [repCant, setRepCant] = useState('')
  const [repFoto, setRepFoto] = useState<File | null>(null)
  const repFotoRef = useRef<HTMLInputElement | null>(null)

  const ejecutable = !!a.item_id && !!a.instance_id

  const guardarFotos = (files: File[]) => {
    if (!ejecutable || files.length === 0) return
    marcar.mutate(
      { instanceItemId: a.item_id!, instanceId: a.instance_id!, files },
      { onSuccess: onCambio },
    )
  }
  const guardarComentario = () => {
    if (!ejecutable || comentario === (a.observacion ?? '')) return
    marcar.mutate(
      { instanceItemId: a.item_id!, instanceId: a.instance_id!, observacion: comentario.trim() || null },
      { onSuccess: onCambio },
    )
  }
  const pedirRepuesto = () => {
    const n = Number(repCant)
    if (!n || n <= 0 || repDesc.trim().length < 3) return
    const nombre = typeof window !== 'undefined' ? localStorage.getItem('taller-mecanico') : null
    solicitar.mutate({
      productoId: null,
      descripcion: repDesc.trim(),
      cantidad: n,
      comentario: `Hallazgo: ${a.descripcion}`,
      solicitadoNombre: nombre,
      fotos: repFoto ? [repFoto] : undefined,
      instanceItemId: a.item_id ?? null,
    }, {
      onSuccess: () => { setPidiendo(false); setRepDesc(''); setRepCant(''); setRepFoto(null) },
    })
  }

  const fotos = a.fotos.length ? a.fotos : (a.foto_url ? [a.foto_url] : [])

  return (
    <div className={`rounded-xl border bg-white p-3 ${a.resuelto ? 'border-green-200' : 'border-gray-200'}`}>
      <div className="flex items-start gap-1.5">
        <p className="flex-1 text-sm text-gray-800">{a.descripcion}</p>
        {a.severidad && (
          <span className={`shrink-0 rounded-full px-1.5 py-0.5 text-[10px] font-medium ${SEV_CLS[a.severidad] ?? SEV_CLS.baja}`}>
            {a.severidad}
          </span>
        )}
        {a.resuelto && (
          <span className="flex shrink-0 items-center gap-0.5 rounded-full bg-green-100 px-1.5 py-0.5 text-[10px] font-medium text-green-700">
            <Check className="h-3 w-3" /> resuelta
          </span>
        )}
      </div>

      {/* La evidencia: la del hallazgo + lo que el mecánico va sumando */}
      {fotos.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-1.5">
          {fotos.map((u, i) => (
            // eslint-disable-next-line @next/next/no-img-element
            <img key={i} src={u} alt={`evidencia ${i + 1}`} loading="lazy"
                 onClick={() => window.open(u, '_blank')}
                 className="h-16 w-16 rounded-lg border object-cover" />
          ))}
        </div>
      )}
      {fotos.length === 0 && (
        <span className="mt-2 flex h-14 w-14 items-center justify-center rounded-lg border border-dashed border-gray-300 text-gray-300">
          <ImageOff className="h-5 w-5" />
        </span>
      )}

      {ejecutable ? (
        <>
          {/* Comentario + foto: el checklist de siempre, actividad por actividad */}
          <div className="mt-2 flex gap-2">
            <input type="text" value={comentario} onChange={(e) => setComentario(e.target.value)}
                   onBlur={guardarComentario} placeholder="Comentario de la ejecución…"
                   className="flex-1 rounded-lg border border-gray-200 px-3 py-2 text-sm" />
            <button type="button" onClick={() => fotoRef.current?.click()}
                    title="Agregar foto o video"
                    className="flex h-10 min-w-10 items-center justify-center rounded-lg border border-blue-300 bg-blue-50 px-2 text-blue-600">
              {marcar.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Camera className="h-4 w-4" />}
            </button>
            <input ref={fotoRef} type="file" accept="image/*,video/*" capture="environment" multiple
                   className="hidden"
                   onChange={(e) => { const fs = Array.from(e.target.files ?? []) as File[]; guardarFotos(fs); e.target.value = '' }} />
          </div>

          {/* Pedir repuesto: mismo ciclo de siempre — lo evalúa el jefe */}
          {pidiendo ? (
            <div className="mt-2 space-y-2 rounded-lg border border-orange-200 bg-orange-50/60 p-2">
              <input value={repDesc} onChange={(e) => setRepDesc(e.target.value)}
                     placeholder="¿Qué repuesto necesitas?"
                     className="w-full rounded-lg border border-gray-200 px-2.5 py-2 text-sm" />
              <div className="flex items-center gap-2">
                <input type="number" inputMode="decimal" min="0" value={repCant}
                       onChange={(e) => setRepCant(e.target.value)} placeholder="Cant."
                       className="w-20 rounded-lg border border-gray-200 px-2.5 py-2 text-sm" />
                <button type="button" onClick={() => repFotoRef.current?.click()}
                        className={`flex items-center gap-1 rounded-lg border px-2 py-2 text-[11px] font-medium ${
                          repFoto ? 'border-green-300 bg-green-50 text-green-700' : 'border-gray-300 text-gray-600'}`}>
                  <Camera className="h-3.5 w-3.5" /> {repFoto ? 'Foto lista' : 'Foto'}
                </button>
                <input ref={repFotoRef} type="file" accept="image/*" capture="environment" className="hidden"
                       onChange={(e) => { const f = e.target.files?.[0]; if (f) setRepFoto(f); e.target.value = '' }} />
                <button type="button" disabled={solicitar.isPending || !Number(repCant) || repDesc.trim().length < 3}
                        onClick={pedirRepuesto}
                        className="ml-auto rounded-lg bg-orange-600 px-3 py-2 text-[11px] font-semibold text-white disabled:opacity-50">
                  {solicitar.isPending ? 'Enviando…' : 'Pedir al jefe'}
                </button>
                <button type="button" onClick={() => setPidiendo(false)} className="text-gray-500">
                  <X className="h-4 w-4" />
                </button>
              </div>
              {solicitar.isError && (
                <p className="text-[11px] font-medium text-red-700">{(solicitar.error as Error).message}</p>
              )}
            </div>
          ) : (
            <button type="button" onClick={() => setPidiendo(true)}
                    className="mt-2 flex items-center gap-1 rounded-lg border border-orange-300 bg-orange-50 px-2 py-1.5 text-[11px] font-semibold text-orange-700">
              <Package className="h-3.5 w-3.5" /> Pedir repuesto (lo evalúa el jefe)
            </button>
          )}
        </>
      ) : (
        <p className="mt-2 rounded-lg bg-gray-50 px-2 py-1.5 text-[11px] text-gray-500">
          Esta NC no nació de un checklist: la foto y el comentario van en la nota al jefe (abajo).
        </p>
      )}
    </div>
  )
}

export default function OsDetallePage() {
  const params = useParams()
  const osId = params?.id as string
  const online = useNetworkStatus()
  const qc = useQueryClient()

  const { data: os, isLoading, error } = useQuery({
    queryKey: ['os-detalle', osId],
    queryFn: () => getOSDetalle(osId),
    enabled: !!osId,
    retry: false,
  })
  const { data: tecnicoId } = useQuery({
    queryKey: ['mi-tecnico'], queryFn: getMiTecnicoId, staleTime: 10 * 60_000, retry: false,
  })
  const { data: misOs = [] } = useQuery({
    queryKey: ['mis-os'], queryFn: getMisOS, enabled: !!tecnicoId,
    refetchInterval: online ? 60_000 : false, retry: false,
  })
  const mia = misOs.find((o) => o.os_id === osId)

  // Nota general al jefe (va a las notas de la OT: él la evalúa y puede
  // convertirla en NC — el «volver a evaluar» que pidió Manuel).
  const agregarNota = useAgregarNota(os?.ot_id ?? '')
  const [nota, setNota] = useState('')
  const [notaOk, setNotaOk] = useState(false)
  const guardarNota = () => {
    if (!nota.trim() || !os) return
    const nombre = typeof window !== 'undefined' ? localStorage.getItem('taller-mecanico') : null
    agregarNota.mutate({ texto: `[${os.folio}] ${nota.trim()}`, autor: nombre }, {
      onSuccess: () => { setNota(''); setNotaOk(true); setTimeout(() => setNotaOk(false), 4000) },
    })
  }

  const refrescar = () => {
    qc.invalidateQueries({ queryKey: ['os-detalle', osId] })
    qc.invalidateQueries({ queryKey: ['mis-os'] })
    qc.invalidateQueries({ queryKey: ['os-abiertas-taller'] })
  }
  const [terminando, setTerminando] = useState(false)
  const [obs, setObs] = useState('')
  const empezar = useMutation({ mutationFn: () => iniciarOS(osId, tecnicoId!), onSuccess: refrescar })
  const parar = useMutation({ mutationFn: () => pausarOS(osId, tecnicoId!), onSuccess: refrescar })
  const terminar = useMutation({
    mutationFn: () => finalizarOS(osId, obs.trim() || null),
    onSuccess: () => { setTerminando(false); setObs(''); refrescar() },
  })
  const accionError = empezar.error ?? parar.error ?? terminar.error

  if (isLoading) return <div className="flex justify-center py-16"><Spinner /></div>
  if (error || !os) {
    return (
      <div className="p-4 space-y-3">
        <Link href="/m/taller" className="inline-flex items-center gap-1 text-sm text-gray-500">
          <ArrowLeft className="h-4 w-4" /> Volver
        </Link>
        <p className="text-sm text-gray-500">No se pudo cargar la orden de servicio.</p>
      </div>
    )
  }

  const f = os.fecha_programada ? fechaLegible(os.fecha_programada) : null
  const pend = os.actividades.filter((a) => !a.resuelto).length

  return (
    <div className="p-3 space-y-3">
      <Link href="/m/taller" className="inline-flex items-center gap-1 text-sm text-gray-500">
        <ArrowLeft className="h-4 w-4" /> Taller
      </Link>

      {/* Cabecera — la misma lógica de la OT: qué equipo, qué día, cuánto */}
      <div className="rounded-xl border border-gray-200 bg-white p-3">
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="rounded bg-gray-100 px-1.5 py-0.5 font-mono text-xs font-bold text-gray-700">{os.folio}</span>
          <span className="text-base font-bold text-gray-900">{os.patente ?? '—'}</span>
          <span className="rounded-full bg-gray-100 px-2 py-0.5 text-[10px] font-medium text-gray-600">
            {ESTADO_OS_LABEL[os.estado] ?? os.estado}
          </span>
          {os.es_externo && (
            <span className="rounded-full bg-indigo-100 px-2 py-0.5 text-[10px] font-medium text-indigo-700">externo</span>
          )}
        </div>
        <p className="mt-1 text-sm font-medium text-gray-800">{os.titulo}</p>
        {os.equipo && <p className="text-xs text-gray-500">{os.equipo}</p>}
        <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px] text-gray-600">
          {f && (
            <span className={`flex items-center gap-1 font-semibold ${f.atrasada ? 'text-red-600' : 'text-orange-700'}`}>
              <CalendarDays className="h-3.5 w-3.5" /> {f.atrasada ? `programada para el ${f.texto} (atrasada)` : `programada para ${f.texto}`}
            </span>
          )}
          {os.horas_estimadas != null && (
            <span className="flex items-center gap-1"><Clock className="h-3.5 w-3.5" /> {os.horas_estimadas} h asignadas</span>
          )}
          {os.asignados.length > 0 && (
            <span className="flex items-center gap-1"><Users className="h-3.5 w-3.5" /> {os.asignados.join(' y ')}</span>
          )}
        </div>
      </div>

      {/* Reloj — solo si la OS es mía (el tiempo que se mide es el que se reparte) */}
      {os.mi_asignada && tecnicoId && (
        terminando ? (
          <div className="rounded-xl border border-gray-200 bg-white p-3">
            <label className="text-[11px] font-medium text-gray-700">¿Qué hiciste? (opcional)</label>
            <textarea rows={2} value={obs} onChange={(e) => setObs(e.target.value)}
                      placeholder="Lo que quede acá lo lee el jefe de taller"
                      className="mt-1 w-full rounded border border-gray-300 px-2 py-1.5 text-sm" />
            <div className="mt-2 flex gap-2">
              <button onClick={() => terminar.mutate()} disabled={terminar.isPending || !online}
                      className="flex-1 rounded-md bg-green-600 px-3 py-2 text-sm font-semibold text-white disabled:opacity-50">
                Confirmar que terminé
              </button>
              <button onClick={() => setTerminando(false)}
                      className="rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-700">Volver</button>
            </div>
          </div>
        ) : (
          <div className="flex gap-2">
            {mia?.trabajando ? (
              <button onClick={() => parar.mutate()} disabled={parar.isPending || !online}
                      className="flex flex-1 items-center justify-center gap-1.5 rounded-xl border border-orange-300 bg-white py-3 text-sm font-semibold text-orange-700 disabled:opacity-50">
                <Pause className="h-4 w-4" /> Parar
              </button>
            ) : (
              <button onClick={() => empezar.mutate()} disabled={empezar.isPending || !!mia?.bloqueo || !online}
                      className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-orange-600 py-3 text-sm font-semibold text-white disabled:opacity-50">
                <Play className="h-4 w-4" /> Empezar
              </button>
            )}
            <button onClick={() => setTerminando(true)} disabled={!online}
                    className="flex flex-1 items-center justify-center gap-1.5 rounded-xl border border-green-300 bg-white py-3 text-sm font-semibold text-green-700 disabled:opacity-50">
              <CheckCircle2 className="h-4 w-4" /> Terminé
            </button>
          </div>
        )
      )}
      {os.mi_asignada && mia?.bloqueo && (
        <p className="flex items-start gap-1.5 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
          <AlertTriangle className="mt-px h-3.5 w-3.5 shrink-0" /> {mia.bloqueo}
        </p>
      )}
      {accionError && (
        <p className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs font-medium text-red-700">
          {(accionError as Error).message}
        </p>
      )}

      {/* Actividades — el checklist de la OS: foto, comentario y repuestos */}
      <div className="flex items-baseline justify-between pt-1">
        <h2 className="text-sm font-bold text-gray-900">Actividades</h2>
        <span className="text-[11px] text-gray-500">
          {os.actividades.length === 0 ? 'sin actividades ligadas'
            : pend === 0 ? `${os.actividades.length} — todas resueltas`
            : `${pend} pendiente${pend > 1 ? 's' : ''} de ${os.actividades.length}`}
        </span>
      </div>

      {os.actividades.length === 0 && (
        <p className="rounded-lg border border-dashed border-gray-300 bg-white px-3 py-3 text-center text-xs text-gray-500">
          Esta OS no tiene no conformidades ligadas: el detalle del trabajo está en el checklist de la OT.
        </p>
      )}

      {os.actividades.map((a) => (
        <ActividadCard key={a.nc_id} a={a} otId={os.ot_id}
                       onCambio={() => qc.invalidateQueries({ queryKey: ['os-detalle', osId] })} />
      ))}

      {/* Nota general al jefe: la evalúa y puede convertirla en NC */}
      <div className="rounded-xl border border-gray-200 bg-white p-3">
        <p className="flex items-center gap-1.5 text-sm font-semibold text-gray-800">
          <StickyNote className="h-4 w-4 text-blue-600" /> Comentario al jefe de taller
        </p>
        <textarea rows={2} value={nota} onChange={(e) => setNota(e.target.value)}
                  placeholder="Algo que el jefe deba evaluar de este trabajo (lo ve en la bandeja y puede convertirlo en NC)…"
                  className="mt-1.5 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm" maxLength={1000} />
        <div className="mt-1.5 flex items-center gap-2">
          {notaOk && <span className="text-[11px] font-medium text-green-700">Nota enviada al jefe ✓</span>}
          <button type="button" onClick={guardarNota} disabled={!nota.trim() || agregarNota.isPending}
                  className="ml-auto rounded-lg bg-blue-600 px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-50">
            {agregarNota.isPending ? 'Enviando…' : 'Enviar al jefe'}
          </button>
        </div>
      </div>

      {/* La ejecución fina del resto del equipo vive en la OT */}
      <Link href={`/m/taller/ot/${os.ot_id}`}
            className="flex items-center justify-between rounded-xl border border-blue-200 bg-blue-50 px-3 py-3 active:bg-blue-100">
        <span className="text-sm font-semibold text-blue-800">
          Abrir el checklist completo de la OT {os.ot_folio}
        </span>
        <ChevronRight className="h-4 w-4 text-blue-600" />
      </Link>
    </div>
  )
}
