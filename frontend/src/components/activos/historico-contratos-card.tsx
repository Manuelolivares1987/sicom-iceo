'use client'

import { useEffect, useState } from 'react'
import { History, Building2, RefreshCw } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { Button } from '@/components/ui/button'
import { cargarHistoricoContratoActivo, type HistoricoContratoRow } from '@/lib/services/contrato-activo'

export function HistoricoContratosCard({ activoId, refrescarKey }: { activoId: string; refrescarKey?: number }) {
  const [rows, setRows] = useState<HistoricoContratoRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const cargar = async () => {
    setLoading(true); setError(null)
    try {
      setRows(await cargarHistoricoContratoActivo(activoId))
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { cargar() /* eslint-disable-line react-hooks/exhaustive-deps */ }, [activoId, refrescarKey])

  return (
    <Card>
      <CardHeader className="pb-2 flex flex-row items-center justify-between">
        <CardTitle className="flex items-center gap-2 text-base">
          <History className="h-4 w-4" /> Histórico de contratos ({rows.length})
        </CardTitle>
        <Button variant="ghost" size="sm" onClick={cargar} className="gap-1">
          <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
        </Button>
      </CardHeader>
      <CardContent className="p-0">
        {loading && rows.length === 0 ? (
          <div className="flex h-24 items-center justify-center"><Spinner /></div>
        ) : error ? (
          <div className="p-4 text-sm text-red-700">{error}</div>
        ) : rows.length === 0 ? (
          <div className="p-4 text-center text-sm text-muted-foreground">
            Sin cambios de contrato registrados aún.
          </div>
        ) : (
          <div className="max-h-96 overflow-auto">
            <table className="w-full text-xs">
              <thead className="sticky top-0 bg-gray-50">
                <tr>
                  <th className="px-2 py-2 text-left">Fecha</th>
                  <th className="px-2 py-2 text-left">Anterior</th>
                  <th className="px-2 py-2 text-left">Nuevo</th>
                  <th className="px-2 py-2 text-right">Duración previa</th>
                  <th className="px-2 py-2 text-right">Horómetro</th>
                  <th className="px-2 py-2 text-left">Razón</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id} className="border-t align-top">
                    <td className="px-2 py-1.5 text-gray-500 whitespace-nowrap">
                      {new Date(r.cambio_at).toLocaleString('es-CL')}
                      {r.cambio_por_email && (
                        <div className="text-[10px] text-gray-400 truncate max-w-[140px]">
                          {r.cambio_por_email}
                        </div>
                      )}
                    </td>
                    <td className="px-2 py-1.5">
                      <ContratoCell codigo={r.contrato_anterior_codigo} cliente={r.cliente_anterior} />
                    </td>
                    <td className="px-2 py-1.5">
                      <ContratoCell codigo={r.contrato_nuevo_codigo} cliente={r.cliente_nuevo} />
                    </td>
                    <td className="px-2 py-1.5 text-right">
                      {r.duracion_contrato_anterior_dias != null
                        ? `${r.duracion_contrato_anterior_dias.toFixed(1)} d`
                        : '—'}
                    </td>
                    <td className="px-2 py-1.5 text-right font-mono">
                      {r.horometro != null ? `${r.horometro.toFixed(0)}h` : '—'}
                      {r.kilometraje != null && (
                        <div className="text-[10px] text-gray-400">{r.kilometraje.toFixed(0)} km</div>
                      )}
                    </td>
                    <td className="px-2 py-1.5 max-w-[200px]">
                      {r.razon ? (
                        <span className="text-gray-700">{r.razon}</span>
                      ) : (
                        <span className="text-gray-400 italic">—</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </CardContent>
    </Card>
  )
}

function ContratoCell({ codigo, cliente }: { codigo: string | null; cliente: string | null }) {
  if (!codigo && !cliente) {
    return <span className="italic text-gray-400">Sin contrato</span>
  }
  return (
    <div className="flex items-start gap-1">
      <Building2 className="mt-0.5 h-3 w-3 shrink-0 text-gray-400" />
      <div className="min-w-0">
        <div className="font-medium truncate">{codigo ?? '—'}</div>
        <div className="text-[10px] text-gray-500 truncate">{cliente ?? '—'}</div>
      </div>
    </div>
  )
}
