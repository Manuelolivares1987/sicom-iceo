#!/usr/bin/env node
// ============================================================================
// copiloto-ocr.mjs — transcribe con Claude Vision los PDF escaneados del
// corpus (paginas_con_texto = 0) para que el copiloto pueda leerlos.
// ----------------------------------------------------------------------------
// El dolor #1 del taller es eléctrico y justo los diagramas de fusibles
// (ocupación GM del Actros, caja MP8 del Mack, errores DAS) son escaneos sin
// capa de texto. Claude lee el PDF completo como documento (visión nativa,
// hasta 100 págs / 32 MB) y devuelve la transcripción página por página, que
// reemplaza al chunk-placeholder en el corpus.
//
// Uso:
//   node copiloto-ocr.mjs                # solo los escaneados de alto valor
//   node copiloto-ocr.mjs --todos        # todos los escaneados
//   node copiloto-ocr.mjs --max 3        # límite de documentos
//   node copiloto-ocr.mjs --dry-run      # lista qué haría, sin llamar a la IA
//
// Credenciales: COPILOTO_DB_URL en database/.env.copiloto.local y
// ANTHROPIC_API_KEY (misma de frontend/.env.local).
// ============================================================================
import { readFileSync, existsSync } from 'node:fs'
import { resolve, join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'
import dotenv from 'dotenv'
import Anthropic from '@anthropic-ai/sdk'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../.env.copiloto.local') })
if (!process.env.ANTHROPIC_API_KEY) {
  const feEnv = resolve(__dirname, '../../frontend/.env.local')
  if (existsSync(feEnv)) {
    const m = readFileSync(feEnv, 'utf8').match(/^ANTHROPIC_API_KEY=(.*)$/m)
    if (m) process.env.ANTHROPIC_API_KEY = m[1].trim()
  }
}
if (!process.env.COPILOTO_DB_URL || !process.env.ANTHROPIC_API_KEY) {
  console.error('Faltan COPILOTO_DB_URL y/o ANTHROPIC_API_KEY'); process.exit(2)
}

const args = process.argv.slice(2)
const todos = args.includes('--todos')
const dryRun = args.includes('--dry-run')
const maxDocs = args.includes('--max') ? Number(args[args.indexOf('--max') + 1]) : Infinity

// Dónde puede vivir el archivo según de qué ingesta vino (ruta_origen es
// relativa a la raíz que se usó en cada corrida)
const RAICES = [
  'C:/Users/Manuel Olivares/Desktop/OPERACIONES/00_PILLADO (PRIORIDAD)/01_OPERACIONES/Mantenimiento',
  'C:/Users/Manuel Olivares/Desktop/OPERACIONES/00_PILLADO (PRIORIDAD)/01_OPERACIONES/Mantenimiento/Manuales/_Descargados oficiales 2026-09',
  'C:/Users/Manuel Olivares/Desktop/OPERACIONES/02_FLOTA Y EQUIPOS/PATENTES/DOCUMETACIÓN CAMIÓN',
  'C:/Users/Manuel Olivares/Desktop/OPERACIONES/02_FLOTA Y EQUIPOS/LUBRICANTES',
]
function localizar(rutaOrigen) {
  for (const r of RAICES) {
    const p = join(r, rutaOrigen)
    if (existsSync(p)) return p
  }
  return null
}

// Lo eléctrico/diagramas primero: es el caso del camión 42
const ALTO_VALOR = /fusib|fuse|electr|diagrama|das|error|reprogramac|scania|mp8|rele|relé/i

function tipoChunk(texto) {
  if (/\d+\s*(nm|n·m|n\.m)\b/i.test(texto) || /\d+\s*(bar|psi|kpa)\b/i.test(texto)) return 'torque_presion'
  if (/atenci[oó]n|peligro|advertencia|warning/i.test(texto)) return 'advertencia'
  if (/\b[pbcu]\d{4}\b/i.test(texto) || /c[oó]digo de (falla|error|aver[ií]a)/i.test(texto)) return 'codigo_falla'
  return 'general'
}
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

const client = new pg.Client({ connectionString: process.env.COPILOTO_DB_URL, ssl: { rejectUnauthorized: false } })
await client.connect()
const anthropic = new Anthropic()

const { rows: docs } = await client.query(
  `SELECT id, titulo, archivo, ruta_origen, paginas, marca, sistema
     FROM copiloto_documentos
    WHERE paginas_con_texto = 0
    ORDER BY created_at`)

let candidatos = docs.filter((d) => todos || ALTO_VALOR.test(d.titulo + ' ' + d.archivo))
  .filter((d) => !/ruso/i.test(d.archivo))          // el manual Yale en ruso no ayuda
candidatos = candidatos.slice(0, maxDocs)

console.log(`Escaneados en corpus: ${docs.length} · candidatos${todos ? '' : ' (alto valor)'}: ${candidatos.length}${dryRun ? ' (DRY-RUN)' : ''}`)

let ok = 0, saltados = 0, errores = 0, inTok = 0, outTok = 0
for (const [i, d] of candidatos.entries()) {
  const ruta = localizar(d.ruta_origen)
  if (!ruta) { console.log(`  [${i + 1}] SIN ARCHIVO LOCAL: ${d.archivo}`); saltados++; continue }
  const buf = readFileSync(ruta)
  if (buf.length > 30_000_000 || (d.paginas ?? 0) > 90) {
    console.log(`  [${i + 1}] MUY GRANDE (${Math.round(buf.length / 1048576)}MB/${d.paginas}p): ${d.archivo}`); saltados++; continue
  }
  console.log(`  [${i + 1}/${candidatos.length}] ${d.titulo.slice(0, 70)} — ${d.paginas} págs, ${Math.round(buf.length / 1024)}KB`)
  if (dryRun) continue

  try {
    const stream = anthropic.messages.stream({
      model: 'claude-opus-5',
      max_tokens: 32000,
      messages: [{
        role: 'user',
        content: [
          { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: buf.toString('base64') } },
          { type: 'text', text:
            'Este es un documento técnico de taller ESCANEADO. Transcribe fielmente TODO el texto legible, página por página, en el idioma original.\n' +
            'Formato: una línea "=== PÁGINA N ===" y debajo el contenido de esa página.\n' +
            'Tablas (fusibles, relés, códigos, torques): transcríbelas completas, una fila por línea con "etiqueta | valor | valor".\n' +
            'Números, amperajes y códigos EXACTOS como aparecen. No resumas, no omitas, no inventes: si algo no se lee, escribe [ilegible]. Si una página es solo una imagen sin texto, descríbela en una línea: [Diagrama: ...].' },
        ],
      }],
    })
    const final = await stream.finalMessage()
    const texto = final.content.filter((b) => b.type === 'text').map((b) => b.text).join('\n')
    inTok += final.usage.input_tokens; outTok += final.usage.output_tokens

    // Partir por página y reemplazar los chunks del documento
    const paginas = []
    for (const m of texto.split(/===\s*P[ÁA]GINA\s+(\d+)\s*===/i).slice(1).reduce((acc, v, idx, arr) => {
      if (idx % 2 === 0) acc.push({ n: Number(v), t: (arr[idx + 1] ?? '').trim() })
      return acc
    }, [])) paginas.push(m)

    if (paginas.length === 0 && texto.trim().length > 100) paginas.push({ n: 1, t: texto.trim() })
    const conTexto = paginas.filter((p) => p.t.length >= 40)
    if (conTexto.length === 0) { console.log('      sin texto útil transcrito'); saltados++; continue }

    await client.query('BEGIN')
    await client.query('DELETE FROM copiloto_chunks WHERE documento_id = $1', [d.id])
    const filas = []
    for (const p of conTexto) {
      chunksDePagina(p.t).forEach((chunk, j) => filas.push([d.id, p.n, j, chunk, tipoChunk(chunk)]))
    }
    for (let b = 0; b < filas.length; b += 200) {
      const lote = filas.slice(b, b + 200)
      const values = lote.map((_, k) => `($${k * 5 + 1},$${k * 5 + 2},$${k * 5 + 3},$${k * 5 + 4},$${k * 5 + 5})`).join(',')
      await client.query(`INSERT INTO copiloto_chunks (documento_id, pagina, chunk_index, contenido, tipo_chunk) VALUES ${values}`, lote.flat())
    }
    await client.query(`UPDATE copiloto_documentos SET paginas_con_texto = $2 WHERE id = $1`, [d.id, conTexto.length])
    await client.query('COMMIT')
    ok++
    console.log(`      ✓ ${conTexto.length} páginas transcritas, ${filas.length} chunks (${final.usage.input_tokens}/${final.usage.output_tokens} tok)`)
  } catch (err) {
    errores++
    try { await client.query('ROLLBACK') } catch { /* ignore */ }
    console.error(`      ✗ ${err.message?.slice(0, 160)}`)
  }
}

const costo = inTok * 5 / 1e6 + outTok * 25 / 1e6
console.log('═'.repeat(70))
console.log(`OCR: ${ok} OK · ${saltados} saltados · ${errores} errores`)
console.log(`Tokens: ${inTok.toLocaleString()} in / ${outTok.toLocaleString()} out ≈ US$${costo.toFixed(2)}`)
await client.end()
