import { supabase } from '@/lib/supabase'
import { emailShell, seccionTitulo, tablaAbrir, tablaCerrar, celda, MARCA, FUENTE, type ChipResumen } from '@/lib/email/plantilla'
import { fmtClp, fmtMM, fmtPct, variacionPct } from '@/lib/costos-operacion'

// ============================================================================
// Informe mensual de costos (MIG617) — para el dueño, corto a propósito
// ----------------------------------------------------------------------------
// Top 10 del mes por equipo, por familia y por centro de costo, contra el mes
// anterior. Mismo esquema que fiabilidad: el correo se copia con formato para
// pegarlo en Outlook y su botón abre /reporte-costos con el token del link
// (?t=), que se ve sin iniciar sesión. El costo/h es de 12 meses: mes a mes no
// hay horas (el horómetro GPS diario no avanza).
// ============================================================================

export type ItemEquipo = {
  activo_id: string | null
  etiqueta: string
  tipo_equipo: string | null
  faena: string | null
  total: number
  total_anterior: number | null
  costo_hora_12m: number | null
  horas_12m: number | null
  mediana_tipo: number | null
  familias: { nombre: string; total: number }[]
}
export type ItemFamilia = {
  familia: string; nombre: string; grupo: string | null; total: number; total_anterior: number | null
}
export type ItemCc = {
  codi_cc: string; area: string; descripcion: string | null; total: number; total_anterior: number | null
}
type Top<T> = { n: number; items: T[]; resto: number }

export type ReporteCostos = {
  mes: string
  mes_anterior: string
  sync: { ultima: string | null; max_fecha: string | null } | null
  kpi: {
    total: number; total_anterior: number; asignado_equipo: number; asignado_equipo_anterior: number
    equipos_con_gasto: number; lineas_sin_precio: number
    total_12m: number; costo_hora_12m: number | null; horas_12m: number | null; equipos_medidos_12m: number
  }
  tendencia: { mes: string; total: number }[]
  equipos: Top<ItemEquipo>
  familias: Top<ItemFamilia>
  centros_costo: Top<ItemCc>
}

const MESES_LARGO = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
  'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']
/** '2026-09-01' → 'septiembre 2026' */
export const mesLargo = (iso: string) => `${MESES_LARGO[Number(iso.slice(5, 7)) - 1]} ${iso.slice(0, 4)}`

/** Último mes cerrado: el mes en curso todavía se está cargando en Softland. */
export function mesCerradoIso(hoy = new Date()): string {
  const d = new Date(hoy.getFullYear(), hoy.getMonth() - 1, 1)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
}

export const NOMBRE_AREA_CC: Record<string, string> = {
  operacion: 'Operación de faena', taller: 'Taller', proyectos: 'Proyectos',
  generico: 'Sin equipo', sin_clasificar: 'Sin centro de costo',
}

export async function getReporteCostos(mes: string, token?: string | null) {
  const { data, error } = await supabase.rpc('fn_reporte_costos_publico', { p_mes: mes, p_token: token ?? null })
  if (error) throw new Error(error.message)
  return data as ReporteCostos
}

export async function getTokenReporteCostos(): Promise<string | null> {
  const { data, error } = await supabase.rpc('fn_reporte_costos_link_token')
  if (error) return null
  return (data as string | null) ?? null
}

export const linkReporteCostos = (origin: string, mes: string, token?: string | null) =>
  `${origin}/reporte-costos/?mes=${mes.slice(0, 7)}${token ? `&t=${token}` : ''}`

/** El panel completo de SICOM (gráficos + Pareto), abierto con el token del link (MIG620). */
export const linkPanelCostos = (origin: string, token?: string | null) =>
  `${origin}/reporte-costos/panel/${token ? `?t=${token}` : ''}`

const esc = (s: unknown) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c] as string))

/** Variación contra el mes anterior: gastar más es lo que se mira → rojo. */
function variacionHtml(actual: number, anterior: number | null | undefined): string {
  const v = variacionPct(actual, anterior)
  if (v == null) return '<span style="color:#9ca3af">antes $0</span>'
  const color = v > 0 ? MARCA.rojo : MARCA.verde
  return `<span style="color:${color};font-weight:700">${v > 0 ? '▲' : '▼'} ${fmtPct(Math.abs(v))}</span>`
}

const MESES_CORTO = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic']

/**
 * Gráfico de barras de los últimos 12 meses hecho con celdas de tabla: Outlook
 * no muestra SVG ni canvas, pero sí una celda con alto y color de fondo.
 * El mes del informe va en verde oscuro, el resto en verde claro.
 */
