'use client'

// ============================================================================
// Pedirle a bodega por un link (MIG376/377)
// ----------------------------------------------------------------------------
// La gente de oficina pide tóner o cloro una vez al mes: crearle y mantenerle
// una cuenta a cada uno cuesta más que el pedido. Este link se reenvía por
// WhatsApp y hace lo mismo que la pantalla con sesión.
//
// PRIMERO SE DICE QUIÉN ES UNO
// El vale existe para que el gasto quede con responsable. Sin nombre quedaría
// con centro de costo y nada más, que es la mitad de lo que sirve. Igual que el
// portal de prevención de Romeral: nombre y apellido antes de pedir.
//
// DOS CAMINOS, Y EL SEGUNDO ES EL QUE MÁS SE VA A USAR
// De los 357 artículos de oficina, aseo y EPP del catálogo, sólo 2 tienen
// stock: bodega no guarda tóner, lo compra cuando se lo piden. Por eso el
// buscador dice al lado de cada cosa si hay o no hay, y cuando no hay, el
// camino no es emitir un vale que nadie puede despachar — es pedir la compra.
//
// SIN LAYOUT DE DASHBOARD
// Vive fuera de /dashboard a propósito: no hay sesión, no hay sidebar y no hay
// nada del sistema que mostrar. Es una sola pantalla.
// ============================================================================

import { useCallback, useEffect, useRef, useState } from 'react'
import { useParams } from 'next/navigation'
import {
  PackageSearch, Loader2, Printer, ShoppingCart, Receipt, Search, Trash2,
  AlertTriangle, CheckCircle2, Clock, XCircle, LogOut, Plus,
} from 'lucide-react'
import { SignaturePad } from '@/components/ui/signature-pad'
import { ValeImprimible, EstilosImpresionVale, type ValePapel, type ValePapelItem } from '@/components/bodega/vale-imprimible'
import {
  getPortalPublico, entrarAlPortal, buscarEnPortal, crearValePortal,
  pedirCompraPortal, getMisPedidosPortal, getValePortal,
  type SesionPortal, type ProductoPortal, type MisPedidosPortal,
} from '@/lib/services/portal-vale'
import { cn } from '@/lib/utils'

type Linea = { key: string; producto_id: string; nombre: string; unidad: string | null; cantidad: number }
type Vista = 'retirar' | 'comprar' | 'mis-pedidos'

const ESTADO_SOL: Record<string, { t: string; c: string; i: typeof Clock }> = {
  pendiente: { t: 'Esperando', c: 'bg-amber-100 text-amber-800', i: Clock },
  atendida:  { t: 'Entregada', c: 'bg-green-100 text-green-700', i: CheckCircle2 },
  rechazada: { t: 'Rechazada', c: 'bg-gray-200 text-gray-600', i: XCircle },
}

const ESTADO_VALE: Record<string, { t: string; c: string }> = {
  emitido:   { t: 'Por retirar', c: 'bg-blue-100 text-blue-800' },
  parcial:   { t: 'Entrega parcial', c: 'bg-amber-100 text-amber-800' },
  entregado: { t: 'Retirado', c: 'bg-green-100 text-green-700' },
  anulado:   { t: 'Anulado', c: 'bg-gray-200 text-gray-600' },
}

