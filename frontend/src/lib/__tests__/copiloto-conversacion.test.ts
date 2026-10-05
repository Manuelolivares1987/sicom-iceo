import { describe, it, expect } from 'vitest'
import {
  tituloConversacion, construirHistorial, describirPausa, necesitaSeguimiento,
} from '@/lib/copiloto/conversacion'

describe('tituloConversacion', () => {
  it('usa la pregunta tal cual cuando es corta', () => {
    expect(tituloConversacion('no parte en frío')).toBe('No parte en frío')
  })
  it('limpia los mensajes automáticos del diagnóstico guiado', () => {
    expect(tituloConversacion('Diagnóstico iniciado. Síntoma: se apagan las luces del tablero. ¿Por dónde parto?'))
      .toBe('Se apagan las luces del tablero.')
  })
  it('corta en la primera frase si es larga', () => {
    const t = tituloConversacion('El camión HHWB-42 no enciende las luces de trabajo cuando prendo la PTO. Ya revisé el fusible F12 y está bueno, qué más puede ser')
    expect(t.length).toBeLessThanOrEqual(91)
    expect(t.endsWith('.')).toBe(true)
  })
  it('sin pregunta, nombra los adjuntos', () => {
    expect(tituloConversacion('', [{ nombre: 'informe-scanner.pdf' }])).toBe('Revisión de informe-scanner.pdf')
    expect(tituloConversacion('', [{ nombre: 'a.jpg' }, { nombre: 'b.jpg' }])).toBe('Revisión de 2 adjuntos')
    expect(tituloConversacion('')).toBe('Consulta al copiloto')
  })
})

describe('construirHistorial', () => {
  const c = (i: number, conRespuesta = true) => ({
    pregunta: `pregunta ${i}`, respuesta: conRespuesta ? `respuesta ${i}` : null,
    created_at: `2026-10-0${Math.min(9, 1 + Math.floor(i / 10))}T10:${String(i % 60).padStart(2, '0')}:00Z`,
  })
  it('omite las consultas sin respuesta (cortadas) y mantiene el orden', () => {
    const { turnos, resumenAnteriores } = construirHistorial([c(2), c(1), c(3, false)])
    expect(turnos.map((t) => t.texto)).toEqual(['pregunta 1', 'respuesta 1', 'pregunta 2', 'respuesta 2'])
    expect(resumenAnteriores).toBeNull()
  })
  it('las antiguas van como lista de preguntas, las recientes completas', () => {
    const { turnos, resumenAnteriores } = construirHistorial(Array.from({ length: 9 }, (_, i) => c(i)), 3)
    expect(turnos).toHaveLength(6)
    expect(turnos[0].texto).toBe('pregunta 6')
    expect(resumenAnteriores).toContain('pregunta 0')
    expect(resumenAnteriores).toContain('pregunta 5')
    expect(resumenAnteriores).not.toContain('pregunta 6')
  })
})

describe('seguimiento', () => {
  const ahora = new Date('2026-10-05T20:00:00Z')
  it('describe la pausa en horas o días', () => {
    expect(describirPausa('2026-10-05T19:30:00Z', ahora)).toBe('hace menos de una hora')
    expect(describirPausa('2026-10-05T14:00:00Z', ahora)).toBe('hace 6 h')
    expect(describirPausa('2026-10-02T14:00:00Z', ahora)).toBe('hace 3 días')
  })
  it('pide seguimiento solo a hilos abiertos con equipo y silencio largo', () => {
    const base = { estado: 'abierta', activo_id: 'a', diagnostico_id: null, mensajes: 2, ultimo_at: '2026-10-04T20:00:00Z' }
    expect(necesitaSeguimiento(base, ahora)).toBe(true)
    expect(necesitaSeguimiento({ ...base, ultimo_at: '2026-10-05T15:00:00Z' }, ahora)).toBe(false)
    expect(necesitaSeguimiento({ ...base, estado: 'resuelta' }, ahora)).toBe(false)
    expect(necesitaSeguimiento({ ...base, activo_id: null }, ahora)).toBe(false)
    expect(necesitaSeguimiento({ ...base, activo_id: null, diagnostico_id: 'd' }, ahora)).toBe(true)
  })
})
