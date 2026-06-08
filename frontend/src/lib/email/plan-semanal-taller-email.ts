import type {
  TallerPlanDia, TallerPlanOTFull, TallerKpiSemanal,
} from '@/lib/services/taller-plan-semanal'

// ============================================================================
// HTML email-safe del Plan Semanal de Taller (para "copiar para correo").
// Estilos inline, tablas — compatible con Outlook/Gmail.
// ============================================================================

const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c] as string))

const NAVY = '#0b2a4a'

function fmtFecha(iso: string): string {
  // YYYY-MM-DD -> DD-MM
  if (!iso) return ''
  const [, m, d] = iso.split('-')
  return d && m ? `${d}-${m}` : iso
}

const TIPO_COLOR: Record<string, string> = {
  preventivo: '#16a34a', correctivo: '#ea580c', inspeccion: '#2563eb',
  lubricacion: '#0891b2', abastecimiento: '#7c3aed',
}
const ESTADO_COLOR: Record<string, string> = {
  finalizada: '#16a34a', en_ejecucion: '#2563eb', pausada: '#d97706',
  no_ejecutada: '#dc2626', bloqueada: '#dc2626', reprogramada: '#6b7280',
  planificada: '#6b7280', asignada: '#6b7280', liberada: '#0891b2', cancelada: '#9ca3af',
}
const ESTADO_LABEL: Record<string, string> = {
  finalizada: 'Finalizada', en_ejecucion: 'En ejecución', pausada: 'Pausada',
  no_ejecutada: 'No ejecutada', bloqueada: 'Bloqueada', reprogramada: 'Reprogramada',
  planificada: 'Planificada', asignada: 'Asignada', liberada: 'Liberada', cancelada: 'Cancelada',
}

function chip(text: string, color: string): string {
  return `<span style="display:inline-block;background:${color};color:#fff;font-size:10px;font-weight:700;padding:2px 8px;border-radius:10px;white-space:nowrap">${esc(text)}</span>`
}

function kpiCell(label: string, val: string, accent = NAVY): string {
  return `<td style="padding:10px;border:1px solid #e5e7eb;text-align:center;background:#f8fafc;border-radius:6px">
    <div style="font-size:10px;color:#64748b;text-transform:uppercase;letter-spacing:.04em">${esc(label)}</div>
    <div style="font-size:22px;font-weight:800;color:${accent};margin-top:2px">${esc(val)}</div></td>`
}

export function asuntoPlanSemanalTaller(ini: string, fin: string): string {
  return `🔧 Plan Semanal de Taller — ${fmtFecha(ini)} al ${fmtFecha(fin)}`
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
    (jornadas ?? [])
      .filter((j) => j.dia_fecha === fecha)
      .sort((a, b) => (a.secuencia_jornada ?? 0) - (b.secuencia_jornada ?? 0))

  const k = kpi
  const cumpl = k ? Math.round(Number(k.cumplimiento_pct ?? 0)) : 0
  const cumplColor = cumpl >= 85 ? '#16a34a' : cumpl >= 60 ? '#d97706' : '#dc2626'

  const seccionDia = (d: TallerPlanDia): string => {
    const items = porDia(d.fecha)
    const filas = items.length === 0
      ? `<tr><td colspan="4" style="padding:10px;font-size:12px;color:#9ca3af;text-align:center">— Sin trabajos —</td></tr>`
      : items.map((j) => {
          const tipoCol = TIPO_COLOR[j.ot_tipo] ?? '#6b7280'
          const estCol = ESTADO_COLOR[j.jornada_estado] ?? '#6b7280'
          const resp = j.responsable || j.cuadrilla || '—'
          const trabajo = j.pm_nombre || j.ot_folio || j.ot_tipo
          const horas = j.horas_planificadas != null ? `${j.horas_planificadas} h` : '—'
          return `<tr>
            <td style="padding:7px 8px;border-bottom:1px solid #eef2f7">
              <b style="color:${NAVY}">${esc(j.activo_patente || j.activo_codigo || '—')}</b>
              <span style="color:#9ca3af;font-size:11px"> ${esc(j.activo_tipo || '')}</span>
            </td>
            <td style="padding:7px 8px;border-bottom:1px solid #eef2f7">
              ${chip(j.ot_tipo, tipoCol)} <span style="font-size:12px;color:#475569">${esc(trabajo)}</span>
            </td>
            <td style="padding:7px 8px;border-bottom:1px solid #eef2f7;font-size:12px">${esc(resp)}<div style="color:#9ca3af;font-size:11px">${esc(horas)}</div></td>
            <td style="padding:7px 8px;border-bottom:1px solid #eef2f7;text-align:right">${chip(ESTADO_LABEL[j.jornada_estado] ?? j.jornada_estado, estCol)}</td>
          </tr>`
        }).join('')
    return `<div style="margin-top:14px">
      <div style="background:${NAVY};color:#fff;padding:7px 12px;border-radius:6px 6px 0 0;font-weight:700;font-size:13px">
        ${esc(d.nombre_dia)} <span style="opacity:.7;font-weight:400">· ${fmtFecha(d.fecha)}</span>
        <span style="float:right;opacity:.8;font-weight:400">${items.length} trabajo(s)</span>
      </div>
      <table style="width:100%;border-collapse:collapse;font-size:13px;border:1px solid #e5e7eb;border-top:none">
        ${filas}
      </table>
    </div>`
  }

  return `<div style="max-width:820px;font-family:Segoe UI,Arial,sans-serif;color:#1f2937">
  <div style="background:${NAVY};color:#fff;padding:18px 22px;border-radius:8px 8px 0 0">
    <div style="font-size:20px;font-weight:800">🔧 Plan Semanal de Taller — Pillado</div>
    <div style="font-size:12px;opacity:.85;margin-top:2px">
      Semana ${fmtFecha(semanaInicio)} al ${fmtFecha(semanaFin)}${faena ? ` · ${esc(faena)}` : ''}
    </div>
  </div>
  <div style="padding:16px 22px;border:1px solid #e5e7eb;border-top:none">
    ${k ? `<table style="width:100%;border-collapse:separate;border-spacing:5px"><tr>
      ${kpiCell('Jornadas', String(k.jornadas_planificadas ?? 0))}
      ${kpiCell('OTs únicas', String(k.ots_unicas ?? 0))}
      ${kpiCell('Horas plan.', `${Math.round(Number(k.horas_planificadas ?? 0))} h`)}
      ${kpiCell('Cumplimiento', `${cumpl}%`, cumplColor)}
      ${kpiCell('Finalizadas', String(k.jornadas_finalizadas ?? 0), '#16a34a')}
      ${kpiCell('Atrasadas', String(k.jornadas_atrasadas ?? 0), Number(k.jornadas_atrasadas ?? 0) > 0 ? '#dc2626' : NAVY)}
    </tr></table>` : ''}

    ${diasOrden.map(seccionDia).join('')}

    <div style="text-align:center;margin:18px 0 4px">
      <a href="${esc(link)}" style="display:inline-block;background:#16a34a;color:#fff;text-decoration:none;font-weight:700;font-size:14px;padding:11px 22px;border-radius:8px">▶ Abrir plan interactivo</a>
    </div>
    <p style="font-size:11px;color:#94a3b8;margin-top:10px">
      Preventivo (verde) · Correctivo (naranjo) · Inspección (azul). Generado desde SICOM-ICEO.
    </p>
  </div>
</div>`
}
