// ============================================================================
// cargar-camiones-esmax-sqm.mjs — alta de los 6 Renault C440 nuevos para ESMAX
// ----------------------------------------------------------------------------
//   node database/scripts/cargar-camiones-esmax-sqm.mjs --dry   (sólo muestra)
//   node database/scripts/cargar-camiones-esmax-sqm.mjs         (carga)
//
// Origen: Desktop/OPERACIONES/02_FLOTA Y EQUIPOS/PATENTES/ESMAX_SQM/<patente>/
// Cada dato sale de un papel leído (2026-10-18), nunca deducido:
//   · motor / año / VIN: SOAP, permiso de circulación o factura SALFA
//   · capacidad 20.000 L: TC8 INTECIL (sólo WBFZ-22 y WBGD-20 lo traen)
//   · vencimientos: los que el papel declara. Si no declara → sin vencimiento;
//     si no se puede leer (escaneo de WBGD-30) → queda «falta la fecha»
//     (2099 + archivo = 'sin_fecha'), nunca inventada.
// Idempotente: el camión se busca por patente y el papel por archivo_url.
// ============================================================================

import { readFileSync, readdirSync } from 'node:fs'
import { resolve, dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
const DRY = process.argv.includes('--dry')
const CARPETA = 'C:/Users/Manuel Olivares/Desktop/OPERACIONES/02_FLOTA Y EQUIPOS/PATENTES/ESMAX_SQM'

dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })
const feEnv = readFileSync(resolve(__dirname, '../../frontend/.env.local'), 'utf8')
const SUPA_URL = feEnv.match(/NEXT_PUBLIC_SUPABASE_URL=(.+)/)?.[1].trim()
const ANON = feEnv.match(/NEXT_PUBLIC_SUPABASE_ANON_KEY=(.+)/)?.[1].trim()
const db = new pg.Client({ connectionString: process.env.SUPABASE_DB_URL, ssl: { rejectUnauthorized: false } })

const SIN_VENC = '2099-12-31'

// ── Los camiones ─────────────────────────────────────────────────────────────
const CAMIONES = [
  { patente: 'WBFZ-22', codigo: 'CC-20-04', vin: 'VF630N36XTD003276', motor: '2602453', anio: 2026, tc8: true },
  { patente: 'WBGD-20', codigo: 'CC-20-05', vin: 'VF630N368TD003096', motor: '2566376', anio: 2026, tc8: true },
  { patente: 'WBGD-30', codigo: 'CC-20-06', vin: 'VF630N363TD003104', motor: '2567508', anio: 2026, tc8: false },
  { patente: 'WCWR-25', codigo: 'CC-20-07', vin: 'VF630N36XTD003214', motor: '2584779', anio: 2027, tc8: false },
  { patente: 'WCWR-33', codigo: 'CC-20-08', vin: 'VF630N363TD003278', motor: '2602909', anio: 2027, tc8: false },
  { patente: 'WCWR-35', codigo: 'CC-20-09', vin: 'VF630N367TD003199', motor: '2582675', anio: 2027, tc8: false },
]

// Datos leídos de SOAP y permisos (texto del PDF).
const SOAP = {
  'WBFZ-22': { desde: '2026-10-05', folio: '9808712503', poliza: '12530738' },
  'WBGD-20': { desde: '2026-10-05', folio: '9808153817', poliza: '12530739' },
  'WBGD-30': { desde: '2026-10-06', folio: '9808916984', poliza: '12531723' },
  'WCWR-33': { desde: '2026-10-15', folio: '9809483704', poliza: '12538817' },
}
const PERMISO = { // por nombre de archivo
  'T2026WBFZ229025646.pdf':        { serie: '9025646', emision: '2026-10-07', vence: '2027-09-30' },
  'T2026WBGD209025648.pdf':        { serie: '9025648', emision: '2026-10-07', vence: '2027-09-30' },
  'T2025WBGD309025738.pdf':        { serie: '9025738', emision: '2026-10-16', vence: '2026-09-30' },
  'T2026WBGD309025739.pdf':        { serie: '9025739', emision: '2026-10-16', vence: '2027-09-30' },
  'T2026WCWR339025644 (1).pdf':    { serie: '9025644', emision: '2026-10-06', vence: '2027-09-30' },
}
const SALFA_EMISION = '2026-10-08' // «Santiago de Chile, 08 de octubre de 2026» en todos

