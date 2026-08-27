// ============================================================================
// El Excel de la revisión documental: una hoja por patente, con la foto
// ----------------------------------------------------------------------------
// Manuel, 27-08-2026: «necesito que de tu análisis forense se haga un Excel,
// con todas las patentes y en su interior fotos con los papeles y las fechas
// que se están considerando, para realizar una revisión completa».
//
// La idea es que se pueda revisar sin abrir un solo PDF: en cada fila está la
// foto del papel y, al lado, la fecha que el sistema está usando y de dónde
// salió. Quien revisa mira la foto, mira la fecha, y marca.
//
// ── LO QUE NO HACE ─────────────────────────────────────────────────────────
// No decide. Donde la auditoría leyó el documento, lo dice y muestra la frase;
// donde no pudo, lo dice también. Las dos últimas columnas van en blanco a
// propósito: son para quien revisa.
// ============================================================================
import { readFileSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const RAIZ = resolve(__dirname, '../..')
const FE = resolve(RAIZ, 'frontend')
const ExcelJS = (await import(pathToFileURL(resolve(FE, 'node_modules/exceljs/lib/exceljs.nodejs.js')).href)).default

const MINI = resolve(RAIZ, 'reportes/forense/miniaturas')
const forense = JSON.parse(readFileSync(resolve(RAIZ, 'reportes/forense/forense.json'), 'utf8'))
const fallos = Object.fromEntries(
  JSON.parse(readFileSync(resolve(RAIZ, 'reportes/forense/miniaturas.json'), 'utf8')).map((m) => [m.id, m]))

const HOY = process.argv[2] ?? '2026-08-27'

const TIPO = {
  revision_tecnica: 'Revisión técnica', soap: 'SOAP', permiso_circulacion: 'Permiso de circulación',
  seguro_rc: 'Seguro responsabilidad civil', hermeticidad: 'Hermeticidad del estanque',
  laminas_seguridad: 'Láminas de seguridad', analisis_gases: 'Análisis de gases',
  cert_cabina: 'Certificado de cabina', tacografo: 'Tacógrafo', torque_ruedas: 'Torque de ruedas',
  ausencia_falla_ecm: 'Ausencia de falla ECM', operatividad: 'Operatividad', mantencion: 'Mantención',
  mant_hidraulico: 'Mantención hidráulica', aire_acondicionado: 'Aire acondicionado',
  inventario_neumaticos: 'Inventario de neumáticos', grilletes_eslingas: 'Grilletes y eslingas',
  barra_antivuelco: 'Barra antivuelco', sist_riego: 'Sistema de riego', flujo_descarga: 'Flujo de descarga',
  optico_sobrellenado: 'Óptico de sobrellenado', calibracion: 'Calibración', tc8_sec: 'TC8 SEC',
  inscripcion_sec: 'Inscripción SEC', inscripcion_rnvm: 'Inscripción RNVM', padron: 'Padrón',
  ficha_tecnica: 'Ficha técnica', factura_compra: 'Factura de compra', homologacion: 'Homologación',
  gps: 'GPS', cert_gancho: 'Certificado de gancho', sec: 'SEC', seremi: 'SEREMI', otra: 'Otro',
}
const nombreTipo = (t) => TIPO[t] ?? t.replace(/_/g, ' ')

const ORIGEN = {
  documento: 'Leída del documento',
  documento_sin_vencimiento: 'El documento dice que no vence',
  manual: 'Escrita a mano',
  carga_inicial: 'Carga masiva de abril',
  regla_2_anios: 'Regla de 2 años (descartada)',
}

const dia = (iso) => !iso || iso >= '2099-01-01' ? '' : iso.split('-').reverse().join('-')
const dias = (a, b) => Math.round((new Date(b) - new Date(a)) / 86400000)

function estado(r) {
  const v = r.sistema.vencimiento
  if (r.sistema.dudosa) return { t: 'FECHA NO CONFIABLE', c: 'FFF3E0', f: 'FFB45309' }
  if (r.sistema.origen === 'documento_sin_vencimiento') return { t: 'Sin vencimiento', c: 'FFF5F5F4', f: 'FF57534E' }
  if (!v || v >= '2099-01-01') {
    return r.veredicto === 'NO_CADUCA'
      ? { t: 'No caduca', c: 'FFF5F5F4', f: 'FF57534E' }
      : { t: 'FALTA LA FECHA', c: 'FFFDF8EA', f: 'FFA16207' }
  }
  const d = dias(HOY, v)
  if (d < 0) return { t: `VENCIDO hace ${-d} días`, c: 'FFFDF0EF', f: 'FFB3261E' }
  if (d <= 30) return { t: `Vence en ${d} días`, c: 'FFFDF8EA', f: 'FFA16207' }
  return { t: 'Vigente', c: 'FFF0F8F2', f: 'FF15803D' }
}

/** Qué dice el documento, en una frase que se pueda leer de corrido. */
function dictamen(r) {
  const f = fallos[r.id]
  if (f && !f.ok) return f.motivo

  // Si la fecha salió de abrir el documento durante esta auditoría, eso vale
  // más que lo que pueda decir el lector automático: se muestra tal cual.
  const nota = (r.sistema.nota ?? '').replace(/^MIG\d+ · /, '')
  if (nota) {
    const aOjo = /le[íi]do a ojo|le[íi]do del certificado|le[íi]do del texto/i.test(nota)
    return (aOjo ? 'Verificado en esta auditoría: ' : '')
      + nota.replace(/^le[íi]do a ojo del escaneo, /i, '')
            .replace(/^le[íi]do a ojo del escaneo: /i, '')
            .replace(/^le[íi]do del certificado /i, 'certificado ')
            .replace(/^le[íi]do del texto del documento: /i, '')
  }
  if (r.sistema.dudosa && r.sistema.nota_duda) {
    return r.sistema.nota_duda.replace(/^MIG\d+ · /, '')
  }

  switch (r.veredicto) {
    case 'DECLARA':
      return `El documento dice que vence el ${dia(r.vencimiento)}.`
        + (r.contraste === 'DIFIERE' ? '  ← NO COINCIDE con la fecha del sistema' : '')
    case 'NO_DECLARA': return 'Se leyó el documento y no menciona fecha de vencimiento.'
    case 'NO_CADUCA':  return 'Papel de identidad del equipo: no vence.'
    case 'ILEGIBLE':   return 'Es un escaneo sin texto: la fecha hay que leerla en la foto.'
    default:           return r.motivo ?? ''
  }
}

// ── El libro ────────────────────────────────────────────────────────────────
const wb = new ExcelJS.Workbook()
wb.creator = 'SICOM-ICEO · auditoría forense documental'
wb.created = new Date(HOY)

const porPatente = new Map()
for (const r of forense) {
  if (!porPatente.has(r.patente)) porPatente.set(r.patente, [])
  porPatente.get(r.patente).push(r)
}
const patentes = [...porPatente.keys()].sort()

// ── Hoja 1: el resumen ──────────────────────────────────────────────────────
const res = wb.addWorksheet('Resumen', { views: [{ state: 'frozen', ySplit: 3 }] })
res.mergeCells('A1:H1')
res.getCell('A1').value = 'Revisión documental de la flota'
res.getCell('A1').font = { size: 16, bold: true, color: { argb: 'FF1C1917' } }
res.getRow(1).height = 26
res.mergeCells('A2:H2')
res.getCell('A2').value = `Al ${dia(HOY)}. Cada patente tiene su propia hoja, con la foto de cada papel y la fecha que el sistema está usando.`
res.getCell('A2').font = { size: 10, color: { argb: 'FF57534E' } }

const cabRes = ['Patente', 'Papeles', 'Vencidos', 'De ellos, bloquean', 'Falta la fecha', 'Por vencer (30 d)', 'Vigentes', 'Sin vencimiento / no caducan']
res.getRow(3).values = cabRes
res.getRow(3).font = { bold: true, size: 10 }
res.getRow(3).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFF5F5F4' } }
res.getRow(3).alignment = { wrapText: true, vertical: 'middle' }
res.getRow(3).height = 34
res.columns = [{ width: 12 }, { width: 9 }, { width: 10 }, { width: 17 }, { width: 14 }, { width: 16 }, { width: 10 }, { width: 26 }]

for (const p of patentes) {
  const rs = porPatente.get(p)
  const e = rs.map(estado)
  const venc = e.filter((x) => x.t.startsWith('VENCIDO')).length
  const bloq = rs.filter((r, i) => r.bloqueante && e[i].t.startsWith('VENCIDO')).length
  const fila = res.addRow([p, rs.length, venc, bloq,
    e.filter((x) => x.t === 'FALTA LA FECHA' || x.t === 'FECHA NO CONFIABLE').length,
    e.filter((x) => x.t.startsWith('Vence en')).length,
    e.filter((x) => x.t === 'Vigente').length,
    e.filter((x) => x.t === 'Sin vencimiento' || x.t === 'No caduca').length])
  fila.getCell(1).font = { bold: true }
  if (venc) fila.getCell(3).font = { bold: true, color: { argb: 'FFB3261E' } }
  if (bloq) fila.getCell(4).font = { bold: true, color: { argb: 'FFB3261E' } }
  fila.getCell(1).value = { text: p, hyperlink: `#'${p}'!A1` }
  fila.getCell(1).font = { bold: true, color: { argb: 'FF1D4ED8' }, underline: true }
}
res.autoFilter = { from: 'A3', to: `H${3 + patentes.length}` }

// ── Una hoja por patente ────────────────────────────────────────────────────
const ANCHO_FOTO = 430, ALTO_FOTO = 600

for (const p of patentes) {
  const hoja = wb.addWorksheet(p, { views: [{ state: 'frozen', ySplit: 3 }] })
  hoja.columns = [
    { width: 24 },   // tipo
    { width: 10 },   // bloquea
    { width: 15 },   // fecha del sistema
    { width: 24 },   // de dónde salió
    { width: 22 },   // estado
    { width: 52 },   // qué dice el documento
    { width: 62 },   // foto
    { width: 16 },   // ¿está bien?
    { width: 16 },   // fecha correcta
  ]

  hoja.mergeCells('A1:I1')
  hoja.getCell('A1').value = `${p} — ${porPatente.get(p).length} papeles`
  hoja.getCell('A1').font = { size: 14, bold: true }
  hoja.getRow(1).height = 22
  hoja.mergeCells('A2:I2')
  hoja.getCell('A2').value = 'Mirar la foto, comparar con la fecha del sistema, y marcar en las dos últimas columnas. Volver al Resumen: primera hoja.'
  hoja.getCell('A2').font = { size: 9, italic: true, color: { argb: 'FF57534E' } }

  const cab = ['Papel', '¿Bloquea?', 'Fecha del sistema', 'De dónde salió esa fecha', 'Estado hoy',
               'Qué dice el documento', 'Foto del papel', '¿Está bien?', 'Fecha correcta']
  hoja.getRow(3).values = cab
  hoja.getRow(3).font = { bold: true, size: 10 }
  hoja.getRow(3).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFF5F5F4' } }
  hoja.getRow(3).alignment = { wrapText: true, vertical: 'middle' }
  hoja.getRow(3).height = 32

  const rs = porPatente.get(p).slice().sort((a, b) => {
    const orden = (r) => {
      const e = estado(r).t
      return e.startsWith('VENCIDO') ? 0 : e === 'FECHA NO CONFIABLE' ? 1 : e === 'FALTA LA FECHA' ? 2
           : e.startsWith('Vence en') ? 3 : e === 'Vigente' ? 4 : 5
    }
    return orden(a) - orden(b) || a.tipo.localeCompare(b.tipo)
  })

  let n = 4
  for (const r of rs) {
    const e = estado(r)
    const fila = hoja.getRow(n)
    fila.values = [
      nombreTipo(r.tipo),
      r.bloqueante ? 'SÍ' : '',
      dia(r.sistema.vencimiento) || '—',
      ORIGEN[r.sistema.origen] ?? 'No consta',
      e.t,
      dictamen(r),
      '', '', '',
    ]
    fila.height = ALTO_FOTO * 0.76      // los puntos de Excel son ~0,75 px
    fila.alignment = { vertical: 'top', wrapText: true }
    fila.getCell(1).font = { bold: true, size: 11 }
    fila.getCell(2).font = { bold: true, color: { argb: 'FFB3261E' } }
    fila.getCell(2).alignment = { horizontal: 'center', vertical: 'top' }
    fila.getCell(3).font = { size: 12, bold: true }
    fila.getCell(5).font = { bold: true, color: { argb: e.f } }
    fila.getCell(5).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: e.c } }
    if (r.contraste === 'DIFIERE') {
      fila.getCell(6).font = { bold: true, color: { argb: 'FFB3261E' } }
      fila.getCell(6).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFFDF0EF' } }
    }
    // Las dos columnas de quien revisa, en blanco y marcadas.
    for (const c of [8, 9]) {
      fila.getCell(c).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFFFFBEB' } }
      fila.getCell(c).border = { left: { style: 'thin', color: { argb: 'FFD6D3D1' } } }
    }

    const foto = resolve(MINI, r.id + '.jpg')
    if (existsSync(foto)) {
      const id = wb.addImage({ filename: foto, extension: 'jpeg' })
      hoja.addImage(id, {
        tl: { col: 6.1, row: n - 1 + 0.05 },
        ext: { width: ANCHO_FOTO, height: ALTO_FOTO },
        editAs: 'oneCell',
      })
    } else {
      fila.getCell(7).value = fallos[r.id]?.motivo ?? 'Sin foto disponible.'
      fila.getCell(7).font = { italic: true, color: { argb: 'FFB3261E' } }
    }
    n++
  }
}

const salida = resolve(RAIZ, 'reportes/Revision_documental_flota.xlsx')
await wb.xlsx.writeFile(salida)
console.log(`${salida}\n${patentes.length} patentes · ${forense.length} papeles`)
