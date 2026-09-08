#!/usr/bin/env node
// ============================================================================
// copiloto-ingesta.mjs — carga los manuales del taller al proyecto
// Supabase "copiloto-corpus" (NO a la base de SICOM producción).
// ----------------------------------------------------------------------------
// Manuel, 08-09-2026: el copiloto del taller necesita los 275 PDFs de
// manuales que viven en el Desktop (Mercedes ACTROS, Mack, IMT, etc.).
// La DB de SICOM va en 255/500 MB → el corpus vive en un proyecto paralelo.
//
// Lee el PDF por líneas reconstruidas desde la posición en página (mismo
// patrón probado en auditoria-documental.mjs — ver MIG415: leer por el orden
// interno del archivo mezcla las tablas y separa etiquetas de sus valores).
//
// Uso:
//   node copiloto-ingesta.mjs --schema              # aplica corpus_schema.sql
//   node copiloto-ingesta.mjs                       # ingesta todo el corpus
//   node copiloto-ingesta.mjs --carpeta "ACTROS"    # solo carpetas que calcen
//   node copiloto-ingesta.mjs --max 5 --dry-run     # prueba sin escribir
//
// Credenciales: database/.env.copiloto.local con
//   COPILOTO_DB_URL=postgresql://postgres:...@db.<ref>.supabase.co:5432/postgres
// ============================================================================
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { resolve, join, basename, dirname, relative } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
const FE = resolve(__dirname, '../../frontend')
const ENV_PATH = resolve(__dirname, '../.env.copiloto.local')
const SCHEMA_SQL = resolve(__dirname, '../copiloto/corpus_schema.sql')

const CORPUS_ROOT = 'C:/Users/Manuel Olivares/Desktop/OPERACIONES/00_PILLADO (PRIORIDAD)/01_OPERACIONES/Mantenimiento'

// Carpetas que se ingieren (las OS en Excel ya están en SICOM vía MIG310-314)
const CARPETAS = ['Mercedes ACTROS', 'Manuales']

const args = process.argv.slice(2)
const soloSchema = args.includes('--schema')
const dryRun = args.includes('--dry-run')

// En dry-run se puede probar el parseo sin tener aún el proyecto corpus.
if (existsSync(ENV_PATH)) dotenv.config({ path: ENV_PATH })
const DB_URL = (process.env.COPILOTO_DB_URL || '').trim()
if (!DB_URL && !dryRun) {
  console.error(`ERROR: falta COPILOTO_DB_URL (en ${ENV_PATH})`)
  console.error('Créalo con: COPILOTO_DB_URL=postgresql://... (DB del proyecto copiloto-corpus)')
  process.exit(2)
}
const filtro = args.includes('--carpeta') ? args[args.indexOf('--carpeta') + 1] : null
const maxFiles = args.includes('--max') ? Number(args[args.indexOf('--max') + 1]) : Infinity
// --dir: ingesta una carpeta arbitraria (fuera del corpus raíz), con filtro
// de nombre para quedarse con lo técnico y dejar fuera lo comercial.
const extraDir = args.includes('--dir') ? args[args.indexOf('--dir') + 1] : null
const filtroNombre = args.includes('--filtro-nombre') ? new RegExp(args[args.indexOf('--filtro-nombre') + 1], 'i') : null

