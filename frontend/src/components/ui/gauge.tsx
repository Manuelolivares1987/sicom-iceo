'use client'

import * as React from 'react'
import { cn } from '@/lib/utils'

function getGaugeColor(value: number): string {
  if (value >= 95) return '#7C3AED' // iceo.excelencia - purple
  if (value >= 85) return '#16A34A' // iceo.bueno - green
  if (value >= 70) return '#F59E0B' // iceo.aceptable - yellow
  return '#DC2626' // iceo.deficiente - red
}

function getGaugeLabel(value: number): string {
  if (value >= 95) return 'Excelencia'
  if (value >= 85) return 'Bueno'
  if (value >= 70) return 'Aceptable'
  return 'Deficiente'
}

function getGaugeLabelColor(value: number): string {
  if (value >= 95) return 'text-iceo-excelencia'
  if (value >= 85) return 'text-iceo-bueno'
  if (value >= 70) return 'text-iceo-aceptable'
  return 'text-iceo-deficiente'
}

export interface GaugeProps extends React.HTMLAttributes<HTMLDivElement> {
  value: number
  min?: number
  max?: number
  label?: string
  showValue?: boolean
  size?: 'md' | 'lg' | 'xl'
}

const sizeConfig = {
  md: { width: 180, stroke: 14, fontSize: 28, labelSize: 'text-sm' as const },
  lg: { width: 240, stroke: 18, fontSize: 36, labelSize: 'text-base' as const },
  xl: { width: 320, stroke: 22, fontSize: 48, labelSize: 'text-lg' as const },
} as const

const Gauge = React.forwardRef<HTMLDivElement, GaugeProps>(
  (
    {
      value,
      min = 0,
      max = 100,
      label,
      showValue = true,
      size = 'lg',
      className,
      ...props
    },
    ref
  ) => {
    const cfg = sizeConfig[size]
    const clampedValue = Math.max(min, Math.min(max, value))
    const percentage = ((clampedValue - min) / (max - min)) * 100

    const radius = (cfg.width - cfg.stroke) / 2
    const circumference = Math.PI * radius // semicircle
    const dashOffset = circumference * (1 - percentage / 100)

    const cy = cfg.width / 2
    const height = cy + cfg.stroke + 4

    const gaugeColor = getGaugeColor(percentage)
    const resolvedLabel = label || getGaugeLabel(percentage)
    const labelColor = getGaugeLabelColor(percentage)

    const gradientId = React.useId()

    // Arc path (semicircle from left to right)
    const arcPath = `M ${cfg.stroke / 2} ${cy} A ${radius} ${radius} 0 0 1 ${cfg.width - cfg.stroke / 2} ${cy}`

    return (
      <div
        ref={ref}
        className={cn('flex flex-col items-center', className)}
        {...props}
      >
        <svg
          width={cfg.width}
          height={height}
          viewBox={`0 0 ${cfg.width} ${height}`}
          className="overflow-visible"
        >
          <defs>
            <linearGradient id={gradientId} x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stopColor="#DC2626" stopOpacity="0.15" />
              <stop offset="35%" stopColor="#F59E0B" stopOpacity="0.15" />
              <stop offset="65%" stopColor="#16A34A" stopOpacity="0.15" />
              <stop offset="100%" stopColor="#7C3AED" stopOpacity="0.15" />
            </linearGradient>
          </defs>

          {/* Background track with gradient */}
          <path
            d={arcPath}
            fill="none"
            stroke={`url(#${gradientId})`}
            strokeWidth={cfg.stroke}
            strokeLinecap="round"
          />

          {/* Value arc */}
          {percentage > 0 && (
            <path
              d={arcPath}
              fill="none"
              stroke={gaugeColor}
              strokeWidth={cfg.stroke}
              strokeLinecap="round"
              strokeDasharray={circumference}
              strokeDashoffset={dashOffset}
              style={{ transition: 'stroke-dashoffset 0.7s ease-out' }}
            />
          )}

          {/* Center value text */}
          {showValue && (
            <text
              x={cfg.width / 2}
              y={cy - 6}
              textAnchor="middle"
              dominantBaseline="auto"
              fontSize={cfg.fontSize}
              fontWeight={700}
              fill={gaugeColor}
            >
              {clampedValue.toFixed(1)}
            </text>
          )}

          {/* Min label */}
          <text
            x={cfg.stroke / 2 + 2}
            y={cy + 16}
            textAnchor="start"
            fill="#9CA3AF"
            fontSize="11"
          >
            {min}
          </text>

          {/* Max label */}
          <text
            x={cfg.width - cfg.stroke / 2 - 2}
            y={cy + 16}
            textAnchor="end"
            fill="#9CA3AF"
            fontSize="11"
          >
            {max}
          </text>
        </svg>

        {/* Label below */}
        <span
          className={cn(
            'mt-1 font-semibold',
            cfg.labelSize,
            labelColor
          )}
        >
          {resolvedLabel}
        </span>
      </div>
    )
  }
)
Gauge.displayName = 'Gauge'

export { Gauge }
