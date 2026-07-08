'use client'

// Módulo Calama-ENEX — Fase 1: control + KPI de cumplimiento (MIG206).
// Replica el "Panel de Control ESM-ENEX": instalación × servicio por mes, plan
// vs cumplimiento, con el KPI de cumplimiento y la exposición a multa en vivo.

import { useMemo, useState } from 'react'
import { useQuery, useQueryClient, useMutation } from '@tanstack/react-query'
import {
  Building2, ChevronLeft, ChevronRight, Copy, Plus, CheckCircle2, Clock, X, AlertTriangle, Loader2, Camera,
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
  getFaenas, getInstalaciones, getPanelMensual, getKpiMensual,
  programar, desprogramar, registrarEjecucion, duplicarPeriodo, crearInstalacion,
  subirFirmaMandante, subirEvidenciaEnex,
  TIPO_INSTALACION_LABEL, MESES, clp,
  type EnexPanelRow, type EnexInstalacion, type TipoServicio,
} from '@/lib/services/enex'

const hoy = () => { const d = new Date(); return { anio: d.getFullYear(), mes: d.getMonth() + 1 } }
const SERVICIOS: TipoServicio[] = ['mantencion', 'calibracion']
const SERVICIO_LABEL: Record<TipoServicio, string> = { mantencion: 'Mantención', calibracion: 'Calibración y certificación' }

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
  const [faenaSel, setFaenaSel] = useState<string | null>(null)
  const [cell, setCell] = useState<{ inst: EnexInstalacion; servicio: TipoServicio; row?: EnexPanelRow } | null>(null)
  const [addInst, setAddInst] = useState(false)

  const { data: faenas = [] } = useQuery({ queryKey: ['enex-faenas'], queryFn: getFaenas, staleTime: 5 * 60_000 })
  const faenaId = faenaSel ?? faenas[0]?.id ?? null
  const { data: kpis = [] } = useQuery({ queryKey: ['enex-kpi', anio, mes], queryFn: () => getKpiMensual(anio, mes), staleTime: 15_000 })
  const { data: instalaciones = [] } = useQuery({
    queryKey: ['enex-inst', faenaId], queryFn: () => getInstalaciones(faenaId ?? undefined), enabled: !!faenaId, staleTime: 60_000,
  })
  const { data: panel = [] } = useQuery({
    queryKey: ['enex-panel', anio, mes, faenaId], queryFn: () => getPanelMensual(anio, mes, faenaId ?? undefined),
    enabled: !!faenaId, staleTime: 10_000,
  })

  const invalidar = () => {
    qc.invalidateQueries({ queryKey: ['enex-panel'] })
    qc.invalidateQueries({ queryKey: ['enex-kpi'] })
  }

  // Índice panel por instalación+servicio
  const panelIdx = useMemo(() => {
    const m = new Map<string, EnexPanelRow>()
    for (const r of panel) m.set(`${r.instalacion_id}|${r.tipo_servicio}`, r)
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
    if (m < 1) { m = 12; a-- } else if (m > 12) { m = 1; a++ }
    setPeriodo({ anio: a, mes: m })
  }

  const faenaActual = faenas.find((f) => f.id === faenaId)

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
        <div className="flex items-center gap-2">
          <button onClick={() => cambiarMes(-1)} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50"><ChevronLeft className="h-4 w-4" /></button>
          <span className="min-w-[130px] text-center text-sm font-semibold">{MESES[mes - 1]} {anio}</span>
          <button onClick={() => cambiarMes(1)} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50"><ChevronRight className="h-4 w-4" /></button>
          <Button variant="outline" onClick={() => dup.mutate()} disabled={dup.isPending} title="Copiar el plan del mes anterior">
            {dup.isPending ? <Spinner className="h-4 w-4" /> : <Copy className="h-4 w-4 mr-1" />} Copiar mes ant.
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
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-xs text-gray-500">
                  <th className="p-2 text-left">Instalación</th>
                  {SERVICIOS.map((s) => <th key={s} className="p-2 text-center min-w-[180px]">{SERVICIO_LABEL[s]}</th>)}
                </tr>
              </thead>
              <tbody>
                {instalaciones.length === 0 ? (
                  <tr><td colSpan={3} className="p-6 text-center text-sm text-gray-400">
                    Esta faena aún no tiene instalaciones. Agrégalas con «Instalación».
                  </td></tr>
                ) : instalaciones.map((i) => (
                  <tr key={i.id} className="border-b hover:bg-gray-50/50">
                    <td className="p-2">
                      <div className="font-medium text-gray-800">{i.nombre}</div>
                      <div className="text-[11px] text-gray-500">
                        {TIPO_INSTALACION_LABEL[i.tipo]}{i.patente ? ` · ${i.patente}` : ''}{i.linea ? ` · ${i.linea}` : ''}
                      </div>
                    </td>
                    {SERVICIOS.map((s) => {
                      const row = panelIdx.get(`${i.id}|${s}`)
                      return (
                        <td key={s} className="p-2 text-center">
                          <CeldaServicio row={row} onClick={() => setCell({ inst: i, servicio: s, row })} />
                        </td>
                      )
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>

      {cell && (
        <CeldaModal anio={anio} mes={mes} inst={cell.inst} servicio={cell.servicio} row={cell.row}
                    onClose={() => setCell(null)} onDone={() => { setCell(null); invalidar() }} />
      )}
      {addInst && faenaId && (
        <AgregarInstalacionModal faenaId={faenaId} onClose={() => setAddInst(false)}
                                 onDone={() => { setAddInst(false); qc.invalidateQueries({ queryKey: ['enex-inst'] }) }} />
      )}
    </div>
  )
}

function CeldaServicio({ row, onClick }: { row?: EnexPanelRow; onClick: () => void }) {
  if (!row) {
    return <button onClick={onClick} className="rounded-md border border-dashed border-gray-300 px-2 py-1 text-[11px] text-gray-400 hover:border-blue-400 hover:text-blue-600">+ programar</button>
  }
  if (row.cumplida) {
    return <button onClick={onClick} className="inline-flex items-center gap-1 rounded-full bg-green-100 px-2.5 py-1 text-[11px] font-semibold text-green-700">
      <CheckCircle2 className="h-3.5 w-3.5" /> Cumplida{row.ot_numero ? ` · ${row.ot_numero}` : ''}
    </button>
  }
  if (row.estado === 'no_realizada') {
    return <button onClick={onClick} className="inline-flex items-center gap-1 rounded-full bg-red-100 px-2.5 py-1 text-[11px] font-semibold text-red-700">
      <X className="h-3.5 w-3.5" /> No realizada
    </button>
  }
  if (row.estado === 'ejecutada') {
    return <button onClick={onClick} className="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2.5 py-1 text-[11px] font-semibold text-amber-800">
      <Clock className="h-3.5 w-3.5" /> Ejecutada · falta firma
    </button>
  }
  return <button onClick={onClick} className="inline-flex items-center gap-1 rounded-full bg-blue-100 px-2.5 py-1 text-[11px] font-semibold text-blue-700">
    <Clock className="h-3.5 w-3.5" /> Programada{row.fecha_programada ? ` · ${row.fecha_programada.slice(8, 10)}/${row.fecha_programada.slice(5, 7)}` : ''}
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

  // No programada aún → programar
  if (!row) {
    return (
      <Modal open onClose={onClose} title={titulo}>
        <div className="space-y-3">
          <p className="text-sm text-gray-600">Programa este servicio para {MESES[mes - 1]} {anio}.</p>
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
            <Button variant="outline" size="sm" onClick={() => setModo('ejecutar')}>Editar registro</Button>
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
