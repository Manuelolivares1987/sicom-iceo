'use client'

// Seguimiento de compra de repuestos solicitados por el taller (MIG201).
// Cierra el cuello de botella: aprobado sin stock → generar OC → recepción
// (pasa solo a recibido) → vale. Aging visible por solicitud.

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Package, ShoppingCart, Clock, X, Plus, ExternalLink, RefreshCw, Search,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getSeguimientoRecursos, asignarProductoRecurso, crearProductoRapido, generarOcRecursos,
  registrarNumeroOcExterno, RECURSO_ESTADO_LABEL, type OTRecursoSeguimiento,
} from '@/lib/services/ot-recursos'
import { buscarProductos, } from '@/lib/services/ot-materiales'
import { listarProveedoresActivos } from '@/lib/services/bodega-oc'

type Filtro = 'por_comprar' | 'en_compra' | 'recibido' | 'todos'
type ProductoLite = { id: string; codigo: string | null; nombre: string; unidad_medida: string | null }

const FILTROS: [Filtro, string][] = [
  ['por_comprar', 'Por comprar'],
  ['en_compra', 'En compra'],
  ['recibido', 'Recibidos'],
  ['todos', 'Todos'],
]

function AgingBadge({ dias }: { dias: number }) {
  const cls = dias >= 7 ? 'bg-red-100 text-red-700' : dias >= 3 ? 'bg-amber-100 text-amber-800' : 'bg-gray-100 text-gray-600'
  return <span className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium ${cls}`}>
    <Clock className="h-3 w-3" /> {dias} d
  </span>
}

// Buscador/creador de producto para pedidos en texto libre.
function VincularProducto({ recurso, onDone }: { recurso: OTRecursoSeguimiento; onDone: () => void }) {
  const toast = useToast()
  const [q, setQ] = useState(recurso.descripcion ?? '')
  const [resultados, setResultados] = useState<ProductoLite[]>([])
  const [creando, setCreando] = useState(false)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (q.trim().length < 2) { setResultados([]); return }
    const t = setTimeout(async () => {
      try {
        const { data } = await buscarProductos(q, 8)
        setResultados((data ?? []) as ProductoLite[])
      } catch { setResultados([]) }
    }, 300)
    return () => clearTimeout(t)
  }, [q])

  async function vincular(productoId: string) {
    setBusy(true)
    try { await asignarProductoRecurso(recurso.id, productoId); toast.success('Producto vinculado'); onDone() }
    catch (e) { toast.error((e as Error).message) }
    finally { setBusy(false) }
  }
  async function crear() {
    setBusy(true); setCreando(true)
    try {
      const r = await crearProductoRapido({ nombre: q.trim() || (recurso.descripcion ?? 'Repuesto'), unidad: recurso.unidad ?? 'unidad' })
      await asignarProductoRecurso(recurso.id, r.producto_id)
      toast.success(`Producto ${r.codigo} creado y vinculado`)
      onDone()
    } catch (e) { toast.error((e as Error).message) }
    finally { setBusy(false); setCreando(false) }
  }

  return (
    <Modal open onClose={onDone} title="Vincular a producto de bodega">
      <div className="space-y-3">
        <p className="text-sm text-gray-600">
          «{recurso.descripcion}» no está amarrado al catálogo. Para comprarlo y que la recepción
          alimente el stock, vincúlalo a un producto (o créalo).
        </p>
        <div className="relative">
          <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-gray-400" />
          <Input value={q} onChange={(e) => setQ(e.target.value)} className="pl-8"
                 placeholder="Buscar en el catálogo…" />
        </div>
        {resultados.length > 0 && (
          <div className="overflow-hidden rounded-lg border border-gray-200">
            {resultados.map((p) => (
              <button key={p.id} disabled={busy} onClick={() => vincular(p.id)}
                      className="flex w-full items-center gap-2 border-b border-gray-100 bg-white px-3 py-2 text-left text-sm last:border-0 hover:bg-gray-50 disabled:opacity-50">
                <span className="flex-1">{p.nombre}</span>
                {p.codigo && <span className="font-mono text-[10px] text-gray-400">{p.codigo}</span>}
              </button>
            ))}
          </div>
        )}
        <Button variant="outline" disabled={busy || q.trim().length < 3} onClick={crear} className="w-full">
          {creando ? <Spinner className="h-4 w-4 mr-1" /> : <Plus className="h-4 w-4 mr-1" />}
          No existe — crear producto «{q.trim() || recurso.descripcion}»
        </Button>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onDone}>Cerrar</Button>
      </ModalFooter>
    </Modal>
  )
}

export default function SeguimientoRepuestosPage() {
  useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()
  const { data: filas, isLoading, refetch, isFetching } = useQuery({
    queryKey: ['seguimiento-repuestos'],
    queryFn: getSeguimientoRecursos,
    staleTime: 15_000,
  })
  const { data: provData } = useQuery({
    queryKey: ['proveedores-activos'],
    queryFn: async () => (await listarProveedoresActivos()).data ?? [],
    staleTime: 5 * 60_000,
  })

  const [filtro, setFiltro] = useState<Filtro>('por_comprar')
  const [sel, setSel] = useState<Set<string>>(new Set())
  const [vincular, setVincular] = useState<OTRecursoSeguimiento | null>(null)
  // Modal generar OC
  const [ocOpen, setOcOpen] = useState(false)
  const [proveedor, setProveedor] = useState('')
  const [numeroOc, setNumeroOc] = useState('')
  const [eta, setEta] = useState('')
  const [obsOc, setObsOc] = useState('')

  const generarOc = useMutation({
    mutationFn: generarOcRecursos,
    onSuccess: (r) => {
      toast.success(`Solicitud ${r.numero_oc} creada (${r.items} ítems) — cuando Softland emita la OC registra su N°; al recepcionar pasan solos a "Recibido"`)
      setOcOpen(false); setSel(new Set()); setProveedor(''); setNumeroOc(''); setEta(''); setObsOc('')
      qc.invalidateQueries({ queryKey: ['seguimiento-repuestos'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })

  const numExterno = useMutation({
    mutationFn: ({ ocId, numero }: { ocId: string; numero: string }) => registrarNumeroOcExterno(ocId, numero),
    onSuccess: () => {
      toast.success('N° de OC Softland registrado')
      qc.invalidateQueries({ queryKey: ['seguimiento-repuestos'] })
    },
    onError: (e) => toast.error((e as Error).message),
  })
  function pedirNumeroSoftland(f: OTRecursoSeguimiento) {
    const n = window.prompt(`N° de la OC emitida en Softland para la solicitud ${f.oc_numero}:`)
    if (n && n.trim() && f.oc_id) numExterno.mutate({ ocId: f.oc_id, numero: n.trim() })
  }

  const lista = useMemo(() => {
    const all = (filas ?? []).filter((f) => f.estado !== 'rechazado')
    switch (filtro) {
      case 'por_comprar': return all.filter((f) => f.por_comprar)
      case 'en_compra':   return all.filter((f) => f.estado === 'en_compra')
      case 'recibido':    return all.filter((f) => f.estado === 'recibido')
      default:            return all
    }
  }, [filas, filtro])

  const counts = useMemo(() => {
    const all = (filas ?? []).filter((f) => f.estado !== 'rechazado')
    return {
      por_comprar: all.filter((f) => f.por_comprar).length,
      en_compra: all.filter((f) => f.estado === 'en_compra').length,
      recibido: all.filter((f) => f.estado === 'recibido').length,
      todos: all.length,
    }
  }, [filas])

  const seleccionables = lista.filter((f) => f.por_comprar && f.producto_id)
  const nSel = sel.size

  function toggleSel(id: string) {
    setSel((p) => { const n = new Set(p); if (n.has(id)) { n.delete(id) } else { n.add(id) }; return n })
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold flex items-center gap-2">
            <ShoppingCart className="h-5 w-5 text-orange-600" /> Seguimiento de repuestos
          </h1>
          <p className="text-sm text-gray-500 mt-0.5">
            Pedidos del taller sin stock: aquí se compran y se sigue cada etapa hasta la entrega.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button variant="outline" onClick={() => refetch()} disabled={isFetching}>
            <RefreshCw className={`h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} />
          </Button>
          <Button disabled={nSel === 0} onClick={() => setOcOpen(true)}>
            <ShoppingCart className="h-4 w-4 mr-1" /> Solicitar OC ({nSel})
          </Button>
        </div>
      </div>

      <div className="flex flex-wrap gap-2">
        {FILTROS.map(([k, l]) => (
          <button key={k} onClick={() => setFiltro(k)}
                  className={`rounded-full border px-3 py-1 text-xs ${
                    filtro === k ? 'bg-orange-600 text-white border-orange-600' : 'bg-white hover:bg-gray-50'}`}>
            {l} ({counts[k]})
          </button>
        ))}
      </div>

      <Card>
        <CardContent className="p-0 overflow-x-auto">
          {isLoading ? (
            <div className="p-6 text-center"><Spinner /></div>
          ) : lista.length === 0 ? (
            <p className="p-8 text-center text-sm text-gray-400">
              {filtro === 'por_comprar'
                ? 'Nada por comprar: no hay repuestos aprobados sin stock.'
                : 'Sin repuestos en esta etapa.'}
            </p>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="text-xs text-gray-500 border-b">
                  <th className="p-2 w-8"></th>
                  <th className="text-left p-2">Repuesto</th>
                  <th className="text-left p-2">OT / Equipo</th>
                  <th className="text-right p-2">Cant.</th>
                  <th className="text-right p-2">Stock</th>
                  <th className="text-left p-2">Estado</th>
                  <th className="text-left p-2">OC (Softland) / ETA</th>
                  <th className="text-right p-2">Espera</th>
                </tr>
              </thead>
              <tbody>
                {lista.map((f) => {
                  const chip = RECURSO_ESTADO_LABEL[f.estado]
                  const selectable = f.por_comprar && !!f.producto_id
                  return (
                    <tr key={f.id} className="border-b hover:bg-gray-50/60">
                      <td className="p-2 text-center">
                        {selectable && (
                          <input type="checkbox" checked={sel.has(f.id)} onChange={() => toggleSel(f.id)} />
                        )}
                      </td>
                      <td className="p-2">
                        <div className="font-medium text-gray-800">
                          {f.producto_nombre ?? f.descripcion}
                          {f.producto_codigo && <span className="ml-1 font-mono text-[10px] text-gray-400">{f.producto_codigo}</span>}
                        </div>
                        <div className="text-[11px] text-gray-500">
                          {f.solicitado_nombre ?? (f.agregado_por_jefe ? 'jefatura' : '—')}
                          {f.comentario && <span className="italic"> · «{f.comentario}»</span>}
                        </div>
                        {(f.fotos?.length ?? 0) > 0 && (
                          <div className="mt-1 flex gap-1">
                            {(f.fotos ?? []).map((url, i) => (
                              <a key={i} href={url} target="_blank" rel="noreferrer">
                                {/* eslint-disable-next-line @next/next/no-img-element */}
                                <img src={url} alt="foto" className="h-9 w-9 rounded border object-cover hover:opacity-80" />
                              </a>
                            ))}
                          </div>
                        )}
                        {f.por_comprar && !f.producto_id && (
                          <button onClick={() => setVincular(f)}
                                  className="mt-1 flex items-center gap-1 rounded border border-orange-300 bg-orange-50 px-2 py-0.5 text-[11px] font-semibold text-orange-700">
                            <Package className="h-3 w-3" /> Vincular a producto para comprar
                          </button>
                        )}
                      </td>
                      <td className="p-2 whitespace-nowrap">
                        <div className="font-mono text-xs font-semibold">{f.ot_folio}</div>
                        <div className="text-[11px] text-gray-500">{f.activo_codigo}{f.activo_patente ? ` · ${f.activo_patente}` : ''}</div>
                      </td>
                      <td className="p-2 text-right whitespace-nowrap">
                        {f.cantidad_aprobada ?? f.cantidad} {f.unidad ?? 'un'}
                      </td>
                      <td className="p-2 text-right">
                        {f.producto_id
                          ? <span className={Number(f.stock_total ?? 0) > 0 ? 'text-gray-600' : 'font-semibold text-red-600'}>{f.stock_total ?? 0}</span>
                          : <span className="text-[11px] text-orange-600">sin catálogo</span>}
                      </td>
                      <td className="p-2">
                        <span className={`rounded-full px-2 py-0.5 text-[11px] font-medium whitespace-nowrap ${chip.cls}`}>
                          {chip.label}
                        </span>
                        {f.estado === 'en_vale' && f.ticket_folio && (
                          <div className="mt-0.5 font-mono text-[10px] text-gray-500">{f.ticket_folio}</div>
                        )}
                      </td>
                      <td className="p-2">
                        {f.oc_numero ? (
                          <Link href={`/dashboard/abastecimiento/oc/${f.oc_id}`}
                                className="text-blue-600 hover:underline flex items-center gap-1 text-xs">
                            {f.oc_numero_externo ?? `${f.oc_numero} (solicitud)`} <ExternalLink className="h-3 w-3" />
                          </Link>
                        ) : <span className="text-[11px] text-gray-400">—</span>}
                        {f.oc_numero && (
                          <div className="text-[11px] text-gray-500">
                            {f.oc_proveedor}
                            {f.oc_fecha_entrega && <> · llega {new Date(f.oc_fecha_entrega + 'T12:00:00').toLocaleDateString('es-CL', { day: '2-digit', month: 'short' })}</>}
                            {f.estado === 'en_compra' && f.oc_fecha_entrega && new Date(f.oc_fecha_entrega) < new Date() && (
                              <span className="ml-1 font-semibold text-red-600">atrasada</span>
                            )}
                          </div>
                        )}
                        {f.estado === 'en_compra' && !f.oc_numero_externo && (
                          <button onClick={() => pedirNumeroSoftland(f)} disabled={numExterno.isPending}
                                  className="mt-0.5 rounded border border-purple-300 bg-purple-50 px-1.5 py-0.5 text-[10px] font-semibold text-purple-700 disabled:opacity-50">
                            + N° OC Softland
                          </button>
                        )}
                      </td>
                      <td className="p-2 text-right"><AgingBadge dias={f.dias_desde_solicitud} /></td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>

      {filtro === 'por_comprar' && seleccionables.length > 0 && (
        <p className="text-xs text-gray-500">
          Marca los repuestos y pulsa «Solicitar OC»: queda la solicitud con proveedor y fecha
          estimada. La OC oficial la emite el área especialista <b>en Softland</b> (registra su N°
          en la fila) y al <b>recepcionar</b> (Listado OCs → Recepcionar) cada repuesto pasa solo a
          «Recibido» y le avisa al jefe de taller para emitir el vale.
        </p>
      )}

      {vincular && (
        <VincularProducto recurso={vincular}
                          onDone={() => { setVincular(null); qc.invalidateQueries({ queryKey: ['seguimiento-repuestos'] }) }} />
      )}

      {ocOpen && (
        <Modal open onClose={() => setOcOpen(false)} title={`Solicitud de OC (${nSel} repuestos)`}>
          <div className="space-y-3">
            <p className="text-xs text-gray-500">
              La OC oficial la emite el área especialista en Softland. Esta solicitud deja la
              trazabilidad: cuando Softland la emita, registra su N° en la fila del repuesto.
            </p>
            <div>
              <label className="text-xs font-medium">Proveedor <span className="text-red-500">*</span></label>
              <select value={proveedor} onChange={(e) => setProveedor(e.target.value)}
                      className="w-full border rounded px-2 py-1.5 text-sm">
                <option value="">Elegir proveedor…</option>
                {(provData ?? []).map((p) => (
                  <option key={p.id} value={p.id}>{p.nombre}{p.rut ? ` (${p.rut})` : ''}</option>
                ))}
              </select>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs font-medium">N° OC Softland (si ya existe)</label>
                <Input value={numeroOc} onChange={(e) => setNumeroOc(e.target.value)} placeholder="Se puede registrar después" />
              </div>
              <div>
                <label className="text-xs font-medium">Fecha estimada de llegada</label>
                <Input type="date" value={eta} onChange={(e) => setEta(e.target.value)} />
              </div>
            </div>
            <div>
              <label className="text-xs font-medium">Observación</label>
              <Input value={obsOc} onChange={(e) => setObsOc(e.target.value)} placeholder="opcional" />
            </div>
            <ul className="rounded-lg border border-gray-100 bg-gray-50 p-2 text-xs text-gray-600 space-y-0.5 max-h-40 overflow-y-auto">
              {lista.filter((f) => sel.has(f.id)).map((f) => (
                <li key={f.id}>• {f.producto_nombre ?? f.descripcion} — {f.cantidad_aprobada ?? f.cantidad} {f.unidad ?? 'un'} ({f.ot_folio})</li>
              ))}
            </ul>
          </div>
          <ModalFooter>
            <Button variant="outline" onClick={() => setOcOpen(false)}><X className="h-4 w-4 mr-1" /> Cancelar</Button>
            <Button disabled={!proveedor || generarOc.isPending}
                    onClick={() => generarOc.mutate({
                      recursoIds: Array.from(sel), proveedorId: proveedor,
                      numeroOc: numeroOc.trim() || null, fechaEntrega: eta || null,
                      observacion: obsOc.trim() || null,
                    })}>
              {generarOc.isPending ? <Spinner className="h-4 w-4 mr-1" /> : <ShoppingCart className="h-4 w-4 mr-1" />}
              Generar OC
            </Button>
          </ModalFooter>
        </Modal>
      )}
    </div>
  )
}
