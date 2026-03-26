'use client'

import { useState, useMemo, useCallback } from 'react'
import {
  ScanLine,
  Package,
  CheckCircle2,
  AlertTriangle,
  Plus,
  List,
  ChevronDown,
  Search,
  ArrowLeft,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { EmptyState } from '@/components/ui/empty-state'
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@/components/ui/table'
import { formatCLP, formatDate, cn } from '@/lib/utils'
import {
  useBodegas,
  useConteos,
  useConteoDetalle,
  useCrearConteo,
  useRegistrarLineaConteo,
  useCompletarConteo,
  useProductos,
  useProductoByBarcode,
} from '@/hooks/use-inventario'
import { useScanner } from '@/hooks/use-scanner'
import { useAuth } from '@/contexts/auth-context'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
type Step = 'list' | 'create' | 'counting' | 'completed'

interface ConteoActivo {
  id: string
  bodega_id: string
  bodega_nombre: string
  tipo: string
  fecha_inicio: string
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function getEstadoConteoBadge(estado: string) {
  const map: Record<string, string> = {
    en_proceso: 'bg-amber-100 text-amber-700',
    completado: 'bg-green-100 text-green-700',
    aprobado: 'bg-blue-100 text-blue-700',
    rechazado: 'bg-red-100 text-red-700',
  }
  const labels: Record<string, string> = {
    en_proceso: 'En Proceso',
    completado: 'Completado',
    aprobado: 'Aprobado',
    rechazado: 'Rechazado',
  }
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold',
        map[estado] || 'bg-gray-100 text-gray-700'
      )}
    >
      {labels[estado] || estado}
    </span>
  )
}

function getTipoBadge(tipo: string) {
  const map: Record<string, string> = {
    ciclico: 'bg-blue-100 text-blue-700',
    general: 'bg-purple-100 text-purple-700',
    selectivo: 'bg-orange-100 text-orange-700',
  }
  const labels: Record<string, string> = {
    ciclico: 'Ciclico',
    general: 'General',
    selectivo: 'Selectivo',
  }
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold',
        map[tipo] || 'bg-gray-100 text-gray-700'
      )}
    >
      {labels[tipo] || tipo}
    </span>
  )
}

