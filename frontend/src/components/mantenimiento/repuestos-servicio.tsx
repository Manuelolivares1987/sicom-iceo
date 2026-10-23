'use client'

import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  AlertTriangle, ChevronDown, ChevronUp, Download, Pencil, Plus, Trash2,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Modal } from '@/components/ui/modal'
import { useToast } from '@/hooks/use-toast'
import {
  claveRepuesto, fijarIntervalo, getModelos, getOperaciones, getProgramas, getRepuestos,
  getServiciosProyectados, guardarOperacion, guardarRepuestos, kitDelServicio, parsearRepuestosPegados,
  puedeEditarPrograma, quitarOperacion, tocaEnServicio,
  type AccionOperacion, type Operacion, type Repuesto, type RepuestoInput, type ServicioProyectado,
} from '@/lib/services/programa-servicio'

// ============================================================================
// Repuestos por servicio (MIG647) — pestañas de Horas por equipo
// ----------------------------------------------------------------------------
// Tres miradas sobre lo mismo:
//   · Próximos servicios — para el jefe de taller: qué camión, cuándo, qué se
//     hace y qué repuestos pide, con el stock de bodega al lado.
//   · Compras — el consolidado a 30/60/90 días contra el stock, a Excel.
//   · Programa por modelo — las operaciones del fabricante con su «cada N
//     servicios» y los repuestos de cada una (se pegan desde Excel).
// ============================================================================

const NUM = new Intl.NumberFormat('es-CL', { maximumFractionDigits: 1 })
const n1 = (v: number | null | undefined) => (v == null ? '—' : NUM.format(v))
const fecha = (iso: string | null) =>
  iso ? new Date(iso.slice(0, 10) + 'T12:00:00').toLocaleDateString('es-CL', { day: '2-digit', month: 'short', year: '2-digit' }) : 'sin ritmo'
const diasHasta = (iso: string | null) =>
  iso ? Math.round((new Date(iso.slice(0, 10) + 'T12:00:00').getTime() - Date.now()) / 86_400_000) : null

const ACCION: Record<AccionOperacion, string> = {
  sustituir: 'Sustituir', lubricar: 'Lubricar', ajustar: 'Ajustar', inspeccionar: 'Inspeccionar', otro: 'Otro',
}

export type VistaRepuestos = 'servicios' | 'compras' | 'programa'

/** Las vistas de repuestos dentro de Horas por equipo: la pestaña la elige la página. */
export function RepuestosServicio({ vista }: { vista: VistaRepuestos }) {
  const [horizonte, setHorizonte] = useState(30)

  const servicios = useQuery({ queryKey: ['servicios-proyectados'], queryFn: getServiciosProyectados, staleTime: 5 * 60_000 })
  const ops = useQuery({ queryKey: ['programa-operaciones'], queryFn: getOperaciones, staleTime: 5 * 60_000 })
  const reps = useQuery({ queryKey: ['programa-repuestos'], queryFn: getRepuestos, staleTime: 5 * 60_000 })
  const programas = useQuery({ queryKey: ['programas-servicio'], queryFn: getProgramas, staleTime: 5 * 60_000 })
  const editor = useQuery({ queryKey: ['programa-puede-editar'], queryFn: puedeEditarPrograma, staleTime: 30 * 60_000 })

  const cargando = servicios.isLoading || ops.isLoading || reps.isLoading || programas.isLoading
  const error = servicios.error || ops.error || reps.error || programas.error

  // Compras suma solo lo que cae en el período; la lista del taller muestra
  // además el próximo de cada equipo aunque esté más lejos.
  const enHorizonte = useMemo(() => (servicios.data ?? []).filter((s) => {
    const d = diasHasta(s.fecha_estimada)
    return d != null && d <= horizonte
  }), [servicios.data, horizonte])
  const paraTaller = useMemo(() => (servicios.data ?? []).filter((s) => {
    const d = diasHasta(s.fecha_estimada)
    return s.orden === 0 || (d != null && d <= horizonte)
  }), [servicios.data, horizonte])

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <p className="text-xs text-gray-500">
          Servicio cada 300 h; lo que se hace en cada uno sigue la pauta del fabricante contada en
          servicios (una operación «cada 3» toca en el 3, 6, 9…). El cuándo sale de la escalera.
        </p>
        {vista !== 'programa' && (
          <div className="ml-auto flex items-center gap-1 text-xs text-gray-500">
            Próximos
            {[30, 60, 90].map((d) => (
              <button key={d} type="button" onClick={() => setHorizonte(d)}
                className={`rounded px-2 py-1 font-medium ${horizonte === d ? 'bg-pillado-green-500 text-white' : 'bg-gray-100 text-gray-700'}`}>
                {d} días
              </button>
            ))}
          </div>
        )}
      </div>

      {error ? (
        <Card><CardContent className="p-4 text-sm text-red-600">{(error as Error).message}</CardContent></Card>
      ) : cargando ? (
        <div className="py-16 text-center"><Spinner /></div>
      ) : vista === 'servicios' ? (
        <TabServicios servicios={paraTaller} ops={ops.data ?? []} reps={reps.data ?? []} />
      ) : vista === 'compras' ? (
        <TabCompras servicios={enHorizonte} ops={ops.data ?? []} reps={reps.data ?? []} horizonte={horizonte} />
      ) : (
        <TabPrograma ops={ops.data ?? []} reps={reps.data ?? []}
                     programas={programas.data ?? []} puedeEditar={!!editor.data} />
      )}
    </div>
  )
}

