'use client'

// Comentarios y requerimientos al mandante (MIG287).
//
// El informe cuenta lo que se hizo. Acá se escribe lo que HAY QUE HACER y que
// no se resuelve en terreno: comprar un repuesto, autorizar un trabajo mayor,
// coordinar una detención. Lo que se escriba sale impreso en el mismo documento
// que ESM / ENEX firma, así que al firmar el mandante lo da por informado.
//
// Por eso se puede escribir SOLO mientras el informe esté pendiente de esa
// firma: cambiar un documento ya firmado sería otra cosa.

import { useEffect, useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { AlertTriangle, Lock, MessageSquare, Pencil, Plus, Trash2 } from 'lucide-react'
import { Modal } from '@/components/ui/modal'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import {
  getRequerimientos, guardarRequerimiento, eliminarRequerimiento, getEjecucionItems,
  REQ_PRIORIDAD_LABEL,
  type EnexRequerimiento, type EnexReqTipo, type EnexReqPrioridad,
} from '@/lib/services/enex'

type ItemPauta = {
  pauta_item_id: string; item_codigo: string | null; descripcion: string
  resultado: string | null; bloque_orden: number | null; orden: number | null
}

const PRIO_CLS: Record<EnexReqPrioridad, string> = {
  alta: 'bg-red-100 text-red-800 border-red-200',
  media: 'bg-amber-100 text-amber-800 border-amber-200',
  baja: 'bg-gray-100 text-gray-600 border-gray-200',
}

function fmtFecha(iso?: string | null): string {
  if (!iso) return ''
  const [y, m, d] = iso.slice(0, 10).split('-')
  return `${d}-${m}-${y}`
}

const VACIO = {
  id: null as string | null,
  tipo: 'requerimiento' as EnexReqTipo,
  prioridad: 'media' as EnexReqPrioridad,
  titulo: '',
  descripcion: '',
  pautaItemId: '',
  plazo: '',
}

export function RequerimientosModal({
  open, onClose, ejecucionId, instalacion, fecha, firmadoPorMandante, onCambio,
}: {
  open: boolean
  onClose: () => void
  ejecucionId: string
  instalacion: string
  fecha?: string | null
  /** Con la recepción conforme ya firmada, el documento queda cerrado. */
  firmadoPorMandante: boolean
  onCambio?: () => void
}) {
  const toast = useToast()
  const [form, setForm] = useState({ ...VACIO })
  const [editando, setEditando] = useState(false)
  const [guardando, setGuardando] = useState(false)

  const { data: reqs = [], isLoading, refetch } = useQuery({
    queryKey: ['enex-requerimientos', ejecucionId],
    queryFn: () => getRequerimientos(ejecucionId),
    enabled: open && !!ejecucionId,
    staleTime: 0,
  })

  // Los ítems de la pauta que se ejecutaron: sirven para colgar el requerimiento
  // del hallazgo que lo originó ("esto sale del ítem 3.2 que quedó NO OK").
  const { data: itemsRaw = [] } = useQuery({
    queryKey: ['enex-ejec-items', ejecucionId],
    queryFn: () => getEjecucionItems(ejecucionId),
    enabled: open && !!ejecucionId,
    staleTime: 60_000,
  })

  const items = useMemo(() => (itemsRaw as ItemPauta[])
    .filter((i) => !(i.item_codigo ?? '').startsWith('DS.'))
    .sort((a, b) => (a.bloque_orden ?? 99) - (b.bloque_orden ?? 99) || (a.orden ?? 999) - (b.orden ?? 999)),
  [itemsRaw])

  useEffect(() => { if (!open) { setForm({ ...VACIO }); setEditando(false) } }, [open])

  function editar(r: EnexRequerimiento) {
    setForm({
      id: r.id, tipo: r.tipo, prioridad: r.prioridad, titulo: r.titulo ?? '',
      descripcion: r.descripcion, pautaItemId: r.pauta_item_id ?? '', plazo: r.plazo?.slice(0, 10) ?? '',
    })
    setEditando(true)
  }

  async function guardar() {
    if (!form.descripcion.trim()) { toast.error('Escribe qué se necesita'); return }
    setGuardando(true)
    try {
      await guardarRequerimiento({
        id: form.id, ejecucionId, tipo: form.tipo, prioridad: form.prioridad,
        titulo: form.titulo.trim() || null, descripcion: form.descripcion.trim(),
        pautaItemId: form.pautaItemId || null, plazo: form.plazo || null,
      })
      toast.success(form.id ? 'Actualizado' : 'Agregado al informe')
      setForm({ ...VACIO }); setEditando(false)
      await refetch(); onCambio?.()
    } catch (e) { toast.error((e as Error).message) } finally { setGuardando(false) }
  }

  async function borrar(r: EnexRequerimiento) {
    try {
      await eliminarRequerimiento(r.id)
      toast.success('Eliminado')
      await refetch(); onCambio?.()
    } catch (e) { toast.error((e as Error).message) }
  }

  const pedidos = reqs.filter((r) => r.tipo === 'requerimiento').length

  return (
    <Modal open={open} onClose={onClose} className="sm:max-w-2xl"
           title="Comentarios y requerimientos"
           description={`${instalacion}${fecha ? ` · ${fmtFecha(fecha)}` : ''} — salen impresos en el informe que firma ESM`}>
      {firmadoPorMandante ? (
        <div className="mb-4 flex items-start gap-2 rounded-lg border border-gray-200 bg-gray-50 p-3">
          <Lock className="mt-0.5 h-4 w-4 shrink-0 text-gray-500" />
          <p className="text-xs text-gray-600">
            ESM / ENEX ya recibió este servicio conforme. El informe quedó cerrado: lo que se
            firmó no se cambia. Si apareció algo nuevo, va en el informe del próximo servicio.
          </p>
        </div>
      ) : (
        <div className="mb-4 rounded-lg border border-blue-200 bg-blue-50 p-3">
          <p className="text-xs text-blue-900">
            Escribe acá lo que el mandante tiene que resolver y no se puede hacer en terreno
            (comprar, autorizar, coordinar). Al firmar el informe, ESM lo da por informado.
          </p>
        </div>
      )}

      {/* Lo que ya está escrito */}
      {isLoading ? (
        <div className="flex justify-center py-6"><Spinner /></div>
      ) : reqs.length === 0 ? (
        <p className="py-4 text-center text-sm text-gray-400">
          Este informe todavía no lleva comentarios ni requerimientos.
        </p>
      ) : (
        <ul className="space-y-2">
          {reqs.map((r, k) => (
            <li key={r.id} className="rounded-lg border border-gray-200 p-2.5">
              <div className="flex flex-wrap items-center gap-1.5">
                <span className="text-xs font-bold text-gray-400">{k + 1}</span>
                {r.tipo === 'requerimiento' ? (
                  <span className={`rounded border px-1.5 py-0.5 text-[10px] font-bold uppercase ${PRIO_CLS[r.prioridad]}`}>
                    Requerimiento · {REQ_PRIORIDAD_LABEL[r.prioridad]}
                  </span>
                ) : (
                  <span className="inline-flex items-center gap-1 rounded border border-gray-200 bg-gray-50 px-1.5 py-0.5 text-[10px] font-bold uppercase text-gray-600">
                    <MessageSquare className="h-3 w-3" /> Comentario
                  </span>
                )}
                {r.item_codigo && (
                  <span className="rounded bg-gray-100 px-1.5 py-0.5 font-mono text-[10px] text-gray-500">
                    Ítem {r.item_codigo}
                  </span>
                )}
                {r.plazo && (
                  <span className="text-[10px] text-gray-500">antes del {fmtFecha(r.plazo)}</span>
                )}
                {!firmadoPorMandante && (
                  <span className="ml-auto flex items-center gap-1">
                    <button onClick={() => editar(r)} title="Editar"
                            className="rounded p-1 text-gray-400 hover:text-blue-600">
                      <Pencil className="h-3.5 w-3.5" />
                    </button>
                    <button onClick={() => borrar(r)} title="Eliminar"
                            className="rounded p-1 text-gray-400 hover:text-red-600">
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  </span>
                )}
              </div>
              {r.titulo && <p className="mt-1 text-sm font-semibold text-gray-800">{r.titulo}</p>}
              <p className="mt-0.5 whitespace-pre-wrap text-xs text-gray-700">{r.descripcion}</p>
              {r.creado_por_nombre && (
                <p className="mt-1 text-[10px] text-gray-400">Escrito por {r.creado_por_nombre}</p>
              )}
            </li>
          ))}
        </ul>
      )}

      {pedidos > 0 && (
        <p className="mt-2 flex items-center gap-1.5 text-[11px] text-amber-800">
          <AlertTriangle className="h-3.5 w-3.5" />
          {pedidos} requerimiento(s) quedan a la espera de resolución del mandante.
        </p>
      )}

      {/* Alta / edición */}
      {!firmadoPorMandante && (
        <div className="mt-4 rounded-lg border border-gray-200 bg-gray-50/60 p-3">
          <p className="mb-2 text-xs font-bold text-gray-700">
            {editando ? 'Editando' : 'Agregar al informe'}
          </p>

          <div className="flex flex-wrap items-end gap-2">
            <div>
              <label className="text-[11px] font-medium text-gray-600">Tipo</label>
              <select value={form.tipo}
                      onChange={(e) => setForm({ ...form, tipo: e.target.value as EnexReqTipo })}
                      className="block h-9 rounded border px-2 text-sm">
                <option value="requerimiento">Requerimiento (pide una acción)</option>
                <option value="comentario">Comentario (informativo)</option>
              </select>
            </div>
            {form.tipo === 'requerimiento' && (
              <div>
                <label className="text-[11px] font-medium text-gray-600">Prioridad</label>
                <select value={form.prioridad}
                        onChange={(e) => setForm({ ...form, prioridad: e.target.value as EnexReqPrioridad })}
                        className="block h-9 rounded border px-2 text-sm">
                  <option value="alta">Alta</option>
                  <option value="media">Media</option>
                  <option value="baja">Baja</option>
                </select>
              </div>
            )}
            {form.tipo === 'requerimiento' && (
              <div>
                <label className="text-[11px] font-medium text-gray-600">Atender antes de</label>
                <Input type="date" value={form.plazo}
                       onChange={(e) => setForm({ ...form, plazo: e.target.value })} className="h-9" />
              </div>
            )}
          </div>

          <div className="mt-2">
            <label className="text-[11px] font-medium text-gray-600">Título (opcional)</label>
            <Input value={form.titulo} onChange={(e) => setForm({ ...form, titulo: e.target.value })}
                   placeholder="Ej: Cambio de manguera de descarga" className="h-9" />
          </div>

          <div className="mt-2">
            <label className="text-[11px] font-medium text-gray-600">
              Qué se necesita y por qué <span className="text-red-500">*</span>
            </label>
            <textarea value={form.descripcion} rows={3}
                      onChange={(e) => setForm({ ...form, descripcion: e.target.value })}
                      placeholder="Describe la necesidad como la va a leer el mandante: qué falta, qué riesgo tiene no hacerlo y qué se requiere de ESM."
                      className="w-full rounded border border-gray-300 px-2 py-1.5 text-sm" />
          </div>

          <div className="mt-2">
            <label className="text-[11px] font-medium text-gray-600">Hallazgo que lo originó (opcional)</label>
            <select value={form.pautaItemId}
                    onChange={(e) => setForm({ ...form, pautaItemId: e.target.value })}
                    className="block h-9 w-full rounded border px-2 text-sm">
              <option value="">Sin ítem asociado</option>
              {items.map((i) => (
                <option key={i.pauta_item_id} value={i.pauta_item_id}>
                  {i.item_codigo ? `${i.item_codigo} · ` : ''}{i.descripcion}
                  {i.resultado === 'no_ok' || i.resultado === 'no' ? '  (NO CONFORME)' : ''}
                </option>
              ))}
            </select>
          </div>

          <div className="mt-3 flex items-center gap-2">
            <Button size="sm" variant="primary" onClick={guardar} disabled={guardando || !form.descripcion.trim()}>
              {guardando ? <Spinner className="mr-1 h-3.5 w-3.5" /> : <Plus className="mr-1 h-3.5 w-3.5" />}
              {form.id ? 'Guardar cambios' : 'Agregar'}
            </Button>
            {editando && (
              <Button size="sm" variant="outline" onClick={() => { setForm({ ...VACIO }); setEditando(false) }}>
                Cancelar
              </Button>
            )}
            <span className="text-[11px] text-gray-500">
              Al guardar, el PDF se marca para regenerarse con esto adentro.
            </span>
          </div>
        </div>
      )}
    </Modal>
  )
}
