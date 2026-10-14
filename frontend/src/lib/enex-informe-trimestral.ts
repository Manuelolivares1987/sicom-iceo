// Informe trimestral ENEX — consolida los informes de servicio del período
// (MIG590). Pedido para Lomas Bayas Lubricantes, sirve para cualquier faena.
// Puro: recibe lo leído de la BD y arma las secciones del informe.

import type {
  EnexPanelRow, EnexItemEjecutado, EnexRequerimiento, EnexReprogramacion, EnexPautaItem, EnexEjecucionMeta,
  EnexLugarItem, EnexActividadTrimestre,
} from '@/lib/services/enex'
import { tramoMulta } from '@/lib/enex-avance'
import { avancePorArea, type AvanceArea } from '@/lib/enex-pauta-lugar'

/** Pauta por lugar (MIG591): avance por actividad como la planilla de Lomas. */
export type PautaLugarInforme = {
  areas: AvanceArea[]
  total: AvanceArea
  sinInforme: { area: string; lugar: string; codigo: string; descripcion: string; fecha: string | null }[]
  faltantes: { area: string; lugar: string; codigo: string; descripcion: string; estado: string; fecha: string | null }[]
}

export type PuntoInforme = {
  instalacion_id: string
  instalacion: string
  area: string | null
  programados: number
  ejecutados: number
  cumplidos: number
  fechas: string[]
  tecnicos: string[]
  actividades: number
  hallazgos: number
  requerimientos: number
  informes: { fecha: string | null; url: string; tipo: string }[]
}

export type Hallazgo = {
  fecha: string | null
  instalacion: string
  codigo: string | null
  descripcion: string | null
  observacion: string | null
  medicion: string | null
}

export type CoberturaPauta = {
  pauta_id: string
  trimestrales: number
  hechas: number
  noAplica: number
  pct: number | null
  pendientes: { codigo: string | null; descripcion: string }[]
}

export type InformeTrimestral = {
  resumen: {
    programados: number
    ejecutados: number
    cumplidos: number
    sinFirma: number
    pendientes: number
    pctCumplimiento: number | null
    pctEjecucion: number | null
    tramo: ReturnType<typeof tramoMulta>
    informesPdf: number
    horasTerreno: number
    actividades: number
    hallazgos: number
    requerimientos: number
    requerimientosAlta: number
    reprogramaciones: number
  }
  porMes: { anio: number; mes: number; programados: number; cumplidos: number; ejecutados: number; pct: number | null }[]
  puntos: PuntoInforme[]
  hallazgos: Hallazgo[]
  requerimientos: (EnexRequerimiento & { instalacion: string; fecha: string | null })[]
  cobertura: CoberturaPauta[]
  reprogramaciones: EnexReprogramacion[]
  pautaLugar: PautaLugarInforme | null
  conclusion: string
}

const pct = (n: number, d: number) => (d > 0 ? Math.round((n / d) * 1000) / 10 : null)
// Los campos de texto del formulario (motivo, horas, RUT, fotos) son datos del
// informe, no actividades de mantenimiento: no cuentan ni en actividades ni en cobertura.
// Se reconocen por el tipo (texto) o por el prefijo del código (DS.MOTIVO, FOT.1).
const esActividad = (tipoCampo: string | null | undefined, codigo: string | null | undefined) =>
  tipoCampo !== 'texto' && !/^[a-z]+\./i.test(codigo ?? '')
// Hecha = con resultado (OK / NO OK) o medición; «na» (no aplica) no cuenta.
const hecho = (i: EnexItemEjecutado) => esActividad(i.tipo_campo, i.item_codigo) && (i.valor_medicion != null || (i.resultado != null && i.resultado !== 'na'))
const esHallazgo = (i: EnexItemEjecutado) => i.resultado === 'no_ok' || i.dentro_tolerancia === false

