'use client'

import { rutaWebPermitida, type FaenaAcotada } from '@/lib/faena-acotada'
import { usePathname } from 'next/navigation'
import { RedireccionSegura } from '@/components/layout/redireccion-segura'
import AppShell from '@/components/layout/app-shell'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { usePermissions } from '@/hooks/use-permissions'
import { useAuth } from '@/contexts/auth-context'
import { Spinner } from '@/components/ui/spinner'

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const { loading } = useRequireAuth()
  const { perfil } = useAuth()
  const { esOperadorCalamaSolo, esSupervisorCalamaSolo, esOperadorTallerSolo, faenaExclusiva,
          esOperadorCombustibleSolo } = usePermissions()
  const pathname = usePathname()

  // La app de terreno la declara la faena (MIG361), no el rol. Mientras Romeral
  // fue la única faena con app, mandar a todo operador de combustible a
  // /m/romeral era correcto; con Franke adentro sería mandar a un conductor de
  // Taltal al catálogo y a los camiones de otra faena.
  const appDeFaena = perfil?.faena?.app_movil ?? null
  const faenaSolo = faenaExclusiva()

  // Guards de ruta:
  //  - OOCC: cualquier /dashboard/* → /m/calama.
  //  - Operador de Taller: cualquier /dashboard/* → /m/taller.
  //  - Operador de Combustible: cualquier /dashboard/* → la app de su faena.
  //  - Mecánico de una faena con app: su pauta está allá, no en el panel web.
  //  - Supervisor Calama: cualquier /dashboard/* fuera de /dashboard/operacion-calama → /dashboard/operacion-calama.
  //
  // [19-11-2026] Antes cada guard hacía router.replace y mostraba SOLO un
  // spinner mientras tanto. Con señal de faena o una versión vieja en el
  // teléfono la navegación no terminaba y la persona quedaba cargando para
  // siempre (Franke tras MIG714). Ahora el destino se calcula una vez y
  // <RedireccionSegura> escala a navegación completa y ofrece salida.
  function destinoGuard(): string | null {
    if (esOperadorCalamaSolo()) return '/m/calama'
    if (esOperadorTallerSolo()) return '/m/taller'
    // Romeral por defecto: es donde caían antes de que las faenas declararan
    // su app, y una faena sin app no debe dejar a nadie en el limbo.
    if (esOperadorCombustibleSolo()) return appDeFaena ?? '/m/romeral'
    // Un técnico de mantención del taller de Coquimbo sí usa el panel web; el
    // de una faena con app de terreno, no. Por eso la condición es la faena y
    // no el rol.
    if (perfil?.rol === 'tecnico_mantenimiento' && appDeFaena) return appDeFaena
    // [MIG648] La cuenta que trabaja en una app de terreno (supervisores ENEX)
    // entra directo a ella. Solo desde la portada; el resto del panel sigue abierto.
    if (perfil?.app_terreno && /^\/dashboard\/?$/.test(pathname)) return perfil.app_terreno
    if (esSupervisorCalamaSolo() && !pathname.startsWith('/dashboard/operacion-calama')) {
      return '/dashboard/operacion-calama'
    }
    // [MIG385] Quien responde por una faena se queda en las pantallas de su
    // menú. Esconderlas del sidebar sin cerrar la ruta dejaría el sistema
    // completo a un enlace pegado de distancia.
    if (faenaSolo && !rutaPermitidaEnFaena(pathname, faenaSolo)) {
      return faenaSolo.panel_web ?? faenaSolo.app_movil ?? '/dashboard'
    }
    return null
  }

  if (loading) {
    return (
      <div className="flex h-screen items-center justify-center">
        <Spinner size="lg" className="text-gray-400" />
      </div>
    )
  }

  const destino = destinoGuard()
  // Nunca redirigir a la misma pantalla: eso era otra ruedita eterna posible
  // (faena acotada sin panel_web ni app_movil, parado en /dashboard).
  if (destino && normalizar(destino) !== normalizar(pathname)) {
    return <RedireccionSegura destino={conSlash(destino)} />
  }

  return <AppShell>{children}</AppShell>
}

/**
 * [MIG385] Las pantallas del menú de faena, y sólo ésas.
 *
 * Es una lista blanca y no una negra a propósito: con una lista negra, cada
 * pantalla nueva del sistema queda abierta hasta que alguien se acuerde de
 * cerrarla. Así, lo que no está escrito acá no se ve.
 */
function rutaPermitidaEnFaena(
  pathname: string,
  faena: FaenaAcotada,
): boolean {
  // [MIG714] lista única con extras por faena (Franke: bodega, copiloto, mis OTs)
  return rutaWebPermitida(pathname, faena)
}

const normalizar = (r: string) => (r.split('?')[0] || '/').replace(/\/+$/, '') || '/'

/** trailingSlash: true — ir directo a la URL final evita un salto 308 más con mala señal. */
function conSlash(r: string): string {
  const [ruta, query] = r.split('?')
  const conBarra = ruta.endsWith('/') ? ruta : `${ruta}/`
  return query ? `${conBarra}?${query}` : conBarra
}
