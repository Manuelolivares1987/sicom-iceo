'use client'

// ============================================================================
// Informe mensual de gestión — Franke (MIG367/368)
// ----------------------------------------------------------------------------
// Las ocho páginas que hoy se escriben el día 3 del mes siguiente cruzando una
// planilla de 4.989 filas. Acá salen calculadas, en el mismo orden y con los
// mismos cortes que el documento que se le manda a CM Cenizas.
//
// LO QUE NO CALCULA SE DICE, NO SE ESCONDE
// Las novedades del periodo, las horas hombre y las conclusiones son criterio
// del Administrador de Contrato. La pantalla las lista como pendientes de
// redacción. Un informe que se ve completo y no lo está es peor que uno que
// declara sus huecos.
//
// LAS ADVERTENCIAS VAN ARRIBA
// «No hay conteo físico de cierre» tiene que verse antes que los números
// bonitos, porque es lo que decide si el informe se puede emitir. En julio esa
// advertencia habría aparecido, y el informe salió igual con +366 L de ajustes
// sin respaldo.
// ============================================================================

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  FileText, AlertTriangle, PenLine, Users, Truck, Fuel, Ticket, Scale,
  Printer, CheckCircle2,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { cn } from '@/lib/utils'
import { FAENA_FRANKE, getFaenaId } from '@/lib/services/faena-pauta'
import { getInformeMensual, mesDe } from '@/lib/services/faena-entrega'

const miles = (n: number | null | undefined) =>
  n == null || Number.isNaN(Number(n)) ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 0 })
const pct = (n: number | null | undefined) =>
  n == null ? '—' : `${Number(n).toLocaleString('es-CL', { minimumFractionDigits: 3, maximumFractionDigits: 3 })} %`

// El informe lo lee el mandante. «en_mantenimiento» es el nombre de un valor de
// la base de datos, no castellano.
const ESTADO: Record<string, string> = {
  operativo: 'Operativo',
  back_up: 'Back up',
  en_mantencion: 'En mantención',
  en_mantenimiento: 'En mantención',
  fuera_de_faena: 'Fuera de faena',
  detenido: 'Detenido',
  de_baja: 'De baja',
  siniestrado: 'Siniestrado',
}
const estadoTexto = (e: string) => ESTADO[e] ?? e.replace(/_/g, ' ')

