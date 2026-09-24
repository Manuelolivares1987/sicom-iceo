// ============================================================================
// Correo simple: casi texto plano, para avisos automáticos que deben llegar a
// la bandeja de entrada (24-09-2026, pedido de Manuel tras ver el de papeles).
// ----------------------------------------------------------------------------
// El filtro de Outlook castiga los correos «de campaña»: tablas anchas, colores
// de fondo, emojis en el asunto, HTML sin versión en texto. Este formato es lo
// que escribiría una persona: títulos, viñetas, un enlace. Siempre va con su
// versión en texto plano (multipart/alternative), que también baja el puntaje
// de spam. La plantilla con marca (plantilla.ts) queda para correos a pedido.
//
// Todo el texto que entra acá es texto plano: se escapa adentro.
// ============================================================================

export type LineaSimple = { texto: string; alerta?: boolean; url?: string }
export type ItemSimple = { titulo: string; sub?: string; lineas: LineaSimple[] }
export type SeccionSimple = { titulo: string; nota?: string; items: ItemSimple[] }

const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!))

export function correoSimple(p: {
  titulo: string
  /** Párrafos antes de las secciones. */
  intro?: string[]
  secciones: SeccionSimple[]
  enlace?: { url: string; texto: string }
  pie: string
}): { html: string; text: string } {
  const linea = (l: LineaSimple) => {
    const t = l.alerta ? `<span style="color:#b91c1c">${esc(l.texto)}</span>` : esc(l.texto)
    return `<li style="margin:2px 0">${t}${l.url ? ` <a href="${esc(l.url)}">(ver mapa)</a>` : ''}</li>`
  }
  const item = (it: ItemSimple) => `
    <p style="margin:12px 0 2px"><b>${esc(it.titulo)}</b>${it.sub ? ` <span style="color:#555">— ${esc(it.sub)}</span>` : ''}</p>
    <ul style="margin:0 0 0 20px;padding:0">${it.lineas.map(linea).join('')}</ul>`
  const seccion = (s: SeccionSimple) => s.items.length === 0 ? '' : `
    <h3 style="margin:24px 0 4px;font-size:15px;border-bottom:1px solid #ccc;padding-bottom:4px">${esc(s.titulo)}</h3>
    ${s.nota ? `<p style="margin:4px 0;color:#555">${esc(s.nota)}</p>` : ''}
    ${s.items.map(item).join('')}`

  const html = `<!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><title>${esc(p.titulo)}</title></head>
<body style="margin:0;padding:16px">
<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.45;color:#222;max-width:680px">
  <h2 style="margin:0 0 8px;font-size:18px">${esc(p.titulo)}</h2>
  ${(p.intro ?? []).map((t) => `<p style="margin:6px 0">${esc(t)}</p>`).join('')}
  ${p.secciones.map(seccion).join('')}
  ${p.enlace ? `<p style="margin:24px 0 8px"><a href="${esc(p.enlace.url)}">${esc(p.enlace.texto)}</a></p>` : ''}
  <p style="margin:16px 0 0;font-size:12px;color:#777">${esc(p.pie)}</p>
</div>
</body></html>`

  const t: string[] = [p.titulo, '='.repeat(Math.min(p.titulo.length, 60)), '']
  for (const x of p.intro ?? []) t.push(x, '')
  for (const s of p.secciones) {
    if (s.items.length === 0) continue
    t.push('', s.titulo.toUpperCase(), '-'.repeat(Math.min(s.titulo.length, 60)))
    if (s.nota) t.push(s.nota)
    for (const it of s.items) {
      t.push('', it.titulo + (it.sub ? ` — ${it.sub}` : ''))
      for (const l of it.lineas) t.push(`  - ${l.texto}${l.url ? ` (${l.url})` : ''}`)
    }
  }
  if (p.enlace) t.push('', `${p.enlace.texto}: ${p.enlace.url}`)
  t.push('', '--', p.pie)
  return { html, text: t.join('\n') }
}
