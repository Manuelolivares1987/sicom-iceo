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

for (const a of buscarArchivos(join(RAIZ, 'CMP ROMERAL'), /^BBDD MES.*\.xlsx$/i)) {
  const r = await leerRomeral(a)
  if (r) { registros.push(r); console.log(`✓ Romeral ${r.anio}-${String(r.mes).padStart(2, '0')}  ${r.transacciones} transacciones  ${r.litros_total.toLocaleString('es-CL')} L`) }
  else console.warn(`⚠ sin datos utilizables: ${a}`)
}

if (!registros.length) {
  console.error('No se encontró ninguna planilla legible bajo', RAIZ)
  process.exit(1)
}

if (DRY) {
  console.log('\n--dry-run: no se escribió nada en la base.\n')
  console.log(JSON.stringify(registros, null, 2))
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
    ON CONFLICT (faena_codigo, anio, mes) DO UPDATE SET
      transacciones = EXCLUDED.transacciones,
      litros_venta = EXCLUDED.litros_venta,
      litros_trasvasije = EXCLUDED.litros_trasvasije,
      litros_total = EXCLUDED.litros_total,
      stock_inicial = EXCLUDED.stock_inicial,
      fluctuacion_lt = EXCLUDED.fluctuacion_lt,
      fluctuacion_pct = EXCLUDED.fluctuacion_pct,
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

await client.end()
console.log(`\n✓ ${registros.length} cierre(s) cargado(s) en combustible_faena_resumen_mensual.`)
