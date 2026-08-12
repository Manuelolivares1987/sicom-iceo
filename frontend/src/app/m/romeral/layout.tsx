import SugerenciaWidget from '@/components/sugerencias/sugerencia-widget'

export default function RomeralMobileLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="mx-auto min-h-screen max-w-[480px] bg-gray-50">
      {children}
      {/* El operador del camión reporta desde la misma app lo que le falta o le
          estorba: es quien mejor sabe si el registro le sirve o le complica. */}
      <SugerenciaWidget />
    </div>
  )
}
