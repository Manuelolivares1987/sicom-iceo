'use client'

import * as React from 'react'
import { cn } from '@/lib/utils'
import { X, CheckCircle, AlertCircle, AlertTriangle, Info } from 'lucide-react'

export type ToastVariant = 'success' | 'error' | 'warning' | 'info'

export interface ToastData {
  id: string
  message: string
  variant: ToastVariant
  duration?: number
}

const variantConfig: Record<
  ToastVariant,
  { icon: React.ElementType; bg: string; border: string; text: string; progress: string }
> = {
  success: {
    icon: CheckCircle,
    bg: 'bg-green-50',
    border: 'border-green-200',
    text: 'text-green-800',
    progress: 'bg-green-500',
  },
  error: {
    icon: AlertCircle,
    bg: 'bg-red-50',
    border: 'border-red-200',
    text: 'text-red-800',
    progress: 'bg-red-500',
  },
  warning: {
    icon: AlertTriangle,
    bg: 'bg-orange-50',
    border: 'border-orange-200',
    text: 'text-orange-800',
    progress: 'bg-orange-500',
  },
  info: {
    icon: Info,
    bg: 'bg-blue-50',
    border: 'border-blue-200',
    text: 'text-blue-800',
    progress: 'bg-blue-500',
  },
}

interface ToastProps {
  toast: ToastData
  onDismiss: (id: string) => void
}

function Toast({ toast, onDismiss }: ToastProps) {
  const config = variantConfig[toast.variant]
  const Icon = config.icon
  const duration = toast.duration ?? 5000
  const [exiting, setExiting] = React.useState(false)

  React.useEffect(() => {
    const timer = setTimeout(() => {
      setExiting(true)
      setTimeout(() => onDismiss(toast.id), 300)
    }, duration)

    return () => clearTimeout(timer)
  }, [toast.id, duration, onDismiss])

  return (
    <div
      className={cn(
        'pointer-events-auto relative w-80 overflow-hidden rounded-lg border shadow-lg transition-all duration-300',
        config.bg,
        config.border,
        exiting
          ? 'translate-x-full opacity-0'
          : 'translate-x-0 opacity-100 animate-in slide-in-from-right-full'
      )}
      role="alert"
    >
      <div className="flex items-start gap-3 p-4">
        <Icon className={cn('h-5 w-5 shrink-0 mt-0.5', config.text)} />
        <p className={cn('flex-1 text-sm font-medium', config.text)}>
          {toast.message}
        </p>
        <button
          onClick={() => {
            setExiting(true)
            setTimeout(() => onDismiss(toast.id), 300)
          }}
          className={cn(
            'shrink-0 rounded p-0.5 transition-colors hover:bg-black/5',
            config.text
          )}
          aria-label="Cerrar"
        >
          <X className="h-4 w-4" />
        </button>
      </div>

      {/* Progress bar */}
      <div className="h-1 w-full bg-black/5">
        <div
          className={cn('h-full', config.progress)}
          style={{
            animation: `toast-progress ${duration}ms linear forwards`,
          }}
        />
      </div>

      <style jsx>{`
        @keyframes toast-progress {
          from {
            width: 100%;
          }
          to {
            width: 0%;
          }
        }
      `}</style>
    </div>
  )
}

interface ToastContainerProps {
  toasts: ToastData[]
  onDismiss: (id: string) => void
}

function ToastContainer({ toasts, onDismiss }: ToastContainerProps) {
  return (
    <div className="pointer-events-none fixed bottom-4 right-4 z-[100] flex flex-col gap-2">
      {toasts.map((toast) => (
        <Toast key={toast.id} toast={toast} onDismiss={onDismiss} />
      ))}
    </div>
  )
}

export { Toast, ToastContainer }
