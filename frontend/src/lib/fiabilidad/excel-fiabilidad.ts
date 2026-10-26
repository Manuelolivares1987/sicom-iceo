// Excel de fiabilidad por patente: el consolidado del período (una hoja) y el
// mes a mes (resumen de flota + una tabla por indicador con los meses en
// columnas + el detalle completo con una fila por patente y mes).
//
// El cálculo es UNO solo para la pantalla y los dos archivos: si el mes a mes
// sumara distinto que el consolidado, nadie confiaría en ninguno de los dos.

import type { Worksheet } from 'exceljs'
import {
  getDetalleFiabilidadFlota,
  type ActivoFiabilidadDetalle,
  type EstadoDiaCelda,
} from '@/lib/services/fiabilidad'

export const ESTADO_ORDEN = ['A', 'C', 'L', 'U', 'D', 'H', 'R', 'M', 'T', 'F', 'V', 'S']
export const ESTADO_LABELS: Record<string, string> = {
  A: 'Arrendado', C: 'En contrato', D: 'Disponible', H: 'Habilitación', R: 'Recepción',
  M: 'Mantención', T: 'Taller', F: 'Fuera de servicio', V: 'Venta',
  U: 'Uso interno', L: 'Leasing',
  // 'S' está fuera del cálculo de disponibilidad (MIG306), pero se sigue
  // dibujando: el equipo existe y hay que poder verlo en la matriz.
  S: 'Siniestrado / fuera de control',
}
const DOWN_LETRAS = new Set(['M', 'T', 'F', 'R', 'H'])
const MESES = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic']

export type DetalleCalc = ActivoFiabilidadDetalle & {
  dias_c: number
  utilizacion: number
  fallas_taller: number
  reincidencias: number
  calidad_taller: number
  oee: number
}

/**
 * Utilización, calidad del trabajo y OEE por equipo. La matriz se restringe a
 * los equipos del detalle (vehículos de flota).
 */
export function calcularIndicadores(
  detalles: ActivoFiabilidadDetalle[],
  matriz: EstadoDiaCelda[],
): DetalleCalc[] {
  const ids = new Set(detalles.map((d) => d.activo_id))

  // Días en estado 'C' (en contrato) por activo — no viene en el detalle (OEE),
  // se cuenta desde la matriz. Cuenta como utilización (A + L + C).
  const diasC = new Map<string, number>()
  // ── Calidad del trabajo (taller): penaliza FALLAS REPETIDAS en el mismo mes ──
  // Una "falla" = un episodio (racha de días consecutivos) en estado M/T/F. Si en
  // un mismo mes calendario hay 2+ episodios, los extra son "reincidencias" y
  // bajan la nota. Calidad = fallas_primarias ÷ fallas_totales (1 si no hay fallas).
  const downByActivo = new Map<string, string[]>()
  for (const c of matriz) {
    if (!ids.has(c.activo_id)) continue
    if (c.estado_codigo === 'C') diasC.set(c.activo_id, (diasC.get(c.activo_id) ?? 0) + 1)
    if (c.estado_codigo === 'M' || c.estado_codigo === 'T' || c.estado_codigo === 'F') {
      const arr = downByActivo.get(c.activo_id) ?? []
      arr.push(c.fecha.slice(0, 10))
      downByActivo.set(c.activo_id, arr)
    }
  }
  const taller = new Map<string, { fallas: number; reincidencias: number; calidad: number }>()
  downByActivo.forEach((raw, id) => {
    const fechas = Array.from(new Set(raw)).sort()
    const porMes: Record<string, number> = {}
    let prev: number | null = null
    for (const f of fechas) {
      const t = new Date(f).getTime()
      if (prev === null || t - prev > 86400000) porMes[f.slice(0, 7)] = (porMes[f.slice(0, 7)] ?? 0) + 1 // nuevo episodio
      prev = t
    }
    const fallas = Object.values(porMes).reduce((a, b) => a + b, 0)
    const primarias = Object.keys(porMes).length // meses con al menos una falla
    taller.set(id, { fallas, reincidencias: fallas - primarias, calidad: fallas > 0 ? primarias / fallas : 1 })
  })

  // OEE (único, lente del taller) = Disp. Técnica × Calidad del trabajo.
  // La Utilización (A+L+C) es comercial → se muestra aparte, NO entra al OEE.
  return detalles.map((d) => {
    const c = diasC.get(d.activo_id) ?? 0
    const dispFis = Number(d.disponibilidad_fisica ?? 0) // UP / Total (servidor, nueva def)
    const util = d.dias_observados > 0 ? (d.dias_a + d.dias_l + c) / d.dias_observados : 0
    const t = taller.get(d.activo_id)
    const calidadTaller = t?.calidad ?? 1
    return {
      ...d, dias_c: c, utilizacion: util,
      fallas_taller: t?.fallas ?? 0,
      reincidencias: t?.reincidencias ?? 0,
      calidad_taller: calidadTaller,
      oee: dispFis * calidadTaller,
    }
  })
}

