// ============================================================================
// [MIG705] Excel del presupuesto de mantención con fórmulas
// ----------------------------------------------------------------------------
// El archivo rehace el cálculo de SICOM con fórmulas para poder modificarlo:
// las celdas amarillas son datos (horómetro, ritmo, bases, costos de kit,
// supuestos) y todo lo demás se recalcula. La columna «SICOM» y su diferencia
// permiten comprobar que las fórmulas dan lo mismo que el sistema.
//
// Hojas: Léeme · Supuestos · Kits · Escalera · Equipos · Neumáticos · Resumen.
// ============================================================================

import ExcelJS from 'exceljs'
import type { CamionDetallePpto, KitItemPpto, ParametrosExcelPpto, TrazaExcelPpto } from '@/lib/services/presupuesto'

const CLP = '"$"#,##0'
const VERDE = 'FF15803D'
const AMARILLO = 'FFFEF9C3'
const NIVELES = ['SL', 'SM1', 'SM2', 'SM3', 'SM4', 'SM5', 'SM6'] as const

function encabezado(ws: ExcelJS.Worksheet, fila = 1) {
  const r = ws.getRow(fila)
  r.font = { bold: true, color: { argb: 'FFFFFFFF' } }
  r.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: VERDE } }
  r.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true }
  r.height = 42
}
const dato = (c: ExcelJS.Cell) => { c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: AMARILLO } } }
const col = (n: number) => { let s = ''; let x = n; while (x > 0) { const m = (x - 1) % 26; s = String.fromCharCode(65 + m) + s; x = Math.floor((x - 1) / 26) } return s }

const fechaExcel = (s: string | null | undefined) => (s ? new Date(`${String(s).slice(0, 10)}T12:00:00`) : null)
const UNICAS = ['C1', 'C2', 'C4', 'C5', 'C6', 'C7', 'C8']
const LINEAS_12M = ['B3', 'C1', 'C2', 'C3', 'C4', 'C5', 'C6', 'C7', 'C8', 'D1']
const LINEAS_24M = ['A5', 'B2']
const CAT_PREV = 'Mantención preventiva (ya va en el preventivo)'

