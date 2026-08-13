'use client'

// ============================================================================
// Ruta pública /equipo/[id]/checklist
// ============================================================================
// Esta ruta llevaba al checklist QR: 21 ítems, preguntas de control
// aleatorias, tiempo mínimo de inspección y captura de GPS. Está pensado para
// el operador propio, no para el cliente.
//
// Es la URL que quedó grabada en los QR ya impresos y pegados en los equipos.
// Manda al MENÚ, no al checklist: el cliente que escanea puede venir por los
// papeles o por el historial, y si cae directo en el formulario no se entera
// de que existen. Desde el menú elige.
// ============================================================================

import { useEffect } from 'react'
import { useParams, useRouter } from 'next/navigation'
import { Spinner } from '@/components/ui/spinner'

export default function ChecklistPublicoRedirect() {
  const { id } = useParams<{ id: string }>()
  const router = useRouter()

  useEffect(() => {
    router.replace(`/equipo/${id}`)
  }, [id, router])

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-100">
      <Spinner size="lg" className="text-pillado-green-600" />
    </div>
  )
}
