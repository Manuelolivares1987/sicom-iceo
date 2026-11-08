'use client'

// [MIG672] Un toque para decir por qué se para el trabajo. Sin esto, 46 de 53
// pausas quedaban sin motivo y nadie podía medir cuánto se espera un repuesto.
// «Otro» pide una frase: un «otro» mudo es lo mismo que no decir nada.
import { useEffect, useState } from 'react'
import { Modal } from '@/components/ui/modal'
import { MOTIVOS_PAUSA, type MotivoPausa } from '@/lib/taller-motivos-pausa'

export function MotivoPausaModal({ open, onClose, onElegir, ocupado = false }: {
  open: boolean
  onClose: () => void
  onElegir: (tipo: MotivoPausa, texto: string | null) => void
  ocupado?: boolean
}) {
  const [otro, setOtro] = useState(false)
  const [texto, setTexto] = useState('')
  useEffect(() => { if (open) { setOtro(false); setTexto('') } }, [open])

  return (
    <Modal open={open} onClose={onClose} title="¿Por qué pausas?">
      {!otro ? (
        <div className="grid grid-cols-1 gap-2">
          {MOTIVOS_PAUSA.map((m) => (
            <button key={m.v} type="button" disabled={ocupado}
                    onClick={() => (m.v === 'otro' ? setOtro(true) : onElegir(m.v, null))}
                    className="flex items-center gap-3 rounded-xl border px-4 py-3 text-left text-base font-medium hover:bg-amber-50 active:bg-amber-100 disabled:opacity-50">
              <span className="text-xl" aria-hidden>{m.emoji}</span> {m.label}
            </button>
          ))}
        </div>
      ) : (
        <div className="space-y-3">
          <textarea autoFocus value={texto} onChange={(e) => setTexto(e.target.value)} rows={3}
                    placeholder="Escribe en pocas palabras por qué se para"
                    className="w-full rounded-lg border px-3 py-2 text-sm" />
          <div className="flex gap-2">
            <button type="button" onClick={() => setOtro(false)}
                    className="flex-1 rounded-xl border py-3 text-sm">Volver</button>
            <button type="button" disabled={ocupado || texto.trim().length < 3}
                    onClick={() => onElegir('otro', texto.trim())}
                    className="flex-1 rounded-xl bg-amber-500 py-3 text-sm font-semibold text-white disabled:opacity-50">
              Pausar
            </button>
          </div>
        </div>
      )}
    </Modal>
  )
}
