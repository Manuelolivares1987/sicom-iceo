// ============================================================================
// Leer un papel: qué dice, con la frase exacta que lo dice
// ----------------------------------------------------------------------------
// Este módulo existe separado del script que lo usa por una razón concreta: la
// primera versión del lector vivía dentro del script de auditoría y no se podía
// probar. Se le encontraron tres fallas en cadena —cada una descubierta por
// casualidad al mirar un resultado raro— y ninguna habría llegado a producción
// si hubiera existido un test.
//
// Las tres, para que no vuelvan:
//
//   1. Unía los trozos de texto en el orden en que vienen dentro del PDF, que
//      no es el orden de lectura. «Fecha de vencimiento» quedaba a decenas de
//      trozos de su fecha. 24 hermeticidades pasaron dos años mal cargadas.
//   2. Confundía la tabla de cuotas de una póliza con su vigencia: la columna
//      «Vencimiento» de un pagaré dio 5 seguros vencidos en 2014.
//   3. Buscaba la palabra «vencimiento». El SOAP no la usa: pone «RIGE DESDE |
//      HASTA» como cabecera y las dos fechas en la fila de abajo.
//
// El módulo NO decide qué hacer con lo que lee. Sólo reporta, con evidencia.
// ============================================================================

// ── Fechas ──────────────────────────────────────────────────────────────────

const MESES = {
  enero: 1, febrero: 2, marzo: 3, abril: 4, mayo: 5, junio: 6, julio: 7,
  agosto: 8, septiembre: 9, setiembre: 9, octubre: 10, noviembre: 11, diciembre: 12,
}
const sinTilde = (s) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
const iso = (d, m, a) => `${a}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`

const plausible = (d, m, a) => d >= 1 && d <= 31 && m >= 1 && m <= 12 && a >= 1990 && a <= 2100

/**
 * Todas las fechas de un texto, en orden de aparición, con la posición donde
 * aparecen. Se devuelven TODAS a propósito: en una fila «01/10/2025 30/09/2026»
 * la que importa es la segunda, y quien llama necesita poder elegir.
 */
export function fechasDe(txt) {
  const out = []
  let m
  // Un sello de firma electrónica lleva la hora pegada: «14/11/2025 10:31:39».
  // Es cuándo se firmó el papel, no hasta cuándo vale. En las revisiones
  // técnicas conviven en la misma línea con la vigencia real y se confunden.
  const conHora = (fin) => /^\s*\d{1,2}\s*:\s*\d{2}/.test(txt.slice(fin))

  const agregar = (o) => {
    // Se descarta lo que caiga DENTRO de una fecha ya reconocida: «29 de junio
    // de 2026» no debe además contarse como «junio 2026».
    if (out.some((p) => o.en < p.fin && o.fin > p.en)) return
    out.push(o)
  }

  // «29 de junio de 2026»
  const reLargo = /(\d{1,2})\s+de\s+([a-zA-ZáéíóúÁÉÍÓÚ]+)\s+de\s+(\d{4})/g
  while ((m = reLargo.exec(txt)) !== null) {
    const mes = MESES[sinTilde(m[2])]
    if (mes && plausible(+m[1], mes, +m[3]))
      agregar({ fecha: iso(+m[1], mes, m[3]), en: m.index, fin: m.index + m[0].length, txt: m[0] })
  }

  // «14 MAYO 2026» — sin los «de». Así viene la revisión técnica.
  const reSinDe = /(\d{1,2})\s+([a-zA-ZáéíóúÁÉÍÓÚ]{4,10})\s+(\d{4})/g
  while ((m = reSinDe.exec(txt)) !== null) {
    const mes = MESES[sinTilde(m[2])]
    if (mes && plausible(+m[1], mes, +m[3]))
      agregar({ fecha: iso(+m[1], mes, m[3]), en: m.index, fin: m.index + m[0].length, txt: m[0] })
  }

  // 2026-06-29 — va ANTES del formato corto: si no, «26-06-29» se lleva el
  // trozo de «2026-06-29» y lo lee como 26 de junio de 2029.
  const reIso = /(\d{4})-(\d{2})-(\d{2})/g
  while ((m = reIso.exec(txt)) !== null) {
    if (plausible(+m[3], +m[2], +m[1]))
      agregar({ fecha: `${m[1]}-${m[2]}-${m[3]}`, en: m.index, fin: m.index + m[0].length, txt: m[0],
                sello: conHora(m.index + m[0].length) })
  }

  // 29/06/2026 · 29-06-2026 · 29.06.2026
  const reCorto = /(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})/g
  while ((m = reCorto.exec(txt)) !== null) {
    const a = m[3].length === 2 ? 2000 + +m[3] : +m[3]
    if (plausible(+m[1], +m[2], a))
      agregar({ fecha: iso(+m[1], +m[2], a), en: m.index, fin: m.index + m[0].length, txt: m[0],
                sello: conHora(m.index + m[0].length) })
  }

  // «SEPTIEMBRE 2026», sin día: vale hasta el último día de ese mes. Es como la
  // revisión técnica chilena declara su vigencia, y es una fecha real, no una
  // suposición: el permiso cubre el mes completo.
  const reMesAnio = /\b([a-zA-ZáéíóúÁÉÍÓÚ]{4,10})\s+(?:de\s+)?(\d{4})\b/g
  while ((m = reMesAnio.exec(txt)) !== null) {
    const mes = MESES[sinTilde(m[1])]
    if (!mes) continue
    const ultimo = new Date(Date.UTC(+m[2], mes, 0)).getUTCDate()
    agregar({ fecha: iso(ultimo, mes, m[2]), en: m.index, fin: m.index + m[0].length, txt: m[0], soloMes: true })
  }

  return out.sort((a, b) => a.en - b.en)
}

