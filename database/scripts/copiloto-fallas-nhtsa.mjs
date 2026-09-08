#!/usr/bin/env node
// ============================================================================
// copiloto-fallas-nhtsa.mjs — fallas recurrentes y soluciones desde la base
// pública de seguridad vehicular de EE.UU. (NHTSA) hacia el corpus.
// ----------------------------------------------------------------------------
// Manuel, 08-09-2026: «descarga fallas recurrentes y soluciones para la flota
// que manejamos en condición severa, de tal manera de tener más data».
//
// Qué trae por cada modelo vendido en EE.UU. de nuestra flota:
//  - RECALLS oficiales: defecto + consecuencia + REMEDIO (falla conocida con
//    solución del fabricante, oro para diagnóstico)
//  - QUEJAS de flotas/dueños agrupadas por componente con relatos de muestra
//    (patrón de falla recurrente en condición real)
//
// Se ingesta como tipo 'reporte_falla' (peso 0.6 en el ranking: por debajo
// del manual oficial, por encima de 'otro'). El prompt del copiloto ya
// distingue el tipo de fuente al citar.
//
// Uso:  node copiloto-fallas-nhtsa.mjs [--dry-run]
// ============================================================================
import { createHash } from 'node:crypto'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../.env.copiloto.local') })
if (!process.env.COPILOTO_DB_URL) { console.error('Falta COPILOTO_DB_URL'); process.exit(2) }
const dryRun = process.argv.includes('--dry-run')

// Nuestra flota en el mercado EE.UU. La marca es el slug del corpus para que
// el filtro por equipo funcione (el pluma JPZV-22 está keyeado como 'imt').
const OBJETIVOS = [
  { make: 'MACK', patron: /GU|GRANITE/i, marcaCorpus: 'mack', titulo: 'Mack Granite GU — Fallas conocidas y soluciones (NHTSA)' },
  { make: 'FREIGHTLINER', patron: /^M2|BUSINESS CLASS M2|M2-106|M2 106/i, marcaCorpus: 'imt', titulo: 'Freightliner M2-106 (chasis camión pluma JPZV-22) — Fallas conocidas y soluciones (NHTSA)' },
  { make: 'MITSUBISHI FUSO', patron: /FE|FG|CANTER/i, marcaCorpus: 'mitsubishi', titulo: 'Mitsubishi Fuso Canter FE/FG — Fallas conocidas y soluciones (NHTSA)' },
]
const YEARS = Array.from({ length: 24 }, (_, i) => 2003 + i) // 2003..2026

const espera = (ms) => new Promise((r) => setTimeout(r, ms))
async function api(url, intentos = 3) {
  for (let i = 0; i < intentos; i++) {
    try {
      const res = await fetch(url, { headers: { accept: 'application/json' } })
      if (res.status === 429) { await espera(2000 * (i + 1)); continue }
      if (!res.ok) return null
      return await res.json()
    } catch { await espera(1500) }
  }
  return null
}

const limpiar = (t) => String(t ?? '').replace(/\s+/g, ' ').trim()

// La cosecha por la API demora varios minutos: si la conexión a Postgres se
// abre al principio, el pooler la corta por inactividad y se pierde todo.
// Se abre una conexión NUEVA solo al momento de guardar cada marca.
async function conDB(fn) {
  const c = new pg.Client({ connectionString: process.env.COPILOTO_DB_URL, ssl: { rejectUnauthorized: false } })
  await c.connect()
  try { return await fn(c) } finally { try { await c.end() } catch { /* ignore */ } }
}

