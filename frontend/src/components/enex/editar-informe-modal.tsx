'use client'

// Editar el informe ENEX desde la web (MIG586).
//
// La observación general del servicio y el N° OT del mandante se escribían
// solo en el teléfono, en terreno. Aquí se corrigen antes de mandar el
// informe a firmar. Con la firma de ESM puesta ya no se cambian: lo que ESM
// firmó es lo que ESM vio (misma regla que los requerimientos, MIG287).
//
// Lo que se registró actividad por actividad (resultados, fotos) se edita en
// la pantalla de terreno: el enlace lleva directo al servicio.

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { Lock, ClipboardList } from 'lucide-react'
import { Modal } from '@/components/ui/modal'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useToast } from '@/contexts/toast-context'
import { editarInformeEnex } from '@/lib/services/enex'

function fmtFecha(iso?: string | null): string {
  if (!iso) return ''
  const [y, m, d] = iso.slice(0, 10).split('-')
  return `${d}-${m}-${y}`
}

export function EditarInformeModal({
  open, onClose, ejecucionId, programacionId, instalacion, fecha,
  observacion, otNumero, firmadoPorMandante, onGuardado,
}: {
  open: boolean
  onClose: () => void
  ejecucionId: string
  programacionId: string
  instalacion: string
  fecha: string | null
  observacion: string | null
  otNumero: string | null
  firmadoPorMandante: boolean
  onGuardado: () => void
}) {
  const toast = useToast()
  const [obs, setObs] = useState(observacion ?? '')
  const [ot, setOt] = useState(otNumero ?? '')
  const [guardando, setGuardando] = useState(false)

  useEffect(() => {
    if (!open) return
    setObs(observacion ?? '')
    setOt(otNumero ?? '')
  }, [open, observacion, otNumero])

  const sinCambios = obs.trim() === (observacion ?? '').trim() && ot.trim() === (otNumero ?? '').trim()

  async function guardar() {
    setGuardando(true)
    try {
      const r = await editarInformeEnex({
        ejecucionId, observacion: obs.trim() || null, otNumero: ot.trim() || null,
      })
      toast.success(r.cambio ? 'Informe actualizado. Rehaz el PDF para que salga con el cambio.' : 'Sin cambios')
      onGuardado()
      onClose()
    } catch (e) {
      toast.error((e as Error).message)
    } finally {
      setGuardando(false)
    }
  }

  return (
    <Modal open={open} onClose={onClose} className="sm:max-w-2xl"
           title="Editar informe"
           description={`${instalacion}${fecha ? ` · ${fmtFecha(fecha)}` : ''}`}>
      {firmadoPorMandante && (
        <div className="mb-3 flex items-start gap-2 rounded-lg border border-gray-300 bg-gray-50 p-2.5 text-xs text-gray-700">
          <Lock className="mt-0.5 h-4 w-4 flex-shrink-0" />
          <span>ESM ya firmó la recepción conforme de este informe. No se puede cambiar lo que firmó.</span>
        </div>
      )}
      <div className="space-y-3">
        <div>
          <label className="text-xs font-medium text-gray-700">N° OT (mandante)</label>
          <Input value={ot} onChange={(e) => setOt(e.target.value)} disabled={firmadoPorMandante}
                 placeholder="N° de OT de ENEX / ESM" className="h-9" />
        </div>
        <div>
          <label className="text-xs font-medium text-gray-700">Observación general del servicio</label>
          <textarea value={obs} onChange={(e) => setObs(e.target.value)} disabled={firmadoPorMandante}
                    rows={7} placeholder="Lo que hay que contar del servicio en general. Sale impresa en el informe."
                    className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm disabled:bg-gray-50" />
          <p className="mt-1 text-[11px] text-gray-500">
            Se imprime en el bloque «Observación general del servicio» del PDF.
          </p>
        </div>
        {!firmadoPorMandante && (
          <Link href={`/m/enex/${programacionId}`} target="_blank"
                className="inline-flex items-center gap-1.5 text-xs font-medium text-blue-700 hover:underline">
            <ClipboardList className="h-3.5 w-3.5" />
            Corregir resultados, observaciones por actividad o fotos (pantalla de terreno)
          </Link>
        )}
      </div>
      <div className="mt-4 flex justify-end gap-2">
        <Button variant="outline" onClick={onClose}>Cerrar</Button>
        {!firmadoPorMandante && (
          <Button variant="primary" onClick={guardar} disabled={guardando || sinCambios}>
            {guardando ? 'Guardando…' : 'Guardar'}
          </Button>
        )}
      </div>
    </Modal>
  )
}
