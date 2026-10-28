// ============================================================================
// Rendimiento de combustible: tendencia mes a mes y revisión por vehículo
// ----------------------------------------------------------------------------
// Todo sale de v_combustible_rendimiento_mes (MIG659/660). Solo la flota con
// tarjeta (sin aljibes ni Renault) entra a la tendencia y al mapa de calor.
//
// - El mes en curso se proyecta al cierre (litros × días del mes ÷ días con
//   datos), si no un mes a medias siempre parece «bajo».
// - El «normal» de un vehículo es la mediana de sus otros meses: un mes raro
//   no se tapa a sí mismo.
// - Los $ cambian con el precio del diésel ($948 → $1.547 en 2026): se compara
//   en litros.
// ============================================================================

import type { RendimientoMes } from '@/lib/services/combustible-tarjeta'

export const mesIso = (y: number, m: number) => `${y}-${String(m).padStart(2, '0')}-01`
export const sumarMes = (iso: string, d: number) => {
  const [y, m] = iso.split('-').map(Number)
  const t = new Date(y, m - 1 + d, 1)
  return mesIso(t.getFullYear(), t.getMonth() + 1)
}
export const rangoMeses = (hasta: string, n: number) => Array.from({ length: n }, (_, i) => sumarMes(hasta, i - n + 1))

export function mediana(xs: number[]): number | null {
  if (!xs.length) return null
  const s = [...xs].sort((a, b) => a - b)
  const k = Math.floor(s.length / 2)
  return s.length % 2 ? s[k] : (s[k - 1] + s[k]) / 2
}

// Factor para llevar el mes al cierre. `corte` = último día con cargas cargadas ('YYYY-MM-DD').
export function factorMes(mes: string, corte: string | null): number {
  if (!corte || corte.slice(0, 7) !== mes.slice(0, 7)) return 1
  const [y, m, d] = corte.split('-').map(Number)
  const diasMes = new Date(y, m, 0).getDate()
  return d >= diasMes ? 1 : diasMes / Math.max(d, 1)
}
// El primer mes con datos casi nunca empieza el día 1 (el historial del portal parte el 29-12-2025):
// ese mes no se proyecta ni sirve de normal. `inicio` = fecha de la primera carga ('YYYY-MM-DD').
export const mesIncompleto = (mes: string, inicio: string | null | undefined) =>
  !!inicio && inicio.slice(0, 7) === mes.slice(0, 7) && Number(inicio.slice(8, 10)) > 1
// Con menos de 10 días la proyección de un vehículo es puro ruido.
const PROYECCION_CONFIABLE = 3

const esFlota = (r: RendimientoMes) => r.fuente === 'tarjeta' && r.grupo === 'flota'
const delMes = (r: RendimientoMes, mes: string) => r.mes.slice(0, 10) === mes

// km/L de un grupo = km medidos ÷ litros de esos tramos (los litros se recuperan del km/L de cada fila).
function kmLGrupo(filas: RendimientoMes[]): number | null {
  const m = filas.filter((f) => f.km_l != null && f.km_l > 0 && (f.km_medidos ?? 0) > 0)
  const km = m.reduce((s, f) => s + Number(f.km_medidos), 0)
  const l = m.reduce((s, f) => s + Number(f.km_medidos) / Number(f.km_l), 0)
  return l > 0 ? km / l : null
}
function costoKmGrupo(filas: RendimientoMes[]): number | null {
  const m = filas.filter((f) => f.costo_km != null && (f.km_medidos ?? 0) > 0)
  const km = m.reduce((s, f) => s + Number(f.km_medidos), 0)
  return km > 0 ? m.reduce((s, f) => s + Number(f.costo_km) * Number(f.km_medidos), 0) / km : null
}

export type PuntoFlota = {
  mes: string
  parcial: boolean
  incompleto: boolean      // primer mes con datos, empezado a medias
  litros: number           // cargado hasta el corte
  litrosProy: number       // proyectado al cierre (= litros si el mes está cerrado)
  monto: number
  montoProy: number
  cargas: number
  vehiculos: number
  precioL: number | null
  kmL: number | null
  costoKm: number | null
}

