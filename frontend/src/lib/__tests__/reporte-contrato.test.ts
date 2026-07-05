import { describe, it, expect } from 'vitest'
import { clavesFaltantesReporte, reporteContratoValido } from '@/lib/reporte-contrato'

describe('contrato reporte fiabilidad (RPC↔frontend)', () => {
  it('respuesta completa es válida', () => {
    const ok = { categorias: [], equipos: [], matriz: [], combustible: [] }
    expect(clavesFaltantesReporte(ok)).toEqual([])
    expect(reporteContratoValido(ok)).toBe(true)
  })
  it('falta combustible (regresión MIG146) → inválido', () => {
    const sinComb = { categorias: [], equipos: [], matriz: [] }
    expect(clavesFaltantesReporte(sinComb)).toEqual(['combustible'])
    expect(reporteContratoValido(sinComb)).toBe(false)
  })
  it('clave presente pero no-arreglo → inválido (no confundir con vacío)', () => {
    const malo = { categorias: [], equipos: [], matriz: [], combustible: null }
    expect(reporteContratoValido(malo)).toBe(false)
  })
  it('null/undefined → todas faltantes', () => {
    expect(clavesFaltantesReporte(null)).toHaveLength(4)
  })
})
