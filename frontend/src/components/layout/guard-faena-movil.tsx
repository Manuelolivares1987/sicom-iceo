'use client'

// [MIG714] Quien está acotado a su faena tampoco entra a las apps de terreno de otras
// (taller de Coquimbo, Romeral, Calama, ENEX…): vuelve a la de su faena. Sin perfil
// cargado (offline sin caché) no redirige: nunca deja a alguien en el limbo sin señal.
import { useEffect } from 'react'
import { usePathname, useRouter } from 'next/navigation'
import { usePermissions } from '@/hooks/use-permissions'
import { rutaMovilPermitida } from '@/lib/faena-acotada'

export function GuardFaenaMovil() {
  const pathname = usePathname()
  const router = useRouter()
  const { faenaExclusiva } = usePermissions()
  const faena = faenaExclusiva()
  useEffect(() => {
    if (!faena || !pathname) return
    if (!rutaMovilPermitida(pathname, faena)) router.replace(faena.app_movil ?? faena.panel_web ?? '/dashboard')
  }, [faena, pathname, router])
  return null
}
