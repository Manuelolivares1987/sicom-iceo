'use client'

import { useEffect, useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import QRCode from 'qrcode'
import {
  Ticket, Truck, ScanLine, Printer, Search, CheckCircle2, AlertTriangle, PenLine, History, X,
  PackageSearch, Image as ImageIcon, Check, Loader2, ChevronLeft,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { SignaturePad } from '@/components/ui/signature-pad'
import { BarcodeScanner } from '@/components/ui/barcode-scanner'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  useTicketsEmitibles, useTickets, useTicketItems, useBodegasTaller, useStockProductos,
  useCrearTicket, useEntregarTicket, useAnularTicket,
} from '@/hooks/use-bodega-tickets'
import {
  getTicketByFolio, subirFirmaTicket,
  type TicketEmitible, type BodegaTicket,
} from '@/lib/services/bodega-tickets'
import { getSolicitudesBodega, atenderSolicitudBodega, type BodegaSolicitud } from '@/lib/services/bodega-solicitudes'
import { useMaterialesPendientesDespacho, useDespacharMaterialOT } from '@/hooks/use-ot-materiales'
import { cn } from '@/lib/utils'

type Tab = 'despachar' | 'solicitudes' | 'historial' | 'emitir'

// El QR del vale es un LINK: cualquier cámara de teléfono lo abre en esta
// página con el ticket cargado para despachar (MIG205).
function urlDespachoTicket(folio: string): string {
  return `${typeof window !== 'undefined' ? window.location.origin : ''}/dashboard/bodega/tickets?folio=${folio}`
}

/** Extrae el folio TKT-… de lo escaneado (texto plano, SICOM-… o URL). */
function extraerFolio(raw: string): string {
  const m = raw.toUpperCase().match(/TKT-\d{6}-\d{5}/)
  return m ? m[0] : raw.trim().toUpperCase().replace(/^SICOM-/, '')
}

function QrImg({ value, size = 180 }: { value: string; size?: number }) {
  const [url, setUrl] = useState('')
  useEffect(() => { QRCode.toDataURL(value, { width: size, margin: 1 }).then(setUrl).catch(() => {}) }, [value, size])
  // eslint-disable-next-line @next/next/no-img-element
  return url ? <img src={url} alt="QR" width={size} height={size} /> : <Spinner />
}

function estadoBadge(e: string) {
  switch (e) {
    case 'emitido':   return 'bg-blue-100 text-blue-800'
    case 'parcial':   return 'bg-amber-100 text-amber-800'
    case 'entregado': return 'bg-green-100 text-green-800'
    case 'anulado':   return 'bg-gray-200 text-gray-600'
    default:          return 'bg-gray-100 text-gray-700'
  }
}

// Bodega gestiona TODO el pedido del taller en esta única página: vales por
// despachar (con fotos), solicitudes de material y el historial.
export default function BodegaTicketsPage() {
  useRequireAuth()
  const [tab, setTab] = useState<Tab>('despachar')

  // Badges de las pestañas
  const { data: tickets } = useTickets()
  const nPorDespachar = (tickets ?? []).filter((t) => t.estado === 'emitido' || t.estado === 'parcial').length
  const { data: solsNc = [] } = useQuery({ queryKey: ['bodega-solicitudes', 'pendiente'], queryFn: () => getSolicitudesBodega('pendiente'), staleTime: 15_000 })
  const { data: pendientesOT = [] } = useMaterialesPendientesDespacho()
  const nSolicitudes = (solsNc as BodegaSolicitud[]).length + (pendientesOT as any[]).length

  // Llegada por QR (?folio=TKT-…) o link antiguo (?tab=solicitudes)
  useEffect(() => {
    const p = new URLSearchParams(window.location.search)
    if (p.get('folio')) setTab('despachar')
    else if (p.get('tab') === 'solicitudes') setTab('solicitudes')
  }, [])

  return (
    <div className="pb-16">
      <div className="mb-4 flex items-center gap-2">
        <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-orange-600 text-white">
          <Ticket className="h-5 w-5" />
        </div>
        <div>
          <h1 className="text-lg font-bold text-gray-900">Pedidos a bodega</h1>
          <p className="text-xs text-gray-500">Vales por despachar (con fotos), solicitudes de material e historial — todo en un solo lugar</p>
        </div>
      </div>

      <div className="mb-4 flex gap-1 rounded-xl bg-gray-100 p-1">
        {([
          ['despachar', 'Por despachar', Truck, nPorDespachar],
          ['solicitudes', 'Solicitudes', PackageSearch, nSolicitudes],
          ['historial', 'Historial', History, 0],
          ['emitir', 'Emitir', PenLine, 0],
        ] as const).map(([id, label, Icon, n]) => (
          <button key={id} onClick={() => setTab(id)}
                  className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg px-2 py-2 text-sm font-medium ${
                    tab === id ? 'bg-white text-orange-600 shadow-sm' : 'text-gray-500'}`}>
            <Icon className="h-4 w-4" /> <span className="truncate">{label}</span>
            {n > 0 && <span className="rounded-full bg-orange-600 px-1.5 py-0.5 text-[10px] font-bold text-white">{n}</span>}
          </button>
        ))}
      </div>

      {tab === 'despachar' && <DespacharTab />}
      {tab === 'solicitudes' && <SolicitudesTab />}
      {tab === 'historial' && <HistorialTab />}
      {tab === 'emitir' && <EmitirTab />}
    </div>
  )
}

// ── Emitir (jefe) ─────────────────────────────────────────────────────────────
function EmitirTab() {
  const toast = useToast()
  const { data: emitibles, isLoading } = useTicketsEmitibles()
  const crear = useCrearTicket()
  const [target, setTarget] = useState<TicketEmitible | null>(null)
  const [firma, setFirma] = useState<string>('')
  const [obs, setObs] = useState('')
  const [resultado, setResultado] = useState<{ folio: string; qr: string } | null>(null)

  async function emitir() {
    if (!target || !firma) return
    try {
      const firmaUrl = await subirFirmaTicket(firma, 'jefe')
      const r = await crear.mutateAsync({ otId: target.ot_id, firmaJefeUrl: firmaUrl, observacion: obs.trim() || null })
      setResultado({ folio: r.folio, qr: r.qr })
      setTarget(null); setFirma(''); setObs('')
    } catch (e) { toast.error((e as Error).message) }
  }

  return (
    <div className="space-y-2">
      {isLoading ? (
        <div className="flex justify-center py-8"><Spinner /></div>
      ) : (emitibles ?? []).length === 0 ? (
        <p className="py-8 text-center text-sm text-gray-400">No hay OTs con materiales de NC pendientes de ticket.</p>
      ) : (
        (emitibles ?? []).map((o) => (
          <Card key={o.ot_id}>
            <CardContent className="flex items-center gap-3 p-3">
              <div className="flex-1">
                <div className="font-mono text-xs font-bold">{o.ot_folio}</div>
                <div className="text-sm text-gray-800">{o.activo_codigo} {o.activo_patente && `· ${o.activo_patente}`}</div>
                <div className="text-xs text-gray-500">{o.activo_nombre} — {o.n_materiales} material(es)</div>
              </div>
              <Button variant="primary" onClick={() => { setTarget(o); setFirma(''); setObs('') }}>
                <Ticket className="h-4 w-4 mr-1" /> Emitir
              </Button>
            </CardContent>
          </Card>
        ))
      )}

      {/* Modal emitir */}
      {target && (
        <Modal open onClose={() => setTarget(null)} title={`Emitir ticket · ${target.ot_folio}`}>
          <div className="space-y-3">
            <div className="rounded-lg bg-gray-50 border p-2 text-sm">
              {target.activo_codigo} {target.activo_patente && `· ${target.activo_patente}`} — {target.n_materiales} material(es) de las NC
            </div>
            <div>
              <label className="text-xs font-medium">Observación (opcional)</label>
              <Input value={obs} onChange={(e) => setObs(e.target.value)} placeholder="opcional" />
            </div>
            <SignaturePad label="Firma del jefe de taller (obligatoria)" onCapture={setFirma} />
          </div>
          <ModalFooter>
            <Button variant="outline" onClick={() => setTarget(null)}>Cancelar</Button>
            <Button disabled={!firma || crear.isPending} onClick={emitir}>
              {crear.isPending ? <Spinner className="h-4 w-4 mr-1" /> : <PenLine className="h-4 w-4 mr-1" />}
              Emitir ticket
            </Button>
          </ModalFooter>
        </Modal>
      )}

      {/* Resultado con QR */}
      {resultado && (
        <Modal open onClose={() => setResultado(null)} title={`Ticket ${resultado.folio}`}>
          <div className="flex flex-col items-center gap-3 py-2 print-area">
            <div className="text-sm text-gray-600">
              Entrega este ticket al ejecutor. Cualquier teléfono que escanee el QR abre el
              despacho con el ticket cargado.
            </div>
            <QrImg value={urlDespachoTicket(resultado.folio)} />
            <div className="font-mono text-lg font-bold">{resultado.folio}</div>
          </div>
          <ModalFooter>
            <Button variant="outline" onClick={() => setResultado(null)}>Cerrar</Button>
            <Button onClick={() => window.print()}><Printer className="h-4 w-4 mr-1" /> Imprimir</Button>
          </ModalFooter>
        </Modal>
      )}
    </div>
  )
}

// ── Por despachar (bodeguero): lista de vales pendientes + despacho ───────────
function DespacharTab() {
  const toast = useToast()
  const [folio, setFolio] = useState('')
  const [scan, setScan] = useState(false)
  const [ticket, setTicket] = useState<BodegaTicket | null>(null)
  const [buscando, setBuscando] = useState(false)

  // Vales pendientes (emitido/parcial): el bodeguero los ve SIN escanear nada
  const { data: todos, isLoading: cargandoLista } = useTickets()
  const pendientes = useMemo(
    () => (todos ?? []).filter((t) => t.estado === 'emitido' || t.estado === 'parcial'),
    [todos])

  const { data: items } = useTicketItems(ticket?.id ?? null)
  const { data: bodegasAll } = useBodegasTaller()
  // Solo bodegas de la faena de la OT (o sin faena); la salida valida esto.
  const bodegas = useMemo(() => {
    const list = bodegasAll ?? []
    if (!ticket?.faena_id) return list
    const f = list.filter((b) => !b.faena_id || b.faena_id === ticket.faena_id)
    return f.length ? f : list
  }, [bodegasAll, ticket?.faena_id])
  const [bodegaId, setBodegaId] = useState('')
  const productoIds = useMemo(() => (items ?? []).map((i) => i.producto_id).filter(Boolean) as string[], [items])
  const { data: stock } = useStockProductos(bodegaId || null, productoIds)
  const entregar = useEntregarTicket()
  const [cant, setCant] = useState<Record<string, string>>({})
  const [firmaBod, setFirmaBod] = useState('')
  const [entregadoA, setEntregadoA] = useState('')
  const [resultado, setResultado] = useState<{ despacho: string | null; estado: string } | null>(null)

  useEffect(() => {
    if (bodegas.length && !bodegas.some((b) => b.id === bodegaId)) setBodegaId(bodegas[0].id)
  }, [bodegas, bodegaId])

  async function buscar(f: string) {
    const limpio = extraerFolio(f)
    if (!limpio) return
    setBuscando(true)
    try {
      const t = await getTicketByFolio(limpio)
      if (!t) { toast.error('Ticket no encontrado'); setTicket(null) }
      else { setTicket(t); setCant({}); setResultado(null) }
    } catch (e) { toast.error((e as Error).message) } finally { setBuscando(false) }
  }

  // Llegada por QR (?folio=…): cargar el ticket al tiro.
  useEffect(() => {
    const f = new URLSearchParams(window.location.search).get('folio')
    if (f) { setFolio(extraerFolio(f)); void buscar(f) }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const usable = ticket && ticket.estado !== 'entregado' && ticket.estado !== 'anulado'

  async function confirmar() {
    if (!ticket || !bodegaId) return
    // Validar contra pendiente y stock ANTES de mandar: el servidor rechaza
    // toda la entrega si un solo ítem no tiene stock (rebaja FIFO atómica).
    for (const i of items ?? []) {
      const c = Number(cant[i.id] || 0)
      if (c <= 0) continue
      const nombre = i.producto_nombre ?? i.descripcion ?? 'ítem'
      if (c > i.pendiente) {
        toast.error(`"${nombre}": ingresaste ${c} pero quedan ${i.pendiente} pendientes en el vale.`)
        return
      }
      const disp = i.producto_id && stock ? (stock[i.producto_id] ?? 0) : null
      if (disp != null && c > disp) {
        toast.error(disp === 0
          ? `"${nombre}" no tiene stock en esta bodega. Déjalo en 0: queda pendiente en el vale y se gestiona como compra/reposición.`
          : `"${nombre}": solo hay ${disp} en stock. Entrega ${disp} y el saldo queda pendiente en el vale.`)
        return
      }
    }
    const entregas = (items ?? [])
      .map((i) => ({ ticket_item_id: i.id, cantidad: Number(cant[i.id] || 0) }))
      .filter((e) => e.cantidad > 0)
    if (entregas.length === 0) { toast.error('Ingresa al menos una cantidad'); return }
    try {
      const firmaUrl = firmaBod ? await subirFirmaTicket(firmaBod, 'bodeguero') : null
      const r = await entregar.mutateAsync({
        ticketId: ticket.id, bodegaId, entregas, entregadoA: entregadoA.trim() || null, firmaBodegueroUrl: firmaUrl,
      })
      setResultado({ despacho: r.despacho_folio, estado: r.estado })
      const t = await getTicketByFolio(ticket.folio)  // refrescar estado
      setTicket(t)
      setCant({}); setFirmaBod('')
      toast.success(r.estado === 'entregado' ? 'Entrega total — ticket cerrado' : 'Entrega parcial registrada')
    } catch (e) { toast.error((e as Error).message) }
  }

  return (
    <div className="space-y-3">
      {/* Buscar / escanear (el QR del vale impreso también llega aquí) */}
      <div className="flex gap-2">
        <div className="flex-1">
          <Input value={folio} onChange={(e) => setFolio(e.target.value)} placeholder="Folio del ticket (TKT-…)"
                 onKeyDown={(e) => { if (e.key === 'Enter') buscar(folio) }} />
        </div>
        <Button variant="outline" onClick={() => buscar(folio)} disabled={buscando}>
          {buscando ? <Spinner className="h-4 w-4" /> : <Search className="h-4 w-4" />}
        </Button>
        <Button variant="outline" onClick={() => setScan(true)}><ScanLine className="h-4 w-4 mr-1" /> Escanear</Button>
      </div>

      {scan && (
        <div className="rounded-lg border p-2">
          <BarcodeScanner active={scan} onClose={() => setScan(false)}
                          onScan={(code) => { setScan(false); setFolio(extraerFolio(code)); buscar(code) }} />
          <Button variant="ghost" size="sm" className="mt-2" onClick={() => setScan(false)}><X className="h-4 w-4 mr-1" /> Cerrar cámara</Button>
        </div>
      )}

      {/* Lista de vales pendientes: tocar uno lo carga para despachar */}
      {!ticket && (
        cargandoLista ? (
          <div className="flex justify-center py-8"><Spinner /></div>
        ) : pendientes.length === 0 ? (
          <p className="py-8 text-center text-sm text-gray-400">No hay vales pendientes de despacho. 🎉</p>
        ) : (
          <div className="space-y-2">
            <p className="text-xs text-gray-500">{pendientes.length} vale{pendientes.length !== 1 ? 's' : ''} por despachar — toca uno para gestionarlo:</p>
            {pendientes.map((t) => (
              <button key={t.id} type="button" onClick={() => buscar(t.folio)}
                      className="w-full text-left">
                <Card className="border-orange-200 hover:bg-orange-50/50 transition-colors">
                  <CardContent className="flex items-center gap-3 p-3">
                    <div className="flex-1">
                      <div className="flex items-center gap-2">
                        <span className="font-mono text-xs font-bold">{t.folio}</span>
                        <span className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${estadoBadge(t.estado)}`}>{t.estado}</span>
                      </div>
                      <div className="text-sm font-semibold text-gray-800">{t.activo_patente ?? t.activo_codigo} <span className="font-normal text-gray-500">{t.activo_nombre}</span></div>
                      <div className="text-[11px] text-gray-500">
                        OT {t.ot_folio} · {t.n_items} ítem{t.n_items !== 1 ? 's' : ''} · emitió {t.emitido_por_nombre ?? '—'} · {new Date(t.created_at).toLocaleDateString('es-CL')}
                      </div>
                    </div>
                    <Truck className="h-5 w-5 text-orange-500 shrink-0" />
                  </CardContent>
                </Card>
              </button>
            ))}
          </div>
        )
      )}

      {ticket && (
        <>
          <Button variant="ghost" size="sm" onClick={() => { setTicket(null); setResultado(null); setFolio('') }}>
            <ChevronLeft className="h-4 w-4 mr-1" /> Volver a la lista
          </Button>
          <Card>
            <CardContent className="p-3 space-y-3">
              <div className="flex items-center gap-2">
                <span className="font-mono text-sm font-bold">{ticket.folio}</span>
                <span className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${estadoBadge(ticket.estado)}`}>{ticket.estado}</span>
                <button type="button" onClick={() => window.open(`/vale/${ticket.id}`, '_blank')}
                        title="Ver / imprimir el vale" className="text-gray-400 hover:text-gray-600">
                  <Printer className="h-4 w-4" />
                </button>
                <span className="ml-auto text-xs text-gray-500">{ticket.activo_codigo} {ticket.activo_patente && `· ${ticket.activo_patente}`}</span>
              </div>
              <div className="text-xs text-gray-500">OT {ticket.ot_folio} · emitió {ticket.emitido_por_nombre ?? '—'}</div>

              {!usable && (
                <div className="flex items-center gap-2 rounded-lg bg-amber-50 border border-amber-200 p-2 text-sm text-amber-800">
                  <AlertTriangle className="h-4 w-4" /> Este ticket ya está {ticket.estado} — no se puede usar.
                </div>
              )}

              {/* Bodega */}
              <div>
                <label className="text-xs font-medium">Bodega de despacho</label>
                <select value={bodegaId} onChange={(e) => setBodegaId(e.target.value)} disabled={!usable}
                        className="w-full border rounded px-2 py-1.5 text-sm">
                  {(bodegas ?? []).map((b) => <option key={b.id} value={b.id}>{b.nombre}</option>)}
                </select>
              </div>

              {/* Items (con las fotos del pedido — MIG212) */}
              <div className="space-y-2">
                {(items ?? []).map((i) => {
                  // null = sin producto en catálogo O stock aún cargando (no bloquear).
                  const disp = i.producto_id && stock ? (stock[i.producto_id] ?? 0) : null
                  const max = disp != null ? Math.min(i.pendiente, disp) : i.pendiente
                  return (
                    <div key={i.id} className="rounded-lg border p-2">
                      <div className="flex items-center gap-2">
                        <div className="flex-1">
                          <div className="text-sm font-medium">{i.producto_nombre ?? i.descripcion}</div>
                          <div className="text-[11px] text-gray-500">
                            Pide {i.cantidad_solicitada} · entregado {i.cantidad_entregada} · pendiente {i.pendiente}
                            {i.producto_id
                              ? <span className={disp === 0 ? 'font-semibold text-red-600' : undefined}> · stock {disp ?? '…'}</span>
                              : <span className="text-amber-600"> · sin producto en catálogo</span>}
                          </div>
                          {(i.solicitado_nombre || i.nc_descripcion) && (
                            <div className="text-[10px] text-gray-400">
                              {i.solicitado_nombre}{i.nc_descripcion ? ` · NC: ${i.nc_descripcion}` : ''}
                            </div>
                          )}
                        </div>
                        {usable && i.pendiente > 0 && i.producto_id && (
                          disp === 0 ? (
                            <span className="shrink-0 rounded-full bg-red-100 px-2 py-1 text-[10px] font-semibold text-red-700">
                              sin stock
                            </span>
                          ) : (
                            <div className="w-20">
                              <Input type="number" min="0" max={max} value={cant[i.id] ?? ''}
                                     onChange={(e) => setCant((p) => ({ ...p, [i.id]: e.target.value }))}
                                     placeholder="0" />
                            </div>
                          )
                        )}
                        {i.pendiente <= 0 && <CheckCircle2 className="h-4 w-4 text-green-600" />}
                      </div>
                      {(i.fotos?.length ?? 0) > 0 && (
                        <div className="mt-1.5 flex gap-1.5">
                          {(i.fotos ?? []).map((url, j) => (
                            <a key={j} href={url} target="_blank" rel="noreferrer">
                              {/* eslint-disable-next-line @next/next/no-img-element */}
                              <img src={url} alt="foto del pedido" className="h-14 w-14 rounded border object-cover hover:opacity-80" />
                            </a>
                          ))}
                        </div>
                      )}
                      {usable && i.producto_id && disp != null && Number(cant[i.id] || 0) > disp && (
                        <div className="mt-1 text-[11px] text-red-600">Supera el stock disponible ({disp}).</div>
                      )}
                    </div>
                  )
                })}
              </div>

              {usable && (items ?? []).some((i) => i.pendiente > 0 && i.producto_id && stock && (stock[i.producto_id] ?? 0) === 0) && (
                <p className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800">
                  Hay ítems <b>sin stock</b> en esta bodega: entrega el resto y el vale queda
                  <b> parcial</b> por el saldo. El material faltante se gestiona como
                  compra/reposición (pestaña Solicitudes) y se despacha con el mismo vale al llegar.
                </p>
              )}
              {usable && (
                <>
                  <div>
                    <label className="text-xs font-medium">Entregado a (nombre)</label>
                    <Input value={entregadoA} onChange={(e) => setEntregadoA(e.target.value)} placeholder="ej: Yusedl" />
                  </div>
                  <SignaturePad label="Firma del bodeguero (opcional)" onCapture={setFirmaBod} />
                  <Button variant="primary" className="w-full" disabled={entregar.isPending} onClick={confirmar}>
                    {entregar.isPending ? <Spinner className="h-4 w-4 mr-1" /> : <CheckCircle2 className="h-4 w-4 mr-1" />}
                    Confirmar entrega (rebaja FIFO)
                  </Button>
                </>
              )}
            </CardContent>
          </Card>
        </>
      )}

      {resultado && (
        <div className="rounded-lg bg-green-50 border border-green-200 p-3 text-sm text-green-800">
          {resultado.estado === 'entregado'
            ? '✓ Entrega TOTAL — ticket cerrado (no se puede reusar).'
            : '✓ Entrega PARCIAL registrada — el ticket sigue abierto por el saldo.'}
          {resultado.despacho && <div className="mt-1 font-mono text-xs">Despacho: {resultado.despacho}</div>}
        </div>
      )}
    </div>
  )
}

// ── Solicitudes (material que no está en bodega + materiales de OT) ──────────
function SolicitudesTab() {
  const { data: pendientesOT = [] } = useMaterialesPendientesDespacho()
  return (
    <div className="space-y-6">
      <SolicitudesNCSection />
      <MaterialesOTSection items={pendientesOT as any[]} />
    </div>
  )
}

function SolicitudesNCSection() {
  const qc = useQueryClient()
  const toast = useToast()
  const [filtro, setFiltro] = useState('pendiente')
  const { data: sols = [], isLoading } = useQuery({ queryKey: ['bodega-solicitudes', filtro], queryFn: () => getSolicitudesBodega(filtro || undefined), staleTime: 15_000 })
  const [busy, setBusy] = useState<string | null>(null)
  const FILTROS = [['pendiente', 'Pendientes'], ['atendida', 'Atendidas'], ['rechazada', 'Rechazadas'], ['', 'Todas']] as const

  const accion = async (s: BodegaSolicitud, estado: 'atendida' | 'rechazada') => {
    setBusy(s.id)
    try {
      await atenderSolicitudBodega({ id: s.id, estado })
      toast.success(estado === 'atendida' ? 'Solicitud atendida' : 'Solicitud rechazada')
      qc.invalidateQueries({ queryKey: ['bodega-solicitudes'] })
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error') } finally { setBusy(null) }
  }

  return (
    <div className="space-y-3">
      <div>
        <h2 className="text-sm font-bold text-gray-800 flex items-center gap-1.5"><PackageSearch className="h-4 w-4 text-indigo-600" /> Material que NO está en bodega</h2>
        <p className="text-xs text-muted-foreground">Solicitado desde las No Conformidades, con la foto y el equipo. Atender = ya se gestionó (compra/reposición).</p>
      </div>
      <div className="flex gap-2">
        {FILTROS.map(([k, l]) => (
          <button key={k} onClick={() => setFiltro(k)} className={cn('rounded-full border px-3 py-1 text-xs', filtro === k ? 'bg-indigo-600 text-white border-indigo-600' : 'hover:bg-muted')}>{l}</button>
        ))}
      </div>
      {isLoading && <div className="p-6"><Spinner className="h-5 w-5" /></div>}
      {!isLoading && sols.length === 0 && <Card><CardContent className="p-6 text-center text-sm text-muted-foreground">Sin solicitudes {filtro && `(${filtro})`}.</CardContent></Card>}
      <div className="grid gap-3 md:grid-cols-2">
        {sols.map((s) => (
          <Card key={s.id} className={cn(s.estado === 'pendiente' && 'border-amber-300')}>
            <CardContent className="p-3 flex gap-3">
              {s.foto_url ? (
                <a href={s.foto_url} target="_blank" rel="noreferrer" className="shrink-0">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={s.foto_url} alt="foto solicitud" className="h-20 w-20 rounded object-cover border" />
                </a>
              ) : (
                <div className="h-20 w-20 rounded border bg-muted flex items-center justify-center text-muted-foreground shrink-0"><ImageIcon className="h-6 w-6" /></div>
              )}
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="font-semibold">{s.descripcion}</span>
                  <span className="text-xs text-muted-foreground">x{s.cantidad}{s.unidad ? ` ${s.unidad}` : ''}</span>
                </div>
                <div className="text-xs text-muted-foreground mt-0.5">
                  {s.patente ?? s.activo_codigo ?? '—'} · {s.solicitado_por_nombre ?? '—'} · {new Date(s.created_at).toLocaleDateString('es-CL')}
                </div>
                {s.observacion && <p className="text-xs mt-1 text-gray-600 line-clamp-2">{s.observacion}</p>}
                <div className="mt-2 flex items-center gap-2">
                  <Badge variant={s.estado === 'pendiente' ? 'asignada' : s.estado === 'atendida' ? 'operativo' : 'default'} className="text-[10px]">{s.estado}</Badge>
                  {s.estado === 'pendiente' && (
                    <>
                      <Button size="sm" disabled={busy === s.id} onClick={() => accion(s, 'atendida')}>
                        {busy === s.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5 mr-1" />} Atender
                      </Button>
                      <Button size="sm" variant="outline" disabled={busy === s.id} onClick={() => accion(s, 'rechazada')}><X className="h-3.5 w-3.5 mr-1" /> Rechazar</Button>
                    </>
                  )}
                  {s.nota_bodega && <span className="text-[11px] text-muted-foreground">· {s.nota_bodega}</span>}
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  )
}

function MaterialesOTSection({ items }: { items: any[] }) {
  const toast = useToast()
  const despachar = useDespacharMaterialOT()
  const [busy, setBusy] = useState<string | null>(null)
  const [soloFalta, setSoloFalta] = useState(false)

  const lista = soloFalta ? items.filter((m) => m.estado === 'faltante') : items
  const faltan = items.filter((m) => m.estado === 'faltante').length

  const onDespachar = (m: any) => {
    setBusy(m.material_id)
    despachar.mutate({ materialId: m.material_id, otId: m.ot_id }, {
      onSuccess: () => toast.success('Material despachado'),
      onError: (e: any) => toast.error(e?.message ?? 'Error al despachar'),
      onSettled: () => setBusy(null),
    })
  }

  return (
    <div className="space-y-3">
      <div>
        <h2 className="text-sm font-bold text-gray-800 flex items-center gap-1.5"><Truck className="h-4 w-4 text-indigo-600" /> Materiales planificados en las OT</h2>
        <p className="text-xs text-muted-foreground">Lo pedido en las órdenes de trabajo, con o sin stock.</p>
      </div>
      {items.length === 0 ? (
        <Card><CardContent className="p-6 text-center text-sm text-muted-foreground">Sin materiales pedidos por OT pendientes.</CardContent></Card>
      ) : (
        <>
          <label className="flex items-center gap-2 text-xs text-muted-foreground">
            <input type="checkbox" checked={soloFalta} onChange={(e) => setSoloFalta(e.target.checked)} />
            Mostrar solo lo que <b className="text-red-600">falta</b> ({faltan})
          </label>
          <Card>
            <CardContent className="p-0 overflow-x-auto">
              <table className="w-full text-sm">
                <thead><tr className="text-xs text-muted-foreground border-b">
                  <th className="text-left p-2">Material</th><th className="text-left p-2">OT / Equipo</th>
                  <th className="p-2">Pide</th><th className="p-2">Stock</th><th className="p-2">Estado</th><th className="p-2"></th>
                </tr></thead>
                <tbody>
                  {lista.map((m) => {
                    const hay = m.estado === 'suficiente'
                    return (
                      <tr key={m.material_id} className={cn('border-b', !hay && 'bg-red-50/40')}>
                        <td className="p-2"><span className="font-mono text-xs text-muted-foreground">{m.producto_codigo}</span> {m.producto_nombre}</td>
                        <td className="p-2 text-xs">{m.ot_folio} · <b>{m.activo_patente ?? m.activo_codigo ?? '—'}</b></td>
                        <td className="p-2 text-center">{m.cantidad_plan}</td>
                        <td className="p-2 text-center text-xs">{m.stock_actual ?? 0}</td>
                        <td className="p-2 text-center">
                          <Badge variant={hay ? 'operativo' : 'critica'} className="text-[10px]">{hay ? 'Hay stock' : 'Falta'}</Badge>
                        </td>
                        <td className="p-2 text-right">
                          {hay ? (
                            <Button size="sm" disabled={busy === m.material_id} onClick={() => onDespachar(m)}>
                              {busy === m.material_id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Truck className="h-3.5 w-3.5 mr-1" />} Despachar
                            </Button>
                          ) : (
                            <span className="text-[11px] text-amber-600 flex items-center justify-end gap-1"><AlertTriangle className="h-3.5 w-3.5" /> comprar / reponer</span>
                          )}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </CardContent>
          </Card>
        </>
      )}
    </div>
  )
}

// ── Historial ─────────────────────────────────────────────────────────────────
function HistorialTab() {
  const { data: tickets, isLoading } = useTickets()
  const anular = useAnularTicket()
  return (
    <div className="space-y-2">
      {isLoading ? (
        <div className="flex justify-center py-8"><Spinner /></div>
      ) : (tickets ?? []).length === 0 ? (
        <p className="py-8 text-center text-sm text-gray-400">Sin tickets.</p>
      ) : (
        (tickets ?? []).map((t) => (
          <Card key={t.id}>
            <CardContent className="flex items-center gap-3 p-3">
              <div className="flex-1">
                <div className="flex items-center gap-2">
                  <span className="font-mono text-xs font-bold">{t.folio}</span>
                  <span className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${estadoBadge(t.estado)}`}>{t.estado}</span>
                </div>
                <div className="text-sm text-gray-800">{t.activo_codigo} {t.activo_patente && `· ${t.activo_patente}`}</div>
                <div className="text-[11px] text-gray-500">
                  OT {t.ot_folio} · {t.n_entregados}/{t.n_items} ítems · emitió {t.emitido_por_nombre ?? '—'}
                </div>
              </div>
              <Button variant="outline" size="sm" title="Vale imprimible para el retiro"
                      onClick={() => window.open(`/vale/${t.id}`, '_blank')}>
                Imprimir
              </Button>
              {(t.estado === 'emitido' || t.estado === 'parcial') && (
                <Button variant="ghost" size="sm"
                        onClick={() => { if (confirm(`¿Anular ticket ${t.folio}?`)) anular.mutate({ ticketId: t.id }) }}>
                  Anular
                </Button>
              )}
            </CardContent>
          </Card>
        ))
      )}
    </div>
  )
}
