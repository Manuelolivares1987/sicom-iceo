'use client'

import * as React from 'react'
import { ToastContainer, type ToastData, type ToastVariant } from '@/components/ui/toast'

interface ToastContextValue {
  success: (message: string) => void
  error: (message: string) => void
  warning: (message: string) => void
  info: (message: string) => void
}

const ToastContext = React.createContext<ToastContextValue | null>(null)

let toastCounter = 0

function generateId(): string {
  toastCounter += 1
  return `toast-${toastCounter}-${Date.now()}`
}

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = React.useState<ToastData[]>([])

  const dismiss = React.useCallback((id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id))
  }, [])

  const addToast = React.useCallback((message: string, variant: ToastVariant) => {
    const id = generateId()
    setToasts((prev) => [...prev, { id, message, variant }])
  }, [])

  const value = React.useMemo<ToastContextValue>(
    () => ({
      success: (msg: string) => addToast(msg, 'success'),
      error: (msg: string) => addToast(msg, 'error'),
      warning: (msg: string) => addToast(msg, 'warning'),
      info: (msg: string) => addToast(msg, 'info'),
    }),
    [addToast]
  )

  return (
    <ToastContext.Provider value={value}>
      {children}
      <ToastContainer toasts={toasts} onDismiss={dismiss} />
    </ToastContext.Provider>
  )
}

export function useToast(): ToastContextValue {
  const context = React.useContext(ToastContext)
  if (!context) {
    throw new Error('useToast must be used within a ToastProvider')
  }
  return context
}
