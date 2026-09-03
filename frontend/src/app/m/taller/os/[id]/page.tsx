'use client'

// [MIG508] La página de UNA Orden de Servicio en el teléfono.
//
// Manuel: «necesito que sea igual que cuando revisa las actividades el
// operador cuando se planifica OT — hoy no sale nada». La OS se abre como una
// OT: cabecera con el equipo y el día, y abajo las ACTIVIDADES — las no
// conformidades que resuelve, cada una con su foto y observación.
//
// El reloj (empezar/parar/terminé) aparece solo si la OS es del técnico que
// abrió sesión; el resto la ve completa igual (regla MIG507).

import { useState } from 'react'
import Link from 'next/link'
import { useParams } from 'next/navigation'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  ArrowLeft, Play, Pause, CheckCircle2, Clock, CalendarDays, Users,
  ImageOff, ChevronRight, AlertTriangle,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useNetworkStatus } from '@/hooks/use-taller-mecanico'
import {
  getOSDetalle, getMisOS, getMiTecnicoId, iniciarOS, pausarOS, finalizarOS,
  ESTADO_OS_LABEL,
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
  // El estado del reloj (trabajando / mis horas) sale de mis OS.
  const { data: misOs = [] } = useQuery({
    queryKey: ['mis-os'], queryFn: getMisOS, enabled: !!tecnicoId,
    refetchInterval: online ? 60_000 : false, retry: false,
  })
  const mia = misOs.find((o) => o.os_id === osId)

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

      {/* Actividades — lo que esta OS resuelve, con la evidencia a la vista */}
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
        <div key={a.nc_id} className={`rounded-xl border bg-white p-3 ${a.resuelto ? 'border-green-200 opacity-70' : 'border-gray-200'}`}>
          <div className="flex gap-2.5">
            {a.foto_url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={a.foto_url} alt="Evidencia" loading="lazy"
                   onClick={() => window.open(a.foto_url!, '_blank')}
                   className="h-16 w-16 shrink-0 rounded-lg border object-cover" />
            ) : (
              <span className="flex h-16 w-16 shrink-0 items-center justify-center rounded-lg border border-dashed border-gray-300 text-gray-300">
                <ImageOff className="h-5 w-5" />
              </span>
            )}
            <div className="min-w-0 flex-1">
              <p className="text-sm text-gray-800">{a.descripcion}</p>
              {a.observacion && <p className="mt-0.5 text-[11px] text-gray-600">«{a.observacion}»</p>}
              <div className="mt-1 flex flex-wrap items-center gap-1">
                {a.severidad && (
                  <span className={`rounded-full px-1.5 py-0.5 text-[10px] font-medium ${SEV_CLS[a.severidad] ?? SEV_CLS.baja}`}>
                    {a.severidad}
                  </span>
                )}
                {a.resuelto && (
                  <span className="flex items-center gap-0.5 rounded-full bg-green-100 px-1.5 py-0.5 text-[10px] font-medium text-green-700">
                    <CheckCircle2 className="h-3 w-3" /> resuelta
                  </span>
                )}
              </div>
            </div>
          </div>
        </div>
      ))}

      {/* La ejecución fina (marcar ítems, fotos, repuestos) vive en la OT */}
      <Link href={`/m/taller/ot/${os.ot_id}`}
            className="flex items-center justify-between rounded-xl border border-blue-200 bg-blue-50 px-3 py-3 active:bg-blue-100">
        <span className="text-sm font-semibold text-blue-800">
          Abrir el checklist de la OT {os.ot_folio}
        </span>
        <ChevronRight className="h-4 w-4 text-blue-600" />
      </Link>
      <p className="text-[10px] text-gray-400">
        Ahí se marcan las tareas, se suben las fotos y se piden los repuestos — igual que siempre.
      </p>
    </div>
  )
}
