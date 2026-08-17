#!/usr/bin/env node
// ============================================================================
// cargar-combustible-faenas.mjs
// ----------------------------------------------------------------------------
// Lee las planillas de cierre de combustible de faena y carga el RESUMEN
// MENSUAL a `combustible_faena_resumen_mensual` (MIG296).
//
// No sube el detalle transaccional (~5.000 filas/mes por faena): eso pertenece
// a `combustible_movimientos` cuando la operación migre al sistema. Acá se
// carga lo que la gerencia necesita para decidir —volumen, fluctuación y
// cobertura de fechas— con trazabilidad del archivo de origen.
//
// Estructura esperada de la carpeta:
//   <raiz>/FRANKE/<Mes>/*Control Suministro*.xlsx      hoja CONTROL ABASTECIMIENTO
//   <raiz>/CMP ROMERAL/<Mes>/<dd.mm>/BBDD MES*.xlsx    hoja BBDD
//
// Uso:
//   node cargar-combustible-faenas.mjs "C:/.../COMBUSTIBLE FAENAS"
//   node cargar-combustible-faenas.mjs "<raiz>" --dry-run
// ============================================================================

import { readdirSync, statSync, existsSync } from 'node:fs'
import { resolve, dirname, join, basename } from 'node:path'
import { fileURLToPath } from 'node:url'
import ExcelJS from 'exceljs'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })

const RAIZ = process.argv[2]
const DRY = process.argv.includes('--dry-run')

if (!RAIZ || !existsSync(RAIZ)) {
  console.error('Uso: node cargar-combustible-faenas.mjs "<carpeta COMBUSTIBLE FAENAS>" [--dry-run]')
  process.exit(2)
}

// ── helpers de lectura de celda ────────────────────────────────────────────
// ExcelJS devuelve Date para fechas, {result} para fórmulas y {richText} para
// texto con formato. Sin este orden, las fechas se pierden como null.
const val = (c) => {
  let v = c?.value
  if (v instanceof Date) return v
  if (v && typeof v === 'object') {
    if (v.result instanceof Date) return v.result
    v = v.result ?? v.text ?? v.richText?.map((t) => t.text).join('') ?? null
  }
  return v
}
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0 }
const dia = (v) => {
  if (v instanceof Date) {
    // Las fechas de Excel vienen en UTC medianoche; tomar la parte de fecha
    // directamente evita que un huso negativo las corra al día anterior.
    return new Date(Date.UTC(v.getUTCFullYear(), v.getUTCMonth(), v.getUTCDate()))
      .toISOString().slice(0, 10)
  }
  if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}/.test(v)) return v.slice(0, 10)
  return null
}
const topN = (obj, n = 20) => Object.entries(obj)
  .sort((a, b) => b[1] - a[1]).slice(0, n)
  .map(([clave, litros]) => ({ clave, litros: Math.round(litros) }))

const txt = (c) => String(val(c) ?? '').trim().toUpperCase()

/**
 * Fluctuación por estanque desde el "Cierre" de Romeral (hojas BIMODAL, MINA,
 * CASA FUERZA). Cada hoja es un cuadre diario: teórico vs. físico.
 *
 * Dos trampas que obligan a no leer el mes completo:
 *  1. El teórico viene precalculado para los 31 días, así que los días
 *     futuros traen físico = 0 y una "variación" de -teórico. Sumar todo daba
 *     -289% en BIMODAL.
 *  2. El último día suele estar a medias: el 13-ago MINA registra 30.000 L de
 *     recepción sin lectura física (-11.700 L de falsa variación).
 *
 * Por eso se corta en el último día con despachos o ventas REALES. Con ese
 * corte el resultado cuadra con el total que la propia planilla calcula
 * (BIMODAL -291 L, MINA +1.097 L). Aun así es una heurística: el valor queda
 * marcado origen='excel' y gerencia lo corrige desde el panel si no cuadra.
 */
