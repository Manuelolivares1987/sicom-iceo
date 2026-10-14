'use client'

// Pauta trimestral por lugar (MIG591) — la planilla "Pauta_Lomas_Trimestral"
// dentro de SICOM: cada Truck Shop con sus 33 actividades por lugar
// (housekeeping, TK, sala de microfiltrado, racks), marcas x / P / RP / n/a
// por fecha y % de avance real y proyectado.
//
// Planificar con fecha deja la actividad en el «Plan de hoy» del mantenedor
// (/m/enex), que sigue viendo lo mismo de siempre: las tareas de ese día.

import { Fragment, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ChevronLeft, ChevronRight, ClipboardList, FileSpreadsheet, Loader2, CalendarRange, FileText, X } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import {
  getFaenas, getFaenasConLugares, getLugarItems, getActividadesTrimestre, setActividadesTrimestre, sincronizarTrimestre,
  getInformesPdfDe, type EnexLugarItem, type EnexActividadTrimestre, type EstadoActividad,
} from '@/lib/services/enex'
import {
  avancePorArea, columnasFecha, fechaDe, MARCA_DE, trimestreCalendario, moverTrimestre, etiquetaTrimestre, type AvanceArea,
} from '@/lib/enex-pauta-lugar'
import { isoDe } from '@/lib/enex-avance'

