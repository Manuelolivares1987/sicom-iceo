'use client'

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { Download, Package } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Modal } from '@/components/ui/modal'
import { fmtClp, fmtMM } from '@/lib/costos-operacion'
import { armarFilaInsumo, filaParaProveedor, periodosInsumo, type FilaInsumo } from '@/lib/insumos-consumo'
import { getConsumoInsumos, getDetalleInsumo, type FuenteInsumo } from '@/lib/services/insumos-consumo'

// ============================================================================
// Pestaña de consumos por insumo (MIG681): histórico de Softland y proyección
// por pauta, para pedir cotizaciones con volúmenes reales.
// ============================================================================

const LIMITE = 150
const fmtQ = (v: number | null | undefined) => (v == null ? '—' : v.toLocaleString('es-CL', { maximumFractionDigits: v !== 0 && Math.abs(v) < 10 ? 1 : 0 }))
const hoyLocal = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}` }
type Alcance = 'todos' | 'pauta' | 'sin_codigo'
type Orden = 'monto' | 'acumulado' | 'proyeccion' | 'monto_proyectado'

export function ConsumosInsumos() {
  const periodos = useMemo(() => periodosInsumo(hoyLocal()), [])
  const [periodoId, setPeriodoId] = useState(periodos[0].id)
  const [fuente, setFuente] = useState<FuenteInsumo>('bodega')
  const [texto, setTexto] = useState('')
  const [familia, setFamilia] = useState('')
  const [alcance, setAlcance] = useState<Alcance>('todos')
  const [orden, setOrden] = useState<Orden>('monto')
  const [detalle, setDetalle] = useState<FilaInsumo | null>(null)
  const [msg, setMsg] = useState<string | null>(null)
  const periodo = periodos.find((p) => p.id === periodoId) ?? periodos[0]

  const { data, isLoading, error } = useQuery({
    queryKey: ['insumos-consumo', fuente, periodo.desde, periodo.hasta],
    queryFn: () => getConsumoInsumos(fuente, periodo.desde, periodo.hasta),
  })

  const filasBase = useMemo(() => (data?.items ?? []).map((i) => armarFilaInsumo(i, periodo.meses)), [data, periodo.meses])
  const familias = useMemo(() => Array.from(new Set(filasBase.map((f) => f.familia))).sort((a, b) => a.localeCompare(b, 'es')), [filasBase])
  const filas = useMemo(() => {
    const q = texto.trim().toLowerCase()
    return filasBase
      .filter((f) => !familia || f.familia === familia)
      .filter((f) => alcance === 'todos' || (alcance === 'pauta' ? f.con_pauta : !f.cod_prod))
      .filter((f) => !q || f.descripcion.toLowerCase().includes(q) || (f.cod_prod ?? '').toLowerCase().includes(q) || (f.proveedor ?? '').toLowerCase().includes(q))
      .sort((a, b) => (Number(b[orden]) || 0) - (Number(a[orden]) || 0))
  }, [filasBase, familia, alcance, texto, orden])

  const totalMonto = filas.reduce((s, f) => s + f.monto, 0)
  const totalProyectado = filas.reduce((s, f) => s + (f.monto_proyectado ?? 0), 0)
  const conPauta = filas.filter((f) => f.con_pauta).length

  const exportar = async (paraProveedor: boolean) => {
    setMsg(null)
    try {
      const ExcelJS = (await import('exceljs')).default
      const wb = new ExcelJS.Workbook()
      const ws = wb.addWorksheet('Volúmenes')
      ws.columns = [
        { header: 'Código', key: 'codigo', width: 16 }, { header: 'Insumo', key: 'insumo', width: 56 }, { header: 'Familia', key: 'familia', width: 26 },
        { header: 'Unidad', key: 'unidad', width: 9 }, { header: `Acumulado (${periodo.label})`, key: 'acumulado', width: 20 },
        { header: 'Promedio mensual', key: 'promedio', width: 16 }, { header: 'Proyección 12 meses', key: 'proyeccion', width: 18 }, { header: 'Base proyección', key: 'base', width: 20 },
        ...(paraProveedor ? [] : [
          { header: 'Pauta 2027', key: 'p27', width: 12 }, { header: 'Pauta 2028', key: 'p28', width: 12 }, { header: 'Pauta 2029', key: 'p29', width: 12 },
          { header: 'Gasto período', key: 'monto', width: 15 }, { header: 'Precio promedio', key: 'precio', width: 15 }, { header: 'Proyección $', key: 'mp', width: 15 },
          { header: 'Proveedor principal', key: 'prov', width: 34 },
        ]),
      ]
      ws.getRow(1).font = { bold: true }
      ws.views = [{ state: 'frozen', ySplit: 1 }]
      for (const f of filas) {
        ws.addRow({ ...filaParaProveedor(f), ...(paraProveedor ? {} : { p27: f.pauta_2027, p28: f.pauta_2028, p29: f.pauta_2029, monto: f.monto, precio: f.precio, mp: f.monto_proyectado, prov: f.proveedor }) })
      }
      for (const k of ['acumulado', 'promedio', 'proyeccion']) ws.getColumn(k).numFmt = '#,##0.0'
      const buf = await wb.xlsx.writeBuffer()
      const url = URL.createObjectURL(new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }))
      const a = document.createElement('a')
      a.href = url
      a.download = `Consumo_insumos_${paraProveedor ? 'proveedores' : 'interno'}_${hoyLocal()}.xlsx`
      a.click()
      URL.revokeObjectURL(url)
    } catch (e) { setMsg(`No se pudo generar el Excel: ${(e as Error).message}`) }
  }

  const control = 'rounded-md border border-gray-300 bg-white px-2 py-1.5 text-sm'
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="flex items-center gap-2 text-xl font-bold text-gray-900">
            <Package className="h-5 w-5 text-pillado-green-600" /> Consumos por insumo
          </h2>
          <p className="mt-0.5 max-w-3xl text-sm text-gray-600">
            Histórico de Softland y proyección de 12 meses según las pautas de cada camión. Aceites en litros y grasas en kilos, aunque Softland los lleve por envase.
          </p>
          <p className="mt-0.5 text-xs text-gray-500">Pautas calculadas el {data?.calculado_at ? new Date(data.calculado_at).toLocaleDateString('es-CL') : '—'}. Se actualizan con «Recalcular» en Presupuesto.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button variant="outline" disabled={!filas.length} onClick={() => exportar(true)}><Download className="mr-1.5 h-4 w-4" /> Excel para proveedores</Button>
          <Button variant="outline" disabled={!filas.length} onClick={() => exportar(false)}><Download className="mr-1.5 h-4 w-4" /> Excel interno</Button>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <select aria-label="Período" className={control} value={periodo.id} onChange={(e) => setPeriodoId(e.target.value)}>
          {periodos.map((p) => <option key={p.id} value={p.id}>{p.label}</option>)}
        </select>
        <select aria-label="Fuente" className={control} value={fuente} onChange={(e) => setFuente(e.target.value as FuenteInsumo)}>
          <option value="bodega">Consumo (salidas de bodega)</option>
          <option value="oc">Compras (OC aprobadas)</option>
        </select>
        <select aria-label="Familia" className={control} value={familia} onChange={(e) => setFamilia(e.target.value)}>
          <option value="">Todas las familias</option>
          {familias.map((f) => <option key={f} value={f}>{f}</option>)}
        </select>
        <select aria-label="Alcance" className={control} value={alcance} onChange={(e) => setAlcance(e.target.value as Alcance)}>
          <option value="todos">Todos los insumos</option>
          <option value="pauta">Solo los que están en pauta</option>
          <option value="sin_codigo">En pauta sin código Softland</option>
        </select>
        <select aria-label="Ordenar" className={control} value={orden} onChange={(e) => setOrden(e.target.value as Orden)}>
          <option value="monto">Ordenar por gasto</option>
          <option value="acumulado">Ordenar por acumulado</option>
          <option value="proyeccion">Ordenar por proyección</option>
          <option value="monto_proyectado">Ordenar por proyección $</option>
        </select>
        <input aria-label="Buscar" className={`${control} min-w-[200px] flex-1`} placeholder="Buscar insumo, código o proveedor" value={texto} onChange={(e) => setTexto(e.target.value)} />
      </div>
      {msg && <p className="rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">{msg}</p>}

      {isLoading ? <p className="py-10 text-center text-sm text-gray-500">Cargando consumos…</p>
        : error ? <p className="py-10 text-center text-sm text-red-600">No se pudieron cargar los consumos: {(error as Error).message}</p>
        : (
          <>
            <div className="grid gap-3 sm:grid-cols-3">
              <Dato titulo={`Gasto · ${periodo.label}`} valor={fmtMM(totalMonto)} nota={`${fmtMM(totalMonto / periodo.meses)} promedio mensual`} />
              <Dato titulo="Proyección 12 meses" valor={fmtMM(totalProyectado)} nota="Pauta cuando existe; si no, promedio histórico" />
              <Dato titulo="Insumos en la selección" valor={filas.length.toLocaleString('es-CL')} nota={`${conPauta.toLocaleString('es-CL')} proyectados por pauta`} />
            </div>
            <Card>
              <CardContent className="overflow-x-auto p-0">
                <table className="w-full min-w-[980px] text-sm">
                  <thead className="bg-gray-50 text-xs uppercase text-gray-500">
                    <tr>
                      <th className="px-3 py-2 text-left">Insumo</th><th className="px-2 py-2 text-left">Un.</th>
                      <th className="px-2 py-2 text-right">Acumulado</th><th className="px-2 py-2 text-right">Prom. mes</th>
                      <th className="px-2 py-2 text-right">Proyección 12 m</th><th className="px-2 py-2 text-right">2027</th><th className="px-2 py-2 text-right">2028</th>
                      <th className="px-2 py-2 text-right">Precio prom.</th><th className="px-3 py-2 text-left">Proveedor principal</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y">
                    {filas.slice(0, LIMITE).map((f) => (
                      <tr key={f.clave} className="cursor-pointer hover:bg-gray-50" onClick={() => setDetalle(f)}>
                        <td className="max-w-[340px] px-3 py-2">
                          <div className="truncate font-medium text-gray-900" title={f.descripcion}>{f.descripcion}</div>
                          <div className="text-xs text-gray-500">{f.cod_prod ?? 'Sin código Softland'} · {f.familia}</div>
                        </td>
                        <td className="px-2 py-2 text-gray-600">{f.unidad}</td>
                        <td className="px-2 py-2 text-right tabular-nums">{fmtQ(f.acumulado)}</td>
                        <td className="px-2 py-2 text-right tabular-nums">{fmtQ(f.promedio)}</td>
                        <td className="px-2 py-2 text-right tabular-nums">
                          <span className="font-semibold text-gray-900">{fmtQ(f.proyeccion)}</span>
                          <div className={`text-[11px] ${f.base === 'pauta' ? 'text-pillado-green-700' : 'text-gray-500'}`}>{f.base === 'pauta' ? 'Pauta' : 'Promedio'}</div>
                        </td>
                        <td className="px-2 py-2 text-right tabular-nums text-gray-600">{fmtQ(f.pauta_2027)}</td>
                        <td className="px-2 py-2 text-right tabular-nums text-gray-600">{fmtQ(f.pauta_2028)}</td>
                        <td className="px-2 py-2 text-right tabular-nums">{f.precio != null ? fmtClp(f.precio) : '—'}</td>
                        <td className="max-w-[190px] truncate px-3 py-2 text-gray-600" title={f.proveedor ?? ''}>{f.proveedor ?? '—'}{f.n_proveedores > 1 ? ` +${f.n_proveedores - 1}` : ''}</td>
                      </tr>
                    ))}
                    {!filas.length && <tr><td colSpan={9} className="px-3 py-8 text-center text-gray-500">Ningún insumo coincide con estos filtros.</td></tr>}
                  </tbody>
                </table>
              </CardContent>
            </Card>
            {filas.length > LIMITE && <p className="text-xs text-gray-500">Se muestran los primeros {LIMITE} de {filas.length.toLocaleString('es-CL')}. El Excel incluye todos los de la selección.</p>}
            <p className="text-xs text-gray-500">
              La pauta cubre solo el preventivo de la flota con kit: el consumo real también incluye correctivos y otros equipos, por eso puede ser mayor. No incluye el petróleo de reventa, inversión en camiones ni servicios.
            </p>
          </>
        )}
      {detalle && <DetalleInsumo fila={detalle} fuente={fuente} onClose={() => setDetalle(null)} />}
    </div>
  )
}

function Dato({ titulo, valor, nota }: { titulo: string; valor: string; nota: string }) {
  return (
    <Card><CardContent className="p-4">
      <p className="text-xs text-gray-500">{titulo}</p>
      <p className="mt-1 text-2xl font-bold text-gray-900">{valor}</p>
      <p className="mt-0.5 text-xs text-gray-500">{nota}</p>
    </CardContent></Card>
  )
}

function DetalleInsumo({ fila, fuente, onClose }: { fila: FilaInsumo; fuente: FuenteInsumo; onClose: () => void }) {
  const { data, isLoading, error } = useQuery({ queryKey: ['insumo-detalle', fuente, fila.clave], queryFn: () => getDetalleInsumo(fuente, fila.clave) })
  const serie = useMemo(() => {
    const m = new Map<string, { mes: string; Histórico?: number; Pauta?: number }>()
    data?.historico.forEach((h) => m.set(h.mes, { mes: h.mes, Histórico: Number(h.cantidad) }))
    data?.proyeccion.forEach((p) => m.set(p.mes, { ...(m.get(p.mes) ?? { mes: p.mes }), Pauta: Number(p.cantidad) }))
    return Array.from(m.values()).sort((a, b) => a.mes.localeCompare(b.mes))
  }, [data])
  const nombre = fuente === 'oc' ? 'Compras' : 'Consumo'

  return (
    <Modal open onClose={onClose} title={fila.descripcion} className="max-w-3xl">
      <div className="space-y-4">
        <p className="text-sm text-gray-600">{fila.cod_prod ?? 'Sin código Softland'} · Cantidades en {fila.unidad}</p>
        {isLoading ? <p className="py-6 text-center text-sm text-gray-500">Cargando…</p>
          : error || !data ? <p className="py-6 text-center text-sm text-red-600">No se pudo cargar el detalle.</p>
          : (
            <>
              <div className="h-60">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={serie} margin={{ top: 8, right: 8, left: 0, bottom: 0 }} barGap={2}>
                    <CartesianGrid vertical={false} stroke="#e5e7eb" />
                    <XAxis dataKey="mes" tick={{ fontSize: 11, fill: '#6b7280' }} tickLine={false} minTickGap={24} />
                    <YAxis tick={{ fontSize: 11, fill: '#6b7280' }} tickLine={false} axisLine={false} width={48} />
                    <Tooltip formatter={(v) => `${fmtQ(Number(v))} ${fila.unidad}`} cursor={{ fill: '#f3f4f6' }} />
                    <Legend wrapperStyle={{ fontSize: 12 }} />
                    <Bar dataKey="Histórico" name={nombre} fill="#059669" radius={[4, 4, 0, 0]} maxBarSize={14} />
                    <Bar dataKey="Pauta" name="Proyección por pauta" fill="#2563EB" radius={[4, 4, 0, 0]} maxBarSize={14} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
              {data.proveedores.length > 0 && (
                <Tabla titulo="Proveedores, últimos 36 meses" cols={['Proveedor', 'Cantidad', 'Precio prom.', 'Última OC']}
                       filas={data.proveedores.map((p) => [p.proveedor, fmtQ(Number(p.cantidad)), p.precio != null ? fmtClp(Number(p.precio)) : '—', new Date(`${p.ultima.slice(0, 10)}T12:00:00`).toLocaleDateString('es-CL')])} />
              )}
              {data.camiones.length > 0 && (
                <Tabla titulo="Camiones que lo usan, próximos 12 meses" cols={['Patente', 'Pauta', 'Visitas', 'Cantidad']}
                       filas={data.camiones.map((c) => [c.patente, c.grupo, String(c.visitas), fmtQ(Number(c.cantidad))])} />
              )}
            </>
          )}
      </div>
    </Modal>
  )
}

function Tabla({ titulo, cols, filas }: { titulo: string; cols: string[]; filas: string[][] }) {
  return (
    <div>
      <h4 className="mb-1 text-sm font-semibold text-gray-800">{titulo}</h4>
      <div className="max-h-48 overflow-auto rounded border">
        <table className="w-full text-sm">
          <thead className="sticky top-0 bg-gray-50 text-xs text-gray-500"><tr>{cols.map((c, i) => <th key={c} className={`px-2 py-1 ${i === 0 ? 'text-left' : 'text-right'}`}>{c}</th>)}</tr></thead>
          <tbody className="divide-y">{filas.map((f, n) => <tr key={n}>{f.map((c, i) => <td key={i} className={`px-2 py-1 ${i === 0 ? 'text-left' : 'text-right tabular-nums'}`}>{c}</td>)}</tr>)}</tbody>
        </table>
      </div>
    </div>
  )
}