export default function PortalValeOficinaPage() {
  const token = useParams()?.token as string
  const [portal, setPortal] = useState<{ valido: boolean; portal?: string } | null>(null)
  const [sesion, setSesion] = useState<SesionPortal | null>(null)
  // El vale recién emitido, para imprimirlo sin salir de la pantalla.
  const [imprimir, setImprimir] = useState<{ ticket: ValePapel; items: ValePapelItem[] } | null>(null)

  useEffect(() => {
    if (!token) return
    getPortalPublico(token).then(setPortal).catch(() => setPortal({ valido: false }))
  }, [token])

  // El ingreso sobrevive a un refresco pero no al cierre del navegador: es una
  // credencial temporal, no una sesión.
  useEffect(() => {
    if (!token) return
    try {
      const raw = sessionStorage.getItem(`portal-vale-${token}`)
      if (raw) setSesion(JSON.parse(raw))
    } catch { /* sessionStorage bloqueado: se vuelve a identificar y ya */ }
  }, [token])

  const entrar = (s: SesionPortal) => {
    setSesion(s)
    try { sessionStorage.setItem(`portal-vale-${token}`, JSON.stringify(s)) } catch { /* da igual */ }
  }
  const salir = () => {
    try { sessionStorage.removeItem(`portal-vale-${token}`) } catch { /* da igual */ }
    setSesion(null)
  }

  if (portal === null) {
    return <Centro><Loader2 className="h-6 w-6 animate-spin text-gray-400" /></Centro>
  }
  if (!portal.valido) {
    return (
      <Centro>
        <div className="max-w-sm text-center">
          <AlertTriangle className="mx-auto h-10 w-10 text-amber-500" />
          <h1 className="mt-3 text-lg font-bold text-gray-900">Este link ya no sirve</h1>
          <p className="mt-1 text-sm text-gray-600">
            Puede que lo hayan revocado o que haya vencido. Pídale uno nuevo a bodega.
          </p>
        </div>
      </Centro>
    )
  }

  // El vale impreso ocupa la pantalla entera: es lo que hay que llevar a bodega.
  if (imprimir) {
    return (
      <div className="mx-auto max-w-2xl bg-white p-4 print:max-w-full print:p-0">
        <EstilosImpresionVale />
        <div className="mb-4 flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 px-4 py-3 print:hidden">
          <p className="text-sm text-gray-600">Imprima este vale y llévelo a bodega.</p>
          <div className="flex gap-2">
            <button onClick={() => setImprimir(null)}
                    className="rounded-lg border border-gray-300 px-3 py-2 text-sm font-semibold text-gray-700">
              Volver
            </button>
            <button onClick={() => window.print()}
                    className="flex items-center gap-1.5 rounded-lg bg-[#0b2a4a] px-4 py-2 text-sm font-semibold text-white">
              <Printer className="h-4 w-4" /> Imprimir
            </button>
          </div>
        </div>
        <ValeImprimible ticket={imprimir.ticket} items={imprimir.items} />
      </div>
    )
  }

  if (!sesion) return <Ingreso token={token} nombrePortal={portal.portal ?? ''} onEntrar={entrar} />

  return (
    <Portal token={token} sesion={sesion} onSalir={salir} onImprimir={setImprimir} />
  )
}

function Centro({ children }: { children: React.ReactNode }) {
  return <div className="flex min-h-[70vh] items-center justify-center p-6">{children}</div>
}

// ══ Decir quién es uno ══════════════════════════════════════════════════════

function Ingreso({ token, nombrePortal, onEntrar }: {
  token: string; nombrePortal: string; onEntrar: (s: SesionPortal) => void
}) {
  const [nombre, setNombre] = useState('')
  const [rut, setRut] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const entrar = async () => {
    setBusy(true); setError(null)
    try {
      onEntrar(await entrarAlPortal(token, nombre.trim(), rut.trim() || undefined))
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudo entrar')
    } finally { setBusy(false) }
  }

  return (
    <Centro>
      <div className="w-full max-w-sm">
        <div className="mb-5 text-center">
          <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-xl bg-orange-600 text-white">
            <PackageSearch className="h-6 w-6" />
          </div>
          <h1 className="mt-3 text-xl font-bold text-gray-900">{nombrePortal || 'Vale de bodega'}</h1>
          <p className="mt-1 text-sm text-gray-500">
            Para retirar de bodega o pedir que lo compren.
          </p>
        </div>

        <div className="space-y-3 rounded-xl border border-gray-200 bg-white p-5">
          <p className="text-sm font-semibold text-gray-800">¿Quién está pidiendo?</p>
          <label className="block">
            <span className="text-xs font-medium text-gray-600">Nombre y apellido</span>
            <input value={nombre} onChange={(e) => setNombre(e.target.value)}
                   onKeyDown={(e) => { if (e.key === 'Enter' && nombre.trim().includes(' ')) entrar() }}
                   placeholder="María González"
                   className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
          </label>
          <label className="block">
            <span className="text-xs font-medium text-gray-600">
              RUT <span className="font-normal text-gray-400">— opcional</span>
            </span>
            <input value={rut} onChange={(e) => setRut(e.target.value)}
                   placeholder="12.345.678-9"
                   className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
          </label>

          {error && (
            <p className="rounded-lg bg-red-50 p-2 text-xs text-red-700">{error}</p>
          )}

          <button onClick={entrar} disabled={busy || nombre.trim().length < 5}
                  className="flex w-full items-center justify-center gap-1.5 rounded-lg bg-orange-600 px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-50">
            {busy && <Loader2 className="h-4 w-4 animate-spin" />} Entrar
          </button>
          <p className="text-center text-[11px] leading-snug text-gray-500">
            El vale sale a su nombre: es lo que va a explicar el gasto a fin de mes.
          </p>
        </div>
      </div>
    </Centro>
  )
}

