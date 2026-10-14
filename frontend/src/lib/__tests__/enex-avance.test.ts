import { describe, it, expect } from 'vitest'
import {
  ventanaTrimestre, inicioTrimestreContractual, calcularAvance, curvaS, codigoCelda,
  interpretarCodigo, leerHojaPlanilla, emparejar, tramoMulta, type ProgAvance,
} from '@/lib/enex-avance'

const prog = (id: string, fecha: string | null, estado: ProgAvance['estado'] = null, fechaEj: string | null = null, mes = 8): ProgAvance => ({
  programacion_id: id, periodo_anio: 2026, periodo_mes: fecha ? Number(fecha.slice(5, 7)) : mes,
  fecha_programada: fecha, fecha_ejecucion: fechaEj, estado, cumplida: estado === 'cumplida',
})

describe('ventanas', () => {
  it('trimestre contractual anclado en febrero', () => {
    expect(inicioTrimestreContractual('2026-10-14')).toEqual({ anio: 2026, mes: 8 })
    expect(inicioTrimestreContractual('2026-08-01')).toEqual({ anio: 2026, mes: 8 })
    expect(inicioTrimestreContractual('2027-01-20')).toEqual({ anio: 2026, mes: 11 })
    expect(inicioTrimestreContractual('2026-12-05')).toEqual({ anio: 2026, mes: 11 })
    expect(inicioTrimestreContractual('2026-02-01')).toEqual({ anio: 2026, mes: 2 })
  })
  it('ventana de tres meses cruza el año', () => {
    const v = ventanaTrimestre(2026, 11)
    expect(v.desde).toBe('2026-11-01')
    expect(v.hasta).toBe('2027-01-31')
    expect(v.meses.map((m) => `${m.anio}-${m.mes}`)).toEqual(['2026-11', '2026-12', '2027-1'])
  })
})

describe('avance', () => {
  const hoy = '2026-09-15'
  const rows = [
    prog('a', '2026-08-05', 'cumplida', '2026-08-05'),
    prog('b', '2026-08-20', 'ejecutada', '2026-08-22'),
    prog('c', '2026-09-01'),                 // atrasada
    prog('d', '2026-09-10', 'no_realizada'),
    prog('e', '2026-09-15'),                 // hoy
    prog('f', '2026-10-01'),
    prog('g', null, null, null, 10),         // sin fecha → pesa al 31-oct
    prog('h', '2026-10-20'),
  ]
  it('real, ejecutado, plan y proyecciones', () => {
    const a = calcularAvance(rows, hoy)
    expect(a.total).toBe(8)
    expect(a.planHoy).toBe(5)            // a b c d e
    expect(a.cumplidas).toBe(1)
    expect(a.ejecutadas).toBe(2)
    expect(a.atrasadas).toBe(1)
    expect(a.noRealizadas).toBe(1)
    expect(a.futuras).toBe(4)            // e f g h
    expect(a.pctReal).toBe(12.5)
    expect(a.pctEjecutado).toBe(25)
    expect(a.pctPlanHoy).toBe(62.5)
    expect(a.pctProyectadoPlan).toBe(75) // 2 hechas + 4 futuras; atrasada y no realizada no suman
    expect(a.spi).toBe(0.4)
    expect(a.pctProyectadoRitmo).toBe(40)
    expect(a.desviacion).toBe(-37.5)
  })
  it('vacío no divide por cero', () => {
    const a = calcularAvance([], hoy)
    expect(a.pctReal).toBeNull()
    expect(a.spi).toBeNull()
  })
  it('curva S: plan termina en 100, real se corta hoy, proyección parte del real', () => {
    const c = curvaS(rows, '2026-08-01', '2026-10-31', hoy)
    expect(c[0].fecha).toBe('2026-08-01')
    expect(c[c.length - 1].plan).toBe(100)
    const iHoy = c.findIndex((p) => p.fecha === hoy)
    expect(c[iHoy].real).toBe(25)
    expect(c[iHoy + 1].real).toBeNull()
    expect(c[iHoy].proyectado).toBe(37.5)     // 2 hechas + la de hoy
    expect(c[c.length - 1].proyectado).toBe(75)
    expect(c[iHoy - 1].proyectado).toBeNull()
  })
})

