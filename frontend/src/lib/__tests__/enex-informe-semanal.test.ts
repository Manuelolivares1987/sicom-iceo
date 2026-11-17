import { describe, expect, it } from 'vitest'
import { armarInformeSemanal, lunesDe, lunesSemanaAnterior, numeroSemana } from '@/lib/enex-informe-semanal'
import { asuntoInforme, htmlInformeSemanal, htmlParaPegar } from '@/lib/email/enex-informe-semanal'
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

  it('informa todas las faenas en %, con Lomas separada y lubricantes por actividad', () => {
    const comb = { id: 'C', nombre: 'Lomas Bayas — Combustibles', trimestre_ancla: 1, contrato_inst_combustible: 3, contrato_camiones: 4 } as EnexFaena
    const lub = { id: 'L', nombre: 'Lomas Bayas — Lubricantes', trimestre_ancla: 1 } as EnexFaena
    const des = { id: 'D', nombre: 'Nueva Centinela (DES)', trimestre_ancla: 2 } as EnexFaena
    const li = (id: string) => ({ lugar_item_id: id, area: 'TS1' }) as never
    const ac = (id: string, estado: string, fecha_plan: string | null, fecha_ejecucion: string | null = null) => ({ lugar_item_id: id, estado, fecha_plan, fecha_ejecucion }) as never
    const i = armarInformeSemanal({
      lunes: '2026-11-02', hoy: '2026-11-09', faenas: [faena, comb, lub, des], reprogs: [], hallazgos: [],
      rows: [row('A', { estado: 'cumplida', fecha_ejecucion: '2026-11-04', firma_mandante_url: 'x' }), row('O', { faena_id: 'C', fecha_programada: '2026-10-28', periodo_mes: 10, estado: 'cumplida', fecha_ejecucion: '2026-10-28', firma_mandante_url: 'x' })],
      pautaLugar: { L: { items: [li('a'), li('b'), li('c'), li('d')], acts: [ac('a', 'ejecutada', '2026-11-03', '2026-11-03'), ac('b', 'planificada', '2026-11-05')] } },
    })
    expect(i.faenas.map((f) => f.nombre)).toEqual(['Centinela', 'Lomas Bayas — Combustibles', 'Lomas Bayas — Lubricantes'])
    const c = i.faenas[1], l = i.faenas[2]
    expect(c.semana.comprometidas).toBe(0)
    expect(c.trimestre.pctAvance).toBe(10)
    expect(l.semana).toMatchObject({ unidad: 'actividades', comprometidas: 2, ejecutadas: 1, pct: 50 })
    expect(l.trimestre).toMatchObject({ unidad: 'actividades', universo: 4, pctAvance: 25 })
    expect(i.totales.comprometidas).toBe(1)
    const html = htmlInformeSemanal(i)
    expect(html).toContain('Cumplimiento por faena')
    expect(html).toContain('Lomas Bayas — Lubricantes')
    expect(html).toContain('Sin trabajos')
  })

  it('acumula las reprogramaciones del trimestre hasta el cierre de la semana', () => {
    // Semana 46 (09-11): trimestre Nov-Ene de Centinela.
    const i = armarInformeSemanal({
      lunes: '2026-11-09', hoy: '2026-11-16', faenas: [faena], hallazgos: [],
      rows: [
        row('R1', { fecha_programada: '2026-12-07', periodo_mes: 12 }),
        row('R2', { fecha_programada: '2026-11-05', estado: 'cumplida', cumplida: true, fecha_ejecucion: '2026-11-05' }),
        row('R3', { fecha_programada: '2026-11-04' }),
        row('R4', { fecha_programada: '2026-12-02', periodo_mes: 12 }),
      ],
      reprogs: [
        rep({ id: '1', programacion_id: 'R1', fecha_original: '2026-11-06', nueva_fecha: '2026-12-07', responsable: 'operaciones_esm', causa: 'prioridad_operacional' }),
        rep({ id: '2', programacion_id: 'R2', fecha_original: '2026-11-04', nueva_fecha: '2026-11-05', responsable: 'mandante' }),
        rep({ id: '3', programacion_id: 'R3', fecha_original: '2026-11-04', nueva_fecha: null, responsable: null }),
        rep({ id: '4', programacion_id: 'R4', fecha_original: '2026-11-11', nueva_fecha: '2026-12-02', responsable: 'operaciones_esm' }),
        // De otro trimestre y posterior a la semana: no cuentan.
        rep({ id: '5', programacion_id: 'R4', fecha_original: '2026-10-20', nueva_fecha: '2026-11-11', responsable: 'pillado', created_at: '2026-10-20' }),
        rep({ id: '6', programacion_id: 'R1', fecha_original: '2026-11-18', nueva_fecha: '2026-12-07', responsable: 'pillado', created_at: '2026-11-17' }),
      ],
    })
    const r = i.faenas[0].reprogramaciones
    expect(r).toMatchObject({ total: 4, ejecutadas: 1, pendientes: 3, sinFecha: 1 })
    expect(r.porResponsable).toEqual([
      { responsable: 'Mandante', n: 1 }, { responsable: 'Operaciones ESM', n: 2 }, { responsable: 'Sin indicar', n: 1 },
    ])
    expect(r.lista.map((x) => x.estado)).toEqual(['Ejecutada el 05-11', 'Sin fecha nueva', 'Programada al 07-12', 'Programada al 02-12'])
    expect(i.totales.reprogTrimestre).toBe(4)
    expect(htmlInformeSemanal(i)).toContain('Reprogramaciones acumuladas del trimestre')
    expect(htmlParaPegar(i)).toContain('3. Reprogramaciones acumuladas del trimestre')
  })

  it('separa el cambio de tarea (se trabajó en otra cosa) de la reprogramación (no se pudo trabajar)', () => {
    const i = armarInformeSemanal({
      lunes: '2026-10-26', hoy: '2026-11-16', faenas: [faena], hallazgos: [],
      rows: [row('V', { fecha_programada: '2026-12-01', periodo_mes: 12 }), row('X', { fecha_programada: '2026-12-02', periodo_mes: 12 })],
      reprogs: [
        rep({ id: 'cambio:1', programacion_id: 'V', fecha_original: '2026-10-26', nueva_fecha: '2026-12-01', responsable: 'operaciones_esm',
          causa: 'Cambio de tarea pedido por ESM', descripcion: 'ESM pidió calibrar SKOL-82 en lugar de la EESS', origen: 'cambio_tarea' }),
        rep({ id: '2', programacion_id: 'X', fecha_original: '2026-10-27', nueva_fecha: '2026-12-02', responsable: 'mandante' }),
      ],
    })
    // Centinela: el trimestre de octubre es Ago-Oct (ancla 2).
    const r = i.faenas[0].reprogramaciones
    expect(r).toMatchObject({ total: 2, sinTrabajo: 1, cambiosTarea: 1 })
    expect(r.lista.map((x) => x.tipo)).toEqual(['Cambio de tarea', 'Reprogramación'])
    expect(r.lista[0].detalle).toContain('SKOL-82')
    expect(i.faenas[0].actividad.find((a) => a.programacion_id === 'V')!.estado).toBe('Cambio de tarea pedido por ESM, pasa al 01-12')
    const pegar = htmlParaPegar(i)
    expect(pegar).toContain('No se pudo trabajar')
    expect(pegar).toContain('«Cambio de tarea»: el equipo fue a faena')
    // Ejecutivo: solo el resumen por faena, sin la tabla de detalle de cada reprogramación.
    expect(pegar).not.toContain('Fecha original')
    expect(htmlInformeSemanal(i)).not.toContain('Fecha original')
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
    const pegar = htmlParaPegar(i)
    expect(pegar).toContain('Cumplimiento por faena')
    expect(pegar).toContain('Observaciones de los operadores')
    expect(pegar).not.toContain('<img src=x>')
    expect(pegar.toLowerCase()).not.toContain('multa')
  })
})
