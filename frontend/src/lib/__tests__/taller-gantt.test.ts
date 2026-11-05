import { describe, expect, it } from 'vitest'
import { carrilesDe, colocarBarras, diasVisibles, etiquetaEstadoBarra, lunesDe, papelCorto, textoPapel } from '@/lib/taller-gantt'

// 02-11-2026 es lunes.
const dias = diasVisibles('2026-11-02', '2026-11-14')
const b = (id: string, inicio: string, fin: string) => ({ id, inicio, fin })

describe('diasVisibles', () => {
  it('son 12 días y se salta el domingo', () => {
    expect(dias).toHaveLength(12)
    expect(dias).not.toContain('2026-11-08')
    expect(dias[6]).toBe('2026-11-09')
  })
})

describe('lunesDe', () => {
  it('un jueves y un domingo caen en el lunes de su semana', () => {
    expect(lunesDe('2026-11-05')).toBe('2026-11-02')
    expect(lunesDe('2026-11-08')).toBe('2026-11-02')
    expect(lunesDe('2026-11-05', 1)).toBe('2026-11-09')
  })
})

describe('colocarBarras', () => {
  it('ubica columna y largo', () => {
    const [c] = colocarBarras([b('a', '2026-11-03', '2026-11-05')], dias)
    expect([c.col, c.largo, c.carril]).toEqual([1, 3, 0])
  })

  it('no cuenta el domingo como columna al cruzar la semana', () => {
    const [c] = colocarBarras([b('a', '2026-11-07', '2026-11-09')], dias)
    expect([c.col, c.largo]).toEqual([5, 2])
  })

  it('lo atrasado de antes del rango queda pegado a la izquierda', () => {
    const [c] = colocarBarras([b('a', '2026-10-20', '2026-10-21')], dias)
    expect([c.col, c.largo, c.cortadaInicio]).toEqual([0, 1, true])
  })

  it('no dibuja lo que parte después del rango y corta lo que se pasa', () => {
    expect(colocarBarras([b('a', '2026-11-20', '2026-11-21')], dias)).toHaveLength(0)
    const [c] = colocarBarras([b('a', '2026-11-13', '2026-11-20')], dias)
    expect([c.col, c.largo, c.cortadaFin]).toEqual([10, 2, true])
  })

  it('dos barras que se topan van en carriles distintos y las seguidas comparten', () => {
    const r = colocarBarras([b('a', '2026-11-02', '2026-11-04'), b('b', '2026-11-03', '2026-11-03'), b('c', '2026-11-05', '2026-11-05')], dias)
    expect(r.map((x) => x.carril)).toEqual([0, 1, 0])
    expect(carrilesDe(r)).toBe(2)
  })
})

describe('textos', () => {
  it('papeles', () => {
    expect(textoPapel('RT', 'vencido', -148)).toBe('RT venció hace 148 d')
    expect(textoPapel('RT', 'por_vencer', 30)).toBe('RT vence en 30 d')
    expect(textoPapel('Hermeticidad', 'sin_fecha', null)).toBe('Hermeticidad: falta la fecha')
    expect(papelCorto('revision_tecnica')).toBe('RT')
  })

  it('una OT terminada sin cierre no pide foto', () => {
    expect(etiquetaEstadoBarra('falta', null, 'ot')).toBe('Falta cierre')
    expect(etiquetaEstadoBarra('falta', 'foto', 'actividad')).toBe('Falta foto')
    expect(etiquetaEstadoBarra('falta', 'certificado', 'actividad')).toBe('Falta certif.')
  })
})
