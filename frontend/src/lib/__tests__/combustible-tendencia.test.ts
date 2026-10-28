import { describe, expect, it } from 'vitest'
import type { RendimientoMes } from '@/lib/services/combustible-tarjeta'
import {
  factorMes, filaFlota, litrosSinExplicar, mapaCalor, mediana, paraRevisar, rangoMeses, revisarVehiculos, serieFlota, valorBase,
} from '@/lib/combustible-tendencia'

// Patentes y cifras inventadas.
const fila = (patente: string, mes: string, litros: number, extra: Partial<RendimientoMes> = {}): RendimientoMes => ({
  fuente: 'tarjeta', activo_id: null, patente, tipo: 'Camionetas', mes, cargas: 4, litros, monto: litros * 1000,
  monto_real: true, km_gps: null, dias_gps: null, horas: null, litros_ralenti: null, cargas_medidas: null,
  km_medidos: null, km_l: null, costo_km: null, grupo: 'flota', ...extra,
})

describe('mediana y meses', () => {
  it('mediana par e impar', () => {
    expect(mediana([3, 1, 2])).toBe(2)
    expect(mediana([4, 1, 2, 3])).toBe(2.5)
    expect(mediana([])).toBeNull()
  })
  it('rango de meses cruza el año', () => {
    expect(rangoMeses('2026-02-01', 3)).toEqual(['2025-12-01', '2026-01-01', '2026-02-01'])
  })
})

describe('factorMes', () => {
  it('proyecta el mes del corte y deja igual los cerrados', () => {
    expect(factorMes('2026-10-01', '2026-10-27')).toBeCloseTo(31 / 27)
    expect(factorMes('2026-09-01', '2026-10-27')).toBe(1)
    expect(factorMes('2026-10-01', '2026-10-31')).toBe(1)
    expect(factorMes('2026-10-01', null)).toBe(1)
  })
})

describe('serie de la flota', () => {
  const rend = [
    fila('AAAA11', '2026-09-01', 100, { km_medidos: 1200, km_l: 12, costo_km: 100 }),
    fila('BBBB22', '2026-09-01', 50, { km_medidos: 400, km_l: 8, costo_km: 150 }),
    fila('CCCC33', '2026-09-01', 900, { grupo: 'abastecimiento' }),
    fila('RENA44', '2026-09-01', 300, { fuente: 'computador' }),
  ]
  it('solo suma la flota con tarjeta y pondera el km/L por los litros', () => {
    const [p] = serieFlota(rend, ['2026-09-01'], '2026-10-10')
    expect(p.litros).toBe(150)
    expect(p.vehiculos).toBe(2)
    expect(p.kmL).toBeCloseTo(1600 / (100 + 50))
    expect(p.costoKm).toBeCloseTo((100 * 1200 + 150 * 400) / 1600)
    expect(p.parcial).toBe(false)
  })
  it('compara contra el mes anterior o el promedio de 3', () => {
    const s = serieFlota([
      fila('A', '2026-06-01', 100), fila('A', '2026-07-01', 200), fila('A', '2026-08-01', 300), fila('A', '2026-09-01', 400),
    ], rangoMeses('2026-09-01', 4), null)
    expect(valorBase(s, '2026-09-01', 'ant', 'litrosProy')).toBe(300)
    expect(valorBase(s, '2026-09-01', 'prom3', 'litrosProy')).toBe(200)
    expect(valorBase(s, '2026-06-01', 'ant', 'litrosProy')).toBeNull()
  })
})

describe('mapa de calor', () => {
  const meses = rangoMeses('2026-10-01', 5)
  const rend = [
    fila('AAAA11', '2026-06-01', 120), fila('AAAA11', '2026-07-01', 110), fila('AAAA11', '2026-08-01', 130),
    fila('AAAA11', '2026-09-01', 125), fila('AAAA11', '2026-10-01', 270),
  ]
  it('el mes raro se compara contra la mediana de los otros meses cerrados', () => {
    const [f] = mapaCalor(rend, meses, '2026-10-31')
    const oct = f.celdas['2026-10-01']
    expect(oct.normal).toBe(122.5)
    expect(oct.desvio).toBeCloseTo(270 / 122.5 - 1)
    // El mes raro no entra a su propio normal.
    expect(f.celdas['2026-06-01'].normal).toBe(127.5)
  })
  it('el mes en curso se proyecta y no cuenta como normal de los otros', () => {
    const [f] = mapaCalor(rend, meses, '2026-10-15')
    expect(f.celdas['2026-10-01'].litrosProy).toBeCloseTo(270 * 31 / 15)
    expect(f.celdas['2026-06-01'].normal).toBe(125)
  })
  it('el mes en que parte el historial no se pinta ni sirve de normal', () => {
    const r = [fila('AAAA11', '2026-05-01', 10), ...rend]
    const m = rangoMeses('2026-10-01', 6)
    const [f] = mapaCalor(r, m, '2026-10-31', '2026-05-29')
    expect(f.celdas['2026-05-01'].desvio).toBeNull()
    expect(f.celdas['2026-06-01'].normal).toBe(127.5)
    const s = serieFlota(r, m, '2026-10-31', '2026-05-29')
    expect(valorBase(s, '2026-06-01', 'ant', 'litrosProy')).toBeNull()
  })
  it('la fila de toda la flota usa la misma regla', () => {
    const f = filaFlota(serieFlota(rend, meses, '2026-10-31'))
    expect(f.celdas['2026-10-01'].normal).toBe(122.5)
  })
})

