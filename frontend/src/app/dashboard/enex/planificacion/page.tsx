'use client'

// Planificación ENEX (MIG590) — la planilla "Planificación diaria" dentro de la
// plataforma, con mirada hacia adelante: Gantt instalación × día del trimestre,
// % de avance real vs planificado vs proyectado, curva S y lo que viene.
//
// Solo cambia la vista del planificador. El mantenedor sigue viendo en /m/enex
// las tareas de cada fecha, como siempre: la Gantt escribe esas mismas
// programaciones.

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  CalendarRange, ChevronLeft, ChevronRight, FileSpreadsheet, Upload, Building2, FileText, AlertTriangle, CalendarClock, Replace,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getFaenas, getInstalaciones, getPanelVentana, mundoDeLinea, MESES,
  CAMBIO_DESTINO_TXT, type EnexPanelRow, type EnexInstalacion, type EnexFaena,
} from '@/lib/services/enex'
import {
  ventanaTrimestre, ventanaDesde, inicioTrimestreContractual, calcularAvance, estadoProg, codigoCelda, isoDe, sumarDias, fechaDeIso, FERIADOS_CL,
} from '@/lib/enex-avance'
import { TarjetasAvance, CurvaSEnex, TablaFaenas, TablaContratos } from '@/components/enex/planificacion/avance-enex'
import { GanttEnex, LEYENDA_ESTADO } from '@/components/enex/planificacion/gantt-enex'
import { ImportarPlanillaModal } from '@/components/enex/planificacion/importar-planilla-modal'
import { ReprogramacionModal } from '@/components/enex/reprogramacion-modal'
import { CambioTareaModal, GestionarCambioModal, nombreProg } from '@/components/enex/cambio-tarea-modal'

const ROLES_GESTION = ['administrador', 'subgerente_operaciones', 'jefe_operaciones', 'supervisor', 'planificador', 'jefe_mantenimiento']
type Mundo = 'todos' | 'combustible' | 'lubricante'