/** Estado del último día de la matriz, por activo. */
export function estadoUltimoDia(matriz: EstadoDiaCelda[], ids: Set<string>): Map<string, string> {
  const m = new Map<string, string>()
  let ultimo = ''
  for (const c of matriz) if (c.fecha > ultimo) ultimo = c.fecha
  for (const c of matriz) if (c.fecha === ultimo && ids.has(c.activo_id)) m.set(c.activo_id, c.estado_codigo)
  return m
}

// ── Hoja "Equipos": toda la info por patente ────────────────────────────────
function columnasEquipos() {
  return [
    { header: 'Patente', key: 'patente', width: 12 },
    { header: 'Equipamiento', key: 'equipamiento', width: 28 },
    { header: 'Categoría', key: 'categoria_uso', width: 18 },
    { header: 'Marca', key: 'marca', width: 14 },
    { header: 'Modelo', key: 'modelo', width: 18 },
    { header: 'Año', key: 'anio_fabricacion', width: 8 },
    { header: 'Capacidad', key: 'capacidad', width: 16 },
    { header: 'Potencia', key: 'potencia', width: 12 },
    { header: 'VIN / Chasis', key: 'vin_chasis', width: 22 },
    { header: 'N° Motor', key: 'numero_motor', width: 18 },
    { header: 'Estado del día', key: 'estado_dia', width: 20 },
    { header: 'Zona', key: 'zona', width: 16 },
    // [MIG650] Ubicación = lo que fijó el planificador en Sugerencias GPS; el GPS
    // queda como referencia (TRDP-97 salía «Spence» estando en Sierra Gorda).
    { header: 'Ubicación (planificador)', key: 'ubicacion', width: 30 },
    { header: 'GPS (referencia)', key: 'ubicacion_gps', width: 34 },
    { header: '¿GPS coincide?', key: 'ubicacion_revisar', width: 16 },
    { header: 'Último contrato', key: 'contrato_codigo', width: 18 },
    { header: 'Cliente contrato', key: 'contrato_cliente', width: 26 },
    { header: 'Cliente actual', key: 'cliente_actual', width: 24 },
    { header: 'Días arriendo (total)', key: 'dias_arriendo_total', width: 16 },
    { header: 'Días por contrato', key: 'contratos_dias_txt', width: 44 },
    { header: 'Últ. arriendo cliente', key: 'ult_cliente', width: 22 },
    { header: 'Últ. arriendo lugar', key: 'ult_lugar', width: 20 },
    { header: 'Días observados', key: 'dias_observados', width: 14 },
    { header: 'Días UP', key: 'dias_up', width: 9 }, { header: 'Días DOWN', key: 'dias_down', width: 10 },
    // Desglose de días por estado (todas las letras), calculado desde la matriz.
    ...ESTADO_ORDEN.map((s) => ({ header: `${s} — ${ESTADO_LABELS[s]}`, key: `dias_${s.toLowerCase()}`, width: 14 })),
    { header: 'Total letras (=Días obs)', key: 'dias_letras_total', width: 18 },
    { header: 'Cuadre (letras = días obs)', key: 'cuadre', width: 18 },
    { header: 'N° Fallas', key: 'eventos_falla', width: 10 },
    { header: 'MTBF (d)', key: 'mtbf_dias', width: 10 }, { header: 'MTTR (d)', key: 'mttr_dias', width: 10 },
    { header: 'Disp. inherente %', key: 'disp_inh', width: 15 },
    { header: 'Disp. física %', key: 'disp_fis', width: 14 },
    { header: 'Utilización (A+L+C) %', key: 'util_pct', width: 18 },
    { header: 'Fallas repetidas (mes)', key: 'reincidencias', width: 18 },
    { header: 'Calidad del trabajo %', key: 'cal_taller_pct', width: 18 },
    { header: 'OEE %', key: 'oee_pct', width: 10 },
  ]
}

