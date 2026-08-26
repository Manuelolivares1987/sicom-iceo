// ============================================================================
// El nombre de las cosas, dicho como lo diría una persona.
// ----------------------------------------------------------------------------
// Los tipos y severidades de `alertas` son valores de la base: 'doc_por_vencer',
// 'ot_vencida', 'vale_emitido', 'critical'. Se estaban imprimiendo tal cual en
// el tablero de inicio, con guión bajo y en inglés. Para quien escribió el
// código son evidentes; para quien recién llega parecen un error del sistema.
//
// Este archivo es el único lugar donde esos valores se traducen. Si aparece un
// tipo nuevo sin traducción, se muestra el valor con los guiones cambiados por
// espacios en vez de romperse — feo, pero legible, y avisa que falta agregarlo.
// ============================================================================

export const ALERTA_TIPO_LABEL: Record<string, string> = {
  // Documentación
  doc_por_vencer:        'Documento por vencer',
  doc_vencido:           'Documento vencido',
  doc_vencidos_equipo:   'Documentos vencidos',
  vencimiento:           'Vencimiento',
  semep_vencido:         'SEMEP vencido',
  rt_por_vencer:         'Revisión técnica por vencer',
  disponibilidad_vencida:'Disponibilidad vencida',
  hermeticidad_vencida:  'Hermeticidad vencida',
  // Trabajo
  ot_vencida:            'OT vencida',
  no_conformidad:        'No conformidad',
  incumplimiento:        'Incumplimiento',
  bloqueante:            'Bloqueante',
  // Repuestos y bodega
  recurso_solicitado:    'Repuesto pedido',
  recurso_por_comprar:   'Repuesto por comprar',
  recurso_recibido:      'Repuesto recibido',
  vale_emitido:          'Vale para despachar',
  // Flota
  gps_sin_senal:         'Equipo sin señal GPS',
}

export const ALERTA_SEVERIDAD_LABEL: Record<string, string> = {
  critical: 'Crítica',
  warning:  'Atención',
  info:     'Aviso',
}

/** Etiqueta legible del tipo de alerta. Nunca devuelve el valor crudo con guiones. */
export function etiquetaTipoAlerta(tipo: string | null | undefined): string {
  if (!tipo) return 'Aviso'
  return ALERTA_TIPO_LABEL[tipo] ?? tipo.replace(/_/g, ' ')
}

/** Etiqueta legible de la severidad. */
export function etiquetaSeveridadAlerta(sev: string | null | undefined): string {
  if (!sev) return 'Aviso'
  return ALERTA_SEVERIDAD_LABEL[sev] ?? sev
}

// ── Estado del equipo ───────────────────────────────────────────────────────
// Mismo problema: 'en_mantenimiento' y 'fuera_servicio' se mostraban con guión
// bajo en Auditoría de calidad.

export const ESTADO_ACTIVO_LABEL: Record<string, string> = {
  operativo:        'Operativo',
  en_mantenimiento: 'En mantención',
  fuera_servicio:   'Fuera de servicio',
  dado_baja:        'Dado de baja',
  siniestrado:      'Siniestrado',
}

export function etiquetaEstadoActivo(estado: string | null | undefined): string {
  if (!estado) return '—'
  return ESTADO_ACTIVO_LABEL[estado] ?? estado.replace(/_/g, ' ')
}
