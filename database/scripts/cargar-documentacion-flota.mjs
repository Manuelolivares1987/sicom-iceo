#!/usr/bin/env node
// ============================================================================
// cargar-documentacion-flota.mjs
// ----------------------------------------------------------------------------
// Carga la carpeta "DOCUMENTACIÓN VIGENTE" a producción:
//   1. Sube cada PDF al bucket 'documentos' (carpeta certificaciones/<activo>/)
//      usando la anon key + una policy INSERT temporal (se crea y borra aquí).
//   2. Upsertea `certificaciones` (1 fila viva por activo+tipo) con las fechas
//      de vencimiento de la hoja "Estado Documentos" del Excel consolidado.
//   SE OMITEN: "00 - Índice/Control" y "30 - Manual" (309 MB; no caben en el
//   plan Free de storage y no tienen vencimiento).
//
// Uso:  node cargar-documentacion-flota.mjs [--dry]
// ============================================================================

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs'
import { resolve, join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'
import dotenv from 'dotenv'
import ExcelJS from 'exceljs'

const __dirname = dirname(fileURLToPath(import.meta.url))
const DRY = process.argv.includes('--dry')

const CARPETA = 'C:/Users/Manuel Olivares/Desktop/DOCUMETACIÓN CAMIÓN/DOCUMENTACIÓN VIGENTE 2026-07-09'
const EXCEL = join(CARPETA, '00 - Control Documental Flota (consolidado 09-07-2026).xlsx')

// ── credenciales ─────────────────────────────────────────────────────────────
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })
const feEnv = readFileSync(resolve(__dirname, '../../frontend/.env.local'), 'utf8')
const SUPA_URL = feEnv.match(/NEXT_PUBLIC_SUPABASE_URL=(.+)/)?.[1].trim()
const ANON = feEnv.match(/NEXT_PUBLIC_SUPABASE_ANON_KEY=(.+)/)?.[1].trim()
if (!SUPA_URL || !ANON) { console.error('Faltan credenciales frontend'); process.exit(2) }

const db = new pg.Client({ connectionString: process.env.SUPABASE_DB_URL, ssl: { rejectUnauthorized: false } })

// ── mapeo prefijo → tipo enum ────────────────────────────────────────────────
const PREFIJO_TIPO = {
  '01': 'permiso_circulacion', '02': 'soap', '03': 'revision_tecnica',
  '04': 'analisis_gases', '05': 'padron', '06': 'inscripcion_rnvm',
  '07': 'homologacion', '08': 'inscripcion_sec', '09': 'tc8_sec',
  '10': 'hermeticidad', '11': 'calibracion', '12': 'optico_sobrellenado',
  '13': 'flujo_descarga', '14': 'sist_riego', '15': 'cert_cabina',
  '16': 'laminas_seguridad', '17': 'barra_antivuelco', '18': 'operatividad',
  '19': 'grilletes_eslingas', '20': 'mant_hidraulico', '21': 'mantencion',
  '22': 'aire_acondicionado', '23': 'tacografo', '24': 'torque_ruedas',
  '25': 'ausencia_falla_ecm', '26': 'gps', '27': 'inventario_neumaticos',
  '28': 'seguro_rc', '29': 'ficha_tecnica', '31': 'factura_compra',
}
const OMITIR = new Set(['00', '30'])

// nombre de documento del Excel → tipo (por contenido, normalizado)
function tipoDesdeNombreExcel(doc) {
  const d = doc.toLowerCase()
  if (d.includes('permiso de circulaci')) return 'permiso_circulacion'
  if (d === 'soap') return 'soap'
  if (d.includes('revisión técnica') || d.includes('revision tecnica')) return 'revision_tecnica'
  if (d.includes('gases')) return 'analisis_gases'
  if (d.includes('padrón') || d.includes('padron')) return 'padron'
  if (d.includes('rnvm')) return 'inscripcion_rnvm'
  if (d.includes('homologa')) return 'homologacion'
  if (d.includes('sec') && d.includes('inscrip')) return 'inscripcion_sec'
  if (d.includes('tc8')) return 'tc8_sec'
  if (d.includes('hermeticidad')) return 'hermeticidad'
  if (d.includes('calibración') || d.includes('calibracion')) return 'calibracion'
  if (d.includes('óptico') || d.includes('optico')) return 'optico_sobrellenado'
  if (d.includes('flujo')) return 'flujo_descarga'
  if (d.includes('riego')) return 'sist_riego'
  if (d.includes('cabina')) return 'cert_cabina'
  if (d.includes('láminas') || d.includes('laminas')) return 'laminas_seguridad'
  if (d.includes('antivuelco')) return 'barra_antivuelco'
  if (d.includes('operatividad')) return 'operatividad'
  if (d.includes('grilletes')) return 'grilletes_eslingas'
  if (d.includes('hidraul')) return 'mant_hidraulico'
  if (d.includes('aire acondicionado')) return 'aire_acondicionado'
  if (d.includes('tacógrafo') || d.includes('tacografo')) return 'tacografo'
  if (d.includes('torque')) return 'torque_ruedas'
  if (d.includes('ecm')) return 'ausencia_falla_ecm'
  if (d.includes('gps')) return 'gps'
  if (d.includes('neumáticos') || d.includes('neumaticos')) return 'inventario_neumaticos'
  if (d.includes('póliza') || d.includes('poliza') || d.includes('seguro')) return 'seguro_rc'
  if (d.includes('ficha técnica') || d.includes('ficha tecnica')) return 'ficha_tecnica'
  if (d.includes('manual')) return 'manual'
  if (d.includes('factura')) return 'factura_compra'
  if (d.includes('mantención') || d.includes('mantencion')) return 'mantencion'
  return null
}