const ROLES_GESTION = ['administrador', 'subgerente_operaciones', 'jefe_operaciones', 'supervisor', 'planificador', 'jefe_mantenimiento']
const ESTILO_MARCA: Record<string, string> = {
  x: 'bg-green-600 text-white', P: 'bg-blue-100 text-blue-800 ring-1 ring-inset ring-blue-300',
  RP: 'bg-amber-300 text-amber-950', 'n/a': 'bg-gray-200 text-gray-600',
}
const fmt = (n: number | null) => (n == null ? '—' : `${n.toLocaleString('es-CL', { maximumFractionDigits: 1 })} %`)
const dm = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`

export default function PautaTrimestralPage() {
  const { perfil } = useRequireAuth()
  const qc = useQueryClient()
  const toast = useToast()
  const puedeEditar = !!perfil?.rol && ROLES_GESTION.includes(perfil.rol)
  const [hoy, setHoy] = useState('')
  const [trim, setTrim] = useState('')
  useEffect(() => { const h = isoDe(new Date()); setHoy(h); setTrim(trimestreCalendario(h)) }, [])
  const [faenaId, setFaenaId] = useState<string | null>(null)
  const [areaSel, setAreaSel] = useState<string>('todas')
  const [sel, setSel] = useState<Set<string>>(new Set())

  const { data: faenas = [] } = useQuery({ queryKey: ['enex-faenas'], queryFn: getFaenas, staleTime: 5 * 60_000 })
  const { data: conLugares = [] } = useQuery({ queryKey: ['enex-faenas-lugares'], queryFn: getFaenasConLugares, staleTime: 5 * 60_000 })
  const faenasPauta = faenas.filter((f) => conLugares.includes(f.id))
  useEffect(() => {
    if (!faenaId && faenasPauta.length) setFaenaId((faenasPauta.find((f) => f.codigo === 'LB_LUB') ?? faenasPauta[0]).id)
  }, [faenasPauta, faenaId])

  const { data: items = [] } = useQuery({
    queryKey: ['enex-lugar-items', faenaId], queryFn: () => getLugarItems(faenaId!), enabled: !!faenaId, staleTime: 5 * 60_000,
  })
  // Al abrir, lo registrado en los informes de terreno marca lo ejecutado.
  const { data: acts = [], isLoading } = useQuery({
    queryKey: ['enex-trim-acts', faenaId, trim, items.length],
    enabled: !!faenaId && !!trim && items.length > 0,
    queryFn: async () => {
      try { await sincronizarTrimestre(faenaId!, trim) } catch { /* sin conexión o sin permiso: se muestra lo guardado */ }
      return getActividadesTrimestre(items.map((i) => i.lugar_item_id), trim)
    },
  })
  const { data: pdfs = {} } = useQuery({
    queryKey: ['enex-trim-pdfs', acts.map((a) => a.ejecucion_id).filter(Boolean).join(',')],
    queryFn: () => getInformesPdfDe(acts.map((a) => a.ejecucion_id).filter(Boolean) as string[]),
    enabled: acts.some((a) => a.ejecucion_id),
  })
  const recargar = () => qc.invalidateQueries({ queryKey: ['enex-trim-acts'] })

  const areas = useMemo(() => Array.from(new Set(items.map((i) => i.area))), [items])
  const itemsVista = items.filter((i) => areaSel === 'todas' || i.area === areaSel)
  const actPorItem = useMemo(() => new Map(acts.map((a) => [a.lugar_item_id, a])), [acts])
  const actsVista = acts.filter((a) => itemsVista.some((i) => i.lugar_item_id === a.lugar_item_id))
  const fechas = columnasFecha(actsVista)
  const avance = useMemo(() => avancePorArea(items, acts, hoy), [items, acts, hoy])

  // Agrupar por área y lugar, en el orden de la planilla.
  const grupos = useMemo(() => {
    const out: { area: string; lugar: string; obs: string | null; items: EnexLugarItem[] }[] = []
    for (const it of itemsVista) {
      let g = out.find((x) => x.area === it.area && x.lugar === it.lugar)
      if (!g) { g = { area: it.area, lugar: it.lugar, obs: it.lugar_observacion, items: [] }; out.push(g) }
      g.items.push(it)
    }
    return out
  }, [itemsVista])

  function toggle(ids: string[], on: boolean) {
    setSel((p) => { const n = new Set(p); ids.forEach((id) => (on ? n.add(id) : n.delete(id))); return n })
  }

  if (!trim || !hoy) return <div className="flex justify-center p-10"><Spinner /></div>
  const faena = faenas.find((f) => f.id === faenaId)

  return (
    <div className="space-y-4 pb-24">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-xl font-bold"><ClipboardList className="h-5 w-5 text-blue-700" /> Pauta trimestral por lugar</h1>
          <p className="mt-0.5 text-sm text-gray-500">
            Actividades de la pauta por lugar y fecha (x ejecutado · P planificado · RP reprogramado · n/a no aplica).
            Lo que planificas le aparece al mantenedor en «Plan de hoy» ese día.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link href="/dashboard/enex/planificacion"><Button variant="outline"><CalendarRange className="mr-1 h-4 w-4" /> Planificación</Button></Link>
          <Link href="/dashboard/enex/informe-trimestral"><Button variant="outline"><FileText className="mr-1 h-4 w-4" /> Informe trimestral</Button></Link>
          <Button variant="outline" disabled={items.length === 0}
                  onClick={() => exportar(items, acts, trim, faena?.nombre ?? '', avance.areas)}>
            <FileSpreadsheet className="mr-1 h-4 w-4" /> Exportar Excel
          </Button>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        {faenasPauta.length > 1 && (
          <select value={faenaId ?? ''} onChange={(e) => { setFaenaId(e.target.value); setSel(new Set()) }} className="rounded-lg border px-2 py-1.5 text-sm">
            {faenasPauta.map((f) => <option key={f.id} value={f.id}>{f.nombre}</option>)}
          </select>
        )}
        {faenasPauta.length === 1 && <span className="text-sm font-semibold">{faena?.nombre}</span>}
        <button onClick={() => { setTrim(moverTrimestre(trim, -1)); setSel(new Set()) }} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50" aria-label="Trimestre anterior"><ChevronLeft className="h-4 w-4" /></button>
        <span className="min-w-[150px] text-center text-sm font-semibold">{etiquetaTrimestre(trim)}</span>
        <button onClick={() => { setTrim(moverTrimestre(trim, 1)); setSel(new Set()) }} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50" aria-label="Trimestre siguiente"><ChevronRight className="h-4 w-4" /></button>
        <div className="flex overflow-hidden rounded-lg border">
          {['todas', ...areas].map((a) => (
            <button key={a} onClick={() => setAreaSel(a)}
                    className={`px-2.5 py-1.5 text-xs font-semibold ${areaSel === a ? 'bg-blue-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>
              {a === 'todas' ? 'Todo' : a.replace('Truck Shop ', '')}
            </button>
          ))}
        </div>
        {isLoading && <Spinner className="h-4 w-4" />}
      </div>

      {/* Avance por Truck Shop y total */}
      <div className="grid gap-2 md:grid-cols-3">
        {[...avance.areas, ...(avance.areas.length > 1 ? [avance.total] : [])].map((a) => <TarjetaArea key={a.area} a={a} />)}
      </div>

      <Card><CardContent className="p-0">
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-xs">
            <thead>
              <tr className="border-b bg-gray-50 text-[11px] text-gray-600">
                {puedeEditar && <th className="w-8 p-2" />}
                <th className="w-12 p-2 text-left">Ítem</th>
                <th className="p-2 text-left">Actividad</th>
                {fechas.map((f) => <th key={f} className={`w-14 border-l p-1 text-center ${f === hoy ? 'bg-blue-50' : ''}`}>{dm(f)}</th>)}
                <th className="border-l p-2 text-left">Comentario / informe</th>
              </tr>
            </thead>
            <tbody>
              {grupos.map((g) => {
                const ids = g.items.map((i) => i.lugar_item_id)
                const todos = ids.every((id) => sel.has(id))
                return (
                  <Fragment key={`${g.area}|${g.lugar}`}>
                    <tr className="border-b bg-slate-100">
                      {puedeEditar && (
                        <td className="p-2 text-center"><input type="checkbox" checked={todos} onChange={(e) => toggle(ids, e.target.checked)} aria-label={`Seleccionar ${g.lugar}`} /></td>
                      )}
                      <td colSpan={2 + fechas.length + 1} className="px-2 py-1 text-[11px] font-bold uppercase tracking-wide text-slate-700">
                        {areaSel === 'todas' ? `${g.area} · ` : ''}{g.lugar}
                        {g.obs && <span className={`ml-2 rounded px-1.5 py-0.5 text-[10px] normal-case ${/no operativa/i.test(g.obs) ? 'bg-red-100 text-red-700' : 'bg-gray-200 text-gray-600'}`}>{g.obs}</span>}
                      </td>
                    </tr>
                    {g.items.map((it) => {
                      const a = actPorItem.get(it.lugar_item_id)
                      const marca = a ? MARCA_DE[a.estado] : ''
                      const f = fechaDe(a)
                      const atrasada = !!a && (a.estado === 'planificada' || a.estado === 'reprogramada') && !!a.fecha_plan && a.fecha_plan < hoy
                      const pdf = a?.ejecucion_id ? pdfs[a.ejecucion_id] : null
                      return (
                        <tr key={it.lugar_item_id} className={`border-b hover:bg-gray-50 ${sel.has(it.lugar_item_id) ? 'bg-blue-50/60' : ''}`}
                            onClick={() => puedeEditar && toggle([it.lugar_item_id], !sel.has(it.lugar_item_id))}>
                          {puedeEditar && (
                            <td className="p-2 text-center" onClick={(e) => e.stopPropagation()}>
                              <input type="checkbox" checked={sel.has(it.lugar_item_id)} onChange={(e) => toggle([it.lugar_item_id], e.target.checked)} aria-label={`Seleccionar ${it.codigo}`} />
                            </td>
                          )}
                          <td className="p-2 font-mono text-gray-500">{it.codigo}</td>
                          <td className="p-2 text-gray-800">
                            {it.descripcion}
                            {it.observacion && <span className="ml-1 text-gray-500">({it.observacion})</span>}
                          </td>
                          {fechas.map((col) => (
                            <td key={col} className={`border-l p-0.5 text-center ${col === hoy ? 'bg-blue-50' : ''}`}>
                              {f === col && marca && (
                                <span className={`inline-block min-w-[30px] rounded px-1 py-0.5 text-[10px] font-bold ${atrasada ? 'bg-red-500 text-white' : ESTILO_MARCA[marca]}`}
                                      title={atrasada ? 'Atrasada: la fecha pasó sin ejecutar' : undefined}>
                                  {marca}
                                </span>
                              )}
                            </td>
                          ))}
                          <td className="border-l p-2 text-[11px] text-gray-500">
                            {a?.comentario}
                            {a?.estado === 'ejecutada' && (a.ejecucion_id
                              ? <>{a.comentario ? ' · ' : ''}{pdf ? <a href={pdf} target="_blank" rel="noreferrer" onClick={(e) => e.stopPropagation()} className="text-blue-600 underline">informe</a> : 'con informe'}</>
                              : <span className="text-amber-700">{a.comentario ? ' · ' : ''}sin informe en SICOM</span>)}
                          </td>
                        </tr>
                      )
                    })}
                  </Fragment>
                )
              })}
              {grupos.length === 0 && (
                <tr><td colSpan={4 + fechas.length} className="p-6 text-center text-gray-400">Esta faena no tiene pauta por lugar.</td></tr>
              )}
            </tbody>
            {fechas.length > 0 && (
              <tfoot>
                <tr className="border-t-2 text-[11px] font-semibold text-gray-600">
                  {puedeEditar && <td />}
                  <td colSpan={2} className="p-2 text-right">Actividades por fecha</td>
                  {fechas.map((col) => <td key={col} className="border-l p-1 text-center tabular-nums">{actsVista.filter((a) => fechaDe(a) === col && a.estado !== 'pendiente').length}</td>)}
                  <td className="border-l" />
                </tr>
              </tfoot>
            )}
          </table>
        </div>
      </CardContent></Card>

      {puedeEditar && sel.size > 0 && (
        <BarraAcciones n={sel.size} hoy={hoy}
                       onCancelar={() => setSel(new Set())}
                       onAplicar={async (estado, fecha, comentario) => {
                         try {
                           const r = await setActividadesTrimestre({ lugarItemIds: Array.from(sel), trimestreInicio: trim, estado, fecha, comentario })
                           toast.success(`${r.actualizadas} actividad${r.actualizadas === 1 ? '' : 'es'} actualizada${r.actualizadas === 1 ? '' : 's'}${estado === 'planificada' || estado === 'reprogramada' ? ' — el mantenedor las verá ese día' : ''}`)
                           if (r.plan_en_borrador) toast.error('El plan semanal de esa fecha está en borrador: publícalo en «Plan semanal» para que el mantenedor lo vea')
                           setSel(new Set()); recargar()
                         } catch (e) { toast.error((e as Error).message) }
                       }} />
      )}
    </div>
  )
}

