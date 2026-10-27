'use client'

// Avance del período (MIG590): tarjetas real / plan / proyectado, curva S y
// tabla por faena con el KPI proyectado de cada mes y su tramo de multa.

import { useMemo, useState } from 'react'
import {
  ResponsiveContainer, LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ReferenceLine,
} from 'recharts'
import { AlertTriangle, TrendingUp, TrendingDown, Table2, LineChart as LineIcon } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useToast } from '@/contexts/toast-context'
import { MESES, guardarUniversoFaena, type EnexFaena, type EnexPanelRow } from '@/lib/services/enex'
import {
  calcularAvance, curvaS, tramoMulta, ultimoDiaMes, avanceContrato, CATEGORIA_TXT,
  type Avance, type Ventana, type UniversoContrato,
} from '@/lib/enex-avance'

const fmt = (n: number | null | undefined) => (n == null ? '—' : `${n.toLocaleString('es-CL', { maximumFractionDigits: 1 })}%`)

function colorPct(p: number | null): string {
  if (p == null) return 'text-gray-400'
  if (p >= 96) return 'text-green-700'
  if (p >= 90) return 'text-amber-700'
  return 'text-red-700'
}

function Tarjeta({ titulo, valor, sub, ayuda, tono }: { titulo: string; valor: string; sub?: string; ayuda: string; tono?: string }) {
  return (
    <div className="rounded-xl border border-gray-200 bg-white p-3" title={ayuda}>
      <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-500">{titulo}</div>
      <div className={`mt-0.5 text-2xl font-bold tabular-nums ${tono ?? 'text-gray-900'}`}>{valor}</div>
      {sub && <div className="text-[11px] text-gray-500">{sub}</div>}
    </div>
  )
}

export function TarjetasAvance({ a }: { a: Avance }) {
  const atrasoTono = a.desviacion == null ? 'text-gray-900' : a.desviacion >= 0 ? 'text-green-700' : a.desviacion >= -10 ? 'text-amber-700' : 'text-red-700'
  return (
    <div className="grid grid-cols-2 gap-2 md:grid-cols-3 xl:grid-cols-6">
      <Tarjeta titulo="Plan a la fecha" valor={fmt(a.pctPlanHoy)} sub={`${a.planHoy} de ${a.total} servicios ya debían hacerse`}
               ayuda="Porcentaje de los servicios del período cuya fecha planificada ya llegó." />
      <Tarjeta titulo="Ejecutado" valor={fmt(a.pctEjecutado)} sub={`${a.ejecutadas} hechos en terreno · ${a.sinFirma} sin firma`}
               ayuda="Avance físico: servicios hechos en terreno, firmados o no por el mandante." />
      <Tarjeta titulo="Real (KPI)" valor={fmt(a.pctReal)} sub={`${a.cumplidas} cumplidos con firma del mandante`} tono={colorPct(a.pctReal)}
               ayuda="Lo que vale para el contrato: cumplido con firma del mandante, sobre el total del período." />
      <Tarjeta titulo="Desviación" valor={a.desviacion == null ? '—' : `${a.desviacion > 0 ? '+' : ''}${a.desviacion.toLocaleString('es-CL')} pts`}
               sub={a.spi == null ? 'aún no hay plan vencido' : `SPI ${a.spi.toLocaleString('es-CL')} · ${a.atrasadas} atrasados`} tono={atrasoTono}
               ayuda="Ejecutado menos plan a la fecha. SPI = ejecutado ÷ plan a la fecha (1 = al día)." />
      <Tarjeta titulo="Proyectado según plan" valor={fmt(a.pctProyectadoPlan)} tono={colorPct(a.pctProyectadoPlan)}
               sub={a.atrasadas + a.noRealizadas > 0 ? `${a.atrasadas + a.noRealizadas} sin reprogramar no suman` : 'si lo pendiente se hace en su día'}
               ayuda="Cierre del período si todo lo pendiente con fecha futura se ejecuta en su día. Lo atrasado y lo no realizado no suman hasta reprogramarlo." />
      <Tarjeta titulo="Proyectado según ritmo" valor={fmt(a.pctProyectadoRitmo)} tono={colorPct(a.pctProyectadoRitmo)}
               sub="si se sigue al ritmo actual"
               ayuda="Cierre del período si se mantiene el ritmo de hoy (SPI × 100)." />
    </div>
  )
}

