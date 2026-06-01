'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, CalendarCheck, MapPin, MapPinOff, Wand2, Check,
  AlertTriangle, Save, Lock,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  usePropuestaCierre, useContratosActivos, useConfirmarCierre,
} from '@/hooks/use-cierre-diario'
import {
  ESTADO_CODIGO_LABELS, ESTADO_CODIGO_COLORS, ESTADO_CODIGO_ORDEN,
  frescuraGps,
  type EstadoCodigo, type CierreItem,
} from '@/lib/services/cierre-diario'
import { todayISO } from '@/lib/utils'

type Edit = { estado_codigo: EstadoCodigo; contrato_id: string | null }

export default function CierreDiarioPage() {
  useRequireAuth()
  const [fecha, setFecha] = useState(todayISO())
  const [edits, setEdits] = useState<Record<string, Edit>>({})
  const [okMsg, setOkMsg] = useState<string | null>(null)

  const { data: propuesta = [], isLoading } = usePropuestaCierre(fecha)
  const { data: contratos = [] } = useContratosActivos()
  const confirmar = useConfirmarCierre()

  // Inicializar/resetear edits cuando cambia la propuesta (default = sugerido)
  useEffect(() => {
    const init: Record<string, Edit> = {}
    for (const r of propuesta) {
      init[r.activo_id] = {
        estado_codigo: (r.estado_dia_actual ?? r.estado_sugerido ?? r.estado_previo ?? 'D') as EstadoCodigo,
        contrato_id: r.contrato_id,
      }
    }
    setEdits(init)
    setOkMsg(null)
  }, [propuesta])

  const setEstado = (id: string, estado: EstadoCodigo) =>
    setEdits((e) => ({ ...e, [id]: { ...e[id], estado_codigo: estado } }))
  const setContrato = (id: string, contrato: string | null) =>
    setEdits((e) => ({ ...e, [id]: { ...e[id], contrato_id: contrato } }))

  const usarSugeridos = () =>
    setEdits((prev) => {
      const next = { ...prev }
      for (const r of propuesta) {
        if (r.estado_sugerido) next[r.activo_id] = { ...next[r.activo_id], estado_codigo: r.estado_sugerido }
      }
      return next
    })

  const stats = useMemo(() => {
    let cambian = 0, confirmados = 0
    for (const r of propuesta) {
      if (r.ya_confirmado) confirmados++
      const ed = edits[r.activo_id]
      if (ed && ed.estado_codigo !== (r.estado_previo ?? ed.estado_codigo)) cambian++
    }
    return { total: propuesta.length, cambian, confirmados }
  }, [propuesta, edits])

  const handleConfirmar = async () => {
    const items: CierreItem[] = propuesta.map((r) => ({
      activo_id: r.activo_id,
      estado_codigo: edits[r.activo_id]?.estado_codigo ?? (r.estado_sugerido ?? 'D'),
      contrato_id: edits[r.activo_id]?.contrato_id ?? null,
    }))
    const res = await confirmar.mutateAsync({ fecha, items })
    setOkMsg(`Día ${fecha} confirmado: ${res.confirmados} equipos. Estado comercial y contratos propagados.`)
  }

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
              <CalendarCheck className="h-6 w-6 text-blue-600" />
              Cierre diario de flota
            </h1>
            <p className="text-sm text-muted-foreground">
              Semilla = día anterior · sugerido por geocerca · revisa, ajusta y confirma
            </p>
          </div>
        </div>
        <div className="flex items-end gap-2">
          <div>
            <label className="block text-[10px] uppercase text-gray-400">Día a cerrar</label>
            <input
              type="date"
              className="h-9 rounded border border-gray-300 px-2 text-sm"
              value={fecha}
              onChange={(e) => setFecha(e.target.value)}
            />
          </div>
        </div>
      </div>

      {/* Barra de acción */}
      <Card>
        <CardContent className="flex flex-wrap items-center justify-between gap-3 p-4">
          <div className="flex flex-wrap gap-4 text-sm">
            <span className="text-gray-600">Equipos: <b>{stats.total}</b></span>
            <span className="text-amber-700">Cambian vs día previo: <b>{stats.cambian}</b></span>
            <span className="text-green-700">Ya confirmados: <b>{stats.confirmados}</b></span>
          </div>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" className="gap-1" onClick={usarSugeridos}>
              <Wand2 className="h-4 w-4" /> Usar sugeridos en todos
            </Button>
            <Button
              size="sm"
              className="gap-1 bg-green-600 hover:bg-green-700"
              onClick={handleConfirmar}
              disabled={confirmar.isPending || isLoading || propuesta.length === 0}
            >
              <Save className="h-4 w-4" />
              {confirmar.isPending ? 'Confirmando...' : `Confirmar día ${fecha}`}
            </Button>
          </div>
        </CardContent>
      </Card>

      {okMsg && (
        <Card className="border-green-200 bg-green-50">
          <CardContent className="flex items-center gap-2 p-3 text-sm text-green-800">
            <Check className="h-4 w-4" /> {okMsg}
          </CardContent>
        </Card>
      )}
      {confirmar.isError && (
        <Card className="border-red-200 bg-red-50">
          <CardContent className="flex items-center gap-2 p-3 text-sm text-red-700">
            <AlertTriangle className="h-4 w-4" /> {(confirmar.error as Error).message}
          </CardContent>
        </Card>
      )}

      {isLoading ? (
        <div className="flex h-64 items-center justify-center"><Spinner /></div>
      ) : (
        <Card>
          <CardContent className="p-0">
            <div className="max-h-[68vh] overflow-auto">
              <table className="w-full text-sm">
                <thead className="sticky top-0 z-10 bg-gray-50 text-left text-xs uppercase text-gray-500">
                  <tr>
                    <th className="px-3 py-2">Patente</th>
                    <th className="px-3 py-2">Equipamiento</th>
                    <th className="px-3 py-2">Ubicación (GPS)</th>
                    <th className="px-3 py-2 text-center">Previo</th>
                    <th className="px-3 py-2 text-center">Sugerido</th>
                    <th className="px-3 py-2">Estado del día</th>
                    <th className="px-3 py-2">Contrato</th>
                    <th className="px-3 py-2 text-center"></th>
                  </tr>
                </thead>
                <tbody>
                  {propuesta.map((r) => {
                    const ed = edits[r.activo_id]
                    const gps = frescuraGps(r.gps_ts)
                    const cambio = ed && r.estado_previo && ed.estado_codigo !== r.estado_previo
                    return (
                      <tr key={r.activo_id} className={`border-t ${cambio ? 'bg-amber-50/40' : ''}`}>
                        <td className="px-3 py-1.5 font-mono font-semibold text-blue-700">
                          {r.patente ?? r.codigo ?? '—'}
                        </td>
                        <td className="px-3 py-1.5 text-gray-600 max-w-[160px] truncate">
                          {r.equipamiento ?? '—'}
                        </td>
                        <td className="px-3 py-1.5">
                          <div className="flex items-center gap-1">
                            {r.geocerca_nombre ? (
                              <MapPin className="h-3.5 w-3.5 text-green-600" />
                            ) : (
                              <MapPinOff className="h-3.5 w-3.5 text-gray-400" />
                            )}
                            <span className={r.geocerca_nombre ? '' : 'text-gray-400 italic'}>
                              {r.geocerca_nombre ?? 'fuera de geocerca'}
                            </span>
                          </div>
                          <span className={`text-[10px] ${gps.viejo ? 'text-red-500' : 'text-gray-400'}`}>
                            GPS {gps.texto}
                          </span>
                        </td>
                        <td className="px-3 py-1.5 text-center">
                          <EstadoChip e={r.estado_previo} />
                        </td>
                        <td className="px-3 py-1.5 text-center">
                          <EstadoChip e={r.estado_sugerido} />
                        </td>
                        <td className="px-3 py-1.5">
                          <select
                            className="h-8 w-full rounded border border-gray-300 px-1 text-sm"
                            value={ed?.estado_codigo ?? ''}
                            onChange={(e) => setEstado(r.activo_id, e.target.value as EstadoCodigo)}
                          >
                            {ESTADO_CODIGO_ORDEN.map((c) => (
                              <option key={c} value={c}>{c} · {ESTADO_CODIGO_LABELS[c]}</option>
                            ))}
                          </select>
                        </td>
                        <td className="px-3 py-1.5">
                          <select
                            className="h-8 w-full max-w-[200px] rounded border border-gray-300 px-1 text-sm"
                            value={ed?.contrato_id ?? ''}
                            onChange={(e) => setContrato(r.activo_id, e.target.value || null)}
                          >
                            <option value="">— sin contrato —</option>
                            {contratos.map((c) => (
                              <option key={c.id} value={c.id}>
                                {c.codigo}{c.cliente ? ` · ${c.cliente}` : ''}
                              </option>
                            ))}
                          </select>
                        </td>
                        <td className="px-3 py-1.5 text-center">
                          {r.ya_confirmado && (
                            <span title="Ya confirmado para este día">
                              <Lock className="mx-auto h-3.5 w-3.5 text-green-600" />
                            </span>
                          )}
                        </td>
                      </tr>
                    )
                  })}
                  {propuesta.length === 0 && (
                    <tr>
                      <td colSpan={8} className="py-8 text-center text-gray-400">
                        Sin equipos de flota para esta fecha.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}

function EstadoChip({ e }: { e: EstadoCodigo | null }) {
  if (!e) return <span className="text-[10px] text-gray-300">—</span>
  return (
    <span
      className={`inline-block rounded border px-1.5 py-0.5 text-[10px] font-bold ${ESTADO_CODIGO_COLORS[e]}`}
      title={ESTADO_CODIGO_LABELS[e]}
    >
      {e}
    </span>
  )
}
