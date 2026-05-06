'use client'

import { Wifi, WifiOff, AlertTriangle, CheckCircle2, Loader2 } from 'lucide-react'
import { useNetworkStatus, useCalamaOfflineCounters, useAutoSyncOnOnline } from '@/hooks/use-calama-offline'

export function OfflineStatusBanner() {
  const online = useNetworkStatus()
  const { counters } = useCalamaOfflineCounters(4000)
  const autoSync = useAutoSyncOnOnline()
  void autoSync

  if (!counters) {
    return null
  }
  const pendientes = counters.pendientes
  const errores = counters.errores

  let cls = 'border-green-200 bg-green-50 text-green-800'
  let Icon = Wifi
  let txt = 'Con conexion'
  if (!online) {
    cls = 'border-red-200 bg-red-50 text-red-800'
    Icon = WifiOff
    txt = 'Sin conexion: trabajando offline'
  } else if (pendientes > 0) {
    cls = 'border-amber-200 bg-amber-50 text-amber-800'
    Icon = Loader2
    txt = `${pendientes} pendiente${pendientes === 1 ? '' : 's'} de sincronizar`
  } else if (errores > 0) {
    cls = 'border-orange-300 bg-orange-50 text-orange-800'
    Icon = AlertTriangle
    txt = `${errores} con error de sincronizacion`
  }

  return (
    <div className={`rounded-lg border px-3 py-2 text-xs flex items-center gap-2 ${cls}`}>
      <Icon className={`h-4 w-4 shrink-0 ${pendientes > 0 && online ? 'animate-spin' : ''}`} />
      <span className="flex-1">{txt}</span>
      {counters.last_download_at && (
        <span className="text-[10px] opacity-70">
          Descargado: {new Date(counters.last_download_at).toLocaleString('es-CL', {
            day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
          })}
        </span>
      )}
    </div>
  )
}

export function OfflineCountersCompact() {
  const { counters } = useCalamaOfflineCounters(4000)
  if (!counters || (counters.pendientes === 0 && counters.errores === 0 && counters.jornadas_offline === 0)) {
    return null
  }
  return (
    <div className="flex flex-wrap gap-2 text-[10px]">
      {counters.jornadas_offline > 0 && (
        <span className="rounded bg-blue-50 border border-blue-200 px-2 py-0.5 text-blue-700">
          <CheckCircle2 className="h-3 w-3 inline mr-0.5" />
          {counters.jornadas_offline} jornadas offline
        </span>
      )}
      {counters.pendientes_eventos > 0 && (
        <span className="rounded bg-amber-50 border border-amber-200 px-2 py-0.5 text-amber-700">
          {counters.pendientes_eventos} eventos pendientes
        </span>
      )}
      {counters.pendientes_evidencias > 0 && (
        <span className="rounded bg-amber-50 border border-amber-200 px-2 py-0.5 text-amber-700">
          {counters.pendientes_evidencias} fotos pendientes
        </span>
      )}
      {counters.pendientes_firmas > 0 && (
        <span className="rounded bg-amber-50 border border-amber-200 px-2 py-0.5 text-amber-700">
          {counters.pendientes_firmas} firmas pendientes
        </span>
      )}
      {counters.errores > 0 && (
        <span className="rounded bg-red-50 border border-red-200 px-2 py-0.5 text-red-700">
          {counters.errores} con error
        </span>
      )}
    </div>
  )
}
