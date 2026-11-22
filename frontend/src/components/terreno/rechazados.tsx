'use client'

// ============================================================================
// Lo que el servidor NO aceptó (22-11-2026)
// ----------------------------------------------------------------------------
// Antes un despacho, un movimiento o una pauta rechazados por una regla del
// servidor quedaban «se sube solo» para siempre: el trabajador nunca se
// enteraba y el dato nunca llegaba. Acá se ve QUÉ fue, POR QUÉ, y se puede
// descartar (con confirmación) para volver a hacerlo bien.
// ============================================================================
import { useState } from 'react'
import { AlertTriangle } from 'lucide-react'

export type Rechazado = {
  id: string
  titulo: string
  detalle?: string | null
  motivo: string | null | undefined
  onDescartar: () => Promise<void>
}

export function RechazadosTerreno({ items, onCambio }: { items: Rechazado[]; onCambio?: () => void }) {
  const [confirmar, setConfirmar] = useState<string | null>(null)
  const [ocupado, setOcupado] = useState(false)
  if (items.length === 0) return null
  return (
    <section className="rounded-xl border border-red-300 bg-red-50 p-3" aria-label="No aceptado por el servidor">
      <p className="flex items-center gap-1.5 text-sm font-semibold text-red-800">
        <AlertTriangle className="h-4 w-4" /> {items.length} no aceptado{items.length === 1 ? '' : 's'} por el sistema
      </p>
      <p className="mt-0.5 text-xs text-red-700">
        No es la señal: el sistema lo rechazó. Léelo, descártalo y vuelve a hacerlo como corresponde (o avisa a tu jefatura).
      </p>
      <ul className="mt-2 space-y-1.5">
        {items.map((r) => (
          <li key={r.id} className="rounded-lg border border-red-200 bg-white px-2.5 py-2 text-xs">
            <div className="font-medium text-gray-900">{r.titulo}</div>
            {r.detalle && <div className="text-gray-500">{r.detalle}</div>}
            <div className="mt-0.5 break-words text-red-700">{r.motivo || 'Rechazado sin motivo'}</div>
            <div className="mt-1.5 flex justify-end">
              {confirmar === r.id ? (
                <span className="flex items-center gap-2">
                  <span className="text-gray-600">¿Descartar? Se pierde lo que no subió.</span>
                  <button type="button" disabled={ocupado}
                    onClick={async () => {
                      setOcupado(true)
                      try { await r.onDescartar() } finally { setOcupado(false); setConfirmar(null); onCambio?.() }
                    }}
                    className="rounded-md bg-red-600 px-2 py-1 font-semibold text-white disabled:opacity-50">Sí, descartar</button>
                  <button type="button" onClick={() => setConfirmar(null)} className="px-1 text-gray-500">No</button>
                </span>
              ) : (
                <button type="button" onClick={() => setConfirmar(r.id)} className="text-gray-500 underline">Descartar</button>
              )}
            </div>
          </li>
        ))}
      </ul>
    </section>
  )
}
