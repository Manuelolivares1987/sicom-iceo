'use client'

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts'
import { AlertTriangle, CheckCircle2, Clock, Gauge, HelpCircle, Search, Wrench } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Modal } from '@/components/ui/modal'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getConsumoDia, getEquiposHoras, getHorasDia, type EquipoHoras, type EstadoPreventiva,
} from '@/lib/services/horas-equipos'

// ============================================================================
// Horas por equipo (MIG597)
// ----------------------------------------------------------------------------
// Una fila por equipo: cuánto trabajó (GPS), a qué ritmo, y cuándo le toca el
// próximo preventivo por horas. Ordenada por lo que falta: lo vencido arriba.
// El ritmo es el de los últimos 30 días medidos, no el promedio desde la última
// mantención (un equipo parado meses daba fechas absurdas).
// ============================================================================

const ESTADO: Record<EstadoPreventiva, { label: string; clase: string; icon: typeof Clock; orden: number }> = {
  vencida:      { label: 'Vencida',       clase: 'bg-red-100 text-red-800',       icon: AlertTriangle, orden: 0 },
  proxima:      { label: '≤ 50 h',        clase: 'bg-amber-100 text-amber-800',   icon: Clock,         orden: 1 },
  atento:       { label: '≤ 100 h',       clase: 'bg-yellow-50 text-yellow-800',  icon: Clock,         orden: 2 },
  al_dia:       { label: 'Al día',        clase: 'bg-green-100 text-green-800',   icon: CheckCircle2,  orden: 3 },
  revisar_base: { label: 'Revisar base',  clase: 'bg-purple-100 text-purple-800', icon: HelpCircle,    orden: 4 },
  sin_plan:     { label: 'Sin plan',      clase: 'bg-gray-100 text-gray-600',     icon: HelpCircle,    orden: 5 },
}

const NUM1 = new Intl.NumberFormat('es-CL', { maximumFractionDigits: 1 })
const NUM0 = new Intl.NumberFormat('es-CL', { maximumFractionDigits: 0 })
const n1 = (v: number | null | undefined) => (v == null ? '—' : NUM1.format(v))
const n0 = (v: number | null | undefined) => (v == null ? '—' : NUM0.format(v))
const fecha = (iso: string | null | undefined) =>
  iso ? new Date(iso.slice(0, 10) + 'T12:00:00').toLocaleDateString('es-CL', { day: '2-digit', month: 'short', year: '2-digit' }) : '—'

