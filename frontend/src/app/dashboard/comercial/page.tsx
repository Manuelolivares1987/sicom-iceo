'use client'

import { useMemo, useState } from 'react'
import {
  Briefcase,
  TrendingUp,
  TrendingDown,
  Users,
  DollarSign,
  MapPin,
  AlertCircle,
} from 'lucide-react'
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Cell,
} from 'recharts'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { cn, todayISO } from '@/lib/utils'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useFlotaVehicular, useOEEFlota } from '@/hooks/use-flota'
import { useReporteDiario } from '@/hooks/use-reporte-diario'

export default function ComercialPage() {
  useRequireAuth()

  const today = new Date()
  const firstOfMonth = new Date(today.getFullYear(), today.getMonth(), 1)
  const fechaInicio = `${firstOfMonth.getFullYear()}-${String(firstOfMonth.getMonth() + 1).padStart(2, '0')}-01`
  const fechaFin = todayISO()

  const { data: flota, isLoading: loadingFlota } = useFlotaVehicular()
  const { data: oeeTotal } = useOEEFlota(fechaInicio, fechaFin)
  const { data: reporte } = useReporteDiario()

  // ── Agregaciones ──
  const stats = useMemo(() => {
    if (!flota) return null
    const total = flota.length
    const porEstadoComercial: Record<string, number> = {}
    const porCliente: Record<string, number> = {}
    const porOperacion: Record<string, number> = {}

    flota.forEach((a: any) => {
      const ec = a.estado_comercial || 'sin_estado'
      porEstadoComercial[ec] = (porEstadoComercial[ec] || 0) + 1
      const cliente = a.cliente_actual || 'Sin cliente'
      porCliente[cliente] = (porCliente[cliente] || 0) + 1
      const op = a.operacion || 'Sin asignar'
      porOperacion[op] = (porOperacion[op] || 0) + 1
    })

    const arrendados = porEstadoComercial['arrendado'] || 0
    const disponibles = porEstadoComercial['disponible'] || 0
    const usoInterno = porEstadoComercial['uso_interno'] || 0
    const leasing = porEstadoComercial['leasing'] || 0

    return {
      total,
      arrendados,
      disponibles,
      usoInterno,
      leasing,
      porCliente,
      porOperacion,
      tasaOcupacion: total > 0 ? ((arrendados + usoInterno + leasing) / total * 100) : 0,
      perdidaComercial: disponibles,
      perdidaPct: total > 0 ? (disponibles / total * 100) : 0,
    }
  }, [flota])

  const clientesData = useMemo(() => {
    if (!stats) return []
    return Object.entries(stats.porCliente)
      .filter(([k]) => k !== 'Sin cliente')
      .map(([cliente, cantidad]) => ({ clienteFull: cliente, cliente: cliente.slice(0, 20), cantidad }))
      .sort((a, b) => b.cantidad - a.cantidad)
      .slice(0, 10)
  }, [stats])

  // ── Filtro por cliente desde BarChart ──
  const [filtroCliente, setFiltroCliente] = useState<string | null>(null)

  if (loadingFlota) {
    return (
      <div className="flex h-64 items-center justify-center">
        <Spinner className="h-8 w-8" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* ── Header ── */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
          <Briefcase className="h-7 w-7 text-purple-600" />
          Vista Comercial
        </h1>
        <p className="text-sm text-gray-500 mt-1">
          Estado de arriendo, pérdida comercial y cumplimiento de contratos · {fechaInicio} al {fechaFin}
        </p>
      </div>

      {/* ── KPIs comerciales ── */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <Card className="border-green-200 bg-green-50">
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium text-green-700">Arrendados</span>
              <TrendingUp className="h-4 w-4 text-green-600" />
            </div>
            <div className="mt-2 text-3xl font-bold text-green-900">{stats?.arrendados ?? 0}</div>
            <div className="mt-1 text-xs text-green-600">
              {stats?.total ? ((stats.arrendados / stats.total) * 100).toFixed(1) : 0}% de la flota
            </div>
          </CardContent>
        </Card>
        <Card className="border-amber-200 bg-amber-50">
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium text-amber-700">Pérdida Comercial</span>
              <TrendingDown className="h-4 w-4 text-amber-600" />
            </div>
            <div className="mt-2 text-3xl font-bold text-amber-900">{stats?.perdidaComercial ?? 0}</div>
            <div className="mt-1 text-xs text-amber-600">
              {stats?.perdidaPct.toFixed(1) ?? 0}% ociosos sin arriendo
            </div>
          </CardContent>
        </Card>
        <Card className="border-blue-200 bg-blue-50">
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium text-blue-700">Tasa de Ocupación</span>
              <DollarSign className="h-4 w-4 text-blue-600" />
            </div>
            <div className="mt-2 text-3xl font-bold text-blue-900">
              {stats?.tasaOcupacion.toFixed(1) ?? 0}%
            </div>
            <div className="mt-1 text-xs text-blue-600">
              Arrendados + Uso Interno + Leasing
            </div>
          </CardContent>
        </Card>
        <Card className="border-purple-200 bg-purple-50">
          <CardContent className="pt-6">
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium text-purple-700">Clientes Activos</span>
              <Users className="h-4 w-4 text-purple-600" />
            </div>
            <div className="mt-2 text-3xl font-bold text-purple-900">
              {stats?.porCliente ? Object.keys(stats.porCliente).filter((k) => k !== 'Sin cliente').length : 0}
            </div>
            <div className="mt-1 text-xs text-purple-600">
              Con equipos asignados
            </div>
          </CardContent>
        </Card>
      </div>

      {/* ── Distribución por cliente ── */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2 justify-between">
            <span className="flex items-center gap-2">
              <Users className="h-5 w-5 text-gray-600" />
              Equipos por Cliente (Top 10)
            </span>
            {filtroCliente && (
              <button className="text-xs font-medium text-blue-600 hover:underline" onClick={() => setFiltroCliente(null)}>
                Limpiar filtro
              </button>
            )}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {clientesData.length > 0 ? (
            <>
              <div className="h-72">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={clientesData} layout="vertical" margin={{ left: 100 }}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis type="number" />
                    <YAxis dataKey="cliente" type="category" width={100} tick={{ fontSize: 11 }} />
                    <Tooltip />
                    <Bar
                      dataKey="cantidad"
                      fill="#9333ea"
                      radius={[0, 4, 4, 0]}
                      cursor="pointer"
                      onClick={(data: any) => {
                        if (data?.clienteFull) {
                          setFiltroCliente(filtroCliente === data.clienteFull ? null : data.clienteFull)
                        }
                      }}
                    >
                      {clientesData.map((entry, index) => (
                        <Cell
                          key={index}
                          fill="#9333ea"
                          opacity={filtroCliente && filtroCliente !== entry.clienteFull ? 0.3 : 1}
                        />
                      ))}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              </div>
              <p className="mt-1 text-xs text-gray-500 text-center">Click en una barra para filtrar las tablas</p>
            </>
          ) : (
            <p className="text-sm text-gray-400">Sin datos</p>
          )}
        </CardContent>
      </Card>

      {/* ── OEE comercial ── */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <TrendingUp className="h-5 w-5 text-gray-600" />
            OEE de la Flota (Mes Corriente)
          </CardTitle>
        </CardHeader>
        <CardContent>
          {oeeTotal ? (
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
              <div className="text-center">
                <div className="text-xs text-gray-500">OEE Total</div>
                <div className="text-3xl font-bold text-gray-900">
                  {oeeTotal.oee_promedio?.toFixed(1) ?? 0}%
                </div>
                <div className="text-xs text-gray-500">{oeeTotal.clasificacion}</div>
              </div>
              <div className="text-center">
                <div className="text-xs text-gray-500">Disponibilidad</div>
                <div className="text-3xl font-bold text-blue-700">
                  {oeeTotal.disponibilidad_promedio?.toFixed(1) ?? 0}%
                </div>
              </div>
              <div className="text-center">
                <div className="text-xs text-gray-500">Utilización</div>
                <div className="text-3xl font-bold text-green-700">
                  {oeeTotal.utilizacion_promedio?.toFixed(1) ?? 0}%
                </div>
              </div>
              <div className="text-center">
                <div className="text-xs text-gray-500">Calidad Servicio</div>
                <div className="text-3xl font-bold text-purple-700">
                  {oeeTotal.calidad_promedio?.toFixed(1) ?? 0}%
                </div>
              </div>
            </div>
          ) : (
            <p className="text-sm text-gray-400">Sin datos de OEE</p>
          )}
        </CardContent>
      </Card>

      {/* ── Detalle de equipos arrendados ── */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <MapPin className="h-5 w-5 text-gray-600" />
            Equipos Arrendados en Faena
          </CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b text-left text-gray-500 uppercase">
                <th className="px-2 py-2">PPU</th>
                <th className="px-2 py-2">Equipo</th>
                <th className="px-2 py-2">Cliente</th>
                <th className="px-2 py-2">Operación</th>
                <th className="px-2 py-2">Ubicación</th>
                <th className="px-2 py-2">Año</th>
              </tr>
            </thead>
            <tbody>
              {flota?.filter((a: any) => a.estado_comercial === 'arrendado' && (!filtroCliente || a.cliente_actual === filtroCliente)).map((activo: any) => (
                <tr key={activo.id} className="border-b hover:bg-gray-50">
                  <td className="px-2 py-2 font-mono font-semibold">{activo.patente || activo.codigo}</td>
                  <td className="px-2 py-2">{activo.nombre}</td>
                  <td className="px-2 py-2 text-gray-600">{activo.cliente_actual || '—'}</td>
                  <td className="px-2 py-2">{activo.operacion}</td>
                  <td className="px-2 py-2 text-gray-500 max-w-[200px] truncate">{activo.ubicacion_actual}</td>
                  <td className="px-2 py-2">{activo.anio_fabricacion}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </CardContent>
      </Card>

      {/* ── Equipos disponibles (pérdida comercial) ── */}
      <Card className="border-amber-200">
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2 text-amber-700">
            <AlertCircle className="h-5 w-5" />
            Equipos Disponibles — Oportunidad Comercial
          </CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          <p className="text-xs text-gray-600 mb-3">
            Estos equipos están operativos pero sin arriendo asignado. Son pérdida comercial diaria.
          </p>
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b text-left text-gray-500 uppercase">
                <th className="px-2 py-2">PPU</th>
                <th className="px-2 py-2">Equipo</th>
                <th className="px-2 py-2">Operación</th>
                <th className="px-2 py-2">Ubicación Actual</th>
                <th className="px-2 py-2">Año</th>
              </tr>
            </thead>
            <tbody>
              {flota?.filter((a: any) => a.estado_comercial === 'disponible' && (!filtroCliente || !a.cliente_actual)).map((activo: any) => (
                <tr key={activo.id} className="border-b hover:bg-amber-50">
                  <td className="px-2 py-2 font-mono font-semibold">{activo.patente || activo.codigo}</td>
                  <td className="px-2 py-2">{activo.nombre}</td>
                  <td className="px-2 py-2">{activo.operacion}</td>
                  <td className="px-2 py-2 text-gray-500 max-w-[200px] truncate">{activo.ubicacion_actual}</td>
                  <td className="px-2 py-2">{activo.anio_fabricacion}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </CardContent>
      </Card>

      {reporte?.payload?.respel_mes && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base text-gray-600 text-sm">Combustibles — Cumplimiento del mes</CardTitle>
          </CardHeader>
          <CardContent className="text-xs text-gray-500">
            Módulo de combustibles y cumplimiento de rutas por desarrollar. Por ahora se ve el estado agregado en el dashboard de Abastecimiento.
          </CardContent>
        </Card>
      )}
    </div>
  )
}
