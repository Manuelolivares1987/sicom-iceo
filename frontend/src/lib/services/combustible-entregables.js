// ============================================================================
// Los tres entregables del cierre (MIG333)
// ----------------------------------------------------------------------------
// El cierre no termina cuando cuadra: termina cuando salen tres documentos que
// hoy se llenan a mano, celda por celda, desde datos que el sistema ya tiene.
//
//   CIERRE ROMERAL   una hoja por día con las mediciones físicas y los
//                    numerales, más una hoja por estación con el mes
//   FORM AC 066      el stock de cada estanque día por día, con el KPI de
//                    llenado
//   BBDD             la lista plana de transacciones con la Semana ENAP
//
// Esa doble digitación no es sólo lenta: es el origen de la mitad de los
// hallazgos. La hoja de Casa Fuerza se abandonó el día 2 del mes porque nadie
// alcanza a tipear cuatro veces lo mismo. Lo que no se tipea no existe, y lo
// que se tipea dos veces se contradice.
//
// Los encabezados y el orden de las columnas replican las planillas que ya
// usan. No es nostalgia: quien las recibe las lee a la misma altura de
// siempre, y un formato nuevo obliga a explicar el cambio antes de poder
// hablar de los números.
// ============================================================================

import ExcelJS from 'exceljs'
import { supabase as cliente } from '@/lib/supabase'

// En el navegador es el cliente de Supabase. Fuera de él —en la prueba que
// genera estos mismos libros contra los datos reales— se reemplaza por un
// cliente equivalente contra Postgres, para que lo que se verifica sea
// exactamente este archivo y no una copia parecida.
const supabase = globalThis.__supaShim ?? cliente

const ANCHO = (ws, anchos) => {
  ws.columns = anchos.map((w) => ({ width: w }))
}

/** Encabezado en negrita sobre fondo gris, como en las planillas actuales. */
function encabezar(fila) {
  fila.font = { bold: true, size: 10 }
  fila.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true }
  fila.eachCell((c) => {
    c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFE8E8E8' } }
    c.border = {
      top: { style: 'thin' }, left: { style: 'thin' },
      bottom: { style: 'thin' }, right: { style: 'thin' },
    }
  })
}

function descargar(buf, nombre) {
  const url = URL.createObjectURL(
    new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }))
  const a = document.createElement('a')
  a.href = url
  a.download = nombre
  a.click()
  URL.revokeObjectURL(url)
}

const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']

/** Los días del mes, como fechas ISO. */
function diasDelMes(mes) {
  const [y, m] = mes.split('-').map(Number)
  const ultimo = new Date(Date.UTC(y, m, 0)).getUTCDate()
  return Array.from({ length: ultimo }, (_, i) =>
    `${y}-${String(m).padStart(2, '0')}-${String(i + 1).padStart(2, '0')}`)
}

// ── BBDD con Semana ENAP ────────────────────────────────────────────────────


export async function construirBbdd(faenaId, mes) {
  const dias = diasDelMes(mes)
  const { data, error } = await supabase
    .from('v_comb_bbdd').select('*')
    .eq('faena_id', faenaId)
    .gte('dia_cierre', dias[0]).lte('dia_cierre', dias[dias.length - 1])
    .order('dia_cierre').order('hora')
  if (error) throw error
  const filas = data ?? []

  const wb = new ExcelJS.Workbook()
  const ws = wb.addWorksheet('BBDD')
  ANCHO(ws, [6, 12, 8, 28, 18, 10, 10, 22, 38, 14, 20, 8, 16, 14, 14, 18, 10])
  encabezar(ws.addRow([
    'id', 'Date', 'HORA', 'Flota', 'Equipo', 'Product', 'Volumen',
    'Nombre Estacion', 'Departamento', 'Numero de Tarjeta', 'Dispositivo',
    'Bomba', 'Registro Manual', 'CECO', 'Dia de Cierre', 'Semana Enap', 'Origen',
  ]))

  filas.forEach((f, i) => {
    ws.addRow([
      i + 1, f.fecha, f.hora ?? '', f.flota ?? '', f.equipo ?? '',
      f.producto ?? 'Diesel', f.volumen, f.estacion ?? '', f.departamento ?? '',
      f.tarjeta ?? '', f.autorizado_por ?? '', f.bomba ?? '',
      f.registro_manual, f.ceco_codigo ?? '', f.dia_cierre, f.semana_enap, f.origen,
    ])
  })
  ws.getColumn(7).numFmt = '#,##0.0'
  ws.views = [{ state: 'frozen', ySplit: 1 }]
  ws.autoFilter = { from: 'A1', to: { row: 1, column: 17 } }

  return { wb, nombre: `BBDD_${mes}.xlsx`, filas: filas.length }
}

