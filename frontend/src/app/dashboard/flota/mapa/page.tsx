'use client'

import { useEffect, useMemo, useState } from 'react'
import dynamic from 'next/dynamic'
import Link from 'next/link'
import {
  MapPin, RefreshCw, Satellite, AlertTriangle, ArrowLeft,
  Activity, Pause, WifiOff, HelpCircle,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { supabase } from '@/lib/supabase'
import type { PosicionFlota } from '@/components/flota/mapa-flota'

const MapaFlota = dynamic(
  () => import('@/components/flota/mapa-flota').then((m) => m.MapaFlota),
  { ssr: false, loading: () => <div className="flex h-[500px] items-center justify-center"><Spinner /></div> }
)

const REFRESH_MS = 60_000  // 60s

export default function MapaFlotaPage() {
  useRequireAuth()

  const [posiciones, setPosiciones] = useState<PosicionFlota[]>([])
  const [loading, setLoading]       = useState(true)
  const [error, setError]           = useState<string | null>(null)
  const [ultimoFetch, setUltimoFetch] = useState<Date | null>(null)

  const cargar = async () => {
    setError(null)
    const { data, error } = await supabase
      .from('v_flota_posiciones')
      .select('*')
      .order('activo_codigo')
    if (error) { setError(error.message); setLoading(false); return }
    setPosiciones((data ?? []) as PosicionFlota[])
    setUltimoFetch(new Date())
    setLoading(false)
  }

  useEffect(() => {
    cargar()
    const t = setInterval(cargar, REFRESH_MS)
    return () => clearInterval(t)
  }, [])

  const stats = useMemo(() => {
    const acc = { en_ruta: 0, detenido_motor_on: 0, detenido: 0, sin_senal: 0, sin_datos: 0 }
    for (const p of posiciones) acc[p.estado_pin]++
    return acc
  }, [posiciones])

  return (
    <div className="space-y-4 p-4 sm:p-6">
      {/* Header */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Link href="/dashboard/flota">
            <Button variant="ghost" size="sm" className="gap-1">
              <ArrowLeft className="h-4 w-4" /> Flota
            </Button>
          </Link>
          <div>
            <h1 className="flex items-center gap-2 text-2xl font-bold">
              <Satellite className="h-6 w-6 text-blue-600" />
              Mapa en vivo
            </h1>
            <p className="text-sm text-muted-foreground">
              {ultimoFetch
                ? `Actualizado ${ultimoFetch.toLocaleTimeString('es-CL')} — refresca cada 60s`
                : 'Cargando posiciones...'}
            </p>
          </div>
        </div>
        <Button onClick={cargar} variant="outline" size="sm" className="gap-1" disabled={loading}>
          <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          Refrescar
        </Button>
      </div>

      {/* Contadores por estado */}
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
        <StatCard color="bg-green-50 border-green-200 text-green-700"
                  icon={<Activity className="h-4 w-4" />} label="En ruta" valor={stats.en_ruta} />
        <StatCard color="bg-amber-50 border-amber-200 text-amber-700"
                  icon={<Pause className="h-4 w-4" />} label="Motor ON detenido" valor={stats.detenido_motor_on} />
        <StatCard color="bg-gray-50 border-gray-200 text-gray-700"
                  icon={<Pause className="h-4 w-4" />} label="Detenido" valor={stats.detenido} />
        <StatCard color="bg-red-50 border-red-200 text-red-700"
                  icon={<WifiOff className="h-4 w-4" />} label="Sin señal >2h" valor={stats.sin_senal} />
        <StatCard color="bg-zinc-50 border-zinc-200 text-zinc-700"
                  icon={<HelpCircle className="h-4 w-4" />} label="Sin datos GPS" valor={stats.sin_datos} />
      </div>

      {error && (
        <Card className="border-red-200 bg-red-50">
          <CardContent className="flex items-center gap-2 p-4 text-sm text-red-700">
            <AlertTriangle className="h-4 w-4" /> {error}
          </CardContent>
        </Card>
      )}

      {/* Mapa */}
      <Card>
        <CardContent className="p-0">
          <div style={{ height: 'calc(100vh - 320px)', minHeight: 500 }}>
            {loading && posiciones.length === 0 ? (
              <div className="flex h-full items-center justify-center"><Spinner /></div>
            ) : (
              <MapaFlota posiciones={posiciones} />
            )}
          </div>
        </CardContent>
      </Card>

      {/* Tabla compacta — vehículos con problemas de señal o sin datos */}
      {(stats.sin_senal > 0 || stats.sin_datos > 0) && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <AlertTriangle className="h-4 w-4 text-amber-600" />
              Vehículos sin reportar
            </CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <div className="max-h-64 overflow-auto">
              <table className="w-full text-sm">
                <thead className="sticky top-0 bg-gray-50">
                  <tr>
                    <th className="px-3 py-2 text-left">Código</th>
                    <th className="px-3 py-2 text-left">Estado</th>
                    <th className="px-3 py-2 text-left">Último reporte</th>
                    <th className="px-3 py-2 text-right">Odómetro</th>
                    <th className="px-3 py-2 text-right">Horómetro</th>
                  </tr>
                </thead>
                <tbody>
                  {posiciones
                    .filter((p) => p.estado_pin === 'sin_senal' || p.estado_pin === 'sin_datos')
                    .map((p) => (
                      <tr key={p.activo_id} className="border-t">
                        <td className="px-3 py-2 font-medium">{p.activo_codigo}</td>
                        <td className="px-3 py-2">
                          <Badge variant={p.estado_pin === 'sin_senal' ? 'no_ejecutada' : 'default'}>
                            {p.estado_pin === 'sin_senal' ? 'Sin señal >2h' : 'Sin datos'}
                          </Badge>
                        </td>
                        <td className="px-3 py-2 text-muted-foreground">
                          {p.ts_gps ? new Date(p.ts_gps).toLocaleString('es-CL') : '—'}
                        </td>
                        <td className="px-3 py-2 text-right">
                          {p.odometro_km != null ? `${p.odometro_km.toFixed(0)} km` : '—'}
                        </td>
                        <td className="px-3 py-2 text-right">
                          {p.horometro_hrs != null ? `${p.horometro_hrs.toFixed(1)} h` : '—'}
                        </td>
                      </tr>
                    ))}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}

function StatCard({
  color, icon, label, valor,
}: { color: string; icon: React.ReactNode; label: string; valor: number }) {
  return (
    <div className={`flex items-center justify-between rounded-lg border px-3 py-2 ${color}`}>
      <div className="flex items-center gap-2">
        {icon}
        <span className="text-xs font-medium">{label}</span>
      </div>
      <span className="text-lg font-bold">{valor}</span>
    </div>
  )
}
