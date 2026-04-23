'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { ScanBarcode, Camera, Package, Minus, Plus, CheckCircle2, XCircle } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { BarcodeScanner } from '@/components/ui/barcode-scanner'
import { supabase } from '@/lib/supabase'
import { cn } from '@/lib/utils'

type Producto = {
  id: string
  codigo: string
  codigo_barras: string | null
  nombre: string
  unidad_medida: string
  stock_total: number
  stocks: Array<{ bodega_id: string; bodega: string; cantidad: number; costo_promedio: number }>
}

type Tipo = 'entrada' | 'salida'

export default function ScannerPage() {
  useRequireAuth()

  const [scannerOn, setScannerOn] = useState(false)
  const [codigoInput, setCodigoInput] = useState('')
  const [producto, setProducto] = useState<Producto | null>(null)
  const [bodegaSel, setBodegaSel] = useState<string>('')
  const [cantidad, setCantidad] = useState('1')
  const [tipo, setTipo] = useState<Tipo>('salida')
  const [loading, setLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [historial, setHistorial] = useState<Array<{ codigo: string; nombre: string; cantidad: number; tipo: Tipo; ts: string }>>([])
  const [errorMsg, setErrorMsg] = useState<string | null>(null)
  const [successMsg, setSuccessMsg] = useState<string | null>(null)

  // Fetch producto por código (barras o código interno)
  const buscarProducto = async (codigo: string) => {
    setLoading(true)
    setErrorMsg(null)
    setProducto(null)
    try {
      const q = codigo.trim()
      if (!q) return
      const { data, error } = await supabase
        .from('productos')
        .select('id, codigo, codigo_barras, nombre, unidad_medida')
        .or(`codigo.eq.${q},codigo_barras.eq.${q}`)
        .maybeSingle()
      if (error) throw error
      if (!data) {
        setErrorMsg(`No se encontró producto con código "${q}"`)
        return
      }
      // Traer stocks por bodega
      const { data: stocks, error: stErr } = await supabase
        .from('stock_bodega')
        .select('bodega_id, cantidad, costo_promedio, bodega:bodegas(nombre)')
        .eq('producto_id', data.id)
        .gt('cantidad', 0)
      if (stErr) throw stErr
      const stockList = (stocks ?? []).map((s: any) => ({
        bodega_id: s.bodega_id as string,
        bodega: s.bodega?.nombre ?? '—',
        cantidad: Number(s.cantidad),
        costo_promedio: Number(s.costo_promedio),
      }))
      const totalStock = stockList.reduce((acc, s) => acc + s.cantidad, 0)
      setProducto({
        id: data.id,
        codigo: data.codigo,
        codigo_barras: data.codigo_barras,
        nombre: data.nombre,
        unidad_medida: data.unidad_medida,
        stock_total: totalStock,
        stocks: stockList,
      })
      // Auto-select primera bodega con stock
      if (stockList.length > 0) setBodegaSel(stockList[0].bodega_id)
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Error')
    } finally {
      setLoading(false)
    }
  }

  const handleScan = (codigo: string) => {
    if (loading || saving) return
    setScannerOn(false)
    setCodigoInput(codigo)
    buscarProducto(codigo)
  }

  const handleSubmit = async () => {
    if (!producto) return
    const qty = Number(cantidad)
    if (!qty || qty <= 0) {
      setErrorMsg('Cantidad debe ser mayor a cero')
      return
    }
    if (tipo === 'salida' && !bodegaSel) {
      setErrorMsg('Selecciona una bodega')
      return
    }
    if (tipo === 'entrada' && !bodegaSel) {
      setErrorMsg('Selecciona bodega destino')
      return
    }

    setSaving(true)
    setErrorMsg(null)
    setSuccessMsg(null)
    try {
      const delta = tipo === 'salida' ? -qty : qty
      const bodegaTarget = bodegaSel

      // Verificar stock
      const { data: actual } = await supabase
        .from('stock_bodega')
        .select('cantidad, costo_promedio')
        .eq('bodega_id', bodegaTarget)
        .eq('producto_id', producto.id)
        .maybeSingle()

      const stockActual = Number(actual?.cantidad ?? 0)
      const costoProm = Number(actual?.costo_promedio ?? 0)
      const nuevoStock = stockActual + delta

      if (nuevoStock < 0) {
        throw new Error(`Stock insuficiente (disponible ${stockActual})`)
      }

      // Crear movimiento
      const { error: movErr } = await supabase.from('movimientos_inventario').insert({
        bodega_id: bodegaTarget,
        producto_id: producto.id,
        tipo_movimiento: tipo === 'salida' ? 'salida_consumo' : 'entrada_compra',
        cantidad: qty,
        costo_unitario: costoProm,
        costo_total: qty * costoProm,
        observacion: `Scanner ${tipo}`,
      })
      if (movErr) throw movErr

      // Upsert stock
      const { error: stErr } = await supabase.from('stock_bodega').upsert(
        {
          bodega_id: bodegaTarget,
          producto_id: producto.id,
          cantidad: nuevoStock,
          costo_promedio: costoProm,
          ultimo_movimiento: new Date().toISOString(),
        },
        { onConflict: 'bodega_id,producto_id' },
      )
      if (stErr) throw stErr

      setSuccessMsg(`${tipo === 'salida' ? 'Salida' : 'Entrada'} registrada: ${qty} ${producto.unidad_medida} de ${producto.nombre}`)
      setHistorial((h) => [
        { codigo: producto.codigo, nombre: producto.nombre, cantidad: qty, tipo, ts: new Date().toLocaleTimeString('es-CL') },
        ...h,
      ].slice(0, 20))

      // Refrescar stocks
      await buscarProducto(codigoInput)
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Error')
    } finally {
      setSaving(false)
    }
  }

  // Submit al presionar Enter en el input
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Enter' && codigoInput && !loading && document.activeElement?.tagName === 'INPUT') {
        const el = document.activeElement as HTMLInputElement
        if (el.type === 'text') buscarProducto(codigoInput)
      }
    }
    window.addEventListener('keypress', onKey)
    return () => window.removeEventListener('keypress', onKey)
  }, [codigoInput, loading])

  return (
    <div className="space-y-4">
      <div className="rounded-2xl bg-gradient-to-r from-cyan-600 to-blue-600 p-5 text-white shadow-lg">
        <h1 className="text-xl font-bold flex items-center gap-2">
          <ScanBarcode className="h-6 w-6" />
          Pistola Inventario (Scanner)
        </h1>
        <p className="text-sm text-white/80 mt-1">
          Escanea un código de barras o escríbelo. Apto para pistolas USB (teclado) y cámara móvil.
        </p>
      </div>

      {/* Toggle Entrada / Salida */}
      <div className="flex gap-2">
        <Button
          variant={tipo === 'salida' ? 'primary' : 'secondary'}
          onClick={() => setTipo('salida')}
          className="flex-1"
        >
          <Minus className="h-4 w-4" />
          Salida / Rebajar
        </Button>
        <Button
          variant={tipo === 'entrada' ? 'primary' : 'secondary'}
          onClick={() => setTipo('entrada')}
          className="flex-1"
        >
          <Plus className="h-4 w-4" />
          Entrada / Ingresar
        </Button>
      </div>

      {/* Scanner cámara */}
      {scannerOn && (
        <BarcodeScanner active onScan={handleScan} onClose={() => setScannerOn(false)} />
      )}

      {/* Input código + cámara */}
      <Card>
        <CardContent className="p-3 space-y-2">
          <div className="flex gap-2">
            <Input
              autoFocus
              placeholder="Escanea o escribe código…"
              value={codigoInput}
              onChange={(e) => setCodigoInput(e.target.value)}
              className="flex-1 font-mono text-lg"
            />
            <Button variant="primary" onClick={() => buscarProducto(codigoInput)} loading={loading}>
              Buscar
            </Button>
            <Button variant="secondary" onClick={() => setScannerOn((v) => !v)}>
              <Camera className="h-4 w-4" />
              {scannerOn ? 'Cerrar' : 'Cámara'}
            </Button>
          </div>
          <p className="text-[11px] text-gray-500">
            La pistola USB emula un teclado + Enter. Si usas móvil, toca "Cámara".
          </p>
        </CardContent>
      </Card>

      {errorMsg && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          {errorMsg}
        </div>
      )}
      {successMsg && (
        <div className="rounded-lg border border-green-200 bg-green-50 p-3 text-sm text-green-700 flex items-center gap-2">
          <CheckCircle2 className="h-5 w-5" /> {successMsg}
        </div>
      )}

      {/* Producto encontrado */}
      {producto && (
        <Card className="border-blue-300">
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center justify-between">
              <span className="flex items-center gap-2">
                <Package className="h-5 w-5" />
                {producto.nombre}
              </span>
              <Badge className="bg-indigo-100 text-indigo-800">
                Stock total: {producto.stock_total} {producto.unidad_medida}
              </Badge>
            </CardTitle>
            <div className="text-xs text-gray-500 font-mono mt-1">
              {producto.codigo}
              {producto.codigo_barras && <span className="ml-2">· {producto.codigo_barras}</span>}
            </div>
          </CardHeader>
          <CardContent className="space-y-3">
            <div>
              <label className="text-xs font-medium text-gray-600">Bodega</label>
              <select
                className="h-10 w-full rounded border border-gray-300 px-2 text-sm"
                value={bodegaSel}
                onChange={(e) => setBodegaSel(e.target.value)}
              >
                <option value="">Seleccionar…</option>
                {producto.stocks.map((s) => (
                  <option key={s.bodega_id} value={s.bodega_id}>
                    {s.bodega} — stock: {s.cantidad} {producto.unidad_medida}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="text-xs font-medium text-gray-600">
                Cantidad a {tipo === 'salida' ? 'rebajar' : 'ingresar'} ({producto.unidad_medida})
              </label>
              <Input
                type="number" step="1" min="0.001"
                value={cantidad}
                onChange={(e) => setCantidad(e.target.value)}
              />
            </div>
            <Button
              variant="primary"
              size="lg"
              onClick={handleSubmit}
              loading={saving}
              className="w-full"
            >
              {tipo === 'salida' ? <Minus className="h-5 w-5" /> : <Plus className="h-5 w-5" />}
              Confirmar {tipo}
            </Button>
          </CardContent>
        </Card>
      )}

      {/* Historial de la sesión */}
      {historial.length > 0 && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Últimos movimientos en esta sesión</CardTitle>
          </CardHeader>
          <CardContent className="divide-y text-sm">
            {historial.map((h, i) => (
              <div key={i} className="flex items-center gap-2 py-1.5">
                {h.tipo === 'salida' ? <Minus className="h-4 w-4 text-red-600" /> : <Plus className="h-4 w-4 text-green-600" />}
                <span className="font-mono text-xs text-gray-500">{h.codigo}</span>
                <span className="flex-1 truncate">{h.nombre}</span>
                <span className={cn('font-semibold', h.tipo === 'salida' ? 'text-red-700' : 'text-green-700')}>
                  {h.tipo === 'salida' ? '−' : '+'}{h.cantidad}
                </span>
                <span className="text-[10px] text-gray-400">{h.ts}</span>
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      {/* Link a cargar maestro */}
      <div className="text-center text-xs text-gray-500">
        ¿Nuevo producto? <Link href="/dashboard/inventario/cargar-maestro" className="text-blue-600 hover:underline">Carga el maestro desde Excel</Link>
      </div>
    </div>
  )
}
