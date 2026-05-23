'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import {
  Truck, Wrench, AlertTriangle, MapPin, Radio, BarChart3, CheckCircle2,
  XCircle, Activity, ShieldAlert, Calendar, ArrowRight, FileText, Layers,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Input } from '@/components/ui/input'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  useFlotaDashboard, useFlotaKpiResumen, useFlotaAlertasResumen,
} from '@/hooks/use-flota-dashboard'
import type { FlotaDashboardActivo } from '@/lib/services/flota-dashboard'

type TabId = 'overview' | 'activos' | 'gps' | 'alertas'

export default function FlotaDashboardHubPage() {
  useRequireAuth()
  const [tab, setTab] = useState<TabId>('overview')
  const [filtro, setFiltro] = useState('')
  const [filtroEstado, setFiltroEstado] = useState<string>('')
  const [filtroPm, setFiltroPm] = useState<string>('')

  const { data: kpi, isLoading: loadKpi } = useFlotaKpiResumen()
  const { data: activos, isLoading: loadActivos } = useFlotaDashboard()
  const { data: alertas } = useFlotaAlertasResumen()

  const activosFiltrados = useMemo(() => {
    let rows = activos ?? []
    if (filtro) {
      const q = filtro.toLowerCase()
      rows = rows.filter((a) =>
        a.activo_codigo.toLowerCase().includes(q)
        || (a.patente ?? '').toLowerCase().includes(q)
        || (a.activo_nombre ?? '').toLowerCase().includes(q)
        || (a.contrato_cliente ?? '').toLowerCase().includes(q),
      )
    }
    if (filtroEstado) rows = rows.filter((a) => a.estado_comercial === filtroEstado)
    if (filtroPm)     rows = rows.filter((a) => a.pm_status === filtroPm)
    return rows
  }, [activos, filtro, filtroEstado, filtroPm])

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold">
            <Truck className="h-6 w-6 text-blue-700" />
            Flota — Dashboard unificado
          </h1>
          <p className="text-sm text-muted-foreground">
            Vista única de todos los activos: estado, mantenimiento, GPS y geocercas.
          </p>
        </div>
        <div className="flex gap-2 flex-wrap">
          <Link href="/dashboard/flota"><Button variant="outline" size="sm"><Layers className="h-4 w-4 mr-1" />Maestro</Button></Link>
          <Link href="/dashboard/flota/mapa"><Button variant="outline" size="sm"><MapPin className="h-4 w-4 mr-1" />Mapa</Button></Link>
          <Link href="/dashboard/mantenimiento/plan-semanal-taller"><Button variant="outline" size="sm"><Wrench className="h-4 w-4 mr-1" />Taller</Button></Link>
          <Link href="/dashboard/reporte-diario"><Button size="sm" className="bg-blue-600 hover:bg-blue-700"><FileText className="h-4 w-4 mr-1" />Reporte diario</Button></Link>
        </div>
      </div>

      {/* KPIs principales */}
      {loadKpi ? (
        <div className="flex justify-center py-10"><Spinner /></div>
      ) : kpi ? (
        <>
          <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3">
            <Kpi icon={<Truck className="h-4 w-4" />} label="Total flota"   valor={kpi.total_activos} />
            <Kpi icon={<Activity className="h-4 w-4" />} label="Arrendados"    valor={kpi.arrendados}        color="text-green-700" />
            <Kpi icon={<Activity className="h-4 w-4" />} label="Disponibles"   valor={kpi.disponibles}       color="text-amber-700" />
            <Kpi icon={<Wrench className="h-4 w-4" />} label="En mantención" valor={kpi.en_mantenimiento}  color="text-orange-700" />
            <Kpi icon={<XCircle className="h-4 w-4" />} label="Fuera serv."   valor={kpi.fuera_servicio}    color="text-red-700" />
            <Kpi icon={<AlertTriangle className="h-4 w-4" />} label="Alertas críticas" valor={kpi.alertas_criticas_total} color={kpi.alertas_criticas_total > 0 ? 'text-red-700' : 'text-gray-500'} />
          </div>

          {/* Tabs */}
          <div className="flex gap-1 border-b">
            <TabBtn active={tab === 'overview'} onClick={() => setTab('overview')}>Resumen</TabBtn>
            <TabBtn active={tab === 'activos'} onClick={() => setTab('activos')}>Activos ({activos?.length ?? 0})</TabBtn>
            <TabBtn active={tab === 'gps'} onClick={() => setTab('gps')}>GPS / geocercas</TabBtn>
            <TabBtn active={tab === 'alertas'} onClick={() => setTab('alertas')}>Alertas ({kpi.alertas_activas_total})</TabBtn>
          </div>

          {tab === 'overview' && <OverviewTab kpi={kpi} />}
          {tab === 'activos' && (
            <ActivosTab
              activos={activosFiltrados}
              loading={loadActivos}
              filtro={filtro} setFiltro={setFiltro}
              filtroEstado={filtroEstado} setFiltroEstado={setFiltroEstado}
              filtroPm={filtroPm} setFiltroPm={setFiltroPm}
            />
          )}
          {tab === 'gps' && <GpsTab activos={activos ?? []} kpi={kpi} />}
          {tab === 'alertas' && <AlertasTab alertas={alertas ?? []} />}
        </>
      ) : (
        <div className="text-center text-sm text-gray-500 py-10">Sin datos.</div>
      )}
    </div>
  )
}

