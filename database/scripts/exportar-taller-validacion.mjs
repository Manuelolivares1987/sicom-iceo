#!/usr/bin/env node
// ============================================================================
// exportar-taller-validacion.mjs
// ----------------------------------------------------------------------------
// Exporta a Excel los checklists cargados (V02 + QR) y las pautas con tiempos,
// con una columna de "Validación" para que el jefe de taller los revise.
// Salida: reportes/Validacion_Taller_Checklists_Pautas.xlsx
// ============================================================================

import ExcelJS from 'exceljs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { mkdirSync } from 'node:fs'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })
const client = new pg.Client({ connectionString: (process.env.SUPABASE_DB_URL || '').trim(), ssl: { rejectUnauthorized: false } })

const HEADER_FILL = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF0B2A4A' } }
function styleHeader(ws) {
  const row = ws.getRow(1)
  row.font = { bold: true, color: { argb: 'FFFFFFFF' } }
  row.fill = HEADER_FILL
  row.alignment = { vertical: 'middle', wrapText: true }
  row.height = 26
  ws.views = [{ state: 'frozen', ySplit: 1 }]
}

async function main() {
  await client.connect()

  const v02 = (await client.query(`
    SELECT t.codigo AS tpl, i.bloque, i.orden, i.codigo, i.descripcion,
           array_to_string(i.tipos_equipamiento,', ') AS tipos, i.instrumento, i.unidad,
           i.obligatorio, i.requiere_foto, i.default_cobrable, i.costo_referencial_clp, i.fuente_fabricante
      FROM checklist_template_v2 t JOIN checklist_template_v2_item i ON i.template_id=t.id
     ORDER BY t.codigo, i.bloque, i.orden`)).rows

  const qr = (await client.query(`
    SELECT t.nombre AS checklist, i.seccion, i.orden, i.codigo_item, i.descripcion,
           i.tipo_respuesta, i.criticidad_si_falla, i.obligatorio, i.requiere_foto
      FROM qr_checklist_templates t JOIN qr_checklist_template_items i ON i.template_id=t.id
     ORDER BY t.nombre, i.seccion, i.orden`)).rows

  const pautas = (await client.query(`
    SELECT DISTINCT ON (nombre) nombre, tipo_plan, frecuencia_dias, frecuencia_km,
           frecuencia_horas, duracion_estimada_hrs,
           jsonb_array_length(COALESCE(items_checklist,'[]'::jsonb)) AS n_items
      FROM pautas_fabricante ORDER BY nombre, id`)).rows

  await client.end()

  const wb = new ExcelJS.Workbook()
  wb.creator = 'SICOM-ICEO'

  // ── Resumen ──
  const res = wb.addWorksheet('Resumen')
  res.columns = [{ header: 'Sección', width: 40 }, { header: 'Cantidad', width: 14 }]
  styleHeader(res)
  res.addRows([
    ['Checklist Entrega V02 (ítems)', v02.filter(r => r.tpl === 'CL-ENTREGA-V02').length],
    ['Checklist Recepción V02 (ítems)', v02.filter(r => r.tpl === 'CL-RECEPCION-V02').length],
    ['Checklists QR operador (plantillas)', new Set(qr.map(r => r.checklist)).size],
    ['Checklists QR operador (ítems totales)', qr.length],
    ['Pautas de fabricante únicas', pautas.length],
  ])

  // ── V02: una hoja por template ──
  for (const [tpl, hoja] of [['CL-ENTREGA-V02', 'Entrega V02'], ['CL-RECEPCION-V02', 'Recepción V02']]) {
    const ws = wb.addWorksheet(hoja)
    ws.columns = [
      { header: 'Bloque', width: 22 }, { header: 'Orden', width: 7 }, { header: 'Código', width: 14 },
      { header: 'Descripción', width: 50 }, { header: 'Tipos equipo', width: 28 },
      { header: 'Instrumento', width: 14 }, { header: 'Unidad', width: 9 },
      { header: 'Oblig.', width: 7 }, { header: 'Foto', width: 6 }, { header: 'Cobrable', width: 9 },
      { header: 'Costo ref $', width: 12 }, { header: 'Fuente', width: 16 },
      { header: 'VALIDACIÓN (OK / Ajustar / Observación)', width: 40 },
    ]
    styleHeader(ws)
    for (const r of v02.filter(x => x.tpl === tpl)) {
      ws.addRow([r.bloque, r.orden, r.codigo, r.descripcion, r.tipos, r.instrumento, r.unidad,
        r.obligatorio ? 'Sí' : '', r.requiere_foto ? 'Sí' : '', r.default_cobrable ? 'Sí' : '',
        r.costo_referencial_clp, r.fuente_fabricante, ''])
    }
    ws.eachRow((row, n) => { if (n > 1) row.alignment = { vertical: 'top', wrapText: true } })
  }

  // ── QR (operador) ──
  const wsq = wb.addWorksheet('Checklists QR (operador)')
  wsq.columns = [
    { header: 'Checklist', width: 34 }, { header: 'Sección', width: 18 }, { header: 'Orden', width: 7 },
    { header: 'Código', width: 14 }, { header: 'Descripción', width: 50 },
    { header: 'Tipo resp.', width: 14 }, { header: 'Criticidad', width: 12 },
    { header: 'Oblig.', width: 7 }, { header: 'Foto', width: 6 },
    { header: 'VALIDACIÓN', width: 36 },
  ]
  styleHeader(wsq)
  for (const r of qr) {
    wsq.addRow([r.checklist, r.seccion, r.orden, r.codigo_item, r.descripcion, r.tipo_respuesta,
      r.criticidad_si_falla, r.obligatorio ? 'Sí' : '', r.requiere_foto ? 'Sí' : '', ''])
  }
  wsq.eachRow((row, n) => { if (n > 1) row.alignment = { vertical: 'top', wrapText: true } })

  // ── Pautas con tiempos ──
  const wsp = wb.addWorksheet('Pautas y tiempos')
  wsp.columns = [
    { header: 'Pauta', width: 44 }, { header: 'Tipo plan', width: 16 },
    { header: 'Frec. días', width: 11 }, { header: 'Frec. km', width: 12 }, { header: 'Frec. horas', width: 12 },
    { header: 'Duración (hrs)', width: 14 }, { header: 'N° ítems', width: 9 },
    { header: 'VALIDACIÓN tiempo / ajuste', width: 36 },
  ]
  styleHeader(wsp)
  for (const r of pautas) {
    wsp.addRow([r.nombre, r.tipo_plan, r.frecuencia_dias, r.frecuencia_km, r.frecuencia_horas,
      r.duracion_estimada_hrs, r.n_items, r.duracion_estimada_hrs == null ? 'FALTA TIEMPO' : ''])
  }

  const outDir = resolve(__dirname, '../../reportes')
  mkdirSync(outDir, { recursive: true })
  const out = resolve(outDir, 'Validacion_Taller_Checklists_Pautas.xlsx')
  await wb.xlsx.writeFile(out)
  console.log(`OK -> ${out}`)
  console.log(`V02: ${v02.length} items | QR: ${qr.length} items (${new Set(qr.map(r=>r.checklist)).size} plantillas) | Pautas: ${pautas.length}`)
}

main().catch((e) => { console.error('ERROR:', e.message); process.exit(1) })
