// Copiloto Prevención Centinela (MIG734) — tipos compartidos cliente/servidor.

export type AtajoSso = 'art' | 'charla' | 'subir'

export type FuenteSso = {
  n: number
  chunkId: number
  documento: string
  codigo: string
  seccion: string | null
  /** Leído por OCR (RECSS, Directriz, SOFI): verificar cifras en el PDF original. */
  escaneado: boolean
  citada: boolean
  extracto?: string
}

export type EventoSso =
  | { t: 'estado'; d: string }
  | { t: 'texto'; d: string }
  | { t: 'fuentes'; d: FuenteSso[] }
  | { t: 'fin'; consultaId?: string; duracion_ms: number }
  | { t: 'error'; d: string }
