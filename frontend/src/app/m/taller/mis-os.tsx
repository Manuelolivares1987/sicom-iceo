'use client'

/**
 * [MIG479 · Fase 3] Mi trabajo — las órdenes de servicio que me tocan.
 *
 * Esto es lo que faltaba del circuito: la OT es la revisión del equipo, de ahí
 * salen las no conformidades, y cada grupo de NC se trabaja en una OS. El jefe
 * de taller reparte; acá el mecánico ve SÓLO lo suyo y mueve el reloj.
 *
 * Dos reglas que se ven en el código y conviene no perder:
 *
 *  · Nadie se asigna trabajo solo. Esta pantalla no tiene «tomar esta OS»: lee
 *    lo que el jefe repartió. Si no hay nada, no hay nada.
 *
 *  · El reloj es por persona. Las horas que muestra cada tarjeta son las MÍAS,
 *    no las de la OS: si el turno anterior dejó 6 h puestas, esas no son mías y
 *    no me pagan a mí.
 *
 * La cuenta compartida no ve nada de esto (no resuelve técnico), y sigue
 * funcionando como antes. Es a propósito: el tiempo medido sólo sirve si se
 * puede atribuir.
 */

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Play, Pause, CheckCircle2, ChevronRight, ChevronDown, Clock, AlertTriangle, WifiOff, CalendarDays } from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import {
  getMisOS, getMiTecnicoId, getOSAbiertas, iniciarOS, pausarOS, finalizarOS,
  type MiOS, ESTADO_OS_LABEL,
} from '@/lib/services/taller-os'

/** Horas decimales a lo que se lee en un teléfono: «2 h 15 min». */
function horasLegibles(h: number): string {
  const total = Math.max(0, Math.round(h * 60))
  const hh = Math.floor(total / 60)
  const mm = total % 60
  if (hh === 0) return `${mm} min`
  if (mm === 0) return `${hh} h`
  return `${hh} h ${mm} min`
}

/** [MIG507] La fecha programada, dicha como se habla: hoy / mañana / vie 05-09. */
function fechaLegible(f: string): { texto: string; atrasada: boolean; esHoy: boolean } {
  const hoy = new Date(); hoy.setHours(0, 0, 0, 0)
  const d = new Date(`${f}T00:00:00`)
  const dias = Math.round((d.getTime() - hoy.getTime()) / 86_400_000)
  if (dias === 0) return { texto: 'programada para HOY', atrasada: false, esHoy: true }
  if (dias === 1) return { texto: 'programada para mañana', atrasada: false, esHoy: false }
  const txt = d.toLocaleDateString('es-CL', { weekday: 'short', day: '2-digit', month: '2-digit' })
  if (dias < 0) return { texto: `programada para el ${txt} (atrasada)`, atrasada: true, esHoy: false }
  return { texto: `programada para el ${txt}`, atrasada: false, esHoy: false }
}