// Un archivo → uno o más papeles. `vence: null` = el papel no declara vencimiento.
function papeles(pat, f) {
  const sinV = (tipo, extra = {}) => ({ tipo, emision: SALFA_EMISION, vence: null, entidad: 'Salinas y Fabres S.A. (SALFA)', ...extra })
  if (/^Certificado BBM/.test(f)) return [sinV('otra', { tipo_otro: 'Certificado conexiones auxiliares (BBM)' })]
  if (/Apriete y Torque/.test(f)) return [sinV('torque_ruedas')]
  if (/Cabina, Parabrisas/.test(f)) return [sinV('cert_cabina')]
  if (/Certificado de Frenos/.test(f)) return [sinV('otra', { tipo_otro: 'Capacidad de frenado' })]
  // Ojo: es la hermeticidad de la CABINA (sellos, filtro), no la del estanque
  // (tipo 'hermeticidad', 6 meses). Mezclarlas le pondría un vencimiento falso.
  if (/Hermeticidad de Cabina/.test(f)) return [sinV('otra', { tipo_otro: 'Hermeticidad de cabina' })]
  if (/Operatividad/.test(f)) return [sinV('operatividad', { vence: '2027-10-08', nota: 'El papel declara: validez 1 año desde la emisión.' })]
  if (/ADAS/.test(f)) return [sinV('otra', { tipo_otro: 'Asistente de conducción ADAS' })]
  if (/^Certificado Estanque INTECIL (\d+)/.test(f)) {
    const n = f.match(/INTECIL (\d+)/)[1]
    return [{ tipo: 'tc8_sec', numero: n, entidad: 'INTECIL SpA', emision: n === '757408' ? '2026-08-24' : '2026-09-22', vence: null,
              nota: 'Certificado de producción del estanque, 20.000 L (DOT MC-306). No declara vencimiento.' }]
  }
  if (/HDISOAP|^soap/i.test(f)) {
    const s = SOAP[pat]
    return [{ tipo: 'soap', numero: `Folio ${s.folio} · Póliza ${s.poliza}`, entidad: 'HDI Seguros', emision: s.desde, vence: '2027-09-30' }]
  }
  // Pagado el 16-10-2026 por el período 2025, que venció el 30-09-2026: es un
  // comprobante de pago atrasado, no un permiso vigente (y la base rechaza un
  // vencimiento anterior a la emisión).
  if (f === 'T2025WBGD309025738.pdf') {
    return [{ tipo: 'otra', tipo_otro: 'Comprobante pago permiso de circulación 2025 (período anterior)',
              numero: '9025738', entidad: 'Municipalidad de La Higuera', emision: '2026-10-16', vence: null }]
  }
  if (PERMISO[f]) {
    const p = PERMISO[f]
    return [{ tipo: 'permiso_circulacion', numero: p.serie, entidad: 'Municipalidad de La Higuera', emision: p.emision, vence: p.vence }]
  }
  if (/^Factura SALFA (\d+)/.test(f)) {
    return [{ tipo: 'factura_compra', numero: f.match(/SALFA (\d+)/)[1], entidad: 'Salinas y Fabres S.A. (SALFA)', emision: '2026-09-23', vence: null }]
  }
  if (/^HOMOLOGADO/.test(f)) {
    return [{ tipo: 'homologacion', entidad: 'Salinas y Fabres S.A. (SALFA)', emision: '2026-09-23', vence: null,
              nota: 'Escaneo: la fecha de emisión no se lee; se registra la de la factura.' }]
  }
  if (f === '3278 PRT+ GASES.pdf') { // leído como imagen: Systech AB-1308, 14-10-2026
    const base = { numero: 'A1308000000148410', entidad: 'Systech Chile SpA (planta AB-1308)', emision: '2026-10-14', vence: '2027-04-14' }
    return [{ tipo: 'revision_tecnica', ...base }, { tipo: 'analisis_gases', ...base }]
  }
  // RT + gases de UVT (planta A-1303), leídos como imagen. OJO: pdf.js los
  // renderiza casi en blanco; con pdfium (pypdfium2) se leen perfecto. El
  // 2026-10-18 se cargó WBGD-30 como «falta la fecha» por ese error del lector.
  const UVT = {
    '3104 PRT+GASES+CERT FRENADO+ CERT MEDIDAS.pdf':        { numero: 'A1303000000588254', emision: '2026-10-05', vence: '2027-04-05' },
    '3276 PRT + GASES + FRENADO + DIMENSIONES.pdf':         { numero: 'A1303000000583388', emision: '2026-09-04', vence: '2027-03-04' },
    '3096 PRT + GASES + CERT MEDIDAS + CERT FRENADO.pdf':   { numero: 'A1303000000586045', emision: '2026-09-22', vence: '2027-03-22' },
  }
  if (UVT[f]) {
    const base = { ...UVT[f], entidad: 'Revisiones Técnicas UVT S.A. (planta A-1303)' }
    return [{ tipo: 'revision_tecnica', ...base }, { tipo: 'analisis_gases', ...base }]
  }
  throw new Error(`Archivo sin regla: ${pat}/${f}`)
}

