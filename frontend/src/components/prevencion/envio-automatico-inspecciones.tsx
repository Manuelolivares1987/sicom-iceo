'use client'

// ============================================================================
// Inspecciones APR: se envían SOLAS (21-11-2026)
// ----------------------------------------------------------------------------
// Antes el APR tenía que volver a la inspección y apretar «Enviar» cuando
// tuviera señal; si se le olvidaba, la inspección no llegaba nunca a la oficina.
// Ahora, como WhatsApp: con señal (confirmada) y sesión, toda inspección con
// cambios sin enviar y con lo mínimo (trabajo + cuadrilla) se envía sola. La
// base la recibe como «avance» si faltan puntos y la cierra cuando está completa.
// Corre en todas las pantallas de /m/prevencion: al abrir, al volver la señal,
// al volver a la app y cada 30 s. La que está abierta en el editor espera a que
// el APR deje de escribir (45 s), para no mandarla a medio escribir.
// ============================================================================

import { useEffect } from 'react'
import { estaEnLinea, EVENTO_CONECTIVIDAD } from '@/lib/conectividad'
import { haySesionServidor } from '@/lib/supabase'
import { esTransitorio } from '@/lib/offline/bandeja'
import {
  listarBorradores, pendienteDeEnvio, editando, mutarBorrador,
} from '@/lib/offline/inspeccion-apr-db'
import { problemasInspeccion, enviarBorradorInspeccion } from '@/components/prevencion/inspeccion-apr-form'

const QUIETO_MS = 45_000
let enCurso = false

export async function enviarInspeccionesPendientes(): Promise<number> {
  if (enCurso || !estaEnLinea() || !haySesionServidor()) return 0
  enCurso = true
  let ok = 0
  try {
    for (const b of await listarBorradores()) {
      if (!pendienteDeEnvio(b) || b.error_envio) continue
      if (problemasInspeccion(b).length) continue
      const tocada = editando.get(b.cliente_uuid)
      if (tocada !== undefined && Date.now() - tocada < QUIETO_MS) continue
      if (!estaEnLinea()) break
      try {
        await enviarBorradorInspeccion(b.cliente_uuid)
        ok++
      } catch (e) {
        // Señal o sesión: se reintenta en la próxima vuelta. Una regla de la
        // base (p. ej. ya estaba cerrada y se cambió después): se muestra.
        if (!esTransitorio(e) && !/fetch|network|timeout|failed/i.test(String((e as Error)?.message ?? e))) {
          await mutarBorrador(b.cliente_uuid, (d) => ({ ...d, error_envio: (e as Error)?.message ?? String(e) }))
        }
      }
    }
  } catch { /* IndexedDB no disponible: no se rompe la pantalla */ } finally {
    enCurso = false
  }
  return ok
}

export function EnvioAutomaticoInspecciones() {
  useEffect(() => {
    const correr = () => { void enviarInspeccionesPendientes() }
    const alConectar = (e: Event) => { if ((e as CustomEvent<{ enLinea: boolean }>).detail?.enLinea) correr() }
    const alVolver = () => { if (document.visibilityState === 'visible') correr() }
    correr()
    const t = setInterval(correr, 30_000)
    window.addEventListener(EVENTO_CONECTIVIDAD, alConectar)
    window.addEventListener('online', correr)
    document.addEventListener('visibilitychange', alVolver)
    return () => {
      clearInterval(t)
      window.removeEventListener(EVENTO_CONECTIVIDAD, alConectar)
      window.removeEventListener('online', correr)
      document.removeEventListener('visibilitychange', alVolver)
    }
  }, [])
  return null
}
