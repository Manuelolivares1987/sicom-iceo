'use client'

import { useState } from 'react'
import { Download, RefreshCw, Trash2, CheckCircle2, AlertTriangle, Loader2, Eraser } from 'lucide-react'
import { useDownloadJornadas, useSyncPending, useClearCalamaOfflineDB, useDiscardFailedItems, useNetworkStatus, useCalamaOfflineCounters } from '@/hooks/use-calama-offline'
import { useToast } from '@/contexts/toast-context'

export function OfflineActions() {
  const toast = useToast()
  const online = useNetworkStatus()
  const { run: download, pending: dlPending, lastError: dlError } = useDownloadJornadas()
  const { run: sync, pending: syncPending, lastResult: syncResult } = useSyncPending()
  const { run: clear, pending: clearPending } = useClearCalamaOfflineDB()
  const { run: discard, pending: discardPending } = useDiscardFailedItems()
  const { counters, refresh } = useCalamaOfflineCounters(0)
  const [showAvanzado, setShowAvanzado] = useState(false)

  const handleDownload = async () => {
    if (!online) { toast.error('Sin conexion: no se pueden descargar jornadas'); return }
    try {
      const r = await download()
      toast.success(`${r.jornadas_count} jornadas descargadas para offline`)
      void refresh()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al descargar')
    }
  }

  const handleSync = async () => {
    if (!online) { toast.error('Sin conexion: no se puede sincronizar'); return }
    const r = await sync()
    if (r.ok > 0 || r.err > 0) {
      if (r.err === 0) toast.success(`${r.ok} sincronizados`)
      else if (r.ok === 0) toast.error(`Fallaron ${r.err} envios`)
      else toast.warning(`${r.ok} OK, ${r.err} con error`)
    } else {
      toast.info('Nada pendiente para sincronizar')
    }
    void refresh()
  }

  const handleClear = async () => {
    if (!confirm('¿Borrar TODOS los datos offline de este telefono? Solo hazlo en dispositivos que ya no usaras.')) return
    await clear()
    toast.success('Datos offline borrados')
    void refresh()
  }

  const totalErrConf = (counters?.errores ?? 0) + (counters?.conflictos ?? 0)
  const handleDiscard = async () => {
    if (totalErrConf === 0) { toast.info('No hay eventos con error o conflicto para descartar'); return }
    if (!confirm(
      `Vas a descartar ${totalErrConf} item(s) que el server rechazo o que tienen error. ` +
      'Sus fotos/firmas locales asociadas tambien se borran. Los eventos pendientes (no enviados) se conservan. Continuar?'
    )) return
    const r = await discard()
    toast.success(
      `Descartado: ${r.events} eventos, ${r.evidencias} fotos, ${r.firmas} firmas, ${r.blobs} archivos locales.`,
    )
    void refresh()
  }

  return (
    <div className="space-y-2">
      <div className="grid grid-cols-2 gap-2">
        <button
          onClick={handleDownload} disabled={dlPending || !online}
          className="rounded-lg border border-blue-300 bg-blue-50 px-3 py-2 text-xs font-medium text-blue-800 hover:bg-blue-100 disabled:opacity-50 inline-flex items-center justify-center gap-1.5"
        >
          {dlPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
          Descargar jornadas
        </button>
        <button
          onClick={handleSync} disabled={syncPending || !online || (counters?.pendientes ?? 0) === 0 && (counters?.errores ?? 0) === 0}
          className="rounded-lg border border-green-300 bg-green-50 px-3 py-2 text-xs font-medium text-green-800 hover:bg-green-100 disabled:opacity-50 inline-flex items-center justify-center gap-1.5"
        >
          {syncPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <RefreshCw className="h-4 w-4" />}
          Sincronizar
        </button>
      </div>

      {dlError && (
        <div className="rounded border border-red-200 bg-red-50 p-2 text-[11px] text-red-800 flex items-start gap-1">
          <AlertTriangle className="h-3 w-3 mt-0.5 shrink-0" /> {dlError}
        </div>
      )}
      {syncResult && (syncResult.ok > 0 || syncResult.err > 0) && (
        <div className={`rounded border p-2 text-[11px] flex items-start gap-1 ${
          syncResult.err === 0 ? 'border-green-200 bg-green-50 text-green-800'
            : 'border-amber-200 bg-amber-50 text-amber-900'
        }`}>
          {syncResult.err === 0 ? <CheckCircle2 className="h-3 w-3 mt-0.5 shrink-0" /> : <AlertTriangle className="h-3 w-3 mt-0.5 shrink-0" />}
          <div className="flex-1">
            {syncResult.ok} sincronizados, {syncResult.err} con error
            {syncResult.errors.slice(0, 3).map((e, i) => (
              <div key={i} className="text-[10px] opacity-80">• {e.tipo}: {e.mensaje}</div>
            ))}
          </div>
        </div>
      )}

      <button
        onClick={() => setShowAvanzado((v) => !v)}
        className="text-[10px] text-gray-500 underline"
      >
        {showAvanzado ? 'Ocultar' : 'Avanzado'}
      </button>
      {showAvanzado && (
        <div className="space-y-2">
          <button
            onClick={handleDiscard} disabled={discardPending || totalErrConf === 0}
            className="w-full rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-xs font-medium text-amber-900 hover:bg-amber-100 disabled:opacity-50 inline-flex items-center justify-center gap-1.5"
          >
            {discardPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Eraser className="h-4 w-4" />}
            Descartar eventos con error/conflicto ({totalErrConf})
          </button>
          <button
            onClick={handleClear} disabled={clearPending}
            className="w-full rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-xs font-medium text-red-800 hover:bg-red-100 disabled:opacity-50 inline-flex items-center justify-center gap-1.5"
          >
            {clearPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Trash2 className="h-4 w-4" />}
            Borrar datos offline de este telefono
          </button>
        </div>
      )}
    </div>
  )
}
