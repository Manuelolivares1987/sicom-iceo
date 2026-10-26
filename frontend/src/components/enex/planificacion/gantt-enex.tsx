'use client'

// Gantt diaria ENEX (MIG590) — la planilla "Planificación diaria" dentro de la
// plataforma: instalación × día, códigos CMP / C / MP / CP, fines de semana y
// feriados en gris, color por estado. Cada celda son programaciones reales
// (enex_programaciones): lo que se planifica aquí es lo que el mantenedor ve
// ese día en /m/enex.

import { useEffect, useMemo, useRef, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ChevronDown, ChevronRight, Loader2, Trash2, CalendarClock, Truck, Redo2, MapPin } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useToast } from '@/contexts/toast-context'
import { ReprogramacionModal } from '@/components/enex/reprogramacion-modal'
import {
  programarLote, moverProgramacion, desprogramar, getReprogramaciones, TIPO_INSTALACION_LABEL,
  getFaenasConLugares, getLugarItems, getActividadesTrimestre, setActividadesTrimestre,
  type EnexFaena, type EnexInstalacion, type EnexPanelRow, type TipoServicio,
  type EnexLugarItem, type EnexActividadTrimestre,
} from '@/lib/services/enex'
import {
  codigoCelda, estadoProg, sumarDias, fechaDeIso, FERIADOS_CL, type EstadoProg, type Ventana,
} from '@/lib/enex-avance'

const ANCHO_DIA = 30
const DOW = ['d', 'l', 'm', 'x', 'j', 'v', 's']
const MES_CORTO = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic']

// Peor estado manda en la celda (lo que pide acción primero).
const PRIORIDAD: EstadoProg[] = ['atrasada', 'no_realizada', 'hoy', 'programada', 'sin_firma', 'cumplida']
const ESTILO: Record<EstadoProg, string> = {
  atrasada: 'bg-red-500 text-white',
  no_realizada: 'bg-red-100 text-red-700 line-through',
  hoy: 'bg-blue-600 text-white',
  programada: 'bg-blue-100 text-blue-800 ring-1 ring-inset ring-blue-300',
  sin_firma: 'bg-amber-300 text-amber-950',
  cumplida: 'bg-green-600 text-white',
}
export const LEYENDA_ESTADO: [EstadoProg, string][] = [
  ['programada', 'Programado'], ['hoy', 'Toca hoy'], ['cumplida', 'Cumplido (firma mandante)'],
  ['sin_firma', 'Hecho, falta firma'], ['atrasada', 'Atrasado'], ['no_realizada', 'No realizado'],
]

// [MIG651] Zona de Lomas Lubricantes (Instalaciones exteriores · Sala de
// microfiltrado · Racks): se planifica por día y sus actividades llegan al
// «Plan de hoy» del supervisor.
type Zona = { lugar_id: string; area: string; lugar: string; observacion: string | null; items: EnexLugarItem[] }

type FilaGantt =
  | { tipo: 'faena'; faena: EnexFaena; n: number }
  | { tipo: 'inst'; key: string; inst: EnexInstalacion; faena: EnexFaena; sub?: boolean }
  | { tipo: 'camiones'; key: string; faena: EnexFaena; camiones: EnexInstalacion[] }
  | { tipo: 'zona'; key: string; faena: EnexFaena; zona: Zona }

type FilaServicio = Exclude<FilaGantt, { tipo: 'faena' } | { tipo: 'zona' }>

type Seleccion =
  | { modo: 'programar'; fila: FilaServicio; fecha: string }
  | { modo: 'detalle'; fila: FilaServicio; fecha: string | null; rows: EnexPanelRow[] }
  | { modo: 'zona'; zona: Zona; fecha: string }

/** Primer día del trimestre calendario (Lomas mide por trimestre calendario). */
export function trimestreDe(iso: string): string {
  const m = Number(iso.slice(5, 7))
  return `${iso.slice(0, 4)}-${String(Math.floor((m - 1) / 3) * 3 + 1).padStart(2, '0')}-01`
}

