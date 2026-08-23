#!/usr/bin/env node
// ============================================================================
// Los tres entregables, generados contra los datos reales de junio 2026
// ----------------------------------------------------------------------------
// Un exportador que sólo se puede probar haciendo clic no se prueba nunca. Acá
// se arman los tres libros fuera del navegador — con las mismas consultas y el
// mismo código que corre en la pantalla — y se revisa que los números que salen
// sean los que están en la base.
//
// Lo que se verifica:
//   · el Cierre Romeral trae una hoja por estación y una por día
//   · el FORM AC 066 trae el stock de cada estanque en la columna de su día
//   · la BBDD trae todas las transacciones, con la Semana ENAP resuelta
//   · los totales del libro coinciden con los totales de la base
//
// Uso:  node database/tests/entregables_junio.mjs [YYYY-MM-01] [carpeta_salida]
// ============================================================================

import { existsSync, writeFileSync } from 'node:fs'
import { resolve, dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from '../scripts/node_modules/pg/lib/index.js'
import dotenv from '../scripts/node_modules/dotenv/lib/main.js'
import ExcelJS from '../../frontend/node_modules/exceljs/excel.js'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })

const MES = process.argv[2] || '2026-06-01'
const SALIDA = process.argv[3] || process.env.TEMP || '.'

// PostgREST y el driver de Postgres no devuelven lo mismo: PostgREST manda las
// fechas como texto «YYYY-MM-DD» y los numeric como número JSON; pg manda Date
// y string. Si el arnés no iguala eso, la prueba encuentra fallas que no
// existen en el navegador — y peor, podría tapar las que sí existen.
pg.types.setTypeParser(1082, (v) => v)                    // date
pg.types.setTypeParser(1700, (v) => (v === null ? null : Number(v)))  // numeric
pg.types.setTypeParser(20,   (v) => (v === null ? null : Number(v)))  // bigint

const client = new pg.Client({
  connectionString: (process.env.SUPABASE_DB_URL || '').trim(),
  ssl: { rejectUnauthorized: false },
})

// El módulo del frontend habla con Supabase por HTTP. Acá se le pone delante un
// cliente equivalente contra Postgres, para ejercitar EL MISMO código de armado
// del libro sin levantar la aplicación.
//
// OJO CON ESTO, QUE COSTÓ CARO: el arnés tiene que imitar los LÍMITES de
// PostgREST, no sólo su forma. PostgREST devuelve como máximo 1.000 filas por
// respuesta, en silencio y sin error. La primera versión de este arnés
// consultaba Postgres sin tope, así que los tres entregables pasaban la prueba
// y el que se bajaba del navegador salía cortado en mil filas — con cara de
// completo. Un arnés más permisivo que la realidad no prueba: tranquiliza.
function supabaseFalso(faenaId) {
  return {
    from(vista) {
      const filtros = []
      const orden = []
      let rango = null
      const api = {
        select() { return api },
        eq(col, val) { filtros.push([col, '=', val]); return api },
        gte(col, val) { filtros.push([col, '>=', val]); return api },
        lte(col, val) { filtros.push([col, '<=', val]); return api },
        order(col) { orden.push(col); return api },
        range(desde, hasta) { rango = [desde, hasta]; return api },
        then(res, rej) {
          const cond = filtros.map(([c, op], i) => `"${c}" ${op} $${i + 1}`).join(' AND ')
          // El tope de PostgREST: 1.000 filas por respuesta, aunque el
          // llamador no pida rango.
          const TOPE = 1000
          const desde = rango ? rango[0] : 0
          const cuantas = rango ? Math.min(rango[1] - rango[0] + 1, TOPE) : TOPE
          const sql = `SELECT * FROM ${vista}` + (cond ? ` WHERE ${cond}` : '')
            + (orden.length ? ` ORDER BY ${orden.map((c) => `"${c}"`).join(', ')}` : '')
            + ` LIMIT ${cuantas} OFFSET ${desde}`
          return client.query(sql, filtros.map(([, , v]) => v))
            .then((r) => ({ data: r.rows, error: null }))
            .then(res, rej)
        },
      }
      return api
    },
  }
}

let fallas = 0
const chequear = (cond, texto, detalle) => {
  console.log(`   ${cond ? 'OK  ' : 'FALLA'}  ${texto}${detalle ? '  ->  ' + detalle : ''}`)
  if (!cond) fallas++
}

