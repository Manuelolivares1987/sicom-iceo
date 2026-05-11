// ============================================================================
// oc-pdf-parser.ts — Extracción texto-first de OCs en PDF
// ----------------------------------------------------------------------------
// Usa pdfjs-dist (dynamic import) para extraer texto del PDF, luego aplica
// regex/heurísticas para detectar cabecera + items. NO usa OCR, así que PDFs
// escaneados como imagen no se parsearán y devolverán warnings.
//
// Diseñado para el formato OC Pillado (campos: N° OC, Proveedor, RUT, fechas
// emisión/entrega, Neto, IVA, Total, Forma de pago, tabla de items con
// Código/Descripción/CCosto/Cant./Unidad/Precio/Total).
//
// El parser es DEFENSIVO: si no encuentra un campo, devuelve null y agrega
// un warning. Nunca lanza excepción salvo que el archivo no sea PDF.
// ============================================================================

import type { TipoItemOC } from '@/lib/services/bodega-oc'

// ── Tipos ───────────────────────────────────────────────────────────────────

export interface ParsedOCItem {
  codigo_externo: string | null
  descripcion: string
  cantidad: number
  unidad_externa: string | null
  centro_costo_codigo_externo: string | null
  precio_unitario_clp: number | null
  total_linea_clp: number | null
  tipo_item_sugerido: TipoItemOC
  requiere_stock_sugerido: boolean
  confidence: number  // 0-1
}

export interface ParsedOC {
  numero_oc_externo: string | null
  proveedor_nombre: string | null
  proveedor_rut: string | null
  fecha_emision: string | null   // YYYY-MM-DD
  fecha_entrega: string | null
  neto_clp: number | null
  iva_clp: number | null
  total_clp: number | null
  forma_pago: string | null
  moneda: string | null
  raw_text: string
  confidence: number  // 0-1, promedio cabecera + items
  warnings: string[]
  items: ParsedOCItem[]
}

// ── Helpers ─────────────────────────────────────────────────────────────────

const REGEX_SERVICIO = /\b(SERVICIO|CERTIFICAC\w+|OPERATIVIDAD|MANTENIM\w+|CALIBRAC\w+|REPARAC\w+|TRANSPORT\w*|TRASLADO|ARRIEND\w*|ALQUILE\w*)\b/i

function parseNumeroCLP(s: string | null | undefined): number | null {
  if (!s) return null
  // "290.700" -> 290700 (CLP usa . como separador de miles)
  // "290.700,50" -> 290700.50 (raro en CLP pero parseamos)
  // "290,700.50" -> 290700.50 (formato US, defensivo)
  let cleaned = s.trim().replace(/[^\d.,-]/g, '')
  if (cleaned === '') return null
  const lastComma = cleaned.lastIndexOf(',')
  const lastDot = cleaned.lastIndexOf('.')
  if (lastComma > -1 && lastDot > -1) {
    // Ambos presentes: el último es decimal
    if (lastComma > lastDot) {
      cleaned = cleaned.replace(/\./g, '').replace(',', '.')
    } else {
      cleaned = cleaned.replace(/,/g, '')
    }
  } else if (lastComma > -1) {
    // Solo coma: si hay 1 coma y siguen 1-2 dígitos -> decimal; si no, separador miles
    const after = cleaned.length - lastComma - 1
    if (after === 1 || after === 2) cleaned = cleaned.replace(',', '.')
    else cleaned = cleaned.replace(/,/g, '')
  } else if (lastDot > -1) {
    // Solo punto: en CLP siempre es separador de miles si hay 3 dígitos después.
    const after = cleaned.length - lastDot - 1
    if (after === 3) cleaned = cleaned.replace(/\./g, '')
    // si after 1 o 2, asumimos decimal y dejamos el punto
  }
  const n = Number(cleaned)
  return Number.isFinite(n) ? n : null
}

