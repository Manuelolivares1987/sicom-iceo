'use client'

// ============================================================================
// Las líneas de un vale (MIG375)
// ----------------------------------------------------------------------------
// Salió del pedido manual del taller (MIG371) cuando oficina necesitó emitir su
// propio vale. Es el mismo problema en los dos lados: elegir qué se pide, en
// qué cantidad, y qué pasa cuando lo que hace falta no está en el catálogo.
//
// EL CATÁLOGO ANTES QUE EL TEXTO LIBRE
// Un ítem con producto del catálogo descuenta stock solo; uno escrito a mano lo
// tiene que amarrar bodega antes de despachar. Se permite escribirlo —quien
// pide no siempre sabe el código— pero la pantalla lo dice al tiro, no al final.
// ============================================================================

import { useRef, useState } from 'react'
import { Loader2, Plus, Trash2, Package, AlertTriangle } from 'lucide-react'
import { buscarProductos } from '@/lib/services/ot-materiales'
import type { ItemValeManual } from '@/lib/services/bodega-tickets'
import { cn } from '@/lib/utils'

type ProductoLite = { id: string; codigo: string | null; nombre: string; unidad_medida: string | null }

export type LineaVale = ItemValeManual & { key: string; nombreVisible: string }

/** Lo que se le manda al RPC: la línea sin lo que existe sólo para la pantalla. */
export function aItemsRpc(lineas: LineaVale[]): ItemValeManual[] {
  return lineas.map(({ producto_id, descripcion, cantidad, unidad, comentario }) =>
    ({ producto_id, descripcion, cantidad, unidad, comentario }))
}

/** Las líneas ya puestas, con el aviso de las que bodega tendrá que amarrar. */
export function ListaLineasVale({
  lineas, onQuitar,
}: { lineas: LineaVale[]; onQuitar: (key: string) => void }) {
  const sinCatalogo = lineas.filter((l) => !l.producto_id).length
  if (lineas.length === 0) return null

  return (
    <>
      <div className="mt-1.5 space-y-1">
        {lineas.map((l) => (
          <div key={l.key}
               className={cn('flex items-center gap-2 rounded border px-2.5 py-1.5',
                             l.producto_id ? 'border-gray-200' : 'border-amber-300 bg-amber-50')}>
            <Package className={cn('h-3.5 w-3.5 shrink-0',
                                   l.producto_id ? 'text-gray-400' : 'text-amber-600')} />
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm text-gray-800">{l.nombreVisible}</p>
              {!l.producto_id && (
                <p className="text-[10px] text-amber-800">
                  Escrito a mano: bodega tiene que amarrarlo a un producto antes de despachar
                </p>
              )}
            </div>
            <span className="shrink-0 text-sm font-semibold tabular-nums text-gray-700">
              {l.cantidad}{l.unidad ? ` ${l.unidad}` : ''}
            </span>
            <button type="button" onClick={() => onQuitar(l.key)}
                    aria-label="Quitar" className="shrink-0 text-gray-400 hover:text-red-600">
              <Trash2 className="h-3.5 w-3.5" />
            </button>
          </div>
        ))}
      </div>

      {sinCatalogo > 0 && (
        <p className="mt-1.5 flex items-start gap-1.5 text-[11px] leading-snug text-amber-800">
          <AlertTriangle className="mt-px h-3.5 w-3.5 shrink-0" />
          {sinCatalogo === 1 ? '1 ítem' : `${sinCatalogo} ítems`} sin producto del catálogo. El vale
          se emite igual, pero bodega no podrá despacharlos hasta decir cuál es —y hasta entonces el
          stock no baja.
        </p>
      )}
    </>
  )
}

