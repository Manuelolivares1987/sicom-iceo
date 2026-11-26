'use client'

// ============================================================================
// Cobranza (MIG730-731) — fase 1 del módulo de finanzas
// ----------------------------------------------------------------------------
// La cartera de clientes sale de Softland (solo lectura, una vez al día).
// Cartera cobrable = facturas emitidas desde el 01-01-2026; lo anterior es
// historia. Se lee de arriba hacia abajo:
//   1. ¿Cuánto me deben y cuánto está vencido?   → tarjetas
//   2. ¿Qué tan atrasado?                         → antigüedad de lo vencido
//   3. ¿Cobro lo que facturo?                     → facturado vs cobrado por mes
//   4. ¿A quién llamo hoy?                        → clientes / facturas abiertas
// La ficha del cliente liga cada factura a las patentes que factura.
// ============================================================================

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import {
  AlertTriangle, CheckCircle2, Clock, Database, Search, ShieldAlert, Truck, X,
} from 'lucide-react'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { Modal } from '@/components/ui/modal'
import { fmtClp, fmtMM } from '@/lib/costos-operacion'
import {
  getCarteraCxc, getFichaCliente, clasificarPagador, SinPermisoFinanzas,
  type ClienteCxc, type DocumentoCxc, type EstadoDoc, type Pagador,
} from '@/lib/services/cxc'

// Paleta validada (skill dataviz: slots 1 y 2, claro y oscuro, CVD ΔE ≥ 26).
const AZUL = '#257de0'
const NARANJO = '#f47230'
// Antigüedad: una sola tonalidad, de claro a oscuro (rampa secuencial azul).
const RAMPA = ['#84b9f3', '#338ced', '#1b64be', '#0e3d7e']

const fecha = (s: string | null | undefined) =>
  s ? new Date(`${s.slice(0, 10)}T12:00:00`).toLocaleDateString('es-CL', { day: '2-digit', month: 'short', year: '2-digit' }) : '—'
const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic']
const mesCorto = (m: string) => `${MESES[Number(m.slice(5, 7)) - 1]}-${m.slice(2, 4)}`

const TONO_PAGADOR: Record<Pagador['tono'], string> = {
  bueno: 'bg-green-50 text-green-800 ring-green-600/30',
  atento: 'bg-amber-50 text-amber-800 ring-amber-600/30',
  serio: 'bg-orange-50 text-orange-800 ring-orange-600/30',
  critico: 'bg-red-50 text-red-800 ring-red-600/30',
  sin: 'bg-gray-50 text-gray-600 ring-gray-400/30',
}
const ICONO_PAGADOR: Record<Pagador['tono'], typeof CheckCircle2> = {
  bueno: CheckCircle2, atento: Clock, serio: AlertTriangle, critico: ShieldAlert, sin: Clock,
}

