'use client'

// Sin sesión iniciada y sin señal. Mandar al login no sirve (no puede validar
// credenciales), así que se dice qué pasa y qué hacer, en vez de dejar la
// pantalla en "Cargando…" o rebotando a un formulario inservible.

import { WifiOff, RefreshCw } from 'lucide-react'

export function SinSesionOffline() {
  return (
    <div className="p-6 text-center">
      <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-amber-100">
        <WifiOff className="h-6 w-6 text-amber-600" />
      </div>
      <h1 className="mt-3 text-base font-bold text-gray-800">Sin señal y sin sesión iniciada</h1>
      <p className="mt-1 text-sm text-gray-500">
        Para entrar por primera vez en este teléfono hace falta conexión. Busca señal
        —o conéctate a un wifi— y vuelve a intentar. Una vez dentro, la app queda
        disponible aunque te quedes sin cobertura.
      </p>
      <button
        onClick={() => window.location.reload()}
        className="mt-4 inline-flex items-center gap-2 rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white"
      >
        <RefreshCw className="h-4 w-4" /> Reintentar
      </button>
    </div>
  )
}
