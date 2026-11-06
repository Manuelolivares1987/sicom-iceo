'use client'

import { Fragment, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts'
import { Calculator, Lock, Pencil, Plus, Trash2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Modal } from '@/components/ui/modal'
import { MESES, fmtFecha } from '@/components/costos/comunes'
import { fmtClp, fmtMM, fmtNum } from '@/lib/costos-operacion'
import {
  borrarProgramaPpto, congelarPpto, getCamionesPpto, getDetalleLineaPpto, getRealVsPpto, getResumenPpto,
  getVisitasPpto, guardarProgramaPpto, guardarSupuestoPpto, recalcularPpto,
  type LineaPpto, type ProgramaPpto, type ResumenPpto, type SupuestoPpto,
} from '@/lib/services/presupuesto'

// ============================================================================
// Pestaña de presupuesto (MIG670): real 2023-2026 y proyección 2027-2029.
// ============================================================================

const COLOR_BLOQUE: Record<string, string> = {
  A: '#059669', B: '#2563EB', C: '#D97706', D: '#7C3AED', E: '#DB2777',
}
const ANIOS_PPTO = [2027, 2028, 2029] as const
type Vista = 'resumen' | 'camiones' | 'visitas' | 'real' | 'supuestos'
const VISTAS: { id: Vista; label: string }[] = [
  { id: 'resumen', label: 'Resumen' },
  { id: 'camiones', label: 'Por camión' },
  { id: 'visitas', label: 'Próximas mantenciones' },
  { id: 'real', label: 'Real vs presupuesto' },
  { id: 'supuestos', label: 'Supuestos y programas' },
]

const fmtM = (v: number) => (v / 1e6).toLocaleString('es-CL', { minimumFractionDigits: 1, maximumFractionDigits: 1 })
const sumar = (ls: LineaPpto[], f: (l: LineaPpto) => number) => ls.reduce((a, l) => a + f(l), 0)
const pct = (a: number, b: number) => (b ? `${a >= b ? '+' : ''}${(((a - b) / b) * 100).toLocaleString('es-CL', { maximumFractionDigits: 1 })} %` : '—')

export function PresupuestoOperaciones() {
  const qc = useQueryClient()
  const [vista, setVista] = useState<Vista>('resumen')
  const [msg, setMsg] = useState<string | null>(null)
  const { data, isLoading, error } = useQuery({ queryKey: ['ppto-resumen'], queryFn: getResumenPpto })

  const recalcular = useMutation({
    mutationFn: recalcularPpto,
    onSuccess: () => { qc.invalidateQueries({ predicate: (q) => String(q.queryKey[0]).startsWith('ppto-') }); setMsg('Presupuesto recalculado.') },
    onError: (e: Error) => setMsg(e.message),
  })

  if (isLoading) return <p className="py-10 text-center text-sm text-gray-500">Cargando presupuesto…</p>
  if (error || !data) return <p className="py-10 text-center text-sm text-red-600">No se pudo cargar el presupuesto: {(error as Error)?.message}</p>

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="flex items-center gap-2 text-xl font-bold text-gray-900">
            <Calculator className="h-5 w-5 text-pillado-green-600" /> Presupuesto de Operaciones 2027-2029
          </h2>
          <p className="mt-0.5 max-w-3xl text-sm text-gray-600">
            Parte del gasto real de Softland y de la proyección de mantenciones de cada camión. Pesos netos de cada año.
            No incluye personal propio, petróleo de reventa ni inversión en camiones.
          </p>
          <p className="mt-0.5 text-xs text-gray-500">
            Calculado el {data.calculado_at ? new Date(data.calculado_at).toLocaleString('es-CL', { dateStyle: 'medium', timeStyle: 'short' }) : '—'}
            {data.congelada ? ` · Versión congelada: ${data.congelada.nombre}` : ' · Aún sin versión congelada'}
          </p>
        </div>
        {data.puede_editar && (
          <Button variant="outline" disabled={recalcular.isPending} onClick={() => { setMsg(null); recalcular.mutate() }}>
            {recalcular.isPending ? 'Recalculando…' : 'Recalcular con datos de hoy'}
          </Button>
        )}
      </div>
      {msg && <p className="rounded-lg bg-gray-100 px-3 py-2 text-sm text-gray-700">{msg}</p>}

      <div className="flex flex-wrap gap-1 border-b">
        {VISTAS.map((v) => (
          <button key={v.id} type="button" onClick={() => setVista(v.id)}
                  className={`-mb-px border-b-2 px-3 py-2 text-sm font-medium ${vista === v.id ? 'border-pillado-green-600 text-pillado-green-700' : 'border-transparent text-gray-500 hover:text-gray-800'}`}>
            {v.label}
          </button>
        ))}
      </div>

      {vista === 'resumen' && <Resumen data={data} />}
      {vista === 'camiones' && <Camiones />}
      {vista === 'visitas' && <Visitas />}
      {vista === 'real' && <RealVs hoy={data.hoy} />}
      {vista === 'supuestos' && <Supuestos data={data} />}
    </div>
  )
}

