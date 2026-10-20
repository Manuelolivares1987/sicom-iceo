'use client'

import { useRequireAuth } from '@/hooks/use-require-auth'
import { PanelCostosOperacion } from '@/components/costos/panel-costos'
import { ConciliacionUbicacion } from '@/components/costos/conciliacion-ubicacion'

// ============================================================================
// Flota · Costo por faena y por equipo (MIG598-603)
// ----------------------------------------------------------------------------
// El mismo panel de Costos de Operación (tarjetas, qué revisar, gasto mensual,
// faenas, equipos, Pareto en cada clic) + dónde está cada camión según ficha,
// estado diario y GPS. Mismo permiso (fn_costos_operacion_puede_ver).
// ============================================================================

export default function FlotaCostosPage() {
  useRequireAuth()
  return (
    <PanelCostosOperacion
      titulo="Costo por faena y por equipo"
      descripcion="Compras aprobadas (OC) o consumo de bodega de Softland, por equipo, faena y familia. Sin combustible de reventa."
      despues={<ConciliacionUbicacion />} />
  )
}