function parseFechaCL(s: string | null | undefined): string | null {
  if (!s) return null
  // dd/mm/yyyy o dd-mm-yyyy
  const m = s.match(/(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})/)
  if (!m) return null
  const dd = m[1].padStart(2, '0')
  const mm = m[2].padStart(2, '0')
  const yy = m[3]
  return `${yy}-${mm}-${dd}`
}

function classifyItem(descripcion: string, unidad: string | null): {
  tipo: TipoItemOC
  requiereStock: boolean
} {
  if (REGEX_SERVICIO.test(descripcion)) {
    return { tipo: 'servicio', requiereStock: false }
  }
  const desc = descripcion.toLowerCase()
  if (desc.includes('combustible') || desc.includes('diesel') || desc.includes('petroleo') || desc.includes('gasolina')) {
    return { tipo: 'combustible', requiereStock: true }
  }
  if (desc.includes('aceite') || desc.includes('lubric') || desc.includes('shell') || desc.includes('rimula')) {
    return { tipo: 'lubricante', requiereStock: true }
  }
  if (desc.includes('filtro')) {
    return { tipo: 'inventariable', requiereStock: true }
  }
  if (desc.includes('repuesto') || desc.includes('pieza') || desc.includes('parte')) {
    return { tipo: 'repuesto', requiereStock: true }
  }
  // Default: inventariable con stock
  return { tipo: 'inventariable', requiereStock: true }
}

// ── Extracción de texto con pdfjs ───────────────────────────────────────────

async function extractText(file: File): Promise<string> {
  const pdfjsLib = await import('pdfjs-dist')
  // Worker desde CDN para evitar config webpack
  pdfjsLib.GlobalWorkerOptions.workerSrc =
    `https://unpkg.com/pdfjs-dist@${pdfjsLib.version}/build/pdf.worker.min.mjs`

  const arrayBuffer = await file.arrayBuffer()
  const pdf = await pdfjsLib.getDocument({ data: arrayBuffer }).promise
  const lines: string[] = []

  for (let p = 1; p <= pdf.numPages; p++) {
    const page = await pdf.getPage(p)
    const content = await page.getTextContent()
    // Agrupar items por línea aproximada (mismo y ± 2px)
    const items = content.items as Array<{ str: string; transform: number[] }>
    type Row = { y: number; parts: Array<{ x: number; str: string }> }
    const rows: Row[] = []
    for (const it of items) {
      if (!('transform' in it)) continue
      const [, , , , x, y] = it.transform
      let row = rows.find((r) => Math.abs(r.y - y) < 2)
      if (!row) {
        row = { y, parts: [] }
        rows.push(row)
      }
      row.parts.push({ x, str: it.str })
    }
    rows.sort((a, b) => b.y - a.y)  // top-down
    for (const r of rows) {
      r.parts.sort((a, b) => a.x - b.x)
      const text = r.parts.map((p) => p.str).join(' ').replace(/\s+/g, ' ').trim()
      if (text) lines.push(text)
    }
  }
  return lines.join('\n')
}

// ── Parser principal ────────────────────────────────────────────────────────

