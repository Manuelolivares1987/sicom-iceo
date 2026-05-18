'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, ShieldAlert, Inbox, History, MapPinOff, RefreshCw,
  AlertTriangle, Check, X, ExternalLink,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  cargarSugerenciasPendientes, validarSugerencia,
  cargarHistoricoEstado, cargarActivosFueraGeocercaAhora,
  formatHaceMin,
  ESTADO_LABELS, ESTADO_COLORS,
  type SugerenciaPendiente, type HistoricoEstadoRow, type ActivoFueraGeocerca,
  type EstadoComercial,
} from '@/lib/services/estado-flota'

const REFRESH_MS = 2 * 60_000

type Tab = 'pendientes' | 'historico' | 'fuera_ahora'

export default function EstadoFlotaPage() {
  useRequireAuth()
  const [tab, setTab] = useState<Tab>('pendientes')

  const [pendientes, setPendientes]   = useState<SugerenciaPendiente[]>([])
  const [historico, setHistorico]     = useState<HistoricoEstadoRow[]>([])
  const [fuera, setFuera]             = useState<ActivoFueraGeocerca[]>([])
  const [loading, setLoading]         = useState(true)
  const [error, setError]             = useState<string | null>(null)
  const [ultimoFetch, setUltimoFetch] = useState<Date | null>(null)

  const cargar = async () => {
    setError(null)
    try {
      const [p, h, f] = await Promise.all([
        cargarSugerenciasPendientes(),
        cargarHistoricoEstado({ limit: 100 }),
        cargarActivosFueraGeocercaAhora(),
      ])
      setPendientes(p); setHistorico(h); setFuera(f)
      setUltimoFetch(new Date())
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    cargar()
    const t = setInterval(cargar, REFRESH_MS)
    return () => clearInterval(t)
  }, [])

  const counts = useMemo(() => ({
    pendientes:  pendientes.length,
    fueraAhora:  fuera.filter((f) => f.fuera_de_geocerca).length,
    historico:   historico.length,
  }), [pendientes, fuera, historico])

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Link href="/dashboard/flota">
            <Button variant="ghost" size="sm" className="gap-1">
              <ArrowLeft className="h-4 w-4" /> Flota
            </Button>
          </Link>
          <div>
            <h1 className="flex items-center gap-2 text-2xl font-bold">
              <ShieldAlert className="h-6 w-6 text-blue-600" />
              Estado de Flota — Bandeja Planificador
            </h1>
            <p className="text-sm text-muted-foreground">
              {ultimoFetch
                ? `Actualizado ${ultimoFetch.toLocaleTimeString('es-CL')} — refresca cada 2 min`
                : 'Cargando...'}
            </p>
          </div>
        </div>
        <Button onClick={cargar} variant="outline" size="sm" className="gap-1" disabled={loading}>
          <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          Refrescar
        </Button>
      </div>

      {/* Tabs */}
      <div className="flex flex-wrap gap-2 border-b">
        <TabBtn icon={<Inbox className="h-4 w-4" />} label="Sugerencias pendientes" count={counts.pendientes}
                active={tab === 'pendientes'} onClick={() => setTab('pendientes')} highlight />
        <TabBtn icon={<MapPinOff className="h-4 w-4" />} label="Fuera de geocerca ahora" count={counts.fueraAhora}
                active={tab === 'fuera_ahora'} onClick={() => setTab('fuera_ahora')} />
        <TabBtn icon={<History className="h-4 w-4" />} label="Histórico cambios" count={counts.historico}
                active={tab === 'historico'} onClick={() => setTab('historico')} />
      </div>

      {error && (
        <Card className="border-red-200 bg-red-50">
          <CardContent className="flex items-center gap-2 p-4 text-sm text-red-700">
            <AlertTriangle className="h-4 w-4" /> {error}
          </CardContent>
        </Card>
      )}

      {loading && pendientes.length === 0 && historico.length === 0 && fuera.length === 0 ? (
        <div className="flex h-64 items-center justify-center"><Spinner /></div>
      ) : tab === 'pendientes' ? (
        <PendientesTab pendientes={pendientes} onActualizar={cargar} />
      ) : tab === 'fuera_ahora' ? (
        <FueraAhoraTab fuera={fuera} />
      ) : (
        <HistoricoTab historico={historico} />
      )}
    </div>
  )
}

function TabBtn({ icon, label, count, active, onClick, highlight }: {
  icon: React.ReactNode; label: string; count: number; active: boolean; onClick: () => void; highlight?: boolean
}) {
  return (
    <button
      onClick={onClick}
      className={`flex items-center gap-2 rounded-t-md px-3 py-2 text-sm transition-colors ${
        active
          ? 'border-b-2 border-blue-600 bg-blue-50 font-semibold text-blue-700'
          : 'text-gray-600 hover:bg-gray-50'
      }`}>
      {icon}
      <span>{label}</span>
      <span className={`rounded-full px-2 py-0.5 text-xs font-bold ${
        count > 0 && highlight ? 'bg-red-100 text-red-700' :
        active ? 'bg-blue-100 text-blue-700' : 'bg-gray-100 text-gray-600'
      }`}>{count}</span>
    </button>
  )
}

