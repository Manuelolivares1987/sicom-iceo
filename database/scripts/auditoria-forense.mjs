// ============================================================================
// Auditoría forense: qué dice cada papel, uno por uno
// ----------------------------------------------------------------------------
// Manuel, 26-08-2026: «necesito que hagas una auditoría forense a cada papel».
//
// Forense quiere decir que de cada documento queda un registro de lo que dice,
// con la frase textual que lo dice, y la diferencia contra lo que afirma el
// sistema. No hay promedios ni muestreos: son todos.
//
// Lo que hace con cada uno:
//   · lo descarga (y lo deja en caché, para poder repetir la auditoría sin
//     volver a bajar 900 archivos)
//   · reconstruye sus líneas por posición en la página
//   · extrae TODAS las fechas con la frase donde aparecen
//   · dictamina: DECLARA su vencimiento / NO_DECLARA / ILEGIBLE
//   · si es un escaneo, saca la imagen más grande a disco para leerla a ojo
//
// La lógica de lectura vive en lib/leer-papel.mjs y tiene tests. Se separó
// justamente porque la versión anterior no se podía probar y acumuló tres
// fallas en cadena.
//
// NO escribe en la base. Produce reportes/forense/.
// ============================================================================
import { readFileSync, writeFileSync, existsSync, mkdirSync, statSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import pg from 'pg'
import dotenv from 'dotenv'
import { veredicto, emisionDeclarada, fechasDe, DICE_VENCE, DICE_EMISION, ES_PAGO } from './lib/leer-papel.mjs'

const __dirname = dirname(fileURLToPath(import.meta.url))
const RAIZ = resolve(__dirname, '../..')
const FE = resolve(RAIZ, 'frontend')
dotenv.config({ path: resolve(RAIZ, '.env.supabase-admin.local') })

// En Windows un path absoluto no es una URL válida para import().
const pdfjs = await import(pathToFileURL(resolve(FE, 'node_modules/pdfjs-dist/legacy/build/pdf.mjs')).href)

const CACHE = process.env.FORENSE_CACHE || resolve(RAIZ, '.cache-papeles')
const SALIDA = resolve(RAIZ, 'reportes/forense')
for (const d of [CACHE, SALIDA, resolve(SALIDA, 'escaneos')]) if (!existsSync(d)) mkdirSync(d, { recursive: true })

// ── Líneas por posición, no por orden de archivo ────────────────────────────
function lineasDeItems(items) {
  if (!items.some((i) => i.transform)) return [items.map((i) => i.str).join(' ')]
  const pos = items.filter((i) => (i.str ?? '').trim())
    .map((i) => ({ s: i.str, x: i.transform[4], y: Math.round(i.transform[5]) }))
  pos.sort((a, b) => b.y - a.y || a.x - b.x)
  const out = []
  let ultimaY = null
  for (const o of pos) {
    if (ultimaY === null || Math.abs(ultimaY - o.y) > 4) { out.push(o.s); ultimaY = o.y }
    else out[out.length - 1] += ' ' + o.s
  }
  return out
}

async function leerPdf(buf) {
  const doc = await pdfjs.getDocument({
    data: new Uint8Array(buf), useSystemFonts: true, isEvalSupported: false,
    standardFontDataUrl: resolve(FE, 'node_modules/pdfjs-dist/standard_fonts') + '/',
  }).promise
  const lineas = []
  for (let p = 1; p <= doc.numPages; p++) {
    const tc = await (await doc.getPage(p)).getTextContent()
    lineas.push(...lineasDeItems(tc.items).map((l) => l.replace(/\s+/g, ' ').trim()).filter(Boolean))
  }
  const n = doc.numPages
  await doc.destroy()
  return { lineas, paginas: n }
}

/**
 * La imagen más grande incrustada en el PDF. La primera suele ser el logo o la
 * marca de agua de CamScanner: por tamaño se acierta con la página escaneada.
 */
function imagenMasGrande(buf) {
  const trozos = []
  for (let i = 0; i < buf.length - 3; i++) {
    if (buf[i] === 0xFF && buf[i + 1] === 0xD8 && buf[i + 2] === 0xFF) {
      for (let j = i + 3; j < buf.length - 1; j++) {
        if (buf[j] === 0xFF && buf[j + 1] === 0xD9) { trozos.push({ ini: i, largo: j + 2 - i }); i = j + 1; break }
      }
    }
  }
  if (!trozos.length) return null
  trozos.sort((a, b) => b.largo - a.largo)
  return buf.subarray(trozos[0].ini, trozos[0].ini + trozos[0].largo)
}

/**
 * Qué es el archivo de verdad, según sus primeros bytes. La extensión miente:
 * 16 «PDF corruptos» de la flota resultaron ser PNG, JPEG y un archivo de
 * Office subidos tal cual. Siete de ellos respaldan una revisión técnica
 * bloqueante con fecha hasta 2027.
 */
function tipoReal(buf) {
  if (buf.slice(0, 4).toString('latin1') === '%PDF') return 'pdf'
  if (buf[0] === 0xFF && buf[1] === 0xD8 && buf[2] === 0xFF) return 'jpg'
  if (buf.slice(0, 4).toString('hex') === '89504e47') return 'png'
  if (buf.slice(0, 2).toString('latin1') === 'PK') return 'office'
  return 'desconocido'
}

const fechaISO = (v) => {
  if (!v) return null
  if (typeof v === 'string') return v.slice(0, 10)
  const d = new Date(v)
  return isNaN(+d) ? null
    : `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

// ── Traer el maestro ────────────────────────────────────────────────────────
const db = new pg.Client({ connectionString: process.env.SUPABASE_DB_URL, ssl: { rejectUnauthorized: false } })
await db.connect()
const { rows } = await db.query(`
  SELECT c.id, COALESCE(a.patente, a.codigo) AS patente, a.id AS activo_id,
         c.tipo::text AS tipo, c.archivo_url, c.bloqueante,
         c.numero_certificado, c.fecha_emision, c.fecha_vencimiento,
         c.fecha_origen, c.fecha_origen_nota, c.vigencia_dudosa,
         c.vigencia_dudosa_nota, v.estado_real::text AS estado_sistema
    FROM certificaciones c
    JOIN activos a ON a.id = c.activo_id
    LEFT JOIN v_certificacion_actual v ON v.id = c.id
   WHERE c.archivo_url IS NOT NULL
     AND a.estado <> 'dado_baja'::estado_activo_enum
     AND c.id IN (SELECT id FROM v_certificacion_actual)
   ORDER BY c.bloqueante DESC NULLS LAST, 2, 4`)
await db.end()

const soloIds = process.argv[2] ? new Set(JSON.parse(readFileSync(process.argv[2], 'utf8'))) : null
const objetivo = soloIds ? rows.filter((r) => soloIds.has(r.id)) : rows
console.log(`Auditoría forense de ${objetivo.length} papeles\n`)

const res = []
for (const [i, c] of objetivo.entries()) {
  const cacheFile = resolve(CACHE, `${c.id}.pdf`)
  const reg = {
    id: c.id, patente: c.patente, activo_id: c.activo_id, tipo: c.tipo,
    bloqueante: !!c.bloqueante, numero: c.numero_certificado,
    archivo_url: c.archivo_url,
    sistema: {
      emision: fechaISO(c.fecha_emision), vencimiento: fechaISO(c.fecha_vencimiento),
      origen: c.fecha_origen, nota: c.fecha_origen_nota,
      dudosa: c.vigencia_dudosa, nota_duda: c.vigencia_dudosa_nota,
      estado: c.estado_sistema,
    },
  }

  try {
    if (!existsSync(cacheFile) || statSync(cacheFile).size === 0) {
      const r = await fetch(c.archivo_url)
      if (!r.ok) throw new Error('HTTP ' + r.status)
      writeFileSync(cacheFile, Buffer.from(await r.arrayBuffer()))
    }
    const buf = readFileSync(cacheFile)
    reg.bytes = buf.length
    reg.formato = tipoReal(buf)

    if (reg.formato === 'office') {
      Object.assign(reg, veredicto([], c.tipo))
      if (reg.veredicto !== 'NO_CADUCA') {
        reg.veredicto = 'NO_ES_UN_DOCUMENTO'
        reg.motivo = 'El archivo es una planilla o documento de Office, no el certificado escaneado.'
      }
      contrastar(reg); res.push(reg); continue
    }

    if (reg.formato === 'jpg' || reg.formato === 'png') {
      // No es un PDF roto: es la foto del papel, subida tal cual. Se deja a mano
      // para leerla a ojo, igual que un escaneo.
      Object.assign(reg, veredicto([], c.tipo))
      if (reg.veredicto !== 'NO_CADUCA') {
        reg.veredicto = 'ILEGIBLE'
        reg.motivo = `El archivo es una imagen ${reg.formato.toUpperCase()}, no un PDF. Hay que leerla a ojo.`
        const dest = resolve(SALIDA, 'escaneos', `${c.patente}__${c.tipo}__${c.id.slice(0, 8)}.${reg.formato}`)
        writeFileSync(dest, buf)
        reg.imagen = dest
      }
      contrastar(reg); res.push(reg); continue
    }

    if (reg.formato === 'desconocido') {
      reg.veredicto = 'NO_ES_UN_DOCUMENTO'
      reg.motivo = 'El archivo no es ni PDF ni imagen: no se puede leer.'
      contrastar(reg); res.push(reg); continue
    }

    const { lineas, paginas } = await leerPdf(buf)
    reg.paginas = paginas
    reg.lineas_texto = lineas.length

    const v = veredicto(lineas, c.tipo)
    Object.assign(reg, v)
    const em = emisionDeclarada(lineas)
    if (em) reg.emision_documento = em.fecha

    // Todas las fechas del documento, con la frase donde aparecen. Es lo que
    // permite discutir un dictamen en vez de creerle.
    reg.fechas = []
    for (const l of lineas) {
      for (const f of fechasDe(l)) {
        reg.fechas.push({
          fecha: f.fecha,
          rol: ES_PAGO.test(l) ? 'cuota_de_pago'
             : DICE_VENCE.test(l) ? 'vencimiento'
             : DICE_EMISION.test(l) ? 'emision'
             : 'sin_etiqueta',
          linea: l.slice(0, 130),
        })
      }
    }
    // Sin duplicados: el mismo dato repetido en cada página no aporta.
    const vistas = new Set()
    reg.fechas = reg.fechas.filter((f) => {
      const k = f.fecha + '|' + f.rol
      if (vistas.has(k)) return false
      vistas.add(k); return true
    }).slice(0, 25)

    if (reg.veredicto === 'ILEGIBLE') {
      const img = imagenMasGrande(buf)
      if (img) {
        const dest = resolve(SALIDA, 'escaneos', `${c.patente}__${c.tipo}__${c.id.slice(0, 8)}.jpg`)
        writeFileSync(dest, img)
        reg.imagen = dest
        reg.motivo = 'Escaneo sin texto. Se extrajo la página para leerla a ojo.'
      } else {
        reg.motivo = 'Escaneo sin texto y sin imagen recuperable del PDF.'
      }
    }
  } catch (e) {
    reg.veredicto = 'ERROR'
    reg.motivo = String(e.message ?? e)
  }

  contrastar(reg)
  res.push(reg)
  if ((i + 1) % 50 === 0) console.log(`  ${i + 1}/${objetivo.length}`)
}

// El contraste: ¿lo que muestra el sistema es lo que dice el papel?
function contrastar(reg) {
  const sisFicticia = !reg.sistema.vencimiento || reg.sistema.vencimiento >= '2099-01-01'
  reg.contraste =
      reg.veredicto === 'DECLARA'    ? (reg.vencimiento === reg.sistema.vencimiento ? 'coincide' : 'DIFIERE')
    : reg.veredicto === 'NO_DECLARA' ? (sisFicticia ? 'coincide' : 'sistema_tiene_fecha_que_el_papel_no_dice')
    // Un papel de identidad no caduca: que el sistema le haya puesto una fecha
    // es un dato inventado, aunque parezca inofensivo.
    : reg.veredicto === 'NO_CADUCA'  ? (sisFicticia ? 'coincide' : 'sistema_tiene_fecha_que_el_papel_no_dice')
    : 'sin_dictamen'
}
for (const r of res) if (!r.contraste) contrastar(r)

writeFileSync(resolve(SALIDA, 'forense.json'), JSON.stringify(res, null, 2))

const esc = (s) => `"${String(s ?? '').replace(/"/g, '""')}"`
writeFileSync(resolve(SALIDA, 'forense.csv'),
  'patente;tipo;bloqueante;veredicto;dice_el_papel;dice_el_sistema;contraste;regla;evidencia\n' +
  res.map((r) => [
    r.patente, r.tipo, r.bloqueante ? 'SI' : '', r.veredicto,
    r.vencimiento ?? (r.veredicto === 'NO_DECLARA' ? 'SIN VENCIMIENTO' : ''),
    r.sistema.vencimiento && r.sistema.vencimiento < '2099-01-01' ? r.sistema.vencimiento : 'sin fecha',
    r.contraste, r.regla ?? '', esc(r.evidencia ?? r.motivo ?? ''),
  ].join(';')).join('\n'))

