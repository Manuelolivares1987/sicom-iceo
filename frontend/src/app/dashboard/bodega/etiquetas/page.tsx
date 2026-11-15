'use client'

// ============================================================================
// Etiquetas para el lector (MIG692)
// ----------------------------------------------------------------------------
// Code128 con el código del producto, que es lo que el lector teclea. Hoja A4
// de 3 columnas para imprimir en papel adhesivo y pegar en el estante o el
// envase. Se eligen los productos de la bodega (o se busca uno del maestro).
// ============================================================================

import { Suspense, useMemo, useState } from 'react'
import { useSearchParams } from 'next/navigation'
import { useQuery } from '@tanstack/react-query'
import { Printer, Search } from 'lucide-react'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { barras, esCodificable } from '@/lib/barcode/code128'
import { buscarProducto, getPanelBodega, type ProductoLector } from '@/lib/services/bodega-faena'

type Etiqueta = { producto_id: string; codigo: string; nombre: string; copias: number }

function CodigoBarras({ texto }: { texto: string }) {
  if (!esCodificable(texto)) return <p className="text-[9px] text-red-700">Código con caracteres no imprimibles</p>
  const b = barras(texto)
  return (
    <svg viewBox={`0 0 ${b.total} 40`} preserveAspectRatio="none" className="h-12 w-full" role="img" aria-label={`Código ${texto}`}>
      <rect width={b.total} height={40} fill="#fff" />
      {b.map((r, i) => <rect key={i} x={r.x} y={0} width={r.w} height={40} fill="#000" />)}
    </svg>
  )
}

function EtiquetasInner() {
  useRequireAuth()
  const bodegaId = useSearchParams()?.get('bodega') ?? ''
  const { data: panel } = useQuery({ queryKey: ['bodega-panel', bodegaId], queryFn: () => getPanelBodega(bodegaId), enabled: !!bodegaId })
  const [sel, setSel] = useState<Record<string, Etiqueta>>({})
  const [texto, setTexto] = useState('')
  const [encontrados, setEncontrados] = useState<ProductoLector[]>([])

  const lista = useMemo(() => Object.values(sel).flatMap((e) => Array.from({ length: e.copias }, () => e)), [sel])
  const alternar = (p: { producto_id: string; codigo: string; nombre: string }) =>
    setSel((s) => {
      const n = { ...s }
      if (n[p.producto_id]) delete n[p.producto_id]
      else n[p.producto_id] = { ...p, copias: 1 }
      return n
    })

  return (
    <div className="mx-auto max-w-6xl space-y-4 p-4 md:p-6">
      <div className="space-y-3 print:hidden">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Etiquetas para el lector</h1>
            <p className="text-sm text-gray-500">{panel?.bodega.nombre ?? 'Bodega'} · elija productos y copias, luego imprima en papel adhesivo (A4, 3 columnas)</p>
          </div>
          <button onClick={() => window.print()} disabled={lista.length === 0}
                  className="flex items-center gap-2 rounded-lg bg-emerald-800 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-900 disabled:opacity-40">
            <Printer className="h-4 w-4" /> Imprimir {lista.length} etiqueta{lista.length === 1 ? '' : 's'}
          </button>
        </div>
        <div className="flex flex-wrap gap-2 text-sm">
          <button onClick={() => setSel(Object.fromEntries((panel?.stock ?? []).map((p) => [p.producto_id, { producto_id: p.producto_id, codigo: p.codigo, nombre: p.nombre, copias: 1 }])))}
                  className="rounded-lg border bg-white px-3 py-1.5 hover:bg-gray-50">Todos los de la bodega ({panel?.stock.length ?? 0})</button>
          <button onClick={() => setSel({})} className="rounded-lg border bg-white px-3 py-1.5 hover:bg-gray-50">Ninguno</button>
          <form className="flex items-center gap-2 rounded-lg border bg-white px-3" onSubmit={async (e) => {
            e.preventDefault(); if (bodegaId && texto.trim()) setEncontrados(await buscarProducto(bodegaId, texto.trim()))
          }}>
            <Search className="h-4 w-4 text-gray-400" />
            <input value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="Buscar en el maestro" className="py-1.5 outline-none" />
          </form>
        </div>
        {encontrados.length > 0 && (
          <div className="flex flex-wrap gap-2">
            {encontrados.map((p) => (
              <button key={p.producto_id} onClick={() => alternar(p)}
                      className={`rounded-full border px-3 py-1 text-xs ${sel[p.producto_id] ? 'border-emerald-700 bg-emerald-50' : 'bg-white'}`}>
                {p.nombre} · {p.codigo}
              </button>
            ))}
          </div>
        )}
        <div className="max-h-72 overflow-y-auto rounded-xl border bg-white">
          <table className="w-full text-sm">
            <tbody className="divide-y">
              {(panel?.stock ?? []).map((p) => (
                <tr key={p.producto_id}>
                  <td className="w-8 px-3 py-1.5"><input type="checkbox" checked={!!sel[p.producto_id]} onChange={() => alternar(p)} /></td>
                  <td className="px-3 py-1.5">{p.nombre}<span className="ml-2 text-xs text-gray-400">{p.codigo}</span></td>
                  <td className="px-3 py-1.5 text-right">
                    {sel[p.producto_id] && (
                      <input type="number" min={1} max={50} value={sel[p.producto_id].copias}
                             onChange={(e) => setSel((s) => ({ ...s, [p.producto_id]: { ...s[p.producto_id], copias: Math.max(1, Math.min(50, Number(e.target.value) || 1)) } }))}
                             className="w-16 rounded border px-2 py-0.5 text-right" aria-label="Copias" />
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-2 print:gap-0">
        {lista.map((e, i) => (
          <div key={`${e.producto_id}-${i}`} className="break-inside-avoid rounded border border-gray-300 p-2 print:rounded-none print:border-dashed">
            <p className="line-clamp-2 h-7 text-[10px] font-semibold leading-tight text-black">{e.nombre}</p>
            <CodigoBarras texto={e.codigo} />
            <p className="text-center font-mono text-[11px] tracking-wider text-black">{e.codigo}</p>
          </div>
        ))}
      </div>
    </div>
  )
}

export default function EtiquetasPage() {
  return <Suspense fallback={null}><EtiquetasInner /></Suspense>
}
