'use client'

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Bar, BarChart, CartesianGrid, Legend, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts'
import {
  AlertTriangle, Database, Droplets, Fuel, Package, ShieldCheck, Truck, Wallet,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Modal } from '@/components/ui/modal'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  AREAS_OPERACION, NOMBRE_AREA, getDetalleCostos, getPanelCostos,
  type AreaCosto, type CostoEquipo, type PanelCostos,
} from '@/lib/services/costos-operacion'
import {
  fmtClp, fmtMM, fmtNum, fmtPct, nivelAsignacion, pct, precioLitro, rangoPreset,
  variacionPct, type RangoPreset,
} from '@/lib/costos-operacion'

// ============================================================================
// Costos de Operación (MIG594-595)
// ----------------------------------------------------------------------------
// Salidas de bodega Softland (consumo 07 + EPP 08), copiadas una vez al día.
// Se lee de arriba hacia abajo:
//   1. ¿Le puedo creer?        → calidad del dato y última sincronización
//   2. ¿Cuánto y hacia dónde?  → tarjetas con variación vs período anterior
//   3. ¿Qué reviso hoy?        → excepciones
//   4. ¿De dónde sale?         → equipos, familias, centros de costo, línea
// El petróleo va siempre separado: casi todo cae a un centro de costo genérico
// y, mezclado, tapa el resto del gasto.
// ============================================================================

const COLOR_RESTO = '#2563EB'
const COLOR_PETROLEO = '#F59E0B'

const PRESETS: { id: RangoPreset; label: string }[] = [
  { id: 'mes', label: 'Mes en curso' },
  { id: '3m', label: 'Últimos 3 meses' },
  { id: 'ytd', label: 'Año a la fecha' },
  { id: '12m', label: 'Últimos 12 meses' },
]

const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic']
const fmtMes = (iso: string) => `${MESES[Number(iso.slice(5, 7)) - 1]} ${iso.slice(2, 4)}`

type Detalle = { titulo: string; codiCc?: string; familia?: string }

export default function CostosOperacionPage() {
  useRequireAuth()
  const [preset, setPreset] = useState<RangoPreset>('12m')
  const [conAdmin, setConAdmin] = useState(false)
  const [detalle, setDetalle] = useState<Detalle | null>(null)
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
            <Wallet className="h-6 w-6 text-pillado-green-600" /> Costos de Operación
          </h1>
          <p className="text-sm text-gray-500">
            Salidas de bodega Softland (consumo y EPP) por equipo, faena y familia de producto.
          </p>
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
      {data && <Contenido data={data} onDetalle={setDetalle} />}

      {detalle && (
        <DetalleModal detalle={detalle} desde={rango.desde} hasta={rango.hasta}
                      onClose={() => setDetalle(null)} />
      )}
    </div>
  )
}

