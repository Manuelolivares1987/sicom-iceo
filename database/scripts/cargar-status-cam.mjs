// ETL: carga el estado actual (cliente + lugar fisico) de cada equipo desde el
// Excel "Status cam.xlsx" y deja una linea base en el historial de arriendos.
//
// Columnas del Excel (Hoja1, desde fila 2):
//   B=patente  C=marca  D=modelo  E=tipo  F=spec  G=anio  H=cliente  I=lugar fisico
//
// Que hace, por patente:
//   1) UPDATE activos SET cliente_actual=H, ubicacion_actual=I (+ faena_id si el
//      lugar calza con una faena del contrato). NO cambia estado_comercial.
//   2) INSERT linea base en historico_estado_activo (origen='importado') para que
//      el "ultimo arriendo" y el historial muestren la foto de hoy. Idempotente:
//      no duplica si ya hay una fila 'importado' para ese equipo.
//
// Uso: NODE_PATH=<ruta a node_modules con pg y exceljs> \
//      SUPABASE_DB_URL=... node database/scripts/cargar-status-cam.mjs
// (requiere SUPABASE_DB_URL en el entorno, ver .env.supabase-admin.local)

import ExcelJS from 'exceljs'
import pg from 'pg'
import dotenv from 'dotenv'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

dotenv.config({ path: resolve(dirname(fileURLToPath(import.meta.url)), '../../.env.supabase-admin.local') })

const ARCHIVO = 'C:\\Users\\Manuel Olivares\\Desktop\\Status cam.xlsx'

function norm(p) {
  // normaliza patente: mayusculas, sin espacios ni guiones ni puntos
  return p == null ? '' : String(p).trim().toUpperCase().replace(/[^A-Z0-9]/g, '')
}
function txt(c) {
  let v = c == null ? null : c.value
  if (v && typeof v === 'object') {
    if ('result' in v) v = v.result
    else if ('text' in v) v = v.text
    else if ('richText' in v) v = v.richText.map((t) => t.text).join('')
    else return null
  }
  return v == null ? null : String(v).trim() || null
}

const c = new pg.Client({
  connectionString: process.env.SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false },
  statement_timeout: 120000,
  connectionTimeoutMillis: 20000,
})
await c.connect()
console.log('conectado')

// Mapa patente normalizada -> { id, contrato_id, estado_comercial }
const act = await c.query(`
  SELECT id, contrato_id, estado_comercial,
         upper(regexp_replace(patente,'[^A-Za-z0-9]','','g')) AS pnorm
    FROM activos WHERE patente IS NOT NULL`)
const byPatente = new Map(act.rows.map((r) => [r.pnorm, r]))

const wb = new ExcelJS.Workbook()
await wb.xlsx.readFile(ARCHIVO)
const ws = wb.worksheets[0]

let leidas = 0, actualizadas = 0, faenaMatch = 0, baseInsert = 0
const sinMatch = []

for (let r = 1; r <= ws.rowCount; r++) {
  const row = ws.getRow(r)
  const patente = txt(row.getCell(2)) // B
  if (!patente) continue
  const pnorm = norm(patente)
  if (!pnorm || pnorm === 'PATENTE') continue
  const cliente = txt(row.getCell(8)) // H
  const lugar   = txt(row.getCell(9)) // I
  if (!byPatente.has(pnorm)) { sinMatch.push(patente); continue }
  leidas++

  const a = byPatente.get(pnorm)

  // 1) Lugar fisico: intentar calzar el texto del Excel con una faena del contrato
  let faenaId = null
  if (lugar) {
    const f = await c.query(
      `SELECT id FROM faenas
        WHERE ($1::uuid IS NULL OR contrato_id = $1)
          AND (unaccent(lower(nombre)) = unaccent(lower($2))
               OR unaccent(lower(nombre)) LIKE unaccent(lower($2)) || '%')
        ORDER BY (contrato_id = $1) DESC NULLS LAST
        LIMIT 1`,
      [a.contrato_id, lugar]
    ).catch(async () => {
      // si no existe unaccent, fallback simple
      return c.query(
        `SELECT id FROM faenas WHERE lower(nombre)=lower($1) LIMIT 1`, [lugar]
      )
    })
    if (f.rows[0]) { faenaId = f.rows[0].id; faenaMatch++ }
  }

  await c.query(
    `UPDATE activos
        SET cliente_actual = COALESCE($2, cliente_actual),
            ubicacion_actual = COALESCE($3, ubicacion_actual),
            faena_id = COALESCE($4, faena_id),
            updated_at = NOW()
      WHERE id = $1`,
    [a.id, cliente, lugar, faenaId]
  )
  actualizadas++

  // 2) Linea base en el historial (idempotente por origen='importado')
  const yaBase = await c.query(
    `SELECT 1 FROM historico_estado_activo
      WHERE activo_id = $1 AND origen = 'importado' LIMIT 1`, [a.id]
  )
  if (yaBase.rowCount === 0) {
    const estado = ['arrendado', 'leasing', 'uso_interno'].includes(a.estado_comercial)
      ? a.estado_comercial : 'arrendado'
    await c.query(
      `INSERT INTO historico_estado_activo
         (activo_id, estado_anterior, estado_nuevo, cambio_at, origen,
          contrato_id, razon, cliente, ubicacion_lugar, faena_id)
       VALUES ($1, NULL, $2, NOW(), 'importado', $3,
               'Carga inicial Status cam', $4, $5, $6)`,
      [a.id, estado, a.contrato_id, cliente, lugar, faenaId]
    )
    baseInsert++
  }
}

console.log(`Filas con match:        ${leidas}`)
console.log(`Activos actualizados:   ${actualizadas}`)
console.log(`Faenas calzadas:        ${faenaMatch}`)
console.log(`Lineas base historial:  ${baseInsert}`)
if (sinMatch.length) console.log(`Patentes SIN activo (${sinMatch.length}): ${sinMatch.join(', ')}`)

await c.end()
console.log('listo')
