'use client'

// ============================================================================
// Ruta pública /equipo/[id]/checklist
// ============================================================================
// Esta ruta llevaba al checklist QR: 21 ítems, preguntas de control
// aleatorias, tiempo mínimo de inspección y captura de GPS. Está pensado para
// el operador propio, no para el cliente.
//
// Pero el QR lo escanea el cliente, y para él tiene que haber UN solo
// checklist y el más simple: los 11 ítems de la inspección del arrendatario.
// Los QR ya impresos y los links compartidos siguen apuntando aquí, así que
// esta ruta redirige en vez de desaparecer.
// ============================================================================

import { useEffect } from 'react'
import { useParams, useRouter } from 'next/navigation'
import { Spinner } from '@/components/ui/spinner'

export default function ChecklistPublicoRedirect() {
  const { id } = useParams<{ id: string }>()
  const router = useRouter()

  useEffect(() => {
    router.replace(`/equipo/${id}/checklist-cliente`)
  }, [id, router])

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-100">
      <Spinner size="lg" className="text-pillado-green-600" />
    </div>
  )
}