export function serieFlota(rend: RendimientoMes[], meses: string[], corte: string | null, inicio?: string | null): PuntoFlota[] {
  return meses.map((mes) => {
    const f = rend.filter((r) => esFlota(r) && delMes(r, mes))
    const k = factorMes(mes, corte)
    const litros = f.reduce((s, r) => s + Number(r.litros ?? 0), 0)
    const monto = f.reduce((s, r) => s + Number(r.monto ?? 0), 0)
    return {
      mes, parcial: k > 1, incompleto: mesIncompleto(mes, inicio), litros, litrosProy: litros * k, monto, montoProy: monto * k,
      cargas: f.reduce((s, r) => s + Number(r.cargas ?? 0), 0), vehiculos: f.length,
      precioL: litros > 0 ? monto / litros : null, kmL: kmLGrupo(f), costoKm: costoKmGrupo(f),
    }
  })
}

export type Base = 'ant' | 'prom3'
type Clave = 'litrosProy' | 'montoProy' | 'kmL' | 'costoKm'

// Valor contra el que se compara el mes: el mes anterior, o el promedio de los 3 anteriores con dato.
export function valorBase(serie: PuntoFlota[], mes: string, base: Base, clave: Clave): number | null {
  const i = serie.findIndex((p) => p.mes === mes)
  if (i <= 0) return null
  const ok = (v: number | null) => v != null && v > 0
  if (base === 'ant') { const p = serie[i - 1]; return !p.incompleto && ok(p[clave]) ? p[clave] : null }
  const prev = serie.slice(0, i).filter((p) => !p.incompleto).map((p) => p[clave]).filter(ok) as number[]
  const u = prev.slice(-3)
  return u.length ? u.reduce((s, v) => s + v, 0) / u.length : null
}
export const variacion = (v: number | null, b: number | null) => (v == null || b == null || b === 0 ? null : v / b - 1)

// ── Mapa de calor patente × mes ──
export type Celda = {
  mes: string; parcial: boolean; incompleto: boolean; litros: number; litrosProy: number
  normal: number | null; desvio: number | null; kmGps: number | null; kmL: number | null; cargas: number
}
export type FilaCalor = { patente: string; tipo: string | null; total: number; celdas: Record<string, Celda> }

// Desvío de cada mes contra la mediana de los OTROS meses cerrados (hacen falta 3).
function conDesvio(celdas: Celda[]): Celda[] {
  return celdas.map((c) => {
    const otros = celdas.filter((o) => o.mes !== c.mes && !o.parcial && !o.incompleto && o.litros > 0).map((o) => o.litros)
    const normal = otros.length >= 3 ? mediana(otros) : null
    return { ...c, normal, desvio: normal && !c.incompleto ? c.litrosProy / normal - 1 : null }
  })
}

export function mapaCalor(rend: RendimientoMes[], meses: string[], corte: string | null, inicio?: string | null): FilaCalor[] {
  const porPatente = new Map<string, RendimientoMes[]>()
  for (const r of rend) {
    if (!esFlota(r) || !meses.includes(r.mes.slice(0, 10))) continue
    porPatente.set(r.patente, [...(porPatente.get(r.patente) ?? []), r])
  }
  const filas = Array.from(porPatente.entries()).map(([patente, rs]) => {
    const celdas = conDesvio(rs.filter((r) => Number(r.litros ?? 0) > 0).map((r) => {
      const mes = r.mes.slice(0, 10), k = factorMes(mes, corte), litros = Number(r.litros)
      return { mes, parcial: k > 1, incompleto: mesIncompleto(mes, inicio), litros, litrosProy: litros * k, normal: null, desvio: null,
        kmGps: r.km_gps, kmL: r.km_l, cargas: Number(r.cargas ?? 0) }
    }))
    return { patente, tipo: rs[0].tipo, total: celdas.reduce((s, c) => s + c.litros, 0),
      celdas: Object.fromEntries(celdas.map((c) => [c.mes, c])) }
  })
  return filas.sort((a, b) => b.total - a.total)
}

