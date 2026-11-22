'use client'

// ============================================================================
// Scanner de bodega (rehecho 22-11-2026)
// ----------------------------------------------------------------------------
// Pistola (o cámara) → la lista se arma sola (el mismo código suma +1) →
// Salida (CECO + OT opcional, FIFO) o Entrada (proveedor + documento).
// Registra con las MISMAS funciones de la oficina (ver lib/services/bodega-scanner).
// Si el código no está en el catálogo, se asigna a un producto en el momento.
// ============================================================================
import { useEffect, useMemo, useRef, useState } from 'react'
import { ScanBarcode, Camera, Minus, Plus, Trash2, Link2, PackageMinus, PackagePlus } from 'lucide-react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { BarcodeScanner } from '@/components/ui/barcode-scanner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { useCECO, useOTsValidasSalida } from '@/hooks/use-bodega-salida-fifo'
import {
  getBodegasParaIngreso, buscarProveedores, registrarIngresoBodega,
  type DocTipo, type ProveedorBusqueda,
} from '@/lib/services/bodega-ingreso'
import {
  buscarPorCodigo, buscarParaAsignar, asignarCodigoBarras, stockEnBodega, registrarSalidaScanner,
  type ProductoScan,
} from '@/lib/services/bodega-scanner'
import { cn, errorMessage, todayISO } from '@/lib/utils'

type Modo = 'salida' | 'entrada'
type Linea = { p: ProductoScan; cantidad: number; costo: string }
const DOCS: Array<{ v: DocTipo; l: string }> = [
  { v: 'factura', l: 'Factura' }, { v: 'guia', l: 'Guía' }, { v: 'boleta', l: 'Boleta' }, { v: 'vale', l: 'Vale' }, { v: 'otro', l: 'Otro' },
]

