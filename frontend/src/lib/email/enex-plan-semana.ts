// Correo a ESM con el plan de la semana de una faena: resumen por día y el
// detalle de actividades. Sale como archivo .eml que Outlook (escritorio) abre
// como mensaje nuevo, listo para revisar y enviar. También se puede copiar.

import { fechaDeIso, sumarDias } from '@/lib/enex-avance'
import { numeroSemana } from '@/lib/enex-informe-semanal'
import type { EnexPanelRow, EnexPlanTarea } from '@/lib/services/enex'

const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))

const DIAS = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado']
const ddmm = (iso: string) => `${iso.slice(8, 10)}-${iso.slice(5, 7)}`
const diaTxt = (iso: string) => `${DIAS[fechaDeIso(iso).getDay()]} ${ddmm(iso)}`
/** «1. Housekeeping de instalaciones» → «Housekeeping de instalaciones». */
const sinNumero = (s: string) => s.replace(/^\s*\d+(\.\d+)*\.?\s*/, '')
const ordenCodigo = (a: string, b: string) => a.localeCompare(b, 'es', { numeric: true })

export type ActividadPlan = { codigo: string; actividad: string; instalaciones: string[] }
export type BloquePlan = { bloque: string; actividades: ActividadPlan[] }
export type GrupoPlan = {
  lugar: string
  instalaciones: string[]
  /** true si todas las actividades se hacen en todas las instalaciones del grupo. */
  mismasEnCada: boolean
  bloques: BloquePlan[]
  nActividades: number
}
export type ServicioPlan = { instalacion: string; servicio: string }
export type DiaPlan = { fecha: string; grupos: GrupoPlan[]; servicios: ServicioPlan[] }
export type PlanSemanaCorreo = {
  faena: string
  lunes: string
  domingo: string
  numero: number
  dias: DiaPlan[]
  /** Rangos de días sin nada, p. ej. ['2026-11-26', '2026-11-29']. */
  libres: [string, string][]
  jornadas: number
}

const nombreProg = (r: EnexPanelRow) =>
  r.es_comodin ? 'Camión por asignar' : r.instalacion_tipo === 'camion' ? `Camión ${r.patente ?? r.instalacion}` : r.instalacion

/**
 * Arma el plan de la semana. Las tareas del plan semanal (pauta por lugar) van
 * con su detalle de actividades; las programaciones de la Gantt que el plan no
 * detalla salen como servicio (mantención / calibración) de la instalación.
 */
