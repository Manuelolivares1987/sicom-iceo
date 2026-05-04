'use client'

// ============================================================================
// Indicador del estado de sincronizacion del checklist offline.
// ============================================================================

import type { EstadoSyncLocal } from '@/lib/offline/qr-checklist-types'

interface Props {
  estado: EstadoSyncLocal
  online: boolean
  syncError?: string | null
  intentos?: number
  onRetry?: () => void
}

function statusClass(estado: EstadoSyncLocal, online: boolean): {
  text: string
  desc: string
  cls: string
  showRetry: boolean
} {
  if (estado === 'sincronizado') {
    return {
      text: 'Sincronizado',
      desc: 'Checklist enviado correctamente al servidor.',
      cls: 'bg-pillado-green-50 border-pillado-green-300 text-pillado-green-800',
      showRetry: false,
    }
  }
  if (estado === 'sincronizando') {
    return {
      text: 'Sincronizando...',
      desc: 'Subiendo evidencias y enviando datos.',
      cls: 'bg-blue-50 border-blue-300 text-blue-800',
      showRetry: false,
    }
  }
  if (estado === 'pendiente_sync' && !online) {
    return {
      text: 'Guardado en este dispositivo',
      desc: 'Se enviará automáticamente cuando vuelva la señal.',
      cls: 'bg-yellow-50 border-yellow-300 text-yellow-800',
      showRetry: false,
    }
  }
  if (estado === 'pendiente_sync' && online) {
    return {
      text: 'Pendiente de envío',
      desc: 'Reintentando automáticamente.',
      cls: 'bg-yellow-50 border-yellow-300 text-yellow-800',
      showRetry: true,
    }
  }
  if (estado === 'error_sync') {
    return {
      text: 'Error de sincronización',
      desc: 'No se pudo enviar al servidor. Reintentar manualmente.',
      cls: 'bg-red-50 border-red-300 text-red-800',
      showRetry: true,
    }
  }
  return {
    text: 'Borrador local',
    desc: 'Aún no enviado. Guardado en este dispositivo.',
    cls: 'bg-gray-50 border-gray-300 text-gray-700',
    showRetry: false,
  }
}

export function ChecklistSyncStatus({ estado, online, syncError, intentos, onRetry }: Props) {
  const s = statusClass(estado, online)
  return (
    <div className={`rounded-lg border-2 px-4 py-3 ${s.cls}`}>
      <div className="flex items-start justify-between gap-3">
        <div className="flex-1">
          <p className="text-sm font-bold">{s.text}</p>
          <p className="mt-0.5 text-xs">{s.desc}</p>
          {syncError && (
            <p className="mt-1 text-[11px] font-mono break-all">{syncError}</p>
          )}
          {(intentos ?? 0) > 0 && (
            <p className="mt-0.5 text-[11px]">Intentos: {intentos}</p>
          )}
        </div>
        {s.showRetry && onRetry && (
          <button
            type="button"
            onClick={onRetry}
            className="shrink-0 rounded-md bg-white px-3 py-2 text-xs font-semibold border border-current"
          >
            Reintentar
          </button>
        )}
      </div>
      {!online && (
        <p className="mt-2 text-[11px] font-semibold uppercase tracking-wide">
          Sin conexión
        </p>
      )}
    </div>
  )
}