export function GanttEnex({ rows, faenas, instalaciones, ventana, hoy, puedeEditar, onCambio }: {
  rows: EnexPanelRow[]; faenas: EnexFaena[]; instalaciones: EnexInstalacion[]
  ventana: Ventana; hoy: string; puedeEditar: boolean; onCambio: () => void
}) {
  const toast = useToast()
  const [abiertos, setAbiertos] = useState<Record<string, boolean>>({})
  const [sel, setSel] = useState<Seleccion | null>(null)
  // Programaciones con registro de reprogramación → fecha original (marca «RP» en la celda).
  const { data: reprogs = [] } = useQuery({ queryKey: ['enex-reprogramaciones'], queryFn: getReprogramaciones, staleTime: 60_000 })
  const reprogDe = useMemo(() => {
    const m = new Map<string, string>()
    for (const r of reprogs) if (r.programacion_id && !m.has(r.programacion_id)) m.set(r.programacion_id, r.fecha_original ?? '')
    return m
  }, [reprogs])
  const [arrastre, setArrastre] = useState<{ filaKey: string; ids: string[] } | null>(null)
  const [moviendo, setMoviendo] = useState(false)
  const scrollRef = useRef<HTMLDivElement>(null)

  const dias = useMemo(() => {
    const out: string[] = []
    for (let f = ventana.desde; f <= ventana.hasta; f = sumarDias(f, 1)) out.push(f)
    return out
  }, [ventana])

  const instPorId = useMemo(() => new Map(instalaciones.map((i) => [i.id, i])), [instalaciones])

  // ── Zonas (Lomas) ──────────────────────────────────────────────────────────
  const { data: faenasZonas = [] } = useQuery({ queryKey: ['enex-faenas-lugares'], queryFn: getFaenasConLugares, staleTime: 5 * 60_000 })
  const idsZonas = useMemo(() => faenas.filter((f) => faenasZonas.includes(f.id)).map((f) => f.id), [faenas, faenasZonas])
  const { data: lugarItems = [] } = useQuery({
    queryKey: ['enex-lugar-items-gantt', idsZonas],
    queryFn: async () => (await Promise.all(idsZonas.map((id) => getLugarItems(id)))).flat(),
    enabled: idsZonas.length > 0, staleTime: 5 * 60_000,
  })
  const trimestres = useMemo(() => {
    const out: string[] = []
    for (let q = trimestreDe(ventana.desde); q <= ventana.hasta;) {
      out.push(q)
      const m = Number(q.slice(5, 7)) + 3
      q = m > 12 ? `${Number(q.slice(0, 4)) + 1}-01-01` : `${q.slice(0, 4)}-${String(m).padStart(2, '0')}-01`
    }
    return out
  }, [ventana])
  const { data: actividades = [] } = useQuery({
    queryKey: ['enex-actividades-gantt', lugarItems.length, trimestres],
    queryFn: async () => (await Promise.all(trimestres.map((q) => getActividadesTrimestre(lugarItems.map((l) => l.lugar_item_id), q)))).flat(),
    enabled: lugarItems.length > 0, staleTime: 10_000,
  })
  const zonasPorFaena = useMemo(() => {
    const m = new Map<string, Zona[]>()
    for (const it of lugarItems) {
      const zs = m.get(it.faena_id) ?? []
      let z = zs.find((x) => x.lugar_id === it.lugar_id)
      if (!z) { z = { lugar_id: it.lugar_id, area: it.area, lugar: it.lugar, observacion: it.lugar_observacion, items: [] }; zs.push(z) }
      z.items.push(it)
      m.set(it.faena_id, zs)
    }
    return m
  }, [lugarItems])
  // Actividades por zona y día (plan o ejecución).
  const actsZona = useMemo(() => {
    const zonaDe = new Map(lugarItems.map((l) => [l.lugar_item_id, l.lugar_id]))
    const m = new Map<string, EnexActividadTrimestre[]>()
    for (const a of actividades) {
      const dia = a.estado === 'ejecutada' ? a.fecha_ejecucion : (a.estado === 'planificada' || a.estado === 'reprogramada') ? a.fecha_plan : null
      if (!dia) continue
      const k = `${zonaDe.get(a.lugar_item_id)}|${dia.slice(0, 10)}`
      m.set(k, [...(m.get(k) ?? []), a])
    }
    return m
  }, [actividades, lugarItems])
  const porReprogZona = useMemo(() => {
    const zonaDe = new Map(lugarItems.map((l) => [l.lugar_item_id, l.lugar_id]))
    const m = new Map<string, number>()
    for (const a of actividades) if (a.por_reprogramar_at && a.estado === 'pendiente') {
      const z = zonaDe.get(a.lugar_item_id)!
      m.set(z, (m.get(z) ?? 0) + 1)
    }
    return m
  }, [actividades, lugarItems])

  // Índices de celdas: por instalación y por grupo de camiones de la faena.
  const idx = useMemo(() => {
    const m = new Map<string, EnexPanelRow[]>()
    const push = (k: string, r: EnexPanelRow) => { const a = m.get(k) ?? []; a.push(r); m.set(k, a) }
    for (const r of rows) {
      const dia = r.fecha_programada?.slice(0, 10) ?? 'sin'
      push(`${r.instalacion_id}|${dia}`, r)
      if (r.instalacion_tipo === 'camion') push(`CAM:${r.faena_id}|${dia}`, r)
    }
    return m
  }, [rows])

  const filas = useMemo<FilaGantt[]>(() => {
    const out: FilaGantt[] = []
    for (const f of faenas) {
      const inst = instalaciones.filter((i) => i.faena_id === f.id)
      // Instalaciones de la ventana que ya no están en el maestro (dadas de baja) igual se muestran.
      const extra = Array.from(new Set(rows.filter((r) => r.faena_id === f.id && !instPorId.has(r.instalacion_id)).map((r) => r.instalacion_id)))
      const fijas = inst.filter((i) => i.tipo !== 'camion')
      // El camión por asignar va primero: es donde cae lo planificado sin patente.
      const camiones = inst.filter((i) => i.tipo === 'camion').sort((a, b) => Number(!!b.es_comodin) - Number(!!a.es_comodin))
      const n = rows.filter((r) => r.faena_id === f.id).length
      // Las zonas siguen el filtro de la vista (mundo/faena): se muestran si sus puntos están.
      const zonas = (zonasPorFaena.get(f.id) ?? []).filter((z) => z.items[0]?.instalacion_ids.some((id) => instPorId.has(id)))
      if (fijas.length === 0 && camiones.length === 0 && extra.length === 0 && zonas.length === 0) continue
      out.push({ tipo: 'faena', faena: f, n })
      for (const z of zonas) out.push({ tipo: 'zona', key: `Z:${z.lugar_id}`, faena: f, zona: z })
      for (const i of fijas) out.push({ tipo: 'inst', key: i.id, inst: i, faena: f })
      for (const id of extra) {
        const r = rows.find((x) => x.instalacion_id === id)!
        const fake = { id, faena_id: f.id, nombre: `${r.instalacion} (inactiva)`, tipo: r.instalacion_tipo, patente: r.patente } as EnexInstalacion
        if (r.instalacion_tipo !== 'camion') out.push({ tipo: 'inst', key: id, inst: fake, faena: f })
      }
      if (camiones.length > 0) {
        const key = `CAM:${f.id}`
        out.push({ tipo: 'camiones', key, faena: f, camiones })
        if (abiertos[key]) for (const c of camiones) out.push({ tipo: 'inst', key: c.id, inst: c, faena: f, sub: true })
      }
    }
    return out
  }, [faenas, instalaciones, rows, abiertos, instPorId, zonasPorFaena])

  // Al abrir, la Gantt se para en la semana actual (como mirar la planilla desde hoy).
  useEffect(() => {
    const i = dias.indexOf(hoy)
    if (i > 7 && scrollRef.current) scrollRef.current.scrollLeft = (i - 7) * ANCHO_DIA
  }, [dias, hoy])

  // Carga diaria (fila "Actividades por día" de la planilla) sobre las filas visibles.
  const carga = useMemo(() => {
    const m = new Map<string, number>()
    for (const r of rows) if (r.fecha_programada) m.set(r.fecha_programada.slice(0, 10), (m.get(r.fecha_programada.slice(0, 10)) ?? 0) + 1)
    return m
  }, [rows])
  const sinFechaTotal = rows.filter((r) => !r.fecha_programada).length

  // Semanas para el encabezado (S41 · 05 oct).
  const semanas = useMemo(() => {
    const out: { label: string; span: number }[] = []
    for (const d of dias) {
      const dt = fechaDeIso(d)
      if (out.length === 0 || dt.getDay() === 1) {
        out.push({ label: `S${semanaIso(dt)} · ${d.slice(8, 10)} ${MES_CORTO[dt.getMonth()]}`, span: 0 })
      }
      out[out.length - 1].span++
    }
    return out
  }, [dias])

  const celdaRows = (fila: FilaServicio, dia: string) =>
    idx.get(fila.tipo === 'camiones' ? `${fila.key}|${dia}` : `${fila.inst.id}|${dia}`) ?? []

  async function soltar(fila: FilaServicio, dia: string) {
    const a = arrastre
    setArrastre(null)
    if (!a || a.filaKey !== fila.key || !puedeEditar) return
    setMoviendo(true)
    try {
      for (const id of a.ids) await moverProgramacion(id, dia)
      toast.success(`${a.ids.length === 1 ? 'Servicio movido' : `${a.ids.length} servicios movidos`} al ${dia.slice(8, 10)}/${dia.slice(5, 7)}`)
      onCambio()
    } catch (e) { toast.error((e as Error).message) } finally { setMoviendo(false) }
  }

  return (
    <div className="relative">
      {moviendo && <div className="absolute inset-0 z-30 flex items-center justify-center bg-white/50"><Loader2 className="h-6 w-6 animate-spin text-blue-600" /></div>}
      <div ref={scrollRef} className="overflow-x-auto">
        <table className="border-collapse text-xs" style={{ minWidth: 260 + 56 + dias.length * ANCHO_DIA }}>
          <thead>
            <tr>
              <th rowSpan={3} className="sticky left-0 z-20 w-[260px] min-w-[260px] border-b border-r bg-white p-2 text-left align-bottom text-[11px] text-gray-500">Instalación / Equipo</th>
              <th rowSpan={3} className="w-14 min-w-[56px] border-b border-r bg-white p-1 text-center align-bottom text-[10px] text-gray-500" title="Programados en el mes sin día asignado">Sin fecha</th>
              {semanas.map((s, i) => (
                <th key={i} colSpan={s.span} className="border-b border-r bg-slate-700 px-1 py-1 text-left text-[10px] font-semibold text-white whitespace-nowrap overflow-hidden">{s.span >= 3 ? s.label : ''}</th>
              ))}
            </tr>
            <tr>
              {dias.map((d) => <th key={d} className={`border-r text-center text-[10px] font-semibold ${d === hoy ? 'bg-violet-600 text-white' : claseDia(d, hoy)}`} style={{ width: ANCHO_DIA, minWidth: ANCHO_DIA }}>{Number(d.slice(8, 10))}</th>)}
            </tr>
            <tr>
              {dias.map((d) => d === hoy
                ? <th key={d} className="border-b border-r bg-violet-600 text-center text-[9px] font-bold text-white" title="Hoy">HOY</th>
                : <th key={d} className={`border-b border-r text-center text-[10px] font-normal text-gray-500 ${claseDia(d, hoy)}`} title={FERIADOS_CL[d]}>{DOW[fechaDeIso(d).getDay()]}</th>)}
            </tr>
          </thead>
          <tbody>
            {filas.length === 0 && (
              <tr><td colSpan={dias.length + 2} className="p-6 text-center text-sm text-gray-400">No hay instalaciones en la selección.</td></tr>
            )}
            {filas.map((fila) => {
              if (fila.tipo === 'faena') {
                return (
                  <tr key={`F:${fila.faena.id}`}>
                    <td className="sticky left-0 z-10 border-b border-r bg-slate-100 px-2 py-1 text-[11px] font-bold uppercase tracking-wide text-slate-700">
                      {fila.faena.nombre} <span className="font-normal normal-case text-slate-500">· {fila.n} servicios</span>
                    </td>
                    <td colSpan={dias.length + 1} className="border-b bg-slate-100" />
                  </tr>
                )
              }
              if (fila.tipo === 'zona') {
                const z = fila.zona
                const pr = porReprogZona.get(z.lugar_id) ?? 0
                return (
                  <tr key={fila.key} className="group">
                    <td className="sticky left-0 z-10 w-[260px] max-w-[260px] border-b border-r bg-emerald-50/60 px-2 py-1 group-hover:bg-emerald-50">
                      <div className="truncate" title={`${z.area} · ${z.lugar}${z.observacion ? ` (${z.observacion})` : ''}`}>
                        <MapPin className="mr-1 inline h-3 w-3 text-emerald-600" />
                        <span className="font-medium text-gray-800">{z.lugar}</span>
                        <span className="ml-1 text-[10px] text-gray-500">{z.area.replace('Truck Shop ', 'TS ')}</span>
                        {pr > 0 && <span className="ml-1 rounded bg-orange-100 px-1 text-[9px] font-semibold text-orange-800" title="No se hizo en terreno: falta fecha nueva">{pr} por reprog.</span>}
                      </div>
                    </td>
                    <td className="border-b border-r" />
                    {dias.map((d) => {
                      const acts = actsZona.get(`${z.lugar_id}|${d}`) ?? []
                      const fondo = claseDia(d, hoy)
                      if (acts.length === 0) {
                        return (
                          <td key={d} className={`border-b border-r p-0 ${fondo}`}>
                            <button disabled={!puedeEditar} onClick={() => setSel({ modo: 'zona', zona: z, fecha: d })}
                                    className="block h-6 w-full hover:bg-emerald-50 disabled:cursor-default disabled:hover:bg-transparent"
                                    aria-label={`Planificar ${z.lugar} el ${d}`} />
                          </td>
                        )
                      }
                      const hechas = acts.filter((a) => a.estado === 'ejecutada').length
                      const estilo = hechas === acts.length ? ESTILO.cumplida
                        : d < hoy ? ESTILO.atrasada : d === hoy ? ESTILO.hoy : ESTILO.programada
                      return (
                        <td key={d} className={`border-b border-r p-0.5 ${fondo}`}>
                          <button onClick={() => setSel({ modo: 'zona', zona: z, fecha: d })}
                                  title={`${z.lugar}: ${acts.length} actividades${hechas ? ` · ${hechas} hechas` : ''}`}
                                  className={`block h-5 w-full rounded text-[9px] font-bold leading-5 ${estilo}`}>
                            {acts.length}
                          </button>
                        </td>
                      )
                    })}
                  </tr>
                )
              }
              const sinFecha = celdaRows(fila, 'sin')
              return (
                <tr key={fila.key} className="group">
                  <td className={`sticky left-0 z-10 w-[260px] max-w-[260px] border-b border-r bg-white px-2 py-1 group-hover:bg-gray-50 ${fila.tipo === 'inst' && fila.sub ? 'pl-7' : ''}`}>
                    {fila.tipo === 'camiones' ? (
                      <button className="flex w-full items-center gap-1 text-left font-medium text-gray-800"
                              onClick={() => setAbiertos((a) => ({ ...a, [fila.key]: !a[fila.key] }))}>
                        {abiertos[fila.key] ? <ChevronDown className="h-3.5 w-3.5" /> : <ChevronRight className="h-3.5 w-3.5" />}
                        <Truck className="h-3.5 w-3.5 text-gray-500" /> Calibración camiones ({fila.camiones.filter((c) => !c.es_comodin).length})
                      </button>
                    ) : (
                      <div className="truncate" title={fila.inst.nombre}>
                        <span className={`font-medium ${fila.inst.es_comodin ? 'italic text-blue-700' : 'text-gray-800'}`}>
                          {fila.inst.es_comodin ? 'Por asignar (patente en terreno)' : fila.inst.tipo === 'camion' ? (fila.inst.patente ?? fila.inst.nombre) : fila.inst.nombre}
                        </span>
                        {!fila.sub && <span className="ml-1 text-[10px] text-gray-400">{TIPO_INSTALACION_LABEL[fila.inst.tipo] ?? ''}</span>}
                        {fila.inst.creada_en_terreno && <span className="ml-1 rounded bg-amber-100 px-1 text-[9px] text-amber-800" title="Patente anotada en terreno: no estaba en el maestro">nuevo</span>}
                      </div>
                    )}
                  </td>
                  <td className="border-b border-r text-center">
                    {sinFecha.length > 0 && (
                      <button onClick={() => setSel({ modo: 'detalle', fila, fecha: null, rows: sinFecha })}
                              className="rounded bg-gray-200 px-1.5 text-[10px] font-semibold text-gray-700 hover:bg-gray-300"
                              title="Programado en el mes, sin día asignado: clic para asignarle día">{sinFecha.length}</button>
                    )}
                  </td>
                  {dias.map((d) => {
                    const rs = celdaRows(fila, d)
                    const fondo = claseDia(d, hoy)
                    if (rs.length === 0) {
                      return (
                        <td key={d} className={`border-b border-r p-0 ${fondo} ${arrastre?.filaKey === fila.key ? 'outline-dashed outline-1 outline-blue-300' : ''}`}
                            onDragOver={(e) => { if (arrastre?.filaKey === fila.key) e.preventDefault() }}
                            onDrop={() => soltar(fila, d)}>
                          <button disabled={!puedeEditar} onClick={() => setSel({ modo: 'programar', fila, fecha: d })}
                                  className="block h-6 w-full hover:bg-blue-50 disabled:cursor-default disabled:hover:bg-transparent"
                                  aria-label={`Programar el ${d}`} />
                        </td>
                      )
                    }
                    const estados = rs.map((r) => estadoProg(r, hoy))
                    const peor = PRIORIDAD.find((p) => estados.includes(p)) ?? 'programada'
                    const codigo = codigoCelda(rs.map((r) => ({ tipo_servicio: r.tipo_servicio, esCamion: r.instalacion_tipo === 'camion' && fila.tipo === 'camiones' })))
                    const movibles = rs.filter((r) => !r.ejecucion_id).map((r) => r.programacion_id)
                    const rp = rs.filter((r) => reprogDe.has(r.programacion_id)).map((r) => reprogDe.get(r.programacion_id) || 's/f')
                    // [MIG651] «No se hizo» en terreno (pedido ESM): falta fecha nueva.
                    const noHecho = rs.filter((r) => r.por_reprogramar_motivo && !r.ejecucion_id)
                    return (
                      <td key={d} className={`border-b border-r p-0.5 ${fondo}`}
                          onDragOver={(e) => { if (arrastre?.filaKey === fila.key) e.preventDefault() }}
                          onDrop={() => soltar(fila, d)}>
                        <button
                          draggable={puedeEditar && movibles.length === rs.length}
                          onDragStart={(e) => { e.dataTransfer.effectAllowed = 'move'; setArrastre({ filaKey: fila.key, ids: movibles }) }}
                          onDragEnd={() => setArrastre(null)}
                          onClick={() => setSel({ modo: 'detalle', fila, fecha: d, rows: rs })}
                          title={tooltipCelda(rs, hoy, instPorId) + (rp.length ? `\nReprogramado (fecha original ${rp.join(', ')})` : '')
                                 + (noHecho.length ? `\nNo se hizo en terreno: ${noHecho[0].por_reprogramar_motivo} — falta fecha nueva` : '')}
                          className={`relative block h-5 w-full rounded text-[9px] font-bold leading-5 ${noHecho.length === rs.length ? 'bg-orange-100 text-orange-800 line-through ring-1 ring-inset ring-orange-400' : ESTILO[peor]}`}>
                          {codigo}
                          {noHecho.length > 0 && <span className="absolute -left-0.5 -top-1 rounded-sm bg-orange-600 px-0.5 text-[7px] leading-[9px] text-white">NH</span>}
                          {rp.length > 0 && <span className="absolute -right-0.5 -top-1 rounded-sm bg-orange-500 px-0.5 text-[7px] leading-[9px] text-white">RP</span>}
                        </button>
                      </td>
                    )
                  })}
                </tr>
              )
            })}
          </tbody>
          <tfoot>
            <tr>
              <td className="sticky left-0 z-10 border-r border-t-2 bg-white px-2 py-1 text-[11px] font-semibold text-gray-600">Actividades por día</td>
              <td className="border-r border-t-2 text-center text-[10px] text-gray-500">{sinFechaTotal || ''}</td>
              {dias.map((d) => {
                const n = carga.get(d) ?? 0
                return <td key={d} className={`border-r border-t-2 text-center text-[10px] tabular-nums ${n >= 4 ? 'font-bold text-red-700' : n > 0 ? 'font-semibold text-gray-700' : 'text-gray-300'} ${claseDia(d, hoy)}`}
                           title={n >= 4 ? 'Carga alta para una cuadrilla' : undefined}>{n || ''}</td>
              })}
            </tr>
          </tfoot>
        </table>
      </div>

      {sel?.modo === 'programar' && (
        <ProgramarModal fila={sel.fila} fecha={sel.fecha} rows={rows}
                        onClose={() => setSel(null)} onDone={() => { setSel(null); onCambio() }} />
      )}
      {sel?.modo === 'zona' && (
        <ZonaModal zona={sel.zona} fecha={sel.fecha} actividades={actividades} puedeEditar={puedeEditar}
                   onClose={() => setSel(null)} onDone={() => { setSel(null); onCambio() }} />
      )}
      {sel?.modo === 'detalle' && (
        <DetalleModal fila={sel.fila} fecha={sel.fecha} rows={sel.rows} hoy={hoy} puedeEditar={puedeEditar} reprogDe={reprogDe}
                      onProgramarOtro={sel.fecha ? () => setSel({ modo: 'programar', fila: sel.fila, fecha: sel.fecha! }) : undefined}
                      onClose={() => setSel(null)} onDone={() => { setSel(null); onCambio() }} />
      )}
    </div>
  )
}

