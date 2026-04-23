'use client'

import { useEffect, useState, useMemo } from 'react'
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, Legend,
} from 'recharts'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import {
  getHistorialEstadosActivo,
  ESTADO_DIARIO_LABELS,
  type HistorialMesActivo,
} from '@/lib/services/flota'

// Paleta alineada con los colores del sistema (mig 25)
const COLORS: Record<string, string> = {
  A: '#16A34A',  // Arrendado — verde
  L: '#4F46E5',  // Leasing — índigo
  U: '#0891B2',  // Uso interno — cian
  D: '#F59E0B',  // Disponible — ámbar
  H: '#FBBF24',  // Habilitación — amarillo
  R: '#7C3AED',  // Recepción — violeta
  V: '#6B7280',  // Venta — gris
  M: '#F97316',  // Mantención — naranja
  T: '#EAB308',  // Taller — amarillo oscuro
  F: '#DC2626',  // Fuera servicio — rojo
}

interface Props {
  activoId: string
  titulo?: string
  year?: number  // default = año actual
}

export function HistorialEstadosChart({ activoId, titulo, year }: Props) {
  const [data, setData] = useState<HistorialMesActivo[]>([])
  const [loading, setLoading] = useState(true)

  const rango = useMemo(() => {
    const y = year ?? new Date().getFullYear()
    return {
      inicio: `${y}-01-01`,
      fin: `${y}-12-31`,
    }
  }, [year])

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    getHistorialEstadosActivo(activoId, rango.inicio, rango.fin).then(({ data }) => {
      if (cancelled) return
      setData(data)
      setLoading(false)
    })
    return () => { cancelled = true }
  }, [activoId, rango.inicio, rango.fin])

  // Rellenar meses faltantes con ceros para que el eje X muestre los 12
  const dataConMesesLlenos = useMemo(() => {
    const y = year ?? new Date().getFullYear()
    const map = new Map(data.map((d) => [d.mes, d]))
    const out: HistorialMesActivo[] = []
    for (let m = 1; m <= 12; m++) {
      const key = `${y}-${String(m).padStart(2, '0')}`
      out.push(
        map.get(key) ?? {
          mes: key, A: 0, D: 0, H: 0, R: 0, V: 0,
          U: 0, L: 0, M: 0, T: 0, F: 0, total: 0,
        },
      )
    }
    return out
  }, [data, year])

  const mesLabel = (mes: string) => {
    const m = parseInt(mes.slice(5, 7), 10)
    const meses = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic']
    return meses[m - 1] ?? mes
  }

  // Orden visual: los productivos abajo, los DOWN arriba
  const orden = ['A', 'L', 'U', 'D', 'H', 'R', 'V', 'M', 'T', 'F'] as const

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base text-gray-700">
          {titulo ?? `Histórico de Estados ${year ?? new Date().getFullYear()}`}
        </CardTitle>
        <p className="text-xs text-gray-400">
          Días de cada estado por mes. Eje Y = días totales observados.
        </p>
      </CardHeader>
      <CardContent>
        {loading ? (
          <div className="h-64 flex items-center justify-center">
            <Spinner className="h-8 w-8" />
          </div>
        ) : (
          <div className="h-72">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={dataConMesesLlenos} margin={{ top: 10, right: 10, bottom: 0, left: 0 }}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis
                  dataKey="mes"
                  tickFormatter={mesLabel}
                  tick={{ fontSize: 11 }}
                />
                <YAxis tick={{ fontSize: 11 }} />
                <Tooltip
                  labelFormatter={(v) => mesLabel(String(v))}
                  formatter={(value: number, name: string) => [
                    `${value} días`,
                    `${name} — ${ESTADO_DIARIO_LABELS[name] ?? name}`,
                  ]}
                />
                <Legend
                  formatter={(value) => `${value} — ${ESTADO_DIARIO_LABELS[value] ?? value}`}
                  wrapperStyle={{ fontSize: 11 }}
                />
                {orden.map((key) => (
                  <Bar
                    key={key}
                    dataKey={key}
                    stackId="estados"
                    fill={COLORS[key]}
                    name={key}
                  />
                ))}
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}
        <p className="mt-1 text-[10px] text-gray-400">
          A = Arrendado · D = Disponible · H = Habilitación · R = Recepción · V = Venta ·
          U = Uso interno · L = Leasing · M = Mantención &gt;1d · T = Taller &lt;1d · F = Fuera servicio.
        </p>
      </CardContent>
    </Card>
  )
}
