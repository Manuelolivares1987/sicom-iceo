import type { ClasificacionICEO } from '@/types/database'

/**
 * KPI / ICEO presentation logic - pure business rules, no Supabase imports.
 * Extracted from lib/utils.ts for domain isolation.
 */

/**
 * Get the ICEO classification based on the numeric value.
 */
export function getICEOClassification(valor: number): ClasificacionICEO {
  if (valor >= 95) return 'excelencia'
  if (valor >= 85) return 'bueno'
  if (valor >= 70) return 'aceptable'
  return 'deficiente'
}

/**
 * Get the text color class for an ICEO value.
 */
export function getICEOColor(valor: number): string {
  if (valor >= 95) return 'text-iceo-excelencia'
  if (valor >= 85) return 'text-iceo-bueno'
  if (valor >= 70) return 'text-iceo-aceptable'
  return 'text-iceo-deficiente'
}

/**
 * Get the background color class for an ICEO value.
 */
export function getICEOBgColor(valor: number): string {
  if (valor >= 95) return 'bg-iceo-excelencia'
  if (valor >= 85) return 'bg-iceo-bueno'
  if (valor >= 70) return 'bg-iceo-aceptable'
  return 'bg-iceo-deficiente'
}

/**
 * Get the Spanish label for an ICEO value.
 */
export function getICEOLabel(valor: number): string {
  if (valor >= 95) return 'Excelencia'
  if (valor >= 85) return 'Bueno'
  if (valor >= 70) return 'Aceptable'
  return 'Deficiente'
}

/**
 * Get the ring/stroke color (hex) for gauge components.
 */
export function getICEORingColor(valor: number): string {
  if (valor >= 95) return '#7C3AED' // purple - excelencia
  if (valor >= 85) return '#16A34A' // green - bueno
  if (valor >= 70) return '#F59E0B' // amber - aceptable
  return '#DC2626' // red - deficiente
}

/**
 * Get a status icon name based on a KPI percentage value.
 */
export function getKPIStatusIcon(pct: number): 'check' | 'warning' | 'alert' {
  if (pct >= 90) return 'check'
  if (pct >= 70) return 'warning'
  return 'alert'
}

/**
 * Format a KPI value with its unit for display.
 */
export function formatKPIValue(value: number, unit: string): string {
  switch (unit) {
    case '%':
      return `${value.toFixed(1)}%`
    case 'dias':
    case 'dias':
      return `${value.toFixed(0)} dias`
    case 'horas':
      return `${value.toFixed(1)} hrs`
    case 'unidades':
      return value.toFixed(0)
    default:
      return `${value.toFixed(1)} ${unit}`
  }
}

/**
 * Check if a blocker is active based on measured value, threshold, and direction.
 *
 * @param valor - The measured KPI value
 * @param umbral - The threshold value
 * @param direccion - 'mayor_mejor' means higher is better, 'menor_mejor' means lower is better
 * @returns true if the blocker should activate (value fails the threshold)
 */
export function isBlockerActive(
  valor: number,
  umbral: number,
  direccion: string
): boolean {
  if (direccion === 'mayor_mejor') {
    // Higher is better -> blocker activates when value is below threshold
    return valor < umbral
  }
  // Lower is better -> blocker activates when value exceeds threshold
  return valor > umbral
}