export async function exportarPresupuestoExcel(p: ParametrosExcelPpto, camiones: CamionDetallePpto[], extra?: { kitItems?: KitItemPpto[]; traza?: TrazaExcelPpto }): Promise<Blob> {
  const wb = new ExcelJS.Workbook()
  wb.creator = 'SICOM-Pillado'
  wb.created = new Date()
  const sup = p.supuestos

  // ── Léeme ─────────────────────────────────────────────────────────────────
  const wl = wb.addWorksheet('Léeme')
  wl.getColumn(1).width = 120
  const texto = [
    'Presupuesto de mantención 2027 por equipo — SICOM',
    `Calculado en SICOM el ${p.fecha_calculo ?? '—'}. Generado el ${new Date().toLocaleString('es-CL')}.`,
    '',
    'Celdas AMARILLAS: datos que puedes cambiar. Todo lo demás son fórmulas.',
    'TRAZABILIDAD: los montos históricos salen de la hoja «Compras» (cada línea de Softland / OS que usa el presupuesto). Filtra «Compras» por patente y línea para ver qué compras forman cada número.',
    '   Monto pesos 2026 = monto × (1 + IPC histórico)^(2026 − año). «Mes cerrado» = Sí si la compra es anterior al fin de la ventana (último mes cerrado).',
    '   Correctivo base 24m = suma de compras línea A2 de los últimos 24 meses cerrados en pesos 2026 ÷ 2; en equipos con pauta se restan las de categoría «Mantención preventiva» (ya van en el preventivo).',
    '   Neumáticos base = compras A3 de 36 meses ÷ 3. Preventivo sin pauta = compras A1 de 24 meses ÷ 2. Real por año = suma de compras A* del año (pesos de cada año).',
    '   Ritmo = manual si existe; si no, el mayor entre promedio 18 meses y el mejor mes de la hoja «Horas GPS» (máx. 14 h/día); si no hay GPS, el de respaldo.',
    '   Cumplimiento de la pauta = preventivas de la hoja «Preventivas registradas» ÷ años ÷ las que pide la pauta (ritmo × 365 ÷ intervalo).',
    '   Mayores 2027 = hoja «Mayores» (overhaul programados y componentes por pauta que vencen en 2027, al costo del kit).',
    '   Resumen: las líneas sin patente también se calculan desde «Compras» (12 o 24 meses), el seguro con su cuota típica × 12 y la reserva por gastos únicos.',
    'Supuestos: IPC, piso de correctivo y neumáticos, umbral del servicio anual, costo del TC8 y de la certificación de pluma, curva de edad.',
    'Kits: costo de cada nivel de pauta por modelo, sumado desde «Kits detalle» (kit completo y la parte de filtros y lubricantes, que es la que entra al preventivo).',
    'Kits detalle: cada ítem del kit con su cantidad, precio de referencia, precio real de Softland y PRECIO USADO (editable); la observación marca precios sin compra o en otra unidad (balde).',
    'Preventivas hechas: por equipo, lo que pide la pauta, las visitas del presupuesto, las preventivas registradas (OS 2025-2026 + OT SICOM) y el gasto real en preventivo.',
    'Escalera: costo de filtros y lubricantes por nivel; si un modelo no tiene un nivel, toma el nivel anterior (el mayor absorbe a los menores).',
    'Equipos: una fila por equipo. Horas 2027 = horómetro + ritmo × días. Visitas por nivel: múltiplos de (intervalo × 2^n) que caen en 2027',
    '   (SL cada intervalo, SM1 cada 2, SM2 cada 4, SM3 cada 8, SM4 cada 16, SM5 cada 32, SM6 cada 64).',
    '   Servicio anual si el ritmo está bajo el umbral. Equipos sin pauta: su preventivo real de 24 meses.',
    '   Correctivo = promedio real 24 meses × factor de edad (curva 2027 ÷ curva de la ventana medida, tope 1,5) × (1 − baja por cumplir la pauta × lo que faltaba cumplir), con piso de camión joven; + ajuste de pluma.',
    '   Neumáticos: hoja Neumáticos. TC8: si vence en 2027 o antes. Certificación de pluma: 1 = sí.',
    'Neumáticos: real por año, promedio de 36 meses y piso para camión con uso (ritmo ≥ 1 h/día y 2 o más años de edad equivalente).',
    'Resumen: total por línea; las líneas de equipos suman la hoja Equipos y el resto (sin patente, flota, estructura) va como dato.',
    'Columnas «SICOM» y «Diferencia»: el valor del sistema, para comprobar que las fórmulas cuadran (diferencias de pocos pesos son redondeo).',
  ]
  texto.forEach((t, i) => { const c = wl.getCell(i + 1, 1); c.value = t; if (i === 0) c.font = { bold: true, size: 14 } })

  // El resumen va segundo; se llena al final, cuando ya existen las demás hojas.
  const wr = wb.addWorksheet('Resumen')

  // ── Supuestos ─────────────────────────────────────────────────────────────
  const ws = wb.addWorksheet('Supuestos')
  ws.columns = [{ width: 46 }, { width: 16 }, { width: 60 }]
  ws.getRow(1).values = ['Supuesto', 'Valor', 'Nota']
  encabezado(ws)
  const traza = extra?.traza
  const filasSup: [string, string, number | ExcelJS.CellFormulaValue | Date | ((r: Record<string, string>) => ExcelJS.CellFormulaValue), string, string?][] = [
    ['fecha', 'Fecha de cálculo (desde aquí se proyectan las horas)', p.fecha_calculo ? new Date(`${p.fecha_calculo}T12:00:00`) : new Date(), 'dd-mm-yyyy'],
    ['ipc27', 'IPC 2027', sup.ipc_2027 ?? 0.035, '0.0%'],
    ['ipc28', 'IPC 2028', sup.ipc_2028 ?? 0.03, '0.0%'],
    ['ipc29', 'IPC 2029', sup.ipc_2029 ?? 0.03, '0.0%'],
    ['f27', 'Factor de precios 2027 (sobre pesos 2026)', { formula: '1+B3' }, '0.0000', 'calc'],
    ['f28', 'Factor de precios 2028', { formula: 'B6*(1+B4)' }, '0.0000', 'calc'],
    ['f29', 'Factor de precios 2029', { formula: 'B7*(1+B5)' }, '0.0000', 'calc'],
    ['hedad', 'Horas que equivalen a un año de edad', sup.horas_por_anio_edad ?? 2500, '#,##0'],
    ['cmad', 'Correctivo anual de un camión pesado maduro', sup.correctivo_maduro ?? 0, CLP],
    ['nmad', 'Neumáticos anuales de un camión con uso (piso)', sup.neumatico_maduro ?? 0, CLP],
    ['umbral', 'Bajo este ritmo (h/día) se agrega el servicio anual', sup.ritmo_anual_calendario ?? 6.6, '0.0'],
    ['tc8', 'Costo de renovar un TC8', sup.costo_tc8 ?? 840000, CLP],
    ['pluma', 'Certificación anual de una pluma', sup.costo_cert_pluma ?? 550000, CLP],
    ['cont', 'Contingencia (sobre todo menos combustible)', sup.contingencia ?? 0.03, '0.0%'],
    ['redu', 'Baja del correctivo si se cumple la pauta (× lo que faltaba cumplir)', sup.reduccion_correctivo_pauta ?? 0.2, '0%'],
    ['ipch', 'IPC histórico (lleva las compras pasadas a pesos 2026)', Number(traza?.ipc_historico ?? 0.04), '0.0%'],
    ['fin', 'Fin de la ventana medida (último mes cerrado)', fechaExcel(traza?.fin) ?? new Date(), 'dd-mm-yyyy'],
    ['i12', 'Inicio ventana 12 meses', (x) => ({ formula: `EDATE(${x.fin}+1,-12)` }), 'dd-mm-yyyy', 'calc'],
    ['i24', 'Inicio ventana 24 meses (correctivo, preventivo sin pauta)', (x) => ({ formula: `EDATE(${x.fin}+1,-24)` }), 'dd-mm-yyyy', 'calc'],
    ['i36', 'Inicio ventana 36 meses (neumáticos)', (x) => ({ formula: `EDATE(${x.fin}+1,-36)` }), 'dd-mm-yyyy', 'calc'],
    ['anios', 'Años de historia (desde 01-01-2023 al fin de la ventana)', (x) => ({ formula: `(INT(${x.fin})-DATE(2023,1,1)+1)/365.25` }), '0.00', 'calc'],
    ['seg', 'Cuota mensual típica del seguro (mediana de cuotas ≥ $2 MM, 12 meses)', Number(traza?.seguro_cuota ?? 0), CLP],
  ]
  const ref: Record<string, string> = {}
  filasSup.forEach(([k], i) => { ref[k] = `Supuestos!$B$${i + 2}` })
  filasSup.forEach(([, nombre, valor, fmt, calc], i) => {
    const r = i + 2
    ws.getCell(r, 1).value = nombre
    const c = ws.getCell(r, 2); c.value = (typeof valor === 'function' ? valor(ref) : valor) as ExcelJS.CellValue; c.numFmt = fmt
    if (!calc) dato(c)
  })
  const curvaIni = filasSup.length + 4
  ws.getCell(curvaIni - 1, 1).value = 'Curva de edad (factor del correctivo según edad equivalente)'
  ws.getCell(curvaIni - 1, 1).font = { bold: true }
  ws.getCell(curvaIni, 1).value = 'Edad (años)'; ws.getCell(curvaIni, 2).value = 'Factor'
  ws.getRow(curvaIni).font = { bold: true }
  const curva = [...p.curva].sort((a, b) => a.edad - b.edad)
  curva.forEach((x, i) => {
    ws.getCell(curvaIni + 1 + i, 1).value = x.edad
    const c = ws.getCell(curvaIni + 1 + i, 2); c.value = Number(x.factor); c.numFmt = '0.00'; dato(c)
  })
  const curvaRango = `Supuestos!$B$${curvaIni + 1}:$B$${curvaIni + curva.length}`
  const maxEdad = Math.max(...curva.map((x) => x.edad), 0)

  // ── Kits (suma de Kits detalle) ───────────────────────────────────────────
  const wk = wb.addWorksheet('Kits')
  const wd = wb.addWorksheet('Kits detalle')
  const items = extra?.kitItems ?? []
  const itN = items.length + 1
  wk.columns = [
    { header: 'Grupo kit', key: 'g', width: 22 }, { header: 'Intervalo (h)', key: 'i', width: 12 },
    { header: 'Nivel', key: 'n', width: 10 }, { header: 'Costo kit completo', key: 'c', width: 18 },
    { header: 'Filtros y lubricantes (entra al preventivo)', key: 'fl', width: 22 },
  ]
  encabezado(wk)
  p.kits.forEach((k, i) => {
    const r = wk.addRow({ g: k.grupo_kit, i: p.intervalos[k.grupo_kit] ?? null, n: k.nivel })
    const fila = i + 2
    const rng = (c: string) => `'Kits detalle'!$${c}$2:$${c}$${itN}`
    if (items.length) {
      r.getCell('c').value = { formula: `SUMIFS(${rng('M')},${rng('A')},A${fila},${rng('B')},C${fila})` }
      r.getCell('fl').value = { formula: `SUMIFS(${rng('M')},${rng('A')},A${fila},${rng('B')},C${fila},${rng('N')},"Sí")` }
    } else {
      r.getCell('c').value = Number(k.costo); r.getCell('fl').value = Number(k.fl)
      dato(r.getCell('c')); dato(r.getCell('fl'))
    }
    r.getCell('c').numFmt = CLP; r.getCell('fl').numFmt = CLP
  })
  wk.views = [{ state: 'frozen', ySplit: 1 }]
  wk.autoFilter = { from: 'A1', to: 'E1' }
  const kitN = p.kits.length + 1

  // ── Kits detalle: cada ítem con su precio ─────────────────────────────────
  wd.getRow(1).values = ['Grupo kit', 'Nivel', 'Ítem', 'Cantidad', 'Unidad', 'Código Softland', 'Última compra en Softland', 'Fecha última compra',
    'Precio de referencia (por unidad del kit)', 'Precio Softland (por unidad de compra)', 'Hoy usa precio real', 'PRECIO USADO', 'Subtotal',
    'Filtros y lubricantes', 'Observación']
  encabezado(wd)
  ;[18, 8, 38, 9, 7, 15, 36, 11, 14, 14, 9, 13, 13, 9, 46].forEach((w, i) => { wd.getColumn(i + 1).width = w })
  items.forEach((it, i) => {
    const r = i + 2
    const ref = Number(it.precio_ref)
    const soft = it.precio_softland == null ? null : Number(it.precio_softland)
    const obs = soft == null
      ? 'Sin compras en Softland en 18 meses: se usa la referencia.'
      : !it.usa_precio_real && soft > ref * 2
        ? 'Softland compra en otra unidad (balde, caja): su precio no es comparable por unidad del kit.'
        : !it.usa_precio_real && soft < ref * 0.5
          ? 'Precio Softland muy bajo frente a la referencia: revisar unidad o producto.'
          : it.provisorio ? 'Ítem provisorio en la pauta.' : ''
    const vals: ExcelJS.CellValue[] = [it.grupo_kit, it.nivel, it.item, Number(it.cantidad), it.unidad, it.cod_softland, it.descripcion_softland,
      it.ultima_compra ? new Date(`${it.ultima_compra}T12:00:00`) : null, ref, soft, it.usa_precio_real ? 'Sí' : 'No',
      it.usa_precio_real && soft != null ? soft : ref, { formula: `D${r}*L${r}` }, it.fil_lub ? 'Sí' : 'No', obs]
    vals.forEach((v, j) => { wd.getCell(r, j + 1).value = v })
    wd.getCell(r, 8).numFmt = 'dd-mm-yyyy'
    ;[9, 10, 12, 13].forEach((c) => { wd.getCell(r, c).numFmt = CLP })
    dato(wd.getCell(r, 4)); dato(wd.getCell(r, 12)); dato(wd.getCell(r, 14))
    if (obs && !obs.startsWith('Ítem')) wd.getCell(r, 15).font = { color: { argb: 'FFB45309' } }
  })
  wd.views = [{ state: 'frozen', xSplit: 3, ySplit: 1 }]
  wd.autoFilter = { from: 'A1', to: 'O1' }

  // ── Escalera (nivel efectivo con absorción) ───────────────────────────────
  const we = wb.addWorksheet('Escalera')
  we.getRow(1).values = ['Grupo kit', 'Intervalo (h)', ...NIVELES, 'ANUAL']
  encabezado(we)
  we.getColumn(1).width = 22
  for (let i = 2; i <= 10; i++) we.getColumn(i).width = 12
  const grupos = Array.from(new Set(p.kits.map((k) => k.grupo_kit))).sort()
  const sumifs = (g: string, nivel: string) => `SUMIFS(Kits!$E$2:$E$${kitN},Kits!$A$2:$A$${kitN},${g},Kits!$C$2:$C$${kitN},"${nivel}")`
  const countifs = (g: string, nivel: string) => `COUNTIFS(Kits!$A$2:$A$${kitN},${g},Kits!$C$2:$C$${kitN},"${nivel}")`
  grupos.forEach((g, i) => {
    const r = i + 2
    we.getCell(r, 1).value = g
    const ci = we.getCell(r, 2); ci.value = p.intervalos[g] ?? null; dato(ci)
    NIVELES.forEach((nv, j) => {
      const c = we.getCell(r, 3 + j)
      c.value = j === 0
        ? { formula: sumifs(`$A${r}`, nv) }
        : { formula: `IF(${countifs(`$A${r}`, nv)}>0,${sumifs(`$A${r}`, nv)},${col(2 + j)}${r})` }
      c.numFmt = CLP
    })
    const ca = we.getCell(r, 10); ca.value = { formula: sumifs(`$A${r}`, 'ANUAL') }; ca.numFmt = CLP
  })
  const escN = grupos.length + 1
  const esc = (g: string, idx: number) => `INDEX(Escalera!$C$2:$J$${escN},MATCH(${g},Escalera!$A$2:$A$${escN},0),${idx})`

  // ── Hojas de origen (MIG709) ──────────────────────────────────────────────
  const compras = traza?.compras ?? []
  const compN = Math.max(compras.length + 1, 2)
  const cr = (c: string) => `Compras!$${c}$2:$${c}$${compN}`
  const gps = traza?.gps ?? []
  const gpsN = Math.max(gps.length + 1, 2)
  const regs = traza?.preventivas ?? []
  const regN = Math.max(regs.length + 1, 2)
  const mayores = traza?.mayores ?? []
  const mayN = Math.max(mayores.length + 1, 2)
  const opex = traza?.opex ?? []
  const T = !!traza
  // Suma de compras en pesos 2026 de una patente, una línea y desde una fecha, solo meses cerrados.
  const sumaCompras = (pat: string, linea: string, desde: string, extraCrit = '') =>
    `SUMIFS(${cr('L')},${cr('A')},${pat},${cr('D')},"${linea}",${cr('B')},">="&${desde},${cr('M')},"Sí"${extraCrit})`

  const equiposAntes = wb.addWorksheet('Equipos')

  // Compras: cada línea de Softland / OS que usa el presupuesto.
  const wc = wb.addWorksheet('Compras')
  wc.getRow(1).values = ['Patente', 'Fecha', 'Año', 'Línea', 'Categoría (correctivo)', 'Proveedor / origen', 'Folio / OC', 'Código', 'Descripción',
    'Monto (pesos del año)', 'Factor a pesos 2026', 'Monto pesos 2026', 'Mes cerrado', 'Gasto único ≥ $10 MM', 'Mantención de pluma Calama']
  encabezado(wc)
  ;[10, 11, 6, 6, 30, 30, 11, 14, 46, 14, 9, 14, 8, 9, 9].forEach((w, i) => { wc.getColumn(i + 1).width = w })
  compras.forEach((x, i) => {
    const r = i + 2
    const row = wc.getRow(r)
    row.values = [x[0], fechaExcel(x[1]), { formula: `YEAR(B${r})` }, x[2], x[3], x[4], x[5] == null ? null : String(x[5]), x[6], x[7], Number(x[8]),
      { formula: `(1+${ref.ipch})^(2026-C${r})` }, { formula: `J${r}*K${r}` }, { formula: `IF(B${r}<=${ref.fin},"Sí","No")` },
      { formula: `IF(AND(J${r}>=10000000,OR(${UNICAS.map((l) => `D${r}="${l}"`).join(',')})),"Sí","No")` }, x[9] ? 'Sí' : 'No']
    row.getCell(2).numFmt = 'dd-mm-yyyy'; row.getCell(10).numFmt = CLP; row.getCell(11).numFmt = '0.0000'; row.getCell(12).numFmt = CLP
  })
  wc.views = [{ state: 'frozen', ySplit: 1 }]
  wc.autoFilter = { from: 'A1', to: 'O1' }

  // Horas GPS por mes completo.
  const wg = wb.addWorksheet('Horas GPS')
  wg.getRow(1).values = ['Patente', 'Mes', 'Horas del mes', 'Días del mes', 'Horas por día']
  encabezado(wg)
  ;[10, 11, 11, 9, 9].forEach((w, i) => { wg.getColumn(i + 1).width = w })
  gps.forEach((x, i) => {
    const r = i + 2
    wg.getRow(r).values = [x[0], fechaExcel(x[1]), Number(x[2]), { formula: `DAY(EOMONTH(B${r},0))` }, { formula: `C${r}/D${r}` }]
    wg.getCell(r, 2).numFmt = 'mm-yyyy'; wg.getCell(r, 3).numFmt = '#,##0.0'; wg.getCell(r, 5).numFmt = '0.00'
    dato(wg.getCell(r, 3))
  })
  wg.autoFilter = { from: 'A1', to: 'E1' }

  // Preventivas registradas una por una.
  const wp = wb.addWorksheet('Preventivas registradas')
  wp.getRow(1).values = ['Patente', 'Fecha', 'Año', 'Fuente', 'Número (OS / OT / folio)']
  encabezado(wp)
  ;[10, 11, 6, 30, 16].forEach((w, i) => { wp.getColumn(i + 1).width = w })
  regs.forEach((x, i) => {
    const r = i + 2
    wp.getRow(r).values = [x[0], fechaExcel(x[1]), { formula: `YEAR(B${r})` }, x[2], x[3]]
    wp.getCell(r, 2).numFmt = 'dd-mm-yyyy'
  })
  wp.autoFilter = { from: 'A1', to: 'E1' }

  // Mayores 2027: overhaul programados y componentes por pauta.
  const wm = wb.addWorksheet('Mayores')
  wm.getRow(1).values = ['Patente', 'Tipo', 'Descripción', 'Gatillo / condición', 'Grupo kit', 'Nivel', 'Horas', 'MONTO 2027']
  encabezado(wm)
  ;[10, 20, 44, 44, 18, 8, 9, 14].forEach((w, i) => { wm.getColumn(i + 1).width = w })
  mayores.forEach((x, i) => {
    const r = i + 2
    wm.getRow(r).values = [x[0], x[1], x[2], x[3], x[4], x[5], x[6] == null ? null : Number(x[6]),
      x[7] != null ? Number(x[7]) : { formula: `SUMIFS(Kits!$D$2:$D$${kitN},Kits!$A$2:$A$${kitN},E${r},Kits!$C$2:$C$${kitN},F${r})*${ref.f27}` }]
    wm.getCell(r, 8).numFmt = CLP; wm.getCell(r, 7).numFmt = '#,##0'
    if (x[7] != null) dato(wm.getCell(r, 8))
  })
  wm.autoFilter = { from: 'A1', to: 'H1' }
  const rOpex = mayN + 3
  wm.getCell(rOpex - 1, 1).value = 'Programas de gasto 2027 sin patente (línea E2)'
  wm.getCell(rOpex - 1, 1).font = { bold: true }
  opex.forEach((x, i) => {
    const r = rOpex + i
    wm.getCell(r, 2).value = 'Programa (E2)'; wm.getCell(r, 3).value = x[0]; wm.getCell(r, 4).value = x[1]
    const c = wm.getCell(r, 8); c.value = Number(x[2]); c.numFmt = CLP; dato(c)
  })
  const opexRango = `Mayores!$H$${rOpex}:$H$${rOpex + Math.max(opex.length, 1) - 1}`

  // ── Equipos ───────────────────────────────────────────────────────────────
  const wq = equiposAntes
  const cols: { h: string; w: number }[] = [
    { h: 'Grupo', w: 22 }, { h: 'Patente', w: 11 }, { h: 'Código', w: 11 }, { h: 'Modelo', w: 18 }, { h: 'Año fab.', w: 8 }, { h: 'Faena', w: 24 },
    { h: 'Real 2023', w: 12 }, { h: 'Real 2024', w: 12 }, { h: 'Real 2025', w: 12 }, { h: 'Real 2026 a la fecha', w: 12 },
    { h: 'Grupo kit (pauta)', w: 18 }, { h: 'Intervalo (h)', w: 10 }, { h: 'Horómetro', w: 11 }, { h: 'Ritmo (h/día)', w: 9 }, { h: 'Origen del ritmo', w: 26 },
    { h: 'Días al 1-ene-2027', w: 9 }, { h: 'Días al 31-dic-2027', w: 9 }, { h: 'Horas inicio 2027', w: 11 }, { h: 'Horas fin 2027', w: 11 },
    ...NIVELES.map((n) => ({ h: `Visitas ${n}`, w: 8 })), { h: 'Servicio anual', w: 8 },
    { h: 'Preventivo 24m sin pauta (pesos 2026)', w: 13 }, { h: 'PREVENTIVO 2027', w: 13 },
    { h: 'Correctivo base 24m (pesos 2026)', w: 13 }, { h: 'Edad equivalente 2027', w: 9 }, { h: 'Edad de la ventana medida', w: 9 },
    { h: 'Curva 2027', w: 8 }, { h: 'Curva ventana', w: 8 }, { h: 'Factor de edad (tope 1,5)', w: 8 }, { h: 'Piso camión joven', w: 12 },
    { h: 'Ajuste pluma 2027', w: 12 }, { h: 'CORRECTIVO 2027', w: 13 },
    { h: 'NEUMÁTICOS 2027 (hoja Neumáticos)', w: 13 }, { h: 'MAYORES 2027 (overhaul y componentes)', w: 13 },
    { h: 'TC8 vence', w: 11 }, { h: 'TC8 2027', w: 11 }, { h: 'Certifica pluma (1/0)', w: 8 }, { h: 'Cert. pluma 2027', w: 11 },
    { h: 'TOTAL 2027', w: 14 }, { h: 'SICOM 2027', w: 14 }, { h: 'Diferencia', w: 11 },
    { h: 'Cumplimiento de la pauta 2025-2026 (0 a 1)', w: 12 },
    { h: 'Ritmo promedio 18 meses (GPS)', w: 9 }, { h: 'Ritmo mejor mes (hoja Horas GPS)', w: 9 }, { h: 'Ritmo manual', w: 8 },
    { h: 'Ritmo de respaldo (sin GPS)', w: 9 }, { h: 'Cumplimiento: se mide desde', w: 11 },
    { h: 'Preventivas registradas en el período', w: 10 }, { h: 'La pauta pide al año', w: 9 },
  ]
  wq.getRow(1).values = cols.map((c) => c.h)
  cols.forEach((c, i) => { wq.getColumn(i + 1).width = c.w })
  encabezado(wq)
  // Letras de columna por nombre corto.
  const C = {
    grupo: 1, pat: 2, cod: 3, mod: 4, anio: 5, faena: 6, r23: 7, r24: 8, r25: 9, r26: 10,
    kit: 11, int: 12, hor: 13, rit: 14, ori: 15, d0: 16, d1: 17, hi: 18, hf: 19,
    v0: 20, anual: 27, pbase: 28, prev: 29, cbase: 30, e27: 31, ew: 32, ct: 33, cw: 34, fac: 35, piso: 36, aplu: 37, corr: 38,
    neu: 39, may: 40, tc8v: 41, tc8: 42, plf: 43, plc: 44, tot: 45, sic: 46, dif: 47, cump: 48,
    r18: 49, rmm: 50, rman: 51, rres: 52, desde: 53, hech: 54, pide: 55,
  }
  const L = Object.fromEntries(Object.entries(C).map(([k, v]) => [k, col(v)])) as Record<keyof typeof C, string>
  const f27 = (sup.ipc_2027 ?? 0.035) + 1
  const ordenados = [...camiones].sort((a, b) =>
    (a.contrato ? 0 : 1) - (b.contrato ? 0 : 1) || (a.contrato ?? a.familia).localeCompare(b.contrato ?? b.familia) || a.patente.localeCompare(b.patente))

  ordenados.forEach((c, i) => {
    const r = i + 2
    const b = c.base
    const ajustePluma = (b.partidas_correctivo ?? []).reduce((s, x) => s + Number(x.monto), 0)
    const certPluma = (b.certificaciones ?? []).some((x) => x.anio === 2027 && x.descripcion.includes('pluma')) ? 1 : 0
    const certTotal = (b.certificaciones ?? []).filter((x) => x.anio === 2027).reduce((s, x) => s + Number(x.monto), 0)
    const set = (k: keyof typeof C, v: ExcelJS.CellValue, fmt?: string, esDato = false) => {
      const cell = wq.getCell(r, C[k]); cell.value = v; if (fmt) cell.numFmt = fmt; if (esDato) dato(cell)
    }
    const F = (s: string) => ({ formula: s })
    set('grupo', c.contrato ? `Contrato ${c.contrato}` : c.familia)
    set('pat', c.patente); set('cod', c.codigo); set('mod', c.modelo); set('anio', c.anio_fab, '0', true); set('faena', c.faena)
    const P = `$${L.pat}${r}`
    const te = traza?.equipos?.[c.patente]
    if (T) {
      ;(['r23', 'r24', 'r25', 'r26'] as const).forEach((k, j) => set(k, F(`SUMIFS(${cr('J')},${cr('A')},${P},${cr('C')},${2023 + j},${cr('D')},"A*")`), CLP))
    } else {
      set('r23', c.real['2023'], CLP); set('r24', c.real['2024'], CLP); set('r25', c.real['2025'], CLP); set('r26', c.real['2026'], CLP)
    }
    set('kit', b.con_pauta ? b.grupo_kit : null, undefined, true)
    set('int', F(`IF(${L.kit}${r}="","",INDEX(Escalera!$B$2:$B$${escN},MATCH(${L.kit}${r},Escalera!$A$2:$A$${escN},0)))`), '#,##0')
    set('hor', Number(b.horometro), '#,##0', true)
    if (T) {
      set('r18', te?.ritmo_18m == null ? null : Number(te.ritmo_18m), '0.00', true)
      set('rmm', F(`_xlfn.MAXIFS('Horas GPS'!$E$2:$E$${gpsN},'Horas GPS'!$A$2:$A$${gpsN},${P},'Horas GPS'!$E$2:$E$${gpsN},"<=14")`), '0.00')
      set('rman', te?.ritmo_manual == null ? null : Number(te.ritmo_manual), '0.00', true)
      set('rres', te?.ritmo_respaldo == null ? null : Number(te.ritmo_respaldo), '0.00', true)
      set('rit', F(`IF(${L.rman}${r}<>"",${L.rman}${r},IF(MAX(${L.r18}${r},${L.rmm}${r})>0,MAX(${L.r18}${r},${L.rmm}${r}),N(${L.rres}${r})))`), '0.00')
      set('ori', F(`IF(${L.rman}${r}<>"","Manual",IF(AND(${L.rmm}${r}>0,${L.rmm}${r}>N(${L.r18}${r})),"Mejor mes GPS",IF(N(${L.r18}${r})>0,"Promedio 18 meses","Respaldo: ${(b.ritmo_fuente ?? "sin dato").replace(/"/g, '')}")))`))
    } else {
      set('rit', Number(b.ritmo), '0.00', true)
      set('ori', b.ritmo_fuente)
    }
    set('d0', F(`DATE(2027,1,1)-${ref.fecha}`), '0')
    set('d1', F(`DATE(2027,12,31)-${ref.fecha}`), '0')
    set('hi', F(`${L.hor}${r}+${L.rit}${r}*(${L.d0}${r}-1)`), '#,##0')
    set('hf', F(`${L.hor}${r}+${L.rit}${r}*${L.d1}${r}`), '#,##0')
    const ok = `AND(${L.kit}${r}<>"",${L.rit}${r}>=0.1)`
    const n = (m: number) => `(INT(${L.hf}${r}/(${L.int}${r}*${m}))-INT(${L.hi}${r}/(${L.int}${r}*${m})))`
    NIVELES.forEach((_, j) => {
      const m = 2 ** j
      const formula = j < 6 ? `IF(${ok},${n(m)}-${n(m * 2)},0)` : `IF(${ok},${n(m)},0)`
      const cell = wq.getCell(r, C.v0 + j); cell.value = F(formula); cell.numFmt = '0'
    })
    set('anual', F(`IF(AND(${L.kit}${r}<>"",${L.rit}${r}<${ref.umbral}),1,0)`), '0')
    if (T) set('pbase', F(`IF(${L.kit}${r}="",${sumaCompras(P, 'A1', ref.i24)}/2,0)`), CLP)
    else set('pbase', b.con_pauta ? 0 : Math.round(Number(c.preventivo) / f27), CLP, true)
    const prevCon = [...NIVELES.map((_, j) => `${col(C.v0 + j)}${r}*${esc(`${L.kit}${r}`, j + 1)}`), `${L.anual}${r}*${esc(`${L.kit}${r}`, 8)}`].join('+')
    set('prev', F(`IF(${L.kit}${r}="",${L.pbase}${r},${prevCon})*${ref.f27}`), CLP)
    if (T) set('cbase', F(`(${sumaCompras(P, 'A2', ref.i24)}-IF(${L.kit}${r}<>"",${sumaCompras(P, 'A2', ref.i24, `,${cr('E')},"${CAT_PREV}"`)},0))/2`), CLP)
    else set('cbase', Number(b.correctivo_base), CLP, true)
    set('e27', F(`MAX(IF(${L.anio}${r}="",99,2027-${L.anio}${r}),(${L.hor}${r}+${L.rit}${r}*365.25*0.5)/${ref.hedad})`), '0.0')
    set('ew', F(`MAX(IF(${L.anio}${r}="",99,2025.5-${L.anio}${r}),(${L.hor}${r}-${L.rit}${r}*365.25)/${ref.hedad},0)`), '0.0')
    set('ct', F(`INDEX(${curvaRango},MIN(INT(MAX(${L.e27}${r},0)),${maxEdad})+1)`), '0.00')
    set('cw', F(`INDEX(${curvaRango},MIN(INT(${L.ew}${r}),${maxEdad})+1)`), '0.00')
    set('fac', F(`MIN(${L.ct}${r}/${L.cw}${r},1.5)`), '0.00')
    set('piso', F(`IF(AND(${L.kit}${r}<>"",${L.e27}${r}<6),${ref.cmad}*${L.ct}${r}*0.5,0)`), CLP)
    if (T) {
      const plu26 = `SUMIFS(${cr('L')},${cr('A')},${P},${cr('O')},"Sí",${cr('B')},">="&DATE(2026,1,1),${cr('M')},"Sí")*365/(INT(${ref.fin})-DATE(2026,1,1)+1)`
      set('aplu', F(`MAX(${plu26}-${sumaCompras(P, 'A2', ref.i24, `,${cr('O')},"Sí"`)}/2,0)*${ref.f27}`), CLP)
      set('desde', fechaExcel(te?.desde) ?? new Date(2025, 0, 1), 'dd-mm-yyyy', true)
      set('hech', F(`COUNTIFS('Preventivas registradas'!$A$2:$A$${regN},${P},'Preventivas registradas'!$B$2:$B$${regN},">="&${L.desde}${r},'Preventivas registradas'!$B$2:$B$${regN},"<="&${ref.fin})`), '0')
      set('pide', F(`IF(${L.kit}${r}="","",MAX(${L.rit}${r},0)*365.25/${L.int}${r})`), '0.0')
      set('cump', F(`IF(${L.kit}${r}="",1,IF(OR(${L.pide}${r}<0.5,${ref.fin}-${L.desde}${r}<180),1,MIN(${L.hech}${r}/MAX((${ref.fin}-${L.desde}${r}+1)/365.25,0.1)/${L.pide}${r},1)))`), '0%')
    } else {
      set('aplu', Math.round(ajustePluma), CLP, true)
      set('cump', Number(b.cumplimiento_pauta ?? 1), '0%', true)
    }
    set('corr', F(`IF(${L.kit}${r}<>"",MAX(${L.cbase}${r}*${L.fac}${r}*(1-${ref.redu}*(1-${L.cump}${r})),${L.piso}${r}),${L.cbase}${r})*${ref.f27}+${L.aplu}${r}`), CLP)
    set('neu', F(`Neumáticos!L${r}`), CLP)
    if (T) set('may', F(`SUMIFS(Mayores!$H$2:$H$${mayN},Mayores!$A$2:$A$${mayN},${P})`), CLP)
    else set('may', Number(c.mayores), CLP, true)
    set('tc8v', c.tc8_vence ? new Date(`${c.tc8_vence}T12:00:00`) : null, 'dd-mm-yyyy', true)
    set('tc8', F(`IF(AND(${L.tc8v}${r}<>"",YEAR(${L.tc8v}${r})<=2027),${ref.tc8}*${ref.f27},0)`), CLP)
    set('plf', certPluma, '0', true)
    set('plc', F(`${L.plf}${r}*${ref.pluma}*${ref.f27}`), CLP)
    set('tot', F(`${L.prev}${r}+${L.corr}${r}+${L.neu}${r}+${L.may}${r}+${L.tc8}${r}+${L.plc}${r}`), CLP)
    set('sic', Math.round(Number(c.preventivo) + Number(c.correctivo) + Number(c.neumaticos) + Number(c.mayores) + certTotal), CLP)
    set('dif', F(`${L.tot}${r}-${L.sic}${r}`), CLP)
    wq.getCell(r, C.tot).font = { bold: true }
  })
  const n = ordenados.length + 1
  const tr = n + 1
  wq.getCell(tr, 1).value = 'TOTAL (respeta el filtro)'
  wq.getRow(tr).font = { bold: true }
  for (const k of ['r23', 'r24', 'r25', 'r26', 'prev', 'corr', 'neu', 'may', 'tc8', 'plc', 'tot', 'sic', 'dif'] as const) {
    const cell = wq.getCell(tr, C[k]); cell.value = { formula: `SUBTOTAL(9,${L[k]}2:${L[k]}${n})` }; cell.numFmt = CLP
  }
  wq.views = [{ state: 'frozen', xSplit: 2, ySplit: 1 }]
  wq.autoFilter = { from: 'A1', to: `${col(C.pide)}1` }

  // ── Neumáticos ────────────────────────────────────────────────────────────
  const wn = wb.addWorksheet('Neumáticos')
  wn.getRow(1).values = ['Patente', 'Grupo', 'Real 2023', 'Real 2024', 'Real 2025', 'Real 2026 a la fecha', 'Promedio real 36 meses (pesos 2026)',
    'Con pauta', 'Ritmo (h/día)', 'Edad equivalente 2027', 'Piso (camión con uso)', 'NEUMÁTICOS 2027', 'SICOM 2027', 'Diferencia']
  encabezado(wn)
  ;[11, 22, 12, 12, 12, 12, 14, 8, 9, 9, 12, 14, 14, 11].forEach((w, i) => { wn.getColumn(i + 1).width = w })
  ordenados.forEach((c, i) => {
    const r = i + 2
    const rn = c.real_neumaticos ?? { '2023': 0, '2024': 0, '2025': 0, '2026': 0 }
    wn.getCell(r, 1).value = { formula: `Equipos!${L.pat}${r}` }
    wn.getCell(r, 2).value = { formula: `Equipos!${L.grupo}${r}` }
    const PN = `$A${r}`
    ;(['2023', '2024', '2025', '2026'] as const).forEach((y, j) => {
      const cl = wn.getCell(r, 3 + j)
      cl.value = T ? { formula: `SUMIFS(${cr('J')},${cr('A')},${PN},${cr('C')},${y},${cr('D')},"A3")` } : Number(rn[y])
      cl.numFmt = CLP
    })
    const base = wn.getCell(r, 7); base.numFmt = CLP
    if (T) base.value = { formula: `${sumaCompras(PN, 'A3', ref.i36)}/3` }
    else { base.value = Number(c.base.neumatico_base); dato(base) }
    wn.getCell(r, 8).value = { formula: `IF(Equipos!${L.kit}${r}<>"","Sí","No")` }
    wn.getCell(r, 9).value = { formula: `Equipos!${L.rit}${r}` }; wn.getCell(r, 9).numFmt = '0.00'
    wn.getCell(r, 10).value = { formula: `Equipos!${L.e27}${r}` }; wn.getCell(r, 10).numFmt = '0.0'
    const piso = wn.getCell(r, 11); piso.value = { formula: `IF(AND(H${r}="Sí",I${r}>=1,J${r}>=2),${ref.nmad},0)` }; piso.numFmt = CLP
    const tot = wn.getCell(r, 12); tot.value = { formula: `MAX(G${r},K${r})*${ref.f27}` }; tot.numFmt = CLP; tot.font = { bold: true }
    const s = wn.getCell(r, 13); s.value = Math.round(Number(c.neumaticos)); s.numFmt = CLP
    const d = wn.getCell(r, 14); d.value = { formula: `L${r}-M${r}` }; d.numFmt = CLP
  })
  wn.getCell(tr, 1).value = 'TOTAL (respeta el filtro)'
  wn.getRow(tr).font = { bold: true }
  ;['C', 'D', 'E', 'F', 'G', 'K', 'L', 'M', 'N'].forEach((cl) => {
    const cell = wn.getCell(`${cl}${tr}`); cell.value = { formula: `SUBTOTAL(9,${cl}2:${cl}${n})` }; cell.numFmt = CLP
  })
  wn.views = [{ state: 'frozen', xSplit: 1, ySplit: 1 }]
  wn.autoFilter = { from: 'A1', to: 'N1' }

  // ── Resumen ───────────────────────────────────────────────────────────────
  wr.getRow(1).values = ['Código', 'Línea', 'Bloque', 'Equipos 2027 (hoja Equipos)', 'Sin patente / flota 2027 (desde Compras)', 'TOTAL 2027', 'SICOM 2027', 'Diferencia', 'SICOM 2028', 'SICOM 2029']
  encabezado(wr)
  ;[8, 42, 24, 16, 16, 16, 16, 12, 16, 16].forEach((w, i) => { wr.getColumn(i + 1).width = w })
  const sumaEq = (k: keyof typeof C) => `SUM(Equipos!${L[k]}2:${L[k]}${n})`
  const formulaEquipos: Record<string, string> = {
    A1: sumaEq('prev'), A2: sumaEq('corr'), A3: sumaEq('neu'), A4: sumaEq('may'), B4: `${sumaEq('tc8')}+${sumaEq('plc')}`,
  }
  const filasLinea = p.lineas
  const rCont = filasLinea.findIndex((l) => l.codigo === 'E3') + 2
  filasLinea.forEach((l, i) => {
    const r = i + 2
    wr.getCell(r, 1).value = l.codigo; wr.getCell(r, 2).value = l.nombre; wr.getCell(r, 3).value = l.bloque
    const eq = wr.getCell(r, 4); eq.numFmt = CLP
    const fl = wr.getCell(r, 5); fl.numFmt = CLP
    const tot = wr.getCell(r, 6); tot.numFmt = CLP
    if (l.codigo === 'E3') {
      eq.value = 0
      fl.value = 0
      // Contingencia sobre las líneas anteriores, sin combustible (E3 va última: sin referencia circular).
      tot.value = { formula: `${ref.cont}*(SUM(F2:F${rCont - 1})-SUMIF(A2:A${rCont - 1},"D1",F2:F${rCont - 1}))` }
    } else {
      eq.value = formulaEquipos[l.codigo] ? { formula: formulaEquipos[l.codigo] } : 0
      const lineaF = (() => {
        if (!T) return null
        const s = (desde: string, crit = '') => `SUMIFS(${cr('L')},${cr('D')},"${l.codigo}",${cr('B')},">="&${desde},${cr('M')},"Sí"${crit})`
        if (LINEAS_12M.includes(l.codigo)) return `${s(ref.i12, `,${cr('N')},"No"`)}*${ref.f27}`
        if (LINEAS_24M.includes(l.codigo)) return `${s(ref.i24, `,${cr('N')},"No"`)}/2*${ref.f27}`
        if (l.codigo === 'B1') return `(${ref.seg}*12+${s(ref.i12, `,${cr('H')},"<>SERSEGSEG002"`)})*${ref.f27}`
        if (l.codigo === 'E1') return `(SUMIFS(${cr('L')},${cr('D')},"E1",${cr('M')},"Sí")+SUMIFS(${cr('L')},${cr('N')},"Sí",${cr('M')},"Sí"))/${ref.anios}*${ref.f27}`
        if (l.codigo === 'A4') return `MAX(SUMIFS(${cr('L')},${cr('D')},"A4",${cr('M')},"Sí")/${ref.anios}*${ref.f27}-D${r},0)`
        if (l.codigo === 'E2') return `SUM(${opexRango})`
        return null
      })()
      if (lineaF) fl.value = { formula: lineaF }
      else { fl.value = Number(l['2027']) - (formulaEquipos[l.codigo] ? Number(l['2027_equipos']) : 0); dato(fl) }
      tot.value = { formula: `D${r}+E${r}` }
    }
    tot.font = { bold: true }
    const s = wr.getCell(r, 7); s.value = Number(l['2027']); s.numFmt = CLP
    const d = wr.getCell(r, 8); d.value = { formula: `F${r}-G${r}` }; d.numFmt = CLP
    const s8 = wr.getCell(r, 9); s8.value = Number(l['2028']); s8.numFmt = CLP
    const s9 = wr.getCell(r, 10); s9.value = Number(l['2029']); s9.numFmt = CLP
  })
  const rt = filasLinea.length + 2
  wr.getCell(rt, 2).value = 'TOTAL'
  wr.getRow(rt).font = { bold: true }
  ;['D', 'E', 'F', 'G', 'H', 'I', 'J'].forEach((cl) => {
    const cell = wr.getCell(`${cl}${rt}`); cell.value = { formula: `SUM(${cl}2:${cl}${rt - 1})` }; cell.numFmt = CLP
  })
  wr.views = [{ state: 'frozen', ySplit: 1 }]

  // ── Preventivas hechas: pauta contra lo registrado y lo gastado ───────────
  const wh = wb.addWorksheet('Preventivas hechas')
  wh.getRow(1).values = ['Patente', 'Grupo', 'Grupo kit', 'Ritmo (h/día)', 'Intervalo (h)', 'La pauta pide al año', 'Visitas PPTO 2027',
    'Preventivas registradas 2025', 'Preventivas registradas 2026 a la fecha', '% hecho 2025',
    'Real preventivo 2023', 'Real preventivo 2024', 'Real preventivo 2025', 'Real preventivo 2026 a la fecha', 'PPTO preventivo 2027', 'Real total mantención 2025']
  encabezado(wh)
  ;[11, 22, 18, 9, 9, 10, 10, 12, 12, 9, 13, 13, 13, 13, 13, 14].forEach((w, i) => { wh.getColumn(i + 1).width = w })
  ordenados.forEach((c, i) => {
    const r = i + 2
    const ph: Record<string, number> = c.preventivas_hechas ?? {}
    const rp: Record<string, number> = c.real_preventivo ?? {}
    const visitas = [...NIVELES.map((_, j) => `Equipos!${col(C.v0 + j)}${r}`), `Equipos!${L.anual}${r}`].join('+')
    const vals: ExcelJS.CellValue[] = [
      { formula: `Equipos!${L.pat}${r}` }, { formula: `Equipos!${L.grupo}${r}` }, { formula: `IF(Equipos!${L.kit}${r}="","",Equipos!${L.kit}${r})` },
      { formula: `Equipos!${L.rit}${r}` }, { formula: `Equipos!${L.int}${r}` },
      { formula: `IF(E${r}="","",D${r}*365/E${r})` }, { formula: visitas },
      ...(T
        ? [2025, 2026].map((y) => ({ formula: `COUNTIFS('Preventivas registradas'!$A$2:$A$${regN},$A${r},'Preventivas registradas'!$C$2:$C$${regN},${y})` }))
        : [Number(ph['2025'] ?? 0), Number(ph['2026'] ?? 0)]),
      { formula: `IF(OR(F${r}="",F${r}=0),"",H${r}/F${r})` },
      ...(T
        ? [2023, 2024, 2025, 2026].map((y) => ({ formula: `SUMIFS(${cr('J')},${cr('A')},$A${r},${cr('C')},${y},${cr('D')},"A1")` }))
        : [Number(rp['2023'] ?? 0), Number(rp['2024'] ?? 0), Number(rp['2025'] ?? 0), Number(rp['2026'] ?? 0)]),
      { formula: `Equipos!${L.prev}${r}` }, { formula: `Equipos!${L.r25}${r}` },
    ]
    vals.forEach((v, j) => { wh.getCell(r, j + 1).value = v })
    wh.getCell(r, 4).numFmt = '0.0'; wh.getCell(r, 6).numFmt = '0.0'; wh.getCell(r, 7).numFmt = '0'
    wh.getCell(r, 10).numFmt = '0%'
    ;[11, 12, 13, 14, 15, 16].forEach((cc) => { wh.getCell(r, cc).numFmt = CLP })
  })
  wh.getCell(tr, 1).value = 'TOTAL (respeta el filtro)'
  wh.getRow(tr).font = { bold: true }
  ;['F', 'G', 'H', 'I', 'K', 'L', 'M', 'N', 'O', 'P'].forEach((cl) => {
    const cell = wh.getCell(`${cl}${tr}`); cell.value = { formula: `SUBTOTAL(9,${cl}2:${cl}${n})` }
    cell.numFmt = ['F', 'G', 'H', 'I'].includes(cl) ? '0' : CLP
  })
  wh.getCell(`J${tr}`).value = { formula: `IF(F${tr}=0,"",H${tr}/F${tr})` }; wh.getCell(`J${tr}`).numFmt = '0%'
  wh.views = [{ state: 'frozen', xSplit: 1, ySplit: 1 }]
  wh.autoFilter = { from: 'A1', to: 'P1' }

  const buf = await wb.xlsx.writeBuffer()
  return new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
}
