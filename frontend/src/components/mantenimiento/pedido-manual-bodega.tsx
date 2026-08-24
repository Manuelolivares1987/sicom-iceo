'use client'

// ============================================================================
// Pedido manual a bodega (MIG371)
// ----------------------------------------------------------------------------
// El otro camino del vale. El que ya existía sólo sirve cuando el equipo tiene
// una OT y esa OT ya tiene ítems —de un hallazgo o de lo que pidió el operador—.
// Esto cubre el caso de todos los días: hacen falta filtros, aceite o una
// manguera para una patente, y no hay hallazgo ni OT.
//
// TRES DECISIONES DE PANTALLA
//
//   · LA PATENTE PRIMERO. Es lo que el jefe tiene en la cabeza cuando pide, y
//     es lo que decide a qué equipo se le carga el costo.
//
//   · EL CATÁLOGO ANTES QUE EL TEXTO LIBRE. Un ítem con producto del catálogo
//     descuenta stock solo; uno escrito a mano lo tiene que amarrar bodega
//     antes de despachar. Se permite escribirlo —quien pide no siempre sabe el
//     código— pero la pantalla lo dice, y no al final.
//
//   · EL MOTIVO NO ES UN CAMPO MÁS. Un vale que nace de un hallazgo se explica
//     solo: ahí está la NC con su foto. Éste no tiene de dónde agarrarse, y sin
//     el motivo escrito, a fin de mes nadie puede decir por qué salió.
// ============================================================================

import { useMemo, useRef, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Loader2, Plus, Search, Trash2, Truck, AlertTriangle, Package } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useToast } from '@/contexts/toast-context'
import { buscarProductos } from '@/lib/services/ot-materiales'
import {
  crearValeManual, getEquiposParaVale, subirFirmaTicket,
  type EquipoParaVale, type ItemValeManual,
} from '@/lib/services/bodega-tickets'
import { cn } from '@/lib/utils'

type ProductoLite = { id: string; codigo: string | null; nombre: string; unidad_medida: string | null }
type Linea = ItemValeManual & { key: string; nombreVisible: string }

