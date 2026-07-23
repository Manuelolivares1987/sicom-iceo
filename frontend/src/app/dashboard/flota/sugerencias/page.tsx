'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { ArrowLeft, MapPin, Check, CheckCheck, RefreshCw, Building2, Search } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { errorMessage, todayISO } from '@/lib/utils'
import { useSugerenciasEstado, useConfirmarEstado } from '@/hooks/use-sugerencias-estado'
import { CambiarEstadoModal } from '@/components/flota/cambiar-estado-modal'
import { supabase } from '@/lib/supabase'

type EstadoCodigo = 'A' | 'C' | 'D' | 'H' | 'R' | 'M' | 'T' | 'F' | 'V' | 'U' | 'L'
type ActivoModal = {
  id: string
  patente?: string | null
  codigo?: string | null
  nombre?: string | null
  estado_comercial?: string | null
  operacion?: string | null
  cliente_actual?: string | null
  contrato_id?: string | null
  ubicacion_actual?: string | null
}

const COLOR: Record<string, string> = {
  A: '#16A34A', C: '#15803D', L: '#4F46E5', U: '#0891B2', D: '#2563EB',
  H: '#A855F7', R: '#06B6D4', M: '#F59E0B', T: '#FB923C', F: '#DC2626', V: '#9333EA',
}
const LABEL: Record<string, string> = {
  A: 'Arrendado', C: 'En contrato', D: 'Disponible', H: 'Habilitación', R: 'Recepción',
  M: 'Mantención', T: 'Taller', F: 'Fuera de servicio', V: 'Venta', U: 'Uso interno', L: 'Leasing',
}
const OPCIONES = ['A', 'C', 'D', 'H', 'R', 'M', 'T', 'F', 'U', 'L', 'V']

function Pill({ e }: { e: string | null }) {
  if (!e) return <span className="text-gray-300">—</span>
  return (
    <span className="inline-flex items-center gap-1 rounded px-2 py-0.5 text-xs font-semibold text-white" style={{ background: COLOR[e] ?? '#9CA3AF' }}>
      {e} · {LABEL[e] ?? e}
    </span>
  )
}