function BadgePagador({ p }: { p: Pagador }) {
  const Icono = ICONO_PAGADOR[p.tono]
  return (
    <span title={p.detalle} className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset ${TONO_PAGADOR[p.tono]}`}>
      <Icono className="h-3.5 w-3.5" aria-hidden="true" /> {p.etiqueta}
    </span>
  )
}

const ESTADO: Record<EstadoDoc, { etiqueta: string; clase: string; Icono: typeof CheckCircle2 }> = {
  pagada: { etiqueta: 'Pagada', clase: 'text-green-700', Icono: CheckCircle2 },
  por_vencer: { etiqueta: 'Por vencer', clase: 'text-amber-700', Icono: Clock },
  vencida: { etiqueta: 'Vencida', clase: 'text-red-700', Icono: AlertTriangle },
}
function EstadoTexto({ d }: { d: Pick<DocumentoCxc, 'estado' | 'dias_vencida'> }) {
  const e = ESTADO[d.estado]
  return (
    <span className={`inline-flex items-center gap-1 text-xs font-medium ${e.clase}`}>
      <e.Icono className="h-3.5 w-3.5" aria-hidden="true" />
      {e.etiqueta}{d.estado === 'vencida' ? ` · ${d.dias_vencida} d` : ''}
    </span>
  )
}

function Patentes({ lista }: { lista?: string[] }) {
  if (!lista?.length) return <span className="text-xs text-gray-400">—</span>
  return (
    <span className="flex flex-wrap gap-1">
      {lista.map((p) => (
        <span key={p} className="inline-flex items-center gap-0.5 rounded bg-gray-100 px-1.5 py-0.5 font-mono text-[11px] text-gray-700">
          <Truck className="h-3 w-3" aria-hidden="true" />{p}
        </span>
      ))}
    </span>
  )
}

export default function CobranzaPage() {
  useRequireAuth()
  const { data, isLoading, error } = useQuery({ queryKey: ['cxc-cartera'], queryFn: getCarteraCxc })
  const [vista, setVista] = useState<'clientes' | 'facturas'>('clientes')
  const [buscar, setBuscar] = useState('')
  const [verTabla, setVerTabla] = useState(false)
  const [ficha, setFicha] = useState<ClienteCxc | null>(null)

  const clientes = useMemo(() => {
    const q = buscar.trim().toLowerCase()
    return (data?.clientes ?? []).filter((c) => (c.deuda ?? 0) !== 0 || q)
      .filter((c) => !q || c.cliente.toLowerCase().includes(q) || (c.rut ?? '').includes(q))
  }, [data, buscar])
  const documentos = useMemo(() => {
    const q = buscar.trim().toLowerCase()
    return (data?.documentos ?? []).filter((d) => d.saldo > 0)
      .filter((d) => !q || d.cliente.toLowerCase().includes(q) || String(d.folio).includes(q)
        || (d.patentes ?? []).some((p) => p.toLowerCase().includes(q)))
  }, [data, buscar])

  if (isLoading) return <div className="flex justify-center py-16"><Spinner /></div>
  if (error instanceof SinPermisoFinanzas) {
    return <Card><CardContent className="py-10 text-center text-sm text-gray-600">No tiene permiso para ver la cobranza. Pídalo a administración.</CardContent></Card>
  }
  if (error || !data) {
    return <Card><CardContent className="py-10 text-center text-sm text-red-700">No se pudo cargar la cartera: {(error as Error)?.message}</CardContent></Card>
  }

  const r = data.resumen
  const deudaTotal = r.por_vencer + r.vencido
  const tramos = [
    { id: '1_30', etiqueta: '1 a 30 días', v: r.tramos['1_30'] },
    { id: '31_60', etiqueta: '31 a 60 días', v: r.tramos['31_60'] },
    { id: '61_90', etiqueta: '61 a 90 días', v: r.tramos['61_90'] },
    { id: 'mas_90', etiqueta: 'Más de 90 días', v: r.tramos.mas_90 },
  ]
  const maxTramo = Math.max(1, ...tramos.map((t) => t.v))

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-2">
        <div>
          <h1 className="text-xl font-bold text-gray-900">Cobranza</h1>
          <p className="text-sm text-gray-500">Facturas emitidas desde el 01-01-2026, leídas de Softland.</p>
        </div>
        <p className="inline-flex items-center gap-1 text-xs text-gray-500">
          <Database className="h-3.5 w-3.5" aria-hidden="true" />
          Softland al {data.sincronizado_at ? new Date(data.sincronizado_at).toLocaleString('es-CL', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—'}
        </p>
      </div>

      {/* 1. Tarjetas */}
      <div className="grid gap-3 sm:grid-cols-3">
        <Tarjeta titulo="Cobrado en 2026" valor={r.pagado} detalle={`${r.n_pagada} facturas pagadas de ${fmtMM(r.facturado)} facturado`}
                 Icono={CheckCircle2} clase="border-green-200 bg-green-50 text-green-900" />
        <Tarjeta titulo="Por vencer" valor={r.por_vencer} detalle={`${r.n_por_vencer} facturas`}
                 Icono={Clock} clase="border-amber-200 bg-amber-50 text-amber-900" />
        <Tarjeta titulo="Vencido" valor={r.vencido} detalle={`${r.n_vencido} facturas · ${deudaTotal ? Math.round((r.vencido / deudaTotal) * 100) : 0} % de lo que se debe`}
                 Icono={AlertTriangle} clase="border-red-200 bg-red-50 text-red-900" />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        {/* 2. Antigüedad */}
        <Card>
          <CardHeader><CardTitle className="text-base">Antigüedad de lo vencido</CardTitle></CardHeader>
          <CardContent>
            <ul className="space-y-3">
              {tramos.map((t, i) => (
                <li key={t.id} className="grid grid-cols-[7.5rem_1fr_auto] items-center gap-3 text-sm">
                  <span className="text-gray-600">{t.etiqueta}</span>
                  <span className="h-3 rounded-r bg-gray-100" aria-hidden="true">
                    <span className="block h-3 rounded-r" style={{ width: `${(t.v / maxTramo) * 100}%`, background: RAMPA[i] }} />
                  </span>
                  <span className="tabular-nums text-gray-900">{fmtMM(t.v)}</span>
                </li>
              ))}
            </ul>
            {r.credito_a_favor < 0 && (
              <p className="mt-4 text-xs text-gray-500">
                Además hay {fmtClp(-r.credito_a_favor)} pagados de más o sin factura (saldo a favor de clientes).
              </p>
            )}
          </CardContent>
        </Card>

        {/* 3. Facturado vs cobrado */}
        <Card>
          <CardHeader className="flex flex-row items-center justify-between">
            <CardTitle className="text-base">Facturado por mes: cobrado y pendiente</CardTitle>
            <button type="button" onClick={() => setVerTabla((v) => !v)} className="text-xs font-medium text-blue-700 hover:underline">
              {verTabla ? 'Ver gráfico' : 'Ver tabla'}
            </button>
          </CardHeader>
          <CardContent>
            {verTabla ? (
              <table className="w-full text-sm">
                <thead><tr className="text-left text-xs text-gray-500"><th className="py-1">Mes</th><th className="text-right">Facturado</th><th className="text-right">Cobrado</th><th className="text-right">Pendiente</th></tr></thead>
                <tbody>
                  {data.mensual.map((m) => (
                    <tr key={m.mes} className="border-t border-gray-100">
                      <td className="py-1">{mesCorto(m.mes)}</td>
                      <td className="text-right tabular-nums">{fmtMM(m.facturado)}</td>
                      <td className="text-right tabular-nums">{fmtMM(m.cobrado)}</td>
                      <td className="text-right tabular-nums">{fmtMM(m.pendiente)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            ) : (
              <div className="h-60" role="img" aria-label="Facturado por mes separado en cobrado y pendiente. Use «Ver tabla» para los valores.">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={data.mensual.map((m) => ({ ...m, mes: mesCorto(m.mes) }))} barCategoryGap="25%">
                    <CartesianGrid vertical={false} stroke="#eeeeee" />
                    <XAxis dataKey="mes" tick={{ fontSize: 11, fill: '#666666' }} axisLine={false} tickLine={false} />
                    <YAxis tickFormatter={(v: number) => `${Math.round(v / 1e6)}`} tick={{ fontSize: 11, fill: '#666666' }} axisLine={false} tickLine={false} width={36}
                           label={{ value: 'MM$', angle: -90, position: 'insideLeft', fontSize: 11, fill: '#666666' }} />
                    <Tooltip cursor={{ fill: 'rgba(0,0,0,0.04)' }} formatter={(v: number, n: string) => [fmtClp(v), n]} />
                    <Legend wrapperStyle={{ fontSize: 12 }} />
                    <Bar dataKey="cobrado" name="Cobrado" stackId="a" fill={AZUL} stroke="#ffffff" strokeWidth={2} />
                    <Bar dataKey="pendiente" name="Pendiente" stackId="a" fill={NARANJO} stroke="#ffffff" strokeWidth={2} radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* 4. Clientes / facturas abiertas */}
      <Card>
        <CardHeader className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex gap-1 rounded-lg bg-gray-100 p-1">
            {(['clientes', 'facturas'] as const).map((v) => (
              <button key={v} type="button" onClick={() => setVista(v)} aria-pressed={vista === v}
                      className={`rounded-md px-3 py-1.5 text-sm font-medium ${vista === v ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-600'}`}>
                {v === 'clientes' ? `Clientes con deuda (${(data.clientes ?? []).filter((c) => (c.deuda ?? 0) > 0).length})` : `Facturas abiertas (${data.documentos.filter((d) => d.saldo > 0).length})`}
              </button>
            ))}
          </div>
          <label className="relative block sm:w-72">
            <span className="sr-only">Buscar</span>
            <Search className="pointer-events-none absolute left-2.5 top-2.5 h-4 w-4 text-gray-400" aria-hidden="true" />
            <input value={buscar} onChange={(e) => setBuscar(e.target.value)} placeholder="Cliente, RUT, folio o patente"
                   className="w-full rounded-lg border border-gray-300 py-2 pl-8 pr-3 text-sm" />
          </label>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          {vista === 'clientes' ? (
            <table className="w-full min-w-[720px] text-sm">
              <thead>
                <tr className="text-left text-xs text-gray-500">
                  <th className="py-2">Cliente</th><th className="text-right">Debe</th><th className="text-right">Vencido</th>
                  <th className="text-right">Abiertas</th><th className="text-right">Paga en</th><th className="pl-4">Pagador</th>
                </tr>
              </thead>
              <tbody>
                {clientes.map((c) => (
                  <tr key={c.cod_aux} className="cursor-pointer border-t border-gray-100 hover:bg-gray-50" onClick={() => setFicha(c)}>
                    <td className="py-2">
                      <button type="button" className="text-left font-medium text-gray-900 hover:underline" onClick={(e) => { e.stopPropagation(); setFicha(c) }}>{c.cliente}</button>
                      <span className="block text-xs text-gray-500">{c.rut ?? c.cod_aux}</span>
                    </td>
                    <td className="text-right tabular-nums">{fmtClp(c.deuda)}</td>
                    <td className={`text-right tabular-nums ${(c.vencido ?? 0) > 0 ? 'font-semibold text-red-700' : 'text-gray-400'}`}>{(c.vencido ?? 0) > 0 ? fmtClp(c.vencido) : '—'}</td>
                    <td className="text-right tabular-nums">{c.abiertas}</td>
                    <td className="text-right tabular-nums">{c.dias_pago_prom != null ? `${Math.round(c.dias_pago_prom)} d` : '—'}</td>
                    <td className="pl-4"><BadgePagador p={clasificarPagador(c)} /></td>
                  </tr>
                ))}
                {!clientes.length && <tr><td colSpan={6} className="py-6 text-center text-gray-500">Sin resultados.</td></tr>}
              </tbody>
            </table>
          ) : (
            <TablaFacturas docs={documentos} onCliente={(cod) => setFicha(data.clientes.find((c) => c.cod_aux === cod) ?? null)} />
          )}
        </CardContent>
      </Card>

      <p className="text-xs text-gray-500">
        «Paga en» = días promedio entre la emisión y el último pago de sus facturas 2026 ya pagadas. Pagador según su atraso
        promedio contra el vencimiento: Puntual ≤ 5 días · Normal ≤ 15 · Lento ≤ 30 · Moroso más de 30.
      </p>

      {ficha && <FichaClienteModal cliente={ficha} onClose={() => setFicha(null)} />}
    </div>
  )
}

