#!/usr/bin/env node
// ============================================================================
// copiloto-conocimiento.mjs — carga al corpus lo investigado en la web
// (19-09-2026) y la ficha técnica de cada camión.
// ----------------------------------------------------------------------------
// Manuel, 19-09-2026: «consigue información técnica de toda la flota pesada
// para mejorar el diagnóstico, ejemplo diagramas eléctricos».
//
// Fuentes (en database/copiloto/conocimiento/):
//   <marca>.md            fichas "## [sistema] Título" con Aplica/Tipo/
//                         Confiabilidad/Fuente → un chunk por ficha, con su URL
//   codigos/<marca>.json  códigos de falla → copiloto_codigos_falla
//   fichas_familias.json  motor/caja/ECUs/lectura de códigos por familia
//   flota_pesada.json     export de la Biblioteca Maestra (hoja Flota_Pesada)
//                         → copiloto_fichas_equipo (una fila por patente)
// + manifiestos _descargas.json de las carpetas de descarga → url_fuente de
//   los PDFs ya ingeridos (la app enlaza la página citada al documento oficial)
//
// Uso:
//   node copiloto-conocimiento.mjs --schema-v2        # aplica corpus_schema_v2.sql
//   node copiloto-conocimiento.mjs --fichas [flota_pesada.json]
//   node copiloto-conocimiento.mjs --conocimiento
//   node copiloto-conocimiento.mjs --codigos
//   node copiloto-conocimiento.mjs --urls
//   node copiloto-conocimiento.mjs --aportes          # baja PDFs y fotos que los mecánicos
//                                                     # propusieron a la biblioteca
//   node copiloto-conocimiento.mjs --todo              # todo lo anterior salvo schema
//   ... --dry-run                                      # parsea y cuenta, no escribe
//
// Idempotente: cada archivo de conocimiento/códigos se reemplaza completo al
// reingestarlo (se identifica por su nombre), así se puede corregir y volver
// a correr sin duplicar.
// ============================================================================
import { readFileSync, existsSync, readdirSync, mkdirSync, writeFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { resolve, join, dirname, basename } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
const BASE = resolve(__dirname, '../copiloto')
const DIR_CONOC = join(BASE, 'conocimiento')
const DIR_COD = join(DIR_CONOC, 'codigos')
const MANUALES = 'C:/Users/Manuel Olivares/Desktop/OPERACIONES/00_PILLADO (PRIORIDAD)/01_OPERACIONES/Mantenimiento/Manuales'

dotenv.config({ path: resolve(__dirname, '../.env.copiloto.local') })
const args = process.argv.slice(2)
const dryRun = args.includes('--dry-run')
const todo = args.includes('--todo')
const hacer = (f) => todo || args.includes(f)
const argDe = (f) => {
  const i = args.indexOf(f)
  return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : null
}

const DB_URL = (process.env.COPILOTO_DB_URL || '').trim()
if (!DB_URL && !dryRun) { console.error('Falta COPILOTO_DB_URL en database/.env.copiloto.local'); process.exit(2) }

let client = null
async function db() {
  if (dryRun) return null
  if (!client) {
    client = new pg.Client({ connectionString: DB_URL, ssl: { rejectUnauthorized: false } })
    await client.connect()
  }
  return client
}

// Marca del corpus por nombre de archivo. Los componentes, Allison y la
// metodología quedan genéricos (marca NULL): aplican a toda la flota.
const MARCA_ARCHIVO = {
  'mercedes-benz': 'mercedes-benz', mack: 'mack', volvo: 'volvo', renault: 'renault',
  scania: 'scania', wabco: null, allison: null, 'j1939-generico': null,
  'componentes-implementos': null, 'metodologia-diagnostico': null, implementos: null,
}
const marcaDe = (nombre) => (nombre in MARCA_ARCHIVO ? MARCA_ARCHIVO[nombre] : null)
const MARCAS_CAMION = ['mercedes-benz', 'mack', 'volvo', 'renault', 'scania']

const SISTEMAS_OK = new Set(['electrico', 'motor', 'transmision', 'frenos', 'hidraulica', 'direccion',
  'tren_rodaje', 'combustible', 'postratamiento', 'implemento', 'general', 'lubricacion'])
const TIPOS_CHUNK = new Set(['codigo_falla', 'fusibles_reles', 'diagrama_electrico', 'pinout_conector',
  'arquitectura_can', 'procedimiento_diagnostico', 'falla_conocida', 'especificacion',
  'boletin_recall', 'lectura_codigos_tablero'])

// ── Fichas markdown ─────────────────────────────────────────────────────────
function parsearFichas(md) {
  const fichas = []
  const bloques = md.split(/^## /m).slice(1)
  for (const b of bloques) {
    const [cab, ...resto] = b.split('\n')
    const cuerpo = resto.join('\n').trim()
    const m = cab.match(/^\[([^\]]+)\]\s*(.+)$/)
    const sistema = m ? m[1].trim().toLowerCase() : null
    const titulo = (m ? m[2] : cab).trim()
    const campo = (k) => cuerpo.match(new RegExp(`^-\\s*${k}\\s*:\\s*(.+)$`, 'mi'))?.[1]?.trim() ?? null
    const tipo = campo('Tipo')?.toLowerCase().split(/[\s|,]/)[0] ?? null
    const conf = campo('Confiabilidad')?.toLowerCase().match(/oficial|tecnica_terceros|experiencia_campo/)?.[0] ?? 'tecnica_terceros'
    const fuente = campo('Fuente')
    const url = fuente?.match(/https?:\/\/[^\s)>\]]+/)?.[0] ?? null
    if (!cuerpo || cuerpo.length < 40) continue
    fichas.push({
      titulo, sistema: SISTEMAS_OK.has(sistema) ? sistema : null,
      tipoChunk: TIPOS_CHUNK.has(tipo) ? tipo : 'general',
      confiabilidad: conf, url,
      // El contenido lleva el título y los metadatos: así la FTS los encuentra
      // y Claude ve Aplica/Fuente al citar.
      contenido: `${titulo}${sistema ? ` [${sistema}]` : ''}\n${cuerpo}`.slice(0, 6000),
    })
  }
  return fichas
}