/**
 * Las fechas que pueden ser una vigencia: sin los sellos de firma.
 * Si SÓLO hay sellos, se devuelve vacío a propósito. En la revisión técnica del
 * TGGF-56 la vigencia está en el timbre (una imagen) y en el texto sólo queda
 * «04/03/2026 12:55:25», la hora en que se firmó. Reportar eso como vencimiento
 * es peor que decir que no se pudo leer.
 */
const sinSellos = (fs) => fs.filter((f) => !f.sello)

// ── Qué está diciendo cada línea ────────────────────────────────────────────

/** Tabla de cuotas de un pagaré: su «Vencimiento» es cuándo se paga, no hasta
 *  cuándo cubre. Confundirlos dio 5 pólizas «vencidas» en 2014. */
export const ES_PAGO = /(cuota|forma\s+de\s+pago|valor\s+cuota|monto\s+cuota|pagar[eé]|n[°º]\s*cuota|pagado|pendiente\s|dividendo|nro\.?\s*sec|situaci[óo]n\s+valor|prima\s+total)/i

/** La línea dice hasta cuándo vale el documento. */
export const DICE_VENCE = /(fecha\s+de\s+vencimiento|vencimiento|vence\b|v[áa]lid[oa]\s+hasta|validez\s+hasta|vigente\s+hasta|hasta\s+el\b|caduca)/i

/** Cabecera de tabla de vigencia: «RIGE DESDE ... HASTA», «VIGENCIA DESDE/HASTA». */
export const CABECERA_VIGENCIA = /(rige|vigencia|vigente|desde).{0,40}\bhasta\b|\bdesde\b.{0,20}\bhasta\b/i

/** La línea dice cuándo se emitió o se inspeccionó. */
export const DICE_EMISION = /(fecha\s+de\s+(emisi[óo]n|inspecci[óo]n|prueba|otorgamiento)|emitido|expedido|fecha\s+de\s+control)/i

/** El documento declara que no caduca. */
export const DICE_NO_VENCE = /(no\s+tiene\s+vencimiento|sin\s+fecha\s+de\s+vencimiento|sin\s+vencimiento|vigencia\s+indefinida|indefinid[oa]|no\s+caduca)/i

// ── El veredicto ────────────────────────────────────────────────────────────

/**
 * Qué dice este documento sobre su vencimiento. Devuelve uno de tres
 * veredictos y SIEMPRE la frase en que se apoya.
 *
 *   DECLARA      la fecha está escrita → { vencimiento, evidencia, regla }
 *   NO_DECLARA   se leyó completo y no la menciona
 *   ILEGIBLE     no hay texto que leer
 */
/**
 * Papeles de identidad del equipo: no caducan. Buscarles un vencimiento sólo
 * encuentra ruido — en la factura del SVCZ-38 el lector se agarró de la
 * letra chica sobre intereses de mora («hasta su fecha de vencimiento») y
 * reportó 2008 como si el equipo tuviera un papel vencido hace 18 años.
 */
export const TIPO_NO_CADUCA = new Set([
  'factura_compra', 'ficha_tecnica', 'padron', 'inscripcion_rnvm', 'homologacion',
])

