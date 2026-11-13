import { describe, expect, it, vi } from 'vitest'

// El formulario importa Supabase e IndexedDB; para probar la regla pura se
// reemplazan por dobles vacíos.
vi.mock('@/lib/supabase', () => ({ supabase: {} }))
vi.mock('@/lib/offline/inspeccion-apr-db', () => ({
  respuestaVacia: () => ({ respuesta: null, observacion: '', fotos: [] }),
}))

import { evaluarFatiga } from '@/lib/services/prevencion-inspeccion'
import { avanceBorrador, respuestaAutomatica } from '@/components/prevencion/inspeccion-apr-form'
import type { BorradorInspeccion } from '@/lib/offline/inspeccion-apr-db'
import type { PuntoPlantilla } from '@/lib/services/prevencion-inspeccion'

describe('evaluarFatiga (misma regla que fn_prevencion_evaluar_fatiga)', () => {
  const base = { horas_24: 7, horas_48: 14, horas_despierto: 3 }

  it('apto con buen descanso y sin señales', () => {
    expect(evaluarFatiga(base).resultado).toBe('apto')
  })
  it('incompleta si faltan las horas', () => {
    expect(evaluarFatiga({ horas_24: 7 }).resultado).toBe('incompleta')
  })
  it('no apto con menos de 5 h en 24 h', () => {
    expect(evaluarFatiga({ ...base, horas_24: 4.5 }).resultado).toBe('no_apto')
  })
  it('no apto con menos de 12 h en 48 h', () => {
    expect(evaluarFatiga({ ...base, horas_48: 11 }).resultado).toBe('no_apto')
  })
  it('no apto si lleva más horas despierto que lo dormido en 48 h', () => {
    expect(evaluarFatiga({ ...base, horas_despierto: 15 }).resultado).toBe('no_apto')
  })
  it('no apto con alcohol, medicamentos, malestar o somnolencia', () => {
    for (const k of ['alcohol', 'medicamentos', 'malestar', 'somnolencia'] as const) {
      expect(evaluarFatiga({ ...base, [k]: true }).resultado).toBe('no_apto')
    }
  })
  it('apto con observación entre 5 y 6 h, o con preocupaciones', () => {
    expect(evaluarFatiga({ ...base, horas_24: 5.5 }).resultado).toBe('apto_observacion')
    expect(evaluarFatiga({ ...base, preocupaciones: true }).resultado).toBe('apto_observacion')
  })
})

const P = (codigo: string, evidencia: PuntoPlantilla['evidencia'], extra: Partial<PuntoPlantilla> = {}): PuntoPlantilla => ({
  codigo, etapa_orden: 1, etapa: 'E', orden: 1, pregunta: codigo, ayuda: null,
  evidencia, posterior: false, solo_cruzado: false, ...extra,
})

const req = (item: string, ok: boolean, aplica_a: 'todos' | 'conductor' = 'todos') => ({
  tipo_codigo: item + aplica_a, nombre: item, categoria: 'curso', item_codigo: item,
  aplica_a, estado: ok ? 'vigente' : 'sin_dato', vence: null, ok,
})

function borrador(over: Partial<BorradorInspeccion> = {}): BorradorInspeccion {
  return {
    cliente_uuid: 'x', servidor_id: null, faena_id: 'f', faena_nombre: 'F', grupo: 'CALAMA',
    fecha: '2026-11-12', hora_inicio: '', instalacion: '', area_sector: '', trabajo: 't', supervisor: '',
    trabajo_cruzado: false, empresas_cruzadas: '', observacion: '',
    personas: [
      { personal_id: 'a', nombre: 'A', es_conductor: true, fatiga: { horas_24: 7, horas_48: 14, horas_despierto: 2 } },
      { personal_id: 'b', nombre: 'B', es_conductor: false, fatiga: {} },
    ],
    respuestas: {},
    plantilla: [P('T2', 'fatiga'), P('T3', 'documental'), P('D1', 'documental'), P('C1', 'foto', { solo_cruzado: true }), P('A1', 'foto')],
    habilitacion: {
      generado_at: '', grupo: 'CALAMA', requisitos: [],
      personas: [
        { personal_id: 'a', nombre: 'A', rut: '1-9', rut_provisorio: false, cargo: null,
          requisitos: [req('T3', true, 'conductor'), req('D1', true)], habilitado: true, habilitado_conductor: true },
        { personal_id: 'b', nombre: 'B', rut: '2-7', rut_provisorio: false, cargo: null,
          requisitos: [req('T3', false, 'conductor'), req('D1', false)], habilitado: false, habilitado_conductor: false },
      ],
    },
    ultimo_envio: null, created_at: '', updated_at: '',
    ...over,
  }
}

describe('respuestaAutomatica', () => {
  it('documental: no cumple si alguien de la cuadrilla falla el requisito', () => {
    expect(respuestaAutomatica(borrador(), P('D1', 'documental'))).toBe('no_cumple')
  })
  it('documental: el requisito de conductor solo cuenta para quien conduce', () => {
    // B falla T3 pero no conduce; A conduce y cumple.
    expect(respuestaAutomatica(borrador(), P('T3', 'documental'))).toBe('cumple')
  })
  it('fatiga: no aplica sin conductores; no cumple con un no apto', () => {
    const sinCond = borrador({ personas: [{ personal_id: 'b', nombre: 'B', es_conductor: false, fatiga: {} }] })
    expect(respuestaAutomatica(sinCond, P('T2', 'fatiga'))).toBe('no_aplica')
    const cansado = borrador({ personas: [{ personal_id: 'a', nombre: 'A', es_conductor: true, fatiga: { horas_24: 3, horas_48: 14, horas_despierto: 2 } }] })
    expect(respuestaAutomatica(cansado, P('T2', 'fatiga'))).toBe('no_cumple')
  })
  it('trabajo cruzado: no aplica si no hubo', () => {
    expect(respuestaAutomatica(borrador(), P('C1', 'foto', { solo_cruzado: true }))).toBe('no_aplica')
    expect(respuestaAutomatica(borrador({ trabajo_cruzado: true }), P('C1', 'foto', { solo_cruzado: true }))).toBeUndefined()
  })
  it('avance cuenta automáticos y deja pendiente lo del APR', () => {
    const av = avanceBorrador(borrador())
    // T2 cumple, T3 cumple, D1 no cumple, C1 no aplica, A1 pendiente
    expect(av).toMatchObject({ cumple: 2, noCumple: 1, noAplica: 1, pend: 1 })
    expect(av.pct).toBeCloseTo(66.7, 1)
  })
})
