#!/usr/bin/env node
// ============================================================================
// analizar-certificados.mjs
// ----------------------------------------------------------------------------
// Lee los PDF de certificación de la flota y PROPONE la fecha de vencimiento
// que dice el documento. NO ESCRIBE NADA EN LA BASE.
//
// POR QUÉ NO ESCRIBE
// 468 de los 958 certificados tienen fecha `2099-12-31` y estado `no_aplica`:
// se cargó el archivo pero nunca se leyó la fecha. Esos registros deciden si un
// equipo puede salir a operar. Una fecha mal extraída o bien deja un camión
// parado sin motivo, o —peor— declara vigente un certificado vencido.
//
// Así que esto propone y deja la evidencia; aplicar es otra pasada, con revisión.
//
// CÓMO LEE UN CERTIFICADO
// Los PDF vienen de formularios y el texto sale desordenado (los campos no
// respetan el orden visual). Así que no sirve «la fecha que está al lado de la
// palabra vencimiento». Se busca:
//
//   1. Una fecha de vencimiento EXPLÍCITA ("válido hasta", "vence el"…)
//   2. Si no, una fecha base ("fecha de emisión / inspección / instalación")
//      más una vigencia declarada ("válido por 1 año", "periodo de 2 años")
//
// El caso 2 es el común: el certificado de hermeticidad del TGGF-57 dice
// «FECHA INSPECCION: 02/05/2024» y, en otra parte de la hoja, «CERTIFICADO
// valido por 1 año desde fecha de Emision».
//
// Uso:
//   node analizar-certificados.mjs            → todos los que tienen placeholder
//   node analizar-certificados.mjs --todos    → todos los que tengan archivo
//   node analizar-certificados.mjs --patente TGGF-57
// ============================================================================

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ENV_PATH = resolve(__dirname, '../../.env.supabase-admin.local')
if (!existsSync(ENV_PATH)) { console.error(`ERROR: falta ${ENV_PATH}`); process.exit(2) }
dotenv.config({ path: ENV_PATH })

const FE = resolve(__dirname, '../../frontend')
const pdfjs = await import(pathToFileURL(`${FE}/node_modules/pdfjs-dist/legacy/build/pdf.mjs`).href)

// ── Texto del PDF ───────────────────────────────────────────────────────────
async function textoDePdf(buf) {
  const doc = await pdfjs.getDocument({
    data: new Uint8Array(buf), useSystemFonts: true, isEvalSupported: false,
    standardFontDataUrl: `${FE}/node_modules/pdfjs-dist/standard_fonts/`,
  }).promise
  let out = ''
  for (let p = 1; p <= doc.numPages; p++) {
    const tc = await (await doc.getPage(p)).getTextContent()
    out += tc.items.map((i) => i.str).join(' ') + '\n'
  }
  await doc.destroy()
  return out
}

// ── Fechas ──────────────────────────────────────────────────────────────────
const MESES = {
  enero: 1, febrero: 2, marzo: 3, abril: 4, mayo: 5, junio: 6, julio: 7,
  agosto: 8, septiembre: 9, setiembre: 9, octubre: 10, noviembre: 11, diciembre: 12,
}

function normalizar(t) {
  return t.replace(/\s+/g, ' ')
          .replace(/[áÁ]/g, 'a').replace(/[éÉ]/g, 'e').replace(/[íÍ]/g, 'i')
          .replace(/[óÓ]/g, 'o').replace(/[úÚ]/g, 'u').replace(/[ñÑ]/g, 'n')
}

