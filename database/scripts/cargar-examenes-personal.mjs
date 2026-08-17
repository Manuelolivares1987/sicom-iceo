#!/usr/bin/env node
// ============================================================================
// cargar-examenes-personal.mjs
// ----------------------------------------------------------------------------
// Carga la "Planilla Exámenes Personal" a prevencion_personal / _examenes
// (MIG298). Pedido por auditoría.
//
// La planilla tiene DOS bloques apilados en la misma hoja "Personal":
//   bloque 1 (fila 4 = encabezado): 5 exámenes, cada uno Laboratorio+Vencimiento
//   bloque 2 (otra fila de encabezado más abajo): licencias municipal/planta/mina
// El segundo bloque se detecta buscando la fila que repite "Nro Contrato", no
// por número de fila fijo: la planilla crece hacia abajo cada mes.
//
// Uso:
//   node cargar-examenes-personal.mjs "<ruta.xlsx>" [--faena ROMERAL] [--dry-run]
// ============================================================================

import { existsSync } from 'node:fs'
import { resolve, dirname, basename } from 'node:path'
import { fileURLToPath } from 'node:url'
import ExcelJS from 'exceljs'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })

const ARCHIVO = process.argv[2]
const DRY = process.argv.includes('--dry-run')
const iF = process.argv.indexOf('--faena')
const FAENA = iF > -1 ? process.argv[iF + 1] : 'ROMERAL'

if (!ARCHIVO || !existsSync(ARCHIVO)) {
  console.error('Uso: node cargar-examenes-personal.mjs "<ruta.xlsx>" [--faena ROMERAL] [--dry-run]')
  process.exit(2)
}

const val = (c) => {
  let v = c?.value
  if (v instanceof Date) return v
  if (v && typeof v === 'object') {
    if (v.result instanceof Date) return v.result
    v = v.result ?? v.text ?? v.richText?.map((t) => t.text).join('') ?? null
  }
  return v
}
const txt = (c) => {
  const v = val(c)
  if (v instanceof Date) return ''
  return String(v ?? '').trim()
}
const fecha = (c) => {
  const v = val(c)
  if (v instanceof Date) {
    if (Number.isNaN(v.getTime())) return null      // "Invalid Date" de la planilla
    return new Date(Date.UTC(v.getUTCFullYear(), v.getUTCMonth(), v.getUTCDate()))
      .toISOString().slice(0, 10)
  }
  const s = String(v ?? '').trim()
  return /^\d{4}-\d{2}-\d{2}/.test(s) ? s.slice(0, 10) : null
}

/** RUT normalizado: sin puntos, con guion, DV en mayúscula. */
const normalizaRut = (s) => {
  const t = String(s ?? '').replace(/[.\s]/g, '').toUpperCase()
  if (!/^\d{7,9}-?[\dK]$/.test(t)) return null
  return t.includes('-') ? t : `${t.slice(0, -1)}-${t.slice(-1)}`
}

/**
 * Una celda de "vencimiento" que no es fecha suele ser una EXENCIÓN escrita a
 * mano: "Sin trabajo en altura física", "No conduce en faena", "N/A". Eso no
 * es un dato faltante y no puede contarse como brecha ante auditoría.
 */
const EXENCION = /^(n\/?a|no aplica|sin |no conduce|no requiere)/i
const esExencion = (s) => !!s && EXENCION.test(s.trim())

/**
 * Observaciones que INVALIDAN el examen aunque la fecha esté vigente. El caso
 * real: laboratorio que el mandante no acepta. Si esto no se marcara, el
 * tablero mostraría verde sobre un examen que CMP rechaza.
 */
const BLOQUEANTE = /(no aceptado|rechazad|no autorizado|pendiente)/i

const TIPOS = [
  { codigo: 'ocupacional',       lab: 6,  venc: 7 },
  { codigo: 'alcohol_drogas',    lab: 8,  venc: 9 },
  { codigo: 'ruido',             lab: 10, venc: 11 },
  { codigo: 'altura_fisica',     lab: 12, venc: 13 },
  { codigo: 'psicosensotecnico', lab: 14, venc: 15 },
]

const wb = new ExcelJS.Workbook()
await wb.xlsx.readFile(resolve(ARCHIVO))
const ws = wb.getWorksheet('Personal')
if (!ws) { console.error('No existe la hoja "Personal".'); process.exit(1) }

// El bloque 2 arranca donde se repite el encabezado. Todo lo que venga después
// son licencias, no exámenes, y se ignora en esta carga (estructura distinta).
let finBloque1 = ws.rowCount
for (let r = 6; r <= ws.rowCount; r++) {
  if (txt(ws.getRow(r).getCell(1)).toLowerCase().startsWith('nro contrato')) { finBloque1 = r - 1; break }
}