function cuentaLetras(matriz: EstadoDiaCelda[]): Map<string, Record<string, number>> {
  const m = new Map<string, Record<string, number>>()
  for (const c of matriz) {
    const r = m.get(c.activo_id) ?? {}
    r[c.estado_codigo] = (r[c.estado_codigo] ?? 0) + 1
    m.set(c.activo_id, r)
  }
  return m
}

// Días por letra desde la matriz diaria (incluye todas las letras: A..V).
// UP = A,C,L,U,D,V ; DOWN = M,T,F,R,H (down operacional, incluye recepción
// y habilitación). Suma de letras = días observados.
function filaEquipo(e: DetalleCalc, cuenta: Record<string, number>, code: string | undefined) {
  const porLetra = Object.fromEntries(ESTADO_ORDEN.map((s) => [`dias_${s.toLowerCase()}`, cuenta[s] ?? 0]))
  const upCalc = ESTADO_ORDEN.reduce((a, s) => a + (DOWN_LETRAS.has(s) ? 0 : (cuenta[s] ?? 0)), 0)
  const downCalc = ESTADO_ORDEN.reduce((a, s) => a + (DOWN_LETRAS.has(s) ? (cuenta[s] ?? 0) : 0), 0)
  const totalLetras = upCalc + downCalc
  return {
    ...e,
    ...porLetra,
    dias_up: upCalc,
    dias_down: downCalc,
    dias_letras_total: totalLetras,
    cuadre: totalLetras === Number(e.dias_observados) ? 'OK' : `≠ (${totalLetras}/${e.dias_observados})`,
    estado_dia: code ? `${code} — ${ESTADO_LABELS[code] ?? code}` : '—',
    ubicacion_revisar: e.ubicacion_coincide === false ? 'NO — revisar' : e.ubicacion_coincide ? 'Sí' : 'Sin GPS en geocerca',
    contratos_dias_txt: (e.contratos_dias ?? []).map((c) => `${c.codigo}: ${c.dias} d`).join('; '),
    disp_inh: Math.round(Number(e.disponibilidad_inherente) * 100),
    disp_fis: Math.round(Number(e.disponibilidad_fisica) * 100),
    util_pct: e.utilizacion != null ? Math.round(e.utilizacion * 100) : '',
    reincidencias: e.reincidencias ?? 0,
    cal_taller_pct: e.calidad_taller != null ? Math.round(e.calidad_taller * 100) : '',
    oee_pct: e.oee != null ? Math.round(e.oee * 100) : '',
  }
}

