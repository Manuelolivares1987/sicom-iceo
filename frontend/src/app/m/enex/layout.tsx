import SugerenciaWidget from '@/components/sugerencias/sugerencia-widget'
import { VolverAlPanel } from '@/components/layout/volver-al-panel'
import { EnexSyncAgent } from '@/components/enex/sync-agent'

export default function EnexMobileLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="mx-auto min-h-screen max-w-[480px] bg-gray-50">
      {children}
      {/* Envía la cola «Por enviar» sola, en cualquier pantalla de la app. */}
      <EnexSyncAgent />
      {/* Ampolleta de sugerencias: el supervisor de terreno (combustible/lubricantes)
          reporta mejoras/errores al instante desde la app. */}
      <SugerenciaWidget />
      <VolverAlPanel />
    </div>
  )
}