export function MisOrdenesDeServicio({ online }: { online: boolean }) {
  const qc = useQueryClient()
  const [terminando, setTerminando] = useState<string | null>(null)
  const [observacion, setObservacion] = useState('')

  const { data: tecnicoId } = useQuery({
    queryKey: ['mi-tecnico'],
    queryFn: getMiTecnicoId,
    staleTime: 10 * 60_000,
    retry: false,
  })

  const { data: oss = [], isLoading } = useQuery({
    queryKey: ['mis-os'],
    queryFn: getMisOS,
    enabled: !!tecnicoId,
    // El reloj corre en el servidor: refrescar cada minuto mantiene el contador
    // honesto sin inventar el tiempo en el teléfono.
    refetchInterval: online ? 60_000 : false,
    retry: false,
  })

  // Un tick local para que el minutero de la OS que está andando no se quede
  // congelado entre refrescos.
  const [, setTick] = useState(0)
  useEffect(() => {
    if (!oss.some((o) => o.trabajando)) return
    const t = setInterval(() => setTick((n) => n + 1), 30_000)
    return () => clearInterval(t)
  }, [oss])

  const refrescar = () => {
    qc.invalidateQueries({ queryKey: ['mis-os'] })
    qc.invalidateQueries({ queryKey: ['taller-mecanico-ots'] })
  }

  const empezar = useMutation({
    mutationFn: (osId: string) => iniciarOS(osId, tecnicoId!),
    onSuccess: refrescar,
  })
  const parar = useMutation({
    mutationFn: (osId: string) => pausarOS(osId, tecnicoId!),
    onSuccess: refrescar,
  })
  const terminar = useMutation({
    mutationFn: (p: { osId: string; obs: string }) => finalizarOS(p.osId, p.obs || null),
    onSuccess: () => { setTerminando(null); setObservacion(''); refrescar() },
  })

  const error = empezar.error ?? parar.error ?? terminar.error

  // Cuenta compartida o cuenta sin técnico vinculado: la pantalla de siempre.
  if (!tecnicoId) return null

  return (
    <section className="space-y-2">
      <div className="flex items-baseline justify-between">
        <h2 className="text-sm font-bold text-gray-900">Mi trabajo</h2>
        <span className="text-[11px] text-gray-500">
          {oss.length === 0 ? 'nada asignado' : `${oss.length} orden${oss.length === 1 ? '' : 'es'} de servicio`}
        </span>
      </div>

      {isLoading && (
        <div className="flex justify-center py-4"><Spinner className="h-5 w-5" /></div>
      )}

      {!isLoading && oss.length === 0 && (
        <p className="rounded-lg border border-dashed border-gray-300 bg-white px-3 py-3 text-center text-xs text-gray-500">
          El jefe de taller todavía no te asigna una orden de servicio.
        </p>
      )}

      {error && (
        <p className="rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-xs text-red-800">
          {(error as Error).message}
        </p>
      )}

      {!online && oss.length > 0 && (
        <p className="flex items-center gap-1.5 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
          <WifiOff className="h-4 w-4 shrink-0" />
          Sin señal el reloj no se puede marcar. Avísale al jefe de taller la hora real de partida.
        </p>
      )}

      {oss.map((os) => (
        <TarjetaOS
          key={os.os_id}
          os={os}
          online={online}
          ocupado={empezar.isPending || parar.isPending || terminar.isPending}
          terminando={terminando === os.os_id}
          observacion={observacion}
          onObservacion={setObservacion}
          onEmpezar={() => empezar.mutate(os.os_id)}
          onParar={() => parar.mutate(os.os_id)}
          onPedirTerminar={() => { setTerminando(os.os_id); setObservacion('') }}
          onCancelarTerminar={() => setTerminando(null)}
          onTerminar={() => terminar.mutate({ osId: os.os_id, obs: observacion })}
        />
      ))}
    </section>
  )
}