// ── Próximos servicios ──────────────────────────────────────────────────────
function TabServicios({ servicios, ops, reps }: {
  servicios: ServicioProyectado[]; ops: Operacion[]; reps: Repuesto[]
}) {
  const [abierto, setAbierto] = useState<string | null>(null)
  if (servicios.length === 0) {
    return <p className="py-10 text-center text-sm text-gray-400">No hay servicios en el período.</p>
  }
  return (
    <Card>
      <CardContent className="p-0">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-left text-xs uppercase text-gray-500">
              <tr>
                <th className="px-3 py-2">Equipo</th>
                <th className="px-3 py-2">Servicio</th>
                <th className="px-3 py-2 text-right">A las</th>
                <th className="px-3 py-2 text-right">Faltan</th>
                <th className="px-3 py-2">Fecha estimada</th>
                <th className="px-3 py-2">Operaciones</th>
                <th className="px-3 py-2">Repuestos</th>
                <th className="w-8" />
              </tr>
            </thead>
            <tbody className="divide-y">
              {servicios.map((s) => {
                const opsModelo = ops.filter((o) => o.modelo_id === s.modelo_id)
                const repsModelo = reps.filter((r) => r.modelo_id === s.modelo_id)
                const kit = kitDelServicio(s.n_servicio, opsModelo, repsModelo)
                const sinRep = kit.operaciones.filter((o) => o.accion === 'sustituir'
                  && !kit.repuestos.some((r) => r.operacion_id === o.id)).length
                const faltaStock = kit.repuestos.filter((r) => r.producto_id && (r.stock_total ?? 0) < r.cantidad).length
                const key = `${s.activo_id}-${s.n_servicio}`
                const open = abierto === key
                return (
                  <FilaServicio key={key} s={s} kit={kit} sinRep={sinRep} faltaStock={faltaStock}
                                open={open} onToggle={() => setAbierto(open ? null : key)} />
                )
              })}
            </tbody>
          </table>
        </div>
      </CardContent>
    </Card>
  )
}

