import { describe, expect, it } from 'vitest'
import { armarInformeSemanal, lunesDe, lunesSemanaAnterior, numeroSemana } from '@/lib/enex-informe-semanal'
import { asuntoInforme, htmlInformeSemanal } from '@/lib/email/enex-informe-semanal'
import type { EnexFaena, EnexPanelRow, EnexReprogramacion } from '@/lib/services/enex'

const faena = { id: 'F', nombre: 'Centinela', trimestre_ancla: 2, contrato_inst_combustible: 11, contrato_inst_lubricante: 3, contrato_camiones: 20 } as EnexFaena
const row = (id: string, x: Partial<EnexPanelRow>) => ({
  programacion_id: id, faena_id: 'F', instalacion: id, instalacion_tipo: 'camion', linea: 'combustible', tipo_servicio: 'calibracion',
  periodo_anio: 2026, periodo_mes: 11, fecha_programada: '2026-11-04', fecha_ejecucion: null, estado: null, cumplida: false, ejecucion_id: null,
  firma_mandante_url: null, ejec_observacion: null, ot_numero: null, tecnico_nombre: null, ejecutor: null, ...x,
}) as EnexPanelRow
const rep = (x: Partial<EnexReprogramacion>) => ({ programacion_id: 'R', fecha_original: '2026-11-06', nueva_fecha: '2026-12-07', created_at: '2026-11-09', ...x }) as EnexReprogramacion

const armar = (rows: EnexPanelRow[], reprogs: EnexReprogramacion[] = [], hallazgos: Parameters<typeof armarInformeSemanal>[0]['hallazgos'] = []) =>
  armarInformeSemanal({ lunes: '2026-11-02', hoy: '2026-11-09', faenas: [faena], rows, reprogs, hallazgos })

describe('informe semanal ENEX', () => {
  it('fechas de semana', () => {
    expect(lunesDe('2026-11-08')).toBe('2026-11-02')
    expect(lunesSemanaAnterior('2026-11-09')).toBe('2026-11-02')
    expect(numeroSemana('2026-11-02')).toBe(45)
  })

  it('la tarea movida a otra fecha sigue comprometida en su semana', () => {
    const i = armar([
      row('A', { estado: 'cumplida', cumplida: true, fecha_ejecucion: '2026-11-04', firma_mandante_url: 'x', ejecucion_id: 'e' }),
      row('B', { estado: 'cumplida', fecha_ejecucion: '2026-11-03', ejecucion_id: 'e2' }),
      row('R', { fecha_programada: '2026-12-07', periodo_mes: 12 }),
    ], [rep({})])
    const s = i.faenas[0].semana
    expect(s).toMatchObject({ comprometidas: 3, ejecutadas: 2, firmadas: 1, reprogramadas: 1, pendientes: 0, pct: 66.7 })
    const r = i.faenas[0].actividad.find((a) => a.programacion_id === 'R')!
    expect(r.estado).toBe('Reprogramada al 07-12')
    expect(r.fecha_plan).toBe('2026-11-06')
  })

  it('reprogramada sin fecha nueva queda por coordinar y no suma como pendiente', () => {
    const i = armar([row('R', {})], [rep({ fecha_original: '2026-11-04', nueva_fecha: null })])
    expect(i.faenas[0].actividad[0].estado).toBe('Reprogramada, fecha por coordinar')
    expect(i.faenas[0].semana).toMatchObject({ comprometidas: 1, reprogramadas: 1, pendientes: 0, pct: 0 })
  })

  it('lo de otra semana se informa sin entrar al %, y lo justificado no cuenta', () => {
    const i = armar([
      row('V', { fecha_programada: '2026-10-20', periodo_mes: 10, estado: 'cumplida', fecha_ejecucion: '2026-11-03', firma_mandante_url: 'x' }),
      row('J', { justificada: true }),
    ])
    expect(i.faenas[0].semana).toMatchObject({ comprometidas: 0, adicionales: 1, pct: null })
    expect(i.faenas[0].actividad).toHaveLength(2)
  })

  it('observación del servicio y hallazgos solo de lo hecho en la semana', () => {
    const i = armar([
      row('A', { estado: 'cumplida', fecha_ejecucion: '2026-11-04', ejecucion_id: 'e', ejec_observacion: 'Fuga menor', tecnico_nombre: 'Ana' }),
      row('Z', { fecha_programada: '2026-11-20', estado: 'cumplida', fecha_ejecucion: '2026-11-20', ejecucion_id: 'z', ejec_observacion: 'Otra semana' }),
    ], [], [{ ejecucion_id: 'e', pauta_item_id: 'p', descripcion: 'Válvula', observacion: null, foto: null }])
    const o = i.faenas[0].observaciones
    expect(o.map((x) => x.tipo)).toEqual(['servicio', 'hallazgo'])
    expect(o[0].autor).toBe('Ana')
    expect(o[1].texto).toBe('Sin comentario del técnico.')
  })

  it('el correo escapa lo que escribe el operador y no muestra multas', () => {
    const i = armar([row('<b>X</b>', { estado: 'cumplida', fecha_ejecucion: '2026-11-04', ejecucion_id: 'e', ejec_observacion: '"><img src=x>' })])
    i.faenas[0].observaciones[0].foto = 'javascript:alert(1)'
    const html = htmlInformeSemanal(i)
    expect(html).not.toContain('<img src=x>')
    expect(html).not.toContain('<b>X</b>')
    expect(html).not.toContain('javascript:')
    expect(html.toLowerCase()).not.toContain('multa')
    expect(asuntoInforme(i)).toContain('Semana 45')
  })
})
