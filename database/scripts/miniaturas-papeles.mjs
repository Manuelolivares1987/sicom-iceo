// ============================================================================
// Una miniatura legible de cada papel, para poder revisarlo sin abrir el PDF
// ----------------------------------------------------------------------------
// Manuel, 27-08-2026: «necesito que de tu análisis forense se haga un Excel,
// con todas las patentes y en su interior fotos con los papeles y las fechas
// que se están considerando, para realizar una revisión completa».
//
// Esto produce la foto. Renderiza la página con pdfjs sobre un canvas, que es
// lo que se ve al abrir el archivo, en vez de sacarle las imágenes incrustadas:
// hay escaneos guardados en tiras de 140 píxeles y otros comprimidos en
// formatos que no son JPEG, y con extraer bytes no salen.
//
// ── LO QUE MIDE, Y POR QUÉ ─────────────────────────────────────────────────
// Después de renderizar cuenta cuánta tinta hay en la página. Una hoja casi
// blanca no es una miniatura mala: es un PDF sin contenido, y hay varios en la
// flota —el TC8 del FSLZ-67 se abre en blanco hasta en Chrome—. Cuando pasa, se
// prueban las páginas siguientes y después las imágenes incrustadas; si nada da
// tinta, queda anotado como PÁGINA EN BLANCO, que es un hallazgo y no un error.
// ============================================================================
import { readFileSync, writeFileSync, existsSync, mkdirSync, statSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const RAIZ = resolve(__dirname, '../..')
const FE = resolve(RAIZ, 'frontend')

const pdfjs = await import(pathToFileURL(resolve(FE, 'node_modules/pdfjs-dist/legacy/build/pdf.mjs')).href)
const { createCanvas, loadImage } = await import(pathToFileURL(resolve(FE, 'node_modules/@napi-rs/canvas/index.js')).href)

const CACHE = resolve(RAIZ, '.cache-papeles')
const DEST = resolve(RAIZ, 'reportes/forense/miniaturas')
if (!existsSync(DEST)) mkdirSync(DEST, { recursive: true })

const ALTO = 1100          // suficiente para leer una fecha impresa
const CALIDAD = 0.62       // 871 miniaturas tienen que caber en un Excel

/** Qué porcentaje de la página tiene tinta. Una hoja en blanco da casi 0. */
function tinta(ctx, w, h) {
  const d = ctx.getImageData(0, 0, w, h).data
  let oscuros = 0, total = 0
  // Se muestrea cada 7 píxeles: con 1,2 millones de píxeles la cuenta exacta
  // no cambia la conclusión y sí cuesta.
  for (let i = 0; i < d.length; i += 4 * 7) {
    total++
    if (d[i] < 200 || d[i + 1] < 200 || d[i + 2] < 200) oscuros++
  }
  return total ? oscuros / total : 0
}

function encuadrar(img) {
  const escala = ALTO / img.height
  const w = Math.round(img.width * escala)
  const c = createCanvas(w, ALTO)
  const ctx = c.getContext('2d')
  ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, w, ALTO)
  ctx.drawImage(img, 0, 0, w, ALTO)
  return c
}

function jpegsDe(buf) {
  const t = []
  for (let i = 0; i < buf.length - 3; i++) {
    if (buf[i] === 0xFF && buf[i + 1] === 0xD8 && buf[i + 2] === 0xFF) {
      for (let j = i + 3; j < buf.length - 1; j++) {
        if (buf[j] === 0xFF && buf[j + 1] === 0xD9) { t.push(buf.subarray(i, j + 2)); i = j + 1; break }
      }
    }
  }
  return t.sort((a, b) => b.length - a.length)
}

async function miniatura(buf) {
  const esPdf = buf.slice(0, 4).toString('latin1') === '%PDF'

  // Imagen suelta guardada como si fuera PDF: se usa tal cual.
  if (!esPdf) {
    try {
      const c = encuadrar(await loadImage(buf))
      return { jpg: c.toBuffer('image/jpeg', CALIDAD), fuente: 'archivo de imagen' }
    } catch { return { motivo: 'El archivo no es PDF ni una imagen que se pueda abrir.' } }
  }

  const doc = await pdfjs.getDocument({
    data: new Uint8Array(buf), useSystemFonts: true, isEvalSupported: false,
    standardFontDataUrl: resolve(FE, 'node_modules/pdfjs-dist/standard_fonts') + '/',
  }).promise

  // Se prueban las primeras páginas hasta encontrar una con tinta.
  for (let p = 1; p <= Math.min(doc.numPages, 4); p++) {
    const pg = await doc.getPage(p)
    const base = pg.getViewport({ scale: 1 })
    const vp = pg.getViewport({ scale: ALTO / base.height })
    const c = createCanvas(Math.round(vp.width), Math.round(vp.height))
    const ctx = c.getContext('2d')
    ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, c.width, c.height)
    await pg.render({ canvasContext: ctx, viewport: vp }).promise
    if (tinta(ctx, c.width, c.height) > 0.004) {
      await doc.destroy()
      return { jpg: c.toBuffer('image/jpeg', CALIDAD), fuente: `página ${p} renderizada` }
    }
  }
  await doc.destroy()

  // El render salió en blanco: se intenta con las imágenes que trae dentro.
  for (const j of jpegsDe(buf).slice(0, 3)) {
    try {
      const c = encuadrar(await loadImage(j))
      if (tinta(c.getContext('2d'), c.width, c.height) > 0.004)
        return { jpg: c.toBuffer('image/jpeg', CALIDAD), fuente: 'imagen incrustada' }
    } catch { /* sigue con la siguiente */ }
  }

  return { motivo: 'El PDF se abre en blanco: no hay documento que leer.' }
}

// ── Correr sobre todos ──────────────────────────────────────────────────────
const forense = JSON.parse(readFileSync(resolve(RAIZ, 'reportes/forense/forense.json'), 'utf8'))
const salida = []
for (const [i, r] of forense.entries()) {
  const f = resolve(CACHE, r.id + '.pdf')
  const dest = resolve(DEST, r.id + '.jpg')
  if (existsSync(dest) && statSync(dest).size > 0) { salida.push({ id: r.id, ok: true, cache: true }); continue }
  if (!existsSync(f)) { salida.push({ id: r.id, ok: false, motivo: 'El archivo no se pudo descargar.' }); continue }
  try {
    const m = await miniatura(readFileSync(f))
    if (m.jpg) { writeFileSync(dest, m.jpg); salida.push({ id: r.id, ok: true, fuente: m.fuente, kb: Math.round(m.jpg.length / 1024) }) }
    else salida.push({ id: r.id, ok: false, motivo: m.motivo })
  } catch (e) {
    salida.push({ id: r.id, ok: false, motivo: 'No se pudo abrir: ' + String(e.message ?? e).slice(0, 80) })
  }
  if ((i + 1) % 50 === 0) console.log(`  ${i + 1}/${forense.length}`)
}

writeFileSync(resolve(RAIZ, 'reportes/forense/miniaturas.json'), JSON.stringify(salida, null, 1))
const ok = salida.filter((s) => s.ok).length
console.log(`\n${ok} miniaturas de ${salida.length}`)
const fallos = salida.filter((s) => !s.ok)
const porMotivo = {}
for (const f of fallos) porMotivo[f.motivo] = (porMotivo[f.motivo] ?? 0) + 1
for (const [m, n] of Object.entries(porMotivo)) console.log(`  ${n}  ${m}`)
