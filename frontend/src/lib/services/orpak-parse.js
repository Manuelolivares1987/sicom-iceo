// ============================================================================
// Lector del export de Orpak
// ----------------------------------------------------------------------------
// El archivo que baja de Orpak no es un formato: es una familia de formatos.
// Trae una hoja por estación y los encabezados cambian entre hojas del MISMO
// archivo — «Total Sale» en Bimodal, «Quantity» en Mina, «Volumen» en Camiones;
// «Vehicle Number» aquí, «Equipo» allá. Por eso las columnas se detectan por lo
// que dicen, no por su posición.
//
// Lo que este módulo NO hace, a propósito: no clasifica ni decide a qué
// estanque va cada fila. Eso vive en la base de datos (MIG328), como reglas
// editables, para que corregir una estación nueva no sea recompilar la app.
// Aquí sólo se lee el papel y se transcribe fiel.
// ============================================================================

/** Quita tildes y deja en mayúsculas, para comparar encabezados sin sorpresas. */
function norm(s) {
  return String(s ?? '')
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .trim().toUpperCase()
}

/**
 * Localiza las columnas por su nombre. Devuelve un mapa {campo: índice}.
 * Cada regla es una lista de textos que pueden aparecer en el encabezado.
 */
const COLUMNAS = [
  ['serie',        (h) => h.includes('SER')],
  ['fecha',        (h) => h === 'FECHA' || h.includes('DATE')],
  ['hora',         (h) => h === 'HORA' || h.includes('TIME')],
  ['flota',        (h) => h.includes('FLOTA') || h.includes('FLEET')],
  ['vehiculo',     (h) => h.includes('VEHICULO') || h.includes('VEHICLE') || h.includes('EQUIPO')],
  ['producto',     (h) => h.includes('PRODUCTO') || h.includes('PRODUCT')],
  ['litros',       (h) => h.includes('VENTA') || h.includes('TOTAL SALE') || h === 'QUANTITY' || h.includes('VOLUMEN')],
  ['estacion',     (h) => h.includes('NOMBRE') || h.includes('ESTACION') || (h.includes('STATION') && !h.includes('SHEET'))],
  ['departamento', (h) => h.includes('DEPARTAMENTO') || h.includes('DEPARTMENT')],
  ['tarjeta',      (h) => h.includes('TARJETA') || h.includes('CARD') || h.includes('NUMERO DE')],
  ['autorizado_por', (h) => h.includes('AUTORIZADO') || h.includes('AUTHORIZED') || h.includes('DISPOSITIVO')],
  ['bomba',        (h) => h.includes('BOMBA') || h === 'PUMP'],
  ['dia_cierre',   (h) => h.includes('DIA DE CIERRE') || h.includes('DIA CIERRE')],
]

function detectarColumnas(fila) {
  const ci = {}
  fila.forEach((celda, i) => {
    const h = norm(celda)
    if (!h) return
    for (const [campo, prueba] of COLUMNAS) {
      if (prueba(h)) ci[campo] = i
    }
  })
  return ci
}

/**
 * Excel guarda las fechas en UTC. Leerlas en hora local las corre un día hacia
 * atrás en Chile — el error clásico que hace que una carga del 1 aparezca el 31
 * del mes anterior. Se leen siempre en UTC.
 */
function aFecha(v) {
  if (v == null || v === '') return null
  if (v instanceof Date) {
    const y = v.getUTCFullYear()
    if (y < 2000 || y > 2100) return null
    return `${y}-${String(v.getUTCMonth() + 1).padStart(2, '0')}-${String(v.getUTCDate()).padStart(2, '0')}`
  }
  if (typeof v === 'number') {
    const d = new Date(Math.round((v - 25569) * 86400 * 1000))
    return aFecha(d)
  }
  const s = String(v).trim()
  // DD-MM-YY / DD/MM/YYYY
  const m = s.match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{2,4})$/)
  if (m) {
    const yy = m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3])
    return `${yy}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`
  }
  // YYYY-MM-DD
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10)
  return null
}

/** La hora viene como Date anclado a 1899. Sólo interesa HH:MM. */
function aHora(v) {
  if (v == null || v === '') return null
  if (v instanceof Date) {
    return `${String(v.getUTCHours()).padStart(2, '0')}:${String(v.getUTCMinutes()).padStart(2, '0')}`
  }
  if (typeof v === 'number') {
    const min = Math.round(v * 24 * 60)
    return `${String(Math.floor(min / 60) % 24).padStart(2, '0')}:${String(min % 60).padStart(2, '0')}`
  }
  const m = String(v).match(/(\d{1,2}):(\d{2})/)
  return m ? `${m[1].padStart(2, '0')}:${m[2]}` : null
}

/**
 * Convierte a numero un valor que puede venir como numero o como texto.
 *
 * OJO, ESTO NO ES TRIVIAL Y AQUI SE PERDIA UN ORDEN DE MAGNITUD.
 * En el mismo archivo conviven las dos convenciones: la hoja MINA trae los
 * litros como numero, y la hoja CAMIONES los trae como TEXTO con punto
 * DECIMAL — «405.9» son 405,9 litros. Tratar ese punto como separador de
 * miles convierte 405,9 en 4.059 y multiplica por diez todo lo que despacha
 * un camion. En junio 2026 eso inflaba la hoja de camiones de 43.000 a
 * 810.000 litros, contra 125.789 litros de trasvasije recibido: un camion
 * entregando seis veces mas de lo que carga.
 *
 * La regla: si aparecen los dos separadores, el ultimo es el decimal. Si
 * aparece uno solo, es decimal salvo que venga seguido de exactamente tres
 * digitos, en cuyo caso se lee como agrupador de miles — «1.234» son mil
 * doscientos treinta y cuatro litros, no uno coma dos. Ese es el unico caso
 * genuinamente ambiguo y se cuenta aparte para que alguien lo mire.
 */
