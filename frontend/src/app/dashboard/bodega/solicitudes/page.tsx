'use client'

// Consolidado en "Pedidos a bodega" (/dashboard/bodega/tickets, pestaña
// Solicitudes) para que el bodeguero gestione todo en un solo lugar.
// Esta URL queda como redirect para links antiguos.
import { useEffect } from 'react'
import { useRouter } from 'next/navigation'

export default function SolicitudesRedirect() {
  const router = useRouter()
  useEffect(() => { router.replace('/dashboard/bodega/tickets?tab=solicitudes') }, [router])
  return null
}
