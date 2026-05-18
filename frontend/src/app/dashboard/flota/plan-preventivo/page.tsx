'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, CalendarClock, RefreshCw, AlertTriangle, Filter, Search, X,
  Wrench, ChevronDown, ChevronUp,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  cargarPautasEstado, formatRestante, formatUltimo,
  ESTADO_LABELS, ESTADO_COLORS,
  type EstadoPauta, type PautaEstadoRow,
} from '@/lib/services/plan-preventivo'

const REFRESH_MS = 5 * 60_000  // 5 min

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

export default function PlanPreventivoPage() {
  useRequireAuth()
  const [rows, setRows]       = useState<PautaEstadoRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError]     = useState<string | null>(null)
  const [ultimoFetch, setUltimoFetch] = useState<Date | null>(null)

  // Filtros
  const [estadosSel, setEstadosSel]       = useState<Set<EstadoPauta>>(new Set<EstadoPauta>(['vencida', 'critica']))
  const [tiposSel, setTiposSel]           = useState<Set<string>>(new Set())
  const [activoSel, setActivoSel]         = useState<string>('')
  const [busqueda, setBusqueda]           = useState('')
  const [agruparActivo, setAgruparActivo] = useState(true)

  const cargar = async () => {
    setError(null)
    try {
      const data = await cargarPautasEstado()
      setRows(data)
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

  const stats = useMemo(() => {
    const acc: Record<EstadoPauta, number> = {
      vencida: 0, critica: 0, proxima: 0, al_dia: 0, sin_historico: 0,
    }
    for (const r of rows) acc[r.estado_pauta]++
    return acc
  }, [rows])

  const tiposDisponibles = useMemo(
    () => Array.from(new Set(rows.map((r) => r.tipo_equipamiento))).sort(),
    [rows]
  )

  const activosDisponibles = useMemo(() => {
    const set = new Map<string, string>()
    for (const r of rows) {
      const label = `${r.activo_codigo}${r.activo_patente ? ' · ' + r.activo_patente : ''}`
      set.set(r.activo_id, label)
    }
    return Array.from(set.entries()).sort((a, b) => a[1].localeCompare(b[1]))
  }, [rows])

  const filtradas = useMemo(() => {
    const q = busqueda.trim().toLowerCase()
    return rows.filter((r) => {
      if (estadosSel.size > 0 && !estadosSel.has(r.estado_pauta)) return false
      if (tiposSel.size > 0 && !tiposSel.has(r.tipo_equipamiento)) return false
      if (activoSel && r.activo_id !== activoSel) return false
      if (q) {
        const hay =
          r.activo_codigo.toLowerCase().includes(q) ||
          (r.activo_patente ?? '').toLowerCase().includes(q) ||
          r.pauta_nombre.toLowerCase().includes(q)
        if (!hay) return false
      }
      return true
    })
  }, [rows, estadosSel, tiposSel, activoSel, busqueda])

  // Agrupado por activo
  const filtradasAgrupadas = useMemo(() => {
    if (!agruparActivo) return null
    const grupos = new Map<string, PautaEstadoRow[]>()
    for (const r of filtradas) {
      if (!grupos.has(r.activo_id)) grupos.set(r.activo_id, [])
      grupos.get(r.activo_id)!.push(r)
    }
    return Array.from(grupos.entries())
  }, [filtradas, agruparActivo])

  const toggleEstado = (e: EstadoPauta) => {
    const n = new Set(estadosSel)
    if (n.has(e)) n.delete(e); else n.add(e)
    setEstadosSel(n)
  }
  const toggleTipo = (t: string) => {
    const n = new Set(tiposSel)
    if (n.has(t)) n.delete(t); else n.add(t)
    setTiposSel(n)
  }
  const limpiar = () => {
    setEstadosSel(new Set())
    setTiposSel(new Set())
    setActivoSel('')
    setBusqueda('')
  }

  const hayFiltros = estadosSel.size > 0 || tiposSel.size > 0 || activoSel || busqueda

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
              <CalendarClock className="h-6 w-6 text-blue-600" />
              Plan Preventivo
            </h1>
            <p className="text-sm text-muted-foreground">
              {ultimoFetch
                ? `Actualizado ${ultimoFetch.toLocaleTimeString('es-CL')} — refresca cada 5 min`
                : 'Cargando...'}
            </p>
          </div>
        </div>
        <Button onClick={cargar} variant="outline" size="sm" className="gap-1" disabled={loading}>
          <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          Refrescar
        </Button>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
        <StatBox color="bg-red-50 text-red-700 border-red-200"
                 label="Vencidas" v={stats.vencida} onClick={() => setEstadosSel(new Set<EstadoPauta>(['vencida']))} />
        <StatBox color="bg-amber-50 text-amber-700 border-amber-200"
                 label="Críticas" v={stats.critica} onClick={() => setEstadosSel(new Set<EstadoPauta>(['critica']))} />
        <StatBox color="bg-blue-50 text-blue-700 border-blue-200"
                 label="Próximas" v={stats.proxima} onClick={() => setEstadosSel(new Set<EstadoPauta>(['proxima']))} />
        <StatBox color="bg-green-50 text-green-700 border-green-200"
                 label="Al día" v={stats.al_dia} onClick={() => setEstadosSel(new Set<EstadoPauta>(['al_dia']))} />
        <StatBox color="bg-zinc-50 text-zinc-700 border-zinc-200"
                 label="Sin histórico" v={stats.sin_historico} onClick={() => setEstadosSel(new Set<EstadoPauta>(['sin_historico']))} />
      </div>

      {/* Filtros */}
      <Card>
        <CardContent className="space-y-3 p-3">
          <div className="flex flex-wrap items-center gap-2">
            <Filter className="h-4 w-4 text-gray-500" />
            <span className="text-sm font-medium">Filtros</span>
            <div className="relative ml-2 flex-1 min-w-[180px] max-w-sm">
              <Search className="absolute left-2 top-2.5 h-4 w-4 text-gray-400" />
              <Input
                value={busqueda}
                onChange={(e) => setBusqueda(e.target.value)}
                placeholder="Código, patente, nombre pauta..."
                className="pl-8 h-9"
              />
            </div>
            <select
              value={activoSel}
              onChange={(e) => setActivoSel(e.target.value)}
              className="h-9 rounded-md border border-gray-200 bg-white px-2 text-sm max-w-xs">
              <option value="">Todos los activos</option>
              {activosDisponibles.map(([id, label]) => (
                <option key={id} value={id}>{label}</option>
              ))}
            </select>
            <label className="flex items-center gap-1 text-xs text-gray-600 ml-2">
              <input type="checkbox" checked={agruparActivo} onChange={(e) => setAgruparActivo(e.target.checked)} />
              Agrupar por activo
            </label>
            {hayFiltros && (
              <Button variant="ghost" size="sm" onClick={limpiar} className="gap-1">
                <X className="h-4 w-4" /> Limpiar
              </Button>
            )}
            <span className="ml-auto text-xs text-muted-foreground">
              Mostrando <b>{filtradas.length}</b> de {rows.length}
            </span>
          </div>

          <div className="flex flex-wrap gap-1.5">
            <span className="self-center text-xs text-gray-500">Estado:</span>
            {(['vencida', 'critica', 'proxima', 'al_dia', 'sin_historico'] as EstadoPauta[]).map((e) => {
              const sel = estadosSel.has(e)
              return (
                <button
                  key={e}
                  onClick={() => toggleEstado(e)}
                  className={`rounded-full border px-2.5 py-0.5 text-xs font-medium transition-colors ${
                    sel ? ESTADO_COLORS[e] : 'border-gray-200 bg-white text-gray-600 hover:bg-gray-50'
                  }`}>
                  {ESTADO_LABELS[e]}
                </button>
              )
            })}
          </div>

          <div className="flex flex-wrap gap-1.5">
            <span className="self-center text-xs text-gray-500">Tipo:</span>
            {tiposDisponibles.map((t) => {
              const sel = tiposSel.has(t)
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

      {error && (
        <Card className="border-red-200 bg-red-50">
          <CardContent className="flex items-center gap-2 p-4 text-sm text-red-700">
            <AlertTriangle className="h-4 w-4" /> {error}
          </CardContent>
        </Card>
      )}

      {/* Tabla */}
      <Card>
        <CardContent className="p-0">
          {loading && rows.length === 0 ? (
            <div className="flex h-32 items-center justify-center"><Spinner /></div>
          ) : filtradas.length === 0 ? (
            <div className="p-6 text-center text-sm text-muted-foreground">
              Sin pautas que cumplan los filtros.
            </div>
          ) : agruparActivo && filtradasAgrupadas ? (
            <div className="divide-y">
              {filtradasAgrupadas.map(([activoId, pautas]) => (
                <GrupoActivo key={activoId} pautas={pautas} />
              ))}
            </div>
          ) : (
            <TablaPlana rows={filtradas} />
          )}
        </CardContent>
      </Card>
    </div>
  )
}

function StatBox({ color, label, v, onClick }: { color: string; label: string; v: number; onClick?: () => void }) {
  return (
    <button
      onClick={onClick}
      className={`flex items-center justify-between rounded-lg border px-3 py-2 transition-shadow hover:shadow-md ${color}`}>
      <span className="text-xs font-medium">{label}</span>
      <span className="text-2xl font-bold">{v}</span>
    </button>
  )
}

function EstadoBadge({ e }: { e: EstadoPauta }) {
  return (
    <span className={`rounded-full border px-2 py-0.5 text-[10px] font-bold ${ESTADO_COLORS[e]}`}>
      {ESTADO_LABELS[e].toUpperCase()}
    </span>
  )
}

function TablaPlana({ rows }: { rows: PautaEstadoRow[] }) {
  return (
    <div className="max-h-[70vh] overflow-auto">
      <table className="w-full text-xs">
        <thead className="sticky top-0 bg-gray-50">
          <tr>
            <th className="px-2 py-2 text-left">Activo</th>
            <th className="px-2 py-2 text-left">Tipo</th>
            <th className="px-2 py-2 text-left">Pauta</th>
            <th className="px-2 py-2 text-left">Estado</th>
            <th className="px-2 py-2 text-left">Último servicio</th>
            <th className="px-2 py-2 text-left">Restante (h / km / d)</th>
            <th className="px-2 py-2 text-right">Acción</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={`${r.activo_id}-${r.pauta_id}`} className="border-t">
              <td className="px-2 py-1.5 font-medium">
                {r.activo_codigo}
                {r.activo_patente && <span className="text-gray-500"> · {r.activo_patente}</span>}
              </td>
              <td className="px-2 py-1.5 text-gray-600">
                {TIPO_EQUIPAMIENTO_LABELS[r.tipo_equipamiento] ?? r.tipo_equipamiento}
              </td>
              <td className="px-2 py-1.5">{r.pauta_nombre}</td>
              <td className="px-2 py-1.5"><EstadoBadge e={r.estado_pauta} /></td>
              <td className="px-2 py-1.5 text-gray-500">{formatUltimo(r)}</td>
              <td className="px-2 py-1.5 font-mono">{formatRestante(r)}</td>
              <td className="px-2 py-1.5 text-right">
                {(r.estado_pauta === 'vencida' || r.estado_pauta === 'critica') && (
                  <button
                    title="Crear OT preventiva (proximo lanzamiento)"
                    disabled
                    className="rounded border border-blue-200 bg-blue-50 px-2 py-0.5 text-blue-700 opacity-50 cursor-not-allowed">
                    <Wrench className="inline h-3 w-3" /> Crear OT
                  </button>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function GrupoActivo({ pautas }: { pautas: PautaEstadoRow[] }) {
  const [open, setOpen] = useState(true)
  const a = pautas[0]
  const peor = pautas[0].estado_pauta
  const vencidas = pautas.filter((p) => p.estado_pauta === 'vencida').length
  const criticas = pautas.filter((p) => p.estado_pauta === 'critica').length

  return (
    <div>
      <button
        onClick={() => setOpen(!open)}
        className="flex w-full items-center justify-between gap-3 bg-gray-50 px-4 py-2 hover:bg-gray-100">
        <div className="flex items-center gap-2">
          {open ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
          <span className="font-semibold">{a.activo_codigo}</span>
          {a.activo_patente && <span className="text-xs text-gray-500">{a.activo_patente}</span>}
          <span className="text-xs text-gray-500">·</span>
          <span className="text-xs text-gray-500">
            {TIPO_EQUIPAMIENTO_LABELS[a.tipo_equipamiento] ?? a.tipo_equipamiento}
          </span>
          {a.horas_actuales != null && (
            <span className="text-xs text-gray-500">· {a.horas_actuales.toFixed(0)}h</span>
          )}
          {a.km_actuales != null && (
            <span className="text-xs text-gray-500">· {a.km_actuales.toFixed(0)}km</span>
          )}
        </div>
        <div className="flex items-center gap-2 text-xs">
          {vencidas > 0 && <span className="rounded-full bg-red-100 px-2 py-0.5 text-red-700 font-semibold">{vencidas} vencidas</span>}
          {criticas > 0 && <span className="rounded-full bg-amber-100 px-2 py-0.5 text-amber-700 font-semibold">{criticas} críticas</span>}
          <span className="text-gray-500">{pautas.length} pautas</span>
        </div>
      </button>
      {open && (
        <table className="w-full text-xs">
          <tbody>
            {pautas.map((r) => (
              <tr key={r.pauta_id} className="border-t">
                <td className="px-4 py-1.5 w-2/5">{r.pauta_nombre}</td>
                <td className="px-2 py-1.5 w-24"><EstadoBadge e={r.estado_pauta} /></td>
                <td className="px-2 py-1.5 text-gray-500">{formatUltimo(r)}</td>
                <td className="px-2 py-1.5 font-mono">{formatRestante(r)}</td>
                <td className="px-2 py-1.5 text-right w-24">
                  {(r.estado_pauta === 'vencida' || r.estado_pauta === 'critica') && (
                    <button
                      title="Crear OT preventiva (proximo lanzamiento)"
                      disabled
                      className="rounded border border-blue-200 bg-blue-50 px-2 py-0.5 text-blue-700 opacity-50 cursor-not-allowed">
                      <Wrench className="inline h-3 w-3" /> Crear OT
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  )
}
