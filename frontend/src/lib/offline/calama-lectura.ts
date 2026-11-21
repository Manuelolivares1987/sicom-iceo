// ============================================================================
// Calama: lo que el operador MIRA en su OT, guardado en el teléfono (21-11-2026)
// ----------------------------------------------------------------------------
// Sin señal, la OT mostraba solo título y fecha: la faena, el rechazo anterior
// (qué hay que corregir) y las fotos/firmas ya hechas venían solo del servidor.
// Ahora cada lectura guarda lo último que llegó con señal y, sin señal, muestra
// eso. Se baja sola junto con las jornadas (mantenerCalamaAlDia).
// El ESTADO de la jornada NO va por acá: sin señal lo manda el teléfono
// (calama-db); una copia vieja del servidor haría repetir pasos ya hechos.
// ============================================================================
import { conRespaldo } from '@/lib/offline/terreno-cache'
import { getOTById, getSubtareasPorOT } from '@/lib/services/calama'
import { getFirmasJornada, getRechazosJornada, getEvidenciasJornada } from '@/lib/services/calama-jornada'

const sinError = async <T,>(p: Promise<{ data: T | null; error: unknown }>): Promise<T | null> => {
  const { data, error } = await p
  if (error) throw error
  return data
}

export const leerOTCalama = (id: string) => conRespaldo(`calama-ot:${id}`, () => sinError(getOTById(id)))
export const leerSubtareasCalama = (otId: string) => conRespaldo(`calama-subtareas:${otId}`, async () => (await sinError(getSubtareasPorOT(otId))) ?? [])
export const leerFirmasJornada = (j: string) => conRespaldo(`calama-firmas:${j}`, () => sinError(getFirmasJornada(j)))
export const leerRechazosJornada = (j: string) => conRespaldo(`calama-rechazos:${j}`, () => sinError(getRechazosJornada(j)))
export const leerEvidenciasJornada = (j: string) => conRespaldo(`calama-evidencias:${j}`, () => sinError(getEvidenciasJornada(j)))

/** Con señal: deja guardado lo que se mira de cada OT/jornada del operador. */
export async function precargarLecturasCalama(jornadas: { local_id: string; ot_id: string }[]): Promise<void> {
  const ots = Array.from(new Set(jornadas.map((j) => j.ot_id)))
  for (const id of ots) {
    await leerOTCalama(id).catch(() => undefined)
    await leerSubtareasCalama(id).catch(() => undefined)
  }
  for (const j of jornadas) {
    await leerRechazosJornada(j.local_id).catch(() => undefined)
    await leerFirmasJornada(j.local_id).catch(() => undefined)
    await leerEvidenciasJornada(j.local_id).catch(() => undefined)
  }
}
