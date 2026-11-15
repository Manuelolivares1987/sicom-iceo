'use client'

// ============================================================================
// Bodega de faena Franke con lector (MIG692)
// ----------------------------------------------------------------------------
// El lector físico («pistola») teclea el código de la etiqueta y un Enter. Este
// campo está siempre enfocado: se dispara, aparece el producto en la lista, se
// vuelve a disparar el mismo y suma 1. Así se trabaja con una mano.
//
// Tres modos sobre la misma lista:
//   Sacar   → repuesto/filtro/lubricante exige camión; agua/EPP va a la operación.
//   Recibir → lo que llega (envío desde Coquimbo, compra local).
//   Contar  → inventario físico; queda para aprobación de bodega/administración.
// Las alertas de stock bajo las dispara la base al guardar (no esta pantalla).
// ============================================================================

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  AlertTriangle, ArrowDownToLine, ArrowUpFromLine, ChevronLeft, ClipboardCheck, Minus, Plus, ScanBarcode, Trash2,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { cn, errorMessage } from '@/lib/utils'
import {
  BODEGA_FRANKE, CATEGORIAS_NUEVO, buscarProducto, crearProductoFaena, getBodegaPorCodigo, getPanelBodega, nuevoUuid,
  registrarConteo, registrarIngreso, registrarSalida, type ProductoLector,
} from '@/lib/services/bodega-faena'

type Modo = 'sacar' | 'recibir' | 'contar'
type Linea = ProductoLector & { cantidad: number }

const MODOS: { id: Modo; texto: string; icono: typeof Plus; color: string }[] = [
  { id: 'sacar', texto: 'Sacar', icono: ArrowUpFromLine, color: 'bg-red-700' },
  { id: 'recibir', texto: 'Recibir', icono: ArrowDownToLine, color: 'bg-emerald-700' },
  { id: 'contar', texto: 'Contar', icono: ClipboardCheck, color: 'bg-blue-700' },
]
const fmt = (n: number | null | undefined) => (n == null ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 2 }))

