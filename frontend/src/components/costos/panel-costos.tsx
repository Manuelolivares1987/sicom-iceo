'use client'

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts'
import {
  AlertTriangle, Database, Gauge, HardHat, Package, ShieldCheck, Truck, Wallet,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Modal } from '@/components/ui/modal'
import {
  Barras, COLOR_EQUIPO, COLOR_OTROS, PRESETS, TablaEquiposCosto,
  etiquetaEquipo, fmtFecha, fmtMes, nombreTipo, paretoEquipo,
} from '@/components/costos/comunes'
import { PanelFaenas } from '@/components/costos/panel-faenas'
import { ParetoModal, type PasoPareto } from '@/components/costos/pareto-modal'
import {
  AREAS_OPERACION, NOMBRE_AREA, getPanelCostos,
  type AreaCosto, type CostoEquipo, type PanelCostos,
} from '@/lib/services/costos-operacion'
import {
  HORAS_MINIMAS_CPH, fmtClp, fmtMM, fmtNum, fmtPct, nivelAsignacion, pct, rangoPreset,
  etiquetaRango, variacionPct, vsMediana, type RangoPreset,
} from '@/lib/costos-operacion'

// ============================================================================
// Panel de costos de operación (MIG594-603) — compartido Gerencia / Flota
// ----------------------------------------------------------------------------
// Salidas de bodega Softland (consumo 07 + EPP 08), copiadas una vez al día.
// El petróleo NO está: se compra para revender, es mercadería (MIG598).
// Se lee de arriba hacia abajo:
//   1. ¿Le puedo creer?                → calidad del dato y última sincronización
//   2. ¿Cuánto y cuánto cuesta la hora? → tarjetas
//   3. ¿Qué reviso hoy?                → excepciones (costo por hora fuera de rango…)
//   4. ¿De dónde sale?                 → equipos, familias, centros de costo, línea
// Costo por hora = gasto entre dos lecturas de horómetro creíbles ÷ horas
// entre ellas (MIG599); se compara contra la mediana del mismo tipo.
// ============================================================================



/**
 * Panel completo de costos de operación. Lo usan Gerencia (Costos de
 * Operación) y Flota (Costo por faena y equipo): mismas tarjetas, mismas
 * excepciones, mismo Pareto. `despues` agrega bloques al final (p. ej. la
 * conciliación de ubicación en Flota).
 */
export function PanelCostosOperacion({ titulo, descripcion, despues }: {
  titulo: string; descripcion: string; despues?: React.ReactNode
}) {
  const [preset, setPreset] = useState<RangoPreset>('ytd')
  const [conAdmin, setConAdmin] = useState(false)
  const [pareto, setPareto] = useState<PasoPareto | null>(null)
  const rango = useMemo(() => rangoPreset(preset, new Date()), [preset])
  const areas: AreaCosto[] | null = conAdmin
    ? [...AREAS_OPERACION, 'administracion', 'comercial'] : null

  const { data, isLoading, error } = useQuery({
    queryKey: ['costos-operacion', rango.desde, rango.hasta, conAdmin],
    queryFn: () => getPanelCostos(rango.desde, rango.hasta, areas),
    staleTime: 5 * 60_000,
    retry: (n, err) => err?.name !== 'CostosNoAutorizadoError' && n < 2,
  })

  return (
    <div className="space-y-5 p-4 md:p-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold text-gray-900">
            <Wallet className="h-6 w-6 text-pillado-green-600" /> {titulo}
          </h1>
          <p className="text-sm text-gray-500">{descripcion}</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {PRESETS.map((p) => (
            <Button key={p.id} size="sm" variant={preset === p.id ? 'primary' : 'outline'}
                    onClick={() => setPreset(p.id)}>
              {p.label}
            </Button>
          ))}
          <label className="ml-2 flex items-center gap-1.5 text-sm text-gray-600">
            <input type="checkbox" checked={conAdmin} onChange={(e) => setConAdmin(e.target.checked)} />
            Incluir administración y comercial
          </label>
        </div>
      </div>

      {isLoading && <div className="flex justify-center py-16"><Spinner /></div>}
      {error && (
        <Card><CardContent className="p-6 text-sm text-red-700">{(error as Error).message}</CardContent></Card>
      )}
      {data && <Contenido data={data} onPareto={setPareto} />}
      {despues}

      {pareto && (
        <ParetoModal inicio={pareto} desde={rango.desde} hasta={rango.hasta} conAdmin={conAdmin}
                     onClose={() => setPareto(null)} />
      )}
    </div>
  )
}

