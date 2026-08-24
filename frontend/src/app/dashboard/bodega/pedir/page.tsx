'use client'

// ============================================================================
// Pedirle algo a bodega (MIG374/375)
// ----------------------------------------------------------------------------
// La entrada de oficina. Todo lo que llegaba a bodega venía del taller —de un
// hallazgo, de una OT o del pedido manual contra una patente—. El tóner, las
// resmas y lo de aseo se pedían de palabra: sin papel, sin folio y sin quedar
// cargados a ningún centro de costo.
//
// DOS CAMINOS, Y NO SON LO MISMO
//
//   · RETIRAR LO QUE HAY. Sale el mismo vale físico que el del taller —folio,
//     QR e ítems, para imprimir y retirar—. Lo que cambia es a qué se carga: el
//     del taller va contra el equipo; éste, contra el centro de costo del área.
//     Así el gasto de administración deja de ser invisible a fin de mes.
//
//   · PEDIR QUE LO COMPREN. Si no está en el catálogo o bodega no lo tiene, el
//     vale no sirve: no se puede descontar lo que no existe. Queda como
//     solicitud, y bodega la resuelve comprando.
//
// QUIEN RETIRA ES QUIEN FIRMA
// El vale del taller lo autoriza el jefe porque el material se le carga a un
// equipo que él responde. Acá el control es otro: el gasto queda con el nombre
// de quien pidió y con el centro de costo al que se cargó.
//
// SIN GATE DE MÓDULO
// Quien pide un tóner es de administración, de prevención o de comercial, y
// ninguno tiene el permiso de bodega. Lo que sí necesita es sesión.
// ============================================================================

import { useEffect, useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  PackageSearch, Send, Loader2, CheckCircle2, Clock, XCircle, Truck, Search, X,
  Receipt, ShoppingCart, Printer,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useAuth } from '@/contexts/auth-context'
import {
  solicitarMaterialBodega, getMisSolicitudesBodega, type BodegaSolicitud,
} from '@/lib/services/bodega-solicitudes'
import {
  getEquiposParaVale, getCecosArea, getBodegas, crearValeOficina, getMisVales,
  subirFirmaTicket, type EquipoParaVale, type BodegaTicket,
} from '@/lib/services/bodega-tickets'
import {
  AgregarLineaVale, ListaLineasVale, aItemsRpc, type LineaVale,
} from '@/components/bodega/lineas-vale'
import { cn } from '@/lib/utils'

const AREAS = ['Oficina', 'Prevención', 'Taller', 'Terreno', 'Aseo y casino'] as const

const ESTADO = {
  pendiente: { t: 'Esperando', c: 'bg-amber-100 text-amber-800', i: Clock },
  atendida:  { t: 'Entregada', c: 'bg-green-100 text-green-700', i: CheckCircle2 },
  rechazada: { t: 'Rechazada', c: 'bg-gray-200 text-gray-600', i: XCircle },
} as const

const ESTADO_VALE = {
  emitido:   { t: 'Por retirar', c: 'bg-blue-100 text-blue-800' },
  parcial:   { t: 'Entrega parcial', c: 'bg-amber-100 text-amber-800' },
  entregado: { t: 'Retirado', c: 'bg-green-100 text-green-700' },
  anulado:   { t: 'Anulado', c: 'bg-gray-200 text-gray-600' },
} as const

type Camino = 'vale' | 'compra'

export default function PedirABodegaPage() {
  useRequireAuth()
  const { perfil } = useAuth()
  const [camino, setCamino] = useState<Camino>('vale')

  return (
    <div className="mx-auto max-w-3xl space-y-6 p-6">
      <div className="flex items-center gap-3">
        <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-orange-600 text-white">
          <PackageSearch className="h-5 w-5" />
        </div>
        <div>
          <h1 className="text-xl font-bold text-gray-900">Pedirle algo a bodega</h1>
          <p className="text-xs text-gray-500">
            Para lo que no viene de un hallazgo ni de una orden de trabajo: útiles, tóner,
            insumos de aseo, lo que haga falta.
          </p>
        </div>
      </div>

      {/* Los dos caminos, con la diferencia dicha antes de elegir */}
      <div className="grid grid-cols-2 gap-2">
        <BotonCamino activo={camino === 'vale'} onClick={() => setCamino('vale')}
                     icono={Receipt} titulo="Retirar de bodega"
                     bajada="Sale el vale con folio para imprimir y retirar" />
        <BotonCamino activo={camino === 'compra'} onClick={() => setCamino('compra')}
                     icono={ShoppingCart} titulo="Pedir que lo compren"
                     bajada="Cuando bodega no lo tiene o no está en el catálogo" />
      </div>

      {camino === 'vale' ? <ValeDeOficina /> : <SolicitudDeCompra />}

      {perfil?.nombre_completo && (
        <p className="text-center text-[11px] text-gray-400">
          Pidiendo como {perfil.nombre_completo}{perfil.cargo ? ` · ${perfil.cargo}` : ''}
        </p>
      )}
    </div>
  )
}