const norm = (s) => (s ?? '').toString().toUpperCase().replace(/[\s\-–]/g, '')

function fechaIso(v) {
  if (!v) return null
  if (v instanceof Date) return v.toISOString().slice(0, 10)
  const m = v.toString().match(/(\d{4})-(\d{2})-(\d{2})/)
  return m ? m[0] : null
}

function estadoPorFecha(vence) {
  if (!vence) return 'no_aplica'
  const dias = Math.floor((new Date(vence + 'T12:00:00') - new Date()) / 86400000)
  if (dias < 0) return 'vencido'
  if (dias <= 45) return 'por_vencer'
  return 'vigente'
}

// Documentos que no vencen (identidad del equipo, compra, etc.)
const SIN_VENCIMIENTO = new Set([
  'padron', 'inscripcion_rnvm', 'homologacion', 'ficha_tecnica', 'factura_compra', 'manual',
])

// fecha_vencimiento es NOT NULL: los documentos sin vencimiento usan la fecha
// simbólica 2099-12-31 con estado no_aplica ("permanente").
const SIN_VENC_FECHA = '2099-12-31'

// Regla pedida por Manuel: documento presente pero MUY ANTIGUO → indicar
// renovación. Si un certificado renovable no trae vencimiento, se asume
// vigencia de 12 meses desde su emisión (queda vencido si ya pasó).
function resolverVigencia(tipo, emision, vence) {
  if (vence) return { vence, estado: estadoPorFecha(vence), nota: null }
  if (SIN_VENCIMIENTO.has(tipo)) return { vence: SIN_VENC_FECHA, estado: 'no_aplica', nota: '[documento sin vencimiento]' }
  if (!emision) return { vence: SIN_VENC_FECHA, estado: 'no_aplica', nota: '[sin fecha en control documental — verificar]' }
  const d = new Date(emision + 'T12:00:00')
  d.setFullYear(d.getFullYear() + 1)
  const v = d.toISOString().slice(0, 10)
  return { vence: v, estado: estadoPorFecha(v), nota: '[vencimiento estimado: emisión + 12 meses — verificar/renovar]' }
}

function slug(s) {
  return s.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-zA-Z0-9._-]+/g, '_').slice(0, 90)
}

async function subirPdf(path, ruta) {
  const body = readFileSync(path)
  const res = await fetch(`${SUPA_URL}/storage/v1/object/documentos/${ruta}`, {
    method: 'POST',
    headers: {
      apikey: ANON, Authorization: `Bearer ${ANON}`,
      'Content-Type': 'application/pdf', 'x-upsert': 'false',
    },
    body,
  })
  if (res.status === 409) return 'ya-existia' // duplicado: ok (re-ejecución)
  if (!res.ok) throw new Error(`storage ${res.status}: ${(await res.text()).slice(0, 200)}`)
  return 'subido'
}