function tendenciaHtml(tend: { mes: string; total: number }[], mes: string): string {
  const xs = tend.slice(-12)
  const max = Math.max(...xs.map((t) => Number(t.total) || 0), 0)
  if (xs.length < 2 || max <= 0) return ''
  const ALTO = 90
  const col = (t: { mes: string; total: number }) => {
    const v = Number(t.total) || 0
    const h = Math.max(2, Math.round((v / max) * ALTO))
    const actual = String(t.mes).slice(0, 7) === mes.slice(0, 7)
    const color = actual ? MARCA.verdeOscuro : '#a7d4ae'
    const etiqueta = `${(v / 1e6).toLocaleString('es-CL', { maximumFractionDigits: 0 })}`
    return `<td valign="bottom" align="center" style="padding:0 2px;${FUENTE}">
      <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="width:100%">
        <tr><td align="center" style="${FUENTE};font-size:10px;line-height:13px;color:${actual ? MARCA.verdeOscuro : '#6b7280'};
                 font-weight:${actual ? 'bold' : 'normal'};padding-bottom:3px">${etiqueta}</td></tr>
        <tr><td height="${h}" bgcolor="${color}" style="height:${h}px;background:${color};font-size:1px;line-height:1px;
                 border-radius:3px 3px 0 0">&nbsp;</td></tr>
        <tr><td align="center" style="${FUENTE};font-size:10px;line-height:14px;color:${actual ? MARCA.verdeOscuro : '#6b7280'};
                 font-weight:${actual ? 'bold' : 'normal'};padding-top:4px;border-top:1px solid #d1d5db">${MESES_CORTO[Number(String(t.mes).slice(5, 7)) - 1]}</td></tr>
      </table></td>`
  }
  return `${seccionTitulo('Gasto de los últimos 12 meses (millones de $)', MARCA.verdeOscuro, MARCA.verdeClaro)}
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="width:100%;table-layout:fixed">
      <tr>${xs.map(col).join('')}</tr>
    </table>`
}