// La misma fila para toda la flota, para comparar cada vehículo contra el global.
export function filaFlota(serie: PuntoFlota[]): FilaCalor {
  const celdas = conDesvio(serie.filter((p) => p.litros > 0).map((p) => ({
    mes: p.mes, parcial: p.parcial, incompleto: p.incompleto, litros: p.litros, litrosProy: p.litrosProy, normal: null, desvio: null,
    kmGps: null, kmL: p.kmL, cargas: p.cargas,
  })))
  return { patente: 'Toda la flota', tipo: null, total: celdas.reduce((s, c) => s + c.litros, 0),
    celdas: Object.fromEntries(celdas.map((c) => [c.mes, c])) }
}

// ── Litros sin explicar (Fase 2) ──
// Litros que el vehículo cargó en el mes menos los que piden sus km GPS a su km/L normal.
// El nivel del estanque al inicio y al final del mes mueve esto hasta ±1 estanque, por eso
// solo es sospecha si sobra más que un estanque lleno + 20 % (misma regla que la alerta de
// 30 días de MIG662). Los km del mes solo valen si el vehículo ya tenía GPS el mes anterior.
export type RefVehiculo = { kmL: number | null; capacidad: number | null }
export type SinExplicar = {
  litros: number; kmGps: number; kmLRef: number; esperados: number; exceso: number
  capacidad: number; sospechoso: boolean
}

export function litrosSinExplicar(rend: RendimientoMes[], mes: string, refs: Map<string, RefVehiculo>): Map<string, SinExplicar> {
  const ant = sumarMes(mes, -1)
  const conGpsAnt = new Set(rend.filter((r) => esFlota(r) && delMes(r, ant) && r.km_gps != null).map((r) => r.patente))
  const out = new Map<string, SinExplicar>()
  for (const r of rend) {
    if (!esFlota(r) || !delMes(r, mes) || !conGpsAnt.has(r.patente) || !(Number(r.km_gps) > 0)) continue
    const ref = refs.get(r.patente)
    if (!ref?.kmL || ref.kmL <= 0) continue
    const litros = Number(r.litros ?? 0), kmGps = Number(r.km_gps), capacidad = ref.capacidad ?? 80
    const esperados = kmGps / ref.kmL
    out.set(r.patente, { litros, kmGps, kmLRef: ref.kmL, esperados, exceso: litros - esperados, capacidad,
      sospechoso: litros > esperados * 1.2 + capacidad * 1.1 })
  }
  return out
}

// ── Revisión por vehículo del mes elegido ──
export type Nivel = 'alto' | 'medio' | 'info'
export type Motivo = { nivel: Nivel; texto: string }
export type Revision = {
  patente: string; tipo: string | null; parcial: boolean
  litrosProy: number; normalLitros: number | null; desvio: number | null
  kmGps: number | null; kmL: number | null; kmLNormal: number | null; kmLTipo: number | null
  alertas: number; sinExplicar: SinExplicar | null; motivos: Motivo[]
}

const pct = (x: number) => `${x > 0 ? '+' : ''}${Math.round(x * 100)} %`
const f1 = (x: number) => x.toLocaleString('es-CL', { maximumFractionDigits: 1 })
const f0 = (x: number) => Math.round(x).toLocaleString('es-CL')
const tipoDe = (t: string | null) => (t ?? '').toLowerCase().startsWith('furg') ? 'furgón' : 'camioneta'

