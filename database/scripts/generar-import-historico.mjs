#!/usr/bin/env node
// Lee 'Historico OS Auditoria.xlsx' hoja 'Detalle OS' y produce 2 cosas:
//
//  1. /tmp/historico_payload.json - el payload jsonb listo para llamar
//     rpc_importar_historial_os_legacy(p_payload jsonb)
//
//  2. Pega-y-corre.sql - un SELECT sobre el RPC que se puede pegar
//     directamente en el SQL editor de Supabase (sin necesitar service key).
//
// Uso: node generar-import-historico.mjs
// Salida en mismo directorio: payload.json y aplicar-historico.sql

import ExcelJS from 'exceljs'
import { writeFileSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const FILE = 'C:\\Users\\Manuel Olivares\\Desktop\\2026\\PILLADO\\Mantenimiento\\Historico OS Auditoria.xlsx'

// ── Helpers ────────────────────────────────────────────────────────────────
function isTick(v) {
  if (v == null) return false
  const s = String(v).trim()
  return s === '✓' || s === 'x' || s === 'X' || s === '1' || s.toLowerCase() === 'si'
}

function toNumber(v) {
  if (v == null || v === '') return null
  if (typeof v === 'number') return v
  if (typeof v === 'object' && 'result' in v) return toNumber(v.result)
  // Quitar comas (formato es-CL "1.234,5")
  const s = String(v).trim().replace(/\./g, '').replace(',', '.')
  const n = Number(s)
  return Number.isFinite(n) ? n : null
}

function toInt(v) {
  const n = toNumber(v)
  return n == null ? null : Math.round(n)
}

function toString(v) {
  if (v == null) return null
  if (typeof v === 'object' && 'text' in v) return String(v.text).trim() || null
  if (typeof v === 'object' && 'result' in v) return String(v.result).trim() || null
  if (v instanceof Date) return v.toISOString().slice(0, 10)
  const s = String(v).trim()
  return s || null
}

// Valida que sea fecha real (mes 1-12, dia 1-31). Postgres es estricto.
function fechaValida(yyyy, mm, dd) {
  const y = Number(yyyy), m = Number(mm), d = Number(dd)
  if (!Number.isInteger(y) || !Number.isInteger(m) || !Number.isInteger(d)) return false
  if (y < 1900 || y > 2100) return false
  if (m < 1 || m > 12) return false
  if (d < 1 || d > 31) return false
  // Validacion fina via Date
  const test = new Date(y, m - 1, d)
  return test.getFullYear() === y && test.getMonth() === m - 1 && test.getDate() === d
}

// Acepta '2026-04-20', '20-04-2026', '20-04-26', Date objects.
function toDate(v) {
  if (v == null || v === '') return null
  if (v instanceof Date) return v.toISOString().slice(0, 10)
  if (typeof v === 'object' && 'text' in v) return toDate(v.text)
  if (typeof v === 'object' && 'result' in v) return toDate(v.result)
  const s = String(v).trim()
  if (!s) return null

  let yyyy, mm, dd
  // YYYY-MM-DD
  let m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(s)
  if (m) { yyyy = m[1]; mm = m[2].padStart(2, '0'); dd = m[3].padStart(2, '0') }
  // DD-MM-YYYY o DD-MM-YY
  if (!m) {
    m = /^(\d{1,2})-(\d{1,2})-(\d{2,4})$/.exec(s)
    if (m) {
      dd = m[1].padStart(2, '0'); mm = m[2].padStart(2, '0')
      let yy = m[3]
      if (yy.length === 2) yy = '20' + yy
      if (yy.length === 3) yy = '2' + yy  // ej '025' -> '2025'
      yyyy = yy
    }
  }
  // DD/MM/YYYY
  if (!m) {
    m = /^(\d{1,2})\/(\d{1,2})\/(\d{2,4})$/.exec(s)
    if (m) {
      dd = m[1].padStart(2, '0'); mm = m[2].padStart(2, '0')
      let yy = m[3]
      if (yy.length === 2) yy = '20' + yy
      yyyy = yy
    }
  }
  if (!yyyy) return null
  if (!fechaValida(yyyy, mm, dd)) {
    console.warn(`  ⚠ Fecha invalida descartada: "${s}" (yyyy=${yyyy} mm=${mm} dd=${dd})`)
    return null
  }
  return `${yyyy}-${mm}-${dd}`
}

// ── Leer Excel ─────────────────────────────────────────────────────────────
console.log(`Leyendo ${FILE}...`)
const wb = new ExcelJS.Workbook()
await wb.xlsx.readFile(FILE)
const ws = wb.getWorksheet('Detalle OS')
if (!ws) { console.error('Hoja "Detalle OS" no existe'); process.exit(1) }

// Header en fila 2. Datos desde fila 3.
const colByHeader = {}
ws.getRow(2).eachCell({ includeEmpty: false }, (c, col) => {
  const h = String(c.value ?? '').trim()
  if (h) colByHeader[h] = col
})

const requiredHeaders = ['Año', 'OS#', 'OS CQBO', 'Patente']
for (const h of requiredHeaders) {
  if (!colByHeader[h]) {
    console.error(`Header faltante: ${h}`)
    process.exit(1)
  }
}

const payload = []
let saltadas = 0

for (let r = 3; r <= ws.rowCount; r++) {
  const row = ws.getRow(r)
  if (row.cellCount === 0) continue

  const osNumero = toString(row.getCell(colByHeader['OS#']).value)
  if (!osNumero) { saltadas++; continue }

  const item = {
    anio:             toInt(row.getCell(colByHeader['Año']).value),
    os_numero:        osNumero,
    os_cqbo:          toString(row.getCell(colByHeader['OS CQBO']).value),
    patente_raw:      toString(row.getCell(colByHeader['Patente']).value),
    tipo_equipo:      toString(row.getCell(colByHeader['Tipo']).value),
    marca_modelo:     toString(row.getCell(colByHeader['Marca/Modelo']).value),
    faena:            toString(row.getCell(colByHeader['Faena']).value),
    cliente:          toString(row.getCell(colByHeader['Cliente']).value),
    ubicacion:        toString(row.getCell(colByHeader['Ubicación']).value),
    fecha_recepcion:  toDate(row.getCell(colByHeader['Fecha Recepción']).value),
    fecha_entrega:    toDate(row.getCell(colByHeader['Fecha Entrega']).value),
    horometro:        toNumber(row.getCell(colByHeader['Horómetro']).value),
    kilometraje:      toNumber(row.getCell(colByHeader['Kilometraje']).value),
    cumplimiento_pct: toNumber(row.getCell(colByHeader['% Cumpl.']).value),
    responsable:      toString(row.getCell(colByHeader['Resp.']).value),
    flag_mant_prev:   isTick(row.getCell(colByHeader['Mant.Prev.']).value),
    flag_correctivo:  isTick(row.getCell(colByHeader['Correctivo']).value),
    flag_neumaticos:  isTick(row.getCell(colByHeader['Neumáticos']).value),
    flag_rev_tec:     isTick(row.getCell(colByHeader['Rev.Téc.']).value),
    flag_hab_estado:  isTick(row.getCell(colByHeader['Hab.Est.']).value),
    flag_serv_externo: isTick(row.getCell(colByHeader['Serv.Ext.']).value),
    num_trabajos:     toInt(row.getCell(colByHeader['# Trabajos']).value),
    horas_mo:         toNumber(row.getCell(colByHeader['Horas MO']).value),
  }
  payload.push(item)
}

console.log(`Filas procesadas: ${payload.length}`)
console.log(`Saltadas (sin OS#): ${saltadas}`)
console.log(`Patentes unicas: ${new Set(payload.map((p) => p.patente_raw).filter(Boolean)).size}`)

// ── Output 1: payload.json (para debugging) ────────────────────────────────
const jsonPath = resolve(__dirname, 'payload-historico.json')
writeFileSync(jsonPath, JSON.stringify(payload, null, 2), 'utf-8')
console.log(`✓ JSON escrito: ${jsonPath}`)

// ── Output 2: SQL pega-y-corre ─────────────────────────────────────────────
// Usamos INSERT directo (no RPC) para evitar el check de auth.uid() del RPC
// — el SQL editor de Supabase corre como postgres, no como un usuario auth.
const payloadEscaped = JSON.stringify(payload).replace(/'/g, "''")
const sql = `-- Pega-y-corre: importa el historial de OS legacy
-- Generado por generar-import-historico.mjs

-- 1. Insertar todas las OS desde el JSON (ON CONFLICT no duplica)
INSERT INTO historial_os_legacy (
    anio, os_numero, os_cqbo, patente_raw, tipo_equipo, marca_modelo,
    faena, cliente, ubicacion, fecha_recepcion, fecha_entrega,
    horometro, kilometraje, cumplimiento_pct, responsable,
    flag_mant_prev, flag_correctivo, flag_neumaticos,
    flag_rev_tec, flag_hab_estado, flag_serv_externo,
    num_trabajos, horas_mo
)
SELECT
    NULLIF(os->>'anio', '')::INT,
    os->>'os_numero',
    os->>'os_cqbo',
    os->>'patente_raw',
    os->>'tipo_equipo',
    os->>'marca_modelo',
    os->>'faena',
    os->>'cliente',
    os->>'ubicacion',
    NULLIF(os->>'fecha_recepcion', '')::DATE,
    NULLIF(os->>'fecha_entrega', '')::DATE,
    NULLIF(os->>'horometro', '')::NUMERIC,
    NULLIF(os->>'kilometraje', '')::NUMERIC,
    NULLIF(os->>'cumplimiento_pct', '')::NUMERIC,
    os->>'responsable',
    COALESCE((os->>'flag_mant_prev')::BOOLEAN, false),
    COALESCE((os->>'flag_correctivo')::BOOLEAN, false),
    COALESCE((os->>'flag_neumaticos')::BOOLEAN, false),
    COALESCE((os->>'flag_rev_tec')::BOOLEAN, false),
    COALESCE((os->>'flag_hab_estado')::BOOLEAN, false),
    COALESCE((os->>'flag_serv_externo')::BOOLEAN, false),
    NULLIF(os->>'num_trabajos', '')::INT,
    NULLIF(os->>'horas_mo', '')::NUMERIC
FROM jsonb_array_elements('${payloadEscaped}'::jsonb) AS os
ON CONFLICT (os_numero) DO NOTHING;

-- 2. Matchear activo_id por patente normalizada (case-insensitive, trim)
UPDATE historial_os_legacy h
   SET activo_id = a.id
  FROM activos a
 WHERE UPPER(TRIM(a.patente)) = UPPER(TRIM(h.patente_raw))
   AND h.activo_id IS NULL
   AND h.patente_raw IS NOT NULL;

-- 3. Verificar resultado final
SELECT
    COUNT(*)                                       AS total_filas,
    COUNT(*) FILTER (WHERE activo_id IS NOT NULL)  AS con_activo_match,
    COUNT(*) FILTER (WHERE activo_id IS NULL)      AS sin_activo_match,
    COUNT(DISTINCT activo_id) FILTER (WHERE activo_id IS NOT NULL) AS activos_distintos
  FROM historial_os_legacy;
`

const sqlPath = resolve(__dirname, 'aplicar-historico.sql')
writeFileSync(sqlPath, sql, 'utf-8')
console.log(`✓ SQL escrito: ${sqlPath} (${(sql.length / 1024).toFixed(1)} KB)`)
console.log('')
console.log('Siguiente paso: abrir ese .sql, copiar todo y pegarlo en SQL editor de Supabase.')
