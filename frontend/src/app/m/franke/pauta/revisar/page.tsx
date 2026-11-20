'use client'

// Pauta por equipo como página FIJA (20-11-2026): /m/franke/pauta/revisar/?p=<pauta>&a=<activo>&turno=
// Las rutas con [id] no se pueden guardar enteras en el teléfono; esta sí, y
// abre sin señal como el resto de la app de la faena.

import { Suspense } from 'react'
import EjecutarPautaPage from '../[pautaId]/[activoId]/page'
import { EsperandoSesion } from '@/components/layout/esperando-sesion'

export default function RevisarPautaPage() {
  return (
    <Suspense fallback={<EsperandoSesion />}>
      <EjecutarPautaPage />
    </Suspense>
  )
}
