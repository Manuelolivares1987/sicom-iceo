import SugerenciaWidget from '@/components/sugerencias/sugerencia-widget'
import { VolverAlPanel } from '@/components/layout/volver-al-panel'

export default function PrevencionMobileLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="mx-auto min-h-screen max-w-[480px] bg-gray-50">
      {children}
      {/* El supervisor que carga sus RIT en el teléfono es quien mejor sabe si
          la pantalla le sirve o le estorba. */}
      <SugerenciaWidget />
      <VolverAlPanel />
    </div>
  )
}
