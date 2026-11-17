// Informe semanal de cumplimiento a ENEX (MIG679). Todo puro, para poder probarlo.
//
// Comprometido en la semana = lo que tenía fecha en ella, incluida la tarea que
// se reprogramó a otra fecha (si no, reprogramar inflaría el cumplimiento).
// Una tarea de otra semana hecha en esta se informa, pero no entra al %.
// Las justificadas por el ADC (Consideración 1 del KPI V8) no cuentan.

import {
  avanceContrato, etiquetaTrimestre, fechaDeIso, fechaPlan, isoDe, sumarDias, trimestreContrato,
} from '@/lib/enex-avance'
import { avancePorArea } from '@/lib/enex-pauta-lugar'
import type { EnexActividadTrimestre, EnexFaena, EnexLugarItem, EnexPanelRow, EnexReprogramacion } from '@/lib/services/enex'

/** Pauta por lugar (Lomas Lubricantes): ahí el avance se mide por actividad, no por servicio. */
export type PautaLugarFaena = { items: EnexLugarItem[]; acts: EnexActividadTrimestre[] }

export type HallazgoItem = {
  ejecucion_id: string
  pauta_item_id: string
  descripcion: string | null
  observacion: string | null
  foto: string | null
}

export type FilaSemana = {
  programacion_id: string
  instalacion: string
  servicio: string
  fecha_plan: string
  fecha_ejecucion: string | null
  estado: string
  /** ok = hecha · alerta = pendiente o reprogramada · info = no entra al % */
  tono: 'ok' | 'alerta' | 'info'
  ot: string | null
}

export type ObservacionSemana = {
  id: string
  tipo: 'servicio' | 'hallazgo'
  instalacion: string
  servicio: string
  fecha: string
  autor: string | null
  item: string | null
  texto: string
  foto: string | null
}

export type ReprogAcumulada = {
  fecha_original: string
  instalacion: string
  servicio: string
  responsable: string
  causa: string | null
  nueva_fecha: string | null
  /** Hoy: ejecutada, programada para la nueva fecha, atrasada o sin fecha. */
  estado: string
  tono: 'ok' | 'alerta' | 'info'
}

export type ReprogramacionesTrimestre = {
  total: number
  porResponsable: { responsable: string; n: number }[]
  ejecutadas: number
  pendientes: number
  sinFecha: number
  lista: ReprogAcumulada[]
}

export type FaenaSemana = {
  faena_id: string
  nombre: string
  semana: { unidad: 'servicios' | 'actividades'; comprometidas: number; ejecutadas: number; firmadas: number; reprogramadas: number; pendientes: number; adicionales: number; pct: number | null; pctFirmado: number | null }
  trimestre: { etiqueta: string; universo: number | null; ejecutadas: number; cumplidas: number; programadas: number; pctAvance: number | null; pctFirmado: number | null; unidad: 'servicios' | 'actividades' }
  /** Reprogramaciones acumuladas en el trimestre del contrato, hasta el cierre de la semana. */
  reprogramaciones: ReprogramacionesTrimestre
  actividad: FilaSemana[]
  observaciones: ObservacionSemana[]
}

export type InformeSemanal = {
  semana: { desde: string; hasta: string; numero: number }
  comentario: string
  totales: { comprometidas: number; ejecutadas: number; firmadas: number; reprogramadas: number; pct: number | null; reprogTrimestre: number }
  faenas: FaenaSemana[]
}

const pct = (n: number, d: number) => (d > 0 ? Math.round((n / d) * 1000) / 10 : null)
const SERVICIO = { mantencion: 'Mantención', calibracion: 'Calibración' } as const
// Mismas etiquetas que el formulario de reprogramación (REPROG_RESPONSABLE / REPROG_CAUSA en services/enex).
export const RESPONSABLE_REPROG: Record<string, string> = {
  mandante: 'Mandante', operaciones_esm: 'Operaciones ESM', pillado: 'PILLADO', cliente: 'Cliente', otro: 'Otro',
}
export const CAUSA_REPROG: Record<string, string> = {
  equipo_no_disponible: 'Equipo/Camión no disponible', prioridad_operacional: 'Prioridad operacional',
  emergencia: 'Emergencia', falta_autorizacion: 'Falta autorización', otro: 'Otro',
}
const ORDEN_RESPONSABLE = ['Mandante', 'Cliente', 'Operaciones ESM', 'PILLADO', 'Otro', 'Sin indicar']
export const fechaCorta = (iso: string) => `${iso.slice(8, 10)}-${iso.slice(5, 7)}`