function TarjetaArea({ a }: { a: AvanceArea }) {
  return (
    <div className={`rounded-xl border p-3 ${a.area === 'Total' ? 'border-blue-300 bg-blue-50/40' : 'bg-white'}`}>
      <div className="text-xs font-semibold text-gray-700">{a.area === 'Total' ? 'Total faena' : a.area}</div>
      <div className="mt-1 flex items-end gap-4">
        <div><div className="text-[10px] uppercase tracking-wide text-gray-500">Avance real</div><div className="text-2xl font-bold tabular-nums">{fmt(a.pctReal)}</div></div>
        <div><div className="text-[10px] uppercase tracking-wide text-gray-500">Proyectado</div><div className="text-lg font-semibold tabular-nums text-blue-700">{fmt(a.pctProyectado)}</div></div>
      </div>
      <div className="mt-1 text-[11px] text-gray-500">
        {a.ejecutadas} de {a.total} ejecutadas · {a.planificadas} planificadas
        {a.atrasadas > 0 && <span className="font-semibold text-red-700"> · {a.atrasadas} atrasadas</span>}
        {a.noAplica > 0 && ` · ${a.noAplica} n/a`} · {a.sinPlan} sin fecha
      </div>
    </div>
  )
}

function BarraAcciones({ n, hoy, onAplicar, onCancelar }: {
  n: number; hoy: string; onCancelar: () => void
  onAplicar: (estado: EstadoActividad, fecha: string | null, comentario: string | null) => Promise<void>
}) {
  const [fecha, setFecha] = useState(hoy)
  const [comentario, setComentario] = useState('')
  const [busy, setBusy] = useState<EstadoActividad | null>(null)
  const ir = async (estado: EstadoActividad, conFecha: boolean) => {
    setBusy(estado)
    try { await onAplicar(estado, conFecha ? fecha : null, comentario.trim() || null) } finally { setBusy(null) }
  }
  const B = ({ estado, label, conFecha, cls }: { estado: EstadoActividad; label: string; conFecha: boolean; cls?: string }) => (
    <Button size="sm" variant="outline" className={cls} disabled={busy !== null || (conFecha && !fecha)} onClick={() => ir(estado, conFecha)}>
      {busy === estado && <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" />}{label}
    </Button>
  )
  return (
    <div className="fixed inset-x-0 bottom-0 z-40 border-t bg-white/95 p-3 shadow-lg backdrop-blur">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-2">
        <span className="text-sm font-semibold">{n} seleccionada{n === 1 ? '' : 's'}</span>
        <Input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} className="h-8 w-40" aria-label="Fecha" />
        <Input value={comentario} onChange={(e) => setComentario(e.target.value)} placeholder="Comentario (opcional)" className="h-8 w-56" />
        <B estado="planificada" label="P · Planificar" conFecha cls="border-blue-300 text-blue-800" />
        <B estado="reprogramada" label="RP · Reprogramar" conFecha cls="border-amber-300 text-amber-800" />
        <B estado="ejecutada" label="x · Ejecutada" conFecha cls="border-green-300 text-green-800" />
        <B estado="no_aplica" label="n/a" conFecha={false} />
        <B estado="pendiente" label="Limpiar" conFecha={false} cls="text-gray-500" />
        <button onClick={onCancelar} className="ml-auto rounded p-1 text-gray-500 hover:bg-gray-100" aria-label="Cancelar selección"><X className="h-4 w-4" /></button>
      </div>
    </div>
  )
}