// ── Clasificación por carpeta y nombre ──────────────────────────────────────
function clasificar(ruta, nombre) {
  const r = ruta.toLowerCase(); const n = nombre.toLowerCase()
  let marca = null, modelo = null, equipo = null

  if (r.includes('mercedes actros')) { marca = 'mercedes-benz'; modelo = 'actros' }
  else if (n.includes('accelo')) { marca = 'mercedes-benz'; modelo = 'accelo' }
  else if (/mack|granite|gu ?813|mdrive|maxitorque|mp8/.test(n) || r.includes('\\mack') || r.includes('/mack')) { marca = 'mack' }
  else if (/scania|p ?450/.test(n) || r.includes('scania')) { marca = 'scania'; modelo = 'p450b' }
  else if (/vm ?350/.test(n)) { marca = 'volvo'; modelo = 'vm-350' }
  else if (/fmx/.test(n) || r.includes('volvo fmx')) { marca = 'volvo'; modelo = 'fmx' }
  else if (r.includes('\\volvo') || r.includes('/volvo') || n.includes('volvo')) { marca = 'volvo' }
  else if (r.includes('renault') || n.includes('c440')) { marca = 'renault'; modelo = 'c440' }
  else if (r.includes('yale')) { marca = 'yale' }
  else if (r.includes('jpzv-22')) { marca = 'imt'; equipo = 'JPZV-22' }
  else if (n.includes('actros')) { marca = 'mercedes-benz'; modelo = 'actros' }
  else if (n.includes('atego')) { marca = 'mercedes-benz'; modelo = 'atego' }
  else if (n.includes('axor')) { marca = 'mercedes-benz'; modelo = 'axor' }
  else if (n.includes('canter')) { marca = 'mitsubishi'; modelo = 'canter' }
  else if (n.includes('np300') || n.includes('nissan')) { marca = 'nissan'; modelo = 'np300' }

  let sistema = null
  if (/caja|embrague|transmis|telligent|powershift|retardador|selectora/.test(n)) sistema = 'transmision'
  else if (/electr|fusible|diagrama|m[oó]dulo|sensor|bater|tablero|valores.reales|reprogramac|das.gs|kontact/.test(n)) sistema = 'electrico'
  else if (/freno|abs|aire.comprimido/.test(n)) sistema = 'frenos'
  else if (/motor|inyec|turbo|revoluciones/.test(n)) sistema = 'motor'
  else if (/direcci[oó]n/.test(n)) sistema = 'direccion'
  else if (/bomba|hidr[aá]ul|pto/.test(n)) sistema = 'hidraulica'
  else if (/eje|suspensi[oó]n|neum[aá]tic/.test(n)) sistema = 'tren_rodaje'
  else if (/lubric|aceite|filtro/.test(n)) sistema = 'lubricacion'
  else if (/combustible|estanque|sobrellenado/.test(n)) sistema = 'combustible'
  else if (/tac[oó]grafo/.test(n)) sistema = 'tacografo'

  let tipo = 'manual_oficial'
  if (/pauta|programa de mantenci|procedimiento|instructivo|paso a paso|check list|est[aá]ndar|prueba/.test(n)) tipo = 'procedimiento_interno'
  else if (/cat[aá]logo|partes|despiece|parts/.test(n)) tipo = 'catalogo_partes'
  else if (/ficha t[eé]cnica|specs/.test(n)) tipo = 'ficha_tecnica'

  return { marca, modelo, equipo, sistema, tipo }
}

function tipoChunk(texto) {
  if (/\d+\s*(nm|n·m|n\.m)\b/i.test(texto) || /\d+\s*(bar|psi|kpa)\b/i.test(texto)) return 'torque_presion'
  if (/atenci[oó]n|peligro|advertencia|warning/i.test(texto)) return 'advertencia'
  if (/\b[pbcu]\d{4}\b/i.test(texto) || /c[oó]digo de (falla|error|aver[ií]a)/i.test(texto)) return 'codigo_falla'
  if (/paso\s+1|procedimiento:|desmontar|montar y desmontar/i.test(texto)) return 'procedimiento'
  return 'general'
}

// ── PDF → líneas por posición (patrón auditoria-documental.mjs) ─────────────
const pdfjs = await import(pathToFileURL(resolve(FE, 'node_modules/pdfjs-dist/legacy/build/pdf.mjs')).href)

function lineasDeItems(items) {
  if (!items.some((i) => i.transform)) return [items.map((i) => i.str).join(' ')]
  const pos = items.filter((i) => (i.str ?? '').trim())
    .map((i) => ({ s: i.str, x: i.transform[4], y: Math.round(i.transform[5]) }))
  pos.sort((a, b) => b.y - a.y || a.x - b.x)
  const out = []; let ultimaY = null
  for (const o of pos) {
    if (ultimaY === null || Math.abs(ultimaY - o.y) > 4) { out.push(o.s); ultimaY = o.y }
    else out[out.length - 1] += ' ' + o.s
  }
  return out
}

