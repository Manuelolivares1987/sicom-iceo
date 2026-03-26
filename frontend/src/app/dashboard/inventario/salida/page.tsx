'use client'

import { useState, useCallback, useEffect } from 'react'
import { useAuth } from '@/contexts/auth-context'
import Link from 'next/link'
import {
  ArrowLeft,
  ScanLine,
  Search,
  AlertCircle,
  CheckCircle2,
  MapPin,
  Clock,
  ChevronDown,
  Package,
  XCircle,
  X,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { formatCLP, formatDateTime, cn } from '@/lib/utils'
import { useScanner } from '@/hooks/use-scanner'
import {
  useProductoByBarcode,
  useBodegas,
  useStockBodega,
  useRegistrarSalida,
} from '@/hooks/use-inventario'
import { useOrdenesTrabajo } from '@/hooks/use-ordenes-trabajo'

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------
export default function SalidaInventarioPage() {
  const { user } = useAuth()

  // OT search
  const [otSearch, setOtSearch] = useState('')
  const [selectedOT, setSelectedOT] = useState<any>(null)
  const [showOTResults, setShowOTResults] = useState(false)
  const [showOTWarning, setShowOTWarning] = useState(false)

  // Product search / scanner
  const [productoSearch, setProductoSearch] = useState('')
  const [selectedProducto, setSelectedProducto] = useState<any>(null)
  const [showProductoResults, setShowProductoResults] = useState(false)
  const [scannedBarcode, setScannedBarcode] = useState<string | undefined>(undefined)

  // Form
  const [cantidad, setCantidad] = useState('')
  const [bodegaId, setBodegaId] = useState('')
  const [observaciones, setObservaciones] = useState('')

  // Feedback
  const [submitError, setSubmitError] = useState<string | null>(null)
  const [submitSuccess, setSubmitSuccess] = useState(false)

  // ── Hooks ──────────────────────────────────────────────
  const { data: bodegas, isLoading: bodegasLoading } = useBodegas()
  const registrarSalida = useRegistrarSalida()

  // Set default bodega when loaded
  useEffect(() => {
    if (bodegas && (bodegas as any[]).length > 0 && !bodegaId) {
      setBodegaId((bodegas as any[])[0].id)
    }
  }, [bodegas, bodegaId])

  // OT search query (searches active OTs)
  const { data: otResults } = useOrdenesTrabajo(
    otSearch.length >= 2 ? {} : undefined
  )

  // Barcode lookup
  const { data: barcodeProduct } = useProductoByBarcode(scannedBarcode)

  // When barcode product is found, select it
  useEffect(() => {
    if (barcodeProduct && scannedBarcode) {
      setSelectedProducto(barcodeProduct)
      setScannedBarcode(undefined)
    }
  }, [barcodeProduct, scannedBarcode])

  // Scanner hook
  const onScan = useCallback((code: string) => {
    setScannedBarcode(code)
  }, [])
  const { startScanning, stopScanning, isScanning, error: scanError } = useScanner(onScan)

  // Filter OTs client-side by folio
  const filteredOTs = otSearch.length >= 2
    ? ((otResults ?? []) as any[]).filter((ot: any) => {
        const q = otSearch.toLowerCase()
        const activoName = ot.activo?.nombre || ot.activo?.codigo || ''
        return ot.folio.toLowerCase().includes(q) || activoName.toLowerCase().includes(q)
      })
    : []

  // Product search — client side from stock data
  const { data: allStock } = useStockBodega(
    bodegaId ? { bodega_id: bodegaId } : undefined
  )
  const filteredProductos = productoSearch && !selectedProducto
    ? ((allStock ?? []) as any[]).filter((s: any) => {
        const p = s.producto
        if (!p) return false
        const q = productoSearch.toLowerCase()
        return (
          (p.codigo?.toLowerCase().includes(q)) ||
          (p.nombre?.toLowerCase().includes(q)) ||
          (p.codigo_barras?.toLowerCase().includes(q))
        )
      })
    : []

  // Get stock info for display
  const stockInfo = selectedProducto && allStock
    ? ((allStock as any[]).find((s: any) => s.producto_id === selectedProducto.id) ?? null)
    : null

  // Cost calculation
  const costoUnitario = stockInfo?.costo_promedio ?? selectedProducto?.costo_unitario_actual ?? 0
  const costoTotal = costoUnitario * (parseInt(cantidad) || 0)

  function handleSubmit() {
    if (!selectedOT) {
      setShowOTWarning(true)
      return
    }
    if (!selectedProducto || !cantidad || !bodegaId) return

    setSubmitError(null)
    setSubmitSuccess(false)

    registrarSalida.mutate(
      {
        bodega_id: bodegaId,
        producto_id: selectedProducto.id,
        cantidad: parseInt(cantidad),
        ot_id: selectedOT.id,
        motivo: observaciones || null,
        usuario_id: user!.id,
      },
      {
        onSuccess: () => {
          setSubmitSuccess(true)
          const prodName = selectedProducto?.nombre
          const prodUnit = selectedProducto?.unidad_medida
          // Reset form
          setSelectedProducto(null)
          setCantidad('')
          setObservaciones('')
          setTimeout(() => setSubmitSuccess(false), 4000)
        },
        onError: (err: any) => {
          setSubmitError(err?.message || 'Error al registrar la salida')
        },
      }
    )
  }

  const bodegasList = (bodegas ?? []) as any[]

  return (
    <div className="mx-auto max-w-lg space-y-6 pb-8">
      {/* Back */}
      <Link
        href="/dashboard/inventario"
        className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700"
      >
        <ArrowLeft className="h-4 w-4" />
        Volver a Inventario
      </Link>

      <h1 className="text-2xl font-bold text-gray-900">Salida de Inventario</h1>

      {/* Scanner button */}
      <button
        type="button"
        onClick={() => (isScanning ? stopScanning() : startScanning())}
        className={cn(
          'flex w-full flex-col items-center justify-center gap-3 rounded-2xl border-2 border-dashed py-8 transition-colors',
          isScanning
            ? 'border-red-300 bg-red-50 hover:border-red-400'
            : 'border-pillado-green-300 bg-pillado-green-50 hover:border-pillado-green-400 hover:bg-pillado-green-100 active:bg-pillado-green-200'
        )}
      >
        <div className={cn(
          'flex h-16 w-16 items-center justify-center rounded-2xl',
          isScanning ? 'bg-red-500' : 'bg-pillado-green-500'
        )}>
          <ScanLine className="h-8 w-8 text-white" />
        </div>
        <span className={cn(
          'text-lg font-semibold',
          isScanning ? 'text-red-700' : 'text-pillado-green-700'
        )}>
          {isScanning ? 'Detener escáner' : 'Escanear Producto'}
        </span>
        <span className={cn(
          'text-sm',
          isScanning ? 'text-red-600' : 'text-pillado-green-600'
        )}>
          {isScanning ? 'Escaneando...' : 'Abrir cámara para código de barras'}
        </span>
      </button>

      {/* Scanner region (hidden, used by html5-qrcode) */}
      <div id="scanner-region" className={isScanning ? '' : 'hidden'} />

      {/* Scanner error */}
      {scanError && (
        <div className="flex items-center gap-2 rounded-lg bg-red-50 p-3 text-sm text-red-700">
          <AlertCircle className="h-4 w-4 shrink-0" />
          {scanError}
        </div>
      )}

      {/* Success message */}
      {submitSuccess && (
        <div className="flex items-center gap-3 rounded-xl border border-green-200 bg-green-50 p-4">
          <CheckCircle2 className="h-6 w-6 text-green-600" />
          <div>
            <p className="text-sm font-semibold text-green-800">Salida registrada correctamente</p>
          </div>
        </div>
      )}

      {/* Error message */}
      {submitError && (
        <div className="flex items-center gap-3 rounded-xl border border-red-200 bg-red-50 p-4">
          <XCircle className="h-6 w-6 text-red-600" />
          <div className="flex-1">
            <p className="text-sm font-semibold text-red-800">{submitError}</p>
          </div>
          <button onClick={() => setSubmitError(null)} className="text-red-400 hover:text-red-600">
            <X className="h-4 w-4" />
          </button>
        </div>
      )}

      {/* Form */}
      <div className="space-y-5">
        {/* OT Asociada */}
        <div>
          <label className="mb-1.5 flex items-center gap-1 text-sm font-medium text-gray-700">
            OT Asociada <span className="text-red-500">*</span>
          </label>
          {!selectedOT ? (
            <div className="relative">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
                <input
                  type="text"
                  placeholder="Buscar OT por folio o activo..."
                  value={otSearch}
                  onChange={(e) => {
                    setOtSearch(e.target.value)
                    setShowOTResults(true)
                    setShowOTWarning(false)
                  }}
                  onFocus={() => setShowOTResults(true)}
                  className={cn(
                    'min-h-[48px] w-full rounded-lg border bg-white pl-10 pr-3 text-base focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20',
                    showOTWarning ? 'border-red-500' : 'border-gray-300'
                  )}
                />
              </div>
              {showOTResults && otSearch.length >= 2 && (
                <div className="absolute z-20 mt-1 w-full rounded-xl border border-gray-200 bg-white shadow-lg">
                  {filteredOTs.length > 0 ? (
                    filteredOTs.slice(0, 10).map((ot: any) => (
                      <button
                        key={ot.id}
                        type="button"
                        onClick={() => {
                          setSelectedOT(ot)
                          setShowOTResults(false)
                          setOtSearch('')
                          setShowOTWarning(false)
                        }}
                        className="flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-gray-50"
                      >
                        <div>
                          <p className="text-sm font-semibold text-gray-900">{ot.folio}</p>
                          <p className="text-xs text-gray-500">
                            {tipoLabel(ot.tipo)} — {ot.activo?.nombre || ot.activo?.codigo || '—'}
                          </p>
                        </div>
                      </button>
                    ))
                  ) : (
                    <p className="px-4 py-3 text-sm text-gray-400">Sin resultados</p>
                  )}
                </div>
              )}
            </div>
          ) : (
            <div className="flex items-center justify-between rounded-lg border border-pillado-green-200 bg-pillado-green-50 p-3">
              <div>
                <p className="text-sm font-bold text-gray-900">{selectedOT.folio}</p>
                <p className="text-xs text-gray-500">
                  {tipoLabel(selectedOT.tipo)} — {selectedOT.activo?.nombre || selectedOT.activo?.codigo || '—'}
                </p>
              </div>
              <button
                type="button"
                onClick={() => setSelectedOT(null)}
                className="text-xs text-red-500 hover:underline"
              >
                Cambiar
              </button>
            </div>
          )}
          {showOTWarning && (
            <div className="mt-2 flex items-center gap-2 rounded-lg bg-red-50 p-3">
              <AlertCircle className="h-5 w-5 shrink-0 text-red-500" />
              <p className="text-sm font-semibold text-red-700">
                No se permite salida sin OT asociada
              </p>
            </div>
          )}
        </div>

        {/* Producto */}
        <div>
          <label className="mb-1.5 flex items-center gap-1 text-sm font-medium text-gray-700">
            Producto <span className="text-red-500">*</span>
          </label>
          {!selectedProducto ? (
            <div className="relative">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
                <input
                  type="text"
                  placeholder="Buscar por código o nombre..."
                  value={productoSearch}
                  onChange={(e) => {
                    setProductoSearch(e.target.value)
                    setShowProductoResults(true)
                  }}
                  onFocus={() => setShowProductoResults(true)}
                  className="min-h-[48px] w-full rounded-lg border border-gray-300 bg-white pl-10 pr-3 text-base focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
                />
              </div>
              {showProductoResults && productoSearch && filteredProductos.length > 0 && (
                <div className="absolute z-20 mt-1 w-full rounded-xl border border-gray-200 bg-white shadow-lg">
                  {filteredProductos.slice(0, 10).map((s: any) => {
                    const p = s.producto
                    return (
                      <button
                        key={s.id}
                        type="button"
                        onClick={() => {
                          setSelectedProducto(p)
                          setShowProductoResults(false)
                          setProductoSearch('')
                        }}
                        className="flex w-full items-center justify-between px-4 py-3 text-left hover:bg-gray-50"
                      >
                        <div>
                          <p className="text-sm font-semibold text-gray-900">{p.nombre}</p>
                          <p className="font-mono text-xs text-gray-400">{p.codigo}</p>
                        </div>
                        <div className="text-right">
                          <p className="text-sm font-semibold text-gray-700">
                            {s.cantidad} {p.unidad_medida}
                          </p>
                          <p className="text-xs text-gray-400">
                            {formatCLP(s.costo_promedio)}/{p.unidad_medida}
                          </p>
                        </div>
                      </button>
                    )
                  })}
                </div>
              )}
              {showProductoResults && productoSearch && filteredProductos.length === 0 && (
                <div className="absolute z-20 mt-1 w-full rounded-xl border border-gray-200 bg-white shadow-lg">
                  <p className="px-4 py-3 text-sm text-gray-400">Sin resultados</p>
                </div>
              )}
            </div>
          ) : (
            <div className="flex items-center justify-between rounded-lg border border-pillado-green-200 bg-pillado-green-50 p-3">
              <div>
                <p className="text-sm font-bold text-gray-900">{selectedProducto.nombre}</p>
                <p className="text-xs text-gray-500">
                  {stockInfo
                    ? `Stock: ${stockInfo.cantidad} ${selectedProducto.unidad_medida} — ${formatCLP(stockInfo.costo_promedio)}/${selectedProducto.unidad_medida}`
                    : `${formatCLP(selectedProducto.costo_unitario_actual)}/${selectedProducto.unidad_medida}`}
                </p>
              </div>
              <button
                type="button"
                onClick={() => setSelectedProducto(null)}
                className="text-xs text-red-500 hover:underline"
              >
                Cambiar
              </button>
            </div>
          )}
        </div>

        {/* Cantidad */}
        <div>
          <label className="mb-1.5 flex items-center gap-1 text-sm font-medium text-gray-700">
            Cantidad <span className="text-red-500">*</span>
          </label>
          <input
            type="number"
            min="1"
            max={stockInfo?.cantidad}
            value={cantidad}
            onChange={(e) => setCantidad(e.target.value)}
            placeholder="0"
            className="min-h-[56px] w-full rounded-lg border border-gray-300 bg-white px-4 text-center text-2xl font-bold text-gray-900 focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
          />
          {selectedProducto && cantidad && (
            <p className="mt-2 text-center text-sm text-gray-500">
              Costo total: <span className="font-semibold text-gray-900">{formatCLP(costoTotal)}</span>
            </p>
          )}
        </div>

        {/* Bodega */}
        <div>
          <label className="mb-1.5 flex items-center gap-1 text-sm font-medium text-gray-700">
            Bodega <span className="text-red-500">*</span>
          </label>
          <div className="relative">
            {bodegasLoading ? (
              <div className="flex h-12 items-center justify-center">
                <Spinner size="sm" className="text-gray-400" />
              </div>
            ) : (
              <>
                <select
                  value={bodegaId}
                  onChange={(e) => setBodegaId(e.target.value)}
                  className="min-h-[48px] w-full appearance-none rounded-lg border border-gray-300 bg-white px-3 pr-8 text-base focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
                >
                  {bodegasList.map((b: any) => (
                    <option key={b.id} value={b.id}>{b.nombre}</option>
                  ))}
                </select>
                <ChevronDown className="pointer-events-none absolute right-3 top-1/2 h-5 w-5 -translate-y-1/2 text-gray-400" />
              </>
            )}
          </div>
        </div>

        {/* Observaciones */}
        <div>
          <label className="mb-1.5 block text-sm font-medium text-gray-700">
            Observaciones <span className="text-xs text-gray-400">(opcional)</span>
          </label>
          <textarea
            value={observaciones}
            onChange={(e) => setObservaciones(e.target.value)}
            placeholder="Agregar observación..."
            rows={3}
            className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
          />
        </div>

        {/* Submit */}
        <Button
          variant="primary"
          size="lg"
          className="w-full text-lg"
          onClick={handleSubmit}
          disabled={!selectedOT || !selectedProducto || !cantidad || registrarSalida.isPending}
        >
          {registrarSalida.isPending ? (
            <Spinner size="sm" className="mr-1" />
          ) : (
            <Package className="h-5 w-5" />
          )}
          Registrar Salida
        </Button>
      </div>

      {/* Bottom info */}
      <Card>
        <CardContent className="flex flex-col gap-2 p-4 text-xs text-gray-500">
          <div className="flex items-center gap-2">
            <Clock className="h-4 w-4" />
            <span>{formatDateTime(new Date().toISOString())}</span>
          </div>
          {selectedOT?.faena && (
            <div className="flex items-center gap-2">
              <MapPin className="h-4 w-4" />
              <span>{selectedOT.faena.nombre}</span>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const tipoLabelsMap: Record<string, string> = {
  inspeccion: 'Inspección',
  preventivo: 'Preventivo',
  correctivo: 'Correctivo',
  abastecimiento: 'Abastecimiento',
  lubricacion: 'Lubricación',
  inventario: 'Inventario',
  regularizacion: 'Regularización',
}

function tipoLabel(tipo: string) {
  return tipoLabelsMap[tipo] || tipo
}