// ── Subcomponentes ──────────────────────────────────────────────────────────

function Kpi({ icon, label, valor, color }: { icon: React.ReactNode; label: string; valor: number | string; color?: string }) {
  return (
    <div className="rounded-lg border bg-white p-3">
      <div className="flex items-center justify-between">
        <div className="text-[10px] uppercase tracking-wide text-gray-500">{label}</div>
        <div className="text-gray-400">{icon}</div>
      </div>
      <div className={`text-2xl font-bold tabular-nums mt-1 ${color ?? 'text-gray-900'}`}>{valor}</div>
    </div>
  )
}

function TabBtn({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button onClick={onClick}
            className={`px-3 py-2 text-sm font-medium border-b-2 transition-colors ${
              active ? 'border-blue-600 text-blue-700' : 'border-transparent text-gray-500 hover:text-gray-700'
            }`}>{children}</button>
  )
}

function OverviewTab({ kpi }: { kpi: any }) {
  return (
    <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
      {/* PM */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base flex items-center gap-2">
            <Wrench className="h-4 w-4" /> Plan preventivo
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm">
          <Line label="Al día" valor={kpi.pm_al_dia} color="text-green-700" />
          <Line label="Próximos 7 días" valor={kpi.pm_proximos_7d} color="text-amber-700" />
          <Line label="Vencidos" valor={kpi.pm_vencidos} color={kpi.pm_vencidos > 0 ? 'text-red-700' : 'text-gray-500'} bold />
          <Line label="Sin planes" valor={kpi.pm_sin_planes} color="text-gray-500" />
          <Line label="Cumplimiento %" valor={kpi.pm_cumplimiento_pct ? `${kpi.pm_cumplimiento_pct}%` : '—'} color="text-blue-700" bold />
          <Link href="/dashboard/mantenimiento/plan-semanal-taller"
                className="text-xs text-blue-700 underline mt-2 inline-flex items-center gap-1">
            Programar en Kanban <ArrowRight className="h-3 w-3" />
          </Link>
        </CardContent>
      </Card>

      {/* GPS */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base flex items-center gap-2">
            <Radio className="h-4 w-4" /> GPS
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm">
          <Line label="Mapeados" valor={kpi.gps_mapeados} color="text-green-700" />
          <Line label="Sin GPS" valor={kpi.sin_gps} color="text-gray-500" />
          <Line label="En ruta" valor={kpi.gps_en_ruta} color="text-blue-700" />
          <Line label="Detenido motor ON" valor={kpi.gps_detenido_motor_on} color="text-amber-700" />
          <Line label="Sin señal > 24h" valor={kpi.gps_sin_senal_24h} color={kpi.gps_sin_senal_24h > 0 ? 'text-red-700' : 'text-gray-500'} bold />
          <Link href="/dashboard/flota/mapa"
                className="text-xs text-blue-700 underline mt-2 inline-flex items-center gap-1">
            Ver mapa en vivo <ArrowRight className="h-3 w-3" />
          </Link>
        </CardContent>
      </Card>

      {/* Geocercas + OT correctivas */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base flex items-center gap-2">
            <MapPin className="h-4 w-4" /> Geocercas / OT
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm">
          <Line label="En zona esperada" valor={kpi.en_zona_esperada} color="text-green-700" />
          <Line label="Fuera de zona" valor={kpi.fuera_zona_esperada} color={kpi.fuera_zona_esperada > 0 ? 'text-red-700' : 'text-gray-500'} bold />
          <Line label="Sin dato de zona" valor={kpi.sin_dato_zona} color="text-gray-500" />
          <div className="border-t pt-2 mt-2">
            <Line label="OT correctivas abiertas" valor={kpi.correctivas_abiertas_total} color="text-amber-700" />
          </div>
          <Link href="/dashboard/admin/geocercas"
                className="text-xs text-blue-700 underline mt-2 inline-flex items-center gap-1">
            Gestionar geocercas <ArrowRight className="h-3 w-3" />
          </Link>
        </CardContent>
      </Card>
    </div>
  )
}

function Line({ label, valor, color, bold }: { label: string; valor: any; color?: string; bold?: boolean }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-gray-600 text-xs">{label}</span>
      <span className={`tabular-nums ${color ?? 'text-gray-900'} ${bold ? 'font-bold' : ''}`}>{valor}</span>
    </div>
  )
}

function ActivosTab({ activos, loading, filtro, setFiltro, filtroEstado, setFiltroEstado, filtroPm, setFiltroPm }: {
  activos: FlotaDashboardActivo[]
  loading: boolean
  filtro: string; setFiltro: (s: string) => void
  filtroEstado: string; setFiltroEstado: (s: string) => void
  filtroPm: string; setFiltroPm: (s: string) => void
}) {
  return (
    <Card>
      <CardContent className="p-3 space-y-2">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
          <Input placeholder="Buscar por código, patente, cliente..." value={filtro}
                 onChange={(e) => setFiltro(e.target.value)} />
          <select value={filtroEstado} onChange={(e) => setFiltroEstado(e.target.value)}
                  className="w-full rounded border px-2 py-1.5 text-sm">
            <option value="">Todos los estados comerciales</option>
            <option value="arrendado">Arrendado</option>
            <option value="disponible">Disponible</option>
            <option value="uso_interno">Uso interno</option>
            <option value="leasing">Leasing</option>
            <option value="en_recepcion">En recepción</option>
            <option value="en_venta">En venta</option>
          </select>
          <select value={filtroPm} onChange={(e) => setFiltroPm(e.target.value)}
                  className="w-full rounded border px-2 py-1.5 text-sm">
            <option value="">Todos los estados PM</option>
            <option value="al_dia">PM al día</option>
            <option value="proximo">PM próximo (7d)</option>
            <option value="vencido">PM vencido</option>
            <option value="sin_planes">Sin planes</option>
          </select>
        </div>
        {loading ? (
          <div className="flex justify-center py-10"><Spinner /></div>
        ) : (
          <div className="overflow-x-auto max-h-[70vh]">
            <table className="w-full text-xs">
              <thead className="sticky top-0 bg-gray-50">
                <tr>
                  <th className="px-2 py-2 text-left">Activo</th>
                  <th className="px-2 py-2 text-left">Cliente / Faena</th>
                  <th className="px-2 py-2 text-center">Estado</th>
                  <th className="px-2 py-2 text-center">PM</th>
                  <th className="px-2 py-2 text-center">OT corr.</th>
                  <th className="px-2 py-2 text-center">GPS</th>
                  <th className="px-2 py-2 text-center">Zona</th>
                  <th className="px-2 py-2 text-center">Alertas</th>
                </tr>
              </thead>
              <tbody>
                {activos.map((a) => (
                  <tr key={a.activo_id} className="border-t hover:bg-gray-50">
                    <td className="px-2 py-1.5">
                      <Link href={`/dashboard/activos/${a.activo_id}`} className="text-blue-700 hover:underline font-mono">
                        {a.activo_codigo}
                      </Link>
                      {a.patente && <span className="ml-1 text-gray-500">· {a.patente}</span>}
                      <div className="text-[10px] text-gray-500">{a.modelo_marca} {a.modelo_nombre}</div>
                    </td>
                    <td className="px-2 py-1.5 text-gray-700">
                      {a.contrato_cliente ?? '—'}
                      {a.faena_nombre && <div className="text-[10px] text-gray-500">{a.faena_nombre}</div>}
                    </td>
                    <td className="px-2 py-1.5 text-center">
                      <BadgeEstado estado={a.estado_comercial} />
                    </td>
                    <td className="px-2 py-1.5 text-center">
                      <BadgePm status={a.pm_status} />
                      {a.pm_planes_vencidos > 0 && <div className="text-[9px] text-red-700">{a.pm_planes_vencidos} venc.</div>}
                    </td>
                    <td className="px-2 py-1.5 text-center">
                      {a.ots_correctivas_abiertas > 0 ? (
                        <span className="rounded bg-amber-100 text-amber-800 px-1.5 py-0.5 font-bold">
                          {a.ots_correctivas_abiertas}
                        </span>
                      ) : <span className="text-gray-300">—</span>}
                    </td>
                    <td className="px-2 py-1.5 text-center">
                      <BadgeGps estado={a.gps_estado_pin} />
                    </td>
                    <td className="px-2 py-1.5 text-center">
                      {a.geocerca_esperada_id == null ? <span className="text-gray-300">—</span>
                       : a.en_zona_esperada === true ? <CheckCircle2 className="h-4 w-4 text-green-600 mx-auto" />
                       : a.en_zona_esperada === false ? <XCircle className="h-4 w-4 text-red-600 mx-auto" />
                       : <span className="text-gray-300">?</span>}
                    </td>
                    <td className="px-2 py-1.5 text-center">
                      {a.alertas_criticas > 0 && (
                        <span className="rounded bg-red-100 text-red-800 px-1.5 py-0.5 font-bold mr-1">
                          {a.alertas_criticas}
                        </span>
                      )}
                      {a.alertas_activas > a.alertas_criticas && (
                        <span className="rounded bg-amber-100 text-amber-800 px-1.5 py-0.5">
                          {a.alertas_activas - a.alertas_criticas}
                        </span>
                      )}
                      {a.alertas_activas === 0 && <span className="text-gray-300">—</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </CardContent>
    </Card>
  )
}

function BadgeEstado({ estado }: { estado: string }) {
  const map: Record<string, string> = {
    arrendado: 'bg-green-100 text-green-800',
    disponible: 'bg-amber-100 text-amber-800',
    uso_interno: 'bg-cyan-100 text-cyan-800',
    leasing: 'bg-purple-100 text-purple-800',
    en_recepcion: 'bg-blue-100 text-blue-800',
    en_venta: 'bg-red-100 text-red-800',
    comprometido: 'bg-orange-100 text-orange-800',
  }
  return <span className={`rounded px-1.5 py-0.5 text-[10px] font-bold ${map[estado] ?? 'bg-gray-100 text-gray-700'}`}>{estado}</span>
}

function BadgePm({ status }: { status: string }) {
  const map: Record<string, [string, string]> = {
    al_dia: ['Al día', 'bg-green-100 text-green-700'],
    proximo: ['Próx.', 'bg-amber-100 text-amber-700'],
    vencido: ['Vencido', 'bg-red-100 text-red-700'],
    sin_planes: ['Sin PM', 'bg-gray-100 text-gray-500'],
  }
  const [label, color] = map[status] ?? ['—', 'bg-gray-100 text-gray-500']
  return <span className={`rounded px-1.5 py-0.5 text-[10px] font-bold ${color}`}>{label}</span>
}

function BadgeGps({ estado }: { estado: string }) {
  const map: Record<string, [string, string]> = {
    en_ruta: ['En ruta', 'bg-blue-100 text-blue-700'],
    detenido_motor_on: ['Det. ON', 'bg-amber-100 text-amber-700'],
    detenido: ['Detenido', 'bg-gray-200 text-gray-700'],
    offline: ['Offline', 'bg-orange-100 text-orange-700'],
    sin_senal_24h: ['Sin señal', 'bg-red-100 text-red-700'],
    sin_datos: ['Sin datos', 'bg-gray-100 text-gray-500'],
    sin_gps: ['Sin GPS', 'bg-gray-100 text-gray-400'],
  }
  const [label, color] = map[estado] ?? ['—', 'bg-gray-100 text-gray-500']
  return <span className={`rounded px-1.5 py-0.5 text-[10px] font-bold ${color}`}>{label}</span>
}

function GpsTab({ activos, kpi }: { activos: FlotaDashboardActivo[]; kpi: any }) {
  const fueraDeZona = activos.filter((a) => a.en_zona_esperada === false)
  const sinSenal = activos.filter((a) => a.gps_estado_pin === 'sin_senal_24h' || a.gps_estado_pin === 'offline')
  const sinGps = activos.filter((a) => a.gps_estado_pin === 'sin_gps')

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <CardListaActivos
          titulo={`Fuera de zona esperada (${fueraDeZona.length})`}
          icono={<XCircle className="h-4 w-4 text-red-600" />}
          activos={fueraDeZona}
          empty="Todos los activos están en su zona esperada"
          campoSecundario="geocerca_esperada"
        />
        <CardListaActivos
          titulo={`Sin señal / offline (${sinSenal.length})`}
          icono={<Radio className="h-4 w-4 text-orange-600" />}
          activos={sinSenal}
          empty="Todos los GPS reportando"
          campoSecundario="gps_estado_pin"
        />
        <CardListaActivos
          titulo={`Sin GPS instalado (${sinGps.length})`}
          icono={<ShieldAlert className="h-4 w-4 text-gray-500" />}
          activos={sinGps}
          empty="Toda la flota con GPS"
          campoSecundario={null}
        />
      </div>
    </div>
  )
}

function CardListaActivos({ titulo, icono, activos, empty, campoSecundario }: {
  titulo: string
  icono: React.ReactNode
  activos: FlotaDashboardActivo[]
  empty: string
  campoSecundario: keyof FlotaDashboardActivo | null
}) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm flex items-center gap-2">{icono} {titulo}</CardTitle>
      </CardHeader>
      <CardContent className="p-2 max-h-[60vh] overflow-y-auto">
        {activos.length === 0 ? (
          <div className="text-xs text-green-700 p-3 text-center">
            <CheckCircle2 className="h-5 w-5 mx-auto mb-1" /> {empty}
          </div>
        ) : (
          <ul className="space-y-1">
            {activos.map((a) => (
              <li key={a.activo_id} className="text-xs border-b last:border-0 py-1.5">
                <Link href={`/dashboard/activos/${a.activo_id}`}
                      className="font-mono font-bold text-blue-700 hover:underline">
                  {a.activo_codigo}
                </Link>
                {a.patente && <span className="ml-1 text-gray-500">· {a.patente}</span>}
                <div className="text-[10px] text-gray-500">
                  {a.contrato_cliente ?? '—'}
                  {campoSecundario && a[campoSecundario] ? ` · ${String(a[campoSecundario])}` : ''}
                </div>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}

function AlertasTab({ alertas }: { alertas: any[] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Activos con alertas activas</CardTitle>
      </CardHeader>
      <CardContent className="p-0 overflow-x-auto">
        {alertas.length === 0 ? (
          <div className="p-8 text-center text-sm text-green-700">
            <CheckCircle2 className="h-8 w-8 mx-auto mb-2" />
            No hay alertas activas en la flota.
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-3 py-2 text-left">Activo</th>
                <th className="px-3 py-2 text-right">Críticas</th>
                <th className="px-3 py-2 text-right">Warnings</th>
                <th className="px-3 py-2 text-right">Info</th>
                <th className="px-3 py-2 text-left">Tipos</th>
                <th className="px-3 py-2 text-left">Última</th>
              </tr>
            </thead>
            <tbody>
              {alertas.map((a) => (
                <tr key={a.activo_id} className="border-t hover:bg-gray-50">
                  <td className="px-3 py-2">
                    <Link href={`/dashboard/activos/${a.activo_id}`} className="font-mono text-blue-700 hover:underline">
                      {a.activo_codigo}
                    </Link>
                    {a.patente && <span className="ml-1 text-gray-500">· {a.patente}</span>}
                  </td>
                  <td className="px-3 py-2 text-right">
                    {a.criticas > 0 ? <span className="rounded bg-red-100 text-red-800 px-2 py-0.5 font-bold">{a.criticas}</span> : <span className="text-gray-300">—</span>}
                  </td>
                  <td className="px-3 py-2 text-right">
                    {a.warnings > 0 ? <span className="rounded bg-amber-100 text-amber-800 px-2 py-0.5">{a.warnings}</span> : <span className="text-gray-300">—</span>}
                  </td>
                  <td className="px-3 py-2 text-right">{a.infos || '—'}</td>
                  <td className="px-3 py-2 text-xs text-gray-600">{(a.tipos_activos ?? []).join(', ')}</td>
                  <td className="px-3 py-2 text-xs text-gray-500">
                    {new Date(a.ultima_alerta_at).toLocaleString('es-CL')}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </CardContent>
    </Card>
  )
}