function Resumen({ data }: { data: ResumenPpto }) {
  const [detalle, setDetalle] = useState<LineaPpto | null>(null)
  const ls = data.lineas
  const cierre = sumar(ls, (l) => l.cierre_2026)
  const t = (a: 2027 | 2028 | 2029) => sumar(ls, (l) => l.ppto[String(a) as '2027'])
  const capex = (a: number) => data.programas.filter((p) => p.tipo === 'capex' && p.anio === a).reduce((s, p) => s + p.monto, 0)

  const bloques = useMemo(() => {
    const m = new Map<string, { nombre: string; lineas: LineaPpto[] }>()
    ls.forEach((l) => {
      if (!m.has(l.bloque)) m.set(l.bloque, { nombre: l.bloque_nombre, lineas: [] })
      m.get(l.bloque)!.lineas.push(l)
    })
    return Array.from(m.entries())
  }, [ls])

  const serie = useMemo(() => {
    const fila = (etq: string, f: (l: LineaPpto) => number) => {
      const o: Record<string, string | number> = { anio: etq }
      bloques.forEach(([, b]) => { o[b.nombre] = sumar(b.lineas, f) })
      return o
    }
    return [
      fila('2023', (l) => l.real['2023']), fila('2024', (l) => l.real['2024']), fila('2025', (l) => l.real['2025']),
      fila('Cierre 2026', (l) => l.cierre_2026),
      ...ANIOS_PPTO.map((a) => fila(`PPTO ${a}`, (l) => l.ppto[String(a) as '2027'])),
    ]
  }, [bloques])

  const tarjetas = [
    { t: 'Cierre 2026 estimado', v: cierre, s: `Real a hoy ${fmtMM(sumar(ls, (l) => l.real['2026']))}` },
    { t: 'Presupuesto 2027', v: t(2027), s: `${pct(t(2027), cierre)} vs cierre 2026` },
    { t: 'Presupuesto 2028', v: t(2028), s: `${pct(t(2028), t(2027))} vs 2027` },
    { t: 'Presupuesto 2029', v: t(2029), s: `${pct(t(2029), t(2028))} vs 2028` },
  ]

  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {tarjetas.map((c) => (
          <Card key={c.t}><CardContent className="p-4">
            <p className="text-xs font-medium uppercase tracking-wide text-gray-500">{c.t}</p>
            <p className="mt-1 text-2xl font-bold text-gray-900">{fmtMM(c.v)}</p>
            <p className="mt-0.5 text-xs text-gray-500">{c.s}</p>
          </CardContent></Card>
        ))}
      </div>

      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-base">Gasto real y presupuesto por bloque</CardTitle></CardHeader>
        <CardContent>
          <div style={{ width: '100%', height: 320 }}>
            <ResponsiveContainer>
              <BarChart data={serie} margin={{ top: 10, right: 10, left: 10, bottom: 0 }} barCategoryGap="28%">
                <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" vertical={false} />
                <XAxis dataKey="anio" tick={{ fontSize: 12 }} />
                <YAxis tick={{ fontSize: 11 }} tickFormatter={(v: number) => `${Math.round(v / 1e6)} M`} />
                <Tooltip formatter={(v: number, n: string) => [fmtMM(v), n]} cursor={{ fill: '#F3F4F6' }} />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                {bloques.map(([cod, b], i) => (
                  <Bar key={cod} dataKey={b.nombre} stackId="a" fill={COLOR_BLOQUE[cod]} stroke="#fff" strokeWidth={2}
                       radius={i === bloques.length - 1 ? [4, 4, 0, 0] : undefined} />
                ))}
              </BarChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Por línea, en millones de pesos</CardTitle>
          <p className="text-xs text-gray-500">Toca una línea para ver cómo se calcula y qué tiene adentro.</p>
        </CardHeader>
        <CardContent className="overflow-x-auto p-0">
          <table className="w-full min-w-[860px] text-sm">
            <thead className="bg-gray-50 text-xs text-gray-500">
              <tr>
                <th className="px-3 py-2 text-left">Línea</th>
                <th className="px-2 py-2 text-right">2023</th><th className="px-2 py-2 text-right">2024</th>
                <th className="px-2 py-2 text-right">2025</th>
                <th className="px-2 py-2 text-right">2026 a hoy</th><th className="px-2 py-2 text-right">Cierre 2026</th>
                {ANIOS_PPTO.map((a) => <th key={a} className="bg-pillado-green-50 px-2 py-2 text-right text-pillado-green-800">PPTO {a}</th>)}
              </tr>
            </thead>
            <tbody>
              {bloques.map(([cod, b]) => (
                <Fragment key={cod}>
                  <tr className="border-t bg-gray-50 font-semibold text-gray-900">
                    <td className="px-3 py-1.5">
                      <span className="mr-2 inline-block h-2.5 w-2.5 rounded-sm" style={{ background: COLOR_BLOQUE[cod] }} />{b.nombre}
                    </td>
                    {(['2023', '2024', '2025', '2026'] as const).map((y) => <td key={y} className="px-2 py-1.5 text-right">{fmtM(sumar(b.lineas, (l) => l.real[y]))}</td>)}
                    <td className="px-2 py-1.5 text-right">{fmtM(sumar(b.lineas, (l) => l.cierre_2026))}</td>
                    {ANIOS_PPTO.map((a) => <td key={a} className="px-2 py-1.5 text-right">{fmtM(sumar(b.lineas, (l) => l.ppto[String(a) as '2027']))}</td>)}
                  </tr>
                  {b.lineas.map((l) => (
                    <tr key={l.codigo} className="cursor-pointer border-t hover:bg-gray-50" onClick={() => setDetalle(l)}>
                      <td className="px-3 py-1.5 pl-7 text-gray-700">{l.nombre}</td>
                      {(['2023', '2024', '2025', '2026'] as const).map((y) => <td key={y} className="px-2 py-1.5 text-right text-gray-600">{fmtM(l.real[y])}</td>)}
                      <td className="px-2 py-1.5 text-right text-gray-600">{fmtM(l.cierre_2026)}</td>
                      {ANIOS_PPTO.map((a) => <td key={a} className="px-2 py-1.5 text-right font-medium text-gray-900">{fmtM(l.ppto[String(a) as '2027'])}</td>)}
                    </tr>
                  ))}
                </Fragment>
              ))}
              <tr className="border-t-2 border-gray-300 font-bold text-gray-900">
                <td className="px-3 py-2">Total</td>
                {(['2023', '2024', '2025', '2026'] as const).map((y) => <td key={y} className="px-2 py-2 text-right">{fmtM(sumar(ls, (l) => l.real[y]))}</td>)}
                <td className="px-2 py-2 text-right">{fmtM(cierre)}</td>
                {ANIOS_PPTO.map((a) => <td key={a} className="px-2 py-2 text-right">{fmtM(t(a))}</td>)}
              </tr>
              <tr className="border-t text-gray-600">
                <td className="px-3 py-1.5">Inversión, aparte del total</td>
                <td colSpan={5} />
                {ANIOS_PPTO.map((a) => <td key={a} className="px-2 py-1.5 text-right">{fmtM(capex(a))}</td>)}
              </tr>
            </tbody>
          </table>
        </CardContent>
      </Card>

      {data.meta && (
        <p className="text-xs text-gray-500">
          Base de cálculo: OC aprobadas hasta {fmtFecha(data.meta.corte)}. El {data.meta.kit_pct_precio_real} % del costo en filtros y lubricantes de los kits usa
          precio de compra real de Softland; el resto es precio estimado y conviene cotizarlo.
        </p>
      )}

      {detalle && <DetalleLinea linea={detalle} onClose={() => setDetalle(null)} />}
    </div>
  )
}

