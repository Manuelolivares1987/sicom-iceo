'use client'

import { useEffect, useState } from 'react'
import { useParams, useRouter } from 'next/navigation'
import {
  ArrowLeft, Play, Pause, RotateCcw, CheckCircle2, AlertTriangle,
  MapPin, MessageSquare, User, Coffee, Wrench,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useCalamaOT } from '@/hooks/use-calama'
import {
  useEjecucionActivaPorOT, useIniciarEjecucion, usePausarEjecucion,
  useReanudarEjecucion, useFinalizarEjecucion, useMisOTsAsignadas,
} from '@/hooks/use-calama-plan-semanal'
import {
  useMarcarOTCompletadaOperador, useRegistrarAvanceParcialOperador,
} from '@/hooks/use-calama-avance'
import { excelCodigoFromFolio, zonaCodeFromFolio } from '@/lib/services/calama'

const MOTIVOS_PAUSA: Array<{ value: string; label: string }> = [
  { value: 'colacion',                label: 'Colacion' },
  { value: 'espera_autorizacion',     label: 'Espera autorizacion' },
  { value: 'falta_material',          label: 'Falta material' },
  { value: 'falta_herramienta',       label: 'Falta herramienta' },
  { value: 'interferencia_mandante',  label: 'Interferencia mandante' },
  { value: 'traslado',                label: 'Traslado' },
  { value: 'clima',                   label: 'Clima' },
  { value: 'condicion_insegura',      label: 'Condicion insegura' },
  { value: 'otro',                    label: 'Otro' },
]

