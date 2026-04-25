import type { Metadata, Viewport } from 'next'
import './globals.css'
import { QueryProvider } from '@/contexts/query-provider'
import { AuthProvider } from '@/contexts/auth-context'
import { ToastProvider } from '@/contexts/toast-context'

export const metadata: Metadata = {
  title: 'SICOM-ICEO | Pillado Empresas',
  description:
    'Sistema Integral de Control Operacional — Plataforma de gestión y monitoreo de indicadores operacionales, mantenimiento, abastecimiento y cumplimiento para operaciones industriales.',
  applicationName: 'SICOM',
  manifest: '/manifest.json',
  appleWebApp: {
    capable: true,
    statusBarStyle: 'default',
    title: 'SICOM',
  },
  formatDetection: {
    telephone: false,
  },
  icons: {
    icon: [
      { url: '/images/icon-192.png', sizes: '192x192', type: 'image/png' },
      { url: '/images/icon-512.png', sizes: '512x512', type: 'image/png' },
    ],
    apple: '/images/icon-192.png',
    shortcut: '/images/logo_empresa_2.png',
  },
}

export const viewport: Viewport = {
  themeColor: '#16a34a',
  width: 'device-width',
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  viewportFit: 'cover',
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
          <AuthProvider>
            <ToastProvider>{children}</ToastProvider>
          </AuthProvider>
        </QueryProvider>
      </body>
    </html>
  )
}
