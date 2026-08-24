import SugerenciaWidget from '@/components/sugerencias/sugerencia-widget'

export default function FrankeMobileLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="mx-auto min-h-screen max-w-[480px] bg-gray-50">
      {children}
      {/* El mecánico es quien mejor sabe si la pauta le sirve o le estorba. Que
          lo pueda decir desde la misma pantalla en que trabaja. */}
      <SugerenciaWidget />
    </div>
  )
}
