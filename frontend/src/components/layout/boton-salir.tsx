'use client'

// ============================================================================
// «Cerrar sesión» de las apps de terreno (26-11-2026)
// ----------------------------------------------------------------------------
// Botón de ícono de 44×44 (blanco cómodo para el dedo en faena) que nunca se
// encoge: el supervisor de Calama no podía salir de la cuenta de obras civiles
// porque el nombre largo empujaba este botón fuera de la pantalla.
// Tras salir va al login, para que la siguiente persona entre con su cuenta.
// ============================================================================

import { useState } from 'react'
import { LogOut } from 'lucide-react'
import { useAuth } from '@/contexts/auth-context'

export function BotonSalir({ className = '' }: { className?: string }) {
  const { signOut } = useAuth()
  const [saliendo, setSaliendo] = useState(false)
  const salir = async () => {
    if (saliendo) return
    setSaliendo(true)
    try {
      if (await signOut()) window.location.replace('/login/')
    } finally {
      setSaliendo(false)
    }
  }
  return (
    <button
      type="button"
      onClick={salir}
      disabled={saliendo}
      aria-label="Cerrar sesión"
      title="Cerrar sesión"
      className={`inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-full disabled:opacity-50 ${className}`}
    >
      <LogOut className="h-5 w-5" aria-hidden="true" />
    </button>
  )
}
