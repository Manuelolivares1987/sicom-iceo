'use client'

import { useState } from 'react'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { PanelCostosOperacion } from '@/components/costos/panel-costos'
import { InformeMensualCostos } from '@/components/costos/informe-mensual'
import { PresupuestoOperaciones } from '@/components/costos/presupuesto'
import { ConsumosInsumos } from '@/components/costos/consumos-insumos'

const PESTANAS = [
  { id: 'costos', label: 'Costos reales' },
  { id: 'presupuesto', label: 'Presupuesto' },
  { id: 'insumos', label: 'Consumos por insumo' },
] as const

// Costos de Operación (Gerencia). El panel vive en components/costos/panel-costos.tsx
// y lo comparte con Flota → Costo por faena y equipo.
export default function CostosOperacionPage() {
  useRequireAuth()
  const [pestana, setPestana] = useState<(typeof PESTANAS)[number]['id']>('costos')
  // El mes elegido arriba filtra todo el panel; los botones de período lo limpian.
  const [mes, setMes] = useState<string | null>(null)
  return (
    <>
      <div className="mb-4 flex gap-1 rounded-lg bg-gray-100 p-1 sm:inline-flex">
        {PESTANAS.map((p) => (
          <button key={p.id} type="button" onClick={() => setPestana(p.id)}
                  className={`flex-1 rounded-md px-4 py-1.5 text-sm font-medium sm:flex-none ${pestana === p.id ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-600 hover:text-gray-900'}`}>
            {p.label}
          </button>
        ))}
      </div>
      {pestana === 'costos' ? (
        <>
          <InformeMensualCostos mesFiltro={mes} onMes={setMes} />
          <PanelCostosOperacion
            mes={mes} onLimpiarMes={() => setMes(null)}
            titulo="Costos de Operación"
            descripcion="Compras aprobadas (OC) o consumo de bodega de Softland, por equipo, faena y familia. Sin combustible de reventa." />
        </>
      ) : pestana === 'presupuesto' ? <PresupuestoOperaciones /> : <ConsumosInsumos />}
    </>
  )
}
