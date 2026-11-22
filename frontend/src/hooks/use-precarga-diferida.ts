'use client'

import { useEffect } from 'react'
import { estaEnLinea } from '@/lib/conectividad'

/** Baja un módulo pesado (PDF, Excel) en segundo plano, 3 s después de abrir la
 *  pantalla y solo con señal: la pantalla abre rápido y el módulo queda en la
 *  caché del teléfono para usarlo después sin señal. */
export function usePrecargaDiferida(cargar: () => Promise<unknown>, ms = 3000) {
  useEffect(() => {
    const t = setTimeout(() => { if (estaEnLinea()) void cargar().catch(() => undefined) }, ms)
    return () => clearTimeout(t)
  }, [cargar, ms])
}