// ══ Ya adentro ══════════════════════════════════════════════════════════════

function Portal({ token, sesion, onSalir, onImprimir }: {
  token: string; sesion: SesionPortal; onSalir: () => void
  onImprimir: (v: { ticket: ValePapel; items: ValePapelItem[] }) => void
}) {
  const [vista, setVista] = useState<Vista>('retirar')
  const [aviso, setAviso] = useState<{ t: string; ok: boolean } | null>(null)
  const [mios, setMios] = useState<MisPedidosPortal>({ vales: [], solicitudes: [] })

  const refrescar = useCallback(() => {
    getMisPedidosPortal(token, sesion.acceso_id).then(setMios).catch(() => { /* no es crítico */ })
  }, [token, sesion.acceso_id])

  useEffect(() => { refrescar() }, [refrescar])

  useEffect(() => {
    if (!aviso) return
    const t = setTimeout(() => setAviso(null), 6000)
    return () => clearTimeout(t)
  }, [aviso])

  const abrirVale = async (ticketId: string) => {
    try {
      const r = await getValePortal(token, sesion.acceso_id, ticketId)
      onImprimir({ ticket: r.ticket as unknown as ValePapel, items: r.items as unknown as ValePapelItem[] })
    } catch (e) {
      setAviso({ t: e instanceof Error ? e.message : 'No se pudo abrir el vale', ok: false })
    }
  }

  return (
    <div className="mx-auto max-w-2xl space-y-5 p-4 pb-16">
      <header className="flex items-center gap-3 pt-2">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-orange-600 text-white">
          <PackageSearch className="h-5 w-5" />
        </div>
        <div className="min-w-0 flex-1">
          <h1 className="truncate text-base font-bold text-gray-900">{sesion.portal}</h1>
          <p className="truncate text-xs text-gray-500">Pidiendo como {sesion.nombre}</p>
        </div>
        <button onClick={onSalir} title="Salir"
                className="shrink-0 rounded-lg border border-gray-300 p-2 text-gray-500">
          <LogOut className="h-4 w-4" />
        </button>
      </header>

      {aviso && (
        <p className={cn('rounded-lg p-3 text-sm', aviso.ok
          ? 'bg-green-50 text-green-800' : 'bg-red-50 text-red-700')}>
          {aviso.t}
        </p>
      )}

      <div className="grid grid-cols-3 gap-1.5">
        <Pestana activa={vista === 'retirar'} onClick={() => setVista('retirar')}
                 icono={Receipt} texto="Retirar" />
        <Pestana activa={vista === 'comprar'} onClick={() => setVista('comprar')}
                 icono={ShoppingCart} texto="Que lo compren" />
        <Pestana activa={vista === 'mis-pedidos'} onClick={() => { setVista('mis-pedidos'); refrescar() }}
                 icono={Clock} texto="Mis pedidos"
                 badge={mios.vales.length + mios.solicitudes.length} />
      </div>

      {vista === 'retirar' && (
        <Retirar token={token} sesion={sesion}
                 onListo={(msg, ticketId) => { setAviso({ t: msg, ok: true }); refrescar(); abrirVale(ticketId) }}
                 onError={(msg) => setAviso({ t: msg, ok: false })}
                 onNoHayStock={() => setVista('comprar')} />
      )}
      {vista === 'comprar' && (
        <Comprar token={token} sesion={sesion}
                 onListo={(msg) => { setAviso({ t: msg, ok: true }); refrescar() }}
                 onError={(msg) => setAviso({ t: msg, ok: false })} />
      )}
      {vista === 'mis-pedidos' && (
        <MisPedidos mios={mios} onAbrirVale={abrirVale} />
      )}
    </div>
  )
}

