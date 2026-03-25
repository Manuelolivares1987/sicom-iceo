'use client'

import * as React from 'react'
import { cva, type VariantProps } from 'class-variance-authority'
import { cn } from '@/lib/utils'

const badgeVariants = cva(
  'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold transition-colors',
  {
    variants: {
      variant: {
        default: 'bg-gray-100 text-gray-700',
        // Estado OT
        creada: 'bg-gray-100 text-gray-700',
        asignada: 'bg-blue-100 text-blue-700',
        en_ejecucion: 'bg-amber-100 text-amber-700',
        pausada: 'bg-orange-100 text-orange-700',
        ejecutada_ok: 'bg-green-100 text-green-700',
        ejecutada_con_observaciones: 'bg-yellow-100 text-yellow-700',
        no_ejecutada: 'bg-red-100 text-red-700',
        cancelada: 'bg-gray-200 text-gray-500',
        // Criticidad
        critica: 'bg-red-600 text-white',
        alta: 'bg-orange-500 text-white',
        media: 'bg-yellow-400 text-yellow-900',
        baja: 'bg-green-500 text-white',
        // Semaforo
        operativo: 'bg-green-100 text-green-700',
        en_mantenimiento: 'bg-yellow-100 text-yellow-700',
        fuera_servicio: 'bg-red-100 text-red-700',
        dado_baja: 'bg-gray-200 text-gray-500',
        en_transito: 'bg-blue-100 text-blue-700',
        // ICEO
        deficiente: 'bg-red-100 text-red-700',
        aceptable: 'bg-yellow-100 text-yellow-700',
        bueno: 'bg-green-100 text-green-700',
        excelencia: 'bg-purple-100 text-purple-700',
        // Brand
        primary: 'bg-pillado-green-100 text-pillado-green-700',
        secondary: 'bg-pillado-orange-100 text-pillado-orange-700',
      },
    },
    defaultVariants: {
      variant: 'default',
    },
  }
)

export interface BadgeProps
  extends React.HTMLAttributes<HTMLSpanElement>,
    VariantProps<typeof badgeVariants> {}

const Badge = React.forwardRef<HTMLSpanElement, BadgeProps>(
  ({ className, variant, ...props }, ref) => {
    return (
      <span
        ref={ref}
        className={cn(badgeVariants({ variant }), className)}
        {...props}
      />
    )
  }
)
Badge.displayName = 'Badge'

export { Badge, badgeVariants }