function Tarjeta({ titulo, valor, detalle, Icono, clase }: { titulo: string; valor: number; detalle: string; Icono: typeof CheckCircle2; clase: string }) {
  return (
    <div className={`rounded-xl border p-4 ${clase}`}>
      <p className="flex items-center gap-1.5 text-sm font-medium"><Icono className="h-4 w-4" aria-hidden="true" />{titulo}</p>
      <p className="mt-1 text-2xl font-bold tabular-nums">{fmtClp(valor)}</p>
      <p className="mt-0.5 text-xs opacity-80">{detalle}</p>
    </div>
  )
}

function TablaFacturas({ docs, onCliente }: { docs: DocumentoCxc[]; onCliente: (cod: string) => void }) {
  return (
    <table className="w-full min-w-[820px] text-sm">
      <thead>
        <tr className="text-left text-xs text-gray-500">
          <th className="py-2">Folio</th><th>Cliente</th><th>Emisión</th><th>Vence</th>
          <th className="text-right">Saldo</th><th className="pl-4">Estado</th><th>Equipos facturados</th>
        </tr>
      </thead>
      <tbody>
        {docs.map((d) => (
          <tr key={`${d.cod_aux}-${d.folio}`} className="border-t border-gray-100">
            <td className="py-2 font-mono text-xs">{d.folio}</td>
            <td><button type="button" className="text-left hover:underline" onClick={() => onCliente(d.cod_aux)}>{d.cliente}</button></td>
            <td className="whitespace-nowrap">{fecha(d.emision)}</td>
            <td className="whitespace-nowrap">{fecha(d.vence)}</td>
            <td className="text-right tabular-nums">{fmtClp(d.saldo)}</td>
            <td className="pl-4 whitespace-nowrap"><EstadoTexto d={d} /></td>
            <td className="max-w-[16rem]"><Patentes lista={d.patentes} /></td>
          </tr>
        ))}
        {!docs.length && <tr><td colSpan={7} className="py-6 text-center text-gray-500">Sin resultados.</td></tr>}
      </tbody>
    </table>
  )
}

