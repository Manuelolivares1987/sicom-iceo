import { describe, it, expect } from 'vitest'
import { avancePorArea, columnasFecha, trimestreCalendario, moverTrimestre, etiquetaTrimestre, fechaDe } from '@/lib/enex-pauta-lugar'
import type { EnexLugarItem, EnexActividadTrimestre } from '@/lib/services/enex'

const it_ = (id: string, area: string) => ({ lugar_item_id: id, area } as EnexLugarItem)
const act = (id: string, estado: EnexActividadTrimestre['estado'], fecha_plan: string | null, fecha_ejecucion: string | null = null) =>
  ({ lugar_item_id: id, estado, fecha_plan, fecha_ejecucion } as EnexActividadTrimestre)

describe('pauta trimestral por lugar', () => {
  const items = [it_('a', 'TS1'), it_('b', 'TS1'), it_('c', 'TS1'), it_('d', 'TS1'), it_('e', 'TS1'), it_('f', 'TS2')]
  const acts = [
    act('a', 'ejecutada', null, '2026-08-11'),
    act('b', 'no_aplica', '2026-08-20'),
    act('c', 'reprogramada', '2026-09-21'),   // pasada → atrasada
    act('d', 'planificada', '2026-10-20'),    // futura
    act('f', 'ejecutada', '2026-08-01', '2026-08-05'),
  ]
  it('real y proyectado como la planilla (n/a no suma)', () => {
    const { areas, total } = avancePorArea(items, acts, '2026-10-14')
    const ts1 = areas.find((a) => a.area === 'TS1')!
    expect(ts1).toMatchObject({ total: 5, ejecutadas: 1, noAplica: 1, atrasadas: 1, planificadas: 1, sinPlan: 1, pctReal: 20, pctProyectado: 40 })
    expect(total).toMatchObject({ total: 6, ejecutadas: 2, pctReal: 33.3, pctProyectado: 50 })
  })
  it('columnas y fechas', () => {
    expect(columnasFecha(acts)).toEqual(['2026-08-05', '2026-08-11', '2026-08-20', '2026-09-21', '2026-10-20'])
    expect(fechaDe(acts[0])).toBe('2026-08-11')
  })
  it('trimestres calendario', () => {
    expect(trimestreCalendario('2026-10-14')).toBe('2026-10-01')
    expect(trimestreCalendario('2026-09-30')).toBe('2026-07-01')
    expect(moverTrimestre('2026-10-01', 1)).toBe('2027-01-01')
    expect(moverTrimestre('2026-01-01', -1)).toBe('2025-10-01')
    expect(etiquetaTrimestre('2026-07-01')).toBe('3°T 2026 · jul–sep')
  })
})
