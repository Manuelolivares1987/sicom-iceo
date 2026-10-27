'use client'

// Registro de reprogramación ENEX (MIG234), compartido por «Control & KPI» y la
// planificación diaria. Guarda el registro, mueve la programación a la nueva
// fecha y genera el PDF para ESM.

import { useState } from 'react'
import { Loader2, FileSpreadsheet } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useToast } from '@/contexts/toast-context'
import { reprogramar, subirFirmaEnex, REPROG_RESPONSABLE, REPROG_CAUSA, type EnexPanelRow } from '@/lib/services/enex'
import { inicioTrimestreContractual, ventanaTrimestre, ultimoDiaMes } from '@/lib/enex-avance'
import { generarReprogramacionPdf } from '@/components/enex/pdf-reprogramacion-enex'

// Registro de reprogramación (formato ESM/PILLADO) → guarda + genera PDF para ENEX.
export function ReprogramacionModal({ row, nombre, limitarTrimestre = false, fechaInicial = '', onClose, onDone }: {
  row: EnexPanelRow; nombre: string
  /** Desde la planificación: la nueva fecha es obligatoria y no puede salir del trimestre contractual. */
  limitarTrimestre?: boolean; fechaInicial?: string
  onClose: () => void; onDone: () => void
}) {
  const toast = useToast()
  const [busy, setBusy] = useState(false)
  const [horaIngreso, setHoraIngreso] = useState('')
  const [supervisorEsm, setSupervisorEsm] = useState('')
  const [tecnicos, setTecnicos] = useState(row.ejecutor ?? '')
  const [responsable, setResponsable] = useState('mandante')
  const [causa, setCausa] = useState('prioridad_operacional')
  const [descripcion, setDescripcion] = useState('')
  const [nuevaFecha, setNuevaFecha] = useState(fechaInicial)
  // Una reprogramación vale para el KPI si cae dentro del mismo trimestre contractual.
  const original = row.fecha_programada?.slice(0, 10) ?? ultimoDiaMes(row.periodo_anio, row.periodo_mes)
  const tri = inicioTrimestreContractual(original, row.faena_trimestre_ancla ?? 2)
  const finTrimestre = ventanaTrimestre(tri.anio, tri.mes).hasta
  const [nuevaHora, setNuevaHora] = useState('')
  const [firmaTec, setFirmaTec] = useState('')
  const [firmaEsm, setFirmaEsm] = useState('')

  async function guardar() {
    if (!descripcion.trim()) { toast.error('Describe el motivo de la reprogramación'); return }
    if (limitarTrimestre && !nuevaFecha) { toast.error('Elige la nueva fecha'); return }
    if (limitarTrimestre && nuevaFecha > finTrimestre) { toast.error(`Fuera del trimestre: la reprogramación debe caer a más tardar el ${finTrimestre}`); return }
    setBusy(true)
    try {
      const firmaTecUrl = firmaTec ? await subirFirmaEnex(firmaTec) : null
      const firmaEsmUrl = firmaEsm ? await subirFirmaEnex(firmaEsm) : null
      const r = await reprogramar({
        programacionId: row.programacion_id, horaIngreso: horaIngreso || null,
        supervisorEsm: supervisorEsm || null, tecnicosPillado: tecnicos || null,
        responsable, causa, descripcion: descripcion.trim(),
        nuevaFecha: nuevaFecha || null, nuevaHora: nuevaHora || null,
        firmaTecnicoUrl: firmaTecUrl, firmaEsmUrl: firmaEsmUrl, moverFecha: true,
      })
      toast.success('Reprogramación registrada — generando PDF para ENEX…')
      try {
        await generarReprogramacionPdf(r.reprogramacion_id)
        toast.success('Registro PDF generado y descargado')
      } catch { toast.error('Registrado, pero el PDF no se generó — reintenta desde Recobros y reprogramación') }
      onDone()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  return (
    <Modal open onClose={onClose} title={`Reprogramar · ${nombre}`}>
      <div className="space-y-3">
        <div className="rounded-lg border border-indigo-200 bg-indigo-50/60 px-3 py-2 text-xs text-indigo-800">
          Genera el <b>Registro de Reprogramación de Actividades</b> (formato ESM/PILLADO) para entregar a ENEX.
          {row.fecha_programada && <> Fecha original: <b>{row.fecha_programada.slice(0, 10)}</b>.</>}
          {limitarTrimestre && <> Debe quedar dentro del trimestre: a más tardar el <b>{finTrimestre}</b>.</>}
        </div>
        <div className="grid grid-cols-2 gap-2">
          <div><label className="text-xs font-medium">Nueva fecha</label><Input type="date" value={nuevaFecha} max={limitarTrimestre ? finTrimestre : undefined} onChange={(e) => setNuevaFecha(e.target.value)} /></div>
          <div><label className="text-xs font-medium">Nueva hora</label><Input value={nuevaHora} onChange={(e) => setNuevaHora(e.target.value)} placeholder="ej 14:00" /></div>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <div>
            <label className="text-xs font-medium">Responsable</label>
            <select value={responsable} onChange={(e) => setResponsable(e.target.value)} className="w-full rounded border px-2 py-1.5 text-sm">
              {Object.entries(REPROG_RESPONSABLE).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </div>
          <div>
            <label className="text-xs font-medium">Causa</label>
            <select value={causa} onChange={(e) => setCausa(e.target.value)} className="w-full rounded border px-2 py-1.5 text-sm">
              {Object.entries(REPROG_CAUSA).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </div>
        </div>
        <div>
          <label className="text-xs font-medium">Descripción del motivo *</label>
          <textarea value={descripcion} onChange={(e) => setDescripcion(e.target.value)} rows={3}
                    className="w-full rounded border px-2 py-1.5 text-sm" placeholder="Detalle de por qué se reprograma" />
        </div>
        <div className="grid grid-cols-2 gap-2">
          <div><label className="text-xs font-medium">Supervisor / Jefe Turno ESM</label><Input value={supervisorEsm} onChange={(e) => setSupervisorEsm(e.target.value)} /></div>
          <div><label className="text-xs font-medium">Hora ingreso a faena</label><Input value={horaIngreso} onChange={(e) => setHoraIngreso(e.target.value)} placeholder="ej 08:30" /></div>
        </div>
        <div><label className="text-xs font-medium">Técnicos PILLADO</label><Input value={tecnicos} onChange={(e) => setTecnicos(e.target.value)} /></div>
        <div className="grid grid-cols-2 gap-3">
          <div className="rounded-lg border border-gray-200 p-2">
            <label className="text-xs font-semibold">Firma Técnico PILLADO</label>
            <SignaturePad label="Firmar" onCapture={setFirmaTec} />
          </div>
          <div className="rounded-lg border border-gray-200 p-2">
            <label className="text-xs font-semibold">Firma Responsable ESM</label>
            <SignaturePad label="Firmar" onCapture={setFirmaEsm} />
          </div>
        </div>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button disabled={busy} onClick={guardar}>
          {busy ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : <FileSpreadsheet className="h-4 w-4 mr-1" />}
          Registrar y generar PDF
        </Button>
      </ModalFooter>
    </Modal>
  )
}
