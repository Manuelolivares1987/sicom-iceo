import { VolverAlPanel } from '@/components/layout/volver-al-panel'

// La venta de Franke era la única app de terreno sin layout propio, y por eso
// la única sin puerta de vuelta al panel.
export default function FrankeVentaMobileLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      {children}
      <VolverAlPanel />
    </>
  )
}