function encabezado(ws: Worksheet) {
  ws.getRow(1).font = { bold: true, color: { argb: 'FFFFFFFF' } }
  ws.getRow(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF1E3A8A' } }
  ws.autoFilter = { from: 'A1', to: { row: 1, column: ws.columnCount } }
  ws.views = [{ state: 'frozen', ySplit: 1 }]
}

async function bajar(wb: { xlsx: { writeBuffer(): Promise<ArrayBuffer> } }, nombre: string) {
  const buf = await wb.xlsx.writeBuffer()
  const blob = new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = nombre
  a.click()
  setTimeout(() => URL.revokeObjectURL(url), 10_000)
}

/** Consolidado del período: una fila por patente. */
export async function exportarExcelConsolidado(
  rows: DetalleCalc[], matriz: EstadoDiaCelda[], fechaInicio: string, fechaFin: string,
) {
  const ExcelJS = (await import('exceljs')).default
  const wb = new ExcelJS.Workbook()
  const ws = wb.addWorksheet('Equipos')
  ws.columns = columnasEquipos()
  const cuenta = cuentaLetras(matriz)
  const estado = estadoUltimoDia(matriz, new Set(rows.map((r) => r.activo_id)))
  for (const e of rows) ws.addRow(filaEquipo(e, cuenta.get(e.activo_id) ?? {}, estado.get(e.activo_id)))
  encabezado(ws)
  await bajar(wb, `fiabilidad_equipos_${fechaInicio}_a_${fechaFin}.xlsx`)
}

/** Meses calendario dentro del rango, recortados a sus bordes. */
export function mesesDelRango(fechaInicio: string, fechaFin: string) {
  const out: { clave: string; etiqueta: string; ini: string; fin: string }[] = []
  let y = Number(fechaInicio.slice(0, 4)), m = Number(fechaInicio.slice(5, 7))
  for (;;) {
    const clave = `${y}-${String(m).padStart(2, '0')}`
    if (clave > fechaFin.slice(0, 7)) break
    const ultimoDia = new Date(Date.UTC(y, m, 0)).getUTCDate()
    const ini = clave === fechaInicio.slice(0, 7) ? fechaInicio : `${clave}-01`
    const finMes = `${clave}-${String(ultimoDia).padStart(2, '0')}`
    out.push({ clave, etiqueta: `${MESES[m - 1]} ${y}`, ini, fin: finMes < fechaFin ? finMes : fechaFin })
    if (++m > 12) { m = 1; y++ }
  }
  return out
}

/**
 * Mes a mes. `consolidado` son las filas que el usuario ve en pantalla (ya
 * filtradas): fija qué patentes salen y da la columna «Período» de cada tabla,
 * que es exactamente el número del Excel consolidado.
 */
export async function exportarExcelMensual(p: {
  consolidado: DetalleCalc[]
  matriz: EstadoDiaCelda[]                 // la del rango completo (ya está cargada)
  fechaInicio: string
  fechaFin: string
  onProgreso?: (hechos: number, total: number) => void
}) {
  const { consolidado, matriz, fechaInicio, fechaFin, onProgreso } = p
  const meses = mesesDelRango(fechaInicio, fechaFin)
  const ids = new Set(consolidado.map((r) => r.activo_id))

  // El detalle (MTBF, disponibilidad, fallas) lo calcula el servidor por
  // rango: una consulta por mes, de a una para no saturar la base (NANO).
  const porMes: { mes: (typeof meses)[number]; filas: DetalleCalc[]; matriz: EstadoDiaCelda[] }[] = []
  for (let i = 0; i < meses.length; i++) {
    const mes = meses[i]
    onProgreso?.(i, meses.length)
    const { data, error } = await getDetalleFiabilidadFlota(mes.ini, mes.fin)
    if (error) throw new Error(`No se pudo calcular ${mes.etiqueta}: ${(error as Error).message ?? error}`)
    const mMes = matriz.filter((c) => c.fecha >= mes.ini && c.fecha <= mes.fin)
    porMes.push({ mes, matriz: mMes, filas: calcularIndicadores(data.filter((d) => ids.has(d.activo_id)), mMes) })
  }
  onProgreso?.(meses.length, meses.length)

  const ExcelJS = (await import('exceljs')).default
  const wb = new ExcelJS.Workbook()

  // 1) Resumen de la flota, una fila por mes (+ el período completo al final).
  const res = wb.addWorksheet('Resumen mensual')
  res.columns = [
    { header: 'Mes', key: 'mes', width: 12 },
    { header: 'Equipos', key: 'equipos', width: 9 },
    { header: 'Días observados', key: 'dias', width: 14 },
    { header: 'Días UP', key: 'up', width: 9 },
    { header: 'Días DOWN', key: 'down', width: 10 },
    { header: 'Disp. física %', key: 'disp', width: 13 },
    { header: 'Utilización (A+L+C) %', key: 'util', width: 18 },
    { header: 'N° Fallas', key: 'fallas', width: 10 },
    { header: 'MTBF flota (d)', key: 'mtbf', width: 13 },
    { header: 'MTTR flota (d)', key: 'mttr', width: 13 },
    { header: 'Fallas repetidas', key: 'reinc', width: 14 },
    { header: 'OEE % (prom. equipos)', key: 'oee', width: 18 },
    ...ESTADO_ORDEN.map((s) => ({ header: `${s} — ${ESTADO_LABELS[s]}`, key: `l_${s}`, width: 13 })),
  ]
  const resumen = (etiqueta: string, filas: DetalleCalc[], mz: EstadoDiaCelda[]) => {
    const conDias = filas.filter((d) => d.dias_observados > 0)
    const dias = conDias.reduce((s, d) => s + d.dias_observados, 0)
    const up = conDias.reduce((s, d) => s + d.dias_up, 0)
    const mt = conDias.reduce((s, d) => s + d.dias_m + d.dias_t, 0)   // reparación con HH (para MTTR)
    const util = conDias.reduce((s, d) => s + d.dias_a + d.dias_l + d.dias_c, 0)
    const fallas = conDias.reduce((s, d) => s + d.eventos_falla, 0)
    const letras: Record<string, number> = {}
    for (const c of mz) if (ids.has(c.activo_id)) letras[c.estado_codigo] = (letras[c.estado_codigo] ?? 0) + 1
    res.addRow({
      mes: etiqueta, equipos: conDias.length, dias, up, down: dias - up,
      disp: dias > 0 ? Math.round((up / dias) * 1000) / 10 : '',
      util: dias > 0 ? Math.round((util / dias) * 1000) / 10 : '',
      fallas,
      mtbf: Math.round((fallas > 0 ? up / fallas : up) * 10) / 10,
      mttr: Math.round((fallas > 0 ? mt / fallas : 0) * 10) / 10,
      reinc: conDias.reduce((s, d) => s + d.reincidencias, 0),
      oee: conDias.length ? Math.round((conDias.reduce((s, d) => s + d.oee, 0) / conDias.length) * 1000) / 10 : '',
      ...Object.fromEntries(ESTADO_ORDEN.map((s) => [`l_${s}`, letras[s] ?? 0])),
    })
  }
  for (const x of porMes) resumen(x.mes.etiqueta, x.filas, x.matriz)
  resumen('Período', consolidado, matriz)
  encabezado(res)
  res.getRow(res.rowCount).font = { bold: true }

  // 2) Una tabla por indicador: patente × mes. Vacío = el equipo no tuvo días
  //    observados ese mes (no es un cero).
  const pct = (v: number) => Math.round(v * 1000) / 10
  const indicadores: { hoja: string; valor: (d: DetalleCalc) => number }[] = [
    { hoja: 'Disp. física %', valor: (d) => pct(Number(d.disponibilidad_fisica ?? 0)) },
    { hoja: 'Utilización %', valor: (d) => pct(d.utilizacion) },
    { hoja: 'OEE %', valor: (d) => pct(d.oee) },
    { hoja: 'Días DOWN', valor: (d) => d.dias_down },
    { hoja: 'N° Fallas', valor: (d) => d.eventos_falla },
  ]
  const idx = porMes.map((x) => new Map(x.filas.map((f) => [f.activo_id, f])))
  for (const ind of indicadores) {
    const ws = wb.addWorksheet(ind.hoja)
    ws.columns = [
      { header: 'Patente', key: 'patente', width: 12 },
      { header: 'Equipamiento', key: 'equipamiento', width: 28 },
      { header: 'Categoría', key: 'categoria_uso', width: 18 },
      ...porMes.map((x) => ({ header: x.mes.etiqueta, key: x.mes.clave, width: 10 })),
      { header: 'Período', key: 'periodo', width: 10 },
    ]
    for (const e of consolidado) {
      const fila: Record<string, unknown> = {
        patente: e.patente, equipamiento: e.equipamiento, categoria_uso: e.categoria_uso,
        periodo: e.dias_observados > 0 ? ind.valor(e) : '',
      }
      porMes.forEach((x, i) => {
        const d = idx[i].get(e.activo_id)
        fila[x.mes.clave] = d && d.dias_observados > 0 ? ind.valor(d) : ''
      })
      ws.addRow(fila)
    }
    encabezado(ws)
    ws.getColumn('periodo').font = { bold: true }
  }

  // 3) Detalle completo: las mismas columnas del consolidado + el mes, una
  //    fila por patente y mes. Sirve para filtrar o armar tablas dinámicas.
  const det = wb.addWorksheet('Detalle mensual')
  det.columns = [{ header: 'Mes', key: 'mes_etq', width: 10 }, ...columnasEquipos()]
  for (const x of porMes) {
    const cuenta = cuentaLetras(x.matriz)
    const estado = estadoUltimoDia(x.matriz, ids)
    for (const e of x.filas) {
      det.addRow({ mes_etq: x.mes.etiqueta, ...filaEquipo(e, cuenta.get(e.activo_id) ?? {}, estado.get(e.activo_id)) })
    }
  }
  encabezado(det)

  await bajar(wb, `fiabilidad_mensual_${fechaInicio}_a_${fechaFin}.xlsx`)
}
