'use client'

import { useParams } from 'next/navigation'
import Link from 'next/link'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { cn, formatCLP, formatDate } from '@/lib/utils'
import {
  getSemaforoDot,
  getCriticidadColor,
  getCriticidadLabel,
  getEstadoActivoLabel,
} from '@/domain/activos/status'
import { useFichaActivo } from '@/hooks/use-activos'

function getProximaColor(fecha: string | null) {
  if (!fecha) return 'text-gray-500'
  const diff = (new Date(fecha).getTime() - Date.now()) / (1000 * 60 * 60 * 24)
  if (diff < 0) return 'text-red-600 font-bold'
  if (diff <= 7) return 'text-yellow-600 font-semibold'
  return 'text-green-600'
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  if (!value && value !== 0) return null
  return (
    <div className="flex items-start justify-between border-b border-gray-100 py-2.5">
      <span className="text-sm text-gray-500">{label}</span>
      <span className="text-sm font-medium text-gray-900 text-right max-w-[55%]">{value}</span>
    </div>
  )
}

export default function FichaEquipoPage() {
  const params = useParams()
  const id = params.id as string

  const { data: ficha, isLoading, error } = useFichaActivo(id)

  if (isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gray-100">
        <Spinner size="lg" className="text-pillado-green-600" />
      </div>
    )
  }

  if (error || !ficha) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gray-100 p-4">
        <div className="w-full max-w-md rounded-2xl bg-white p-8 text-center shadow-lg">
          <p className="text-lg font-semibold text-red-500">Equipo no encontrado</p>
          <p className="mt-2 text-sm text-gray-400">
            {(error as Error)?.message ?? 'No se pudo cargar la ficha del equipo.'}
          </p>
        </div>
      </div>
    )
  }

  const f = ficha as any

  return (
    <div className="flex min-h-screen items-start justify-center bg-gray-100 px-4 py-8">
      <div className="w-full max-w-md space-y-0 rounded-2xl bg-white shadow-lg overflow-hidden">
        {/* Logo header */}
        <div className="flex flex-col items-center gap-2 border-b border-gray-100 px-6 py-6">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/images/logo_empresa_2.png"
            alt="Pillado Empresas"
            className="h-12 object-contain"
          />
          <p className="text-xs font-medium tracking-wide text-gray-400 uppercase">
            SICOM-ICEO — Ficha de Equipo
          </p>
        </div>

        {/* Body */}
        <div className="px-6 py-5 space-y-4">
          {/* Code + name */}
          <div className="text-center space-y-1">
            <p className="font-mono text-2xl font-bold text-gray-900">{f.codigo}</p>
            {f.nombre && <p className="text-sm text-gray-500">{f.nombre}</p>}
          </div>

          {/* Badges */}
          <div className="flex flex-wrap items-center justify-center gap-2">
            <div className="flex items-center gap-1.5">
              <span className={cn('h-3 w-3 rounded-full', getSemaforoDot(f.estado))} />
              <Badge variant={f.estado as any}>{getEstadoActivoLabel(f.estado)}</Badge>
            </div>
            {f.criticidad && (
              <Badge className={getCriticidadColor(f.criticidad)}>
                {getCriticidadLabel(f.criticidad)}
              </Badge>
            )}
          </div>

          {/* Info rows */}
          <div>
            <Row
              label="Marca — Modelo"
              value={
                f.marca_nombre || f.modelo_nombre
                  ? `${f.marca_nombre ?? ''}${f.marca_nombre && f.modelo_nombre ? ' — ' : ''}${f.modelo_nombre ?? ''}`
                  : null
              }
            />
            <Row label="Numero de serie" value={f.numero_serie} />
            <Row label="Faena" value={f.faena_nombre} />
            {f.anio_fabricacion && <Row label="Ano fabricacion" value={f.anio_fabricacion} />}
            {(f.kilometraje_actual > 0 || f.horas_uso_actual > 0 || f.ciclos_actual > 0) && (
              <Row
                label="KM / Horas / Ciclos"
                value={[
                  f.kilometraje_actual > 0 ? `${Number(f.kilometraje_actual).toLocaleString('es-CL')} km` : null,
                  f.horas_uso_actual > 0 ? `${Number(f.horas_uso_actual).toLocaleString('es-CL')} hrs` : null,
                  f.ciclos_actual > 0 ? `${Number(f.ciclos_actual).toLocaleString('es-CL')} ciclos` : null,
                ]
                  .filter(Boolean)
                  .join(' · ')}
              />
            )}
            <Row
              label="Ultima mantencion"
              value={f.ultima_mantencion ? formatDate(f.ultima_mantencion) : '—'}
            />
            <Row
              label="Proxima mantencion"
              value={
                f.proxima_mantencion ? (
                  <span className={getProximaColor(f.proxima_mantencion)}>
                    {formatDate(f.proxima_mantencion)}
                  </span>
                ) : (
                  '—'
                )
              }
            />
            <Row
              label="OTs abiertas"
              value={
                f.ots_abiertas > 0 ? (
                  <Link
                    href="/login"
                    className="text-pillado-green-600 hover:underline font-semibold"
                  >
                    {f.ots_abiertas}
                  </Link>
                ) : (
                  '0'
                )
              }
            />
            {(f.cert_vigentes > 0 || f.cert_por_vencer > 0 || f.cert_vencidas > 0) && (
              <Row
                label="Certificaciones"
                value={
                  <span className="space-x-2">
                    <span className="text-green-600">{f.cert_vigentes ?? 0} vigentes</span>
                    {f.cert_por_vencer > 0 && (
                      <span className="text-yellow-600">{f.cert_por_vencer} por vencer</span>
                    )}
                    {f.cert_vencidas > 0 && (
                      <span className="text-red-600">{f.cert_vencidas} vencidas</span>
                    )}
                  </span>
                }
              />
            )}
            {f.costo_acumulado > 0 && (
              <Row label="Costo acumulado" value={formatCLP(f.costo_acumulado)} />
            )}
            {f.mttr_horas != null && f.mttr_horas > 0 && (
              <Row label="MTTR" value={`${Number(f.mttr_horas).toFixed(1)} hrs`} />
            )}
          </div>

          {/* QR value */}
          {f.qr_code && (
            <div className="rounded-lg bg-gray-50 px-4 py-3 text-center">
              <p className="text-[10px] font-medium uppercase tracking-wider text-gray-400">
                QR
              </p>
              <p className="mt-1 font-mono text-xs text-gray-600 break-all">{f.qr_code}</p>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="border-t border-gray-100 px-6 py-5">
          <Link
            href="/login"
            className="flex w-full items-center justify-center rounded-lg bg-pillado-green-600 px-4 py-3 text-sm font-semibold text-white transition-colors hover:bg-pillado-green-700"
          >
            Acceder al sistema
          </Link>
        </div>
      </div>
    </div>
  )
}