function BotonCamino({ activo, onClick, icono: Icono, titulo, bajada }: {
  activo: boolean; onClick: () => void
  icono: typeof Receipt; titulo: string; bajada: string
}) {
  return (
    <button type="button" onClick={onClick}
            className={cn('rounded-xl border-2 p-3 text-left transition',
                          activo ? 'border-orange-500 bg-orange-50' : 'border-gray-200 bg-white hover:border-gray-300')}>
      <span className="flex items-center gap-2">
        <Icono className={cn('h-4 w-4', activo ? 'text-orange-600' : 'text-gray-400')} />
        <span className={cn('text-sm font-bold', activo ? 'text-orange-900' : 'text-gray-700')}>{titulo}</span>
      </span>
      <span className="mt-0.5 block text-[11px] leading-snug text-gray-500">{bajada}</span>
    </button>
  )
}

// ══ Camino 1: el vale físico, cargado a un centro de costo ══════════════════

function ValeDeOficina() {
  const toast = useToast()
  const [ceco, setCeco] = useState('')
  const [bodegaId, setBodegaId] = useState('')
  const [lineas, setLineas] = useState<LineaVale[]>([])
  const [motivo, setMotivo] = useState('')
  const [observacion, setObservacion] = useState('')
  const [firma, setFirma] = useState('')
  const [busy, setBusy] = useState(false)

  const { data: cecos = [] } = useQuery({
    queryKey: ['cecos-area'], queryFn: getCecosArea, staleTime: 600_000,
  })
  const { data: bodegas = [] } = useQuery({
    queryKey: ['bodegas'], queryFn: getBodegas, staleTime: 600_000,
  })
  const { data: vales = [], refetch } = useQuery({
    queryKey: ['mis-vales'], queryFn: getMisVales, staleTime: 15_000,
  })

  // Con una sola bodega no hay nada que preguntar: se elige sola.
  useEffect(() => {
    if (!bodegaId && bodegas.length === 1) setBodegaId(bodegas[0].id)
  }, [bodegas, bodegaId])

  const listo = !!ceco && lineas.length > 0 && motivo.trim().length >= 5 && !!firma

  const emitir = async () => {
    if (!listo) return
    setBusy(true)
    try {
      const url = await subirFirmaTicket(firma, 'vale-oficina')
      const r = await crearValeOficina({
        cecoId: ceco,
        items: aItemsRpc(lineas),
        motivo: motivo.trim(),
        firmaUrl: url,
        bodegaId: bodegaId || null,
        observacion: observacion.trim() || null,
      })
      toast.success(
        r.items_sin_catalogo > 0
          ? `Vale ${r.folio} emitido, cargado a ${r.ceco_nombre}. ${r.items_sin_catalogo} ítem(s) sin producto del catálogo: bodega los amarra antes de despachar.`
          : `Vale ${r.folio} emitido y cargado a ${r.ceco_nombre}. Imprímalo y llévelo a bodega.`,
      )
      // El vale se abre solo: el papel es el punto de todo esto.
      window.open(`/vale/${r.ticket_id}`, '_blank')
      setLineas([]); setMotivo(''); setObservacion(''); setFirma('')
      refetch()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'No se pudo emitir el vale')
    } finally { setBusy(false) }
  }

  return (
    <>
      <Card>
        <CardContent className="space-y-4 p-5">
          <p className="rounded-lg bg-blue-50 p-2.5 text-[11px] leading-snug text-blue-900">
            Sale el mismo vale con folio y QR que usa el taller, pero cargado a un centro de costo en
            vez de a un equipo. Se imprime, se firma y con eso bodega entrega.
          </p>

          {/* ── 1. A qué se carga ─────────────────────────────────────── */}
          <div>
            <label className="text-sm font-semibold text-gray-800">
              1. ¿A qué centro de costo se carga?
            </label>
            <select value={ceco} onChange={(e) => setCeco(e.target.value)}
                    className="mt-1 h-10 w-full rounded-md border border-gray-300 px-2 text-sm">
              <option value="">Elegir…</option>
              {cecos.map((c) => (
                <option key={c.id} value={c.id}>{c.nombre} · {c.codigo}</option>
              ))}
            </select>
            <p className="mt-0.5 text-[10px] text-gray-500">
              Es el gasto del área, no el de un equipo. Lo que se retira contra una patente va por el
              vale del taller.
            </p>
          </div>

          {/* ── 2. Qué se retira ──────────────────────────────────────── */}
          <div>
            <label className="text-sm font-semibold text-gray-800">2. ¿Qué se retira?</label>
            <AgregarLineaVale onAdd={(l) => setLineas((ls) => [...ls, l])} />
            <ListaLineasVale lineas={lineas}
                             onQuitar={(k) => setLineas((ls) => ls.filter((x) => x.key !== k))} />
          </div>

          {/* ── 3. Por qué y quién firma ──────────────────────────────── */}
          {lineas.length > 0 && (
            <>
              <label className="block text-sm font-semibold text-gray-800">
                3. ¿Para qué es? <span className="font-normal text-gray-500">— obligatorio</span>
                <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={2}
                          placeholder="Insumos de la oficina de administración del mes"
                          className="mt-0.5 w-full rounded-md border border-gray-300 px-2 py-1.5 text-sm font-normal" />
                <span className="mt-0.5 block text-[10px] font-normal text-gray-500">
                  Es lo único que va a explicar este gasto cuando se revise el costo del centro a fin
                  de mes.
                </span>
              </label>

              {bodegas.length > 1 && (
                <label className="block text-sm font-semibold text-gray-800">
                  ¿En qué bodega retira?
                  <select value={bodegaId} onChange={(e) => setBodegaId(e.target.value)}
                          className="mt-0.5 h-10 w-full rounded-md border border-gray-300 px-2 text-sm font-normal">
                    <option value="">La que tenga el stock</option>
                    {bodegas.map((b) => <option key={b.id} value={b.id}>{b.nombre}</option>)}
                  </select>
                </label>
              )}

              <label className="block text-sm font-semibold text-gray-800">
                Algo más que bodega deba saber <span className="font-normal text-gray-500">— opcional</span>
                <Input value={observacion} onChange={(e) => setObservacion(e.target.value)}
                       placeholder="Quién retira, cuándo, dónde dejarlo" className="mt-0.5 font-normal" />
              </label>

              <SignaturePad label="Su firma (obligatoria)" onCapture={setFirma} />

              <Button onClick={emitir} disabled={!listo || busy} className="w-full">
                {busy ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" /> : <Printer className="mr-1.5 h-4 w-4" />}
                Emitir el vale e imprimirlo
              </Button>
              {!listo && !busy && (
                <p className="text-center text-[11px] text-gray-500">
                  {!ceco ? 'Falta elegir el centro de costo.'
                    : motivo.trim().length < 5 ? 'Falta decir para qué es el pedido.'
                    : !firma ? 'Falta su firma.' : ''}
                </p>
              )}
            </>
          )}
        </CardContent>
      </Card>

      {/* Los vales propios: para no llamar a bodega a preguntar */}
      <div>
        <h2 className="mb-2 text-sm font-bold uppercase tracking-wide text-gray-500">Mis vales</h2>
        {vales.length === 0 ? (
          <p className="rounded-lg border border-dashed border-gray-300 p-6 text-center text-sm text-gray-400">
            Todavía no ha emitido ningún vale.
          </p>
        ) : (
          <div className="space-y-2">
            {vales.map((v: BodegaTicket) => {
              const e = ESTADO_VALE[v.estado] ?? ESTADO_VALE.emitido
              return (
                <a key={v.id} href={`/vale/${v.id}`} target="_blank" rel="noreferrer"
                   className="flex items-center gap-3 rounded-lg border border-gray-200 bg-white p-3 hover:border-orange-300">
                  <Receipt className="h-4 w-4 shrink-0 text-gray-400" />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-semibold text-gray-900">{v.folio}</p>
                    <p className="truncate text-xs text-gray-500">
                      {v.ceco_nombre ?? v.activo_patente ?? '—'}
                      {' · '}{v.n_items} ítem{v.n_items === 1 ? '' : 's'}
                      {' · '}{new Date(v.created_at).toLocaleDateString('es-CL')}
                    </p>
                  </div>
                  <span className={cn('inline-flex shrink-0 items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold', e.c)}>
                    {e.t}
                  </span>
                </a>
              )
            })}
          </div>
        )}
      </div>
    </>
  )
}

