import { describe, expect, it } from 'vitest'
import { armarPlanSemana, asuntoPlanSemana, emlBorrador, htmlPlanSemana } from '@/lib/email/enex-plan-semana'
import type { EnexPanelRow, EnexPlanTarea } from '@/lib/services/enex'

let orden = 100
const t = (fecha: string, instalacion: string, alcance: string, codigo: string, actividad: string, bloque: string) => ({
  fecha, instalacion, instalacion_id: instalacion, alcance, area: 'Truck Shop Lomas 2', codigo_item: codigo, actividad, bloque,
  bloque_orden: Number(codigo.split('.')[0]), orden: orden++,
}) as EnexPlanTarea
const MF = 'Truck Shop Lomas 2 - Microfiltrado'
const racks = ['Truck Shop Lomas 2 - Rack 1', 'Truck Shop Lomas 2 - Rack 2', 'Truck Shop Lomas 2 - Rack 3']

const tareas: EnexPlanTarea[] = [
  t('2026-11-23', MF, 'Instalaciones exteriores', '1.1', 'Limpieza exterior de líneas de lubricantes', '1. Housekeeping de instalaciones'),
  t('2026-11-23', MF, 'Instalaciones exteriores', '4.4', 'Medición de temperatura del motor eléctrico', '4. Mantención Eléctrica'),
  t('2026-11-24', MF, 'Sala de microfiltrado', '2.4', 'Inspección de manómetros de presión', '2. Instrumentación'),
  ...racks.map((r) => t('2026-11-25', r, 'Lubricanteras (Rack 1, 2 y 3)', '5.1', 'Inspección estaciones de carrete', '5. Lubricanteras')),
  ...racks.slice(0, 2).map((r) => t('2026-11-25', r, 'Lubricanteras (Rack 1, 2 y 3)', '3.2', 'Mantención bombas de diafragma 2"', '3. Mantención Mecánica')),
  t('2026-11-30', MF, 'Fuera', '1.2', 'De la otra semana', '1. Housekeeping'),
]
const prog = (id: string, fecha: string, x: Partial<EnexPanelRow> = {}) => ({
  programacion_id: id, instalacion_id: id, instalacion: id, instalacion_tipo: 'estanque', tipo_servicio: 'mantencion', fecha_programada: fecha, ...x,
}) as EnexPanelRow

describe('correo plan semanal ESM', () => {
  const p = armarPlanSemana({
    faena: 'Lomas Bayas — Lubricantes', lunes: '2026-11-23', tareas,
    programaciones: [prog(MF, '2026-11-23'), prog('EESS X', '2026-11-27', { tipo_servicio: 'calibracion' })],
  })

  it('agrupa por día y lugar, y junta los días libres', () => {
    expect(p.numero).toBe(48)
    expect(p.dias.map((d) => d.fecha)).toEqual(['2026-11-23', '2026-11-24', '2026-11-25', '2026-11-27'])
    expect(p.libres).toEqual([['2026-11-26', '2026-11-26'], ['2026-11-28', '2026-11-29']])
    expect(p.dias[0].grupos[0].bloques.map((b) => b.bloque)).toEqual(['Housekeeping de instalaciones', 'Mantención Eléctrica'])
    // La programación ya detallada por el plan no se repite como servicio.
    expect(p.dias[0].servicios).toEqual([])
    expect(p.dias[3].servicios).toEqual([{ instalacion: 'EESS X', servicio: 'Calibración' }])
  })

  it('racks: distingue actividades que no van en todos', () => {
    const g = p.dias[2].grupos[0]
    expect(g.instalaciones).toHaveLength(3)
    expect(g.mismasEnCada).toBe(false)
    const html = htmlPlanSemana(p, 'Manuel Olivares')
    expect(html).toContain('(Rack 1 y Rack 2)')
    expect(html).toContain('Mantención bombas de diafragma 2&quot;')
    expect(html).toContain('Truck Shop Lomas 2 – Rack 1, Rack 2 y Rack 3')
  })

  it('asunto con la estructura pedida por ESM', () => {
    expect(asuntoPlanSemana(p)).toBe('ESM PILLADO // Plan semanal Lomas Bayas — Lubricantes · Semana 48 (23-11 al 29-11)')
  })

  it('eml sin enviar con acentos bien codificados', () => {
    const eml = emlBorrador({ para: ['a@esm.cl'], copia: ['b@esm.cl', 'malo'], asunto: 'Plan Miércoles', html: '<p>Mantención</p>' })
    expect(eml).toContain('X-Unsent: 1')
    expect(eml).toContain('To: a@esm.cl\r\nCc: b@esm.cl\r\n')
    const asunto = /Subject: =\?UTF-8\?B\?(.+)\?=/.exec(eml)![1]
    expect(Buffer.from(asunto, 'base64').toString('utf8')).toBe('Plan Miércoles')
    const cuerpo = eml.split('\r\n\r\n')[1].replace(/\r\n/g, '')
    expect(Buffer.from(cuerpo, 'base64').toString('utf8')).toContain('<p>Mantención</p>')
  })
})