export default function ScannerPage() {
  useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()
  const pistola = useRef<HTMLInputElement>(null)

  const [modo, setModo] = useState<Modo>('salida')
  const [bodegaId, setBodegaId] = useState('')
  const [codigo, setCodigo] = useState('')
  const [camara, setCamara] = useState(false)
  const [lineas, setLineas] = useState<Linea[]>([])
  const [buscando, setBuscando] = useState(false)
  const [desconocido, setDesconocido] = useState<string | null>(null)
  const [qAsignar, setQAsignar] = useState('')
  const [candidatos, setCandidatos] = useState<ProductoScan[]>([])
  const [guardando, setGuardando] = useState(false)
  // salida
  const [cecoId, setCecoId] = useState('')
  const [otId, setOtId] = useState('')
  const [motivo, setMotivo] = useState('')
  const [entregadoA, setEntregadoA] = useState('')
  // entrada
  const [qProv, setQProv] = useState('')
  const [proveedores, setProveedores] = useState<ProveedorBusqueda[]>([])
  const [proveedor, setProveedor] = useState<ProveedorBusqueda | null>(null)
  const [docTipo, setDocTipo] = useState<DocTipo>('factura')
  const [docNumero, setDocNumero] = useState('')
  const [docFecha, setDocFecha] = useState(todayISO())

  const { data: bodegas } = useQuery({ queryKey: ['scanner-bodegas'], queryFn: getBodegasParaIngreso, staleTime: 5 * 60_000 })
  const { data: cecos } = useCECO()
  const { data: ots } = useOTsValidasSalida()
  const ids = useMemo(() => lineas.map((l) => l.p.id), [lineas])
  const { data: stock } = useQuery({
    queryKey: ['scanner-stock', bodegaId, ids.join(',')],
    queryFn: () => stockEnBodega(bodegaId, ids),
    enabled: !!bodegaId && ids.length > 0,
  })

  useEffect(() => { try { const b = localStorage.getItem('scanner-bodega'); if (b) setBodegaId(b) } catch { /* */ } }, [])
  useEffect(() => { try { if (bodegaId) localStorage.setItem('scanner-bodega', bodegaId) } catch { /* */ } }, [bodegaId])
  const enfocar = () => setTimeout(() => pistola.current?.focus(), 50)

  const agregar = (p: ProductoScan) => {
    setLineas((ls) => {
      const i = ls.findIndex((l) => l.p.id === p.id)
      if (i >= 0) return ls.map((l, j) => (j === i ? { ...l, cantidad: l.cantidad + 1 } : l))
      return [{ p, cantidad: 1, costo: p.costo_unitario_actual ? String(p.costo_unitario_actual) : '' }, ...ls]
    })
  }

  const leer = async (raw: string) => {
    const c = raw.trim()
    setCodigo('')
    if (!c) return
    setBuscando(true)
    let volverAPistola = true
    try {
      const p = await buscarPorCodigo(c)
      if (p) { agregar(p); setDesconocido(null) } else {
        // Código desconocido: el cursor queda en el buscador para asignarlo
        // (antes volvía a la pistola y lo escrito caía ahí).
        setDesconocido(c); setQAsignar(''); setCandidatos([]); volverAPistola = false
      }
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo buscar el código'))
    } finally { setBuscando(false); if (volverAPistola) enfocar() }
  }

  useEffect(() => {
    if (!desconocido || qAsignar.trim().length < 2) { setCandidatos([]); return }
    const t = setTimeout(() => { buscarParaAsignar(qAsignar).then(setCandidatos).catch(() => setCandidatos([])) }, 300)
    return () => clearTimeout(t)
  }, [qAsignar, desconocido])

  useEffect(() => {
    if (qProv.trim().length < 2) { setProveedores([]); return }
    const t = setTimeout(() => { buscarProveedores(qProv).then(setProveedores).catch(() => setProveedores([])) }, 300)
    return () => clearTimeout(t)
  }, [qProv])

  const asignar = async (p: ProductoScan) => {
    if (!desconocido) return
    try {
      await asignarCodigoBarras(p.id, desconocido)
      toast.success(`Código ${desconocido} asignado a ${p.nombre}`)
      agregar({ ...p, codigo_barras: desconocido })
      setDesconocido(null)
      enfocar()
    } catch (e) { toast.error(errorMessage(e, 'No se pudo asignar el código')) }
  }

  const faltaStock = modo === 'salida' && !!stock && lineas.some((l) => (stock[l.p.id] ?? 0) < l.cantidad)
  const puede = !!bodegaId && lineas.length > 0 && !guardando && (modo === 'salida'
    ? !!cecoId && motivo.trim().length >= 5 && !faltaStock
    : !!proveedor && !!docNumero.trim())

  const registrar = async () => {
    if (!puede) return
    setGuardando(true)
    try {
      if (modo === 'salida') {
        const r = await registrarSalidaScanner({
          bodega_id: bodegaId, ceco_id: cecoId, ot_id: otId || null, motivo: motivo.trim(),
          entregado_a: entregadoA.trim() || null,
          items: lineas.map((l) => ({ producto_id: l.p.id, cantidad: l.cantidad, unidad: l.p.unidad_medida })),
        })
        toast.success(`Salida registrada${r.folio ? ` (${r.folio})` : ''}`)
      } else {
        const r = await registrarIngresoBodega({
          proveedor_id: proveedor!.id, bodega_id: bodegaId, doc_tipo: docTipo, doc_numero: docNumero.trim(),
          doc_fecha: docFecha || null,
          items: lineas.map((l) => ({
            producto_id: l.p.id, cantidad: l.cantidad, unidad: l.p.unidad_medida,
            costo_unitario: l.costo.trim() === '' ? null : Number(l.costo),
          })),
        })
        toast.success(`Entrada registrada (${r.folio})`)
      }
      setLineas([]); setMotivo(''); setEntregadoA(''); setDocNumero('')
      for (const k of ['stock-bodega', 'movimientos', 'bodega-reportes', 'valorizacion-total', 'bodega-salida', 'scanner-stock']) {
        qc.invalidateQueries({ queryKey: [k] })
      }
      enfocar()
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo registrar'))
    } finally { setGuardando(false) }
  }

  return (
    <div className="mx-auto max-w-3xl space-y-4 p-4">
      <div className="flex items-center gap-2">
        <ScanBarcode className="h-6 w-6 text-slate-700" />
        <h1 className="text-xl font-bold text-gray-900">Scanner de bodega</h1>
      </div>

      <Card>
        <CardContent className="space-y-3 pt-4">
          <div className="grid grid-cols-2 gap-2">
            {(['salida', 'entrada'] as Modo[]).map((m) => (
              <button key={m} type="button" onClick={() => { setModo(m); enfocar() }}
                className={cn('flex items-center justify-center gap-2 rounded-lg border py-2.5 text-sm font-semibold',
                  modo === m ? (m === 'salida' ? 'border-red-500 bg-red-50 text-red-700' : 'border-green-600 bg-green-50 text-green-700') : 'border-gray-200 text-gray-600')}>
                {m === 'salida' ? <PackageMinus className="h-4 w-4" /> : <PackagePlus className="h-4 w-4" />}
                {m === 'salida' ? 'Salida' : 'Entrada'}
              </button>
            ))}
          </div>
          <label className="block text-xs font-medium text-gray-600">Bodega
            <select value={bodegaId} onChange={(e) => setBodegaId(e.target.value)}
              className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm">
              <option value="">Elige la bodega…</option>
              {(bodegas ?? []).map((b) => <option key={b.id} value={b.id}>{b.codigo} · {b.nombre}</option>)}
            </select>
          </label>
          <form onSubmit={(e) => { e.preventDefault(); void leer(codigo) }} className="flex gap-2">
            <Input ref={pistola} autoFocus value={codigo} onChange={(e) => setCodigo(e.target.value)}
              placeholder="Pistolea o escribe el código y Enter" aria-label="Código" className="flex-1" />
            <Button type="button" variant="outline" onClick={() => setCamara((v) => !v)} aria-label="Cámara">
              <Camera className="h-4 w-4" />
            </Button>
          </form>
          {buscando && <p className="text-xs text-gray-500">Buscando…</p>}
          {camara && <BarcodeScanner active onScan={(c) => { setCamara(false); void leer(c) }} onClose={() => setCamara(false)} />}
        </CardContent>
      </Card>

      {desconocido && (
        <Card className="border-amber-300 bg-amber-50">
          <CardContent className="space-y-2 pt-4">
            <p className="text-sm font-semibold text-amber-900">El código {desconocido} no está en el catálogo</p>
            <p className="text-xs text-amber-800">Busca el producto y asígnaselo: la próxima vez se reconoce solo.</p>
            <Input value={qAsignar} onChange={(e) => setQAsignar(e.target.value)} placeholder="Nombre o código interno del producto" autoFocus />
            <ul className="max-h-56 divide-y overflow-auto rounded-lg border bg-white">
              {candidatos.map((p) => (
                <li key={p.id} className="flex items-center justify-between gap-2 px-3 py-2 text-sm">
                  <span className="min-w-0"><span className="font-medium">{p.nombre}</span> <span className="text-xs text-gray-500">{p.codigo}{p.codigo_barras ? ` · ya tiene ${p.codigo_barras}` : ''}</span></span>
                  <Button size="sm" onClick={() => void asignar(p)}><Link2 className="mr-1 h-3.5 w-3.5" /> Asignar</Button>
                </li>
              ))}
            </ul>
            <button type="button" onClick={() => { setDesconocido(null); enfocar() }} className="text-xs text-gray-600 underline">Cancelar</button>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader><CardTitle className="text-base">Lista ({lineas.length})</CardTitle></CardHeader>
        <CardContent>
          {lineas.length === 0 ? <p className="text-sm text-gray-500">Pistolea los productos: aparecen acá.</p> : (
            <ul className="divide-y">
              {lineas.map((l) => {
                const disp = stock?.[l.p.id]
                const corto = modo === 'salida' && disp !== undefined && disp < l.cantidad
                return (
                  <li key={l.p.id} className="flex flex-wrap items-center gap-2 py-2">
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium text-gray-900">{l.p.nombre}</p>
                      <p className={cn('text-xs', corto ? 'font-semibold text-red-600' : 'text-gray-500')}>
                        {l.p.codigo} · {l.p.unidad_medida}{bodegaId && modo === 'salida' ? ` · disponible ${disp ?? 0}` : ''}
                      </p>
                    </div>
                    {modo === 'entrada' && (
                      <Input value={l.costo} onChange={(e) => setLineas((ls) => ls.map((x) => (x.p.id === l.p.id ? { ...x, costo: e.target.value } : x)))}
                        inputMode="decimal" placeholder="$ unit." aria-label="Costo unitario" className="w-24" />
                    )}
                    <div className="flex items-center gap-1">
                      <Button size="sm" variant="outline" aria-label="Menos" onClick={() => setLineas((ls) => ls.map((x) => (x.p.id === l.p.id ? { ...x, cantidad: Math.max(1, x.cantidad - 1) } : x)))}><Minus className="h-3.5 w-3.5" /></Button>
                      <Input value={String(l.cantidad)} inputMode="decimal" aria-label="Cantidad" className="w-16 text-center"
                        onChange={(e) => { const n = Number(e.target.value.replace(',', '.')); if (!Number.isNaN(n)) setLineas((ls) => ls.map((x) => (x.p.id === l.p.id ? { ...x, cantidad: n } : x))) }} />
                      <Button size="sm" variant="outline" aria-label="Más" onClick={() => setLineas((ls) => ls.map((x) => (x.p.id === l.p.id ? { ...x, cantidad: x.cantidad + 1 } : x)))}><Plus className="h-3.5 w-3.5" /></Button>
                      <Button size="sm" variant="ghost" aria-label="Quitar" onClick={() => setLineas((ls) => ls.filter((x) => x.p.id !== l.p.id))}><Trash2 className="h-3.5 w-3.5 text-red-600" /></Button>
                    </div>
                  </li>
                )
              })}
            </ul>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardContent className="space-y-3 pt-4">
          {modo === 'salida' ? (
            <>
              <label className="block text-xs font-medium text-gray-600">Centro de costo *
                <select value={cecoId} onChange={(e) => setCecoId(e.target.value)} className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm">
                  <option value="">Elige el CECO…</option>
                  {(cecos ?? []).map((c) => <option key={c.id} value={c.id}>{c.codigo} · {c.nombre}</option>)}
                </select>
              </label>
              <label className="block text-xs font-medium text-gray-600">OT (opcional)
                <select value={otId} onChange={(e) => setOtId(e.target.value)} className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm">
                  <option value="">Sin OT (solo CECO)</option>
                  {(ots ?? []).map((o) => <option key={o.id} value={o.id}>{o.folio}{o.faena_nombre ? ` · ${o.faena_nombre}` : ''}</option>)}
                </select>
              </label>
              <Input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Motivo * (mínimo 5 letras)" />
              <Input value={entregadoA} onChange={(e) => setEntregadoA(e.target.value)} placeholder="Entregado a (opcional)" />
              {faltaStock && <p className="text-xs font-semibold text-red-600">Hay productos con menos stock que lo que se quiere sacar.</p>}
            </>
          ) : (
            <>
              <div>
                <Input value={proveedor ? `${proveedor.nombre}${proveedor.rut ? ` · ${proveedor.rut}` : ''}` : qProv}
                  onChange={(e) => { setProveedor(null); setQProv(e.target.value) }} placeholder="Proveedor * (nombre o RUT)" />
                {!proveedor && proveedores.length > 0 && (
                  <ul className="mt-1 max-h-48 divide-y overflow-auto rounded-lg border bg-white">
                    {proveedores.map((p) => (
                      <li key={p.id}><button type="button" onClick={() => { setProveedor(p); setProveedores([]) }} className="w-full px-3 py-2 text-left text-sm hover:bg-gray-50">{p.nombre} <span className="text-xs text-gray-500">{p.rut ?? ''}</span></button></li>
                    ))}
                  </ul>
                )}
              </div>
              <div className="grid grid-cols-3 gap-2">
                <select value={docTipo} onChange={(e) => setDocTipo(e.target.value as DocTipo)} aria-label="Tipo de documento" className="rounded-lg border border-gray-300 px-2 py-2 text-sm">
                  {DOCS.map((d) => <option key={d.v} value={d.v}>{d.l}</option>)}
                </select>
                <Input value={docNumero} onChange={(e) => setDocNumero(e.target.value)} placeholder="N° documento *" />
                <Input type="date" value={docFecha} max={todayISO()} onChange={(e) => setDocFecha(e.target.value)} aria-label="Fecha del documento" />
              </div>
              <p className="text-[11px] text-gray-500">Sin precio, la línea entra con costo provisional (se corrige al llegar la factura).</p>
            </>
          )}
          <Button className="w-full" disabled={!puede} onClick={() => void registrar()}>
            {guardando ? 'Registrando…' : modo === 'salida' ? `Registrar salida (${lineas.length})` : `Registrar entrada (${lineas.length})`}
          </Button>
          {!bodegaId && <p className="text-xs text-amber-700">Elige la bodega para registrar.</p>}
        </CardContent>
      </Card>
    </div>
  )
}
