'use client'

import * as React from 'react'
import { cn } from '@/lib/utils'
import { TrendingUp, TrendingDown, Minus } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'

export interface StatCardProps extends React.HTMLAttributes<HTMLDivElement> {
  title: string
  value: string | number
  subtitle?: string
  trend?: {
    direction: 'up' | 'down' | 'neutral'
    delta: string
  }
  icon: LucideIcon
  color?: 'green' | 'orange' | 'blue' | 'red'
}

const colorConfig = {
  green: {
    bg: 'bg-pillado-green-50',
    icon: 'text-pillado-green-500',
  },
  orange: {
    bg: 'bg-pillado-orange-50',
    icon: 'text-pillado-orange-500',
  },
  blue: {
    bg: 'bg-blue-50',
    icon: 'text-blue-500',
  },
  red: {
    bg: 'bg-red-50',
    icon: 'text-red-500',
  },
} as const

const trendConfig = {
  up: { icon: TrendingUp, text: 'text-green-600' },
  down: { icon: TrendingDown, text: 'text-red-600' },
  neutral: { icon: Minus, text: 'text-gray-400' },
} as const

function StatCard({
  title,
  value,
  subtitle,
  trend,
  icon: Icon,
  color = 'green',
  className,
  ...props
}: StatCardProps) {
  const colors = colorConfig[color]

  return (
    <div
      className={cn(
        'rounded-xl border border-gray-100 bg-white p-5 shadow-sm',
        className
      )}
      {...props}
    >
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <p className="text-sm font-medium text-gray-500">{title}</p>
          <p className="mt-1 text-2xl font-bold text-gray-900">{value}</p>
          {subtitle && (
            <p className="mt-0.5 text-xs text-gray-400">{subtitle}</p>
          )}
        </div>
        <div
          className={cn(
            'flex h-10 w-10 shrink-0 items-center justify-center rounded-lg',
            colors.bg
          )}
        >
          <Icon className={cn('h-5 w-5', colors.icon)} />
        </div>
      </div>

      {trend && (
        <div className="mt-3 flex items-center gap-1.5">
          {React.createElement(trendConfig[trend.direction].icon, {
            className: cn('h-4 w-4', trendConfig[trend.direction].text),
          })}
          <span
            className={cn(
              'text-xs font-medium',
              trendConfig[trend.direction].text
            )}
          >
            {trend.delta}
          </span>
        </div>
      )}
    </div>
  )
}

export { StatCard }