// ── FORM AC 066: stock diario y KPI de llenado ──────────────────────────────


export async function construirFormAc066(faenaId, mes) {
  const dias = diasDelMes(mes)
  const [{ data: d1, error: e1 }, { data: d2, error: e2 }] = await Promise.all([
    supabase.from('v_comb_form_ac066').select('*')
      .eq('faena_id', faenaId).gte('fecha', dias[0]).lte('fecha', dias[dias.length - 1]),
    supabase.from('v_comb_form_ac066_dia').select('*')
      .eq('faena_id', faenaId).gte('fecha', dias[0]).lte('fecha', dias[dias.length - 1]),
  ])
  if (e1) throw e1
  if (e2) throw e2
  const filas = d1 ?? []
  const totales = d2 ?? []

  // Un estanque por fila, un día por columna: así se lee la planilla original.
  const estanques = Array.from(new Map(filas.map((f) => [f.estanque_id, f])).values())
    .sort((a, b) => (a.orden_cierre ?? 99) - (b.orden_cierre ?? 99))
  const porDia = new Map(filas.map((f) => [`${f.estanque_id}|${f.fecha}`, f]))
  const totPorDia = new Map(totales.map((t) => [t.fecha, t]))

  const [y, m] = mes.split('-').map(Number)
  const wb = new ExcelJS.Workbook()
  const ws = wb.addWorksheet(`${MESES[m - 1]} ${y}`)
  ANCHO(ws, [3, 3, 30, 13, 15, ...dias.map(() => 11)])

  ws.addRow([])
  ws.addRow([]).getCell(9).value = 'FORM AC 066 STOCK COMBUSTIBLE'
  ws.getRow(2).font = { bold: true, size: 13 }
  ws.addRow([])
  ws.addRow(['', '', '', '', `Mes: ${MESES[m - 1]} ${y}`]).font = { bold: true }
  ws.addRow([])
  encabezar(ws.addRow(['', '', 'Estación / Estanque', 'Capacidad Nominal',
    'Capacidad Máxima de llenado', ...dias.map((d) => Number(d.slice(8)))]))

  for (const e of estanques) {
    const fila = ws.addRow(['', '', e.estanque, e.capacidad_nominal, e.capacidad_llenado,
      ...dias.map((d) => porDia.get(`${e.estanque_id}|${d}`)?.stock ?? null)])
    fila.getCell(3).font = { bold: true }
    const kpi = ws.addRow(['', '', `KPI ${e.estanque}`, e.capacidad_nominal, e.capacidad_llenado,
      ...dias.map((d) => porDia.get(`${e.estanque_id}|${d}`)?.kpi_llenado ?? null)])
    for (let i = 6; i < 6 + dias.length; i++) kpi.getCell(i).numFmt = '0.0%'
    kpi.font = { italic: true, color: { argb: 'FF666666' } }
  }

  ws.addRow([])
  const total = ws.addRow(['', '', 'Total', null, null,
    ...dias.map((d) => totPorDia.get(d)?.stock_total ?? null)])
  total.font = { bold: true }
  const kpiT = ws.addRow(['', '', 'KPI DIARIO', null, null,
    ...dias.map((d) => totPorDia.get(d)?.kpi_diario ?? null)])
  for (let i = 6; i < 6 + dias.length; i++) kpiT.getCell(i).numFmt = '0.0%'
  kpiT.font = { bold: true }

  ws.addRow([])
  ws.addRow(['', '', 'Recibido de flota primaria', null, null,
    ...dias.map((d) => totPorDia.get(d)?.recibido_total ?? 0)])
  ws.addRow(['', '', 'C/E recepcionados', null, null,
    ...dias.map((d) => totPorDia.get(d)?.camiones_recepcionados ?? 0)])

  ws.views = [{ state: 'frozen', xSplit: 5, ySplit: 6 }]
  return { wb, nombre: `FORM_AC066_${MESES[m - 1]}_${y}.xlsx`, filas: estanques.length }
}

