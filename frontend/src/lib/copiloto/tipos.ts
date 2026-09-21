// ============================================================================
// Copiloto Técnico — protocolo del stream /api/copiloto/consulta (NDJSON).
// Una línea JSON por evento. El cliente viejo (sin `formato: 'ndjson'`) sigue
// recibiendo texto plano: el servidor mantiene ese modo por compatibilidad
// con la PWA cacheada en los teléfonos.
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

export type EventoCopiloto =
  | { t: 'estado'; d: string }
  | { t: 'texto'; d: string }
  | { t: 'fuentes'; d: FuenteCopiloto[] }
  | { t: 'codigos'; d: CodigoCopiloto[] }
  | { t: 'fin'; consultaId: string | null }
  | { t: 'error'; d: string }