export async function parseOCFromPDF(file: File): Promise<ParsedOC> {
  const warnings: string[] = []
  let raw_text = ''

  try {
    raw_text = await extractText(file)
  } catch (e) {
    warnings.push('No se pudo extraer texto del PDF: ' + (e instanceof Error ? e.message : String(e)))
    return emptyParsed(raw_text, warnings)
  }

  if (raw_text.trim().length < 50) {
    warnings.push('PDF parece ser una imagen escaneada (texto extraído muy corto). Completa manualmente.')
    return emptyParsed(raw_text, warnings)
  }

  // ── Cabecera ─────────────────────────────────────────────────────────────
  const numero_oc_externo = parseNumeroOC(raw_text, warnings)
  const proveedor_rut     = parseRUT(raw_text)
  const proveedor_nombre  = parseProveedor(raw_text, proveedor_rut)
  const { fecha_emision, fecha_entrega } = parseFechas(raw_text)
  const neto_clp  = parseMonto(raw_text, /\b(?:Neto|Sub\s*Total|Subtotal)\s*[:.]?\s*\$?\s*([\d.,]+)/i)
  const iva_clp   = parseMonto(raw_text, /\bIVA\s*(?:\(?\d{1,2}%?\)?)?\s*[:.]?\s*\$?\s*([\d.,]+)/i)
  const total_clp = parseMonto(raw_text, /\bTotal(?:\s+(?:OC|Documento|Neto|Bruto))?\s*[:.]?\s*\$?\s*([\d.,]+)/i)
  const forma_pago = parseFormaPago(raw_text)
  const moneda = /CLP|PESOS\s+CHILE|\$\s*CHILENO/i.test(raw_text) ? 'CLP' : null

  if (!numero_oc_externo) warnings.push('No se detectó número OC.')
  if (!proveedor_nombre) warnings.push('No se detectó proveedor.')
  if (!fecha_emision) warnings.push('No se detectó fecha de emisión.')
  if (!total_clp) warnings.push('No se detectó monto total.')

  // ── Items ────────────────────────────────────────────────────────────────
  const items = parseItems(raw_text, warnings)
  if (items.length === 0) {
    warnings.push('No se detectaron items en la tabla. Agrega manualmente.')
  }

  // Confidence: campos cabecera detectados (max 7) + ratio items detectados
  const cabeceraFields = [numero_oc_externo, proveedor_nombre, proveedor_rut, fecha_emision, neto_clp, iva_clp, total_clp]
  const cabeceraScore = cabeceraFields.filter((x) => x != null).length / cabeceraFields.length
  const itemsScore = items.length > 0 ? 0.8 : 0
  const confidence = (cabeceraScore * 0.6 + itemsScore * 0.4)

  return {
    numero_oc_externo,
    proveedor_nombre,
    proveedor_rut,
    fecha_emision,
    fecha_entrega,
    neto_clp,
    iva_clp,
    total_clp,
    forma_pago,
    moneda,
    raw_text,
    confidence,
    warnings,
    items,
  }
}

function emptyParsed(raw_text: string, warnings: string[]): ParsedOC {
  return {
    numero_oc_externo: null,
    proveedor_nombre: null,
    proveedor_rut: null,
    fecha_emision: null,
    fecha_entrega: null,
    neto_clp: null,
    iva_clp: null,
    total_clp: null,
    forma_pago: null,
    moneda: null,
    raw_text,
    confidence: 0,
    warnings,
    items: [],
  }
}

// ── Parsers de campo ─────────────────────────────────────────────────────────

function parseNumeroOC(text: string, _w: string[]): string | null {
  // Patrones esperados (en orden de prioridad):
  //   "Orden de Compra N°: 13559" / "OC Nº 13559"
  //   "N° OC 13559" / "N° de OC: 13559"
  //   En el header puede aparecer solo el número junto a "OC".
  const patterns = [
    /Orden\s+de\s+Compra\s*N?[°ºo]?\s*:?\s*(\d{3,8})/i,
    /\bOC\s*N?[°ºo]?\s*:?\s*(\d{3,8})/i,
    /\bN[°ºo]\s*(?:de\s+)?OC\s*:?\s*(\d{3,8})/i,
    /\bN[°ºo]\s*:?\s*(\d{4,8})\b/i,
  ]
  for (const re of patterns) {
    const m = text.match(re)
    if (m) return m[1]
  }
  return null
}

function parseRUT(text: string): string | null {
  const m = text.match(/\b(\d{1,2}\.\d{3}\.\d{3}-[\dKk])\b/)
  return m ? m[1].toUpperCase() : null
}

