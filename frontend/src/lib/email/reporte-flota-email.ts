// Constructor del correo HTML del Reporte de Flota.
// Función pura (sin dependencias de red) para poder testear y reutilizar tanto
// desde la API route como desde cualquier otro disparador (cron, etc).

export type EquipoReporte = {
  patente: string | null
  equipamiento: string | null
  estado: string | null
  dias_arrendado: number
  ultimo_cliente: string | null
}

export type EstanqueReporte = {
  estanque_codigo: string
  estanque_nombre: string
  capacidad_lt: number
  stock_actual: number
  dias_cobertura: number | null
  fecha_agotamiento_estimada: string | null
  ventana_usada: '7d' | '30d' | 'sin_datos'
  severidad: 'agotado' | 'critico' | 'urgente' | 'atencion' | 'ok'
}

export type ReporteEmailPayload = {
  fecha: string | null
  total: number
  disponibilidad: number | null
  utilizacion: number | null
  por_estado: Record<string, number> | null
  por_operacion: Record<string, number> | null
  disponibles: EquipoReporte[]
  combustible: EstanqueReporte[]
  reporteUrl: string
}

const LABEL: Record<string, string> = {
  A: 'Arrendado', C: 'En contrato', D: 'Disponible', H: 'Habilitación', R: 'Recepción',
  M: 'Mantención', T: 'Taller', F: 'Fuera de servicio', V: 'Venta', U: 'Uso interno', L: 'Leasing',
}
const COLOR: Record<string, string> = {
  A: '#16A34A', C: '#15803D', L: '#4F46E5', U: '#0891B2', D: '#2563EB',
  M: '#F59E0B', T: '#FB923C', F: '#DC2626', H: '#A855F7', R: '#06B6D4', V: '#9333EA',
}
const ORDEN = ['A', 'C', 'L', 'U', 'D', 'M', 'T', 'F', 'H', 'R', 'V']

const SEV_COLOR: Record<string, string> = {
  agotado: '#7f1d1d', critico: '#dc2626', urgente: '#ea580c', atencion: '#f59e0b', ok: '#16a34a',
}
const SEV_LABEL: Record<string, string> = {
  agotado: 'Agotado', critico: 'Crítico', urgente: 'Urgente', atencion: 'Atención', ok: 'OK',
}

const NAVY = '#0b2a4a'
const fmtLt = (n: number) => Math.round(n).toLocaleString('es-CL')
const esc = (s: unknown) =>
  String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

function kpiCard(n: string, l: string) {
  return `
    <td style="padding:6px;" width="33%">
      <div style="border:1px solid #e5e7eb;border-radius:10px;padding:14px 10px;text-align:center;background:#ffffff;">
        <div style="font-size:26px;font-weight:700;color:${NAVY};line-height:1.1;">${n}</div>
        <div style="font-size:11px;color:#6b7280;margin-top:4px;">${l}</div>
      </div>
    </td>`
}

function alcanceTxt(e: EstanqueReporte): string {
  if (e.dias_cobertura == null) return 'Sin demanda reciente'
  const d = e.dias_cobertura
  const dias = `${d.toFixed(1)} día${d === 1 ? '' : 's'}`
  return e.fecha_agotamiento_estimada ? `${dias} · agota ~${e.fecha_agotamiento_estimada}` : dias
}

export function asuntoReporteFlota(p: ReporteEmailPayload): string {
  return `Reporte de Flota Pillado${p.fecha ? ` · ${p.fecha}` : ''} — ${p.total} equipos, ${p.disponibles.length} disponibles`
}

