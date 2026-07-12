'use client'

// Módulo Calama-ENEX — Fase 1: control + KPI de cumplimiento (MIG206).
// Replica el "Panel de Control ESM-ENEX": instalación × servicio por mes, plan
// vs cumplimiento, con el KPI de cumplimiento y la exposición a multa en vivo.
// MIG229: vista TRIMESTRAL y varias programaciones del mismo punto en el mes.

import { useMemo, useState } from 'react'
import { useQuery, useQueryClient, useMutation } from '@tanstack/react-query'
import {
  Building2, ChevronLeft, ChevronRight, Copy, Plus, CheckCircle2, Clock, X, AlertTriangle, Loader2, Camera,
  Printer, FileSpreadsheet, CalendarDays, CalendarRange,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getFaenas, getInstalaciones, getPanelMensual, getKpiMensual, getPanelMeses, getKpiMeses,
  programar, desprogramar, registrarEjecucion, duplicarPeriodo, crearInstalacion, actualizarFrecuencias,
  subirFirmaMandante, subirEvidenciaEnex,
  TIPO_INSTALACION_LABEL, MESES, clp,
  type EnexPanelRow, type EnexInstalacion, type TipoServicio,
} from '@/lib/services/enex'

const hoy = () => { const d = new Date(); return { anio: d.getFullYear(), mes: d.getMonth() + 1 } }
const SERVICIOS: TipoServicio[] = ['mantencion', 'calibracion']
const SERVICIO_LABEL: Record<TipoServicio, string> = { mantencion: 'Mantención', calibracion: 'Calibración y certificación' }
const SERVICIO_CORTO: Record<TipoServicio, string> = { mantencion: 'Mant.', calibracion: 'Calib.' }

function kpiColor(pct: number | null): string {
  if (pct == null) return 'text-gray-400'
  if (pct >= 96) return 'text-green-600'
  if (pct >= 90) return 'text-amber-600'
  return 'text-red-600'
}