// Excel con el mismo formato de la planilla: una hoja por Truck Shop.
async function exportar(items: EnexLugarItem[], acts: EnexActividadTrimestre[], trim: string, faena: string, avance: AvanceArea[]) {
  const ExcelJS = (await import('exceljs')).default
  const wb = new ExcelJS.Workbook()
  const porItem = new Map(acts.map((a) => [a.lugar_item_id, a]))
  const fill = (argb: string) => ({ type: 'pattern' as const, pattern: 'solid' as const, fgColor: { argb } })
  for (const area of Array.from(new Set(items.map((i) => i.area)))) {
    const its = items.filter((i) => i.area === area)
    const fechas = columnasFecha(acts.filter((a) => its.some((i) => i.lugar_item_id === a.lugar_item_id)))
    const ws = wb.addWorksheet(area.replace('Truck Shop ', '').toUpperCase().slice(0, 31))
    ws.getCell(1, 1).value = `PLAN DE MANTENIMIENTO INSTALACIONES LUBRICANTES – ACTIVIDADES TRIMESTRALES · ${faena} · ${area} · ${etiquetaTrimestre(trim)}`
    ws.getCell(1, 1).font = { bold: true }
    const head = ['Ítem', 'Lugar', 'Actividad a realizar', 'Periodicidad', ...fechas.map((f) => dm(f)), 'Comentario']
    head.forEach((h, k) => { const c = ws.getCell(3, k + 1); c.value = h; c.font = { bold: true }; c.fill = fill('FFD9E1F2') })
    let r = 4
    for (const it of its) {
      const a = porItem.get(it.lugar_item_id)
      const f = fechaDe(a)
      ws.getCell(r, 1).value = it.codigo
      ws.getCell(r, 2).value = it.lugar
      ws.getCell(r, 3).value = it.observacion ? `${it.descripcion} (${it.observacion})` : it.descripcion
      ws.getCell(r, 4).value = 'Trimestral'
      const k = f ? fechas.indexOf(f) : -1
      if (a && k >= 0 && MARCA_DE[a.estado]) {
        const c = ws.getCell(r, 5 + k)
        c.value = MARCA_DE[a.estado]
        c.alignment = { horizontal: 'center' }
        c.fill = fill(a.estado === 'ejecutada' ? 'FFC6E0B4' : a.estado === 'reprogramada' ? 'FFFFE699' : a.estado === 'planificada' ? 'FFDDEBF7' : 'FFEDEDED')
      }
      ws.getCell(r, 5 + fechas.length).value = a?.comentario ?? ''
      r++
    }
    const av = avance.find((x) => x.area === area)
    r++
    ws.getCell(r, 2).value = 'Total de actividades:'; ws.getCell(r, 3).value = its.length; r++
    ws.getCell(r, 2).value = 'Total avance real:'; ws.getCell(r, 3).value = av?.ejecutadas ?? 0; r++
    ws.getCell(r, 2).value = '% Avance real'; ws.getCell(r, 3).value = (av?.pctReal ?? 0) / 100; ws.getCell(r, 3).numFmt = '0.0%'; r++
    ws.getCell(r, 2).value = '% Avance proyectado'; ws.getCell(r, 3).value = (av?.pctProyectado ?? 0) / 100; ws.getCell(r, 3).numFmt = '0.0%'; r += 2
    ws.getCell(r, 2).value = 'P = planificado · x = ejecutado · RP = reprogramación · n/a = no aplica'
    ws.getColumn(1).width = 6; ws.getColumn(2).width = 30; ws.getColumn(3).width = 50; ws.getColumn(4).width = 11
    fechas.forEach((_, k) => { ws.getColumn(5 + k).width = 7 })
    ws.getColumn(5 + fechas.length).width = 40
  }
  const buf = await wb.xlsx.writeBuffer()
  const a = document.createElement('a')
  a.href = URL.createObjectURL(new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }))
  a.download = `Pauta_Trimestral_${faena.replace(/\W+/g, '_')}_${trim}.xlsx`
  a.click()
  URL.revokeObjectURL(a.href)
}