async function cargarConocimiento() {
  const archivos = readdirSync(DIR_CONOC).filter((f) => f.endsWith('.md') && !f.startsWith('_'))
  let totalFichas = 0
  for (const f of archivos) {
    const nombre = f.replace(/\.md$/, '')
    const md = readFileSync(join(DIR_CONOC, f), 'utf8')
    const fichas = parsearFichas(md)
    totalFichas += fichas.length
    const porConf = new Map()
    for (const x of fichas) {
      if (!porConf.has(x.confiabilidad)) porConf.set(x.confiabilidad, [])
      porConf.get(x.confiabilidad).push(x)
    }
    console.log(`  ${f}: ${fichas.length} fichas (${[...porConf].map(([k, v]) => `${k} ${v.length}`).join(', ')})`)
    const c = await db(); if (!c) continue

    await c.query('BEGIN')
    // Reemplazo completo del archivo (idempotente al corregir y reingestar)
    await c.query(`DELETE FROM copiloto_documentos WHERE archivo LIKE $1`, [`conocimiento/${f}#%`])
    const marca = marcaDe(nombre)
    for (const [conf, lista] of porConf) {
      const archivo = `conocimiento/${f}#${conf}`
      const hash = createHash('sha256').update(archivo + JSON.stringify(lista)).digest('hex')
      const titulo = `Guía técnica ${nombre.replace(/-/g, ' ')} — investigación web 2026-09 (${conf.replace('_', ' ')})`
      const doc = await c.query(
        `INSERT INTO copiloto_documentos (titulo, archivo, ruta_origen, hash, tipo_documento, marca, paginas,
                                          paginas_con_texto, confiabilidad, idioma)
         VALUES ($1,$2,'database/copiloto/conocimiento',$3,'guia_tecnica_web',$4,$5,$5,$6,'es') RETURNING id`,
        [titulo, archivo, hash, marca, lista.length, conf])
      const docId = doc.rows[0].id
      for (let b = 0; b < lista.length; b += 100) {
        const lote = lista.slice(b, b + 100)
        const vals = lote.map((_, k) => `($${k * 5 + 1},$${k * 5 + 2},0,$${k * 5 + 3},$${k * 5 + 4},$${k * 5 + 5})`).join(',')
        // pagina = número de ficha dentro del documento (cita estable)
        await c.query(
          `INSERT INTO copiloto_chunks (documento_id, pagina, chunk_index, contenido, tipo_chunk, url_fuente) VALUES ${vals}`,
          lote.flatMap((x, k) => [docId, b + k + 1, x.contenido, x.tipoChunk, x.url]))
      }
    }
    await c.query('COMMIT')
  }
  console.log(`✓ conocimiento: ${archivos.length} archivos, ${totalFichas} fichas`)
}