/** Todas las fechas del texto, con su posición, en ISO. */
function fechasEn(t) {
  const out = []
  // dd/mm/yyyy · dd-mm-yyyy · dd.mm.yyyy
  for (const m of t.matchAll(/\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b/g)) {
    let [, d, mo, y] = m
    y = Number(y); d = Number(d); mo = Number(mo)
    if (y < 100) y += y < 70 ? 2000 : 1900
    if (d > 31 || mo > 12 || d < 1 || mo < 1) continue
    if (y < 2000 || y > 2100) continue
    out.push({ iso: `${y}-${String(mo).padStart(2,'0')}-${String(d).padStart(2,'0')}`, pos: m.index })
  }
  // yyyy-mm-dd
  for (const m of t.matchAll(/\b(20\d{2})-(\d{1,2})-(\d{1,2})\b/g)) {
    const [, y, mo, d] = m
    if (Number(d) > 31 || Number(mo) > 12) continue
    out.push({ iso: `${y}-${String(Number(mo)).padStart(2,'0')}-${String(Number(d)).padStart(2,'0')}`, pos: m.index })
  }
  // 26 de marzo de 2024
  for (const m of t.matchAll(/\b(\d{1,2})\s+de\s+([a-z]+)\s+(?:de\s+|del\s+)?(20\d{2})\b/gi)) {
    const mo = MESES[m[2].toLowerCase()]
    if (!mo) continue
    out.push({ iso: `${m[3]}-${String(mo).padStart(2,'0')}-${String(Number(m[1])).padStart(2,'0')}`, pos: m.index })
  }
  return out
}

function sumar(iso, { anios = 0, meses = 0 }) {
  const [y, m, d] = iso.split('-').map(Number)
  const dt = new Date(Date.UTC(y + anios, m - 1 + meses, d))
  return dt.toISOString().slice(0, 10)
}

const RE_VENCE = /(vence|vencimiento|valido hasta|valida hasta|vigente hasta|caduca|expira|fecha de termino|proxima revision|proximo control)/i
const RE_EMISION = /(fecha de emision|fecha emision|fecha de inspeccion|fecha inspeccion|fecha de instalacion|fecha instalacion|fecha de certificacion|fecha de control|emitido el|fecha de ensayo|fecha de prueba|fecha)/i
const RE_VIGENCIA = /valid[oa]?\s+por\s+(un|una|\d+)\s*(anos?|ano|meses|mes)|periodo\s+de\s+(un|una|\d+)\s*(anos?|ano|meses|mes)|vigencia\s+(?:de\s+)?(un|una|\d+)\s*(anos?|ano|meses|mes)/i

function palabraANumero(w) {
  if (!w) return null
  const s = String(w).toLowerCase()
  if (s === 'un' || s === 'una') return 1
  const n = Number(s)
  return Number.isFinite(n) ? n : null
}