export default function BodegaFrankePage() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const toast = useToast()
  const qc = useQueryClient()
  const lector = useRef<HTMLInputElement>(null)
  const [modo, setModo] = useState<Modo>('sacar')
  const [codigo, setCodigo] = useState('')
  const [lineas, setLineas] = useState<Linea[]>([])
  const [opciones, setOpciones] = useState<ProductoLector[]>([])
  const [buscando, setBuscando] = useState(false)
  const [guardando, setGuardando] = useState(false)
  const [equipo, setEquipo] = useState('')
  const [motivo, setMotivo] = useState('')
  const [entregadoA, setEntregadoA] = useState('')
  const [origen, setOrigen] = useState('Envío desde bodega Coquimbo')
  const [documento, setDocumento] = useState('')
  const [completo, setCompleto] = useState(false)
  const [uuid, setUuid] = useState(nuevoUuid)
  const [nuevo, setNuevo] = useState<{ nombre: string; categoria: string; unidad: string } | null>(null)

  const { data: bodega } = useQuery({ queryKey: ['bodega', BODEGA_FRANKE], queryFn: () => getBodegaPorCodigo(BODEGA_FRANKE) })
  const { data: panel } = useQuery({
    queryKey: ['bodega-panel', bodega?.id], queryFn: () => getPanelBodega(bodega!.id), enabled: !!bodega?.id,
  })

  const enfocar = useCallback(() => setTimeout(() => lector.current?.focus(), 30), [])
  useEffect(() => { enfocar() }, [modo, enfocar])

  const agregar = useCallback((p: ProductoLector) => {
    setLineas((ls) => {
      const i = ls.findIndex((l) => l.producto_id === p.producto_id)
      if (i >= 0) return ls.map((l, j) => (j === i ? { ...l, cantidad: l.cantidad + 1 } : l))
      return [{ ...p, cantidad: 1 }, ...ls]
    })
    setOpciones([])
    setCodigo('')
    enfocar()
  }, [enfocar])

  async function alLeer(e: React.FormEvent) {
    e.preventDefault()
    const t = codigo.trim()
    if (!t || !bodega) return
    setBuscando(true)
    try {
      const r = await buscarProducto(bodega.id, t)
      const exacto = r.find((p) => p.exacto)
      if (exacto) agregar(exacto)
      else if (r.length === 1) agregar(r[0])
      else if (r.length === 0) { toast.error(`No encuentro «${t}». Búsquelo por nombre o créelo.`); setCodigo(''); enfocar() }
      else setOpciones(r)
    } catch (err) { toast.error(errorMessage(err)) } finally { setBuscando(false) }
  }

  const exigeEquipo = lineas.some((l) => l.exige_equipo)
  const faltaStock = modo === 'sacar' ? lineas.filter((l) => l.cantidad > Number(l.stock)) : []

  async function guardar() {
    if (!bodega || lineas.length === 0) return
    if (modo === 'sacar' && exigeEquipo && !equipo) { toast.error('Hay repuestos en la lista: elija el camión o equipo.'); return }
    if (modo === 'sacar' && faltaStock.length) { toast.error(`No alcanza el stock de ${faltaStock[0].nombre}.`); return }
    const items = lineas.map((l) => ({ producto_id: l.producto_id, cantidad: l.cantidad }))
    setGuardando(true)
    try {
      if (modo === 'sacar') {
        const r = await registrarSalida({ bodegaId: bodega.id, items, activoId: equipo || null, motivo, entregadoA, clientUuid: uuid })
        toast.success(`Salida registrada: ${r.items} producto${r.items === 1 ? '' : 's'}.`)
        if (r.bajo_minimo?.length) {
          toast.error(`Bajo el mínimo: ${r.bajo_minimo.map((b) => `${b.producto} (${fmt(b.stock)})`).join(', ')}. Se avisó a bodega.`)
        }
      } else if (modo === 'recibir') {
        const r = await registrarIngreso({ bodegaId: bodega.id, items, origen, documento, clientUuid: uuid })
        toast.success(`Recepción registrada: ${r.items} producto${r.items === 1 ? '' : 's'}.`)
      } else {
        const r = await registrarConteo({ bodegaId: bodega.id, items, completo, observacion: motivo, clientUuid: uuid })
        toast.success(`Conteo enviado: ${r.productos} productos, ${r.con_diferencia} con diferencia. Queda para aprobación.`)
      }
      setLineas([]); setMotivo(''); setEntregadoA(''); setDocumento(''); setUuid(nuevoUuid())
      qc.invalidateQueries({ queryKey: ['bodega-panel'] })
    } catch (err) { toast.error(errorMessage(err)) } finally { setGuardando(false); enfocar() }
  }

  async function crearNuevo() {
    if (!bodega || !nuevo) return
    try {
      const r = await crearProductoFaena(bodega.id, nuevo.nombre, nuevo.categoria, nuevo.unidad)
      toast.success(`Creado ${r.codigo}. Imprima su etiqueta desde el panel de bodega.`)
      const [p] = await buscarProducto(bodega.id, r.codigo)
      if (p) agregar(p)
      setNuevo(null)
    } catch (err) { toast.error(errorMessage(err)) }
  }

  const alertas = panel?.alertas ?? []
  const modoInfo = useMemo(() => MODOS.find((m) => m.id === modo)!, [modo])

  if (verificando) return <div className="flex min-h-screen items-center justify-center"><Spinner className="h-8 w-8" /></div>
  if (sinSesionOffline) return <SinSesionOffline />

  return (
    <div className="min-h-screen bg-gray-50 pb-28">
      <header className="border-b bg-white px-4 pb-3 pt-[max(1rem,env(safe-area-inset-top))]">
        <Link href="/m/franke" className="mb-1 inline-flex items-center gap-1 text-xs text-gray-500"><ChevronLeft className="h-3.5 w-3.5" /> Franke</Link>
        <p className="text-lg font-bold text-gray-900">Bodega de faena</p>
        <p className="text-xs text-gray-500">Agua, repuestos y EPP · use el lector sobre la etiqueta</p>
      </header>

      {alertas.length > 0 && (
        <div className="mx-4 mt-3 rounded-xl border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
          <p className="flex items-center gap-1.5 font-semibold"><AlertTriangle className="h-4 w-4" /> {alertas.length} bajo el mínimo</p>
          <p className="mt-0.5 text-xs">{alertas.slice(0, 4).map((a) => `${a.producto} (${fmt(a.stock)})`).join(' · ')}{alertas.length > 4 ? '…' : ''}</p>
        </div>
      )}

      <div className="mx-4 mt-3 grid grid-cols-3 gap-2">
        {MODOS.map((m) => (
          <button key={m.id} onClick={() => { setModo(m.id); setLineas([]); setUuid(nuevoUuid()) }}
                  className={cn('flex flex-col items-center gap-1 rounded-xl border-2 py-3 text-sm font-semibold',
                    modo === m.id ? `${m.color} border-transparent text-white` : 'border-gray-200 bg-white text-gray-700')}>
            <m.icono className="h-5 w-5" />{m.texto}
          </button>
        ))}
      </div>

      <form onSubmit={alLeer} className="mx-4 mt-3">
        <label className="flex items-center gap-2 rounded-xl border-2 border-gray-900 bg-white px-3 py-3 focus-within:ring-2 focus-within:ring-gray-900">
          {buscando ? <Spinner className="h-5 w-5" /> : <ScanBarcode className="h-5 w-5 shrink-0 text-gray-700" />}
          <input ref={lector} value={codigo} onChange={(e) => setCodigo(e.target.value)} autoFocus
                 autoComplete="off" autoCapitalize="characters" spellCheck={false} inputMode="text"
                 placeholder="Dispare el lector o escriba código / nombre"
                 className="w-full bg-transparent text-base outline-none" />
        </label>
      </form>

      {opciones.length > 0 && (
        <ul className="mx-4 mt-2 divide-y overflow-hidden rounded-xl border bg-white">
          {opciones.map((p) => (
            <li key={p.producto_id}>
              <button onClick={() => agregar(p)} className="flex w-full items-center justify-between gap-2 px-3 py-2.5 text-left text-sm hover:bg-gray-50">
                <span><b>{p.nombre}</b><span className="block text-xs text-gray-500">{p.codigo}</span></span>
                <span className="shrink-0 text-xs text-gray-500">hay {fmt(p.stock)}</span>
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
          <div key={l.producto_id} className={cn('rounded-xl border bg-white p-3',
            modo === 'sacar' && l.cantidad > Number(l.stock) && 'border-red-400')}>
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <p className="truncate text-sm font-semibold text-gray-900">{l.nombre}</p>
                <p className="text-xs text-gray-500">{l.codigo} · hay {fmt(l.stock)} {l.unidad}{l.exige_equipo ? ' · repuesto' : ''}</p>
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
          {modo === 'sacar' && (
            <>
              <label className="block text-sm">
                <span className="font-medium text-gray-700">Camión o equipo {exigeEquipo ? '(obligatorio: hay repuestos)' : '(opcional: agua/EPP van a la operación)'}</span>
                <select value={equipo} onChange={(e) => setEquipo(e.target.value)} className="mt-1 w-full rounded-lg border px-3 py-2.5">
                  <option value="">{exigeEquipo ? 'Elegir…' : 'Operación Franke (uso general)'}</option>
                  {(panel?.equipos ?? []).map((e) => <option key={e.id} value={e.id}>{e.patente} · {e.tipo.replace('_', ' ')}</option>)}
                </select>
              </label>
              <input value={entregadoA} onChange={(e) => setEntregadoA(e.target.value)} placeholder="Entregado a (nombre)"
                     className="w-full rounded-lg border px-3 py-2.5 text-sm" />
              <input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Motivo (ej. cambio de filtro, consumo turno A)"
                     className="w-full rounded-lg border px-3 py-2.5 text-sm" />
            </>
          )}
          {modo === 'recibir' && (
            <>
              <input value={origen} onChange={(e) => setOrigen(e.target.value)} placeholder="De dónde viene"
                     className="w-full rounded-lg border px-3 py-2.5 text-sm" />
              <input value={documento} onChange={(e) => setDocumento(e.target.value)} placeholder="N° guía o factura (opcional)"
                     className="w-full rounded-lg border px-3 py-2.5 text-sm" />
            </>
          )}
          {modo === 'contar' && (
            <>
              <label className="flex items-start gap-2 text-sm">
                <input type="checkbox" checked={completo} onChange={(e) => setCompleto(e.target.checked)} className="mt-1" />
                <span><b>Inventario completo de la bodega.</b> Lo que NO se escaneó se cuenta como 0. Déjelo sin marcar para contar solo algunos productos.</span>
              </label>
              <input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Observación (opcional)"
                     className="w-full rounded-lg border px-3 py-2.5 text-sm" />
            </>
          )}
        </section>
      )}

      <section className="mx-4 mt-3">
        {!nuevo ? (
          <button onClick={() => setNuevo({ nombre: '', categoria: 'ferreteria', unidad: 'un' })} className="text-xs font-medium text-gray-500 underline">
            ¿El producto no existe en el sistema? Crearlo
          </button>
        ) : (
          <div className="space-y-2 rounded-xl border bg-white p-3 text-sm">
            <p className="font-semibold">Producto nuevo</p>
            <input value={nuevo.nombre} onChange={(e) => setNuevo({ ...nuevo, nombre: e.target.value })} placeholder="Nombre (ej. BIDÓN AGUA PURIFICADA 20 L)"
                   className="w-full rounded-lg border px-3 py-2" />
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

      {lineas.length > 0 && (
        <div className="fixed inset-x-0 bottom-0 mx-auto max-w-[480px] border-t bg-white p-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
          <button onClick={guardar} disabled={guardando}
                  className={cn('w-full rounded-xl py-3.5 text-base font-bold text-white disabled:opacity-50', modoInfo.color)}>
            {guardando ? 'Guardando…' : `${modoInfo.texto} ${lineas.length} producto${lineas.length === 1 ? '' : 's'}`}
          </button>
        </div>
      )}
    </div>
  )
}
