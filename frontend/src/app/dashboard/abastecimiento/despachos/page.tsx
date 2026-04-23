'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import {
  Send, AlertTriangle, CheckCircle2, Package, Truck, ExternalLink,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  useMaterialesPendientesDespacho,
  useDespacharMaterialOT,
  useCancelarMaterialOT,
} from '@/hooks/use-ot-materiales'
import { cn } from '@/lib/utils'

export default function DespachosPage() {
  useRequireAuth()

  const { data: pendientes = [], isLoading } = useMaterialesPendientesDespacho()
  const despMut = useDespacharMaterialOT()
  const canMut = useCancelarMaterialOT()
  const [filtroFaena, setFiltroFaena] = useState('')
  const [busqueda, setBusqueda] = useState('')
  const [errorMsg, setErrorMsg] = useState<string | null>(null)

  const faenas = useMemo(() => {
    const set = new Set<string>()
    for (const p of pendientes) if (p.faena) set.add(p.faena)
    return Array.from(set).sort()
  }, [pendientes])

  const filtrados = useMemo(() => {
    const q = busqueda.trim().toLowerCase()
    return pendientes.filter((p) => {
      if (filtroFaena && p.faena !== filtroFaena) return false
      if (q) {
        const text = `${p.producto_codigo} ${p.producto_nombre} ${p.ot_folio} ${p.activo_patente ?? ''}`.toLowerCase()
        if (!text.includes(q)) return false
      }
      return true
    })
  }, [pendientes, filtroFaena, busqueda])

  const faltantes = filtrados.filter((p) => p.estado === 'faltante')
  const suficientes = filtrados.filter((p) => p.estado === 'suficiente')

  const handleDespachar = async (materialId: string, otId: string) => {
    setErrorMsg(null)
    try {
      await despMut.mutateAsync({ materialId, otId })
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Error al despachar')
    }
  }

  const handleCancelar = async (materialId: string, otId: string) => {
    if (!confirm('¿Cancelar este requerimiento de material?')) return
    setErrorMsg(null)
    try {
      await canMut.mutateAsync({ materialId, otId })
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Error')
    }
  }

  return (
    <div className="space-y-6">
      <div className="rounded-2xl bg-gradient-to-r from-orange-600 to-red-600 p-6 text-white shadow-lg">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <Truck className="h-6 w-6" />
          Despachos de Bodega
        </h1>
        <p className="text-sm text-white/80 mt-1">
          Materiales planificados por las OTs que requieren despacho.
        </p>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-3 gap-3">
        <KpiBox label="Con Stock (listos)" value={suficientes.length} color="text-green-700" />
        <KpiBox label="Con Faltante" value={faltantes.length} color="text-red-700" />
        <KpiBox label="Total pendientes" value={filtrados.length} color="text-gray-700" />
      </div>

      {errorMsg && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{errorMsg}</div>
      )}

      {/* Filtros */}
      <Card>
        <CardContent className="p-3">
          <div className="flex flex-col sm:flex-row gap-2">
            <Input
              placeholder="Buscar por folio, producto, patente…"
              value={busqueda}
              onChange={(e) => setBusqueda(e.target.value)}
              className="flex-1"
            />
            <select
              className="h-10 rounded border border-gray-300 px-2 text-sm"
              value={filtroFaena}
              onChange={(e) => setFiltroFaena(e.target.value)}
            >
              <option value="">Todas las faenas</option>
              {faenas.map((f) => (
                <option key={f} value={f}>{f}</option>
              ))}
            </select>
          </div>
        </CardContent>
      </Card>

      {/* ── Faltantes (atención prioritaria) ── */}
      {faltantes.length > 0 && (
        <Card className="border-red-200">
          <CardHeader className="pb-2">
            <CardTitle className="text-base text-red-700 flex items-center gap-2">
              <AlertTriangle className="h-5 w-5" />
              Con Faltante de Stock ({faltantes.length})
            </CardTitle>
          </CardHeader>
          <CardContent className="overflow-x-auto">
            <p className="text-xs text-red-700 mb-2">
              Estos ítems no tienen stock suficiente en la bodega asignada. Haz una orden de compra o reabastece.
            </p>
            <TablaPendientes
              rows={faltantes}
              onDespachar={handleDespachar}
              onCancelar={handleCancelar}
              disabled={despMut.isPending}
            />
          </CardContent>
        </Card>
      )}

      {/* ── Listos para despachar ── */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base flex items-center justify-between text-gray-700">
            <span className="flex items-center gap-2">
              <Package className="h-5 w-5" />
              Con Stock Disponible ({suficientes.length})
            </span>
          </CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          {isLoading ? (
            <div className="flex justify-center py-6"><Spinner className="h-8 w-8" /></div>
          ) : suficientes.length === 0 ? (
            <p className="text-sm text-gray-400 py-4 text-center">Sin materiales listos para despachar.</p>
          ) : (
            <TablaPendientes
              rows={suficientes}
              onDespachar={handleDespachar}
              onCancelar={handleCancelar}
              disabled={despMut.isPending}
            />
          )}
        </CardContent>
      </Card>
    </div>
  )
}

