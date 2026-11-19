'use client'

// ============================================================================
// Enviar a faena (MIG712) — la bodega central despacha y la faena confirma
// ----------------------------------------------------------------------------
// Gustavo arma el envío (a mano o con «Cargar lo que falta»: lo necesario para
// que la faena llegue a 30 días de consumo, contando lo que ya va en camino).
// Al enviar sale del stock de Coquimbo por FIFO y queda «en camino». El
// supervisor de la faena lo confirma desde el lector (Bodega → Recibir) y
// entra con el costo del envío. Un envío en camino se puede anular: vuelve a
// Coquimbo. Un solo registro, nada se cuenta dos veces.
// ============================================================================

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowRight, ChevronDown, ChevronUp, PackagePlus, Search, Send, Trash2, Truck, XCircle } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { cn, errorMessage } from '@/lib/utils'
import { BODEGA_FRANKE, buscarProducto, nuevoUuid, type ProductoLector } from '@/lib/services/bodega-faena'
import { BODEGA_COQUIMBO, ESTADO_ENVIO, anularEnvio, crearEnvio, getEnvios, getSugerido, type Envio } from '@/lib/services/bodega-envios'

const fmt = (n: number | null | undefined) => (n == null ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 2 }))
const pesos = (n: number | null | undefined) => (n == null ? '—' : '$' + Math.round(Number(n)).toLocaleString('es-CL'))
const fecha = (s: string | null) => (s ? new Date(s).toLocaleString('es-CL', { dateStyle: 'short', timeStyle: 'short' }) : '—')

type Bodega = { id: string; codigo: string; nombre: string }
type Linea = { producto_id: string; codigo: string; nombre: string; unidad: string | null; stock_origen: number; cantidad: number; nota?: string }