/** El buscador de una línea: primero el catálogo, y si no está, a mano. */
export function AgregarLineaVale({ onAdd }: { onAdd: (l: LineaVale) => void }) {
  const [q, setQ] = useState('')
  const [resultados, setResultados] = useState<ProductoLite[]>([])
  const [prod, setProd] = useState<ProductoLite | null>(null)
  const [cant, setCant] = useState('')
  const [buscando, setBuscando] = useState(false)
  // Al elegir el producto, lo siguiente que se hace SIEMPRE es escribir cuánto.
  // Sin esto hay que ir a buscar con el dedo una caja de 80 píxeles.
  const cantRef = useRef<HTMLInputElement>(null)

  const buscar = async (texto: string) => {
    setQ(texto); setProd(null)
    if (texto.trim().length < 2) { setResultados([]); return }
    setBuscando(true)
    try {
      const { data } = await buscarProductos(texto, 8)
      setResultados((data ?? []) as ProductoLite[])
    } catch { setResultados([]) } finally { setBuscando(false) }
  }

  const agregar = () => {
    const n = Number(String(cant).replace(',', '.'))
    if (!Number.isFinite(n) || n <= 0) return
    if (!prod && q.trim().length < 3) return
    onAdd({
      key: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
      producto_id: prod?.id ?? null,
      descripcion: prod ? null : q.trim(),
      cantidad: n,
      unidad: prod?.unidad_medida ?? null,
      comentario: null,
      nombreVisible: prod ? `${prod.codigo ? `${prod.codigo} · ` : ''}${prod.nombre}` : q.trim(),
    })
    setQ(''); setProd(null); setCant(''); setResultados([])
  }

  // Enter agrega la línea: quien carga diez ítems no quiere diez clicks al «+».
  const alTeclear = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') { e.preventDefault(); agregar() }
  }

  return (
    <div className="mt-1 rounded-lg border border-dashed border-gray-300 p-2">
      <div className="flex gap-1.5">
        <div className="relative min-w-0 flex-1">
          <input value={prod ? `${prod.codigo ? `${prod.codigo} · ` : ''}${prod.nombre}` : q}
                 onChange={(e) => buscar(e.target.value)}
                 onKeyDown={alTeclear}
                 placeholder="Buscar en el catálogo… o escribirlo si no está"
                 className="w-full rounded border px-2 py-1.5 text-sm" />
          {buscando && (
            <Loader2 className="absolute right-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 animate-spin text-gray-400" />
          )}
        </div>
        <input ref={cantRef} value={cant} onKeyDown={alTeclear}
               onChange={(e) => setCant(e.target.value.replace(/[^\d.,]/g, ''))}
               inputMode="decimal" placeholder="Cant."
               className="w-20 rounded border px-2 py-1.5 text-right text-sm tabular-nums" />
        <button type="button" onClick={agregar}
                disabled={!Number(String(cant).replace(',', '.')) || (!prod && q.trim().length < 3)}
                className="shrink-0 rounded bg-orange-600 px-2.5 text-[11px] font-semibold text-white disabled:opacity-50">
          <Plus className="h-3.5 w-3.5" />
        </button>
      </div>

      {resultados.length > 0 && !prod && (
        <div className="mt-1 max-h-36 space-y-0.5 overflow-y-auto">
          {resultados.map((r) => (
            <button key={r.id} type="button"
                    onClick={() => {
                      setProd(r); setResultados([])
                      // El foco va a la cantidad, que es el paso siguiente.
                      setTimeout(() => cantRef.current?.focus(), 0)
                    }}
                    className="flex w-full items-center gap-2 rounded px-2 py-1 text-left text-xs hover:bg-gray-50">
              <span className="font-mono text-[10px] text-gray-500">{r.codigo}</span>
              <span className="min-w-0 flex-1 truncate">{r.nombre}</span>
              {r.unidad_medida && <span className="shrink-0 text-[10px] text-gray-400">{r.unidad_medida}</span>}
            </button>
          ))}
        </div>
      )}

      {!prod && q.trim().length >= 3 && resultados.length === 0 && !buscando && (
        <p className="mt-1 text-[10px] text-amber-800">
          No está en el catálogo: se va a pedir como «{q.trim()}» y bodega lo amarra al despachar.
        </p>
      )}
    </div>
  )
}
