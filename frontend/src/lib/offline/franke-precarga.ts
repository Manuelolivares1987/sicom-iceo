// ============================================================================
// Todo lo de la faena, bajado al teléfono apenas hay señal (F3, 20-11-2026)
// ----------------------------------------------------------------------------
// Antes cada pantalla bajaba sus datos SOLO cuando alguien la abría con señal:
// un teléfono nuevo, o una pantalla que nunca se había abierto, no funcionaba
// sin señal (bodega «no tiene el catálogo», despacho sin camiones…). Ahora, con
// señal y sesión, se baja todo de una vez y se refresca cada 30 minutos.
// Cada paso es independiente: si uno falla, los demás siguen.
// ============================================================================

import { estaEnLinea } from '@/lib/conectividad'
import { haySesionServidor } from '@/lib/supabase'
import { FAENA_FRANKE, getFaenaId } from '@/lib/services/faena-pauta'
import { refrescarSiViejo } from '@/lib/offline/faena-pauta-offline'
import { getCatalogo } from '@/lib/offline/bodega-faena-offline'
import { descargarCatalogo } from '@/lib/offline/combustible-faena-offline'
import { getBitacora } from '@/lib/offline/faena-bitacora-offline'
import { cacheGuardar } from '@/lib/offline/terreno-cache'
import { getPuntosMedicion } from '@/lib/services/combustible-cierre'
import { getCalendarioCiclo, periodoSugerido } from '@/lib/services/faena-entrega'
import { guardarPlantilla } from '@/lib/offline/faena-entrega-offline'

const CLAVE = 'sicom-franke-precarga'
const CADA_MS = 30 * 60_000

export type EstadoPrecarga = { at: string; ok: string[]; fallaron: string[] }

export function ultimaPrecarga(): EstadoPrecarga | null {
  try { return JSON.parse(localStorage.getItem(CLAVE) || 'null') } catch { return null }
}

let enCurso: Promise<EstadoPrecarga | null> | null = null

/** Baja todo si toca (o si `forzar`). Devuelve el resultado o null si no corrió. */
export function precargarFaena(forzar = false): Promise<EstadoPrecarga | null> {
  if (enCurso) return enCurso
  const previa = ultimaPrecarga()
  if (!forzar && previa && Date.now() - new Date(previa.at).getTime() < CADA_MS && previa.fallaron.length === 0) {
    return Promise.resolve(null)
  }
  if (!estaEnLinea() || !haySesionServidor()) return Promise.resolve(null)
  enCurso = (async () => {
    const ok: string[] = [], fallaron: string[] = []
    const paso = async (nombre: string, f: () => Promise<unknown>) => {
      try { await f(); ok.push(nombre) } catch { fallaron.push(nombre) }
    }
    const faenaId = await getFaenaId(FAENA_FRANKE).catch(() => null)
    if (!faenaId) return null
    await paso('Pautas', () => refrescarSiViejo(faenaId, 0.5))
    await paso('Bodega', () => getCatalogo(undefined, false))
    await paso('Despacho', () => descargarCatalogo(FAENA_FRANKE))
    await paso('Bitácora', () => getBitacora(faenaId, false))
    await paso('Carga del camión', async () => cacheGuardar(`franke-carga-puntos:${faenaId}`, await getPuntosMedicion(faenaId)))
    await paso('Turno', async () => cacheGuardar(`franke-turno-cal:${faenaId}`, await getCalendarioCiclo(faenaId)))
    // [F4] Para poder abrir la entrega de turno sin señal. Solo supervisores:
    // al resto el servidor le dice «no autorizado» y no es una falla.
    try {
      const { desde, hasta } = periodoSugerido()
      await guardarPlantilla(faenaId, desde, hasta)
      ok.push('Entrega de turno')
    } catch (e) {
      const c = typeof e === 'object' && e && 'code' in e ? String((e as { code: unknown }).code) : ''
      if (c !== '42501') fallaron.push('Entrega de turno')
    }
    const r = { at: new Date().toISOString(), ok, fallaron }
    try { localStorage.setItem(CLAVE, JSON.stringify(r)) } catch { /* noop */ }
    return r
  })().finally(() => { enCurso = null })
  return enCurso
}
