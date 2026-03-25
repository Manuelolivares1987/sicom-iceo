'use client'

import * as React from 'react'
import { createPortal } from 'react-dom'
import { cn } from '@/lib/utils'
import { X } from 'lucide-react'

export interface ModalProps {
  open: boolean
  onClose: () => void
  children: React.ReactNode
  className?: string
  title?: string
  description?: string
  closeOnOverlay?: boolean
}

function Modal({
  open,
  onClose,
  children,
  className,
  title,
  description,
  closeOnOverlay = true,
}: ModalProps) {
  const [mounted, setMounted] = React.useState(false)

  React.useEffect(() => {
    setMounted(true)
  }, [])

  React.useEffect(() => {
    if (!open) return

    const handleEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
    }

    document.addEventListener('keydown', handleEscape)
    document.body.style.overflow = 'hidden'

    return () => {
      document.removeEventListener('keydown', handleEscape)
      document.body.style.overflow = ''
    }
  }, [open, onClose])

  if (!mounted || !open) return null

  return createPortal(
    <div
      className="fixed inset-0 z-50 flex items-center justify-center"
      role="dialog"
      aria-modal="true"
      aria-labelledby={title ? 'modal-title' : undefined}
      aria-describedby={description ? 'modal-description' : undefined}
    >
      {/* Overlay */}
      <div
        className="fixed inset-0 bg-black/50 backdrop-blur-sm transition-opacity"
        onClick={closeOnOverlay ? onClose : undefined}
        aria-hidden="true"
      />

      {/* Content */}
      <div
        className={cn(
          'relative z-10 flex max-h-[100dvh] w-full flex-col bg-white shadow-xl',
          'sm:max-h-[90dvh] sm:max-w-lg sm:rounded-xl sm:border sm:border-gray-100',
          // Full-screen on mobile, dialog on desktop
          'h-full sm:h-auto',
          className
        )}
      >
        {/* Header */}
        {(title || true) && (
          <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4">
            <div>
              {title && (
                <h2
                  id="modal-title"
                  className="text-lg font-semibold text-gray-900"
                >
                  {title}
                </h2>
              )}
              {description && (
                <p id="modal-description" className="mt-1 text-sm text-gray-500">
                  {description}
                </p>
              )}
            </div>
            <button
              onClick={onClose}
              className="rounded-lg p-1.5 text-gray-400 transition-colors hover:bg-gray-100 hover:text-gray-600"
              aria-label="Cerrar"
            >
              <X className="h-5 w-5" />
            </button>
          </div>
        )}

        {/* Body */}
        <div className="flex-1 overflow-y-auto p-6">{children}</div>
      </div>
    </div>,
    document.body
  )
}

export interface ModalFooterProps extends React.HTMLAttributes<HTMLDivElement> {}

const ModalFooter = React.forwardRef<HTMLDivElement, ModalFooterProps>(
  ({ className, ...props }, ref) => (
    <div
      ref={ref}
      className={cn(
        'flex items-center justify-end gap-3 border-t border-gray-100 px-6 py-4',
        className
      )}
      {...props}
    />
  )
)
ModalFooter.displayName = 'ModalFooter'

export { Modal, ModalFooter }