for (const obj of OBJETIVOS) {
  console.log(`\n══ ${obj.make} ══`)

  // 1 · Descubrir los modelos reales año a año (la API solo lista los que
  //     tuvieron recalls/quejas ese año)
  const modelos = new Map() // modelo -> Set(años)
  for (const tipo of ['r', 'c']) {
    for (const y of YEARS) {
      const j = await api(`https://api.nhtsa.gov/products/vehicle/models?modelYear=${y}&make=${encodeURIComponent(obj.make)}&issueType=${tipo}`)
      for (const m of j?.results ?? []) {
        if (obj.patron.test(m.model)) {
          if (!modelos.has(m.model)) modelos.set(m.model, new Set())
          modelos.get(m.model).add(y)
        }
      }
    }
  }
  console.log(`  modelos: ${Array.from(modelos.keys()).join(', ') || '(ninguno)'}`)
  if (modelos.size === 0) continue

  // 2 · Recalls (únicos por campaña) y quejas (agrupadas por componente)
  const campanas = new Map()
  const quejas = new Map() // componente -> {n, relatos:[], modelos:Set}
  for (const [modelo, anios] of modelos) {
    for (const y of anios) {
      const r = await api(`https://api.nhtsa.gov/recalls/recallsByVehicle?make=${encodeURIComponent(obj.make)}&model=${encodeURIComponent(modelo)}&modelYear=${y}`)
      for (const rec of r?.results ?? []) {
        const k = rec.NHTSACampaignNumber ?? `${rec.Component}|${rec.Summary?.slice(0, 40)}`
        const prev = campanas.get(k)
        if (prev) { prev.anios.add(y); prev.modelos.add(modelo) }
        else campanas.set(k, {
          num: rec.NHTSACampaignNumber, comp: limpiar(rec.Component),
          resumen: limpiar(rec.Summary), consecuencia: limpiar(rec.Consequence),
          remedio: limpiar(rec.Remedy), fecha: rec.ReportReceivedDate ?? '',
          anios: new Set([y]), modelos: new Set([modelo]),
        })
      }
      const c = await api(`https://api.nhtsa.gov/complaints/complaintsByVehicle?make=${encodeURIComponent(obj.make)}&model=${encodeURIComponent(modelo)}&modelYear=${y}`)
      for (const q of c?.results ?? []) {
        const comp = limpiar(q.components) || 'SIN COMPONENTE'
        if (!quejas.has(comp)) quejas.set(comp, { n: 0, relatos: [], modelos: new Set() })
        const g = quejas.get(comp)
        g.n += 1; g.modelos.add(`${modelo} ${y}`)
        const rel = limpiar(q.summary)
        if (rel.length > 60 && g.relatos.length < 4) g.relatos.push(rel.slice(0, 420))
      }
      await espera(150)
    }
  }
  console.log(`  recalls únicos: ${campanas.size} · componentes con quejas: ${quejas.size} · quejas totales: ${Array.from(quejas.values()).reduce((s, g) => s + g.n, 0)}`)

  // 3 · Documento por marca → páginas sintéticas (1 recall = 1 chunk;
  //     1 componente de quejas = 1 chunk)
  const secciones = []
  const ordenadas = Array.from(campanas.values()).sort((a, b) => (b.fecha || '').localeCompare(a.fecha || ''))
  for (const cpn of ordenadas) {
    secciones.push(
      `RECALL OFICIAL ${cpn.num ?? ''} — ${cpn.comp}\n` +
      `Modelos/años afectados: ${Array.from(cpn.modelos).join(', ')} (${Math.min(...cpn.anios)}–${Math.max(...cpn.anios)})\n` +
      `Defecto: ${cpn.resumen}\n` +
      `Consecuencia: ${cpn.consecuencia}\n` +
      `SOLUCIÓN DEL FABRICANTE: ${cpn.remedio}`)
  }
  const compOrden = Array.from(quejas.entries()).sort((a, b) => b[1].n - a[1].n)
  for (const [comp, g] of compOrden) {
    if (g.n < 2) continue // 1 sola queja no es patrón
    secciones.push(
      `FALLA RECURRENTE REPORTADA — Componente: ${comp} (${g.n} reportes de dueños/flotas)\n` +
      `Afecta: ${Array.from(g.modelos).slice(0, 8).join(', ')}\n` +
      g.relatos.map((r, i) => `Relato ${i + 1}: ${r}`).join('\n'))
  }
  if (secciones.length === 0) { console.log('  nada que ingestar'); continue }

  if (dryRun) { console.log(`  DRY-RUN: ${secciones.length} secciones`); continue }

  const cuerpo = secciones.join('\n\n')
  const hash = createHash('sha256').update(obj.titulo + cuerpo).digest('hex')
  await conDB(async (client) => {
    const dup = await client.query('SELECT id FROM copiloto_documentos WHERE hash = $1', [hash])
    if (dup.rows.length) { console.log('  sin cambios desde la última corrida'); return }
    // Si hay versión anterior del mismo título, se reemplaza (los datos crecen)
    await client.query('BEGIN')
    await client.query(`DELETE FROM copiloto_documentos WHERE titulo = $1`, [obj.titulo])
    const doc = await client.query(
      `INSERT INTO copiloto_documentos (titulo, archivo, ruta_origen, hash, tipo_documento, marca, paginas, paginas_con_texto)
       VALUES ($1, $2, 'api.nhtsa.gov', $3, 'reporte_falla', $4, $5, $5) RETURNING id`,
      [obj.titulo, `nhtsa-${obj.make.toLowerCase().replace(/\s+/g, '-')}.txt`, hash, obj.marcaCorpus, secciones.length])
    const docId = doc.rows[0].id
    for (let i = 0; i < secciones.length; i += 100) {
      const lote = secciones.slice(i, i + 100)
      const values = lote.map((_, k) => `($${k * 4 + 1},$${k * 4 + 2},$${k * 4 + 3},$${k * 4 + 4})`).join(',')
      await client.query(
        `INSERT INTO copiloto_chunks (documento_id, pagina, chunk_index, contenido) VALUES ${values}`,
        lote.flatMap((s, k) => [docId, i + k + 1, 0, s.slice(0, 8000)]))
    }
    await client.query('COMMIT')
    console.log(`  ✓ ingestado: ${secciones.length} chunks`)
  })
}

await conDB(async (client) => {
  const size = await client.query(`SELECT pg_size_pretty(pg_database_size(current_database())) s`)
  console.log(`\nTamaño DB corpus: ${size.rows[0].s}`)
})