function FichaClienteModal({ cliente, onClose }: { cliente: ClienteCxc; onClose: () => void }) {
  const { data, isLoading, error } = useQuery({ queryKey: ['cxc-cliente', cliente.cod_aux], queryFn: () => getFichaCliente(cliente.cod_aux) })
  const p = clasificarPagador(cliente)
  return (
    <Modal open onClose={onClose} title={cliente.cliente} description={cliente.rut ?? undefined} className="sm:max-w-4xl">
      <div className="max-h-[70vh] space-y-4 overflow-y-auto">
        <div className="grid gap-2 text-sm sm:grid-cols-4">
          <Dato titulo="Debe" valor={fmtClp(cliente.deuda)} />
          <Dato titulo="Vencido" valor={(cliente.vencido ?? 0) > 0 ? fmtClp(cliente.vencido) : '—'} />
          <Dato titulo="Facturado 2026" valor={fmtMM(cliente.facturado)} />
          <div className="rounded-lg bg-gray-50 p-2"><p className="text-xs text-gray-500">Pagador</p><div className="mt-1"><BadgePagador p={p} /></div><p className="mt-1 text-[11px] text-gray-500">{p.detalle}</p></div>
        </div>
        {data?.cliente && (
          <p className="text-xs text-gray-600">
            Correo: {data.cliente.email || data.cliente.email_dte || 'sin correo en Softland'}
            {data.cliente.telefono ? ` · Tel. ${data.cliente.telefono}` : ''}
            {data.cliente.dia_plazo ? ` · Plazo ${data.cliente.dia_plazo} días` : ''}
          </p>
        )}
        {isLoading && <div className="flex justify-center py-6"><Spinner /></div>}
        {error && <p className="text-sm text-red-700">No se pudo cargar la ficha: {(error as Error).message}</p>}
        {data && (
          <div className="overflow-x-auto">
          <table className="w-full min-w-[640px] text-sm">
            <thead>
              <tr className="text-left text-xs text-gray-500">
                <th className="py-2">Folio</th><th>Emisión</th><th>Vence</th><th className="text-right">Monto</th>
                <th className="text-right">Saldo</th><th className="pl-4">Estado</th><th>Equipos</th>
              </tr>
            </thead>
            <tbody>
              {data.documentos.map((d) => (
                <tr key={d.folio} className="border-t border-gray-100 align-top">
                  <td className="py-2 font-mono text-xs">{d.folio}</td>
                  <td className="whitespace-nowrap">{fecha(d.emision)}</td>
                  <td className="whitespace-nowrap">{fecha(d.vence)}</td>
                  <td className="text-right tabular-nums">{fmtClp(d.monto)}</td>
                  <td className="text-right tabular-nums">{d.saldo > 0 ? fmtClp(d.saldo) : '—'}</td>
                  <td className="pl-4">
                    <EstadoTexto d={d} />
                    {d.estado === 'pagada' && d.dias_pago != null && <span className="block text-[11px] text-gray-500">en {d.dias_pago} días</span>}
                  </td>
                  <td className="max-w-[14rem]"><Patentes lista={d.equipos.map((e) => e.patente)} /></td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        )}
      </div>
      <div className="mt-4 flex justify-end">
        <button type="button" onClick={onClose} className="inline-flex items-center gap-1 rounded-lg border border-gray-300 px-3 py-2 text-sm"><X className="h-4 w-4" aria-hidden="true" />Cerrar</button>
      </div>
    </Modal>
  )
}

function Dato({ titulo, valor }: { titulo: string; valor: string }) {
  return <div className="rounded-lg bg-gray-50 p-2"><p className="text-xs text-gray-500">{titulo}</p><p className="mt-0.5 font-semibold tabular-nums text-gray-900">{valor}</p></div>
}