describe('revisión por vehículo', () => {
  const base = [
    fila('AAAA11', '2026-06-01', 120), fila('AAAA11', '2026-07-01', 110), fila('AAAA11', '2026-08-01', 130),
  ]
  const revisar = (oct: RendimientoMes, sep?: RendimientoMes) =>
    revisarVehiculos([...base, ...(sep ? [sep] : []), oct], '2026-10-01', '2026-10-31', new Map())[0]

  it('carga mucho más y sin km: medio', () => {
    const r = revisar(fila('AAAA11', '2026-10-01', 260))
    expect(r.motivos.map((m) => m.nivel)).toEqual(['medio'])
    expect(r.motivos[0].texto).toContain('no hay km')
  })
  it('carga mucho más pero el km/L se mantiene: solo informativo', () => {
    const r = revisar(fila('AAAA11', '2026-10-01', 260, { km_l: 12 }), fila('AAAA11', '2026-09-01', 120, { km_l: 12.5 }))
    expect(r.motivos.map((m) => m.nivel)).toEqual(['info'])
    expect(paraRevisar([r])).toHaveLength(0)
  })
  it('carga mucho más y el km/L se cae: alto', () => {
    const r = revisar(fila('AAAA11', '2026-10-01', 260, { km_l: 8 }), fila('AAAA11', '2026-09-01', 120, { km_l: 12.5 }))
    expect(r.motivos[0].nivel).toBe('alto')
  })
  it('km/L bajo su normal aunque los litros estén normales: alto', () => {
    const r = revisar(fila('AAAA11', '2026-10-01', 125, { km_l: 9 }), fila('AAAA11', '2026-09-01', 120, { km_l: 12.5 }))
    expect(r.motivos.map((m) => m.nivel)).toEqual(['alto'])
  })
  it('con pocos días del mes no se juzga por litros', () => {
    const r = revisarVehiculos([...base, fila('AAAA11', '2026-10-01', 80)], '2026-10-01', '2026-10-05', new Map())[0]
    expect(r.motivos).toHaveLength(0)
  })
  it('cuenta las cargas con alerta y ordena por gravedad', () => {
    const rs = revisarVehiculos([
      ...base, fila('AAAA11', '2026-10-01', 125),
      fila('BBBB22', '2026-06-01', 50), fila('BBBB22', '2026-07-01', 50), fila('BBBB22', '2026-08-01', 50),
      fila('BBBB22', '2026-10-01', 200),
    ], '2026-10-01', '2026-10-31', new Map([['AAAA11', 2]]))
    expect(paraRevisar(rs).map((r) => r.patente)).toEqual(['BBBB22', 'AAAA11'])
  })
})

describe('litros sin explicar', () => {
  const refs = new Map([['AAAA11', { kmL: 12, capacidad: 80 }]])
  const sep = fila('AAAA11', '2026-09-01', 300, { km_gps: 3600 })
  it('lo esperado sale de los km GPS a su km/L normal', () => {
    const se = litrosSinExplicar([sep, fila('AAAA11', '2026-10-01', 330, { km_gps: 3600 })], '2026-10-01', refs).get('AAAA11')!
    expect(se.esperados).toBe(300)
    expect(se.exceso).toBe(30)
    expect(se.sospechoso).toBe(false) // cabe en el nivel del estanque
  })
  it('sospechoso si sobra más que un estanque + 20 %', () => {
    const oct = fila('AAAA11', '2026-10-01', 460, { km_gps: 3600 })
    const se = litrosSinExplicar([sep, oct], '2026-10-01', refs).get('AAAA11')!
    expect(se.sospechoso).toBe(true) // 460 > 300 × 1,2 + 88
    const [r] = revisarVehiculos([sep, oct], '2026-10-01', '2026-10-31', new Map(), null, new Map([['AAAA11', se]]))
    expect(r.motivos[0]).toMatchObject({ nivel: 'alto' })
    expect(r.motivos[0].texto).toContain('sobran 160 L')
  })
  it('sin GPS el mes anterior no se calcula (los km del mes estarían incompletos)', () => {
    expect(litrosSinExplicar([fila('AAAA11', '2026-10-01', 460, { km_gps: 3600 })], '2026-10-01', refs).size).toBe(0)
  })
})