function TarjetaOS(p: {
  os: MiOS
  online: boolean
  ocupado: boolean
  terminando: boolean
  observacion: string
  onObservacion: (v: string) => void
  onEmpezar: () => void
  onParar: () => void
  onPedirTerminar: () => void
  onCancelarTerminar: () => void
  onTerminar: () => void
}) {
  const { os } = p
  const bloqueado = !!os.bloqueo

  return (
    <div className={`rounded-lg border bg-white p-3 ${
      os.trabajando ? 'border-amber-400 ring-1 ring-amber-200' : 'border-gray-200'}`}>
      <div className="flex items-start gap-2">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="rounded bg-gray-100 px-1.5 py-0.5 font-mono text-[11px] text-gray-700">
              {os.folio}
            </span>
            <span className="text-sm font-bold text-gray-900">{os.patente}</span>
            {os.trabajando && (
              <span className="flex items-center gap-1 rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-medium text-amber-800">
                <Play className="h-3 w-3" /> andando
              </span>
            )}
          </div>
          <p className="mt-0.5 text-sm text-gray-800">{os.titulo}</p>
          {/* [MIG507] El día que el jefe programó: lo primero que decide qué hago hoy. */}
          {os.fecha_programada && (() => {
            const f = fechaLegible(os.fecha_programada)
            return (
              <p className={`mt-0.5 flex items-center gap-1 text-[11px] font-semibold ${
                f.atrasada ? 'text-red-600' : f.esHoy ? 'text-orange-700' : 'text-gray-600'}`}>
                <CalendarDays className="h-3 w-3" /> {f.texto}
              </p>
            )
          })()}
          <p className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[11px] text-gray-500">
            {os.ncs > 0 && <span>{os.ncs} no conformidad{os.ncs === 1 ? '' : 'es'}</span>}
            <span className="flex items-center gap-1">
              <Clock className="h-3 w-3" /> llevo {horasLegibles(os.mis_horas)}
              {os.horas_estimadas ? ` · asignado ${os.horas_estimadas} h` : ''}
            </span>
          </p>
          {/* [MIG498] El trabajo viene CON tiempo: el mecánico lo ve correr
              contra lo asignado, y se da cuenta solo cuando se está pasando. */}
          {os.horas_estimadas != null && os.horas_estimadas > 0 && (() => {
            const frac = os.mis_horas / os.horas_estimadas
            const pasado = frac > 1
            return (
              <div className="mt-1.5">
                <div className="h-1.5 w-full rounded-full bg-gray-100">
                  <div className={`h-1.5 rounded-full ${pasado ? 'bg-red-500' : frac > 0.8 ? 'bg-amber-500' : 'bg-green-500'}`}
                       style={{ width: `${Math.min(100, Math.round(frac * 100))}%` }} />
                </div>
                {pasado && (
                  <p className="mt-0.5 text-[11px] font-semibold text-red-600">
                    Te pasaste del tiempo asignado por {horasLegibles(os.mis_horas - os.horas_estimadas)}.
                    Avísale al jefe de taller.
                  </p>
                )}
              </div>
            )
          })()}
        </div>
        {/* [MIG508] Abre el detalle de la OS (sus actividades); desde ahí se
            llega al checklist completo de la OT. */}
        <Link href={`/m/taller/os/${os.os_id}`} aria-label="Ver las actividades de la OS"
              className="shrink-0 rounded-md border border-gray-200 p-1.5 text-gray-400 active:bg-gray-50">
          <ChevronRight className="h-4 w-4" />
        </Link>
      </div>

      {bloqueado && (
        <p className="mt-2 flex items-start gap-1.5 rounded border border-amber-300 bg-amber-50 px-2 py-1.5 text-[11px] text-amber-900">
          <AlertTriangle className="mt-px h-3.5 w-3.5 shrink-0" />
          {os.bloqueo}
        </p>
      )}

      {p.terminando ? (
        <div className="mt-2 rounded border border-gray-200 bg-gray-50 p-2">
          <label className="text-[11px] font-medium text-gray-700">¿Qué hiciste? (opcional)</label>
          <textarea rows={2} value={p.observacion} onChange={(e) => p.onObservacion(e.target.value)}
                    placeholder="Lo que quede acá lo lee el jefe de taller al revisar"
                    className="mt-1 w-full rounded border border-gray-300 px-2 py-1.5 text-sm" />
          <div className="mt-2 flex gap-2">
            <button onClick={p.onTerminar} disabled={p.ocupado || !p.online}
                    className="flex-1 rounded-md bg-green-600 px-3 py-2 text-sm font-semibold text-white disabled:opacity-50">
              Confirmar que terminé
            </button>
            <button onClick={p.onCancelarTerminar}
                    className="rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-700">
              Volver
            </button>
          </div>
        </div>
      ) : (
        <div className="mt-2 flex gap-2">
          {os.trabajando ? (
            <button onClick={p.onParar} disabled={p.ocupado || !p.online}
                    className="flex flex-1 items-center justify-center gap-1.5 rounded-md border border-orange-300 bg-white px-3 py-2 text-sm font-semibold text-orange-700 disabled:opacity-50">
              <Pause className="h-4 w-4" /> Parar
            </button>
          ) : (
            <button onClick={p.onEmpezar} disabled={p.ocupado || bloqueado || !p.online}
                    className="flex flex-1 items-center justify-center gap-1.5 rounded-md bg-orange-600 px-3 py-2 text-sm font-semibold text-white disabled:opacity-50">
              <Play className="h-4 w-4" /> Empezar
            </button>
          )}
          <button onClick={p.onPedirTerminar} disabled={p.ocupado || !p.online}
                  className="flex items-center justify-center gap-1.5 rounded-md border border-green-300 bg-white px-3 py-2 text-sm font-semibold text-green-700 disabled:opacity-50">
            <CheckCircle2 className="h-4 w-4" /> Terminé
          </button>
        </div>
      )}
    </div>
  )
}

