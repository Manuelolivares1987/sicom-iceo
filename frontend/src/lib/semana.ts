/**
 * La semana, en zona local.
 *
 * Vive aparte porque la tira semanal ya se usa en dos apps de terreno —Calama
 * y Taller— y el cálculo tiene una trampa que no conviene reescribir dos
 * veces: `toISOString()` convierte a UTC, así que a partir de cierta hora de
 * la tarde en Chile devuelve el día siguiente y la semana se corre entera.
 * Todo lo de acá trabaja con la fecha local y con strings 'YYYY-MM-DD'.
 *
 * La semana parte el lunes.
 */

export const DIAS_CORTOS = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb']
export const DIAS_INICIAL = ['L', 'M', 'X', 'J', 'V', 'S', 'D']
export const MESES_CORTOS = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic']

function pad2(n: number): string { return n < 10 ? `0${n}` : `${n}` }

export function localISO(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`
}

export function isoToday(): string { return localISO(new Date()) }

export function startOfWeekISOOffset(weekOffset: number): string {
  const d = new Date(); const dow = d.getDay()
  const diff = (dow === 0 ? -6 : 1) - dow
  d.setDate(d.getDate() + diff + weekOffset * 7)
  return localISO(d)
}

export function endOfWeekISOOffset(weekOffset: number): string {
  const d = new Date(startOfWeekISOOffset(weekOffset) + 'T00:00:00')
  d.setDate(d.getDate() + 6)
  return localISO(d)
}

export function diasDeSemana(weekStart: string): string[] {
  const out: string[] = []
  const d = new Date(weekStart + 'T00:00:00')
  for (let i = 0; i < 7; i++) {
    out.push(localISO(d))
    d.setDate(d.getDate() + 1)
  }
  return out
}

export function rangoSemanaLabel(weekStart: string, weekEnd: string): string {
  const a = new Date(weekStart + 'T00:00:00')
  const b = new Date(weekEnd + 'T00:00:00')
  if (a.getMonth() === b.getMonth()) {
    return `${a.getDate()}–${b.getDate()} ${MESES_CORTOS[a.getMonth()]}`
  }
  return `${a.getDate()} ${MESES_CORTOS[a.getMonth()]} – ${b.getDate()} ${MESES_CORTOS[b.getMonth()]}`
}

export function formatDiaCorto(fechaISO: string): string {
  const d = new Date(fechaISO + 'T00:00:00')
  return `${DIAS_CORTOS[d.getDay()]} ${d.getDate()} ${MESES_CORTOS[d.getMonth()]}`
}