export default function EnexPlanificacionPage() {
  const { perfil } = useRequireAuth()
  const qc = useQueryClient()
  // La fecha se fija tras montar (la página se prerenderiza en el build).
  const [hoy, setHoy] = useState('')
  const [inicio, setInicio] = useState<{ anio: number; mes: number } | null>(null)
  useEffect(() => { const h = isoDe(new Date()); setHoy(h); setInicio(inicioTrimestreContractual(h)) }, [])
  const [faenaSel, setFaenaSel] = useState<string>('todas')
  const [mundo, setMundo] = useState<Mundo>('todos')
  const [importar, setImportar] = useState(false)
  const [horizonte, setHorizonte] = useState<3 | 6 | 12>(6)
  const puedeEditar = !!perfil?.rol && ROLES_GESTION.includes(perfil.rol)

  const ventana = useMemo(() => (inicio ? ventanaTrimestre(inicio.anio, inicio.mes) : null), [inicio])
  // La Gantt mira hacia adelante: en el trimestre en curso parte el lunes de la semana pasada y
  // sigue `horizonte` meses. Si se navega a otro trimestre, parte al inicio de ese trimestre.
  // El avance, la curva S y el KPI siguen midiéndose sobre el trimestre contractual.
  const ventanaGantt = useMemo(() => {
    if (!ventana || !hoy) return null
    const enCurso = hoy >= ventana.desde && hoy <= ventana.hasta
    const lunes = sumarDias(hoy, -7 - ((fechaDeIso(hoy).getDay() + 6) % 7))
    return ventanaDesde(enCurso ? lunes : ventana.desde, horizonte)
  }, [ventana, hoy, horizonte])

  const { data: faenas = [] } = useQuery({ queryKey: ['enex-faenas'], queryFn: getFaenas, staleTime: 5 * 60_000 })
  const { data: instalaciones = [], refetch: refetchInst } = useQuery({
    queryKey: ['enex-inst', 'todas'], queryFn: () => getInstalaciones(), staleTime: 60_000,
  })
  const { data: panel = [], isLoading } = useQuery({
    queryKey: ['enex-plan-ventana', ventana?.desde],
    queryFn: () => getPanelVentana(ventana!.meses), enabled: !!ventana, staleTime: 10_000,
  })
  const { data: panelGantt = [], isLoading: cargandoGantt } = useQuery({
    queryKey: ['enex-plan-ventana', 'gantt', ventanaGantt?.desde, horizonte],
    queryFn: () => getPanelVentana(ventanaGantt!.meses), enabled: !!ventanaGantt, staleTime: 10_000,
  })

  const invalidar = () => {
    qc.invalidateQueries({ queryKey: ['enex-plan-ventana'] })
    qc.invalidateQueries({ queryKey: ['enex-panel'] })
    qc.invalidateQueries({ queryKey: ['enex-kpi'] })
    qc.invalidateQueries({ queryKey: ['enex-kpi-tri'] })
  }

  const enMundo = (linea: string | null) => mundo === 'todos' || mundoDeLinea(linea) === mundo
  const rows = useMemo(() => panel.filter((r) => (faenaSel === 'todas' || r.faena_id === faenaSel) && enMundo(r.linea)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [panel, faenaSel, mundo])
  const rowsGantt = useMemo(() => panelGantt.filter((r) => (faenaSel === 'todas' || r.faena_id === faenaSel) && enMundo(r.linea)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [panelGantt, faenaSel, mundo])
  const instVista = useMemo(() => instalaciones.filter((i) => (faenaSel === 'todas' || i.faena_id === faenaSel) && enMundo(i.linea)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [instalaciones, faenaSel, mundo])
  const faenasVista = useMemo(() => faenas.filter((f) => faenaSel === 'todas' || f.id === faenaSel), [faenas, faenaSel])
  const avance = useMemo(() => calcularAvance(rows, hoy), [rows, hoy])

  function mover(delta: number) {
    if (!inicio) return
    let m = inicio.mes + delta, a = inicio.anio
    while (m < 1) { m += 12; a-- }
    while (m > 12) { m -= 12; a++ }
    setInicio({ anio: a, mes: m })
  }

  if (!ventana || !ventanaGantt || !hoy) return <div className="flex justify-center p-10"><Spinner /></div>
  const m0 = ventana.meses[0], m2 = ventana.meses[2]

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-xl font-bold">
            <CalendarRange className="h-5 w-5 text-blue-700" /> Planificación ENEX / ESM
          </h1>
          <p className="mt-0.5 text-sm text-gray-500">
            Plan diario del trimestre por instalación, avance real contra lo planificado y proyección al cierre.
            El mantenedor ve cada servicio en su teléfono el día que lo programes.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Link href="/dashboard/enex"><Button variant="outline"><Building2 className="mr-1 h-4 w-4" /> Control & KPI</Button></Link>
          <Link href="/dashboard/enex/pauta-trimestral"><Button variant="outline"><FileText className="mr-1 h-4 w-4" /> Pauta por lugar</Button></Link>
          <Link href="/dashboard/enex/informe-trimestral"><Button variant="outline"><FileText className="mr-1 h-4 w-4" /> Informe trimestral</Button></Link>
          <Button variant="outline" disabled={rowsGantt.length === 0} onClick={() => exportarExcel(rowsGantt, instVista, faenasVista, ventanaGantt.desde, ventanaGantt.hasta)}>
            <FileSpreadsheet className="mr-1 h-4 w-4" /> Exportar Excel
          </Button>
          {puedeEditar && (
            <Button onClick={() => setImportar(true)}><Upload className="mr-1 h-4 w-4" /> Importar planilla</Button>
          )}
        </div>
      </div>

      {/* Filtros en una fila */}
      <div className="flex flex-wrap items-center gap-2">
        <button onClick={() => mover(-1)} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50" aria-label="Mes anterior"><ChevronLeft className="h-4 w-4" /></button>
        <span className="min-w-[170px] text-center text-sm font-semibold capitalize">
          {MESES[m0.mes - 1].slice(0, 3)} {m0.anio !== m2.anio ? m0.anio : ''} – {MESES[m2.mes - 1].slice(0, 3)} {m2.anio}
        </span>
        <button onClick={() => mover(1)} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50" aria-label="Mes siguiente"><ChevronRight className="h-4 w-4" /></button>
        <button onClick={() => setInicio(inicioTrimestreContractual(hoy))} className="rounded-lg border px-2 py-1.5 text-xs hover:bg-gray-50"
                title="Trimestre contractual ENEX (Feb-Abr, May-Jul, Ago-Oct, Nov-Ene)">Trimestre actual</button>
        <select value={faenaSel} onChange={(e) => setFaenaSel(e.target.value)} className="rounded-lg border px-2 py-1.5 text-sm">
          <option value="todas">Todas las faenas</option>
          {faenas.map((f) => <option key={f.id} value={f.id}>{f.nombre}</option>)}
        </select>
        <div className="flex overflow-hidden rounded-lg border">
          {([['todos', 'Todo'], ['combustible', 'Combustibles'], ['lubricante', 'Lubricantes']] as const).map(([k, l]) => (
            <button key={k} onClick={() => setMundo(k)}
                    className={`px-2.5 py-1.5 text-xs font-semibold ${mundo === k ? 'bg-blue-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>{l}</button>
          ))}
        </div>
        {isLoading && <Spinner className="h-4 w-4" />}
      </div>

      <TarjetasAvance a={avance} />

      <Card><CardContent className="p-0">
        <div className="border-b px-3 py-2">
          <h2 className="text-sm font-semibold">Avance por contrato · trimestre {MESES[m0.mes - 1].slice(0, 3)}–{MESES[m2.mes - 1].slice(0, 3)}</h2>
          <p className="text-[11px] text-gray-500">
            % de avance = ejecutado ÷ lo que el contrato exige en el trimestre (instalación de combustible = mantención + calibración,
            truck shop = mantención, camión = calibración), menos lo justificado por el ADC. «Por programar» es lo que el contrato pide y aún no está en la Gantt.
          </p>
        </div>
        <TablaContratos rows={rows} faenas={faenasVista} mundo={mundo} puedeEditar={puedeEditar}
                        onCambio={() => { qc.invalidateQueries({ queryKey: ['enex-faenas'] }) }} />
      </CardContent></Card>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2"><CardContent className="p-3">
          <CurvaSEnex rows={rows} ventana={ventana} hoy={hoy} />
        </CardContent></Card>
        <Card><CardContent className="p-3">
          <LoQueViene rows={rows} hoy={hoy} />
        </CardContent></Card>
      </div>

      {faenaSel === 'todas' && (
        <Card><CardContent className="p-0">
          <div className="border-b px-3 py-2">
            <h2 className="text-sm font-semibold">Avance por faena</h2>
            <p className="text-[11px] text-gray-500">KPI de cada mes: real si el mes ya cerró; si no, proyectado (cumplido + lo que aún puede cumplirse a tiempo) con su tramo de multa.</p>
          </div>
          <TablaFaenas rows={rows} faenas={faenas} ventana={ventana} hoy={hoy} onElegir={setFaenaSel} />
        </CardContent></Card>
      )}

      <NoSeHizoEnTerreno rows={rowsGantt} instalaciones={instalaciones} puedeEditar={puedeEditar} onCambio={invalidar} />
      <EsperanCorreoAdc rows={rows} puedeEditar={puedeEditar} onCambio={invalidar} />

      <Card><CardContent className="p-0">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b px-3 py-2">
          <div>
            <h2 className="text-sm font-semibold">Planificación diaria</h2>
            <p className="text-[11px] text-gray-500">
              {puedeEditar ? 'Clic en un día vacío para programar · clic en un código para mover, reprogramar o quitar · arrastra un código a otro día de la misma fila.' : 'Solo lectura.'}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-[11px] text-gray-500">Ver</span>
            <div className="flex overflow-hidden rounded-lg border">
              {([3, 6, 12] as const).map((n) => (
                <button key={n} onClick={() => setHorizonte(n)}
                        className={`px-2 py-1 text-xs font-semibold ${horizonte === n ? 'bg-blue-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>{n} meses</button>
              ))}
            </div>
            {cargandoGantt && <Spinner className="h-4 w-4" />}
          </div>
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[10px] text-gray-600">
            <span><b>CMP</b> mant.+calib.</span><span><b>C</b> calibración</span><span><b>MP</b> mantención</span><span><b>CP·n</b> camiones</span>
            {LEYENDA_ESTADO.map(([e, l]) => <span key={e} className="flex items-center gap-1"><span className={`inline-block h-2.5 w-2.5 rounded-sm ${MUESTRA[e]}`} />{l}</span>)}
            <span className="flex items-center gap-1"><span className="inline-block h-2.5 w-2.5 rounded-sm bg-gray-300" />Feriado</span>
            <span className="flex items-center gap-1"><span className="inline-block h-2.5 w-2.5 rounded-sm bg-violet-600" />Hoy</span>
            <span className="flex items-center gap-1"><span className="rounded-sm bg-orange-500 px-0.5 text-[7px] font-bold text-white">RP</span>Reprogramado</span>
            <span className="flex items-center gap-1"><span className="rounded-sm bg-orange-600 px-0.5 text-[7px] font-bold text-white">NH</span>No se hizo en terreno</span>
          </div>
        </div>
        <GanttEnex rows={rowsGantt} faenas={faenasVista} instalaciones={instVista} ventana={ventanaGantt} hoy={hoy}
                   puedeEditar={puedeEditar} onCambio={invalidar} />
      </CardContent></Card>

      {importar && (
        <ImportarPlanillaModal faenas={faenas} instalaciones={instalaciones} hoy={hoy}
                               onClose={() => setImportar(false)} onDone={() => { setImportar(false); invalidar() }}
                               onInstalacionCreada={() => { qc.invalidateQueries({ queryKey: ['enex-inst'] }); return refetchInst() }} />
      )}
    </div>
  )
}

const MUESTRA: Record<string, string> = {
  programada: 'bg-blue-100 ring-1 ring-blue-300', hoy: 'bg-blue-600', cumplida: 'bg-green-600',
  sin_firma: 'bg-amber-300', atrasada: 'bg-red-500', no_realizada: 'bg-red-100 ring-1 ring-red-300',
  justificada: 'bg-gray-100 ring-1 ring-gray-300',
}

// Mirada hacia adelante: atrasados por reprogramar + los próximos 14 días.
function LoQueViene({ rows, hoy }: { rows: EnexPanelRow[]; hoy: string }) {
  const atrasados = rows.filter((r) => estadoProg(r, hoy) === 'atrasada')
    .sort((a, b) => (a.fecha_programada ?? '').localeCompare(b.fecha_programada ?? ''))
  const hasta = sumarDias(hoy, 13)
  const proximos = new Map<string, EnexPanelRow[]>()
  for (const r of rows) {
    const f = r.fecha_programada?.slice(0, 10)
    if (!f || f < hoy || f > hasta || r.ejecucion_id) continue
    proximos.set(f, [...(proximos.get(f) ?? []), r])
  }
  const dias = Array.from(proximos.keys()).sort()
  const nombre = (r: EnexPanelRow) => (r.instalacion_tipo === 'camion' ? `Camión ${r.patente ?? ''}` : r.instalacion)
  return (
    <div className="space-y-3">
      {atrasados.length > 0 && (
        <div>
          <h3 className="mb-1 flex items-center gap-1 text-sm font-semibold text-red-700"><AlertTriangle className="h-4 w-4" /> Atrasados por reprogramar ({atrasados.length})</h3>
          <ul className="max-h-28 space-y-0.5 overflow-y-auto text-xs">
            {atrasados.map((r) => (
              <li key={r.programacion_id} className="flex justify-between gap-2">
                <span className="truncate">{nombre(r)} · {r.tipo_servicio === 'mantencion' ? 'Mant.' : 'Calib.'}</span>
                <span className="shrink-0 tabular-nums text-red-700">{r.fecha_programada?.slice(8, 10)}/{r.fecha_programada?.slice(5, 7)}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
      <div>
        <h3 className="mb-1 flex items-center gap-1 text-sm font-semibold text-gray-800"><CalendarClock className="h-4 w-4" /> Próximos 14 días</h3>
        {dias.length === 0 ? <p className="text-xs text-gray-400">Nada programado. Planifica en la Gantt de abajo.</p> : (
          <ul className="max-h-60 space-y-1.5 overflow-y-auto text-xs">
            {dias.map((d) => {
              const rs = proximos.get(d)!
              const porInst = new Map<string, EnexPanelRow[]>()
              for (const r of rs) {
                const k = r.instalacion_tipo === 'camion' ? `CAM:${r.faena_id}` : r.instalacion_id
                porInst.set(k, [...(porInst.get(k) ?? []), r])
              }
              return (
                <li key={d}>
                  <div className={`font-semibold ${d === hoy ? 'text-blue-700' : 'text-gray-700'}`}>
                    {d === hoy ? 'Hoy · ' : ''}{fechaDeIso(d).toLocaleDateString('es-CL', { weekday: 'short', day: 'numeric', month: 'short' })}
                    {FERIADOS_CL[d] && <span className="ml-1 font-normal text-gray-500">({FERIADOS_CL[d]})</span>}
                  </div>
                  {Array.from(porInst.values()).map((g) => {
                    const cam = g[0].instalacion_tipo === 'camion'
                    const cod = codigoCelda(g.map((r) => ({ tipo_servicio: r.tipo_servicio, esCamion: cam })))
                    return (
                      <div key={g[0].programacion_id} className="flex gap-2 pl-2 text-gray-600">
                        <span className="w-9 shrink-0 font-bold text-blue-700">{cod}</span>
                        <span className="truncate">{cam ? `Camiones ${g.map((r) => r.patente).filter(Boolean).join(', ')}` : g[0].instalacion} <span className="text-gray-400">· {g[0].faena}</span></span>
                      </div>
                    )
                  })}
                </li>
              )
            })}
          </ul>
        )}
      </div>
    </div>
  )
}

// Exporta la Gantt con el mismo formato de la planilla (una hoja por faena).
async function exportarExcel(rows: EnexPanelRow[], instalaciones: EnexInstalacion[], faenas: EnexFaena[], desde: string, hasta: string) {
  const ExcelJS = (await import('exceljs')).default
  const wb = new ExcelJS.Workbook()
  const dias: string[] = []
  for (let f = desde; f <= hasta; f = sumarDias(f, 1)) dias.push(f)
  const DOW = ['d', 'l', 'm', 'x', 'j', 'v', 's']
  const relleno = (argb: string) => ({ type: 'pattern' as const, pattern: 'solid' as const, fgColor: { argb } })
  for (const f of faenas) {
    const inst = instalaciones.filter((i) => i.faena_id === f.id)
    const rf = rows.filter((r) => r.faena_id === f.id)
    if (inst.length === 0 && rf.length === 0) continue
    const ws = wb.addWorksheet(f.nombre.slice(0, 31).replace(/[\\/?*[\]:]/g, '-'))
    ws.getCell(1, 1).value = `PLANIFICACIÓN DIARIA — ${f.nombre.toUpperCase()} · ${desde} a ${hasta} · exportado de SICOM ${isoDe(new Date())}`
    ws.getCell(1, 1).font = { bold: true, size: 12 }
    ws.getCell(4, 1).value = 'Instalación / Equipo'
    dias.forEach((d, j) => {
      const c = 3 + j
      const dt = fechaDeIso(d)
      if (j === 0 || dt.getDate() === 1) ws.getCell(4, c).value = MESES[dt.getMonth()]
      ws.getCell(5, c).value = dt.getDate()
      ws.getCell(6, c).value = DOW[dt.getDay()]
      ws.getColumn(c).width = 4.5
      const finde = dt.getDay() === 0 || dt.getDay() === 6
      if (FERIADOS_CL[d]) { ws.getCell(5, c).fill = relleno('FFA6A6A6'); ws.getCell(6, c).fill = relleno('FFA6A6A6') }
      else if (finde) { ws.getCell(5, c).fill = relleno('FFEDEDED'); ws.getCell(6, c).fill = relleno('FFEDEDED') }
    })
    ws.getColumn(1).width = 42
    ws.getColumn(2).width = 13
    const filas: { nombre: string; ids: Set<string>; cam: boolean }[] = [
      ...inst.filter((i) => i.tipo !== 'camion').map((i) => ({ nombre: i.nombre, ids: new Set([i.id]), cam: false })),
    ]
    const cams = inst.filter((i) => i.tipo === 'camion')
    if (cams.length) filas.push({ nombre: `Calibración camiones (${cams.length})`, ids: new Set(cams.map((c) => c.id)), cam: true })
    filas.forEach((fl, k) => {
      const r = 7 + k
      ws.getCell(r, 1).value = fl.nombre
      ws.getCell(r, 2).value = fl.cam || inst.find((i) => fl.ids.has(i.id))?.linea !== 'lubricante' ? 'Combustibles' : 'Lubricantes'
      dias.forEach((d, j) => {
        const rs = rf.filter((x) => fl.ids.has(x.instalacion_id) && x.fecha_programada?.slice(0, 10) === d)
        if (rs.length === 0) return
        const cell = ws.getCell(r, 3 + j)
        cell.value = codigoCelda(rs.map((x) => ({ tipo_servicio: x.tipo_servicio, esCamion: fl.cam })))
        cell.alignment = { horizontal: 'center' }
        cell.font = { bold: true, size: 8 }
        const cumplida = rs.every((x) => x.cumplida)
        cell.fill = relleno(cumplida ? 'FFC6E0B4' : fl.cam ? 'FFDDEBF7' : 'FFFFE699')
      })
    })
    const rTot = 7 + filas.length
    ws.getCell(rTot, 1).value = 'Actividades por día'
    ws.getCell(rTot, 1).font = { bold: true }
    dias.forEach((d, j) => { const n = rf.filter((x) => x.fecha_programada?.slice(0, 10) === d).length; if (n) ws.getCell(rTot, 3 + j).value = n })
    ws.getCell(rTot + 2, 1).value = 'LEYENDA: CMP calibración y mantención · C calibración · MP mantención · CP/CP2/CP3 calibración camiones (n unidades) · verde = cumplido'
    ws.views = [{ state: 'frozen', xSplit: 2, ySplit: 6 }]
  }
  const buf = await wb.xlsx.writeBuffer()
  const a = document.createElement('a')
  a.href = URL.createObjectURL(new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }))
  a.download = `Planificacion_Diaria_ENEX_${desde}_a_${hasta}.xlsx`
  a.click()
  URL.revokeObjectURL(a.href)
}


// [MIG651] Lo que la cuadrilla no hizo porque ESM pidió otra cosa: espera
// fecha nueva. Sigue contando como programado (el KPI no se maquilla).
function NoSeHizoEnTerreno({ rows, instalaciones, puedeEditar, onCambio }: {
  rows: EnexPanelRow[]; instalaciones: EnexInstalacion[]; puedeEditar: boolean; onCambio: () => void
}) {
  const [reprog, setReprog] = useState<EnexPanelRow | null>(null)
  const [cambio, setCambio] = useState<EnexPanelRow | null>(null)
  const qc = useQueryClient()
  const pend = rows.filter((r) => r.por_reprogramar_motivo && !r.ejecucion_id)
    .sort((a, b) => (a.fecha_programada ?? '').localeCompare(b.fecha_programada ?? ''))
  if (pend.length === 0) return null
  return (
    <Card className="border-orange-300"><CardContent className="p-3">
      <p className="flex items-center gap-1.5 text-sm font-semibold text-orange-900">
        <AlertTriangle className="h-4 w-4" /> No se hizo en terreno — falta fecha nueva ({pend.length})
      </p>
      <p className="text-[11px] text-gray-500">
        El supervisor lo marcó desde el teléfono. Si fue la misma tarea otro día: «Reprogramar» (registro y PDF para ESM).
        Si ESM la sacó y pidió otra: «Cambio de tarea (ESM)».
      </p>
      <div className="mt-2 divide-y rounded border">
        {pend.map((r) => (
          <div key={r.programacion_id} className="flex flex-wrap items-center gap-2 px-2 py-1.5 text-xs">
            <span className="w-20 tabular-nums text-gray-500">{r.fecha_programada ? `${r.fecha_programada.slice(8, 10)}/${r.fecha_programada.slice(5, 7)}` : 's/f'}</span>
            <span className="font-medium">{r.es_comodin ? 'Camión por asignar' : r.instalacion}</span>
            <span className="text-gray-500">· {r.faena} · {r.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención'}</span>
            <span className="flex-1 text-orange-800">{r.por_reprogramar_motivo}</span>
            {puedeEditar && (
              <Button size="sm" variant="outline" className="h-7 text-orange-700" onClick={() => setReprog(r)}>
                <CalendarClock className="mr-1 h-3.5 w-3.5" /> Reprogramar
              </Button>
            )}
            {puedeEditar && !r.es_comodin && (
              <Button size="sm" variant="outline" className="h-7 text-violet-700" onClick={() => setCambio(r)}
                      title="ESM sacó la tarea y pidió otra: anota qué se hizo en su lugar">
                <Replace className="mr-1 h-3.5 w-3.5" /> Cambio de tarea (ESM)
              </Button>
            )}
          </div>
        ))}
      </div>
      {cambio && (
        <CambioTareaModal row={cambio} rows={rows} instalaciones={instalaciones}
                          onClose={() => setCambio(null)}
                          onDone={() => { setCambio(null); qc.invalidateQueries({ queryKey: ['enex-inst'] }); onCambio() }} />
      )}
      {reprog && (
        <ReprogramacionModal row={reprog} nombre={reprog.es_comodin ? 'Camión por asignar' : reprog.instalacion_tipo === 'camion' ? `Camión ${reprog.patente ?? reprog.instalacion}` : reprog.instalacion}
                             limitarTrimestre onClose={() => setReprog(null)}
                             onDone={() => { setReprog(null); qc.invalidateQueries({ queryKey: ['enex-reprogramaciones'] }); onCambio() }} />
      )}
    </CardContent></Card>
  )
}


// [MIG658] Tareas que ESM cambió y no cupieron en el trimestre: siguen contando
// como atrasadas hasta adjuntar el correo de autorización del ADC.
function EsperanCorreoAdc({ rows, puedeEditar, onCambio }: { rows: EnexPanelRow[]; puedeEditar: boolean; onCambio: () => void }) {
  const [sel, setSel] = useState<EnexPanelRow | null>(null)
  const pend = rows.filter((r) => r.cambio_destino === 'pendiente_adc' && !r.ejecucion_id)
    .sort((a, b) => (a.cambio_fecha ?? '').localeCompare(b.cambio_fecha ?? ''))
  if (pend.length === 0) return null
  return (
    <Card className="border-violet-300"><CardContent className="p-3">
      <p className="flex items-center gap-1.5 text-sm font-semibold text-violet-900">
        <Replace className="h-4 w-4" /> Cambios de tarea esperando el correo del ADC ({pend.length})
      </p>
      <p className="text-[11px] text-gray-500">Mientras no llegue el correo, cuentan como atrasadas en el KPI (KPI V8, consideración 1).</p>
      <div className="mt-2 divide-y rounded border">
        {pend.map((r) => (
          <div key={r.programacion_id} className="flex flex-wrap items-center gap-2 px-2 py-1.5 text-xs">
            <span className="w-20 tabular-nums text-gray-500">{r.cambio_fecha ? `${r.cambio_fecha.slice(8, 10)}/${r.cambio_fecha.slice(5, 7)}` : 's/f'}</span>
            <span className="font-medium">{nombreProg(r)}</span>
            <span className="text-gray-500">· {r.faena} · {r.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención'}</span>
            <span className="flex-1 text-violet-800">{r.cambio_solicitante}: {r.cambio_motivo}</span>
            <span className="text-[10px] text-gray-400">{r.cambio_destino ? CAMBIO_DESTINO_TXT[r.cambio_destino] : ''}</span>
            {puedeEditar && (
              <Button size="sm" variant="outline" className="h-7 text-violet-700" onClick={() => setSel(r)}>Adjuntar correo / reprogramar</Button>
            )}
          </div>
        ))}
      </div>
      {sel && <GestionarCambioModal row={sel} onClose={() => setSel(null)} onDone={() => { setSel(null); onCambio() }} />}
    </CardContent></Card>
  )
}