function KpiBox({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div className="rounded-lg border bg-white p-3 text-center">
      <div className="text-xs uppercase text-gray-500">{label}</div>
      <div className={cn('text-2xl font-bold', color)}>{value}</div>
    </div>
  )
}

function TablaPendientes({
  rows, onDespachar, onCancelar, disabled,
}: {
  rows: any[]
  onDespachar: (materialId: string, otId: string) => void
  onCancelar: (materialId: string, otId: string) => void
  disabled: boolean
}) {
  return (
    <table className="w-full text-xs">
      <thead>
        <tr className="border-b bg-gray-50 text-left text-gray-500 uppercase">
          <th className="px-2 py-2">OT</th>
          <th className="px-2 py-2">Equipo</th>
          <th className="px-2 py-2">Producto</th>
          <th className="px-2 py-2 text-right">Requerido</th>
          <th className="px-2 py-2 text-right">Stock</th>
          <th className="px-2 py-2">Bodega</th>
          <th className="px-2 py-2">Faena</th>
          <th className="px-2 py-2">Prioridad</th>
          <th className="px-2 py-2 text-right">Acción</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((r) => {
          const faltante = r.estado === 'faltante'
          const stock = Number(r.stock_actual ?? 0)
          return (
            <tr key={r.material_id} className={cn('border-b', faltante && 'bg-red-50/40')}>
              <td className="px-2 py-1.5">
                <Link href={`/dashboard/ordenes-trabajo/${r.ot_id}`} className="font-mono font-semibold text-blue-600 hover:underline">
                  {r.ot_folio} <ExternalLink className="inline h-3 w-3" />
                </Link>
              </td>
              <td className="px-2 py-1.5 font-mono">{r.activo_patente ?? r.activo_codigo ?? '—'}</td>
              <td className="px-2 py-1.5">
                <div className="text-gray-500 text-[11px]">{r.producto_codigo}</div>
                <div>{r.producto_nombre}</div>
              </td>
              <td className="px-2 py-1.5 text-right font-semibold">
                {r.cantidad_plan} {r.unidad_medida}
              </td>
              <td className={cn('px-2 py-1.5 text-right font-semibold', faltante ? 'text-red-700' : 'text-gray-700')}>
                {stock} {r.unidad_medida}
              </td>
              <td className="px-2 py-1.5">{r.bodega ?? '—'}</td>
              <td className="px-2 py-1.5 text-gray-500">{r.faena ?? '—'}</td>
              <td className="px-2 py-1.5">
                <PrioridadBadge prioridad={r.ot_prioridad} />
              </td>
              <td className="px-2 py-1.5">
                <div className="flex items-center justify-end gap-1">
                  {!faltante && (
                    <Button
                      size="sm"
                      variant="primary"
                      onClick={() => onDespachar(r.material_id, r.ot_id)}
                      disabled={disabled}
                    >
                      <Send className="h-3 w-3" />
                      Despachar
                    </Button>
                  )}
                  <button
                    className="text-xs text-gray-400 hover:text-red-600 px-1"
                    onClick={() => onCancelar(r.material_id, r.ot_id)}
                    title="Cancelar"
                  >
                    ✕
                  </button>
                </div>
              </td>
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}

function PrioridadBadge({ prioridad }: { prioridad: string }) {
  const map: Record<string, string> = {
    emergencia: 'bg-red-200 text-red-800',
    urgente: 'bg-orange-200 text-orange-800',
    alta: 'bg-amber-100 text-amber-800',
    normal: 'bg-blue-100 text-blue-800',
    baja: 'bg-gray-100 text-gray-700',
  }
  return (
    <span className={cn('rounded-full px-2 py-0.5 text-[10px] font-semibold', map[prioridad] ?? 'bg-gray-100')}>
      {prioridad}
    </span>
  )
}
