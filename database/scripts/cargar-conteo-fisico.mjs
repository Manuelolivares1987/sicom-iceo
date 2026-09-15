#!/usr/bin/env node
// ============================================================================
// cargar-conteo-fisico.mjs
// ----------------------------------------------------------------------------
// Carga un inventario físico (Excel CODIGO | TALLA | COLOR | CANTIDAD |
// DESCRIPCION) contra una bodega usando el flujo oficial del sistema:
//
//   1. Productos nuevos → alta en `productos` (nunca modifica los existentes).
//   2. Conteo → `conteos_inventario` (tipo general, estado completado) con una
//      línea por producto contado en `conteo_detalle` (stock sistema vs físico).
//   3. Aprobación → rpc_aprobar_conteo_inventario: un ajuste (movimiento +
//      kardex + capa FIFO) por cada diferencia. Requiere MIG563.
//
// Variantes talla/color siguen la convención ya usada en el maestro:
//   CODIGO-<TALLA>  |  CODIGO-<inicial color>  |  CODIGO-<TALLA><inicial color>
//   (la última solo cuando la misma talla aparece en 2 colores, p.ej. -LB/-LC).
//
// Todo corre en UNA transacción. Sin --apply hace ROLLBACK (simulación).
//
// Uso:
//   node cargar-conteo-fisico.mjs --file "<xlsx>" --bodega BOD-CQB-F01 \
//        --fecha 2026-09-14 --usuario <uuid> [--apply]
// ============================================================================
import ExcelJS from 'exceljs'
import pg from 'pg'
import dotenv from 'dotenv'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { writeFileSync, mkdirSync } from 'node:fs'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > -1 ? process.argv[i + 1] : d }
const FILE    = arg('--file')
const BODEGA  = arg('--bodega', 'BOD-CQB-F01')
const FECHA   = arg('--fecha')
const USUARIO = arg('--usuario')
const APPLY   = process.argv.includes('--apply')
if (!FILE || !FECHA || !USUARIO) {
  console.error('Uso: --file <xlsx> --fecha YYYY-MM-DD --usuario <uuid> [--bodega COD] [--apply]'); process.exit(2)
}

// ── Categoría por prefijo (misma lógica que el maestro ya cargado) ───────────
const CAT = { REP: 'repuesto', AFE: 'ferreteria', ISE: 'implementos_de_seguridad', AOF: 'articulos_de_oficina',
              IAF: 'implementos_de_aseo_y_fungibles', CLU: 'combustibles_y_lubricantes', EQU: 'equipos', COM: 'repuesto' }

// ── 1. Leer Excel ────────────────────────────────────────────────────────────
const s = (v) => v == null ? '' : (typeof v === 'object'
  ? (v.text ?? v.result ?? (v.richText ? v.richText.map(t => t.text).join('') : String(v))) : String(v))
const wb = new ExcelJS.Workbook(); await wb.xlsx.readFile(FILE)
const ws = wb.worksheets[0]
const raw = []
for (let r = 2; r <= ws.rowCount; r++) {
  const row = ws.getRow(r)
  const codigo = s(row.getCell(1).value).trim().toUpperCase()
  if (!codigo) continue
  raw.push({
    fila: r, codigo,
    talla: s(row.getCell(2).value).trim().toUpperCase(),
    color: s(row.getCell(3).value).trim().toUpperCase(),
    cant: Number(row.getCell(4).value ?? 0),
    desc: s(row.getCell(5).value).replace(/\s+/g, ' ').trim(),
  })
}

