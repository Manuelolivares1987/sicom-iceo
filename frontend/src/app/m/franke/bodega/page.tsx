'use client'

// ============================================================================
// Bodega de faena Franke con lector — funciona sin señal (MIG692 + MIG694)
// ----------------------------------------------------------------------------
// El lector físico («pistola») teclea el código de la etiqueta y un Enter. El
// campo está siempre enfocado: se dispara, aparece el producto; se vuelve a
// disparar el mismo y suma 1. Así se trabaja con una mano.
//
// SIN SEÑAL: el teléfono guarda el catálogo completo (maestro + stock + equipos)
// y la búsqueda es local. Lo que se registra queda en cola y sube solo al volver
// la señal (sincronizador del layout). El stock que se ve ya descuenta lo que
// está en la cola. Igual que la pauta del mecánico.
//
//   Sacar   → repuesto/filtro/lubricante exige camión; agua/EPP va a la operación.
//   Recibir → primero los envíos de Coquimbo en camino (se confirman, MIG712);
//             lo demás (compra local) con el lector.
//   El mecánico (MIG712) solo ve «Sacar».
//   Contar  → inventario físico; lo aprueba administración.
// ============================================================================

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import {
  AlertTriangle, ArrowDownToLine, ArrowUpFromLine, ChevronLeft, ClipboardCheck, CloudOff, Download, Minus, Plus, ScanBarcode, Trash2, XCircle,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { useNetworkStatus } from '@/hooks/use-calama-offline'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { cn, errorMessage } from '@/lib/utils'
import { CATEGORIAS_NUEVO, buscarProducto, crearProductoFaena, nuevoUuid, type ProductoLector } from '@/lib/services/bodega-faena'
import {
  ajustePendiente, buscarEnCatalogo, descartarOperacion, getCatalogo, guardarOperacion, pendientesBodega,
  type Catalogo, type OperacionPendiente, type TipoOperacion,
} from '@/lib/offline/bodega-faena-offline'
import { EnviosPorRecibir } from '@/components/bodega/envios-por-recibir'

type Modo = 'sacar' | 'recibir' | 'contar'
type Linea = ProductoLector & { cantidad: number }

const MODOS: { id: Modo; tipo: TipoOperacion; texto: string; icono: typeof Plus; color: string }[] = [
  { id: 'sacar', tipo: 'salida', texto: 'Sacar', icono: ArrowUpFromLine, color: 'bg-red-700' },
  { id: 'recibir', tipo: 'ingreso', texto: 'Recibir', icono: ArrowDownToLine, color: 'bg-emerald-700' },
  { id: 'contar', tipo: 'conteo', texto: 'Contar', icono: ClipboardCheck, color: 'bg-blue-700' },
]
const fmt = (n: number | null | undefined) => (n == null ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 2 }))
const hace = (iso: string | null | undefined) => {
  if (!iso) return 'nunca'
  const min = Math.round((Date.now() - new Date(iso).getTime()) / 60000)
  return min < 1 ? 'recién' : min < 60 ? `hace ${min} min` : min < 1440 ? `hace ${Math.round(min / 60)} h` : `hace ${Math.round(min / 1440)} d`
}