await client.connect()
try {
  const { rows: [f] } = await client.query(`SELECT id FROM faenas WHERE codigo='FAE-CMP-ROMERAL'`)

  const mod = await cargarEntregables(f.id)

  const [y, m] = MES.split('-').map(Number)
  const ultimo = new Date(Date.UTC(y, m, 0)).getUTCDate()
  const desde = MES
  const hasta = `${y}-${String(m).padStart(2, '0')}-${String(ultimo).padStart(2, '0')}`

  console.log(`\n=== ENTREGABLES DE ${MES.slice(0, 7)} ===`)

  // ── Los totales que dice la base ──
  const { rows: [ref] } = await client.query(`
    SELECT (SELECT count(*) FROM v_comb_bbdd
             WHERE faena_id=$1 AND dia_cierre BETWEEN $2 AND $3) AS bbdd_filas,
           (SELECT count(DISTINCT semana_enap) FROM v_comb_bbdd
             WHERE faena_id=$1 AND dia_cierre BETWEEN $2 AND $3) AS semanas,
           (SELECT count(DISTINCT estanque_id) FROM v_comb_form_ac066
             WHERE faena_id=$1 AND fecha BETWEEN $2 AND $3) AS estanques,
           (SELECT count(DISTINCT fecha) FROM v_comb_cierre_romeral_mes
             WHERE faena_id=$1 AND fecha BETWEEN $2 AND $3) AS dias`,
    [f.id, desde, hasta])
  console.log(`   la base tiene ${ref.bbdd_filas} transacciones en ${ref.semanas} semanas ENAP,`
    + ` ${ref.estanques} estanques y ${ref.dias} dias cerrados`)

  // ── BBDD ──
  console.log('\n--- BBDD ---')
  const bbdd = await mod.construirBbdd(f.id, MES)
  const wsB = bbdd.wb.getWorksheet('BBDD')
  chequear(wsB.actualRowCount - 1 === Number(ref.bbdd_filas),
    'la BBDD trae todas las transacciones', `${wsB.actualRowCount - 1} de ${ref.bbdd_filas}`)
  const colSemana = wsB.getRow(1).values.indexOf('Semana Enap')
  const semanas = new Set()
  wsB.eachRow((r, i) => { if (i > 1) semanas.add(r.getCell(colSemana).value) })
  chequear(semanas.size === Number(ref.semanas) && !semanas.has(''),
    'todas las filas tienen Semana ENAP', Array.from(semanas).sort().join(' · '))
  guardar(bbdd)

  // ── FORM AC 066 ──
  console.log('\n--- FORM AC 066 ---')
  const ac = await mod.construirFormAc066(f.id, MES)
  const wsA = ac.wb.worksheets[0]
  chequear(ac.filas === Number(ref.estanques),
    'un renglon por estanque', `${ac.filas} de ${ref.estanques}`)
  // El stock del dia 3 en la columna del dia 3, contra lo que dice la base.
  const { rows: [chk] } = await client.query(`
    SELECT estanque, stock FROM v_comb_form_ac066
     WHERE faena_id=$1 AND fecha=$2 AND stock IS NOT NULL ORDER BY orden_cierre LIMIT 1`,
    [f.id, `${MES.slice(0, 8)}03`])
  let hallado = null
  wsA.eachRow((r) => { if (String(r.getCell(3).value) === chk.estanque) hallado = r.getCell(8).value })
  chequear(hallado != null && Math.abs(Number(hallado) - Number(chk.stock)) < 0.5,
    `el stock del dia 3 de ${chk.estanque} cae en su columna`,
    `libro ${hallado} · base ${chk.stock}`)
  guardar(ac)

  // ── Cierre Romeral ──
  console.log('\n--- CIERRE ROMERAL ---')
  const cr = await mod.construirCierreRomeral(f.id, MES)
  const hojasDia = cr.wb.worksheets.filter((w) => /^\d{2}$/.test(w.name))
  const hojasEst = cr.wb.worksheets.filter((w) => !/^\d{2}$/.test(w.name))
  chequear(hojasDia.length === Number(ref.dias),
    'una hoja por dia cerrado', `${hojasDia.length} de ${ref.dias}`)
  chequear(hojasEst.length === Number(ref.estanques),
    'una hoja por estacion', `${hojasEst.length} de ${ref.estanques}`)
  const d1 = hojasDia[0]
  const tieneNumerales = d1 && d1.getSheetValues()
    .some((r) => r && String(r[2] ?? '').includes('NUMERALES'))
  chequear(!!tieneNumerales, 'la hoja del dia trae los numerales mecanicos')
  guardar(cr)

  console.log(`\n=== RESULTADO ===\n   ${fallas === 0 ? '6 chequeos, 0 FALLAS' : fallas + ' FALLAS'}`)
} catch (e) {
  console.error('\nERROR:', e.message)
  fallas++
} finally {
  await client.end()
}
process.exit(fallas === 0 ? 0 : 1)

function guardar(hecho) {
  const ruta = join(SALIDA, hecho.nombre)
  hecho.wb.xlsx.writeFile(ruta)
  console.log(`   -> ${ruta}`)
}

// El módulo del frontend habla con Supabase; acá se le pasa el cliente contra
// Postgres por el mismo nombre global. El archivo que se importa es EL MISMO
// que corre en el navegador, sin copias ni transformaciones.
async function cargarEntregables(faenaId) {
  globalThis.__supaShim = supabaseFalso(faenaId)
  globalThis.document = { createElement: () => ({ click() {} }) }
  globalThis.URL = { createObjectURL: () => '', revokeObjectURL() {} }
  globalThis.Blob = class {}
  return import('../../frontend/src/lib/services/combustible-entregables.js')
}