export default function EnexControlPage() {
  useRequireAuth()
  const qc = useQueryClient()
  const toast = useToast()
  const [{ anio, mes }, setPeriodo] = useState(hoy())
  const [vista, setVista] = useState<'mes' | 'trimestre'>('mes')
  const [faenaSel, setFaenaSel] = useState<string | null>(null)
  const [cell, setCell] = useState<{ inst: EnexInstalacion; servicio: TipoServicio; mes: number; row?: EnexPanelRow } | null>(null)
  const [addInst, setAddInst] = useState(false)
  const [frecEdit, setFrecEdit] = useState<EnexInstalacion | null>(null)

  // Meses del trimestre calendario del mes seleccionado (T1: ene-mar, …)
  const mesesTri = useMemo(() => {
    const base = Math.floor((mes - 1) / 3) * 3 + 1
    return [base, base + 1, base + 2]
  }, [mes])
  const meses = vista === 'mes' ? [mes] : mesesTri

  const { data: faenas = [] } = useQuery({ queryKey: ['enex-faenas'], queryFn: getFaenas, staleTime: 5 * 60_000 })
  const faenaId = faenaSel ?? faenas[0]?.id ?? null
  const { data: kpis = [] } = useQuery({ queryKey: ['enex-kpi', anio, mes], queryFn: () => getKpiMensual(anio, mes), staleTime: 15_000 })
  const { data: kpisTri = [] } = useQuery({
    queryKey: ['enex-kpi-tri', anio, mesesTri[0]], queryFn: () => getKpiMeses(anio, mesesTri),
    enabled: vista === 'trimestre', staleTime: 15_000,
  })
  const { data: instalaciones = [] } = useQuery({
    queryKey: ['enex-inst', faenaId], queryFn: () => getInstalaciones(faenaId ?? undefined), enabled: !!faenaId, staleTime: 60_000,
  })
  const { data: panel = [] } = useQuery({
    queryKey: ['enex-panel', anio, vista, meses.join(','), faenaId],
    queryFn: () => vista === 'mes'
      ? getPanelMensual(anio, mes, faenaId ?? undefined)
      : getPanelMeses(anio, mesesTri, faenaId ?? undefined),
    enabled: !!faenaId, staleTime: 10_000,
  })

  const invalidar = () => {
    qc.invalidateQueries({ queryKey: ['enex-panel'] })
    qc.invalidateQueries({ queryKey: ['enex-kpi'] })
    qc.invalidateQueries({ queryKey: ['enex-kpi-tri'] })
  }

  // Índice panel: (instalación, servicio, mes) → TODAS sus programaciones
  // (MIG229: un punto puede estar programado varias veces en el mes).
  const panelIdx = useMemo(() => {
    const m = new Map<string, EnexPanelRow[]>()
    for (const r of panel) {
      const k = `${r.instalacion_id}|${r.tipo_servicio}|${r.periodo_mes}`
      const arr = m.get(k) ?? []
      arr.push(r)
      m.set(k, arr)
    }
    m.forEach((arr) => {
      arr.sort((a, b) => (a.fecha_programada ?? '9999').localeCompare(b.fecha_programada ?? '9999'))
    })
    return m
  }, [panel])

  const dup = useMutation({
    mutationFn: () => {
      const prev = mes === 1 ? { a: anio - 1, m: 12 } : { a: anio, m: mes - 1 }
      return duplicarPeriodo(prev.a, prev.m, anio, mes)
    },
    onSuccess: (r) => { toast.success(`${r.copiadas} programaciones copiadas del mes anterior`); invalidar() },
    onError: (e) => toast.error((e as Error).message),
  })

  function cambiarMes(delta: number) {
    let m = mes + delta, a = anio
    while (m < 1) { m += 12; a-- }
    while (m > 12) { m -= 12; a++ }
    setPeriodo({ anio: a, mes: m })
  }

  const faenaActual = faenas.find((f) => f.id === faenaId)
  const trimestreNum = Math.floor((mes - 1) / 3) + 1

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold flex items-center gap-2">
            <Building2 className="h-5 w-5 text-blue-700" /> Control Calama — ENEX / ESM
          </h1>
          <p className="text-sm text-gray-500 mt-0.5">
            Programa de mantención por instalación y cumplimiento del contrato (KPI y exposición a multa).
          </p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <div className="flex rounded-lg border overflow-hidden">
            {([['mes', 'Mes', CalendarDays], ['trimestre', 'Trimestre', CalendarRange]] as const).map(([id, label, Icon]) => (
              <button key={id} onClick={() => setVista(id)}
                      className={`flex items-center gap-1 px-2.5 py-1.5 text-xs font-semibold ${
                        vista === id ? 'bg-blue-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>
                <Icon className="h-3.5 w-3.5" /> {label}
              </button>
            ))}
          </div>
          <button onClick={() => cambiarMes(vista === 'mes' ? -1 : -3)} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50"><ChevronLeft className="h-4 w-4" /></button>
          <span className="min-w-[130px] text-center text-sm font-semibold">
            {vista === 'mes'
              ? `${MESES[mes - 1]} ${anio}`
              : `T${trimestreNum} · ${MESES[mesesTri[0] - 1].slice(0, 3)}–${MESES[mesesTri[2] - 1].slice(0, 3)} ${anio}`}
          </span>
          <button onClick={() => cambiarMes(vista === 'mes' ? 1 : 3)} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50"><ChevronRight className="h-4 w-4" /></button>
          {vista === 'mes' && (
          <Button variant="outline" onClick={() => dup.mutate()} disabled={dup.isPending} title="Copiar el plan del mes anterior">
            {dup.isPending ? <Spinner className="h-4 w-4" /> : <Copy className="h-4 w-4 mr-1" />} Copiar mes ant.
          </Button>
          )}
          <Button variant="outline" disabled={panel.length === 0}
                  title="Exportar el programa del mes a Excel/CSV (respaldo mensual para ENEX)"
                  onClick={() => {
                    const esc = (v: unknown) => `"${String(v ?? '').replace(/"/g, '""')}"`
                    const filas = panel.map((r) => [
                      r.faena, MESES[r.periodo_mes - 1], r.instalacion, r.instalacion_tipo ?? '', r.patente ?? '', r.tipo_servicio,
                      r.fecha_programada ?? '', r.fecha_ejecucion ?? '', r.ot_numero ?? '', r.ejecutor ?? '',
                      r.cumplida ? 'CUMPLIDA' : (r.estado ?? 'programada'), r.firmante_mandante_nombre ?? '',
                    ].map(esc).join(';'))
                    const csv = ['Faena;Mes;Instalación;Tipo;Patente;Servicio;Programada;Ejecutada;OT;Ejecutor;Estado;Firmó mandante', ...filas].join('\r\n')
                    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' })
                    const a = document.createElement('a')
                    a.href = URL.createObjectURL(blob)
                    a.download = vista === 'mes'
                      ? `ENEX_programa_${anio}-${String(mes).padStart(2, '0')}.csv`
                      : `ENEX_programa_${anio}-T${trimestreNum}.csv`
                    a.click()
                    URL.revokeObjectURL(a.href)
                  }}>
            <FileSpreadsheet className="h-4 w-4 mr-1" /> Exportar mes
          </Button>
        </div>
      </div>

      {/* KPI por faena (todas) */}
      <div className="grid gap-2 grid-cols-2 md:grid-cols-3 lg:grid-cols-5">
        {faenas.map((f) => {
          const k = kpis.find((x) => x.faena_id === f.id)
          const pct = k?.cumplimiento_pct ?? null
          const activo = f.id === faenaId
          return (
            <button key={f.id} onClick={() => setFaenaSel(f.id)}
                    className={`rounded-xl border p-3 text-left ${activo ? 'border-blue-500 bg-blue-50/40' : 'border-gray-200 bg-white hover:bg-gray-50'}`}>
              <div className="text-xs font-semibold text-gray-700 truncate">{f.nombre}</div>
              <div className={`text-2xl font-bold ${kpiColor(pct)}`}>{pct != null ? `${pct}%` : '—'}</div>
              <div className="text-[11px] text-gray-500">
                {k ? `${k.cumplidas}/${k.programadas} cumplidas` : 'sin programación'}
              </div>
              {k && k.programadas > 0 && k.tramo_multa_pct > 0 && (
                <div className={`mt-1 rounded px-1.5 py-0.5 text-[10px] font-semibold ${k.en_revision_continuidad ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-800'}`}>
                  {k.en_revision_continuidad ? 'Revisión continuidad' : `Multa ${k.tramo_multa_pct}%`} · {clp(k.monto_riesgo_clp)} en riesgo
                </div>
              )}
            </button>
          )
        })}
      </div>

      {/* Panel de la faena seleccionada */}
      <Card>
        <CardContent className="p-0">
          <div className="flex items-center justify-between border-b p-3">
            <div>
              <h2 className="text-sm font-semibold">{faenaActual?.nombre}</h2>
              <p className="text-[11px] text-gray-500">
                {faenaActual?.cliente_minero} · {faenaActual?.operador} · vence {faenaActual?.vigencia_hasta}
                {faenaActual && ` · factura ${clp(faenaActual.facturacion_mensual_clp)}/mes`}
              </p>
            </div>
            <Button variant="outline" size="sm" onClick={() => setAddInst(true)}>
              <Plus className="h-4 w-4 mr-1" /> Instalación
            </Button>
          </div>
          {/* KPI por mes del trimestre (faena seleccionada) */}
          {vista === 'trimestre' && (
            <div className="grid grid-cols-3 gap-2 border-b p-3">
              {mesesTri.map((m) => {
                const k = kpisTri.find((x) => x.faena_id === faenaId && x.periodo_mes === m)
                const pct = k?.cumplimiento_pct ?? null
                return (
                  <div key={m} className="rounded-lg border bg-gray-50/60 p-2 text-center">
                    <div className="text-[11px] font-semibold text-gray-600">{MESES[m - 1]}</div>
                    <div className={`text-lg font-bold ${kpiColor(pct)}`}>{pct != null ? `${pct}%` : '—'}</div>
                    <div className="text-[10px] text-gray-500">{k ? `${k.cumplidas}/${k.programadas} cumplidas` : 'sin programación'}</div>
                  </div>
                )
              })}
            </div>
          )}
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-xs text-gray-500">
                  <th className="p-2 text-left">Instalación</th>
                  {vista === 'mes'
                    ? SERVICIOS.map((s) => <th key={s} className="p-2 text-center min-w-[180px]">{SERVICIO_LABEL[s]}</th>)
                    : mesesTri.map((m) => <th key={m} className="p-2 text-center min-w-[190px] capitalize">{MESES[m - 1]}</th>)}
                </tr>
              </thead>
              <tbody>
                {instalaciones.length === 0 ? (
                  <tr><td colSpan={4} className="p-6 text-center text-sm text-gray-400">
                    Esta faena aún no tiene instalaciones. Agrégalas con «Instalación».
                  </td></tr>
                ) : instalaciones.map((i) => (
                  <tr key={i.id} className="border-b hover:bg-gray-50/50">
                    <td className="p-2">
                      <div className="font-medium text-gray-800">{i.nombre}</div>
                      <div className="text-[11px] text-gray-500">
                        {TIPO_INSTALACION_LABEL[i.tipo]}{i.patente ? ` · ${i.patente}` : ''}{i.linea ? ` · ${i.linea}` : ''}
                      </div>
                      {/* Frecuencia exigida por el contrato — referencia al planificar (MIG230) */}
                      {(i.frecuencia_mantencion || i.frecuencia_calibracion) && (
                        <button onClick={() => setFrecEdit(i)} title="Frecuencia del contrato — clic para editar"
                                className="mt-0.5 block text-left text-[10px] text-indigo-600 hover:underline">
                          Contrato: {i.frecuencia_mantencion && `Mant. ${i.frecuencia_mantencion}`}
                          {i.frecuencia_mantencion && i.frecuencia_calibracion && ' · '}
                          {i.frecuencia_calibracion && `Calib. ${i.frecuencia_calibracion}`}
                        </button>
                      )}
                    </td>
                    {vista === 'mes' ? (
                      SERVICIOS.map((s) => {
                        const rows = panelIdx.get(`${i.id}|${s}|${mes}`) ?? []
                        return (
                          <td key={s} className="p-2 text-center align-top">
                            <CeldaServicio rows={rows}
                                           onOpen={(row) => setCell({ inst: i, servicio: s, mes, row })}
                                           onAdd={() => setCell({ inst: i, servicio: s, mes })} />
                          </td>
                        )
                      })
                    ) : (
                      mesesTri.map((m) => (
                        <td key={m} className="p-2 align-top">
                          <div className="space-y-1.5">
                            {SERVICIOS.map((s) => {
                              const rows = panelIdx.get(`${i.id}|${s}|${m}`) ?? []
                              return (
                                <div key={s} className="flex items-start gap-1">
                                  <span className="mt-0.5 w-9 shrink-0 text-[9px] font-bold uppercase text-gray-400">{SERVICIO_CORTO[s]}</span>
                                  <div className="flex-1">
                                    <CeldaServicio rows={rows} compact
                                                   onOpen={(row) => setCell({ inst: i, servicio: s, mes: m, row })}
                                                   onAdd={() => setCell({ inst: i, servicio: s, mes: m })} />
                                  </div>
                                </div>
                              )
                            })}
                          </div>
                        </td>
                      ))
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>

      {cell && (
        <CeldaModal anio={anio} mes={cell.mes} inst={cell.inst} servicio={cell.servicio} row={cell.row}
                    onClose={() => setCell(null)} onDone={() => { setCell(null); invalidar() }} />
      )}
      {addInst && faenaId && (
        <AgregarInstalacionModal faenaId={faenaId} onClose={() => setAddInst(false)}
                                 onDone={() => { setAddInst(false); qc.invalidateQueries({ queryKey: ['enex-inst'] }) }} />
      )}
      {frecEdit && (
        <FrecuenciasModal inst={frecEdit} onClose={() => setFrecEdit(null)}
                          onDone={() => { setFrecEdit(null); qc.invalidateQueries({ queryKey: ['enex-inst'] }) }} />
      )}
    </div>
  )
}

// Una celda = TODAS las programaciones del punto ese mes (MIG229) + botón «+»
// para agregar otra (ej. calibración quincenal: 2 veces en el mes).
function CeldaServicio({ rows, onOpen, onAdd, compact }: {
  rows: EnexPanelRow[]; onOpen: (row: EnexPanelRow) => void; onAdd: () => void; compact?: boolean
}) {
  if (rows.length === 0) {
    return (
      <button onClick={onAdd}
              className="rounded-md border border-dashed border-gray-300 px-2 py-1 text-[11px] text-gray-400 hover:border-blue-400 hover:text-blue-600">
        + programar
      </button>
    )
  }
  return (
    <div className={`flex flex-wrap items-center gap-1 ${compact ? '' : 'justify-center'}`}>
      {rows.map((row) => <ChipProgramacion key={row.programacion_id} row={row} onClick={() => onOpen(row)} />)}
      <button onClick={onAdd} title="Programar otra vez este punto en el mes"
              className="rounded-full border border-dashed border-gray-300 px-1.5 py-0.5 text-[11px] font-bold text-gray-400 hover:border-blue-400 hover:text-blue-600">
        +
      </button>
    </div>
  )
}

function ChipProgramacion({ row, onClick }: { row: EnexPanelRow; onClick: () => void }) {
  const dia = row.fecha_programada ? ` · ${row.fecha_programada.slice(8, 10)}/${row.fecha_programada.slice(5, 7)}` : ''
  if (row.cumplida) {
    return <button onClick={onClick} className="inline-flex items-center gap-1 rounded-full bg-green-100 px-2 py-0.5 text-[11px] font-semibold text-green-700">
      <CheckCircle2 className="h-3 w-3" /> Cumplida{dia || (row.ot_numero ? ` · ${row.ot_numero}` : '')}
    </button>
  }
  if (row.estado === 'no_realizada') {
    return <button onClick={onClick} className="inline-flex items-center gap-1 rounded-full bg-red-100 px-2 py-0.5 text-[11px] font-semibold text-red-700">
      <X className="h-3 w-3" /> No realizada
    </button>
  }
  if (row.estado === 'ejecutada') {
    return <button onClick={onClick} className="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-semibold text-amber-800">
      <Clock className="h-3 w-3" /> Falta firma{dia}
    </button>
  }
  return <button onClick={onClick} className="inline-flex items-center gap-1 rounded-full bg-blue-100 px-2 py-0.5 text-[11px] font-semibold text-blue-700">
    <Clock className="h-3 w-3" /> Prog.{dia}
  </button>
}

function CeldaModal({ anio, mes, inst, servicio, row, onClose, onDone }: {
  anio: number; mes: number; inst: EnexInstalacion; servicio: TipoServicio
  row?: EnexPanelRow; onClose: () => void; onDone: () => void
}) {
  const toast = useToast()
  const [busy, setBusy] = useState(false)
  // programar
  const [fecha, setFecha] = useState(row?.fecha_programada ?? '')
  // ejecución
  const [ejecFecha, setEjecFecha] = useState(row?.fecha_ejecucion ?? '')
  const [otNumero, setOtNumero] = useState(row?.ot_numero ?? '')
  const [ejecutor, setEjecutor] = useState(row?.ejecutor ?? '')
  const [obs, setObs] = useState(row?.ejec_observacion ?? '')
  const [firma, setFirma] = useState('')
  const [firmante, setFirmante] = useState(row?.firmante_mandante_nombre ?? '')
  const [evid, setEvid] = useState<File[]>([])
  const [modo, setModo] = useState<'ver' | 'ejecutar'>(row?.estado === 'ejecutada' || !row?.ejecucion_id ? 'ejecutar' : 'ver')

  async function doProgramar() {
    setBusy(true)
    try {
      await programar({ instalacionId: inst.id, tipoServicio: servicio, anio, mes, fecha: fecha || null })
      toast.success('Programada'); onDone()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }
  async function doQuitar() {
    if (!row) return
    setBusy(true)
    try { await desprogramar(row.programacion_id); toast.success('Quitada del plan'); onDone() }
    catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }
  async function doEjecutar() {
    if (!row) return
    setBusy(true)
    try {
      const evidUrls: string[] = []
      for (const f of evid) evidUrls.push(await subirEvidenciaEnex(f))
      const firmaUrl = firma ? await subirFirmaMandante(firma) : null
      const r = await registrarEjecucion({
        programacionId: row.programacion_id, fecha: ejecFecha || null, otNumero: otNumero || null,
        ejecutor: ejecutor || null, observacion: obs || null,
        evidenciaUrls: evidUrls.length ? evidUrls : null,
        firmaMandanteUrl: firmaUrl, firmanteMandante: firmante || null,
      })
      toast.success(r.cumplida ? 'Registrada y CUMPLIDA (con firma del mandante)' : 'Ejecución registrada — falta firma del mandante para cumplir el KPI')
      onDone()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  const titulo = `${inst.nombre} · ${SERVICIO_LABEL[servicio]}`

  // Frecuencia que exige el contrato para este servicio (referencia MIG230).
  const frecContrato = servicio === 'mantencion' ? inst.frecuencia_mantencion : inst.frecuencia_calibracion

  // No programada aún → programar
  if (!row) {
    return (
      <Modal open onClose={onClose} title={titulo}>
        <div className="space-y-3">
          <p className="text-sm text-gray-600">Programa este servicio para {MESES[mes - 1]} {anio}.</p>
          {frecContrato && (
            <div className="rounded-lg border border-indigo-200 bg-indigo-50/60 px-3 py-2 text-xs text-indigo-800">
              <b>Frecuencia según contrato:</b> {frecContrato}
            </div>
          )}
          <div>
            <label className="text-xs font-medium">Fecha planificada (opcional)</label>
            <Input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} />
          </div>
        </div>
        <ModalFooter>
          <Button variant="outline" onClick={onClose}>Cancelar</Button>
          <Button disabled={busy} onClick={doProgramar}>{busy ? <Spinner className="h-4 w-4 mr-1" /> : null} Programar</Button>
        </ModalFooter>
      </Modal>
    )
  }

  return (
    <Modal open onClose={onClose} title={titulo}>
      <div className="space-y-3">
        <div className="flex items-center gap-2 text-xs">
          <span className="rounded bg-gray-100 px-2 py-0.5 text-gray-600">{MESES[mes - 1]} {anio}</span>
          {row.cumplida
            ? <span className="rounded-full bg-green-100 px-2 py-0.5 font-semibold text-green-700">Cumplida</span>
            : <span className="rounded-full bg-amber-100 px-2 py-0.5 font-semibold text-amber-800">Pendiente de firma del mandante</span>}
        </div>

        {modo === 'ver' && row.cumplida ? (
          <div className="space-y-2 text-sm">
            <p><b>OT:</b> {row.ot_numero ?? '—'} · <b>Fecha:</b> {row.fecha_ejecucion ?? '—'}</p>
            <p><b>Ejecutor:</b> {row.ejecutor ?? '—'}</p>
            {row.ejec_observacion && <p className="text-gray-600">{row.ejec_observacion}</p>}
            <p><b>Firmó (mandante):</b> {row.firmante_mandante_nombre ?? '—'}</p>
            <div className="flex flex-wrap gap-2">
              {(row.evidencia_urls ?? []).map((u, i) => (
                // eslint-disable-next-line @next/next/no-img-element
                <a key={i} href={u} target="_blank" rel="noreferrer"><img src={u} alt="ev" className="h-16 w-16 rounded border object-cover" /></a>
              ))}
              {row.firma_mandante_url && (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={row.firma_mandante_url} alt="firma" className="h-16 rounded border bg-white object-contain px-2" />
              )}
            </div>
            <div className="flex gap-2">
              {row.ejecucion_id && (
                <Button variant="primary" size="sm" onClick={() => window.open(`/enex-reporte/${row.ejecucion_id}`, '_blank')}>
                  <Printer className="h-4 w-4 mr-1" />
                  {row.tipo_servicio === 'calibracion' ? 'Certificado de calibración' : 'Reporte de servicio'}
                </Button>
              )}
              <Button variant="outline" size="sm" onClick={() => setModo('ejecutar')}>Editar registro</Button>
            </div>
          </div>
        ) : (
          <div className="space-y-2">
            <div className="grid grid-cols-2 gap-2">
              <div><label className="text-xs font-medium">Fecha ejecución</label><Input type="date" value={ejecFecha} onChange={(e) => setEjecFecha(e.target.value)} /></div>
              <div><label className="text-xs font-medium">N° OT (mandante)</label><Input value={otNumero} onChange={(e) => setOtNumero(e.target.value)} placeholder="ej 249827871" /></div>
            </div>
            <div><label className="text-xs font-medium">Ejecutor(es)</label><Input value={ejecutor} onChange={(e) => setEjecutor(e.target.value)} placeholder="Mantenedor(es)" /></div>
            <div><label className="text-xs font-medium">Observación</label><Input value={obs} onChange={(e) => setObs(e.target.value)} placeholder="opcional" /></div>
            <div>
              <label className="text-xs font-medium flex items-center gap-1"><Camera className="h-3.5 w-3.5" /> Evidencias (fotos)</label>
              <div className="mt-1 flex items-center gap-2">
                {evid.map((f, i) => <span key={i} className="rounded bg-gray-100 px-2 py-1 text-[10px]">{f.name}</span>)}
                <label className="cursor-pointer rounded border border-dashed px-2 py-1 text-[11px] text-gray-500">
                  + foto
                  <input type="file" accept="image/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) setEvid((p) => [...p, f]); e.target.value = '' }} />
                </label>
              </div>
            </div>
            <div className="rounded-lg border border-blue-200 bg-blue-50/40 p-2">
              <label className="text-xs font-semibold text-blue-800">Firma del mandante (obligatoria para cumplir KPI)</label>
              <Input value={firmante} onChange={(e) => setFirmante(e.target.value)} placeholder="Nombre de quien firma (ESM/ENEX)" className="my-1.5" />
              <SignaturePad label="Firma en pantalla" onCapture={setFirma} />
              {row.firma_mandante_url && !firma && (
                <p className="mt-1 text-[10px] text-green-700">Ya tiene firma registrada — vuelve a firmar solo si quieres reemplazarla.</p>
              )}
            </div>
          </div>
        )}
      </div>
      <ModalFooter>
        {row.estado !== 'cumplida' && !row.ejecucion_id && (
          <Button variant="outline" onClick={doQuitar} disabled={busy} className="mr-auto text-red-600">Quitar del plan</Button>
        )}
        <Button variant="outline" onClick={onClose}>Cerrar</Button>
        {modo === 'ejecutar' && (
          <Button disabled={busy} onClick={doEjecutar}>
            {busy ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <CheckCircle2 className="h-4 w-4 mr-1" />}
            Guardar {firma || row.firma_mandante_url ? '(cumplida)' : 'ejecución'}
          </Button>
        )}
      </ModalFooter>
    </Modal>
  )
}

// Editar la frecuencia contractual de referencia de una instalación (MIG230).
function FrecuenciasModal({ inst, onClose, onDone }: { inst: EnexInstalacion; onClose: () => void; onDone: () => void }) {
  const toast = useToast()
  const [mant, setMant] = useState(inst.frecuencia_mantencion ?? '')
  const [calib, setCalib] = useState(inst.frecuencia_calibracion ?? '')
  const [busy, setBusy] = useState(false)

  async function guardar() {
    setBusy(true)
    try {
      await actualizarFrecuencias(inst.id, {
        frecuenciaMantencion: mant.trim() || null,
        frecuenciaCalibracion: calib.trim() || null,
      })
      toast.success('Frecuencias actualizadas')
      onDone()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  return (
    <Modal open onClose={onClose} title={`Frecuencia del contrato · ${inst.nombre}`}>
      <div className="space-y-3">
        <p className="text-xs text-gray-500">
          Referencia al planificar (contrato VA_24_068 y anexos). Ejemplos: «Trimestral»,
          «Mensual», «2 veces/mes», «Quincenal», «Según requerimiento».
        </p>
        <div>
          <label className="text-xs font-medium">Mantención</label>
          <Input value={mant} onChange={(e) => setMant(e.target.value)} placeholder="ej. Trimestral" />
        </div>
        <div>
          <label className="text-xs font-medium">Calibración y certificación</label>
          <Input value={calib} onChange={(e) => setCalib(e.target.value)} placeholder="ej. Trimestral · NCh 1436:2001" />
        </div>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button disabled={busy} onClick={guardar}>{busy ? <Spinner className="h-4 w-4 mr-1" /> : null} Guardar</Button>
      </ModalFooter>
    </Modal>
  )
}

function AgregarInstalacionModal({ faenaId, onClose, onDone }: { faenaId: string; onClose: () => void; onDone: () => void }) {
  const toast = useToast()
  const [nombre, setNombre] = useState('')
  const [tipo, setTipo] = useState<EnexInstalacion['tipo']>('eess')
  const [linea, setLinea] = useState('combustible')
  const [patente, setPatente] = useState('')
  const [busy, setBusy] = useState(false)

  async function guardar() {
    if (!nombre.trim()) return
    setBusy(true)
    try {
      await crearInstalacion({ faenaId, nombre: nombre.trim(), tipo, linea, patente: tipo === 'camion' ? (patente.trim() || null) : null })
      toast.success('Instalación agregada'); onDone()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  return (
    <Modal open onClose={onClose} title="Agregar instalación">
      <div className="space-y-3">
        <div><label className="text-xs font-medium">Nombre</label><Input value={nombre} onChange={(e) => setNombre(e.target.value)} placeholder="ej EESS Muelle / Camión SXGH-43" /></div>
        <div className="grid grid-cols-2 gap-2">
          <div>
            <label className="text-xs font-medium">Tipo</label>
            <select value={tipo} onChange={(e) => setTipo(e.target.value as EnexInstalacion['tipo'])} className="w-full rounded border px-2 py-1.5 text-sm">
              {Object.entries(TIPO_INSTALACION_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </div>
          <div>
            <label className="text-xs font-medium">Línea</label>
            <select value={linea} onChange={(e) => setLinea(e.target.value)} className="w-full rounded border px-2 py-1.5 text-sm">
              <option value="combustible">Combustible</option>
              <option value="lubricante">Lubricante</option>
            </select>
          </div>
        </div>
        {tipo === 'camion' && (
          <div><label className="text-xs font-medium">Patente</label><Input value={patente} onChange={(e) => setPatente(e.target.value)} placeholder="ej SXGH-43" /></div>
        )}
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button disabled={busy || !nombre.trim()} onClick={guardar}>{busy ? <Spinner className="h-4 w-4 mr-1" /> : null} Agregar</Button>
      </ModalFooter>
    </Modal>
  )
}
