'use client'

import {
  Play,
  Pause,
  CheckCircle2,
  XCircle,
  AlertTriangle,
  AlertCircle,
  UserPlus,
  type LucideIcon,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import type { EstadoOT } from '@/types/database'
import { getActionButtons } from '@/domain/ot/transitions'

// ---------------------------------------------------------------------------
// Icon mapping from string names to Lucide components
// ---------------------------------------------------------------------------
const ICON_MAP: Record<string, LucideIcon> = {
  Play,
  Pause,
  CheckCircle: CheckCircle2,
  CheckCircle2,
  XCircle,
  AlertTriangle,
  AlertCircle,
  UserPlus,
}

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------
export interface OTActionBarProps {
  estado: EstadoOT
  onIniciar: () => void
  onPausar: () => void
  onFinalizar: () => void
  onNoEjecutada: () => void
  onAsignar?: () => void
  onCancelar?: () => void
  onFinalizarConObs?: () => void
  loading: boolean
}

// ---------------------------------------------------------------------------
// Map a domain button config to the appropriate callback
// ---------------------------------------------------------------------------
function getHandler(
  targetEstado: EstadoOT,
  props: OTActionBarProps
): (() => void) | null {
  switch (targetEstado) {
    case 'asignada':
      return props.onAsignar ?? null
    case 'en_ejecucion':
      return props.onIniciar
    case 'pausada':
      return props.onPausar
    case 'ejecutada_ok':
      return props.onFinalizar
    case 'ejecutada_con_observaciones':
      return props.onFinalizarConObs ?? props.onFinalizar
    case 'no_ejecutada':
      return props.onNoEjecutada
    case 'cancelada':
      return props.onCancelar ?? null
    default:
      return null
  }
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------
export function OTActionBar(props: OTActionBarProps) {
  const { estado, loading } = props
  const buttons = getActionButtons(estado)

  // Filter out buttons without a handler
  const renderableButtons = buttons.filter((btn) => getHandler(btn.estado, props) !== null)

  if (renderableButtons.length === 0) return null

  return (
    <div className="sticky bottom-0 z-50 border-t border-gray-200 bg-white p-4 shadow-lg sm:static sm:mt-6 sm:border-0 sm:bg-transparent sm:p-0 sm:shadow-none">
      <div className="flex flex-wrap gap-2">
        {renderableButtons.map((btn) => {
          const Icon = ICON_MAP[btn.icon]
          const handler = getHandler(btn.estado, props)!
          return (
            <Button
              key={btn.estado}
              variant={btn.variant}
              size="lg"
              className="flex-1 sm:flex-none"
              onClick={handler}
              disabled={loading}
            >
              {Icon && <Icon className="h-5 w-5" />}
              {btn.label}
            </Button>
          )
        })}
      </div>
    </div>
  )
}