async function leerFluctuacionesRomeral(archivo, anio, mes) {
  const wb = new ExcelJS.Workbook()
  await wb.xlsx.readFile(archivo)
  const out = []

  for (const ws of wb.worksheets) {
    // Solo las hojas de estanque: tienen el par FINAL TEORICO / FINAL FISICO.
    let cVar = null, cVen = null, cTeo = null, cFis = null, cRec = null, cDes = null
    for (let col = 1; col <= 30; col++) {
      const g = txt(ws.getRow(4).getCell(col)), s = txt(ws.getRow(5).getCell(col))
      if (g.startsWith('VARIACION') && s === 'LITROS') cVar = col
      if (g === 'TOTAL' && s === 'VENTAS')             cVen = col
      if (g === 'FINAL' && s === 'TEORICO')            cTeo = col
      if (g === 'FINAL' && s === 'FISICO')             cFis = col
      if (s === 'RECEP.')                              cRec = col
      if (s.includes('ORPAK'))                         cDes = col
    }
    if (cTeo == null || cFis == null || cVar == null) continue

    const filas = []
    for (let r = 6; r <= ws.rowCount; r++) {
      const d = num(val(ws.getRow(r).getCell(1)))
      if (!d || d < 1 || d > 31) continue
      const g = (c) => (c == null ? 0 : (num(val(ws.getRow(r).getCell(c))) ?? 0))
      filas.push({ d, rec: g(cRec), des: g(cDes), ven: g(cVen),
                   teo: g(cTeo), fis: g(cFis), v: g(cVar) })
    }
    const ultimo = Math.max(0, ...filas.filter((f) => f.des > 0 || f.ven > 0).map((f) => f.d))
    if (!ultimo) continue
    const usar = filas.filter((f) => f.d <= ultimo && f.fis > 0)
    if (!usar.length) continue

    const fluct = usar.reduce((a, f) => a + f.v, 0)
    const desp = usar.reduce((a, f) => a + f.des, 0)
    const ventas = usar.reduce((a, f) => a + f.ven, 0)
    const base = ventas || desp
    const pct = base ? fluct / base : null

    // ── Filtro de plausibilidad ────────────────────────────────────────────
    // En combustible una fluctuación mensual sobre 5% no existe: es un error
    // de lectura. Las hojas de CAMIÓN dan 40%, 63% y 87% porque son estanques
    // móviles y su columna de "ventas" significa otra cosa que en un estanque
    // fijo. Cargar ese número sería peor que no cargar nada: gerencia lo vería
    // como una merma catastrófica inexistente.
    //
    // Se registra igual el punto —para que se sepa que existe y que falta—,
    // pero con la fluctuación en NULL y la nota de por qué. Gerencia lo
    // completa desde el panel.
    const PLAUSIBLE = pct != null && Math.abs(pct) <= 0.05

    out.push({
      faena_codigo: 'ROMERAL',
      anio, mes,
      punto: ws.name.trim(),
      litros_despachados: Math.round(base),
      fluctuacion_lt: PLAUSIBLE ? Math.round(fluct) : null,
      fluctuacion_pct: PLAUSIBLE ? pct : null,
      dias_cuadrados: usar.length,
      ultimo_dia_cuadre: `${anio}-${String(mes).padStart(2, '0')}-${String(ultimo).padStart(2, '0')}`,
      fuente_archivo: basename(archivo),
      plausible: PLAUSIBLE,
      observacion: PLAUSIBLE ? null
        : `Requiere carga manual. La lectura automática de la hoja "${ws.name.trim()}" `
          + `dio ${(pct * 100).toFixed(1)}% sobre ${Math.round(base).toLocaleString('es-CL')} L, `
          + 'valor implausible para combustible (umbral 5%). Las hojas de camión '
          + 'son estanques móviles y su columna de ventas no es comparable con la '
          + 'de un estanque fijo.',
    })
  }
  return out
}

const buscarArchivos = (dir, patron) => {
  const out = []
  const walk = (d) => {
    for (const e of readdirSync(d)) {
      const p = join(d, e)
      if (statSync(p).isDirectory()) walk(p)
      else if (patron.test(e) && !e.startsWith('~$')) out.push(p)
    }
  }
  if (existsSync(dir)) walk(dir)
  return out
}