function aNumero(v) {
  if (v == null || v === '') return null
  if (typeof v === 'number') return Number.isFinite(v) ? v : null

  let s = String(v).trim().replace(/\s/g, '').replace(/(lt|lts|l)$/i, '')
  if (!s || !/[0-9]/.test(s)) return null

  const puntos = (s.match(/\./g) || []).length
  const comas = (s.match(/,/g) || []).length
  let ambiguo = false
  let decimal = null

  if (puntos > 0 && comas > 0) {
    decimal = s.lastIndexOf('.') > s.lastIndexOf(',') ? '.' : ','
  } else if (comas === 1) {
    if (/,\d{3}$/.test(s)) ambiguo = true
    else decimal = ','
  } else if (puntos === 1) {
    if (/\.\d{3}$/.test(s)) ambiguo = true
    else decimal = '.'
  }

  if (decimal === '.') s = s.replace(/,/g, '')
  else if (decimal === ',') s = s.replace(/\./g, '').replace(',', '.')
  else s = s.replace(/[.,]/g, '')

  const n = parseFloat(s)
  if (!Number.isFinite(n)) return null
  return ambiguo ? { valor: n, ambiguo: true } : n
}

/** Desenvuelve el resultado de aNumero, que puede venir marcado como ambiguo. */
function numero(x) {
  return x != null && typeof x === 'object' ? x.valor : x
}

/** ExcelJS devuelve objetos para celdas con fórmula, hipervínculo o texto rico. */
function valor(c) {
  if (c == null) return null
  if (typeof c === 'object') {
    if (c instanceof Date) return c
    if ('result' in c) return c.result
    if ('text' in c) return c.text
    if ('richText' in c) return c.richText.map((r) => r.text).join('')
    return null
  }
  return c
}

/**
 * Lee un libro de ExcelJS y devuelve las filas listas para `rpc_comb_orpak_cargar`.
 * @param {import('exceljs').Workbook} wb
 * @returns {{filas: any[], hojas: {hoja: string, leidas: number, sinColumnas: boolean}[], ambiguos: number}}
 */
export function leerOrpak(wb) {
  const filas = []
  const hojas = []
  let ambiguos = 0

  for (const ws of wb.worksheets) {
    // La fila de encabezados no siempre es la primera: algunos exports traen
    // un título o una fila en blanco arriba. Se busca en las primeras cinco.
    let ci = null
    let filaHdr = 0
    for (let r = 1; r <= Math.min(5, ws.rowCount); r++) {
      const vals = ws.getRow(r).values.map(valor)
      const cand = detectarColumnas(vals)
      if (cand.fecha != null && cand.litros != null && cand.vehiculo != null) {
        ci = cand
        filaHdr = r
        break
      }
    }
    if (!ci) {
      hojas.push({ hoja: ws.name, leidas: 0, sinColumnas: true })
      continue
    }

    let leidas = 0
    ws.eachRow((row, r) => {
      if (r <= filaHdr) return
      const v = row.values.map(valor)
      const bruto = aNumero(v[ci.litros])
      const litros = numero(bruto)
      if (bruto != null && typeof bruto === 'object') ambiguos++
      const fecha = aFecha(v[ci.fecha])
      // Una hoja de Excel siempre tiene cola: filas de totales, celdas
      // sueltas, restos. Sin fecha o sin litros no es una transacción.
      if (fecha == null || litros == null || litros === 0) return

      leidas++
      filas.push({
        hoja: ws.name,
        serie: ci.serie != null ? String(valor(v[ci.serie]) ?? '') : null,
        fecha,
        hora: ci.hora != null ? aHora(v[ci.hora]) : null,
        flota: ci.flota != null ? String(v[ci.flota] ?? '').trim() : null,
        vehiculo: String(v[ci.vehiculo] ?? '').trim(),
        producto: ci.producto != null ? String(v[ci.producto] ?? '').trim() : null,
        litros,
        estacion: ci.estacion != null ? String(v[ci.estacion] ?? '').trim() : ws.name,
        departamento: ci.departamento != null ? String(v[ci.departamento] ?? '').trim() : null,
        tarjeta: ci.tarjeta != null ? String(v[ci.tarjeta] ?? '').trim() : null,
        autorizado_por: ci.autorizado_por != null ? String(v[ci.autorizado_por] ?? '').trim() : null,
        bomba: ci.bomba != null && v[ci.bomba] != null ? String(v[ci.bomba]).trim() : null,
        dia_cierre: ci.dia_cierre != null ? aFecha(v[ci.dia_cierre]) : null,
      })
    })

    hojas.push({ hoja: ws.name, leidas, sinColumnas: false })
  }

  return { filas, hojas, ambiguos }
}

export const _internas = { norm, aFecha, aHora, aNumero, numero, detectarColumnas }
