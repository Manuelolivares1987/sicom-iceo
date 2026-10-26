'use client'

// Bandeja «Por enviar»: lo guardado en el teléfono que todavía no llega al
// servidor. Como en Kizeo, cada fila dice cuántas fotos van, si está enviando,
// esperando señal o si falló (y por qué), y se puede reintentar a mano.

import { useState } from 'react'
import Link from 'next/link'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { CloudOff, Loader2, AlertTriangle, RefreshCw, Clock } from 'lucide-react'
import { getBandejaEnex, syncEnexPending, type EnexBandejaRow } from '@/lib/offline/enex-offline'

function hace(iso: string | null): string {
  if (!iso) return ''
  const min = Math.round((Date.now() - new Date(iso).getTime()) / 60_000)
  if (min < 1) return 'recién'
  if (min < 60) return `hace ${min} min`
  const h = Math.round(min / 60)
  return h < 24 ? `hace ${h} h` : `hace ${Math.round(h / 24)} d`
}

function Fila({ r }: { r: EnexBandejaRow }) {
  const color = r.estado === 'error' ? 'border-red-200 bg-red-50' : r.estado === 'enviando' ? 'border-blue-200 bg-blue-50' : 'border-amber-200 bg-amber-50'
  return (
    <Link href={`/m/enex/servicio/?id=${r.programacion_id}`} className={`block rounded-lg border p-2 ${color}`}>
      <div className="flex items-center gap-1.5">
        {r.estado === 'enviando' ? <Loader2 className="h-3.5 w-3.5 animate-spin text-blue-600" />
          : r.estado === 'error' ? <AlertTriangle className="h-3.5 w-3.5 text-red-600" />
          : <Clock className="h-3.5 w-3.5 text-amber-600" />}
        <p className="flex-1 truncate text-xs font-semibold text-gray-800">{r.instalacion ?? 'Servicio'}</p>
        <span className="text-[10px] text-gray-500">{r.con_mandante ? 'Cierre' : 'Avance'}</span>
      </div>
      <p className="mt-0.5 text-[11px] text-gray-600">
        {r.estado === 'enviando' ? 'Enviando' : r.estado === 'error' ? 'Falló el envío' : 'Esperando señal'}
        {r.fotos_total > 0 && <> · {r.fotos_subidas} de {r.fotos_total} fotos enviadas</>}
        {' · '}guardado {hace(r.guardado_at)}
      </p>
      {r.estado === 'error' && r.motivo && (
        <p className="mt-0.5 text-[11px] text-red-700">{r.motivo} · intento {r.intentos} — se reintenta solo</p>
      )}
    </Link>
  )
}

export function BandejaPorEnviar() {
  const qc = useQueryClient()
  const [reintentando, setReintentando] = useState(false)
  const { data: filas = [] } = useQuery({
    queryKey: ['enex-bandeja'], queryFn: getBandejaEnex, networkMode: 'always', refetchInterval: 3000,
  })
  if (filas.length === 0) return null

  async function reintentar() {
    setReintentando(true)
    try { await syncEnexPending() } finally {
      setReintentando(false)
      qc.invalidateQueries({ queryKey: ['enex-bandeja'] })
      qc.invalidateQueries({ queryKey: ['enex-pending-count'] })
      qc.invalidateQueries({ queryKey: ['enex-terreno'] })
    }
  }
  const online = typeof navigator === 'undefined' || navigator.onLine

  return (
    <div className="rounded-xl border-2 border-amber-300 bg-white p-2.5">
      <div className="flex items-center gap-1.5">
        <CloudOff className="h-4 w-4 text-amber-700" />
        <p className="text-sm font-bold text-gray-900">Por enviar ({filas.length})</p>
        <button onClick={reintentar} disabled={reintentando || !online}
                className="ml-auto inline-flex items-center gap-1 rounded-md border border-gray-300 px-2 py-1 text-[11px] font-medium text-gray-700 disabled:opacity-50">
          <RefreshCw className={`h-3 w-3 ${reintentando ? 'animate-spin' : ''}`} /> Reintentar
        </button>
      </div>
      <p className="mt-0.5 text-[10px] text-gray-500">
        Está guardado en este teléfono. No desinstales la app ni borres los datos del navegador hasta que esta lista quede vacía.
      </p>
      <div className="mt-2 space-y-1.5">
        {filas.map((r) => <Fila key={r.local_id} r={r} />)}
      </div>
    </div>
  )
}
