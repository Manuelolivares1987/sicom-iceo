import { supabase } from '@/lib/supabase'

// Arma el HTML con formato del reporte de fiabilidad y lo deja en el
// portapapeles para pegar directo en Outlook. Usa el mismo dataset publico
// (fn_reporte_fiabilidad_publico) para que el correo sea identico desde
// cualquier pagina (dashboard o reporte publico).

type Categoria = {
  categoria: string | null; total_equipos: number; disponibilidad_fisica: number
  dias_equipo: number; dias_up: number; dias_down: number; eventos_falla_total: number
  utilizacion_bruta: number; mtbf_agregado: number; mttr_agregado: number
}
type Equipo = {
  patente: string; equipamiento: string | null; dias_down: number; disponibilidad_inherente: number
}
type Estanque = { estanque_codigo: string; capacidad_lt: number; stock_actual: number }
type Reporte = { categorias: Categoria[]; equipos: Equipo[]; combustible: Estanque[] }

const CAT: Record<string, string> = {
  arriendo_comercial: 'Arriendo comercial', leasing_operativo: 'Leasing operativo',
  uso_interno: 'Uso interno', venta: 'Venta',
}
const lt = (v: number | null | undefined) => Math.round(Number(v || 0)).toLocaleString('es-CL')
const pct = (v: number | null | undefined, d = 1) => v == null ? '—' : `${(Number(v) * 100).toFixed(d)}%`
const num = (v: number | null | undefined, d = 1) => v == null ? '—' : Number(v).toFixed(d)
const esc = (s: unknown) => String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c] as string))