describe('códigos', () => {
  it('celda como la planilla', () => {
    expect(codigoCelda([{ tipo_servicio: 'mantencion', esCamion: false }, { tipo_servicio: 'calibracion', esCamion: false }])).toBe('CMP')
    expect(codigoCelda([{ tipo_servicio: 'calibracion', esCamion: false }])).toBe('C')
    expect(codigoCelda([{ tipo_servicio: 'mantencion', esCamion: false }])).toBe('MP')
    expect(codigoCelda([{ tipo_servicio: 'calibracion', esCamion: true }])).toBe('CP')
    expect(codigoCelda([{ tipo_servicio: 'calibracion', esCamion: true }, { tipo_servicio: 'calibracion', esCamion: true }])).toBe('CP2')
  })
  it('interpretar códigos de la planilla', () => {
    expect(interpretarCodigo('CMP')?.servicios).toEqual(['mantencion', 'calibracion'])
    expect(interpretarCodigo(' cp2 ')).toEqual({ servicios: ['calibracion'], camiones: 2 })
    expect(interpretarCodigo('AG')?.servicios).toEqual(['mantencion'])
    expect(interpretarCodigo('R')).toBeNull()
    expect(interpretarCodigo('RP')).toBeNull()
  })
  it('tramos de multa', () => {
    expect(tramoMulta(97).pct).toBe(0)
    expect(tramoMulta(92).pct).toBe(10)
    expect(tramoMulta(85).pct).toBe(20)
    expect(tramoMulta(70).revision).toBe(true)
  })
})

describe('leer planilla', () => {
  // Réplica reducida de la hoja CENTINELA: semanas en la fila 4, días en la 5, letras en la 6.
  const fila = (vals: Record<number, unknown>, n = 12) => Array.from({ length: n }, (_, i) => vals[i] ?? null)
  const m: unknown[][] = [
    fila({ 0: 'PLANIFICACIÓN DIARIA — CENTINELA · AGOSTO–OCTUBRE 2026' }),
    fila({}),
    fila({}),
    fila({ 0: 'Instalación / Equipo', 2: 'S35 · 24 ago – 30 ago', 9: 'S36 · 31 ago – 06 sep' }),
    fila({ 2: 28, 3: 29, 4: 30, 5: 31, 6: 1, 7: 2, 8: 3, 9: 4, 10: 5, 11: 6 }),
    fila({ 2: 'v', 3: 's' }),
    fila({ 0: 'RONDA 3ER TRIMESTRE' }),
    fila({ 0: 'Estación de Servicios Óxido', 1: 'Combustibles', 2: 'CMP', 6: 'R' }),
    fila({ 0: 'Semi Móvil 2 (Sulfuro)', 1: 'Combustibles' }),
    fila({ 0: 'CAMIONES — RONDA' }),
    fila({ 0: 'Calibración camiones', 1: 'Combustibles', 5: 'CP2', 7: 'cp' }),
    fila({ 0: 'Actividades por día', 2: 1 }),
    fila({ 0: 'Otra cosa', 1: 'x', 2: 'CMP' }),
  ]
  it('fechas, cambio de mes y códigos', () => {
    const h = leerHojaPlanilla(m, 2025)
    expect(h.desde).toBe('2026-08-28')
    expect(h.hasta).toBe('2026-09-06')
    expect(h.filas.map((f) => f.nombre)).toEqual(['Estación de Servicios Óxido', 'Semi Móvil 2 (Sulfuro)', 'Calibración camiones'])
    expect(h.filas[0].entradas).toEqual([{ fecha: '2026-08-28', codigo: 'CMP', servicios: ['mantencion', 'calibracion'], camiones: 0 }])
    expect(h.filas[2].esCamiones).toBe(true)
    expect(h.filas[2].entradas.map((e) => [e.fecha, e.camiones])).toEqual([['2026-08-31', 2], ['2026-09-02', 1]])
    expect(h.ignorados).toEqual([{ codigo: 'R', n: 1 }])
  })
})

describe('emparejar nombres', () => {
  const inst = [
    { id: '1', nombre: 'EESS Óxido' }, { id: '2', nombre: 'EESS Sulfuro' }, { id: '3', nombre: 'Semimóvil 2' },
    { id: '4', nombre: 'Petrolera Óxido' }, { id: '5', nombre: 'Semimóvil Esperanza Sur' },
  ]
  it('sinónimos de la planilla', () => {
    expect(emparejar('Estación de Servicios Óxido', inst)?.id).toBe('1')
    expect(emparejar('Estación de Servicios Sulfuro', inst)?.id).toBe('2')
    expect(emparejar('Semi Móvil 2 (Sulfuro)', inst)?.id).toBe('3')
    expect(emparejar('Petrolera Óxido', inst)?.id).toBe('4')
    expect(emparejar('TK 120 SX', inst)).toBeNull()
  })
})
