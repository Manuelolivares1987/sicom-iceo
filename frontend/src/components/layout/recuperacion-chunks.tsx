'use client'

// Escucha los errores de carga de chunks que no pasan por un error boundary
// (navegación interna, import() perezoso) y recupera la versión. Ver
// src/lib/recuperar-version.ts.
import { useEffect } from 'react'
import { esErrorDeChunk, recuperarVersion } from '@/lib/recuperar-version'

export function RecuperacionChunks() {
  useEffect(() => {
    const onError = (ev: ErrorEvent) => {
      if (esErrorDeChunk(ev.error ?? ev.message)) recuperarVersion()
    }
    const onRechazo = (ev: PromiseRejectionEvent) => {
      if (esErrorDeChunk(ev.reason)) recuperarVersion()
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