// ── Códigos de falla ────────────────────────────────────────────────────────
const norm = (s) => String(s ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '')
function spnFmi(codigo, formato) {
  const s = String(codigo)
  const spn = s.match(/SPN\s*[:#-]?\s*(\d+)/i)?.[1]
  const fmi = s.match(/FMI\s*[:#-]?\s*(\d+)/i)?.[1]
  if (spn) return { spn: +spn, fmi: fmi != null ? +fmi : null }
  if (/SPN/i.test(formato ?? '')) {
    const n = s.match(/(\d+)\D+(\d+)/)
    if (n) return { spn: +n[1], fmi: +n[2] <= 31 ? +n[2] : null }
    const u = s.match(/(\d+)/)
    if (u) return { spn: +u[1], fmi: null }
  }
  return { spn: null, fmi: null }
}

// "GS 06 a GS 18, GS 27, GS 29" → GS 06, GS 07, … GS 18, GS 27, GS 29: cada
// código queda buscable por sí solo (el mecánico escribe "GS 12").
function expandirRango(codigo) {
  if (!/\d\s*(a|-|–)\s*[A-Z]*\s*\d|,/i.test(codigo) || /spn|fmi|mid|pid|sid/i.test(codigo)) return [codigo]
  const out = []
  for (const parte of codigo.split(',').map((s) => s.trim()).filter(Boolean)) {
    const m = parte.match(/^([A-Z]+)\s*(\d+)\s*(?:a|-|–)\s*(?:\1)?\s*(\d+)$/i)
    if (m) {
      const [, pre, a, b] = m
      const ancho = a.length
      for (let n = Number(a); n <= Number(b) && out.length < 60; n++) out.push(`${pre} ${String(n).padStart(ancho, '0')}`)
    } else if (/^[A-Z]+\s*\d+$/i.test(parte)) out.push(parte)
    else return [codigo]   // formato que no entiendo: se deja tal cual
  }
  return out.length ? out : [codigo]
}

async function cargarCodigos() {
  if (!existsSync(DIR_COD)) { console.log('  (sin carpeta codigos/)'); return }
  const archivos = readdirSync(DIR_COD).filter((f) => f.endsWith('.json'))
  let total = 0
  for (const f of archivos) {
    let lista
    try { lista = JSON.parse(readFileSync(join(DIR_COD, f), 'utf8')) } catch (e) {
      console.error(`  ✗ ${f}: JSON inválido (${e.message})`); continue
    }
    if (!Array.isArray(lista)) { console.error(`  ✗ ${f}: no es un array`); continue }
    const filas = lista
      .filter((x) => x && x.codigo && x.descripcion)
      .flatMap((x) => expandirRango(String(x.codigo)).map((codigo) => ({ ...x, codigo })))
      .map((x) => {
        const { spn, fmi } = spnFmi(x.codigo, x.formato)
        // "generico"/"todas" = aplica a toda la flota → NULL (el filtro por
        // marca deja pasar NULL; un slug 'generico' lo escondería).
        // Componentes (WABCO, Allison, Voith...) también: van montados en
        // camiones de varias marcas. Solo las marcas de camión filtran.
        const m = slug(x.marca ?? '') ?? ''
        const marca = MARCAS_CAMION.find((k) => m.startsWith(k) || (m.length >= 4 && k.startsWith(m))) ?? (x.marca ? null : marcaDe(f.replace(/\.json$/, '')))
        return [
          marca || null, x.aplica ?? null, x.ecu ?? null, x.formato ?? 'DTC-OEM', String(x.codigo),
          norm(x.codigo), spn, fmi, String(x.descripcion),
          JSON.stringify(Array.isArray(x.causas) ? x.causas : x.causas ? [x.causas] : []),
          JSON.stringify(Array.isArray(x.comprobaciones) ? x.comprobaciones : x.comprobaciones ? [x.comprobaciones] : []),
          x.sistema ?? null,
          /oficial|tecnica_terceros|experiencia_campo/.test(x.confiabilidad ?? '') ? x.confiabilidad : 'tecnica_terceros',
          x.fuente ?? null, f,
        ]
      })
    total += filas.length
    console.log(`  ${f}: ${filas.length} códigos`)
    const c = await db(); if (!c) continue
    await c.query('BEGIN')
    await c.query('DELETE FROM copiloto_codigos_falla WHERE origen_archivo = $1', [f])
    for (let b = 0; b < filas.length; b += 150) {
      const lote = filas.slice(b, b + 150)
      const N = 15
      const vals = lote.map((_, k) => `(${Array.from({ length: N }, (__, j) => `$${k * N + j + 1}`).join(',')})`).join(',')
      await c.query(
        `INSERT INTO copiloto_codigos_falla (marca, aplica, ecu, formato, codigo, codigo_norm, spn, fmi, descripcion,
           causas, comprobaciones, sistema, confiabilidad, fuente, origen_archivo) VALUES ${vals}`,
        lote.flat())
    }
    await c.query('COMMIT')
  }
  console.log(`✓ códigos: ${total}`)
}

// ── Fichas técnicas por equipo (Biblioteca Maestra) ─────────────────────────
const slug = (v) => String(v ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim().replace(/\s+/g, '-')

async function cargarFichas() {
  // La Biblioteca Maestra se exporta a conocimiento/flota_pesada.json (ExcelJS
  // no lee ese .xlsx; se regenera con openpyxl — ver README del copiloto).
  const ruta = argDe('--fichas') ?? join(DIR_CONOC, 'flota_pesada.json')
  if (!existsSync(ruta)) { console.error(`  ✗ no existe ${ruta}`); return }
  const familias = existsSync(join(DIR_CONOC, 'fichas_familias.json'))
    ? JSON.parse(readFileSync(join(DIR_CONOC, 'fichas_familias.json'), 'utf8')) : {}
  const { equipos } = JSON.parse(readFileSync(ruta, 'utf8'))
  // Columnas por prefijo: aguanta tildes/°  que cambian entre exportaciones
  const val = (e, pref) => {
    const k = Object.keys(e).find((h) => h.toLowerCase().startsWith(pref.toLowerCase()))
    const v = k ? e[k] : null
    return v == null || String(v).trim() === '' ? null : String(v).trim()
  }
  const filas = []
  for (const e of equipos ?? []) {
    const patente = val(e, 'Patente')
    if (!patente || !/^[A-Z]{2,4}-?\d{2,4}$/i.test(patente.replace(/\s/g, ''))) continue
    const familia = val(e, 'Familia')
    const fam = familias[familia] ?? {}
    filas.push({
      patente: patente.toUpperCase().replace(/\s/g, ''),
      marca: slug(val(e, 'Marca')),
      modelo: val(e, 'Modelo'),
      anio: Number(val(e, 'A')) || null,
      vin: val(e, 'VIN'),
      numero_motor: val(e, 'N'),
      motor: fam.motor ?? null,
      transmision: fam.transmision ?? null,
      emisiones: fam.emisiones ?? null,
      ecus: fam.ecus ?? null,
      equipamiento: val(e, 'Equipamiento'),
      implemento: val(e, 'Implemento'),
      zona: val(e, 'Zona'),
      fuente_oem: val(e, 'Fuente OEM'),
      lectura_codigos: fam.lectura_codigos ?? null,
      notas: fam.notas ?? null,
      datos: { familia, capacidad: val(e, 'Capacidad'), potencia: val(e, 'Potencia'),
               estado_documentacion: val(e, 'Estado doc'), fuentes_familia: fam.fuentes ?? [] },
    })
  }
  console.log(`  ${basename(ruta)}: ${filas.length} equipos (familias con datos técnicos: ${Object.keys(familias).length})`)
  const c = await db(); if (!c) return
  for (const f of filas) {
    await c.query(
      `INSERT INTO copiloto_fichas_equipo (patente, marca, modelo, anio, vin, numero_motor, motor, transmision, emisiones,
         ecus, equipamiento, implemento, zona, fuente_oem, lectura_codigos, notas, datos, updated_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,NOW())
       ON CONFLICT (patente) DO UPDATE SET marca=EXCLUDED.marca, modelo=EXCLUDED.modelo, anio=EXCLUDED.anio,
         vin=EXCLUDED.vin, numero_motor=EXCLUDED.numero_motor, motor=EXCLUDED.motor, transmision=EXCLUDED.transmision,
         emisiones=EXCLUDED.emisiones, ecus=EXCLUDED.ecus, equipamiento=EXCLUDED.equipamiento,
         implemento=EXCLUDED.implemento, zona=EXCLUDED.zona, fuente_oem=EXCLUDED.fuente_oem,
         lectura_codigos=EXCLUDED.lectura_codigos, notas=EXCLUDED.notas, datos=EXCLUDED.datos, updated_at=NOW()`,
      [f.patente, f.marca, f.modelo, f.anio, f.vin, f.numero_motor, f.motor, f.transmision, f.emisiones, f.ecus,
       f.equipamiento, f.implemento, f.zona, f.fuente_oem, f.lectura_codigos, f.notas, JSON.stringify(f.datos)])
  }
  console.log(`✓ fichas de equipo: ${filas.length}`)
}

// ── URLs de origen de los PDFs descargados ──────────────────────────────────
function* manifiestos(dir) {
  if (!existsSync(dir)) return
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, e.name)
    if (e.isDirectory()) yield* manifiestos(full)
    else if (e.name === '_descargas.json') yield full
  }
}

async function cargarUrls() {
  let n = 0, act = 0
  for (const m of manifiestos(MANUALES)) {
    let lista
    try { lista = JSON.parse(readFileSync(m, 'utf8')) } catch { console.error(`  ✗ ${m}: JSON inválido`); continue }
    for (const x of Array.isArray(lista) ? lista : []) {
      if (!x?.archivo || !/^https?:\/\//.test(x.url ?? '')) continue
      n++
      const c = await db(); if (!c) continue
      const r = await c.query(
        `UPDATE copiloto_documentos SET url_fuente = $2, confiabilidad = COALESCE(confiabilidad, 'oficial'),
                idioma = COALESCE(idioma, $3)
          WHERE archivo = $1`, [basename(x.archivo), x.url, x.idioma ?? null])
      act += r.rowCount
    }
  }
  console.log(`✓ URLs: ${n} en manifiestos, ${act} documentos actualizados${dryRun ? ' (dry-run)' : ''}`)
}

// ── Aportes del taller: PDFs y fotos que los mecánicos propusieron ──────────
// Se bajan a Manuales/_Aportes taller/ (con su descripción en un .txt) para
// que jefatura los revise y borre lo que no sirva. Después:
//   python copiloto-aportes-pdf.py        # foto + descripción → PDF buscable
//   node copiloto-ingesta.mjs --dir "<...>/Manuales/_Aportes taller"
async function bajarAportes() {
  const url = (process.env.COPILOTO_SUPABASE_URL || '').replace(/\/$/, '')
  const key = process.env.COPILOTO_SUPABASE_SERVICE_KEY || ''
  if (!url || !key) { console.error('  ✗ faltan COPILOTO_SUPABASE_URL / COPILOTO_SUPABASE_SERVICE_KEY'); return }
  const h = { apikey: key, Authorization: `Bearer ${key}` }
  const r = await fetch(`${url}/rest/v1/copiloto_adjuntos?select=id,storage_path,nombre,tipo,descripcion,created_at&propuesto_biblioteca=eq.true&estado=neq.ingerido&order=created_at`, { headers: h })
  if (!r.ok) { console.error(`  ✗ ${r.status} ${await r.text()}`); return }
  const lista = await r.json()
  const destino = join(MANUALES, '_Aportes taller')
  mkdirSync(destino, { recursive: true })
  let n = 0
  for (const a of lista) {
    // El nombre lleva la descripción: la ingesta clasifica marca/sistema por nombre
    const base = a.descripcion ? `${a.descripcion.slice(0, 90)} (aporte taller)` : a.nombre.replace(/\.[a-z0-9]+$/i, '')
    const ext = a.tipo === 'application/pdf' ? 'pdf' : (a.tipo.split('/')[1] || 'jpg')
    const nombre = `${a.created_at.slice(0, 10)} ${base}.${ext}`.replace(/[\\/:*?"<>|]/g, '_')
    if (dryRun) { console.log(`  (dry) ${nombre}`); continue }
    const f = await fetch(`${url}/storage/v1/object/adjuntos/${a.storage_path}`, { headers: h })
    if (!f.ok) { console.error(`  ✗ ${a.nombre}: ${f.status}`); continue }
    writeFileSync(join(destino, nombre), Buffer.from(await f.arrayBuffer()))
    if (a.descripcion) writeFileSync(join(destino, nombre.replace(/\.[a-z0-9]+$/i, '.txt')), a.descripcion, 'utf8')
    await fetch(`${url}/rest/v1/copiloto_adjuntos?id=eq.${a.id}`, {
      method: 'PATCH', headers: { ...h, 'Content-Type': 'application/json' }, body: JSON.stringify({ estado: 'ingerido' }),
    })
    n++; console.log(`  ↓ ${nombre}`)
  }
  console.log(`✓ aportes: ${lista.length} propuestos, ${n} bajados a ${destino}`)
}

// ── main ────────────────────────────────────────────────────────────────────
try {
  if (args.includes('--schema-v2')) {
    const c = await db()
    if (c) {
      const res = await c.query(readFileSync(join(BASE, 'corpus_schema_v2.sql'), 'utf8'))
      const ult = Array.isArray(res) ? res[res.length - 1] : res
      console.log('✓ corpus_schema_v2.sql aplicado', ult?.rows?.[0] ?? '')
    }
  }
  if (hacer('--fichas')) await cargarFichas()
  if (hacer('--conocimiento')) await cargarConocimiento()
  if (hacer('--codigos')) await cargarCodigos()
  if (hacer('--urls')) await cargarUrls()
  if (args.includes('--aportes')) await bajarAportes()
  if (!args.some((a) => ['--schema-v2', '--fichas', '--conocimiento', '--codigos', '--urls', '--todo', '--aportes'].includes(a))) {
    console.log('Nada que hacer. Usa --schema-v2 | --fichas | --conocimiento | --codigos | --urls | --aportes | --todo [--dry-run]')
  }
} catch (e) {
  try { await client?.query('ROLLBACK') } catch { /* ignore */ }
  console.error('✗', e.message)
  process.exitCode = 1
} finally {
  await client?.end()
}
