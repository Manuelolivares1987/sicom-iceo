'use client'

// ============================================================================
// Pedir insumos del taller (MIG386)
// ----------------------------------------------------------------------------
// Desde MIG197 el operador pide repuestos desde su OT: los abre, marca el
// hallazgo y de ahí sale el pedido. Pero guantes, trapos, cinta o discos de
// corte no son de ningún equipo — son del taller— y hasta hoy se pedían de
// palabra, sin papel y sin que el gasto quedara con nombre.
//
// EL MISMO CIRCUITO, SIN ORDEN DE TRABAJO
// Pide el operador, valida el jefe, sale el vale. Lo único distinto es a qué se
// carga: la OT lleva el costo al equipo, el centro de costo lo lleva al taller.
//
// NO SE PIDE CONTRA UNA PATENTE
// Cada patente es un centro de costo, y aquí no aparecen. Meter guantes en el
// costo de un camión sin que ninguna OT lo explique arruinaría el costo por
// equipo, que es lo que el sistema cuida. Si el material es PARA un equipo, la
// pantalla lo dice y manda a pedirlo desde su OT.
//
// SE PIDE, NO SE RETIRA
// El pedido no es un vale: queda esperando el visto bueno del jefe. Decirlo en
// la pantalla evita que el operador vaya a bodega con las manos vacías.
// ============================================================================

import { useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import {
  PackageSearch, ChevronLeft, Loader2, Plus, Search, Trash2, Clock,
  CheckCircle2, XCircle, Receipt, AlertTriangle,
} from 'lucide-react'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useAuth } from '@/contexts/auth-context'
import { buscarProductos } from '@/lib/services/ot-materiales'
import {
  getCecosTaller, solicitarInsumoTaller, getSeguimientoRecursos,
  type CecoTaller, type OTRecursoSeguimiento,
} from '@/lib/services/ot-recursos'
import { cn } from '@/lib/utils'

type ProductoLite = { id: string; codigo: string | null; nombre: string; unidad_medida: string | null }
type Linea = {
  key: string
  producto_id: string | null
  descripcion: string | null
  nombreVisible: string
  unidad: string | null
  cantidad: number
}

const ESTADO: Record<string, { t: string; c: string; i: typeof Clock }> = {
  solicitado: { t: 'Esperando al jefe', c: 'bg-amber-100 text-amber-800', i: Clock },
  aprobado:   { t: 'Aprobado', c: 'bg-blue-100 text-blue-800', i: CheckCircle2 },
  rechazado:  { t: 'Rechazado', c: 'bg-gray-200 text-gray-600', i: XCircle },
  en_vale:    { t: 'Con vale', c: 'bg-green-100 text-green-700', i: Receipt },
  en_compra:  { t: 'En compra', c: 'bg-purple-100 text-purple-700', i: Clock },
  recibido:   { t: 'Recibido', c: 'bg-green-100 text-green-700', i: CheckCircle2 },
}