function FilaServicio({ s, kit, sinRep, faltaStock, open, onToggle }: {
  s: ServicioProyectado; kit: { operaciones: Operacion[]; repuestos: Repuesto[] }
  sinRep: number; faltaStock: number; open: boolean; onToggle: () => void
}) {
  return (
    <>
      <tr className="cursor-pointer hover:bg-gray-50" onClick={onToggle}>
        <td className="px-3 py-2">
          <div className="font-semibold text-gray-900">{s.patente ?? s.codigo}</div>
          <div className="text-xs text-gray-500">{s.modelo} · {s.faena ?? '—'}</div>
        </td>
        <td className="px-3 py-2">
          <span className="font-medium">N° {s.n_servicio}</span>
          {s.ot_abierta && s.orden === 0 && <div className="text-xs text-gray-500">{s.ot_abierta}</div>}
        </td>
        <td className="px-3 py-2 text-right tabular-nums">{n1(s.horas_servicio)} h</td>
        <td className={`px-3 py-2 text-right tabular-nums ${s.horas_faltan <= 0 ? 'font-semibold text-red-700' : ''}`}>
          {s.horas_faltan <= 0 ? `+${n1(-s.horas_faltan)} h atraso` : `${n1(s.horas_faltan)} h`}
        </td>
        <td className="px-3 py-2">{fecha(s.fecha_estimada)}</td>
        <td className="px-3 py-2">{kit.operaciones.length}</td>
        <td className="px-3 py-2">
          <span>{kit.repuestos.length}</span>
          {sinRep > 0 && (
            <span className="ml-2 rounded bg-amber-100 px-1.5 py-0.5 text-[10px] font-semibold text-amber-800"
                  title="Operaciones de sustitución sin repuestos cargados">{sinRep} sin lista</span>
          )}
          {faltaStock > 0 && (
            <span className="ml-1 rounded bg-red-100 px-1.5 py-0.5 text-[10px] font-semibold text-red-700">{faltaStock} sin stock</span>
          )}
        </td>
        <td className="px-2">{open ? <ChevronUp className="h-4 w-4 text-gray-400" /> : <ChevronDown className="h-4 w-4 text-gray-400" />}</td>
      </tr>
      {open && (
        <tr>
          <td colSpan={8} className="bg-gray-50 px-4 py-3">
            <div className="grid gap-4 md:grid-cols-2">
              <div>
                <p className="mb-1 text-xs font-semibold uppercase text-gray-500">Qué se hace</p>
                <ul className="space-y-1 text-sm">
                  {kit.operaciones.map((o) => (
                    <li key={o.id} className="flex gap-2">
                      <span className="w-20 shrink-0 text-xs text-gray-500">{ACCION[o.accion]}</span>
                      <span>{o.operacion}{o.cada_servicios > 1 && <span className="text-xs text-gray-400"> · cada {o.cada_servicios}</span>}</span>
                    </li>
                  ))}
                </ul>
              </div>
              <div>
                <p className="mb-1 text-xs font-semibold uppercase text-gray-500">Repuestos</p>
                {kit.repuestos.length === 0 ? (
                  <p className="text-sm italic text-gray-400">Aún no hay repuestos cargados para estas operaciones.</p>
                ) : (
                  <table className="w-full text-xs">
                    <tbody className="divide-y">
                      {kit.repuestos.map((r) => (
                        <tr key={r.id}>
                          <td className="py-1 pr-2 font-mono">{r.n_parte ?? '—'}</td>
                          <td className="py-1 pr-2">{r.descripcion}</td>
                          <td className="py-1 pr-2 text-right tabular-nums">{n1(r.cantidad)} {r.unidad}</td>
                          <td className={`py-1 text-right ${r.producto_id == null ? 'text-gray-400'
                            : (r.stock_total ?? 0) >= r.cantidad ? 'text-green-700' : 'font-semibold text-red-700'}`}>
                            {r.producto_id == null ? 'sin producto' : `stock ${n1(r.stock_total)}`}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>
            </div>
          </td>
        </tr>
      )}
    </>
  )
}

// ── Compras ─────────────────────────────────────────────────────────────────
type LineaCompra = {
  clave: string; n_parte: string | null; descripcion: string; unidad: string
  producto: string | null; stock: number | null; necesita: number; servicios: number; equipos: Set<string>
  costo: number | null
}

function TabCompras({ servicios, ops, reps, horizonte }: {
  servicios: ServicioProyectado[]; ops: Operacion[]; reps: Repuesto[]; horizonte: number
}) {
  const toast = useToast()
  const { lineas, sinLista } = useMemo(() => {
    const m = new Map<string, LineaCompra>()
    const sinLista = new Map<string, { modelo: string; operacion: string; veces: number }>()
    for (const s of servicios) {
      const kit = kitDelServicio(s.n_servicio,
        ops.filter((o) => o.modelo_id === s.modelo_id), reps.filter((r) => r.modelo_id === s.modelo_id))
      for (const o of kit.operaciones) {
        if (o.accion === 'sustituir' && !kit.repuestos.some((r) => r.operacion_id === o.id)) {
          const k = `${s.modelo}|${o.operacion}`
          const x = sinLista.get(k) ?? { modelo: s.modelo, operacion: o.operacion, veces: 0 }
          x.veces++; sinLista.set(k, x)
        }
      }
      for (const r of kit.repuestos) {
        const k = claveRepuesto(r)
        const l = m.get(k) ?? {
          clave: k, n_parte: r.n_parte, descripcion: r.descripcion, unidad: r.unidad,
          producto: r.producto_codigo ? `${r.producto_codigo} · ${r.producto_nombre}` : null,
          stock: r.producto_id ? Number(r.stock_total ?? 0) : null, necesita: 0, servicios: 0,
          equipos: new Set<string>(), costo: r.costo_unitario_actual,
        }
        l.necesita += Number(r.cantidad); l.servicios++; l.equipos.add(s.patente ?? s.codigo ?? '')
        m.set(k, l)
      }
    }
    return {
      lineas: Array.from(m.values()).sort((a, b) =>
        (b.necesita - (b.stock ?? 0)) - (a.necesita - (a.stock ?? 0)) || a.descripcion.localeCompare(b.descripcion)),
      sinLista: Array.from(sinLista.values()).sort((a, b) => b.veces - a.veces),
    }
  }, [servicios, ops, reps])

  const exportar = async () => {
    try {
      const ExcelJS = (await import('exceljs')).default
      const wb = new ExcelJS.Workbook()
      const ws = wb.addWorksheet(`Compras ${horizonte} días`)
      ws.columns = [
        { header: 'N° parte', key: 'np', width: 16 }, { header: 'Descripción', key: 'd', width: 40 },
        { header: 'Producto bodega', key: 'p', width: 36 }, { header: 'Unidad', key: 'u', width: 8 },
        { header: 'Se necesita', key: 'n', width: 12 }, { header: 'Stock', key: 's', width: 10 },
        { header: 'Comprar', key: 'c', width: 10 }, { header: 'Servicios', key: 'sv', width: 10 },
        { header: 'Equipos', key: 'e', width: 40 },
      ]
      ws.getRow(1).font = { bold: true }
      for (const l of lineas) {
        ws.addRow({ np: l.n_parte, d: l.descripcion, p: l.producto, u: l.unidad, n: l.necesita,
          s: l.stock, c: Math.max(0, l.necesita - (l.stock ?? 0)), sv: l.servicios, e: Array.from(l.equipos).join(', ') })
      }
      const ws2 = wb.addWorksheet('Servicios')
      ws2.columns = [
        { header: 'Equipo', key: 'p', width: 12 }, { header: 'Modelo', key: 'm', width: 12 },
        { header: 'Servicio N°', key: 'n', width: 11 }, { header: 'A las (h)', key: 'h', width: 10 },
        { header: 'Fecha estimada', key: 'f', width: 14 }, { header: 'Faena', key: 'fa', width: 28 },
      ]
      ws2.getRow(1).font = { bold: true }
      for (const s of servicios) {
        ws2.addRow({ p: s.patente ?? s.codigo, m: s.modelo, n: s.n_servicio, h: s.horas_servicio,
          f: s.fecha_estimada?.slice(0, 10) ?? 'sin ritmo', fa: s.faena })
      }
      if (sinLista.length) {
        const ws3 = wb.addWorksheet('Sin lista de repuestos')
        ws3.columns = [{ header: 'Modelo', key: 'm', width: 12 }, { header: 'Operación', key: 'o', width: 50 },
          { header: 'Veces en el período', key: 'v', width: 18 }]
        ws3.getRow(1).font = { bold: true }
        sinLista.forEach((x) => ws3.addRow({ m: x.modelo, o: x.operacion, v: x.veces }))
      }
      const buf = await wb.xlsx.writeBuffer()
      const url = URL.createObjectURL(new Blob([buf], {
        type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }))
      const a = document.createElement('a')
      a.href = url; a.download = `repuestos-proximos-${horizonte}-dias.xlsx`; a.click()
      URL.revokeObjectURL(url)
    } catch (e) { toast.error((e as Error).message) }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <p className="text-sm text-gray-600">
          {servicios.length} servicios en los próximos {horizonte} días · {lineas.length} repuestos distintos
        </p>
        <Button size="sm" variant="outline" className="ml-auto" onClick={exportar}>
          <Download className="mr-1 h-4 w-4" /> Excel
        </Button>
      </div>

      {sinLista.length > 0 && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800">
          <p className="flex items-center gap-1 font-semibold">
            <AlertTriangle className="h-3.5 w-3.5" /> {sinLista.length} operaciones de sustitución sin lista de repuestos
          </p>
          <p className="mt-1">
            {sinLista.slice(0, 8).map((x) => `${x.modelo}: ${x.operacion}`).join(' · ')}
            {sinLista.length > 8 && ` · y ${sinLista.length - 8} más`}. Se cargan en «Programa por modelo».
          </p>
        </div>
      )}

      <Card>
        <CardContent className="p-0">
          {lineas.length === 0 ? (
            <p className="py-10 text-center text-sm text-gray-400">
              Todavía no hay repuestos cargados para los servicios del período.
            </p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 text-left text-xs uppercase text-gray-500">
                  <tr>
                    <th className="px-3 py-2">N° parte</th>
                    <th className="px-3 py-2">Descripción</th>
                    <th className="px-3 py-2">Producto bodega</th>
                    <th className="px-3 py-2 text-right">Se necesita</th>
                    <th className="px-3 py-2 text-right">Stock</th>
                    <th className="px-3 py-2 text-right">Comprar</th>
                    <th className="px-3 py-2">Equipos</th>
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {lineas.map((l) => {
                    const comprar = Math.max(0, l.necesita - (l.stock ?? 0))
                    return (
                      <tr key={l.clave}>
                        <td className="px-3 py-1.5 font-mono text-xs">{l.n_parte ?? '—'}</td>
                        <td className="px-3 py-1.5">{l.descripcion}</td>
                        <td className="px-3 py-1.5 text-xs text-gray-500">{l.producto ?? 'sin enlazar'}</td>
                        <td className="px-3 py-1.5 text-right tabular-nums">{n1(l.necesita)} {l.unidad}</td>
                        <td className="px-3 py-1.5 text-right tabular-nums">{l.stock == null ? '—' : n1(l.stock)}</td>
                        <td className={`px-3 py-1.5 text-right font-semibold tabular-nums ${comprar > 0 ? 'text-red-700' : 'text-green-700'}`}>
                          {comprar > 0 ? n1(comprar) : 'ok'}
                        </td>
                        <td className="px-3 py-1.5 text-xs text-gray-500">{Array.from(l.equipos).join(', ')}</td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

// ── Programa por modelo ─────────────────────────────────────────────────────
function TabPrograma({ ops, reps, programas, puedeEditar }: {
  ops: Operacion[]; reps: Repuesto[]
  programas: { modelo_id: string; intervalo_horas: number; fuente: string | null
               modelo: { nombre: string; marca: { nombre: string } | null } | null }[]
  puedeEditar: boolean
}) {
  const qc = useQueryClient()
  const toast = useToast()
  const modelos = useQuery({ queryKey: ['modelos-todos'], queryFn: getModelos, staleTime: 30 * 60_000 })
  const [modeloId, setModeloId] = useState<string>(programas[0]?.modelo_id ?? '')
  const [editOp, setEditOp] = useState<Operacion | 'nueva' | null>(null)
  const [editRep, setEditRep] = useState<Operacion | null>(null)

  const prog = programas.find((p) => p.modelo_id === modeloId)
  const opsModelo = ops.filter((o) => o.modelo_id === modeloId)
  const repsModelo = reps.filter((r) => r.modelo_id === modeloId)
  const columnas = Array.from({ length: 12 }, (_, i) => i + 1)
  const intervalo = prog?.intervalo_horas ?? 300

  const refrescar = () => {
    qc.invalidateQueries({ queryKey: ['programa-operaciones'] })
    qc.invalidateQueries({ queryKey: ['programa-repuestos'] })
    qc.invalidateQueries({ queryKey: ['programas-servicio'] })
    qc.invalidateQueries({ queryKey: ['servicios-proyectados'] })
  }

  const conPrograma = new Set(programas.map((p) => p.modelo_id))
  const nombreModelo = (id: string) => {
    const p = programas.find((x) => x.modelo_id === id)
    if (p?.modelo) return `${p.modelo.marca?.nombre ?? ''} ${p.modelo.nombre}`.trim()
    const m = modelos.data?.find((x) => x.id === id)
    return m ? `${m.marca ?? ''} ${m.nombre}`.trim() : id
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <select value={modeloId} onChange={(e) => setModeloId(e.target.value)}
                className="rounded border px-2 py-1.5 text-sm">
          <optgroup label="Con programa">
            {programas.map((p) => <option key={p.modelo_id} value={p.modelo_id}>{nombreModelo(p.modelo_id)}</option>)}
          </optgroup>
          {puedeEditar && (
            <optgroup label="Sin programa (agregar)">
              {(modelos.data ?? []).filter((m) => !conPrograma.has(m.id)).map((m) => (
                <option key={m.id} value={m.id}>{`${m.marca ?? ''} ${m.nombre}`.trim()}</option>
              ))}
            </optgroup>
          )}
        </select>
        <span className="text-sm text-gray-600">
          Servicio cada <b>{n1(intervalo)} h</b>{prog?.fuente && <span className="text-xs text-gray-400"> · {prog.fuente}</span>}
        </span>
        {puedeEditar && modeloId && (
          <>
            <Button size="sm" variant="ghost" onClick={async () => {
              const v = window.prompt('Intervalo entre servicios (horas)', String(intervalo))
              const h = v ? Number(v.replace(',', '.')) : NaN
              if (!Number.isFinite(h) || h <= 0) return
              try { await fijarIntervalo(modeloId, h); refrescar(); toast.success('Intervalo guardado') }
              catch (e) { toast.error((e as Error).message) }
            }}>
              <Pencil className="mr-1 h-3.5 w-3.5" /> Intervalo
            </Button>
            <Button size="sm" className="ml-auto" onClick={() => setEditOp('nueva')}>
              <Plus className="mr-1 h-4 w-4" /> Operación
            </Button>
          </>
        )}
      </div>

      <Card>
        <CardContent className="p-0">
          {opsModelo.length === 0 ? (
            <p className="py-10 text-center text-sm text-gray-400">Este modelo no tiene operaciones cargadas.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 text-xs text-gray-500">
                  <tr>
                    <th className="px-3 py-2 text-left uppercase">Operación</th>
                    <th className="px-2 py-2 text-center uppercase">Cada</th>
                    {columnas.map((n) => (
                      <th key={n} className="w-10 px-1 py-2 text-center font-normal">
                        <div className="font-semibold text-gray-700">{n}</div>
                        <div className="text-[9px]">{NUM.format(n * intervalo)}</div>
                      </th>
                    ))}
                    <th className="px-3 py-2 text-left uppercase">Repuestos</th>
                    {puedeEditar && <th className="w-16" />}
                  </tr>
                </thead>
                <tbody className="divide-y">
                  {opsModelo.map((o) => {
                    const rs = repsModelo.filter((r) => r.operacion_id === o.id)
                    return (
                      <tr key={o.id} className="hover:bg-gray-50">
                        <td className="px-3 py-1.5">
                          <div>{o.operacion}</div>
                          {o.nota && <div className="text-[11px] text-gray-400">{o.nota}</div>}
                        </td>
                        <td className="px-2 py-1.5 text-center text-xs">{o.cada_servicios}</td>
                        {columnas.map((n) => (
                          <td key={n} className="px-1 py-1.5 text-center">
                            {tocaEnServicio(o, n) && <span className="inline-block h-2.5 w-2.5 rounded-full bg-pillado-green-500" />}
                          </td>
                        ))}
                        <td className="px-3 py-1.5">
                          <button type="button" onClick={() => setEditRep(o)}
                            className={`text-xs font-medium hover:underline ${rs.length ? 'text-blue-600'
                              : o.accion === 'sustituir' ? 'text-amber-700' : 'text-gray-400'}`}>
                            {rs.length ? `${rs.length} repuesto${rs.length > 1 ? 's' : ''}`
                              : puedeEditar ? 'Cargar' : 'sin lista'}
                          </button>
                        </td>
                        {puedeEditar && (
                          <td className="px-2 py-1.5 text-right">
                            <button type="button" title="Editar" onClick={() => setEditOp(o)}
                                    className="p-1 text-gray-400 hover:text-gray-700"><Pencil className="h-3.5 w-3.5" /></button>
                            <button type="button" title="Quitar" className="p-1 text-gray-400 hover:text-red-600"
                              onClick={async () => {
                                if (!window.confirm(`¿Quitar «${o.operacion}» del programa?`)) return
                                try { await quitarOperacion(o.id); refrescar() } catch (e) { toast.error((e as Error).message) }
                              }}><Trash2 className="h-3.5 w-3.5" /></button>
                          </td>
                        )}
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      {editOp && (
        <ModalOperacion op={editOp === 'nueva' ? null : editOp} modeloId={modeloId}
                        onClose={() => setEditOp(null)} onListo={() => { setEditOp(null); refrescar() }} />
      )}
      {editRep && (
        <ModalRepuestos op={editRep} actuales={repsModelo.filter((r) => r.operacion_id === editRep.id)}
                        puedeEditar={puedeEditar}
                        onClose={() => setEditRep(null)} onListo={() => { setEditRep(null); refrescar() }} />
      )}
    </div>
  )
}

function ModalOperacion({ op, modeloId, onClose, onListo }: {
  op: Operacion | null; modeloId: string; onClose: () => void; onListo: () => void
}) {
  const toast = useToast()
  const [texto, setTexto] = useState(op?.operacion ?? '')
  const [accion, setAccion] = useState<AccionOperacion>(op?.accion ?? 'sustituir')
  const [cada, setCada] = useState(String(op?.cada_servicios ?? 1))
  const [nota, setNota] = useState(op?.nota ?? '')
  const [busy, setBusy] = useState(false)
  const n = Number(cada)
  const valido = texto.trim().length >= 3 && Number.isInteger(n) && n >= 1 && n <= 100

  const guardar = async () => {
    setBusy(true)
    try {
      await guardarOperacion({ id: op?.id ?? null, modeloId, operacion: texto.trim(), accion,
        cada: n, nota: nota.trim() || null, orden: op?.orden ?? null })
      toast.success('Operación guardada'); onListo()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  return (
    <Modal open onClose={onClose} title={op ? 'Editar operación' : 'Nueva operación'}>
      <div className="space-y-3">
        <label className="block text-xs font-medium text-gray-600">Operación
          <input value={texto} onChange={(e) => setTexto(e.target.value)}
                 className="mt-1 w-full rounded border px-2 py-1.5 text-sm" placeholder="Ej: Filtro de combustible, sustituir" />
        </label>
        <div className="grid grid-cols-2 gap-3">
          <label className="text-xs font-medium text-gray-600">Acción
            <select value={accion} onChange={(e) => setAccion(e.target.value as AccionOperacion)}
                    className="mt-1 w-full rounded border px-2 py-1.5 text-sm">
              {Object.entries(ACCION).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </label>
          <label className="text-xs font-medium text-gray-600">Cada cuántos servicios
            <input inputMode="numeric" value={cada} onChange={(e) => setCada(e.target.value)}
                   className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
          </label>
        </div>
        {Number.isInteger(n) && n >= 1 && (
          <p className="text-[11px] text-gray-500">
            Toca en los servicios {[1, 2, 3, 4].map((k) => k * n).join(', ')}…
          </p>
        )}
        <label className="block text-xs font-medium text-gray-600">Nota (opcional)
          <input value={nota} onChange={(e) => setNota(e.target.value)}
                 className="mt-1 w-full rounded border px-2 py-1.5 text-sm" />
        </label>
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancelar</Button>
          <Button disabled={!valido || busy} loading={busy} onClick={guardar}>Guardar</Button>
        </div>
      </div>
    </Modal>
  )
}

function ModalRepuestos({ op, actuales, puedeEditar, onClose, onListo }: {
  op: Operacion; actuales: Repuesto[]; puedeEditar: boolean; onClose: () => void; onListo: () => void
}) {
  const toast = useToast()
  const [filas, setFilas] = useState<RepuestoInput[]>(actuales.map((r) => ({
    n_parte: r.n_parte, descripcion: r.descripcion, cantidad: Number(r.cantidad), unidad: r.unidad,
    producto_id: r.producto_id,
  })))
  const [pegado, setPegado] = useState('')
  const [busy, setBusy] = useState(false)

  const set = (i: number, campo: keyof RepuestoInput, v: string) => setFilas((fs) => fs.map((f, j) => j !== i ? f
    : { ...f, [campo]: campo === 'cantidad' ? Number(v.replace(',', '.')) : v,
        // Cambiar el N° de parte suelta el producto: se vuelve a buscar al guardar.
        ...(campo === 'n_parte' ? { producto_id: null } : {}) }))

  const agregarPegado = () => {
    const nuevas = parsearRepuestosPegados(pegado)
    if (!nuevas.length) { toast.error('No se reconoció ninguna fila: N° parte | Descripción | Cantidad | Unidad'); return }
    setFilas((fs) => [...fs, ...nuevas]); setPegado('')
  }

  const validas = filas.every((f) => f.descripcion.trim().length >= 2 && Number.isFinite(f.cantidad) && f.cantidad > 0)

  const guardar = async () => {
    setBusy(true)
    try {
      const n = await guardarRepuestos(op.id, filas.map((f) => ({
        ...f, n_parte: f.n_parte?.trim() || null, descripcion: f.descripcion.trim(), unidad: f.unidad?.trim() || 'un' })))
      toast.success(`${n} repuestos guardados`); onListo()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  return (
    <Modal open onClose={onClose} title={op.operacion} className="max-w-3xl">
      <div className="space-y-3">
        <p className="text-xs text-gray-500">
          Cada {op.cada_servicios} servicio{op.cada_servicios > 1 ? 's' : ''}. Cantidades por servicio y por equipo.
          Si el N° de parte aparece en un solo producto de bodega, se enlaza solo para ver el stock.
        </p>
        <table className="w-full text-sm">
          <thead className="text-left text-[11px] uppercase text-gray-500">
            <tr><th className="pb-1">N° parte</th><th className="pb-1">Descripción</th>
              <th className="w-20 pb-1">Cant.</th><th className="w-16 pb-1">Unidad</th><th className="pb-1">Bodega</th><th /></tr>
          </thead>
          <tbody>
            {filas.map((f, i) => {
              const act = actuales.find((a) => a.producto_id && a.producto_id === f.producto_id)
              return (
                <tr key={i}>
                  <td className="py-0.5 pr-1"><input disabled={!puedeEditar} value={f.n_parte ?? ''} onChange={(e) => set(i, 'n_parte', e.target.value)}
                    className="w-full rounded border px-1.5 py-1 font-mono text-xs" /></td>
                  <td className="py-0.5 pr-1"><input disabled={!puedeEditar} value={f.descripcion} onChange={(e) => set(i, 'descripcion', e.target.value)}
                    className="w-full rounded border px-1.5 py-1 text-xs" /></td>
                  <td className="py-0.5 pr-1"><input disabled={!puedeEditar} inputMode="decimal" value={Number.isFinite(f.cantidad) ? String(f.cantidad) : ''}
                    onChange={(e) => set(i, 'cantidad', e.target.value)} className="w-full rounded border px-1.5 py-1 text-right text-xs" /></td>
                  <td className="py-0.5 pr-1"><input disabled={!puedeEditar} value={f.unidad} onChange={(e) => set(i, 'unidad', e.target.value)}
                    className="w-full rounded border px-1.5 py-1 text-xs" /></td>
                  <td className="py-0.5 pr-1 text-[11px] text-gray-500">
                    {act ? `${act.producto_codigo} · stock ${n1(act.stock_total)}` : f.producto_id ? 'enlazado' : '—'}
                  </td>
                  <td>{puedeEditar && (
                    <button type="button" onClick={() => setFilas((fs) => fs.filter((_, j) => j !== i))}
                            className="p-1 text-gray-400 hover:text-red-600"><Trash2 className="h-3.5 w-3.5" /></button>
                  )}</td>
                </tr>
              )
            })}
            {filas.length === 0 && (
              <tr><td colSpan={6} className="py-3 text-center text-xs italic text-gray-400">Sin repuestos.</td></tr>
            )}
          </tbody>
        </table>

        {puedeEditar && (
          <>
            <Button size="sm" variant="ghost" onClick={() => setFilas((fs) => [...fs, { n_parte: '', descripcion: '', cantidad: 1, unidad: 'un' }])}>
              <Plus className="mr-1 h-3.5 w-3.5" /> Fila
            </Button>
            <div className="rounded-lg border border-dashed p-2">
              <p className="text-[11px] text-gray-500">
                Pegar desde Excel (columnas: <b>N° parte · Descripción · Cantidad · Unidad</b>)
              </p>
              <textarea rows={3} value={pegado} onChange={(e) => setPegado(e.target.value)}
                        className="mt-1 w-full rounded border px-2 py-1 font-mono text-xs" />
              <Button size="sm" variant="outline" disabled={!pegado.trim()} onClick={agregarPegado}>Agregar lo pegado</Button>
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={onClose}>Cancelar</Button>
              <Button disabled={!validas || busy} loading={busy} onClick={guardar}>Guardar repuestos</Button>
            </div>
          </>
        )}
      </div>
    </Modal>
  )
}