function claseDia(d: string, hoy: string): string {
  // Hoy: columna violeta (no se confunde con los colores de estado) con bordes marcados, para no perderse al planificar.
  if (d === hoy) return 'bg-violet-50 shadow-[inset_2px_0_0_#7c3aed,inset_-2px_0_0_#7c3aed]'
  if (FERIADOS_CL[d]) return 'bg-gray-300/70'
  const dow = fechaDeIso(d).getDay()
  return dow === 0 || dow === 6 ? 'bg-gray-100' : ''
}

function semanaIso(dt: Date): number {
  const d = new Date(Date.UTC(dt.getFullYear(), dt.getMonth(), dt.getDate()))
  const dia = d.getUTCDay() || 7
  d.setUTCDate(d.getUTCDate() + 4 - dia)
  const ini = new Date(Date.UTC(d.getUTCFullYear(), 0, 1))
  return Math.ceil(((d.getTime() - ini.getTime()) / 86400000 + 1) / 7)
}

const ESTADO_TXT: Record<EstadoProg, string> = {
  programada: 'programado', hoy: 'toca hoy', cumplida: 'cumplido', sin_firma: 'hecho, falta firma', atrasada: 'ATRASADO', no_realizada: 'no realizado',
}
const SERV_TXT: Record<TipoServicio, string> = { mantencion: 'Mantención', calibracion: 'Calibración' }

