'use client'

// [19-11-2026] Antes no había error boundary: cualquier error de render (o un
// chunk de una versión vieja) dejaba la pantalla en blanco o en su spinner.
import { useEffect } from 'react'
import { esErrorDeChunk, recuperarVersion } from '@/lib/recuperar-version'
import { repararApp } from '@/components/layout/redireccion-segura'

export default function ErrorPantalla({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  const deChunk = esErrorDeChunk(error)
  useEffect(() => {
    console.error('[SICOM] error de pantalla', error)
    if (deChunk) recuperarVersion()
  }, [error, deChunk])

  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-4 px-6 text-center">
      <p className="text-base font-semibold text-gray-900">
        {deChunk ? 'Actualizando la app…' : 'Algo falló al abrir esta pantalla'}
      </p>
      <p className="max-w-xs text-sm text-gray-600">
        Lo que tenga guardado sin señal no se pierde. No cierre sesión.
      </p>
      <div className="flex w-full max-w-xs flex-col gap-2">
        <button type="button" onClick={() => reset()}
                className="rounded-lg bg-gray-900 px-4 py-3 text-sm font-semibold text-white">
          Reintentar
        </button>
        <button type="button" onClick={() => repararApp()}
                className="rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-medium text-gray-700">
          Reparar app
        </button>
      </div>
    </div>
  )
}
