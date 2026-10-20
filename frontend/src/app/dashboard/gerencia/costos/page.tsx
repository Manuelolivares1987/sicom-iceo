'use client'

import { useRequireAuth } from '@/hooks/use-require-auth'
import { PanelCostosOperacion } from '@/components/costos/panel-costos'
import { InformeMensualCostos } from '@/components/costos/informe-mensual'

// Costos de Operación (Gerencia). El panel vive en components/costos/panel-costos.tsx
// y lo comparte con Flota → Costo por faena y equipo.
export default function CostosOperacionPage() {
  useRequireAuth()
  return (
    <>
    <InformeMensualCostos />
    <PanelCostosOperacion
      titulo="Costos de Operación"
      descripcion="Compras aprobadas (OC) o consumo de bodega de Softland, por equipo, faena y familia. Sin combustible de reventa." />
    </>
  )
}