// ── Cierre Romeral ──────────────────────────────────────────────────────────



export async function construirCierreRomeral(faenaId, mes) {
  const dias = diasDelMes(mes)
  const desde = dias[0]
  const hasta = dias[dias.length - 1]

  const [{ data: d1, error: e1 }, { data: d2, error: e2 }] = await Promise.all([
    supabase.from('v_comb_cierre_romeral_mes').select('*')
      .eq('faena_id', faenaId).gte('fecha', desde).lte('fecha', hasta).order('fecha'),
    supabase.from('v_comb_cierre_romeral_numerales').select('*')
      .eq('faena_id', faenaId).gte('fecha', desde).lte('fecha', hasta).order('fecha'),
  ])
  if (e1) throw e1
  if (e2) throw e2
  const puntos = d1 ?? []
  const numerales = d2 ?? []

  const [y, m] = mes.split('-').map(Number)
  const wb = new ExcelJS.Workbook()

  // ── Una hoja por estación, con el movimiento del mes ──
  const estanques = Array.from(new Map(puntos.map((p) => [p.estanque_id, p])).values())
    .sort((a, b) => (a.orden_cierre ?? 99) - (b.orden_cierre ?? 99))

  for (const e of estanques) {
    // Los nombres de hoja de Excel no aceptan : \ / ? * [ ] y topan en 31.
    const nombre = e.estanque_nombre.replace(/[:\\/?*[\]]/g, ' ').slice(0, 31)
    const ws = wb.addWorksheet(nombre)
    ANCHO(ws, [4, 6, 12, 12, 12, 12, 12, 12, 12, 12])
    ws.addRow([]).getCell(3).value = `${e.estanque_nombre} — INFORME MENSUAL`
    ws.getRow(1).font = { bold: true, size: 12 }
    ws.addRow(['', '', 'MES:', `${MESES[m - 1]} ${y}`]).font = { bold: true }
    ws.addRow([])
    encabezar(ws.addRow(['', 'DIA', 'SALDO INICIAL', 'RECEPCIÓN DE CAMIÓN',
      'TRASVASIJE RECIBIDO', 'DESPACHOS', 'TRASVASIJE ENTREGADO',
      'SALDO FINAL', 'POR VARILLA', 'POR CONTADOR']))

    const porFecha = new Map(puntos.filter((p) => p.estanque_id === e.estanque_id)
      .map((p) => [p.fecha, p]))
    for (const d of dias) {
      const p = porFecha.get(d)
      ws.addRow(['', Number(d.slice(8)),
        p?.saldo_inicial ?? null, p?.recepcion_camion ?? null,
        p?.trasvasije_recibido ?? null, p?.despacho_orpak ?? null,
        p?.trasvasije_entregado ?? null, p?.saldo_final ?? null,
        p?.salida_por_varilla ?? null, p?.salida_por_contador ?? null])
    }
    ws.views = [{ state: 'frozen', ySplit: 4 }]
  }

  // ── Una hoja por día: el registro de cierre diario ──
  const diasConDatos = Array.from(new Set(puntos.map((p) => p.fecha))).sort()
  for (const d of diasConDatos) {
    const ws = wb.addWorksheet(d.slice(8))
    ANCHO(ws, [3, 26, 10, 12, 14, 8, 12, 12, 12, 12, 12])
    ws.addRow([]).getCell(2).value = 'REGISTRO DE CIERRE DIARIO'
    ws.getRow(1).font = { bold: true, size: 13 }
    const delDia = puntos.filter((p) => p.fecha === d)
    ws.addRow(['', 'Realizado por:', delDia[0]?.medido_por ?? ''])
    ws.addRow(['', 'Fecha:', d])
    ws.addRow(['', 'Estado:', delDia[0]?.estado === 'firmado' ? 'FIRMADO' : 'BORRADOR'])
    ws.addRow([])

    ws.addRow(['', 'MEDICIONES FÍSICAS']).font = { bold: true }
    encabezar(ws.addRow(['', 'Estación', 'Capacidad', 'H2O (mm)', 'Medición Inicial',
      'Recep. flota', 'Trasvasije', 'Medición Final', 'Salida varilla']))
    for (const p of delDia.sort((a, b) => (a.orden_cierre ?? 99) - (b.orden_cierre ?? 99))) {
      if (p.sin_medicion) {
        ws.addRow(['', p.estanque_nombre, null, null,
          `SIN MEDIR — ${p.motivo_sin_medicion ?? 'sin motivo'}`]).font =
          { italic: true, color: { argb: 'FF996600' } }
        continue
      }
      ws.addRow(['', p.estanque_nombre, null, p.agua_mm, p.saldo_inicial,
        p.recepcion_camion, p.trasvasije_recibido, p.saldo_final, p.salida_por_varilla])
    }

    ws.addRow([])
    ws.addRow(['', 'NUMERALES MECÁNICOS']).font = { bold: true }
    encabezar(ws.addRow(['', 'Estación', 'Surtidor', 'Nº Cta. Lts.', 'Numeral Inicial',
      'Numeral Final', 'Calibración', 'Despachado', 'Foto']))
    for (const n of numerales.filter((x) => x.fecha === d)
      .sort((a, b) => (a.orden_cierre ?? 99) - (b.orden_cierre ?? 99))) {
      const fila = ws.addRow(['', n.estanque, n.surtidor, n.cuentalitros,
        n.numeral_ini, n.numeral_fin, n.calibracion, n.despachado,
        n.con_foto ? 'Sí' : 'No'])
      if (n.reinicio_contador) {
        fila.getCell(9).value = `CONTADOR CAMBIADO — ${n.motivo_reinicio ?? ''}`
        fila.font = { italic: true, color: { argb: 'FF996600' } }
      }
    }
  }

  return { wb, nombre: `Cierre_Romeral_${MESES[m - 1]}_${y}.xlsx`, filas: diasConDatos.length }
}

// ── Construir y bajar ───────────────────────────────────────────────────────
// La construcción del libro va separada de la descarga a propósito: así se
// puede generar el mismo entregable, con el mismo código, fuera del navegador
// para verificarlo contra los datos reales. Un exportador que sólo se puede
// probar haciendo clic no se prueba nunca.

async function bajar(hecho) {
  const buf = await hecho.wb.xlsx.writeBuffer()
  descargar(buf, hecho.nombre)
  return hecho.filas
}

export const exportarBbdd = (faenaId, mes) =>
  construirBbdd(faenaId, mes).then(bajar)

export const exportarFormAc066 = (faenaId, mes) =>
  construirFormAc066(faenaId, mes).then(bajar)

export const exportarCierreRomeral = (faenaId, mes) =>
  construirCierreRomeral(faenaId, mes).then(bajar)
