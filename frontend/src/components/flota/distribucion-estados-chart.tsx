'use client'

import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from 'recharts'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { BarChart3 } from 'lucide-react'
import type { TendenciaDia } from '@/lib/services/reporte-diario'

interface Props {
  data: TendenciaDia[]
  isLoading?: boolean
}

function formatFecha(fecha: string) {
  const d = new Date(fecha + 'T00:00:00')
  return `${d.getDate().toString().padStart(2, '0')}/${(d.getMonth() + 1).toString().padStart(2, '0')}`
}

const ESTADO_COLORS = {
  Arrendado: '#16a34a',
  Disponible: '#2563eb',
  'Uso interno': '#0891b2',
  Leasing: '#7c3aed',
  Mantención: '#f59e0b',
  Taller: '#ea580c',
  'Fuera servicio': '#dc2626',
} as const

export function DistribucionEstadosChart({ data, isLoading }: Props) {
  const rows = data.map((d) => ({
    fecha: formatFecha(d.fecha),
    Arrendado: d.total_arrendados,
    Disponible: d.total_disponibles,
    'Uso interno': d.total_uso_interno,
    Leasing: d.total_leasing,
    Mantención: d.total_mantencion,
    Taller: d.total_taller,
    'Fuera servicio': d.total_fuera_servicio,
  }))

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <BarChart3 className="h-5 w-5 text-indigo-600" />
          Distribución diaria de estados de la flota
        </CardTitle>
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
            <BarChart data={rows} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
              <XAxis dataKey="fecha" tick={{ fontSize: 11 }} />
              <YAxis tick={{ fontSize: 11 }} />
              <Tooltip contentStyle={{ fontSize: 12 }} />
              <Legend wrapperStyle={{ fontSize: 11 }} />
              {Object.entries(ESTADO_COLORS).map(([k, color]) => (
                <Bar key={k} dataKey={k} stackId="estados" fill={color} />
              ))}
            </BarChart>
          </ResponsiveContainer>
        )}
      </CardContent>
    </Card>
  )
}