export default function HorasEquiposPage() {
  useRequireAuth()
  const [filtro, setFiltro] = useState<EstadoPreventiva | 'todos'>('todos')
  const [texto, setTexto] = useState('')
  const [abierto, setAbierto] = useState<EquipoHoras | null>(null)

  const { data, isLoading, error } = useQuery({
    queryKey: ['equipo-horas'],
    queryFn: getEquiposHoras,
    staleTime: 5 * 60_000,
  })

  const conteo = useMemo(() => {
    const c: Partial<Record<EstadoPreventiva, number>> = {}
    for (const e of data ?? []) c[e.estado_preventiva] = (c[e.estado_preventiva] ?? 0) + 1
    return c
  }, [data])

  const filas = useMemo(() => {
    const q = texto.trim().toLowerCase()
    return (data ?? [])
      .filter((e) => filtro === 'todos' || e.estado_preventiva === filtro)
      .filter((e) => !q || [e.patente, e.codigo, e.nombre, e.faena, e.proxima_pauta]
        .some((v) => v?.toLowerCase().includes(q)))
      .sort((a, b) => ESTADO[a.estado_preventiva].orden - ESTADO[b.estado_preventiva].orden
        || (a.horas_faltan ?? 1e9) - (b.horas_faltan ?? 1e9))
  }, [data, filtro, texto])

  return (
    <div className="space-y-5 p-4 md:p-6">
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-bold text-gray-900">
          <Gauge className="h-6 w-6 text-pillado-green-600" /> Horas por equipo
        </h1>
        <p className="text-sm text-gray-500">
          Horómetro del GPS, uso real de los últimos 30 días y próximo preventivo por horas.
          La campanita avisa al jefe de mantenimiento y a planificación cuando faltan 50 h o menos.
        </p>
      </div>

      {/* Contadores = filtros */}
      <div className="flex flex-wrap gap-2">
        <Chip activo={filtro === 'todos'} onClick={() => setFiltro('todos')}
              label="Todos" n={data?.length ?? 0} clase="bg-gray-100 text-gray-800" />
        {(Object.keys(ESTADO) as EstadoPreventiva[]).map((k) => (
          <Chip key={k} activo={filtro === k} onClick={() => setFiltro(k)}
                label={ESTADO[k].label} n={conteo[k] ?? 0} clase={ESTADO[k].clase} />
        ))}
        <div className="relative ml-auto w-full sm:w-64">
          <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-gray-400" />
          <Input className="pl-8" placeholder="Patente, faena, pauta…" value={texto}
                 onChange={(e) => setTexto(e.target.value)} />
        </div>
      </div>

      {isLoading && <div className="flex justify-center py-16"><Spinner /></div>}
      {error && <Card><CardContent className="p-6 text-sm text-red-700">{(error as Error).message}</CardContent></Card>}

      {data && (
        <Card>
          <CardContent className="overflow-x-auto p-0">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-xs text-gray-600">
                <tr>
                  <th className="px-3 py-2 text-left">Equipo</th>
                  <th className="px-3 py-2 text-right">Horómetro</th>
                  <th className="px-3 py-2 text-right">Ayer</th>
                  <th className="px-3 py-2 text-right">7 días</th>
                  <th className="px-3 py-2 text-right">30 días</th>
                  <th className="px-3 py-2 text-right">h/día</th>
                  <th className="px-3 py-2 text-left">Próximo preventivo</th>
                  <th className="px-3 py-2 text-right">Faltan</th>
                  <th className="px-3 py-2 text-left">Fecha estimada</th>
                  <th className="px-3 py-2 text-left">Estado</th>
                </tr>
              </thead>
              <tbody>
                {filas.map((e) => {
                  const est = ESTADO[e.estado_preventiva]
                  const Icon = est.icon
                  return (
                    <tr key={e.activo_id} className="cursor-pointer border-t hover:bg-gray-50"
                        onClick={() => setAbierto(e)}>
                      <td className="px-3 py-1.5">
                        <div className="font-medium">{e.patente ?? e.codigo}</div>
                        <div className="text-xs text-gray-500">{e.faena ?? '—'}</div>
                      </td>
                      <td className="px-3 py-1.5 text-right">{n0(e.horometro)}</td>
                      <td className="px-3 py-1.5 text-right">{n1(e.horas_ayer)}</td>
                      <td className="px-3 py-1.5 text-right">{n1(e.horas_7d)}</td>
                      <td className="px-3 py-1.5 text-right">{n1(e.horas_30d)}</td>
                      <td className="px-3 py-1.5 text-right">{n1(e.horas_por_dia)}</td>
                      <td className="px-3 py-1.5">
                        <div>{e.proxima_pauta ?? '—'}</div>
                        {e.ot_abierta && (
                          <div className="flex items-center gap-1 text-xs text-gray-500">
                            <Wrench className="h-3 w-3" /> {e.ot_abierta}
                          </div>
                        )}
                      </td>
                      <td className={`px-3 py-1.5 text-right font-medium ${(e.horas_faltan ?? 1) <= 0 ? 'text-red-700' : ''}`}>
                        {e.estado_preventiva === 'revisar_base' ? '—'
                          : e.horas_faltan == null ? '—'
                          : e.horas_faltan <= 0 ? `+${n0(Math.abs(e.horas_faltan))} h atraso`
                          : `${n0(e.horas_faltan)} h`}
                      </td>
                      <td className="px-3 py-1.5">
                        {e.fecha_estimada ? fecha(e.fecha_estimada)
                          : e.plan_id && e.estado_preventiva !== 'revisar_base'
                            ? <span className="text-xs text-gray-400">sin uso medido</span> : '—'}
                      </td>
                      <td className="px-3 py-1.5">
                        <span className={`inline-flex items-center gap-1 rounded px-2 py-0.5 text-xs font-medium ${est.clase}`}>
                          <Icon className="h-3 w-3" /> {est.label}
                        </span>
                      </td>
                    </tr>
                  )
                })}
                {filas.length === 0 && (
                  <tr><td colSpan={10} className="p-6 text-center text-sm text-gray-500">Sin equipos para este filtro.</td></tr>
                )}
              </tbody>
            </table>
          </CardContent>
        </Card>
      )}

      {abierto && <DetalleEquipo equipo={abierto} onClose={() => setAbierto(null)} />}
    </div>
  )
}

function Chip({ activo, onClick, label, n, clase }: {
  activo: boolean; onClick: () => void; label: string; n: number; clase: string
}) {
  return (
    <button onClick={onClick}
            className={`rounded-full px-3 py-1 text-sm font-medium ${clase} ${activo ? 'ring-2 ring-pillado-green-500' : ''}`}>
      {label} <span className="opacity-70">{n}</span>
    </button>
  )
}

