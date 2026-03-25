'use client'

import * as React from 'react'
import { cva, type VariantProps } from 'class-variance-authority'
import { cn } from '@/lib/utils'
import { Spinner } from './spinner'

const buttonVariants = cva(
  'inline-flex items-center justify-center gap-2 rounded-lg font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-pillado-green-500 focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50',
  {
    variants: {
      variant: {
        primary:
          'bg-pillado-green-500 text-white hover:bg-pillado-green-600 active:bg-pillado-green-700',
        secondary:
          'bg-pillado-orange-500 text-white hover:bg-pillado-orange-600 active:bg-pillado-orange-700',
        outline:
          'border-2 border-pillado-green-500 text-pillado-green-500 bg-transparent hover:bg-pillado-green-50 active:bg-pillado-green-100',
        danger:
          'bg-red-600 text-white hover:bg-red-700 active:bg-red-800',
        ghost:
          'bg-transparent text-gray-700 hover:bg-gray-100 active:bg-gray-200',
      },
      size: {
        sm: 'h-8 px-3 text-sm',
        md: 'h-10 px-4 text-sm',
        lg: 'min-h-[48px] px-6 text-base',
      },
    },
    defaultVariants: {
      variant: 'primary',
      size: 'md',
    },
  }
)

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  loading?: boolean
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, loading = false, disabled, children, ...props }, ref) => {
    return (
      <button
        className={cn(buttonVariants({ variant, size, className }))}
        ref={ref}
        disabled={disabled || loading}
        {...props}
      >
        {loading && <Spinner size="sm" className="shrink-0" />}
        {children}
      </button>
    )
  }
)
Button.displayName = 'Button'

export { Button, buttonVariants }