async function paginasDelPdf(buf) {
  const doc = await pdfjs.getDocument({
    data: new Uint8Array(buf), useSystemFonts: true, isEvalSupported: false,
    standardFontDataUrl: `${FE}/node_modules/pdfjs-dist/standard_fonts/`,
  }).promise
  const paginas = []
  for (let p = 1; p <= doc.numPages; p++) {
    try {
      const tc = await (await doc.getPage(p)).getTextContent()
      paginas.push(lineasDeItems(tc.items).join('\n').replace(/\u0000/g, '').trim())
    } catch { paginas.push('') }
  }
  const total = doc.numPages
  try { await doc.destroy() } catch { /* ignore */ }
  return { total, paginas }
}

// Una página muy larga se parte en trozos de ~1800 chars respetando líneas
function chunksDePagina(texto) {
  if (texto.length <= 2400) return [texto]
  const lineas = texto.split('\n'); const out = []; let cur = ''
  for (const l of lineas) {
    if (cur.length + l.length > 1800 && cur.length > 400) { out.push(cur); cur = l }
    else cur = cur ? cur + '\n' + l : l
  }
  if (cur.trim()) out.push(cur)
  return out
}

// ── Recorrer corpus ─────────────────────────────────────────────────────────
function* pdfsDe(dir) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, e.name)
    if (e.isDirectory()) yield* pdfsDe(full)
    else if (/\.pdf$/i.test(e.name)) yield full
  }
}

let client = null
if (!dryRun || soloSchema) {
  client = new pg.Client({ connectionString: DB_URL, ssl: { rejectUnauthorized: false } })
  await client.connect()
  console.log('✓ conectado al proyecto copiloto-corpus')
}

if (soloSchema) {
  const sql = readFileSync(SCHEMA_SQL, 'utf8')
  const res = await client.query(sql)
  console.log('✓ corpus_schema.sql aplicado')
  if (res?.rows?.length) console.log(JSON.stringify(res.rows, null, 2))
  await client.end(); process.exit(0)
}

let archivos = []
if (extraDir) {
  if (!existsSync(extraDir)) { console.error(`ERROR: no existe ${extraDir}`); process.exit(2) }
  archivos = [...pdfsDe(extraDir)]
  if (filtroNombre) archivos = archivos.filter((a) => filtroNombre.test(basename(a)))
} else {
  for (const c of CARPETAS) {
    const dir = join(CORPUS_ROOT, c)
    if (existsSync(dir)) archivos.push(...pdfsDe(dir))
  }
}
if (filtro) archivos = archivos.filter((a) => a.toLowerCase().includes(filtro.toLowerCase()))
// Mercedes primero (el caso del camión 42 es eléctrico y la flota es mayormente MB)
archivos.sort((a, b) => (a.includes('Mercedes ACTROS') ? 0 : 1) - (b.includes('Mercedes ACTROS') ? 0 : 1))
archivos = archivos.slice(0, maxFiles)

console.log(`Corpus: ${archivos.length} PDFs a procesar${dryRun ? ' (DRY-RUN)' : ''}`)

let ok = 0, saltados = 0, sinTexto = 0, errores = 0, chunksTotal = 0
const t0 = Date.now()