function tooltipCelda(rs: EnexPanelRow[], hoy: string, inst: Map<string, EnexInstalacion>): string {
  return rs.map((r) => {
    const nom = r.instalacion_tipo === 'camion' ? (r.patente ?? r.instalacion) : (inst.get(r.instalacion_id)?.nombre ?? r.instalacion)
    return `${nom} · ${SERV_TXT[r.tipo_servicio]} · ${ESTADO_TXT[estadoProg(r, hoy)]}`
  }).join('\n')
}

// ── Programar un día ────────────────────────────────────────────────────────
function ProgramarModal({ fila, fecha, rows, onClose, onDone }: {
  fila: FilaServicio; fecha: string; rows: EnexPanelRow[]; onClose: () => void; onDone: () => void
}) {
  const toast = useToast()
  const [busy, setBusy] = useState(false)
  const esCamiones = fila.tipo === 'camiones' || fila.inst.tipo === 'camion'
  const [servicio, setServicio] = useState<'CMP' | 'C' | 'MP'>(esCamiones ? 'C' : 'CMP')
  const camiones = fila.tipo === 'camiones' ? fila.camiones.filter((c) => !c.es_comodin) : []
  // [MIG651] La patente no se sabe al planificar: «N camiones» van al camión
  // por asignar y el supervisor anota cuál calibró.
  const comodin = fila.tipo === 'camiones' ? fila.camiones.find((c) => c.es_comodin) : fila.inst.es_comodin ? fila.inst : undefined
  const [porAsignar, setPorAsignar] = useState(comodin ? 1 : 0)
  // Camiones ya programados en el período (para no calibrar dos veces el mismo trimestre sin querer).
  const yaProg = useMemo(() => new Set(rows.filter((r) => r.instalacion_tipo === 'camion' && r.tipo_servicio === 'calibracion').map((r) => r.instalacion_id)), [rows])
  const [elegidos, setElegidos] = useState<string[]>([])
  const [obs, setObs] = useState('')

  async function guardar() {
    const items: { instalacion_id: string; tipo_servicio: TipoServicio; fecha: string; observacion: string | null; cantidad?: number }[] = []
    if (comodin && porAsignar > 0) {
      // cantidad = total del día para el camión por asignar (suma a lo que ya hay).
      const ya = rows.filter((r) => r.instalacion_id === comodin.id && r.fecha_programada?.slice(0, 10) === fecha).length
      items.push({ instalacion_id: comodin.id, tipo_servicio: 'calibracion', fecha, observacion: obs || null, cantidad: ya + porAsignar })
    }
    if (fila.tipo === 'camiones') {
      if (elegidos.length === 0 && !(comodin && porAsignar > 0)) { toast.error('Indica cuántos camiones o elige patentes'); return }
      for (const id of elegidos) items.push({ instalacion_id: id, tipo_servicio: 'calibracion', fecha, observacion: obs || null })
    } else if (fila.inst.es_comodin) {
      if (porAsignar < 1) { toast.error('Indica cuántos camiones'); return }
    } else {
      const servs: TipoServicio[] = servicio === 'CMP' ? ['mantencion', 'calibracion'] : servicio === 'C' ? ['calibracion'] : ['mantencion']
      for (const s of servs) items.push({ instalacion_id: fila.inst.id, tipo_servicio: s, fecha, observacion: obs || null })
    }
    setBusy(true)
    try {
      const r = await programarLote(items)
      toast.success(r.omitidas > 0 ? `${r.creadas} programados · ${r.omitidas} ya existían ese día` : `${r.creadas} programado${r.creadas === 1 ? '' : 's'} — el mantenedor lo verá ese día`)
      onDone()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  const titulo = fila.tipo === 'camiones' ? `Calibración de camiones · ${fila.faena.nombre}` : fila.inst.nombre
  return (
    <Modal open onClose={onClose} title={titulo}>
      <div className="space-y-3">
        <p className="text-sm text-gray-600">Programar para el <b>{fechaLarga(fecha)}</b>.</p>
        {comodin && (
          <div className="rounded-lg border border-blue-200 bg-blue-50/60 p-2.5">
            <label className="flex items-center gap-2 text-sm font-medium text-blue-900">
              Camiones a calibrar (patente por asignar)
              <Input type="number" min={0} max={20} className="h-8 w-20" value={porAsignar}
                     onChange={(e) => setPorAsignar(Math.max(0, Math.min(20, Number(e.target.value) || 0)))} />
            </label>
            <p className="mt-1 text-[11px] text-blue-800">La operación entrega el camión en el momento: el supervisor anota la patente en terreno y queda en el cumplimiento.</p>
          </div>
        )}
        {fila.tipo === 'camiones' ? (
          <div className="max-h-72 space-y-1 overflow-y-auto rounded border p-2">
            {camiones.length > 0 && <p className="text-[11px] text-gray-500">…o patentes conocidas:</p>}
            {camiones.map((c) => (
              <label key={c.id} className="flex items-center gap-2 text-sm">
                <input type="checkbox" checked={elegidos.includes(c.id)}
                       onChange={(e) => setElegidos((p) => e.target.checked ? [...p, c.id] : p.filter((x) => x !== c.id))} />
                <span className="font-medium">{c.patente ?? c.nombre}</span>
                {c.ultima_calibracion && <span className="text-[11px] text-gray-500">últ. calib. {c.ultima_calibracion}</span>}
                {yaProg.has(c.id) && <span className="rounded bg-blue-100 px-1 text-[10px] text-blue-700">ya en el período</span>}
              </label>
            ))}
            {camiones.length === 0 && <p className="text-xs text-gray-400">La faena no tiene camiones cargados.</p>}
          </div>
        ) : fila.inst.es_comodin ? null : esCamiones ? (
          <p className="text-sm">Calibración del camión <b>{fila.inst.patente ?? fila.inst.nombre}</b>.</p>
        ) : (
          <div className="grid grid-cols-3 gap-2">
            {([['CMP', 'Mant. + Calib.', 'CMP'], ['C', 'Calibración', 'C'], ['MP', 'Mantención', 'MP']] as const).map(([k, l, c]) => (
              <button key={k} onClick={() => setServicio(k)}
                      className={`rounded-lg border p-2 text-center ${servicio === k ? 'border-blue-600 bg-blue-50 text-blue-800' : 'border-gray-200 hover:bg-gray-50'}`}>
                <div className="text-base font-bold">{c}</div>
                <div className="text-[11px]">{l}</div>
              </button>
            ))}
          </div>
        )}
        {fila.tipo === 'inst' && !esCamiones && (fila.inst.frecuencia_mantencion || fila.inst.frecuencia_calibracion) && (
          <div className="rounded-lg border border-indigo-200 bg-indigo-50/60 px-3 py-2 text-xs text-indigo-800">
            <b>Frecuencia según contrato:</b> {fila.inst.frecuencia_mantencion && `Mant. ${fila.inst.frecuencia_mantencion}`}
            {fila.inst.frecuencia_mantencion && fila.inst.frecuencia_calibracion && ' · '}
            {fila.inst.frecuencia_calibracion && `Calib. ${fila.inst.frecuencia_calibracion}`}
          </div>
        )}
        <div>
          <label className="text-xs font-medium">Observación (opcional)</label>
          <Input value={obs} onChange={(e) => setObs(e.target.value)} placeholder="ej. ventana a.m., coordinar con ESM" />
        </div>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button disabled={busy} onClick={guardar}>{busy && <Loader2 className="mr-1 h-4 w-4 animate-spin" />} Programar</Button>
      </ModalFooter>
    </Modal>
  )
}

// ── Detalle de una celda: mover o quitar ────────────────────────────────────
function DetalleModal({ fila, fecha, rows, hoy, puedeEditar, reprogDe, onProgramarOtro, onClose, onDone }: {
  fila: FilaServicio; fecha: string | null; rows: EnexPanelRow[]; hoy: string; puedeEditar: boolean
  reprogDe: Map<string, string>; onProgramarOtro?: () => void; onClose: () => void; onDone: () => void
}) {
  const toast = useToast()
  const [busy, setBusy] = useState<string | null>(null)
  const [nuevas, setNuevas] = useState<Record<string, string>>({})
  const [reprog, setReprog] = useState<EnexPanelRow | null>(null)
  const qc = useQueryClient()

  if (reprog) {
    return <ReprogramacionModal row={reprog} nombre={reprog.instalacion_tipo === 'camion' ? `Camión ${reprog.patente ?? reprog.instalacion}` : reprog.instalacion}
                                limitarTrimestre fechaInicial={nuevas[reprog.programacion_id] ?? ''}
                                onClose={() => setReprog(null)}
                                onDone={() => { qc.invalidateQueries({ queryKey: ['enex-reprogramaciones'] }); onDone() }} />
  }

  async function mover(r: EnexPanelRow) {
    const f = nuevas[r.programacion_id]
    if (!f) { toast.error('Elige la nueva fecha'); return }
    setBusy(r.programacion_id)
    try { await moverProgramacion(r.programacion_id, f); toast.success('Movido'); onDone() }
    catch (e) { toast.error((e as Error).message) } finally { setBusy(null) }
  }
  async function quitar(r: EnexPanelRow) {
    setBusy(r.programacion_id)
    try { await desprogramar(r.programacion_id); toast.success('Quitado del plan'); onDone() }
    catch (e) { toast.error((e as Error).message) } finally { setBusy(null) }
  }

  const titulo = fila.tipo === 'camiones' ? `Camiones · ${fila.faena.nombre}` : fila.inst.nombre
  return (
    <Modal open onClose={onClose} title={titulo}>
      <div className="space-y-2">
        <p className="text-sm text-gray-600">{fecha ? fechaLarga(fecha) : 'Programados en el mes sin día asignado'}</p>
        {rows.map((r) => {
          const e = estadoProg(r, hoy)
          return (
            <div key={r.programacion_id} className="rounded-lg border p-2">
              <div className="flex flex-wrap items-center gap-2 text-sm">
                <span className="font-medium">{r.es_comodin ? 'Camión por asignar' : r.instalacion_tipo === 'camion' ? (r.patente ?? r.instalacion) : r.instalacion}</span>
                {r.origen === 'terreno' && <span className="rounded bg-orange-100 px-1.5 text-[10px] font-semibold text-orange-800">fuera de plan (terreno)</span>}
                <span className="text-gray-500">· {SERV_TXT[r.tipo_servicio]}</span>
                <span className={`rounded px-1.5 text-[10px] font-semibold ${ESTILO[e]}`}>{ESTADO_TXT[e]}</span>
                {reprogDe.has(r.programacion_id) && <span className="rounded bg-orange-500 px-1.5 text-[10px] font-semibold text-white">RP · original {reprogDe.get(r.programacion_id) || 's/f'}</span>}
              </div>
              {r.ejecucion_id ? (
                <p className="mt-1 text-xs text-gray-500">
                  Ejecutado {r.fecha_ejecucion ?? ''}{r.ot_numero ? ` · OT ${r.ot_numero}` : ''}{r.tecnico_nombre ? ` · ${r.tecnico_nombre}` : ''}
                  {r.informe_pdf_url && <> · <a href={r.informe_pdf_url} target="_blank" rel="noreferrer" className="text-blue-600 underline">informe PDF</a></>}
                </p>
              ) : puedeEditar ? (
                <div className="mt-1.5 flex flex-wrap items-center gap-2">
                  <Input type="date" className="h-8 w-40" value={nuevas[r.programacion_id] ?? ''}
                         onChange={(ev) => setNuevas((p) => ({ ...p, [r.programacion_id]: ev.target.value }))} />
                  <Button size="sm" variant="outline" disabled={busy !== null} onClick={() => mover(r)}>
                    {busy === r.programacion_id ? <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" /> : <CalendarClock className="mr-1 h-3.5 w-3.5" />} Mover
                  </Button>
                  <Button size="sm" variant="outline" className="text-orange-700" disabled={busy !== null} onClick={() => setReprog(r)}
                          title="Reprogramación formal (registro + PDF para ESM), dentro del trimestre">
                    <Redo2 className="mr-1 h-3.5 w-3.5" /> Reprogramar
                  </Button>
                  <Button size="sm" variant="outline" className="text-red-600" disabled={busy !== null} onClick={() => quitar(r)}>
                    <Trash2 className="mr-1 h-3.5 w-3.5" /> Quitar
                  </Button>
                </div>
              ) : null}
              {r.por_reprogramar_motivo && !r.ejecucion_id && (
                <p className="mt-1 rounded bg-orange-50 px-2 py-1 text-[11px] text-orange-800">
                  <b>No se hizo en terreno:</b> {r.por_reprogramar_motivo}. Ponle fecha nueva con «Mover» o «Reprogramar».
                </p>
              )}
              {r.prog_observacion && <p className="mt-1 text-[11px] text-gray-500">{r.prog_observacion}</p>}
            </div>
          )
        })}
        <p className="text-[11px] text-gray-400">
          «Mover» cambia la fecha sin dejar registro (ajuste de plan). «Reprogramar» deja el registro firmado para ESM
          y la celda queda marcada RP; la nueva fecha debe caer dentro del trimestre. La ejecución se registra en «Control & KPI».
        </p>
      </div>
      <ModalFooter>
        {onProgramarOtro && puedeEditar && <Button variant="outline" className="mr-auto" onClick={onProgramarOtro}>+ Otro servicio este día</Button>}
        <Button variant="outline" onClick={onClose}>Cerrar</Button>
      </ModalFooter>
    </Modal>
  )
}

function fechaLarga(iso: string): string {
  return fechaDeIso(iso).toLocaleDateString('es-CL', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })
}


// ── Zona de Lomas en un día ─────────────────────────────────────────────────
// Planificar la zona deja sus actividades en el «Plan de hoy» del supervisor
// (rpc_enex_trimestre_actividad_set, MIG591). Quitar del día la devuelve a
// pendiente.
const EST_ACT: Record<string, string> = {
  pendiente: 'pendiente', planificada: 'planificada', reprogramada: 'reprogramada', ejecutada: 'hecha', no_aplica: 'n/a',
}

function ZonaModal({ zona, fecha, actividades, puedeEditar, onClose, onDone }: {
  zona: Zona; fecha: string; actividades: EnexActividadTrimestre[]; puedeEditar: boolean; onClose: () => void; onDone: () => void
}) {
  const toast = useToast()
  const qc = useQueryClient()
  const trim = trimestreDe(fecha)
  const actDe = useMemo(() => new Map(actividades.filter((a) => a.trimestre_inicio === trim).map((a) => [a.lugar_item_id, a])), [actividades, trim])
  const delDia = zona.items.filter((it) => { const a = actDe.get(it.lugar_item_id); return a?.fecha_plan?.slice(0, 10) === fecha && a.estado !== 'ejecutada' })
  const abiertas = zona.items.filter((it) => !['ejecutada', 'no_aplica'].includes(actDe.get(it.lugar_item_id)?.estado ?? 'pendiente'))
  const [elegidos, setElegidos] = useState<string[]>(() => (delDia.length ? delDia : abiertas).map((it) => it.lugar_item_id))
  const [busy, setBusy] = useState(false)

  async function aplicar(estado: 'planificada' | 'pendiente') {
    const ids = estado === 'pendiente' ? elegidos.filter((id) => delDia.some((d) => d.lugar_item_id === id)) : elegidos
    if (ids.length === 0) { toast.error(estado === 'pendiente' ? 'Elige actividades planificadas este día' : 'Elige al menos una actividad'); return }
    setBusy(true)
    try {
      const r = await setActividadesTrimestre({ lugarItemIds: ids, trimestreInicio: trim, estado, fecha: estado === 'planificada' ? fecha : null })
      qc.invalidateQueries({ queryKey: ['enex-actividades-gantt'] })
      toast.success(estado === 'planificada'
        ? `${ids.length} actividades planificadas — el supervisor las ve ese día${r.plan_en_borrador ? ' (ojo: el plan de esa semana está en borrador)' : ''}`
        : `${ids.length} actividades quitadas del día`)
      onDone()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  return (
    <Modal open onClose={onClose} title={`${zona.lugar} · ${zona.area}`}>
      <div className="space-y-2">
        <p className="text-sm text-gray-600">{fechaLarga(fecha)}{zona.observacion ? ` · ${zona.observacion}` : ''}</p>
        <div className="max-h-80 space-y-1 overflow-y-auto rounded border p-2">
          {zona.items.map((it) => {
            const a = actDe.get(it.lugar_item_id)
            const est = a?.estado ?? 'pendiente'
            const cerrada = est === 'ejecutada' || est === 'no_aplica'
            return (
              <label key={it.lugar_item_id} className={`flex items-start gap-2 text-xs ${cerrada ? 'text-gray-400' : ''}`}>
                <input type="checkbox" disabled={cerrada || !puedeEditar} checked={elegidos.includes(it.lugar_item_id)} className="mt-0.5"
                       onChange={(e) => setElegidos((p) => e.target.checked ? [...p, it.lugar_item_id] : p.filter((x) => x !== it.lugar_item_id))} />
                <span className="w-8 font-mono text-gray-500">{it.codigo}</span>
                <span className="flex-1">{it.descripcion}{it.observacion ? <span className="text-gray-400"> ({it.observacion})</span> : null}</span>
                <span className="whitespace-nowrap text-[10px] text-gray-500">
                  {EST_ACT[est] ?? est}{a?.fecha_plan && est !== 'ejecutada' ? ` ${a.fecha_plan.slice(8, 10)}/${a.fecha_plan.slice(5, 7)}` : ''}
                  {a?.fecha_ejecucion && est === 'ejecutada' ? ` ${a.fecha_ejecucion.slice(8, 10)}/${a.fecha_ejecucion.slice(5, 7)}` : ''}
                  {a?.por_reprogramar_motivo && <span className="block text-orange-700">no se hizo: {a.por_reprogramar_motivo}</span>}
                </span>
              </label>
            )
          })}
        </div>
        <p className="text-[11px] text-gray-400">
          Trimestre {trim.slice(5, 7) === '01' ? '1°' : trim.slice(5, 7) === '04' ? '2°' : trim.slice(5, 7) === '07' ? '3°' : '4°'} {trim.slice(0, 4)}.
          Planificar deja las actividades en el «Plan de hoy» del supervisor ese día. Lo hecho se marca solo desde el informe de terreno.
        </p>
      </div>
      <ModalFooter>
        {puedeEditar && delDia.length > 0 && (
          <Button variant="outline" className="mr-auto text-red-600" disabled={busy} onClick={() => aplicar('pendiente')}>
            <Trash2 className="mr-1 h-4 w-4" /> Quitar del día
          </Button>
        )}
        <Button variant="outline" onClick={onClose}>Cerrar</Button>
        {puedeEditar && (
          <Button disabled={busy} onClick={() => aplicar('planificada')}>
            {busy && <Loader2 className="mr-1 h-4 w-4 animate-spin" />} Planificar este día
          </Button>
        )}
      </ModalFooter>
    </Modal>
  )
}
