// [MIG649] Correo de la ejecución ENEX a la jefatura (Hersaly + Manuel).
//
// Lo deja anotado la cola cuando una ejecución llega al servidor (`correo:` en
// la cache): al cerrar el servicio, o en un avance con repuestos pedidos. Acá
// se despacha: se genera el informe PDF si el servicio quedó cumplido y se
// pide el correo al servidor, que decide qué toca y no lo repite. Sin señal,
// sin sesión o con error, la anotación queda y se reintenta en la próxima
// vuelta del agente de envío. El servicio pudo cerrarse sin señal: por eso el
// informe ya no se genera solo en la pantalla al cerrar.

import { supabase } from '@/lib/supabase'
import { getEjecucionIdDeProgramacion } from '@/lib/services/enex'
import { withTimeout } from '@/lib/upload/with-timeout'
import { enexDB } from './enex-db'

type Anotacion = { programacion_id: string; cierre: boolean; intentos: number; informe_ok?: boolean }

/** Pasado esto se deja de insistir: el panel igual muestra la ejecución. */
const MAX_INTENTOS = 20
const INFORME_MS = 120_000
const CORREO_MS = 45_000

let enCurso: Promise<number> | null = null

/** Despacha los correos pendientes. Devuelve cuántos salieron. */
export function despacharCorreosEnex(): Promise<number> {
  if (typeof navigator !== 'undefined' && !navigator.onLine) return Promise.resolve(0)
  if (enCurso) return enCurso
  enCurso = despachar().finally(() => { enCurso = null })
  return enCurso
}

async function despachar(): Promise<number> {
  const db = enexDB()
  const filas = await db.cache.where('key').startsWith('correo:').toArray()
  if (filas.length === 0) return 0

  const { data } = await withTimeout(supabase.auth.getSession(), 8000, 'sesión').catch(() => ({ data: { session: null } }))
  const token = data.session?.access_token
  if (!token) return 0

  let enviados = 0
  for (const fila of filas) {
    const a = fila.value as Anotacion
    try {
      const eid = await withTimeout(getEjecucionIdDeProgramacion(a.programacion_id), CORREO_MS, 'ejecución')
      if (!eid) throw new Error('La ejecución todavía no está en el servidor')

      // El informe va antes que el correo. Si no se puede generar, el correo
      // sale igual y lo dice; el informe se puede generar desde el panel.
      if (a.cierre && !a.informe_ok) {
        try {
          const { generarYGuardarInformeEnex } = await import('@/components/enex/pdf-informe-enex')
          await withTimeout(generarYGuardarInformeEnex(eid), INFORME_MS, 'informe')
          a.informe_ok = true
        } catch { /* sigue sin informe */ }
      }

      const r = await withTimeout(fetch('/api/notificaciones/enex-ejecucion/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ ejecucionId: eid }),
      }), CORREO_MS, 'correo')
      if (!r.ok) throw new Error(`correo ${r.status}`)
      await db.cache.delete(fila.key)
      enviados++
    } catch {
      a.intentos = (a.intentos ?? 0) + 1
      if (a.intentos >= MAX_INTENTOS) await db.cache.delete(fila.key)
      else await db.cache.put({ key: fila.key, value: a, updated_at: new Date().toISOString() })
    }
  }
  return enviados
}
