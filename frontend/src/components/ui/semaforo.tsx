'use client'

import * as React from 'react'
import { cn } from '@/lib/utils'

type EstadoOperativo =
  | 'operativo'
  | 'en_mantenimiento'
  | 'fuera_servicio'
  | 'dado_baja'
  | 'en_transito'

const estadoConfig: Record<EstadoOperativo, { color: string; label: string }> = {
  operativo: { color: 'bg-semaforo-verde', label: 'Operativo' },
  en_mantenimiento: { color: 'bg-semaforo-amarillo', label: 'En Mantenimiento' },
  fuera_servicio: { color: 'bg-semaforo-rojo', label: 'Fuera de Servicio' },
  dado_baja: { color: 'bg-gray-400', label: 'Dado de Baja' },
  en_transito: { color: 'bg-semaforo-azul', label: 'En Tránsito' },
}

export interface SemaforoProps extends React.HTMLAttributes<HTMLDivElement> {
  estado: EstadoOperativo
  showLabel?: boolean
  size?: 'sm' | 'md' | 'lg'
}

const sizeMap = {
  sm: 'h-2.5 w-2.5',
  md: 'h-3.5 w-3.5',
  lg: 'h-5 w-5',
} as const

function Semaforo({ estado, showLabel = false, size = 'md', className, ...props }: SemaforoProps) {
  const config = estadoConfig[estado] || estadoConfig.operativo

  return (
    <div
      className={cn('inline-flex items-center gap-2', className)}
      title={config.label}
      {...props}
    >
      <span
        className={cn(
          'inline-block shrink-0 rounded-full',
          config.color,
          sizeMap[size]
        )}
        aria-hidden="true"
      />
      {showLabel && (
        <span className="text-sm text-gray-700">{config.label}</span>
      )}
    </div>
  )
}

// ICEO Score variant

function getICEOScoreConfig(valor: number): { color: string; label: string } {
  if (valor >= 95) return { color: 'bg-iceo-excelencia', label: 'Excelencia' }
  if (valor >= 85) return { color: 'bg-iceo-bueno', label: 'Bueno' }
  if (valor >= 70) return { color: 'bg-iceo-aceptable', label: 'Aceptable' }
  return { color: 'bg-iceo-deficiente', label: 'Deficiente' }
}

export interface ICEOIndicatorProps extends React.HTMLAttributes<HTMLDivElement> {
  valor: number
  showLabel?: boolean
  size?: 'sm' | 'md' | 'lg'
}

function ICEOIndicator({
  valor,
  showLabel = false,
  size = 'md',
  className,
  ...props
}: ICEOIndicatorProps) {
  const config = getICEOScoreConfig(valor)

  return (
    <div
      className={cn('inline-flex items-center gap-2', className)}
      title={`ICEO: ${valor.toFixed(1)} - ${config.label}`}
      {...props}
    >
      <span
        className={cn(
          'inline-block shrink-0 rounded-full',
          config.color,
          sizeMap[size]
        )}
        aria-hidden="true"
      />
      {showLabel && (
        <span className="text-sm text-gray-700">{config.label}</span>
      )}
    </div>
  )
}

export { Semaforo, ICEOIndicator }
