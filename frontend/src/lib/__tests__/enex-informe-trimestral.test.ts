import { describe, it, expect } from 'vitest'
import { armarInformeTrimestral } from '@/lib/enex-informe-trimestral'
import type { EnexPanelRow, EnexItemEjecutado, EnexPautaItem, EnexRequerimiento } from '@/lib/services/enex'

const row = (id: string, inst: string, mes: number, estado: EnexPanelRow['estado'], ejec: string | null, pdf = false) => ({
  programacion_id: id, periodo_anio: 2026, periodo_mes: mes, tipo_servicio: 'mantencion', fecha_programada: `2026-0${mes}-10`,
  instalacion_id: inst, instalacion: `Punto ${inst}`, instalacion_tipo: 'truck_shop', faena_id: 'f', faena: 'LB', faena_codigo: 'LB_LUB',
  ejecucion_id: ejec, estado, fecha_ejecucion: ejec ? `2026-0${mes}-11` : null, cumplida: estado === 'cumplida',
  informe_pdf_url: pdf ? `https://x/${id}.pdf` : null, tecnico_nombre: 'R. Cáceres', ejecutor: null,
} as unknown as EnexPanelRow)
const item = (eid: string, pid: string, resultado: string | null, obs: string | null = null) =>
  ({ ejecucion_id: eid, pauta_item_id: pid, item_codigo: pid, descripcion: `Act ${pid}`, resultado, observacion: obs, valor_medicion: null, dentro_tolerancia: null } as EnexItemEjecutado)
const pi = (id: string, periodicidad = 'trimestral') => ({ id, pauta_id: 'P', codigo: id, descripcion: `Act ${id}`, periodicidad, activo: true } as EnexPautaItem)

describe('informe trimestral', () => {
  const inf = armarInformeTrimestral({
    rows: [row('a', '1', 7, 'cumplida', 'e1', true), row('b', '2', 8, 'ejecutada', 'e2', true), row('c', '2', 9, null, null)],
    meses: [{ anio: 2026, mes: 7 }, { anio: 2026, mes: 8 }, { anio: 2026, mes: 9 }],
    items: [item('e1', '1.1', 'ok'), item('e1', '1.2', 'no_ok', 'fuga'), item('e2', '1.1', 'ok'), item('e2', '1.3', 'na')],
    reqs: [{ ejecucion_id: 'e2', tipo: 'requerimiento', prioridad: 'alta' } as EnexRequerimiento],
    reprogs: [],
    metas: [{ id: 'e1', pauta_id: 'P', duracion_segundos: 3600 }, { id: 'e2', pauta_id: 'P', duracion_segundos: 5400 }],
    pautaItems: [pi('1.1'), pi('1.2'), pi('1.3'), pi('1.4'), pi('9.9', 'requerimiento')],
  })
  it('resumen', () => {
    expect(inf.resumen).toMatchObject({ programados: 3, ejecutados: 2, cumplidos: 1, sinFirma: 1, pendientes: 1, informesPdf: 2, horasTerreno: 2.5, actividades: 3, hallazgos: 1, requerimientos: 1, requerimientosAlta: 1 })
    expect(inf.resumen.pctCumplimiento).toBe(33.3)
    expect(inf.resumen.tramo.revision).toBe(true)
  })
  it('cobertura descuenta no aplica y deja pendientes', () => {
    expect(inf.cobertura[0]).toMatchObject({ trimestrales: 4, hechas: 2, noAplica: 1, pct: 66.7 })
    expect(inf.cobertura[0].pendientes.map((p) => p.codigo)).toEqual(['1.4'])
  })
  it('por punto y hallazgos', () => {
    const p2 = inf.puntos.find((p) => p.instalacion_id === '2')!
    expect(p2).toMatchObject({ programados: 2, ejecutados: 1, cumplidos: 0, requerimientos: 1 })
    expect(inf.hallazgos).toHaveLength(1)
    expect(inf.hallazgos[0]).toMatchObject({ instalacion: 'Punto 1', observacion: 'fuga' })
    expect(inf.porMes.map((m) => m.pct)).toEqual([100, 0, 0])
    expect(inf.conclusion).toContain('subiría a 66,7 %')
  })
})