// ── FRANKE ─────────────────────────────────────────────────────────────────
async function leerFranke(archivo) {
  const wb = new ExcelJS.Workbook()
  await wb.xlsx.readFile(archivo)
  const ws = wb.getWorksheet('CONTROL ABASTECIMIENTO')
  if (!ws) return null

  // Columnas (fila 9 es el encabezado real; los datos parten en la 10):
  //  2 Fecha · 4 PPU Camión · 7 Litros · 9 Concepto · 13 Empresa · 15 Ubicación
  const porConcepto = {}, porPunto = {}, porEmpresa = {}, dias = new Set()
  let filas = 0, min = null, max = null

  for (let r = 10; r <= ws.rowCount; r++) {
    const row = ws.getRow(r)
    const f = dia(val(row.getCell(2)))
    if (!f) continue
    const lt = num(val(row.getCell(7)))
    const concepto = String(val(row.getCell(9)) ?? '').trim() || '(sin concepto)'
    const camion = String(val(row.getCell(4)) ?? '').trim() || '(sin camión)'
    const empresa = String(val(row.getCell(13)) ?? '').trim() || '(sin empresa)'

    filas++; dias.add(f)
    if (!min || f < min) min = f
    if (!max || f > max) max = f
    porConcepto[concepto] = (porConcepto[concepto] ?? 0) + lt
    if (concepto.toLowerCase() === 'venta') {
      porPunto[camion] = (porPunto[camion] ?? 0) + lt
      porEmpresa[empresa] = (porEmpresa[empresa] ?? 0) + lt
    }
  }
  if (!filas) return null

  const venta = porConcepto['Venta'] ?? 0
  const trasv = porConcepto['Trasvasije'] ?? 0
  const stockIni = porConcepto['Stock Inicial'] ?? null
  // La fluctuación viene declarada en la celda N7 del propio cierre.
  const fluct = num(val(ws.getRow(7).getCell(14)))
  const fluctPct = num(val(ws.getRow(7).getCell(15)))

  return {
    faena_codigo: 'FRANKE',
    faena_nombre: 'Franke — CM Cenizas, Taltal',
    operacion: 'Coquimbo',
    anio: Number(min.slice(0, 4)),
    mes: Number(min.slice(5, 7)),
    transacciones: filas,
    litros_venta: Math.round(venta),
    litros_trasvasije: Math.round(trasv),
    litros_total: Math.round(venta + trasv),
    stock_inicial: stockIni != null ? Math.round(stockIni) : null,
    fluctuacion_lt: fluct || null,
    fluctuacion_pct: fluctPct || null,
    dias_con_registro: dias.size,
    fecha_min: min,
    fecha_max: max,
    detalle_por_punto: topN(porPunto),
    detalle_por_empresa: topN(porEmpresa),
    fuente_archivo: basename(archivo),
  }
}

// ── ROMERAL ────────────────────────────────────────────────────────────────
async function leerRomeral(archivo) {
  const wb = new ExcelJS.Workbook()
  await wb.xlsx.readFile(archivo)
  const ws = wb.getWorksheet('BBDD')
  if (!ws) return null

  // Columnas: 2 Date · 5 Equipo · 7 Volumen · 8 Nombre Estacion · 9 Departamento
  const porPunto = {}, porEmpresa = {}, dias = new Set()
  let filas = 0, total = 0, min = null, max = null

  for (let r = 2; r <= ws.rowCount; r++) {
    const row = ws.getRow(r)
    const f = dia(val(row.getCell(2)))
    if (!f) continue
    const lt = num(val(row.getCell(7)))
    const estacion = String(val(row.getCell(8)) ?? '').trim() || '(sin estación)'
    const depto = String(val(row.getCell(9)) ?? '').trim() || '(sin departamento)'

    filas++; total += lt; dias.add(f)
    if (!min || f < min) min = f
    if (!max || f > max) max = f
    porPunto[estacion] = (porPunto[estacion] ?? 0) + lt
    porEmpresa[depto] = (porEmpresa[depto] ?? 0) + lt
  }
  if (!filas) return null

  return {
    faena_codigo: 'ROMERAL',
    faena_nombre: 'CMP — Romeral',
    operacion: 'Coquimbo',
    anio: Number(min.slice(0, 4)),
    mes: Number(min.slice(5, 7)),
    transacciones: filas,
    // El registro de Romeral es de despacho a equipo: todo es "venta"
    // (consumo del cliente); no distingue trasvasijes en esta planilla.
    litros_venta: Math.round(total),
    litros_trasvasije: 0,
    litros_total: Math.round(total),
    stock_inicial: null,
    fluctuacion_lt: null,
    fluctuacion_pct: null,
    dias_con_registro: dias.size,
    fecha_min: min,
    fecha_max: max,
    detalle_por_punto: topN(porPunto),
    detalle_por_empresa: topN(porEmpresa),
    fuente_archivo: basename(archivo),
  }
}

