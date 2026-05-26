// ETL: carga los estados diarios reales desde los Excel de Confiabilidad
// (hoja "Report Diario", matriz vehiculo x dia) a estado_diario_flota.
// Uso: NODE_PATH=<pg> node cargar-confiabilidad.mjs
import ExcelJS from 'exceljs'
import pg from 'pg'

const DIR = 'C:\\Users\\Manuel Olivares\\Desktop\\2026\\PILLADO\\2026\\Confiabilidad\\'
const MESES = [
  { archivo: 'ENERO.xlsx',   mes: 1 },
  { archivo: 'FEBRERO.xlsx', mes: 2 },
  { archivo: 'MARZO.xlsx',   mes: 3 },
  { archivo: 'ABRIL.xlsx',   mes: 4 },
  { archivo: 'MAYO.xlsx',    mes: 5 },
]
const ANIO = 2026
const VALIDOS = new Set(['A','C','D','H','R','M','T','F','V','U','L'])
// 'C' (en contrato) es estado valido (Francke, CMP). Se preserva tal cual.
function mapEstado(s) {
  if (!s) return null
  const e = String(s).trim().toUpperCase()
  return VALIDOS.has(e) ? e : null
}
function norm(p) { return p == null ? '' : String(p).trim().toUpperCase().replace(/\s+/g, '') }
function txt(c) {
  let v = c.value
  if (v && typeof v === 'object') { if ('result' in v) v = v.result; else if ('text' in v) v = v.text; else return null }
  return v == null ? null : String(v).trim() || null
}

const c = new pg.Client({ connectionString: process.env.SUPABASE_DB_URL, ssl: { rejectUnauthorized: false }, statement_timeout: 120000, connectionTimeoutMillis: 20000 })
await c.connect()
console.log('conectado')

// Mapa patente -> activo_id
const act = await c.query(`select id, upper(regexp_replace(patente,'\\s','','g')) pnorm from activos where patente is not null`)
const byPatente = new Map(act.rows.map(r => [r.pnorm, r.id]))

let totalRows = 0, totalUpsert = 0, totalSkipEstado = 0
const sinMatch = new Set()

for (const { archivo, mes } of MESES) {
  const wb = new ExcelJS.Workbook()
  await wb.xlsx.readFile(DIR + archivo)
  const ws = wb.getWorksheet('Report Diario')
  if (!ws) { console.log(`  ${archivo}: sin hoja "Report Diario", skip`); continue }

  const recs = []
  for (let r = 2; r <= ws.rowCount; r++) {
    const row = ws.getRow(r)
    const patente = txt(row.getCell(2))
    if (!patente) continue
    const pnorm = norm(patente)
    const activoId = byPatente.get(pnorm)
    const cliente   = txt(row.getCell(9))
    const ubicacion = txt(row.getCell(10))
    const operacion = txt(row.getCell(11))
    // dias 1..31 -> cols 12..42
    for (let d = 1; d <= 31; d++) {
      const raw = txt(row.getCell(11 + d))
      if (!raw) continue
      const est = mapEstado(raw)
      if (!est) { totalSkipEstado++; continue }
      totalRows++
      if (!activoId) { sinMatch.add(patente); continue }
      const fecha = `${ANIO}-${String(mes).padStart(2,'0')}-${String(d).padStart(2,'0')}`
      recs.push({ activoId, fecha, est, cliente, ubicacion, operacion })
    }
  }

  // Upsert por LOTES (multi-row INSERT, chunks de 500)
  const motivo = `Importado reportabilidad ${archivo}`
  const CHUNK = 500
  await c.query('BEGIN')
  for (let i = 0; i < recs.length; i += CHUNK) {
    const lote = recs.slice(i, i + CHUNK)
    const vals = [], params = []
    lote.forEach((x, j) => {
      const b = j * 7
      vals.push(`($${b+1},$${b+2},$${b+3},$${b+4},$${b+5},$${b+6},true,false,$${b+7})`)
      params.push(x.activoId, x.fecha, x.est, x.cliente, x.ubicacion, x.operacion, motivo)
    })
    await c.query(`
      INSERT INTO estado_diario_flota
        (activo_id, fecha, estado_codigo, cliente, ubicacion, operacion,
         override_manual, calculado_auto, motivo_override)
      VALUES ${vals.join(',')}
      ON CONFLICT (activo_id, fecha) DO UPDATE SET
         estado_codigo = EXCLUDED.estado_codigo,
         cliente = COALESCE(EXCLUDED.cliente, estado_diario_flota.cliente),
         ubicacion = COALESCE(EXCLUDED.ubicacion, estado_diario_flota.ubicacion),
         operacion = COALESCE(EXCLUDED.operacion, estado_diario_flota.operacion),
         override_manual = true, calculado_auto = false,
         motivo_override = EXCLUDED.motivo_override, updated_at = now()
    `, params)
    totalUpsert += lote.length
  }
  await c.query('COMMIT')
  console.log(`  ${archivo}: ${recs.length} filas cargadas`)
}

console.log(`\n=== RESUMEN ===`)
console.log(`celdas con estado leidas: ${totalRows}`)
console.log(`upserts a estado_diario_flota: ${totalUpsert}`)
console.log(`celdas con estado invalido (saltadas): ${totalSkipEstado}`)
console.log(`patentes SIN match en activos (${sinMatch.size}): ${[...sinMatch].join(', ') || '(ninguna)'}`)

await c.end()
