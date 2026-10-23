'use client'

import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts'
import { AlertTriangle, CheckCircle2, ClipboardList, Clock, Gauge, HelpCircle, Package, Search, ShoppingCart, Wrench } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Modal } from '@/components/ui/modal'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/hooks/use-toast'
import { RepuestosServicio, type VistaRepuestos } from '@/components/mantenimiento/repuestos-servicio'
import { limiteProxima, reprogramarEscalera, secuenciaEscalera } from '@/lib/escalera-mantencion'
import {
  getConsumoDia, getEquiposHoras, getHorasDia, getPautasEquipo, registrarPreventivaRealizada, leerHorometro, corregirHorometro, reprogramarEscaleraEquipo,
  type EquipoHoras, type EstadoPreventiva, type HorasDia, type PautaEquipo,
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

const VISTAS = [
  ['horas', 'Horas y próximo preventivo', Gauge],
  ['servicios', 'Qué se hace y repuestos', Package],
  ['compras', 'Compras', ShoppingCart],
  ['programa', 'Programa por modelo', ClipboardList],
] as const

export default function HorasEquiposPage() {
  useRequireAuth()
  const [filtro, setFiltro] = useState<EstadoPreventiva | 'todos'>('todos')
  const [texto, setTexto] = useState('')
  const [abierto, setAbierto] = useState<EquipoHoras | null>(null)
  const [vista, setVista] = useState<'horas' | VistaRepuestos>('horas')

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

      {/* [MIG647] Todo el preventivo en un solo lugar: horas, qué se hace en
          cada servicio, qué repuestos comprar y el programa del fabricante. */}
      <div className="flex flex-wrap gap-2 border-b pb-2">
        {VISTAS.map(([id, label, Icon]) => (
          <button key={id} type="button" onClick={() => setVista(id)}
            className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-medium ${
              vista === id ? 'bg-gray-900 text-white' : 'bg-white text-gray-700 ring-1 ring-gray-200 hover:bg-gray-50'}`}>
            <Icon className="h-4 w-4" /> {label}
          </button>
        ))}
      </div>

      {vista !== 'horas' && <RepuestosServicio vista={vista} />}

      {vista === 'horas' && (<>
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
                          : Math.round(e.horas_faltan) === 0 ? 'toca ahora'
                          : e.horas_faltan < 0 ? `+${n0(Math.abs(e.horas_faltan))} h atraso`
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
      </>)}

      {abierto && (
        <DetalleEquipo equipo={data?.find((e) => e.activo_id === abierto.activo_id) ?? abierto}
                       onClose={() => setAbierto(null)} />
      )}
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
      <CorregirHorometro equipo={equipo} />
      <CambiarProximaEquipo equipo={equipo} />
      <PautasEquipo equipo={equipo} horasDia={data ?? []} />
      <ConsumoEquipo activoId={equipo.activo_id} desde={desde} />
    </Modal>
  )
}

// [MIG640] Las pautas del equipo y registrar una ya hecha (taller sin OT
// ligada al plan, servicio externo). El horómetro se propone desde el GPS de
// ese día; la pauta mayor deja al día a las menores de su escalera.
const hoyISO = () => new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Santiago' })

/** Horómetro GPS al cierre de ese día, o del último día anterior con lectura. */
function horometroDelDia(horasDia: HorasDia[], dia: string): number | null {
  let v: number | null = null
  for (const d of horasDia) {
    if (d.fecha.slice(0, 10) > dia) break
    if (d.horometro_fin != null) v = d.horometro_fin
  }
  return v
}

// [MIG641] Corregir el horómetro con lo que marca el tablero: se fija en
// Radicom (el GPS sigue contando desde ahí) y en SICOM con su historial.
// Por defecto la próxima mantención se recalcula contra el valor corregido;
// «mantener lo que falta» mueve también las bases de las pautas.
function CorregirHorometro({ equipo }: { equipo: EquipoHoras }) {
  const qc = useQueryClient()
  const toast = useToast()
  const [abierto, setAbierto] = useState(false)
  const [horas, setHoras] = useState('')
  const [km, setKm] = useState('')
  const [nota, setNota] = useState('')
  const [moverBases, setMoverBases] = useState(false)

  const lectura = useQuery({
    queryKey: ['horometro-leer', equipo.activo_id],
    queryFn: () => leerHorometro(equipo.activo_id),
    enabled: abierto,
    staleTime: 0,
    retry: false,
  })
  const { data: pautas } = useQuery({
    queryKey: ['pautas-equipo', equipo.activo_id],
    queryFn: () => getPautasEquipo(equipo.activo_id),
    enabled: abierto,
  })

  const corregir = useMutation({
    mutationFn: () => corregirHorometro({
      activoId: equipo.activo_id,
      horas: horas.trim() ? Number(horas.replace(',', '.')) : null,
      km: km.trim() ? Number(km.replace(/\./g, '').replace(',', '.')) : null,
      moverBases, nota,
    }),
    onSuccess: (r) => {
      const dest = r.fuente === 'radicom' ? 'Radicom y SICOM' : 'SICOM'
      toast.success(`Horómetro corregido en ${dest}${r.bases_movidas ? `; ${r.bases_movidas} pauta(s) movidas` : ''}`)
      if (r.aviso) toast.warning(r.aviso)
      setAbierto(false); setHoras(''); setKm(''); setNota(''); setMoverBases(false)
      for (const k of ['equipo-horas', 'pautas-equipo', 'equipo-horas-dia', 'horometro-leer', 'equipo-consumo-dia']) {
        qc.invalidateQueries({ queryKey: [k] })
      }
    },
    onError: (e: Error) => toast.error(e.message),
  })

  const l = lectura.data
  const nuevo = horas.trim() ? Number(horas.replace(',', '.')) : null
  // GPS en este instante; sin GPS, lo que tiene SICOM.
  const gpsAhora = l?.fuente === 'radicom' ? (l.horas_gps ?? l.horas_sicom) : l?.horas_sicom ?? null

  // La pauta que toca primero, hoy y con cada opción.
  const proxima = (horometro: number | null, corrimiento: number) => {
    if (horometro == null || !pautas?.length) return null
    let mejor: { nombre: string; faltan: number } | null = null
    for (const p of pautas) {
      if (!p.ultima_ejecucion_horas) continue
      const faltan = p.frecuencia_horas - (horometro - (p.ultima_ejecucion_horas + corrimiento))
      if (!mejor || faltan < mejor.faltan) mejor = { nombre: p.nombre, faltan }
    }
    return mejor
  }
  const hoy = proxima(equipo.horometro, 0)
  const conNuevo = nuevo != null && nuevo > 0
    ? proxima(nuevo, moverBases && gpsAhora != null ? nuevo - gpsAhora : 0) : null

  if (!abierto) {
    return (
      <div className="mt-4 flex justify-end">
        <Button size="sm" variant="outline" onClick={() => setAbierto(true)}>
          <Gauge className="mr-1 h-4 w-4" /> Corregir horómetro
        </Button>
      </div>
    )
  }

  const renault = l?.fuente === 'renault'
  const valido = !renault && !!l && ((nuevo != null && nuevo > 0) || km.trim() !== '') && nota.trim().length >= 5

  return (
    <Card className="mt-4 border-amber-200">
      <CardHeader className="pb-1">
        <CardTitle className="flex items-center gap-2 text-sm"><Gauge className="h-4 w-4" /> Corregir horómetro</CardTitle>
      </CardHeader>
      <CardContent className="text-sm">
        {lectura.isLoading ? <div className="flex justify-center py-4"><Spinner /></div>
          : lectura.error ? <div className="text-red-600">{(lectura.error as Error).message}</div>
          : renault ? (
            <p className="text-gray-600">Este camión toma el horómetro de su computador (GPS de fábrica Renault): no se corrige.</p>
          ) : l && (
            <>
              <div className="mb-3 grid grid-cols-2 gap-2 sm:grid-cols-4">
                <Dato label="SICOM" valor={`${n1(l.horas_sicom)} h`} />
                <Dato label={l.fuente === 'radicom' ? 'Radicom ahora' : 'GPS'}
                      valor={l.fuente === 'radicom' ? `${n1(l.horas_gps)} h` : 'sin GPS'} />
                <Dato label="Km SICOM" valor={n0(l.km_sicom)} />
                <Dato label={l.fuente === 'radicom' ? 'Km Radicom' : 'Km GPS'}
                      valor={l.fuente === 'radicom' ? n0(l.km_gps) : '—'} />
              </div>
              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                <label className="text-xs text-gray-600">Horómetro del tablero (h)
                  <Input inputMode="decimal" value={horas} onChange={(e) => setHoras(e.target.value)} />
                </label>
                <label className="text-xs text-gray-600">Odómetro del tablero (km, opcional)
                  <Input inputMode="numeric" value={km} onChange={(e) => setKm(e.target.value)} />
                </label>
              </div>
              <label className="mt-2 block text-xs text-gray-600">De dónde sale el dato
                <Input value={nota} onChange={(e) => setNota(e.target.value)}
                       placeholder="Ej.: foto tablero recepción 22-10, OS 3410" />
              </label>

              <div className="mt-3 space-y-1 text-xs">
                <label className="flex items-start gap-2">
                  <input type="radio" className="mt-0.5" checked={!moverBases} onChange={() => setMoverBases(false)} />
                  <span><b>Recalcular la próxima mantención</b> con el horómetro corregido (las bases de las pautas no cambian).</span>
                </label>
                <label className="flex items-start gap-2">
                  <input type="radio" className="mt-0.5" checked={moverBases} onChange={() => setMoverBases(true)} />
                  <span><b>Mantener lo que falta</b>: las bases se mueven en la misma diferencia (úsalo si las bases se tomaron del GPS).</span>
                </label>
              </div>

              {hoy && (
                <div className="mt-3 rounded-md bg-gray-50 p-2 text-xs">
                  <div>Próxima hoy: <b>{hoy.nombre}</b> · {hoy.faltan <= 0 ? `vencida por ${n0(-hoy.faltan)} h` : `faltan ${n0(hoy.faltan)} h`}</div>
                  {conNuevo && (
                    <div>Con la corrección: <b>{conNuevo.nombre}</b> · {conNuevo.faltan <= 0
                      ? <span className="text-red-600">vencida por {n0(-conNuevo.faltan)} h</span>
                      : `faltan ${n0(conNuevo.faltan)} h`}</div>
                  )}
                </div>
              )}
              <p className="mt-2 text-[11px] text-gray-500">
                {l.fuente === 'radicom'
                  ? 'Se fija en Radicom y el GPS sigue contando desde ese valor. El historial de horas por día se ajusta a la escala nueva.'
                  : 'Equipo sin GPS: se corrige solo en SICOM.'}
              </p>
            </>
          )}
        <div className="mt-3 flex justify-end gap-2">
          <Button size="sm" variant="ghost" onClick={() => setAbierto(false)}>Cancelar</Button>
          {!renault && (
            <Button size="sm" variant="primary" disabled={!valido} loading={corregir.isPending}
                    onClick={() => corregir.mutate()}>Corregir</Button>
          )}
        </div>
      </CardContent>
    </Card>
  )
}

// [MIG642] Las próximas de la escalera y elegir cuál toca: las bases se
// reacomodan para que el ciclo siga en orden (lib/escalera-mantencion.ts).
function CambiarProximaEquipo({ equipo }: { equipo: EquipoHoras }) {
  const { data: pautas } = useQuery({
    queryKey: ['pautas-equipo', equipo.activo_id],
    queryFn: () => getPautasEquipo(equipo.activo_id),
  })
  return pautas?.length ? <CambiarProxima equipo={equipo} pautas={pautas} /> : null
}

function CambiarProxima({ equipo, pautas }: { equipo: EquipoHoras; pautas: PautaEquipo[] }) {
  const qc = useQueryClient()
  const toast = useToast()
  const [abierto, setAbierto] = useState(false)
  const [planId, setPlanId] = useState('')
  const [horas, setHoras] = useState('')
  const [nota, setNota] = useState('')

  const actuales = useMemo(() => secuenciaEscalera(pautas.map((p) => ({
    nombre: p.nombre, frecuencia_horas: p.frecuencia_horas, base: p.ultima_ejecucion_horas || null,
  }))), [pautas])

  const x = Number(horas.replace(',', '.'))
  const nuevas = useMemo(
    () => (planId && x > 0 ? reprogramarEscalera(pautas, planId, x) : null),
    [pautas, planId, x],
  )
  const limite = nuevas && equipo.horometro != null ? limiteProxima(nuevas, x, equipo.horometro) : null
  const fueraDeLimite = limite != null && x > limite + 0.05
  const secuencia = nuevas ? secuenciaEscalera(nuevas.map((p) => ({
    nombre: p.nombre, frecuencia_horas: p.frecuencia_horas,
    base: p.base_nueva ?? (p.ultima_ejecucion_horas || null),
  }))) : []

  const guardar = useMutation({
    mutationFn: () => reprogramarEscaleraEquipo({ planId, horas: x, nota }),
    onSuccess: (r) => {
      toast.success(`Escalera reprogramada: ${r.pautas} pauta(s) actualizadas`)
      setAbierto(false); setPlanId(''); setHoras(''); setNota('')
      for (const k of ['equipo-horas', 'pautas-equipo', 'planes-mantenimiento', 'plan-mantenimiento']) {
        qc.invalidateQueries({ queryKey: [k] })
      }
    },
    onError: (e: Error) => toast.error(e.message),
  })

  const elegir = (id: string) => {
    setPlanId(id)
    if (!horas && equipo.horometro != null) setHoras(String(Math.round(equipo.horometro)))
  }
  const valido = !!planId && x > 0 && !fueraDeLimite && nota.trim().length >= 5
  const lista = (s: { horas: number; nombre: string }[]) =>
    s.map((v) => `${n0(v.horas)} h ${v.nombre.replace(/^.* - /, '')}`).join(' → ')

  return (
    <div className="mt-3 text-xs">
      {actuales.length > 0 && (
        <div className="text-gray-600"><b>Próximas:</b> {lista(actuales)}</div>
      )}
      {!abierto ? (
        <div className="mt-2 flex justify-end">
          <Button size="sm" variant="outline" onClick={() => setAbierto(true)}>Cambiar próxima mantención</Button>
        </div>
      ) : (
        <div className="mt-2 rounded-lg border border-amber-200 bg-amber-50 p-3">
          <div className="mb-2 text-sm font-medium">¿Cuál es la próxima mantención?</div>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <label className="text-gray-600">Pauta
              <select className="mt-1 h-10 w-full rounded-md border border-gray-300 bg-white px-2 text-sm"
                      value={planId} onChange={(e) => elegir(e.target.value)}>
                <option value="">Elegir…</option>
                {pautas.map((p) => <option key={p.id} value={p.id}>{p.nombre}</option>)}
              </select>
            </label>
            <label className="text-gray-600">Toca a las (h)
              <Input inputMode="decimal" value={horas} onChange={(e) => setHoras(e.target.value)} />
              <span className="text-[11px] text-gray-500">
                Horómetro actual {n1(equipo.horometro)} h{limite != null ? ` · máximo ${n1(limite)} h` : ''}
              </span>
            </label>
          </div>
          <label className="mt-2 block text-gray-600">Motivo
            <Input value={nota} onChange={(e) => setNota(e.target.value)}
                   placeholder="Ej.: según libro del taller la última fue SM1" />
          </label>

          {nuevas && (
            <div className="mt-3 rounded-md bg-white p-2">
              {fueraDeLimite ? (
                <div className="text-red-600">
                  Con el horómetro actual, la próxima puede tocar a lo más a las {n1(limite)} h.
                </div>
              ) : (
                <>
                  <div><b>Quedaría:</b> {lista(secuencia)}</div>
                  <table className="mt-2 w-full">
                    <tbody>
                      {nuevas.map((p) => (
                        <tr key={p.id} className="border-t">
                          <td className="py-1 pr-2">{p.nombre}</td>
                          <td className="py-1 pr-2 text-right text-gray-500">base {n0(p.ultima_ejecucion_horas)} h</td>
                          <td className="py-1 text-right">
                            {p.base_nueva == null ? <span className="text-gray-400">no cambia</span> : <b>→ {n0(p.base_nueva)} h</b>}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </>
              )}
            </div>
          )}
          <div className="mt-2 flex justify-end gap-2">
            <Button size="sm" variant="ghost" onClick={() => setAbierto(false)}>Cancelar</Button>
            <Button size="sm" variant="primary" disabled={!valido} loading={guardar.isPending}
                    onClick={() => guardar.mutate()}>Guardar</Button>
          </div>
        </div>
      )}
    </div>
  )
}

function PautasEquipo({ equipo, horasDia }: { equipo: EquipoHoras; horasDia: HorasDia[] }) {
  const qc = useQueryClient()
  const toast = useToast()
  const [sel, setSel] = useState<PautaEquipo | null>(null)
  const [dia, setDia] = useState(hoyISO())
  const [horas, setHoras] = useState('')
  const [km, setKm] = useState('')
  const [nota, setNota] = useState('')

  const { data: pautas, isLoading } = useQuery({
    queryKey: ['pautas-equipo', equipo.activo_id],
    queryFn: () => getPautasEquipo(equipo.activo_id),
  })

  const proponer = (d: string) => {
    const h = horometroDelDia(horasDia, d) ?? equipo.horometro
    setHoras(h == null ? '' : String(h))
  }
  const abrir = (p: PautaEquipo) => {
    const d = hoyISO()
    setSel(p); setDia(d); setKm(''); setNota('')
    proponer(d)
  }

  const registrar = useMutation({
    mutationFn: () => registrarPreventivaRealizada({
      planId: sel!.id, fecha: dia, horas: Number(horas.replace(',', '.')),
      km: km.trim() ? Number(km.replace(/\./g, '').replace(',', '.')) : null, nota,
    }),
    onSuccess: (r) => {
      toast.success(r.absorbidos > 0
        ? `${r.plan} registrada; ${r.absorbidos} pauta(s) menor(es) quedan al día`
        : `${r.plan} registrada`)
      setSel(null)
      for (const k of ['equipo-horas', 'pautas-equipo', 'planes-mantenimiento', 'plan-mantenimiento']) {
        qc.invalidateQueries({ queryKey: [k] })
      }
    },
    onError: (e: Error) => toast.error(e.message),
  })

  const gpsDelDia = horometroDelDia(horasDia, dia)
  const horasNum = Number(horas.replace(',', '.'))
  const valido = !!sel && !!dia && horasNum > 0 && nota.trim().length >= 5

  return (
    <Card className="mt-4">
      <CardHeader className="pb-1">
        <CardTitle className="flex items-center gap-2 text-sm"><Wrench className="h-4 w-4" /> Pautas por horas</CardTitle>
      </CardHeader>
      <CardContent>
        {isLoading ? <div className="flex justify-center py-6"><Spinner /></div>
          : !pautas?.length ? <div className="py-4 text-center text-sm text-gray-500">El equipo no tiene pautas por horas activas.</div>
          : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-left text-xs text-gray-500">
                    <th className="py-1 pr-2">Pauta</th>
                    <th className="py-1 pr-2 text-right">Cada</th>
                    <th className="py-1 pr-2">Última</th>
                    <th className="py-1 pr-2 text-right">Faltan</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {pautas.map((p) => {
                    const faltan = p.ultima_ejecucion_horas && equipo.horometro != null
                      ? p.frecuencia_horas - (equipo.horometro - p.ultima_ejecucion_horas) : null
                    return (
                      <tr key={p.id} className="border-b last:border-0">
                        <td className="py-1.5 pr-2">{p.nombre}</td>
                        <td className="py-1.5 pr-2 text-right">{n0(p.frecuencia_horas)} h</td>
                        <td className="py-1.5 pr-2 whitespace-nowrap">
                          {fecha(p.ultima_ejecucion_fecha)} · {p.ultima_ejecucion_horas ? `${n0(p.ultima_ejecucion_horas)} h` : 'sin horómetro'}
                        </td>
                        <td className={`py-1.5 pr-2 text-right font-medium ${faltan != null && faltan <= 0 ? 'text-red-600' : ''}`}>
                          {faltan == null ? '—' : `${n0(faltan)} h`}
                        </td>
                        <td className="py-1.5 text-right">
                          <Button size="sm" variant="ghost" onClick={() => abrir(p)}>Registrar hecha</Button>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}


        {sel && (
          <div className="mt-3 rounded-lg border border-blue-200 bg-blue-50 p-3">
            <div className="mb-2 text-sm font-medium">Registrar «{sel.nombre}» como realizada</div>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
              <label className="text-xs text-gray-600">Fecha
                <Input type="date" value={dia} max={hoyISO()}
                       onChange={(e) => { setDia(e.target.value); proponer(e.target.value) }} />
              </label>
              <label className="text-xs text-gray-600">Horómetro (h)
                <Input inputMode="decimal" value={horas} onChange={(e) => setHoras(e.target.value)} />
                <span className="text-[11px] text-gray-500">
                  {gpsDelDia != null ? `GPS ese día: ${n1(gpsDelDia)} h` : `Actual: ${n1(equipo.horometro)} h`}
                </span>
              </label>
              <label className="text-xs text-gray-600">Km (opcional)
                <Input inputMode="numeric" value={km} onChange={(e) => setKm(e.target.value)}
                       placeholder={equipo.odometro != null ? `actual ${n0(equipo.odometro)}` : ''} />
              </label>
            </div>
            <label className="mt-2 block text-xs text-gray-600">De dónde sale el dato
              <Input value={nota} onChange={(e) => setNota(e.target.value)}
                     placeholder="Ej.: OS 3410 taller Coquimbo, OT-202610-00016" />
            </label>
            <p className="mt-2 text-[11px] text-gray-500">
              Las pautas menores de la misma escalera quedan al día con esta fecha y horómetro (si la suya es anterior).
            </p>
            <div className="mt-2 flex justify-end gap-2">
              <Button size="sm" variant="ghost" onClick={() => setSel(null)}>Cancelar</Button>
              <Button size="sm" variant="primary" disabled={!valido} loading={registrar.isPending}
                      onClick={() => registrar.mutate()}>Guardar</Button>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
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
