'use client'

import {
  ResponsiveContainer, LineChart, Line, XAxis, YAxis, CartesianGrid,
  Tooltip, Legend,
} from 'recharts'
import type { CalamaCurvaSPunto, CalamaCurvaSConteoPunto } from '@/lib/services/calama'

type Props = {
  data: CalamaCurvaSPunto[]
  height?: number
}

export function CurvaSChart({ data, height = 280 }: Props) {
  if (!data || data.length === 0) {
    return (
      <div className="rounded-lg border border-dashed border-gray-200 p-6 text-center text-sm text-gray-400">
        Sin datos de curva S para esta planificacion.
      </div>
    )
  }

  const chartData = data.map((p) => ({
    fecha: p.fecha,
    Plan: Number(p.avance_plan_pct),
    Real: Number(p.avance_real_pct),
    Desv: Math.round((Number(p.avance_real_pct) - Number(p.avance_plan_pct)) * 100) / 100,
  }))

  return (
    <div style={{ width: '100%', height }}>
      <ResponsiveContainer>
        <LineChart data={chartData} margin={{ top: 10, right: 16, left: 0, bottom: 4 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
          <XAxis
            dataKey="fecha"
            tick={{ fontSize: 11 }}
            interval="preserveStartEnd"
            tickFormatter={(v) => v.slice(5)}
          />
          <YAxis
            tick={{ fontSize: 11 }}
            domain={[0, 100]}
            tickFormatter={(v) => `${v}%`}
            width={42}
          />
          <Tooltip
            formatter={(value: number) => `${value.toFixed(1)}%`}
            labelFormatter={(l) => `Fecha: ${l}`}
          />
          <Legend wrapperStyle={{ fontSize: 12 }} />
          <Line
            type="monotone" dataKey="Plan" stroke="#6366f1" strokeWidth={2}
            dot={false} strokeDasharray="4 4"
          />
          <Line
            type="monotone" dataKey="Real" stroke="#16a34a" strokeWidth={2.5}
            dot={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}

// MIG46 - Curva S por conteo de OTs (3 metricas oficiales MIG34/35):
//   Plan       (lineal de referencia, dashed)
//   Completitud (Finalizadas / Total) - verde fuerte
//   Real        (Finalizadas + En ejecucion / Total) - ambar
//   Proyectado  (Fin + En ejec + Planificadas semana / Total) - azul
export function CurvaSConteoChart({
  data, height = 280,
}: { data: CalamaCurvaSConteoPunto[]; height?: number }) {
  if (!data || data.length === 0) {
    return (
      <div className="rounded-lg border border-dashed border-gray-200 p-6 text-center text-sm text-gray-400">
        Sin datos de curva S para esta planificacion.
      </div>
    )
  }

  const chartData = data.map((p) => ({
    fecha: p.fecha,
    Plan:        Number(p.avance_plan_pct),
    Completitud: Number(p.completitud_pct),
    Real:        Number(p.real_pct),
    Proyectado:  Number(p.proyectado_pct),
  }))

  return (
    <div style={{ width: '100%', height }}>
      <ResponsiveContainer>
        <LineChart data={chartData} margin={{ top: 10, right: 16, left: 0, bottom: 4 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
          <XAxis
            dataKey="fecha"
            tick={{ fontSize: 11 }}
            interval="preserveStartEnd"
            tickFormatter={(v) => v.slice(5)}
          />
          <YAxis
            tick={{ fontSize: 11 }}
            domain={[0, 100]}
            tickFormatter={(v) => `${v}%`}
            width={42}
          />
          <Tooltip
            formatter={(value: number) => `${value.toFixed(1)}%`}
            labelFormatter={(l) => `Fecha: ${l}`}
          />
          <Legend wrapperStyle={{ fontSize: 12 }} />
          <Line
            type="monotone" dataKey="Plan" stroke="#94a3b8" strokeWidth={1.5}
            dot={false} strokeDasharray="4 4"
          />
          <Line
            type="monotone" dataKey="Completitud" stroke="#16a34a" strokeWidth={2.5}
            dot={false}
          />
          <Line
            type="monotone" dataKey="Real" stroke="#f59e0b" strokeWidth={2}
            dot={false}
          />
          <Line
            type="monotone" dataKey="Proyectado" stroke="#6366f1" strokeWidth={2}
            dot={false} strokeDasharray="6 3"
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  )
}
