'use client'

import { useState } from 'react'
import { Package, Plus, AlertTriangle, CheckCircle2, XCircle, Send } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { cn } from '@/lib/utils'
import {
  useMaterialesPorOT,
  useAgregarMaterialOT,
  useDespacharMaterialOT,
  useCancelarMaterialOT,
  useBuscarProductos,
} from '@/hooks/use-ot-materiales'

interface Props {
  otId: string
  otFolio?: string
  otCerrada?: boolean
  // Si es bodeguero puede despachar; si no, solo planificar
  puedeDespachar?: boolean
}

export function PanelMateriales({ otId, otFolio, otCerrada, puedeDespachar }: Props) {
  const [query, setQuery] = useState('')
  const [productoSel, setProductoSel] = useState<{ id: string; codigo: string; nombre: string; unidad_medida: string } | null>(null)
  const [cantidad, setCantidad] = useState('')
  const [comentario, setComentario] = useState('')
  const [errorMsg, setErrorMsg] = useState<string | null>(null)

  const { data: materiales = [], isLoading } = useMaterialesPorOT(otId)
  const { data: productos = [] } = useBuscarProductos(query)
  const addMat = useAgregarMaterialOT()
  const despMat = useDespacharMaterialOT()
  const canMat = useCancelarMaterialOT()

  const handleAgregar = async () => {
    setErrorMsg(null)
    if (!productoSel || !cantidad || Number(cantidad) <= 0) {
      setErrorMsg('Selecciona un producto y una cantidad válida.')
      return
    }
    try {
      await addMat.mutateAsync({
        otId,
        productoId: productoSel.id,
        cantidad: Number(cantidad),
        comentario: comentario.trim() || undefined,
      })
      setProductoSel(null)
      setQuery('')
      setCantidad('')
      setComentario('')
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Error al agregar')
    }
  }

  const handleDespachar = async (materialId: string) => {
    setErrorMsg(null)
    try {
      await despMat.mutateAsync({ materialId, otId })
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Error al despachar')
    }
  }

  const handleCancelar = async (materialId: string) => {
    setErrorMsg(null)
    try {
      await canMat.mutateAsync({ materialId, otId })
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Error al cancelar')
    }
  }

  const faltantes = materiales.filter((m) => m.estado === 'faltante').length

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center justify-between text-gray-700">
          <span className="flex items-center gap-2">
            <Package className="h-5 w-5" />
            Materiales / Insumos Planeados
          </span>
          {faltantes > 0 && (
            <Badge className="bg-red-100 text-red-700">
              {faltantes} con faltante
            </Badge>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {isLoading && <div className="flex justify-center py-4"><Spinner className="h-6 w-6" /></div>}

        {errorMsg && (
          <div className="rounded-lg border border-red-200 bg-red-50 p-2 text-sm text-red-700">{errorMsg}</div>
        )}

        {/* Lista de materiales ya agregados */}
        {!isLoading && materiales.length > 0 && (
          <div className="divide-y rounded border border-gray-200">
            {materiales.map((m) => (
              <div
                key={m.id}
                className={cn(
                  'p-2 flex flex-col sm:flex-row sm:items-center gap-2',
                  m.estado === 'faltante' && 'bg-red-50/50',
                  m.estado === 'despachado' && 'bg-green-50/50',
                  m.estado === 'cancelado' && 'bg-gray-50 opacity-60',
                )}
              >
                <div className="flex-1 min-w-0">
                  <div className="font-mono text-xs text-gray-500">{m.producto?.codigo}</div>
                  <div className="text-sm font-medium truncate">{m.producto?.nombre}</div>
                  {m.comentario && (
                    <div className="text-[11px] text-gray-500 italic">"{m.comentario}"</div>
                  )}
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  <div className="text-sm text-right">
                    <div className="font-semibold">
                      {m.cantidad_plan} {m.producto?.unidad_medida}
                    </div>
                    {m.estado === 'despachado' && (
                      <div className="text-[10px] text-green-600">
                        Entregado: {m.cantidad_entregada}
                      </div>
                    )}
                  </div>
                  <EstadoBadge estado={m.estado} />
                  {!otCerrada && m.estado !== 'despachado' && m.estado !== 'cancelado' && (
                    <>
                      {puedeDespachar && m.estado === 'suficiente' && (
                        <Button
                          size="sm"
                          variant="primary"
                          onClick={() => handleDespachar(m.id)}
                          loading={despMat.isPending}
                        >
                          <Send className="h-3 w-3" />
                          Despachar
                        </Button>
                      )}
                      <button
                        className="text-xs text-gray-400 hover:text-red-600"
                        onClick={() => handleCancelar(m.id)}
                        title="Cancelar"
                      >
                        <XCircle className="h-4 w-4" />
                      </button>
                    </>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}

        {!isLoading && materiales.length === 0 && (
          <p className="text-sm text-gray-400 text-center py-2">Sin materiales planificados aún.</p>
        )}

        {/* Form de agregar material */}
        {!otCerrada && (
          <div className="rounded border border-dashed border-gray-300 p-2 space-y-2">
            <div className="text-xs font-medium text-gray-600">Agregar material</div>

            {/* Búsqueda de producto */}
            {!productoSel ? (
              <div className="relative">
                <Input
                  placeholder="Buscar producto (código o nombre)…"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                />
                {productos.length > 0 && query.length >= 2 && (
                  <div className="absolute z-10 mt-1 max-h-56 w-full overflow-y-auto rounded border border-gray-200 bg-white shadow-lg">
                    {productos.map((p: any) => (
                      <button
                        key={p.id}
                        className="w-full px-2 py-1.5 text-left text-xs hover:bg-blue-50"
                        onClick={() => {
                          setProductoSel(p)
                          setQuery('')
                        }}
                      >
                        <div className="font-mono text-gray-500">{p.codigo}</div>
                        <div>{p.nombre}</div>
                      </button>
                    ))}
                  </div>
                )}
              </div>
            ) : (
              <div className="flex items-center gap-2 rounded bg-blue-50 p-2 text-sm">
                <div className="flex-1">
                  <span className="font-mono text-xs text-gray-500">{productoSel.codigo}</span>
                  <span className="ml-2">{productoSel.nombre}</span>
                </div>
                <button onClick={() => setProductoSel(null)} className="text-xs text-gray-500 hover:text-red-600">
                  <XCircle className="h-4 w-4" />
                </button>
              </div>
            )}

            <div className="flex gap-2">
              <div className="flex-1">
                <label className="text-[10px] text-gray-500">Cantidad ({productoSel?.unidad_medida ?? '—'})</label>
                <Input type="number" step="0.001" value={cantidad} onChange={(e) => setCantidad(e.target.value)} />
              </div>
              <div className="flex-[2]">
                <label className="text-[10px] text-gray-500">Comentario (opcional)</label>
                <Input value={comentario} onChange={(e) => setComentario(e.target.value)} placeholder="p.ej. lado derecho" />
              </div>
            </div>

            <Button
              variant="primary"
              size="sm"
              onClick={handleAgregar}
              loading={addMat.isPending}
              disabled={!productoSel || !cantidad}
            >
              <Plus className="h-3 w-3" />
              Agregar a la OT
            </Button>
            <p className="text-[10px] text-gray-400">
              Al agregar, el sistema verifica stock y avisa a bodega automáticamente.
            </p>
          </div>
        )}
      </CardContent>
    </Card>
  )
}

function EstadoBadge({ estado }: { estado: string }) {
  const map: Record<string, { label: string; cls: string; icon: React.ReactNode }> = {
    suficiente: { label: 'Stock OK', cls: 'bg-blue-100 text-blue-700', icon: <CheckCircle2 className="h-3 w-3" /> },
    faltante: { label: 'Falta stock', cls: 'bg-red-100 text-red-700', icon: <AlertTriangle className="h-3 w-3" /> },
    despachado: { label: 'Despachado', cls: 'bg-green-100 text-green-700', icon: <CheckCircle2 className="h-3 w-3" /> },
    cancelado: { label: 'Cancelado', cls: 'bg-gray-100 text-gray-500', icon: <XCircle className="h-3 w-3" /> },
  }
  const m = map[estado] ?? { label: estado, cls: 'bg-gray-100', icon: null }
  return (
    <span className={cn('inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold', m.cls)}>
      {m.icon}
      {m.label}
    </span>
  )
}