// ── main ───────────────────────────────────────────────────────────────────
const registros = []

for (const a of buscarArchivos(join(RAIZ, 'FRANKE'), /Control Suministro.*\.xlsx$/i)) {
  const r = await leerFranke(a)
  if (r) { registros.push(r); console.log(`✓ Franke  ${r.anio}-${String(r.mes).padStart(2, '0')}  ${r.transacciones} transacciones  ${r.litros_total.toLocaleString('es-CL')} L`) }
  else console.warn(`⚠ sin datos utilizables: ${a}`)
}

const fluctuaciones = []

for (const a of buscarArchivos(join(RAIZ, 'CMP ROMERAL'), /^BBDD MES.*\.xlsx$/i)) {
  const r = await leerRomeral(a)
  if (r) { registros.push(r); console.log(`✓ Romeral ${r.anio}-${String(r.mes).padStart(2, '0')}  ${r.transacciones} transacciones  ${r.litros_total.toLocaleString('es-CL')} L`) }
  else console.warn(`⚠ sin datos utilizables: ${a}`)
}

// Fluctuación por estanque. Se toma el período del BBDD ya leído: la celda
// "MES:" del propio cierre está desactualizada (dice mayo y enero en un
// archivo de agosto), así que no se puede usar como fuente del período.
const periodoRomeral = registros.find((r) => r.faena_codigo === 'ROMERAL')
if (periodoRomeral) {
  for (const a of buscarArchivos(join(RAIZ, 'CMP ROMERAL'), /Cierre Romeral.*\.xlsx$/i)) {
    const fs = await leerFluctuacionesRomeral(a, periodoRomeral.anio, periodoRomeral.mes)
    for (const f of fs) {
      fluctuaciones.push(f)
      if (f.plausible) {
        const p = (f.fluctuacion_pct * 100).toFixed(2) + '%'
        console.log(`  · ${f.punto.padEnd(14)} ${String(f.fluctuacion_lt).padStart(7)} L  ${p.padStart(8)}  (${f.dias_cuadrados} días)`)
      } else {
        console.log(`  ⚠ ${f.punto.padEnd(14)} lectura implausible → queda para carga MANUAL`)
      }
    }
  }
}

if (!registros.length) {
  console.error('No se encontró ninguna planilla legible bajo', RAIZ)
  process.exit(1)
}

if (DRY) {
  console.log('\n--dry-run: no se escribió nada en la base.\n')
  console.log(JSON.stringify({ registros, fluctuaciones }, null, 2))
  process.exit(0)
}

const client = new pg.Client({
  connectionString: (process.env.SUPABASE_DB_URL || '').trim(),
  ssl: { rejectUnauthorized: false },
})
await client.connect()