function Pestana({ activa, onClick, icono: Icono, texto, badge }: {
  activa: boolean; onClick: () => void; icono: typeof Receipt; texto: string; badge?: number
}) {
  return (
    <button onClick={onClick}
            className={cn('flex flex-col items-center gap-1 rounded-xl border-2 px-2 py-2.5 transition',
              activa ? 'border-orange-500 bg-orange-50' : 'border-gray-200 bg-white')}>
      <span className="relative">
        <Icono className={cn('h-4 w-4', activa ? 'text-orange-600' : 'text-gray-400')} />
        {!!badge && badge > 0 && (
          <span className="absolute -right-2 -top-1.5 rounded-full bg-orange-600 px-1 text-[9px] font-bold text-white">
            {badge}
          </span>
        )}
      </span>
      <span className={cn('text-[11px] font-semibold leading-none',
        activa ? 'text-orange-900' : 'text-gray-600')}>{texto}</span>
    </button>
  )
}

// ══ Camino 1: retirar lo que hay ════════════════════════════════════════════

function Retirar({ token, sesion, onListo, onError, onNoHayStock }: {
  token: string; sesion: SesionPortal
  onListo: (msg: string, ticketId: string) => void
  onError: (msg: string) => void
  onNoHayStock: () => void
}) {
  const [ceco, setCeco] = useState(sesion.cecos.length === 1 ? sesion.cecos[0].id : '')
  const [lineas, setLineas] = useState<Linea[]>([])
  const [motivo, setMotivo] = useState('')
  const [firma, setFirma] = useState('')
  const [busy, setBusy] = useState(false)
  const [nro, setNro] = useState(0)

  const listo = !!ceco && lineas.length > 0 && motivo.trim().length >= 5 && !!firma

  const emitir = async () => {
    if (!listo) return
    setBusy(true)
    try {
      const r = await crearValePortal({
        token, accesoId: sesion.acceso_id, cecoId: ceco,
        items: lineas.map((l) => ({ producto_id: l.producto_id, cantidad: l.cantidad })),
        motivo: motivo.trim(), firma,
      })
      setLineas([]); setMotivo(''); setFirma(''); setNro((n) => n + 1)
      onListo(`Vale ${r.folio} emitido, cargado a ${r.ceco_nombre}.`, r.ticket_id)
    } catch (e) {
      onError(e instanceof Error ? e.message : 'No se pudo emitir el vale')
    } finally { setBusy(false) }
  }

  return (
    <div className="space-y-4 rounded-xl border border-gray-200 bg-white p-4">
      <p className="rounded-lg bg-blue-50 p-2.5 text-[11px] leading-snug text-blue-900">
        Sale un vale con folio para imprimir y llevar a bodega. Queda cargado al centro de costo que
        elija. Si lo que busca no aparece o dice que no hay, se pide por «Que lo compren».
      </p>

      <label className="block">
        <span className="text-sm font-semibold text-gray-800">1. ¿A qué se carga?</span>
        <select value={ceco} onChange={(e) => setCeco(e.target.value)}
                className="mt-1 h-10 w-full rounded-lg border border-gray-300 px-2 text-sm">
          <option value="">Elegir…</option>
          {sesion.cecos.map((c) => <option key={c.id} value={c.id}>{c.nombre}</option>)}
        </select>
      </label>

      <div>
        <span className="text-sm font-semibold text-gray-800">2. ¿Qué se retira?</span>
        <BuscadorPortal key={nro} token={token} accesoId={sesion.acceso_id}
                        onNoHayStock={onNoHayStock}
                        onAdd={(l) => setLineas((ls) => ls.length >= sesion.max_items ? ls : [...ls, l])} />
        {lineas.length > 0 && (
          <div className="mt-1.5 space-y-1">
            {lineas.map((l) => (
              <div key={l.key} className="flex items-center gap-2 rounded-lg border border-gray-200 px-2.5 py-1.5">
                <span className="min-w-0 flex-1 truncate text-sm text-gray-800">{l.nombre}</span>
                <span className="shrink-0 text-sm font-semibold tabular-nums text-gray-700">
                  {l.cantidad}{l.unidad ? ` ${l.unidad}` : ''}
                </span>
                <button type="button" aria-label="Quitar"
                        onClick={() => setLineas((ls) => ls.filter((x) => x.key !== l.key))}
                        className="shrink-0 text-gray-400"><Trash2 className="h-3.5 w-3.5" /></button>
              </div>
            ))}
          </div>
        )}
        {lineas.length >= sesion.max_items && (
          <p className="mt-1 text-[11px] text-amber-800">
            Por este link se pueden pedir hasta {sesion.max_items} artículos por vale.
          </p>
        )}
      </div>

      {lineas.length > 0 && (
        <>
          <label className="block">
            <span className="text-sm font-semibold text-gray-800">3. ¿Para qué es?</span>
            <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={2}
                      placeholder="Insumos de la oficina de administración del mes"
                      className="mt-1 w-full rounded-lg border border-gray-300 px-2 py-1.5 text-sm" />
            <span className="mt-0.5 block text-[10px] text-gray-500">
              Es lo único que va a explicar este gasto cuando se revise el centro de costo.
            </span>
          </label>

          <SignaturePad key={nro} label="Su firma (obligatoria)" onCapture={setFirma} />

          <button onClick={emitir} disabled={!listo || busy}
                  className="flex w-full items-center justify-center gap-1.5 rounded-lg bg-orange-600 px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-50">
            {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Printer className="h-4 w-4" />}
            Emitir el vale
          </button>
          {!listo && !busy && (
            <p className="text-center text-[11px] text-gray-500">
              {!ceco ? 'Falta elegir a qué se carga.'
                : motivo.trim().length < 5 ? 'Falta decir para qué es.'
                : !firma ? 'Falta su firma.' : ''}
            </p>
          )}
        </>
      )}
    </div>
  )
}

