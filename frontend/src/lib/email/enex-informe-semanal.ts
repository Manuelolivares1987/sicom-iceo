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
