'use client'

import { useState } from 'react'
import { usePathname } from 'next/navigation'
import { Lightbulb } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'

// Ampolleta flotante de sugerencias: el usuario describe una mejora y se envía
// (guardada + correo en formato prompt para Claude Code) vía /api/sugerencias.
export default function SugerenciaWidget() {
  const pathname = usePathname()
  const toast = useToast()
  const [open, setOpen] = useState(false)
  const [texto, setTexto] = useState('')
  const [sending, setSending] = useState(false)

  async function enviar() {
    if (texto.trim().length < 5) { toast.error('Escribe tu sugerencia.'); return }
    setSending(true)
    try {
      const { data: { session } } = await supabase.auth.getSession()
      const token = session?.access_token
      if (!token) { toast.error('Sesión no válida.'); return }
      const res = await fetch('/api/sugerencias', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({
          texto: texto.trim(),
          contextoUrl: pathname,
          contextoTitulo: typeof document !== 'undefined' ? document.title : '',
        }),
      })
      const j = await res.json()
      if (!res.ok) throw new Error(j.error ?? 'Error al enviar')
      toast.success(j.emailed ? '¡Gracias! Tu sugerencia fue enviada.' : '¡Gracias! Tu sugerencia quedó registrada.')
      setTexto('')
      setOpen(false)
    } catch (e) {
      toast.error((e as Error).message)
    } finally {
      setSending(false)
    }
  }

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        title="Enviar una sugerencia de mejora"
        aria-label="Sugerir una mejora"
        className="fixed bottom-5 right-5 z-30 flex h-12 w-12 items-center justify-center rounded-full bg-amber-400 text-white shadow-lg transition-transform hover:scale-105 hover:bg-amber-500"
      >
        <Lightbulb className="h-6 w-6" />
      </button>

      {open && (
        <Modal open onClose={() => setOpen(false)} title="💡 Sugerir una mejora">
          <div className="space-y-3">
            <p className="text-xs text-gray-500">
              ¿Qué mejorarías de esta pantalla o del sistema? Tu idea llega al equipo para implementarla.
            </p>
            <textarea
              value={texto}
              onChange={(e) => setTexto(e.target.value)}
              rows={5}
              autoFocus
              className="w-full rounded border px-2 py-1.5 text-sm"
              placeholder="Describe la mejora con el mayor detalle posible…"
            />
            <p className="text-[11px] text-gray-400">Página actual: {pathname}</p>
          </div>
          <ModalFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>Cancelar</Button>
            <Button disabled={sending || texto.trim().length < 5} onClick={enviar}>
              {sending ? <Spinner className="mr-1 h-4 w-4" /> : null} Enviar sugerencia
            </Button>
          </ModalFooter>
        </Modal>
      )}
    </>
  )
}