// ── main ─────────────────────────────────────────────────────────────────────
async function main() {
  await db.connect()

  // Activos: patente normalizada → id (también codigo por si acaso)
  const { rows: activos } = await db.query(`SELECT id, patente, codigo FROM activos WHERE estado != 'dado_baja'`)
  const porPatente = new Map()
  for (const a of activos) {
    if (a.patente) porPatente.set(norm(a.patente), a.id)
    if (a.codigo) porPatente.set(norm(a.codigo), a.id)
  }

  // Excel: (patenteNorm|tipo) → {emision, vence, estado, obs}
  const wb = new ExcelJS.Workbook()
  await wb.xlsx.readFile(EXCEL)
  const hoja = wb.getWorksheet('Estado Documentos')
  const meta = new Map()
  hoja.eachRow((row, n) => {
    if (n < 3) return
    const pat = row.getCell(1).text?.trim()
    const doc = row.getCell(7).text?.trim()
    if (!pat || !doc) return
    const tipo = tipoDesdeNombreExcel(doc)
    if (!tipo) return
    const emision = fechaIso(row.getCell(8).value)
    const vence = fechaIso(row.getCell(9).value)
    const estadoXls = row.getCell(11).text?.trim()
    const obs = row.getCell(13).text?.trim() || null
    if (estadoXls === 'FALTA') return
    meta.set(`${norm(pat)}|${tipo}`, { emision, vence, obs })
  })
  console.log(`Excel: ${meta.size} documentos con metadata`)

  // Carpetas de equipos
  const dirs = readdirSync(CARPETA).filter((d) => statSync(join(CARPETA, d)).isDirectory())
  console.log(`Carpetas de equipos: ${dirs.length}`)

  // Policy temporal para subir con anon (solo carpeta certificaciones/)
  if (!DRY) {
    await db.query(`DROP POLICY IF EXISTS tmp_carga_cert ON storage.objects`)
    await db.query(`CREATE POLICY tmp_carga_cert ON storage.objects FOR INSERT TO anon
                    WITH CHECK (bucket_id='documentos' AND (storage.foldername(name))[1]='certificaciones')`)
  }

  let subidos = 0, existentes = 0, filas = 0, sinActivo = [], sinTipo = [], errores = []

  try {
    for (const dir of dirs) {
      // patente = lo que va después del último " - " (con normalización de casos raros)
      const patRaw = dir.includes(' - ') ? dir.slice(dir.lastIndexOf(' - ') + 3) : dir
      const patKey = norm(patRaw.replace(/\(.*\)/, ''))
      const activoId = porPatente.get(patKey)
      if (!activoId) { sinActivo.push(dir); continue }

      const files = readdirSync(join(CARPETA, dir)).filter((f) => f.toLowerCase().endsWith('.pdf'))
      for (const f of files) {
        const pref = f.slice(0, 2)
        if (OMITIR.has(pref)) continue
        const tipo = PREFIJO_TIPO[pref]
        if (!tipo) { sinTipo.push(`${dir}/${f}`); continue }

        const m = meta.get(`${patKey}|${tipo}`) ?? {}
        const ruta = `certificaciones/${activoId}/${slug(f)}`
        const url = `${SUPA_URL}/storage/v1/object/public/documentos/${ruta}`

        if (DRY) { filas++; continue }

        try {
          const r = await subirPdf(join(CARPETA, dir, f), ruta)
          r === 'subido' ? subidos++ : existentes++
        } catch (e) { errores.push(`${dir}/${f}: ${e.message}`); continue }

        // upsert certificaciones: actualiza la fila más reciente del tipo o inserta
        const { vence, estado, nota: notaVig } = resolverVigencia(tipo, m.emision, m.vence)
        const notas = [m.obs, notaVig, '[carga documental 09-07-2026]'].filter(Boolean).join(' ')
        const { rows: ex } = await db.query(
          `SELECT id FROM certificaciones WHERE activo_id=$1 AND tipo=$2::tipo_certificacion_enum
           ORDER BY fecha_vencimiento DESC NULLS LAST, created_at DESC LIMIT 1`, [activoId, tipo])
        if (ex.length) {
          await db.query(
            `UPDATE certificaciones SET archivo_url=$1,
                    fecha_emision=COALESCE($2::date, fecha_emision),
                    fecha_vencimiento=COALESCE($3::date, fecha_vencimiento),
                    estado=$4::estado_documento_enum,
                    notas=$5,
                    updated_at=NOW()
              WHERE id=$6`, [url, m.emision, vence, estado, notas, ex[0].id])
        } else {
          // fecha_emision es NOT NULL: si el doc no trae fecha, usar la fecha
          // de corte de la carpeta (09-07-2026, día del control documental).
          const emision = m.emision ?? vence ?? '2026-07-09'
          await db.query(
            `INSERT INTO certificaciones (activo_id, tipo, fecha_emision, fecha_vencimiento, estado, archivo_url, notas, bloqueante)
             VALUES ($1, $2::tipo_certificacion_enum, $3::date, $4::date, $5::estado_documento_enum, $6, $7, false)`,
            [activoId, tipo, emision, vence, estado, url, notas])
        }
        filas++
        if (filas % 50 === 0) console.log(`  … ${filas} documentos procesados (${subidos} subidos)`)
      }
    }
  } finally {
    if (!DRY) await db.query(`DROP POLICY IF EXISTS tmp_carga_cert ON storage.objects`)
  }

  console.log('────────────────────────────────────────')
  console.log(`Subidos: ${subidos} · ya existían: ${existentes} · filas certificaciones: ${filas}`)
  if (sinActivo.length) console.log(`Carpetas sin activo en BD (${sinActivo.length}): ${sinActivo.join(' | ')}`)
  if (sinTipo.length) console.log(`Archivos sin tipo (${sinTipo.length}): ${sinTipo.slice(0, 5).join(' | ')}`)
  if (errores.length) console.log(`ERRORES (${errores.length}):\n${errores.slice(0, 10).join('\n')}`)
  await db.end()
}

main().catch((e) => { console.error(e); process.exit(1) })