function Contenido({ data, onDetalle }: {
  data: PanelCostos; onDetalle: (d: Detalle) => void
}) {
  const k = data.kpi
  const sinPetroleoEquipo = data.por_equipo.reduce((s, e) => s + (e.sin_petroleo ?? 0), 0)
  const pctAsignado = pct(sinPetroleoEquipo, k.sin_petroleo)
  const nivel = nivelAsignacion(pctAsignado)
  const pl = precioLitro(k.petroleo_total, k.petroleo_litros)
  const plAnt = precioLitro(k.petroleo_total_anterior, k.petroleo_litros_anterior)
  const pctPetroleoSinEquipo = pct(k.petroleo_sin_equipo_litros, k.petroleo_litros)
  const sinCc = data.por_cc_no_equipo.find((c) => c.codi_cc === '(SIN CC)')

  const serieMes = data.por_mes
    .filter((m) => m.mes >= data.periodo.desde)
    .map((m) => ({
      mes: fmtMes(m.mes),
      'Repuestos, insumos y EPP': Math.round(m.sin_petroleo ?? 0),
      'Petróleo': Math.round(m.petroleo ?? 0),
      precio: m.litros ? Math.round((m.petroleo ?? 0) / m.litros) : null,
    }))

  // Excepciones: lo que alguien tiene que resolver, con su monto.
  const alzas = data.por_equipo
    .filter((e) => (e.sin_petroleo ?? 0) > 1_000_000)
    .map((e) => ({ e, v: variacionPct(e.total, e.total_anterior) }))
    .filter((x) => x.v != null && x.v > 50)
    .sort((a, b) => b.e.total - a.e.total)
    .slice(0, 5)

  return (
    <>
      {/* 1. Calidad del dato */}
      <Card className={nivel === 'mal' ? 'border-red-300' : nivel === 'atencion' ? 'border-amber-300' : ''}>
        <CardContent className="flex flex-wrap items-center gap-x-6 gap-y-2 p-4 text-sm">
          <span className="flex items-center gap-2 font-medium text-gray-800">
            <ShieldCheck className="h-4 w-4" /> Calidad del dato
          </span>
          <span>
            Gasto (sin petróleo) asignado a un equipo:{' '}
            <b className={nivel === 'mal' ? 'text-red-700' : nivel === 'atencion' ? 'text-amber-700' : 'text-green-700'}>
              {fmtPct(pctAsignado)}
            </b>{' '}
            <span className="text-gray-500">(meta ≥ 90 %)</span>
          </span>
          <span>Líneas con precio 0: <b>{fmtNum(k.lineas_sin_precio)}</b> de {fmtNum(k.lineas)}</span>
          <span className="flex items-center gap-1 text-gray-500">
            <Database className="h-3.5 w-3.5" />
            Softland sincronizado {data.sync.ultima
              ? new Date(data.sync.ultima).toLocaleString('es-CL', { dateStyle: 'short', timeStyle: 'short' })
              : 'nunca'} · último documento {data.sync.max_fecha ?? '—'}
          </span>
          <span className="text-xs text-gray-400">El mes en curso está incompleto.</span>
        </CardContent>
      </Card>

      {/* 2. Tarjetas */}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
        <Tarjeta icon={Wallet} titulo="Gasto total de bodega" valor={fmtMM(k.total)}
                 delta={variacionPct(k.total, k.total_anterior)}
                 nota={`Período anterior ${fmtMM(k.total_anterior)}`} />
        <Tarjeta icon={Package} titulo="Repuestos, insumos y EPP (sin petróleo)" valor={fmtMM(k.sin_petroleo)}
                 delta={variacionPct(k.sin_petroleo, k.sin_petroleo_anterior)}
                 nota={`${fmtNum(k.equipos_con_gasto)} equipos con gasto · EPP ${fmtMM(k.epp)}`} />
        <Tarjeta icon={Fuel} titulo="Petróleo" valor={`${fmtNum(k.petroleo_litros)} L`}
                 delta={variacionPct(k.petroleo_litros, k.petroleo_litros_anterior)}
                 nota={`${fmtMM(k.petroleo_total)} · ${pl ? fmtClp(pl) : '—'}/L`} />
        <Tarjeta icon={Droplets} titulo="Precio del litro" valor={pl ? `${fmtClp(pl)}/L` : '—'}
                 delta={pl && plAnt ? variacionPct(pl, plAnt) : null}
                 nota={`Período anterior ${plAnt ? fmtClp(plAnt) : '—'}/L`} />
        <Tarjeta icon={AlertTriangle} titulo="Petróleo sin equipo asignado" valor={fmtPct(pctPetroleoSinEquipo)}
                 alerta={(pctPetroleoSinEquipo ?? 0) > 20}
                 nota={`${fmtNum(k.petroleo_sin_equipo_litros)} L a centros de costo genéricos o de faena`} />
        <Tarjeta icon={Truck} titulo="Gasto directo a equipos" valor={fmtMM(k.asignado_equipo)}
                 nota={`${fmtPct(pct(k.asignado_equipo, k.total))} del gasto total`} />
      </div>

      {/* 3. Excepciones */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <AlertTriangle className="h-4 w-4 text-amber-600" /> Qué revisar
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm">
          {(pctPetroleoSinEquipo ?? 0) > 20 && (
            <Excepcion onClick={() => onDetalle({ titulo: 'Petróleo (todas las salidas)', familia: 'CLUPETPET' })}>
              <b>{fmtPct(pctPetroleoSinEquipo)}</b> del petróleo ({fmtNum(k.petroleo_sin_equipo_litros)} L) no está
              cargado a ningún equipo. Sin eso no se puede medir el consumo ni el costo por equipo: hay que
              imputarlo por patente (los despachos de SICOM ya lo traen).
            </Excepcion>
          )}
          {pl && plAnt && Math.abs(variacionPct(pl, plAnt) ?? 0) > 10 && (
            <Excepcion>
              El precio del litro pasó de <b>{fmtClp(plAnt)}</b> a <b>{fmtClp(pl)}</b>{' '}
              ({fmtPct(variacionPct(pl, plAnt), true)}). Confirmar con contabilidad si cambió el costo real o
              la forma de valorizar (p. ej. impuesto específico).
            </Excepcion>
          )}
          {k.lineas_sin_precio > 0 && (
            <Excepcion>
              <b>{fmtNum(k.lineas_sin_precio)}</b> líneas salieron de bodega con precio 0: el costo está subvaluado.
            </Excepcion>
          )}
          {sinCc && (
            <Excepcion onClick={() => onDetalle({ titulo: 'Salidas sin centro de costo', codiCc: '(SIN CC)' })}>
              <b>{fmtMM(sinCc.total)}</b> salieron sin centro de costo.
            </Excepcion>
          )}
          {alzas.map(({ e, v }) => (
            <Excepcion key={e.codi_cc}
                       onClick={() => onDetalle({ titulo: etiquetaEquipo(e), codiCc: e.codi_cc })}>
              <b>{etiquetaEquipo(e)}</b> gastó {fmtMM(e.total)}, {fmtPct(v, true)} sobre el período anterior.
            </Excepcion>
          ))}
        </CardContent>
      </Card>

      {/* 4a. Evolución mensual */}
      <div className="grid grid-cols-1 gap-4 xl:grid-cols-3">
        <Card className="xl:col-span-2">
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Gasto mensual de bodega</CardTitle>
          </CardHeader>
          <CardContent>
            <div style={{ width: '100%', height: 300 }}>
              <ResponsiveContainer>
                <BarChart data={serieMes} margin={{ top: 10, right: 10, left: 10, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" vertical={false} />
                  <XAxis dataKey="mes" tick={{ fontSize: 11 }} />
                  <YAxis tick={{ fontSize: 11 }} tickFormatter={(v: number) => `${Math.round(v / 1e6)} M`} />
                  <Tooltip formatter={(v: number, n: string) => [fmtClp(v), n]} cursor={{ fill: '#F3F4F6' }} />
                  <Legend wrapperStyle={{ fontSize: 12 }} />
                  <Bar dataKey="Repuestos, insumos y EPP" stackId="a" fill={COLOR_RESTO}
                       stroke="#fff" strokeWidth={1} />
                  <Bar dataKey="Petróleo" stackId="a" fill={COLOR_PETROLEO} radius={[4, 4, 0, 0]}
                       stroke="#fff" strokeWidth={1} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Precio del petróleo ($/L)</CardTitle>
          </CardHeader>
          <CardContent>
            <div style={{ width: '100%', height: 300 }}>
              <ResponsiveContainer>
                <LineChart data={serieMes} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" vertical={false} />
                  <XAxis dataKey="mes" tick={{ fontSize: 11 }} />
                  <YAxis tick={{ fontSize: 11 }} domain={['auto', 'auto']} />
                  <Tooltip formatter={(v: number) => [`${fmtClp(v)}/L`, 'Precio']} />
                  <Line type="monotone" dataKey="precio" stroke={COLOR_PETROLEO} strokeWidth={2}
                        dot={{ r: 4 }} connectNulls />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* 4b. Dónde se va el gasto */}
      <div className="grid grid-cols-1 gap-4 xl:grid-cols-2">
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-base">Por área</CardTitle></CardHeader>
          <CardContent>
            <Barras filas={data.por_area.map((a) => ({
              label: NOMBRE_AREA[a.area] ?? a.area, valor: a.total, sub: a.sin_petroleo,
            }))} />
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-base">Por faena</CardTitle></CardHeader>
          <CardContent>
            <Barras filas={data.por_zona.slice(0, 12).map((z) => ({
              label: z.zona, valor: z.total, sub: z.sin_petroleo,
            }))} />
          </CardContent>
        </Card>
      </div>

      {/* 4c. Equipos */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <Truck className="h-4 w-4" /> Gasto por equipo
            <span className="text-xs font-normal text-gray-500">— clic en una fila para ver las salidas</span>
          </CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto p-0">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-xs text-gray-600">
              <tr>
                <th className="px-3 py-2 text-left">Equipo</th>
                <th className="px-3 py-2 text-left">Faena actual</th>
                <th className="px-3 py-2 text-right">Repuestos</th>
                <th className="px-3 py-2 text-right">Neumáticos</th>
                <th className="px-3 py-2 text-right">Lubricantes</th>
                <th className="px-3 py-2 text-right">Sin petróleo</th>
                <th className="px-3 py-2 text-right">Petróleo (L)</th>
                <th className="px-3 py-2 text-right">Total</th>
                <th className="px-3 py-2 text-right">vs anterior</th>
              </tr>
            </thead>
            <tbody>
              {data.por_equipo.slice(0, 60).map((e) => {
                const v = variacionPct(e.total, e.total_anterior)
                return (
                  <tr key={e.codi_cc} className="cursor-pointer border-t hover:bg-gray-50"
                      onClick={() => onDetalle({ titulo: etiquetaEquipo(e), codiCc: e.codi_cc })}>
                    <td className="px-3 py-1.5">
                      <div className="font-medium">{e.patente ?? e.codi_cc}</div>
                      <div className="text-xs text-gray-500">{e.descripcion}</div>
                    </td>
                    <td className="px-3 py-1.5 text-xs">{e.faena ?? '—'}</td>
                    <td className="px-3 py-1.5 text-right">{fmtMM(e.repuestos)}</td>
                    <td className="px-3 py-1.5 text-right">{fmtMM(e.neumaticos)}</td>
                    <td className="px-3 py-1.5 text-right">{fmtMM(e.lubricantes)}</td>
                    <td className="px-3 py-1.5 text-right">{fmtMM(e.sin_petroleo)}</td>
                    <td className="px-3 py-1.5 text-right">{fmtNum(e.litros)}</td>
                    <td className="px-3 py-1.5 text-right font-medium">{fmtMM(e.total)}</td>
                    <td className={`px-3 py-1.5 text-right ${v != null && v > 25 ? 'text-red-700' : v != null && v < -25 ? 'text-green-700' : ''}`}>
                      {fmtPct(v, true)}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </CardContent>
      </Card>

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
                      onClick={() => onDetalle({ titulo: f.nombre, familia: f.familia })}>
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
                  <th className="px-3 py-2 text-right">Petróleo (L)</th>
                </tr>
              </thead>
              <tbody>
                {data.por_cc_no_equipo.slice(0, 20).map((c) => (
                  <tr key={c.codi_cc} className="cursor-pointer border-t hover:bg-gray-50"
                      onClick={() => onDetalle({ titulo: c.descripcion ?? c.codi_cc, codiCc: c.codi_cc })}>
                    <td className="px-3 py-1.5">
                      {c.descripcion ?? '—'} <span className="text-xs text-gray-400">{c.codi_cc}</span>
                    </td>
                    <td className="px-3 py-1.5 text-xs">{NOMBRE_AREA[c.area] ?? c.area}</td>
                    <td className="px-3 py-1.5 text-right">{fmtMM(c.total)}</td>
                    <td className="px-3 py-1.5 text-right">{fmtNum(c.litros)}</td>
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

function etiquetaEquipo(e: CostoEquipo) {
  return e.patente ? `${e.patente}${e.tipo_equipo ? ` · ${e.tipo_equipo}` : ''}` : (e.descripcion ?? e.codi_cc)
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

/** Barras horizontales: total del renglón, con la parte sin petróleo marcada. */
function Barras({ filas }: { filas: { label: string; valor: number; sub: number | null }[] }) {
  const max = Math.max(1, ...filas.map((f) => f.valor))
  return (
    <div className="space-y-2">
      {filas.map((f) => (
        <div key={f.label} className="text-sm" title={`${f.label}: ${fmtClp(f.valor)} (sin petróleo ${fmtClp(f.sub)})`}>
          <div className="flex justify-between gap-2">
            <span className="truncate">{f.label}</span>
            <span className="shrink-0 font-medium">{fmtMM(f.valor)}</span>
          </div>
          <div className="mt-0.5 flex h-2 w-full overflow-hidden rounded bg-gray-100">
            <div style={{ width: `${((f.sub ?? 0) / max) * 100}%`, background: COLOR_RESTO }} />
            <div style={{ width: `${((f.valor - (f.sub ?? 0)) / max) * 100}%`, background: COLOR_PETROLEO }}
                 className="border-l-2 border-white" />
          </div>
        </div>
      ))}
      <div className="flex gap-4 pt-1 text-xs text-gray-500">
        <span className="flex items-center gap-1"><i className="inline-block h-2 w-3 rounded" style={{ background: COLOR_RESTO }} /> Repuestos, insumos y EPP</span>
        <span className="flex items-center gap-1"><i className="inline-block h-2 w-3 rounded" style={{ background: COLOR_PETROLEO }} /> Petróleo</span>
      </div>
    </div>
  )
}

function DetalleModal({ detalle, desde, hasta, onClose }: {
  detalle: Detalle; desde: string; hasta: string; onClose: () => void
}) {
  const { data, isLoading, error } = useQuery({
    queryKey: ['costos-operacion-detalle', desde, hasta, detalle.codiCc, detalle.familia],
    queryFn: () => getDetalleCostos({ desde, hasta, codiCc: detalle.codiCc, familia: detalle.familia }),
  })
  const total = (data ?? []).reduce((s, l) => s + l.total, 0)
  return (
    <Modal open onClose={onClose} title={detalle.titulo}
           description={`Salidas de bodega Softland, de mayor a menor (máx. 500) · ${fmtClp(total)}`}
           className="max-w-5xl">
      {isLoading && <div className="flex justify-center py-8"><Spinner /></div>}
      {error && <div className="text-sm text-red-700">{(error as Error).message}</div>}
      {data && (
        <div className="max-h-[65vh] overflow-auto">
          <table className="w-full text-xs">
            <thead className="sticky top-0 bg-gray-50 text-gray-600">
              <tr>
                <th className="px-2 py-1.5 text-left">Fecha</th>
                <th className="px-2 py-1.5 text-left">Folio</th>
                <th className="px-2 py-1.5 text-left">Bodega</th>
                <th className="px-2 py-1.5 text-left">CC</th>
                <th className="px-2 py-1.5 text-left">Producto</th>
                <th className="px-2 py-1.5 text-right">Cant.</th>
                <th className="px-2 py-1.5 text-right">Precio</th>
                <th className="px-2 py-1.5 text-right">Total</th>
                <th className="px-2 py-1.5 text-left">Glosa</th>
              </tr>
            </thead>
            <tbody>
              {data.map((l, i) => (
                <tr key={i} className={`border-t ${l.total === 0 ? 'bg-amber-50' : ''}`}>
                  <td className="px-2 py-1">{l.fecha}</td>
                  <td className="px-2 py-1">{l.folio}{l.concepto === '08' ? ' (EPP)' : ''}</td>
                  <td className="px-2 py-1">{l.bodega}</td>
                  <td className="px-2 py-1">{l.codi_cc}</td>
                  <td className="px-2 py-1">{l.des_prod} <span className="text-gray-400">{l.cod_prod}</span></td>
                  <td className="px-2 py-1 text-right">{fmtNum(l.cantidad)}</td>
                  <td className="px-2 py-1 text-right">{fmtClp(l.precio_unit)}</td>
                  <td className="px-2 py-1 text-right font-medium">{fmtClp(l.total)}</td>
                  <td className="px-2 py-1 text-gray-500">{l.glosa}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Modal>
  )
}
