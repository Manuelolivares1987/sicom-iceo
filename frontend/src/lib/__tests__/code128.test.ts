import { describe, expect, it } from 'vitest'
import { PARADA, PATRONES, anchos, barras, esCodificable, simbolos } from '@/lib/barcode/code128'

describe('Code128-B', () => {
  it('cada patrón suma 11 módulos y la parada 13', () => {
    expect(PATRONES).toHaveLength(106)
    for (const p of PATRONES) expect(p.split("").reduce((s, d) => s + Number(d), 0)).toBe(11)
    expect(PARADA.split("").reduce((s, d) => s + Number(d), 0)).toBe(13)
  })

  it('decodificar las barras devuelve el mismo texto y un verificador válido', () => {
    for (const t of ['FRK-0001', 'ISEEPPCAM001-LB', 'AFEFERAGD001']) {
      const w = anchos(t)
      const syms: number[] = []
      for (let i = 0; i + 6 <= w.length - 7; i += 6) syms.push(PATRONES.indexOf(w.slice(i, i + 6).join('')))
      expect(syms[0]).toBe(104)
      const datos = syms.slice(1, -1)
      expect(String.fromCharCode(...datos.map((v) => v + 32))).toBe(t)
      expect(datos.reduce((s, v, i) => s + v * (i + 1), 104) % 103).toBe(syms.at(-1))
      expect(w.slice(-7).join('')).toBe(PARADA)
    }
  })

  it('el código completo tiene 11 módulos por símbolo + 13 de parada', () => {
    const t = 'FRK-0001'
    const total = anchos(t).reduce((s, w) => s + w, 0)
    expect(total).toBe((t.length + 2) * 11 + 13)
    expect(barras(t).total).toBe(total + 20)
  })

  it('rechaza texto fuera de ASCII imprimible', () => {
    expect(esCodificable('AÑO-1')).toBe(false)
    expect(esCodificable('ISEEPPCAM001-LB')).toBe(true)
  })
})