function Contenido({ data, onPareto }: {
  data: PanelCostos; onPareto: (p: PasoPareto) => void
}) {
  const k = data.kpi
  // Contra qué se compara: mismos meses del año anterior si el período es un año (MIG604).
  const compara = `vs ${etiquetaRango(data.periodo.anterior_desde, data.periodo.anterior_hasta)}`
  const pctAsignado = pct(k.asignado_equipo, k.total)
  const nivel = nivelAsignacion(pctAsignado)

  const serieMes = data.por_mes
    .filter((m) => m.mes >= data.periodo.desde)
    .map((m) => ({
      mesIso: m.mes,
      mes: fmtMes(m.mes),
      'Cargado a un equipo': Math.round(m.asignado_equipo ?? 0),
      'Otros centros de costo': Math.round(m.total - (m.asignado_equipo ?? 0)),
    }))

  // Excepciones: lo que alguien tiene que resolver.
  const caros = data.por_equipo
    .map((e) => ({ e, r: vsMediana(e.costo_hora, e.mediana_tipo, e.horas, e.n_tipo) }))
    .filter((x) => x.r != null && x.r >= 1.5)
    .sort((a, b) => (b.r ?? 0) - (a.r ?? 0))
    .slice(0, 6)
  const alzas = data.por_equipo
    .filter((e) => e.total > 1_000_000)
    .map((e) => ({ e, v: variacionPct(e.total, e.total_anterior) }))
    .filter((x) => x.v != null && x.v > 50)
    .sort((a, b) => b.e.total - a.e.total)
    .slice(0, 5)

  const conCph = data.por_equipo.filter((e) => e.costo_hora != null).length

  return (
    <>
      {/* 1. Calidad del dato */}
      <Card className={nivel === 'mal' ? 'border-red-300' : nivel === 'atencion' ? 'border-amber-300' : ''}>
        <CardContent className="flex flex-wrap items-center gap-x-6 gap-y-2 p-4 text-sm">
          <span className="rounded bg-gray-100 px-2 py-0.5 font-medium text-gray-800">
            Período: {etiquetaRango(data.periodo.desde, data.periodo.hasta)} · comparado {compara}
          </span>
          <span className="flex items-center gap-2 font-medium text-gray-800">
            <ShieldCheck className="h-4 w-4" /> Calidad del dato
          </span>
          <span>
            Gasto cargado a un equipo:{' '}
            <b className={nivel === 'mal' ? 'text-red-700' : nivel === 'atencion' ? 'text-amber-700' : 'text-green-700'}>
              {fmtPct(pctAsignado)}
            </b>{' '}
            <span className="text-gray-500">(meta ≥ 90 %)</span>
          </span>
          <span>Equipos con costo por hora: <b>{conCph}</b> de {fmtNum(k.equipos_con_gasto)}</span>
          <span>Líneas con precio 0: <b>{fmtNum(k.lineas_sin_precio)}</b></span>
          <span className="flex items-center gap-1 text-gray-500">
            <Database className="h-3.5 w-3.5" />
            Softland {data.sync.ultima
              ? new Date(data.sync.ultima).toLocaleString('es-CL', { dateStyle: 'short', timeStyle: 'short' })
              : 'nunca'} · último documento {data.sync.max_fecha ?? '—'}
          </span>
          <span className="text-xs text-gray-400">Sin petróleo (se revende). El mes en curso está incompleto.</span>
        </CardContent>
      </Card>

      {/* 2. Tarjetas */}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
        <Tarjeta icon={Wallet} titulo="Gasto de operación" valor={fmtMM(k.total)}
                 delta={variacionPct(k.total, k.total_anterior)}
                 nota={`${compara}: ${fmtMM(k.total_anterior)}`} />
        <Tarjeta icon={Truck} titulo="Cargado a equipos" valor={fmtMM(k.asignado_equipo)}
                 delta={variacionPct(k.asignado_equipo, k.asignado_equipo_anterior)}
                 nota={`${fmtNum(k.equipos_con_gasto)} equipos con gasto · ${compara}: ${fmtMM(k.asignado_equipo_anterior)}`} />
        <Tarjeta icon={Gauge} titulo="Costo por hora operada (flota)"
                 valor={k.flota_costo_hora != null ? `${fmtClp(k.flota_costo_hora)}/h` : '—'}
                 nota={`${fmtNum(k.equipos_medidos)} equipos · ${fmtNum(k.flota_horas)} h medidas · ventana típica ${fmtNum(k.dias_medidos_mediana)} días`} />
        <Tarjeta icon={Package} titulo="Neumáticos" valor={fmtMM(k.neumaticos)}
                 nota={`${fmtPct(pct(k.neumaticos, k.total))} del gasto`} />
        <Tarjeta icon={HardHat} titulo="EPP entregado a personas" valor={fmtMM(k.epp)}
                 nota="Concepto 08 de Softland" />
        <Tarjeta icon={AlertTriangle} titulo="Sin centro de costo" valor={fmtMM(k.sin_cc)}
                 alerta={k.sin_cc > 0} nota="Salidas que no se pueden cargar a nadie" />
      </div>

      {/* 3. Excepciones */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <AlertTriangle className="h-4 w-4 text-amber-600" /> Qué revisar
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm">
          {caros.map(({ e, r }) => (
            <Excepcion key={`c-${e.codi_cc}`}
                       onClick={() => onPareto(paretoEquipo(e))}>
              <b>{etiquetaEquipo(e)}</b> cuesta <b>{fmtClp(e.costo_hora)}/h</b>,{' '}
              {(r ?? 0).toLocaleString('es-CL', { maximumFractionDigits: 1 })} veces la mediana de{' '}
              {nombreTipo(e.tipo_equipo)} ({fmtClp(e.mediana_tipo)}/h) · {fmtNum(e.horas)} h entre{' '}
              {fmtFecha(e.medido_desde)} y {fmtFecha(e.medido_hasta)}.
            </Excepcion>
          ))}
          {k.lineas_sin_precio > 0 && (
            <Excepcion>
              <b>{fmtNum(k.lineas_sin_precio)}</b> líneas salieron de bodega con precio 0: el costo está subvaluado.
            </Excepcion>
          )}
          {k.sin_cc > 0 && (
            <Excepcion onClick={() => onPareto({ titulo: 'Sin centro de costo', filtros: { codi_cc: '(SIN CC)' }, dimension: 'producto' })}>
              <b>{fmtMM(k.sin_cc)}</b> salieron sin centro de costo.
            </Excepcion>
          )}
          {alzas.map(({ e, v }) => (
            <Excepcion key={`a-${e.codi_cc}`}
                       onClick={() => onPareto(paretoEquipo(e))}>
              <b>{etiquetaEquipo(e)}</b> gastó {fmtMM(e.total)}, {fmtPct(v, true)} sobre el período anterior.
            </Excepcion>
          ))}
          {caros.length === 0 && alzas.length === 0 && k.lineas_sin_precio === 0 && k.sin_cc === 0 && (
            <div className="text-gray-500">Nada fuera de rango en este período.</div>
          )}
        </CardContent>
      </Card>

      {/* 4a. Evolución mensual + costo por hora por tipo */}
      <div className="grid grid-cols-1 gap-4 xl:grid-cols-3">
        <Card className="xl:col-span-2">
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Gasto mensual de bodega</CardTitle>
          </CardHeader>
          <CardContent>
            <div style={{ width: '100%', height: 300 }}>
              <ResponsiveContainer>
                <BarChart data={serieMes} margin={{ top: 10, right: 10, left: 10, bottom: 0 }} className="cursor-pointer"
                          onClick={(st: { activePayload?: { payload: { mesIso: string; mes: string } }[] }) => {
                            const p = st?.activePayload?.[0]?.payload
                            if (p) onPareto({ titulo: p.mes, filtros: { mes: p.mesIso }, dimension: 'faena' })
                          }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" vertical={false} />
                  <XAxis dataKey="mes" tick={{ fontSize: 11 }} />
                  <YAxis tick={{ fontSize: 11 }} tickFormatter={(v: number) => `${Math.round(v / 1e6)} M`} />
                  <Tooltip formatter={(v: number, n: string) => [fmtClp(v), n]} cursor={{ fill: '#F3F4F6' }} />
                  <Legend wrapperStyle={{ fontSize: 12 }} />
                  <Bar dataKey="Cargado a un equipo" stackId="a" fill={COLOR_EQUIPO} stroke="#fff" strokeWidth={1} />
                  <Bar dataKey="Otros centros de costo" stackId="a" fill={COLOR_OTROS} radius={[4, 4, 0, 0]}
                       stroke="#fff" strokeWidth={1} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Costo por hora — mediana por tipo</CardTitle>
          </CardHeader>
          <CardContent>
            <Barras filas={data.costo_hora_tipo.map((t) => ({
              label: `${nombreTipo(t.tipo_equipo)} (${t.n})`, valor: t.mediana, clave: t.tipo_equipo,
            }))} formato={(v) => `${fmtClp(v)}/h`}
                    onClick={(f) => onPareto({ titulo: nombreTipo(f.clave ?? null), filtros: { tipo_equipo: f.clave }, dimension: 'equipo' })} />
            <p className="mt-3 text-xs text-gray-400">
              Solo equipos con al menos {HORAS_MINIMAS_CPH} h medidas. Entre paréntesis, cuántos equipos.
            </p>
          </CardContent>
        </Card>
      </div>

      {/* 4b. Dónde se va el gasto */}
      <PanelFaenas desde={data.periodo.desde} hasta={data.periodo.hasta} onPareto={onPareto} />

      <Card>
        <CardHeader className="pb-2"><CardTitle className="text-base">Por área</CardTitle></CardHeader>
        <CardContent>
          <Barras filas={data.por_area.map((a) => ({ label: NOMBRE_AREA[a.area] ?? a.area, valor: a.total, clave: a.area }))}
                  formato={fmtMM}
                  onClick={(f) => onPareto({ titulo: f.label, filtros: { area: f.clave }, dimension: 'centro_costo' })} />
        </CardContent>
      </Card>

      <TablaEquiposCosto equipos={data.por_equipo} onPareto={onPareto} />

      {/* 4d. Familias y centros de costo sin equipo */}
      <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-base">Por familia de producto</CardTitle></CardHeader>
          <CardContent className="overflow-x-auto p-0">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-xs text-gray-600">
                <tr>
                  <th className="px-3 py-2 text-left">Familia</th>
                  <th className="px-3 py-2 text-right">Total</th>
                  <th className="px-3 py-2 text-right">% del gasto</th>
                  <th className="px-3 py-2 text-right">vs anterior</th>
                </tr>
              </thead>
              <tbody>
                {data.por_familia.slice(0, 20).map((f) => (
                  <tr key={f.familia} className="cursor-pointer border-t hover:bg-gray-50"
                      onClick={() => onPareto({ titulo: f.nombre, filtros: { familia: f.familia }, dimension: 'equipo' })}>
                    <td className="px-3 py-1.5">
                      {f.nombre} <span className="text-xs text-gray-400">{f.familia}</span>
                    </td>
                    <td className="px-3 py-1.5 text-right">{fmtMM(f.total)}</td>
                    <td className="px-3 py-1.5 text-right">{fmtPct(pct(f.total, k.total))}</td>
                    <td className="px-3 py-1.5 text-right">{fmtPct(variacionPct(f.total, f.total_anterior), true)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Centros de costo que no son un equipo</CardTitle>
          </CardHeader>
          <CardContent className="overflow-x-auto p-0">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-xs text-gray-600">
                <tr>
                  <th className="px-3 py-2 text-left">Centro de costo</th>
                  <th className="px-3 py-2 text-left">Área</th>
                  <th className="px-3 py-2 text-right">Total</th>
                </tr>
              </thead>
              <tbody>
                {data.por_cc_no_equipo.slice(0, 20).map((c) => (
                  <tr key={c.codi_cc} className="cursor-pointer border-t hover:bg-gray-50"
                      onClick={() => onPareto({ titulo: c.descripcion ?? c.codi_cc, filtros: { codi_cc: c.codi_cc }, dimension: 'familia' })}>
                    <td className="px-3 py-1.5">
                      {c.descripcion ?? '—'} <span className="text-xs text-gray-400">{c.codi_cc}</span>
                    </td>
                    <td className="px-3 py-1.5 text-xs">{NOMBRE_AREA[c.area] ?? c.area}</td>
                    <td className="px-3 py-1.5 text-right">{fmtMM(c.total)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </CardContent>
        </Card>
      </div>
    </>
  )
}

function Tarjeta({ icon: Icon, titulo, valor, delta, nota, alerta }: {
  icon: typeof Wallet; titulo: string; valor: string; delta?: number | null; nota?: string; alerta?: boolean
}) {
  return (
    <Card className={alerta ? 'border-amber-300' : ''}>
      <CardContent className="p-4">
        <div className="flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-gray-500">
          <Icon className="h-4 w-4" /> {titulo}
        </div>
        <div className="mt-1 flex items-baseline gap-2">
          <span className="text-2xl font-bold text-gray-900">{valor}</span>
          {delta != null && (
            // Más gasto = peor: sube en rojo, baja en verde.
            <span className={`text-sm font-medium ${delta > 0 ? 'text-red-700' : 'text-green-700'}`}>
              {delta > 0 ? '▲' : '▼'} {fmtPct(Math.abs(delta))}
            </span>
          )}
        </div>
        {nota && <div className="mt-1 text-xs text-gray-500">{nota}</div>}
      </CardContent>
    </Card>
  )
}

function Excepcion({ children, onClick }: { children: React.ReactNode; onClick?: () => void }) {
  return (
    <div className={`flex items-start gap-2 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 ${onClick ? 'cursor-pointer hover:bg-amber-100' : ''}`}
         onClick={onClick}>
      <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />
      <div>{children}</div>
    </div>
  )
}

