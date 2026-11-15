'use client'

// ============================================================================
// Control de combustible — tablero para directorio (MIG691)
// ----------------------------------------------------------------------------
// Una página en cuatro bloques, el formato que recomienda el benchmark
// (reports/Control combustible flota benchmark.md):
//   1. Resultado económico: gasto vs mes anterior, km/L y $/km de la flota.
//   2. Cobertura del control: qué parte del gasto está bajo control y qué no
//      (tarjetas de uso personal de jefatura declaradas fuera de alcance).
//   3. Diferencias: detectadas, justificadas, por validar y pendientes por
//      operación, con antigüedad. Jefatura acepta o rechaza aquí.
//   4. Ficha del control y limitaciones declaradas.
// Los datos de detalle siguen en /dashboard/flota/rendimiento-combustible.
// ============================================================================

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  AlertTriangle, ArrowDownRight, ArrowUpRight, CheckCircle2, Clock, Printer, ShieldCheck, XCircle,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { cn, errorMessage } from '@/lib/utils'
import {
  ALERTA_TXT, getCargasTarjeta, getImportaciones, getLlamadasApi, getPrimeraCarga, getRendimientoMes, getTarjetasAramco,
  type Alerta,
} from '@/lib/services/combustible-tarjeta'
import {
  diasDesde, getDestinatariosReporte, getDiferenciasPorOperacion, getExcluidas, tramoAntiguedad, validarJustificacion,
  type DiferenciaComb,
} from '@/lib/services/combustible-control'
import { mesIso, rangoMeses, serieFlota, sumarMes, variacion } from '@/lib/combustible-tendencia'
import { GraficoKmL, GraficoLitros, nombreMes } from '../rendimiento-combustible/graficos'

const n0 = (n: number | null | undefined) => (n == null ? '—' : Math.round(Number(n)).toLocaleString('es-CL'))
const n1 = (n: number | null | undefined) => (n == null ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 1 }))
const mm = (n: number | null | undefined) => (n == null ? '—' : '$' + (Number(n) / 1e6).toLocaleString('es-CL', { maximumFractionDigits: 2 }) + ' MM')
const pct = (n: number | null | undefined) => (n == null ? '—' : Math.round(n * 100) + ' %')
const fechaHora = (s: string) => new Date(s).toLocaleString('es-CL', { dateStyle: 'short', timeStyle: 'short' })
const TRAMOS = ['0-7', '8-15', '16-30', '+30'] as const