for (const [i, ruta] of archivos.entries()) {
  const nombre = basename(ruta)
  const rel = relative(extraDir ?? CORPUS_ROOT, ruta)
  try {
    const buf = readFileSync(ruta)
    const hash = createHash('sha256').update(buf).digest('hex')

    if (client) {
      const dup = await client.query('SELECT id FROM copiloto_documentos WHERE hash = $1', [hash])
      if (dup.rows.length > 0) { saltados++; continue }
    }

    const { marca, modelo, equipo, sistema, tipo } = clasificar(rel, nombre)
    const titulo = nombre.replace(/\.pdf$/i, '').replace(/[_-]+/g, ' ').replace(/\s+/g, ' ').trim()

    const { total, paginas } = await paginasDelPdf(buf)
    const conTexto = paginas.filter((p) => p.length >= 40).length

    if (conTexto === 0) {
      sinTexto++
      console.log(`  [${i + 1}/${archivos.length}] ESCANEADO (sin texto): ${nombre}`)
      if (!dryRun) {
        // Documento escaneado: queda encontrable por su título para que el
        // copiloto pueda decir «este manual existe, está escaneado» en vez de
        // «no hay nada». El OCR es fase 2.
        await client.query('BEGIN')
        const doc = await client.query(
          `INSERT INTO copiloto_documentos (titulo, archivo, ruta_origen, hash, tipo_documento, marca, modelo, sistema, equipo, paginas, paginas_con_texto)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,0) RETURNING id`,
          [titulo, nombre, rel, hash, tipo, marca, modelo, sistema, equipo, total])
        await client.query(
          `INSERT INTO copiloto_chunks (documento_id, pagina, chunk_index, contenido, tipo_chunk)
           VALUES ($1, 1, 0, $2, 'general')`,
          [doc.rows[0].id,
           `[DOCUMENTO ESCANEADO — el texto no es extraíble todavía] Título: ${titulo}. ` +
           `${marca ? `Marca: ${marca}. ` : ''}${sistema ? `Sistema: ${sistema}. ` : ''}` +
           `Este manual existe en el corpus (${total} páginas) pero es un escaneo: si el tema calza, indícale al mecánico que el documento «${titulo}» existe y que lo pida al jefe de taller.`])
        await client.query('COMMIT')
      }
      continue
    }

    let nChunks = 0
    if (!dryRun) {
      await client.query('BEGIN')
      const doc = await client.query(
        `INSERT INTO copiloto_documentos (titulo, archivo, ruta_origen, hash, tipo_documento, marca, modelo, sistema, equipo, paginas, paginas_con_texto)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id`,
        [titulo, nombre, rel, hash, tipo, marca, modelo, sistema, equipo, total, conTexto])
      const docId = doc.rows[0].id

      const filas = []
      paginas.forEach((texto, idx) => {
        if (texto.length < 40) return
        chunksDePagina(texto).forEach((chunk, j) => {
          filas.push([docId, idx + 1, j, chunk, tipoChunk(chunk)])
        })
      })
      for (let b = 0; b < filas.length; b += 200) {
        const lote = filas.slice(b, b + 200)
        const values = lote.map((_, k) => `($${k * 5 + 1},$${k * 5 + 2},$${k * 5 + 3},$${k * 5 + 4},$${k * 5 + 5})`).join(',')
        await client.query(
          `INSERT INTO copiloto_chunks (documento_id, pagina, chunk_index, contenido, tipo_chunk) VALUES ${values}`,
          lote.flat())
      }
      await client.query('COMMIT')
      nChunks = filas.length
    } else {
      paginas.forEach((t) => { if (t.length >= 40) nChunks += chunksDePagina(t).length })
    }

    ok++; chunksTotal += nChunks
    console.log(`  [${i + 1}/${archivos.length}] OK ${nombre} — ${total} págs, ${nChunks} chunks${marca ? `, ${marca}` : ''}${sistema ? `/${sistema}` : ''}`)
  } catch (err) {
    errores++
    try { await client.query('ROLLBACK') } catch { /* ignore */ }
    console.error(`  [${i + 1}/${archivos.length}] ✗ ${nombre}: ${err.message}`)
  }
}

console.log('═'.repeat(70))
console.log(`Ingesta: ${ok} OK · ${saltados} ya cargados · ${sinTexto} escaneados sin texto · ${errores} errores`)
console.log(`Chunks nuevos: ${chunksTotal.toLocaleString()} · ${Math.round((Date.now() - t0) / 1000)}s`)
if (client) {
  if (!dryRun) {
    const size = await client.query(`SELECT pg_size_pretty(pg_database_size(current_database())) AS s`)
    console.log(`Tamaño DB copiloto-corpus: ${size.rows[0].s}`)
  }
  await client.end()
}