const personas = []
for (let r = 5; r <= finBloque1; r++) {
  const row = ws.getRow(r)
  const rut = normalizaRut(txt(row.getCell(3)))
  // La planilla trae nombres y apellidos en columnas separadas (4 y 5).
  const nombres = txt(row.getCell(4))
  const apellidos = txt(row.getCell(5))
  // Sin RUT válido no hay persona: la planilla trae filas de relleno (una con
  // RUT "4" y sin nombre).
  if (!rut || !nombres) continue

  const obsPersona = txt(row.getCell(16))
  const examenes = []
  for (const t of TIPOS) {
    const lab = txt(row.getCell(t.lab))
    const venc = fecha(row.getCell(t.venc))
    const vencTexto = txt(row.getCell(t.venc))

    // Exención declarada, venga en la columna de laboratorio o en la de fecha.
    if (esExencion(lab) || esExencion(vencTexto)) {
      examenes.push({ tipo: t.codigo, aplica: false,
        motivo: (esExencion(lab) ? lab : vencTexto) || 'No aplica' })
      continue
    }
    if (!lab && !venc) continue   // celda vacía → se registra como sin_dato

    examenes.push({
      tipo: t.codigo, aplica: true,
      laboratorio: lab || null,
      vencimiento: venc,
      observacion: obsPersona || null,
      bloqueante: BLOQUEANTE.test(obsPersona) && /psico/i.test(obsPersona)
        ? t.codigo === 'psicosensotecnico'
        : false,
    })
  }
  // Los tipos que no aparecieron quedan explícitos como sin dato: en control
  // documental una celda vacía es incumplimiento, no ausencia de obligación.
  for (const t of TIPOS) {
    if (!examenes.some((e) => e.tipo === t.codigo)) {
      examenes.push({ tipo: t.codigo, aplica: true, laboratorio: null, vencimiento: null,
        observacion: obsPersona || null, bloqueante: false })
    }
  }

  personas.push({
    rut,
    nombres,
    apellidos: apellidos || null,
    empresa: txt(row.getCell(2)) || null,
    nro_contrato: txt(row.getCell(1)) || null,
    faena_codigo: FAENA,
    observacion: obsPersona || null,
    examenes,
  })
}

console.log(`Personas leídas: ${personas.length}   faena: ${FAENA}   archivo: ${basename(ARCHIVO)}`)
const hoy = new Date().toISOString().slice(0, 10)
for (const p of personas) {
  const venc = p.examenes.filter((e) => e.aplica && e.vencimiento && e.vencimiento < hoy)
  const sin = p.examenes.filter((e) => e.aplica && !e.vencimiento)
  const blo = p.examenes.filter((e) => e.bloqueante)
  const marca = venc.length ? '✗' : (blo.length || sin.length) ? '!' : '✓'
  console.log(`  ${marca} ${p.rut.padEnd(12)} ${(p.nombres + ' ' + (p.apellidos ?? '')).slice(0, 34).padEnd(35)}`
    + `${venc.length ? `VENCIDOS: ${venc.map((e) => e.tipo).join(',')} ` : ''}`
    + `${sin.length ? `sin dato: ${sin.map((e) => e.tipo).join(',')} ` : ''}`
    + `${blo.length ? `observado: ${blo.map((e) => e.tipo).join(',')}` : ''}`)
}

if (DRY) { console.log('\n--dry-run: no se escribió nada.'); process.exit(0) }

const client = new pg.Client({
  connectionString: (process.env.SUPABASE_DB_URL || '').trim(),
  ssl: { rejectUnauthorized: false },
})
await client.connect()

for (const p of personas) {
  const { rows } = await client.query(`
    INSERT INTO prevencion_personal (rut, nombres, apellidos, empresa, nro_contrato, faena_codigo, observacion)
    VALUES ($1,$2,$3,$4,$5,$6,$7)
    ON CONFLICT (rut) DO UPDATE SET
      nombres = EXCLUDED.nombres, apellidos = EXCLUDED.apellidos,
      empresa = EXCLUDED.empresa, nro_contrato = EXCLUDED.nro_contrato,
      faena_codigo = EXCLUDED.faena_codigo, observacion = EXCLUDED.observacion,
      updated_at = NOW()
    RETURNING id`,
    [p.rut, p.nombres, p.apellidos, p.empresa, p.nro_contrato, p.faena_codigo, p.observacion])
  const personalId = rows[0].id

  for (const e of p.examenes) {
    await client.query(`
      INSERT INTO prevencion_examenes (
        personal_id, tipo_codigo, laboratorio, fecha_vencimiento,
        aplica, motivo_no_aplica, observacion, observacion_bloqueante)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
      ON CONFLICT (personal_id, tipo_codigo) DO UPDATE SET
        laboratorio = EXCLUDED.laboratorio,
        fecha_vencimiento = EXCLUDED.fecha_vencimiento,
        aplica = EXCLUDED.aplica,
        motivo_no_aplica = EXCLUDED.motivo_no_aplica,
        observacion = EXCLUDED.observacion,
        observacion_bloqueante = EXCLUDED.observacion_bloqueante,
        updated_at = NOW()`,
      [personalId, e.tipo, e.laboratorio ?? null, e.vencimiento ?? null,
       e.aplica, e.aplica ? null : (e.motivo ?? 'No aplica'),
       e.observacion ?? null, !!e.bloqueante])
  }
}

await client.end()
console.log(`\n✓ ${personas.length} personas cargadas en prevencion_personal / prevencion_examenes.`)
