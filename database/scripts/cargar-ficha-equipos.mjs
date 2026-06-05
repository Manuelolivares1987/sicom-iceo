// Carga la ficha técnica de equipos desde la planilla "Data Equipo" a activos.
// Columnas Excel: PATENTE | Marca | Modelo | Equipamiento | Capacidad | Año |
//                 Potencia (CV) | VIN (Chasis) | N° Motor
// Sincroniza capacidad, potencia, vin_chasis, numero_motor, anio_fabricacion
// (NO sobrescribe con vacío). Match por patente normalizada.
// Uso: node cargar-ficha-equipos.mjs ["<ruta_xlsx>"]
import ExcelJS from 'exceljs'
import pg from 'pg'
import dotenv from 'dotenv'
import { resolve, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })

const FILE = process.argv[2] || 'C:\\Users\\Manuel Olivares\\Desktop\\Data Equipo 05062026.xlsx'
const norm = (p) => (p == null ? '' : String(p).trim().toUpperCase().replace(/[\s-]/g, ''))
const txt = (cell) => {
  let v = cell?.value
  if (v && typeof v === 'object') {
    if ('result' in v) v = v.result
    else if ('text' in v) v = v.text
    else if ('richText' in v) v = v.richText.map((t) => t.text).join('')
    else return null
  }
  return v == null ? null : String(v).trim() || null
}

const wb = new ExcelJS.Workbook()
await wb.xlsx.readFile(resolve(FILE))
const ws = wb.worksheets[0]
const filas = []
ws.eachRow((row, i) => {
  if (i === 1) return // encabezado
  const patente = txt(row.getCell(1))
  if (!patente) return
  filas.push({
    patente,
    capacidad: txt(row.getCell(5)),
    anio:      txt(row.getCell(6)),
    potencia:  txt(row.getCell(7)),
    vin:       txt(row.getCell(8)),
    motor:     txt(row.getCell(9)),
  })
})

const c = new pg.Client({
  connectionString: (process.env.SUPABASE_DB_URL || '').trim(),
  ssl: { rejectUnauthorized: false }, statement_timeout: 120000, connectionTimeoutMillis: 20000,
})
await c.connect()
console.log('conectado')

const { rows: activos } = await c.query('SELECT id, patente FROM activos WHERE patente IS NOT NULL')
const byPat = new Map(activos.map((a) => [norm(a.patente), a.id]))

let upd = 0
const miss = []
for (const f of filas) {
  const id = byPat.get(norm(f.patente))
  if (!id) { miss.push(f.patente); continue }
  const anioInt = f.anio ? parseInt(String(f.anio).replace(/\D/g, ''), 10) : NaN
  await c.query(
    `UPDATE activos SET
       capacidad        = COALESCE(NULLIF($2,''), capacidad),
       potencia         = COALESCE(NULLIF($3,''), potencia),
       vin_chasis       = COALESCE(NULLIF($4,''), vin_chasis),
       numero_motor     = COALESCE(NULLIF($5,''), numero_motor),
       anio_fabricacion = COALESCE($6, anio_fabricacion)
     WHERE id = $1`,
    [id, f.capacidad, f.potencia, f.vin, f.motor, Number.isFinite(anioInt) ? anioInt : null],
  )
  upd++
}

console.log(`Filas Excel: ${filas.length} · Actualizados: ${upd} · Sin match: ${miss.length}`)
if (miss.length) console.log('Sin match en activos:', miss.join(', '))
await c.end()
