import type {
  TallerPlanDia, TallerPlanOTFull, TallerKpiSemanal,
} from '@/lib/services/taller-plan-semanal'

// ============================================================================
// HTML del Plan Semanal de Taller para PEGAR EN EL CORREO.
// Diseñado para Outlook (motor Word) + Gmail: 100% tablas con bgcolor, sin
// float, sin flex, sin border-radius ni fondos en <span> (no rinden en Outlook).
// Tipo y estado van como TEXTO EN COLOR (rinde en todos los clientes).
// ============================================================================

const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c] as string))

const NAVY = '#0b2a4a'
const FONT = "font-family:Segoe UI,Arial,Helvetica,sans-serif"

function fmtFecha(iso: string): string {
  if (!iso) return ''
  const [, m, d] = iso.split('-')
  return d && m ? `${d}-${m}` : iso
}

const TIPO_COLOR: Record<string, string> = {
  preventivo: '#15803d', correctivo: '#c2410c', inspeccion: '#1d4ed8',
  lubricacion: '#0e7490', abastecimiento: '#6d28d9',
}
const ESTADO_COLOR: Record<string, string> = {
  finalizada: '#15803d', en_ejecucion: '#1d4ed8', pausada: '#b45309',
  no_ejecutada: '#b91c1c', bloqueada: '#b91c1c', reprogramada: '#6b7280',
  planificada: '#6b7280', asignada: '#6b7280', liberada: '#0e7490', cancelada: '#9ca3af',
}
const ESTADO_LABEL: Record<string, string> = {
  finalizada: 'Finalizada', en_ejecucion: 'En ejecución', pausada: 'Pausada',
  no_ejecutada: 'No ejecutada', bloqueada: 'Bloqueada', reprogramada: 'Reprogramada',
  planificada: 'Planificada', asignada: 'Asignada', liberada: 'Liberada', cancelada: 'Cancelada',
}
const cap1 = (s: string) => s ? s.charAt(0).toUpperCase() + s.slice(1) : s

export function asuntoPlanSemanalTaller(ini: string, fin: string): string {
  return `Plan Semanal de Taller — ${fmtFecha(ini)} al ${fmtFecha(fin)}`
}

