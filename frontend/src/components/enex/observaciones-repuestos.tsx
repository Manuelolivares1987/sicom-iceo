'use client'

// [MIG649] Observaciones del servicio y pedido de repuestos desde terreno.
// Igual en calibración y mantención, de combustible y de lubricantes. Todo
// queda en el teléfono (borrador) y viaja con la ejecución; la jefatura lo
// recibe por correo.

import { Package, Plus, Trash2, AlertTriangle } from 'lucide-react'
import { newId, type EnexRepuesto } from '@/lib/offline/enex-db'

const UNIDADES = ['un', 'juego', 'kit', 'lt', 'm', 'kg']

export function ObservacionesYRepuestos({ obs, setObs, repuestos, setRepuestos }: {
  obs: string
  setObs: (v: string) => void
  repuestos: EnexRepuesto[]
  setRepuestos: (r: EnexRepuesto[]) => void
}) {
  const cambiar = (id: string, patch: Partial<EnexRepuesto>) =>
    setRepuestos(repuestos.map((r) => (r.id === id ? { ...r, ...patch } : r)))
  const agregar = () =>
    setRepuestos([...repuestos, { id: newId(), descripcion: '', cantidad: 1, unidad: 'un', urgente: false, nota: null }])
  const quitar = (id: string) => setRepuestos(repuestos.filter((r) => r.id !== id))

  return (
    <div className="space-y-3 rounded-xl border border-gray-200 bg-white p-3">
      <div>
        <label className="text-xs font-bold text-gray-800">Observaciones del servicio</label>
        <textarea value={obs} onChange={(e) => setObs(e.target.value)} rows={3}
                  placeholder="Hallazgos, condición de la instalación, trabajos pendientes, lo que tenga que saber la jefatura…"
                  className="mt-1 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm" />
      </div>

      <div className="border-t pt-2.5">
        <div className="flex items-center gap-1.5">
          <Package className="h-4 w-4 text-blue-700" />
          <p className="flex-1 text-xs font-bold text-gray-800">
            Pedido de repuestos{repuestos.length > 0 && ` (${repuestos.length})`}
          </p>
        </div>
        <p className="mt-0.5 text-[10px] text-gray-500">
          Lo que hace falta para dejar la instalación operativa. Llega por correo a la jefatura al guardar.
        </p>

        <div className="mt-2 space-y-2">
          {repuestos.map((r, i) => (
            <div key={r.id} className={`rounded-lg border p-2 ${r.urgente ? 'border-red-300 bg-red-50' : 'border-gray-200 bg-gray-50'}`}>
              <div className="flex items-start gap-1.5">
                <span className="mt-2 w-4 text-[11px] font-bold text-gray-400">{i + 1}</span>
                <input value={r.descripcion} onChange={(e) => cambiar(r.id, { descripcion: e.target.value })}
                       placeholder="Repuesto (ej. manguera 3/4&quot;, sello pistola, filtro)"
                       className="flex-1 rounded-md border border-gray-200 bg-white px-2 py-1.5 text-sm" />
                <button type="button" onClick={() => quitar(r.id)} aria-label="Quitar repuesto"
                        className="mt-1 rounded p-1 text-gray-400 hover:text-red-600">
                  <Trash2 className="h-4 w-4" />
                </button>
              </div>
              <div className="mt-1.5 flex items-center gap-1.5 pl-5">
                <input type="number" inputMode="decimal" min={0} step="any" value={Number.isFinite(r.cantidad) ? r.cantidad : ''}
                       onChange={(e) => cambiar(r.id, { cantidad: e.target.value === '' ? NaN : Number(e.target.value) })}
                       aria-label="Cantidad"
                       className="w-16 rounded-md border border-gray-200 bg-white px-2 py-1.5 text-sm" />
                <select value={r.unidad} onChange={(e) => cambiar(r.id, { unidad: e.target.value })} aria-label="Unidad"
                        className="rounded-md border border-gray-200 bg-white px-1.5 py-1.5 text-sm">
                  {UNIDADES.map((u) => <option key={u} value={u}>{u}</option>)}
                </select>
                <button type="button" onClick={() => cambiar(r.id, { urgente: !r.urgente })}
                        className={`ml-auto inline-flex items-center gap-1 rounded-md border px-2 py-1.5 text-[11px] font-semibold
                          ${r.urgente ? 'border-red-400 bg-red-600 text-white' : 'border-gray-300 bg-white text-gray-600'}`}>
                  <AlertTriangle className="h-3 w-3" /> Urgente
                </button>
              </div>
              <input value={r.nota ?? ''} onChange={(e) => cambiar(r.id, { nota: e.target.value || null })}
                     placeholder="Detalle: marca, medida, código, para qué equipo (opcional)"
                     className="mt-1.5 ml-5 w-[calc(100%-1.25rem)] rounded-md border border-gray-200 bg-white px-2 py-1.5 text-xs" />
            </div>
          ))}
        </div>

        <button type="button" onClick={agregar}
                className="mt-2 flex w-full items-center justify-center gap-1.5 rounded-lg border-2 border-dashed border-blue-300 py-2 text-xs font-semibold text-blue-700">
          <Plus className="h-4 w-4" /> Agregar repuesto
        </button>
      </div>
    </div>
  )
}