/** Lee el documento y propone el vencimiento. */
function analizar(textoCrudo) {
  const t = normalizar(textoCrudo)
  const bajo = t.toLowerCase()
  const fechas = fechasEn(t)
  if (fechas.length === 0) {
    return { confianza: 'sin_fecha', motivo: 'El PDF no tiene ninguna fecha legible (puede ser un escaneo sin texto)' }
  }

  // 1) Vencimiento explícito: la fecha más cercana después de la palabra clave.
  //    OJO: en las pólizas «Vencimiento» encabeza la TABLA DE CUOTAS del pago
  //    («Nro Cuota | Vencimiento | Total»), no la vigencia del seguro. Tomar esa
  //    fecha daba pólizas «vencidas en 2024» que en realidad estaban al día: el
  //    número era el de la primera cuota. Si el contexto huele a plan de pago,
  //    esta regla no aplica y se sigue con las siguientes.
  const mVence = (() => {
    for (const m of bajo.matchAll(new RegExp(RE_VENCE.source, 'gi'))) {
      const ctx = bajo.slice(Math.max(0, m.index - 90), m.index + 90)
      if (/cuota|dividendo|prima\s|forma de pago|plan de pago/.test(ctx)) continue
      return m
    }
    return null
  })()
  if (mVence) {
    const p = mVence.index
    const cerca = fechas
      .map((f) => ({ ...f, dist: f.pos - p }))
      .filter((f) => f.dist > 0 && f.dist < 120)
      .sort((a, b) => a.dist - b.dist)[0]
    if (cerca) {
      return {
        vencimiento: cerca.iso, confianza: 'alta',
        regla: 'vencimiento explícito en el documento',
        evidencia: t.slice(Math.max(0, p - 40), p + 120).trim(),
      }
    }
  }

  // 2) Rango «desde X hasta Y»: la forma en que lo dicen los seguros y el SOAP
  //    («RIGE DESDE 01/10/2025 HASTA 30/09/2026»). El «hasta» suelto no sirve
  //    de ancla —aparece en cualquier frase— así que se exige el «desde» antes.
  const mRango = bajo.match(/(rige\s+desde|vigencia[^.]{0,60}?desde|desde)\s*:?\s*/)
  if (mRango) {
    const desdePos = mRango.index + mRango[0].length
    const iHasta = bajo.indexOf('hasta', desdePos)
    if (iHasta > 0 && iHasta - desdePos < 260) {
      const tras = fechas.map((f) => ({ ...f, dist: f.pos - iHasta }))
                         .filter((f) => f.dist > 0 && f.dist < 160)
                         .sort((a, b) => a.dist - b.dist)[0]
      const antes = fechas.map((f) => ({ ...f, dist: f.pos - desdePos }))
                          .filter((f) => f.dist >= 0 && f.pos < iHasta)
                          .sort((a, b) => a.dist - b.dist)[0]
      if (tras && (!antes || tras.iso > antes.iso)) {
        return {
          emision: antes?.iso, vencimiento: tras.iso, confianza: 'alta',
          regla: 'rango «desde … hasta …» del documento',
          evidencia: t.slice(Math.max(0, mRango.index - 30), iHasta + 120).trim(),
        }
      }
    }
  }

  // 3) Fecha base + vigencia declarada.
  const mVig = bajo.match(RE_VIGENCIA)
  if (mVig) {
    const n = palabraANumero(mVig[1] ?? mVig[3] ?? mVig[5])
    const unidad = (mVig[2] ?? mVig[4] ?? mVig[6] ?? '').toLowerCase()
    const esMes = unidad.startsWith('mes')
    if (n) {
      const mEmi = bajo.match(RE_EMISION)
      let base = null
      if (mEmi) {
        const p = mEmi.index
        base = fechas.map((f) => ({ ...f, dist: f.pos - p }))
                     .filter((f) => f.dist > 0 && f.dist < 200)
                     .sort((a, b) => a.dist - b.dist)[0]
      }
      // Sin etiqueta clara, la fecha más antigua del documento suele ser la de
      // emisión: las posteriores son de firmas, impresión o normas citadas.
      if (!base) base = [...fechas].sort((a, b) => a.iso.localeCompare(b.iso))[0]
      if (base) {
        return {
          emision: base.iso,
          vencimiento: sumar(base.iso, esMes ? { meses: n } : { anios: n }),
          confianza: mEmi ? 'alta' : 'media',
          regla: `emisión + ${n} ${esMes ? 'mes(es)' : 'año(s)'} declarados`,
          evidencia: t.slice(Math.max(0, mVig.index - 60), mVig.index + 100).trim(),
        }
      }
    }
  }

  // 4) Sin regla: se deja la fecha más antigua como pista, sin proponer nada.
  const masAntigua = [...fechas].sort((a, b) => a.iso.localeCompare(b.iso))[0]
  return {
    emision: masAntigua.iso, confianza: 'baja',
    motivo: 'No dice vencimiento ni vigencia: hay que abrirlo',
    evidencia: t.slice(0, 220).trim(),
  }
}

// ── Main ────────────────────────────────────────────────────────────────────
const args = process.argv.slice(2)
const soloPatente = args.includes('--patente') ? args[args.indexOf('--patente') + 1] : null
const todos = args.includes('--todos')

