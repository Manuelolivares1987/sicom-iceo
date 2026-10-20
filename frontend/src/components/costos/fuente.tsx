'use client'

import { createContext, useContext } from 'react'
import type { FuenteCosto } from '@/lib/services/costos-operacion'

// De dónde sale el gasto que muestra el panel (MIG628). Lo fija el selector de
// PanelCostosOperacion y lo leen el Pareto, las faenas y sus modales.
export const FuenteCostosContext = createContext<FuenteCosto>('oc')
export const useFuenteCostos = () => useContext(FuenteCostosContext)

export const NOMBRE_FUENTE: Record<FuenteCosto, string> = {
  oc: 'Compras aprobadas (OC)',
  bodega: 'Consumo de bodega',
}
