import { describe, expect, it } from 'vitest'
import {
  fmtMM, fmtPct, nivelAsignacion, pct, rangoPreset, sumarMeses, variacionPct, vsMediana,
} from '../costos-operacion'

describe('costos de operación', () => {
  it('variación sin base no inventa un porcentaje', () => {
    expect(variacionPct(100, 0)).toBeNull()
    expect(variacionPct(100, null)).toBeNull()
    expect(variacionPct(150, 100)).toBe(50)
    expect(variacionPct(50, 100)).toBe(-50)
  })

  it('pct', () => {
    expect(pct(25, 100)).toBe(25)
    expect(pct(1, 0)).toBeNull()
  })

  it('costo por hora contra la mediana solo con horas suficientes', () => {
    expect(vsMediana(8000, 4000, 500, 5)).toBe(2)
    expect(vsMediana(69_000, 5000, 40, 5)).toBeNull()   // casi parado: no se compara
    expect(vsMediana(3000, 3000, 500, 1)).toBeNull()    // tipo con un solo equipo
    expect(vsMediana(null, 3000, 500, 5)).toBeNull()
  })

  it('semáforo de asignación', () => {
    expect(nivelAsignacion(95)).toBe('bien')
    expect(nivelAsignacion(80)).toBe('atencion')
    expect(nivelAsignacion(40)).toBe('mal')
    expect(nivelAsignacion(null)).toBeNull()
  })

  it('suma meses cruzando el año', () => {
    expect(sumarMeses('2026-01-01', -1)).toBe('2025-12-01')
    expect(sumarMeses('2026-10-01', -11)).toBe('2025-11-01')
    expect(sumarMeses('2025-12-01', 1)).toBe('2026-01-01')
  })

  it('rangos por meses completos', () => {
    const hoy = new Date(2026, 9, 14)
    expect(rangoPreset('mes', hoy)).toEqual({ desde: '2026-10-01', hasta: '2026-10-01' })
    expect(rangoPreset('ytd', hoy)).toEqual({ desde: '2026-01-01', hasta: '2026-10-01' })
    expect(rangoPreset('12m', hoy)).toEqual({ desde: '2025-11-01', hasta: '2026-10-01' })
  })

  it('formatos', () => {
    expect(fmtMM(12_345_678)).toBe('$12,3 M')
    expect(fmtPct(12.34, true)).toBe('+12,3 %')
    expect(fmtPct(null)).toBe('—')
  })
})
