// ============================================================================
// Plantilla visual compartida de los correos del sistema (2026-09-03)
// ----------------------------------------------------------------------------
// Manuel: «debe ser más atractivo el correo». Todos los correos automáticos
// salen con la misma cáscara: cabecera con la marca (verde Pillado), tarjetas
// de resumen con el número grande, secciones con título de color, tabla limpia
// y un botón de acción. HTML de CORREO: solo estilos inline y tablas — Gmail y
// Outlook no cargan CSS externo ni flexbox.
// ============================================================================

export type ChipResumen = {
  n: number | string
  label: string
  /** Color del texto (ej. '#B91C1C') y fondo suave (ej. '#FEE2E2'). */
  color: string
  fondo: string
}

export const MARCA = {
  verde: '#2D8B3D',
  verdeOscuro: '#1e5929',
  verdeClaro: '#dbf0de',
  naranjo: '#E87722',
  rojo: '#B91C1C',
  rojoFondo: '#FEE2E2',
  ambar: '#B45309',
  ambarFondo: '#FEF3C7',
} as const

/** Título de sección como «píldora» de color. */
export function seccionTitulo(texto: string, color: string, fondo: string): string {
  return `<div style="margin:20px 0 8px">
    <span style="display:inline-block;background:${fondo};color:${color};font-size:13px;
                 font-weight:700;padding:6px 14px;border-radius:999px">${texto}</span>
  </div>`
}

/** Chip de estado dentro de una celda (ej. VENCIDO, hace 12 días). */
export function chipEstado(texto: string, color: string, fondo: string): string {
  return `<span style="display:inline-block;background:${fondo};color:${color};font-size:11px;
                       font-weight:700;padding:3px 10px;border-radius:999px;white-space:nowrap">${texto}</span>`
}

/** Cabecera de tabla consistente. */
export function tablaAbrir(cols: string[]): string {
  return `<table role="presentation" cellpadding="0" cellspacing="0"
                 style="border-collapse:collapse;width:100%;font-size:13px;color:#1f2937">
    <tr>${cols.map((c) => `<th align="left" style="padding:8px 10px;font-size:11px;color:#6b7280;
        text-transform:uppercase;letter-spacing:.5px;border-bottom:2px solid #e5e7eb">${c}</th>`).join('')}
    </tr>`
}
export const tablaCerrar = '</table>'

/** Celda estándar; usar `zebra` para alternar el fondo de la fila. */
export function celda(html: string, zebra: boolean, extra = ''): string {
  return `<td style="padding:9px 10px;border-bottom:1px solid #f1f5f2;
                     background:${zebra ? '#f8faf8' : '#ffffff'};${extra}">${html}</td>`
}

/** La cáscara completa del correo. `cuerpo` va dentro de la tarjeta blanca. */
export function emailShell(p: {
  titulo: string
  subtitulo?: string
  chips?: ChipResumen[]
  cuerpo: string
  ctaUrl?: string
  ctaTexto?: string
  pie?: string
}): string {
  const chips = p.chips ?? []
  const chipsHtml = chips.length === 0 ? '' : `
    <table role="presentation" cellpadding="0" cellspacing="0" style="margin:18px 0 2px"><tr>
      ${chips.map((c, i) => `${i > 0 ? '<td style="width:10px"></td>' : ''}
        <td style="background:${c.fondo};border-radius:12px;padding:12px 20px;text-align:center">
          <div style="font-size:28px;font-weight:800;color:${c.color};line-height:1">${c.n}</div>
          <div style="font-size:10px;font-weight:700;color:${c.color};margin-top:4px;
                      text-transform:uppercase;letter-spacing:.6px">${c.label}</div>
        </td>`).join('')}
    </tr></table>`

  const cta = p.ctaUrl ? `
    <table role="presentation" cellpadding="0" cellspacing="0" style="margin:24px 0 4px"><tr>
      <td style="background:${MARCA.verde};border-radius:10px">
        <a href="${p.ctaUrl}"
           style="display:inline-block;padding:12px 26px;color:#ffffff;font-weight:700;
                  font-size:14px;text-decoration:none">${p.ctaTexto ?? 'Abrir en SICOM'} →</a>
      </td></tr></table>` : ''

  return `
  <div style="margin:0;padding:26px 10px;background:#eef3ef">
    <table role="presentation" cellpadding="0" cellspacing="0" align="center"
           style="max-width:680px;width:100%;margin:0 auto;background:#ffffff;border-radius:16px;
                  overflow:hidden;border:1px solid #dfe8e1;
                  font-family:system-ui,-apple-system,'Segoe UI',Arial,sans-serif">
      <tr><td style="background:${MARCA.verdeOscuro};padding:22px 30px">
        <div style="font-size:11px;font-weight:700;letter-spacing:2px;color:#8bcc95;
                    text-transform:uppercase">Pillado Empresas · SICOM</div>
        <div style="font-size:22px;font-weight:800;color:#ffffff;margin-top:5px;line-height:1.25">${p.titulo}</div>
        ${p.subtitulo ? `<div style="font-size:13px;color:${MARCA.verdeClaro};margin-top:5px">${p.subtitulo}</div>` : ''}
      </td></tr>
      <tr><td style="padding:10px 30px 26px">
        ${chipsHtml}
        ${p.cuerpo}
        ${cta}
      </td></tr>
      <tr><td style="background:#f6f9f6;border-top:1px solid #e8efe9;padding:14px 30px;
                     font-size:11px;color:#87a08c;line-height:1.6">
        ${p.pie ?? 'Correo automático de SICOM · Pillado Empresas. No responder a este mensaje.'}
      </td></tr>
    </table>
  </div>`
}