function getDiferenciaColor(diferencia: number) {
  if (diferencia === 0) return 'text-green-600'
  if (diferencia > 0) return 'text-blue-600'
  return 'text-red-600'
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------
export default function ConteoPage() {
  const { user, perfil } = useAuth()

  // Step state
  const [step, setStep] = useState<Step>('list')
  const [conteoActivo, setConteoActivo] = useState<ConteoActivo | null>(null)

  // Create form
  const [bodegaId, setBodegaId] = useState('')
  const [tipo, setTipo] = useState('ciclico')

  // Counting state
  const [scannedCode, setScannedCode] = useState<string | null>(null)
  const [searchProducto, setSearchProducto] = useState('')
  const [selectedProducto, setSelectedProducto] = useState<any>(null)
  const [stockFisico, setStockFisico] = useState('')
  const [showScanner, setShowScanner] = useState(false)

  // Hooks
  const { data: bodegas } = useBodegas()
  const { data: conteos, isLoading: loadingConteos } = useConteos()
  const { data: detalleItems, isLoading: loadingDetalle } = useConteoDetalle(
    conteoActivo?.id
  )
  const { data: productos } = useProductos(
    searchProducto ? { search: searchProducto } : undefined
  )
  const { data: productoScanned } = useProductoByBarcode(scannedCode ?? undefined)

  const crearConteo = useCrearConteo()
  const registrarLinea = useRegistrarLineaConteo()
  const completar = useCompletarConteo()

  // Scanner
  const handleScan = useCallback(
    (code: string) => {
      setScannedCode(code)
      setShowScanner(false)
      setSearchProducto('')
    },
    []
  )

  const { startScanning, stopScanning, isScanning, error: scannerError } =
    useScanner(handleScan)

  // When barcode product resolves, auto-select it
  useMemo(() => {
    if (productoScanned && scannedCode) {
      setSelectedProducto(productoScanned)
      setScannedCode(null)
    }
  }, [productoScanned, scannedCode])

  // Search results filtering
  const searchResults = useMemo(() => {
    if (!searchProducto || searchProducto.length < 2) return []
    return (productos ?? []).slice(0, 8)
  }, [productos, searchProducto])

  // Counting stats
  const countStats = useMemo(() => {
    if (!detalleItems) return { total: 0, conDiferencia: 0, valorDiferencia: 0 }
    const items = detalleItems as any[]
    const conDiferencia = items.filter(
      (d) => (d.stock_fisico ?? d.cantidad_contada ?? 0) - (d.stock_sistema ?? 0) !== 0
    ).length
    const valorDiferencia = items.reduce(
      (sum, d) => sum + (d.diferencia_valorizada ?? 0),
      0
    )
    return { total: items.length, conDiferencia, valorDiferencia }
  }, [detalleItems])

  // ── Handlers ─────────────────────────────────────────────
  const handleCrearConteo = async () => {
    if (!bodegaId || !user?.id) return
    const bodega = (bodegas as any[])?.find((b: any) => b.id === bodegaId)
    try {
      const result = await crearConteo.mutateAsync({
        bodega_id: bodegaId,
        tipo,
        responsable_id: user.id,
      })
      setConteoActivo({
        id: result.id,
        bodega_id: bodegaId,
        bodega_nombre: bodega?.nombre ?? '',
        tipo,
        fecha_inicio: result.fecha_inicio ?? new Date().toISOString(),
      })
      setStep('counting')
    } catch {
      // error handled by mutation
    }
  }

  const handleRegistrarLinea = async () => {
    if (!conteoActivo || !selectedProducto || !stockFisico) return
    try {
      await registrarLinea.mutateAsync({
        conteo_id: conteoActivo.id,
        producto_id: selectedProducto.id,
        stock_fisico: Number(stockFisico),
      })
      setSelectedProducto(null)
      setStockFisico('')
      setSearchProducto('')
    } catch {
      // error handled by mutation
    }
  }

  const handleCompletarConteo = async () => {
    if (!conteoActivo) return
    try {
      await completar.mutateAsync(conteoActivo.id)
      setStep('completed')
    } catch {
      // error handled by mutation
    }
  }

  const handleToggleScanner = async () => {
    if (isScanning) {
      await stopScanning()
      setShowScanner(false)
    } else {
      setShowScanner(true)
      // Small delay to ensure the DOM element is rendered
      setTimeout(() => {
        startScanning()
      }, 100)
    }
  }

  const handleSelectSearchProduct = (producto: any) => {
    setSelectedProducto(producto)
    setSearchProducto('')
  }

  const handleVolver = () => {
    setStep('list')
    setConteoActivo(null)
    setSelectedProducto(null)
    setStockFisico('')
    setSearchProducto('')
    setScannedCode(null)
  }

  // ── Step: List (previous conteos) ────────────────────────
  if (step === 'list') {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-bold text-gray-900">Conteos de Inventario</h1>
          <Button
            variant="primary"
            size="lg"
            onClick={() => setStep('create')}
          >
            <Plus className="h-5 w-5" />
            Iniciar Conteo
          </Button>
        </div>

        {loadingConteos && (
          <div className="flex justify-center py-16">
            <Spinner size="lg" className="text-pillado-green-600" />
          </div>
        )}

        {!loadingConteos && (!conteos || (conteos as any[]).length === 0) && (
          <Card>
            <CardContent>
              <EmptyState
                icon={List}
                title="Sin conteos registrados"
                description="Inicie un conteo fisico para comparar el stock del sistema contra el real."
                action={{
                  label: 'Iniciar Conteo',
                  onClick: () => setStep('create'),
                }}
              />
            </CardContent>
          </Card>
        )}

        {!loadingConteos && conteos && (conteos as any[]).length > 0 && (
          <Card>
            {/* Desktop table */}
            <div className="hidden md:block">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Fecha</TableHead>
                    <TableHead>Bodega</TableHead>
                    <TableHead>Tipo</TableHead>
                    <TableHead>Estado</TableHead>
                    <TableHead>Responsable</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {(conteos as any[]).map((c) => (
                    <TableRow key={c.id}>
                      <TableCell className="whitespace-nowrap text-xs">
                        {formatDate(c.created_at)}
                      </TableCell>
                      <TableCell className="text-sm">
                        {c.bodega?.nombre ?? '--'}
                      </TableCell>
                      <TableCell>{getTipoBadge(c.tipo)}</TableCell>
                      <TableCell>{getEstadoConteoBadge(c.estado)}</TableCell>
                      <TableCell className="text-xs text-gray-500">
                        {c.responsable?.nombre_completo ?? '--'}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>

            {/* Mobile cards */}
            <div className="space-y-2 p-4 md:hidden">
              {(conteos as any[]).map((c) => (
                <div
                  key={c.id}
                  className="rounded-lg border border-gray-100 p-3"
                >
                  <div className="flex items-start justify-between">
                    <div>
                      <p className="text-sm font-semibold text-gray-900">
                        {c.bodega?.nombre ?? '--'}
                      </p>
                      <p className="text-xs text-gray-400">
                        {formatDate(c.created_at)}
                      </p>
                    </div>
                    {getEstadoConteoBadge(c.estado)}
                  </div>
                  <div className="mt-2 flex items-center justify-between">
                    {getTipoBadge(c.tipo)}
                    <span className="text-xs text-gray-500">
                      {c.responsable?.nombre_completo ?? '--'}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </Card>
        )}
      </div>
    )
  }

  // ── Step: Create ─────────────────────────────────────────
  if (step === 'create') {
    return (
      <div className="space-y-6">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="sm" onClick={() => setStep('list')}>
            <ArrowLeft className="h-4 w-4" />
          </Button>
          <h1 className="text-2xl font-bold text-gray-900">Iniciar Conteo</h1>
        </div>

        <Card>
          <CardContent className="space-y-5 p-6">
            {/* Bodega */}
            <div>
              <label className="mb-1 block text-sm font-medium text-gray-700">
                Bodega
              </label>
              <div className="relative">
                <select
                  value={bodegaId}
                  onChange={(e) => setBodegaId(e.target.value)}
                  className="min-h-[48px] w-full appearance-none rounded-lg border border-gray-300 bg-white px-3 pr-8 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
                >
                  <option value="">Seleccione bodega...</option>
                  {(bodegas ?? []).map((b: any) => (
                    <option key={b.id} value={b.id}>
                      {b.nombre}
                    </option>
                  ))}
                </select>
                <ChevronDown className="pointer-events-none absolute right-2 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
              </div>
            </div>

            {/* Tipo */}
            <div>
              <label className="mb-1 block text-sm font-medium text-gray-700">
                Tipo de Conteo
              </label>
              <div className="relative">
                <select
                  value={tipo}
                  onChange={(e) => setTipo(e.target.value)}
                  className="min-h-[48px] w-full appearance-none rounded-lg border border-gray-300 bg-white px-3 pr-8 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
                >
                  <option value="ciclico">Ciclico</option>
                  <option value="general">General</option>
                  <option value="selectivo">Selectivo</option>
                </select>
                <ChevronDown className="pointer-events-none absolute right-2 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
              </div>
            </div>

            <Button
              variant="primary"
              size="lg"
              className="w-full"
              onClick={handleCrearConteo}
              loading={crearConteo.isPending}
              disabled={!bodegaId}
            >
              <Plus className="h-5 w-5" />
              Iniciar Conteo
            </Button>
          </CardContent>
        </Card>
      </div>
    )
  }

  // ── Step: Counting (main mobile-optimized screen) ────────
  if (step === 'counting' && conteoActivo) {
    return (
      <div className="flex min-h-[calc(100vh-120px)] flex-col space-y-4">
        {/* Header info */}
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="sm" onClick={handleVolver}>
            <ArrowLeft className="h-4 w-4" />
          </Button>
          <div className="flex-1">
            <h1 className="text-lg font-bold text-gray-900">
              Conteo en Proceso
            </h1>
            <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-gray-500">
              <span className="font-medium text-gray-700">
                {conteoActivo.bodega_nombre}
              </span>
              {getTipoBadge(conteoActivo.tipo)}
              <span>{formatDate(conteoActivo.fecha_inicio)}</span>
              <Badge variant="primary">{countStats.total} items</Badge>
            </div>
          </div>
        </div>

        {/* Scanner section */}
        <Card>
          <CardContent className="space-y-4 p-4">
            {/* Scanner button */}
            <Button
              variant={isScanning ? 'danger' : 'secondary'}
              size="lg"
              className="w-full"
              onClick={handleToggleScanner}
            >
              <ScanLine className="h-5 w-5" />
              {isScanning ? 'Detener Camara' : 'Escanear Producto'}
            </Button>

            {/* Camera preview */}
            {showScanner && (
              <div
                id="scanner-region"
                className="mx-auto aspect-square max-w-[300px] overflow-hidden rounded-lg border-2 border-dashed border-gray-300"
              />
            )}

            {scannerError && (
              <div className="rounded-lg bg-red-50 p-3 text-xs text-red-700">
                <AlertTriangle className="mr-1 inline h-4 w-4" />
                {scannerError}
              </div>
            )}

            {/* Manual search */}
            <div className="relative">
              <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
              <Input
                placeholder="Buscar por codigo o nombre..."
                value={searchProducto}
                onChange={(e) => {
                  setSearchProducto(e.target.value)
                  setSelectedProducto(null)
                }}
                className="min-h-[48px] pl-9"
              />
            </div>

            {/* Search results dropdown */}
            {searchResults.length > 0 && !selectedProducto && (
              <div className="max-h-48 overflow-y-auto rounded-lg border border-gray-200 bg-white shadow-lg">
                {searchResults.map((p: any) => (
                  <button
                    key={p.id}
                    onClick={() => handleSelectSearchProduct(p)}
                    className="flex w-full items-center gap-3 border-b border-gray-50 px-3 py-2.5 text-left transition-colors hover:bg-gray-50 last:border-0"
                  >
                    <Package className="h-4 w-4 shrink-0 text-gray-400" />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium text-gray-900">
                        {p.nombre}
                      </p>
                      <p className="font-mono text-xs text-gray-400">
                        {p.codigo}
                      </p>
                    </div>
                    <span className="shrink-0 text-xs text-gray-400">
                      {p.unidad_medida}
                    </span>
                  </button>
                ))}
              </div>
            )}

            {/* Selected product form */}
            {selectedProducto && (
              <div className="rounded-lg border-2 border-pillado-green-200 bg-pillado-green-50/30 p-4 space-y-3">
                <div>
                  <p className="text-base font-semibold text-gray-900">
                    {selectedProducto.nombre}
                  </p>
                  <p className="font-mono text-xs text-gray-500">
                    {selectedProducto.codigo} - {selectedProducto.unidad_medida}
                  </p>
                </div>

                <div>
                  <label className="mb-1 block text-xs font-medium text-gray-500">
                    Stock Fisico
                  </label>
                  <Input
                    type="number"
                    inputMode="numeric"
                    min={0}
                    placeholder="Cantidad contada..."
                    value={stockFisico}
                    onChange={(e) => setStockFisico(e.target.value)}
                    className="min-h-[48px] text-lg font-bold"
                    autoFocus
                  />
                </div>

                <Button
                  variant="primary"
                  size="lg"
                  className="w-full"
                  onClick={handleRegistrarLinea}
                  loading={registrarLinea.isPending}
                  disabled={!stockFisico}
                >
                  <CheckCircle2 className="h-5 w-5" />
                  Registrar
                </Button>

                <Button
                  variant="ghost"
                  size="sm"
                  className="w-full"
                  onClick={() => {
                    setSelectedProducto(null)
                    setStockFisico('')
                  }}
                >
                  Cancelar
                </Button>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Counted items list */}
        <Card className="flex-1">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-semibold text-gray-700">
              Items Contados ({countStats.total})
            </CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            {loadingDetalle && (
              <div className="flex justify-center py-8">
                <Spinner size="sm" className="text-pillado-green-600" />
              </div>
            )}

            {!loadingDetalle && (!detalleItems || (detalleItems as any[]).length === 0) && (
              <div className="py-8 text-center text-sm text-gray-400">
                Aun no se han contado productos
              </div>
            )}

            {!loadingDetalle && detalleItems && (detalleItems as any[]).length > 0 && (
              <div className="max-h-[320px] overflow-y-auto">
                {(detalleItems as any[]).map((d) => {
                  const fisico = d.stock_fisico ?? d.cantidad_contada ?? 0
                  const sistema = d.stock_sistema ?? 0
                  const diferencia = fisico - sistema
                  return (
                    <div
                      key={d.id}
                      className="flex items-center justify-between border-b border-gray-50 px-4 py-2.5 last:border-0"
                    >
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium text-gray-900">
                          {d.producto?.nombre ?? '--'}
                        </p>
                        <p className="text-xs text-gray-400">
                          Sistema: {sistema} | Fisico: {fisico}
                        </p>
                      </div>
                      <div className="ml-3 text-right">
                        <p
                          className={cn(
                            'text-sm font-bold',
                            getDiferenciaColor(diferencia)
                          )}
                        >
                          {diferencia > 0 ? '+' : ''}
                          {diferencia}
                        </p>
                        {d.diferencia_valorizada != null && d.diferencia_valorizada > 0 && (
                          <p className="text-xs text-gray-400">
                            {formatCLP(d.diferencia_valorizada)}
                          </p>
                        )}
                      </div>
                    </div>
                  )
                })}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Sticky bottom: Finalizar */}
        <div className="sticky bottom-0 bg-white pb-4 pt-2">
          <Button
            variant="primary"
            size="lg"
            className="w-full bg-green-600 hover:bg-green-700 active:bg-green-800"
            onClick={handleCompletarConteo}
            loading={completar.isPending}
            disabled={countStats.total === 0}
          >
            <CheckCircle2 className="h-5 w-5" />
            Finalizar Conteo
          </Button>
        </div>
      </div>
    )
  }

  // ── Step: Completed ──────────────────────────────────────
  if (step === 'completed') {
    const itemsConDiferencia = (detalleItems as any[] | null)?.filter((d) => {
      const fisico = d.stock_fisico ?? d.cantidad_contada ?? 0
      const sistema = d.stock_sistema ?? 0
      return fisico - sistema !== 0
    }) ?? []

    return (
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-gray-900">Conteo Completado</h1>

        {/* Summary cards */}
        <div className="grid grid-cols-3 gap-3">
          <Card>
            <CardContent className="flex flex-col items-center p-4 text-center">
              <Package className="mb-1 h-6 w-6 text-pillado-green-600" />
              <p className="text-2xl font-bold text-gray-900">
                {countStats.total}
              </p>
              <p className="text-xs text-gray-500">Total Items</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="flex flex-col items-center p-4 text-center">
              <AlertTriangle className="mb-1 h-6 w-6 text-amber-600" />
              <p className="text-2xl font-bold text-gray-900">
                {countStats.conDiferencia}
              </p>
              <p className="text-xs text-gray-500">Con Diferencia</p>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="flex flex-col items-center p-4 text-center">
              <AlertTriangle className="mb-1 h-6 w-6 text-red-600" />
              <p className="text-2xl font-bold text-red-600">
                {formatCLP(countStats.valorDiferencia)}
              </p>
              <p className="text-xs text-gray-500">Dif. Valorizada</p>
            </CardContent>
          </Card>
        </div>

        {/* Items with differences */}
        {itemsConDiferencia.length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle className="text-sm font-semibold text-gray-700">
                Items con Diferencias ({itemsConDiferencia.length})
              </CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              {/* Desktop */}
              <div className="hidden md:block">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Producto</TableHead>
                      <TableHead className="text-right">Sistema</TableHead>
                      <TableHead className="text-right">Fisico</TableHead>
                      <TableHead className="text-right">Diferencia</TableHead>
                      <TableHead className="text-right">
                        Dif. Valorizada
                      </TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {itemsConDiferencia.map((d: any) => {
                      const fisico = d.stock_fisico ?? d.cantidad_contada ?? 0
                      const sistema = d.stock_sistema ?? 0
                      const diferencia = fisico - sistema
                      return (
                        <TableRow key={d.id}>
                          <TableCell className="font-medium">
                            {d.producto?.nombre ?? '--'}
                          </TableCell>
                          <TableCell className="text-right">{sistema}</TableCell>
                          <TableCell className="text-right">{fisico}</TableCell>
                          <TableCell
                            className={cn(
                              'text-right font-bold',
                              getDiferenciaColor(diferencia)
                            )}
                          >
                            {diferencia > 0 ? '+' : ''}
                            {diferencia}
                          </TableCell>
                          <TableCell className="text-right">
                            {formatCLP(d.diferencia_valorizada ?? 0)}
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </div>

              {/* Mobile */}
              <div className="space-y-2 p-4 md:hidden">
                {itemsConDiferencia.map((d: any) => {
                  const fisico = d.stock_fisico ?? d.cantidad_contada ?? 0
                  const sistema = d.stock_sistema ?? 0
                  const diferencia = fisico - sistema
                  return (
                    <div
                      key={d.id}
                      className="rounded-lg border border-gray-100 p-3"
                    >
                      <p className="text-sm font-semibold text-gray-900">
                        {d.producto?.nombre ?? '--'}
                      </p>
                      <div className="mt-1 flex justify-between text-xs text-gray-500">
                        <span>
                          Sistema: {sistema} | Fisico: {fisico}
                        </span>
                        <span
                          className={cn(
                            'font-bold',
                            getDiferenciaColor(diferencia)
                          )}
                        >
                          {diferencia > 0 ? '+' : ''}
                          {diferencia}
                        </span>
                      </div>
                      {d.diferencia_valorizada != null && d.diferencia_valorizada > 0 && (
                        <p className="mt-1 text-right text-xs text-gray-400">
                          {formatCLP(d.diferencia_valorizada)}
                        </p>
                      )}
                    </div>
                  )
                })}
              </div>
            </CardContent>
          </Card>
        )}

        <Button
          variant="primary"
          size="lg"
          className="w-full"
          onClick={handleVolver}
        >
          <List className="h-5 w-5" />
          Volver a Conteos
        </Button>
      </div>
    )
  }

  return null
}