const client = new pg.Client({
  connectionString: (process.env.SUPABASE_DB_URL || '').trim(),
  ssl: { rejectUnauthorized: false },
})
await client.connect()

const where = [`c.archivo_url IS NOT NULL`]
if (!todos && !soloPatente) where.push(`c.fecha_vencimiento::date = '2099-12-31'`)
if (soloPatente) where.push(`a.patente = '${soloPatente.replace(/'/g, "''")}'`)

const { rows } = await client.query(`
  SELECT c.id, c.tipo, c.archivo_url, c.fecha_emision::date AS emision_bd,
         c.fecha_vencimiento::date AS vence_bd, c.estado,
         a.patente, a.codigo AS activo_codigo
    FROM certificaciones c JOIN activos a ON a.id = c.activo_id
   WHERE ${where.join(' AND ')}
   ORDER BY a.patente, c.tipo`)

console.log(`Certificados a analizar: ${rows.length}\n`)

const OUT = resolve(__dirname, '../../reportes')
if (!existsSync(OUT)) mkdirSync(OUT, { recursive: true })

const resultados = []
let i = 0
for (const r of rows) {
  i++
  const etiqueta = `${r.patente ?? r.activo_codigo} · ${r.tipo}`
  try {
    const resp = await fetch(r.archivo_url)
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
    const buf = Buffer.from(await resp.arrayBuffer())
    const texto = await textoDePdf(buf)
    const an = analizar(texto)
    resultados.push({ ...r, ...an, caracteres: texto.trim().length })
    const v = an.vencimiento ?? '—'
    const alerta = an.vencimiento && an.vencimiento < new Date().toISOString().slice(0, 10) ? ' ⚠ VENCIDO' : ''
    console.log(`[${i}/${rows.length}] ${etiqueta.padEnd(42)} ${String(an.confianza).padEnd(10)} ${v}${alerta}`)
  } catch (e) {
    resultados.push({ ...r, confianza: 'error', motivo: e.message })
    console.log(`[${i}/${rows.length}] ${etiqueta.padEnd(42)} ERROR      ${e.message}`)
  }
}

const hoy = new Date().toISOString().slice(0, 10)
writeFileSync(resolve(OUT, 'certificados-propuesta.json'), JSON.stringify(resultados, null, 2), 'utf8')

const csv = ['patente;tipo;confianza;regla;emision_propuesta;vencimiento_propuesto;vencido;vence_en_bd;estado_bd;evidencia;certificacion_id']
for (const r of resultados) {
  const vencido = r.vencimiento ? (r.vencimiento < hoy ? 'SI' : 'no') : ''
  csv.push([r.patente ?? r.activo_codigo, r.tipo, r.confianza, r.regla ?? r.motivo ?? '',
            r.emision ?? '', r.vencimiento ?? '', vencido, r.vence_bd ?? '', r.estado,
            (r.evidencia ?? '').replace(/[;\n\r]/g, ' ').slice(0, 300), r.id].join(';'))
}
writeFileSync(resolve(OUT, 'certificados-propuesta.csv'), '﻿' + csv.join('\n'), 'utf8')

const porConf = resultados.reduce((a, r) => { a[r.confianza] = (a[r.confianza] ?? 0) + 1; return a }, {})
const vencidos = resultados.filter((r) => r.vencimiento && r.vencimiento < hoy)
console.log('\n── Resumen ──────────────────────────────────────')
for (const [k, v] of Object.entries(porConf).sort((a, b) => b[1] - a[1])) console.log(`  ${k.padEnd(12)} ${v}`)
console.log(`\n  VENCIDOS detectados: ${vencidos.length}`)
for (const v of vencidos.slice(0, 25)) console.log(`    ${v.patente} · ${v.tipo} → venció ${v.vencimiento}`)
console.log(`\n  Propuesta en reportes/certificados-propuesta.csv`)

await client.end()