// ── 2. Resolver código final (variantes) ─────────────────────────────────────
const alertas = []
const COLORES_EN_TALLA = new Set(['BLANCO', 'BLANCA', 'NEGRO', 'ROJO', 'AZUL', 'VERDE', 'GRIS', 'AMBAR'])
for (const x of raw) {
  if (x.talla && COLORES_EN_TALLA.has(x.talla) && !x.color) { x.color = x.talla; x.talla = ''; alertas.push(`Fila ${x.fila} ${x.codigo}: "${x.color}" venía en la columna TALLA, se toma como color`) }
  if (!Number.isFinite(x.cant)) { alertas.push(`Fila ${x.fila} ${x.codigo}: cantidad no numérica → 0`); x.cant = 0 }
  if (x.cant < 0) { alertas.push(`Fila ${x.fila} ${x.codigo}: cantidad negativa (${x.cant}) → se toma 0`); x.cant = 0 }
  if (/\[@|\+\[/.test(x.desc)) { alertas.push(`Fila ${x.fila} ${x.codigo}: descripción es una fórmula rota ("${x.desc}"), se ignora`); x.desc = '' }
}
const familias = new Map()
for (const x of raw) { if (!familias.has(x.codigo)) familias.set(x.codigo, []); familias.get(x.codigo).push(x) }

const client = new pg.Client({ connectionString: process.env.SUPABASE_DB_URL, ssl: { rejectUnauthorized: false } })
await client.connect()
const { rows: prods } = await client.query('select id, codigo, nombre, categoria, subcategoria, unidad_medida from productos')
const byCod = new Map(prods.map(p => [p.codigo.toUpperCase(), p]))
const { rows: [bod] } = await client.query('select id, nombre from bodegas where codigo = $1', [BODEGA])
if (!bod) { console.error(`Bodega ${BODEGA} no existe`); process.exit(2) }
const { rows: [usr] } = await client.query('select id, nombre_completo, rol from usuarios_perfil where id = $1', [USUARIO])
if (!usr) { console.error(`Usuario ${USUARIO} no existe en usuarios_perfil`); process.exit(2) }

const inicial = (c) => c.replace('CAFÉ', 'CAFE').trim()[0]
const lineas = new Map() // codigoFinal → { codigo, base, talla, color, cant, desc, filas[] }
for (const [base, filas] of familias) {
  const esFamilia = filas.some(f => f.talla || f.color)
  for (const f of filas) {
    let cod = base
    if (esFamilia && !f.talla && !f.color) {
      if (f.cant === 0 && !byCod.has(base)) { alertas.push(`Fila ${f.fila} ${base}: línea sin talla/color con cantidad 0 dentro de una familia con variantes → se omite`); continue }
      cod = base
    } else if (f.talla || f.color) {
      const unicoEnBD = byCod.has(base) && !prods.some(p => p.codigo.toUpperCase().startsWith(base + '-')) && filas.length === 1
      if (unicoEnBD) {
        cod = base // el maestro ya lo tiene sin sufijo y es la única variante
      } else if (f.talla) {
        const mismaTalla = filas.filter(g => g.talla === f.talla)
        const colores = new Set(mismaTalla.map(g => g.color).filter(Boolean))
        cod = (colores.size > 1) ? `${base}-${f.talla}${inicial(f.color)}` : `${base}-${f.talla}`
      } else {
        cod = `${base}-${inicial(f.color)}`
      }
    }
    const l = lineas.get(cod)
    if (l) {
      l.cant += f.cant; l.filas.push(f.fila); l.repetido = true
    } else {
      lineas.set(cod, { codigo: cod, base, talla: f.talla, color: f.color, cant: f.cant, desc: f.desc, filas: [f.fila] })
    }
  }
}

for (const l of lineas.values()) {
  if (l.repetido) alertas.push(`Filas ${l.filas.join('/')} → ${l.codigo}: código repetido en el Excel, cantidades sumadas (${l.cant})`)
  if (!l.talla && !l.color && prods.some(p => p.codigo.toUpperCase().startsWith(l.codigo + '-')))
    alertas.push(`${l.codigo} (filas ${l.filas.join('/')}): el maestro lo tiene POR TALLA/COLOR pero el Excel no trae la variante → queda en el código base con ${l.cant} un.; el bodeguero debe redistribuir por talla`)
}

// ── 3. Clasificar: existentes vs nuevos ──────────────────────────────────────
const subcatPorPrefijo = new Map()
{
  const cnt = new Map()
  for (const p of prods) {
    const k = p.codigo.slice(0, 6).toUpperCase(); const sc = p.subcategoria || 'POR DEFINIR'
    if (!cnt.has(k)) cnt.set(k, new Map()); cnt.get(k).set(sc, (cnt.get(k).get(sc) || 0) + 1)
  }
  for (const [k, m] of cnt) subcatPorPrefijo.set(k, [...m.entries()].sort((a, b) => b[1] - a[1])[0][0])
}
const nuevos = [], existentes = []
for (const l of lineas.values()) {
  const p = byCod.get(l.codigo)
  if (p) { existentes.push({ ...l, producto_id: p.id, nombre_bd: p.nombre }); continue }
  const baseProd = byCod.get(l.base)
  let nombre = l.desc || baseProd?.nombre || l.codigo
  const variante = [l.talla && `Talla ${l.talla}`, l.color && `Color ${l.color}`].filter(Boolean).join(' / ')
  if (variante && l.codigo !== l.base) nombre = `${nombre} (${variante})`
  nuevos.push({
    ...l, nombre: nombre.slice(0, 200),
    categoria: baseProd?.categoria || CAT[l.codigo.slice(0, 3)] || 'repuesto',
    subcategoria: baseProd?.subcategoria || subcatPorPrefijo.get(l.codigo.slice(0, 6)) || 'POR DEFINIR',
    unidad: baseProd?.unidad_medida || 'un',
  })
}

// ── 4. Transacción ───────────────────────────────────────────────────────────
const resumen = { bodega: bod.nombre, fecha: FECHA, usuario: usr.nombre_completo, filasExcel: raw.length,
  lineas: lineas.size, existentes: existentes.length, nuevos: nuevos.length, unidadesContadas: [...lineas.values()].reduce((a, b) => a + b.cant, 0) }
await client.query('BEGIN')
try {
  // --pre-sql: SQL que corre dentro de la misma transacción antes de la carga
  // (p.ej. simular con la MIG563 todavía no aplicada; sin --apply se revierte).
  const PRE = arg('--pre-sql')
  if (PRE) { const { readFileSync } = await import('node:fs'); await client.query(readFileSync(PRE, 'utf8')); resumen.pre_sql = PRE }
  // 4.1 alta de productos nuevos
  for (const n of nuevos) {
    const { rows: [p] } = await client.query(
      `insert into productos (codigo, nombre, categoria, subcategoria, unidad_medida, costo_unitario_actual, metodo_valorizacion, stock_minimo, tiene_vencimiento, created_by)
       values ($1,$2,$3,$4,$5,0,'cpp',0,false,$6) returning id`,
      [n.codigo, n.nombre, n.categoria, n.subcategoria, n.unidad, USUARIO])
    n.producto_id = p.id
  }
  // 4.2 conteo
  const obs = `Inventario físico ${FECHA} — ${bod.nombre}. Archivo ${FILE.split(/[\\/]/).pop()} (${raw.length} filas, ${lineas.size} productos). Carga vía cargar-conteo-fisico.mjs.`
  const { rows: [conteo] } = await client.query(
    `insert into conteos_inventario (bodega_id, tipo, fecha_inicio, fecha_fin, estado, responsable_id, observaciones, created_by)
     values ($1,'general',$2::date,$2::date + interval '23 hours','completado',$3,$4,$3) returning id`,
    [bod.id, FECHA, USUARIO, obs])
  // 4.3 detalle
  const todas = [...existentes, ...nuevos]
  const { rows: stock } = await client.query('select producto_id, cantidad, costo_promedio from stock_bodega where bodega_id=$1', [bod.id])
  const stockBy = new Map(stock.map(r => [r.producto_id, r]))
  const vals = []; const params = []
  todas.forEach((l, i) => {
    const st = stockBy.get(l.producto_id); const sis = Number(st?.cantidad ?? 0); const cpp = Number(st?.costo_promedio ?? 0)
    const o = i * 6
    vals.push(`($${o + 1},$${o + 2},$${o + 3},$${o + 4},$${o + 5},$${o + 6})`)
    params.push(conteo.id, l.producto_id, sis, l.cant, (l.cant - sis) * cpp, `Excel fila(s) ${l.filas.join('/')}`)
    l.sistema = sis
  })
  for (let i = 0; i < vals.length; i += 500) {
    const chunk = vals.slice(i, i + 500); const p = params.slice(i * 6, (i + 500) * 6)
    // renumerar placeholders del chunk
    const sql = chunk.map((_, j) => { const o = j * 6; return `($${o + 1},$${o + 2},$${o + 3},$${o + 4},$${o + 5},$${o + 6})` }).join(',')
    await client.query(`insert into conteo_detalle (conteo_id, producto_id, stock_sistema, stock_fisico, diferencia_valorizada, motivo) values ${sql}`, p)
  }
  // 4.4 aprobar
  const { rows: [{ r }] } = await client.query('select rpc_aprobar_conteo_inventario($1,$2) r', [conteo.id, USUARIO])
  resumen.conteo_id = conteo.id; resumen.aprobacion = r

  // 4.5 verificación
  const { rows: [chk] } = await client.query(`
    select count(*) filas_stock, sum(sb.cantidad) unidades_stock,
           (select coalesce(sum(cantidad_disponible),0) from inventario_capas ic where ic.bodega_id=$1 and ic.estado='disponible') unidades_fifo
      from stock_bodega sb where sb.bodega_id=$1`, [bod.id])
  const { rows: desv } = await client.query(`
    select p.codigo, sb.cantidad stock, coalesce(sum(ic.cantidad_disponible),0) fifo
      from stock_bodega sb join productos p on p.id=sb.producto_id
      left join inventario_capas ic on ic.producto_id=sb.producto_id and ic.bodega_id=sb.bodega_id and ic.estado='disponible'
     where sb.bodega_id=$1 group by 1,2 having sb.cantidad <> coalesce(sum(ic.cantidad_disponible),0)`, [bod.id])
  const { rows: [xls] } = await client.query(`
    select count(*) n, sum(stock_fisico) fisico from conteo_detalle where conteo_id=$1`, [conteo.id])
  resumen.verificacion = { stock_bodega: chk, conteo: xls, productos_stock_vs_fifo_desviados: desv.length, ejemplos: desv.slice(0, 5) }
  const okUnidades = Math.abs(Number(chk.unidades_stock) - resumen.unidadesContadas) < 0.001
  resumen.verificacion.unidades_cuadran_con_excel = okUnidades
  if (!okUnidades) throw new Error(`Stock final (${chk.unidades_stock}) no cuadra con Excel (${resumen.unidadesContadas})`)
  if (desv.length) throw new Error(`Quedan ${desv.length} productos con stock ≠ capas FIFO`)

  if (APPLY) { await client.query('COMMIT'); resumen.resultado = 'APLICADO (COMMIT)' }
  else { await client.query('ROLLBACK'); resumen.resultado = 'SIMULACIÓN (ROLLBACK) — usa --apply para grabar' }
} catch (e) {
  await client.query('ROLLBACK')
  resumen.resultado = 'ERROR (ROLLBACK): ' + e.message
  console.error(e)
}
await client.end()

// ── 5. Reporte ───────────────────────────────────────────────────────────────
const outDir = resolve(__dirname, '../../reportes'); mkdirSync(outDir, { recursive: true })
const tag = `${BODEGA}_${FECHA}${APPLY ? '' : '_simulacion'}`
const difs = [...existentes, ...nuevos].filter(l => l.sistema !== undefined && l.cant !== l.sistema)
const csv = ['codigo;nombre;talla;color;stock_sistema;stock_fisico;diferencia;origen;filas_excel',
  ...[...existentes, ...nuevos].map(l => [l.codigo, (l.nombre_bd || l.nombre || '').replace(/;/g, ','), l.talla, l.color, l.sistema ?? '', l.cant, (l.cant - (l.sistema ?? 0)), l.nombre_bd ? 'existente' : 'NUEVO', l.filas.join('/')].join(';'))].join('\n')
writeFileSync(resolve(outDir, `conteo_${tag}.csv`), '﻿' + csv, 'utf8')
writeFileSync(resolve(outDir, `conteo_${tag}_alertas.txt`), alertas.join('\n'), 'utf8')
writeFileSync(resolve(outDir, `conteo_${tag}_resumen.json`), JSON.stringify(resumen, null, 2), 'utf8')

console.log(JSON.stringify(resumen, null, 2))
console.log(`\nDiferencias: ${difs.length} (positivas ${difs.filter(l => l.cant > l.sistema).length}, negativas ${difs.filter(l => l.cant < l.sistema).length})`)
console.log(`Alertas: ${alertas.length}`); alertas.forEach(a => console.log('  · ' + a))
console.log(`\nReportes en ${outDir}/conteo_${tag}*`)