export default function InformeMensualFrankePage() {
  useRequireAuth()
  const inicial = useMemo(() => {
    // Por omisión, el mes pasado: el informe se emite los primeros días del
    // mes siguiente, que es cuando alguien abre esta pantalla.
    const d = new Date()
    d.setMonth(d.getMonth() - 1)
    return mesDe(d)
  }, [])
  const [desde, setDesde] = useState(inicial.desde)
  const [hasta, setHasta] = useState(inicial.hasta)

  const { data: faenaId } = useQuery({
    queryKey: ['faena', FAENA_FRANKE],
    queryFn: () => getFaenaId(FAENA_FRANKE),
  })
  const { data: inf, isLoading } = useQuery({
    queryKey: ['informe-franke', faenaId, desde, hasta],
    queryFn: () => getInformeMensual(faenaId as string, desde, hasta),
    enabled: !!faenaId,
  })

  return (
    <div className="space-y-6 p-6 print:p-0">
      <div className="flex flex-wrap items-end justify-between gap-4 print:hidden">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Informe mensual de gestión</h1>
          <p className="mt-1 text-sm text-gray-600">
            Contrato FRK 220/2024 · Servicio de abastecimiento de combustible en Faena Franke
          </p>
        </div>
        <div className="flex items-end gap-2">
          <label className="block">
            <span className="text-xs font-semibold text-gray-600">Desde</span>
            <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)}
                   className="mt-1 h-10 rounded-lg border-2 border-gray-300 px-2 text-sm" />
          </label>
          <label className="block">
            <span className="text-xs font-semibold text-gray-600">Hasta</span>
            <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)}
                   className="mt-1 h-10 rounded-lg border-2 border-gray-300 px-2 text-sm" />
          </label>
          <button onClick={() => window.print()}
                  className="flex h-10 items-center gap-2 rounded-lg bg-gray-900 px-4 text-sm font-semibold text-white">
            <Printer className="h-4 w-4" /> Imprimir
          </button>
        </div>
      </div>

      {isLoading && <div className="flex justify-center py-16"><Spinner /></div>}

      {inf && (
        <>
          <p className="text-sm text-gray-600">{inf.periodo.texto}</p>

          {/* ── Lo que impide emitir el informe ───────────────────────── */}
          {inf.advertencias?.length > 0 && (
            <Card className="border-amber-300 bg-amber-50">
              <CardHeader className="pb-2">
                <CardTitle className="flex items-center gap-2 text-base text-amber-900">
                  <AlertTriangle className="h-5 w-5" /> Antes de emitirlo
                </CardTitle>
              </CardHeader>
              <CardContent>
                <ul className="space-y-1.5 text-sm text-amber-900">
                  {inf.advertencias.map((a) => <li key={a}>· {a}</li>)}
                </ul>
              </CardContent>
            </Card>
          )}

          {/* ── 4. Abastecimiento: los números duros ──────────────────── */}
          <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Kpi t="Transacciones" v={miles(inf.litros_por_concepto?.transacciones)} u="L" />
            <Kpi t="Ventas" v={miles(inf.litros_por_concepto?.ventas)} u="L" destacado />
            <Kpi t="Trasvasijes" v={miles(inf.litros_por_concepto?.trasvasijes)} u="L" />
            <Kpi t="Deriva del cuentalitros" v={pct(inf.deriva?.pct)}
                 sub={`${miles(inf.deriva?.diferencia)} L en ${miles(inf.deriva?.transacciones_medidas)} transacciones`} />
          </section>

          <div className="grid gap-6 lg:grid-cols-2">
            {/* Tickets y folios */}
            <Bloque icono={Ticket} titulo="Tickets emitidos">
              <Fila k="Total con folio" v={miles(inf.tickets?.emitidos)} />
              <Fila k="Ventas" v={miles(inf.tickets?.ventas)} />
              <Fila k="Ventas válidas" v={miles(inf.tickets?.ventas_validas)} />
              <Fila k="Nulos (cero litros)" v={miles(inf.tickets?.nulos_cero_litros)} />
              <Fila k="Trasvasije y stock inicial" v={miles(inf.tickets?.trasvasije_y_stock)} />
              <Fila k="Calibración o recirculación" v={miles(inf.tickets?.calibracion_recirculacion)} />
              <Fila k="Folios"
                    v={inf.tickets?.folio_desde != null
                       ? `${inf.tickets.folio_desde} → ${inf.tickets.folio_hasta}` : '—'} />
              {inf.tickets?.sin_folio > 0 && (
                <Fila k="Cargas sin folio" v={miles(inf.tickets.sin_folio)} alerta />
              )}
              {inf.folios_faltantes?.length > 0 && (
                <p className="mt-2 rounded-lg bg-amber-50 p-2 text-xs text-amber-900">
                  <strong>{inf.folios_faltantes.length} folio(s) sin registrar:</strong>{' '}
                  {inf.folios_faltantes.slice(0, 12).map((f) => f.folio).join(', ')}
                  {inf.folios_faltantes.length > 12 && '…'}
                </p>
              )}
            </Bloque>

            {/* Balance */}
            <Bloque icono={Scale} titulo="Balance del periodo">
              <Fila k="Stock inicial" v={miles(inf.balance?.stock_inicial)} u="L"
                    sub={inf.balance?.stock_inicial_verificado ? 'verificado' : 'sin verificar'}
                    alerta={!inf.balance?.stock_inicial_verificado} />
              <Fila k="Cargas" v={miles(inf.balance?.cargas)} u="L" />
              <Fila k="Ventas" v={miles(inf.balance?.ventas)} u="L" />
              <Fila k="Stock teórico al cierre" v={miles(inf.balance?.stock_teorico)} u="L" />
              <Fila k="Stock físico al cierre" v={miles(inf.balance?.stock_fisico)} u="L"
                    sub={inf.balance?.stock_fisico_verificado ? 'verificado' : 'sin verificar'}
                    alerta={!inf.balance?.stock_fisico_verificado} />
              {inf.balance?.comparable ? (
                <Fila k="Diferencia" v={miles(inf.balance.diferencia)} u="L"
                      sub={pct(inf.balance.diferencia_pct)} destacado />
              ) : (
                <p className="mt-2 rounded-lg bg-gray-100 p-2 text-xs text-gray-700">
                  {inf.balance?.por_que_no_comparable}
                </p>
              )}
            </Bloque>

            {/* Ventas por cargo */}
            <Bloque icono={Fuel} titulo="Ventas por cargo">
              {inf.ventas_por_cargo?.length === 0
                ? <Vacio>No hay ventas registradas en el periodo.</Vacio>
                : inf.ventas_por_cargo.map((c) => (
                    <Fila key={c.ceco ?? 'sin'} k={c.ceco ?? '(sin CECO)'} v={miles(c.litros)} u="L"
                          sub={c.empresa ?? undefined} />
                  ))}
              {inf.no_venta_por_concepto?.length > 0 && (
                <>
                  <p className="mt-3 border-t border-gray-200 pt-3 text-xs font-semibold uppercase tracking-wide text-gray-500">
                    Movimientos que no son venta
                  </p>
                  {inf.no_venta_por_concepto.map((c) => (
                    <Fila key={c.concepto} k={c.concepto} v={miles(c.litros)} u="L"
                          sub={`${c.tickets} ticket(s)`} />
                  ))}
                </>
              )}
            </Bloque>

            {/* Cargas */}
            <Bloque icono={Truck} titulo="Cargas del camión en estación">
              {inf.cargas_por_camion?.length === 0
                ? <Vacio>No hay cargas registradas. Sin ellas el balance no cierra contra la estación.</Vacio>
                : inf.cargas_por_camion.map((c) => (
                    <Fila key={c.camion} k={c.camion} v={miles(c.litros)} u="L"
                          sub={`${c.cargas} carga(s)`} />
                  ))}
              {inf.cargas_por_surtidor?.length > 0 && (
                <>
                  <p className="mt-3 border-t border-gray-200 pt-3 text-xs font-semibold uppercase tracking-wide text-gray-500">
                    Por surtidor
                  </p>
                  {inf.cargas_por_surtidor.map((s) => (
                    <Fila key={`${s.eds}-${s.surtidor}`} k={`${s.eds} · surtidor ${s.surtidor}`}
                          v={miles(s.litros)} u="L" />
                  ))}
                </>
              )}
            </Bloque>
          </div>

          {/* ── 3. Equipos ────────────────────────────────────────────── */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="flex items-center gap-2 text-base">
                <Truck className="h-5 w-5 text-gray-400" /> Equipos al cierre
              </CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="border-y border-gray-200 bg-gray-50 text-left text-xs uppercase tracking-wide text-gray-500">
                    <tr>
                      <th className="px-4 py-2">Equipo</th><th className="px-4 py-2">Estado</th>
                      <th className="px-4 py-2 text-right">Horómetro</th>
                      <th className="px-4 py-2 text-right">Kilometraje</th>
                      <th className="px-4 py-2 text-right">Desviaciones</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {inf.equipos?.map((e) => (
                      <tr key={e.patente ?? e.equipo}>
                        <td className="px-4 py-2">
                          <span className="font-semibold text-gray-900">{e.patente}</span>
                          <span className="ml-2 text-xs text-gray-500">{e.equipo}</span>
                        </td>
                        <td className="px-4 py-2">
                          {estadoTexto(e.estado)}
                          <span className="ml-1.5 text-[11px] text-gray-400">({e.origen_estado})</span>
                        </td>
                        <td className="px-4 py-2 text-right tabular-nums">{miles(e.horometro)}</td>
                        <td className="px-4 py-2 text-right tabular-nums">{miles(e.kilometraje)}</td>
                        <td className={cn('px-4 py-2 text-right tabular-nums',
                                          e.desviaciones > 0 && 'font-semibold text-red-700')}>
                          {e.desviaciones}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </CardContent>
          </Card>

          {/* ── Entregas de turno del periodo ──────────────────────────── */}
          {inf.entregas_turno?.length > 0 && (
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="flex items-center gap-2 text-base">
                  <CheckCircle2 className="h-5 w-5 text-gray-400" /> Entregas de turno del periodo
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                {inf.entregas_turno.map((e) => (
                  <div key={`${e.desde}-${e.turno_saliente}`}
                       className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-lg border border-gray-200 p-3 text-sm">
                    <span className="font-mono tabular-nums text-gray-600">{e.desde} → {e.hasta}</span>
                    <span className="font-semibold">Turno {e.turno_saliente} → {e.turno_entrante}</span>
                    <span className={cn('rounded px-1.5 py-0.5 text-xs font-semibold',
                                        e.estado === 'recibida' ? 'bg-emerald-100 text-emerald-800'
                                        : e.estado === 'entregada' ? 'bg-blue-100 text-blue-800'
                                        : 'bg-amber-100 text-amber-800')}>
                      {e.estado}
                    </span>
                    {e.conteo_fisico
                      ? <span className="tabular-nums text-gray-700">{miles(e.stock_fisico)} L verificados</span>
                      : <span className="text-xs text-red-700">sin conteo físico{e.conteo_omitido_motivo ? `: ${e.conteo_omitido_motivo}` : ''}</span>}
                    {e.reparos && <span className="w-full text-xs text-amber-800">Reparos: {e.reparos}</span>}
                  </div>
                ))}
              </CardContent>
            </Card>
          )}

          {/* ── 2. Dotación y 5. Año ──────────────────────────────────── */}
          <div className="grid gap-6 lg:grid-cols-2">
            <Bloque icono={Users} titulo={`Dotación · ${inf.dotacion?.length ?? 0} personas`}>
              {inf.dotacion?.map((p) => (
                <Fila key={p.nombre} k={p.nombre} v="" sub={p.cargo ?? p.rol} />
              ))}
            </Bloque>

            <Bloque icono={Fuel} titulo={`Acumulado ${inf.anio?.anio}`}>
              <Fila k="Ventas del año" v={miles(inf.anio?.ventas)} u="L" destacado />
              <Fila k="Transacciones" v={miles(inf.anio?.transacciones)} />
              {inf.mayores_consumidores_anio?.length > 0 && (
                <>
                  <p className="mt-3 border-t border-gray-200 pt-3 text-xs font-semibold uppercase tracking-wide text-gray-500">
                    Mayores consumidores
                  </p>
                  {inf.mayores_consumidores_anio.map((c) => (
                    <Fila key={c.ceco ?? 'sin'} k={c.ceco ?? '(sin CECO)'} v={miles(c.litros)} u="L" />
                  ))}
                </>
              )}
            </Bloque>
          </div>

          {/* ── Lo que hay que escribir ───────────────────────────────── */}
          <Card className="border-gray-300">
            <CardHeader className="pb-2">
              <CardTitle className="flex items-center gap-2 text-base">
                <PenLine className="h-5 w-5 text-gray-400" /> Falta escribir
              </CardTitle>
            </CardHeader>
            <CardContent>
              <p className="mb-2 text-sm text-gray-600">
                El sistema no tiene estos datos y no los inventa. Los redacta el Administrador
                de Contrato antes de emitir.
              </p>
              <ul className="space-y-1.5 text-sm text-gray-800">
                {inf.redaccion_pendiente?.map((r) => <li key={r}>· {r}</li>)}
              </ul>
            </CardContent>
          </Card>

          <p className="flex items-center gap-2 text-xs text-gray-500">
            <FileText className="h-3.5 w-3.5" />
            El periodo corre de {inf.periodo.hora_corte?.slice(0, 5)} a {inf.periodo.hora_corte?.slice(0, 5)} hrs.,
            de cambio de turno a cambio de turno, como lo declara el contrato.
          </p>
        </>
      )}
    </div>
  )
}

function Kpi({ t, v, u, sub, destacado }: {
  t: string; v: string; u?: string; sub?: string; destacado?: boolean
}) {
  return (
    <Card className={cn(destacado && 'border-gray-900')}>
      <CardContent className="p-4">
        <p className="font-mono text-2xl font-bold tabular-nums text-gray-900">
          {v}{u && <span className="ml-1 text-sm font-normal text-gray-500">{u}</span>}
        </p>
        <p className="mt-1 text-xs text-gray-500">{t}</p>
        {sub && <p className="mt-0.5 text-[11px] text-gray-400">{sub}</p>}
      </CardContent>
    </Card>
  )
}

function Bloque({ icono: Icono, titulo, children }: {
  icono: typeof Ticket; titulo: string; children: React.ReactNode
}) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-base">
          <Icono className="h-5 w-5 text-gray-400" /> {titulo}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-1">{children}</CardContent>
    </Card>
  )
}

function Fila({ k, v, u, sub, alerta, destacado }: {
  k: string; v: string; u?: string; sub?: string; alerta?: boolean; destacado?: boolean
}) {
  return (
    <div className="flex items-baseline justify-between gap-3 border-b border-gray-100 py-1.5 last:border-0">
      <div className="min-w-0">
        <span className={cn('text-sm', destacado ? 'font-semibold text-gray-900' : 'text-gray-700')}>{k}</span>
        {sub && <span className={cn('ml-2 text-[11px]', alerta ? 'text-red-600' : 'text-gray-400')}>{sub}</span>}
      </div>
      {v !== '' && (
        <span className={cn('shrink-0 font-mono tabular-nums',
                            destacado ? 'text-base font-bold text-gray-900' : 'text-sm text-gray-900')}>
          {v}{u && <span className="ml-1 text-xs font-normal text-gray-500">{u}</span>}
        </span>
      )}
    </div>
  )
}

function Vacio({ children }: { children: React.ReactNode }) {
  return <p className="py-3 text-sm text-gray-400">{children}</p>
}
