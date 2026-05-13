'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { WifiOff, ArrowLeft, Info } from 'lucide-react'

// Pagina servida por el Service Worker cuando una navegacion (document) no
// esta en cache y no hay red. Reemplaza el error nativo de Chrome
// "no se puede acceder a este sitio".
//
// La ruta original queda en la URL del navegador (el SW no la cambia). Esta
// pantalla la lee de window.location y orienta al usuario a una ruta que SI
// esta cacheada (/m/calama).
export default function OfflinePage() {
  const [originalPath, setOriginalPath] = useState<string | null>(null)
  const [originalOtId, setOriginalOtId] = useState<string | null>(null)

  useEffect(() => {
    if (typeof window === 'undefined') return
    const pathname = window.location.pathname
    setOriginalPath(pathname)
    // /m/calama/ot/<id>
    const m = pathname.match(/^\/m\/calama\/ot\/([^/]+)/)
    if (m) setOriginalOtId(m[1])
  }, [])

  const eraDetalleOT = !!originalOtId

  return (
    <div className="min-h-screen flex items-center justify-center p-4 bg-gradient-to-br from-amber-50 to-orange-100">
      <div className="max-w-sm w-full bg-white rounded-2xl shadow-lg p-6 space-y-4">
        <div className="flex flex-col items-center text-center space-y-2">
          <div className="rounded-full bg-amber-100 p-3">
            <WifiOff className="h-8 w-8 text-amber-700" />
          </div>
          <h1 className="text-lg font-bold text-gray-900">Sin conexion</h1>
          <p className="text-sm text-gray-600">
            Esta pantalla no quedo precargada en el celular. Vuelve a Mis OTs para
            trabajar con las jornadas que descargaste.
          </p>
        </div>

        {originalPath && (
          <div className="rounded-lg bg-gray-50 border border-gray-200 px-3 py-2">
            <p className="text-[10px] uppercase tracking-wider text-gray-500">Ruta solicitada</p>
            <p className="text-xs font-mono text-gray-700 break-all">{originalPath}</p>
          </div>
        )}

        <Link
          href="/m/calama"
          className="flex items-center justify-center gap-2 rounded-lg bg-amber-600 text-white px-4 py-2.5 text-sm font-semibold active:bg-amber-700"
        >
          <ArrowLeft className="h-4 w-4" />
          Volver a Mis OTs Calama
        </Link>

        {eraDetalleOT && (
          <div className="rounded-lg bg-blue-50 border border-blue-200 p-3 flex items-start gap-2">
            <Info className="h-4 w-4 text-blue-700 shrink-0 mt-0.5" />
            <p className="text-xs text-blue-900">
              Para ejecutar OTs sin senal, abre cada una al menos una vez con
              conexion antes de salir a terreno. Asi el celular la guarda en
              cache local.
            </p>
          </div>
        )}
      </div>
    </div>
  )
}
