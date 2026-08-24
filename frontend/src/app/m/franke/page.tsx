'use client'

// ============================================================================
// Franke en el teléfono — portada
// ----------------------------------------------------------------------------
// Una entrada por rol y nada más. El mecánico abre su pauta, no un menú de
// módulos: el sistema que obliga a elegir dónde entrar es el que se deja de
// usar en la segunda semana.
// ============================================================================

import Link from 'next/link'
import { ClipboardList, ChevronRight, Fuel, ArrowLeftRight } from 'lucide-react'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { Spinner } from '@/components/ui/spinner'

export default function FrankeMobileHome() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil } = useAuth()

  if (verificando) {
    return <div className="flex min-h-screen items-center justify-center bg-gray-50"><Spinner className="h-8 w-8" /></div>
  }
  if (sinSesionOffline) return <SinSesionOffline />

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="border-b border-gray-200 bg-white px-4 py-5">
        <p className="text-lg font-bold leading-tight text-gray-900">Faena Franke</p>
        <p className="text-xs text-gray-500">
          Contrato FRK 220/2024 · CM Cenizas
          {perfil?.nombre_completo ? ` · ${perfil.nombre_completo}` : ''}
        </p>
      </header>

      <main className="space-y-3 px-4 py-5">
        <Link href="/m/franke/pauta"
              className="flex items-center gap-3 rounded-xl border-2 border-gray-200 bg-white p-4 active:scale-[0.99]">
          <div className="grid h-12 w-12 shrink-0 place-items-center rounded-lg bg-gray-900 text-white">
            <ClipboardList className="h-6 w-6" />
          </div>
          <div className="min-w-0 flex-1">
            <p className="text-base font-bold text-gray-900">Revisión de equipos</p>
            <p className="text-xs text-gray-500">La pauta del mecánico, por equipo y por día</p>
          </div>
          <ChevronRight className="h-5 w-5 shrink-0 text-gray-400" />
        </Link>

        <div className="rounded-xl border-2 border-dashed border-gray-300 bg-white p-4 opacity-60">
          <div className="flex items-center gap-3">
            <div className="grid h-12 w-12 shrink-0 place-items-center rounded-lg bg-gray-200 text-gray-500">
              <Fuel className="h-6 w-6" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-base font-bold text-gray-700">Despacho de combustible</p>
              <p className="text-xs text-gray-500">Fase 3 · aún se registra en el ticket printer</p>
            </div>
          </div>
        </div>

        <div className="rounded-xl border-2 border-dashed border-gray-300 bg-white p-4 opacity-60">
          <div className="flex items-center gap-3">
            <div className="grid h-12 w-12 shrink-0 place-items-center rounded-lg bg-gray-200 text-gray-500">
              <ArrowLeftRight className="h-6 w-6" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-base font-bold text-gray-700">Entrega de turno</p>
              <p className="text-xs text-gray-500">Fase 2 · se está construyendo</p>
            </div>
          </div>
        </div>
      </main>
    </div>
  )
}
