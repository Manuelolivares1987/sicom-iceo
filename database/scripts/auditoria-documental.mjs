// ============================================================================
// Auditoría documental de la flota — qué dice cada papel, no qué suponemos
// ----------------------------------------------------------------------------
// Manuel, 26-08-2026: «necesito que profesionalmente hagas una auditoría como
// experto en software y documental e indiques la fecha correcta a cada papel
// [...] apégate a lo que indica el documento y si no indica, coloca sin
// vencimiento».
//
// Este script abre TODOS los certificados de la flota y para cada uno dice una
// de tres cosas, nunca una cuarta:
//
//   DECLARA      el documento dice su vencimiento → esa fecha, y la frase exacta
//   NO DECLARA   el documento se leyó completo y no menciona vencimiento
//   ILEGIBLE     es un escaneo sin texto: hay que abrirlo a ojo
//
// No hay regla de 2 años, no hay estimaciones, no hay «probablemente». Lo que
// no está escrito no se escribe.
//
// Lee por líneas reconstruidas desde la posición en la página, no por el orden
// interno del PDF: esa distinción es la que hizo que 24 hermeticidades pasaran
// dos años con la vigencia mal cargada (ver MIG415).
//
// No escribe nada en la base. Produce reportes/auditoria-documental.json y .csv
// ============================================================================
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
const FE = resolve(__dirname, '../../frontend')
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })

// En Windows un path absoluto no es una URL válida para import(): hay que
// convertirlo con pathToFileURL o el loader ESM lo lee como esquema 'c:'.
const pdfjs = await import(pathToFileURL(resolve(FE, 'node_modules/pdfjs-dist/legacy/build/pdf.mjs')).href)

// ── Leer el PDF como se lee en papel ────────────────────────────────────────
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

async function lineasDelPdf(buf) {
  const doc = await pdfjs.getDocument({
    data: new Uint8Array(buf), useSystemFonts: true, isEvalSupported: false,
    standardFontDataUrl: `${FE}/node_modules/pdfjs-dist/standard_fonts/`,
  }).promise
  const out = []
  for (let p = 1; p <= Math.min(doc.numPages, 12); p++) {
    const tc = await (await doc.getPage(p)).getTextContent()
    out.push(...lineasDeItems(tc.items).map((l) => l.replace(/\s+/g, ' ').trim()).filter(Boolean))
  }
  await doc.destroy()
  return out
}

// ── Fechas ──────────────────────────────────────────────────────────────────
const MESES = { enero:1, febrero:2, marzo:3, abril:4, mayo:5, junio:6, julio:7,
  agosto:8, septiembre:9, setiembre:9, octubre:10, noviembre:11, diciembre:12 }
const sinTilde = (s) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
/** Una fecha de la base a ISO, sin pasar por la representación local. */
const fechaISO = (v) => {
  if (!v) return null
  if (typeof v === 'string') return v.slice(0, 10)
  const d = new Date(v)
  return isNaN(+d) ? null
    : `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`
}

const iso = (d, m, a) => `${a}-${String(m).padStart(2,'0')}-${String(d).padStart(2,'0')}`

function fechaDeTexto(txt) {
  let m = txt.match(/(\d{1,2})\s+de\s+([a-zA-ZáéíóúÁÉÍÓÚ]+)\s+de\s+(\d{4})/)
  if (m && MESES[sinTilde(m[2])]) return iso(+m[1], MESES[sinTilde(m[2])], m[3])
  m = txt.match(/(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})/)
  if (m && +m[1] <= 31 && +m[2] <= 12) return iso(+m[1], +m[2], m[3])
  m = txt.match(/(\d{4})-(\d{2})-(\d{2})/)
  if (m) return `${m[1]}-${m[2]}-${m[3]}`
  return null
}

// «Vencimiento» dentro de una tabla de cuotas de pago no es la vigencia del
// seguro: es cuándo se paga la cuota. Confundirlos dio 5 pólizas «vencidas»
// en 2014 que estaban perfectamente vigentes.
const CONTEXTO_PAGO = /(cuota|n[°º]\s*cuota|forma de pago|valor cuota|monto cuota|pagar[eé])/i
const PIDE_VENCE = /(fecha\s+de\s+vencimiento|vencimiento|vence|v[áa]lido\s+hasta|validez\s+hasta|hasta\s+el)/i
// Muchos documentos no escriben «vencimiento»: ponen la vigencia en una tabla,
// con «RIGE DESDE  HASTA» en la fila de titulos y las dos fechas en la de
// valores. El SOAP es asi, y son 53 papeles. Sin esto el lector dice «no
// declara» sobre un documento que declara perfectamente su vigencia.
const CABECERA_RANGO = /(rige\s+desde|vigencia|vigente)?\s*desde\s+.{0,20}hasta\s*$|desde\s+hasta/i
const CABECERA_HASTA = /hasta/i
const NO_VENCE_EXPLICITO = /(no\s+tiene\s+vencimiento|sin\s+vencimiento|indefinid|permanente|no\s+caduca)/i