/* ────────────── Pendientes ────────────── */

function PendientesTab({ pendientes, onActualizar }: {
  pendientes: SugerenciaPendiente[]; onActualizar: () => void
}) {
  if (pendientes.length === 0) {
    return (
      <Card className="border-green-200 bg-green-50">
        <CardContent className="flex flex-col items-center gap-2 p-8 text-center text-green-700">
          <Check className="h-8 w-8" />
          <div className="font-semibold">Sin sugerencias pendientes</div>
          <div className="text-sm">Todos los activos están dentro de su geocerca esperada.</div>
        </CardContent>
      </Card>
    )
  }
  return (
    <div className="space-y-2">
      {pendientes.map((s) => <SugerenciaCard key={s.sugerencia_id} s={s} onAct={onActualizar} />)}
    </div>
  )
}

function SugerenciaCard({ s, onAct }: { s: SugerenciaPendiente; onAct: () => void }) {
  const [comentario, setComentario] = useState('')
  const [enviando, setEnviando]     = useState<'aprobar' | 'rechazar' | null>(null)
  const [error, setError]           = useState<string | null>(null)

  const handleAccion = async (accion: 'aprobar' | 'rechazar') => {
    setEnviando(accion); setError(null)
    try {
      await validarSugerencia(s.sugerencia_id, accion, comentario || undefined)
      onAct()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setEnviando(null)
    }
  }

  return (
    <Card>
      <CardContent className="p-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="flex-1 min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <span className="font-semibold">{s.activo_codigo}</span>
              {s.activo_patente && <span className="text-sm text-gray-500">· {s.activo_patente}</span>}
              {s.cliente && <span className="text-sm text-gray-500">· {s.cliente}</span>}
              {s.contrato_codigo && <span className="text-xs text-gray-400">({s.contrato_codigo})</span>}
            </div>
            <div className="mt-2 flex flex-wrap items-center gap-2 text-sm">
              <EstadoBadge e={s.estado_anterior} />
              <span className="text-gray-400">→</span>
              <EstadoBadge e={s.estado_sugerido} />
            </div>
            <div className="mt-2 text-sm text-gray-700">{s.razon}</div>
            <div className="mt-1 flex flex-wrap gap-3 text-xs text-gray-500">
              {s.geocerca_nombre && <span>Geocerca esperada: <b>{s.geocerca_nombre}</b></span>}
              {s.distancia_a_geocerca_m != null && (
                <span>Distancia: <b>{(s.distancia_a_geocerca_m / 1000).toFixed(1)} km</b></span>
              )}
              {s.minutos_fuera != null && <span>Fuera: <b>{s.minutos_fuera} min</b></span>}
              <span>Sugerida {formatHaceMin(s.minutos_desde_sugerencia)}</span>
            </div>
          </div>
        </div>

        <div className="mt-3 grid gap-2 sm:grid-cols-2">
          <textarea
            value={comentario}
            onChange={(e) => setComentario(e.target.value)}
            placeholder="Comentario (opcional)"
            className="rounded border border-gray-200 px-2 py-1.5 text-sm focus:border-blue-500 focus:outline-none"
            rows={2}
          />
          <div className="flex items-end justify-end gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => handleAccion('rechazar')}
              disabled={enviando !== null}>
              <X className="mr-1 h-4 w-4" />
              {enviando === 'rechazar' ? 'Rechazando...' : 'Rechazar'}
            </Button>
            <Button
              size="sm"
              className="bg-green-600 hover:bg-green-700"
              onClick={() => handleAccion('aprobar')}
              disabled={enviando !== null}>
              <Check className="mr-1 h-4 w-4" />
              {enviando === 'aprobar' ? 'Aprobando...' : 'Aprobar y cambiar estado'}
            </Button>
          </div>
        </div>

        {error && (
          <div className="mt-2 rounded border border-red-200 bg-red-50 p-2 text-sm text-red-700">
            <AlertTriangle className="inline h-4 w-4" /> {error}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

/* ────────────── Fuera de geocerca ────────────── */

function FueraAhoraTab({ fuera }: { fuera: ActivoFueraGeocerca[] }) {
  const fueraReal = fuera.filter((f) => f.fuera_de_geocerca)
  if (fueraReal.length === 0) {
    return (
      <Card className="border-green-200 bg-green-50">
        <CardContent className="flex flex-col items-center gap-2 p-8 text-center text-green-700">
          <Check className="h-8 w-8" />
          <div className="font-semibold">Todos los activos arrendados están en su geocerca</div>
        </CardContent>
      </Card>
    )
  }
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">
          Activos arrendados fuera de su geocerca ({fueraReal.length})
        </CardTitle>
      </CardHeader>
      <CardContent className="p-0">
        <div className="max-h-[60vh] overflow-auto">
          <table className="w-full text-sm">
            <thead className="sticky top-0 bg-gray-50">
              <tr>
                <th className="px-3 py-2 text-left">Activo</th>
                <th className="px-3 py-2 text-left">Cliente</th>
                <th className="px-3 py-2 text-left">Geocerca esperada</th>
                <th className="px-3 py-2 text-left">Estado</th>
                <th className="px-3 py-2 text-right">Distancia</th>
              </tr>
            </thead>
            <tbody>
              {fueraReal
                .sort((a, b) => (b.distancia_m ?? 0) - (a.distancia_m ?? 0))
                .map((f) => (
                <tr key={f.activo_id} className="border-t">
                  <td className="px-3 py-2 font-medium">
                    {f.activo_codigo}
                    {f.activo_patente && <span className="text-gray-500"> · {f.activo_patente}</span>}
                  </td>
                  <td className="px-3 py-2 text-gray-600">
                    {f.cliente ?? '—'}
                    {f.contrato_codigo && <span className="block text-xs text-gray-400">{f.contrato_codigo}</span>}
                  </td>
                  <td className="px-3 py-2 text-gray-600">{f.geocerca_nombre ?? '(sin geocerca)'}</td>
                  <td className="px-3 py-2">
                    <EstadoBadge e={f.estado_comercial} />
                  </td>
                  <td className="px-3 py-2 text-right font-mono">
                    {f.distancia_m != null
                      ? `${(f.distancia_m / 1000).toFixed(1)} km`
                      : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </CardContent>
    </Card>
  )
}

/* ────────────── Histórico ────────────── */

function HistoricoTab({ historico }: { historico: HistoricoEstadoRow[] }) {
  if (historico.length === 0) {
    return (
      <Card><CardContent className="p-8 text-center text-sm text-muted-foreground">
        Sin cambios de estado registrados aún.
      </CardContent></Card>
    )
  }
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Últimos {historico.length} cambios de estado</CardTitle>
      </CardHeader>
      <CardContent className="p-0">
        <div className="max-h-[70vh] overflow-auto">
          <table className="w-full text-xs">
            <thead className="sticky top-0 bg-gray-50">
              <tr>
                <th className="px-2 py-2 text-left">Fecha</th>
                <th className="px-2 py-2 text-left">Activo</th>
                <th className="px-2 py-2 text-left">Cliente</th>
                <th className="px-2 py-2 text-left">Cambio</th>
                <th className="px-2 py-2 text-left">Origen</th>
                <th className="px-2 py-2 text-right">Duración previa</th>
                <th className="px-2 py-2 text-right">Horómetro</th>
                <th className="px-2 py-2 text-right">Km</th>
              </tr>
            </thead>
            <tbody>
              {historico.map((h) => (
                <tr key={h.id} className="border-t">
                  <td className="px-2 py-1.5 whitespace-nowrap text-gray-500">
                    {new Date(h.cambio_at).toLocaleString('es-CL')}
                  </td>
                  <td className="px-2 py-1.5 font-medium">
                    {h.activo_codigo}
                    {h.activo_patente && <span className="text-gray-500"> · {h.activo_patente}</span>}
                  </td>
                  <td className="px-2 py-1.5 text-gray-600">{h.cliente ?? '—'}</td>
                  <td className="px-2 py-1.5">
                    <EstadoBadge e={h.estado_anterior} />
                    <span className="mx-1 text-gray-400">→</span>
                    <EstadoBadge e={h.estado_nuevo} />
                  </td>
                  <td className="px-2 py-1.5">
                    <span className="rounded bg-gray-100 px-1.5 py-0.5 text-[10px] font-mono">
                      {h.origen}
                    </span>
                  </td>
                  <td className="px-2 py-1.5 text-right text-gray-500">
                    {h.duracion_estado_anterior_horas != null
                      ? `${h.duracion_estado_anterior_horas.toFixed(1)} h`
                      : '—'}
                  </td>
                  <td className="px-2 py-1.5 text-right font-mono">
                    {h.horometro != null ? h.horometro.toFixed(0) : '—'}
                  </td>
                  <td className="px-2 py-1.5 text-right font-mono">
                    {h.kilometraje != null ? h.kilometraje.toFixed(0) : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </CardContent>
    </Card>
  )
}

function EstadoBadge({ e }: { e: EstadoComercial | null }) {
  if (e == null) {
    return <span className="rounded border border-gray-200 bg-gray-50 px-1.5 py-0.5 text-[10px] font-bold text-gray-500">—</span>
  }
  return (
    <span className={`rounded border px-1.5 py-0.5 text-[10px] font-bold ${ESTADO_COLORS[e]}`}>
      {ESTADO_LABELS[e].toUpperCase()}
    </span>
  )
}