const BLOQUEANTE = new Set(['soap', 'permiso_circulacion', 'revision_tecnica', 'tc8_sec'])

function slug(s) {
  return s.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-zA-Z0-9._-]+/g, '_').slice(0, 90)
}

async function subir(path, ruta) {
  const res = await fetch(`${SUPA_URL}/storage/v1/object/documentos/${ruta}`, {
    method: 'POST',
    headers: { apikey: ANON, Authorization: `Bearer ${ANON}`, 'Content-Type': 'application/pdf', 'x-upsert': 'false' },
    body: readFileSync(path),
  })
  if (res.status === 409 || (res.status === 400 && /exists/i.test(await res.clone().text()))) return 'ya-existia'
  if (!res.ok) throw new Error(`storage ${res.status}: ${(await res.text()).slice(0, 200)}`)
  return 'subido'
}

async function main() {
  await db.connect()
  const { rows: [ctx] } = await db.query(`
    SELECT (SELECT id FROM contratos WHERE codigo = 'CTR-ESMAX-2025') AS contrato,
           (SELECT mo.id FROM modelos mo JOIN marcas ma ON ma.id = mo.marca_id
             WHERE ma.nombre = 'Renault' AND mo.nombre = 'C440') AS modelo`)
  if (!ctx.contrato || !ctx.modelo) throw new Error('Falta contrato ESMAX o modelo Renault C440')

  // Plan completo antes de tocar nada.
  const plan = CAMIONES.map((c) => ({
    ...c,
    archivos: readdirSync(join(CARPETA, c.patente))
      .sort((a, b) => a.localeCompare(b)) // T2025 antes que T2026: la versión vigente es la última cargada
      .map((f) => ({ f, papeles: papeles(c.patente, f) })),
  }))
  for (const c of plan) {
    console.log(`\n${c.codigo}  ${c.patente}  ${c.vin}  motor ${c.motor}  ${c.anio}`)
    for (const a of c.archivos) for (const p of a.papeles) {
      console.log(`   ${(p.tipo_otro ?? p.tipo).padEnd(42)} emis ${p.emision}  vence ${p.vence ?? 'no declara'}   ← ${a.f}`)
    }
  }
  if (DRY) { console.log('\n--dry: nada escrito'); return }

  await db.query(`DROP POLICY IF EXISTS tmp_carga_cert ON storage.objects`)
  await db.query(`CREATE POLICY tmp_carga_cert ON storage.objects FOR INSERT TO anon
                  WITH CHECK (bucket_id='documentos' AND (storage.foldername(name))[1]='certificaciones')`)
  let camiones = 0, docs = 0, subidos = 0
  try {
    await db.query('BEGIN')
    for (const c of plan) {
      let { rows: [a] } = await db.query(`SELECT id FROM activos WHERE patente = $1`, [c.patente])
      if (!a) {
        ;({ rows: [a] } = await db.query(`
          INSERT INTO activos (codigo, nombre, patente, tipo, tipo_equipamiento, modelo_id, contrato_id,
                               criticidad, estado, estado_comercial, categoria_uso, cliente_actual,
                               capacidad, potencia, vin_chasis, numero_motor, anio_fabricacion,
                               centro_costo, proveedor, qr_publico_habilitado, fecha_alta, notas)
          VALUES ($1, $2, $3, 'camion_cisterna', 'aljibe_combustible', $4, $5,
                  'critica', 'operativo', 'comprometido', 'arriendo_comercial', 'Esmax',
                  $6, '440HP', $7, $8, $9, $1, 'Salinas y Fabres S.A. (SALFA)', true, CURRENT_DATE, $10)
          RETURNING id`,
          [c.codigo, `Aljibe Comb. 20kL ${c.patente}`, c.patente, ctx.modelo, ctx.contrato,
           c.tc8 ? '20.000 L 6x4' : '20.000 L 6x4 (sin TC8 en carpeta: confirmar)',
           c.vin, c.motor, c.anio,
           'Renault C440 nuevo (SALFA, oct-2026). Propietario según padrón/SOAP: Banco Santander Chile (leasing). ' +
           'Alta MIG609b desde carpeta ESMAX_SQM 2026-10-18. Faena y operación por asignar.']))
        camiones++
      }
      for (const { f, papeles: ps } of c.archivos) {
        const ruta = `certificaciones/${a.id}/${slug(f)}`
        const r = await subir(join(CARPETA, c.patente, f), ruta)
        if (r === 'subido') subidos++
        const url = `${SUPA_URL}/storage/v1/object/public/documentos/${ruta}`
        for (const p of ps) {
          const { rowCount } = await db.query(
            `SELECT 1 FROM certificaciones WHERE activo_id = $1 AND archivo_url = $2 AND tipo::text = $3 AND anulado_at IS NULL`,
            [a.id, url, p.tipo])
          if (rowCount) continue
          const falta = p.vence === 'FALTA'
          const vence = p.vence && !falta ? p.vence : SIN_VENC
          const estado = falta ? 'sin_fecha'
            : !p.vence ? 'no_aplica'
            : vence < new Date().toISOString().slice(0, 10) ? 'vencido' : 'vigente'
          await db.query(`
            INSERT INTO certificaciones (activo_id, tipo, tipo_otro, numero_certificado, entidad_certificadora,
                                         fecha_emision, fecha_vencimiento, estado, archivo_url, notas, bloqueante,
                                         fecha_origen, fecha_origen_nota)
            VALUES ($1, $2::tipo_certificacion_enum, $3, $4, $5, $6, $7, $8::estado_documento_enum, $9, $10, $11, $12, $13)`,
            [a.id, p.tipo, p.tipo_otro ?? null, p.numero ?? null, p.entidad ?? null, p.emision, vence, estado, url,
             p.nota ?? null, BLOQUEANTE.has(p.tipo),
             falta ? null : p.vence ? 'documento' : 'documento_sin_vencimiento',
             falta ? 'Papel ilegible: falta confirmar la fecha' : `Leído del papel: ${f}`])
          docs++
        }
      }
    }
    await db.query('COMMIT')
  } catch (e) {
    await db.query('ROLLBACK').catch(() => {})
    throw e
  } finally {
    await db.query(`DROP POLICY IF EXISTS tmp_carga_cert ON storage.objects`)
  }
  console.log(`\nOK: ${camiones} camiones nuevos, ${docs} papeles, ${subidos} archivos subidos`)
}

main().catch((e) => { console.error('ERROR', e.message); process.exitCode = 1 }).finally(() => db.end())