/** El buscador del portal: sólo lo que el token deja ver, y dice si hay stock. */
function BuscadorPortal({ token, accesoId, onAdd, onNoHayStock }: {
  token: string; accesoId: string
  onAdd: (l: Linea) => void
  onNoHayStock: () => void
}) {
  const [q, setQ] = useState('')
  const [res, setRes] = useState<ProductoPortal[]>([])
  const [prod, setProd] = useState<ProductoPortal | null>(null)
  const [cant, setCant] = useState('')
  const [buscando, setBuscando] = useState(false)
  const [buscado, setBuscado] = useState(false)
  const cantRef = useRef<HTMLInputElement>(null)

  const buscar = async (texto: string) => {
    setQ(texto); setProd(null)
    if (texto.trim().length < 2) { setRes([]); setBuscado(false); return }
    setBuscando(true)
    try { setRes(await buscarEnPortal(token, accesoId, texto)) }
    catch { setRes([]) }
    finally { setBuscando(false); setBuscado(true) }
  }

  const agregar = () => {
    const n = Number(String(cant).replace(',', '.'))
    if (!prod || !Number.isFinite(n) || n <= 0) return
    onAdd({
      key: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
      producto_id: prod.id, nombre: prod.nombre,
      unidad: prod.unidad_medida, cantidad: n,
    })
    setQ(''); setProd(null); setCant(''); setRes([]); setBuscado(false)
  }

  return (
    <div className="mt-1 rounded-lg border border-dashed border-gray-300 p-2">
      <div className="flex gap-1.5">
        <div className="relative min-w-0 flex-1">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
          <input value={prod ? prod.nombre : q} onChange={(e) => buscar(e.target.value)}
                 onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); agregar() } }}
                 placeholder="Buscar: tóner, resma, cloro…"
                 className="w-full rounded border border-gray-300 py-1.5 pl-8 pr-2 text-sm" />
          {buscando && (
            <Loader2 className="absolute right-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 animate-spin text-gray-400" />
          )}
        </div>
        <input ref={cantRef} value={cant} inputMode="decimal" placeholder="Cant."
               onChange={(e) => setCant(e.target.value.replace(/[^\d.,]/g, ''))}
               onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); agregar() } }}
               className="w-20 rounded border border-gray-300 px-2 py-1.5 text-right text-sm tabular-nums" />
        <button type="button" onClick={agregar} disabled={!prod || !Number(String(cant).replace(',', '.'))}
                className="shrink-0 rounded bg-orange-600 px-2.5 text-white disabled:opacity-50">
          <Plus className="h-3.5 w-3.5" />
        </button>
      </div>

      {res.length > 0 && !prod && (
        <div className="mt-1 max-h-44 space-y-0.5 overflow-y-auto">
          {res.map((r) => (
            <button key={r.id} type="button" disabled={!r.hay_stock}
                    onClick={() => { setProd(r); setRes([]); setTimeout(() => cantRef.current?.focus(), 0) }}
                    className={cn('flex w-full items-center gap-2 rounded px-2 py-1.5 text-left text-xs',
                      r.hay_stock ? 'hover:bg-gray-50' : 'cursor-not-allowed opacity-60')}>
              <span className="min-w-0 flex-1 truncate">{r.nombre}</span>
              {r.hay_stock
                ? <span className="shrink-0 text-[10px] font-semibold text-green-700">hay</span>
                : <span className="shrink-0 text-[10px] font-semibold text-gray-400">no hay</span>}
            </button>
          ))}
          {res.every((r) => !r.hay_stock) && (
            <button type="button" onClick={onNoHayStock}
                    className="mt-1 w-full rounded-lg bg-amber-50 p-2 text-left text-[11px] leading-snug text-amber-900">
              Bodega no tiene ninguno de estos en stock. Toque acá para pedir que lo compren.
            </button>
          )}
        </div>
      )}

      {buscado && !buscando && res.length === 0 && q.trim().length >= 2 && !prod && (
        <button type="button" onClick={onNoHayStock}
                className="mt-1 w-full rounded-lg bg-amber-50 p-2 text-left text-[11px] leading-snug text-amber-900">
          «{q.trim()}» no está en lo que se puede retirar por este link. Toque acá para pedir que lo
          compren.
        </button>
      )}
    </div>
  )
}

