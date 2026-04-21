'use client'

import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from 'recharts'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { TrendingUp } from 'lucide-react'
import type { TendenciaDia } from '@/lib/services/reporte-diario'

interface Props {
  data: TendenciaDia[]
  isLoading?: boolean
  dias: number
  onChangeDias: (d: number) => void
}

function formatFecha(fecha: string) {
  const d = new Date(fecha + 'T00:00:00')
  return `${d.getDate().toString().padStart(2, '0')}/${(d.getMonth() + 1).toString().padStart(2, '0')}`
}

export function TendenciaFlotaChart({ data, isLoading, dias, onChangeDias }: Props) {
  const rows = data.map((d) => ({
    fecha: formatFecha(d.fecha),
    OEE: d.oee_promedio ? Number(d.oee_promedio.toFixed(1)) : 0,
    Disponibilidad: d.disponibilidad_promedio ? Number(d.disponibilidad_promedio.toFixed(1)) : 0,
    Utilización: d.utilizacion_promedio ? Number(d.utilizacion_promedio.toFixed(1)) : 0,
  }))

  return (
    <Card>
      <CardHeader className="pb-2 flex flex-row items-center justify-between">
        <CardTitle className="text-base flex items-center gap-2">
          <TrendingUp className="h-5 w-5 text-green-600" />
          Tendencia OEE, Disponibilidad y Utilización
        </CardTitle>
        <div className="flex gap-1">
          {[7, 14, 30].map((n) => (
            <button
              key={n}
              onClick={() => onChangeDias(n)}
              className={`rounded px-2 py-1 text-xs font-medium ${
                dias === n
                  ? 'bg-indigo-600 text-white'
                  : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
              }`}
            >
              {n}d
            </button>
          ))}
        </div>
      </CardHeader>
      <CardContent>
        {isLoading ? (
          <div className="flex h-64 items-center justify-center">
            <Spinner className="h-6 w-6" />
          </div>
        ) : rows.length === 0 ? (
          <div className="flex h-64 items-center justify-center text-sm text-gray-400">
            Sin snapshots históricos suficientes todavía.
          </div>
        ) : (
          <ResponsiveContainer width="100%" height={280}>
            <LineChart data={rows} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
              <XAxis dataKey="fecha" tick={{ fontSize: 11 }} />
              <YAxis tick={{ fontSize: 11 }} domain={[0, 100]} unit="%" />
              <Tooltip
                formatter={(value: number) => `${value}%`}
                contentStyle={{ fontSize: 12 }}
              />
              <Legend wrapperStyle={{ fontSize: 12 }} />
              <Line
                type="monotone"
                dataKey="OEE"
                stroke="#16a34a"
                strokeWidth={2.5}
                dot={{ r: 3 }}
                activeDot={{ r: 5 }}
              />
              <Line
                type="monotone"
                dataKey="Disponibilidad"
                stroke="#2563eb"
                strokeWidth={2}
                dot={{ r: 2 }}
              />
              <Line
                type="monotone"
                dataKey="Utilización"
                stroke="#f59e0b"
                strokeWidth={2}
                dot={{ r: 2 }}
              />
            </LineChart>
          </ResponsiveContainer>
        )}
      </CardContent>
    </Card>
  )
}
