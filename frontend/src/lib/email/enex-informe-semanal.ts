// HTML del informe semanal a ENEX. Lo usan la vista previa y el envío, para que
// lo que se revisa sea exactamente lo que sale.

import { celda, chipEstado, emailShell, MARCA, seccionTitulo, tablaAbrir, tablaCerrar } from '@/lib/email/plantilla'
import { fechaCorta, type InformeSemanal } from '@/lib/enex-informe-semanal'

const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))
const pct = (n: number | null) => (n == null ? '—' : `${n.toLocaleString('es-CL', { maximumFractionDigits: 1 })} %`)
const urlSegura = (u: string | null) => (u && /^https:\/\//i.test(u) ? esc(u) : null)

const TONO = {
  ok: [MARCA.verdeOscuro, MARCA.verdeClaro],
  alerta: [MARCA.ambar, MARCA.ambarFondo],
  info: ['#374151', '#f3f4f6'],
} as const

export const asuntoInforme = (i: InformeSemanal) =>
  `Informe semanal de cumplimiento ENEX · Semana ${i.semana.numero} (${fechaCorta(i.semana.desde)} al ${fechaCorta(i.semana.hasta)}) · Pillado`

/**
 * Versión para copiar y pegar en Outlook: tablas con borde y etiquetas clásicas,
 * que sobreviven al pegado. Sin cáscara de correo: la firma la pone quien envía.
 */
export function htmlParaPegar(i: InformeSemanal): string {
  const FUENTE_P = 'font-family:Calibri,Arial,sans-serif;font-size:11pt;color:#1f2937'
  const tabla = (cols: string[], filas: string[][]) => `
    <table border="1" cellpadding="6" cellspacing="0" style="border-collapse:collapse;border-color:#c9d6cc;${FUENTE_P}">
      <tr bgcolor="${MARCA.verdeOscuro}">${cols.map((c) => `<th align="left" bgcolor="${MARCA.verdeOscuro}"><font color="#ffffff"><b>${c}</b></font></th>`).join('')}</tr>
      ${filas.map((f) => `<tr>${f.map((c) => `<td valign="top">${c}</td>`).join('')}</tr>`).join('')}
    </table>`
  const anio = i.semana.hasta.slice(0, 4)
  const actividad = i.faenas.flatMap((f) => f.actividad.map((a) => [
    esc(f.nombre), fechaCorta(a.fecha_plan), esc(a.instalacion), `${esc(a.servicio)}${a.ot ? ` · OT ${esc(a.ot)}` : ''}`,
    a.fecha_ejecucion ? fechaCorta(a.fecha_ejecucion) : '—', esc(a.estado),
  ]))
  const observaciones = i.faenas.flatMap((f) => f.observaciones.map((o) => [
    fechaCorta(o.fecha), `${esc(f.nombre)} · ${esc(o.instalacion)} — ${esc(o.servicio)}`,
    `${o.tipo === 'hallazgo' ? `<b>Hallazgo: ${esc(o.item)}.</b> ` : ''}${esc(o.texto).replace(/\n/g, '<br>')}`,
  ]))
  return `<div style="${FUENTE_P}">
    <p>Estimados:</p>
    <p>Junto con saludar, informamos el cumplimiento del contrato de mantenimiento correspondiente a la <b>semana ${i.semana.numero} (${fechaCorta(i.semana.desde)} al ${fechaCorta(i.semana.hasta)} de ${anio})</b>.</p>
    ${i.comentario.trim() ? `<p>${esc(i.comentario).replace(/\n/g, '<br>')}</p>` : ''}
    <p><b>1. Cumplimiento por faena</b></p>
    ${tabla(['Faena', 'Semana', 'Acumulado trimestre', 'Trimestre'], i.faenas.map((f) => [
      esc(f.nombre), `<b>${f.semana.comprometidas === 0 ? 'Sin trabajos' : pct(f.semana.pct)}</b>`, `<b>${pct(f.trimestre.pctAvance)}</b>`, esc(f.trimestre.etiqueta),
    ]))}
    ${actividad.length ? `<p><b>2. Actividad de la semana</b></p>${tabla(['Faena', 'Fecha', 'Instalación', 'Servicio', 'Ejecutada', 'Estado'], actividad)}` : ''}
    ${observaciones.length ? `<p><b>3. Observaciones de los operadores</b></p>${tabla(['Fecha', 'Instalación', 'Observación'], observaciones)}` : ''}
    <p>Quedamos atentos a cualquier consulta.</p>
    <p>Saludos cordiales,</p>
  </div>`
}

/** Cumplimiento por faena en porcentajes: lo primero que se lee. Lomas va separada en combustibles y lubricantes. */
function resumenPorFaena(i: InformeSemanal): string {
  const filas = i.faenas.map((f, n) => {
    const z = n % 2 === 1
    return `<tr>
      ${celda(`<b>${esc(f.nombre)}</b>`, z)}
      ${celda(`<b>${f.semana.comprometidas === 0 ? 'Sin trabajos' : pct(f.semana.pct)}</b>`, z, 'text-align:right')}
      ${celda(`<b>${pct(f.trimestre.pctAvance)}</b><br><span style="color:#6b7280;font-size:11px">${esc(f.trimestre.etiqueta)}</span>`, z, 'text-align:right')}
    </tr>`
  }).join('')
  return `${seccionTitulo('Cumplimiento por faena', MARCA.verdeOscuro, MARCA.verdeClaro)}
    ${tablaAbrir(['Faena', 'Semana', 'Acumulado trimestre'], [1, 2])}${filas}${tablaCerrar}`
}

export function htmlInformeSemanal(i: InformeSemanal): string {
  const cuerpo = i.faenas.map((f) => {
    const filas = f.actividad.map((a, n) => {
      const z = n % 2 === 1
      const [c, b] = TONO[a.tono]
      return `<tr>
        ${celda(fechaCorta(a.fecha_plan), z)}
        ${celda(`<b>${esc(a.instalacion)}</b><br>${esc(a.servicio)}${a.ot ? ` · OT ${esc(a.ot)}` : ''}`, z)}
        ${celda(a.fecha_ejecucion ? fechaCorta(a.fecha_ejecucion) : '—', z)}
        ${celda(chipEstado(esc(a.estado), c, b), z)}
      </tr>`
    }).join('')

    const obs = f.observaciones.map((o, n) => {
      const z = n % 2 === 1
      const foto = urlSegura(o.foto)
      return `<tr>
        ${celda(fechaCorta(o.fecha), z)}
        ${celda(`<b>${esc(o.instalacion)}</b><br>${esc(o.servicio)}${o.autor ? `<br><span style="color:#6b7280">${esc(o.autor)}</span>` : ''}`, z)}
        ${celda(`${o.tipo === 'hallazgo' ? `${chipEstado('Hallazgo', MARCA.rojo, MARCA.rojoFondo)}<br><b>${esc(o.item)}</b><br>` : ''}${esc(o.texto)}${foto ? `<br><a href="${foto}" target="_blank">Ver foto</a>` : ''}`, z)}
      </tr>`
    }).join('')

    const s = f.semana, t = f.trimestre
    const trimestre = t.unidad === 'actividades'
      ? `Acumulado trimestre ${esc(t.etiqueta)}: <b>${pct(t.pctAvance)}</b> (${t.ejecutadas} de ${t.universo} actividades de la pauta)`
      : t.universo != null
      ? `Acumulado trimestre ${esc(t.etiqueta)}: <b>${pct(t.pctAvance)}</b> (${t.ejecutadas} de ${t.universo} tareas del contrato) · ${pct(t.pctFirmado)} con firma del mandante sobre lo programado`
      : `Acumulado trimestre ${esc(t.etiqueta)}: <b>${pct(t.pctAvance)}</b> (${t.ejecutadas} de ${t.programadas} programadas) · ${pct(t.pctFirmado)} con firma del mandante`
    const semana = s.comprometidas === 0
      ? 'Semana: sin trabajos comprometidos.'
      : `Semana: <b>${pct(s.pct)}</b> de cumplimiento (${s.ejecutadas} de ${s.comprometidas} ${s.unidad})${s.unidad === 'servicios' ? ` · ${s.firmadas} con firma` : ''} · ${s.reprogramadas} reprogramadas · ${s.pendientes} pendientes`

    return `
      ${seccionTitulo(esc(f.nombre), MARCA.verdeOscuro, MARCA.verdeClaro)}
      <p style="margin:0 0 4px;font-size:13px">${semana}${s.adicionales ? ` · ${s.adicionales} de otras semanas` : ''}</p>
      <p style="margin:0 0 10px;font-size:13px">${trimestre}</p>
      ${filas ? `${tablaAbrir(['Fecha', 'Instalación / servicio', 'Ejecutada', 'Estado'])}${filas}${tablaCerrar}` : ''}
      ${obs ? `<p style="margin:16px 0 6px;font-size:13px"><b>Observaciones de los operadores</b></p>
      ${tablaAbrir(['Fecha', 'Instalación', 'Observación'])}${obs}${tablaCerrar}` : ''}`
  }).join('')

  return emailShell({
    titulo: 'Informe semanal de cumplimiento',
    subtitulo: `Contrato ENEX · Semana ${i.semana.numero} · ${fechaCorta(i.semana.desde)} al ${fechaCorta(i.semana.hasta)} de ${i.semana.hasta.slice(0, 4)}`,
    chips: [
      { n: pct(i.totales.pct), label: 'Cumplimiento', color: MARCA.verdeOscuro, fondo: MARCA.verdeClaro },
      { n: `${i.totales.ejecutadas}/${i.totales.comprometidas}`, label: 'Ejecutadas', color: '#374151', fondo: '#f3f4f6' },
      { n: i.totales.firmadas, label: 'Con firma', color: '#374151', fondo: '#f3f4f6' },
      { n: i.totales.reprogramadas, label: 'Reprogramadas', color: MARCA.ambar, fondo: MARCA.ambarFondo },
    ],
    cuerpo: `${i.comentario.trim() ? `<p style="margin:18px 0 0;font-size:14px;line-height:21px">${esc(i.comentario).replace(/\n/g, '<br>')}</p>` : ''}${resumenPorFaena(i)}${cuerpo}`,
    pie: 'Informe preparado por Pillado Empresas desde SICOM. Para consultas, responda este correo.',
  })
}