export function revisarVehiculos(
  rend: RendimientoMes[], mes: string, corte: string | null, alertasPorPatente: Map<string, number>, inicio?: string | null,
  sinExplicar: Map<string, SinExplicar> = new Map(),
): Revision[] {
  const k = factorMes(mes, corte)
  const delMesFlota = rend.filter((r) => esFlota(r) && delMes(r, mes))
  return delMesFlota.map((r) => {
    const previos = rend.filter((p) => esFlota(p) && p.patente === r.patente && p.mes.slice(0, 10) < mes
        && !mesIncompleto(p.mes, inicio))
      .sort((a, b) => a.mes.localeCompare(b.mes))
    const litrosPrev = previos.filter((p) => Number(p.litros ?? 0) > 0).slice(-6).map((p) => Number(p.litros))
    const normalLitros = litrosPrev.length >= 3 ? mediana(litrosPrev) : null
    const litrosProy = Number(r.litros ?? 0) * k
    const desvio = normalLitros ? litrosProy / normalLitros - 1 : null
    const kmLNormal = mediana(previos.filter((p) => p.km_l != null).slice(-6).map((p) => Number(p.km_l)))
    const pares = delMesFlota.filter((o) => o.patente !== r.patente && o.km_l != null && tipoDe(o.tipo) === tipoDe(r.tipo))
    const kmLTipo = pares.length >= 2 ? mediana(pares.map((o) => Number(o.km_l))) : null
    const kmL = r.km_l == null ? null : Number(r.km_l)
    const alertas = alertasPorPatente.get(r.patente) ?? 0

    const motivos: Motivo[] = []
    const se = sinExplicar.get(r.patente) ?? null
    if (se?.sospechoso) motivos.push({ nivel: 'alto', texto:
      `Cargó ${f0(se.litros)} L y sus ${f0(se.kmGps)} km a ${f1(se.kmLRef)} km/L piden ${f0(se.esperados)} L: `
      + `sobran ${f0(se.exceso)} L, más de lo que explica un estanque lleno (${f0(se.capacidad)} L).` })
    const ref = kmLNormal ?? kmLTipo
    const kmLBajo = kmL != null && ref != null && kmL < 0.8 * ref
    if (desvio != null && desvio >= 0.5 && k <= PROYECCION_CONFIABLE) {
      const cargo = `Cargó ${pct(desvio)} sobre su normal (${f0(litrosProy)} L${k > 1 ? ' proyectados' : ''} vs ${f0(normalLitros!)} L)`
      if (kmL == null) motivos.push({ nivel: 'medio', texto: `${cargo} y no hay km del GPS para confirmar que anduvo más.` })
      else if (kmLBajo) motivos.push({ nivel: 'alto', texto: `${cargo} y el km/L bajó a ${f1(kmL)} (normal ${f1(ref!)}).` })
      else motivos.push({ nivel: 'info', texto: `${cargo}, pero recorrió más: el km/L se mantiene en ${f1(kmL)}.` })
    } else if (kmLBajo) {
      motivos.push({ nivel: 'alto', texto: kmLNormal != null
        ? `Km/L ${f1(kmL!)}, bajo su normal de ${f1(kmLNormal)} (${pct(kmL! / kmLNormal - 1)}).`
        : `Km/L ${f1(kmL!)}, bajo el de los otros de su tipo (${f1(kmLTipo!)}).` })
    }
    if (alertas > 0) motivos.push({ nivel: 'medio', texto: `${alertas} ${alertas === 1 ? 'carga' : 'cargas'} con alerta: ver el detalle.` })
    return { patente: r.patente, tipo: r.tipo, parcial: k > 1, litrosProy, normalLitros, desvio,
      kmGps: r.km_gps, kmL, kmLNormal, kmLTipo, alertas, sinExplicar: se, motivos }
  })
}

const PESO: Record<Nivel, number> = { alto: 100, medio: 10, info: 0 }
export const puntaje = (r: Revision) => r.motivos.reduce((s, m) => s + PESO[m.nivel], 0)
export const paraRevisar = (rs: Revision[]) => rs.filter((r) => puntaje(r) > 0)
  .sort((a, b) => puntaje(b) - puntaje(a) || (b.desvio ?? 0) - (a.desvio ?? 0))