for (const r of registros) {
  await client.query(`
    INSERT INTO combustible_faena_resumen_mensual (
      faena_codigo, faena_nombre, operacion, anio, mes, transacciones,
      litros_venta, litros_trasvasije, litros_total, stock_inicial,
      fluctuacion_lt, fluctuacion_pct, dias_con_registro, fecha_min, fecha_max,
      detalle_por_punto, detalle_por_empresa, fuente_archivo
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18)
    -- Si gerencia ya corrigió esta fila a mano, el cargador NO la pisa: se
    -- limita a refrescar la trazabilidad del archivo. Un recargue accidental
    -- no puede borrar una corrección hecha para una reunión de directorio.
    ON CONFLICT (faena_codigo, anio, mes) DO UPDATE SET
      transacciones = CASE WHEN combustible_faena_resumen_mensual.corregido_manual
                           THEN combustible_faena_resumen_mensual.transacciones
                           ELSE EXCLUDED.transacciones END,
      litros_venta = CASE WHEN combustible_faena_resumen_mensual.corregido_manual
                          THEN combustible_faena_resumen_mensual.litros_venta
                          ELSE EXCLUDED.litros_venta END,
      litros_trasvasije = CASE WHEN combustible_faena_resumen_mensual.corregido_manual
                               THEN combustible_faena_resumen_mensual.litros_trasvasije
                               ELSE EXCLUDED.litros_trasvasije END,
      litros_total = CASE WHEN combustible_faena_resumen_mensual.corregido_manual
                          THEN combustible_faena_resumen_mensual.litros_total
                          ELSE EXCLUDED.litros_total END,
      fluctuacion_lt = CASE WHEN combustible_faena_resumen_mensual.corregido_manual
                            THEN combustible_faena_resumen_mensual.fluctuacion_lt
                            ELSE EXCLUDED.fluctuacion_lt END,
      fluctuacion_pct = CASE WHEN combustible_faena_resumen_mensual.corregido_manual
                             THEN combustible_faena_resumen_mensual.fluctuacion_pct
                             ELSE EXCLUDED.fluctuacion_pct END,
      stock_inicial = EXCLUDED.stock_inicial,
      dias_con_registro = EXCLUDED.dias_con_registro,
      fecha_min = EXCLUDED.fecha_min,
      fecha_max = EXCLUDED.fecha_max,
      detalle_por_punto = EXCLUDED.detalle_por_punto,
      detalle_por_empresa = EXCLUDED.detalle_por_empresa,
      fuente_archivo = EXCLUDED.fuente_archivo,
      cargado_at = NOW(),
      updated_at = NOW()
  `, [
    r.faena_codigo, r.faena_nombre, r.operacion, r.anio, r.mes, r.transacciones,
    r.litros_venta, r.litros_trasvasije, r.litros_total, r.stock_inicial,
    r.fluctuacion_lt, r.fluctuacion_pct, r.dias_con_registro, r.fecha_min, r.fecha_max,
    JSON.stringify(r.detalle_por_punto), JSON.stringify(r.detalle_por_empresa),
    r.fuente_archivo,
  ])
}

// ── Fluctuación por estanque ───────────────────────────────────────────────
// Misma regla: lo corregido a mano manda sobre lo que traiga la planilla.
for (const f of fluctuaciones) {
  await client.query(`
    INSERT INTO combustible_fluctuacion_punto (
      faena_codigo, anio, mes, punto, litros_despachados,
      fluctuacion_lt, fluctuacion_pct, dias_cuadrados, ultimo_dia_cuadre,
      origen, fuente_archivo, observacion
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'excel',$10,$11)
    ON CONFLICT (faena_codigo, anio, mes, punto) DO UPDATE SET
      litros_despachados = CASE WHEN combustible_fluctuacion_punto.corregido_manual
                                THEN combustible_fluctuacion_punto.litros_despachados
                                ELSE EXCLUDED.litros_despachados END,
      fluctuacion_lt = CASE WHEN combustible_fluctuacion_punto.corregido_manual
                            THEN combustible_fluctuacion_punto.fluctuacion_lt
                            ELSE EXCLUDED.fluctuacion_lt END,
      fluctuacion_pct = CASE WHEN combustible_fluctuacion_punto.corregido_manual
                             THEN combustible_fluctuacion_punto.fluctuacion_pct
                             ELSE EXCLUDED.fluctuacion_pct END,
      dias_cuadrados = EXCLUDED.dias_cuadrados,
      ultimo_dia_cuadre = EXCLUDED.ultimo_dia_cuadre,
      fuente_archivo = EXCLUDED.fuente_archivo,
      observacion = CASE WHEN combustible_fluctuacion_punto.corregido_manual
                         THEN combustible_fluctuacion_punto.observacion
                         ELSE EXCLUDED.observacion END,
      updated_at = NOW()
  `, [
    f.faena_codigo, f.anio, f.mes, f.punto, f.litros_despachados,
    f.fluctuacion_lt, f.fluctuacion_pct, f.dias_cuadrados, f.ultimo_dia_cuadre,
    f.fuente_archivo, f.observacion,
  ])
}

await client.end()
console.log(`\n✓ ${registros.length} cierre(s) y ${fluctuaciones.length} fluctuación(es) por estanque cargadas.`)
console.log('  Las filas ya corregidas a mano por gerencia NO fueron modificadas.')
