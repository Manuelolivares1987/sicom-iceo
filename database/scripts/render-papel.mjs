// ============================================================================
// Renderizar la página de un PDF, en vez de sacarle las imágenes incrustadas
// ----------------------------------------------------------------------------
// Extraer los JPEG que vienen dentro del PDF funciona con la mayoría de los
// escaneos, pero falla en dos casos que aparecieron en la auditoría forense:
//
//   · PDF que guarda la página partida en tiras (el RSCY-85 venía en 217
//     tiras de 140 píxeles: ninguna se puede leer sola)
//   · escaneos en blanco y negro comprimidos con CCITT o JBIG2, que no son
//     JPEG y por lo tanto no aparecen al buscar bytes FFD8
//
// Renderizando la página con pdfjs sobre un canvas se obtiene lo que se ve al
// abrir el archivo, sea cual sea cómo está guardado adentro.
//
//   node database/scripts/render-papel.mjs <id-del-certificado> [pagina] [escala]
// ============================================================================
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const RAIZ = resolve(__dirname, '../..')
const FE = resolve(RAIZ, 'frontend')

const pdfjs = await import(pathToFileURL(resolve(FE, 'node_modules/pdfjs-dist/legacy/build/pdf.mjs')).href)
const { createCanvas } = await import(pathToFileURL(resolve(FE, 'node_modules/@napi-rs/canvas/index.js')).href)

const id = process.argv[2]
const pagina = Number(process.argv[3] ?? 1)
const escala = Number(process.argv[4] ?? 2)

const DEST = resolve(RAIZ, 'reportes/forense/render')
if (!existsSync(DEST)) mkdirSync(DEST, { recursive: true })

const doc = await pdfjs.getDocument({
  data: new Uint8Array(readFileSync(resolve(RAIZ, '.cache-papeles', id + '.pdf'))),
  useSystemFonts: true, isEvalSupported: false,
  standardFontDataUrl: resolve(FE, 'node_modules/pdfjs-dist/standard_fonts') + '/',
}).promise

const p = await doc.getPage(Math.min(pagina, doc.numPages))
const vp = p.getViewport({ scale: escala })
const canvas = createCanvas(Math.round(vp.width), Math.round(vp.height))
const ctx = canvas.getContext('2d')
// Fondo blanco: un PDF sin fondo declarado se renderiza transparente y al
// guardarlo como JPEG el texto negro queda sobre negro.
ctx.fillStyle = '#fff'
ctx.fillRect(0, 0, canvas.width, canvas.height)
await p.render({ canvasContext: ctx, viewport: vp }).promise

const salida = resolve(DEST, `${id.slice(0, 8)}_p${pagina}.jpg`)
writeFileSync(salida, canvas.toBuffer('image/jpeg', 0.88))
console.log(`${salida}  ${canvas.width}x${canvas.height}  ${doc.numPages} páginas`)
await doc.destroy()
