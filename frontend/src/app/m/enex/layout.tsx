import SugerenciaWidget from '@/components/sugerencias/sugerencia-widget'

export default function EnexMobileLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="mx-auto min-h-screen max-w-[480px] bg-gray-50">
      {children}
      {/* Ampolleta de sugerencias: el supervisor de terreno (combustible/lubricantes)
          reporta mejoras/errores al instante desde la app. */}
      <SugerenciaWidget />
    </div>
  )
}
