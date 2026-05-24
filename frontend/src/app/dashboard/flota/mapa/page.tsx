'use client'

import { useEffect, useMemo, useState } from 'react'
import dynamic from 'next/dynamic'
import Link from 'next/link'
import {
  RefreshCw, Satellite, AlertTriangle, ArrowLeft, Search, X,
  Activity, Pause, WifiOff, HelpCircle, Filter,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { supabase } from '@/lib/supabase'
import type { PosicionFlota } from '@/components/flota/mapa-flota'
import { useFlotaDashboard } from '@/hooks/use-flota-dashboard'

const MapaFlota = dynamic(
  () => import('@/components/flota/mapa-flota').then((m) => m.MapaFlota),
  { ssr: false, loading: () => <div className="flex h-[500px] items-center justify-center"><Spinner /></div> }
)

const REFRESH_MS = 60_000

type EstadoPin = PosicionFlota['estado_pin']

const ESTADO_OPCIONES: { value: EstadoPin; label: string; color: string }[] = [
  { value: 'en_ruta',           label: 'En ruta',         color: 'bg-green-100 text-green-700 border-green-300' },
  { value: 'detenido_motor_on', label: 'Motor ON',        color: 'bg-amber-100 text-amber-700 border-amber-300' },
  { value: 'detenido',          label: 'Detenido',        color: 'bg-gray-100 text-gray-700 border-gray-300' },
  { value: 'sin_senal',         label: 'Sin señal',       color: 'bg-red-100 text-red-700 border-red-300' },
  { value: 'sin_datos',         label: 'Sin datos',       color: 'bg-zinc-100 text-zinc-700 border-zinc-300' },
]

const TIPO_EQUIPAMIENTO_LABELS: Record<string, string> = {
  aljibe_agua:        'Aljibe agua',
  aljibe_combustible: 'Aljibe combustible',
  pluma_grua:         'Pluma / grúa',
  ampliroll:          'Ampliroll',
  grua_horquilla:     'Grúa horquilla',
  camioneta:          'Camioneta',
  tracto:             'Tracto',
  generico:           'Genérico',
}

export default function MapaFlotaPage() {
  useRequireAuth()

  const [posiciones, setPosiciones]   = useState<PosicionFlota[]>([])
  const [loading, setLoading]         = useState(true)
  const [error, setError]             = useState<string | null>(null)
  const [ultimoFetch, setUltimoFetch] = useState<Date | null>(null)

  // Filtros
  const [estadosSeleccionados, setEstadosSeleccionados] = useState<Set<EstadoPin>>(new Set())
  const [tiposSeleccionados, setTiposSeleccionados]     = useState<Set<string>>(new Set())
  const [clienteSeleccionado, setClienteSeleccionado]   = useState<string>('')
  const [busqueda, setBusqueda]                         = useState('')

  // Riesgo de cobro: arrendados/leasing sin señal GPS hace >24h
  const { data: flotaUnificada } = useFlotaDashboard()
  const arrendadosSinSenal = useMemo(() => {
    if (!flotaUnificada) return []
    return flotaUnificada.filter((a) =>
      (a.estado_comercial === 'arrendado' || a.estado_comercial === 'leasing')
      && a.gps_estado_pin === 'sin_senal_24h',
    ).sort((a, b) => (b.gps_minutos_offline ?? 0) - (a.gps_minutos_offline ?? 0))
  }, [flotaUnificada])

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

  // Aplica filtros
  const filtradas = useMemo(() => {
    const q = busqueda.trim().toLowerCase()
    return posiciones.filter((p) => {
      if (estadosSeleccionados.size > 0 && !estadosSeleccionados.has(p.estado_pin)) return false
      if (tiposSeleccionados.size > 0 && !tiposSeleccionados.has(p.tipo_equipamiento)) return false
      if (clienteSeleccionado && p.cliente !== clienteSeleccionado) return false
      if (q) {
        const hay =
          p.activo_codigo.toLowerCase().includes(q) ||
          (p.activo_patente ?? '').toLowerCase().includes(q) ||
          (p.activo_nombre  ?? '').toLowerCase().includes(q) ||
          (p.cliente        ?? '').toLowerCase().includes(q)
        if (!hay) return false
      }
      return true
    })
  }, [posiciones, estadosSeleccionados, tiposSeleccionados, clienteSeleccionado, busqueda])

  const stats = useMemo(() => {
    const acc = { en_ruta: 0, detenido_motor_on: 0, detenido: 0, sin_senal: 0, sin_datos: 0 }
    for (const p of filtradas) acc[p.estado_pin]++
    return acc
  }, [filtradas])

  // Opciones únicas para los selectores
  const tiposDisponibles = useMemo(() => {
    const set = new Set(posiciones.map((p) => p.tipo_equipamiento))
    return Array.from(set).sort()
  }, [posiciones])

  const clientesDisponibles = useMemo(() => {
    const set = new Set(posiciones.map((p) => p.cliente).filter((c): c is string => !!c))
    return Array.from(set).sort()
  }, [posiciones])

  const toggleEstado = (e: EstadoPin) => {
    const next = new Set(estadosSeleccionados)
    if (next.has(e)) next.delete(e); else next.add(e)
    setEstadosSeleccionados(next)
  }

  const toggleTipo = (t: string) => {
    const next = new Set(tiposSeleccionados)
    if (next.has(t)) next.delete(t); else next.add(t)
    setTiposSeleccionados(next)
  }

  const limpiarFiltros = () => {
    setEstadosSeleccionados(new Set())
    setTiposSeleccionados(new Set())
    setClienteSeleccionado('')
    setBusqueda('')
  }

  const hayFiltros = estadosSeleccionados.size > 0 || tiposSeleccionados.size > 0
                   || clienteSeleccionado !== '' || busqueda !== ''

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

      {/* Riesgo de cobro: arrendados/leasing sin senal GPS */}
      {arrendadosSinSenal.length > 0 && (
        <Card className="border-red-300 bg-red-50">
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2 text-red-800">
              <AlertTriangle className="h-5 w-5" />
              Riesgo de cobro: {arrendadosSinSenal.length} activos arrendados/leasing sin señal GPS
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-xs text-red-700 mb-3">
              Estos activos están facturados a cliente pero no podemos verificar ubicación. Coordinar con cliente para diagnóstico del tracker.
            </p>
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="text-left text-red-900 border-b border-red-200">
                    <th className="px-2 py-1">PPU / Activo</th>
                    <th className="px-2 py-1">Cliente</th>
                    <th className="px-2 py-1">Faena</th>
                    <th className="px-2 py-1 text-right">Días sin señal</th>
                    <th className="px-2 py-1 text-right">Batería</th>
                  </tr>
                </thead>
                <tbody>
                  {arrendadosSinSenal.slice(0, 10).map((a) => {
                    const dias = a.gps_minutos_offline ? Math.round(a.gps_minutos_offline / 1440) : null
                    const bat  = a.gps_bateria_pct
                    return (
                      <tr key={a.activo_id} className="border-b border-red-100 last:border-0 hover:bg-red-100/50">
                        <td className="px-2 py-1.5 font-mono">
                          {a.patente ?? a.activo_codigo}
                          <div className="text-[10px] text-gray-600 font-sans">{a.activo_nombre}</div>
                        </td>
                        <td className="px-2 py-1.5 text-gray-700">{a.contrato_cliente ?? '—'}</td>
                        <td className="px-2 py-1.5 text-[10px] text-gray-500">{a.faena_nombre ?? '—'}</td>
                        <td className="px-2 py-1.5 text-right tabular-nums font-bold">{dias != null ? `${dias}d` : '—'}</td>
                        <td className="px-2 py-1.5 text-right tabular-nums">
                          {bat != null ? (
                            <span className={bat < 10 ? 'text-red-700 font-bold' : bat < 30 ? 'text-amber-700' : 'text-gray-600'}>{bat}%</span>
                          ) : <span className="text-gray-400">—</span>}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
              {arrendadosSinSenal.length > 10 && (
                <p className="text-[10px] text-gray-500 mt-2 text-center">
                  Mostrando 10 de {arrendadosSinSenal.length}.
                </p>
              )}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Filtros */}
      <Card>
        <CardContent className="space-y-3 p-3">
          <div className="flex flex-wrap items-center gap-2">
            <Filter className="h-4 w-4 text-gray-500" />
            <span className="text-sm font-medium text-gray-700">Filtros</span>
            <div className="relative ml-2 flex-1 min-w-[180px] max-w-sm">
              <Search className="absolute left-2 top-2.5 h-4 w-4 text-gray-400" />
              <Input
                value={busqueda}
                onChange={(e) => setBusqueda(e.target.value)}
                placeholder="Código, patente, nombre, cliente..."
                className="pl-8 h-9"
              />
            </div>

            <select
              value={clienteSeleccionado}
              onChange={(e) => setClienteSeleccionado(e.target.value)}
              className="h-9 rounded-md border border-gray-200 bg-white px-2 text-sm">
              <option value="">Todos los clientes</option>
              {clientesDisponibles.map((c) => (
                <option key={c} value={c}>{c}</option>
              ))}
            </select>

            {hayFiltros && (
              <Button variant="ghost" size="sm" onClick={limpiarFiltros} className="gap-1">
                <X className="h-4 w-4" /> Limpiar
              </Button>
            )}

            <span className="ml-auto text-xs text-muted-foreground">
              Mostrando <b>{filtradas.length}</b> de {posiciones.length}
            </span>
          </div>

          <div className="flex flex-wrap gap-1.5">
            <span className="self-center text-xs text-gray-500">Estado:</span>
            {ESTADO_OPCIONES.map((opt) => {
              const sel = estadosSeleccionados.has(opt.value)
              return (
                <button
                  key={opt.value}
                  onClick={() => toggleEstado(opt.value)}
                  className={`rounded-full border px-2.5 py-0.5 text-xs font-medium transition-colors ${
                    sel ? opt.color : 'border-gray-200 bg-white text-gray-600 hover:bg-gray-50'
                  }`}>
                  {opt.label}
                </button>
              )
            })}
          </div>

          <div className="flex flex-wrap gap-1.5">
            <span className="self-center text-xs text-gray-500">Tipo equipo:</span>
            {tiposDisponibles.map((t) => {
              const sel = tiposSeleccionados.has(t)
              return (
                <button
                  key={t}
                  onClick={() => toggleTipo(t)}
                  className={`rounded-full border px-2.5 py-0.5 text-xs font-medium transition-colors ${
                    sel ? 'border-blue-300 bg-blue-100 text-blue-700' : 'border-gray-200 bg-white text-gray-600 hover:bg-gray-50'
                  }`}>
                  {TIPO_EQUIPAMIENTO_LABELS[t] ?? t}
                </button>
              )
            })}
          </div>
        </CardContent>
      </Card>

      {/* Contadores por estado (con filtros aplicados) */}
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
        <StatCard color="bg-green-50 border-green-200 text-green-700"
                  icon={<Activity className="h-4 w-4" />} label="En ruta" valor={stats.en_ruta} />
        <StatCard color="bg-amber-50 border-amber-200 text-amber-700"
                  icon={<Pause className="h-4 w-4" />} label="Motor ON" valor={stats.detenido_motor_on} />
        <StatCard color="bg-gray-50 border-gray-200 text-gray-700"
                  icon={<Pause className="h-4 w-4" />} label="Detenido" valor={stats.detenido} />
        <StatCard color="bg-red-50 border-red-200 text-red-700"
                  icon={<WifiOff className="h-4 w-4" />} label="Sin señal" valor={stats.sin_senal} />
        <StatCard color="bg-zinc-50 border-zinc-200 text-zinc-700"
                  icon={<HelpCircle className="h-4 w-4" />} label="Sin datos" valor={stats.sin_datos} />
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
          <div style={{ height: 'calc(100vh - 480px)', minHeight: 450 }}>
            {loading && posiciones.length === 0 ? (
              <div className="flex h-full items-center justify-center"><Spinner /></div>
            ) : (
              <MapaFlota posiciones={filtradas} />
            )}
          </div>
        </CardContent>
      </Card>

      {/* Tabla compacta — vehículos sin reportar (sobre el set filtrado) */}
      {(stats.sin_senal > 0 || stats.sin_datos > 0) && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <AlertTriangle className="h-4 w-4 text-amber-600" />
              Vehículos sin reportar ({stats.sin_senal + stats.sin_datos})
            </CardTitle>
          </CardHeader>
          <CardContent className="p-0">
            <div className="max-h-64 overflow-auto">
              <table className="w-full text-sm">
                <thead className="sticky top-0 bg-gray-50">
                  <tr>
                    <th className="px-3 py-2 text-left">Código</th>
                    <th className="px-3 py-2 text-left">Patente</th>
                    <th className="px-3 py-2 text-left">Cliente</th>
                    <th className="px-3 py-2 text-left">Estado</th>
                    <th className="px-3 py-2 text-left">Último reporte</th>
                    <th className="px-3 py-2 text-right">Km</th>
                    <th className="px-3 py-2 text-right">Horas</th>
                  </tr>
                </thead>
                <tbody>
                  {filtradas
                    .filter((p) => p.estado_pin === 'sin_senal' || p.estado_pin === 'sin_datos')
                    .map((p) => (
                      <tr key={p.activo_id} className="border-t">
                        <td className="px-3 py-2 font-medium">{p.activo_codigo}</td>
                        <td className="px-3 py-2 text-muted-foreground">{p.activo_patente ?? '—'}</td>
                        <td className="px-3 py-2 text-muted-foreground">{p.cliente ?? '—'}</td>
                        <td className="px-3 py-2">
                          <Badge variant={p.estado_pin === 'sin_senal' ? 'no_ejecutada' : 'default'}>
                            {p.estado_pin === 'sin_senal' ? 'Sin señal' : 'Sin datos'}
                          </Badge>
                        </td>
                        <td className="px-3 py-2 text-muted-foreground">
                          {p.ts_gps ? new Date(p.ts_gps).toLocaleString('es-CL') : '—'}
                        </td>
                        <td className="px-3 py-2 text-right">
                          {p.odometro_km != null ? `${p.odometro_km.toFixed(0)}` : '—'}
                        </td>
                        <td className="px-3 py-2 text-right">
                          {p.horometro_hrs != null ? `${p.horometro_hrs.toFixed(1)}` : '—'}
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