export function armarInformeTrimestral(p: {
  rows: EnexPanelRow[]
  meses: { anio: number; mes: number }[]
  items: EnexItemEjecutado[]
  reqs: EnexRequerimiento[]
  reprogs: EnexReprogramacion[]
  metas: EnexEjecucionMeta[]
  pautaItems: EnexPautaItem[]
  areaDe?: (instalacionId: string) => string | null
  lugarItems?: EnexLugarItem[]
  actividades?: EnexActividadTrimestre[]
  hoy?: string
}): InformeTrimestral {
  const { rows, meses, items, reqs, reprogs, metas, pautaItems } = p
  const ejec = rows.filter((r) => r.ejecucion_id && r.estado !== 'no_realizada')
  const cumplidos = rows.filter((r) => r.cumplida).length
  const porEjec = new Map(rows.filter((r) => r.ejecucion_id).map((r) => [r.ejecucion_id!, r]))
  const itemsDe = (eid: string) => items.filter((i) => i.ejecucion_id === eid)

  // Por punto
  const puntosMap = new Map<string, PuntoInforme>()
  for (const r of rows) {
    const pt = puntosMap.get(r.instalacion_id) ?? {
      instalacion_id: r.instalacion_id, instalacion: r.instalacion, area: p.areaDe?.(r.instalacion_id) ?? null,
      programados: 0, ejecutados: 0, cumplidos: 0, fechas: [], tecnicos: [], actividades: 0, hallazgos: 0, requerimientos: 0, informes: [],
    }
    pt.programados++
    if (r.ejecucion_id && r.estado !== 'no_realizada') {
      pt.ejecutados++
      if (r.fecha_ejecucion) pt.fechas.push(r.fecha_ejecucion)
      // "Roberto Cáceres García / 13356767-4" y "Roberto Cáceres García" son la misma persona.
      const tec = (r.tecnico_nombre ?? r.ejecutor ?? '').replace(/\s*[/·-]?\s*\d{1,2}\.?\d{3}\.?\d{3}-[\dkK]\s*$/, '').trim()
      if (tec && !pt.tecnicos.includes(tec)) pt.tecnicos.push(tec)
      const its = itemsDe(r.ejecucion_id)
      pt.actividades += its.filter(hecho).length
      pt.hallazgos += its.filter(esHallazgo).length
      pt.requerimientos += reqs.filter((q) => q.ejecucion_id === r.ejecucion_id).length
      if (r.informe_pdf_url) pt.informes.push({ fecha: r.fecha_ejecucion, url: r.informe_pdf_url, tipo: r.tipo_servicio })
    }
    if (r.cumplida) pt.cumplidos++
    puntosMap.set(r.instalacion_id, pt)
  }
  const puntos = Array.from(puntosMap.values()).map((x) => ({ ...x, fechas: x.fechas.sort() }))
    .sort((a, b) => (a.area ?? '').localeCompare(b.area ?? '') || a.instalacion.localeCompare(b.instalacion))

  // Hallazgos (actividades NO OK o fuera de tolerancia)
  const hallazgos: Hallazgo[] = items.filter(esHallazgo).map((i) => {
    const r = porEjec.get(i.ejecucion_id)
    return {
      fecha: r?.fecha_ejecucion ?? null, instalacion: r?.instalacion ?? '—', codigo: i.item_codigo, descripcion: i.descripcion,
      observacion: i.observacion, medicion: i.valor_medicion != null ? String(i.valor_medicion) : null,
    }
  }).sort((a, b) => (a.fecha ?? '').localeCompare(b.fecha ?? '') || a.instalacion.localeCompare(b.instalacion))

  const requerimientos = reqs.map((q) => {
    const r = porEjec.get(q.ejecucion_id)
    return { ...q, instalacion: r?.instalacion ?? '—', fecha: r?.fecha_ejecucion ?? null }
  })

  // Cobertura de pauta: actividades trimestrales hechas al menos una vez en el período.
  const pautaDeEjec = new Map(metas.map((m) => [m.id, m.pauta_id]))
  const pautas = Array.from(new Set(metas.map((m) => m.pauta_id).filter(Boolean))) as string[]
  const cobertura: CoberturaPauta[] = pautas.map((pid) => {
    const trim = pautaItems.filter((i) => i.pauta_id === pid && i.activo && i.periodicidad === 'trimestral' && esActividad(i.tipo_campo, i.codigo))
    const its = items.filter((i) => pautaDeEjec.get(i.ejecucion_id) === pid)
    const hechos = new Set(its.filter(hecho).map((i) => i.pauta_item_id))
    const na = new Set(its.filter((i) => i.resultado === 'na').map((i) => i.pauta_item_id))
    const hechas = trim.filter((i) => hechos.has(i.id)).length
    const noAplica = trim.filter((i) => !hechos.has(i.id) && na.has(i.id)).length
    return {
      pauta_id: pid, trimestrales: trim.length, hechas, noAplica,
      pct: pct(hechas, trim.length - noAplica),
      pendientes: trim.filter((i) => !hechos.has(i.id) && !na.has(i.id)).map((i) => ({ codigo: i.codigo, descripcion: i.descripcion })),
    }
  })

  const porMes = meses.map((m) => {
    const rm = rows.filter((r) => r.periodo_anio === m.anio && r.periodo_mes === m.mes)
    const c = rm.filter((r) => r.cumplida).length
    return { ...m, programados: rm.length, cumplidos: c, ejecutados: rm.filter((r) => r.ejecucion_id && r.estado !== 'no_realizada').length, pct: pct(c, rm.length) }
  })

  const pctCumplimiento = pct(cumplidos, rows.length)
  const tramo = tramoMulta(pctCumplimiento)
  const horasTerreno = Math.round(metas.reduce((s, m) => s + (m.duracion_segundos ?? 0), 0) / 360) / 10
  const actividades = items.filter(hecho).length
  const resumen = {
    programados: rows.length,
    ejecutados: ejec.length,
    cumplidos,
    sinFirma: ejec.length - cumplidos,
    pendientes: rows.length - ejec.length,
    pctCumplimiento,
    pctEjecucion: pct(ejec.length, rows.length),
    tramo,
    informesPdf: rows.filter((r) => r.informe_pdf_url).length,
    horasTerreno,
    actividades,
    hallazgos: hallazgos.length,
    requerimientos: reqs.filter((q) => q.tipo === 'requerimiento').length,
    requerimientosAlta: reqs.filter((q) => q.tipo === 'requerimiento' && q.prioridad === 'alta').length,
    reprogramaciones: reprogs.length,
  }

  let pautaLugar: PautaLugarInforme | null = null
  if (p.lugarItems && p.lugarItems.length > 0) {
    const acts = p.actividades ?? []
    const porItem = new Map(acts.map((a) => [a.lugar_item_id, a]))
    const { areas, total } = avancePorArea(p.lugarItems, acts, p.hoy ?? '9999-12-31')
    pautaLugar = {
      areas, total,
      // Ejecutada según la planilla o a mano, pero sin informe de terreno que la respalde.
      sinInforme: p.lugarItems.filter((i) => { const a = porItem.get(i.lugar_item_id); return a?.estado === 'ejecutada' && !a.ejecucion_id })
        .map((i) => ({ area: i.area, lugar: i.lugar, codigo: i.codigo, descripcion: i.descripcion, fecha: porItem.get(i.lugar_item_id)?.fecha_ejecucion ?? null })),
      faltantes: p.lugarItems.filter((i) => { const e = porItem.get(i.lugar_item_id)?.estado ?? 'pendiente'; return e !== 'ejecutada' && e !== 'no_aplica' })
        .map((i) => { const a = porItem.get(i.lugar_item_id); return { area: i.area, lugar: i.lugar, codigo: i.codigo, descripcion: i.descripcion, estado: a?.estado ?? 'pendiente', fecha: a?.fecha_plan ?? null } }),
    }
  }

  return { resumen, porMes, puntos, hallazgos, requerimientos, cobertura, reprogramaciones: reprogs, pautaLugar, conclusion: conclusionAuto(resumen, cobertura, pautaLugar) }
}