function parseProveedor(text: string, rut: string | null): string | null {
  // Patrón principal: "Proveedor: NOMBRE EMPRESA" o "Razón Social: ..."
  const patterns = [
    /Proveedor\s*[:.]?\s*([A-ZÁÉÍÓÚÑ&\s.,'-]+?(?:\s+(?:SPA|S\.A\.|LTDA|EIRL|S\.R\.L\.|LIMITADA|SAC))?)(?=\s+(?:RUT|R\.U\.T|Direcc|Email|Tel|Fono|Sucursal|Contacto|\d))/i,
    /Razón\s+Social\s*[:.]?\s*([A-ZÁÉÍÓÚÑ&\s.,'-]+?)(?=\s+(?:RUT|Direcc|Email|\d))/i,
  ]
  for (const re of patterns) {
    const m = text.match(re)
    if (m) {
      const candidato = m[1].trim().replace(/\s+/g, ' ')
      if (candidato.length >= 3 && candidato.length <= 100) return candidato
    }
  }
  // Fallback: si tenemos RUT, buscar línea con el RUT y agarrar el texto antes
  if (rut) {
    const escapedRut = rut.replace(/[.\-/]/g, '\\$&')
    const re = new RegExp(`([A-ZÁÉÍÓÚÑ&][A-ZÁÉÍÓÚÑ&\\s.,'-]{2,80})\\s+(?:RUT\\s*:?\\s*)?${escapedRut}`, 'i')
    const m = text.match(re)
    if (m) {
      const candidato = m[1].trim().replace(/\s+/g, ' ')
      if (candidato.length >= 3) return candidato
    }
  }
  return null
}

function parseFechas(text: string): { fecha_emision: string | null; fecha_entrega: string | null } {
  // Buscar etiquetas "Fecha emision/entrega" cercanas a dd/mm/yyyy
  const reEmision = /Fecha\s+(?:de\s+)?(?:Emisi[óo]n|Documento|OC)\s*[:.]?\s*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{4})/i
  const reEntrega = /Fecha\s+(?:de\s+)?Entrega(?:\s+Esperada)?\s*[:.]?\s*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{4})/i

  const me = text.match(reEmision)
  const ma = text.match(reEntrega)

  let fecha_emision = me ? parseFechaCL(me[1]) : null
  let fecha_entrega = ma ? parseFechaCL(ma[1]) : null

  // Fallback: si no hay labels, usar las dos primeras fechas dd/mm/yyyy del documento
  if (!fecha_emision || !fecha_entrega) {
    const fechas = Array.from(text.matchAll(/(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{4})/g)).map((m) => m[1])
    if (!fecha_emision && fechas[0]) fecha_emision = parseFechaCL(fechas[0])
    if (!fecha_entrega && fechas[1]) fecha_entrega = parseFechaCL(fechas[1])
  }
  return { fecha_emision, fecha_entrega }
}

function parseMonto(text: string, re: RegExp): number | null {
  const m = text.match(re)
  if (!m) return null
  return parseNumeroCLP(m[1])
}

function parseFormaPago(text: string): string | null {
  const patterns = [
    /Forma\s+(?:de\s+)?Pago\s*[:.]?\s*([^\n,;]{2,40})/i,
    /Condiciones?\s+(?:de\s+)?Pago\s*[:.]?\s*([^\n,;]{2,40})/i,
    /\b(\d{1,3}\s*d[ií]as)\b/i,
  ]
  for (const re of patterns) {
    const m = text.match(re)
    if (m) return m[1].trim()
  }
  return null
}

// ── Parser de items ─────────────────────────────────────────────────────────
// Estrategia: detectar la sección de tabla y parsear línea por línea con un
// regex tolerante. Línea típica Pillado:
//   "1   SERSEGCER006   SERVICIO CERTIFICACION OPERATIVIDAD   CC-15-15   1   UN   290.700   290.700"
//
// Heurística: una línea de item suele contener:
//   - un código alfanumérico ([A-Z0-9]{4,})
//   - una descripción
//   - una unidad (1-4 letras mayúsculas)
//   - dos números (cantidad, precio o precio, total)

function parseItems(text: string, _w: string[]): ParsedOCItem[] {
  const lines = text.split('\n').map((l) => l.trim()).filter((l) => l.length > 0)
  const items: ParsedOCItem[] = []

  // Marcadores de inicio/fin de tabla
  const startIdx = lines.findIndex((l) =>
    /^\s*(?:Item|Art[íi]culo|N[°º]\s*Item|Detalle|Descripci[óo]n)\b/i.test(l) &&
    /(?:Cant\.?|Cantidad|Unidad|UM|Precio|Valor)/i.test(l)
  )
  const endIdx = lines.findIndex((l, i) =>
    i > Math.max(startIdx, 0) &&
    /^\s*(?:Neto|Sub\s*Total|Subtotal|Total\s+(?:Neto|Bruto|OC|Documento))\b/i.test(l)
  )

  const tabla = lines.slice(
    startIdx >= 0 ? startIdx + 1 : 0,
    endIdx >= 0 ? endIdx : lines.length,
  )

  for (const raw of tabla) {
    const item = parseItemLine(raw)
    if (item) items.push(item)
  }
  return items
}

function parseItemLine(line: string): ParsedOCItem | null {
  // Saltar líneas muy cortas o que parezcan totales / headers repetidos
  if (line.length < 10) return null
  if (/^(?:Neto|Sub\s*Total|IVA|Total|Subtotal|Bruto|Item\b|N[°º])\b/i.test(line)) return null

  // Tokens
  const tokens = line.split(/\s{2,}|\t+/g).map((t) => t.trim()).filter(Boolean)
  // Si el split por espacios múltiples deja muy pocas columnas, intentar split simple respetando palabras múltiples de descripción.

  // Patrón estricto Pillado: "<numItem?> <codigo> <descripcion...> <CC>? <cantidad> <unidad> <precio> <total>"
  const reStrict = /^(?:(\d+)\s+)?([A-Z0-9][A-Z0-9._-]{2,})\s+(.+?)\s+(?:(CC-?\w[\w-]*)\s+)?([\d.,]+)\s+([A-Z]{1,4})\s+([\d.,]+)\s+([\d.,]+)\s*$/i
  const ms = line.match(reStrict)
  if (ms) {
    const codigo = ms[2]
    const descripcion = ms[3].trim()
    const cc = ms[4] ?? null
    const cantidad = parseNumeroCLP(ms[5]) ?? 0
    const unidad = ms[6]
    const precio = parseNumeroCLP(ms[7])
    const total = parseNumeroCLP(ms[8])
    if (cantidad > 0 && precio != null) {
      const { tipo, requiereStock } = classifyItem(descripcion, unidad)
      return {
        codigo_externo: codigo,
        descripcion,
        cantidad,
        unidad_externa: unidad,
        centro_costo_codigo_externo: cc,
        precio_unitario_clp: precio,
        total_linea_clp: total,
        tipo_item_sugerido: tipo,
        requiere_stock_sugerido: requiereStock,
        confidence: 0.85,
      }
    }
  }

  // Patrón flexible: línea con al menos un código alfanumérico + 2 montos al final + 1 unidad
  const reFlex = /(?:^|\s)([A-Z0-9][A-Z0-9._-]{3,})\s+(.+?)\s+([\d.,]+)\s+([A-Z]{1,4})\s+([\d.,]+)\s+([\d.,]+)\s*$/i
  const mf = line.match(reFlex)
  if (mf) {
    const codigo = mf[1]
    const descripcion = mf[2].trim()
    const cantidad = parseNumeroCLP(mf[3]) ?? 0
    const unidad = mf[4]
    const precio = parseNumeroCLP(mf[5])
    const total = parseNumeroCLP(mf[6])
    if (cantidad > 0 && precio != null) {
      const { tipo, requiereStock } = classifyItem(descripcion, unidad)
      return {
        codigo_externo: codigo,
        descripcion,
        cantidad,
        unidad_externa: unidad,
        centro_costo_codigo_externo: null,
        precio_unitario_clp: precio,
        total_linea_clp: total,
        tipo_item_sugerido: tipo,
        requiere_stock_sugerido: requiereStock,
        confidence: 0.6,
      }
    }
  }

  return null
}
