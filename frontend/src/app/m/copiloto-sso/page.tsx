'use client'

// Copiloto Prevención Centinela en el teléfono (MIG734): supervisores ENEX y APR.
import { ArrowLeft, ShieldCheck } from 'lucide-react'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { Spinner } from '@/components/ui/spinner'
import { BotonSalir } from '@/components/layout/boton-salir'
import { ChatCopilotoSso } from '@/components/copiloto-sso/chat'

export default function CopilotoSsoMovil() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  if (sinSesionOffline) return <SinSesionOffline />
  if (verificando) return <div className="flex justify-center py-10"><Spinner /></div>
  return (
    <div className="mx-auto max-w-[560px]">
      <header className="sticky top-0 z-30 flex items-center gap-2 bg-emerald-700 px-2 py-2 text-white">
        <button type="button" onClick={() => history.back()} aria-label="Volver"
                className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-full hover:bg-white/10">
          <ArrowLeft className="h-5 w-5" aria-hidden="true" />
        </button>
        <div className="min-w-0 flex-1">
          <h1 className="flex items-center gap-1.5 text-base font-bold"><ShieldCheck className="h-5 w-5 shrink-0" aria-hidden="true" />Copiloto Prevención</h1>
          <p className="text-[11px] opacity-90">Minera Centinela · RECSS, EDC y Lecciones Aprendidas</p>
        </div>
        <BotonSalir className="hover:bg-white/10" />
      </header>
      <ChatCopilotoSso compacto />
    </div>
  )
}
