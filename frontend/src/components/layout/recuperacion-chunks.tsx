'use client'

// Escucha los errores de carga de chunks que no pasan por un error boundary
// (navegación interna, import() perezoso) y recupera la versión. Ver
// src/lib/recuperar-version.ts.
import { useEffect } from 'react'
import { esErrorDeChunk, recuperarVersion } from '@/lib/recuperar-version'
import { reportarError } from '@/lib/reportar-error'

export function RecuperacionChunks() {
  useEffect(() => {
    // [MIG722] Todo error de JS sin capturar y todo chunk que no carga se informa.
    const onError = (ev: ErrorEvent) => {
      reportarError(esErrorDeChunk(ev.error ?? ev.message) ? 'chunk' : 'js', ev.error ?? ev.message, { archivo: ev.filename, linea: ev.lineno })
      if (esErrorDeChunk(ev.error ?? ev.message)) recuperarVersion()
    }
    const onRechazo = (ev: PromiseRejectionEvent) => {
      if (esErrorDeChunk(ev.reason)) { reportarError('chunk', ev.reason); recuperarVersion() }
    }
    window.addEventListener('error', onError)
    window.addEventListener('unhandledrejection', onRechazo)
    return () => {
      window.removeEventListener('error', onError)
      window.removeEventListener('unhandledrejection', onRechazo)
    }
  }, [])
  return null
}

export default RecuperacionChunks