const n1 = (x: number | null) => (x == null ? '—' : `${x.toLocaleString('es-CL', { maximumFractionDigits: 1 })} %`)

function conclusionAuto(r: InformeTrimestral['resumen'], cob: CoberturaPauta[], pl: PautaLugarInforme | null): string {
  const partes: string[] = []
  partes.push(`En el período se programaron ${r.programados} servicios y se ejecutaron ${r.ejecutados} (${n1(r.pctEjecucion)}).`)
  partes.push(`${r.cumplidos} ${r.cumplidos === 1 ? 'cuenta' : 'cuentan'} con firma del mandante: cumplimiento contractual ${n1(r.pctCumplimiento)}${r.programados ? ` (${r.tramo.etiqueta.toLowerCase()})` : ''}.`)
  if (r.sinFirma > 0) partes.push(`${r.sinFirma} servicio${r.sinFirma === 1 ? '' : 's'} ejecutado${r.sinFirma === 1 ? '' : 's'} aún sin firma del mandante: al firmarse el cumplimiento subiría a ${n1(r.programados ? Math.round(((r.cumplidos + r.sinFirma) / r.programados) * 1000) / 10 : null)}.`)
  if (r.pendientes > 0) partes.push(`${r.pendientes} servicio${r.pendientes === 1 ? ' quedó' : 's quedaron'} sin ejecutar.`)
  if (pl) {
    partes.push(`Avance de la pauta trimestral por lugar: ${pl.areas.map((a) => `${a.area} ${a.ejecutadas}/${a.total} (${n1(a.pctReal)})`).join(', ')}; total ${n1(pl.total.pctReal)}, proyectado ${n1(pl.total.pctProyectado)}.`)
    if (pl.sinInforme.length) partes.push(`${pl.sinInforme.length} actividad${pl.sinInforme.length === 1 ? '' : 'es'} ejecutada${pl.sinInforme.length === 1 ? '' : 's'} según planilla no tiene${pl.sinInforme.length === 1 ? '' : 'n'} informe de terreno en SICOM que la${pl.sinInforme.length === 1 ? '' : 's'} respalde.`)
  }
  for (const c of pl ? [] : cob) {
    if (c.trimestrales > 0) partes.push(`Cobertura de la pauta trimestral: ${c.hechas} de ${c.trimestrales - c.noAplica} actividades aplicables (${n1(c.pct)})${c.pendientes.length ? `; ${c.pendientes.length} sin registro en el período` : ''}.`)
  }
  partes.push(`Se registraron ${r.actividades} actividades, ${r.hallazgos} hallazgo${r.hallazgos === 1 ? '' : 's'} (NO OK o fuera de tolerancia) y ${r.requerimientos} requerimiento${r.requerimientos === 1 ? '' : 's'}${r.requerimientosAlta ? ` (${r.requerimientosAlta} de prioridad alta)` : ''}.`)
  if (r.reprogramaciones > 0) partes.push(`Hubo ${r.reprogramaciones} reprogramación${r.reprogramaciones === 1 ? '' : 'es'} con registro firmado.`)
  return partes.join(' ')
}