export function buildFiabilidadEmailHtml(data: Reporte, desde: string, hasta: string, origin: string, token?: string | null): string {
  const cats = data.categorias ?? []
  const equipos = data.equipos ?? []
  // Excluir camiones Franke (codigo CAM-*): solo se ven en la sección Franke.
  const combustible = (data.combustible ?? []).filter((e) => !e.estanque_codigo?.startsWith('CAM-'))
  const n = (v: number | null | undefined) => Number(v || 0)
  const s = cats.reduce((a, c) => ({
    eq: a.eq + n(c.total_equipos), dias: a.dias + n(c.dias_equipo),
    up: a.up + n(c.dias_up), down: a.down + n(c.dias_down), ev: a.ev + n(c.eventos_falla_total),
  }), { eq: 0, dias: 0, up: 0, down: 0, ev: 0 })
  const dispFis = s.dias > 0 ? s.up / s.dias : 0
  const mtbf = s.ev > 0 ? s.up / s.ev : s.up
  const mttr = s.ev > 0 ? s.down / s.ev : 0
  const dispInh = mtbf + mttr > 0 ? mtbf / (mtbf + mttr) : 1
  const combTot = combustible.reduce((a, e) => ({ cap: a.cap + n(e.capacidad_lt), st: a.st + n(e.stock_actual) }), { cap: 0, st: 0 })
  const peores = [...equipos].sort((a, b) => n(a.disponibilidad_inherente) - n(b.disponibilidad_inherente)).slice(0, 5)
  // Token del link (MIG200): el destinatario abre el reporte sin iniciar sesión.
  const link = `${origin}/reporte-fiabilidad?desde=${desde}&hasta=${hasta}${token ? `&t=${token}` : ''}`

  const td = (t: string, r = false) => `<td style="padding:8px;border:1px solid #e5e7eb;text-align:${r ? 'right' : 'left'}">${t}</td>`
  const th = (t: string, r = false) => `<th style="padding:8px;border:1px solid #e5e7eb;text-align:${r ? 'right' : 'left'};background:#f1f5f9;color:#475569">${t}</th>`
  const kpiTd = (label: string, val: string) => `<td style="padding:10px;border:1px solid #e5e7eb;text-align:center;background:#f8fafc"><div style="font-size:11px;color:#64748b;text-transform:uppercase">${label}</div><div style="font-size:20px;font-weight:700;color:#0b2a4a">${val}</div></td>`

  return `<div style="max-width:780px;font-family:Segoe UI,Arial,sans-serif;color:#1f2937">
  <div style="background:#0b2a4a;color:#fff;padding:18px 22px;border-radius:8px 8px 0 0">
    <div style="font-size:19px;font-weight:700">Análisis de Fiabilidad de Flota — Pillado</div>
    <div style="font-size:12px;opacity:.85">MTBF · MTTR · Disponibilidad Inherente · ${esc(desde)} a ${esc(hasta)}</div>
  </div>
  <div style="padding:16px 22px;border:1px solid #e5e7eb;border-top:none">
    <table style="width:100%;border-collapse:separate;border-spacing:5px"><tr>
      ${kpiTd('Equipos', String(s.eq))}${kpiTd('Disp. física', pct(dispFis))}${kpiTd('Disp. inherente', pct(dispInh))}${kpiTd('MTBF', num(mtbf) + ' d')}${kpiTd('MTTR', num(mttr) + ' d')}
    </tr></table>
    <div style="text-align:center;margin:16px 0 6px">
      <a href="${link}" style="display:inline-block;background:#16a34a;color:#fff;text-decoration:none;font-weight:700;font-size:14px;padding:12px 24px;border-radius:8px">▶ Ver reporte interactivo — click en cada patente para su historial</a>
    </div>
    <h3 style="color:#0b2a4a;font-size:14px;margin:16px 0 6px">KPIs por categoría</h3>
    <table style="width:100%;border-collapse:collapse;font-size:13px"><tr>${th('Categoría')}${th('Equipos', true)}${th('Disp. física', true)}${th('N° fallas', true)}${th('MTBF', true)}${th('MTTR', true)}</tr>
      ${cats.map((c) => `<tr>${td(esc(CAT[c.categoria ?? ''] ?? c.categoria ?? 'Sin categoría'))}${td(String(c.total_equipos), true)}${td(pct(c.disponibilidad_fisica), true)}${td(String(c.eventos_falla_total), true)}${td(Number(c.mtbf_agregado).toFixed(1), true)}${td(Number(c.mttr_agregado).toFixed(1), true)}</tr>`).join('')}
    </table>
    ${combustible.length ? `<h3 style="color:#0b2a4a;font-size:14px;margin:16px 0 6px">Stock de combustible</h3>
    <table style="width:100%;border-collapse:collapse;font-size:13px"><tr>${th('Estanque')}${th('Capacidad', true)}${th('Stock', true)}${th('% lleno', true)}</tr>
      ${combustible.map((e) => { const cap = n(e.capacidad_lt), st = n(e.stock_actual); return `<tr>${td(esc(e.estanque_codigo))}${td(lt(cap) + ' L', true)}${td(lt(st) + ' L', true)}${td((cap > 0 ? Math.round(st / cap * 100) : 0) + '%', true)}</tr>` }).join('')}
      <tr style="background:#0b2a4a;color:#fff;font-weight:700">${td('CONSOLIDADO')}${td(lt(combTot.cap) + ' L', true)}${td(lt(combTot.st) + ' L', true)}${td((combTot.cap > 0 ? Math.round(combTot.st / combTot.cap * 100) : 0) + '%', true)}</tr>
    </table>` : ''}
    <h3 style="color:#0b2a4a;font-size:14px;margin:16px 0 6px">Menor disponibilidad inherente</h3>
    <table style="width:100%;border-collapse:collapse;font-size:13px"><tr>${th('Patente')}${th('Equipo')}${th('Días fuera', true)}${th('Disp. inherente', true)}</tr>
      ${peores.map((e) => `<tr>${td('<b>' + esc(e.patente) + '</b>')}${td(esc(e.equipamiento))}${td(String(e.dias_down), true)}${td(pct(e.disponibilidad_inherente), true)}</tr>`).join('')}
    </table>
    <p style="font-size:11px;color:#94a3b8;margin-top:12px">El detalle por patente y el historial diario están en el reporte interactivo (botón verde). Disp. inherente = MTBF ÷ (MTBF + MTTR).</p>
  </div>
</div>`
}

// Trae los datos, arma el HTML y lo copia al portapapeles. Devuelve un mensaje
// de estado. Fallback: abre el reporte en otra pestaña para copiar manual.
export async function copiarReporteFiabilidad(desde: string, hasta: string): Promise<string> {
  const { data, error } = await supabase.rpc('fn_reporte_fiabilidad_publico', { p_ini: desde, p_fin: hasta })
  if (error) throw new Error(error.message)
  // Token del link (MIG200): si falla se copia el link sin token (pedirá sesión).
  const { data: token } = await supabase.rpc('fn_reporte_fiabilidad_link_token')
  const linkPlano = `${window.location.origin}/reporte-fiabilidad?desde=${desde}&hasta=${hasta}${token ? `&t=${token}` : ''}`
  const html = buildFiabilidadEmailHtml(data as Reporte, desde, hasta, window.location.origin, token as string | null)
  try {
    await navigator.clipboard.write([new ClipboardItem({
      'text/html': new Blob([html], { type: 'text/html' }),
      'text/plain': new Blob([`Reporte de Fiabilidad de Flota (${desde} a ${hasta}) — ${linkPlano}`], { type: 'text/plain' }),
    })])
    return 'Copiado ✓ — ahora pega en Outlook (Ctrl+V)'
  } catch {
    const w = window.open('', '_blank')
    if (w) { w.document.write(html); w.document.close() }
    return 'Se abrió en otra pestaña: Ctrl+A → Ctrl+C → pega en Outlook'
  }
}
