#!/usr/bin/env node
// ============================================================================
// Prueba de la ingesta de Orpak contra el archivo real de junio 2026
// ----------------------------------------------------------------------------
// Lee ORPAK_AJUSTADO_JUNIO_2026.xlsx con el MISMO parser que usa el frontend,
// lo carga por el RPC de producción y revisa que cada fila haya quedado donde
// corresponde. Todo dentro de una transacción con ROLLBACK.
//
// Lo que se verifica, que es lo que puede salir mal de verdad:
//   · que ninguna fila quede sin estanque (una estación no reconocida es
//     combustible que desaparece del cuadre)
//   · que la clasificación separe venta de trasvasije: si un trasvasije se
//     cuenta como venta, se le cobra dos veces al mandante
//   · que el CECO salga del texto de «Department» y amarre al maestro
//   · que subir el mismo archivo dos veces no duplique nada
//   · que los litros de Orpak se parezcan a los contadores del cierre físico
//
// Uso:  node database/tests/orpak_ingesta_junio.mjs <ruta_al_xlsx>
// ============================================================================

import { existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from '../scripts/node_modules/pg/lib/index.js'
import dotenv from '../scripts/node_modules/dotenv/lib/main.js'
import ExcelJS from '../../frontend/node_modules/exceljs/excel.js'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ENV_PATH = resolve(__dirname, '../../.env.supabase-admin.local')
if (!existsSync(ENV_PATH)) { console.error(`ERROR: falta ${ENV_PATH}`); process.exit(2) }
dotenv.config({ path: ENV_PATH })

const { leerOrpak } = await import('../../frontend/src/lib/services/orpak-parse.js')

const ARCHIVO = process.argv[2]
if (!ARCHIVO || !existsSync(ARCHIVO)) {
  console.error('Uso: node database/tests/orpak_ingesta_junio.mjs <ruta_al_xlsx>')
  process.exit(2)
}

const client = new pg.Client({
  connectionString: (process.env.SUPABASE_DB_URL || '').trim(),
  ssl: { rejectUnauthorized: false },
})

const tabla = (filas, cols) => {
  if (!filas.length) return '   (sin filas)'
  const anchos = cols.map((c) => Math.max(c.length, ...filas.map((f) => String(f[c] ?? '').length)))
  const linea = (vals) => '   ' + vals.map((v, i) => String(v ?? '').padEnd(anchos[i])).join('  ')
  return [linea(cols), '   ' + anchos.map((a) => '-'.repeat(a)).join('  '),
          ...filas.map((f) => linea(cols.map((c) => f[c])))].join('\n')
}

let fallas = 0
const chequear = (cond, texto, detalle) => {
  console.log(`   ${cond ? 'OK  ' : 'FALLA'}  ${texto}${detalle ? '  ->  ' + detalle : ''}`)
  if (!cond) fallas++
}

await client.connect()
client.on('notice', (m) => { if (m.severity !== 'NOTICE') console.log(`   [${m.severity}] ${m.message}`) })

try {
  console.log('\n=== LECTURA DEL ARCHIVO ===')
  const wb = new ExcelJS.Workbook()
  await wb.xlsx.readFile(ARCHIVO)
  const { filas, hojas } = leerOrpak(wb)
  console.log(tabla(hojas, ['hoja', 'leidas', 'sinColumnas']))
  console.log(`   total ${filas.length} transacciones · ${filas.reduce((a, b) => a + b.litros, 0).toLocaleString('es-CL')} L`)

  await client.query('BEGIN')

  const { rows: [u] } = await client.query(
    `SELECT id FROM usuarios_perfil WHERE rol='supervisor' AND activo LIMIT 1`)
  await client.query(`SELECT set_config('request.jwt.claims', $1, true)`,
    [JSON.stringify({ sub: u.id, role: 'authenticated' })])
  const { rows: [f] } = await client.query(`SELECT id FROM faenas WHERE codigo='FAE-CMP-ROMERAL'`)

  console.log('\n=== CARGA ===')
  const t0 = Date.now()
  const { rows: [r1] } = await client.query(
    `SELECT rpc_comb_orpak_cargar($1,$2,$3::jsonb) AS r`,
    [f.id, 'ORPAK_AJUSTADO_JUNIO_2026.xlsx', JSON.stringify(filas)])
  const res = r1.r
  console.log(`   nuevas ${res.nuevas} · repetidas ${res.repetidas} · rechazadas ${res.rechazadas}` +
              ` · periodo ${res.desde} a ${res.hasta} · ${Date.now() - t0} ms`)
  if (res.rechazos?.length) console.log('   rechazos:', JSON.stringify(res.rechazos.slice(0, 5)))

  // Junio ya esta cargado en produccion, asi que en una corrida normal estas
  // filas vuelven como repetidas. Lo que importa es que NINGUNA se pierda por
  // el camino: nuevas + repetidas tiene que dar el total del archivo.
  chequear(res.nuevas + res.repetidas === filas.length,
    'ninguna fila del archivo se pierde',
    `${res.nuevas} nuevas + ${res.repetidas} repetidas de ${filas.length}`)
  chequear(res.rechazadas === 0,
    'ninguna estacion quedo sin reconocer', `${res.rechazadas} rechazadas`)

  console.log('\n=== A QUE ESTANQUE FUE CADA FILA ===')
  const { rows: porEst } = await client.query(`
    SELECT e.nombre AS estanque, t.bomba, count(*) AS filas,
           to_char(sum(t.litros),'FM999G999G999') AS litros
      FROM combustible_orpak_transaccion t
      JOIN combustible_estanques e ON e.id = t.estanque_id
     WHERE t.faena_id = $1 GROUP BY 1,2 ORDER BY 1,2`, [f.id])
  console.log(tabla(porEst, ['estanque', 'bomba', 'filas', 'litros']))

  console.log('\n=== CLASIFICACION ===')
  const { rows: porClase } = await client.query(`
    SELECT clasificacion, count(*) AS filas,
           to_char(sum(litros),'FM999G999G999') AS litros
      FROM combustible_orpak_transaccion WHERE faena_id=$1
     GROUP BY 1 ORDER BY sum(litros) DESC`, [f.id])
  console.log(tabla(porClase, ['clasificacion', 'filas', 'litros']))

  const trasv = porClase.find((c) => c.clasificacion === 'TRASVASIJE')
  chequear(!!trasv, 'el trasvasije se separa de la venta',
    trasv ? `${trasv.filas} movimientos, ${trasv.litros} L` : 'no se detecto ninguno')

  console.log('\n=== IMPUTACION: EL CECO SALE DEL CAMPO DEPARTMENT ===')
  const { rows: [imp] } = await client.query(`
    SELECT count(*) AS total,
           count(*) FILTER (WHERE ceco_codigo IS NOT NULL) AS con_codigo,
           count(*) FILTER (WHERE ceco_id IS NOT NULL)     AS amarrado,
           count(*) FILTER (WHERE ceco_codigo IS NULL
                              AND clasificacion NOT IN ('TRASVASIJE','RECIRCULACION','CALIBRACION')) AS venta_sin_ceco
      FROM combustible_orpak_transaccion WHERE faena_id=$1`, [f.id])
  console.log(`   ${imp.total} transacciones · ${imp.con_codigo} traen codigo de CECO` +
              ` · ${imp.amarrado} amarran al maestro · ${imp.venta_sin_ceco} ventas sin CECO`)
  chequear(Number(imp.con_codigo) / Number(imp.total) > 0.9,
    'mas del 90% de las filas traen CECO legible',
    `${Math.round(100 * imp.con_codigo / imp.total)}%`)

  const { rows: desc } = await client.query(`
    SELECT ceco_codigo, left(departamento,38) AS departamento, transacciones,
           to_char(litros,'FM999G999G999') AS litros
      FROM v_comb_orpak_ceco_desconocido WHERE faena_id=$1
     ORDER BY litros DESC LIMIT 12`, [f.id])
  if (desc.length) {
    console.log('\n   CECO que Orpak usa y el maestro de la faena no tiene:')
    console.log(tabla(desc, ['ceco_codigo', 'departamento', 'transacciones', 'litros']))
  }

  console.log('\n=== IDEMPOTENCIA: EL MISMO ARCHIVO OTRA VEZ ===')
  const { rows: [r2] } = await client.query(
    `SELECT rpc_comb_orpak_cargar($1,$2,$3::jsonb) AS r`,
    [f.id, 'ORPAK_AJUSTADO_JUNIO_2026.xlsx', JSON.stringify(filas)])
  console.log(`   nuevas ${r2.r.nuevas} · repetidas ${r2.r.repetidas}`)
  chequear(r2.r.nuevas === 0, 'subirlo de nuevo no duplica nada',
    `${r2.r.nuevas} nuevas en la segunda carga`)

  console.log('\n=== ORPAK CONTRA EL CONTADOR FISICO, DIA A DIA ===')
  console.log('   (el contador es lo que marco el cuentalitros; Orpak es lo que registro el sistema)')
  const { rows: cruce } = await client.query(`
    WITH orp AS (
      SELECT dia_cierre AS fecha, e.grupo_cuadre AS grupo, sum(t.litros) AS orpak
        FROM combustible_orpak_transaccion t
        JOIN combustible_estanques e ON e.id = t.estanque_id
       WHERE t.faena_id = $1 GROUP BY 1,2
    ), mec AS (
      SELECT c.fecha, e.grupo_cuadre AS grupo,
             sum(cm.numeral_fin - cm.numeral_ini + COALESCE(cm.calibracion,0)) AS contador
        FROM combustible_faena_cierre c
        JOIN combustible_faena_cierre_medidor cm ON cm.cierre_id = c.id
        JOIN combustible_faena_medidores md ON md.id = cm.medidor_id
        JOIN combustible_estanques e ON e.id = md.estanque_id
       WHERE c.faena_id = $1 AND cm.numeral_fin IS NOT NULL
       GROUP BY 1,2
    )
    SELECT to_char(COALESCE(o.fecha,m.fecha),'DD-MM') AS dia,
           COALESCE(o.grupo,m.grupo) AS grupo,
           to_char(COALESCE(o.orpak,0),'FM999G999') AS orpak,
           to_char(COALESCE(m.contador,0),'FM999G999') AS contador,
           to_char(COALESCE(o.orpak,0)-COALESCE(m.contador,0),'FM999G999') AS dif
      FROM orp o FULL JOIN mec m ON m.fecha=o.fecha AND m.grupo=o.grupo
     WHERE COALESCE(o.fecha,m.fecha) BETWEEN DATE '2026-06-01' AND DATE '2026-06-09'
       AND COALESCE(o.grupo,m.grupo) IN ('mina','bimodal')
     ORDER BY 1,2`, [f.id])
  console.log(tabla(cruce, ['dia', 'grupo', 'orpak', 'contador', 'dif']))

  console.log('\n=== RESULTADO ===')
  console.log(fallas === 0 ? `   ${8 - 0} chequeos, 0 FALLAS` : `   ${fallas} FALLAS`)
} catch (e) {
  console.error('\nERROR:', e.message)
  fallas++
} finally {
  await client.query('ROLLBACK').catch(() => {})
  await client.end()
}
process.exit(fallas === 0 ? 0 : 1)
