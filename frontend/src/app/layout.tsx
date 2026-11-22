import type { Metadata, Viewport } from 'next'
import { Inter } from 'next/font/google'
import './globals.css'
import { QueryProvider } from '@/contexts/query-provider'
import { AuthProvider } from '@/contexts/auth-context'
import { ToastProvider } from '@/contexts/toast-context'
import { RecuperacionChunks } from '@/components/layout/recuperacion-chunks'
import { ConectividadInit } from '@/components/layout/conectividad-init'
import { PrecargaTerreno } from '@/components/layout/precarga-terreno'
import { TerrenoGlobal } from '@/components/layout/terreno-global'
import { ActualizacionApp } from '@/components/layout/actualizacion-app'
import { GuardaAlmacenamiento } from '@/components/layout/guarda-almacenamiento'
import { PuenteApp } from '@/components/layout/puente-app'

const inter = Inter({ subsets: ['latin'], weight: ['300', '400', '500', '600', '700', '800'], display: 'swap', variable: '--font-inter' })

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
  // Meta moderno (no deprecated). Apple sigue requiriendo apple-mobile-web-app-capable
  // que Next.js inyecta via appleWebApp arriba; mobile-web-app-capable es el equivalente
  // estandar para Chrome/Edge y reemplaza al deprecated.
  other: {
    'mobile-web-app-capable': 'yes',
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
  // [22-11-2026] Se permite el zoom (WCAG 1.4.4): bloquearlo impedía agrandar
  // la letra a quien la necesita. Los campos usan 16 px y no hacen auto-zoom.
  viewportFit: 'cover',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="es" className={inter.variable}>
      <body>
        <RecuperacionChunks />
        <ConectividadInit />
        <ActualizacionApp />
        <PuenteApp />
        <GuardaAlmacenamiento>
        <QueryProvider>
          <AuthProvider>
            <PrecargaTerreno />
            <TerrenoGlobal />
            <ToastProvider>{children}</ToastProvider>
          </AuthProvider>
        </QueryProvider>
        </GuardaAlmacenamiento>
      </body>
    </html>
  )
}
