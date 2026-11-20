'use client'

// Antes de montar la app (sesión, colas sin señal…) se revisa que el navegador
// deje guardar datos. Si no, en vez de caerse en «La app no pudo abrir», se
// explica cómo habilitarlo.

import type { ReactNode } from 'react'
import { almacenamientoBloqueado } from '@/lib/almacenamiento'
import { PantallaAlmacenamientoBloqueado } from '@/components/layout/almacenamiento-bloqueado'

export function GuardaAlmacenamiento({ children }: { children: ReactNode }) {
  // En el servidor siempre «disponible»; en el teléfono bloqueado la diferencia
  // obliga a React a pintar de nuevo en el cliente, que es lo que queremos.
  if (almacenamientoBloqueado()) return <PantallaAlmacenamientoBloqueado />
  return <>{children}</>
}
