#!/usr/bin/env node
// ============================================================================
// verificar-migraciones-destructivas.mjs
// ----------------------------------------------------------------------------
// Regla automática de la auditoría Fase 0 (hallazgo C2): detecta en
// database/production_run/*.sql operaciones destructivas no protegidas:
//   - DELETE FROM <tabla>;  sin WHERE
//   - UPDATE <tabla> SET ...; sin WHERE
//   - TRUNCATE
//   - DROP TABLE (sin IF EXISTS sobre tablas temporales/backup)
//
// Excepciones permitidas (documentadas):
//   - Archivo con la marca literal:  -- destructivo-ok: <motivo>
//     (la marca cubre el archivo completo; usarla exige explicar el motivo)
//   - Statements dentro de cuerpos $$...$$ de funciones/DO quedan incluidos en
//     el análisis a propósito: un DO con DELETE sin WHERE es igual de peligroso.
//
// Uso:
//   node database/scripts/verificar-migraciones-destructivas.mjs
// Sale con código 1 si encuentra hallazgos sin excepción documentada.
// ============================================================================

import { readFileSync, readdirSync } from 'node:fs'
import { resolve, dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const DIR = resolve(__dirname, '../production_run')

// Quita comentarios -- y /* */ y literales de texto para no dar falsos positivos.
function limpiarSql(sql) {
  return sql
    .replace(/--[^\n]*/g, ' ')
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/'(?:[^']|'')*'/g, "''")
}

// Divide en statements por ';' respetando dollar-quoting ($tag$...$tag$).
function statements(sql) {
  const out = []
  let buf = ''
  let dollarTag = null
  let i = 0
  while (i < sql.length) {
    if (dollarTag) {
      const end = sql.indexOf(dollarTag, i)
      if (end === -1) { buf += sql.slice(i); break }
      buf += sql.slice(i, end + dollarTag.length)
      i = end + dollarTag.length
      dollarTag = null
      continue
    }
    const ch = sql[i]
    if (ch === '$') {
      const m = /^\$[A-Za-z_]*\$/.exec(sql.slice(i))
      if (m) { dollarTag = m[0]; buf += m[0]; i += m[0].length; continue }
    }
    if (ch === ';') { out.push(buf); buf = ''; i++; continue }
    buf += ch; i++
  }
  if (buf.trim()) out.push(buf)
  return out
}

function analizarStatement(st) {
  const s = st.replace(/\s+/g, ' ').trim()
  const hallazgos = []
  // DELETE FROM x  (sin WHERE en el mismo statement)
  for (const m of s.matchAll(/\bDELETE\s+FROM\s+([a-zA-Z_."]+)([^]*?)(?=(\bDELETE\s+FROM\b|$))/gi)) {
    if (!/\bWHERE\b/i.test(m[2]) && !/^pg_|^_/.test(m[1].replace(/"/g, ''))) {
      hallazgos.push(`DELETE sin WHERE sobre ${m[1]}`)
    }
  }
  // UPDATE x SET ... (sin WHERE)
  for (const m of s.matchAll(/\bUPDATE\s+([a-zA-Z_."]+)\s+SET\b([^]*?)(?=(\bUPDATE\s+[a-zA-Z_."]+\s+SET\b|$))/gi)) {
    if (!/\bWHERE\b/i.test(m[2])) hallazgos.push(`UPDATE sin WHERE sobre ${m[1]}`)
  }
  if (/\bTRUNCATE\b/i.test(s)) hallazgos.push('TRUNCATE')
  for (const m of s.matchAll(/\bDROP\s+TABLE\s+(IF\s+EXISTS\s+)?([a-zA-Z_."]+)/gi)) {
    const tabla = m[2].replace(/"/g, '')
    const esTemporal = /^_|^tmp_|^temp_|^smoke_|_tmp$|_temp$|_bkp|_backup|_seed$/i.test(tabla) || /\bTEMP\b/i.test(s)
    if (!esTemporal) hallazgos.push(`DROP TABLE ${m[1] ? '(IF EXISTS) ' : ''}${tabla}`)
  }
  return hallazgos
}

let total = 0
let archivosConHallazgos = 0
const archivos = readdirSync(DIR).filter((f) => f.endsWith('.sql')).sort()

for (const archivo of archivos) {
  const raw = readFileSync(join(DIR, archivo), 'utf8')
  const excepcion = /--\s*destructivo-ok:\s*(.+)/.exec(raw)
  const limpio = limpiarSql(raw)
  const hallazgos = statements(limpio).flatMap(analizarStatement)
  if (hallazgos.length === 0) continue
  if (excepcion) {
    console.log(`  [permitido] ${archivo} — ${hallazgos.length} operación(es) destructiva(s); motivo: ${excepcion[1].trim()}`)
    continue
  }
  archivosConHallazgos++
  total += hallazgos.length
  console.error(`✗ ${archivo}`)
  for (const h of hallazgos) console.error(`    - ${h}`)
}

console.log('─'.repeat(72))
if (total > 0) {
  console.error(`✗ ${total} operación(es) destructiva(s) sin excepción documentada en ${archivosConHallazgos} archivo(s).`)
  console.error('  Si es legítimo (one-shot con guard, seed controlado), agregar en el archivo:')
  console.error('    -- destructivo-ok: <motivo>')
  process.exit(1)
}
console.log(`✓ ${archivos.length} migraciones revisadas: sin operaciones destructivas desprotegidas.`)
