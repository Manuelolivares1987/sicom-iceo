'use client'

// Último recurso: falla el layout raíz. Debe traer su propio <html>/<body>.
import { useEffect } from 'react'
import { esErrorDeChunk, recuperarVersion } from '@/lib/recuperar-version'
import { repararApp } from '@/components/layout/redireccion-segura'
import { detalleError } from '@/lib/detalle-error'
import { reportarError } from '@/lib/reportar-error'
import { esErrorDeAlmacenamiento } from '@/lib/almacenamiento'
import { PantallaAlmacenamientoBloqueado } from '@/components/layout/almacenamiento-bloqueado'

export default function GlobalError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    console.error('[SICOM] error global', error)
    reportarError('global', error)
    if (esErrorDeChunk(error)) recuperarVersion()
  }, [error])

  if (esErrorDeAlmacenamiento(error)) {
    return <html lang="es"><body><PantallaAlmacenamientoBloqueado /></body></html>
  }

  return (
    <html lang="es">
      <body style={{ fontFamily: 'system-ui, sans-serif', display: 'flex', minHeight: '100vh', alignItems: 'center',
                     justifyContent: 'center', flexDirection: 'column', gap: 12, padding: 24, textAlign: 'center' }}>
        <p style={{ fontWeight: 600 }}>La app no pudo abrir</p>
        <p style={{ fontSize: 14, color: '#4b5563', maxWidth: 320 }}>
          Lo que tenga guardado sin señal no se pierde. No cierre sesión.
        </p>
        <button type="button" onClick={() => reset()} style={{ padding: '12px 16px', width: 260, borderRadius: 8, background: '#111827', color: '#fff', border: 0 }}>
          Reintentar
        </button>
        <button type="button" onClick={() => repararApp()} style={{ padding: '12px 16px', width: 260, borderRadius: 8, background: '#fff', border: '1px solid #d1d5db' }}>
          Reparar app
        </button>
        {/* [20-11-2026] El detalle exacto, para que una foto del teléfono baste
            para saber qué falló (no se podía reproducir desde la oficina). */}
        <p style={{ fontSize: 11, color: '#6b7280', maxWidth: 320, wordBreak: 'break-word', marginTop: 8 }}>
          {detalleError(error)}
        </p>
      </body>
    </html>
  )
}