// ══ Camino 2: la solicitud, cuando no hay qué retirar ═══════════════════════

function SolicitudDeCompra() {
  const toast = useToast()
  const [descripcion, setDescripcion] = useState('')
  const [cantidad, setCantidad] = useState('1')
  const [unidad, setUnidad] = useState('')
  const [area, setArea] = useState<string>('Oficina')
  const [observacion, setObservacion] = useState('')
  const [equipo, setEquipo] = useState<EquipoParaVale | null>(null)
  const [buscarEq, setBuscarEq] = useState('')
  const [busy, setBusy] = useState(false)

  const { data: mias = [], refetch } = useQuery({
    queryKey: ['mis-solicitudes-bodega'],
    queryFn: getMisSolicitudesBodega,
    staleTime: 15_000,
  })

  // El equipo sólo se busca si de verdad lo van a usar: la mayoría de los
  // pedidos de oficina no son para una patente.
  const { data: equipos = [] } = useQuery({
    queryKey: ['equipos-para-vale'],
    queryFn: getEquiposParaVale,
    staleTime: 300_000,
    enabled: buscarEq.trim().length > 0,
  })
  const sugerencias = useMemo(() => {
    const q = buscarEq.trim().toLowerCase()
    if (!q) return []
    return equipos.filter((e) =>
      (e.patente ?? '').toLowerCase().includes(q)
      || e.codigo.toLowerCase().includes(q)
      || (e.nombre ?? '').toLowerCase().includes(q)).slice(0, 8)
  }, [equipos, buscarEq])

  const cant = Number(String(cantidad).replace(',', '.'))
  const listo = descripcion.trim().length >= 3 && Number.isFinite(cant) && cant > 0

  const pedir = async () => {
    if (!listo) return
    setBusy(true)
    try {
      await solicitarMaterialBodega({
        descripcion: descripcion.trim(),
        cantidad: cant,
        unidad: unidad.trim() || null,
        observacion: observacion.trim() || null,
        activoId: equipo?.id ?? null,
        area,
      })
      toast.success('Pedido enviado a bodega. Queda con su nombre y con la fecha.')
      setDescripcion(''); setCantidad('1'); setUnidad(''); setObservacion('')
      setEquipo(null); setBuscarEq('')
      refetch()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'No se pudo enviar el pedido')
    } finally { setBusy(false) }
  }

  return (
    <>
      <Card>
        <CardContent className="space-y-4 p-5">
          <p className="rounded-lg bg-gray-50 p-2.5 text-[11px] leading-snug text-gray-700">
            Esto no descuenta stock ni emite vale: es un pedido para que bodega lo consiga. Cuando
            llegue, el retiro se hace con un vale.
          </p>

          <label className="block">
            <span className="text-sm font-semibold text-gray-800">¿Qué necesita?</span>
            <Input value={descripcion} onChange={(e) => setDescripcion(e.target.value)}
                   placeholder="Tóner Brother TN-1060 negro" className="mt-1" />
          </label>

          <div className="grid grid-cols-3 gap-3">
            <label className="block">
              <span className="text-sm font-semibold text-gray-800">Cantidad</span>
              <Input value={cantidad} onChange={(e) => setCantidad(e.target.value.replace(/[^\d.,]/g, ''))}
                     inputMode="decimal" className="mt-1" />
            </label>
            <label className="block">
              <span className="text-sm font-semibold text-gray-800">Unidad</span>
              <Input value={unidad} onChange={(e) => setUnidad(e.target.value)}
                     placeholder="unidad, caja, litro" className="mt-1" />
            </label>
            <label className="block">
              <span className="text-sm font-semibold text-gray-800">¿Para quién?</span>
              <select value={area} onChange={(e) => setArea(e.target.value)}
                      className="mt-1 h-10 w-full rounded-md border border-gray-300 px-2 text-sm">
                {AREAS.map((a) => <option key={a} value={a}>{a}</option>)}
              </select>
            </label>
          </div>

          {/* El equipo, sólo si el pedido es para una patente */}
          <div>
            <span className="text-sm font-semibold text-gray-800">
              ¿Es para un equipo? <span className="font-normal text-gray-500">— opcional</span>
            </span>
            {equipo ? (
              <div className="mt-1 flex items-center gap-3 rounded-lg border-2 border-orange-500 bg-orange-50 px-3 py-2">
                <Truck className="h-4 w-4 shrink-0 text-orange-600" />
                <span className="font-bold text-gray-800">{equipo.patente ?? equipo.codigo}</span>
                <span className="min-w-0 flex-1 truncate text-xs text-gray-500">{equipo.nombre}</span>
                <button type="button" onClick={() => setEquipo(null)} aria-label="Quitar"
                        className="shrink-0 text-orange-700"><X className="h-4 w-4" /></button>
              </div>
            ) : (
              <>
                <div className="relative mt-1">
                  <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
                  <input value={buscarEq} onChange={(e) => setBuscarEq(e.target.value)}
                         placeholder="Buscar patente… (déjelo vacío si no es para un equipo)"
                         className="w-full rounded-md border border-gray-300 py-2 pl-8 pr-2 text-sm" />
                </div>
                {sugerencias.length > 0 && (
                  <div className="mt-1 max-h-40 space-y-0.5 overflow-y-auto rounded-lg border border-gray-200 p-1">
                    {sugerencias.map((e) => (
                      <button key={e.id} type="button"
                              onClick={() => { setEquipo(e); setBuscarEq('') }}
                              className="flex w-full items-center gap-2 rounded px-2 py-1.5 text-left text-sm hover:bg-gray-50">
                        <span className="font-bold text-gray-800">{e.patente ?? e.codigo}</span>
                        <span className="min-w-0 flex-1 truncate text-xs text-gray-500">{e.nombre}</span>
                      </button>
                    ))}
                  </div>
                )}
              </>
            )}
          </div>

          <label className="block">
            <span className="text-sm font-semibold text-gray-800">
              Algo más que bodega deba saber <span className="font-normal text-gray-500">— opcional</span>
            </span>
            <Input value={observacion} onChange={(e) => setObservacion(e.target.value)}
                   placeholder="Para cuándo se necesita, dónde dejarlo, marca equivalente que sirve"
                   className="mt-1" />
          </label>

          <Button onClick={pedir} disabled={!listo || busy} className="w-full">
            {busy ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" /> : <Send className="mr-1.5 h-4 w-4" />}
            Enviar el pedido
          </Button>
          <p className="text-center text-[11px] text-gray-500">
            Queda con su nombre y la fecha. Bodega lo ve en «Pedidos a bodega» y contesta ahí mismo.
          </p>
        </CardContent>
      </Card>

      {/* Lo que uno mismo pidió: para no tener que llamar a preguntar */}
      <div>
        <h2 className="mb-2 text-sm font-bold uppercase tracking-wide text-gray-500">Mis pedidos</h2>
        {mias.length === 0 ? (
          <p className="rounded-lg border border-dashed border-gray-300 p-6 text-center text-sm text-gray-400">
            Todavía no ha pedido nada.
          </p>
        ) : (
          <div className="space-y-2">
            {mias.map((s: BodegaSolicitud) => {
              const e = ESTADO[s.estado] ?? ESTADO.pendiente
              const Icono = e.i
              return (
                <div key={s.id} className="flex items-center gap-3 rounded-lg border border-gray-200 bg-white p-3">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-semibold text-gray-900">{s.descripcion}</p>
                    <p className="text-xs text-gray-500">
                      {s.cantidad}{s.unidad ? ` ${s.unidad}` : ''}
                      {s.area ? ` · ${s.area}` : ''}
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
        )}
      </div>
    </>
  )
}