function DetalleEquipo({ equipo, onClose }: { equipo: EquipoHoras; onClose: () => void }) {
  const desde = useMemo(() => {
    const d = new Date(); d.setDate(d.getDate() - 60)
    return d.toISOString().slice(0, 10)
  }, [])
  const { data, isLoading } = useQuery({
    queryKey: ['equipo-horas-dia', equipo.activo_id, desde],
    queryFn: () => getHorasDia(equipo.activo_id, desde),
  })
  const serie = (data ?? []).map((d) => ({ fecha: d.fecha.slice(5), horas: d.horas }))

  return (
    <Modal open onClose={onClose} title={`${equipo.patente ?? equipo.codigo} — horas por día`}
           description={`${equipo.faena ?? 'Sin faena'} · horómetro ${n0(equipo.horometro)} h · último dato GPS ${fecha(equipo.ultima_lectura)}`}
           className="sm:max-w-3xl">
      <div className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
        <Dato label="Ritmo (30 días)" valor={`${n1(equipo.horas_por_dia)} h/día`} />
        <Dato label="Días con uso (30)" valor={n0(equipo.dias_con_uso_30d)} />
        <Dato label="Última preventiva" valor={`${fecha(equipo.ultima_preventiva_fecha)} · ${n0(equipo.ultima_preventiva_horas)} h`} />
        <Dato label="Próxima" valor={equipo.proxima_pauta ?? '—'} />
      </div>
      <Card className="mt-4">
        <CardHeader className="pb-1"><CardTitle className="text-sm">Horas trabajadas por día (últimos 60 días)</CardTitle></CardHeader>
        <CardContent>
          {isLoading ? <div className="flex justify-center py-8"><Spinner /></div>
            : serie.length === 0 ? <div className="py-8 text-center text-sm text-gray-500">El GPS no tiene lecturas de horómetro en este período.</div>
            : (
              <div style={{ width: '100%', height: 220 }}>
                <ResponsiveContainer>
                  <BarChart data={serie} margin={{ top: 5, right: 5, left: -15, bottom: 0 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" vertical={false} />
                    <XAxis dataKey="fecha" tick={{ fontSize: 10 }} interval="preserveStartEnd" />
                    <YAxis tick={{ fontSize: 11 }} />
                    <Tooltip formatter={(v: number) => [`${n1(v)} h`, 'Horas']} cursor={{ fill: '#F3F4F6' }} />
                    <Bar dataKey="horas" fill="#2563EB" radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            )}
          <p className="mt-2 text-xs text-gray-400">
            Las horas de un día son la diferencia contra el día anterior con lectura. Un salto mayor a 24 h por día
            no se cuenta (cambio de GPS o error de lectura).
          </p>
        </CardContent>
      </Card>
      <ConsumoEquipo activoId={equipo.activo_id} desde={desde} />
    </Modal>
  )
}

// [MIG635] Litros desde el computador del camión (GPS de fábrica Renault).
// Sin GPS de fábrica no hay filas y la tarjeta no aparece.
function ConsumoEquipo({ activoId, desde }: { activoId: string; desde: string }) {
  const { data } = useQuery({
    queryKey: ['equipo-consumo-dia', activoId, desde],
    queryFn: () => getConsumoDia(activoId, desde),
  })
  const dias = (data ?? []).filter((d) => d.litros != null)
  if (dias.length === 0) return null

  const suma = (f: (d: (typeof dias)[number]) => number | null) => dias.reduce((t, d) => t + (f(d) ?? 0), 0)
  const litros = suma((d) => d.litros)
  const ralenti = suma((d) => d.litros_ralenti)
  const horas = suma((d) => (d.litros != null ? d.horas : null))
  const km = suma((d) => (d.litros != null ? d.km : null))
  const serie = dias.map((d) => ({ fecha: d.fecha.slice(5), litros: d.litros, ralenti: d.litros_ralenti }))

  return (
    <Card className="mt-4">
      <CardHeader className="pb-1"><CardTitle className="text-sm">Combustible por día (computador del camión)</CardTitle></CardHeader>
      <CardContent>
        <div className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
          <Dato label="Litros (período)" valor={`${n0(litros)} L`} />
          <Dato label="Litros por hora" valor={horas > 0 ? `${n1(litros / horas)} L/h` : '—'} />
          <Dato label="Rendimiento" valor={litros > 0 && km > 0 ? `${n1(km / litros)} km/L` : '—'} />
          <Dato label="En ralentí" valor={litros > 0 ? `${n0((100 * ralenti) / litros)} % · ${n0(ralenti)} L` : '—'} />
        </div>
        <div className="mt-3" style={{ width: '100%', height: 200 }}>
          <ResponsiveContainer>
            <BarChart data={serie} margin={{ top: 5, right: 5, left: -15, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" vertical={false} />
              <XAxis dataKey="fecha" tick={{ fontSize: 10 }} interval="preserveStartEnd" />
              <YAxis tick={{ fontSize: 11 }} />
              <Tooltip
                formatter={(v: number, k: string) => [`${n1(v)} L`, k === 'ralenti' ? 'En ralentí' : 'Total']}
                cursor={{ fill: '#F3F4F6' }} />
              <Bar dataKey="litros" fill="#2563EB" radius={[4, 4, 0, 0]} />
              <Bar dataKey="ralenti" fill="#F59E0B" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
        <p className="mt-2 text-xs text-gray-400">
          Azul: litros del día. Ámbar: litros quemados con el camión detenido y el motor en marcha. Son los
          acumulados del motor, no las cargas: sirven para cruzar contra lo despachado.
        </p>
      </CardContent>
    </Card>
  )
}

function Dato({ label, valor }: { label: string; valor: string }) {
  return (
    <div className="rounded-md bg-gray-50 p-2">
      <div className="text-xs text-gray-500">{label}</div>
      <div className="font-medium">{valor}</div>
    </div>
  )
}
