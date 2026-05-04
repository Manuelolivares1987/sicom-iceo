'use client'

// ============================================================================
// Badge global de alertas de mantención.
// Visual: verde si 0, amarillo si hay abiertas, rojo si hay críticas.
// Click → /dashboard/mantencion/alertas
// ============================================================================

import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import { AlertTriangle, ShieldCheck, RefreshCw, Eye } from 'lucide-react'
import { obtenerResumenAlertasMantencion } from '@/lib/services/mantencion-alertas'

interface Props {
  /** 'compact' = chip pequeño (sidebar/header), 'card' = bloque completo */
  variant?: 'compact' | 'card'
  className?: string
}

export function AlertasMantencionBadge({ variant = 'card', className = '' }: Props) {
  const { data, isLoading, isFetching, refetch, error } = useQuery({
    queryKey: ['mantencion-alertas-resumen'],
    queryFn: async () => {
      const r = await obtenerResumenAlertasMantencion()
      if (r.error) throw r.error
      return r.data
    },
    staleTime: 30_000,
    refetchInterval: 60_000,
  })

  const total = data?.total_abiertas ?? 0
  const criticas = data?.total_criticas ?? 0
  const sospechosos = data?.alertas_calidad.sospechosos ?? 0

  // Color/estado visual
  const color: 'verde' | 'amarillo' | 'rojo' =
    criticas > 0 ? 'rojo' : total > 0 ? 'amarillo' : 'verde'

  const colorCls: Record<typeof color, string> = {
    verde:    'bg-pillado-green-50 border-pillado-green-300 text-pillado-green-800',
    amarillo: 'bg-yellow-50 border-yellow-300 text-yellow-800',
    rojo:     'bg-red-50 border-red-300 text-red-800',
  }
  const dotCls: Record<typeof color, string> = {
    verde:    'bg-pillado-green-600',
    amarillo: 'bg-yellow-500',
    rojo:     'bg-red-600',
  }

  // ── Compact (chip) ──
  if (variant === 'compact') {
    return (
      <Link
        href="/dashboard/mantencion/alertas"
        className={`inline-flex items-center gap-2 rounded-full border px-3 py-1.5 text-xs font-semibold ${colorCls[color]} ${className}`}
      >
        <span className={`h-2 w-2 rounded-full ${dotCls[color]}`} />
        {isLoading ? '...' :
          color === 'verde' ? 'Sin alertas' :
          `${total} alerta${total === 1 ? '' : 's'}${criticas > 0 ? ` · ${criticas} crítica${criticas === 1 ? '' : 's'}` : ''}`
        }
      </Link>
    )
  }

  // ── Card (bloque completo) ──
  return (
    <div className={`rounded-2xl border-2 p-5 ${colorCls[color]} ${className}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-center gap-3">
          {color === 'verde' ? (
            <ShieldCheck className="h-7 w-7" />
          ) : (
            <AlertTriangle className="h-7 w-7" />
          )}
          <div>
            <p className="text-[11px] font-bold uppercase tracking-wide opacity-70">
              Alertas de mantención
            </p>
            <p className="text-3xl font-extrabold leading-tight">
              {isLoading ? '—' : total}
            </p>
            <p className="text-xs opacity-80">
              {isLoading ? 'Cargando...' :
                color === 'verde' ? 'No hay alertas abiertas' :
                color === 'rojo'  ? 'Hay alertas críticas pendientes' :
                                    'Alertas pendientes de revisión'}
            </p>
          </div>
        </div>
        <button
          type="button"
          onClick={() => refetch()}
          disabled={isFetching}
          className="rounded-md p-2 hover:bg-white/40 disabled:opacity-50"
          aria-label="Actualizar"
          title="Actualizar"
        >
          <RefreshCw className={`h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} />
        </button>
      </div>

      {/* Breakdown */}
      {data && total > 0 && (
        <div className="mt-4 grid grid-cols-2 gap-3 text-xs">
          <div className="rounded-lg bg-white/60 px-3 py-2">
            <p className="font-semibold opacity-70">Tempranas (técnicas)</p>
            <p className="text-lg font-bold">{data.alertas_tempranas.total}</p>
            <p className="opacity-70">
              {data.alertas_tempranas.rojo > 0 && (
                <span className="font-bold text-red-700">{data.alertas_tempranas.rojo} rojas</span>
              )}
              {data.alertas_tempranas.rojo > 0 && (data.alertas_tempranas.naranja + data.alertas_tempranas.amarillo) > 0 && ' · '}
              {data.alertas_tempranas.naranja > 0 && `${data.alertas_tempranas.naranja} naranjas`}
              {data.alertas_tempranas.naranja > 0 && data.alertas_tempranas.amarillo > 0 && ' · '}
              {data.alertas_tempranas.amarillo > 0 && `${data.alertas_tempranas.amarillo} amarillas`}
            </p>
          </div>
          <div className="rounded-lg bg-white/60 px-3 py-2">
            <p className="font-semibold opacity-70">Calidad checklist</p>
            <p className="text-lg font-bold">{data.alertas_calidad.total}</p>
            <p className="opacity-70">
              {data.alertas_calidad.critica > 0 && (
                <span className="font-bold text-red-700">{data.alertas_calidad.critica} críticas</span>
              )}
              {data.alertas_calidad.critica > 0 && data.alertas_calidad.alta > 0 && ' · '}
              {data.alertas_calidad.alta > 0 && `${data.alertas_calidad.alta} altas`}
            </p>
          </div>
        </div>
      )}

      {sospechosos > 0 && (
        <div className="mt-3 rounded-lg bg-white/60 px-3 py-2 text-xs">
          <p className="font-semibold">
            {sospechosos} checklist{sospechosos === 1 ? '' : 's'} sospechoso{sospechosos === 1 ? '' : 's'} requiere{sospechosos === 1 ? '' : 'n'} revisión
          </p>
        </div>
      )}

      {error && (
        <p className="mt-3 text-xs font-mono text-red-700">
          Error: {(error as { message?: string })?.message ?? String(error)}
        </p>
      )}

      <Link
        href="/dashboard/mantencion/alertas"
        className="mt-4 inline-flex w-full items-center justify-center gap-2 rounded-lg bg-white/80 px-4 py-2.5 text-sm font-semibold hover:bg-white"
      >
        <Eye className="h-4 w-4" />
        Ver listado completo
      </Link>
    </div>
  )
}
