// ============================================================================
// Copiloto Técnico — reglas puras de la conversación persistente (MIG583).
// Sin IO: se usan en el servidor (/api/copiloto/consulta) y en el teléfono,
// y se prueban en __tests__/copiloto-conversacion.test.ts.
// ============================================================================

export const MAX_TURNOS_VERBATIM = 6        // intercambios recientes que van completos a la IA
export const MAX_PREGUNTAS_RESUMEN = 20     // preguntas más antiguas que van como lista
export const HORAS_PARA_SEGUIMIENTO = 12    // tras este silencio, al retomar se pregunta cómo terminó

// Mensajes automáticos que la app manda sola (diagnóstico guiado, códigos):
// no sirven de título.
const PREFIJOS_AUTOMATICOS = [
  /^diagn[oó]stico iniciado\.\s*s[ií]ntoma:\s*/i,
  /^registr[eé] la comprobaci[oó]n:\s*/i,
  /^sale el c[oó]digo de falla\s*/i,
  /^tengo el c[oó]digo\s*/i,
  /^la falla volvi[oó][^:]*:\s*/i,
]

// Título del hilo a partir de la primera pregunta: una línea, sin el ruido
// de los mensajes automáticos, cortada en una frase.
export function tituloConversacion(pregunta: string, adjuntos: { nombre: string }[] = []): string {
  let t = (pregunta ?? '').replace(/\s+/g, ' ').trim()
  for (const re of PREFIJOS_AUTOMATICOS) t = t.replace(re, '')
  t = t.replace(/\s*¿por d[oó]nde (parto|empiezo)\??\s*$/i, '').replace(/\s*¿siguiente paso\??\s*$/i, '').trim()
  if (!t && adjuntos.length) t = `Revisión de ${adjuntos.length === 1 ? adjuntos[0].nombre : `${adjuntos.length} adjuntos`}`
  if (!t) t = 'Consulta al copiloto'
  // primera frase si es larga
  if (t.length > 90) {
    const corte = t.slice(0, 90).search(/[.;!?]\s[^.]*$/)
    t = corte > 25 ? t.slice(0, corte + 1) : t.slice(0, 87).replace(/\s+\S*$/, '') + '…'
  }
  return t.charAt(0).toUpperCase() + t.slice(1)
}

export type ConsultaGuardada = {
  pregunta: string
  respuesta: string | null
  created_at: string
}

export type Turno = { rol: 'user' | 'assistant'; texto: string }

// Historial para la IA: los últimos intercambios completos (respuesta
// truncada) y, si hay más, las preguntas anteriores como lista corta. El
// estado estructurado (comprobaciones, causa) viaja aparte en el contexto.
export function construirHistorial(
  consultas: ConsultaGuardada[],
  maxTurnos = MAX_TURNOS_VERBATIM,
  maxTextoRespuesta = 4000,
): { turnos: Turno[]; resumenAnteriores: string | null } {
  const conRespuesta = consultas
    .filter((c) => c.respuesta && c.respuesta.trim())
    .sort((a, b) => a.created_at.localeCompare(b.created_at))
  const recientes = conRespuesta.slice(-maxTurnos)
  const anteriores = conRespuesta.slice(0, Math.max(0, conRespuesta.length - maxTurnos)).slice(-MAX_PREGUNTAS_RESUMEN)
  const turnos: Turno[] = []
  for (const c of recientes) {
    turnos.push({ rol: 'user', texto: c.pregunta.slice(0, 2000) })
    turnos.push({ rol: 'assistant', texto: (c.respuesta ?? '').slice(0, maxTextoRespuesta) })
  }
  const resumenAnteriores = anteriores.length
    ? anteriores.map((c) => `- (${c.created_at.slice(0, 10)}) ${c.pregunta.replace(/\s+/g, ' ').slice(0, 160)}`).join('\n')
    : null
  return { turnos, resumenAnteriores }
}

// «hace 3 días», «hace 5 h», «recién»
export function describirPausa(desdeIso: string, ahora: Date = new Date()): string {
  const ms = ahora.getTime() - new Date(desdeIso).getTime()
  const h = Math.floor(ms / 3_600_000)
  if (h < 1) return 'hace menos de una hora'
  if (h < 48) return `hace ${h} h`
  return `hace ${Math.floor(h / 24)} días`
}

// Al retomar un hilo abierto con equipo y silencio largo, lo primero es saber
// cómo terminó: resuelto, sigue fallando o era solo una consulta.
export function necesitaSeguimiento(
  conv: { estado: string; activo_id: string | null; diagnostico_id: string | null; ultimo_at: string; mensajes: number },
  ahora: Date = new Date(),
): boolean {
  if (conv.estado !== 'abierta') return false
  if (!conv.activo_id && !conv.diagnostico_id) return false
  if (conv.mensajes < 1) return false
  return ahora.getTime() - new Date(conv.ultimo_at).getTime() >= HORAS_PARA_SEGUIMIENTO * 3_600_000
}
