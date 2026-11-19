'use client'

// ============================================================================
// Panel Bodega Franke (MIG692)
// ----------------------------------------------------------------------------
// Lo que pidió Manuel en una sola pantalla: el stock de la bodega de faena
// (agua, repuestos, EPP) con su mínimo y su estado, las alertas abiertas, los
// movimientos hechos con el lector, y el combustible de la faena — stock por
// camión-estanque y los despachos. Desde acá se fijan los mínimos y se
// imprimen las etiquetas para el lector.
// El combustible solo se LEE: en faena el stock lo fija la varilla del cierre.
// ============================================================================

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, CheckCircle2, ClipboardCheck, Fuel, Package, Printer, RefreshCw, ScanBarcode, Search, Truck, XCircle } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { cn, errorMessage } from '@/lib/utils'
import { BODEGA_FRANKE, fijarMinimo, getBodegaPorCodigo, getPanelBodega, type EstadoStock, type FilaStock } from '@/lib/services/bodega-faena'
import { getEnvios, recalcularMinimos } from '@/lib/services/bodega-envios'

const fmt = (n: number | null | undefined, d = 2) => (n == null ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: d }))
const pesos = (n: number | null | undefined) => (n == null ? '—' : '$' + Math.round(Number(n)).toLocaleString('es-CL'))
const fechaHora = (s: string) => new Date(s).toLocaleString('es-CL', { dateStyle: 'short', timeStyle: 'short' })
const ESTADO: Record<EstadoStock, { txt: string; cls: string; icono: typeof CheckCircle2 }> = {
  agotado: { txt: 'Agotado', cls: 'bg-red-100 text-red-800', icono: XCircle },
  bajo: { txt: 'Bajo mínimo', cls: 'bg-amber-100 text-amber-800', icono: AlertTriangle },
  ok: { txt: 'OK', cls: 'bg-emerald-50 text-emerald-800', icono: CheckCircle2 },
  sin_minimo: { txt: 'Sin mínimo', cls: 'bg-gray-100 text-gray-600', icono: Package },
}
const ORDEN: EstadoStock[] = ['agotado', 'bajo', 'sin_minimo', 'ok']
type Pestana = 'stock' | 'movimientos' | 'combustible'

