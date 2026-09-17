'use client'

// ============================================================================
// Ingresar mercadería a bodega (MIG566)
// ----------------------------------------------------------------------------
// La orden de compra la emite un externo en Softland. El bodeguero recibe con
// la FACTURA (o la GUÍA) en la mano y lo único que necesita es que el stock
// suba. Antes tenía que crear o importar la OC en SICOM y "recepcionarla":
// dos recepciones en toda la vida del sistema.
//
// UNA SOLA PANTALLA, TRES PREGUNTAS
//   1. ¿De quién y con qué papel?  proveedor + factura/guía + N° + bodega
//   2. ¿Qué llegó?                 buscar producto → cantidad → costo
//   3. Ingresar a stock.           un botón; el folio REC-… queda abajo
//
// LO QUE PASA SOLO
//   · Guía sin precio: el costo queda provisional (último conocido o $1) y se
//     corrige en Costos FIFO cuando llega la factura.
//   · Si el taller tenía ese producto pedido y esperando compra, la cantidad
//     se le aplica al pedido y el jefe recibe la campanita de "llegó".
//   · La misma factura del mismo proveedor no entra dos veces.
// ============================================================================

import { useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  PackagePlus, Search, X, Plus, Loader2, CheckCircle2, AlertTriangle, Truck, Building2,
  FileText, Camera, ChevronDown, ChevronUp, ArrowLeft, Bell, Receipt,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { getCategoriasProducto } from '@/lib/services/producto-categorias'
import {
  buscarProveedores, crearProveedorRapido, buscarProductos, crearProductoRapido,
  getBodegasParaIngreso, getPendientesCompraPorProducto, subirEvidenciaIngreso,
  registrarIngresoBodega, getIngresosRecientes, rutValido, formatearRut,
  type ProveedorBusqueda, type ProductoBusqueda, type DocTipo, type IngresoResult,
} from '@/lib/services/bodega-ingreso'
import { cn, formatCLP } from '@/lib/utils'

const ROLES_INGRESO = ['administrador', 'subgerente_operaciones', 'jefe_mantenimiento', 'supervisor',
  'operador_abastecimiento', 'bodeguero']

const DOC_TIPOS: Array<{ v: DocTipo; t: string; hint: string }> = [
  { v: 'factura', t: 'Factura', hint: 'Con precios: el costo entra real' },
  { v: 'guia',    t: 'Guía de despacho', hint: 'Sin precios: el costo queda provisional hasta la factura' },
  { v: 'boleta',  t: 'Boleta', hint: '' },
  { v: 'otro',    t: 'Otro', hint: '' },
]

const BODEGA_KEY = 'sicom-ingreso-bodega'

type Linea = {
  key: string
  producto: ProductoBusqueda
  cantidad: string
  costo: string        // '' = sin precio
  lote: string
  vencimiento: string
  abierta: boolean
}

const hoy = () => new Date().toISOString().slice(0, 10)
const num = (s: string) => Number(String(s).replace(/\./g, '').replace(',', '.'))

function useDebounced(value: string, ms = 250) {
  const [v, setV] = useState(value)
  useEffect(() => { const t = setTimeout(() => setV(value), ms); return () => clearTimeout(t) }, [value, ms])
  return v
}

export default function IngresoBodegaPage() {
  const { perfil, loading } = useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()

  // ── Documento ──────────────────────────────────────────────────────────
  const [proveedor, setProveedor] = useState<ProveedorBusqueda | null>(null)
  const [buscarProv, setBuscarProv] = useState('')
  const [crearProv, setCrearProv] = useState(false)
  const [nuevoProvNombre, setNuevoProvNombre] = useState('')
  const [nuevoProvRut, setNuevoProvRut] = useState('')
  const [docTipo, setDocTipo] = useState<DocTipo>('factura')
  const [docNumero, setDocNumero] = useState('')
  const [docFecha, setDocFecha] = useState(hoy())
  const [ocSoftland, setOcSoftland] = useState('')
  const [bodegaId, setBodegaId] = useState('')
  const [evidencia, setEvidencia] = useState<File | null>(null)
  const [observacion, setObservacion] = useState('')

  // ── Productos ──────────────────────────────────────────────────────────
  const [buscarProd, setBuscarProd] = useState('')
  const [lineas, setLineas] = useState<Linea[]>([])
  const [crearProd, setCrearProd] = useState(false)
  const [nuevoProdNombre, setNuevoProdNombre] = useState('')
  const [nuevoProdCategoria, setNuevoProdCategoria] = useState('repuesto')
  const [nuevoProdUnidad, setNuevoProdUnidad] = useState('un')
  const [nuevoProdCodigo, setNuevoProdCodigo] = useState('')

  const [busy, setBusy] = useState(false)
  const [ultimo, setUltimo] = useState<IngresoResult | null>(null)
  const prodInputRef = useRef<HTMLInputElement>(null)

  const qProv = useDebounced(buscarProv)
  const qProd = useDebounced(buscarProd)

  const { data: bodegas = [] } = useQuery({ queryKey: ['bodegas-ingreso'], queryFn: getBodegasParaIngreso, staleTime: 600_000 })
  const { data: categorias = [] } = useQuery({
    queryKey: ['producto-categorias', 'activas'], queryFn: () => getCategoriasProducto(true), staleTime: 600_000,
  })
  const { data: provs = [], isFetching: buscandoProv } = useQuery({
    queryKey: ['prov-busqueda', qProv], queryFn: () => buscarProveedores(qProv), enabled: qProv.trim().length >= 2 && !proveedor,
  })
  const { data: prods = [], isFetching: buscandoProd } = useQuery({
    queryKey: ['prod-busqueda', qProd], queryFn: () => buscarProductos(qProd), enabled: qProd.trim().length >= 2,
  })
  const productoIds = useMemo(() => lineas.map((l) => l.producto.id), [lineas])
  const { data: pendientes = {} } = useQuery({
    queryKey: ['pendientes-compra', productoIds], queryFn: () => getPendientesCompraPorProducto(productoIds),
    enabled: productoIds.length > 0,
  })
  const { data: recientes = [], refetch: refetchRecientes } = useQuery({
    queryKey: ['ingresos-recientes'], queryFn: () => getIngresosRecientes(15), staleTime: 30_000,
  })

  // Bodega: la última usada, si no la de repuestos de la faena del usuario, si no la primera.
  useEffect(() => {
    if (bodegaId || bodegas.length === 0) return
    let guardada: string | null = null
    try { guardada = localStorage.getItem(BODEGA_KEY) } catch { /* sin storage */ }
    const porStorage = bodegas.find((b) => b.id === guardada)
    const deFaena = bodegas.find((b) => b.faena_id === perfil?.faena_id && b.tipo === 'fija')
    const repuestos = bodegas.find((b) => /repuestos/i.test(b.nombre))
    setBodegaId((porStorage ?? deFaena ?? repuestos ?? bodegas[0]).id)
  }, [bodegas, bodegaId, perfil?.faena_id])
  useEffect(() => { if (bodegaId) { try { localStorage.setItem(BODEGA_KEY, bodegaId) } catch { /* nada */ } } }, [bodegaId])

  const puede = !!perfil && ROLES_INGRESO.includes(perfil.rol)

  // ── Acciones ───────────────────────────────────────────────────────────
  const elegirProveedor = (p: ProveedorBusqueda) => { setProveedor(p); setBuscarProv(''); setCrearProv(false) }

  const crearProveedor = async () => {
    const rut = nuevoProvRut.trim()
    if (nuevoProvNombre.trim().length < 3) { toast.error('Escribe el nombre del proveedor'); return }
    if (rut && !rutValido(rut)) { toast.error('El RUT no cuadra (revisa el dígito verificador)'); return }
    setBusy(true)
    try {
      const r = await crearProveedorRapido(nuevoProvNombre.trim(), rut || null)
      setProveedor({ id: r.proveedor_id, codigo: r.codigo ?? '', nombre: nuevoProvNombre.trim().toUpperCase(), rut: rut ? formatearRut(rut) : null, tipo: 'otros' })
      toast.success(r.existia ? 'Ese proveedor ya existía: quedó seleccionado' : 'Proveedor creado')
      setCrearProv(false); setNuevoProvNombre(''); setNuevoProvRut('')
    } catch (e) { toast.error(e instanceof Error ? e.message : 'No se pudo crear el proveedor') }
    finally { setBusy(false) }
  }

  const agregarProducto = (p: ProductoBusqueda) => {
    setLineas((ls) => {
      const i = ls.findIndex((l) => l.producto.id === p.id)
      if (i >= 0) {
        const copia = [...ls]
        copia[i] = { ...copia[i], cantidad: String((num(copia[i].cantidad) || 0) + 1) }
        return copia
      }
      return [...ls, {
        key: `${p.id}-${Date.now()}`, producto: p, cantidad: '1',
        costo: p.costo_unitario_actual > 1 ? String(Math.round(p.costo_unitario_actual)) : '',
        lote: '', vencimiento: '', abierta: false,
      }]
    })
    setBuscarProd('')
    prodInputRef.current?.focus()
  }

  const crearProducto = async () => {
    if (nuevoProdNombre.trim().length < 3) { toast.error('Escribe el nombre del producto'); return }
    setBusy(true)
    try {
      const r = await crearProductoRapido(nuevoProdNombre.trim(), nuevoProdCategoria, nuevoProdUnidad.trim() || 'un', nuevoProdCodigo.trim() || null)
      agregarProducto({
        id: r.producto_id, codigo: r.codigo, codigo_barras: null, nombre: nuevoProdNombre.trim(),
        categoria: nuevoProdCategoria, unidad_medida: nuevoProdUnidad.trim() || 'un', costo_unitario_actual: 0, tiene_vencimiento: false,
      })
      qc.invalidateQueries({ queryKey: ['productos'] })
      toast.success(`Producto creado con código ${r.codigo}`)
      setCrearProd(false); setNuevoProdNombre(''); setNuevoProdCodigo('')
    } catch (e) { toast.error(e instanceof Error ? e.message : 'No se pudo crear el producto') }
    finally { setBusy(false) }
  }

  const setLinea = (key: string, patch: Partial<Linea>) =>
    setLineas((ls) => ls.map((l) => (l.key === key ? { ...l, ...patch } : l)))

  // ── Validación ─────────────────────────────────────────────────────────
  const total = lineas.reduce((s, l) => s + (num(l.cantidad) || 0) * (num(l.costo) || 0), 0)
  const sinPrecio = lineas.filter((l) => !(num(l.costo) > 0)).length
  const errores: string[] = []
  if (!proveedor) errores.push('Elige el proveedor')
  if (!docNumero.trim()) errores.push(`Escribe el N° de la ${docTipo === 'guia' ? 'guía' : docTipo}`)
  if (!bodegaId) errores.push('Elige la bodega')
  if (lineas.length === 0) errores.push('Agrega los productos que llegaron')
  for (const l of lineas) {
    if (!(num(l.cantidad) > 0)) errores.push(`Cantidad de "${l.producto.nombre.slice(0, 30)}" debe ser mayor a 0`)
  }
  if (docTipo === 'factura' && sinPrecio > 0) errores.push(`La factura trae precios: falta el costo en ${sinPrecio} línea(s)`)
  const listo = errores.length === 0 && puede

  const ingresar = async () => {
    if (!listo || !proveedor) return
    setBusy(true)
    try {
      let evidenciaUrl: string | null = null
      if (evidencia) evidenciaUrl = await subirEvidenciaIngreso(evidencia)
      const obs = [observacion.trim(), ocSoftland.trim() ? `OC Softland: ${ocSoftland.trim()}` : ''].filter(Boolean).join(' · ') || null
      const r = await registrarIngresoBodega({
        proveedor_id: proveedor.id, bodega_id: bodegaId, doc_tipo: docTipo, doc_numero: docNumero.trim(),
        doc_fecha: docFecha || null, evidencia_url: evidenciaUrl, observacion: obs,
        items: lineas.map((l) => ({
          producto_id: l.producto.id, cantidad: num(l.cantidad), costo_unitario: num(l.costo) > 0 ? num(l.costo) : null,
          unidad: l.producto.unidad_medida, lote: l.lote.trim() || null, vencimiento: l.vencimiento || null,
        })),
      })
      setUltimo(r)
      toast.success(`${r.folio}: ${r.items} producto(s) en stock`)
      // Listo para el siguiente papel: se conserva la bodega.
      setProveedor(null); setDocNumero(''); setDocFecha(hoy()); setOcSoftland(''); setEvidencia(null)
      setObservacion(''); setLineas([]); setBuscarProd('')
      refetchRecientes()
      qc.invalidateQueries({ queryKey: ['stock-bodega'] })
      qc.invalidateQueries({ queryKey: ['movimientos'] })
      qc.invalidateQueries({ queryKey: ['kardex'] })
      qc.invalidateQueries({ queryKey: ['bodega-oc'] })
      window.scrollTo({ top: 0, behavior: 'smooth' })
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'No se pudo ingresar')
    } finally { setBusy(false) }
  }

  if (loading) return <div className="flex justify-center py-16"><Loader2 className="h-6 w-6 animate-spin text-gray-400" /></div>

  return (
    <div className="mx-auto max-w-5xl space-y-4 p-4 md:p-6">
      <div className="flex flex-wrap items-center gap-2">
        <Link href="/dashboard/inventario" className="rounded-md border border-gray-300 p-1.5 text-gray-600 hover:bg-gray-50" aria-label="Volver">
          <ArrowLeft className="h-4 w-4" />
        </Link>
        <h1 className="flex items-center gap-2 text-xl font-bold text-gray-900">
          <PackagePlus className="h-6 w-6 text-emerald-700" /> Ingresar mercadería
        </h1>
        <span className="text-sm text-gray-500">Factura o guía en mano → stock. Sin orden de compra.</span>
      </div>

      {!puede && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
          Tu perfil ({perfil?.rol ?? 'sin rol'}) no puede ingresar mercadería. Lo hace bodega, abastecimiento o el jefe de taller.
        </div>
      )}

      {ultimo && (
        <div className="rounded-lg border border-emerald-300 bg-emerald-50 p-3 text-sm text-emerald-900">
          <div className="flex items-start gap-2">
            <CheckCircle2 className="mt-0.5 h-5 w-5 shrink-0 text-emerald-600" />
            <div className="min-w-0 flex-1">
              <div className="font-semibold">Ingreso {ultimo.folio} registrado: {ultimo.items} producto(s) ya están en stock.</div>
              {ultimo.items_costo_provisional > 0 && (
                <div className="mt-1 flex items-start gap-1 text-amber-800">
                  <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
                  <span>{ultimo.items_costo_provisional} línea(s) quedaron con <b>costo provisional</b> (documento sin precio).
                    Cuando llegue la factura, administración lo corrige en <Link href="/dashboard/inventario/costos-fifo" className="underline">Costos FIFO</Link>.</span>
                </div>
              )}
              {ultimo.solicitudes_atendidas.length > 0 && (
                <div className="mt-1 flex items-start gap-1">
                  <Bell className="mt-0.5 h-4 w-4 shrink-0 text-sky-700" />
                  <span>El taller estaba esperando esto: {ultimo.solicitudes_atendidas.map((s, i) => (
                    <span key={i}>{i > 0 && ', '}<b>{s.ot_folio ?? 'OT'}</b> ({s.descripcion})</span>
                  ))}. El jefe ya recibió el aviso para emitir el vale.</span>
                </div>
              )}
            </div>
            <button type="button" onClick={() => setUltimo(null)} className="text-emerald-700" aria-label="Cerrar"><X className="h-4 w-4" /></button>
          </div>
        </div>
      )}

      {/* ── 1. ¿De quién y con qué papel? ─────────────────────────────── */}
      <Card>
        <CardContent className="space-y-4 p-5">
          <div className="flex items-center gap-2 text-sm font-bold text-gray-900">
            <span className="flex h-6 w-6 items-center justify-center rounded-full bg-emerald-600 text-xs text-white">1</span>
            ¿De quién y con qué papel?
          </div>

          {/* Proveedor */}
          <div>
            <span className="text-sm font-semibold text-gray-800">Proveedor</span>
            {proveedor ? (
              <div className="mt-1 flex items-center gap-3 rounded-lg border-2 border-emerald-500 bg-emerald-50 px-3 py-2">
                <Building2 className="h-4 w-4 shrink-0 text-emerald-700" />
                <span className="min-w-0 flex-1 truncate font-bold text-gray-800">{proveedor.nombre}</span>
                <span className="text-xs text-gray-500">{proveedor.rut ?? proveedor.codigo}</span>
                <button type="button" onClick={() => setProveedor(null)} aria-label="Cambiar proveedor" className="text-gray-500 hover:text-gray-800">
                  <X className="h-4 w-4" />
                </button>
              </div>
            ) : (
              <div className="relative mt-1">
                <Search className="pointer-events-none absolute left-3 top-3 h-4 w-4 text-gray-400" />
                <Input value={buscarProv} onChange={(e) => { setBuscarProv(e.target.value); setCrearProv(false) }}
                       placeholder="Nombre o RUT del proveedor (como sale en la factura)" className="pl-9" autoFocus />
                {buscarProv.trim().length >= 2 && (
                  <div className="absolute z-20 mt-1 w-full overflow-hidden rounded-lg border border-gray-200 bg-white shadow-lg">
                    {buscandoProv && provs.length === 0 && <div className="p-3 text-xs text-gray-500">Buscando…</div>}
                    {provs.map((p) => (
                      <button key={p.id} type="button" onClick={() => elegirProveedor(p)}
                              className="flex w-full items-center gap-3 border-b border-gray-100 px-3 py-2 text-left hover:bg-emerald-50">
                        <span className="min-w-0 flex-1 truncate text-sm font-medium text-gray-800">{p.nombre}</span>
                        <span className="shrink-0 text-xs text-gray-500">{p.rut ?? p.codigo}</span>
                      </button>
                    ))}
                    {!buscandoProv && provs.length === 0 && (
                      <div className="p-3 text-xs text-gray-600">Ningún proveedor con “{buscarProv}”.</div>
                    )}
                    <button type="button" onClick={() => { setCrearProv(true); setNuevoProvNombre(buscarProv.trim()); setBuscarProv('') }}
                            className="flex w-full items-center gap-2 bg-gray-50 px-3 py-2 text-left text-xs font-semibold text-emerald-700 hover:bg-emerald-50">
                      <Plus className="h-3.5 w-3.5" /> No está: crear proveedor nuevo
                    </button>
                  </div>
                )}
              </div>
            )}
            {crearProv && !proveedor && (
              <div className="mt-2 grid gap-2 rounded-lg border border-dashed border-emerald-400 bg-emerald-50/50 p-3 md:grid-cols-[1fr_180px_auto]">
                <Input value={nuevoProvNombre} onChange={(e) => setNuevoProvNombre(e.target.value)} placeholder="Razón social (como en la factura)" />
                <Input value={nuevoProvRut} onChange={(e) => setNuevoProvRut(e.target.value)} placeholder="RUT 76.123.456-7"
                       className={cn(nuevoProvRut.trim() && !rutValido(nuevoProvRut) && 'border-red-400')} />
                <div className="flex gap-2">
                  <Button type="button" size="sm" onClick={crearProveedor} disabled={busy}>Crear</Button>
                  <Button type="button" size="sm" variant="outline" onClick={() => setCrearProv(false)}>Cancelar</Button>
                </div>
              </div>
            )}
          </div>

          {/* Documento */}
          <div className="grid gap-3 md:grid-cols-[auto_1fr_150px]">
            <div>
              <span className="text-sm font-semibold text-gray-800">Documento</span>
              <div className="mt-1 flex flex-wrap gap-1">
                {DOC_TIPOS.map((d) => (
                  <button key={d.v} type="button" onClick={() => setDocTipo(d.v)}
                          className={cn('rounded-full border px-3 py-1.5 text-xs font-semibold',
                            docTipo === d.v ? 'border-emerald-600 bg-emerald-600 text-white' : 'border-gray-300 bg-white text-gray-700 hover:bg-gray-50')}>
                    {d.t}
                  </button>
                ))}
              </div>
              {DOC_TIPOS.find((d) => d.v === docTipo)?.hint && (
                <div className="mt-1 text-[11px] text-gray-500">{DOC_TIPOS.find((d) => d.v === docTipo)?.hint}</div>
              )}
            </div>
            <label className="block">
              <span className="text-sm font-semibold text-gray-800">N° del documento</span>
              <Input value={docNumero} onChange={(e) => setDocNumero(e.target.value)} placeholder="ej: 145872" className="mt-1 font-mono" inputMode="numeric" />
            </label>
            <label className="block">
              <span className="text-sm font-semibold text-gray-800">Fecha</span>
              <Input type="date" value={docFecha} onChange={(e) => setDocFecha(e.target.value)} className="mt-1" max={hoy()} />
            </label>
          </div>

          <div className="grid gap-3 md:grid-cols-[1fr_200px_1fr]">
            <label className="block">
              <span className="text-sm font-semibold text-gray-800">Bodega que recibe</span>
              <select value={bodegaId} onChange={(e) => setBodegaId(e.target.value)}
                      className="mt-1 h-10 w-full rounded-md border border-gray-300 bg-white px-2 text-sm">
                {bodegas.map((b) => <option key={b.id} value={b.id}>{b.nombre}</option>)}
              </select>
            </label>
            <label className="block">
              <span className="text-sm font-semibold text-gray-800">N° OC Softland <span className="font-normal text-gray-500">— opcional</span></span>
              <Input value={ocSoftland} onChange={(e) => setOcSoftland(e.target.value)} placeholder="si la factura la trae" className="mt-1 font-mono" />
            </label>
            <label className="block">
              <span className="text-sm font-semibold text-gray-800">Foto del documento <span className="font-normal text-gray-500">— opcional</span></span>
              <div className="mt-1 flex items-center gap-2">
                <label className="flex h-10 flex-1 cursor-pointer items-center gap-2 rounded-md border border-dashed border-gray-300 px-3 text-sm text-gray-600 hover:bg-gray-50">
                  <Camera className="h-4 w-4" />
                  <span className="truncate">{evidencia ? evidencia.name : 'Sacar foto o subir PDF'}</span>
                  <input type="file" accept="image/*,application/pdf" capture="environment" className="hidden"
                         onChange={(e) => setEvidencia(e.target.files?.[0] ?? null)} />
                </label>
                {evidencia && <button type="button" onClick={() => setEvidencia(null)} aria-label="Quitar"><X className="h-4 w-4 text-gray-500" /></button>}
              </div>
            </label>
          </div>
        </CardContent>
      </Card>

      {/* ── 2. ¿Qué llegó? ──────────────────────────────────────────────── */}
      <Card>
        <CardContent className="space-y-3 p-5">
          <div className="flex items-center gap-2 text-sm font-bold text-gray-900">
            <span className="flex h-6 w-6 items-center justify-center rounded-full bg-emerald-600 text-xs text-white">2</span>
            ¿Qué llegó?
            <span className="ml-auto text-xs font-normal text-gray-500">{lineas.length} producto(s)</span>
          </div>

          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-3 h-4 w-4 text-gray-400" />
            <Input ref={prodInputRef} value={buscarProd} onChange={(e) => { setBuscarProd(e.target.value); setCrearProd(false) }}
                   placeholder="Buscar por nombre, código o código de barras (pistola)" className="pl-9"
                   onKeyDown={(e) => { if (e.key === 'Enter' && prods.length === 1) { e.preventDefault(); agregarProducto(prods[0]) } }} />
            {buscarProd.trim().length >= 2 && (
              <div className="absolute z-10 mt-1 max-h-80 w-full overflow-y-auto rounded-lg border border-gray-200 bg-white shadow-lg">
                {buscandoProd && prods.length === 0 && <div className="p-3 text-xs text-gray-500">Buscando…</div>}
                {prods.map((p) => (
                  <button key={p.id} type="button" onClick={() => agregarProducto(p)}
                          className="flex w-full items-center gap-3 border-b border-gray-100 px-3 py-2 text-left hover:bg-emerald-50">
                    <span className="w-24 shrink-0 truncate font-mono text-xs text-gray-500">{p.codigo}</span>
                    <span className="min-w-0 flex-1 truncate text-sm font-medium text-gray-800">{p.nombre}</span>
                    <span className="shrink-0 text-xs text-gray-500">{p.unidad_medida}{p.costo_unitario_actual > 1 ? ` · últ. ${formatCLP(p.costo_unitario_actual)}` : ''}</span>
                  </button>
                ))}
                {!buscandoProd && prods.length === 0 && <div className="p-3 text-xs text-gray-600">Nada con “{buscarProd}”.</div>}
                <button type="button" onClick={() => { setCrearProd(true); setNuevoProdNombre(buscarProd.trim()); setBuscarProd('') }}
                        className="flex w-full items-center gap-2 bg-gray-50 px-3 py-2 text-left text-xs font-semibold text-emerald-700 hover:bg-emerald-50">
                  <Plus className="h-3.5 w-3.5" /> No está en el catálogo: crear producto nuevo
                </button>
              </div>
            )}
          </div>

          {crearProd && (
            <div className="grid gap-2 rounded-lg border border-dashed border-emerald-400 bg-emerald-50/50 p-3 md:grid-cols-[1fr_170px_90px_120px_auto]">
              <Input value={nuevoProdNombre} onChange={(e) => setNuevoProdNombre(e.target.value)} placeholder="Nombre del producto" />
              <select value={nuevoProdCategoria} onChange={(e) => setNuevoProdCategoria(e.target.value)} className="h-10 rounded-md border border-gray-300 bg-white px-2 text-sm">
                {(categorias.length ? categorias : [{ codigo: 'repuesto', nombre: 'Repuesto', activo: true }]).map((c) => (
                  <option key={c.codigo} value={c.codigo}>{c.nombre}</option>
                ))}
              </select>
              <Input value={nuevoProdUnidad} onChange={(e) => setNuevoProdUnidad(e.target.value)} placeholder="un" />
              <Input value={nuevoProdCodigo} onChange={(e) => setNuevoProdCodigo(e.target.value)} placeholder="Código (opcional)" className="font-mono" />
              <div className="flex gap-2">
                <Button type="button" size="sm" onClick={crearProducto} disabled={busy}>Crear y agregar</Button>
                <Button type="button" size="sm" variant="outline" onClick={() => setCrearProd(false)}>Cancelar</Button>
              </div>
            </div>
          )}

          {lineas.length === 0 ? (
            <div className="rounded-lg border border-dashed border-gray-300 p-6 text-center text-sm text-gray-500">
              Busca el producto arriba y tócalo para agregarlo. Con pistola: escanea y Enter.
            </div>
          ) : (
            <div className="overflow-hidden rounded-lg border border-gray-200">
              <div className="hidden grid-cols-[1fr_110px_140px_120px_32px] gap-2 bg-gray-50 px-3 py-2 text-[11px] font-semibold uppercase tracking-wide text-gray-500 md:grid">
                <span>Producto</span><span>Cantidad</span><span>Costo unit. (neto)</span><span className="text-right">Subtotal</span><span />
              </div>
              {lineas.map((l) => {
                const pend = pendientes[l.producto.id] ?? 0
                const sub = (num(l.cantidad) || 0) * (num(l.costo) || 0)
                return (
                  <div key={l.key} className="border-t border-gray-100 px-3 py-2">
                    <div className="grid grid-cols-[1fr_auto] gap-2 md:grid-cols-[1fr_110px_140px_120px_32px] md:items-center">
                      <div className="min-w-0">
                        <div className="truncate text-sm font-medium text-gray-800">{l.producto.nombre}</div>
                        <div className="flex flex-wrap items-center gap-2 text-[11px] text-gray-500">
                          <span className="font-mono">{l.producto.codigo}</span>
                          <span>{l.producto.unidad_medida}</span>
                          {pend > 0 && (
                            <span className="inline-flex items-center gap-1 rounded-full bg-sky-100 px-2 py-0.5 font-semibold text-sky-800">
                              <Truck className="h-3 w-3" /> el taller espera {pend}
                            </span>
                          )}
                          <button type="button" onClick={() => setLinea(l.key, { abierta: !l.abierta })}
                                  className="inline-flex items-center gap-0.5 text-gray-500 hover:text-gray-800">
                            {l.abierta ? <ChevronUp className="h-3 w-3" /> : <ChevronDown className="h-3 w-3" />} lote / vencimiento
                          </button>
                        </div>
                      </div>
                      <button type="button" onClick={() => setLineas((ls) => ls.filter((x) => x.key !== l.key))}
                              className="text-gray-400 hover:text-red-600 md:order-last" aria-label="Quitar">
                        <X className="h-4 w-4" />
                      </button>
                      <Input value={l.cantidad} onChange={(e) => setLinea(l.key, { cantidad: e.target.value.replace(/[^\d.,]/g, '') })}
                             inputMode="decimal" className="h-9 text-right font-semibold" aria-label="Cantidad" />
                      <Input value={l.costo} onChange={(e) => setLinea(l.key, { costo: e.target.value.replace(/[^\d.,]/g, '') })}
                             inputMode="decimal" placeholder={docTipo === 'guia' ? 'sin precio' : '$'}
                             className={cn('h-9 text-right', docTipo === 'factura' && !(num(l.costo) > 0) && 'border-amber-400 bg-amber-50')}
                             aria-label="Costo unitario" />
                      <div className="text-right text-sm font-semibold tabular-nums text-gray-800">
                        {sub > 0 ? formatCLP(sub) : <span className="text-xs font-normal text-amber-700">provisional</span>}
                      </div>
                    </div>
                    {l.abierta && (
                      <div className="mt-2 grid gap-2 md:w-2/3 md:grid-cols-2">
                        <Input value={l.lote} onChange={(e) => setLinea(l.key, { lote: e.target.value })} placeholder="Lote (opcional)" className="h-9" />
                        <Input type="date" value={l.vencimiento} onChange={(e) => setLinea(l.key, { vencimiento: e.target.value })} className="h-9" />
                      </div>
                    )}
                  </div>
                )
              })}
              <div className="flex items-center justify-between border-t border-gray-200 bg-gray-50 px-3 py-2 text-sm">
                <span className="text-gray-600">{lineas.length} producto(s){sinPrecio > 0 && <span className="text-amber-700"> · {sinPrecio} sin precio</span>}</span>
                <span className="font-bold text-gray-900">Total neto {formatCLP(total)}</span>
              </div>
            </div>
          )}

          <label className="block">
            <span className="text-xs font-semibold text-gray-600">Observación <span className="font-normal text-gray-500">— opcional</span></span>
            <Input value={observacion} onChange={(e) => setObservacion(e.target.value)} placeholder="ej: llegó una caja abollada, se revisó conforme" className="mt-1" />
          </label>
        </CardContent>
      </Card>

      {/* ── 3. Ingresar ─────────────────────────────────────────────────── */}
      <div className="sticky bottom-0 z-30 -mx-4 border-t border-gray-200 bg-white/95 p-3 backdrop-blur md:-mx-6">
        <div className="mx-auto flex max-w-5xl items-center gap-3">
          <div className="min-w-0 flex-1 text-xs text-gray-600">
            {errores.length > 0 && puede ? (
              <span className="flex items-center gap-1 truncate"><AlertTriangle className="h-3.5 w-3.5 shrink-0 text-amber-600" />{errores[0]}</span>
            ) : listo ? (
              <span className="truncate">{proveedor?.nombre} · {DOC_TIPOS.find((d) => d.v === docTipo)?.t} {docNumero} · {lineas.length} producto(s) · {formatCLP(total)}</span>
            ) : null}
          </div>
          <Button type="button" onClick={ingresar} disabled={!listo || busy} size="lg" className="bg-emerald-600 hover:bg-emerald-700">
            {busy ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <PackagePlus className="mr-2 h-4 w-4" />}
            Ingresar a stock
          </Button>
        </div>
      </div>

      {/* ── Últimos ingresos ────────────────────────────────────────────── */}
      <Card>
        <CardContent className="p-5">
          <div className="mb-3 flex items-center gap-2 text-sm font-bold text-gray-900">
            <Receipt className="h-4 w-4 text-gray-500" /> Últimos ingresos
          </div>
          {recientes.length === 0 ? (
            <div className="text-sm text-gray-500">Todavía no hay ingresos.</div>
          ) : (
            <div className="divide-y divide-gray-100">
              {recientes.map((r) => {
                const total = r.items.reduce((s, it) => s + Number(it.cantidad_recibida) * Number(it.costo_unitario_clp), 0)
                const fecha = new Date(r.created_at).toLocaleString('es-CL', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
                return (
                  <div key={r.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 py-2 text-sm">
                    <span className="font-mono text-xs font-semibold text-gray-700">{r.folio_recepcion}</span>
                    <span className="text-xs text-gray-500">{fecha}</span>
                    <span className="min-w-0 flex-1 truncate font-medium text-gray-800">{r.proveedor?.nombre ?? '—'}</span>
                    <span className="inline-flex items-center gap-1 text-xs text-gray-600">
                      <FileText className="h-3 w-3" /> {r.documento_proveedor_tipo} {r.documento_proveedor_numero}
                    </span>
                    <span className="text-xs text-gray-500">{r.bodega?.codigo}</span>
                    <span className="text-xs text-gray-600">{r.items.length} ítem(s)</span>
                    <span className="w-24 text-right font-semibold tabular-nums text-gray-800">{formatCLP(total)}</span>
                    {r.evidencia_url && <a href={r.evidencia_url} target="_blank" rel="noreferrer" className="text-xs text-sky-700 underline">doc</a>}
                  </div>
                )
              })}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
