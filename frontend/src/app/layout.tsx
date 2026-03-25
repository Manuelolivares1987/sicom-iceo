import type { Metadata } from 'next'
import './globals.css'
import { QueryProvider } from '@/contexts/query-provider'
import { AuthProvider } from '@/contexts/auth-context'

export const metadata: Metadata = {
  title: 'SICOM-ICEO | Pillado Empresas',
  description:
    'Sistema Integral de Control Operacional — Plataforma de gestión y monitoreo de indicadores operacionales, mantenimiento, abastecimiento y cumplimiento para operaciones industriales.',
  icons: {
    icon: '/images/logo_empresa_2.png',
  },
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="es">
      <body>
        <QueryProvider>
          <AuthProvider>{children}</AuthProvider>
        </QueryProvider>
      </body>
    </html>
  )
}