export default function PanelBodegaFrankePage() {
  const { loading } = useRequireAuth()
  const [pestana, setPestana] = useState<Pestana>('stock')
  const [filtro, setFiltro] = useState('')
  const { data: bodega } = useQuery({ queryKey: ['bodega', BODEGA_FRANKE], queryFn: () => getBodegaPorCodigo(BODEGA_FRANKE) })
  const { data: panel, isLoading, error } = useQuery({
    queryKey: ['bodega-panel', bodega?.id], queryFn: () => getPanelBodega(bodega!.id), enabled: !!bodega?.id,
  })

  const qc = useQueryClient()
  const toast = useToast()
  const [recalculando, setRecalculando] = useState(false)
  const { data: envios } = useQuery({
    queryKey: ['bodega-envios', bodega?.id, 'en-camino'], queryFn: () => getEnvios(bodega!.id, true), enabled: !!bodega?.id,
  })
  const enCamino = (envios ?? []).filter((e) => e.estado === 'en_camino' && e.destino.id === bodega?.id).length
  async function recalcular() {
    if (!bodega) return
    setRecalculando(true)
    try {
      const r = await recalcularMinimos(bodega.id)
      toast.success(`Mínimos = ${r.dias} días de consumo (${r.fuente === 'auto_sicom' ? 'salidas de esta bodega' : 'historial Softland de la faena'}, ${r.ventana_dias} días): ${r.productos_calculados} productos. Los fijados a mano no se tocan.`)
      qc.invalidateQueries({ queryKey: ['bodega-panel'] })
    } catch (e) { toast.error(errorMessage(e)) } finally { setRecalculando(false) }
  }

  const stock = useMemo(() => {
    const t = filtro.trim().toLowerCase()
    return (panel?.stock ?? [])
      .filter((s) => !t || s.nombre.toLowerCase().includes(t) || s.codigo.toLowerCase().includes(t))
      .sort((a, b) => ORDEN.indexOf(a.estado) - ORDEN.indexOf(b.estado) || a.nombre.localeCompare(b.nombre))
  }, [panel, filtro])

  if (loading) return null
  const s = panel?.stock ?? []
  const valor = s.reduce((a, x) => a + (x.valor ?? 0), 0)
  const comb = panel?.combustible

  return (
    <div className="mx-auto max-w-7xl space-y-5 p-4 md:p-6">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-emerald-800">Faena Franke · Taltal</p>
          <h1 className="text-2xl font-bold text-gray-900">Bodega de faena</h1>
          <p className="text-sm text-gray-500">Agua, repuestos y EPP con lector de códigos · combustible de los camiones-estanque</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link href="/m/franke/bodega" className="flex items-center gap-2 rounded-lg bg-gray-900 px-3 py-2 text-sm font-medium text-white hover:bg-gray-800">
            <ScanBarcode className="h-4 w-4" /> Usar el lector
          </Link>
          {bodega && (
            <Link href={`/dashboard/bodega/etiquetas?bodega=${bodega.id}`} className="flex items-center gap-2 rounded-lg border bg-white px-3 py-2 text-sm font-medium hover:bg-gray-50">
              <Printer className="h-4 w-4" /> Etiquetas
            </Link>
          )}
          <Link href="/dashboard/bodega/envios" className="flex items-center gap-2 rounded-lg border bg-white px-3 py-2 text-sm font-medium hover:bg-gray-50">
            <Truck className="h-4 w-4" /> Envíos desde Coquimbo{enCamino ? ` (${enCamino} en camino)` : ''}
          </Link>
        </div>
      </header>

      {error && <p className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">{errorMessage(error)}</p>}

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
        <Kpi titulo="Productos" valor={String(s.length)} sub={`${s.filter((x) => x.estado === 'sin_minimo').length} sin mínimo`} />
        <Kpi titulo="Bajo mínimo" valor={String(s.filter((x) => x.estado === 'bajo').length)} estado={s.some((x) => x.estado === 'bajo') ? 'alerta' : 'ok'} />
        <Kpi titulo="Agotados" valor={String(s.filter((x) => x.estado === 'agotado').length)} estado={s.some((x) => x.estado === 'agotado') ? 'critico' : 'ok'} />
        <Kpi titulo="Valor en bodega" valor={pesos(valor)} />
        <Kpi titulo="Combustible en camiones" valor={comb ? `${fmt(comb.estanques.reduce((a, e) => a + (e.stock ?? 0), 0), 0)} L` : '—'}
             sub={comb ? `${fmt(comb.litros_30d, 0)} L despachados en 30 días` : undefined} />
      </div>

      {(panel?.conteos_por_aprobar ?? 0) > 0 && (
        <Link href="/dashboard/inventario/conteo" className="flex items-center gap-2 rounded-xl border border-blue-200 bg-blue-50 p-3 text-sm text-blue-900 hover:bg-blue-100">
          <ClipboardCheck className="h-4 w-4" /> {panel!.conteos_por_aprobar} conteo{panel!.conteos_por_aprobar === 1 ? '' : 's'} de la faena por aprobar → Inventario · Conteo
        </Link>
      )}

      {(panel?.alertas.length ?? 0) > 0 && (
        <Card className="border-amber-200">
          <CardHeader className="pb-2"><CardTitle className="flex items-center gap-2 text-base"><AlertTriangle className="h-4 w-4 text-amber-600" /> Alertas abiertas de stock bajo</CardTitle></CardHeader>
          <CardContent className="space-y-1 text-sm">
            {panel!.alertas.map((a) => (
              <p key={a.codigo}><b>{a.producto}</b> <span className="text-gray-500">({a.codigo})</span>: quedan {fmt(a.stock)}, mínimo {fmt(a.minimo)} · desde {fechaHora(a.desde)}{a.notificada ? ' · avisado por correo' : ''}</p>
            ))}
          </CardContent>
        </Card>
      )}

      <div className="flex gap-1 border-b">
        {([['stock', 'Stock y mínimos'], ['movimientos', 'Movimientos'], ['combustible', 'Combustible']] as [Pestana, string][]).map(([id, t]) => (
          <button key={id} onClick={() => setPestana(id)}
                  className={cn('-mb-px border-b-2 px-4 py-2 text-sm font-medium', pestana === id ? 'border-emerald-700 text-emerald-800' : 'border-transparent text-gray-500 hover:text-gray-800')}>
            {t}
          </button>
        ))}
      </div>

      {isLoading && <p className="text-sm text-gray-500">Cargando…</p>}

      {pestana === 'stock' && panel && (
        <div className="space-y-2">
          <div className="flex flex-wrap items-center gap-3">
            <label className="flex max-w-sm flex-1 items-center gap-2 rounded-lg border bg-white px-3 py-2">
              <Search className="h-4 w-4 text-gray-400" />
              <input value={filtro} onChange={(e) => setFiltro(e.target.value)} placeholder="Buscar producto" className="w-full text-sm outline-none" />
            </label>
            {panel.puede_operar && (
              <button onClick={() => void recalcular()} disabled={recalculando}
                      className="flex items-center gap-2 rounded-lg border bg-white px-3 py-2 text-sm font-medium hover:bg-gray-50 disabled:opacity-50">
                <RefreshCw className={cn('h-4 w-4', recalculando && 'animate-spin')} /> Recalcular mínimos (15 días)
              </button>
            )}
          </div>
          <p className="text-xs text-gray-500">
            Mínimo = 15 días de consumo; máximo = 30 días (lo que pide reponer «Enviar a faena»). Se calcula solo cada semana: mientras la bodega tenga menos
            de 60 días de salidas propias se usa lo que Coquimbo despachó a los CECO de Franke en Softland (180 días). Si cambia un mínimo a mano, queda fijo;
            póngalo en 0 sin máximo para que vuelva a calcularse. Productos de uso esporádico (menos de media unidad en 15 días) quedan sin mínimo.
          </p>
          <div className="overflow-x-auto rounded-xl border bg-white">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-left text-xs uppercase tracking-wide text-gray-500">
                <tr><th className="px-3 py-2">Producto</th><th className="px-3 py-2">Estado</th><th className="px-3 py-2 text-right">Stock</th>
                  <th className="px-3 py-2 text-right">Mínimo</th><th className="px-3 py-2 text-right">Máximo</th><th className="px-3 py-2 text-right">Valor</th><th className="px-3 py-2" /></tr>
              </thead>
              <tbody className="divide-y">
                {stock.map((f) => <FilaProducto key={f.producto_id} f={f} bodegaId={panel.bodega.id} editable={panel.puede_operar} />)}
                {stock.length === 0 && (
                  <tr><td colSpan={7} className="px-3 py-8 text-center text-gray-500">
                    La bodega aún no tiene productos. Haga el primer inventario con el lector (modo «Contar» o «Recibir»).
                  </td></tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {pestana === 'movimientos' && panel && (
        <div className="overflow-x-auto rounded-xl border bg-white">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-left text-xs uppercase tracking-wide text-gray-500">
              <tr><th className="px-3 py-2">Fecha</th><th className="px-3 py-2">Tipo</th><th className="px-3 py-2">Producto</th><th className="px-3 py-2 text-right">Cantidad</th>
                <th className="px-3 py-2">Destino</th><th className="px-3 py-2">Motivo</th><th className="px-3 py-2">Quién</th></tr>
            </thead>
            <tbody className="divide-y">
              {panel.movimientos.map((m, i) => (
                <tr key={i}>
                  <td className="whitespace-nowrap px-3 py-2 text-gray-600">{fechaHora(m.fecha)}</td>
                  <td className="px-3 py-2"><span className={cn('rounded px-1.5 py-0.5 text-xs font-medium', m.tipo === 'salida' ? 'bg-red-50 text-red-800' : m.tipo === 'entrada' ? 'bg-emerald-50 text-emerald-800' : 'bg-blue-50 text-blue-800')}>{m.tipo.replace('_', ' ')}</span></td>
                  <td className="px-3 py-2">{m.producto}<span className="block text-xs text-gray-400">{m.codigo}</span></td>
                  <td className="px-3 py-2 text-right tabular-nums">{fmt(m.cantidad)} {m.unidad}</td>
                  <td className="px-3 py-2">{m.equipo ?? (m.tipo === 'salida' ? 'Operación Franke' : '—')}</td>
                  <td className="px-3 py-2 text-gray-600">{m.motivo}</td>
                  <td className="px-3 py-2 text-gray-600">{m.usuario}</td>
                </tr>
              ))}
              {panel.movimientos.length === 0 && <tr><td colSpan={7} className="px-3 py-8 text-center text-gray-500">Sin movimientos en los últimos 60 días.</td></tr>}
            </tbody>
          </table>
        </div>
      )}

      {pestana === 'combustible' && panel && (
        <div className="space-y-4">
          {!comb && <p className="text-sm text-gray-500">La bodega no está asociada a una faena con combustible.</p>}
          {comb && (
            <>
              <div className="grid gap-3 sm:grid-cols-3">
                {comb.estanques.map((e) => (
                  <div key={e.codigo} className="rounded-xl border bg-white p-4">
                    <p className="flex items-center gap-2 text-sm font-semibold text-gray-800"><Fuel className="h-4 w-4 text-gray-500" /> {e.patente ?? e.codigo}</p>
                    <p className="mt-1 text-2xl font-bold tabular-nums">{fmt(e.stock, 0)} L</p>
                    <div className="mt-2 h-2 overflow-hidden rounded-full bg-gray-100" role="img" aria-label={`Llenado ${fmt(e.llenado_pct, 0)} %`}>
                      <div className="h-full rounded-full bg-emerald-700" style={{ width: `${Math.min(100, Math.max(0, Number(e.llenado_pct ?? 0)))}%` }} />
                    </div>
                    <p className="mt-1 text-xs text-gray-500">{fmt(e.llenado_pct, 0)} % de {fmt(e.capacidad, 0)} L{e.estimable === false ? ' · sin medición de partida' : ''}</p>
                  </div>
                ))}
              </div>
              <p className="text-xs text-gray-500">Stock estimado desde la última medición (varilla del cierre) más cargas y menos despachos. En faena manda la varilla.</p>
              <div className="overflow-x-auto rounded-xl border bg-white">
                <table className="w-full text-sm">
                  <thead className="bg-gray-50 text-left text-xs uppercase tracking-wide text-gray-500">
                    <tr><th className="px-3 py-2">Fecha</th><th className="px-3 py-2">Turno</th><th className="px-3 py-2">Desde camión</th><th className="px-3 py-2">Equipo</th>
                      <th className="px-3 py-2 text-right">Litros</th><th className="px-3 py-2">Folio</th><th className="px-3 py-2">Operador</th></tr>
                  </thead>
                  <tbody className="divide-y">
                    {comb.despachos.map((d, i) => (
                      <tr key={i}>
                        <td className="whitespace-nowrap px-3 py-2 text-gray-600">{d.fecha.split('-').reverse().join('-')} {d.hora?.slice(0, 5) ?? ''}</td>
                        <td className="px-3 py-2">{d.turno ?? '—'}</td>
                        <td className="px-3 py-2">{d.camion ?? '—'}</td>
                        <td className="px-3 py-2">{d.equipo ?? '—'}{d.tipo && d.tipo !== 'despacho' ? <span className="ml-1 text-xs text-gray-400">({d.tipo})</span> : null}</td>
                        <td className="px-3 py-2 text-right tabular-nums">{fmt(d.litros, 1)}</td>
                        <td className="px-3 py-2">{d.folio ?? '—'}</td>
                        <td className="px-3 py-2 text-gray-600">{d.operador ?? '—'}</td>
                      </tr>
                    ))}
                    {comb.despachos.length === 0 && <tr><td colSpan={7} className="px-3 py-8 text-center text-gray-500">Sin despachos registrados en los últimos 30 días.</td></tr>}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </div>
      )}
    </div>
  )
}

function FilaProducto({ f, bodegaId, editable }: { f: FilaStock; bodegaId: string; editable: boolean }) {
  const qc = useQueryClient()
  const toast = useToast()
  const [min, setMin] = useState(f.minimo != null ? String(f.minimo) : '')
  const [max, setMax] = useState(f.maximo != null ? String(f.maximo) : '')
  const cambiado = min !== (f.minimo != null ? String(f.minimo) : '') || max !== (f.maximo != null ? String(f.maximo) : '')
  const E = ESTADO[f.estado]
  async function guardar() {
    try {
      await fijarMinimo(bodegaId, f.producto_id, Number(min || 0), max === '' ? null : Number(max))
      toast.success(`Mínimo de ${f.nombre} guardado.`)
      qc.invalidateQueries({ queryKey: ['bodega-panel'] })
    } catch (e) { toast.error(errorMessage(e)) }
  }
  return (
    <tr>
      <td className="px-3 py-2">{f.nombre}<span className="block text-xs text-gray-400">{f.codigo} · {f.categoria?.replaceAll('_', ' ')}</span></td>
      <td className="px-3 py-2"><span className={cn('inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-xs font-medium', E.cls)}><E.icono className="h-3 w-3" />{E.txt}</span></td>
      <td className="px-3 py-2 text-right font-semibold tabular-nums">{fmt(f.stock)} <span className="text-xs font-normal text-gray-500">{f.unidad}</span></td>
      <td className="px-3 py-2 text-right">
        {editable ? <input value={min} onChange={(e) => setMin(e.target.value)} inputMode="decimal" className="w-20 rounded border px-2 py-1 text-right" /> : fmt(f.minimo)}
      </td>
      <td className="px-3 py-2 text-right">
        {editable ? <input value={max} onChange={(e) => setMax(e.target.value)} inputMode="decimal" className="w-20 rounded border px-2 py-1 text-right" /> : fmt(f.maximo)}
      </td>
      <td className="px-3 py-2 text-right tabular-nums text-gray-600">{pesos(f.valor)}</td>
      <td className="px-3 py-2 text-right">
        {editable && cambiado && <button onClick={guardar} className="rounded bg-emerald-700 px-2 py-1 text-xs font-medium text-white hover:bg-emerald-800">Guardar</button>}
      </td>
    </tr>
  )
}

function Kpi({ titulo, valor, sub, estado }: { titulo: string; valor: string; sub?: string; estado?: 'ok' | 'alerta' | 'critico' }) {
  const I = estado === 'ok' ? CheckCircle2 : estado ? AlertTriangle : null
  return (
    <div className="rounded-xl border bg-white p-4">
      <p className="flex items-center justify-between text-xs font-medium uppercase tracking-wide text-gray-500">
        {titulo}{I && <I aria-label={estado} className={cn('h-4 w-4', estado === 'ok' ? 'text-emerald-600' : estado === 'alerta' ? 'text-amber-600' : 'text-red-600')} />}
      </p>
      <p className="mt-1 text-2xl font-bold tabular-nums text-gray-900">{valor}</p>
      {sub && <p className="mt-0.5 text-xs text-gray-500">{sub}</p>}
    </div>
  )
}