const n = (f) => res.filter(f).length
console.log(`
── Forense ──────────────────────────────────────────────────
  DECLARA su vencimiento     ${n((r) => r.veredicto === 'DECLARA')}
     coincide con el sistema    ${n((r) => r.veredicto === 'DECLARA' && r.contraste === 'coincide')}
     DIFIERE                    ${n((r) => r.veredicto === 'DECLARA' && r.contraste === 'DIFIERE')}
  NO declara vencimiento     ${n((r) => r.veredicto === 'NO_DECLARA')}
  No caduca (identidad)      ${n((r) => r.veredicto === 'NO_CADUCA')}
     el sistema le puso fecha   ${n((r) => r.veredicto === 'NO_DECLARA' && r.contraste !== 'coincide')}
  Escaneo, hay que mirarlo   ${n((r) => r.veredicto === 'ILEGIBLE')}
     con imagen extraída        ${n((r) => r.veredicto === 'ILEGIBLE' && r.imagen)}
  Error al abrir             ${n((r) => r.veredicto === 'ERROR')}
  El archivo no es el papel  ${n((r) => r.veredicto === 'NO_ES_UN_DOCUMENTO')}
  ────────────────────────────────────────────────────────
  TOTAL                      ${res.length}   (bloqueantes: ${n((r) => r.bloqueante)})

  reportes/forense/forense.csv · forense.json
  escaneos en reportes/forense/escaneos/`)
