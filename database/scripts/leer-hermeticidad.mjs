// ============================================================================
// Leer los certificados de hermeticidad como se leen en papel: por líneas.
// ----------------------------------------------------------------------------
// El lector anterior (analizar-certificados.mjs) unía todos los trozos de texto
// del PDF en el orden en que vienen dentro del archivo. Ese orden no es el
// orden de lectura: en estos certificados la etiqueta «Fecha de vencimiento» y
// su fecha quedan a decenas de trozos de distancia, y la asociación se pierde.
// Por eso 25 certificados de hermeticidad —todos bloqueantes— pasaron dos años
// con la vigencia equivocada sin que nadie lo notara.
//
// Acá se reconstruyen las líneas por su posición en la página (coordenada Y),
// que es como las lee una persona. Con eso «Fecha de vencimiento: lunes, 27 de
// julio de 2026» vuelve a ser una sola frase.
//
// No escribe nada en la base: imprime lo que dice cada documento.
// ============================================================================
import fs from 'node:fs'
import path from 'node:path'

const MESES = { enero:1, febrero:2, marzo:3, abril:4, mayo:5, junio:6, julio:7,
                agosto:8, septiembre:9, setiembre:9, octubre:10, noviembre:11, diciembre:12 }

const iso = (d, m, a) => `${a}-${String(m).padStart(2,'0')}-${String(d).padStart(2,'0')}`

/** «lunes, 27 de julio de 2026» o «27/07/2026» → 2026-07-27 */
function parseFecha(txt) {
  let m = txt.match(/(\d{1,2})\s+de\s+([a-záéíóú]+)\s+de\s+(\d{4})/i)
  if (m && MESES[m[2].toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'')])
    return iso(+m[1], MESES[m[2].toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'')], m[3])
  m = txt.match(/(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})/)
  if (m) return iso(+m[1], +m[2], m[3])
  return null
}

/** Líneas de la página en orden de lectura, no en orden de archivo. */
async function lineas(pdfjs, buf) {
  const doc = await pdfjs.getDocument({ data: new Uint8Array(buf), useSystemFonts: true }).promise
  const out = []
  for (let i = 1; i <= doc.numPages; i++) {
    const items = (await (await doc.getPage(i)).getTextContent()).items
      .filter(x => x.str.trim())
      .map(x => ({ s: x.str, x: Math.round(x.transform[4]), y: Math.round(x.transform[5]) }))
    items.sort((a, b) => b.y - a.y || a.x - b.x)
    let cur = null
    for (const o of items) {
      if (!cur || Math.abs(cur.y - o.y) > 4) { cur = { y: o.y, t: o.s }; out.push(cur) }
      else cur.t += ' ' + o.s
    }
  }
  return out.map(l => l.t.replace(/\s+/g, ' ').trim())
}

const main = async () => {
  const pdfjs = await import('../../frontend/node_modules/pdfjs-dist/legacy/build/pdf.mjs')
  const lista = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
  const tmp = process.argv[3] || '.'
  const res = []

  for (const c of lista) {
    const f = path.join(tmp, `h_${c.patente}.pdf`)
    try {
      if (!fs.existsSync(f)) {
        const r = await fetch(c.archivo_url)
        if (!r.ok) throw new Error('HTTP ' + r.status)
        fs.writeFileSync(f, Buffer.from(await r.arrayBuffer()))
      }
      const ls = await lineas(pdfjs, fs.readFileSync(f))
      const buscar = (re) => { for (const l of ls) if (re.test(l)) { const d = parseFecha(l); if (d) return { d, l } } return null }

      const venc = buscar(/fecha\s+de\s+vencimiento/i)
      const insp = buscar(/fecha\s+de\s+(inspecci|prueba)/i)
      const nro  = (ls.find(l => /certificado\s*N[ºo°]/i.test(l)) || '').match(/N[ºo°]\s*([\d\/]+)/i)?.[1] ?? null

      res.push({ patente: c.patente, id: c.id,
                 doc_inspeccion: insp?.d ?? null, doc_vencimiento: venc?.d ?? null,
                 certificado: nro, texto_lineas: ls.length,
                 bd_emision: c.em?.slice(0,10) ?? null, bd_vencimiento: c.ve?.slice(0,10) ?? null,
                 evidencia: venc?.l?.slice(0,110) ?? null })
    } catch (e) {
      res.push({ patente: c.patente, id: c.id, error: String(e.message ?? e),
                 bd_emision: c.em?.slice(0,10) ?? null, bd_vencimiento: c.ve?.slice(0,10) ?? null })
    }
  }

  const hoy = new Date().toISOString().slice(0,10)
  console.log(`${'PATENTE'.padEnd(9)} ${'DOC INSP'.padEnd(11)} ${'DOC VENCE'.padEnd(11)} ${'MESES'.padStart(5)}  ${'BD VENCE'.padEnd(11)} ESTADO REAL`)
  for (const r of res) {
    if (r.error) { console.log(`${r.patente.padEnd(9)} ${'—'.padEnd(11)} ${'ERROR'.padEnd(11)} ${''.padStart(5)}  ${(r.bd_vencimiento||'-').padEnd(11)} ${r.error}`); continue }
    const meses = (r.doc_inspeccion && r.doc_vencimiento)
      ? Math.round((new Date(r.doc_vencimiento) - new Date(r.doc_inspeccion)) / 2629800000) : ''
    const estado = !r.doc_vencimiento ? 'escaneo — hay que abrirlo'
      : r.doc_vencimiento < hoy ? `VENCIDO hace ${Math.round((new Date(hoy)-new Date(r.doc_vencimiento))/86400000)} días`
      : `vigente (${Math.round((new Date(r.doc_vencimiento)-new Date(hoy))/86400000)} días)`
    const dif = r.doc_vencimiento && r.bd_vencimiento && r.doc_vencimiento !== r.bd_vencimiento ? '  ← NO CALZA' : ''
    console.log(`${r.patente.padEnd(9)} ${(r.doc_inspeccion||'—').padEnd(11)} ${(r.doc_vencimiento||'—').padEnd(11)} ${String(meses).padStart(5)}  ${(r.bd_vencimiento||'-').padEnd(11)} ${estado}${dif}`)
  }
  fs.writeFileSync(path.join(tmp, 'hermeticidad-leida.json'), JSON.stringify(res, null, 2))
  console.log('\n→ ' + path.join(tmp, 'hermeticidad-leida.json'))
}
main()