export function veredicto(lineas, tipo) {
  if (tipo && TIPO_NO_CADUCA.has(tipo)) {
    return { veredicto: 'NO_CADUCA', motivo: 'Papel de identidad del equipo: no tiene vencimiento.', regla: 'tipo_no_caduca' }
  }
  if (!lineas.length || !lineas.join('').trim()) {
    return { veredicto: 'ILEGIBLE', motivo: 'El PDF no tiene texto: es un escaneo.' }
  }

  // 1) La línea lo dice y trae la fecha.
  for (const l of lineas) {
    if (!DICE_VENCE.test(l) || ES_PAGO.test(l)) continue
    const f = sinSellos(fechasDe(l))
    if (!f.length) continue
    // Si la línea también menciona la emisión, la del vencimiento es la que va
    // después de esa palabra. «Inspección 29-12-2025 Vencimiento 29-06-2026».
    const pos = l.search(DICE_VENCE)
    const post = f.filter((x) => x.en > pos)
    const elegida = (post.length ? post : f)[0]
    return { veredicto: 'DECLARA', vencimiento: elegida.fecha, evidencia: l.trim(), regla: 'linea_lo_dice' }
  }

  // 2) La etiqueta en una línea y la fecha en la siguiente (tabla partida).
  for (let i = 0; i < lineas.length - 1; i++) {
    if (!DICE_VENCE.test(lineas[i]) || ES_PAGO.test(lineas[i])) continue
    if (fechasDe(lineas[i]).length) continue
    for (let j = i + 1; j <= Math.min(i + 3, lineas.length - 1); j++) {
      // La cabecera puede no delatarse («Tipo Nro. Sec. Vencimiento») pero la
      // fila sí: si dice PAGADO o PENDIENTE es un cuadro de cuotas.
      if (ES_PAGO.test(lineas[j])) continue
      const f = sinSellos(fechasDe(lineas[j]))
      if (f.length) return {
        veredicto: 'DECLARA', vencimiento: f[0].fecha,
        evidencia: `${lineas[i].trim()} → ${lineas[j].trim()}`, regla: 'etiqueta_y_fila',
      }
    }
  }

  // 3a) Rango completo en una sola línea: «VIGENCIA: desde X hasta Y».
  //     Va aparte del bucle de abajo a propósito: aquel recorre hasta
  //     `length - 1` porque necesita una línea siguiente, y con eso un
  //     documento de una sola línea nunca se revisaba.
  for (const l of lineas) {
    if (!CABECERA_VIGENCIA.test(l) || ES_PAGO.test(l)) continue
    const f = sinSellos(fechasDe(l))
    if (f.length >= 2) return {
      // La mayor, no la última: en el SOAP del KVWW-68 la columna HASTA quedó
      // impresa antes que DESDE, y «la última» daba el inicio de vigencia.
      // Una vigencia siempre termina después de empezar.
      veredicto: 'DECLARA', vencimiento: f.map((x) => x.fecha).sort().pop(),
      evidencia: l.trim(), regla: 'rango_en_linea',
    }
  }

  // 3b) Cabecera DESDE/HASTA con los títulos arriba y las fechas abajo. La que
  //     vale es la ÚLTIMA de la fila de valores; la primera es cuándo empieza a
  //     regir. Así viene el SOAP.
  for (let i = 0; i < lineas.length - 1; i++) {
    const cab = lineas[i]
    if (!CABECERA_VIGENCIA.test(cab) || ES_PAGO.test(cab)) continue
    if (fechasDe(cab).length) continue
    for (let j = i + 1; j <= Math.min(i + 3, lineas.length - 1); j++) {
      const f = sinSellos(fechasDe(lineas[j]))
      if (f.length >= 2) return {
        veredicto: 'DECLARA', vencimiento: f.map((x) => x.fecha).sort().pop(),
        evidencia: `${cab.trim()} → ${lineas[j].trim()}`, regla: 'cabecera_desde_hasta',
      }
    }
  }

  // 4) El documento dice explícitamente que no caduca.
  for (const l of lineas) {
    // «incapacidad permanente parcial» de un SOAP no es una declaración de
    // vigencia: se exige que la frase hable del documento, no de la cobertura.
    if (!DICE_NO_VENCE.test(l)) continue
    if (/incapacidad|invalidez|lesi[óo]n|da[ñn]o/i.test(l)) continue
    return { veredicto: 'NO_DECLARA', motivo: 'El documento declara que no tiene vencimiento.', evidencia: l.trim(), regla: 'dice_que_no_vence' }
  }

  // 5) Se leyó completo y no lo menciona.
  return {
    veredicto: 'NO_DECLARA',
    motivo: `Se leyeron ${lineas.length} líneas y no aparece una fecha de vencimiento.`,
    regla: 'leido_sin_hallazgo',
  }
}

/** La fecha de emisión / inspección, si el documento la declara. */
export function emisionDeclarada(lineas) {
  for (const l of lineas) {
    if (!DICE_EMISION.test(l) || ES_PAGO.test(l)) continue
    const pos = l.search(DICE_EMISION)
    const f = fechasDe(l).filter((x) => x.en > pos)
    if (f.length) return { fecha: f[0].fecha, evidencia: l.trim() }
  }
  for (let i = 0; i < lineas.length - 1; i++) {
    if (!DICE_EMISION.test(lineas[i]) || fechasDe(lineas[i]).length) continue
    const f = fechasDe(lineas[i + 1])
    if (f.length) return { fecha: f[0].fecha, evidencia: `${lineas[i].trim()} → ${lineas[i + 1].trim()}` }
  }
  return null
}
