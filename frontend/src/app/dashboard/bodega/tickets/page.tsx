'use client'

import { useEffect, useMemo, useState } from 'react'
import QRCode from 'qrcode'
import {
  Ticket, Truck, ScanLine, Printer, Search, CheckCircle2, AlertTriangle, PenLine, Loader2, History, X,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
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

type Tab = 'emitir' | 'despachar' | 'historial'

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

export default function BodegaTicketsPage() {
  useRequireAuth()
  const [tab, setTab] = useState<Tab>('emitir')

  // Llegada por QR (?folio=TKT-…): directo a Despachar con el ticket cargado.
  useEffect(() => {
    const f = new URLSearchParams(window.location.search).get('folio')
    if (f) setTab('despachar')
  }, [])

  return (
    <div className="pb-16">
      <div className="mb-4 flex items-center gap-2">
        <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-orange-600 text-white">
          <Ticket className="h-5 w-5" />
        </div>
        <div>
          <h1 className="text-lg font-bold text-gray-900">Tickets de bodega</h1>
          <p className="text-xs text-gray-500">Pedido firmado del jefe → entrega del bodeguero (rebaja FIFO)</p>
        </div>
      </div>

      <div className="mb-4 flex gap-1 rounded-xl bg-gray-100 p-1">
        {([['emitir', 'Emitir', Truck], ['despachar', 'Despachar', ScanLine], ['historial', 'Historial', History]] as const).map(([id, label, Icon]) => (
          <button key={id} onClick={() => setTab(id)}
                  className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg px-3 py-2 text-sm font-medium ${
                    tab === id ? 'bg-white text-orange-600 shadow-sm' : 'text-gray-500'}`}>
            <Icon className="h-4 w-4" /> {label}
          </button>
        ))}
      </div>

      {tab === 'emitir' && <EmitirTab />}
      {tab === 'despachar' && <DespacharTab />}
      {tab === 'historial' && <HistorialTab />}
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

// ── Despachar (bodeguero) ─────────────────────────────────────────────────────
function DespacharTab() {
  const toast = useToast()
  const [folio, setFolio] = useState('')
  const [scan, setScan] = useState(false)
  const [ticket, setTicket] = useState<BodegaTicket | null>(null)
  const [buscando, setBuscando] = useState(false)

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
      {/* Buscar / escanear */}
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

      {ticket && (
        <Card>
          <CardContent className="p-3 space-y-3">
            <div className="flex items-center gap-2">
              <span className="font-mono text-sm font-bold">{ticket.folio}</span>
              <span className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${estadoBadge(ticket.estado)}`}>{ticket.estado}</span>
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

            {/* Items */}
            <div className="space-y-2">
              {(items ?? []).map((i) => {
                const disp = i.producto_id ? (stock?.[i.producto_id] ?? 0) : null
                const max = disp != null ? Math.min(i.pendiente, disp) : i.pendiente
                return (
                  <div key={i.id} className="rounded-lg border p-2">
                    <div className="flex items-center gap-2">
                      <div className="flex-1">
                        <div className="text-sm font-medium">{i.producto_nombre ?? i.descripcion}</div>
                        <div className="text-[11px] text-gray-500">
                          Pide {i.cantidad_solicitada} · entregado {i.cantidad_entregada} · pendiente {i.pendiente}
                          {i.producto_id
                            ? <> · stock {disp ?? 0}</>
                            : <span className="text-amber-600"> · sin producto en catálogo</span>}
                        </div>
                      </div>
                      {usable && i.pendiente > 0 && i.producto_id && (
                        <div className="w-20">
                          <Input type="number" min="0" max={max} value={cant[i.id] ?? ''}
                                 onChange={(e) => setCant((p) => ({ ...p, [i.id]: e.target.value }))}
                                 placeholder="0" />
                        </div>
                      )}
                      {i.pendiente <= 0 && <CheckCircle2 className="h-4 w-4 text-green-600" />}
                    </div>
                    {usable && i.producto_id && disp != null && Number(cant[i.id] || 0) > disp && (
                      <div className="mt-1 text-[11px] text-red-600">Supera el stock disponible ({disp}).</div>
                    )}
                  </div>
                )
              })}
            </div>

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
