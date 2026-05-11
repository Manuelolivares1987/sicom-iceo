'use client'

import { Trash2 } from 'lucide-react'
import { Input } from '@/components/ui/input'
import { formatCLP, cn } from '@/lib/utils'

export interface OCItemFormValue {
  producto_id: string | null
  descripcion: string
  unidad: string
  cantidad_comprada: number | ''
  precio_unitario_clp: number | ''
  observacion: string
}

interface Props {
  idx: number
  value: OCItemFormValue
  onChange: (v: OCItemFormValue) => void
  onRemove: () => void
  productos: Array<{ id: string; codigo: string; nombre: string; unidad_medida: string; categoria: string }>
  errors?: Partial<Record<keyof OCItemFormValue, string>>
  removable: boolean
}

export function OCItemForm({ idx, value, onChange, onRemove, productos, errors, removable }: Props) {
  const cantidad = typeof value.cantidad_comprada === 'number' ? value.cantidad_comprada : 0
  const precio   = typeof value.precio_unitario_clp === 'number' ? value.precio_unitario_clp : 0
  const subtotal = cantidad * precio

  const onProductoChange = (id: string) => {
    if (!id) {
      onChange({ ...value, producto_id: null })
      return
    }
    const p = productos.find((pp) => pp.id === id)
    if (!p) {
      onChange({ ...value, producto_id: id })
      return
    }
    onChange({
      ...value,
      producto_id: id,
      descripcion: value.descripcion || p.nombre,
      unidad: value.unidad || p.unidad_medida,
    })
  }

  return (
    <div className="rounded-lg border border-gray-200 bg-white p-3 space-y-2">
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold text-gray-600">Item {idx + 1}</span>
        {removable && (
          <button
            type="button"
            onClick={onRemove}
            className="text-red-600 hover:bg-red-50 rounded p-1"
            aria-label="Eliminar item"
          >
            <Trash2 className="h-4 w-4" />
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
        <div>
          <label className="block text-xs font-medium text-gray-700 mb-1">
            Producto (opcional)
          </label>
          <select
            value={value.producto_id ?? ''}
            onChange={(e) => onProductoChange(e.target.value)}
            className="w-full rounded-md border border-gray-300 bg-white px-2 py-1.5 text-sm"
          >
            <option value="">— Sin producto (descripción libre) —</option>
            {productos.map((p) => (
              <option key={p.id} value={p.id}>
                {p.codigo} — {p.nombre}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="block text-xs font-medium text-gray-700 mb-1">
            Unidad
          </label>
          <Input
            value={value.unidad}
            onChange={(e) => onChange({ ...value, unidad: e.target.value })}
            placeholder="unidad / lt / kg / mt..."
          />
        </div>
      </div>

      <div>
        <label className="block text-xs font-medium text-gray-700 mb-1">
          Descripción {value.producto_id ? '(opcional)' : '*'}
        </label>
        <Input
          value={value.descripcion}
          onChange={(e) => onChange({ ...value, descripcion: e.target.value })}
          placeholder={value.producto_id ? 'Detalle adicional...' : 'Describe el ítem...'}
          className={cn(errors?.descripcion && 'border-red-500')}
        />
        {errors?.descripcion && (
          <p className="text-[11px] text-red-600 mt-0.5">{errors.descripcion}</p>
        )}
      </div>

      <div className="grid grid-cols-3 gap-2">
        <div>
          <label className="block text-xs font-medium text-gray-700 mb-1">
            Cantidad *
          </label>
          <Input
            type="number"
            step="0.01"
            min="0.01"
            value={value.cantidad_comprada}
            onChange={(e) => onChange({
              ...value,
              cantidad_comprada: e.target.value === '' ? '' : Number(e.target.value),
            })}
            className={cn(errors?.cantidad_comprada && 'border-red-500')}
          />
          {errors?.cantidad_comprada && (
            <p className="text-[11px] text-red-600 mt-0.5">{errors.cantidad_comprada}</p>
          )}
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-700 mb-1">
            Precio CLP *
          </label>
          <Input
            type="number"
            step="1"
            min="0"
            value={value.precio_unitario_clp}
            onChange={(e) => onChange({
              ...value,
              precio_unitario_clp: e.target.value === '' ? '' : Number(e.target.value),
            })}
            className={cn(errors?.precio_unitario_clp && 'border-red-500')}
          />
          {errors?.precio_unitario_clp && (
            <p className="text-[11px] text-red-600 mt-0.5">{errors.precio_unitario_clp}</p>
          )}
        </div>
        <div>
          <label className="block text-xs font-medium text-gray-700 mb-1">
            Subtotal
          </label>
          <div className="h-[42px] flex items-center justify-end px-3 rounded-md bg-gray-50 border border-gray-200 text-sm tabular-nums font-semibold">
            {formatCLP(subtotal)}
          </div>
        </div>
      </div>

      <div>
        <label className="block text-xs font-medium text-gray-700 mb-1">
          Observación (opcional)
        </label>
        <Input
          value={value.observacion}
          onChange={(e) => onChange({ ...value, observacion: e.target.value })}
          placeholder="Notas del item"
        />
      </div>
    </div>
  )
}
