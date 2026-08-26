'use client'

// ============================================================================
// La barra de «seleccionar y guardar en el historial». [MIG405]
// ----------------------------------------------------------------------------
// El mismo control en todas las pantallas: aparece sólo cuando hay algo
// seleccionado, dice cuántos son, pide el motivo y ofrece deshacer lo último
// que se guardó. Un solo componente para que el gesto se aprenda una vez.
// ============================================================================

import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Archive, Undo2, X, Loader2 } from 'lucide-react'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useToast } from '@/contexts/toast-context'
import {
  archivar, deshacerLote, getLotesArchivo,
  type EntidadArchivable,
} from '@/lib/services/archivo'

export function BarraArchivar({
  entidad, seleccion, onLimpiar, onListo, queKeys, nombreCosa = 'registro',
}: {
  entidad: EntidadArchivable
  seleccion: string[]
  onLimpiar: () => void
  onListo: () => void
  /** Claves de react-query a refrescar tras archivar o deshacer. */
  queKeys?: string[][]
  /** Cómo se llama lo que se archiva, para que el texto no diga «registros». */
  nombreCosa?: string
}) {
  const toast = useToast()
  const qc = useQueryClient()
  const [abierto, setAbierto] = useState(false)
  const [motivo, setMotivo] = useState('Prueba de agosto 2026')
  const [busy, setBusy] = useState(false)
  const [verHistorial, setVerHistorial] = useState(false)

  const { data: lotes = [], refetch: refetchLotes } = useQuery({
    queryKey: ['archivo-lotes', entidad],
    queryFn: () => getLotesArchivo(entidad),
    staleTime: 30_000,
  })
  const ultimoVigente = lotes.find((l) => l.vigente)

  const refrescar = () => {
    for (const k of queKeys ?? []) qc.invalidateQueries({ queryKey: k })
    void refetchLotes()
    onListo()
  }

  const guardar = async () => {
    setBusy(true)
    try {
      const r = await archivar(entidad, seleccion, motivo)
      if (!r.success) { toast.error(r.mensaje ?? 'No se guardó nada'); return }
      toast.success(`${r.archivados} ${nombreCosa}${r.archivados !== 1 ? 's' : ''} en el historial. Se puede deshacer.`)
      setAbierto(false); onLimpiar(); refrescar()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  const deshacer = async (loteId: string) => {
    setBusy(true)
    try {
      const r = await deshacerLote(loteId)
      toast.success(`${r.devueltos} ${nombreCosa}${r.devueltos !== 1 ? 's' : ''} de vuelta en la lista.`)
      refrescar()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }

  return (
    <>
      {/* La barra sólo existe cuando hay algo elegido: si no, no estorba. */}
      {seleccion.length > 0 && (
        <div className="sticky bottom-3 z-20 flex flex-wrap items-center gap-3 rounded-xl border border-gray-800 bg-gray-900 px-4 py-2.5 text-white shadow-lg">
          <span className="text-sm font-semibold">
            {seleccion.length} {nombreCosa}{seleccion.length !== 1 ? 's' : ''} seleccionado{seleccion.length !== 1 ? 's' : ''}
          </span>
          <Button onClick={() => setAbierto(true)} className="h-8 bg-white text-gray-900 hover:bg-gray-100">
            <Archive className="mr-1 h-3.5 w-3.5" /> Guardar en el historial
          </Button>
          <button type="button" onClick={onLimpiar}
                  className="ml-auto flex items-center gap-1 text-xs text-gray-300 hover:text-white">
            <X className="h-3.5 w-3.5" /> Quitar la selección
          </button>
        </div>
      )}

      {/* Deshacer lo último, sin tener que abrir nada. */}
      {seleccion.length === 0 && ultimoVigente && (
        <div className="flex flex-wrap items-center gap-2 rounded-lg border border-gray-200 bg-gray-50 px-3 py-1.5 text-[12px] text-gray-600">
          <Archive className="h-3.5 w-3.5 text-gray-400" />
          <span>
            <b>{ultimoVigente.n_registros}</b> en el historial · «{ultimoVigente.motivo}» ·{' '}
            {new Date(ultimoVigente.archivado_at).toLocaleDateString('es-CL')} por {ultimoVigente.archivado_por_nombre}
          </span>
          <button type="button" disabled={busy} onClick={() => deshacer(ultimoVigente.id)}
                  className="flex items-center gap-1 font-semibold text-blue-600 underline disabled:opacity-50">
            <Undo2 className="h-3 w-3" /> Deshacer
          </button>
          {lotes.length > 1 && (
            <button type="button" onClick={() => setVerHistorial(true)}
                    className="ml-auto text-gray-500 underline">Ver todo el historial</button>
          )}
        </div>
      )}

      {abierto && (
        <Modal open onClose={() => setAbierto(false)} title="Guardar en el historial">
          <div className="space-y-3">
            <p className="text-sm text-gray-600">
              Se van a guardar <b>{seleccion.length} {nombreCosa}{seleccion.length !== 1 ? 's' : ''}</b>.
              No se borra nada: salen de esta lista y quedan con quién los guardó y por qué.
              Se puede deshacer completo.
            </p>
            <label className="block text-xs font-medium text-gray-700">
              ¿Por qué se guardan?
              <Input value={motivo} onChange={(e) => setMotivo(e.target.value)}
                     placeholder="Prueba de agosto 2026" className="mt-1" />
            </label>
            <p className="text-[11px] text-gray-400">
              Dentro de seis meses, «por qué desapareció esto de la lista» tiene que tener respuesta.
            </p>
          </div>
          <ModalFooter>
            <Button variant="outline" onClick={() => setAbierto(false)}>Cancelar</Button>
            <Button disabled={busy || motivo.trim().length < 4} onClick={guardar}>
              {busy ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : <Archive className="mr-1 h-4 w-4" />}
              Guardar {seleccion.length}
            </Button>
          </ModalFooter>
        </Modal>
      )}

      {verHistorial && (
        <Modal open onClose={() => setVerHistorial(false)} title="Historial de lo guardado">
          <div className="max-h-96 space-y-2 overflow-y-auto">
            {lotes.map((l) => (
              <div key={l.id} className={`rounded-lg border p-2 text-sm ${l.vigente ? 'bg-white' : 'bg-gray-50 opacity-60'}`}>
                <div className="flex items-center gap-2">
                  <span className="font-semibold">{l.n_registros}</span>
                  <span className="flex-1 text-gray-700">«{l.motivo}»</span>
                  {l.vigente ? (
                    <button type="button" disabled={busy} onClick={() => deshacer(l.id)}
                            className="text-xs font-semibold text-blue-600 underline disabled:opacity-50">Deshacer</button>
                  ) : (
                    <span className="text-[11px] text-gray-400">devuelto</span>
                  )}
                </div>
                <div className="text-[11px] text-gray-500">
                  {new Date(l.archivado_at).toLocaleString('es-CL')} · {l.archivado_por_nombre}
                  {l.revertido_at && ` · devuelto por ${l.revertido_por_nombre}`}
                </div>
              </div>
            ))}
            {lotes.length === 0 && (
              <p className="py-6 text-center text-sm text-gray-400">Todavía no se ha guardado nada en el historial.</p>
            )}
          </div>
          <ModalFooter>
            <Button variant="outline" onClick={() => setVerHistorial(false)}>Cerrar</Button>
          </ModalFooter>
        </Modal>
      )}
    </>
  )
}
