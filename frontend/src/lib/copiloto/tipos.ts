// ============================================================================
// Copiloto Técnico — protocolo del stream /api/copiloto/consulta (NDJSON).
// Una línea JSON por evento. El cliente viejo (sin `formato: 'ndjson'`) sigue
// recibiendo texto plano: el servidor mantiene ese modo por compatibilidad
// con la PWA cacheada en los teléfonos.
// 2026-10-05 (MIG583): la conversación persiste. Eventos nuevos:
//   conversacion (id del hilo recién creado), diagnostico (el copiloto
//   registró una comprobación que el mecánico informó) y propuesta (el
//   copiloto cree que ya está la solución y pide confirmarla).
// ============================================================================

export type FuenteCopiloto = {
  n: number                       // número de cita: [F3]
  titulo: string
  pagina: number
  tipo: string                    // manual_oficial, guia_tecnica_web, ...
  confiabilidad: string | null
  url: string | null              // documento oficial en la web (con #page=N si es PDF)
  imagen: string | null           // URL firmada de la página renderizada (diagramas)
  citada: boolean                 // aparece como [Fn] en la respuesta
  documentoId?: string | null     // para volver a firmar la imagen al retomar el chat
}

export type CodigoCopiloto = {
  codigo: string
  formato: string
  descripcion: string
  aplica: string | null
  marca: string | null
  causas: string[]
  comprobaciones: string[]
  confiabilidad: string
  fuente: string | null
  coincidencia: string
}

export type ComprobacionCopiloto = {
  descripcion: string
  resultado: 'ok' | 'no_ok' | 'valor'
  valor?: string | null
  tipo?: string | null            // 'reparacion_fallida' cuando la falla volvió
  at: string
}

export type DiagnosticoCopiloto = {
  id: string
  ot_id: string | null
  activo_id: string | null
  usuario_id: string
  sintoma: string
  sistema: string | null
  estado: 'abierto' | 'resuelto' | 'descartado'
  comprobaciones: ComprobacionCopiloto[]
  causa_raiz: string | null
  reparacion: string | null
  leccion: string | null
  resuelto_at: string | null
  validado_at: string | null
  reaperturas: number
  created_at: string
}

// Lo que el copiloto propone guardar como solución; el mecánico confirma o
// corrige antes de que exista como caso.
export type PropuestaSolucion = {
  causa_raiz: string
  reparacion: string
  sistema: string | null
  sintoma: string | null
}

export type ConversacionCopiloto = {
  id: string
  usuario_id: string
  activo_id: string | null
  ot_id: string | null
  diagnostico_id: string | null
  titulo: string
  estado: 'abierta' | 'resuelta' | 'descartada'
  mensajes: number
  ultimo_at: string
  created_at: string
  activo?: { patente: string | null; codigo: string | null } | null
}

// Un intercambio guardado (copiloto_consultas) tal como lo entrega
// GET /api/copiloto/conversacion?id=
export type MensajeGuardado = {
  consultaId: string
  pregunta: string
  respuesta: string | null
  fuentes: FuenteCopiloto[]
  codigos: CodigoCopiloto[]
  adjuntos: { nombre: string; tipo: string; preview?: string | null }[]
  feedback: 'util' | 'no_util' | null
  created_at: string
}

export type EventoCopiloto =
  | { t: 'conversacion'; id: string; titulo: string }
  | { t: 'estado'; d: string }
  | { t: 'texto'; d: string }
  | { t: 'fuentes'; d: FuenteCopiloto[] }
  | { t: 'codigos'; d: CodigoCopiloto[] }
  | { t: 'diagnostico'; d: DiagnosticoCopiloto }
  | { t: 'propuesta'; d: PropuestaSolucion }
  | { t: 'fin'; consultaId: string | null; input_tokens?: number; output_tokens?: number; duracion_ms?: number; modelo?: string }
  | { t: 'error'; d: string }