// ══ Camino 2: que lo compren ════════════════════════════════════════════════

function Comprar({ token, sesion, onListo, onError }: {
  token: string; sesion: SesionPortal
  onListo: (msg: string) => void; onError: (msg: string) => void
}) {
  const [descripcion, setDescripcion] = useState('')
  const [cantidad, setCantidad] = useState('1')
  const [unidad, setUnidad] = useState('')
  const [area, setArea] = useState('Oficina')
  const [observacion, setObservacion] = useState('')
  const [busy, setBusy] = useState(false)

  const cant = Number(String(cantidad).replace(',', '.'))
  const listo = descripcion.trim().length >= 3 && Number.isFinite(cant) && cant > 0

  const pedir = async () => {
    if (!listo) return
    setBusy(true)
    try {
      await pedirCompraPortal({
        token, accesoId: sesion.acceso_id,
        descripcion: descripcion.trim(), cantidad: cant,
        unidad: unidad.trim() || null, area,
        observacion: observacion.trim() || null,
      })
      setDescripcion(''); setCantidad('1'); setUnidad(''); setObservacion('')
      onListo('Pedido enviado a bodega, con su nombre y la fecha.')
    } catch (e) {
      onError(e instanceof Error ? e.message : 'No se pudo enviar el pedido')
    } finally { setBusy(false) }
  }

  return (
    <div className="space-y-4 rounded-xl border border-gray-200 bg-white p-4">
      <p className="rounded-lg bg-gray-50 p-2.5 text-[11px] leading-snug text-gray-700">
        Esto no emite vale ni descuenta stock: es un encargo para que bodega lo consiga. Cuando
        llegue, el retiro se hace con un vale.
      </p>

      <label className="block">
        <span className="text-sm font-semibold text-gray-800">¿Qué necesita?</span>
        <input value={descripcion} onChange={(e) => setDescripcion(e.target.value)}
               placeholder="Tóner Brother TN-1060 negro"
               className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
      </label>

      <div className="grid grid-cols-3 gap-2">
        <label className="block">
          <span className="text-xs font-semibold text-gray-700">Cantidad</span>
          <input value={cantidad} inputMode="decimal"
                 onChange={(e) => setCantidad(e.target.value.replace(/[^\d.,]/g, ''))}
                 className="mt-1 w-full rounded-lg border border-gray-300 px-2 py-2 text-sm" />
        </label>
        <label className="block">
          <span className="text-xs font-semibold text-gray-700">Unidad</span>
          <input value={unidad} onChange={(e) => setUnidad(e.target.value)} placeholder="caja"
                 className="mt-1 w-full rounded-lg border border-gray-300 px-2 py-2 text-sm" />
        </label>
        <label className="block">
          <span className="text-xs font-semibold text-gray-700">¿Para quién?</span>
          <select value={area} onChange={(e) => setArea(e.target.value)}
                  className="mt-1 h-[38px] w-full rounded-lg border border-gray-300 px-1 text-sm">
            {['Oficina', 'Prevención', 'Taller', 'Terreno', 'Aseo y casino'].map((a) =>
              <option key={a} value={a}>{a}</option>)}
          </select>
        </label>
      </div>

      <label className="block">
        <span className="text-sm font-semibold text-gray-800">
          Algo más que bodega deba saber <span className="font-normal text-gray-500">— opcional</span>
        </span>
        <input value={observacion} onChange={(e) => setObservacion(e.target.value)}
               placeholder="Para cuándo se necesita, marca equivalente que sirve"
               className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
      </label>

      <button onClick={pedir} disabled={!listo || busy}
              className="flex w-full items-center justify-center gap-1.5 rounded-lg bg-orange-600 px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-50">
        {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <ShoppingCart className="h-4 w-4" />}
        Enviar el pedido
      </button>
    </div>
  )
}