export function buildPlanSemanalTallerEmailHtml(args: {
  dias: TallerPlanDia[]
  jornadas: TallerPlanOTFull[]
  kpi?: TallerKpiSemanal | null
  semanaInicio: string
  semanaFin: string
  faena?: string | null
  link: string
}): string {
  const { dias, jornadas, kpi, semanaInicio, semanaFin, faena, link } = args
  const diasOrden = [...(dias ?? [])].sort((a, b) => a.orden - b.orden)
  const porDia = (fecha: string) =>
    (jornadas ?? []).filter((j) => j.dia_fecha === fecha)
      .sort((a, b) => (a.secuencia_jornada ?? 0) - (b.secuencia_jornada ?? 0))

  const k = kpi
  const cumpl = k ? Math.round(Number(k.cumplimiento_pct ?? 0)) : 0
  const cumplColor = cumpl >= 85 ? '#15803d' : cumpl >= 60 ? '#b45309' : '#b91c1c'

  // ── KPI cell ──
  const kpiCell = (label: string, val: string, accent = NAVY) =>
    `<td align="center" bgcolor="#f1f5f9" style="${FONT};padding:9px 6px;border:1px solid #e2e8f0">
       <div style="font-size:10px;color:#64748b;text-transform:uppercase">${esc(label)}</div>
       <div style="font-size:20px;font-weight:bold;color:${accent}">${esc(val)}</div></td>`

  // ── Fila de OT ──
  const filaOT = (j: TallerPlanOTFull, zebra: boolean) => {
    const tipoCol = TIPO_COLOR[j.ot_tipo] ?? '#6b7280'
    const estCol = ESTADO_COLOR[j.jornada_estado] ?? '#6b7280'
    const bg = zebra ? '#f8fafc' : '#ffffff'
    const resp = j.responsable || j.cuadrilla || '—'
    const trabajo = j.pm_nombre || j.ot_folio || ''
    const horas = j.horas_planificadas != null ? `${j.horas_planificadas} h` : ''
    return `<tr bgcolor="${bg}">
      <td style="${FONT};font-size:13px;padding:6px 10px;border-bottom:1px solid #eef2f7">
        <b style="color:${NAVY}">${esc(j.activo_patente || j.activo_codigo || '—')}</b>
        ${j.activo_tipo ? `<span style="color:#94a3b8;font-size:11px">&nbsp;${esc(j.activo_tipo)}</span>` : ''}
      </td>
      <td style="${FONT};font-size:12px;padding:6px 10px;border-bottom:1px solid #eef2f7">
        <b style="color:${tipoCol}">${esc(cap1(j.ot_tipo))}</b>${trabajo ? `<span style="color:#475569">&nbsp;· ${esc(trabajo)}</span>` : ''}
      </td>
      <td style="${FONT};font-size:12px;padding:6px 10px;border-bottom:1px solid #eef2f7;color:#334155">${esc(resp)}</td>
      <td align="center" style="${FONT};font-size:12px;padding:6px 10px;border-bottom:1px solid #eef2f7;color:#64748b">${esc(horas)}</td>
      <td align="right" style="${FONT};font-size:12px;padding:6px 10px;border-bottom:1px solid #eef2f7">
        <b style="color:${estCol}">${esc(ESTADO_LABEL[j.jornada_estado] ?? j.jornada_estado)}</b>
      </td>
    </tr>`
  }

  // ── Sección de un día ──
  const seccionDia = (d: TallerPlanDia) => {
    const items = porDia(d.fecha)
    const cuerpo = items.length === 0
      ? `<tr><td colspan="5" align="center" style="${FONT};font-size:12px;color:#9ca3af;padding:9px">— Sin trabajos —</td></tr>`
      : items.map((j, i) => filaOT(j, i % 2 === 1)).join('')
    return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:14px;border:1px solid #e2e8f0">
      <tr bgcolor="${NAVY}">
        <td style="${FONT};font-size:13px;font-weight:bold;color:#ffffff;padding:7px 10px">${esc(d.nombre_dia)} <span style="color:#9bb4d1;font-weight:normal">· ${fmtFecha(d.fecha)}</span></td>
        <td align="right" style="${FONT};font-size:11px;color:#9bb4d1;padding:7px 10px">${items.length} trabajo(s)</td>
      </tr>
      <tr><td colspan="2" style="padding:0">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
          ${items.length > 0 ? `<tr bgcolor="#f1f5f9">
            <td style="${FONT};font-size:10px;color:#64748b;text-transform:uppercase;padding:4px 10px">Equipo</td>
            <td style="${FONT};font-size:10px;color:#64748b;text-transform:uppercase;padding:4px 10px">Trabajo</td>
            <td style="${FONT};font-size:10px;color:#64748b;text-transform:uppercase;padding:4px 10px">Responsable</td>
            <td align="center" style="${FONT};font-size:10px;color:#64748b;text-transform:uppercase;padding:4px 10px">Horas</td>
            <td align="right" style="${FONT};font-size:10px;color:#64748b;text-transform:uppercase;padding:4px 10px">Estado</td>
          </tr>` : ''}
          ${cuerpo}
        </table>
      </td></tr>
    </table>`
  }

  const kpiRow = k ? `<tr>
    ${kpiCell('Jornadas', String(k.jornadas_planificadas ?? 0))}
    ${kpiCell('OTs', String(k.ots_unicas ?? 0))}
    ${kpiCell('Horas plan.', `${Math.round(Number(k.horas_planificadas ?? 0))} h`)}
    ${kpiCell('Cumplim.', `${cumpl}%`, cumplColor)}
    ${kpiCell('Finalizadas', String(k.jornadas_finalizadas ?? 0), '#15803d')}
    ${kpiCell('Atrasadas', String(k.jornadas_atrasadas ?? 0), Number(k.jornadas_atrasadas ?? 0) > 0 ? '#b91c1c' : NAVY)}
  </tr>` : ''

  return `<table role="presentation" width="680" cellpadding="0" cellspacing="0" border="0" align="center" style="${FONT};color:#1f2937;width:680px;max-width:100%">
  <tr><td bgcolor="${NAVY}" style="padding:16px 20px">
    <div style="${FONT};font-size:19px;font-weight:bold;color:#ffffff">Plan Semanal de Taller — Pillado</div>
    <div style="${FONT};font-size:12px;color:#9bb4d1;padding-top:2px">Semana ${fmtFecha(semanaInicio)} al ${fmtFecha(semanaFin)}${faena ? ` &middot; ${esc(faena)}` : ''}</div>
  </td></tr>
  <tr><td style="padding:16px 20px;border:1px solid #e2e8f0;border-top:none">
    ${k ? `<table role="presentation" width="100%" cellpadding="0" cellspacing="4" border="0">${kpiRow}</table>` : ''}
    ${diasOrden.map(seccionDia).join('')}
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr><td align="center" style="padding:18px 0 4px">
      <a href="${esc(link)}" style="${FONT};background:#16a34a;color:#ffffff;text-decoration:none;font-weight:bold;font-size:14px;padding:11px 22px;display:inline-block">Abrir plan interactivo &raquo;</a>
    </td></tr></table>
    <div style="${FONT};font-size:11px;color:#94a3b8;padding-top:10px">
      Tipo de trabajo: <b style="color:#15803d">Preventivo</b> &middot; <b style="color:#c2410c">Correctivo</b> &middot; <b style="color:#1d4ed8">Inspección</b>. &nbsp;Generado desde SICOM-ICEO.
    </div>
  </td></tr>
</table>`
}