export function CurvaSEnex({ rows, ventana, hoy, height = 260 }: { rows: EnexPanelRow[]; ventana: Ventana; hoy: string; height?: number }) {
  const [tabla, setTabla] = useState(false)
  const data = useMemo(() => curvaS(rows, ventana.desde, ventana.hasta, hoy), [rows, ventana, hoy])
  if (data.length === 0) {
    return <div className="rounded-lg border border-dashed border-gray-200 p-6 text-center text-sm text-gray-400">Sin servicios programados en el período.</div>
  }
  // Tabla semanal (vista accesible de la curva): el último día de cada semana.
  const semanal = data.filter((p, i) => fechaDow(p.fecha) === 0 || i === data.length - 1)
  const hoyEnVentana = hoy >= ventana.desde && hoy <= ventana.hasta
  return (
    <div>
      <div className="mb-1 flex items-center justify-between">
        <h3 className="text-sm font-semibold text-gray-800">Curva S del período · % acumulado de servicios</h3>
        <button onClick={() => setTabla((t) => !t)} className="flex items-center gap-1 rounded border px-2 py-0.5 text-[11px] text-gray-600 hover:bg-gray-50">
          {tabla ? <><LineIcon className="h-3 w-3" /> Ver gráfico</> : <><Table2 className="h-3 w-3" /> Ver tabla</>}
        </button>
      </div>
      {tabla ? (
        <div className="max-h-[260px] overflow-auto">
          <table className="w-full text-xs">
            <thead className="sticky top-0 bg-white"><tr className="border-b text-gray-500">
              <th className="p-1 text-left">Semana al</th><th className="p-1 text-right">Plan</th><th className="p-1 text-right">Real</th><th className="p-1 text-right">Proyectado</th>
            </tr></thead>
            <tbody>
              {semanal.map((p) => (
                <tr key={p.fecha} className="border-b">
                  <td className="p-1">{p.fecha.slice(8, 10)}/{p.fecha.slice(5, 7)}</td>
                  <td className="p-1 text-right tabular-nums">{fmt(p.plan)}</td>
                  <td className="p-1 text-right tabular-nums">{fmt(p.real)}</td>
                  <td className="p-1 text-right tabular-nums">{fmt(p.proyectado)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <div style={{ width: '100%', height }}>
          <ResponsiveContainer>
            <LineChart data={data} margin={{ top: 8, right: 16, left: 0, bottom: 4 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#eef0f3" vertical={false} />
              <XAxis dataKey="fecha" tick={{ fontSize: 11, fill: '#6b7280' }} interval={13}
                     tickFormatter={(v: string) => `${v.slice(8, 10)}/${v.slice(5, 7)}`} />
              <YAxis domain={[0, 100]} tick={{ fontSize: 11, fill: '#6b7280' }} tickFormatter={(v) => `${v}%`} width={40} />
              <Tooltip
                formatter={(v: number, name: string) => [v == null ? '—' : `${v.toFixed(1)}%`, name]}
                labelFormatter={(l: string) => `${l.slice(8, 10)}/${l.slice(5, 7)}/${l.slice(0, 4)}`} />
              <Legend wrapperStyle={{ fontSize: 12 }} />
              {hoyEnVentana && <ReferenceLine x={hoy} stroke="#9ca3af" strokeDasharray="2 2" label={{ value: 'hoy', fontSize: 10, fill: '#6b7280', position: 'top' }} />}
              <Line type="stepAfter" dataKey="plan" name="Plan" stroke="#6366f1" strokeWidth={2} strokeDasharray="5 4" dot={false} />
              <Line type="stepAfter" dataKey="real" name="Real (ejecutado)" stroke="#16a34a" strokeWidth={2.5} dot={false} connectNulls={false} />
              <Line type="stepAfter" dataKey="proyectado" name="Proyectado" stroke="#c2410c" strokeWidth={2} strokeDasharray="1 4" strokeLinecap="round" dot={false} connectNulls={false} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      )}
    </div>
  )
}

const fechaDow = (iso: string) => { const [y, m, d] = iso.split('-').map(Number); return new Date(y, m - 1, d).getDay() }

/** Por faena: avance del período y KPI proyectado de cada mes (con su tramo de multa). */
export function TablaFaenas({ rows, faenas, ventana, hoy, onElegir }: {
  rows: EnexPanelRow[]; faenas: EnexFaena[]; ventana: Ventana; hoy: string; onElegir?: (faenaId: string) => void
}) {
  const filas = useMemo(() => faenas.map((f) => {
    const rf = rows.filter((r) => r.faena_id === f.id)
    const meses = ventana.meses.map((m) => {
      const rm = rf.filter((r) => r.periodo_anio === m.anio && r.periodo_mes === m.mes)
      const a = calcularAvance(rm, hoy)
      // KPI del contrato proyectado: cumplidas + lo que aún puede cumplirse a tiempo.
      const proy = a.total > 0 ? Math.round(((a.cumplidas + a.sinFirma + a.futuras) / a.total) * 1000) / 10 : null
      const cerrado = ultimoDiaMes(m.anio, m.mes) < hoy
      return { ...m, a, proy: cerrado ? a.pctReal : proy, cerrado }
    })
    return { f, a: calcularAvance(rf, hoy), meses }
  }).filter((x) => x.a.total > 0), [rows, faenas, ventana, hoy])

  if (filas.length === 0) return null
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b text-[11px] uppercase tracking-wide text-gray-500">
            <th className="p-2 text-left">Faena</th>
            <th className="p-2 text-right">Servicios</th>
            <th className="p-2 text-right">Plan a la fecha</th>
            <th className="p-2 text-right">Ejecutado</th>
            <th className="p-2 text-right">Real (KPI)</th>
            <th className="p-2 text-right">Proyectado</th>
            <th className="p-2 text-right">Atrasados</th>
            {ventana.meses.map((m) => (
              <th key={`${m.anio}-${m.mes}`} className="p-2 text-center">KPI {MESES[m.mes - 1].slice(0, 3)}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {filas.map(({ f, a, meses }) => (
            <tr key={f.id} className="border-b hover:bg-gray-50/60">
              <td className="p-2">
                <button className="text-left font-medium text-gray-800 hover:underline" onClick={() => onElegir?.(f.id)}>{f.nombre}</button>
              </td>
              <td className="p-2 text-right tabular-nums">{a.total}</td>
              <td className="p-2 text-right tabular-nums">{fmt(a.pctPlanHoy)}</td>
              <td className="p-2 text-right tabular-nums">
                {fmt(a.pctEjecutado)}
                {a.desviacion != null && a.desviacion !== 0 && (
                  a.desviacion > 0
                    ? <TrendingUp className="ml-1 inline h-3.5 w-3.5 text-green-600" aria-label="adelantado" />
                    : <TrendingDown className="ml-1 inline h-3.5 w-3.5 text-red-600" aria-label="atrasado" />
                )}
              </td>
              <td className={`p-2 text-right font-semibold tabular-nums ${colorPct(a.pctReal)}`}>{fmt(a.pctReal)}</td>
              <td className={`p-2 text-right tabular-nums ${colorPct(a.pctProyectadoPlan)}`}>{fmt(a.pctProyectadoPlan)}</td>
              <td className="p-2 text-right tabular-nums">
                {a.atrasadas > 0 ? <span className="inline-flex items-center gap-1 text-red-700"><AlertTriangle className="h-3.5 w-3.5" />{a.atrasadas}</span> : '0'}
              </td>
              {meses.map((m) => {
                const t = tramoMulta(m.proy)
                return (
                  <td key={`${m.anio}-${m.mes}`} className="p-2 text-center">
                    {m.a.total === 0 ? <span className="text-gray-300">—</span> : (
                      <div title={m.cerrado ? 'Mes cerrado: cumplimiento real' : 'Proyección: cumplido + lo que aún puede cumplirse a tiempo'}>
                        <div className={`font-semibold tabular-nums ${colorPct(m.proy)}`}>{fmt(m.proy)}{!m.cerrado && <span className="ml-0.5 text-[9px] font-normal text-gray-400">proy.</span>}</div>
                        {t.pct > 0 && (
                          <div className={`mt-0.5 inline-block rounded px-1 text-[10px] font-semibold ${t.revision ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-800'}`}>{t.etiqueta}</div>
                        )}
                      </div>
                    )}
                  </td>
                )
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

// ── [MIG658] Avance por contrato: contra el universo del contrato ──────────
/** % de avance del trimestre de cada contrato medido contra lo que el contrato exige, no contra lo cargado en SICOM. */
export function TablaContratos({ rows, faenas, mundo, puedeEditar, onCambio }: {
  rows: EnexPanelRow[]; faenas: EnexFaena[]; mundo: 'todos' | 'combustible' | 'lubricante'
  puedeEditar: boolean; onCambio: () => void
}) {
  const [editar, setEditar] = useState<EnexFaena | null>(null)
  const filas = useMemo(() => faenas.map((f) => {
    const definido = f.contrato_inst_combustible != null || f.contrato_inst_lubricante != null || f.contrato_camiones != null
    const u: UniversoContrato = definido ? {
      combustible: mundo === 'lubricante' ? 0 : f.contrato_inst_combustible ?? 0,
      lubricante: mundo === 'combustible' ? 0 : f.contrato_inst_lubricante ?? 0,
      camiones: mundo === 'lubricante' ? 0 : f.contrato_camiones ?? 0,
    } : { combustible: null, lubricante: null, camiones: null }
    return { f, definido, c: avanceContrato(rows.filter((r) => r.faena_id === f.id), u) }
  }), [rows, faenas, mundo])

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b text-[11px] uppercase tracking-wide text-gray-500">
            <th className="p-2 text-left">Contrato</th>
            <th className="p-2 text-right" title="Tareas que el contrato exige en el trimestre">Universo</th>
            <th className="p-2 text-right">Programado</th>
            <th className="p-2 text-right">Por programar</th>
            <th className="p-2 text-right">Ejecutado</th>
            <th className="p-2 text-right">Firmado</th>
            <th className="p-2 text-right" title="Cambiadas por ESM con correo del ADC: fuera del KPI">Justif. ADC</th>
            <th className="p-2 text-left">% avance del contrato</th>
            <th className="p-2 text-right" title="Firmado ÷ programado vigente">KPI</th>
          </tr>
        </thead>
        <tbody>
          {filas.map(({ f, definido, c }) => {
            const t = tramoMulta(c.pctKpi)
            return (
              <tr key={f.id} className="border-b align-top hover:bg-gray-50/60">
                <td className="p-2">
                  <div className="font-medium text-gray-800">{f.nombre}</div>
                  {definido ? (
                    <div className="text-[10px] text-gray-500">
                      {c.categorias.map((k) => `${CATEGORIA_TXT[k.cat]} ${k.programadas}/${k.universo}`).join(' · ')}
                    </div>
                  ) : <div className="max-w-xs text-[10px] text-gray-400">{f.contrato_universo_nota ?? 'Universo sin definir'}</div>}
                  {puedeEditar && <button onClick={() => setEditar(f)} className="text-[10px] text-blue-600 hover:underline">editar universo</button>}
                </td>
                <td className="p-2 text-right tabular-nums">{c.universo ?? '—'}</td>
                <td className="p-2 text-right tabular-nums">{c.programadas}</td>
                <td className="p-2 text-right tabular-nums">
                  {c.porProgramar > 0 ? <span className="font-semibold text-red-700">{c.porProgramar}</span> : definido ? '0' : '—'}
                </td>
                <td className="p-2 text-right tabular-nums">{c.ejecutadas}</td>
                <td className="p-2 text-right tabular-nums">{c.cumplidas}</td>
                <td className="p-2 text-right tabular-nums">
                  {c.justificadas}
                  {c.pendientesAdc > 0 && <div className="text-[10px] text-violet-700">{c.pendientesAdc} esperan correo</div>}
                </td>
                <td className="p-2">
                  {c.pctAvance == null ? <span className="text-gray-300">—</span> : (
                    <div className="flex items-center gap-2">
                      <div className="h-2 w-28 overflow-hidden rounded bg-gray-200" role="img" aria-label={`Avance ${fmt(c.pctAvance)}`}>
                        <div className="h-full bg-blue-600" style={{ width: `${Math.min(100, c.pctAvance)}%` }} />
                      </div>
                      <span className="font-semibold tabular-nums">{fmt(c.pctAvance)}</span>
                    </div>
                  )}
                </td>
                <td className="p-2 text-right">
                  <div className={`font-semibold tabular-nums ${colorPct(c.pctKpi)}`}>{fmt(c.pctKpi)}</div>
                  {t.pct > 0 && <div className={`mt-0.5 inline-block rounded px-1 text-[10px] font-semibold ${t.revision ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-800'}`}>{t.etiqueta}</div>}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
      {editar && <UniversoModal faena={editar} onClose={() => setEditar(null)} onDone={() => { setEditar(null); onCambio() }} />}
    </div>
  )
}

function UniversoModal({ faena, onClose, onDone }: { faena: EnexFaena; onClose: () => void; onDone: () => void }) {
  const toast = useToast()
  const [v, setV] = useState({
    combustible: faena.contrato_inst_combustible ?? null, lubricante: faena.contrato_inst_lubricante ?? null, camiones: faena.contrato_camiones ?? null,
  })
  const [busy, setBusy] = useState(false)
  const num = (s: string) => (s === '' ? null : Math.max(0, Math.floor(Number(s))))
  async function guardar() {
    setBusy(true)
    try { await guardarUniversoFaena(faena.id, v); toast.success('Universo guardado'); onDone() }
    catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }
  const tareas = (v.combustible ?? 0) * 2 + (v.lubricante ?? 0) + (v.camiones ?? 0)
  const campos = [['combustible', 'Inst. combustible', 'mant. + calib.'], ['lubricante', 'Truck shop', 'mantención'], ['camiones', 'Camiones', 'calibración']] as const
  return (
    <Modal open onClose={onClose} title={`Universo del contrato · ${faena.nombre}`}>
      <div className="space-y-3">
        {faena.contrato_universo_nota && <p className="text-xs text-gray-500">{faena.contrato_universo_nota}</p>}
        <div className="grid grid-cols-3 gap-2">
          {campos.map(([k, l, s]) => (
            <div key={k}>
              <label className="text-xs font-medium">{l}</label>
              <Input type="number" min={0} value={v[k] ?? ''} onChange={(e) => setV((p) => ({ ...p, [k]: num(e.target.value) }))} />
              <p className="text-[10px] text-gray-500">{s}</p>
            </div>
          ))}
        </div>
        <p className="text-sm">Tareas por trimestre: <b>{tareas}</b></p>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button disabled={busy} onClick={guardar}>Guardar</Button>
      </ModalFooter>
    </Modal>
  )
}