export default function InsumosTallerPage() {
  useRequireAuth()
  const { perfil } = useAuth()
  const toast = useToast()

  const [ceco, setCeco] = useState('')
  const [lineas, setLineas] = useState<Linea[]>([])
  const [comentario, setComentario] = useState('')
  const [busy, setBusy] = useState(false)
  const [nro, setNro] = useState(0)

  const { data: cecos = [], isLoading: cargandoCecos } = useQuery({
    queryKey: ['cecos-taller'], queryFn: getCecosTaller, staleTime: 600_000,
  })
  const { data: seguimiento = [], refetch } = useQuery({
    queryKey: ['recursos-por-aprobar'], queryFn: getSeguimientoRecursos, staleTime: 20_000,
  })

  // Con un solo taller no hay nada que preguntar.
  useEffect(() => {
    if (!ceco && cecos.length === 1) setCeco(cecos[0].id)
  }, [cecos, ceco])

  // Lo que este operador pidió, para no volver a pedir lo mismo ni ir a bodega
  // antes de que el jefe lo mire.
  const mios = useMemo(
    () => seguimiento.filter((r) => r.es_insumo_taller).slice(0, 12),
    [seguimiento],
  )

  const listo = !!ceco && lineas.length > 0 && !busy

  const enviar = async () => {
    if (!listo) return
    setBusy(true)
    try {
      // Se manda uno por uno: el jefe aprueba o rechaza cada cosa por separado,
      // y una sola línea rechazada no puede botar el pedido completo.
      for (const l of lineas) {
        await solicitarInsumoTaller({
          cecoId: ceco,
          cantidad: l.cantidad,
          productoId: l.producto_id,
          descripcion: l.descripcion,
          unidad: l.unidad,
          comentario: comentario.trim() || null,
          solicitadoNombre: perfil?.nombre_completo ?? null,
          clientUuid: crypto.randomUUID(),
        })
      }
      toast.success(
        lineas.length === 1
          ? 'Pedido enviado. Queda esperando el visto bueno del jefe.'
          : `${lineas.length} insumos enviados. Quedan esperando el visto bueno del jefe.`,
      )
      setLineas([]); setComentario(''); setNro((n) => n + 1)
      refetch()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'No se pudo enviar el pedido')
    } finally { setBusy(false) }
  }

  return (
    <div className="space-y-3 p-3 pb-24">
      <div className="flex items-center gap-2">
        <Link href="/m/taller" className="rounded-lg border border-gray-300 p-2">
          <ChevronLeft className="h-4 w-4 text-gray-600" />
        </Link>
        <div className="min-w-0 flex-1">
          <h1 className="text-base font-bold text-gray-900">Pedir insumos</h1>
          <p className="text-[11px] text-gray-500">Lo del taller: guantes, trapos, discos, cinta</p>
        </div>
      </div>

      <p className="rounded-lg bg-blue-50 p-2.5 text-[11px] leading-snug text-blue-900">
        Esto no es un vale: el jefe lo revisa y recién ahí sale el papel para ir a bodega.
        Si el material es <strong>para un equipo</strong>, pídalo desde su orden de trabajo — así el
        costo queda con el trabajo que lo justifica.
      </p>

      <div className="rounded-xl border-2 border-gray-800 bg-white p-3">
        <label className="block">
          <span className="text-[11px] font-bold text-gray-700">1. ¿Para qué taller?</span>
          <select value={ceco} onChange={(e) => setCeco(e.target.value)}
                  className="mt-1 h-11 w-full rounded-lg border border-gray-300 px-2 text-sm">
            <option value="">Elegir…</option>
            {cecos.map((c: CecoTaller) => (
              <option key={c.id} value={c.id}>{c.nombre}</option>
            ))}
          </select>
          {cargandoCecos && <span className="text-[10px] text-gray-400">Cargando…</span>}
        </label>

        <div className="mt-3">
          <span className="text-[11px] font-bold text-gray-700">2. ¿Qué necesita?</span>
          <AgregarInsumo key={nro} onAdd={(l) => setLineas((ls) => [...ls, l])} />

          {lineas.length > 0 && (
            <div className="mt-1.5 space-y-1">
              {lineas.map((l) => (
                <div key={l.key} className="flex items-center gap-2 rounded-lg border border-gray-200 px-2.5 py-1.5">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm text-gray-800">{l.nombreVisible}</p>
                    {!l.producto_id && (
                      <p className="text-[10px] text-amber-800">
                        Escrito a mano: bodega lo amarra a un producto antes de entregar
                      </p>
                    )}
                  </div>
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
        </div>

        {lineas.length > 0 && (
          <>
            <label className="mt-3 block">
              <span className="text-[11px] font-bold text-gray-700">
                ¿Para qué? <span className="font-normal text-gray-400">— opcional</span>
              </span>
              <input value={comentario} onChange={(e) => setComentario(e.target.value)}
                     placeholder="Se acabaron los del pañol"
                     className="mt-1 w-full rounded-lg border border-gray-300 px-2 py-2 text-sm" />
            </label>

            <button onClick={enviar} disabled={!listo}
                    className="mt-3 flex w-full items-center justify-center gap-2 rounded-xl bg-gray-900 px-4 py-3 text-sm font-bold text-white disabled:opacity-40">
              {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <PackageSearch className="h-4 w-4" />}
              Enviar al jefe
            </button>
            {!ceco && (
              <p className="mt-1 text-center text-[11px] text-gray-500">Falta elegir el taller.</p>
            )}
          </>
        )}
      </div>

      {/* Lo pedido, para no ir a bodega antes de tiempo */}
      <div>
        <h2 className="mb-1.5 text-xs font-bold uppercase tracking-wide text-gray-500">
          Lo que se pidió
        </h2>
        {mios.length === 0 ? (
          <p className="rounded-xl border border-dashed border-gray-300 p-6 text-center text-xs text-gray-400">
            Todavía no hay pedidos de insumos.
          </p>
        ) : (
          <div className="space-y-1.5">
            {mios.map((r: OTRecursoSeguimiento) => {
              const e = ESTADO[r.estado] ?? ESTADO.solicitado
              const Icono = e.i
              const ajustada = r.cantidad_aprobada != null
                && Number(r.cantidad_aprobada) !== Number(r.cantidad)
              return (
                <div key={r.id} className="rounded-lg border border-gray-200 bg-white p-2.5">
                  <div className="flex items-center gap-2">
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-semibold text-gray-900">{r.descripcion}</p>
                      <p className="text-[11px] text-gray-500">
                        {r.cantidad}{r.unidad ? ` ${r.unidad}` : ''}
                        {r.ceco_nombre ? ` · ${r.ceco_nombre}` : ''}
                        {r.ticket_folio ? ` · ${r.ticket_folio}` : ''}
                      </p>
                    </div>
                    <span className={cn('inline-flex shrink-0 items-center gap-1 rounded-full px-2 py-1 text-[10px] font-semibold', e.c)}>
                      <Icono className="h-3 w-3" /> {e.t}
                    </span>
                  </div>
                  {ajustada && (
                    <p className="mt-1 flex items-start gap-1 text-[11px] leading-snug text-amber-800">
                      <AlertTriangle className="mt-px h-3 w-3 shrink-0" />
                      El jefe aprobó {String(r.cantidad_aprobada)} en vez de {String(r.cantidad)}.
                    </p>
                  )}
                  {r.nota_jefe && (
                    <p className="mt-0.5 text-[11px] italic text-gray-600">Jefe: {r.nota_jefe}</p>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}

/** Una línea: primero el catálogo, y si no está, a mano. */
function AgregarInsumo({ onAdd }: { onAdd: (l: Linea) => void }) {
  const [q, setQ] = useState('')
  const [res, setRes] = useState<ProductoLite[]>([])
  const [prod, setProd] = useState<ProductoLite | null>(null)
  const [cant, setCant] = useState('')
  const [buscando, setBuscando] = useState(false)
  // Elegido el producto, lo siguiente es siempre escribir cuánto.
  const cantRef = useRef<HTMLInputElement>(null)

  const buscar = async (texto: string) => {
    setQ(texto); setProd(null)
    if (texto.trim().length < 2) { setRes([]); return }
    setBuscando(true)
    try {
      const { data } = await buscarProductos(texto, 8)
      setRes((data ?? []) as ProductoLite[])
    } catch { setRes([]) } finally { setBuscando(false) }
  }

  const agregar = () => {
    const n = Number(String(cant).replace(',', '.'))
    if (!Number.isFinite(n) || n <= 0) return
    if (!prod && q.trim().length < 3) return
    onAdd({
      key: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
      producto_id: prod?.id ?? null,
      descripcion: prod ? null : q.trim(),
      nombreVisible: prod ? prod.nombre : q.trim(),
      unidad: prod?.unidad_medida ?? null,
      cantidad: n,
    })
    setQ(''); setProd(null); setCant(''); setRes([])
  }

  const alTeclear = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') { e.preventDefault(); agregar() }
  }

  return (
    <div className="mt-1 rounded-lg border border-dashed border-gray-300 p-2">
      <div className="flex gap-1.5">
        <div className="relative min-w-0 flex-1">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
          <input value={prod ? prod.nombre : q} onChange={(e) => buscar(e.target.value)}
                 onKeyDown={alTeclear}
                 placeholder="Buscar… o escribirlo si no está"
                 className="w-full rounded border border-gray-300 py-2 pl-8 pr-2 text-sm" />
          {buscando && (
            <Loader2 className="absolute right-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 animate-spin text-gray-400" />
          )}
        </div>
        <input ref={cantRef} value={cant} inputMode="decimal" placeholder="Cant."
               onChange={(e) => setCant(e.target.value.replace(/[^\d.,]/g, ''))}
               onKeyDown={alTeclear}
               className="w-20 rounded border border-gray-300 px-2 py-2 text-right text-sm tabular-nums" />
        <button type="button" onClick={agregar}
                disabled={!Number(String(cant).replace(',', '.')) || (!prod && q.trim().length < 3)}
                className="shrink-0 rounded bg-orange-600 px-2.5 text-white disabled:opacity-50">
          <Plus className="h-4 w-4" />
        </button>
      </div>

      {res.length > 0 && !prod && (
        <div className="mt-1 max-h-40 space-y-0.5 overflow-y-auto">
          {res.map((r) => (
            <button key={r.id} type="button"
                    onClick={() => { setProd(r); setRes([]); setTimeout(() => cantRef.current?.focus(), 0) }}
                    className="flex w-full items-center gap-2 rounded px-2 py-1.5 text-left text-xs hover:bg-gray-50">
              <span className="font-mono text-[10px] text-gray-500">{r.codigo}</span>
              <span className="min-w-0 flex-1 truncate">{r.nombre}</span>
              {r.unidad_medida && <span className="shrink-0 text-[10px] text-gray-400">{r.unidad_medida}</span>}
            </button>
          ))}
        </div>
      )}

      {!prod && q.trim().length >= 3 && res.length === 0 && !buscando && (
        <p className="mt-1 text-[10px] text-amber-800">
          No está en el catálogo: se pide como «{q.trim()}» y bodega lo amarra al entregar.
        </p>
      )}
    </div>
  )
}
