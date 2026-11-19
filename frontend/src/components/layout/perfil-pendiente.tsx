'use client'

// ============================================================================
// Sesión sin perfil todavía (19-11-2026)
// ----------------------------------------------------------------------------
// El menú, los permisos y la faena salen del perfil. Sin él, el panel mostraba
// el menú general a nombre de «Usuario» —a un mecánico de Franke acotado a su
// faena le aparecía Contrato ENEX (Calama)—. Ahora, mientras el perfil no
// llega, se espera (con reintento automático en auth-context) y se ofrece
// salida; nunca se muestra un menú que no es el de la persona.
// ============================================================================

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useAuth } from '@/contexts/auth-context'
import { Spinner } from '@/components/ui/spinner'

export function PerfilPendiente() {
  const { perfilEstado, reintentarPerfil, signOut, user } = useAuth()
  const router = useRouter()
  const [lento, setLento] = useState(false)

  useEffect(() => {
    const t = setTimeout(() => setLento(true), 8000)
    return () => clearTimeout(t)
  }, [])

  const salir = async () => { if (await signOut()) router.replace('/login') }

  if (perfilEstado === 'sin_perfil') {
    return (
      <Caja>
        <p className="text-base font-semibold text-gray-900">Su cuenta no tiene perfil asignado</p>
        <p className="text-sm text-gray-600">
          {user?.email ? <><b>{user.email}</b> no está habilitada en SICOM. </> : null}
          Pida al administrador que la configure. Revise también que entró con su correo de trabajo.
        </p>
        <Boton onClick={salir} principal>Entrar con otra cuenta</Boton>
      </Caja>
    )
  }

  const conError = perfilEstado === 'error'
  return (
    <Caja>
      <Spinner size="lg" className="text-gray-400" />
      {(conError || lento) && (
        <>
          <p className="text-sm text-gray-600">
            {conError
              ? 'No se pudieron traer sus datos (señal débil). Se reintenta solo.'
              : 'Está tardando más de lo normal en traer sus datos.'}
          </p>
          <Boton onClick={reintentarPerfil} principal>Reintentar ahora</Boton>
          <Boton onClick={salir}>Entrar con otra cuenta</Boton>
        </>
      )}
    </Caja>
  )
}

function Caja({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-screen flex-col items-center justify-center gap-4 px-6 text-center">
      <div className="flex w-full max-w-xs flex-col items-center gap-3">{children}</div>
    </div>
  )
}

function Boton({ children, onClick, principal }: { children: React.ReactNode; onClick: () => void; principal?: boolean }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={principal
        ? 'w-full rounded-lg bg-gray-900 px-4 py-3 text-sm font-semibold text-white active:bg-gray-700'
        : 'w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-medium text-gray-700 active:bg-gray-100'}
    >
      {children}
    </button>
  )
}

export default PerfilPendiente