export default function BodegaFrankePage() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const online = useNetworkStatus()
  const toast = useToast()
  const lector = useRef<HTMLInputElement>(null)
  const [cat, setCat] = useState<Catalogo | null>(null)
  const [catFecha, setCatFecha] = useState<string | null>(null)
  const [cargando, setCargando] = useState(true)
  const [cola, setCola] = useState<OperacionPendiente[]>([])
  const [modo, setModo] = useState<Modo>('sacar')
  const [codigo, setCodigo] = useState('')
  const [lineas, setLineas] = useState<Linea[]>([])
  const [opciones, setOpciones] = useState<ProductoLector[]>([])
  const [guardando, setGuardando] = useState(false)
  const [equipo, setEquipo] = useState('')
  const [motivo, setMotivo] = useState('')
  const [entregadoA, setEntregadoA] = useState('')
  const [origen, setOrigen] = useState('Compra local')
  const [documento, setDocumento] = useState('')
  const [completo, setCompleto] = useState(false)
  const [uuid, setUuid] = useState(nuevoUuid)
  const [nuevo, setNuevo] = useState<{ nombre: string; categoria: string; unidad: string } | null>(null)

  const refrescarCola = useCallback(async () => { try { setCola(await pendientesBodega()) } catch { /* sin IndexedDB */ } }, [])
  const cargarCatalogo = useCallback(async (forzar = false) => {
    try {
      const c = await getCatalogo(undefined, forzar)
      setCat(c); setCatFecha(c?.generado_at ?? null)
    } catch (e) { toast.error(errorMessage(e)) } finally { setCargando(false) }
  }, [toast])

  useEffect(() => { void cargarCatalogo(); void refrescarCola() }, [cargarCatalogo, refrescarCola])
  // La cola la vacía el sincronizador del layout: se mira seguido para reflejarlo.
  useEffect(() => { const t = setInterval(() => void refrescarCola(), 8000); return () => clearInterval(t) }, [refrescarCola])
  useEffect(() => { if (online) void cargarCatalogo() }, [online, cargarCatalogo])

  const enfocar = useCallback(() => setTimeout(() => lector.current?.focus(), 30), [])
  useEffect(() => { enfocar() }, [modo, enfocar])

  const ajuste = useMemo(() => ajustePendiente(cola), [cola])
  const stockDe = useCallback((p: ProductoLector) => Number(p.stock) + (ajuste.get(p.producto_id) ?? 0), [ajuste])
  const bajoMinimo = useMemo(() => (cat?.productos ?? []).filter((p) => (p.minimo ?? 0) > 0 && stockDe(p) <= (p.minimo ?? 0)), [cat, stockDe])
  const rechazadas = cola.filter((c) => c.sync_status === 'rechazada')
  const enCola = cola.filter((c) => c.sync_status === 'pending')

  const agregar = useCallback((p: ProductoLector) => {
    setLineas((ls) => {
      const i = ls.findIndex((l) => l.producto_id === p.producto_id)
      if (i >= 0) return ls.map((l, j) => (j === i ? { ...l, cantidad: l.cantidad + 1 } : l))
      return [{ ...p, cantidad: 1 }, ...ls]
    })
    setOpciones([]); setCodigo(''); enfocar()
  }, [enfocar])

  async function alLeer(e: React.FormEvent) {
    e.preventDefault()
    const t = codigo.trim()
    if (!t || !cat) return
    let r = buscarEnCatalogo(cat, t)
    // Producto creado hace un rato en otro teléfono: con señal se pregunta al servidor.
    if (r.length === 0 && online) { try { r = await buscarProducto(cat.bodega_id, t) } catch { /* sigue vacío */ } }
    const exacto = r.find((p) => p.exacto)
    if (exacto) agregar(exacto)
    else if (r.length === 1) agregar(r[0])
    else if (r.length === 0) { toast.error(`No encuentro «${t}». Búsquelo por nombre${online ? ' o créelo' : ''}.`); setCodigo(''); enfocar() }
    else setOpciones(r)
  }

  // [MIG712] catálogos guardados antes de MIG712 no traen puede_sacar
  const puedeSacar = !!cat && (cat.puede_sacar ?? cat.puede_operar)
  const modosVisibles = cat && !cat.puede_operar ? MODOS.filter((m) => m.id === 'sacar') : MODOS
  const exigeEquipo = lineas.some((l) => l.exige_equipo)
  const faltaStock = modo === 'sacar' ? lineas.filter((l) => l.cantidad > stockDe(l)) : []
  const modoInfo = MODOS.find((m) => m.id === modo)!

  async function guardar() {
    if (!cat || lineas.length === 0) return
    if (lineas.some((l) => !(l.cantidad > 0) && modo !== 'contar')) { toast.error('Hay cantidades en 0.'); return }
    if (modo === 'sacar' && exigeEquipo && !equipo) { toast.error('Hay repuestos en la lista: elija el camión o equipo.'); return }
    if (modo === 'sacar' && faltaStock.length) { toast.error(`No alcanza el stock de ${faltaStock[0].nombre}.`); return }
    if (modo === 'recibir' && origen.trim().length < 3) { toast.error('Indique de dónde viene.'); return }
    setGuardando(true)
    try {
      const r = await guardarOperacion({
        local_id: uuid, tipo: modoInfo.tipo, bodega_id: cat.bodega_id,
        items: lineas.map((l) => ({ producto_id: l.producto_id, cantidad: l.cantidad, nombre: l.nombre })),
        activo_id: equipo || null, motivo, entregado_a: entregadoA, origen, documento, completo,
      })
      if (r.rechazo) toast.error(`No se guardó: ${r.rechazo}`)
      else if (r.enviado) toast.success(modo === 'contar' ? 'Conteo enviado: queda para aprobación.' : `${modoInfo.texto}: registrado.`)
      else toast.success('Guardado en el teléfono. Sube solo cuando vuelva la señal.')
      if (!r.rechazo) {
        setLineas([]); setMotivo(''); setEntregadoA(''); setDocumento(''); setUuid(nuevoUuid())
      }
      await refrescarCola()
      if (r.enviado) void cargarCatalogo(true)
    } catch (err) { toast.error(errorMessage(err)) } finally { setGuardando(false); enfocar() }
  }

  async function crearNuevo() {
    if (!cat || !nuevo) return
    try {
      const r = await crearProductoFaena(cat.bodega_id, nuevo.nombre, nuevo.categoria, nuevo.unidad)
      toast.success(`Creado ${r.codigo}. Imprima su etiqueta desde el panel de bodega.`)
      const [p] = await buscarProducto(cat.bodega_id, r.codigo)
      if (p) agregar(p)
      setNuevo(null)
      void cargarCatalogo(true)
    } catch (err) { toast.error(errorMessage(err)) }
  }

  if (verificando) return <div className="flex min-h-screen items-center justify-center"><Spinner className="h-8 w-8" /></div>
  if (sinSesionOffline) return <SinSesionOffline />

  return (
    <div className="min-h-screen bg-gray-50 pb-28">
      <header className="border-b bg-white px-4 pb-3 pt-[max(1rem,env(safe-area-inset-top))]">
        <Link href="/m/franke" className="mb-1 inline-flex items-center gap-1 text-xs text-gray-500"><ChevronLeft className="h-3.5 w-3.5" /> Franke</Link>
        <div className="flex items-start justify-between gap-2">
          <div>
            <p className="text-lg font-bold text-gray-900">Bodega de faena</p>
            <p className="text-xs text-gray-500">Agua, repuestos y EPP · use el lector sobre la etiqueta</p>
          </div>
          {!online && <span className="flex items-center gap-1 rounded-full bg-amber-100 px-2 py-1 text-xs font-semibold text-amber-900"><CloudOff className="h-3.5 w-3.5" /> Sin señal</span>}
        </div>
        <div className="mt-2 flex items-center justify-between text-[11px] text-gray-500">
          <span>Catálogo guardado {hace(catFecha)}{cat ? ` · ${cat.productos.length} productos` : ''}</span>
          <button onClick={() => void cargarCatalogo(true)} disabled={!online} className="flex items-center gap-1 font-medium text-gray-700 disabled:opacity-40">
            <Download className="h-3.5 w-3.5" /> Actualizar
          </button>
        </div>
      </header>

      {cargando && <div className="flex justify-center py-10"><Spinner className="h-7 w-7" /></div>}
      {!cargando && !cat && (
        <p className="m-4 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          Este teléfono todavía no tiene el catálogo de la bodega. Ábralo una vez con señal para descargarlo.
        </p>
      )}

      {cat && (<>
        {enCola.length > 0 && (
          <p className="mx-4 mt-3 rounded-xl border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900">
            {enCola.length} registro{enCola.length === 1 ? '' : 's'} guardado{enCola.length === 1 ? '' : 's'} en el teléfono, esperando señal. El stock que ve ya los descuenta.
          </p>
        )}
        {rechazadas.map((r) => (
          <div key={r.local_id} className="mx-4 mt-3 rounded-xl border border-red-300 bg-red-50 p-3 text-sm text-red-900">
            <p className="flex items-center gap-1.5 font-semibold"><XCircle className="h-4 w-4" /> No se pudo subir: {r.tipo} de {new Date(r.created_at).toLocaleString('es-CL', { dateStyle: 'short', timeStyle: 'short' })}</p>
            <p className="mt-0.5 text-xs">{r.items.map((i) => `${i.nombre} × ${fmt(i.cantidad)}`).join(' · ')}</p>
            <p className="mt-1 text-xs"><b>Motivo:</b> {r.ultimo_error}</p>
            <button onClick={async () => { await descartarOperacion(r.local_id); await refrescarCola() }}
                    className="mt-2 rounded-lg border border-red-300 bg-white px-3 py-1 text-xs font-medium">Descartar (registrarlo de nuevo bien)</button>
          </div>
        ))}

        {bajoMinimo.length > 0 && (
          <div className="mx-4 mt-3 rounded-xl border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
            <p className="flex items-center gap-1.5 font-semibold"><AlertTriangle className="h-4 w-4" /> {bajoMinimo.length} bajo el mínimo</p>
            <p className="mt-0.5 text-xs">{bajoMinimo.slice(0, 4).map((a) => `${a.nombre} (${fmt(stockDe(a))})`).join(' · ')}{bajoMinimo.length > 4 ? '…' : ''}</p>
          </div>
        )}

        {!puedeSacar && (
          <p className="mx-4 mt-3 rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-800">
            Su usuario puede ver la bodega pero no sacar de ella. Pida al administrador que lo agregue como responsable.
          </p>
        )}
        {cat && !cat.puede_operar && puedeSacar && (
          <p className="mx-4 mt-3 rounded-xl border border-gray-200 bg-white p-3 text-xs text-gray-600">
            Usted saca repuestos y filtros para su camión. Recibir y contar lo hace el supervisor de turno.
          </p>
        )}
        <div className={cn('mx-4 mt-3 grid gap-2', modosVisibles.length === 1 ? 'grid-cols-1' : 'grid-cols-3')}>
          {modosVisibles.map((m) => (
            <button key={m.id} onClick={() => { setModo(m.id); setLineas([]); setUuid(nuevoUuid()) }}
                    className={cn('flex flex-col items-center gap-1 rounded-xl border-2 py-3 text-sm font-semibold',
                      modo === m.id ? `${m.color} border-transparent text-white` : 'border-gray-200 bg-white text-gray-700')}>
              <m.icono className="h-5 w-5" />{m.texto}
            </button>
          ))}
        </div>

        {modo === 'recibir' && cat.puede_operar && (
          <EnviosPorRecibir bodegaId={cat.bodega_id} online={online} onRecibido={() => void cargarCatalogo(true)} />
        )}

        <form onSubmit={alLeer} className="mx-4 mt-3">
          <label className="flex items-center gap-2 rounded-xl border-2 border-gray-900 bg-white px-3 py-3 focus-within:ring-2 focus-within:ring-gray-900">
            <ScanBarcode className="h-5 w-5 shrink-0 text-gray-700" />
            <input ref={lector} value={codigo} onChange={(e) => setCodigo(e.target.value)} autoFocus
                   autoComplete="off" autoCapitalize="characters" spellCheck={false} inputMode="text"
                   placeholder="Dispare el lector o escriba código / nombre" className="w-full bg-transparent text-base outline-none" />
          </label>
        </form>

        {opciones.length > 0 && (
          <ul className="mx-4 mt-2 divide-y overflow-hidden rounded-xl border bg-white">
            {opciones.map((p) => (
              <li key={p.producto_id}>
                <button onClick={() => agregar(p)} className="flex w-full items-center justify-between gap-2 px-3 py-2.5 text-left text-sm hover:bg-gray-50">
                  <span><b>{p.nombre}</b><span className="block text-xs text-gray-500">{p.codigo}</span></span>
                  <span className="shrink-0 text-xs text-gray-500">hay {fmt(stockDe(p))}</span>
                </button>
              </li>
            ))}
          </ul>
        )}

        <section className="mx-4 mt-3 space-y-2">
          {lineas.length === 0 && (
            <p className="rounded-xl border border-dashed border-gray-300 bg-white p-6 text-center text-sm text-gray-500">
              {modo === 'contar' ? 'Escanee cada producto y anote cuánto hay físicamente.' : 'Escanee los productos. Cada disparo del mismo suma 1.'}
            </p>
          )}
          {lineas.map((l) => (
            <div key={l.producto_id} className={cn('rounded-xl border bg-white p-3', modo === 'sacar' && l.cantidad > stockDe(l) && 'border-red-400')}>
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="truncate text-sm font-semibold text-gray-900">{l.nombre}</p>
                  <p className="text-xs text-gray-500">{l.codigo} · hay {fmt(stockDe(l))} {l.unidad}{l.exige_equipo ? ' · repuesto' : ''}</p>
                </div>
                <button onClick={() => setLineas((ls) => ls.filter((x) => x.producto_id !== l.producto_id))} className="text-gray-400" aria-label="Quitar">
                  <Trash2 className="h-4 w-4" />
                </button>
              </div>
              <div className="mt-2 flex items-center gap-2">
                <button onClick={() => setLineas((ls) => ls.map((x) => x.producto_id === l.producto_id ? { ...x, cantidad: Math.max(0, x.cantidad - 1) } : x))}
                        className="grid h-10 w-10 place-items-center rounded-lg border" aria-label="Menos"><Minus className="h-4 w-4" /></button>
                <input type="number" inputMode="decimal" min={0} step="any" value={l.cantidad}
                       onChange={(e) => setLineas((ls) => ls.map((x) => x.producto_id === l.producto_id ? { ...x, cantidad: Number(e.target.value) } : x))}
                       className="h-10 w-24 rounded-lg border text-center text-base font-semibold" />
                <button onClick={() => setLineas((ls) => ls.map((x) => x.producto_id === l.producto_id ? { ...x, cantidad: x.cantidad + 1 } : x))}
                        className="grid h-10 w-10 place-items-center rounded-lg border" aria-label="Más"><Plus className="h-4 w-4" /></button>
                <span className="text-xs text-gray-500">{l.unidad}</span>
              </div>
            </div>
          ))}
        </section>

        {lineas.length > 0 && (
          <section className="mx-4 mt-3 space-y-2 rounded-xl border bg-white p-3">
            {modo === 'sacar' && (<>
              <label className="block text-sm">
                <span className="font-medium text-gray-700">Camión o equipo {exigeEquipo ? '(obligatorio: hay repuestos)' : '(opcional: agua/EPP van a la operación)'}</span>
                <select value={equipo} onChange={(e) => setEquipo(e.target.value)} className="mt-1 w-full rounded-lg border px-3 py-2.5">
                  <option value="">{exigeEquipo ? 'Elegir…' : 'Operación Franke (uso general)'}</option>
                  {cat.equipos.map((e) => <option key={e.id} value={e.id}>{e.patente} · {e.tipo.replace('_', ' ')}</option>)}
                </select>
              </label>
              <input value={entregadoA} onChange={(e) => setEntregadoA(e.target.value)} placeholder="Entregado a (nombre)" className="w-full rounded-lg border px-3 py-2.5 text-sm" />
              <input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Motivo (ej. cambio de filtro, consumo turno A)" className="w-full rounded-lg border px-3 py-2.5 text-sm" />
            </>)}
            {modo === 'recibir' && (<>
              <input value={origen} onChange={(e) => setOrigen(e.target.value)} placeholder="De dónde viene" className="w-full rounded-lg border px-3 py-2.5 text-sm" />
              <input value={documento} onChange={(e) => setDocumento(e.target.value)} placeholder="N° guía o factura (opcional)" className="w-full rounded-lg border px-3 py-2.5 text-sm" />
            </>)}
            {modo === 'contar' && (<>
              <label className="flex items-start gap-2 text-sm">
                <input type="checkbox" checked={completo} onChange={(e) => setCompleto(e.target.checked)} className="mt-1" />
                <span><b>Inventario completo de la bodega.</b> Lo que NO se escaneó se cuenta como 0. Déjelo sin marcar para contar solo algunos productos.</span>
              </label>
              <input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Observación (opcional)" className="w-full rounded-lg border px-3 py-2.5 text-sm" />
            </>)}
          </section>
        )}

        <section className="mx-4 mt-3">
          {!online ? (
            <p className="text-xs text-gray-400">Crear productos nuevos requiere señal.</p>
          ) : !nuevo ? (
            <button onClick={() => setNuevo({ nombre: '', categoria: 'ferreteria', unidad: 'un' })} className="text-xs font-medium text-gray-500 underline">
              ¿El producto no existe en el sistema? Crearlo
            </button>
          ) : (
            <div className="space-y-2 rounded-xl border bg-white p-3 text-sm">
              <p className="font-semibold">Producto nuevo</p>
              <input value={nuevo.nombre} onChange={(e) => setNuevo({ ...nuevo, nombre: e.target.value })} placeholder="Nombre (ej. BIDÓN AGUA PURIFICADA 20 L)" className="w-full rounded-lg border px-3 py-2" />
              <div className="flex gap-2">
                <select value={nuevo.categoria} onChange={(e) => setNuevo({ ...nuevo, categoria: e.target.value })} className="flex-1 rounded-lg border px-2 py-2">
                  {CATEGORIAS_NUEVO.map((c) => <option key={c.valor} value={c.valor}>{c.texto}</option>)}
                </select>
                <input value={nuevo.unidad} onChange={(e) => setNuevo({ ...nuevo, unidad: e.target.value })} className="w-20 rounded-lg border px-2 py-2" placeholder="un" />
              </div>
              <div className="flex gap-2">
                <button onClick={crearNuevo} className="flex-1 rounded-lg bg-gray-900 py-2 font-semibold text-white">Crear</button>
                <button onClick={() => setNuevo(null)} className="rounded-lg border px-3 py-2">Cancelar</button>
              </div>
            </div>
          )}
        </section>
      </>)}

      {lineas.length > 0 && (
        <div className="fixed inset-x-0 bottom-0 mx-auto max-w-[480px] border-t bg-white p-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
          <button onClick={guardar} disabled={guardando} className={cn('w-full rounded-xl py-3.5 text-base font-bold text-white disabled:opacity-50', modoInfo.color)}>
            {guardando ? 'Guardando…' : `${modoInfo.texto} ${lineas.length} producto${lineas.length === 1 ? '' : 's'}${online ? '' : ' (sin señal)'}`}
          </button>
        </div>
      )}
    </div>
  )
}
