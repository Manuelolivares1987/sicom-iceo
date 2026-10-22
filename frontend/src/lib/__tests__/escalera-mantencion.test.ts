import { describe, expect, it } from 'vitest'
import { limiteProxima, reprogramarEscalera, secuenciaEscalera } from '../escalera-mantencion'

const MB = [
  { id: 'sl', nombre: 'SL', frecuencia_horas: 300, ultima_ejecucion_horas: 22310 },
  { id: 'sm1', nombre: 'SM1', frecuencia_horas: 600, ultima_ejecucion_horas: 21581.7 },
  { id: 'sm2', nombre: 'SM2', frecuencia_horas: 1200, ultima_ejecucion_horas: 21581.7 },
  { id: 'sm3', nombre: 'SM3', frecuencia_horas: 2400, ultima_ejecucion_horas: 21581.7 },
  { id: 'sm4', nombre: 'SM4', frecuencia_horas: 4800, ultima_ejecucion_horas: 21581.7 },
]

const secuencia = (r: ReturnType<typeof reprogramarEscalera>, n = 6) =>
  secuenciaEscalera(r.map((p) => ({ nombre: p.nombre, frecuencia_horas: p.frecuencia_horas, base: p.base_nueva ?? p.ultima_ejecucion_horas })), n)

describe('reprogramarEscalera', () => {
  it('próxima SM2: las menores vencen junto, las mayores cuentan desde el peldaño anterior', () => {
    const r = reprogramarEscalera(MB, 'sm2', 23000)
    expect(Object.fromEntries(r.map((p) => [p.id, p.base_nueva]))).toEqual({
      sl: 22700, sm1: 22400, sm2: 21800, sm3: 21800, sm4: 21800,
    })
    expect(secuencia(r).map((s) => `${s.horas} ${s.nombre}`)).toEqual([
      '23000 SM2', '23300 SL', '23600 SM1', '23900 SL', '24200 SM3', '24500 SL',
    ])
  })

  it('próxima SL: después viene SM1', () => {
    const r = reprogramarEscalera(MB, 'sl', 22900)
    expect(secuencia(r, 4).map((s) => s.nombre)).toEqual(['SL', 'SM1', 'SL', 'SM2'])
    expect(secuencia(r, 1)[0].horas).toBe(22900)
  })

  it('las pautas que no calzan con la escalera no se tocan', () => {
    const renault = [
      { id: 'sl', nombre: 'SL', frecuencia_horas: 300, ultima_ejecucion_horas: 1870 },
      { id: 'b', nombre: 'Básico', frecuencia_horas: 600, ultima_ejecucion_horas: 1769 },
      { id: 'o', nombre: 'Overhaul', frecuencia_horas: 6000, ultima_ejecucion_horas: 1769 },
      { id: 'r', nombre: 'Refrigerante', frecuencia_horas: 8000, ultima_ejecucion_horas: 1769 },
      { id: 'm', nombre: 'Mayor', frecuencia_horas: 2400, ultima_ejecucion_horas: 1769 },
    ]
    const r = reprogramarEscalera(renault, 'm', 2100)
    expect(r.find((p) => p.id === 'r')!.base_nueva).toBeNull()
    expect(r.find((p) => p.id === 'o')!.base_nueva).toBeNull()   // 6000 no es múltiplo de 2400
    expect(r.find((p) => p.id === 'sl')!.base_nueva).toBe(1800)
  })

  it('límite: la base más alta no puede quedar sobre el horómetro actual', () => {
    const r = reprogramarEscalera(MB, 'sm2', 23000)
    // base más alta = SL 22700 → con horómetro 22791 la próxima puede ir hasta 23091
    expect(limiteProxima(r, 23000, 22791)).toBe(23091)
  })
})