function DetalleLinea({ linea, onClose }: { linea: LineaPpto; onClose: () => void }) {
  const { data, isLoading } = useQuery({ queryKey: ['ppto-linea', linea.codigo], queryFn: () => getDetalleLineaPpto(linea.codigo) })
  return (
    <Modal open onClose={onClose} title={linea.nombre} className="sm:max-w-4xl">
      <p className="mb-3 text-sm text-gray-700">{linea.metodo}</p>
      {isLoading && <p className="text-sm text-gray-500">Cargando…</p>}
      {data && data.partidas.length > 0 && (
        <>
          <h4 className="mb-1 text-sm font-semibold text-gray-900">Presupuesto</h4>
          <div className="mb-4 max-h-72 overflow-auto rounded border">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-gray-50 text-xs text-gray-500">
                <tr><th className="px-2 py-1.5 text-left">Partida</th>{ANIOS_PPTO.map((a) => <th key={a} className="px-2 py-1.5 text-right">{a}</th>)}</tr>
              </thead>
              <tbody>
                {data.partidas.map((p) => (
                  <tr key={p.nombre} className="border-t">
                    <td className="px-2 py-1">{p.nombre}{p.descripcion && p.descripcion !== p.nombre && <span className="block text-xs text-gray-500">{p.descripcion}</span>}</td>
                    <td className="whitespace-nowrap px-2 py-1 text-right">{fmtMM(p.t27)}</td>
                    <td className="whitespace-nowrap px-2 py-1 text-right">{fmtMM(p.t28)}</td>
                    <td className="whitespace-nowrap px-2 py-1 text-right">{fmtMM(p.t29)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
      {data && data.productos.length > 0 && (
        <>
          <h4 className="mb-1 text-sm font-semibold text-gray-900">Lo más comprado en los últimos 12 meses</h4>
          <div className="max-h-72 overflow-auto rounded border">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-gray-50 text-xs text-gray-500">
                <tr><th className="px-2 py-1.5 text-left">Producto</th><th className="px-2 py-1.5 text-right">Líneas</th><th className="px-2 py-1.5 text-right">Total</th></tr>
              </thead>
              <tbody>
                {data.productos.map((p) => (
                  <tr key={p.cod_prod} className="border-t">
                    <td className="px-2 py-1">{p.descripcion ?? p.cod_prod}<span className="ml-2 text-xs text-gray-400">{p.cod_prod}</span></td>
                    <td className="px-2 py-1 text-right">{fmtNum(p.lineas)}</td>
                    <td className="whitespace-nowrap px-2 py-1 text-right font-medium">{fmtMM(p.total)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </Modal>
  )
}

function Camiones() {
  const { data, isLoading } = useQuery({ queryKey: ['ppto-camiones'], queryFn: getCamionesPpto })
  if (isLoading) return <p className="text-sm text-gray-500">Cargando…</p>
  const filas = data ?? []
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base">Mantención por camión, en millones de pesos</CardTitle>
        <p className="text-xs text-gray-500">
          Real: lo cargado directo al camión. El presupuesto del año incluye preventivo por pauta, correctivo, neumáticos y reparaciones mayores.
        </p>
      </CardHeader>
      <CardContent className="overflow-x-auto p-0">
        <table className="w-full min-w-[1080px] text-sm">
          <thead className="bg-gray-50 text-xs text-gray-500">
            <tr>
              <th className="px-3 py-2 text-left">Camión</th><th className="px-2 py-2 text-right">Horómetro</th>
              <th className="px-2 py-2 text-right">h/día</th><th className="px-2 py-2 text-right">Real 2025</th>
              <th className="px-2 py-2 text-right">Real 2026</th><th className="border-l px-2 py-2 text-right">Prev. 2027</th>
              <th className="px-2 py-2 text-right">Correct. 2027</th><th className="px-2 py-2 text-right">Neum. 2027</th>
              <th className="px-2 py-2 text-right">Mayores 2027</th>
              {ANIOS_PPTO.map((a) => <th key={a} className="bg-pillado-green-50 px-2 py-2 text-right text-pillado-green-800">PPTO {a}</th>)}
              <th className="border-l px-2 py-2 text-right" title="Visitas de pauta 2027 / 2028 / 2029">Visitas</th>
            </tr>
          </thead>
          <tbody>
            {filas.map((c) => (
              <tr key={c.patente} className="border-t hover:bg-gray-50">
                <td className="whitespace-nowrap px-3 py-1.5">
                  <span className="font-medium text-gray-900">{c.patente}</span>
                  <span className="ml-1.5 text-xs text-gray-500">{c.modelo}{c.anio_fab ? ` · ${c.anio_fab}` : ''}</span>
                </td>
                <td className="px-2 py-1.5 text-right">{fmtNum(c.horometro ?? 0)}</td>
                <td className="px-2 py-1.5 text-right" title={c.ritmo_fuente ?? ''}>
                  {(c.ritmo ?? 0).toLocaleString('es-CL', { maximumFractionDigits: 1 })}{c.ritmo_fuente?.startsWith('Sin dato') && <span className="text-amber-600"> *</span>}
                </td>
                <td className="px-2 py-1.5 text-right text-gray-600">{fmtM(c.real_2025)}</td>
                <td className="px-2 py-1.5 text-right text-gray-600">{fmtM(c.real_2026)}</td>
                <td className="border-l px-2 py-1.5 text-right">{fmtM(c.preventivo)}</td>
                <td className="px-2 py-1.5 text-right">{fmtM(c.correctivo)}</td>
                <td className="px-2 py-1.5 text-right">{fmtM(c.neumaticos)}</td>
                <td className="px-2 py-1.5 text-right">{fmtM(c.mayores)}</td>
                <td className="px-2 py-1.5 text-right font-medium">{fmtM(c.total_2027)}</td>
                <td className="px-2 py-1.5 text-right">{fmtM(c.total_2028)}</td>
                <td className="px-2 py-1.5 text-right">{fmtM(c.total_2029)}</td>
                <td className="whitespace-nowrap border-l px-2 py-1.5 text-right text-gray-600">{c.con_pauta ? `${c.visitas_2027} / ${c.visitas_2028} / ${c.visitas_2029}` : 'Sin pauta'}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="border-t px-3 py-2 text-xs text-gray-500">* Sin dato de horas: se usa el ritmo promedio de los camiones del mismo modelo o un supuesto.</p>
      </CardContent>
    </Card>
  )
}

const NOMBRE_TIPO_VISITA: Record<string, string> = { pauta: 'Pauta', componente: 'Componente', anual: 'Servicio anual' }

function Visitas() {
  const [anio, setAnio] = useState(2027)
  const [mes, setMes] = useState<number | null>(null)
  const { data, isLoading } = useQuery({ queryKey: ['ppto-visitas', anio], queryFn: () => getVisitasPpto(anio) })
  const visitas = data ?? []
  const porMes = MESES.map((nombre, i) => {
    const vs = visitas.filter((v) => v.mes === i + 1)
    return { mes: i + 1, nombre, n: vs.length, total: vs.reduce((s, v) => s + v.costo_kit, 0) }
  })
  const lista = mes ? visitas.filter((v) => v.mes === mes) : visitas
  return (
    <Card>
      <CardHeader className="pb-2">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <CardTitle className="text-base">Próximas mantenciones y costo del kit completo</CardTitle>
          <div className="flex gap-1">
            {[2026, 2027, 2028, 2029].map((a) => (
              <button key={a} type="button" onClick={() => { setAnio(a); setMes(null) }}
                      className={`rounded-full px-3 py-1 text-sm font-medium ${anio === a ? 'bg-pillado-green-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>{a}</button>
            ))}
          </div>
        </div>
        <p className="text-xs text-gray-500">Fechas estimadas con el horómetro y el ritmo de hoy. El servicio anual y los componentes por años se reparten en el año.</p>
      </CardHeader>
      <CardContent className="space-y-3">
        {isLoading && <p className="text-sm text-gray-500">Cargando…</p>}
        <div className="grid grid-cols-3 gap-2 sm:grid-cols-6 lg:grid-cols-12">
          {porMes.map((m) => (
            <button key={m.mes} type="button" disabled={!m.n} onClick={() => setMes(mes === m.mes ? null : m.mes)}
                    className={`rounded-lg border px-2 py-1.5 text-left disabled:opacity-40 ${mes === m.mes ? 'border-pillado-green-500 bg-pillado-green-50' : 'border-gray-200 hover:bg-gray-50'}`}>
              <span className="block text-xs capitalize text-gray-500">{m.nombre}</span>
              <span className="block text-sm font-semibold text-gray-900">{m.n}</span>
              <span className="block text-xs text-gray-600">{fmtM(m.total)} M</span>
            </button>
          ))}
        </div>
        <div className="max-h-[480px] overflow-auto rounded border">
          <table className="w-full text-sm">
            <thead className="sticky top-0 bg-gray-50 text-xs text-gray-500">
              <tr>
                <th className="px-3 py-1.5 text-left">Fecha</th><th className="px-2 py-1.5 text-left">Camión</th>
                <th className="px-2 py-1.5 text-left">Servicio</th><th className="px-2 py-1.5 text-right">Horómetro</th>
                <th className="px-2 py-1.5 text-right">Kit</th>
              </tr>
            </thead>
            <tbody>
              {lista.map((v, i) => (
                <tr key={`${v.patente}-${v.fecha}-${v.nivel}-${i}`} className="border-t">
                  <td className="whitespace-nowrap px-3 py-1">{fmtFecha(v.fecha)}</td>
                  <td className="px-2 py-1 font-medium">{v.patente}</td>
                  <td className="px-2 py-1">{NOMBRE_TIPO_VISITA[v.tipo]} {v.tipo === 'anual' ? '' : v.nivel}</td>
                  <td className="px-2 py-1 text-right">{v.horas ? fmtNum(v.horas) : '—'}</td>
                  <td className="whitespace-nowrap px-2 py-1 text-right">{fmtClp(v.costo_kit)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </CardContent>
    </Card>
  )
}

function RealVs({ hoy }: { hoy: string }) {
  const anioHoy = Number(hoy.slice(0, 4))
  const [anio, setAnio] = useState(Math.max(anioHoy, 2027))
  const { data, isLoading } = useQuery({ queryKey: ['ppto-real', anio], queryFn: () => getRealVsPpto(anio) })
  // Se compara hasta el mes en curso; un año futuro aún no tiene real.
  const hastaMes = anio < anioHoy ? 12 : anio > anioHoy ? 0 : Number(hoy.slice(5, 7))
  const acum = (o: Record<string, number>, h: number) => { let s = 0; for (let m = 1; m <= h; m++) s += o[m] ?? 0; return s }
  const filas = (data?.lineas ?? []).map((l) => ({
    ...l, p: acum(l.ppto, hastaMes), r: acum(l.real, hastaMes), anual: acum(l.ppto, 12),
  }))
  const tot = filas.reduce((a, f) => ({ p: a.p + f.p, r: a.r + f.r, anual: a.anual + f.anual }), { p: 0, r: 0, anual: 0 })
  return (
    <Card>
      <CardHeader className="pb-2">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <CardTitle className="text-base">Real contra presupuesto, en millones de pesos</CardTitle>
          <div className="flex gap-1">
            {ANIOS_PPTO.map((a) => (
              <button key={a} type="button" onClick={() => setAnio(a)}
                      className={`rounded-full px-3 py-1 text-sm font-medium ${anio === a ? 'bg-pillado-green-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>{a}</button>
            ))}
          </div>
        </div>
        <p className="text-xs text-gray-500">
          {data?.congelada ? `Compara contra la versión congelada «${data.version}».` : 'Compara contra el presupuesto de trabajo: congela una versión en Supuestos para fijarlo.'}
          {hastaMes === 0 && ` El real parte en enero de ${anio}.`}
        </p>
      </CardHeader>
      <CardContent className="overflow-x-auto p-0">
        {isLoading && <p className="p-4 text-sm text-gray-500">Cargando…</p>}
        <table className="w-full min-w-[640px] text-sm">
          <thead className="bg-gray-50 text-xs text-gray-500">
            <tr>
              <th className="px-3 py-2 text-left">Línea</th><th className="px-2 py-2 text-right">PPTO a la fecha</th>
              <th className="px-2 py-2 text-right">Real a la fecha</th><th className="px-2 py-2 text-right">Diferencia</th>
              <th className="px-2 py-2 text-right">PPTO año</th>
            </tr>
          </thead>
          <tbody>
            {filas.map((f) => (
              <tr key={f.codigo} className="border-t">
                <td className="px-3 py-1.5">{f.nombre}</td>
                <td className="px-2 py-1.5 text-right">{fmtM(f.p)}</td>
                <td className="px-2 py-1.5 text-right">{fmtM(f.r)}</td>
                <td className={`px-2 py-1.5 text-right ${f.r > f.p ? 'text-red-600' : 'text-gray-700'}`}>{fmtM(f.r - f.p)}</td>
                <td className="px-2 py-1.5 text-right text-gray-600">{fmtM(f.anual)}</td>
              </tr>
            ))}
            <tr className="border-t-2 border-gray-300 font-bold">
              <td className="px-3 py-2">Total</td>
              <td className="px-2 py-2 text-right">{fmtM(tot.p)}</td>
              <td className="px-2 py-2 text-right">{fmtM(tot.r)}</td>
              <td className={`px-2 py-2 text-right ${tot.r > tot.p ? 'text-red-600' : ''}`}>{fmtM(tot.r - tot.p)}</td>
              <td className="px-2 py-2 text-right">{fmtM(tot.anual)}</td>
            </tr>
          </tbody>
        </table>
      </CardContent>
    </Card>
  )
}

const NOMBRE_PROGRAMA: Record<ProgramaPpto['tipo'], string> = {
  overhaul: 'Overhaul', opex: 'Programa', capex: 'Inversión',
}
const PROGRAMA_VACIO: Omit<ProgramaPpto, 'id'> & { id: number | null } = {
  id: null, anio: 2027, tipo: 'opex', patente: null, descripcion: '', monto: 0, gatillo: null,
}

function Supuestos({ data }: { data: ResumenPpto }) {
  const qc = useQueryClient()
  const [editando, setEditando] = useState<(Omit<ProgramaPpto, 'id'> & { id: number | null }) | null>(null)
  const [nombreVersion, setNombreVersion] = useState('')
  const [aviso, setAviso] = useState<string | null>(null)
  const refrescar = () => qc.invalidateQueries({ queryKey: ['ppto-resumen'] })
  const fallo = (e: Error) => setAviso(e.message)
  const pideRecalculo = 'Guardado. Toca «Recalcular con datos de hoy» para que entre al presupuesto.'

  const guardarSup = useMutation({
    mutationFn: (v: { clave: string; valor: number }) => guardarSupuestoPpto(v.clave, v.valor),
    onSuccess: () => { refrescar(); setAviso(pideRecalculo) }, onError: fallo,
  })
  const guardarProg = useMutation({
    mutationFn: guardarProgramaPpto,
    onSuccess: () => { refrescar(); setEditando(null); setAviso(pideRecalculo) }, onError: fallo,
  })
  const borrarProg = useMutation({
    mutationFn: borrarProgramaPpto,
    onSuccess: () => { refrescar(); setAviso(pideRecalculo) }, onError: fallo,
  })
  const congelar = useMutation({
    mutationFn: congelarPpto,
    onSuccess: () => { refrescar(); setNombreVersion(''); setAviso('Versión congelada: desde ahora el real se compara contra ella.') }, onError: fallo,
  })
  const ed = data.puede_editar

  return (
    <div className="space-y-4">
      {aviso && <p className="rounded-lg bg-gray-100 px-3 py-2 text-sm text-gray-700">{aviso}</p>}
      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-base">Supuestos</CardTitle></CardHeader>
        <CardContent className="p-0">
          <table className="w-full text-sm">
            <tbody>
              {data.supuestos.map((s) => (
                <tr key={s.clave} className="border-t first:border-t-0">
                  <td className="px-3 py-1.5">{s.nombre}{s.nota && <span className="block text-xs text-gray-500">{s.nota}</span>}</td>
                  <td className="w-44 px-3 py-1.5 text-right">
                    <CampoSupuesto s={s} editable={ed} onGuardar={(valor) => { setAviso(null); guardarSup.mutate({ clave: s.clave, valor }) }} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2">
          <div className="flex items-center justify-between gap-2">
            <CardTitle className="text-base">Overhauls, programas e inversión</CardTitle>
            {ed && <Button variant="outline" size="sm" onClick={() => setEditando({ ...PROGRAMA_VACIO })}><Plus className="mr-1 h-4 w-4" /> Agregar</Button>}
          </div>
          <p className="text-xs text-gray-500">Son decisiones, no vienen de los datos: vienen del PPTO Operaciones v3 y se pueden cambiar aquí.</p>
        </CardHeader>
        <CardContent className="overflow-x-auto p-0">
          {editando && <FormPrograma valor={editando} ocupado={guardarProg.isPending} onCancelar={() => setEditando(null)}
                                     onGuardar={(p) => { setAviso(null); guardarProg.mutate(p) }} />}
          <table className="w-full min-w-[640px] text-sm">
            <thead className="bg-gray-50 text-xs text-gray-500">
              <tr>
                <th className="px-3 py-1.5 text-left">Año</th><th className="px-2 py-1.5 text-left">Tipo</th>
                <th className="px-2 py-1.5 text-left">Descripción</th><th className="px-2 py-1.5 text-right">Monto</th><th />
              </tr>
            </thead>
            <tbody>
              {data.programas.map((p) => (
                <tr key={p.id} className="border-t">
                  <td className="px-3 py-1.5">{p.anio}</td>
                  <td className="px-2 py-1.5">{NOMBRE_PROGRAMA[p.tipo]}</td>
                  <td className="px-2 py-1.5">
                    {p.patente && <span className="mr-1 font-medium">{p.patente}</span>}{p.descripcion}
                    {p.gatillo && <span className="block text-xs text-gray-500">{p.gatillo}</span>}
                  </td>
                  <td className="whitespace-nowrap px-2 py-1.5 text-right">{fmtClp(p.monto)}</td>
                  <td className="whitespace-nowrap px-2 py-1.5 text-right">
                    {ed && (
                      <>
                        <button type="button" aria-label="Editar" className="p-1 text-gray-500 hover:text-gray-900" onClick={() => setEditando(p)}><Pencil className="h-4 w-4" /></button>
                        <button type="button" aria-label="Borrar" className="p-1 text-gray-500 hover:text-red-600" onClick={() => { setAviso(null); borrarProg.mutate(p.id) }}><Trash2 className="h-4 w-4" /></button>
                      </>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </CardContent>
      </Card>

      {ed && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-base"><Lock className="h-4 w-4" /> Congelar el presupuesto aprobado</CardTitle>
            <p className="text-xs text-gray-500">Guarda una copia que no cambia aunque se recalcule. Contra ella se mide el real del año.</p>
          </CardHeader>
          <CardContent className="flex flex-wrap items-center gap-2">
            <input value={nombreVersion} onChange={(e) => setNombreVersion(e.target.value)} placeholder="Nombre, por ejemplo: Aprobado 2027"
                   className="w-72 rounded-md border px-3 py-1.5 text-sm" />
            <Button variant="outline" disabled={!nombreVersion.trim() || congelar.isPending} onClick={() => { setAviso(null); congelar.mutate(nombreVersion) }}>Congelar</Button>
          </CardContent>
        </Card>
      )}
    </div>
  )
}

function CampoSupuesto({ s, editable, onGuardar }: { s: SupuestoPpto; editable: boolean; onGuardar: (v: number) => void }) {
  const esPct = s.unidad === 'pct'
  const mostrar = esPct ? s.valor * 100 : s.valor
  const [txt, setTxt] = useState(String(Number(mostrar.toFixed(4))))
  const sufijo = esPct ? '%' : s.unidad === 'clp' ? '$' : s.unidad
  if (!editable) return <span>{mostrar.toLocaleString('es-CL')} {sufijo}</span>
  return (
    <span className="inline-flex items-center gap-1">
      <input type="number" min={0} step="any" value={txt} onChange={(e) => setTxt(e.target.value)}
             onBlur={() => {
               const n = Number(txt)
               if (txt !== '' && Number.isFinite(n) && n >= 0 && n !== Number(mostrar.toFixed(4))) onGuardar(esPct ? n / 100 : n)
             }}
             className="w-28 rounded-md border px-2 py-1 text-right text-sm" />
      <span className="w-8 text-left text-xs text-gray-500">{sufijo}</span>
    </span>
  )
}

function FormPrograma({ valor, ocupado, onGuardar, onCancelar }: {
  valor: Omit<ProgramaPpto, 'id'> & { id: number | null }
  ocupado: boolean
  onGuardar: (p: Omit<ProgramaPpto, 'id'> & { id: number | null }) => void
  onCancelar: () => void
}) {
  const [f, setF] = useState(valor)
  const campo = 'rounded-md border px-2 py-1.5 text-sm'
  return (
    <div className="flex flex-wrap items-end gap-2 border-b bg-gray-50 p-3 text-sm">
      <label className="grid gap-0.5 text-xs text-gray-600">Año
        <select className={campo} value={f.anio} onChange={(e) => setF({ ...f, anio: Number(e.target.value) })}>
          {ANIOS_PPTO.map((a) => <option key={a} value={a}>{a}</option>)}
        </select>
      </label>
      <label className="grid gap-0.5 text-xs text-gray-600">Tipo
        <select className={campo} value={f.tipo} onChange={(e) => setF({ ...f, tipo: e.target.value as ProgramaPpto['tipo'] })}>
          {Object.entries(NOMBRE_PROGRAMA).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
      </label>
      <label className="grid gap-0.5 text-xs text-gray-600">Patente
        <input className={`${campo} w-24`} value={f.patente ?? ''} onChange={(e) => setF({ ...f, patente: e.target.value })} />
      </label>
      <label className="grid min-w-[240px] flex-1 gap-0.5 text-xs text-gray-600">Descripción
        <input className={campo} value={f.descripcion} onChange={(e) => setF({ ...f, descripcion: e.target.value })} />
      </label>
      <label className="grid gap-0.5 text-xs text-gray-600">Monto ($)
        <input type="number" min={0} className={`${campo} w-32 text-right`} value={f.monto} onChange={(e) => setF({ ...f, monto: Number(e.target.value) })} />
      </label>
      <label className="grid min-w-[200px] flex-1 gap-0.5 text-xs text-gray-600">Condición
        <input className={campo} value={f.gatillo ?? ''} onChange={(e) => setF({ ...f, gatillo: e.target.value })} />
      </label>
      <Button size="sm" disabled={ocupado || !f.descripcion.trim()} onClick={() => onGuardar(f)}>Guardar</Button>
      <Button size="sm" variant="outline" onClick={onCancelar}>Cancelar</Button>
    </div>
  )
}