export default function ControlCombustiblePage() {
  const { loading: authLoading } = useRequireAuth()
  const hoy = new Date()
  const mes = mesIso(hoy.getFullYear(), hoy.getMonth() + 1)
  const meses = useMemo(() => rangoMeses(mes, 12), [mes])
  const [mesGrafico, setMesGrafico] = useState(mes)

  const { data: rend = [] } = useQuery({ queryKey: ['comb-rendimiento-mes', meses[0]], queryFn: () => getRendimientoMes(meses[0]) })
  const { data: importaciones = [] } = useQuery({ queryKey: ['comb-tarjeta-importaciones'], queryFn: getImportaciones })
  const { data: inicio = null } = useQuery({ queryKey: ['comb-tarjeta-importaciones', 'inicio'], queryFn: getPrimeraCarga })
  const { data: cargasMes = [] } = useQuery({ queryKey: ['comb-tarjeta-cargas', mes], queryFn: () => getCargasTarjeta(mes, sumarMes(mes, 1)) })
  const { data: tarjetas = [] } = useQuery({ queryKey: ['comb-tarjeta-tarjetas'], queryFn: getTarjetasAramco })
  const { data: llamadas = [] } = useQuery({ queryKey: ['comb-tarjeta-api'], queryFn: getLlamadasApi })
  const { data: difs = {} } = useQuery({ queryKey: ['comb-diferencias'], queryFn: getDiferenciasPorOperacion })
  const { data: destinatarios = [] } = useQuery({ queryKey: ['comb-destinatarios'], queryFn: getDestinatariosReporte })
  const { data: excluidas = [] } = useQuery({ queryKey: ['comb-excluidas'], queryFn: getExcluidas })

  const corte = useMemo(() => {
    const h = importaciones.map((i) => i.hasta?.slice(0, 10)).filter(Boolean).sort() as string[]
    return h.length ? h[h.length - 1] : null
  }, [importaciones])
  const serie = useMemo(() => serieFlota(rend, meses, corte, inicio), [rend, meses, corte, inicio])
  const actual = serie[serie.length - 1]
  const anterior = serie[serie.length - 2]
  const prom3 = useMemo(() => {
    const p = serie.slice(-4, -1).filter((s) => s.kmL != null && !s.incompleto)
    return p.length ? p.reduce((a, s) => a + (s.kmL ?? 0), 0) / p.length : null
  }, [serie])
  const gasto12 = serie.filter((s) => !s.incompleto).reduce((a, s) => a + s.monto, 0)

  // Cobertura
  const tarjetasBajoControl = tarjetas.filter((t) => !excluidas.some((x) => x.patente === t.patente))
  const conLimite = tarjetas.filter((t) => (t.limite_monto ?? 0) > 0 || (t.limite_volumen ?? 0) > 0).length
  const conGps = cargasMes.filter((c) => c.tiene_gps).length
  const conKm = cargasMes.filter((c) => c.km_tramo != null).length
  const ultimaSync = llamadas.find((l) => l.operacion === 'transacciones' && l.estado === 'ok')

  // Diferencias
  const operaciones = Object.keys(difs).sort()
  const todas = operaciones.flatMap((op) => difs[op].map((d) => ({ ...d, operacion: op })))
  const pendientes = todas.filter((d) => d.estado === 'pendiente')
  const porValidar = todas.filter((d) => d.estado === 'por_validar')
  const cerradas = todas.filter((d) => d.estado === 'cerrada')
  const tasaCierre = todas.length ? cerradas.length / todas.length : null

  if (authLoading) return null
  const varGasto = variacion(actual?.montoProy ?? null, anterior?.monto ?? null)
  const varKmL = variacion(actual?.kmL ?? null, prom3)

  return (
    <div className="mx-auto max-w-7xl space-y-6 p-4 md:p-6 print:max-w-none print:p-0">
      <header className="flex flex-wrap items-end justify-between gap-3 border-b pb-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-emerald-800">Control interno · Combustible</p>
          <h1 className="text-2xl font-bold text-gray-900">Tarjetas Aramco Fleet cruzadas con GPS</h1>
          <p className="text-sm text-gray-500">
            {nombreMes(mes)} · datos sincronizados con Aramco cada hora
            {ultimaSync && <> · última sincronización {fechaHora(ultimaSync.procesada_at ?? ultimaSync.creada_at)}</>}
          </p>
        </div>
        <div className="flex gap-2 print:hidden">
          <Link href="/dashboard/flota/rendimiento-combustible" className="rounded-lg border bg-white px-3 py-2 text-sm font-medium hover:bg-gray-50">Ver detalle</Link>
          <button onClick={() => window.print()} className="flex items-center gap-2 rounded-lg bg-emerald-800 px-3 py-2 text-sm font-medium text-white hover:bg-emerald-900">
            <Printer className="h-4 w-4" /> Imprimir / PDF
          </button>
        </div>
      </header>

      {/* 1. Resultado económico */}
      <Bloque numero={1} titulo="Resultado económico" nota={actual?.parcial ? `Mes en curso proyectado al cierre con datos hasta el ${corte?.split('-').reverse().join('-')}.` : undefined}>
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <Kpi titulo={`Gasto ${nombreMes(mes).toLowerCase()}${actual?.parcial ? ' (proy.)' : ''}`} valor={mm(actual?.montoProy)}
               delta={varGasto} deltaTxt="vs mes anterior" invertir />
          <Kpi titulo="Gasto últimos 12 meses" valor={mm(gasto12)} sub={`${n0(serie.reduce((a, s) => a + s.litros, 0))} L`} />
          <Kpi titulo="Rendimiento flota" valor={actual?.kmL != null ? `${n1(actual.kmL)} km/L` : '—'} delta={varKmL} deltaTxt="vs promedio 3 meses" />
          <Kpi titulo="Costo por km" valor={actual?.costoKm != null ? `$${n0(actual.costoKm)}` : '—'} sub="combustible / km GPS" />
        </div>
        <div className="grid gap-4 lg:grid-cols-2">
          <div className="rounded-xl border bg-white p-4">
            <p className="mb-2 text-sm font-semibold text-gray-700">Litros por mes</p>
            <GraficoLitros serie={serie} mes={mesGrafico} onElegir={setMesGrafico} />
          </div>
          <div className="rounded-xl border bg-white p-4">
            <p className="mb-2 text-sm font-semibold text-gray-700">km/L de la flota</p>
            <GraficoKmL serie={serie} mes={mesGrafico} />
          </div>
        </div>
      </Bloque>

      {/* 2. Cobertura */}
      <Bloque numero={2} titulo="Cobertura del control">
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <Kpi titulo="Tarjetas bajo control" valor={`${tarjetasBajoControl.length} de ${tarjetas.length}`}
               sub={excluidas.length ? `${excluidas.length} fuera de alcance` : undefined} />
          <Kpi titulo="Cargas del mes con GPS" valor={cargasMes.length ? pct(conGps / cargasMes.length) : '—'} sub={`${conGps} de ${cargasMes.length}`} />
          <Kpi titulo="Cargas con km medidos" valor={cargasMes.length ? pct(conKm / cargasMes.length) : '—'} sub="para calcular km/L" />
          <Kpi titulo="Tarjetas con límite en Aramco" valor={`${conLimite} de ${tarjetas.length}`}
               estado={conLimite < tarjetas.length ? 'alerta' : 'ok'} sub={conLimite < tarjetas.length ? 'sin freno preventivo en la bomba' : undefined} />
        </div>
        {excluidas.length > 0 && (
          <p className="text-xs text-gray-500">
            <b>Fuera de alcance:</b> {excluidas.map((x) => `${x.patente.slice(0, 4)}-${x.patente.slice(4)} (${x.motivo_alcance ?? x.motivo})`).join(' · ')}.
            Su gasto aparece en la facturación de Aramco, pero no se audita con GPS.
          </p>
        )}
      </Bloque>

      {/* 3. Diferencias */}
      <Bloque numero={3} titulo="Diferencias detectadas y su justificación"
              nota="Diferencia = carga fuera de horario (L-V 04:00-19:00), lejos de la estación según GPS, sobre la capacidad del estanque, sin movimiento, o litros que no explican los km. Cada operación recibe un reporte semanal y debe justificar.">
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <Kpi titulo="Detectadas desde sept-2026" valor={String(todas.length)} />
          <Kpi titulo="Cerradas" valor={String(cerradas.length)} sub={tasaCierre != null ? `${pct(tasaCierre)} del total` : undefined} estado={cerradas.length === todas.length ? 'ok' : undefined} />
          <Kpi titulo="Por validar (jefatura)" valor={String(porValidar.length)} estado={porValidar.length ? 'alerta' : 'ok'} />
          <Kpi titulo="Pendientes de justificar" valor={String(pendientes.length)} estado={pendientes.length ? 'critico' : 'ok'} />
        </div>
        <div className="overflow-x-auto rounded-xl border bg-white">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-left text-xs uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-4 py-2">Operación</th><th className="px-4 py-2">Responsable</th>
                <th className="px-4 py-2 text-right">Detectadas</th><th className="px-4 py-2 text-right">Cerradas</th>
                <th className="px-4 py-2 text-right">Por validar</th><th className="px-4 py-2 text-right">Pendientes</th>
                {TRAMOS.map((t) => <th key={t} className="px-3 py-2 text-right">{t} d</th>)}
              </tr>
            </thead>
            <tbody className="divide-y">
              {operaciones.map((op) => {
                const ds = difs[op]
                const pend = ds.filter((d) => d.estado === 'pendiente')
                const resp = destinatarios.find((x) => x.operacion === op && x.responsable)
                const porTramo = (t: string) => pend.filter((d) => tramoAntiguedad(diasDesde(d.fecha_hora)) === t).length
                return (
                  <tr key={op}>
                    <td className="px-4 py-2 font-semibold">{op}</td>
                    <td className="px-4 py-2 text-gray-600">{resp?.nombre ?? <span className="text-amber-700">sin responsable</span>}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{ds.length}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{ds.filter((d) => d.estado === 'cerrada').length}</td>
                    <td className="px-4 py-2 text-right tabular-nums">{ds.filter((d) => d.estado === 'por_validar').length}</td>
                    <td className={cn('px-4 py-2 text-right font-semibold tabular-nums', pend.length ? 'text-red-700' : 'text-gray-900')}>{pend.length}</td>
                    {TRAMOS.map((t) => {
                      const n = porTramo(t)
                      return <td key={t} className={cn('px-3 py-2 text-right tabular-nums', n && t !== '0-7' ? 'font-semibold text-red-700' : 'text-gray-500')}>{n || '·'}</td>
                    })}
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
        {porValidar.length > 0 && <PorValidar filas={porValidar} />}
        {pendientes.length > 0 && (
          <details className="rounded-xl border bg-white px-4 py-3 text-sm print:open">
            <summary className="cursor-pointer font-medium text-gray-700">Ver las {pendientes.length} pendientes</summary>
            <ul className="mt-2 divide-y">
              {pendientes.map((d) => (
                <li key={d.carga_id} className="flex flex-wrap justify-between gap-2 py-2">
                  <span><b>{d.patente}</b> · {d.operacion} · {fechaHora(d.fecha_hora)} · {n1(d.litros)} L</span>
                  <span className="text-red-700">{d.alertas.map((a) => ALERTA_TXT[a as Alerta] ?? a).join(' · ')}</span>
                </li>
              ))}
            </ul>
          </details>
        )}
      </Bloque>

      {/* 4. Ficha del control */}
      <Bloque numero={4} titulo="Ficha del control">
        <div className="grid gap-4 lg:grid-cols-2">
          <dl className="grid grid-cols-[9rem_1fr] gap-x-4 gap-y-2 rounded-xl border bg-white p-4 text-sm">
            <dt className="text-gray-500">Objetivo</dt><dd>Detectar uso indebido de las tarjetas de combustible y desviaciones de rendimiento.</dd>
            <dt className="text-gray-500">Alcance</dt><dd>{tarjetasBajoControl.length} tarjetas Aramco Fleet de vehículos livianos. Fuera: tarjetas de uso personal de jefatura y camiones que cargan en faena.</dd>
            <dt className="text-gray-500">Cómo funciona</dt><dd>Cada hora se descargan las transacciones de Aramco y se cruzan con la posición y los km del GPS (Navixy/Radicom).</dd>
            <dt className="text-gray-500">Umbrales</dt><dd>Carga &gt; 110 % del estanque · L-V 04:00-19:00 · distancia a la estación · 30 días: litros ≤ km ÷ km/L normal × 1,2 + 1 estanque.</dd>
            <dt className="text-gray-500">Frecuencia</dt><dd>Detección continua; reporte semanal (lunes) y recordatorio (jueves) por operación.</dd>
            <dt className="text-gray-500">Responsables</dt>
            <dd>{Array.from(new Set(destinatarios.filter((x) => x.responsable).map((x) => `${x.operacion}: ${x.nombre ?? x.email}`))).join(' · ')} justifican; jefatura valida (acepta o rechaza).</dd>
            <dt className="text-gray-500">Evidencia</dt><dd>Cada diferencia queda con justificación, autor, fecha y validación; nada se borra.</dd>
          </dl>
          <div className="space-y-2 rounded-xl border bg-white p-4 text-sm">
            <p className="flex items-center gap-2 font-semibold text-gray-700"><AlertTriangle className="h-4 w-4 text-amber-600" /> Limitaciones declaradas</p>
            <ul className="list-disc space-y-1 pl-5 text-gray-600">
              <li>Sin sensor de nivel de estanque: una sobrefacturación en la bomba solo se ve en el rendimiento sostenido, no carga a carga.</li>
              <li>El odómetro no se digita en la bomba; los km vienen del GPS desde mediados de sept-2026.</li>
              {conLimite < tarjetas.length && <li>{tarjetas.length - conLimite} tarjetas sin límite en el portal Aramco: el control es de detección, no de prevención.</li>}
              <li>Las tarjetas de uso personal de jefatura no se auditan con GPS.</li>
            </ul>
            <p className="flex items-center gap-2 pt-2 text-xs text-gray-500"><ShieldCheck className="h-4 w-4 text-emerald-700" /> Referencia: buenas prácticas de Samsara, Geotab, Verizon Connect y auditoría municipal de Fort Worth (2025).</p>
          </div>
        </div>
      </Bloque>
    </div>
  )
}

function PorValidar({ filas }: { filas: (DiferenciaComb & { operacion: string })[] }) {
  const qc = useQueryClient()
  const toast = useToast()
  const [ocupado, setOcupado] = useState<string | null>(null)
  async function validar(d: DiferenciaComb, aceptar: boolean) {
    let nota = ''
    if (!aceptar) {
      nota = (document.getElementById(`nota-${d.carga_id}`) as HTMLInputElement | null)?.value ?? ''
      if (nota.trim().length < 5) { toast.error('Escriba qué falta en la justificación.'); return }
    }
    setOcupado(d.carga_id)
    try {
      await validarJustificacion(d.carga_id, aceptar, nota)
      toast.success(aceptar ? 'Justificación aceptada.' : 'Rechazada: vuelve a pendiente para la operación.')
      qc.invalidateQueries({ queryKey: ['comb-diferencias'] })
      qc.invalidateQueries({ queryKey: ['comb-tarjeta-revisiones'] })
    } catch (e) { toast.error(errorMessage(e)) } finally { setOcupado(null) }
  }
  return (
    <Card className="border-amber-200 print:hidden">
      <CardHeader className="pb-2"><CardTitle className="flex items-center gap-2 text-base"><Clock className="h-4 w-4 text-amber-600" /> Justificaciones por validar</CardTitle></CardHeader>
      <CardContent className="divide-y p-0">
        {filas.map((d) => (
          <div key={d.carga_id} className="space-y-2 px-4 py-3 text-sm">
            <p><b>{d.patente}</b> · {d.operacion} · {fechaHora(d.fecha_hora)} · {n1(d.litros)} L · <span className="text-red-700">{d.alertas.map((a) => ALERTA_TXT[a as Alerta] ?? a).join(' · ')}</span></p>
            <p className="rounded-lg bg-gray-50 p-2 text-gray-700">«{d.comentario}» <span className="text-gray-400">— {d.autor}</span></p>
            <div className="flex flex-wrap gap-2">
              <button onClick={() => validar(d, true)} disabled={ocupado === d.carga_id}
                      className="flex items-center gap-1 rounded-lg bg-emerald-700 px-3 py-1.5 font-medium text-white hover:bg-emerald-800 disabled:opacity-50">
                <CheckCircle2 className="h-4 w-4" /> Aceptar
              </button>
              <input id={`nota-${d.carga_id}`} placeholder="Si rechaza: qué falta" className="min-w-[12rem] flex-1 rounded-lg border px-2 py-1.5" />
              <button onClick={() => validar(d, false)} disabled={ocupado === d.carga_id}
                      className="flex items-center gap-1 rounded-lg border border-red-300 px-3 py-1.5 font-medium text-red-700 hover:bg-red-50 disabled:opacity-50">
                <XCircle className="h-4 w-4" /> Rechazar
              </button>
            </div>
          </div>
        ))}
      </CardContent>
    </Card>
  )
}

function Bloque({ numero, titulo, nota, children }: { numero: number; titulo: string; nota?: string; children: React.ReactNode }) {
  return (
    <section className="space-y-3 break-inside-avoid">
      <div className="flex items-baseline gap-3">
        <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-800 text-xs font-bold text-white">{numero}</span>
        <div>
          <h2 className="text-lg font-semibold text-gray-900">{titulo}</h2>
          {nota && <p className="text-xs text-gray-500">{nota}</p>}
        </div>
      </div>
      {children}
    </section>
  )
}

function Kpi({ titulo, valor, sub, delta, deltaTxt, invertir, estado }: {
  titulo: string; valor: string; sub?: string; delta?: number | null; deltaTxt?: string; invertir?: boolean
  estado?: 'ok' | 'alerta' | 'critico'
}) {
  const malo = delta != null && (invertir ? delta > 0.05 : delta < -0.05)
  const bueno = delta != null && (invertir ? delta < -0.05 : delta > 0.05)
  const IconoEstado = estado === 'ok' ? CheckCircle2 : estado ? AlertTriangle : null
  return (
    <div className="rounded-xl border bg-white p-4">
      <p className="flex items-center justify-between gap-2 text-xs font-medium uppercase tracking-wide text-gray-500">
        {titulo}
        {IconoEstado && <IconoEstado aria-label={estado} className={cn('h-4 w-4', estado === 'ok' ? 'text-emerald-600' : estado === 'alerta' ? 'text-amber-600' : 'text-red-600')} />}
      </p>
      <p className="mt-1 text-2xl font-bold tabular-nums text-gray-900">{valor}</p>
      {delta != null && (
        <p className={cn('mt-0.5 flex items-center gap-1 text-xs', malo ? 'text-red-700' : bueno ? 'text-emerald-700' : 'text-gray-500')}>
          {delta >= 0 ? <ArrowUpRight className="h-3.5 w-3.5" /> : <ArrowDownRight className="h-3.5 w-3.5" />}
          {(delta >= 0 ? '+' : '') + Math.round(delta * 100)} % {deltaTxt}
        </p>
      )}
      {sub && <p className="mt-0.5 text-xs text-gray-500">{sub}</p>}
    </div>
  )
}