// ══ Lo que uno pidió ════════════════════════════════════════════════════════

function MisPedidos({ mios, onAbrirVale }: {
  mios: MisPedidosPortal; onAbrirVale: (id: string) => void
}) {
  const vacio = mios.vales.length === 0 && mios.solicitudes.length === 0
  if (vacio) {
    return (
      <p className="rounded-xl border border-dashed border-gray-300 p-8 text-center text-sm text-gray-400">
        Todavía no ha pedido nada.
      </p>
    )
  }

  return (
    <div className="space-y-4">
      {mios.vales.length > 0 && (
        <div>
          <h2 className="mb-1.5 text-xs font-bold uppercase tracking-wide text-gray-500">Vales</h2>
          <div className="space-y-1.5">
            {mios.vales.map((v) => {
              const e = ESTADO_VALE[v.estado] ?? ESTADO_VALE.emitido
              return (
                <button key={v.id} onClick={() => onAbrirVale(v.id)}
                        className="flex w-full items-center gap-3 rounded-lg border border-gray-200 bg-white p-3 text-left">
                  <Receipt className="h-4 w-4 shrink-0 text-gray-400" />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-semibold text-gray-900">{v.folio}</p>
                    <p className="truncate text-xs text-gray-500">
                      {v.ceco_nombre} · {v.n_items} ítem{v.n_items === 1 ? '' : 's'}
                      {' · '}{new Date(v.created_at).toLocaleDateString('es-CL')}
                    </p>
                  </div>
                  <span className={cn('shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold', e.c)}>
                    {e.t}
                  </span>
                </button>
              )
            })}
          </div>
        </div>
      )}

      {mios.solicitudes.length > 0 && (
        <div>
          <h2 className="mb-1.5 text-xs font-bold uppercase tracking-wide text-gray-500">
            Pedidos de compra
          </h2>
          <div className="space-y-1.5">
            {mios.solicitudes.map((s) => {
              const e = ESTADO_SOL[s.estado] ?? ESTADO_SOL.pendiente
              const Icono = e.i
              return (
                <div key={s.id} className="flex items-center gap-3 rounded-lg border border-gray-200 bg-white p-3">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-semibold text-gray-900">{s.descripcion}</p>
                    <p className="text-xs text-gray-500">
                      {s.cantidad}{s.unidad ? ` ${s.unidad}` : ''}
                      {' · '}{new Date(s.created_at).toLocaleDateString('es-CL')}
                    </p>
                    {s.nota_bodega && (
                      <p className="mt-0.5 text-xs italic text-gray-600">Bodega: {s.nota_bodega}</p>
                    )}
                  </div>
                  <span className={cn('inline-flex shrink-0 items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold', e.c)}>
                    <Icono className="h-3.5 w-3.5" /> {e.t}
                  </span>
                </div>
              )
            })}
          </div>
        </div>
      )}
    </div>
  )
}
