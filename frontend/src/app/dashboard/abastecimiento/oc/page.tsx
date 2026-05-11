'use client'

import { AlertCircle } from 'lucide-react'
import { OCList } from '@/components/abastecimiento/oc-list'

export default function OCListadoPage() {
  return (
    <div className="space-y-4 p-6">
      <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800 flex items-start gap-2">
        <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />
        <div>
          <strong>Nuevo flujo OC/FIFO.</strong> Las recepciones y salidas FIFO se habilitarán en
          las próximas etapas. Crear una OC no afecta stock.
        </div>
      </div>
      <OCList />
    </div>
  )
}
