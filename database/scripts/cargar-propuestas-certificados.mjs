#!/usr/bin/env node
// ============================================================================
// cargar-propuestas-certificados.mjs
// ----------------------------------------------------------------------------
// Sube a la base lo que `analizar-certificados.mjs` sacó de los PDF, para que
// Control documental pueda ofrecerlo al lado de cada papel.
//
// NO FIJA NINGUNA FECHA. Deja la propuesta en `certificacion_propuestas` con su
// cita textual; aceptarla es un clic de una persona en la pantalla.
//
// Es idempotente: vuelve a correr y reemplaza las propuestas PENDIENTES sin
// tocar las que alguien ya aceptó o descartó — el trabajo hecho no se pierde
// porque el lector haya mejorado.
//
// Uso:  node cargar-propuestas-certificados.mjs [ruta/al/propuesta.json]
// ============================================================================

import { readFileSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ENV_PATH = resolve(__dirname, '../../.env.supabase-admin.local')
if (!existsSync(ENV_PATH)) { console.error(`ERROR: falta ${ENV_PATH}`); process.exit(2) }
dotenv.config({ path: ENV_PATH })

const JSON_PATH = process.argv[2]
  ? resolve(process.argv[2])
  : resolve(__dirname, '../../reportes/certificados-propuesta.json')
if (!existsSync(JSON_PATH)) { console.error(`ERROR: no existe ${JSON_PATH}`); process.exit(2) }

const datos = JSON.parse(readFileSync(JSON_PATH, 'utf8'))

const client = new pg.Client({
  connectionString: (process.env.SUPABASE_DB_URL || '').trim(),
  ssl: { rejectUnauthorized: false },
})
await client.connect()

// Sólo lo que aporta algo: una fecha propuesta, o el aviso de que el archivo es
// un escaneo ilegible. Un «no_vence» no necesita que nadie decida nada.
const utiles = datos.filter((r) => r.vencimiento || r.confianza === 'sin_fecha' || r.confianza === 'sin_ancla')

let nuevas = 0, actualizadas = 0, saltadas = 0
await client.query('BEGIN')
try {
  for (const r of utiles) {
    // Respetar lo ya resuelto: si alguien aceptó o descartó, no se vuelve a preguntar.
    const { rows: previas } = await client.query(
      `SELECT estado FROM certificacion_propuestas WHERE certificacion_id = $1 ORDER BY created_at DESC LIMIT 1`,
      [r.id])
    if (previas[0] && previas[0].estado !== 'pendiente') { saltadas++; continue }

    const { rowCount } = await client.query(
      `UPDATE certificacion_propuestas
          SET emision_propuesta = $2, vencimiento_propuesto = $3, confianza = $4,
              regla = $5, evidencia = $6, caracteres_pdf = $7, created_at = NOW()
        WHERE certificacion_id = $1 AND estado = 'pendiente'`,
      [r.id, r.emision ?? null, r.vencimiento ?? null, r.confianza,
       r.regla ?? r.motivo ?? null, r.evidencia ?? null, r.caracteres ?? null])

    if (rowCount > 0) { actualizadas++; continue }

    await client.query(
      `INSERT INTO certificacion_propuestas
         (certificacion_id, emision_propuesta, vencimiento_propuesto, confianza, regla, evidencia, caracteres_pdf)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [r.id, r.emision ?? null, r.vencimiento ?? null, r.confianza,
       r.regla ?? r.motivo ?? null, r.evidencia ?? null, r.caracteres ?? null])
    nuevas++
  }
  await client.query('COMMIT')
} catch (e) {
  await client.query('ROLLBACK')
  console.error('ERROR, nada se guardó:', e.message)
  process.exit(1)
}

const { rows: resumen } = await client.query(`
  SELECT confianza, count(*) AS n,
         count(*) FILTER (WHERE vencimiento_propuesto < CURRENT_DATE) AS vencidas
    FROM certificacion_propuestas WHERE estado = 'pendiente'
   GROUP BY 1 ORDER BY 2 DESC`)

console.log(`\nPropuestas nuevas: ${nuevas} · actualizadas: ${actualizadas} · ya resueltas (no se tocan): ${saltadas}\n`)
console.log('Pendientes en Control documental:')
for (const r of resumen) {
  console.log(`  ${String(r.confianza).padEnd(16)} ${String(r.n).padStart(4)}${r.vencidas > 0 ? `   (${r.vencidas} ya vencidas)` : ''}`)
}

await client.end()
