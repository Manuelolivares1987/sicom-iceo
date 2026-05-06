'use client'

import { useEffect, useState } from 'react'
import { MapPin, MapPinOff, AlertTriangle, RefreshCw } from 'lucide-react'
import { tryGeolocate, type GeoFix } from '@/lib/services/calama-jornada'

interface GeoStatusProps {
  onChange?: (fix: GeoFix) => void
  // Si true, intenta solicitar GPS al montar.
  autoRequest?: boolean
  compact?: boolean
}

// Componente UI que solicita ubicacion GPS, muestra estado actual y notifica
// al consumidor cada vez que se obtiene un fix nuevo. NO bloquea el flujo si
// el usuario rechaza, pero deja constancia visible.
export function GeoStatus({ onChange, autoRequest = true, compact }: GeoStatusProps) {
  const [fix, setFix] = useState<GeoFix>({ lat: null, lng: null, accuracy: null, status: 'unavailable' })
  const [loading, setLoading] = useState(false)

  const refresh = async () => {
    setLoading(true)
    try {
      const f = await tryGeolocate()
      setFix(f)
      onChange?.(f)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (autoRequest) void refresh()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const config = (() => {
    switch (fix.status) {
      case 'granted':
        return { icon: MapPin, txt: 'GPS OK', cls: 'bg-green-100 text-green-800 border-green-200' }
      case 'denied':
        return { icon: MapPinOff, txt: 'GPS denegado', cls: 'bg-red-100 text-red-800 border-red-200' }
      case 'unavailable':
        return { icon: MapPinOff, txt: 'GPS no disponible', cls: 'bg-gray-100 text-gray-700 border-gray-200' }
      case 'error':
      default:
        return { icon: AlertTriangle, txt: 'GPS error', cls: 'bg-amber-100 text-amber-800 border-amber-200' }
    }
  })()

  const Icon = config.icon

  if (compact) {
    return (
      <button
        type="button" onClick={refresh} disabled={loading}
        className={`inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[10px] font-medium ${config.cls}`}
        title={fix.accuracy ? `Precision ${Math.round(fix.accuracy)}m` : 'Refrescar GPS'}
      >
        <Icon className="h-3 w-3" />
        {config.txt}
        {fix.accuracy && fix.status === 'granted' && (
          <span className="ml-0.5 font-mono">±{Math.round(fix.accuracy)}m</span>
        )}
      </button>
    )
  }

  return (
    <div className={`rounded-lg border p-2 text-xs flex items-center gap-2 ${config.cls}`}>
      <Icon className="h-4 w-4 shrink-0" />
      <div className="flex-1">
        <div className="font-medium">{config.txt}</div>
        {fix.status === 'granted' && (
          <div className="font-mono text-[10px]">
            {fix.lat?.toFixed(5)}, {fix.lng?.toFixed(5)}
            {fix.accuracy && <> · ±{Math.round(fix.accuracy)}m</>}
          </div>
        )}
        {fix.status === 'denied' && (
          <div className="text-[10px]">
            Permite la ubicacion en tu navegador para auditoria correcta de eventos.
          </div>
        )}
      </div>
      <button
        onClick={refresh} disabled={loading}
        className="rounded p-1 hover:bg-white/50 disabled:opacity-50"
        title="Refrescar GPS" aria-label="Refrescar GPS"
      >
        <RefreshCw className={`h-3 w-3 ${loading ? 'animate-spin' : ''}`} />
      </button>
    </div>
  )
}
