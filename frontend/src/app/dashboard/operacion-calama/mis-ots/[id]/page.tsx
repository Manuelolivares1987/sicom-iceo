'use client'

import { useEffect, useState } from 'react'
import { useParams } from 'next/navigation'
import Link from 'next/link'
import {
  ArrowLeft, Play, Pause, RotateCcw, CheckCircle2, AlertTriangle,
  Clock, Calendar, MapPin, Coffee, Wrench,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { Button } from '@/components/ui/button'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useCalamaOT, useCalamaSubtareas } from '@/hooks/use-calama'
import {
  useEjecucionActivaPorOT, useIniciarEjecucion, usePausarEjecucion,
  useReanudarEjecucion, useFinalizarEjecucion,
} from '@/hooks/use-calama-plan-semanal'
import { excelCodigoFromFolio, zonaCodeFromFolio } from '@/lib/services/calama'
import { EstadoBadge } from '@/components/calama/gantt-table'

export default function MiOTDetallePage() {
  useRequireAuth()
  const { id } = useParams<{ id: string }>()
  const otId = id as string | undefined

  const { data: ot, isLoading } = useCalamaOT(otId)
  const { data: subtareas } = useCalamaSubtareas(otId)
  const { data: ejecucion } = useEjecucionActivaPorOT(otId)

  const iniciar = useIniciarEjecucion()
  const pausar = usePausarEjecucion()
  const reanudar = useReanudarEjecucion()
  const finalizar = useFinalizarEjecucion()

  const [errorMsg, setErrorMsg] = useState<string | null>(null)
  const [tickElapsed, setTickElapsed] = useState(0)
  const [avance, setAvance] = useState(100)
  const [obsCierre, setObsCierre] = useState('')

  // Tick para mostrar tiempo en vivo
  useEffect(() => {
    if (!ejecucion || ejecucion.estado !== 'en_ejecucion') return
    const t = setInterval(() => setTickElapsed((n) => n + 1), 1000)
    return () => clearInterval(t)
  }, [ejecucion])

  useEffect(() => { setTickElapsed(0) }, [ejecucion?.last_event_at])

  if (isLoading) {
    return <div className="flex items-center gap-2 text-sm text-gray-500"><Spinner className="h-4 w-4" /> Cargando…</div>
  }
  if (!ot) {
    return <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">OT no encontrada.</div>
  }

  const codigo = excelCodigoFromFolio(ot.folio)
  const zona = zonaCodeFromFolio(ot.folio)

  const handleIniciar = async () => {
    setErrorMsg(null)
    try { await iniciar.mutateAsync(ot.id) } catch (e) { setErrorMsg(e instanceof Error ? e.message : 'Error') }
  }
  const handlePausar = async (motivo = 'pausa') => {
    if (!ejecucion) return
    setErrorMsg(null)
    try { await pausar.mutateAsync({ ejecucionId: ejecucion.id, motivo, otId: ot.id }) } catch (e) { setErrorMsg(e instanceof Error ? e.message : 'Error') }
  }
  const handleReanudar = async () => {
    if (!ejecucion) return
    setErrorMsg(null)
    try { await reanudar.mutateAsync({ ejecucionId: ejecucion.id, otId: ot.id }) } catch (e) { setErrorMsg(e instanceof Error ? e.message : 'Error') }
  }
  const handleFinalizar = async () => {
    if (!ejecucion) return
    setErrorMsg(null)
    try { await finalizar.mutateAsync({ ejecucionId: ejecucion.id, otId: ot.id, avance, observacion: obsCierre || undefined }) } catch (e) { setErrorMsg(e instanceof Error ? e.message : 'Error') }
  }

  const tiempoEfectivoActual = (ejecucion?.tiempo_efectivo_segundos ?? 0)
    + (ejecucion?.estado === 'en_ejecucion' ? tickElapsed : 0)
  const tiempoPausadoActual = (ejecucion?.tiempo_pausado_segundos ?? 0)
    + (ejecucion?.estado === 'pausada' ? tickElapsed : 0)

  return (
    <div className="space-y-4 max-w-2xl mx-auto">
      <Link href="/dashboard/operacion-calama/mis-ots" className="inline-flex items-center gap-1 text-sm text-gray-500">
        <ArrowLeft className="h-4 w-4" /> Mis OTs
      </Link>

      <div className="rounded-2xl bg-gradient-to-r from-amber-700 to-orange-600 p-4 sm:p-6 text-white shadow-lg">
        <div className="flex items-start justify-between gap-2">
          <div>
            <h1 className="text-lg sm:text-xl font-bold line-clamp-2">{ot.titulo}</h1>
            <p className="text-xs text-white/90 mt-1 font-mono">{ot.folio}</p>
          </div>
          <EstadoBadge estado={ot.estado} />
        </div>
      </div>

      <Card>
        <CardContent className="p-3 grid grid-cols-2 sm:grid-cols-4 gap-2 text-xs">
          <Info icon={<MapPin className="h-3 w-3" />} label="Zona" value={zona ?? '—'} mono />
          <Info icon={<Calendar className="h-3 w-3" />} label="Programada" value={ot.fecha_programada} />
          <Info label="Cod. Excel" value={codigo ?? '—'} mono />
          <Info label="Avance" value={`${ot.avance_pct.toFixed(0)}%`} />
        </CardContent>
      </Card>

      {/* PLAY / PAUSA / FINALIZAR */}
      <Card className={ejecucion ? 'border-amber-300' : ''}>
        <CardHeader className="pb-2">
          <CardTitle className="text-base flex items-center gap-2">
            <Wrench className="h-4 w-4" />
            Ejecucion
            {ejecucion && (
              <span className={`ml-auto text-xs rounded-full px-2 py-0.5 ${
                ejecucion.estado === 'en_ejecucion' ? 'bg-green-100 text-green-700'
                : ejecucion.estado === 'pausada' ? 'bg-amber-100 text-amber-700'
                : 'bg-gray-100 text-gray-700'
              }`}>{ejecucion.estado}</span>
            )}
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          {ejecucion ? (
            <>
              <div className="grid grid-cols-3 gap-2 text-xs">
                <Tiempo label="Efectivo" segundos={tiempoEfectivoActual} highlight={ejecucion.estado === 'en_ejecucion'} />
                <Tiempo label="Pausado" segundos={tiempoPausadoActual} highlight={ejecucion.estado === 'pausada'} />
                <Tiempo label="Colacion" segundos={ejecucion.tiempo_colacion_segundos} />
              </div>

              {ejecucion.estado === 'en_ejecucion' && (
                <div className="grid grid-cols-2 gap-2">
                  <Button variant="secondary" onClick={() => handlePausar('pausa')} loading={pausar.isPending}>
                    <Pause className="h-4 w-4" /> Pausar
                  </Button>
                  <Button variant="secondary" onClick={() => handlePausar('colacion')} loading={pausar.isPending}>
                    <Coffee className="h-4 w-4" /> Colacion
                  </Button>
                </div>
              )}
              {ejecucion.estado === 'pausada' && (
                <Button variant="primary" onClick={handleReanudar} loading={reanudar.isPending} className="w-full">
                  <RotateCcw className="h-4 w-4" /> Reanudar
                </Button>
              )}
              {ejecucion.estado !== 'finalizada' && ejecucion.estado !== 'cancelada' && (
                <div className="space-y-2 pt-2 border-t">
                  <div>
                    <label className="text-xs text-gray-500">Avance final %</label>
                    <input
                      type="number" min={0} max={100}
                      value={avance}
                      onChange={(e) => setAvance(Math.min(100, Math.max(0, Number(e.target.value))))}
                      className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
                    />
                  </div>
                  <div>
                    <label className="text-xs text-gray-500">Observacion de cierre (opcional)</label>
                    <textarea
                      value={obsCierre}
                      onChange={(e) => setObsCierre(e.target.value)}
                      rows={2}
                      className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
                    />
                  </div>
                  <Button
                    variant="primary"
                    onClick={() => { if (confirm('¿Finalizar la ejecucion?')) handleFinalizar() }}
                    loading={finalizar.isPending}
                    className="w-full"
                  >
                    <CheckCircle2 className="h-4 w-4" /> Finalizar OT
                  </Button>
                </div>
              )}
            </>
          ) : (
            <div className="text-center py-3">
              <p className="text-sm text-gray-600 mb-3">
                No hay ejecucion activa. Presiona PLAY para comenzar.
              </p>
              <Button
                variant="primary"
                size="lg"
                onClick={handleIniciar}
                loading={iniciar.isPending}
                disabled={!['planificada','liberada','en_pausa'].includes(ot.estado)}
                className="w-full sm:w-auto"
              >
                <Play className="h-5 w-5" /> Iniciar (PLAY)
              </Button>
              {!['planificada','liberada','en_pausa'].includes(ot.estado) && (
                <p className="mt-2 text-xs text-amber-700">
                  OT en estado <span className="font-mono">{ot.estado}</span> — verifica con tu supervisor.
                </p>
              )}
            </div>
          )}

          {errorMsg && (
            <div className="rounded border border-red-200 bg-red-50 p-2 text-xs text-red-700 flex items-start gap-1.5">
              <AlertTriangle className="h-3.5 w-3.5 mt-0.5 shrink-0" />
              {errorMsg}
            </div>
          )}
        </CardContent>
      </Card>

      {subtareas && subtareas.length > 0 && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Subtareas ({subtareas.length})</CardTitle>
          </CardHeader>
          <CardContent>
            <ul className="space-y-1 text-xs">
              {subtareas.slice(0, 30).map((s) => (
                <li key={s.id} className="flex items-center gap-2 py-1 border-b border-gray-100 last:border-0">
                  <span className="font-mono text-gray-500 w-6">{s.orden}</span>
                  <span className="flex-1">{s.descripcion}</span>
                  <EstadoBadge estado={s.estado} />
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>
      )}
    </div>
  )
}

function Info({ label, value, mono, icon }: { label: string; value: string; mono?: boolean; icon?: React.ReactNode }) {
  return (
    <div>
      <div className="flex items-center gap-1 text-gray-500 uppercase text-[10px]">
        {icon} {label}
      </div>
      <div className={`text-gray-900 ${mono ? 'font-mono text-xs' : 'text-sm'} font-medium mt-0.5`}>{value}</div>
    </div>
  )
}

function Tiempo({ label, segundos, highlight }: { label: string; segundos: number; highlight?: boolean }) {
  const h = Math.floor(segundos / 3600)
  const m = Math.floor((segundos % 3600) / 60)
  const s = segundos % 60
  const txt = `${h.toString().padStart(2,'0')}:${m.toString().padStart(2,'0')}:${s.toString().padStart(2,'0')}`
  return (
    <div className={`rounded p-2 text-center ${highlight ? 'bg-amber-50 border border-amber-200' : 'bg-gray-50 border border-gray-100'}`}>
      <div className="text-[10px] text-gray-500 uppercase">{label}</div>
      <div className={`mt-0.5 font-mono ${highlight ? 'text-amber-800 font-bold' : 'text-gray-700'}`}>{txt}</div>
    </div>
  )
}