export function PedidoManualBodega({ onEmitido }: { onEmitido?: () => void }) {
  const toast = useToast()

  const { data: equipos = [], isLoading: cargandoEquipos } = useQuery({
    queryKey: ['equipos-para-vale'],
    queryFn: getEquiposParaVale,
    staleTime: 300_000,
  })

  const [buscarEquipo, setBuscarEquipo] = useState('')
  const [equipo, setEquipo] = useState<EquipoParaVale | null>(null)
  const [lineas, setLineas] = useState<Linea[]>([])
  const [motivo, setMotivo] = useState('')
  const [observacion, setObservacion] = useState('')
  const [firma, setFirma] = useState('')
  const [busy, setBusy] = useState(false)

  const equiposFiltrados = useMemo(() => {
    const q = buscarEquipo.trim().toLowerCase()
    const base = q
      ? equipos.filter((e) =>
          (e.patente ?? '').toLowerCase().includes(q)
          || e.codigo.toLowerCase().includes(q)
          || (e.nombre ?? '').toLowerCase().includes(q))
      : equipos
    return base.slice(0, 30)
  }, [equipos, buscarEquipo])

  const sinCatalogo = lineas.filter((l) => !l.producto_id).length
  const listo = !!equipo && lineas.length > 0 && motivo.trim().length >= 5 && !!firma

  const emitir = async () => {
    if (!equipo || !firma) return
    setBusy(true)
    try {
      const url = await subirFirmaTicket(firma, 'vale-manual')
      const r = await crearValeManual({
        activoId: equipo.id,
        items: lineas.map(({ producto_id, descripcion, cantidad, unidad, comentario }) =>
          ({ producto_id, descripcion, cantidad, unidad, comentario })),
        motivo: motivo.trim(),
        firmaJefeUrl: url,
        observacion: observacion.trim() || null,
      })
      toast.success(
        r.items_sin_catalogo > 0
          ? `Vale ${r.folio} emitido con ${r.items} ítem(s). ${r.items_sin_catalogo} sin producto del catálogo: bodega los amarra antes de despachar.`
          : `Vale ${r.folio} emitido con ${r.items} ítem(s) — bodega ya recibió el pedido.`,
      )
      window.open(`/vale/${r.ticket_id}`, '_blank')
      setLineas([]); setMotivo(''); setObservacion(''); setFirma(''); setEquipo(null); setBuscarEquipo('')
      onEmitido?.()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'No se pudo emitir el pedido')
    } finally { setBusy(false) }
  }

  return (
    <div className="space-y-3">
      <p className="rounded-lg bg-blue-50 p-2.5 text-[11px] leading-snug text-blue-900">
        Para pedir material sin que haya un hallazgo: se elige la patente, se escribe lo que hace
        falta y sale el mismo vale con QR que bodega ya conoce. Queda cargado al equipo, así que el
        costo del mes sigue siendo cierto.
      </p>

      {/* ── 1. La patente ────────────────────────────────────────────── */}
      <div>
        <label className="text-xs font-medium">1. ¿Para qué equipo?</label>
        {equipo ? (
          <div className="mt-1 flex items-center gap-3 rounded-lg border-2 border-orange-500 bg-orange-50 px-3 py-2">
            <Truck className="h-4 w-4 shrink-0 text-orange-600" />
            <span className="text-base font-bold text-gray-800">{equipo.patente ?? equipo.codigo}</span>
            <span className="min-w-0 flex-1 truncate text-xs text-gray-500">{equipo.nombre}</span>
            <button type="button" onClick={() => setEquipo(null)}
                    className="shrink-0 text-[11px] font-semibold text-orange-700 underline">
              cambiar
            </button>
          </div>
        ) : (
          <>
            <div className="relative mt-1">
              <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
              <input value={buscarEquipo} onChange={(e) => setBuscarEquipo(e.target.value)}
                     placeholder="Buscar por patente, código o nombre"
                     className="w-full rounded border py-1.5 pl-8 pr-2 text-sm" />
            </div>
            <div className="mt-1 max-h-44 space-y-1 overflow-y-auto">
              {cargandoEquipos && <p className="py-2 text-center text-xs text-gray-400">Cargando equipos…</p>}
              {!cargandoEquipos && equiposFiltrados.length === 0 && (
                <p className="py-2 text-center text-xs text-gray-400">Ningún equipo con ese nombre.</p>
              )}
              {equiposFiltrados.map((e) => (
                <button key={e.id} type="button" onClick={() => { setEquipo(e); setBuscarEquipo('') }}
                        className="flex w-full items-center gap-2 rounded border border-gray-200 px-2.5 py-1.5 text-left hover:bg-gray-50">
                  <span className="text-sm font-bold text-gray-800">{e.patente ?? e.codigo}</span>
                  <span className="min-w-0 flex-1 truncate text-[11px] text-gray-500">{e.nombre}</span>
                </button>
              ))}
            </div>
          </>
        )}
      </div>

      {/* ── 2. Lo que se pide ────────────────────────────────────────── */}
      {equipo && (
        <div>
          <label className="text-xs font-medium">2. ¿Qué se necesita?</label>
          <AgregarLinea onAdd={(l) => setLineas((ls) => [...ls, l])} />

          {lineas.length > 0 && (
            <div className="mt-1.5 space-y-1">
              {lineas.map((l) => (
                <div key={l.key}
                     className={cn('flex items-center gap-2 rounded border px-2.5 py-1.5',
                                   l.producto_id ? 'border-gray-200' : 'border-amber-300 bg-amber-50')}>
                  <Package className={cn('h-3.5 w-3.5 shrink-0',
                                         l.producto_id ? 'text-gray-400' : 'text-amber-600')} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm text-gray-800">{l.nombreVisible}</p>
                    {!l.producto_id && (
                      <p className="text-[10px] text-amber-800">
                        Escrito a mano: bodega tiene que amarrarlo a un producto antes de despachar
                      </p>
                    )}
                  </div>
                  <span className="shrink-0 text-sm font-semibold tabular-nums text-gray-700">
                    {l.cantidad}{l.unidad ? ` ${l.unidad}` : ''}
                  </span>
                  <button type="button" onClick={() => setLineas((ls) => ls.filter((x) => x.key !== l.key))}
                          aria-label="Quitar" className="shrink-0 text-gray-400 hover:text-red-600">
                    <Trash2 className="h-3.5 w-3.5" />
                  </button>
                </div>
              ))}
            </div>
          )}

          {sinCatalogo > 0 && (
            <p className="mt-1.5 flex items-start gap-1.5 text-[11px] leading-snug text-amber-800">
              <AlertTriangle className="mt-px h-3.5 w-3.5 shrink-0" />
              {sinCatalogo} ítem(s) sin producto del catálogo. El vale se emite igual, pero bodega no
              podrá despacharlos hasta decir cuál es —y hasta entonces el stock no baja.
            </p>
          )}
        </div>
      )}

      {/* ── 3. Por qué ───────────────────────────────────────────────── */}
      {equipo && lineas.length > 0 && (
        <>
          <label className="block text-xs font-medium">
            3. ¿Para qué es? <span className="font-normal text-gray-500">— obligatorio</span>
            <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={2}
                      placeholder="Mantención de rutina: se acabaron los filtros del stock del taller"
                      className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
            <span className="mt-0.5 block text-[10px] text-gray-500">
              Este pedido no nace de una no conformidad, así que esto es lo único que va a quedar
              escrito sobre por qué salió el material.
            </span>
          </label>

          <label className="block text-xs font-medium">
            Observación para bodega <span className="font-normal text-gray-500">— opcional</span>
            <input value={observacion} onChange={(e) => setObservacion(e.target.value)}
                   placeholder="Quién retira, cuándo, dónde dejarlo"
                   className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
          </label>

          <SignaturePad label="Firma del jefe de taller (obligatoria)" onCapture={setFirma} />

          <Button onClick={emitir} disabled={!listo || busy} className="w-full">
            {busy ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" /> : null}
            Emitir el vale
          </Button>
          {!listo && !busy && (
            <p className="text-center text-[11px] text-gray-500">
              {!motivo.trim() || motivo.trim().length < 5
                ? 'Falta decir para qué es el pedido.'
                : !firma ? 'Falta la firma del jefe.' : ''}
            </p>
          )}
        </>
      )}
    </div>
  )
}

