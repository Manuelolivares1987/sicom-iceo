'use client'

import { Play, Pause, CheckCircle2, XCircle } from 'lucide-react'
import { Button } from '@/components/ui/button'
import type { EstadoOT } from '@/types/database'

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------
export interface OTActionBarProps {
  estado: EstadoOT
  onIniciar: () => void
  onPausar: () => void
  onFinalizar: () => void
  onNoEjecutada: () => void
  loading: boolean
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------
export function OTActionBar({
  estado,
  onIniciar,
  onPausar,
  onFinalizar,
  onNoEjecutada,
  loading,
}: OTActionBarProps) {
  const showIniciar = estado === 'asignada'
  const showEnEjecucion = estado === 'en_ejecucion'
  const showPausada = estado === 'pausada'

  // Nothing to show for terminal states
  if (!showIniciar && !showEnEjecucion && !showPausada) return null

  return (
    <div className="sticky bottom-0 z-50 border-t border-gray-200 bg-white p-4 shadow-lg sm:static sm:mt-6 sm:border-0 sm:bg-transparent sm:p-0 sm:shadow-none">
      <div className="flex flex-wrap gap-2">
        {showIniciar && (
          <Button
            variant="primary"
            size="lg"
            className="flex-1 sm:flex-none"
            onClick={onIniciar}
            disabled={loading}
          >
            <Play className="h-5 w-5" />
            Iniciar
          </Button>
        )}

        {showEnEjecucion && (
          <>
            <Button
              variant="secondary"
              size="lg"
              className="flex-1 sm:flex-none"
              onClick={onPausar}
              disabled={loading}
            >
              <Pause className="h-5 w-5" />
              Pausar
            </Button>
            <Button
              variant="primary"
              size="lg"
              className="flex-1 sm:flex-none"
              onClick={onFinalizar}
              disabled={loading}
            >
              <CheckCircle2 className="h-5 w-5" />
              Finalizar
            </Button>
            <Button
              variant="danger"
              size="lg"
              className="flex-1 sm:flex-none"
              onClick={onNoEjecutada}
              disabled={loading}
            >
              <XCircle className="h-5 w-5" />
              No Ejecutada
            </Button>
          </>
        )}

        {showPausada && (
          <>
            <Button
              variant="primary"
              size="lg"
              className="flex-1 sm:flex-none"
              onClick={onIniciar}
              disabled={loading}
            >
              <Play className="h-5 w-5" />
              Reanudar
            </Button>
            <Button
              variant="danger"
              size="lg"
              className="flex-1 sm:flex-none"
              onClick={onNoEjecutada}
              disabled={loading}
            >
              <XCircle className="h-5 w-5" />
              No Ejecutada
            </Button>
          </>
        )}
      </div>
    </div>
  )
}