/** % del mes con una barra de participación debajo — tablas, se ve en Outlook. */
function pctConBarra(pct: number): string {
  const p = Math.min(100, Math.max(1, Math.round(pct)))
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="72" align="right" style="width:72px">
      <tr><td colspan="2" align="right" style="${FUENTE};font-size:13px;color:#1f2937;padding-bottom:4px">${fmtPct(pct)}</td></tr>
      <tr><td width="${p}%" height="5" bgcolor="${MARCA.verde}" style="background:${MARCA.verde};font-size:1px;line-height:1px">&nbsp;</td>
      ${p < 100 ? `<td width="${100 - p}%" height="5" bgcolor="#e5e7eb" style="background:#e5e7eb;font-size:1px;line-height:1px">&nbsp;</td>` : ''}</tr>
    </table>`
}

export function buildCostosEmailHtml(r: ReporteCostos, link: string): string {
  const k = r.kpi
  const mes = mesLargo(r.mes)
  const ant = mesLargo(r.mes_anterior)
  const der = 'text-align:right;white-space:nowrap'
  const pctAsignado = k.total > 0 ? (k.asignado_equipo / k.total) * 100 : null
  const vTotal = variacionPct(k.total, k.total_anterior)

  const chips: ChipResumen[] = [
    { n: fmtMM(k.total), label: `Gasto ${mes.split(' ')[0]}`, color: MARCA.verdeOscuro, fondo: MARCA.verdeClaro },
    {
      n: vTotal == null ? '—' : `${vTotal > 0 ? '+' : ''}${Math.round(vTotal)}%`, label: `vs ${ant.split(' ')[0]}`,
      color: vTotal != null && vTotal > 0 ? MARCA.rojo : MARCA.verdeOscuro,
      fondo: vTotal != null && vTotal > 0 ? MARCA.rojoFondo : MARCA.verdeClaro,
    },
    { n: pctAsignado == null ? '—' : `${Math.round(pctAsignado)}%`, label: 'Asignado a equipo', color: '#1d4ed8', fondo: '#dbeafe' },
    { n: k.costo_hora_12m == null ? '—' : fmtClp(k.costo_hora_12m), label: 'Costo/h flota 12 m', color: MARCA.ambar, fondo: MARCA.ambarFondo },
  ]

  const resto = (n: number, mostrados: number, total: number, cols: number) => n > mostrados
    ? `<tr><td colspan="${cols}" style="padding:8px 10px;font-size:12px;color:#6b7280">Otros ${n - mostrados}: ${fmtClp(total)}</td></tr>` : ''

  const equipos = r.equipos.items.map((e, i) => {
    const z = i % 2 === 1
    const sub = [e.faena, e.familias[0] ? `${e.familias[0].nombre}` : null].filter(Boolean).join(' · ')
    return `<tr>${celda(`<b>${i + 1}. ${esc(e.etiqueta)}</b>${sub ? `<div style="font-size:11px;color:#6b7280">${esc(sub)}</div>` : ''}`, z)}
      ${celda(fmtClp(e.total), z, der)}${celda(variacionHtml(e.total, e.total_anterior), z, der)}
      ${celda(e.costo_hora_12m == null ? '<span style="color:#9ca3af">sin medición</span>' : fmtClp(e.costo_hora_12m), z, der)}</tr>`
  }).join('')

  const familias = r.familias.items.map((f, i) => {
    const z = i % 2 === 1
    return `<tr>${celda(`<b>${i + 1}. ${esc(f.nombre)}</b>`, z)}${celda(fmtClp(f.total), z, der)}
      ${celda(k.total > 0 ? pctConBarra((f.total / k.total) * 100) : '—', z, der)}${celda(variacionHtml(f.total, f.total_anterior), z, der)}</tr>`
  }).join('')

  const ccs = r.centros_costo.items.map((c, i) => {
    const z = i % 2 === 1
    return `<tr>${celda(`<b>${i + 1}. ${esc(c.descripcion ?? c.codi_cc)}</b><div style="font-size:11px;color:#6b7280">${esc(c.codi_cc)} · ${esc(NOMBRE_AREA_CC[c.area] ?? c.area)}</div>`, z)}
      ${celda(fmtClp(c.total), z, der)}${celda(variacionHtml(c.total, c.total_anterior), z, der)}</tr>`
  }).join('')

  const cuerpo = `
    <p style="${FUENTE};font-size:13px;color:#4b5563;margin:14px 0 0">
      Gasto del mes: <b style="color:#1f2937">${fmtClp(k.total)}</b> en ${k.equipos_con_gasto} equipos.
      Variaciones contra ${esc(ant)}: <span style="color:${MARCA.rojo}">▲ rojo = se gastó más</span>,
      <span style="color:${MARCA.verde}">▼ verde = se gastó menos</span>.
    </p>
    ${tendenciaHtml(r.tendencia ?? [], r.mes)}
    ${seccionTitulo('Los 10 equipos con más gasto', MARCA.verdeOscuro, MARCA.verdeClaro)}
    ${tablaAbrir(['Equipo', 'Gasto', 'vs mes ant.', 'Costo/h 12 m'], [1, 2, 3])}${equipos}${resto(r.equipos.n, r.equipos.items.length, r.equipos.resto, 4)}${tablaCerrar}
    ${seccionTitulo('Las 10 familias con más gasto', MARCA.verdeOscuro, MARCA.verdeClaro)}
    ${tablaAbrir(['Familia', 'Gasto', '% del mes', 'vs mes ant.'], [1, 2, 3])}${familias}${resto(r.familias.n, r.familias.items.length, r.familias.resto, 4)}${tablaCerrar}
    ${r.centros_costo.items.length ? `${seccionTitulo('Centros de costo (fuera de los equipos)', MARCA.verdeOscuro, MARCA.verdeClaro)}
    ${tablaAbrir(['Centro de costo', 'Gasto', 'vs mes ant.'], [1, 2])}${ccs}${resto(r.centros_costo.n, r.centros_costo.items.length, r.centros_costo.resto, 3)}${tablaCerrar}` : ''}`

  return emailShell({
    titulo: `Costos de operación · ${mes}`,
    subtitulo: 'Órdenes de compra aprobadas en Softland (materiales y servicios, neto). Sin combustible de reventa.',
    chips,
    cuerpo,
    ctaUrl: link,
    ctaTexto: 'Abrir panel de costos (gráficos y Pareto)',
    pie: 'Costo/h = gasto entre dos lecturas de horómetro ÷ horas entre ellas, últimos 12 meses. '
      + '«Sin medición» = el equipo no tiene dos lecturas de horómetro confiables en ese período. SICOM · Pillado Empresas.',
  })
}

/** Arma el correo y lo deja en el portapapeles con formato, para pegar en Outlook. */
export async function copiarReporteCostos(r: ReporteCostos, token: string | null): Promise<string> {
  // El botón del correo abre el panel completo de SICOM (Manuel: «que pueda ir al
  // gráfico que aparece en SICOM y ver los paretos y todo»).
  const link = linkPanelCostos(window.location.origin, token)
  // Debajo de la tarjeta queda un párrafo en blanco con letra normal para
  // escribir la minuta de trabajos sin heredar el formato del informe.
  const html = `${buildCostosEmailHtml(r, link)}
    <p style="font-family:Calibri,Arial,sans-serif;font-size:11pt;margin:0">&nbsp;</p>
    <p style="font-family:Calibri,Arial,sans-serif;font-size:11pt;margin:0">&nbsp;</p>`
  try {
    await navigator.clipboard.write([new ClipboardItem({
      'text/html': new Blob([html], { type: 'text/html' }),
      'text/plain': new Blob([`Costos de operación · ${mesLargo(r.mes)} — ${link}`], { type: 'text/plain' }),
    })])
    return 'Copiado ✓ — ahora pega en Outlook (Ctrl+V)'
  } catch {
    const w = window.open('', '_blank')
    if (w) { w.document.write(html); w.document.close() }
    return 'Se abrió en otra pestaña: Ctrl+A → Ctrl+C → pega en Outlook'
  }
}
