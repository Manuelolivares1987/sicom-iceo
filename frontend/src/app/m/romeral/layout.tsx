import SugerenciaWidget from '@/components/sugerencias/sugerencia-widget'
import { VolverAlPanel } from '@/components/layout/volver-al-panel'
import { GuardFaenaMovil } from '@/components/layout/guard-faena-movil'

export default function RomeralMobileLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="mx-auto min-h-screen max-w-[480px] bg-gray-50">
      {children}
      {/* El operador del camión reporta desde la misma app lo que le falta o le
          estorba: es quien mejor sabe si el registro le sirve o le complica. */}
      <SugerenciaWidget />
      <VolverAlPanel />
      {/* [MIG714] quien está acotado a su faena no entra a otras apps */}
      <GuardFaenaMovil />
    </div>
  )
}
