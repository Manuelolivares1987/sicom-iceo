'use client'

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { AlertTriangle, CheckCircle2, Satellite } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { getConciliacionUbicacion, type UbicacionCamion } from '@/lib/services/costos-operacion'

// ============================================================================
// ¿Dónde está cada camión? (MIG602)
// ----------------------------------------------------------------------------
// Tres fuentes lado a lado: la ficha (faena asignada), el estado diario
// (última ubicación escrita) y el GPS (geocerca más cercana hoy). El costo por
// faena usa el GPS; donde no coinciden, la ficha o el estado diario están
// desactualizados y hay que corregirlos.
// ============================================================================

const fmtF = (iso: string | null) => iso
  ? new Date(iso.slice(0, 10) + 'T12:00:00').toLocaleDateString('es-CL', { day: '2-digit', month: 'short' }) : ''

function difiere(u: UbicacionCamion) {
  if (!u.grupo_gps) return false
  return u.grupo_ficha !== u.grupo_gps || (u.grupo_estado != null && u.grupo_estado !== u.grupo_gps)
}

export function ConciliacionUbicacion() {
  const [soloDiferencias, setSoloDiferencias] = useState(true)
  const { data, isLoading, error } = useQuery({
    queryKey: ['flota-ubicacion-conciliacion'],
    queryFn: getConciliacionUbicacion,
    staleTime: 5 * 60_000,
  })

  const filas = useMemo(() => {
    const d = [...(data ?? [])].sort((a, b) => (a.patente ?? '').localeCompare(b.patente ?? ''))
    return soloDiferencias ? d.filter(difiere) : d
  }, [data, soloDiferencias])
  const nDif = (data ?? []).filter(difiere).length

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex flex-wrap items-center gap-2 text-base">
          <Satellite className="h-4 w-4" /> ¿Dónde está cada camión? Ficha vs estado diario vs GPS
          {data && (
            <span className={`rounded px-2 py-0.5 text-xs font-medium ${nDif ? 'bg-amber-100 text-amber-800' : 'bg-green-100 text-green-800'}`}>
              {nDif} con diferencias
            </span>
          )}
          <label className="ml-auto flex items-center gap-1.5 text-xs font-normal text-gray-600">
            <input type="checkbox" checked={soloDiferencias} onChange={(e) => setSoloDiferencias(e.target.checked)} />
            Solo los que no coinciden
          </label>
        </CardTitle>
      </CardHeader>
      <CardContent className="overflow-x-auto p-0">
        {isLoading && <div className="flex justify-center py-8"><Spinner /></div>}
        {error && <div className="p-4 text-sm text-red-700">{(error as Error).message}</div>}
        {data && (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-xs text-gray-600">
              <tr>
                <th className="px-3 py-2 text-left">Camión</th>
                <th className="px-3 py-2 text-left">Ficha SICOM</th>
                <th className="px-3 py-2 text-left">Estado diario (último escrito)</th>
                <th className="px-3 py-2 text-left">GPS hoy</th>
                <th className="px-3 py-2 text-left">El costo se carga a</th>
              </tr>
            </thead>
            <tbody>
              {filas.map((u) => {
                const dif = difiere(u)
                const malo = (g: string | null) => u.grupo_gps && g !== u.grupo_gps ? 'text-red-700' : ''
                return (
                  <tr key={u.activo_id} className="border-t">
                    <td className="px-3 py-1.5 font-medium">
                      <span className="flex items-center gap-1.5">
                        {dif ? <AlertTriangle className="h-3.5 w-3.5 text-amber-600" />
                             : <CheckCircle2 className="h-3.5 w-3.5 text-green-600" />}
                        {u.patente ?? '—'}
                      </span>
                    </td>
                    <td className={`px-3 py-1.5 ${malo(u.grupo_ficha)}`}>{u.faena_ficha ?? '—'}</td>
                    <td className={`px-3 py-1.5 ${u.grupo_estado ? malo(u.grupo_estado) : 'text-gray-400'}`}>
                      {u.estado_ubicacion ?? '—'}
                      {u.estado_fecha && <span className="ml-1 text-xs text-gray-400">({fmtF(u.estado_fecha)})</span>}
                    </td>
                    <td className="px-3 py-1.5">
                      {u.gps_geocerca
                        ? <>{u.gps_geocerca} <span className="text-xs text-gray-400">{u.gps_km} km · {fmtF(u.gps_fecha)}</span></>
                        : <span className="text-gray-400">fuera de geocerca o sin GPS</span>}
                    </td>
                    <td className="px-3 py-1.5">
                      {u.subfaena_usada ?? u.grupo_usado ?? '—'}
                      {u.fuente_usada && <span className="ml-1 text-xs text-gray-400">({u.fuente_usada.replace('_', ' ')})</span>}
                    </td>
                  </tr>
                )
              })}
              {filas.length === 0 && (
                <tr><td colSpan={5} className="p-6 text-center text-gray-500">Todas las fuentes coinciden.</td></tr>
              )}
            </tbody>
          </table>
        )}
        <p className="px-3 py-2 text-xs text-gray-400">
          En rojo, la fuente que no coincide con el GPS. Corregir la ficha (faena asignada) y el estado diario deja
          los reportes de flota alineados con el costo por faena.
        </p>
      </CardContent>
    </Card>
  )
}
