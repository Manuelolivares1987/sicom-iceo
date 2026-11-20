'use client'

// ============================================================================
// Franke en el teléfono — portada
// ----------------------------------------------------------------------------
// Una entrada por rol y nada más. El mecánico abre su pauta, no un menú de
// módulos: el sistema que obliga a elegir dónde entrar es el que se deja de
// usar en la segunda semana.
// ============================================================================

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { ClipboardList, ChevronRight, Fuel, ArrowLeftRight, Gauge, CalendarDays, ScanBarcode, MessagesSquare, Bot, LogOut } from 'lucide-react'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { Spinner } from '@/components/ui/spinner'

// Cada rol ve lo suyo y nada más. Un mecánico que toca «Entrega de turno» choca
// contra un error de permisos que él no puede resolver, y a la tercera vez deja
// de abrir la app. Es más barato no mostrar el botón.
const ACCESOS = [
  // [MIG696] Primero: es lo que se abre todos los días. Sin señal funciona igual.
  {
    href: '/m/franke/bitacora',
    icono: MessagesSquare,
    titulo: 'Bitácora del turno',
    bajada: 'Novedades, pendientes y «leído y entendido» entre supervisores · sin señal',
    roles: ['supervisor', 'jefe_operaciones', 'administrador'],
  },
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
  // [MIG692] Bodega de faena con lector: sacar, recibir y contar.
  {
    href: '/m/franke/bodega',
    icono: ScanBarcode,
    titulo: 'Bodega',
    bajada: 'Agua, repuestos y EPP con el lector · sacar, recibir, contar',
    // [MIG712] el mecánico de faena saca repuestos/filtros a su camión
    roles: ['supervisor', 'tecnico_mantenimiento', 'operador_taller', 'jefe_operaciones', 'bodeguero', 'administrador'],
  },
  // [19-11-2026] El copiloto del taller ya estaba permitido para Franke
  // (MIG714) pero sin botón: el mecánico no tenía cómo llegar a él.
  {
    href: '/m/taller/copiloto',
    icono: Bot,
    titulo: 'Copiloto del taller',
    bajada: 'Síntoma, foto o código de falla: diagnóstico con los manuales',
    roles: ['tecnico_mantenimiento', 'operador_taller', 'jefe_mantenimiento',
            'supervisor', 'jefe_operaciones', 'administrador'],
  },
  {
    href: '/m/franke/entrega',
    icono: ArrowLeftRight,
    titulo: 'Entrega de turno',
    bajada: 'Camiones, litros, pendientes y bodega · dos firmas',
    roles: ['supervisor', 'planificador', 'jefe_operaciones', 'administrador'],
  },
  // [MIG392] Va primero en la cabeza de quien entra a trabajar —«¿en qué día
  // vamos?»— pero último en la lista: se mira una vez al día, no cada vez que
  // se abre la app.
  {
    href: '/m/franke/turno',
    icono: CalendarDays,
    titulo: 'El turno',
    bajada: 'Los siete días · el último se entrega el status de los camiones',
    roles: ['tecnico_mantenimiento', 'operador_taller', 'operador_combustible',
            'supervisor', 'planificador', 'jefe_operaciones', 'administrador'],
  },
]

export default function FrankeMobileHome() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil, signOut } = useAuth()
  const router = useRouter()

  if (verificando) {
    return <div className="flex min-h-screen items-center justify-center bg-gray-50"><Spinner className="h-8 w-8" /></div>
  }
  if (sinSesionOffline) return <SinSesionOffline />

  const mios = ACCESOS.filter((a) => !perfil?.rol || a.roles.includes(perfil.rol))

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="flex items-start justify-between gap-3 border-b border-gray-200 bg-white px-4 pb-5 pt-[max(1.25rem,env(safe-area-inset-top))]">
        <div className="min-w-0">
          <p className="text-lg font-bold leading-tight text-gray-900">Faena Franke</p>
          <p className="text-xs text-gray-500">
            Contrato FRK 220/2024 · CM Cenizas
            {perfil?.nombre_completo ? ` · ${perfil.nombre_completo}` : ''}
          </p>
        </div>
        {/* [19-11-2026] No había cómo salir: el teléfono de faena se comparte
            entre turnos. signOut avisa si queda trabajo sin enviar. */}
        <button
          type="button"
          onClick={async () => { if (await signOut()) router.replace('/login') }}
          className="flex shrink-0 items-center gap-1.5 rounded-lg border border-gray-300 px-3 py-2 text-xs font-medium text-gray-700 active:bg-gray-100"
        >
          <LogOut className="h-4 w-4" />
          Cerrar sesión
        </button>
      </header>

      <main className="space-y-3 px-4 py-5">
        {/* [MIG696] La difusión es la mitad del problema: la guía siempre a mano. */}
        <Link href="/m/franke/guia" className="block rounded-xl border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-900">
          <b>¿Cómo se usa?</b> Guía corta · todo funciona sin señal →
        </Link>
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
