import SugerenciaWidget from '@/components/sugerencias/sugerencia-widget'
import { SalidaTerrenoPrevencion } from '@/components/prevencion/salida-terreno'

export default function PrevencionMobileLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="mx-auto min-h-screen max-w-[480px] bg-gray-50">
      {children}
      {/* El supervisor que carga sus RIT en el teléfono es quien mejor sabe si
          la pantalla le sirve o le estorba. */}
      <SugerenciaWidget />
      {/* Cerrar sesión para todos; «Volver al panel» sólo para quien tiene panel. */}
      <SalidaTerrenoPrevencion />
    </div>
  )
}
