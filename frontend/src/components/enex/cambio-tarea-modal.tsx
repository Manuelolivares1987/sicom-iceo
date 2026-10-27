'use client'

// [MIG658] Cambio de tarea por instrucción de ESM. No es una reprogramación
// (misma tarea, otro día): ESM saca la tarea programada y pide otra. Se registra
// quién lo pidió, qué se hizo en su lugar (suma al KPI como tarea del contrato)
// y qué pasa con la desplazada: nueva fecha dentro del trimestre, o fuera del KPI
// solo con el correo del ADC (Consideración 1 del KPI Mantenimiento V8).

import { useMemo, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { Loader2, Replace, Paperclip, X, Truck, Ban } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useToast } from '@/contexts/toast-context'
import {
  registrarCambioTarea, cambiarDestinoCambio, anularCambioTarea, subirArchivoCambio, CAMBIO_DESTINO_TXT,
  type CambioDestino, type CambioReemplazo, type EnexInstalacion, type EnexPanelRow, type TipoServicio,
} from '@/lib/services/enex'
import { inicioTrimestreContractual, ventanaTrimestre, ultimoDiaMes } from '@/lib/enex-avance'

const SERV: Record<TipoServicio, string> = { mantencion: 'Mantención', calibracion: 'Calibración' }
const ddmm = (iso: string | null | undefined) => (iso ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}` : 's/f')
export const nombreProg = (r: EnexPanelRow) =>
  r.es_comodin ? 'Camión por asignar' : r.instalacion_tipo === 'camion' ? `Camión ${r.patente ?? r.instalacion}` : r.instalacion

function finTrimestreDe(r: EnexPanelRow) {
  const original = r.cambio_fecha ?? r.fecha_programada?.slice(0, 10) ?? ultimoDiaMes(r.periodo_anio, r.periodo_mes)
  const t = inicioTrimestreContractual(original, r.faena_trimestre_ancla ?? 2)
  return ventanaTrimestre(t.anio, t.mes).hasta
}

// Destino de la tarea desplazada (compartido por registrar y gestionar).
function DestinoCampos({ destino, setDestino, nuevaFecha, setNuevaFecha, adcNombre, setAdcNombre, adcArchivo, setAdcArchivo, adcUrlActual, fin }: {
  destino: CambioDestino; setDestino: (d: CambioDestino) => void
  nuevaFecha: string; setNuevaFecha: (v: string) => void
  adcNombre: string; setAdcNombre: (v: string) => void
  adcArchivo: File | null; setAdcArchivo: (f: File | null) => void
  adcUrlActual?: string | null; fin: string
}) {
  const opciones: [CambioDestino, string][] = [
    ['reprogramada', `Tiene fecha nueva dentro del trimestre (hasta el ${ddmm(fin)})`],
    ['pendiente_adc', 'No cabe: esperar el correo del ADC (sigue atrasada en el KPI)'],
    ['justificada_adc', 'Ya tengo el correo del ADC: sale del KPI'],
  ]
  return (
    <div className="space-y-2 rounded-lg border p-2">
      <p className="text-xs font-semibold">¿Qué pasa con la tarea desplazada?</p>
      {opciones.map(([k, l]) => (
        <label key={k} className="flex cursor-pointer items-start gap-2 text-sm">
          <input type="radio" name="destino" className="mt-1" checked={destino === k} onChange={() => setDestino(k)} />
          <span>{l}</span>
        </label>
      ))}
      {destino === 'reprogramada' && (
        <div className="pl-6"><Input type="date" className="h-8 w-44" value={nuevaFecha} max={fin} onChange={(e) => setNuevaFecha(e.target.value)} /></div>
      )}
      {destino === 'justificada_adc' && (
        <div className="grid gap-2 pl-6 sm:grid-cols-2">
          <div><label className="text-xs font-medium">Nombre del ADC Enex-ESM *</label>
            <Input value={adcNombre} onChange={(e) => setAdcNombre(e.target.value)} /></div>
          <div><label className="text-xs font-medium">Correo de autorización *</label>
            <input type="file" accept=".pdf,.eml,.msg,image/*" className="block w-full text-xs"
                   onChange={(e) => setAdcArchivo(e.target.files?.[0] ?? null)} />
            {!adcArchivo && adcUrlActual && <a href={adcUrlActual} target="_blank" rel="noreferrer" className="text-[11px] text-blue-600 underline">correo ya adjunto</a>}
          </div>
        </div>
      )}
      <p className="text-[11px] text-gray-500">
        KPI Mantenimiento V8, consideración 1: la no ejecución de una preventiva «puede estar justificada bajo correo y autorizada por ADC Enex-ESM».
      </p>
    </div>
  )
}

export function CambioTareaModal({ row, rows, instalaciones, onClose, onDone }: {
  row: EnexPanelRow
  /** Programaciones de la ventana (para adelantar una ya planificada y desplazar varias del mismo día). */
  rows: EnexPanelRow[]
  instalaciones: EnexInstalacion[]
  onClose: () => void; onDone: () => void
}) {
  const toast = useToast()
  const dia = row.fecha_programada?.slice(0, 10) ?? ''
  const fin = finTrimestreDe(row)
  const libre = (r: EnexPanelRow) => !r.ejecucion_id && !r.cambio_tarea_id
  // Las otras tareas del mismo lugar y día (EESS = mantención + calibración): se desplazan juntas.
  const mismoDia = useMemo(() => rows.filter((r) => r.programacion_id !== row.programacion_id && r.instalacion_id === row.instalacion_id
    && r.fecha_programada?.slice(0, 10) === dia && libre(r)), [rows, row, dia])
  const [tambien, setTambien] = useState<Set<string>>(() => new Set(mismoDia.map((r) => r.programacion_id)))

  const [solicitante, setSolicitante] = useState('')
  const [motivo, setMotivo] = useState(row.por_reprogramar_motivo ?? '')
  const [evidencia, setEvidencia] = useState<File | null>(null)
  const [reemplazos, setReemplazos] = useState<{ key: string; txt: string; r: CambioReemplazo }[]>([])
  const [patente, setPatente] = useState('')
  const [instSel, setInstSel] = useState('')
  const [tipoSel, setTipoSel] = useState<TipoServicio>('calibracion')
  const [adelantar, setAdelantar] = useState('')
  const [destino, setDestino] = useState<CambioDestino>('pendiente_adc')
  const [nuevaFecha, setNuevaFecha] = useState('')
  const [adcNombre, setAdcNombre] = useState('')
  const [adcArchivo, setAdcArchivo] = useState<File | null>(null)
  const [busy, setBusy] = useState(false)

  const deFaena = instalaciones.filter((i) => i.faena_id === row.faena_id && i.activo && !i.es_comodin)
  const camiones = deFaena.filter((i) => i.tipo === 'camion')
  const otras = deFaena.filter((i) => i.tipo !== 'camion')
  const adelantables = rows.filter((r) => r.faena_id === row.faena_id && libre(r) && r.programacion_id !== row.programacion_id
    && !tambien.has(r.programacion_id) && (r.fecha_programada?.slice(0, 10) ?? '') > dia && (r.fecha_programada?.slice(0, 10) ?? '') <= fin)
    .sort((a, b) => (a.fecha_programada ?? '').localeCompare(b.fecha_programada ?? ''))

  const agregar = (key: string, txt: string, r: CambioReemplazo) =>
    setReemplazos((p) => (p.some((x) => x.key === key) ? p : [...p, { key, txt, r }]))
  const quitar = (key: string) => setReemplazos((p) => p.filter((x) => x.key !== key))

  async function guardar() {
    if (!solicitante.trim()) { toast.error('Indica quién de ESM pidió el cambio'); return }
    if (!motivo.trim()) { toast.error('Describe el motivo'); return }
    if (destino === 'reprogramada' && !nuevaFecha) { toast.error('Elige la nueva fecha'); return }
    if (destino === 'reprogramada' && nuevaFecha > fin) { toast.error(`Fuera del trimestre: a más tardar el ${fin}`); return }
    if (destino === 'justificada_adc' && (!adcNombre.trim() || !adcArchivo)) { toast.error('Falta el nombre del ADC y su correo'); return }
    setBusy(true)
    try {
      const evidenciaUrl = evidencia ? await subirArchivoCambio(evidencia) : null
      const adcUrl = adcArchivo ? await subirArchivoCambio(adcArchivo) : null
      const ids = [row.programacion_id, ...Array.from(tambien)]
      for (let k = 0; k < ids.length; k++) {
        const id = ids[k]
        await registrarCambioTarea({
          programacionId: id, solicitante: solicitante.trim(), motivo: motivo.trim(), destino,
          nuevaFecha: destino === 'reprogramada' ? nuevaFecha : null, evidenciaUrl,
          adcNombre: adcNombre.trim() || null, adcUrl,
          // Lo que se hizo en su lugar queda ligado a la primera tarea desplazada.
          reemplazos: k === 0 ? reemplazos.map((x) => x.r) : [],
        })
      }
      toast.success(`Cambio de tarea registrado (${ids.length} desplazada${ids.length > 1 ? 's' : ''}, ${reemplazos.length} en su lugar)`)
      onDone()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  return (
    <Modal open onClose={onClose} title={`Cambio de tarea (ESM) · ${nombreProg(row)}`}>
      <div className="space-y-3">
        <div className="rounded-lg border border-violet-200 bg-violet-50/60 px-3 py-2 text-xs text-violet-900">
          ESM sacó <b>{nombreProg(row)} · {SERV[row.tipo_servicio]}</b> del <b>{ddmm(dia)}</b> y pidió otra tarea.
          No es una reprogramación: lo que se hizo en su lugar cuenta como tarea del contrato.
        </div>
        {mismoDia.length > 0 && (
          <div className="space-y-1">
            <p className="text-xs font-semibold">También se desplazó ese día</p>
            {mismoDia.map((r) => (
              <label key={r.programacion_id} className="flex items-center gap-2 text-sm">
                <input type="checkbox" checked={tambien.has(r.programacion_id)}
                       onChange={(e) => setTambien((p) => { const n = new Set(p); if (e.target.checked) n.add(r.programacion_id); else n.delete(r.programacion_id); return n })} />
                {nombreProg(r)} · {SERV[r.tipo_servicio]}
              </label>
            ))}
          </div>
        )}
        <div className="grid gap-2 sm:grid-cols-2">
          <div><label className="text-xs font-medium">Quién de ESM lo pidió *</label>
            <Input value={solicitante} onChange={(e) => setSolicitante(e.target.value)} placeholder="Nombre y cargo" /></div>
          <div><label className="text-xs font-medium">Respaldo del pedido (WhatsApp, correo)</label>
            <input type="file" accept=".pdf,.eml,.msg,image/*" className="block w-full text-xs" onChange={(e) => setEvidencia(e.target.files?.[0] ?? null)} /></div>
        </div>
        <div><label className="text-xs font-medium">Motivo *</label>
          <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={2} className="w-full rounded border px-2 py-1.5 text-sm"
                    placeholder="ej. ESM priorizó la calibración de camiones" /></div>

        <div className="space-y-2 rounded-lg border p-2">
          <p className="text-xs font-semibold">¿Qué se hizo en su lugar el {ddmm(dia)}?</p>
          {camiones.length > 0 && (
            <div className="flex flex-wrap gap-1">
              {camiones.map((c) => (
                <button key={c.id} type="button" onClick={() => agregar(`i:${c.id}:calibracion`, `Calibración camión ${c.patente ?? c.nombre}`, { instalacion_id: c.id, tipo_servicio: 'calibracion' })}
                        className="flex items-center gap-1 rounded border px-2 py-0.5 text-xs hover:bg-blue-50"><Truck className="h-3 w-3" />{c.patente ?? c.nombre}</button>
              ))}
            </div>
          )}
          <div className="flex flex-wrap items-center gap-2">
            <Input className="h-8 w-32" value={patente} onChange={(e) => setPatente(e.target.value.toUpperCase())} placeholder="Otra patente" />
            <Button size="sm" variant="outline" disabled={patente.trim().length < 4}
                    onClick={() => { const p = patente.trim(); agregar(`p:${p}`, `Calibración camión ${p} (nuevo)`, { patente: p }); setPatente('') }}>+ Camión</Button>
          </div>
          {otras.length > 0 && (
            <div className="flex flex-wrap items-center gap-2">
              <select value={instSel} onChange={(e) => setInstSel(e.target.value)} className="h-8 rounded border px-2 text-sm">
                <option value="">Otra instalación…</option>
                {otras.map((i) => <option key={i.id} value={i.id}>{i.nombre}</option>)}
              </select>
              <select value={tipoSel} onChange={(e) => setTipoSel(e.target.value as TipoServicio)} className="h-8 rounded border px-2 text-sm">
                <option value="calibracion">Calibración</option><option value="mantencion">Mantención</option>
              </select>
              <Button size="sm" variant="outline" disabled={!instSel}
                      onClick={() => { const i = otras.find((x) => x.id === instSel)!; agregar(`i:${i.id}:${tipoSel}`, `${SERV[tipoSel]} ${i.nombre}`, { instalacion_id: i.id, tipo_servicio: tipoSel }); setInstSel('') }}>+ Agregar</Button>
            </div>
          )}
          {adelantables.length > 0 && (
            <div className="flex flex-wrap items-center gap-2">
              <select value={adelantar} onChange={(e) => setAdelantar(e.target.value)} className="h-8 max-w-full rounded border px-2 text-sm">
                <option value="">Adelantar una tarea ya planificada…</option>
                {adelantables.map((r) => <option key={r.programacion_id} value={r.programacion_id}>{ddmm(r.fecha_programada)} · {nombreProg(r)} · {SERV[r.tipo_servicio]}</option>)}
              </select>
              <Button size="sm" variant="outline" disabled={!adelantar}
                      onClick={() => { const r = adelantables.find((x) => x.programacion_id === adelantar)!; agregar(`a:${r.programacion_id}`, `Adelantada: ${nombreProg(r)} · ${SERV[r.tipo_servicio]} (era el ${ddmm(r.fecha_programada)})`, { programacion_id: r.programacion_id }); setAdelantar('') }}>+ Adelantar</Button>
            </div>
          )}
          {reemplazos.length === 0 ? <p className="text-[11px] text-gray-400">Nada agregado todavía.</p> : (
            <ul className="space-y-0.5">
              {reemplazos.map((x) => (
                <li key={x.key} className="flex items-center justify-between rounded bg-blue-50 px-2 py-0.5 text-xs">
                  {x.txt}
                  <button onClick={() => quitar(x.key)} aria-label="Quitar"><X className="h-3.5 w-3.5 text-gray-500" /></button>
                </li>
              ))}
            </ul>
          )}
          <p className="text-[11px] text-gray-500">Si el teléfono ya creó ese servicio para ese día, se enlaza: no se duplica.</p>
        </div>

        <DestinoCampos destino={destino} setDestino={setDestino} nuevaFecha={nuevaFecha} setNuevaFecha={setNuevaFecha}
                       adcNombre={adcNombre} setAdcNombre={setAdcNombre} adcArchivo={adcArchivo} setAdcArchivo={setAdcArchivo} fin={fin} />
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button disabled={busy} onClick={guardar}>
          {busy ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : <Replace className="mr-1 h-4 w-4" />} Registrar cambio
        </Button>
      </ModalFooter>
    </Modal>
  )
}

/** Un cambio ya registrado: llegó el correo del ADC, sí cupo una fecha, o se anula. */
export function GestionarCambioModal({ row, onClose, onDone }: { row: EnexPanelRow; onClose: () => void; onDone: () => void }) {
  const toast = useToast()
  const qc = useQueryClient()
  const fin = finTrimestreDe(row)
  const [destino, setDestino] = useState<CambioDestino>(row.cambio_destino ?? 'pendiente_adc')
  const [nuevaFecha, setNuevaFecha] = useState(row.cambio_nueva_fecha ?? '')
  const [adcNombre, setAdcNombre] = useState(row.cambio_adc_nombre ?? '')
  const [adcArchivo, setAdcArchivo] = useState<File | null>(null)
  const [busy, setBusy] = useState(false)
  const [confirmarAnular, setConfirmarAnular] = useState(false)

  async function guardar() {
    if (destino === 'reprogramada' && (!nuevaFecha || nuevaFecha > fin)) { toast.error(`Elige una fecha hasta el ${fin}`); return }
    if (destino === 'justificada_adc' && (!adcNombre.trim() || (!adcArchivo && !row.cambio_adc_url))) { toast.error('Falta el nombre del ADC y su correo'); return }
    setBusy(true)
    try {
      const adcUrl = adcArchivo ? await subirArchivoCambio(adcArchivo) : null
      await cambiarDestinoCambio({ cambioId: row.cambio_tarea_id!, destino, nuevaFecha: destino === 'reprogramada' ? nuevaFecha : null, adcNombre: adcNombre.trim() || null, adcUrl })
      toast.success('Cambio actualizado'); onDone()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }
  async function anular() {
    setBusy(true)
    try {
      const r = await anularCambioTarea(row.cambio_tarea_id!)
      toast.success(`Cambio anulado${r.reemplazos_borrados ? ` · ${r.reemplazos_borrados} reemplazo(s) quitados del plan` : ''}`)
      qc.invalidateQueries({ queryKey: ['enex-inst'] })
      onDone()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  return (
    <Modal open onClose={onClose} title={`Cambio de tarea · ${nombreProg(row)}`}>
      <div className="space-y-3">
        <div className="rounded-lg border border-violet-200 bg-violet-50/60 px-3 py-2 text-xs text-violet-900">
          <b>{SERV[row.tipo_servicio]}</b> del <b>{ddmm(row.cambio_fecha)}</b> · pedido por <b>{row.cambio_solicitante}</b>: {row.cambio_motivo}
          {row.cambio_evidencia_url && <> · <a href={row.cambio_evidencia_url} target="_blank" rel="noreferrer" className="underline">respaldo</a></>}
          <div className="mt-1">Hoy: <b>{row.cambio_destino ? CAMBIO_DESTINO_TXT[row.cambio_destino] : '—'}</b>
            {row.cambio_destino === 'reprogramada' && row.cambio_nueva_fecha && <> al {ddmm(row.cambio_nueva_fecha)}</>}
            {row.cambio_adc_url && <> · <a href={row.cambio_adc_url} target="_blank" rel="noreferrer" className="underline">correo del ADC</a></>}
          </div>
        </div>
        {row.ejecucion_id ? <p className="text-sm text-gray-600">La tarea ya se ejecutó: el cambio queda solo como registro.</p> : (
          <DestinoCampos destino={destino} setDestino={setDestino} nuevaFecha={nuevaFecha} setNuevaFecha={setNuevaFecha}
                         adcNombre={adcNombre} setAdcNombre={setAdcNombre} adcArchivo={adcArchivo} setAdcArchivo={setAdcArchivo}
                         adcUrlActual={row.cambio_adc_url} fin={fin} />
        )}
      </div>
      <ModalFooter>
        {confirmarAnular ? (
          <div className="mr-auto flex items-center gap-2 text-xs">
            <span className="text-red-700">¿Anular? La tarea vuelve a su día y se quitan los reemplazos sin ejecución.</span>
            <Button size="sm" variant="outline" className="text-red-700" disabled={busy} onClick={anular}>Sí, anular</Button>
            <Button size="sm" variant="outline" onClick={() => setConfirmarAnular(false)}>No</Button>
          </div>
        ) : (
          <Button variant="outline" className="mr-auto text-red-600" disabled={busy} onClick={() => setConfirmarAnular(true)}>
            <Ban className="mr-1 h-4 w-4" /> Anular cambio
          </Button>
        )}
        <Button variant="outline" onClick={onClose}>Cerrar</Button>
        {!row.ejecucion_id && (
          <Button disabled={busy} onClick={guardar}>
            {busy ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : <Paperclip className="mr-1 h-4 w-4" />} Guardar
          </Button>
        )}
      </ModalFooter>
    </Modal>
  )
}
