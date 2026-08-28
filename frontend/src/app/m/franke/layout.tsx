import SugerenciaWidget from '@/components/sugerencias/sugerencia-widget'
import { VolverAlPanel } from '@/components/layout/volver-al-panel'
import { SincronizadorFranke } from '@/components/franke/sincronizador'

export default function FrankeMobileLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="mx-auto min-h-screen max-w-[480px] bg-gray-50">
      {children}
      {/* Sube lo que quedó esperando desde cualquier pantalla de la faena. Vive
          acá y no en cada página porque el que termina la última pauta del día
          sin señal se guarda el teléfono y se va. */}
      <SincronizadorFranke />
      {/* El mecánico y el conductor son quienes mejor saben si la pantalla les
          sirve o les estorba. Que lo puedan decir desde donde trabajan. */}
      <SugerenciaWidget />
      <VolverAlPanel />
    </div>
  )
}
