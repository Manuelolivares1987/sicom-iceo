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
      descripcion="Gasto de bodega Softland (repuestos, neumáticos, lubricantes, insumos y EPP). Sin petróleo, que se revende."
      despues={<ConciliacionUbicacion />} />
  )
}