export default function MobileOTDetallePage() {
  const params = useParams<{ id: string }>()
  const router = useRouter()
  const otId = params?.id as string | undefined

  const { data: ot, isLoading } = useCalamaOT(otId)
  const { data: ejecucion } = useEjecucionActivaPorOT(otId)
  const { data: misOts } = useMisOTsAsignadas()

  const iniciar = useIniciarEjecucion()
  const pausar = usePausarEjecucion()
  const reanudar = useReanudarEjecucion()
  const finalizar = useFinalizarEjecucion()
  const marcarCompletada = useMarcarOTCompletadaOperador()
  const guardarParcial = useRegistrarAvanceParcialOperador()

  const [error, setError] = useState<string | null>(null)
  const [okMsg, setOkMsg] = useState<string | null>(null)
  const [showMotivos, setShowMotivos] = useState(false)
  const [tickElapsed, setTickElapsed] = useState(0)
  const [avanceValor, setAvanceValor] = useState<number>(0)
  const [avanceComentario, setAvanceComentario] = useState<string>('')
  const [comentarioCierre, setComentarioCierre] = useState<string>('')

  useEffect(() => {
    if (!ejecucion || ejecucion.estado !== 'en_ejecucion') return
    const t = setInterval(() => setTickElapsed((n) => n + 1), 1000)
    return () => clearInterval(t)
  }, [ejecucion])
  useEffect(() => { setTickElapsed(0) }, [ejecucion?.last_event_at])
  useEffect(() => {
    if (ot) setAvanceValor(Math.round(Number(ot.avance_pct ?? 0)))
  }, [ot])

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-screen text-gray-500">
        <Spinner className="h-6 w-6" />
      </div>
    )
  }

  if (!ot) {
    return (
      <div className="p-4 text-center">
        <p className="text-sm text-red-700">OT no encontrada o sin permisos.</p>
        <button onClick={() => router.push('/m/calama')}
          className="mt-3 rounded bg-amber-600 px-4 py-2 text-white text-sm">
          Volver
        </button>
      </div>
    )
  }

  const codigo = excelCodigoFromFolio(ot.folio)
  const lugar = zonaCodeFromFolio(ot.folio)
  const avanceReal = Number(ot.avance_pct ?? 0)
  const avanceExcel = Number((ot as { avance_excel_pct?: number }).avance_excel_pct ?? 0)
  const planOt = (misOts ?? []).find((p) => p.ot_id === ot.id)
  const otFinalizada = ot.estado === 'finalizada' || ot.estado === 'cancelada'

  const tEfectivo = (ejecucion?.tiempo_efectivo_segundos ?? 0)
    + (ejecucion?.estado === 'en_ejecucion' ? tickElapsed : 0)
  const tPausado = (ejecucion?.tiempo_pausado_segundos ?? 0)
    + (ejecucion?.estado === 'pausada' ? tickElapsed : 0)

  const handleIniciar = async () => {
    setError(null); setOkMsg(null)
    try { await iniciar.mutateAsync(ot.id); setOkMsg('Ejecucion iniciada') }
    catch (e) { setError(e instanceof Error ? e.message : 'Error al iniciar') }
  }
  const handlePausar = async (motivo: string) => {
    if (!ejecucion) return
    setError(null); setShowMotivos(false)
    try { await pausar.mutateAsync({ ejecucionId: ejecucion.id, motivo, otId: ot.id }) }
    catch (e) { setError(e instanceof Error ? e.message : 'Error al pausar') }
  }
  const handleReanudar = async () => {
    if (!ejecucion) return
    setError(null)
    try { await reanudar.mutateAsync({ ejecucionId: ejecucion.id, otId: ot.id }) }
    catch (e) { setError(e instanceof Error ? e.message : 'Error al reanudar') }
  }
  const handleGuardarAvance = async () => {
    setError(null); setOkMsg(null)
    if (avanceValor < 100 && !avanceComentario.trim()) {
      setError('Comentario obligatorio para avance parcial')
      return
    }
    try {
      await guardarParcial.mutateAsync({
        ot_id: ot.id,
        avance_nuevo: avanceValor,
        comentario: avanceComentario || undefined,
      })
      setOkMsg(`Avance guardado: ${avanceValor}%`)
      setAvanceComentario('')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Error al guardar avance')
    }
  }
  const handleMarcarCompletada = async () => {
    if (!confirm('Marcar la OT como completada al 100%?')) return
    setError(null); setOkMsg(null)
    try {
      await marcarCompletada.mutateAsync({
        ot_id: ot.id,
        ejecucion_id: ejecucion?.id,
        comentario: comentarioCierre || undefined,
      })
      setOkMsg('OT completada')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Error al completar')
    }
  }
  const handleFinalizar = async () => {
    if (!ejecucion) return
    if (!confirm('Finalizar la ejecucion ahora?')) return
    setError(null)
    try {
      await finalizar.mutateAsync({
        ejecucionId: ejecucion.id, otId: ot.id,
        avance: avanceValor, observacion: comentarioCierre || undefined,
      })
      setOkMsg('OT finalizada')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Error al finalizar')
    }
  }

  return (
    <div className="space-y-3">
      {/* Header sticky */}
      <header className="sticky top-0 z-30 bg-amber-700 text-white shadow-md">
        <div className="px-3 py-2.5 flex items-center gap-2">
          <button onClick={() => router.push('/m/calama')} aria-label="Volver"
            className="rounded-full p-1.5 bg-white/10 hover:bg-white/20 active:bg-white/30">
            <ArrowLeft className="h-4 w-4" />
          </button>
          <div className="flex-1 min-w-0">
            <div className="text-[10px] uppercase opacity-90 font-mono">{codigo}</div>
            <h1 className="text-sm font-bold truncate">{ot.titulo}</h1>
          </div>
          <div className="text-right">
            <div className="font-mono text-base font-bold">{avanceReal.toFixed(0)}%</div>
            <EstadoChip estado={ot.estado} />
          </div>
        </div>
      </header>

      <div className="px-3 space-y-3">
        {/* Bloque 1: Lugar fisico */}
        <Card>
          <div className="flex items-start gap-2">
            <MapPin className="h-4 w-4 text-amber-700 mt-0.5 shrink-0" />
            <div className="text-sm flex-1">
              <div className="font-mono text-xs text-gray-500">{lugar ?? '—'}</div>
              <div className="text-gray-900 font-medium">
                {(ot.faena?.nombre ?? '—')}
              </div>
              <div className="text-xs text-gray-500 mt-1 flex items-center gap-2 flex-wrap">
                <span><strong>Programada:</strong> {ot.fecha_programada}</span>
                {ot.responsable_id && (
                  <span className="inline-flex items-center gap-1">
                    <User className="h-3 w-3" /> Asignada
                  </span>
                )}
              </div>
            </div>
          </div>
        </Card>

        {/* Bloque 2: Comentario planificador */}
        {planOt?.observaciones && (
          <Card extraClass="border-amber-300 bg-amber-50">
            <div className="flex items-start gap-2">
              <MessageSquare className="h-4 w-4 text-amber-700 mt-0.5 shrink-0" />
              <div className="text-sm">
                <div className="text-[10px] uppercase font-bold text-amber-800">Nota del planificador</div>
                <p className="text-amber-900 mt-0.5">{planOt.observaciones}</p>
              </div>
            </div>
          </Card>
        )}

        {ot.descripcion && (
          <Card>
            <div className="text-sm">
              <div className="text-[10px] uppercase text-gray-500">Descripcion</div>
              <p className="mt-0.5 text-gray-700 whitespace-pre-line">{ot.descripcion}</p>
            </div>
          </Card>
        )}

        {/* Mensajes */}
        {error && (
          <div className="rounded-xl border border-red-300 bg-red-50 p-3 text-sm text-red-700 flex items-start gap-2">
            <AlertTriangle className="h-4 w-4 shrink-0 mt-0.5" /> {error}
          </div>
        )}
        {okMsg && (
          <div className="rounded-xl border border-green-300 bg-green-50 p-3 text-sm text-green-700 flex items-center gap-2">
            <CheckCircle2 className="h-4 w-4" /> {okMsg}
          </div>
        )}

        {/* Bloque 3: Ejecucion (solo si no esta finalizada) */}
        {!otFinalizada && (
          <Card extraClass={ejecucion ? 'border-amber-300' : ''}>
            <div className="flex items-center gap-2 mb-2">
              <Wrench className="h-4 w-4 text-gray-700" />
              <h2 className="font-bold text-sm">Ejecucion</h2>
              {ejecucion && (
                <span className={`ml-auto text-[10px] rounded-full px-2 py-0.5 font-bold ${
                  ejecucion.estado === 'en_ejecucion' ? 'bg-green-100 text-green-700'
                  : ejecucion.estado === 'pausada' ? 'bg-yellow-100 text-yellow-800'
                  : 'bg-gray-100 text-gray-700'
                }`}>{ejecucion.estado.replace('_', ' ')}</span>
              )}
            </div>

            {ejecucion && (
              <div className="grid grid-cols-3 gap-2 mb-3 text-xs">
                <Tiempo label="Efectivo" segundos={tEfectivo} highlight={ejecucion.estado === 'en_ejecucion'} />
                <Tiempo label="Pausado" segundos={tPausado} highlight={ejecucion.estado === 'pausada'} />
                <Tiempo label="Colacion" segundos={ejecucion.tiempo_colacion_segundos ?? 0} />
              </div>
            )}

            {!ejecucion && (
              <BotonGrande onClick={handleIniciar} loading={iniciar.isPending} variant="green">
                <Play className="h-5 w-5" /> Iniciar
              </BotonGrande>
            )}

            {ejecucion?.estado === 'en_ejecucion' && (
              <div className="space-y-2">
                <BotonGrande onClick={() => setShowMotivos((v) => !v)} variant="amber">
                  <Pause className="h-5 w-5" /> Pausar
                </BotonGrande>
                {showMotivos && (
                  <div className="grid grid-cols-2 gap-1.5 rounded-lg border bg-gray-50 p-2">
                    <button
                      onClick={() => handlePausar('colacion')}
                      disabled={pausar.isPending}
                      className="col-span-2 rounded bg-yellow-100 border border-yellow-300 py-2 text-sm font-medium text-yellow-900 active:bg-yellow-200 disabled:opacity-50 inline-flex items-center justify-center gap-1.5"
                    >
                      <Coffee className="h-4 w-4" /> Colacion
                    </button>
                    {MOTIVOS_PAUSA.filter((m) => m.value !== 'colacion').map((m) => (
                      <button
                        key={m.value}
                        onClick={() => handlePausar(m.value)}
                        disabled={pausar.isPending}
                        className="rounded border border-gray-200 bg-white py-2 px-2 text-xs active:bg-amber-50 active:border-amber-300 disabled:opacity-50"
                      >
                        {m.label}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}

            {ejecucion?.estado === 'pausada' && (
              <BotonGrande onClick={handleReanudar} loading={reanudar.isPending} variant="green">
                <RotateCcw className="h-5 w-5" /> Reanudar
              </BotonGrande>
            )}
          </Card>
        )}

        {/* Bloque 4: Avance */}
        {!otFinalizada && (
          <Card>
            <h2 className="font-bold text-sm mb-2">Avance</h2>
            <div className="grid grid-cols-2 gap-2 mb-3 text-xs">
              <div className="rounded-lg border border-gray-200 bg-gray-50 p-2">
                <div className="text-[10px] uppercase text-gray-500">Excel</div>
                <div className="font-mono text-lg text-gray-700">{avanceExcel.toFixed(0)}%</div>
              </div>
              <div className="rounded-lg border border-amber-200 bg-amber-50 p-2">
                <div className="text-[10px] uppercase text-amber-600">Real</div>
                <div className="font-mono text-lg font-bold text-amber-800">{avanceReal.toFixed(0)}%</div>
              </div>
            </div>

            <div className="mb-2">
              <div className="flex items-center justify-between mb-1">
                <label className="text-xs text-gray-600">Nuevo avance</label>
                <span className="font-mono text-xl font-bold text-amber-700">{avanceValor}%</span>
              </div>
              <input
                type="range" min={0} max={100} step={5}
                value={avanceValor}
                onChange={(e) => setAvanceValor(Number(e.target.value))}
                className="w-full h-2 accent-amber-600"
              />
              <div className="flex gap-2 mt-2">
                {[25, 50, 75, 100].map((v) => (
                  <button
                    key={v}
                    onClick={() => setAvanceValor(v)}
                    className={`flex-1 rounded border py-1.5 text-xs font-medium ${
                      avanceValor === v
                        ? 'bg-amber-600 text-white border-amber-600'
                        : 'bg-white border-gray-200 text-gray-700 active:bg-gray-50'
                    }`}
                  >
                    {v}%
                  </button>
                ))}
              </div>
            </div>

            <textarea
              value={avanceComentario}
              onChange={(e) => setAvanceComentario(e.target.value)}
              rows={2}
              placeholder="Comentario (obligatorio si <100%)"
              className="w-full rounded border border-gray-300 px-3 py-2 text-sm mb-2"
            />

            <div className="grid grid-cols-1 gap-2">
              <BotonGrande onClick={handleGuardarAvance} loading={guardarParcial.isPending} variant="amber" disabled={avanceValor === avanceReal && !avanceComentario.trim()}>
                Guardar avance ({avanceValor}%)
              </BotonGrande>
              <BotonGrande onClick={handleMarcarCompletada} loading={marcarCompletada.isPending} variant="green">
                <CheckCircle2 className="h-5 w-5" /> Marcar completada 100%
              </BotonGrande>
            </div>
          </Card>
        )}

        {/* Bloque 5: Cierre formal (con timer) */}
        {!otFinalizada && ejecucion && (
          <Card>
            <h2 className="font-bold text-sm mb-2">Finalizar OT</h2>
            <textarea
              value={comentarioCierre}
              onChange={(e) => setComentarioCierre(e.target.value)}
              rows={2}
              placeholder="Comentario de cierre (opcional)"
              className="w-full rounded border border-gray-300 px-3 py-2 text-sm mb-2"
            />
            <BotonGrande onClick={handleFinalizar} loading={finalizar.isPending} variant="green">
              <CheckCircle2 className="h-5 w-5" /> Finalizar ejecucion ({avanceValor}%)
            </BotonGrande>
          </Card>
        )}

        {/* Resumen si finalizada */}
        {otFinalizada && (
          <Card extraClass="border-green-300 bg-green-50">
            <div className="flex items-center gap-2 mb-2">
              <CheckCircle2 className="h-5 w-5 text-green-700" />
              <h2 className="font-bold text-sm text-green-800">OT {ot.estado}</h2>
            </div>
            <div className="text-xs text-green-900 space-y-1">
              {ot.fecha_termino_real && <div>Cerrada: {ot.fecha_termino_real.slice(0, 16).replace('T', ' ')}</div>}
              {ot.horas_reales != null && <div>Horas reales: <strong>{Number(ot.horas_reales).toFixed(2)}h</strong></div>}
              <div>Avance final: <strong>{avanceReal.toFixed(0)}%</strong></div>
              {ot.observaciones_cierre && <div className="mt-1 text-green-800">{ot.observaciones_cierre}</div>}
            </div>
          </Card>
        )}
      </div>
    </div>
  )
}

function Card({ children, extraClass = '' }: { children: React.ReactNode; extraClass?: string }) {
  return <div className={`rounded-xl border bg-white p-3 shadow-sm ${extraClass}`}>{children}</div>
}

function BotonGrande({
  children, onClick, loading, disabled, variant = 'amber',
}: {
  children: React.ReactNode
  onClick?: () => void
  loading?: boolean
  disabled?: boolean
  variant?: 'amber' | 'green' | 'gray'
}) {
  const colors: Record<string, string> = {
    amber: 'bg-amber-600 hover:bg-amber-700 active:bg-amber-800',
    green: 'bg-green-600 hover:bg-green-700 active:bg-green-800',
    gray:  'bg-gray-600 hover:bg-gray-700 active:bg-gray-800',
  }
  return (
    <button
      onClick={onClick}
      disabled={loading || disabled}
      className={`w-full rounded-xl ${colors[variant]} text-white font-bold py-3 px-4 text-base inline-flex items-center justify-center gap-2 shadow-md disabled:opacity-50 disabled:cursor-not-allowed`}
    >
      {loading ? <Spinner className="h-4 w-4" /> : children}
    </button>
  )
}

function EstadoChip({ estado }: { estado: string }) {
  const map: Record<string, { bg: string; txt: string }> = {
    planificada:   { bg: 'bg-white/20',   txt: 'Pendiente' },
    liberada:      { bg: 'bg-blue-200/30', txt: 'Liberada' },
    en_ejecucion:  { bg: 'bg-yellow-200/30', txt: 'En ejecucion' },
    en_pausa:      { bg: 'bg-yellow-200/40', txt: 'Pausada' },
    finalizada:    { bg: 'bg-green-200/40', txt: 'Completada' },
    no_ejecutada:  { bg: 'bg-red-200/40', txt: 'No ejecutada' },
    cancelada:     { bg: 'bg-gray-200/40', txt: 'Cancelada' },
  }
  const c = map[estado] ?? { bg: 'bg-white/20', txt: estado }
  return <span className={`inline-block text-[9px] uppercase font-bold rounded px-1.5 py-0.5 mt-0.5 ${c.bg}`}>{c.txt}</span>
}

function Tiempo({ label, segundos, highlight }: { label: string; segundos: number; highlight?: boolean }) {
  const h = Math.floor(segundos / 3600)
  const m = Math.floor((segundos % 3600) / 60)
  const s = segundos % 60
  const txt = `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`
  return (
    <div className={`rounded-lg p-2 text-center ${highlight ? 'bg-amber-100 border border-amber-300' : 'bg-gray-50 border border-gray-200'}`}>
      <div className="text-[9px] uppercase text-gray-500">{label}</div>
      <div className={`font-mono text-xs font-bold ${highlight ? 'text-amber-800' : 'text-gray-700'}`}>{txt}</div>
    </div>
  )
}