export function lunesDe(iso: string): string {
  const d = fechaDeIso(iso)
  return sumarDias(iso, -((d.getDay() + 6) % 7))
}

/** Número de semana ISO (la «semana 45» de los papeles). */
export function numeroSemana(iso: string): number {
  const jueves = fechaDeIso(sumarDias(lunesDe(iso), 3))
  const ini = new Date(jueves.getFullYear(), 0, 1)
  return Math.floor((jueves.getTime() - ini.getTime()) / 86_400_000 / 7) + 1
}

/** Meses a consultar: los de la semana y los de cualquier trimestre de contrato que la contenga. */
export function mesesNecesarios(lunes: string): { anio: number; mes: number }[] {
  const m = new Map<string, { anio: number; mes: number }>()
  for (const a of [1, 2]) for (const x of trimestreContrato(lunes, a).meses) m.set(`${x.anio}-${x.mes}`, x)
  return Array.from(m.values()).sort((a, b) => a.anio - b.anio || a.mes - b.mes)
}

const hecha = (r: EnexPanelRow) => r.cumplida || r.estado === 'ejecutada' || r.estado === 'cumplida'

export function armarInformeSemanal(p: {
  lunes: string
  hoy: string
  faenas: EnexFaena[]
  rows: EnexPanelRow[]
  reprogs: EnexReprogramacion[]
  hallazgos: HallazgoItem[]
  pautaLugar?: Record<string, PautaLugarFaena>
}): InformeSemanal {
  const desde = p.lunes, hasta = sumarDias(p.lunes, 6)
  const enSemana = (f?: string | null) => !!f && f.slice(0, 10) >= desde && f.slice(0, 10) <= hasta

  // Última reprogramación de cada tarea y las que nacieron en esta semana.
  const ultimaReprog = new Map<string, EnexReprogramacion>()
  const reprogDeSemana = new Set<string>()
  for (const r of [...p.reprogs].sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)))) {
    if (!r.programacion_id) continue
    ultimaReprog.set(r.programacion_id, r)
    if (enSemana(r.fecha_original)) reprogDeSemana.add(r.programacion_id)
  }

  const porProg = new Map(p.rows.map((r) => [r.programacion_id, r]))
  const faenas: FaenaSemana[] = []
  for (const f of p.faenas) {
    const delaFaena = p.rows.filter((r) => r.faena_id === f.id)
    const actividad: FilaSemana[] = []
    let comprometidas = 0, ejecutadas = 0, firmadas = 0, reprogramadas = 0, pendientes = 0, adicionales = 0

    for (const r of delaFaena) {
      const plan = fechaPlan(r)
      const rep = ultimaReprog.get(r.programacion_id)
      const compromiso = enSemana(r.fecha_programada) || reprogDeSemana.has(r.programacion_id)
      const adicional = !compromiso && hecha(r) && enSemana(r.fecha_ejecucion)
      if (!compromiso && !adicional) continue

      let estado: string, tono: FilaSemana['tono']
      if (r.justificada) { estado = 'Justificada por ADC'; tono = 'info' }
      else if (r.cumplida || r.estado === 'cumplida') { estado = r.firma_mandante_url ? 'Ejecutada y firmada' : 'Ejecutada, falta firma'; tono = 'ok' }
      else if (r.estado === 'ejecutada') { estado = 'Ejecutada, falta firma'; tono = 'ok' }
      else if (reprogDeSemana.has(r.programacion_id)) {
        estado = rep?.nueva_fecha ? `Reprogramada al ${fechaCorta(rep.nueva_fecha)}` : 'Reprogramada, fecha por coordinar'
        tono = 'alerta'
      } else if (r.estado === 'no_realizada') { estado = 'No realizada'; tono = 'alerta' }
      else if (plan < p.hoy) { estado = 'Pendiente'; tono = 'alerta' }
      else { estado = 'Programada'; tono = 'info' }

      if (adicional) { adicionales++; tono = 'info'; estado += ' (de otra semana)' }
      else if (!r.justificada) {
        comprometidas++
        if (hecha(r)) {
          ejecutadas++
          if (r.firma_mandante_url) firmadas++
        } else if (reprogDeSemana.has(r.programacion_id)) reprogramadas++
        else pendientes++
      }

      actividad.push({
        programacion_id: r.programacion_id,
        instalacion: r.instalacion,
        servicio: SERVICIO[r.tipo_servicio],
        // La tarea reprogramada se muestra en la fecha que tenía en esta semana.
        fecha_plan: reprogDeSemana.has(r.programacion_id) && rep?.fecha_original ? rep.fecha_original.slice(0, 10) : plan,
        fecha_ejecucion: r.fecha_ejecucion?.slice(0, 10) ?? null,
        estado, tono, ot: r.ot_numero,
      })
    }
    actividad.sort((a, b) => a.fecha_plan.localeCompare(b.fecha_plan) || a.instalacion.localeCompare(b.instalacion))

    // Observaciones de lo hecho en la semana.
    const observaciones: ObservacionSemana[] = []
    for (const r of delaFaena) {
      if (!r.ejecucion_id || !enSemana(r.fecha_ejecucion)) continue
      const base = {
        instalacion: r.instalacion, servicio: SERVICIO[r.tipo_servicio], fecha: r.fecha_ejecucion!.slice(0, 10),
        autor: r.tecnico_nombre ?? r.ejecutor ?? null,
      }
      const obs = r.ejec_observacion?.trim()
      if (obs) observaciones.push({ ...base, id: `s:${r.ejecucion_id}`, tipo: 'servicio', item: null, texto: obs, foto: null })
      for (const h of p.hallazgos) {
        if (h.ejecucion_id !== r.ejecucion_id) continue
        observaciones.push({
          ...base, id: `h:${h.ejecucion_id}:${h.pauta_item_id}`, tipo: 'hallazgo',
          item: h.descripcion, texto: h.observacion?.trim() || 'Sin comentario del técnico.', foto: h.foto,
        })
      }
    }
    observaciones.sort((a, b) => a.fecha.localeCompare(b.fecha) || a.instalacion.localeCompare(b.instalacion))

    // Avance del trimestre del contrato de esta faena.
    const ancla = f.trimestre_ancla ?? 2
    const v = trimestreContrato(desde, ancla)
    const delTri = delaFaena.filter((r) => { const x = fechaPlan(r); return x >= v.desde && x <= v.hasta })
    const a = avanceContrato(delTri as Parameters<typeof avanceContrato>[0], {
      combustible: f.contrato_inst_combustible ?? null,
      lubricante: f.contrato_inst_lubricante ?? null,
      camiones: f.contrato_camiones ?? null,
    })

    // Reprogramaciones acumuladas del trimestre del contrato, hasta el domingo de la semana.
    const lista: ReprogAcumulada[] = []
    const conteo = new Map<string, number>()
    let repEjecutadas = 0, repSinFecha = 0
    for (const r of p.reprogs) {
      const fo = r.fecha_original?.slice(0, 10)
      if (!fo || fo < v.desde || fo > hasta) continue
      const row = r.programacion_id ? porProg.get(r.programacion_id) : undefined
      if ((r.faena_id ?? row?.faena_id) !== f.id) continue
      const responsable = (r.responsable && RESPONSABLE_REPROG[r.responsable]) || 'Sin indicar'
      conteo.set(responsable, (conteo.get(responsable) ?? 0) + 1)
      const ultima = r.programacion_id ? ultimaReprog.get(r.programacion_id) : undefined
      let estado: string, tono: ReprogAcumulada['tono']
      if (row && hecha(row)) {
        estado = row.fecha_ejecucion ? `Ejecutada el ${fechaCorta(row.fecha_ejecucion.slice(0, 10))}` : 'Ejecutada'; tono = 'ok'; repEjecutadas++
      } else if (!(ultima ?? r).nueva_fecha) {
        estado = 'Sin fecha nueva'; tono = 'alerta'; repSinFecha++
      } else {
        const nueva = row ? fechaPlan(row) : (ultima ?? r).nueva_fecha!.slice(0, 10)
        estado = nueva < p.hoy ? `Atrasada (era el ${fechaCorta(nueva)})` : `Programada al ${fechaCorta(nueva)}`
        tono = nueva < p.hoy ? 'alerta' : 'info'
      }
      lista.push({
        fecha_original: fo,
        instalacion: r.instalacion ?? row?.instalacion ?? '—',
        servicio: row ? SERVICIO[row.tipo_servicio] : r.actividad === 'calibracion' ? 'Calibración' : r.actividad === 'mantencion' ? 'Mantención' : (r.actividad ?? '—'),
        responsable,
        causa: r.causa ? (CAUSA_REPROG[r.causa] ?? r.causa) : null,
        nueva_fecha: r.nueva_fecha?.slice(0, 10) ?? null,
        estado, tono,
      })
    }
    lista.sort((a, b) => a.fecha_original.localeCompare(b.fecha_original) || a.instalacion.localeCompare(b.instalacion))
    const reprogramaciones: ReprogramacionesTrimestre = {
      total: lista.length,
      porResponsable: Array.from(conteo, ([responsable, n]) => ({ responsable, n }))
        .sort((a, b) => ORDEN_RESPONSABLE.indexOf(a.responsable) - ORDEN_RESPONSABLE.indexOf(b.responsable)),
      ejecutadas: repEjecutadas,
      pendientes: lista.length - repEjecutadas,
      sinFecha: repSinFecha,
      lista,
    }

    const lugar = p.pautaLugar?.[f.id]
    // Sin plan, sin contrato y sin actividad (DES va dentro de Centinela): no se informa.
    if (actividad.length === 0 && a.universo == null && a.programadas === 0 && !lugar?.items.length) continue

    let semana: FaenaSemana['semana'] = { unidad: 'servicios', comprometidas, ejecutadas, firmadas, reprogramadas, pendientes, adicionales, pct: pct(ejecutadas, comprometidas), pctFirmado: pct(firmadas, comprometidas) }
    let trimestre: FaenaSemana['trimestre'] = { etiqueta: etiquetaTrimestre(v), universo: a.universo, ejecutadas: a.ejecutadas, cumplidas: a.cumplidas, programadas: a.programadas, pctAvance: a.pctAvance ?? pct(a.ejecutadas, a.programadas), pctFirmado: a.pctKpi, unidad: 'servicios' }

    if (lugar?.items.length) {
      const av = avancePorArea(lugar.items, lugar.acts, p.hoy).total
      trimestre = { ...trimestre, universo: av.total, ejecutadas: av.ejecutadas, pctAvance: av.pctReal, unidad: 'actividades' }
      if (comprometidas === 0) {
        const planSemana = lugar.acts.filter((x) => x.estado !== 'no_aplica' && (enSemana(x.fecha_plan) || (x.estado === 'ejecutada' && enSemana(x.fecha_ejecucion))))
        const hechas = planSemana.filter((x) => x.estado === 'ejecutada').length
        const rep = planSemana.filter((x) => x.estado === 'reprogramada').length
        semana = { unidad: 'actividades', comprometidas: planSemana.length, ejecutadas: hechas, firmadas: 0, reprogramadas: rep, pendientes: planSemana.length - hechas - rep, adicionales, pct: pct(hechas, planSemana.length), pctFirmado: null }
      }
    }

    faenas.push({ faena_id: f.id, nombre: f.nombre, semana, trimestre, reprogramaciones, actividad, observaciones })
  }

  // Las actividades de pauta no se suman con los servicios: son unidades distintas.
  const s = (k: 'comprometidas' | 'ejecutadas' | 'firmadas' | 'reprogramadas') => faenas.filter((f) => f.semana.unidad === 'servicios').reduce((t, f) => t + f.semana[k], 0)
  return {
    semana: { desde, hasta, numero: numeroSemana(desde) },
    comentario: '',
    totales: { comprometidas: s('comprometidas'), ejecutadas: s('ejecutadas'), firmadas: s('firmadas'), reprogramadas: s('reprogramadas'), pct: pct(s('ejecutadas'), s('comprometidas')), reprogTrimestre: faenas.reduce((t, f) => t + f.reprogramaciones.total, 0) },
    faenas,
  }
}

/** Lunes de la última semana ya cerrada. */
export const lunesSemanaAnterior = (hoy: string) => sumarDias(lunesDe(hoy), -7)
export const hoyIso = () => isoDe(new Date())