export default function SugerenciasEstadoPage() {
  useRequireAuth()
  const toast = useToast()
  const [fecha, setFecha] = useState(todayISO())
  const [soloCambios, setSoloCambios] = useState(true)
  const [filtroPatente, setFiltroPatente] = useState('')
  const [filtroOperacion, setFiltroOperacion] = useState('') // Calama / Coquimbo / ...
  const [elegido, setElegido] = useState<Record<string, string>>({}) // override del planificador

  // Mapa activo_id -> operación (Calama / Coquimbo) para el filtro por zona
  const [operacionPorActivo, setOperacionPorActivo] = useState<Record<string, string | null>>({})
  const cargarOperaciones = () => {
    supabase.from('activos').select('id, operacion').then(({ data }) => {
      if (data) setOperacionPorActivo(Object.fromEntries((data as { id: string; operacion: string | null }[]).map((a) => [a.id, a.operacion])))
    })
  }
  useEffect(() => { cargarOperaciones() }, [])

  const { data: sugerencias = [], isLoading, refetch, isFetching } = useSugerenciasEstado(fecha)
  const confirmar = useConfirmarEstado()

  // ── Modal Cambiar Estado (con contrato) desde una sugerencia ──
  const [modalActivo, setModalActivo] = useState<ActivoModal | null>(null)
  const [modalEstado, setModalEstado] = useState<EstadoCodigo | undefined>(undefined)
  const [abriendoModal, setAbriendoModal] = useState<string | null>(null)

  const abrirConContrato = async (activoId: string, estadoSugerido: string | null) => {
    setAbriendoModal(activoId)
    try {
      const { data, error } = await supabase
        .from('activos')
        .select('id, patente, codigo, nombre, estado_comercial, operacion, cliente_actual, contrato_id, ubicacion_actual')
        .eq('id', activoId)
        .single()
      if (error) throw error
      setModalActivo(data as ActivoModal)
      setModalEstado((estadoSugerido as EstadoCodigo) || undefined)
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo abrir el equipo'))
    } finally {
      setAbriendoModal(null)
    }
  }

  const operaciones = useMemo(() => {
    const set = new Set<string>()
    for (const s of sugerencias) { const op = operacionPorActivo[s.activo_id]; if (op) set.add(op) }
    return Array.from(set).sort()
  }, [sugerencias, operacionPorActivo])

  const filtradas = useMemo(() => {
    const q = filtroPatente.trim().toUpperCase().replace(/[^A-Z0-9]/g, '')
    let base = soloCambios ? sugerencias.filter((s) => !s.coincide && s.estado_sugerido) : sugerencias
    if (q) {
      base = base.filter((s) =>
        (s.patente ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '').includes(q),
      )
    }
    if (filtroOperacion) {
      base = base.filter((s) => (operacionPorActivo[s.activo_id] ?? '') === filtroOperacion)
    }
    return base
  }, [sugerencias, soloCambios, filtroPatente, filtroOperacion, operacionPorActivo])
  const cambios = useMemo(() => sugerencias.filter((s) => !s.coincide && s.estado_sugerido), [sugerencias])

  const confirmarUno = (activoId: string, estado: string) => {
    confirmar.mutate({ activoId, fecha, estado }, {
      onSuccess: () => toast.success('Estado confirmado'),
      onError: (e) => toast.error(errorMessage(e, 'No se pudo confirmar')),
    })
  }
  const confirmarTodas = async () => {
    for (const s of cambios) {
      const est = elegido[s.activo_id] ?? s.estado_sugerido!
      try { await confirmar.mutateAsync({ activoId: s.activo_id, fecha, estado: est }) } catch { /* sigue */ }
    }
    toast.success(`${cambios.length} cambios confirmados`)
    refetch()
  }
  // Cierra TODA la flota para la fecha: escribe los 55 (los que no cambian
  // quedan con su mismo estado del día anterior). Así el informe muestra la
  // flota completa, no solo los que cambiaron.
  const confirmarDiaCompleto = async () => {
    for (const s of sugerencias) {
      const est = elegido[s.activo_id] ?? s.estado_guardado ?? s.estado_sugerido ?? s.estado_actual
      if (!est) continue
      try { await confirmar.mutateAsync({ activoId: s.activo_id, fecha, estado: est }) } catch { /* sigue */ }
    }
    toast.success(`Día ${fecha} cerrado: ${sugerencias.length} equipos`)
    refetch()
  }

  return (
    <div className="space-y-4 p-6">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <Link href="/dashboard/flota/dashboard" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-800">
            <ArrowLeft className="h-4 w-4" /> Volver a Flota
          </Link>
          <h1 className="mt-1 flex items-center gap-2 text-2xl font-bold">
            <MapPin className="h-6 w-6 text-emerald-600" /> Sugerencias de estado (GPS)
          </h1>
          <p className="mt-1 text-sm text-gray-600">
            Estado sugerido por la ubicación GPS / geocerca de cada equipo. <b>Nada se aplica solo</b> — tú confirmas.
          </p>
        </div>
        <div className="flex items-end gap-2">
          <div>
            <label className="block text-[10px] uppercase text-gray-400">Fecha a planificar</label>
            <input type="date" className="h-9 rounded border border-gray-300 px-2 text-sm" value={fecha} onChange={(e) => setFecha(e.target.value)} />
          </div>
          <Button variant="outline" size="sm" onClick={() => refetch()} disabled={isFetching}>
            <RefreshCw className={`h-4 w-4 mr-1 ${isFetching ? 'animate-spin' : ''}`} /> Actualizar
          </Button>
        </div>
      </header>

      <Card>
        <CardHeader className="flex flex-col gap-2 pb-2 sm:flex-row sm:items-center sm:justify-between">
          <CardTitle className="text-base text-gray-700">
            {cambios.length} cambios sugeridos · {sugerencias.length} equipos de flota
          </CardTitle>
          <div className="flex flex-wrap items-center gap-3">
            <div className="relative">
              <Search className="pointer-events-none absolute left-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-gray-400" />
              <input
                type="text"
                value={filtroPatente}
                onChange={(e) => setFiltroPatente(e.target.value)}
                placeholder="Filtrar por patente…"
                className="h-8 w-44 rounded border border-gray-300 pl-7 pr-2 text-xs focus:border-emerald-500 focus:outline-none"
              />
              {filtroPatente && (
                <button onClick={() => setFiltroPatente('')}
                  className="absolute right-1.5 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600">✕</button>
              )}
            </div>
            {operaciones.length > 0 && (
              <select
                value={filtroOperacion}
                onChange={(e) => setFiltroOperacion(e.target.value)}
                className="h-8 rounded border border-gray-300 px-2 text-xs focus:border-emerald-500 focus:outline-none"
                title="Filtrar por operación / zona"
              >
                <option value="">Todas las operaciones</option>
                {operaciones.map((op) => <option key={op} value={op}>{op}</option>)}
              </select>
            )}
            <label className="flex items-center gap-1 text-xs text-gray-600">
              <input type="checkbox" checked={soloCambios} onChange={(e) => setSoloCambios(e.target.checked)} />
              Solo cambios
            </label>
            <Button size="sm" variant="outline" onClick={confirmarTodas} disabled={confirmar.isPending || cambios.length === 0}>
              <CheckCheck className="mr-1 h-4 w-4" /> Confirmar cambios ({cambios.length})
            </Button>
            <Button size="sm" className="bg-emerald-600 hover:bg-emerald-700"
              onClick={confirmarDiaCompleto} disabled={confirmar.isPending || sugerencias.length === 0}>
              <CheckCheck className="mr-1 h-4 w-4" /> Cerrar día · toda la flota ({sugerencias.length})
            </Button>
          </div>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          {isLoading ? (
            <div className="flex justify-center py-10"><Spinner className="h-6 w-6" /></div>
          ) : filtradas.length === 0 ? (
            <p className="py-8 text-center text-sm text-gray-400">
              {soloCambios ? 'No hay cambios sugeridos: todos los equipos coinciden con su ubicación.' : 'Sin equipos de flota.'}
            </p>
          ) : (
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
                  <th className="px-2 py-2">Patente</th>
                  <th className="px-2 py-2">Equipo</th>
                  <th className="px-2 py-2">Zona GPS</th>
                  <th className="px-2 py-2">Estado actual (día previo)</th>
                  <th className="px-2 py-2">Sugerido</th>
                  <th className="px-2 py-2">Confirmado ese día</th>
                  <th className="px-2 py-2">Confirmar como</th>
                  <th className="px-2 py-2"></th>
                </tr>
              </thead>
              <tbody>
                {filtradas.map((s) => {
                  const sel = elegido[s.activo_id] ?? s.estado_guardado ?? s.estado_sugerido ?? ''
                  const editado = s.estado_guardado != null && sel !== s.estado_guardado
                  return (
                    <tr key={s.activo_id} className="border-b hover:bg-gray-50">
                      <td className="px-2 py-1.5 font-mono font-semibold">{s.patente}</td>
                      <td className="px-2 py-1.5 text-gray-500">{s.equipamiento ?? '—'}</td>
                      <td className="px-2 py-1.5 text-gray-600">{s.zona ?? 'Fuera de zona'}</td>
                      <td className="px-2 py-1.5"><Pill e={s.estado_actual} /></td>
                      <td className="px-2 py-1.5"><Pill e={s.estado_sugerido} /></td>
                      <td className="px-2 py-1.5">
                        <Pill e={s.estado_guardado} />
                        {editado && <span className="ml-1 text-[10px] font-semibold text-amber-600">editado</span>}
                      </td>
                      <td className="px-2 py-1.5">
                        <select
                          className="h-8 rounded border border-gray-300 px-1 text-xs"
                          value={sel}
                          onChange={(e) => setElegido((p) => ({ ...p, [s.activo_id]: e.target.value }))}
                        >
                          {OPCIONES.map((o) => (
                            <option key={o} value={o}>{o} · {LABEL[o]}</option>
                          ))}
                        </select>
                      </td>
                      <td className="px-2 py-1.5">
                        <div className="flex items-center gap-1.5">
                          <Button size="sm" variant="outline" disabled={confirmar.isPending || !sel}
                            onClick={() => confirmarUno(s.activo_id, sel)}>
                            <Check className="mr-1 h-4 w-4" /> Confirmar
                          </Button>
                          <Button size="sm" variant="ghost" title="Confirmar y gestionar contrato (mantener / cambiar / asignar)"
                            disabled={abriendoModal === s.activo_id}
                            onClick={() => abrirConContrato(s.activo_id, sel)}>
                            {abriendoModal === s.activo_id
                              ? <Spinner className="h-4 w-4" />
                              : <><Building2 className="mr-1 h-4 w-4" /> Contrato</>}
                          </Button>
                        </div>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          )}
          <div className="mt-3 flex flex-wrap gap-x-3 gap-y-1">
            {OPCIONES.map((e) => (
              <span key={e} className="flex items-center gap-1 text-[10px] text-gray-600">
                <span className="inline-block h-3 w-3 rounded-sm" style={{ background: COLOR[e] }} />{e}={LABEL[e]}
              </span>
            ))}
          </div>
        </CardContent>
      </Card>

      {/* Modal Cambiar Estado con gestión de contrato (mantener / cambiar / asignar) */}
      <CambiarEstadoModal
        open={!!modalActivo}
        onClose={() => {
          setModalActivo(null)
          setModalEstado(undefined)
          refetch()
          cargarOperaciones() // refresca la operación completada desde el contrato
        }}
        activo={modalActivo}
        estadoInicial={modalEstado}
        fechaInicial={fecha}
      />
    </div>
  )
}