// ── Una línea: primero el catálogo, y si no está, a mano ────────────────────
function AgregarLinea({ onAdd }: { onAdd: (l: Linea) => void }) {
  const [q, setQ] = useState('')
  const [resultados, setResultados] = useState<ProductoLite[]>([])
  const [prod, setProd] = useState<ProductoLite | null>(null)
  const [cant, setCant] = useState('')
  const [buscando, setBuscando] = useState(false)
  // Al elegir el producto, lo siguiente que se hace SIEMPRE es escribir cuánto.
  // Sin esto hay que ir a buscar con el dedo una caja de 80 píxeles.
  const cantRef = useRef<HTMLInputElement>(null)

  const buscar = async (texto: string) => {
    setQ(texto); setProd(null)
    if (texto.trim().length < 2) { setResultados([]); return }
    setBuscando(true)
    try {
      const { data } = await buscarProductos(texto, 8)
      setResultados((data ?? []) as ProductoLite[])
    } catch { setResultados([]) } finally { setBuscando(false) }
  }

  const agregar = () => {
    const n = Number(String(cant).replace(',', '.'))
    if (!Number.isFinite(n) || n <= 0) return
    if (!prod && q.trim().length < 3) return
    onAdd({
      key: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
      producto_id: prod?.id ?? null,
      descripcion: prod ? null : q.trim(),
      cantidad: n,
      unidad: prod?.unidad_medida ?? null,
      comentario: null,
      nombreVisible: prod ? `${prod.codigo ? `${prod.codigo} · ` : ''}${prod.nombre}` : q.trim(),
    })
    setQ(''); setProd(null); setCant(''); setResultados([])
  }

  // Enter agrega la línea: quien carga diez ítems no quiere diez clicks al «+».
  const alTeclear = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') { e.preventDefault(); agregar() }
  }

  return (
    <div className="mt-1 rounded-lg border border-dashed border-gray-300 p-2">
      <div className="flex gap-1.5">
        <div className="relative min-w-0 flex-1">
          <input value={prod ? `${prod.codigo ? `${prod.codigo} · ` : ''}${prod.nombre}` : q}
                 onChange={(e) => buscar(e.target.value)}
                 onKeyDown={alTeclear}
                 placeholder="Buscar en el catálogo… o escribirlo si no está"
                 className="w-full rounded border px-2 py-1.5 text-sm" />
          {buscando && (
            <Loader2 className="absolute right-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 animate-spin text-gray-400" />
          )}
        </div>
        <input ref={cantRef} value={cant} onKeyDown={alTeclear}
               onChange={(e) => setCant(e.target.value.replace(/[^\d.,]/g, ''))}
               inputMode="decimal" placeholder="Cant."
               className="w-20 rounded border px-2 py-1.5 text-right text-sm tabular-nums" />
        <button type="button" onClick={agregar}
                disabled={!Number(String(cant).replace(',', '.')) || (!prod && q.trim().length < 3)}
                className="shrink-0 rounded bg-orange-600 px-2.5 text-[11px] font-semibold text-white disabled:opacity-50">
          <Plus className="h-3.5 w-3.5" />
        </button>
      </div>

      {resultados.length > 0 && !prod && (
        <div className="mt-1 max-h-36 space-y-0.5 overflow-y-auto">
          {resultados.map((r) => (
            <button key={r.id} type="button"
                    onClick={() => {
                      setProd(r); setResultados([])
                      // El foco va a la cantidad, que es el paso siguiente.
                      setTimeout(() => cantRef.current?.focus(), 0)
                    }}
                    className="flex w-full items-center gap-2 rounded px-2 py-1 text-left text-xs hover:bg-gray-50">
              <span className="font-mono text-[10px] text-gray-500">{r.codigo}</span>
              <span className="min-w-0 flex-1 truncate">{r.nombre}</span>
              {r.unidad_medida && <span className="shrink-0 text-[10px] text-gray-400">{r.unidad_medida}</span>}
            </button>
          ))}
        </div>
      )}

      {!prod && q.trim().length >= 3 && resultados.length === 0 && !buscando && (
        <p className="mt-1 text-[10px] text-amber-800">
          No está en el catálogo: se va a pedir como «{q.trim()}» y bodega lo amarra al despachar.
        </p>
      )}
    </div>
  )
}