export function buildReporteFlotaEmail(p: ReporteEmailPayload): string {
  const est = p.por_estado ?? {}
  const oper = Object.entries(p.por_operacion ?? {})

  const estadoRows = ORDEN.filter((e) => est[e]).map((e) => {
    const pct = p.total > 0 ? Math.round((est[e] / p.total) * 100) : 0
    return `
      <tr>
        <td style="font-size:12px;color:#374151;padding:3px 0;width:120px;">
          <span style="display:inline-block;width:9px;height:9px;border-radius:2px;background:${COLOR[e]};margin-right:6px;"></span>${LABEL[e]}
        </td>
        <td style="padding:3px 0;">
          <div style="background:#f3f4f6;border-radius:3px;height:9px;width:100%;">
            <div style="background:${COLOR[e]};height:9px;border-radius:3px;width:${pct}%;"></div>
          </div>
        </td>
        <td style="font-size:12px;font-weight:700;color:${NAVY};text-align:right;width:30px;padding:3px 0 3px 8px;">${est[e]}</td>
      </tr>`
  }).join('')

  const disponiblesRows = p.disponibles.length === 0
    ? `<tr><td colspan="3" style="padding:10px;font-size:12px;color:#9ca3af;text-align:center;">Sin equipos disponibles hoy.</td></tr>`
    : p.disponibles.map((e) => `
      <tr>
        <td style="padding:6px 8px;font-family:monospace;font-weight:700;font-size:12px;color:${NAVY};border-bottom:1px solid #f3f4f6;">${esc(e.patente ?? '—')}</td>
        <td style="padding:6px 8px;font-size:12px;color:#374151;border-bottom:1px solid #f3f4f6;">${esc(e.equipamiento ?? '—')}</td>
        <td style="padding:6px 8px;font-size:11px;color:#6b7280;border-bottom:1px solid #f3f4f6;">${esc(e.ultimo_cliente ?? 'Sin contrato')}</td>
      </tr>`).join('')

  const combustibleRows = p.combustible.length === 0
    ? `<tr><td colspan="4" style="padding:10px;font-size:12px;color:#9ca3af;text-align:center;">Sin estanques registrados.</td></tr>`
    : p.combustible.map((e) => `
      <tr>
        <td style="padding:6px 8px;font-size:12px;color:${NAVY};border-bottom:1px solid #f3f4f6;">
          <b>${esc(e.estanque_codigo)}</b> <span style="color:#9ca3af;">${esc(e.estanque_nombre)}</span>
        </td>
        <td style="padding:6px 8px;font-size:12px;color:#374151;text-align:right;border-bottom:1px solid #f3f4f6;white-space:nowrap;">
          ${fmtLt(e.stock_actual)} <span style="color:#9ca3af;">/ ${fmtLt(e.capacidad_lt)} L</span>
        </td>
        <td style="padding:6px 8px;font-size:12px;color:#374151;text-align:right;border-bottom:1px solid #f3f4f6;white-space:nowrap;">${alcanceTxt(e)}</td>
        <td style="padding:6px 8px;border-bottom:1px solid #f3f4f6;text-align:center;">
          <span style="display:inline-block;background:${SEV_COLOR[e.severidad]};color:#fff;font-size:10px;font-weight:700;padding:2px 8px;border-radius:10px;">${SEV_LABEL[e.severidad]}</span>
        </td>
      </tr>`).join('')

  const operRows = oper.map(([k, v]) =>
    `<tr><td style="font-size:12px;color:#374151;padding:3px 0;">${esc(k)}</td><td style="font-size:12px;font-weight:700;color:${NAVY};text-align:right;">${v}</td></tr>`
  ).join('')

  return `<!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f3f4f6;font-family:Arial,Helvetica,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f3f4f6;padding:20px 0;">
    <tr><td align="center">
      <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;">

        <!-- Header -->
        <tr><td style="background:${NAVY};border-radius:12px 12px 0 0;padding:22px 24px;">
          <div style="color:#fff;font-size:20px;font-weight:700;">Reporte de Flota — Pillado</div>
          <div style="color:#9fb4cc;font-size:13px;margin-top:3px;">Estado real de la flota${p.fecha ? ` al ${p.fecha}` : ''} · SICOM-ICEO</div>
        </td></tr>

        <tr><td style="background:#ffffff;padding:18px 18px 6px;">
          <!-- KPIs -->
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
            ${kpiCard(String(p.total), 'Equipos de flota')}
            ${kpiCard(`${p.disponibilidad ?? '—'}%`, 'Disponibilidad física (mes)')}
            ${kpiCard(`${p.utilizacion ?? '—'}%`, 'Utilización bruta (mes)')}
          </tr></table>

          <!-- CTA al gráfico dinámico -->
          <div style="text-align:center;padding:14px 0 4px;">
            <a href="${esc(p.reporteUrl)}" style="display:inline-block;background:#2563eb;color:#fff;text-decoration:none;font-size:14px;font-weight:700;padding:11px 22px;border-radius:8px;">Ver reporte interactivo →</a>
            <div style="font-size:11px;color:#9ca3af;margin-top:6px;">Gráfico dinámico de distribución, por cliente y por operación</div>
          </div>
        </td></tr>

        <!-- Camiones disponibles hoy -->
        <tr><td style="background:#ffffff;padding:8px 18px;">
          <div style="font-size:14px;font-weight:700;color:${NAVY};border-bottom:2px solid #16A34A;padding-bottom:5px;margin-bottom:6px;">
            🟢 Equipos disponibles hoy (${p.disponibles.length})
          </div>
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            <tr><th align="left" style="font-size:10px;text-transform:uppercase;color:#9ca3af;padding:0 8px 4px;">Patente</th>
                <th align="left" style="font-size:10px;text-transform:uppercase;color:#9ca3af;padding:0 8px 4px;">Equipo</th>
                <th align="left" style="font-size:10px;text-transform:uppercase;color:#9ca3af;padding:0 8px 4px;">Último cliente</th></tr>
            ${disponiblesRows}
          </table>
        </td></tr>

        <!-- Stock de combustible + alcance -->
        <tr><td style="background:#ffffff;padding:14px 18px 8px;">
          <div style="font-size:14px;font-weight:700;color:${NAVY};border-bottom:2px solid #F59E0B;padding-bottom:5px;margin-bottom:6px;">
            ⛽ Stock de combustible y alcance
          </div>
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            <tr><th align="left" style="font-size:10px;text-transform:uppercase;color:#9ca3af;padding:0 8px 4px;">Estanque</th>
                <th align="right" style="font-size:10px;text-transform:uppercase;color:#9ca3af;padding:0 8px 4px;">Stock</th>
                <th align="right" style="font-size:10px;text-transform:uppercase;color:#9ca3af;padding:0 8px 4px;">Alcance</th>
                <th align="center" style="font-size:10px;text-transform:uppercase;color:#9ca3af;padding:0 8px 4px;">Estado</th></tr>
            ${combustibleRows}
          </table>
          <div style="font-size:10px;color:#9ca3af;margin-top:6px;">Alcance = stock ÷ consumo diario real (despachos externos, ventana 7/30 días).</div>
        </td></tr>

        <!-- Distribución + operación -->
        <tr><td style="background:#ffffff;padding:14px 18px;border-radius:0 0 0 0;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
            <td valign="top" width="62%" style="padding-right:10px;">
              <div style="font-size:13px;font-weight:700;color:${NAVY};margin-bottom:4px;">Distribución por estado</div>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0">${estadoRows}</table>
            </td>
            <td valign="top" width="38%">
              <div style="font-size:13px;font-weight:700;color:${NAVY};margin-bottom:4px;">Por operación</div>
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0">${operRows}</table>
            </td>
          </tr></table>
        </td></tr>

        <!-- Footer -->
        <tr><td style="background:#ffffff;border-radius:0 0 12px 12px;padding:14px 18px;text-align:center;border-top:1px solid #e5e7eb;">
          <div style="font-size:11px;color:#9ca3af;">Pillado · SICOM-ICEO · Generado ${new Date().toLocaleDateString('es-CL')}</div>
        </td></tr>

      </table>
    </td></tr>
  </table>
</body></html>`
}