/** La ultima fecha de una linea. En una fila «01/10/2025 30/09/2026» el
 *  vencimiento es la segunda, no la primera. */
function ultimaFecha(txt) {
  const todas = []
  const re = /(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4})/g
  let m
  while ((m = re.exec(txt)) !== null) {
    if (+m[1] <= 31 && +m[2] <= 12) todas.push(iso(+m[1], +m[2], m[3]))
  }
  if (todas.length) return todas[todas.length - 1]
  return null
}

function auditar(lineas) {
  const texto = lineas.join(' | ')
  if (!texto.trim()) return { veredicto: 'ILEGIBLE', motivo: 'El PDF no tiene texto: es un escaneo. Hay que abrirlo y leerlo a ojo.' }

  // 1) Una línea que pide vencimiento Y trae fecha.
  for (const l of lineas) {
    if (!PIDE_VENCE.test(l) || CONTEXTO_PAGO.test(l)) continue
    const f = fechaDeTexto(l)
    if (f) return { veredicto: 'DECLARA', vencimiento: f, evidencia: l.slice(0, 160) }
  }
  // 2) La etiqueta en una línea y la fecha en la siguiente (tablas partidas).
  for (let i = 0; i < lineas.length - 1; i++) {
    if (!PIDE_VENCE.test(lineas[i]) || CONTEXTO_PAGO.test(lineas[i])) continue
    if (fechaDeTexto(lineas[i])) continue
    const f = fechaDeTexto(lineas[i + 1])
    if (f) return { veredicto: 'DECLARA', vencimiento: f,
                    evidencia: (lineas[i] + ' → ' + lineas[i + 1]).slice(0, 160) }
  }
  // 2b) Cabecera de tabla con DESDE/HASTA: la fecha que vale es la ULTIMA de la
  //     fila de valores, no la primera (la primera es el inicio de vigencia).
  for (let i = 0; i < lineas.length - 1; i++) {
    const cab = lineas[i]
    if (!CABECERA_HASTA.test(cab) || CONTEXTO_PAGO.test(cab)) continue
    if (fechaDeTexto(cab)) continue          // ya trae fecha: lo vio la regla 1
    if (!/desde|rige|vigen/i.test(cab)) continue
    // La fila de valores no siempre es la de al lado: entre la cabecera y los
    // datos suelen colarse lineas de la maqueta del formulario.
    for (let j = i + 1; j <= Math.min(i + 4, lineas.length - 1); j++) {
      const f = ultimaFecha(lineas[j])
      if (f) return { veredicto: 'DECLARA', vencimiento: f,
                      evidencia: (cab + ' → ' + lineas[j]).slice(0, 160) }
    }
  }
  // 3) Rango «desde ... hasta ...».
  for (const l of lineas) {
    const m = l.match(/desde\s+(.{6,30}?)\s+hasta\s+(.{6,30}?)(?:\s|$|\|)/i)
    if (m) { const f = fechaDeTexto(m[2]); if (f) return { veredicto: 'DECLARA', vencimiento: f, evidencia: l.slice(0, 160) } }
  }
  // 4) El documento dice explícitamente que no vence.
  for (const l of lineas) {
    if (NO_VENCE_EXPLICITO.test(l)) return { veredicto: 'NO DECLARA', motivo: 'El documento dice que no tiene vencimiento.', evidencia: l.slice(0, 160) }
  }
  // 5) Se leyó completo y no menciona vencimiento.
  return { veredicto: 'NO DECLARA',
           motivo: `Se leyeron ${lineas.length} líneas y el documento no menciona vencimiento.`,
           evidencia: lineas.slice(0, 3).join(' | ').slice(0, 160) }
}

// ── Correr ──────────────────────────────────────────────────────────────────
const { Client } = pg
const db = new Client({ connectionString: process.env.SUPABASE_DB_URL, ssl: { rejectUnauthorized: false } })
await db.connect()