export function armarPlanSemana(p: {
  faena: string; lunes: string; tareas: EnexPlanTarea[]; programaciones: EnexPanelRow[]
}): PlanSemanaCorreo {
  const domingo = sumarDias(p.lunes, 6)
  const enSemana = (f: string | null | undefined) => !!f && f.slice(0, 10) >= p.lunes && f.slice(0, 10) <= domingo
  const tareas = p.tareas.filter((t) => enSemana(t.fecha) && (t.actividad || t.codigo_item))
  const cubiertas = new Set(tareas.map((t) => `${t.instalacion_id}|${t.fecha.slice(0, 10)}`))
  const progs = p.programaciones.filter((r) => enSemana(r.fecha_programada)
    && !cubiertas.has(`${r.instalacion_id}|${r.fecha_programada!.slice(0, 10)}`))

  const dias: DiaPlan[] = []
  const libres: [string, string][] = []
  for (let i = 0; i < 7; i++) {
    const f = sumarDias(p.lunes, i)
    const delDia = tareas.filter((t) => t.fecha.slice(0, 10) === f)
    const porLugar = new Map<string, EnexPlanTarea[]>()
    for (const t of delDia) {
      const k = t.alcance || t.area || t.instalacion || 'Sin lugar'
      porLugar.set(k, [...(porLugar.get(k) ?? []), t])
    }
    const grupos: GrupoPlan[] = Array.from(porLugar.entries())
      .sort((a, b) => Math.min(...a[1].map((t) => t.orden)) - Math.min(...b[1].map((t) => t.orden)))
      .map(([lugar, ts]) => {
        const instalaciones = Array.from(new Set(ts.map((t) => t.instalacion ?? '').filter(Boolean))).sort(ordenCodigo)
        const porBloque = new Map<string, { orden: number; acts: Map<string, ActividadPlan & { orden: number }> }>()
        for (const t of ts) {
          const b = sinNumero(t.bloque ?? '') || 'Actividades'
          const blo = porBloque.get(b) ?? { orden: t.bloque_orden ?? t.orden, acts: new Map() }
          blo.orden = Math.min(blo.orden, t.bloque_orden ?? t.orden)
          const k = `${t.codigo_item ?? ''}|${t.actividad ?? ''}`
          const a = blo.acts.get(k) ?? { codigo: t.codigo_item ?? '', actividad: t.actividad ?? '', instalaciones: [], orden: t.orden }
          a.orden = Math.min(a.orden, t.orden)
          if (t.instalacion && !a.instalaciones.includes(t.instalacion)) a.instalaciones.push(t.instalacion)
          blo.acts.set(k, a)
          porBloque.set(b, blo)
        }
        const bloques: BloquePlan[] = Array.from(porBloque.entries())
          .sort((a, b) => a[1].orden - b[1].orden)
          .map(([bloque, { acts }]) => ({
            bloque,
            actividades: Array.from(acts.values()).sort((a, b) => a.orden - b.orden)
              .map(({ codigo, actividad, instalaciones: ins }) => ({ codigo, actividad, instalaciones: ins.sort(ordenCodigo) })),
          }))
        const todas = bloques.flatMap((b) => b.actividades)
        return {
          lugar, instalaciones, bloques, nActividades: todas.length,
          mismasEnCada: todas.every((a) => a.instalaciones.length === instalaciones.length),
        }
      })
    const servicios = progs.filter((r) => r.fecha_programada!.slice(0, 10) === f)
      .map((r) => ({ instalacion: nombreProg(r), servicio: r.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención' }))
      .sort((a, b) => a.instalacion.localeCompare(b.instalacion, 'es', { numeric: true }) || a.servicio.localeCompare(b.servicio))
    if (grupos.length === 0 && servicios.length === 0) {
      const ult = libres[libres.length - 1]
      if (ult && ult[1] === sumarDias(f, -1)) ult[1] = f
      else libres.push([f, f])
    } else dias.push({ fecha: f, grupos, servicios })
  }
  return { faena: p.faena, lunes: p.lunes, domingo, numero: numeroSemana(p.lunes), dias, libres, jornadas: dias.length }
}

export const asuntoPlanSemana = (p: PlanSemanaCorreo) =>
  `ESM PILLADO // Plan semanal ${p.faena} · Semana ${p.numero} (${ddmm(p.lunes)} al ${ddmm(p.domingo)})`

const nombreCorto = (instalacion: string, todas: string[]) => {
  // «Truck Shop Lomas 2 - Rack 1» → «Rack 1» cuando todas comparten el prefijo.
  const pre = instalacion.includes(' - ') ? instalacion.slice(0, instalacion.lastIndexOf(' - ') + 3) : ''
  return pre && todas.every((x) => x.startsWith(pre)) ? instalacion.slice(pre.length) : instalacion
}
const listaY = (xs: string[]) => (xs.length <= 1 ? xs.join('') : `${xs.slice(0, -1).join(', ')} y ${xs[xs.length - 1]}`)
const instalacionesTxt = (g: GrupoPlan) => {
  if (g.instalaciones.length <= 1) return g.instalaciones[0] ?? ''
  const pre = g.instalaciones[0].includes(' - ') ? g.instalaciones[0].slice(0, g.instalaciones[0].lastIndexOf(' - ')) : ''
  const cortos = g.instalaciones.map((i) => nombreCorto(i, g.instalaciones))
  return pre && cortos[0] !== g.instalaciones[0] ? `${pre} – ${listaY(cortos)}` : listaY(g.instalaciones)
}
const sitio = (g: GrupoPlan) => {
  // «Truck Shop Lomas 2» común a las instalaciones del grupo.
  const p = g.instalaciones.map((i) => (i.includes(' - ') ? i.slice(0, i.indexOf(' - ')) : i))
  return p.length > 0 && p.every((x) => x === p[0]) ? p[0] : ''
}

/** HTML para Outlook: tablas con borde y fuente Calibri, sin firma (la pone quien envía). */
export function htmlPlanSemana(p: PlanSemanaCorreo, firma?: string | null): string {
  const F = 'font-family:Calibri,Arial,sans-serif;font-size:11pt;color:#1f2937'
  const VERDE = '#1E5929'
  const par = (s: string) => `<p style="${F};margin:0 0 10px 0">${s}</p>`
  const filasResumen: string[][] = []
  for (const d of p.dias) {
    for (const g of d.grupos) {
      const n = g.instalaciones.length > 1 && g.mismasEnCada ? `${g.nActividades} (en cada una)` : String(g.nActividades)
      filasResumen.push([diaTxt(d.fecha), esc(g.lugar), esc(instalacionesTxt(g)), n])
    }
    for (const s of d.servicios) filasResumen.push([diaTxt(d.fecha), '—', esc(s.instalacion), esc(s.servicio)])
  }
  for (const [a, b] of p.libres) {
    filasResumen.push([a === b ? diaTxt(a) : `${diaTxt(a)} al ${diaTxt(b)}`, '—', 'Sin actividades programadas', '—'])
  }
  filasResumen.sort((a, b) => ordenDia(a[0], p) - ordenDia(b[0], p))
  const tabla = `
<table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;border-color:#c9d6cc;${F}">
  <tr>${['Día', 'Lugar', 'Instalación', 'Actividades / servicio'].map((c) => `<th align="left" bgcolor="${VERDE}" style="${F};color:#ffffff">${c}</th>`).join('')}</tr>
  ${filasResumen.map((f) => `<tr>${f.map((c) => `<td valign="top" style="${F}">${c}</td>`).join('')}</tr>`).join('\n  ')}
</table>`

  const detalle: string[] = []
  for (const d of p.dias) {
    for (const g of d.grupos) {
      const s = sitio(g)
      detalle.push(par(`<b>${esc(diaTxt(d.fecha).toUpperCase())} · ${s ? `${esc(s)} · ` : ''}${esc(g.lugar)}</b>`))
      if (g.instalaciones.length > 1 && g.mismasEnCada) {
        detalle.push(par(`<i>Las mismas actividades en cada una: ${esc(listaY(g.instalaciones.map((i) => nombreCorto(i, g.instalaciones))))}.</i>`))
      }
      for (const b of g.bloques) {
        detalle.push(`<p style="${F};margin:6px 0 2px 0"><i>${esc(b.bloque)}</i></p>`)
        detalle.push(`<ul style="${F};margin-top:0">${b.actividades.map((a) => {
          const donde = g.instalaciones.length > 1 && !g.mismasEnCada
            ? ` <span style="color:#6b7280">(${esc(listaY(a.instalaciones.map((i) => nombreCorto(i, g.instalaciones))))})</span>` : ''
          return `<li>${esc([a.codigo, a.actividad].filter(Boolean).join(' '))}${donde}</li>`
        }).join('')}</ul>`)
      }
    }
    if (d.servicios.length > 0) {
      detalle.push(par(`<b>${esc(diaTxt(d.fecha).toUpperCase())} · Servicios programados</b>`))
      detalle.push(`<ul style="${F};margin-top:0">${d.servicios.map((s) => `<li>${esc(s.instalacion)}: ${esc(s.servicio)}</li>`).join('')}</ul>`)
    }
  }

  const rango = `${Number(p.lunes.slice(8, 10))} al ${Number(p.domingo.slice(8, 10))} de ${fechaDeIso(p.domingo).toLocaleDateString('es-CL', { month: 'long' })} de ${p.domingo.slice(0, 4)}`
  const intro = p.jornadas === 0
    ? `Junto con saludar, informamos que para la <b>semana ${p.numero} (${rango})</b> no hay actividades programadas en <b>${esc(p.faena)}</b>.`
    : `Junto con saludar, enviamos la planificación de la <b>semana ${p.numero} (${rango})</b> para <b>${esc(p.faena)}</b>. El plan contempla ${p.jornadas} ${p.jornadas === 1 ? 'jornada' : 'jornadas'} de trabajo.`

  return [
    `<div style="${F}">`,
    par('Estimados:'),
    par(intro),
    ...(p.jornadas > 0 ? [
      par('<b>1. Resumen</b>'), tabla, '<br>',
      par('<b>2. Detalle de actividades</b>'), ...detalle,
      par('Al terminar cada jornada, el registro y el informe con evidencia fotográfica quedan en SICOM para su revisión y firma.'),
    ] : []),
    par('Quedamos atentos a cualquier comentario.'),
    par('Saludos cordiales,'),
    firma ? par(esc(firma).replace(/\n/g, '<br>')) : '',
    '</div>',
  ].join('\n')
}

function ordenDia(txt: string, p: PlanSemanaCorreo): number {
  for (let i = 0; i < 7; i++) if (txt.startsWith(diaTxt(sumarDias(p.lunes, i)))) return i
  return 99
}

// ── .eml ─────────────────────────────────────────────────────────────────────
function base64Utf8(s: string): string {
  const bytes = new TextEncoder().encode(s)
  const T = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  let out = ''
  for (let i = 0; i < bytes.length; i += 3) {
    const [a, b = 0, c = 0] = [bytes[i], bytes[i + 1], bytes[i + 2]]
    const n = (a << 16) | (b << 8) | c
    out += T[(n >> 18) & 63] + T[(n >> 12) & 63]
      + (i + 1 < bytes.length ? T[(n >> 6) & 63] : '=') + (i + 2 < bytes.length ? T[n & 63] : '=')
  }
  return out
}

const EMAIL = /^[^\s@<>,;"]+@[^\s@<>,;"]+\.[^\s@<>,;"]+$/
export const esCorreo = (x: string) => EMAIL.test(x)
export const separarCorreos = (s: string) => s.split(/[\s,;]+/).map((x) => x.trim()).filter(Boolean)

/**
 * Mensaje .eml sin enviar (X-Unsent: 1): Outlook de escritorio lo abre como
 * correo nuevo, con destinatarios, asunto y cuerpo, listo para «Enviar».
 */
export function emlBorrador(p: { para: string[]; copia: string[]; asunto: string; html: string }): string {
  const limpio = (xs: string[]) => xs.filter(esCorreo).join(', ')
  const cuerpo = base64Utf8(`<!DOCTYPE html><html><head><meta charset="utf-8"></head><body>${p.html}</body></html>`)
  return [
    `To: ${limpio(p.para)}`,
    ...(p.copia.length ? [`Cc: ${limpio(p.copia)}`] : []),
    `Subject: =?UTF-8?B?${base64Utf8(p.asunto)}?=`,
    'X-Unsent: 1',
    'MIME-Version: 1.0',
    'Content-Type: text/html; charset="utf-8"',
    'Content-Transfer-Encoding: base64',
    '',
    ...(cuerpo.match(/.{1,76}/g) ?? []),
    '',
  ].join('\r\n')
}
