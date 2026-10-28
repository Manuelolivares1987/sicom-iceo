'use client'

// Gráficos de la tendencia mes a mes (ver lib/combustible-tendencia).
// Un gráfico por medida (nunca dos ejes); el mes elegido va en azul fuerte.

import { useState } from 'react'
import {
  Bar, BarChart, CartesianGrid, Cell, Line, LineChart, Rectangle, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts'
import { cn } from '@/lib/utils'
import type { Celda, FilaCalor, PuntoFlota } from '@/lib/combustible-tendencia'

const MES_CORTO = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic']
const MES_LARGO = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']
export const etiquetaMes = (iso: string) => {
  const [y, m] = iso.split('-').map(Number)
  return m === 1 || m === 12 ? `${MES_CORTO[m - 1]} ${String(y).slice(2)}` : MES_CORTO[m - 1]
}
export const nombreMes = (iso: string) => {
  const [y, m] = iso.split('-').map(Number)
  return `${MES_LARGO[m - 1]} ${y}`
}
const n0 = (n: number | null | undefined) => (n == null ? '—' : Math.round(n).toLocaleString('es-CL'))
const n1 = (n: number | null | undefined) => (n == null ? '—' : n.toLocaleString('es-CL', { maximumFractionDigits: 1 }))
const pct = (x: number) => `${x > 0 ? '+' : ''}${Math.round(x * 100)} %`

const AZUL = '#2563eb', AZUL_SUAVE = '#93c5fd', GRILLA = '#e5e7eb', EJE = '#6b7280'
const ejeX = { tick: { fontSize: 11, fill: EJE }, tickLine: false, axisLine: { stroke: GRILLA } }
const ejeY = { tick: { fontSize: 11, fill: EJE }, tickLine: false, axisLine: false, width: 48 }

function Caja({ children }: { children: React.ReactNode }) {
  return <div className="rounded-lg border bg-white px-3 py-2 text-xs text-gray-700 shadow-md">{children}</div>
}

type Dato = PuntoFlota & { etiqueta: string; falta: number }

function TipLitros({ active, payload }: { active?: boolean; payload?: { payload: Dato }[] }) {
  if (!active || !payload?.length) return null
  const p = payload[0].payload
  return (
    <Caja>
      <p className="mb-1 font-semibold capitalize text-gray-900">{nombreMes(p.mes)}</p>
      <p>{n0(p.litros)} L cargados{p.parcial && <> · <b>≈ {n0(p.litrosProy)} L</b> al cierre</>}</p>
      <p>${n0(p.monto)} · ${n0(p.precioL)}/L</p>
      <p>{p.cargas} cargas · {p.vehiculos} vehículos</p>
      {p.incompleto && <p className="mt-1 text-gray-500">El historial parte a medias este mes: no se usa para comparar.</p>}
    </Caja>
  )
}

export function GraficoLitros({ serie, mes, onElegir }: { serie: PuntoFlota[]; mes: string; onElegir: (m: string) => void }) {
  const datos: Dato[] = serie.map((p) => ({ ...p, etiqueta: etiquetaMes(p.mes), falta: Math.max(p.litrosProy - p.litros, 0) }))
  return (
    <div>
      <div className="h-56">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={datos} margin={{ top: 8, right: 8, left: 0, bottom: 0 }} barCategoryGap="22%">
            <CartesianGrid vertical={false} stroke={GRILLA} />
            <XAxis dataKey="etiqueta" {...ejeX} />
            <YAxis {...ejeY} tickFormatter={(v: number) => n0(v)} />
            <Tooltip content={<TipLitros />} cursor={{ fill: '#f3f4f6' }} />
            <Bar dataKey="litros" stackId="l" cursor="pointer" onClick={(d: { mes?: string }) => d?.mes && onElegir(d.mes)}
                 shape={(p: any) => <Rectangle {...p} radius={p.payload.falta > 0 ? 0 : [4, 4, 0, 0]} />}>
              {datos.map((d) => <Cell key={d.mes} fill={d.mes === mes ? AZUL : AZUL_SUAVE} />)}
            </Bar>
            <Bar dataKey="falta" stackId="l" fill="#eff6ff" stroke={AZUL_SUAVE} strokeDasharray="3 2" radius={[4, 4, 0, 0]}
                 cursor="pointer" onClick={(d: { mes?: string }) => d?.mes && onElegir(d.mes)} />
          </BarChart>
        </ResponsiveContainer>
      </div>
      <p className="mt-1 flex items-center gap-1.5 text-xs text-gray-500">
        <span className="inline-block h-2.5 w-3.5 rounded-sm border border-dashed border-blue-300 bg-blue-50" />
        proyección al cierre del mes en curso · clic en una barra para ver ese mes
      </p>
    </div>
  )
}

function TipKmL({ active, payload }: { active?: boolean; payload?: { payload: Dato }[] }) {
  if (!active || !payload?.length) return null
  const p = payload[0].payload
  return (
    <Caja>
      <p className="mb-1 font-semibold capitalize text-gray-900">{nombreMes(p.mes)}</p>
      <p>{p.kmL == null ? 'Sin km del GPS' : <><b>{n1(p.kmL)} km/L</b> · ${n0(p.costoKm)}/km</>}</p>
    </Caja>
  )
}

export function GraficoKmL({ serie, mes }: { serie: PuntoFlota[]; mes: string }) {
  const datos = serie.map((p) => ({ ...p, etiqueta: etiquetaMes(p.mes), falta: 0 }))
  const conDato = datos.filter((d) => d.kmL != null)
  return (
    <div>
      <div className="h-56">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={datos} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
            <CartesianGrid vertical={false} stroke={GRILLA} />
            <XAxis dataKey="etiqueta" {...ejeX} />
            <YAxis {...ejeY} domain={[0, 'auto']} tickFormatter={(v: number) => n1(v)} />
            <ReferenceLine x={etiquetaMes(mes)} stroke="#9ca3af" strokeDasharray="3 3" />
            <Tooltip content={<TipKmL />} />
            <Line dataKey="kmL" stroke={AZUL} strokeWidth={2} connectNulls={false} isAnimationActive={false}
                  dot={{ r: 4, fill: AZUL, stroke: '#fff', strokeWidth: 2 }} activeDot={{ r: 6 }} />
          </LineChart>
        </ResponsiveContainer>
      </div>
      <p className="mt-1 text-xs text-gray-500">
        {conDato.length < 3
          ? 'Los km del GPS existen desde septiembre de 2026: la línea se irá llenando mes a mes.'
          : 'Km de los tramos entre cargas ÷ litros de esos tramos.'}
      </p>
    </div>
  )
}

// ── Mapa de calor: cada celda = litros del mes vs el normal de ese vehículo ──
const ESCALA: { hasta: number; cls: string; txt: string }[] = [
  { hasta: -0.5, cls: 'bg-blue-200 text-gray-900', txt: '−50 % o menos' },
  { hasta: -0.25, cls: 'bg-blue-50 text-gray-900', txt: '−25 %' },
  { hasta: 0.25, cls: 'bg-gray-100 text-gray-900', txt: 'normal (±25 %)' },
  { hasta: 0.5, cls: 'bg-red-100 text-gray-900', txt: '+25 %' },
  { hasta: 1, cls: 'bg-red-300 text-gray-900', txt: '+50 %' },
  { hasta: Infinity, cls: 'bg-red-600 text-white', txt: '+100 % o más' },
]
const claseCelda = (d: number | null) => (d == null ? 'bg-white text-gray-600' : ESCALA.find((e) => d <= e.hasta)!.cls)

export function MapaCalor({ filas, flota, meses, mes, onElegir }: {
  filas: FilaCalor[]; flota: FilaCalor; meses: string[]; mes: string; onElegir: (m: string) => void
}) {
  const [sel, setSel] = useState<{ patente: string; celda: Celda } | null>(null)
  // Función y no componente: un componente interno se re-montaría en cada hover.
  const fila = (f: FilaCalor, total?: boolean) => (
    <tr key={f.patente} className={cn(total && 'border-b-2 border-gray-300')}>
      <th className={cn('sticky left-0 z-10 bg-white p-1.5 pr-3 text-left text-xs', total ? 'font-bold text-gray-900' : 'font-medium text-gray-800')}>
        {f.patente}{f.tipo && <div className="text-[10px] font-normal text-gray-500">{f.tipo}</div>}
      </th>
      {meses.map((m) => {
        const c = f.celdas[m]
        if (!c) return <td key={m} className={cn('p-0.5', m === mes && 'bg-blue-50/60')}><div className="h-9 rounded border border-dashed border-gray-200" /></td>
        const elegida = sel?.patente === f.patente && sel.celda.mes === m
        return (
          <td key={m} className={cn('p-0.5', m === mes && 'bg-blue-50/60')}>
            <button type="button" onMouseEnter={() => setSel({ patente: f.patente, celda: c })} onFocus={() => setSel({ patente: f.patente, celda: c })}
                    onClick={() => setSel({ patente: f.patente, celda: c })}
                    className={cn('flex h-9 w-full min-w-[46px] items-center justify-center rounded text-xs tabular-nums transition',
                      claseCelda(c.desvio), c.parcial && 'italic', elegida ? 'ring-2 ring-gray-900' : 'hover:ring-2 hover:ring-gray-400')}>
              {c.parcial ? '≈' : ''}{n0(c.litrosProy)}
            </button>
          </td>
        )
      })}
    </tr>
  )
  const c = sel?.celda
  return (
    <div>
      <div className="overflow-x-auto">
        <table className="w-full border-separate border-spacing-0">
          <thead>
            <tr>
              <th className="sticky left-0 z-10 bg-white p-1.5 text-left text-xs font-medium text-gray-500">Litros al mes</th>
              {meses.map((m) => (
                <th key={m} className="p-0.5">
                  <button type="button" onClick={() => onElegir(m)}
                          className={cn('w-full rounded px-1 py-1 text-xs capitalize', m === mes ? 'bg-blue-600 font-semibold text-white' : 'text-gray-600 hover:bg-gray-100')}>
                    {etiquetaMes(m)}
                  </button>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {fila(flota, true)}
            {filas.map((f) => fila(f))}
          </tbody>
        </table>
      </div>
      <div className="mt-2 min-h-[40px] rounded-lg bg-gray-50 px-3 py-2 text-xs text-gray-700" aria-live="polite">
        {c ? (
          <>
            <b>{sel!.patente}</b> · <span className="capitalize">{nombreMes(c.mes)}</span>: {n0(c.litros)} L en {c.cargas} cargas
            {c.parcial && <> (≈ {n0(c.litrosProy)} L al cierre)</>}
            {c.incompleto ? <> · el historial parte este mes a medias: no se compara</>
              : c.normal != null ? <> · normal {n0(c.normal)} L · <b>{pct(c.desvio!)}</b></> : <> · aún no hay 3 meses para saber su normal</>}
            {c.kmGps != null && <> · {n0(c.kmGps)} km GPS</>}
            {c.kmL != null && <> · {n1(c.kmL)} km/L</>}
          </>
        ) : 'Pase el mouse (o toque) una celda para ver el detalle.'}
      </div>
      <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-gray-600">
        <span>Litros vs su normal:</span>
        {ESCALA.map((e) => <span key={e.txt} className="flex items-center gap-1"><span className={cn('inline-block h-3 w-4 rounded-sm', e.cls)} />{e.txt}</span>)}
        <span className="flex items-center gap-1"><span className="inline-block h-3 w-4 rounded-sm border border-dashed border-gray-300" />sin cargas</span>
        <span className="flex items-center gap-1"><i>≈</i> mes en curso, proyectado</span>
      </div>
    </div>
  )
}