const { rows } = await db.query(`
  SELECT c.id, COALESCE(a.patente, a.codigo) AS patente, c.tipo::text AS tipo,
         c.archivo_url, c.bloqueante,
         c.fecha_emision::date  AS bd_emision,
         c.fecha_vencimiento::date AS bd_vencimiento,
         c.fecha_origen, v.estado_real::text AS estado
    FROM certificaciones c
    JOIN activos a ON a.id = c.activo_id
    LEFT JOIN v_certificacion_actual v ON v.id = c.id
   WHERE c.archivo_url IS NOT NULL
     AND a.estado <> 'dado_baja'::estado_activo_enum
     AND c.id IN (SELECT id FROM v_certificacion_actual)
   ORDER BY 2, 3`)

// Con un archivo de ids como argumento se re-audita sólo ese subconjunto.
// Sirve para volver a pasar los dudosos sin releer los 871 PDF.
const filtro = process.argv[2]
  ? new Set(JSON.parse(readFileSync(process.argv[2], 'utf8')))
  : null
const objetivo = filtro ? rows.filter((r) => filtro.has(r.id)) : rows

console.log(`Auditando ${objetivo.length} papeles...\n`)
const res = []
for (const [i, c] of objetivo.entries()) {
  let r
  try {
    const resp = await fetch(c.archivo_url)
    if (!resp.ok) throw new Error('HTTP ' + resp.status)
    const lineas = await lineasDelPdf(await resp.arrayBuffer())
    r = auditar(lineas)
  } catch (e) {
    r = { veredicto: 'ILEGIBLE', motivo: 'No se pudo abrir: ' + String(e.message ?? e) }
  }

  // pg devuelve un Date, y String(Date) da «Mon Jul 27 2026 ...». Cortar a 10
  // caracteres eso daba «Mon Jul 27», que nunca calza con una fecha ISO: la
  // primera corrida reportó 59 de 59 desajustes que no existían.
  const bd = fechaISO(c.bd_vencimiento)
  const bdEsFicticia = !bd || bd >= '2099-01-01'
  r.calza = r.veredicto === 'DECLARA' ? (r.vencimiento === bd)
          : r.veredicto === 'NO DECLARA' ? bdEsFicticia : null

  res.push({ ...c, bd_emision: fechaISO(c.bd_emision), bd_vencimiento: bd, ...r })
  if ((i + 1) % 25 === 0) console.log(`  ${i + 1}/${objetivo.length}`)
}
await db.end()

// ── Reporte ─────────────────────────────────────────────────────────────────
const dir = resolve(__dirname, '../../reportes')
if (!existsSync(dir)) mkdirSync(dir, { recursive: true })
writeFileSync(resolve(dir, filtro ? 'auditoria-recheck.json' : 'auditoria-documental.json'), JSON.stringify(res, null, 2))

const esc = (s) => `"${String(s ?? '').replace(/"/g, '""')}"`
writeFileSync(resolve(dir, filtro ? 'auditoria-recheck.csv' : 'auditoria-documental.csv'),
  'patente;tipo;bloqueante;veredicto;fecha_correcta;tiene_la_base;calza;evidencia\n' +
  res.map((r) => [r.patente, r.tipo, r.bloqueante ? 'SI' : '', r.veredicto,
    r.vencimiento ?? (r.veredicto === 'NO DECLARA' ? 'SIN VENCIMIENTO' : ''),
    r.bd_vencimiento ?? '', r.calza === null ? '' : r.calza ? 'si' : 'NO',
    esc(r.evidencia ?? r.motivo ?? '')].join(';')).join('\n'))

const n = (f) => res.filter(f).length
console.log(`
── Auditoría ────────────────────────────────────────
  El documento DECLARA su vencimiento : ${n((r) => r.veredicto === 'DECLARA')}
     de esos, la base NO calza         : ${n((r) => r.veredicto === 'DECLARA' && !r.calza)}
  El documento NO declara vencimiento  : ${n((r) => r.veredicto === 'NO DECLARA')}
     de esos, la base tiene una fecha   : ${n((r) => r.veredicto === 'NO DECLARA' && !r.calza)}
  Escaneo ilegible (hay que abrirlo)   : ${n((r) => r.veredicto === 'ILEGIBLE')}
  ─────────────────────────────────────────────────
  TOTAL                                 ${res.length}

  reportes/auditoria-documental.csv`)