export default function EnviosFaenaPage() {
  const { loading } = useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()
  const { data: bodegas } = useQuery({
    queryKey: ['bodegas-lista'],
    queryFn: async () => {
      const { data, error } = await supabase.from('bodegas').select('id, codigo, nombre').order('codigo')
      if (error) throw error
      return data as Bodega[]
    },
  })
  const [origenCod, setOrigenCod] = useState(BODEGA_COQUIMBO)
  const [destinoCod, setDestinoCod] = useState(BODEGA_FRANKE)
  const origen = bodegas?.find((b) => b.codigo === origenCod)
  const destino = bodegas?.find((b) => b.codigo === destinoCod)
  const [lineas, setLineas] = useState<Linea[]>([])
  const [texto, setTexto] = useState('')
  const [opciones, setOpciones] = useState<ProductoLector[]>([])
  const [guia, setGuia] = useState('')
  const [obs, setObs] = useState('')
  const [uuid, setUuid] = useState(nuevoUuid)
  const [enviando, setEnviando] = useState(false)

  const { data: envios, isLoading } = useQuery({
    queryKey: ['bodega-envios', origen?.id], queryFn: () => getEnvios(origen!.id), enabled: !!origen?.id,
  })

  async function buscar(e: React.FormEvent) {
    e.preventDefault()
    if (!origen || texto.trim().length < 2) return
    try {
      const r = await buscarProducto(origen.id, texto.trim())
      const exacto = r.find((p) => p.exacto)
      if (exacto) { agregar(exacto); return }
      if (r.length === 0) toast.error(`No encuentro «${texto}».`)
      setOpciones(r)
    } catch (err) { toast.error(errorMessage(err)) }
  }
  function agregar(p: ProductoLector, cantidad = 1, nota?: string) {
    setLineas((ls) => ls.some((l) => l.producto_id === p.producto_id)
      ? ls.map((l) => (l.producto_id === p.producto_id ? { ...l, cantidad: l.cantidad + cantidad } : l))
      : [...ls, { producto_id: p.producto_id, codigo: p.codigo, nombre: p.nombre, unidad: p.unidad, stock_origen: Number(p.stock), cantidad, nota }])
    setOpciones([]); setTexto('')
  }

  async function cargarSugerido() {
    if (!origen || !destino) return
    try {
      const s = await getSugerido(origen.id, destino.id)
      const conStock = s.filter((x) => x.sugerido > 0)
      if (s.length === 0) { toast.success(`${destino.nombre} tiene todo sobre 30 días de consumo.`); return }
      setLineas((ls) => {
        const m = new Map(ls.map((l) => [l.producto_id, l]))
        for (const x of conStock) {
          m.set(x.producto_id, {
            producto_id: x.producto_id, codigo: x.codigo, nombre: x.nombre, unidad: x.unidad, stock_origen: x.stock_origen,
            cantidad: x.sugerido,
            nota: `faena tiene ${fmt(x.stock_destino)}${x.en_camino ? ` + ${fmt(x.en_camino)} en camino` : ''} · mín ${fmt(x.minimo)} / máx ${fmt(x.maximo)}${x.urgente ? ' · BAJO MÍNIMO' : ''}`,
          })
        }
        return Array.from(m.values())
      })
      const sinStock = s.filter((x) => x.sugerido <= 0)
      toast.success(`${conStock.length} producto(s) cargados para llegar a 30 días.${sinStock.length ? ` ${sinStock.length} faltan pero no hay en ${origen.nombre}: ${sinStock.slice(0, 3).map((x) => x.nombre).join(', ')}${sinStock.length > 3 ? '…' : ''}` : ''}`)
    } catch (err) { toast.error(errorMessage(err)) }
  }

  const sobre = lineas.filter((l) => l.cantidad > l.stock_origen)
  async function enviar() {
    if (!origen || !destino || lineas.length === 0) return
    if (origen.id === destino.id) { toast.error('Origen y destino son la misma bodega.'); return }
    if (lineas.some((l) => !(l.cantidad > 0))) { toast.error('Hay cantidades en 0: quítelas o corríjalas.'); return }
    if (sobre.length) { toast.error(`No alcanza el stock de ${sobre[0].nombre} en ${origen.nombre}.`); return }
    setEnviando(true)
    try {
      const r = await crearEnvio({ origenId: origen.id, destinoId: destino.id, items: lineas.map((l) => ({ producto_id: l.producto_id, cantidad: l.cantidad })), guia, observacion: obs, clientUuid: uuid })
      toast.success(`${r.folio} enviado (${r.items} productos, ${pesos(r.costo_total)}). Queda en camino hasta que la faena lo confirme.`)
      setLineas([]); setGuia(''); setObs(''); setUuid(nuevoUuid())
      qc.invalidateQueries({ queryKey: ['bodega-envios'] })
    } catch (err) { toast.error(errorMessage(err)) } finally { setEnviando(false) }
  }

  const enCamino = useMemo(() => (envios ?? []).filter((e) => e.estado === 'en_camino').length, [envios])
  if (loading) return null

  return (
    <div className="mx-auto max-w-6xl space-y-5 p-4 md:p-6">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-emerald-800">Bodega central</p>
          <h1 className="text-2xl font-bold text-gray-900">Enviar a faena</h1>
          <p className="text-sm text-gray-500">Sale de Coquimbo al enviar y entra a la faena cuando el supervisor confirma lo que llegó.</p>
        </div>
        <Link href="/dashboard/bodega/franke" className="rounded-lg border bg-white px-3 py-2 text-sm font-medium hover:bg-gray-50">Ver Bodega Franke</Link>
      </header>

      <Card>
        <CardHeader className="pb-2"><CardTitle className="flex items-center gap-2 text-base"><PackagePlus className="h-4 w-4" /> Nuevo envío</CardTitle></CardHeader>
        <CardContent className="space-y-3">
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <select value={origenCod} onChange={(e) => { setOrigenCod(e.target.value); setLineas([]) }} className="rounded-lg border px-3 py-2" aria-label="Bodega origen">
              {(bodegas ?? []).map((b) => <option key={b.id} value={b.codigo}>{b.nombre}</option>)}
            </select>
            <ArrowRight className="h-4 w-4 text-gray-400" />
            <select value={destinoCod} onChange={(e) => setDestinoCod(e.target.value)} className="rounded-lg border px-3 py-2" aria-label="Bodega destino">
              {(bodegas ?? []).filter((b) => b.codigo !== origenCod).map((b) => <option key={b.id} value={b.codigo}>{b.nombre}</option>)}
            </select>
            <button onClick={() => void cargarSugerido()} className="rounded-lg bg-emerald-700 px-3 py-2 font-medium text-white hover:bg-emerald-800">
              Cargar lo que falta (hasta 30 días)
            </button>
          </div>

          <form onSubmit={buscar} className="flex max-w-xl items-center gap-2 rounded-lg border bg-white px-3 py-2">
            <Search className="h-4 w-4 text-gray-400" />
            <input value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="Agregar producto: código (lector) o nombre + Enter" className="w-full text-sm outline-none" />
          </form>
          {opciones.length > 0 && (
            <ul className="max-w-xl divide-y overflow-hidden rounded-lg border bg-white">
              {opciones.map((p) => (
                <li key={p.producto_id}>
                  <button onClick={() => agregar(p)} className="flex w-full items-center justify-between gap-2 px-3 py-2 text-left text-sm hover:bg-gray-50">
                    <span>{p.nombre}<span className="block text-xs text-gray-400">{p.codigo}</span></span>
                    <span className="text-xs text-gray-500">hay {fmt(p.stock)}</span>
                  </button>
                </li>
              ))}
            </ul>
          )}

          {lineas.length > 0 && (
            <div className="overflow-x-auto rounded-xl border">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 text-left text-xs uppercase tracking-wide text-gray-500">
                  <tr><th className="px-3 py-2">Producto</th><th className="px-3 py-2 text-right">Stock {origen?.codigo}</th><th className="px-3 py-2 text-right">Enviar</th><th className="px-3 py-2" /></tr>
                </thead>
                <tbody className="divide-y">
                  {lineas.map((l) => (
                    <tr key={l.producto_id} className={cn(l.cantidad > l.stock_origen && 'bg-red-50')}>
                      <td className="px-3 py-2">{l.nombre}<span className="block text-xs text-gray-400">{l.codigo}{l.nota ? ` · ${l.nota}` : ''}</span></td>
                      <td className="px-3 py-2 text-right tabular-nums">{fmt(l.stock_origen)} {l.unidad}</td>
                      <td className="px-3 py-2 text-right">
                        <input type="number" min={0} step="any" value={l.cantidad} aria-label={`Cantidad de ${l.nombre}`}
                               onChange={(e) => setLineas((ls) => ls.map((x) => (x.producto_id === l.producto_id ? { ...x, cantidad: Number(e.target.value) } : x)))}
                               className="w-24 rounded border px-2 py-1 text-right" />
                      </td>
                      <td className="px-3 py-2 text-right">
                        <button onClick={() => setLineas((ls) => ls.filter((x) => x.producto_id !== l.producto_id))} className="text-gray-400 hover:text-red-600" aria-label="Quitar"><Trash2 className="h-4 w-4" /></button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          <div className="flex flex-wrap gap-2">
            <input value={guia} onChange={(e) => setGuia(e.target.value)} placeholder="N° guía de despacho (opcional)" className="w-56 rounded-lg border px-3 py-2 text-sm" />
            <input value={obs} onChange={(e) => setObs(e.target.value)} placeholder="Observación (camión, quién lo lleva…)" className="min-w-[240px] flex-1 rounded-lg border px-3 py-2 text-sm" />
            <button onClick={() => void enviar()} disabled={enviando || lineas.length === 0}
                    className="flex items-center gap-2 rounded-lg bg-gray-900 px-4 py-2 text-sm font-semibold text-white disabled:opacity-40">
              <Send className="h-4 w-4" /> {enviando ? 'Enviando…' : `Enviar ${lineas.length || ''} producto${lineas.length === 1 ? '' : 's'}`}
            </button>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base"><Truck className="h-4 w-4" /> Envíos desde {origen?.nombre ?? '…'} <span className="text-sm font-normal text-gray-500">· {enCamino} en camino · últimos 90 días</span></CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {isLoading && <p className="text-sm text-gray-500">Cargando…</p>}
          {(envios ?? []).filter((e) => e.origen.id === origen?.id).map((e) => <FilaEnvio key={e.id} e={e} />)}
          {!isLoading && (envios ?? []).filter((e) => e.origen.id === origen?.id).length === 0 && <p className="text-sm text-gray-500">Sin envíos todavía.</p>}
        </CardContent>
      </Card>
    </div>
  )
}

function FilaEnvio({ e }: { e: Envio }) {
  const qc = useQueryClient()
  const toast = useToast()
  const [abierto, setAbierto] = useState(false)
  const [motivo, setMotivo] = useState('')
  const [anulando, setAnulando] = useState(false)
  const E = ESTADO_ENVIO[e.estado]
  const difs = e.items.filter((i) => i.recibida != null && i.recibida < i.enviada)
  async function anular() {
    if (motivo.trim().length < 5) { toast.error('Indique por qué se anula.'); return }
    setAnulando(true)
    try {
      await anularEnvio(e.id, motivo)
      toast.success(`${e.folio} anulado: volvió a ${e.origen.nombre}.`)
      qc.invalidateQueries({ queryKey: ['bodega-envios'] })
    } catch (err) { toast.error(errorMessage(err)) } finally { setAnulando(false) }
  }
  return (
    <div className="rounded-xl border bg-white">
      <button onClick={() => setAbierto(!abierto)} className="flex w-full flex-wrap items-center justify-between gap-2 px-3 py-2.5 text-left text-sm">
        <span className="flex flex-wrap items-center gap-2">
          <b>{e.folio}</b>
          <span className={cn('rounded px-1.5 py-0.5 text-xs font-medium', E.cls)}>{E.txt}</span>
          <span className="text-gray-600">→ {e.destino.nombre}</span>
          <span className="text-xs text-gray-500">{fecha(e.created_at)} · {e.items.length} productos · {pesos(e.valor)}{e.guia ? ` · guía ${e.guia}` : ''}</span>
        </span>
        {abierto ? <ChevronUp className="h-4 w-4 text-gray-400" /> : <ChevronDown className="h-4 w-4 text-gray-400" />}
      </button>
      {abierto && (
        <div className="space-y-2 border-t px-3 py-2 text-sm">
          <p className="text-xs text-gray-500">Envió {e.creado_por ?? '—'}{e.recibido_at ? ` · recibió ${e.recibido_por ?? '—'} el ${fecha(e.recibido_at)}` : ''}{e.observacion ? ` · ${e.observacion}` : ''}{e.observacion_recepcion ? ` · recepción: «${e.observacion_recepcion}»` : ''}</p>
          <table className="w-full text-sm">
            <thead className="text-left text-xs text-gray-500"><tr><th className="py-1">Producto</th><th className="py-1 text-right">Enviado</th><th className="py-1 text-right">Recibido</th><th className="py-1 text-right">Costo un.</th></tr></thead>
            <tbody className="divide-y">
              {e.items.map((i) => (
                <tr key={i.producto_id} className={cn(i.recibida != null && i.recibida < i.enviada && 'bg-amber-50')}>
                  <td className="py-1">{i.nombre} <span className="text-xs text-gray-400">{i.codigo}</span></td>
                  <td className="py-1 text-right tabular-nums">{fmt(i.enviada)}</td>
                  <td className="py-1 text-right tabular-nums">{i.recibida == null ? '—' : fmt(i.recibida)}</td>
                  <td className="py-1 text-right tabular-nums">{pesos(i.costo_unitario)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {difs.length > 0 && <p className="text-xs text-amber-900">Faltaron {difs.length} producto(s): revisar con quien llevó el envío. Lo faltante ya salió de {e.origen.nombre}.</p>}
          {e.estado === 'en_camino' && (
            <div className="flex flex-wrap items-center gap-2 pt-1">
              <input value={motivo} onChange={(ev) => setMotivo(ev.target.value)} placeholder="Motivo para anular (ej. no salió el camión)" className="min-w-[260px] flex-1 rounded-lg border px-3 py-1.5 text-sm" />
              <button onClick={() => void anular()} disabled={anulando} className="flex items-center gap-1 rounded-lg border border-red-300 px-3 py-1.5 text-sm font-medium text-red-700 hover:bg-red-50 disabled:opacity-50">
                <XCircle className="h-4 w-4" /> Anular y devolver a {e.origen.codigo}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
