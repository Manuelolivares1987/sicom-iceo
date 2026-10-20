'use client'

import { useState } from 'react'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { PanelCostosOperacion } from '@/components/costos/panel-costos'
import { InformeMensualCostos } from '@/components/costos/informe-mensual'

// Costos de Operación (Gerencia). El panel vive en components/costos/panel-costos.tsx
// y lo comparte con Flota → Costo por faena y equipo.
export default function CostosOperacionPage() {
  useRequireAuth()
  // El mes elegido arriba filtra todo el panel; los botones de período lo limpian.
  const [mes, setMes] = useState<string | null>(null)
  return (
    <>
    <InformeMensualCostos mesFiltro={mes} onMes={setMes} />
    <PanelCostosOperacion
      mes={mes} onLimpiarMes={() => setMes(null)}
      titulo="Costos de Operación"
      descripcion="Compras aprobadas (OC) o consumo de bodega de Softland, por equipo, faena y familia. Sin combustible de reventa." />
    </>
  )
}
