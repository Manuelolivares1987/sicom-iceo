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
import { enviarCorreoCompras } from '@/lib/services/correo-compras'
import { listarProveedoresActivos } from '@/lib/services/bodega-oc'

type Filtro = 'pedidos' | 'por_comprar' | 'en_compra' | 'recibido' | 'todos'
type ProductoLite = { id: string; codigo: string | null; nombre: string; unidad_medida: string | null }

const FILTROS: [Filtro, string][] = [
  // [03-09] Lo que el operador acaba de pedir en terreno, ANTES de que el jefe
  // lo apruebe. No es para actuar: es para que bodega vaya adelantando —mirar
  // si hay stock, dónde está, qué habría que cotizar si no hay.
  ['pedidos', 'Recién pedidos'],
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

// [21-09] Pedido del jefe de taller: «ver en bodega cuánto tiempo están los
// equipos sin que lleguen los repuestos». La tabla cuenta días por repuesto; acá
// se junta por EQUIPO: lo que falta llegar (por comprar u OC solicitada) y
// cuánto lleva esperando lo más antiguo. Lo recibido ya llegó y no cuenta.
function esperaRepuesto(f: OTRecursoSeguimiento) {
  return !f.es_insumo_taller && (f.por_comprar || f.estado === 'en_compra')
}

type EquipoEsperando = {
  clave: string
  patente: string | null
  codigo: string | null
  nombre: string | null
  ots: string[]
  items: number
  porComprar: number
  enCompra: number
  dias: number
  etaAtrasada: boolean
}

function EquiposEsperando({ filas, seleccionado, onSel }: {
  filas: OTRecursoSeguimiento[]
  seleccionado: string | null
  onSel: (clave: string | null) => void
}) {
  const equipos = useMemo(() => {
    const m = new Map<string, EquipoEsperando>()
    const hoy = new Date().toISOString().slice(0, 10)
    for (const f of filas) {
      if (!esperaRepuesto(f)) continue
      const clave = f.activo_codigo ?? f.activo_patente ?? f.ot_folio
      const e = m.get(clave) ?? {
        clave, patente: f.activo_patente, codigo: f.activo_codigo, nombre: f.activo_nombre,
        ots: [], items: 0, porComprar: 0, enCompra: 0, dias: 0, etaAtrasada: false,
      }
      if (!e.ots.includes(f.ot_folio)) e.ots.push(f.ot_folio)
      e.items += 1
      if (f.estado === 'en_compra') e.enCompra += 1; else e.porComprar += 1
      e.dias = Math.max(e.dias, f.dias_desde_solicitud)
      if (f.estado === 'en_compra' && f.oc_fecha_entrega && f.oc_fecha_entrega < hoy) e.etaAtrasada = true
      m.set(clave, e)
    }
    return Array.from(m.values()).sort((a, b) => b.dias - a.dias)
  }, [filas])

  if (equipos.length === 0) return null

  return (
    <Card>
      <CardContent className="p-4">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h2 className="flex items-center gap-2 text-sm font-bold text-gray-900">
            <Clock className="h-4 w-4 text-red-600" />
            Equipos esperando repuestos ({equipos.length})
          </h2>
          <p className="text-[11px] text-gray-500">
            Días desde que se pidió el repuesto más antiguo que aún no llega. Toca un equipo para ver sus repuestos.
          </p>
        </div>
        <div className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
          {equipos.map((e) => {
            const activo = seleccionado === e.clave
            const cls = e.dias >= 7 ? 'border-red-300 bg-red-50' : e.dias >= 3 ? 'border-amber-300 bg-amber-50' : 'border-gray-200 bg-white'
            return (
              <button key={e.clave} onClick={() => onSel(activo ? null : e.clave)}
                      className={`rounded-lg border p-2.5 text-left transition ${cls} ${activo ? 'ring-2 ring-orange-500' : 'hover:shadow-sm'}`}>
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="font-mono text-sm font-bold text-gray-900">{e.patente ?? e.codigo}</div>
                    <div className="truncate text-[11px] text-gray-500">
                      {[e.patente ? e.codigo : null, e.nombre].filter(Boolean).join(' · ')}
                    </div>
                  </div>
                  <div className="shrink-0 text-right">
                    <div className={`text-xl font-bold leading-none ${e.dias >= 7 ? 'text-red-700' : e.dias >= 3 ? 'text-amber-700' : 'text-gray-700'}`}>
                      {e.dias}
                    </div>
                    <div className="text-[10px] text-gray-500">{e.dias === 1 ? 'día' : 'días'}</div>
                  </div>
                </div>
                <div className="mt-1.5 text-[11px] text-gray-600">
                  {e.items} repuesto{e.items === 1 ? '' : 's'} sin llegar
                  {e.porComprar > 0 && <> · {e.porComprar} por comprar</>}
                  {e.enCompra > 0 && <> · {e.enCompra} con OC</>}
                  {e.etaAtrasada && <span className="ml-1 font-semibold text-red-600">· OC atrasada</span>}
                </div>
                <div className="mt-0.5 font-mono text-[10px] text-gray-400">{e.ots.join(' · ')}</div>
              </button>
            )
          })}
        </div>
      </CardContent>
    </Card>
  )
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

  // [MIG394] El mismo cuadro sirve para amarrar por primera vez y para corregir
  // el código: el catálogo tiene familias con varios códigos y quien pidió no
  // siempre eligió el correcto.
  const yaTiene = !!recurso.producto_id

  async function vincular(productoId: string) {
    setBusy(true)
    try {
      const r = await asignarProductoRecurso(recurso.id, productoId)
      toast.success(r.reasignado
        ? `Código corregido: ahora es ${r.producto}${r.codigo ? ` (${r.codigo})` : ''}`
        : 'Producto vinculado')
      onDone()
    }
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
    <Modal open onClose={onDone}
           title={yaTiene ? 'Corregir el código del repuesto' : 'Vincular a producto de bodega'}>
      <div className="space-y-3">
        <p className="text-sm text-gray-600">
          {yaTiene ? (
            <>Hoy figura como <b>{recurso.producto_nombre}</b>
              {recurso.producto_codigo && <span className="font-mono text-xs text-gray-500"> · {recurso.producto_codigo}</span>}
              . Si no es ese el código que hay que descontar, elige el correcto.</>
          ) : (
            <>«{recurso.descripcion}» no está amarrado al catálogo. Para comprarlo y que la recepción
              alimente el stock, vincúlalo a un producto (o créalo).</>
          )}
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
  const [equipoSel, setEquipoSel] = useState<string | null>(null)
  const [sel, setSel] = useState<Set<string>>(new Set())
  const [vincular, setVincular] = useState<OTRecursoSeguimiento | null>(null)
  // [03-09] Correo a compras con autorización explícita (fase de pruebas).
  const [cotizar, setCotizar] = useState<{ recursoId: string; nombre: string; cantidad: number } | null>(null)
  const [cotizarBusy, setCotizarBusy] = useState(false)
  async function confirmarCotizar() {
    if (!cotizar) return
    setCotizarBusy(true)
    const r = await enviarCorreoCompras(cotizar.recursoId)
    setCotizarBusy(false)
    if (r.ok) { toast.success(`Correo enviado a compras (${r.enviado_a})`); setCotizar(null) }
    else toast.error(r.error ?? 'No se pudo enviar el correo')
  }
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
    if (equipoSel) {
      return all.filter((f) => esperaRepuesto(f)
        && (f.activo_codigo ?? f.activo_patente ?? f.ot_folio) === equipoSel)
    }
    switch (filtro) {
      case 'pedidos':     return all.filter((f) => f.estado === 'solicitado')
      case 'por_comprar': return all.filter((f) => f.por_comprar)
      case 'en_compra':   return all.filter((f) => f.estado === 'en_compra')
      case 'recibido':    return all.filter((f) => f.estado === 'recibido')
      default:            return all
    }
  }, [filas, filtro, equipoSel])

  const counts = useMemo(() => {
    const all = (filas ?? []).filter((f) => f.estado !== 'rechazado')
    return {
      pedidos: all.filter((f) => f.estado === 'solicitado').length,
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

      <EquiposEsperando filas={filas ?? []} seleccionado={equipoSel} onSel={setEquipoSel} />

      <div className="flex flex-wrap gap-2">
        {FILTROS.map(([k, l]) => (
          <button key={k} onClick={() => { setFiltro(k); setEquipoSel(null) }}
                  className={`rounded-full border px-3 py-1 text-xs ${
                    filtro === k && !equipoSel ? 'bg-orange-600 text-white border-orange-600' : 'bg-white hover:bg-gray-50'}`}>
            {l} ({counts[k]})
          </button>
        ))}
        {equipoSel && (
          <button onClick={() => setEquipoSel(null)}
                  className="flex items-center gap-1 rounded-full border border-orange-600 bg-orange-600 px-3 py-1 text-xs text-white">
            Esperando: {equipoSel} <X className="h-3 w-3" />
          </button>
        )}
      </div>

      {filtro === 'pedidos' && counts.pedidos > 0 && (
        <p className="rounded-lg border border-blue-200 bg-blue-50 px-3 py-2 text-xs text-blue-800">
          Esto lo acaba de pedir el operador en terreno y <b>el jefe de taller aún no lo aprueba</b>.
          Sirve para adelantar: mira si hay stock, dónde está y qué habría que cotizar si no hay.
          La compra o el vale salen recién cuando el jefe apruebe (al analizar la NC).
        </p>
      )}

      <Card>
        <CardContent className="p-0 overflow-x-auto">
          {isLoading ? (
            <div className="p-6 text-center"><Spinner /></div>
          ) : lista.length === 0 ? (
            <p className="p-8 text-center text-sm text-gray-400">
              {filtro === 'por_comprar'
                ? 'Nada por comprar: no hay repuestos aprobados sin stock.'
                : filtro === 'pedidos'
                ? 'Nada recién pedido: el taller no tiene solicitudes esperando aprobación.'
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
                        {/* [MIG394] Mientras el recurso no esté en un vale, el
                            código se puede poner Y corregir: el catálogo tiene
                            familias con varios códigos y el primer amarre puede
                            estar equivocado. Ya en vale, se corrige allá (que es
                            donde se valida que no haya entrega parcial) y desde
                            allá se sincroniza de vuelta hacia acá. */}
                        {(f.estado === 'solicitado' || f.estado === 'aprobado') && (
                          <button onClick={() => setVincular(f)}
                                  className={`mt-1 flex items-center gap-1 rounded border px-2 py-0.5 text-[11px] font-semibold ${
                                    f.producto_id
                                      ? 'border-gray-300 bg-white text-gray-600 hover:bg-gray-50'
                                      : 'border-orange-300 bg-orange-50 text-orange-700'}`}>
                            <Package className="h-3 w-3" />
                            {f.producto_id ? 'Otro código' : 'Vincular a producto para comprar'}
                          </button>
                        )}
                        {/* [03-09] Fase de pruebas: el correo a compras sale solo
                            con autorización explícita, desde acá o desde el vale. */}
                        {f.por_comprar && (
                          <button onClick={() => setCotizar({ recursoId: f.id, nombre: f.producto_nombre ?? f.descripcion ?? 'ítem', cantidad: f.cantidad_aprobada ?? f.cantidad })}
                                  className="mt-1 flex items-center gap-1 rounded border border-violet-300 bg-violet-50 px-2 py-0.5 text-[11px] font-semibold text-violet-700">
                            ✉ Cotizar por correo a compras
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

      {/* [03-09] ¿Enviar correo a compras? Autorización explícita (fase de pruebas). */}
      {cotizar && (
        <Modal open onClose={() => setCotizar(null)} title="¿Enviar correo a compras?">
          <div className="space-y-3">
            <div className="rounded-lg border bg-gray-50 p-2 text-sm">
              <div className="font-medium text-gray-800">{cotizar.nombre}</div>
              <div className="text-xs text-gray-500">{cotizar.cantidad} para cotizar</div>
            </div>
            <p className="text-xs text-gray-600">
              Se enviará un correo a <b>compras</b> con la foto del repuesto, la descripción, el
              código y los datos del camión — todo lo necesario para cotizar. La respuesta te
              llega directo a ti.
            </p>
            <p className="text-[11px] text-gray-400">Nada sale automático: parte solo si tú lo autorizas aquí.</p>
          </div>
          <ModalFooter>
            <Button variant="outline" onClick={() => setCotizar(null)} disabled={cotizarBusy}>
              No, por ahora
            </Button>
            <Button disabled={cotizarBusy} onClick={confirmarCotizar}>
              {cotizarBusy ? <Spinner className="h-4 w-4 mr-1" /> : <ShoppingCart className="h-4 w-4 mr-1" />}
              Sí, enviar correo
            </Button>
          </ModalFooter>
        </Modal>
      )}
    </div>
  )
}
