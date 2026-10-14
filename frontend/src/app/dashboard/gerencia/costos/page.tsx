'use client'

import { useRequireAuth } from '@/hooks/use-require-auth'
import { PanelCostosOperacion } from '@/components/costos/panel-costos'

// Costos de Operación (Gerencia). El panel vive en components/costos/panel-costos.tsx
// y lo comparte con Flota → Costo por faena y equipo.
export default function CostosOperacionPage() {
  useRequireAuth()
  return (
    <PanelCostosOperacion
      titulo="Costos de Operación"
      descripcion="Salidas de bodega Softland (consumo y EPP) por equipo, faena y familia de producto. Sin petróleo, que se revende." />
  )
}
