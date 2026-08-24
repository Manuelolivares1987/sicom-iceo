'use client'

// ============================================================================
// Franke en el teléfono — portada
// ----------------------------------------------------------------------------
// Una entrada por rol y nada más. El mecánico abre su pauta, no un menú de
// módulos: el sistema que obliga a elegir dónde entrar es el que se deja de
// usar en la segunda semana.
// ============================================================================

import Link from 'next/link'
import { ClipboardList, ChevronRight, Fuel, ArrowLeftRight, Gauge } from 'lucide-react'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { Spinner } from '@/components/ui/spinner'

// Cada rol ve lo suyo y nada más. Un mecánico que toca «Entrega de turno» choca
// contra un error de permisos que él no puede resolver, y a la tercera vez deja
// de abrir la app. Es más barato no mostrar el botón.
const ACCESOS = [
  {
    href: '/m/franke/pauta',
    icono: ClipboardList,
    titulo: 'Revisión de equipos',
    bajada: 'La pauta del mecánico, por equipo y por día',
    roles: ['tecnico_mantenimiento', 'operador_taller', 'jefe_mantenimiento',
            'supervisor', 'planificador', 'jefe_operaciones', 'administrador'],
  },
  {
    href: '/m/franke/despacho',
    icono: Fuel,
    titulo: 'Despacho de combustible',
    bajada: 'Cada carga con su folio de ticket, sin señal',
    roles: ['operador_combustible', 'supervisor', 'planificador',
            'jefe_operaciones', 'administrador'],
  },
  {
    href: '/m/franke/carga',
    icono: Gauge,
    titulo: 'Carga del camión',
    bajada: 'Lo que entra por el surtidor, contra lo que recibió el camión',
    roles: ['supervisor', 'planificador', 'jefe_operaciones', 'administrador'],
  },
  {
    href: '/m/franke/entrega',
    icono: ArrowLeftRight,
    titulo: 'Entrega de turno',
    bajada: 'Camiones, litros, pendientes y bodega · dos firmas',
    roles: ['supervisor', 'planificador', 'jefe_operaciones', 'administrador'],
  },
]

export default function FrankeMobileHome() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil } = useAuth()

  if (verificando) {
    return <div className="flex min-h-screen items-center justify-center bg-gray-50"><Spinner className="h-8 w-8" /></div>
  }
  if (sinSesionOffline) return <SinSesionOffline />

  const mios = ACCESOS.filter((a) => !perfil?.rol || a.roles.includes(perfil.rol))

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="border-b border-gray-200 bg-white px-4 pb-5 pt-[max(1.25rem,env(safe-area-inset-top))]">
        <p className="text-lg font-bold leading-tight text-gray-900">Faena Franke</p>
        <p className="text-xs text-gray-500">
          Contrato FRK 220/2024 · CM Cenizas
          {perfil?.nombre_completo ? ` · ${perfil.nombre_completo}` : ''}
        </p>
      </header>

      <main className="space-y-3 px-4 py-5">
        {mios.map((a) => (
          <Link key={a.href} href={a.href}
                className="flex items-center gap-3 rounded-xl border-2 border-gray-200 bg-white p-4 active:scale-[0.99]">
            <div className="grid h-12 w-12 shrink-0 place-items-center rounded-lg bg-gray-900 text-white">
              <a.icono className="h-6 w-6" />
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-base font-bold text-gray-900">{a.titulo}</p>
              <p className="text-xs text-gray-500">{a.bajada}</p>
            </div>
            <ChevronRight className="h-5 w-5 shrink-0 text-gray-400" />
          </Link>
        ))}

        {mios.length === 0 && (
          <p className="rounded-xl border border-dashed border-gray-300 bg-white p-6 text-center text-sm text-gray-500">
            Su cuenta no tiene nada asignado en esta faena. Avise a quien administra el sistema.
          </p>
        )}
      </main>
    </div>
  )
}