// ── [MIG507] Todas las OS del taller, de solo lectura ───────────────────────
// «El operador no puede ver la orden de servicio»: podía, pero solo la suya y
// solo con cuenta vinculada — la cuenta compartida del teléfono del taller no
// veía nada. Ver el trabajo repartido no es personal; mover el reloj sí.
export function OsDelTaller() {
  // Abierta por defecto: la razón de existir de esta lista es que se VEA
  // (Manuel, 03-09: «no puedo ver la orden de servicio planificada»).
  const [abierto, setAbierto] = useState(true)
  const { data: oss = [], isLoading } = useQuery({
    queryKey: ['os-abiertas-taller'],
    queryFn: getOSAbiertas,
    staleTime: 60_000,
    retry: false,
  })

  if (!isLoading && oss.length === 0) return null

  return (
    <section className="space-y-2">
      <button type="button" onClick={() => setAbierto((v) => !v)}
              className="flex w-full items-center gap-1.5 rounded-lg bg-gray-100 px-3 py-2 text-left active:bg-gray-200">
        <ChevronDown className={`h-4 w-4 shrink-0 text-gray-500 transition-transform ${abierto ? '' : '-rotate-90'}`} />
        <span className="text-sm font-bold text-gray-900">Órdenes de servicio del taller</span>
        <span className="ml-auto text-[11px] text-gray-500">
          {oss.length} abierta{oss.length === 1 ? '' : 's'}
        </span>
      </button>

      {abierto && oss.map((os) => {
        const f = os.fecha_programada ? fechaLegible(os.fecha_programada) : null
        return (
          // [MIG508] La tarjeta se ABRE, como una OT: adentro están las actividades.
          <Link key={os.os_id} href={`/m/taller/os/${os.os_id}`}
                className="block rounded-lg border border-gray-200 bg-white p-3 active:bg-gray-50">
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="rounded bg-gray-100 px-1.5 py-0.5 font-mono text-[11px] text-gray-700">{os.folio}</span>
              <span className="text-sm font-bold text-gray-900">{os.patente ?? '—'}</span>
              <span className="rounded-full bg-gray-100 px-2 py-0.5 text-[10px] font-medium text-gray-600">
                {ESTADO_OS_LABEL[os.estado] ?? os.estado}
              </span>
              {os.es_externo && (
                <span className="rounded-full bg-indigo-100 px-2 py-0.5 text-[10px] font-medium text-indigo-700">externo</span>
              )}
            </div>
            <p className="mt-0.5 text-sm text-gray-800">{os.titulo}</p>
            <p className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[11px] text-gray-500">
              {os.responsable && <span>asignada a <b className="text-gray-700">{os.responsable}</b></span>}
              {f && (
                <span className={`flex items-center gap-1 font-semibold ${
                  f.atrasada ? 'text-red-600' : f.esHoy ? 'text-orange-700' : 'text-gray-600'}`}>
                  <CalendarDays className="h-3 w-3" /> {f.texto}
                </span>
              )}
              {os.horas_estimadas ? <span>· {os.horas_estimadas} h</span> : null}
              {os.ncs > 0 && <span>· {os.ncs} NC</span>}
              <span className="ml-auto flex items-center gap-0.5 font-semibold text-blue-600">
                ver actividades <ChevronRight className="h-3 w-3" />
              </span>
            </p>
          </Link>
        )
      })}
      {abierto && (
        <p className="text-[10px] text-gray-400">
          Para mover el reloj de una OS entra con tu propia cuenta: el tiempo que se mide es el que se reparte.
        </p>
      )}
    </section>
  )
}
