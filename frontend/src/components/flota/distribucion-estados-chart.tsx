'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, Legend,
} from 'recharts'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { BarChart3, ArrowUpRight, XCircle } from 'lucide-react'
import type { TendenciaDia } from '@/lib/services/reporte-diario'
import { getEquiposPorFechaEstado, type EquipoEnEstado } from '@/lib/services/flota'

interface Props {
  data: TendenciaDia[]
  isLoading?: boolean
}

function formatFecha(fecha: string) {
  const d = new Date(fecha + 'T00:00:00')
  return `${d.getDate().toString().padStart(2, '0')}/${(d.getMonth() + 1).toString().padStart(2, '0')}`
}

// Mapeo nombre visible ↔ codigo en DB
const ESTADO_META: Record<string, { color: string; codigo: string }> = {
  Arrendado:         { color: '#16a34a', codigo: 'A' },
  Disponible:        { color: '#2563eb', codigo: 'D' },
  'Uso interno':     { color: '#0891b2', codigo: 'U' },
  Leasing:           { color: '#7c3aed', codigo: 'L' },
  Mantención:        { color: '#f59e0b', codigo: 'M' },
  Taller:            { color: '#ea580c', codigo: 'T' },
  'Fuera servicio':  { color: '#dc2626', codigo: 'F' },
}

export function DistribucionEstadosChart({ data, isLoading }: Props) {
  const [seleccion, setSeleccion] = useState<{ fecha: string; estadoNombre: string; estadoCodigo: string } | null>(null)
  const [detalle, setDetalle] = useState<EquipoEnEstado[]>([])
  const [loadingDetalle, setLoadingDetalle] = useState(false)

  const rows = data.map((d) => ({
    fechaRaw: d.fecha,
    fecha: formatFecha(d.fecha),
    Arrendado: d.total_arrendados,
    Disponible: d.total_disponibles,
    'Uso interno': d.total_uso_interno,
    Leasing: d.total_leasing,
    Mantención: d.total_mantencion,
    Taller: d.total_taller,
    'Fuera servicio': d.total_fuera_servicio,
  }))

  useEffect(() => {
    if (!seleccion) {
      setDetalle([])
      return
    }
    let cancelled = false
    setLoadingDetalle(true)
    getEquiposPorFechaEstado(seleccion.fecha, seleccion.estadoCodigo).then(({ data }) => {
      if (cancelled) return
      setDetalle(data)
      setLoadingDetalle(false)
    })
    return () => { cancelled = true }
  }, [seleccion])

  const handleBarClick = (estadoNombre: string) => (payload: any) => {
    const raw = payload?.fechaRaw ?? payload?.payload?.fechaRaw
    if (!raw) return
    const codigo = ESTADO_META[estadoNombre]?.codigo
    if (!codigo) return
    setSeleccion({ fecha: raw, estadoNombre, estadoCodigo: codigo })
  }

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center justify-between">
          <span className="flex items-center gap-2">
            <BarChart3 className="h-5 w-5 text-indigo-600" />
            Distribución diaria de estados de la flota
          </span>
          {seleccion && (
            <button
              className="text-xs text-blue-600 hover:underline flex items-center gap-1"
              onClick={() => setSeleccion(null)}
            >
              <XCircle className="h-4 w-4" />
              Limpiar filtro
            </button>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {isLoading ? (
          <div className="flex h-64 items-center justify-center">
            <Spinner className="h-6 w-6" />
          </div>
        ) : rows.length === 0 ? (
          <div className="flex h-64 items-center justify-center text-sm text-gray-400">
            Sin snapshots históricos suficientes todavía.
          </div>
        ) : (
          <>
            <ResponsiveContainer width="100%" height={280}>
              <BarChart data={rows} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                <XAxis dataKey="fecha" tick={{ fontSize: 11 }} />
                <YAxis tick={{ fontSize: 11 }} />
                <Tooltip contentStyle={{ fontSize: 12 }} />
                <Legend wrapperStyle={{ fontSize: 11 }} />
                {Object.entries(ESTADO_META).map(([k, meta]) => (
                  <Bar
                    key={k}
                    dataKey={k}
                    stackId="estados"
                    fill={meta.color}
                    cursor="pointer"
                    onClick={handleBarClick(k)}
                  />
                ))}
              </BarChart>
            </ResponsiveContainer>
            <p className="text-[11px] text-gray-400 text-center">
              Click en un segmento para ver qué equipos estaban en ese estado ese día.
            </p>
          </>
        )}

        {/* ── Drill-down ── */}
        {seleccion && (
          <div className="rounded-lg border bg-gray-50/50 p-3">
            <div className="mb-2 flex items-center justify-between text-sm">
              <div className="flex items-center gap-2">
                <Badge
                  className="text-white"
                  style={{ backgroundColor: ESTADO_META[seleccion.estadoNombre]?.color }}
                >
                  {seleccion.estadoNombre}
                </Badge>
                <span className="text-gray-600">
                  · {formatFecha(seleccion.fecha)} ({seleccion.fecha})
                </span>
              </div>
              <div className="text-xs text-gray-500">
                {detalle.length} equipo{detalle.length !== 1 && 's'}
              </div>
            </div>

            {loadingDetalle ? (
              <div className="flex justify-center py-4"><Spinner className="h-6 w-6" /></div>
            ) : detalle.length === 0 ? (
              <p className="text-sm text-gray-400 text-center py-3">
                Sin equipos en ese estado para esa fecha.
              </p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-xs">
                  <thead>
                    <tr className="border-b text-left text-gray-500 uppercase">
                      <th className="px-2 py-1.5">Patente</th>
                      <th className="px-2 py-1.5">Equipo</th>
                      <th className="px-2 py-1.5">Cliente</th>
                      <th className="px-2 py-1.5">Operación</th>
                      <th className="px-2 py-1.5">Ubicación</th>
                      <th className="px-2 py-1.5">Observación</th>
                      <th className="px-2 py-1.5"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {detalle.map((e) => (
                      <tr key={e.activo_id} className="border-b hover:bg-white">
                        <td className="px-2 py-1.5 font-mono font-semibold">{e.patente ?? e.codigo ?? '—'}</td>
                        <td className="px-2 py-1.5">{e.nombre ?? '—'}</td>
                        <td className="px-2 py-1.5 text-gray-600">{e.cliente ?? '—'}</td>
                        <td className="px-2 py-1.5 text-gray-500">{e.operacion ?? '—'}</td>
                        <td className="px-2 py-1.5 text-gray-500 max-w-[160px] truncate">{e.ubicacion ?? '—'}</td>
                        <td className="px-2 py-1.5 text-gray-500 max-w-[200px] truncate italic">{e.observacion ?? ''}</td>
                        <td className="px-2 py-1.5 text-right">
                          <Link href={`/dashboard/activos/${e.activo_id}`} className="text-blue-600 hover:underline">
                            ver <ArrowUpRight className="inline h-3 w-3" />
                          </Link>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  )
}
