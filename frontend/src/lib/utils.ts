import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function formatCLP(value: number): string {
  return new Intl.NumberFormat('es-CL', {
    style: 'currency',
    currency: 'CLP',
    minimumFractionDigits: 0,
  }).format(value)
}

export function formatPercent(value: number, decimals = 1): string {
  return `${value.toFixed(decimals)}%`
}

// Parsea un string de fecha respetando la zona horaria local.
// Para DATE de Postgres (YYYY-MM-DD), new Date(str) lo interpreta como
// UTC-medianoche y al formatear a es-CL (UTC-4) retrocede un dia. Aqui
// parseamos la fecha pura como medianoche LOCAL para evitar ese shift.
function parseDateLocal(input: string | Date): Date {
  if (input instanceof Date) return input
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(input)
  if (m) return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
  return new Date(input)
}

export function formatDate(date: string | Date): string {
  return new Intl.DateTimeFormat('es-CL', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  }).format(parseDateLocal(date))
}

export function formatDateTime(date: string | Date): string {
  return new Intl.DateTimeFormat('es-CL', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(parseDateLocal(date))
}

// Devuelve la fecha de HOY en zona horaria local como 'YYYY-MM-DD'.
// Reemplaza el patron new Date().toISOString().split('T')[0], que
// convierte a UTC antes de cortar y en Chile (UTC-4/-3) despues de
// las 20:00 locales ya devuelve el dia siguiente.
export function todayISO(): string {
  const d = new Date()
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

// ICEO presentation functions — source of truth is domain/kpi/calculator
export { getICEOColor, getICEOBgColor, getICEOLabel } from '@/domain/kpi/calculator'

export function getEstadoOTColor(estado: string): string {
  const colores: Record<string, string> = {
    creada: 'bg-gray-100 text-gray-700',
    asignada: 'bg-blue-100 text-blue-700',
    en_ejecucion: 'bg-amber-100 text-amber-700',
    pausada: 'bg-orange-100 text-orange-700',
    ejecutada_ok: 'bg-green-100 text-green-700',
    ejecutada_con_observaciones: 'bg-yellow-100 text-yellow-700',
    no_ejecutada: 'bg-red-100 text-red-700',
    cancelada: 'bg-gray-200 text-gray-500',
    cerrada: 'bg-purple-100 text-purple-700',
  }
  return colores[estado] || 'bg-gray-100 text-gray-700'
}

export function getEstadoOTLabel(estado: string): string {
  const labels: Record<string, string> = {
    creada: 'Creada',
    asignada: 'Asignada',
    en_ejecucion: 'En Ejecución',
    pausada: 'Pausada',
    ejecutada_ok: 'Ejecutada OK',
    ejecutada_con_observaciones: 'Con Observaciones',
    no_ejecutada: 'No Ejecutada',
    cancelada: 'Cancelada',
    cerrada: 'Cerrada',
  }
  return labels[estado] || estado
}

export function getSemaforoColor(estado: string): string {
  const colores: Record<string, string> = {
    operativo: 'bg-semaforo-verde',
    en_mantenimiento: 'bg-semaforo-amarillo',
    fuera_servicio: 'bg-semaforo-rojo',
    dado_baja: 'bg-gray-400',
    en_transito: 'bg-semaforo-azul',
  }
  return colores[estado] || 'bg-gray-400'
}

export function getCriticidadColor(criticidad: string): string {
  const colores: Record<string, string> = {
    critica: 'bg-red-600 text-white',
    alta: 'bg-orange-500 text-white',
    media: 'bg-yellow-400 text-yellow-900',
    baja: 'bg-green-500 text-white',
  }
  return colores[criticidad] || 'bg-gray-400'
}
