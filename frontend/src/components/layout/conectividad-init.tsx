'use client'

// Arranca la detección de conexión real una sola vez (ver src/lib/conectividad.ts).
import { useEffect } from 'react'
import { iniciarConectividad } from '@/lib/conectividad'

export function ConectividadInit() {
  useEffect(() => { iniciarConectividad() }, [])
  return null
}

export default ConectividadInit
