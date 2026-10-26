// ============================================================================
// Plantilla visual compartida de los correos del sistema (2026-09-03)
// ----------------------------------------------------------------------------
// Manuel: «debe ser más atractivo el correo». Todos los correos automáticos
// salen con la misma cáscara: cabecera con la marca (verde Pillado), tarjetas
// de resumen con el número grande, secciones con título de color, tabla limpia
// y un botón de acción. HTML de CORREO: solo estilos inline y tablas — Gmail y
// Outlook no cargan CSS externo ni flexbox.
//
// 2026-10-26 (Manuel: «que se pueda ver bien en Outlook»): Outlook de
// escritorio dibuja con el motor de Word. Ignora padding/margin/background en
// <div> y <span>, inline-block, border-radius y max-width, y si no reconoce la
// primera fuente cae a Times New Roman. Por eso: todo color de fondo y todo
// relleno va en un <td> (con bgcolor además del style), el ancho va como
// atributo width="680", y cada celda declara su fuente.
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

/** Fuente segura: Segoe UI en Windows/Outlook, Arial en el resto. Nunca system-ui (Outlook → Times). */
export const FUENTE = "font-family:'Segoe UI',Arial,Helvetica,sans-serif"

/** Ancho de la tarjeta. Outlook de escritorio solo respeta el atributo width. */
export const ANCHO_CORREO = 680

/** Título de sección como «píldora» de color (tabla de una celda: Outlook sí le pinta el fondo). */
export function seccionTitulo(texto: string, color: string, fondo: string): string {
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:22px 0 8px">
    <tr><td height="22" style="font-size:1px;line-height:1px">&nbsp;</td></tr>
    <tr><td bgcolor="${fondo}" style="background:${fondo};border-radius:999px;padding:6px 14px;
                 ${FUENTE};font-size:13px;font-weight:bold;color:${color}">${texto}</td></tr>
    <tr><td height="8" style="font-size:1px;line-height:1px">&nbsp;</td></tr>
  </table>`
}

/** Chip de estado dentro de una celda (ej. VENCIDO, hace 12 días). En Outlook queda como texto resaltado. */
export function chipEstado(texto: string, color: string, fondo: string): string {
  return `<span style="display:inline-block;background:${fondo};mso-highlight:${fondo};color:${color};${FUENTE};
                       font-size:11px;font-weight:bold;padding:3px 10px;border-radius:999px;white-space:nowrap">&nbsp;${texto}&nbsp;</span>`
}

/** Cabecera de tabla consistente. `derecha` = índices de columnas numéricas (título a la derecha). */
export function tablaAbrir(cols: string[], derecha: number[] = []): string {
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%"
                 style="border-collapse:collapse;width:100%;${FUENTE};font-size:13px;color:#1f2937">
    <tr>${cols.map((c, i) => {
      const al = derecha.includes(i) ? 'right' : 'left'
      return `<th align="${al}" style="padding:8px 10px;${FUENTE};font-size:11px;
        font-weight:bold;color:#6b7280;text-transform:uppercase;letter-spacing:.5px;
        border-bottom:2px solid #e5e7eb;text-align:${al}">${c}</th>`
    }).join('')}
    </tr>`
}
export const tablaCerrar = '</table>'

/** Celda estándar; usar `zebra` para alternar el fondo de la fila. */
export function celda(html: string, zebra: boolean, extra = ''): string {
  const bg = zebra ? '#f8faf8' : '#ffffff'
  return `<td bgcolor="${bg}" valign="top" style="padding:9px 10px;border-bottom:1px solid #eef2ef;
                     background:${bg};${FUENTE};font-size:13px;color:#1f2937;${extra}">${html}</td>`
}

/** Botón «a prueba de Outlook»: el color y el relleno van en el <td>, no en el <a>. */
export function boton(url: string, texto: string, color: string = MARCA.verde): string {
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:24px 0 4px">
    <tr><td height="24" style="font-size:1px;line-height:1px">&nbsp;</td></tr>
    <tr><td bgcolor="${color}" align="center" style="background:${color};border-radius:10px;padding:13px 28px">
      <a href="${url}" target="_blank"
         style="${FUENTE};font-size:14px;font-weight:bold;color:#ffffff;text-decoration:none;display:inline-block">${texto} &rarr;</a>
    </td></tr></table>`
}

/** Fila de tarjetas de resumen (número grande). Ancho igual para todas. */
function chipsFila(chips: ChipResumen[]): string {
  if (chips.length === 0) return ''
  const ancho = Math.floor(100 / chips.length)
  return `
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="width:100%;margin:18px 0 2px">
      <tr><td colspan="${chips.length * 2 - 1}" height="18" style="font-size:1px;line-height:1px">&nbsp;</td></tr>
      <tr>
      ${chips.map((c, i) => `${i > 0 ? '<td width="10" style="width:10px;font-size:1px">&nbsp;</td>' : ''}
        <td width="${ancho}%" bgcolor="${c.fondo}" align="center" valign="middle"
            style="background:${c.fondo};border-radius:12px;padding:14px 10px;text-align:center">
          <div style="${FUENTE};font-size:26px;font-weight:bold;color:${c.color};line-height:30px;mso-line-height-rule:exactly">${c.n}</div>
          <div style="${FUENTE};font-size:10px;font-weight:bold;color:${c.color};line-height:14px;
                      text-transform:uppercase;letter-spacing:.6px">${c.label}</div>
        </td>`).join('')}
      </tr>
    </table>`
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
  const cta = p.ctaUrl ? boton(p.ctaUrl, p.ctaTexto ?? 'Abrir en SICOM') : ''

  return `
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" bgcolor="#eef3ef"
         style="width:100%;background:#eef3ef">
    <tr><td align="center" style="padding:24px 10px">
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="${ANCHO_CORREO}" align="center"
             style="width:${ANCHO_CORREO}px;max-width:100%;background:#ffffff;border:1px solid #dfe8e1;border-radius:16px">
        <tr><td bgcolor="${MARCA.verdeOscuro}" style="background:${MARCA.verdeOscuro};padding:22px 30px;border-radius:16px 16px 0 0">
          <div style="${FUENTE};font-size:11px;font-weight:bold;letter-spacing:2px;color:#8bcc95;text-transform:uppercase">Pillado Empresas · SICOM</div>
          <div style="${FUENTE};font-size:22px;font-weight:bold;color:#ffffff;line-height:30px;mso-line-height-rule:exactly">${p.titulo}</div>
          ${p.subtitulo ? `<div style="${FUENTE};font-size:13px;color:${MARCA.verdeClaro};line-height:19px">${p.subtitulo}</div>` : ''}
        </td></tr>
        <tr><td bgcolor="#ffffff" style="background:#ffffff;padding:6px 30px 26px;${FUENTE};font-size:13px;color:#1f2937">
          ${chipsFila(p.chips ?? [])}
          ${p.cuerpo}
          ${cta}
        </td></tr>
        <tr><td bgcolor="#f6f9f6" style="background:#f6f9f6;border-top:1px solid #e8efe9;padding:14px 30px;
                       ${FUENTE};font-size:11px;color:#87a08c;line-height:17px;border-radius:0 0 16px 16px">
          ${p.pie ?? 'Correo automático de SICOM · Pillado Empresas. No responder a este mensaje.'}
        </td></tr>
      </table>
    </td></tr>
  </table>`
}
