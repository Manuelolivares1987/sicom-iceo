'use client'

import { useMemo, useState } from 'react'
import {
  Activity, AlertTriangle, TrendingUp, TrendingDown,
  Gauge as GaugeIcon, Zap, Clock, Wrench,
} from 'lucide-react'
import {
  PieChart, Pie, Cell,
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
} from 'recharts'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { Modal } from '@/components/ui/modal'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  useFiabilidadFlota, useDetalleFiabilidadFlota, useMatrizEstadosFlota,
} from '@/hooks/use-fiabilidad'
import {
  CATEGORIA_LABELS,
  CATEGORIA_COLORS,
  type CategoriaUso,
  type ActivoFiabilidadDetalle,
} from '@/lib/services/fiabilidad'
import { todayISO } from '@/lib/utils'
import { copiarReporteFiabilidad } from '@/lib/reporte-fiabilidad-email'

// ─── Paleta ─────────────────────────────────────────────
// ─── Estados diarios de flota (Confiabilidad) ───────────
const ESTADO_COLORES: Record<string, string> = {
  A: '#16A34A', C: '#15803D', L: '#4F46E5', U: '#0891B2', D: '#2563EB',
  H: '#A855F7', R: '#06B6D4', M: '#F59E0B', T: '#FB923C', F: '#DC2626', V: '#9333EA',
}
const ESTADO_LABELS: Record<string, string> = {
  A: 'Arrendado', C: 'En contrato', D: 'Disponible', H: 'Habilitación', R: 'Recepción',
  M: 'Mantención', T: 'Taller', F: 'Fuera de servicio', V: 'Venta',
  U: 'Uso interno', L: 'Leasing',
}
const ESTADO_ORDEN = ['A', 'C', 'L', 'U', 'D', 'H', 'R', 'M', 'T', 'F', 'V']

// ─── Categorías de la torta/tabla: cada equipo se clasifica por su ESTADO del
// último día (un estado = una categoría). Es la vista que ve la organización. ──
const ESTADO_A_CATEGORIA: Record<string, string> = {
  A: 'Arriendo comercial', C: 'Contratos', D: 'Disponible', L: 'Leasing operativo',
  U: 'Uso interno', V: 'Venta', M: 'Mantención', T: 'Taller', F: 'Fuera de servicio',
  H: 'Habilitación', R: 'Recepción',
}
const CATEGORIA_ORDEN = [
  'Arriendo comercial', 'Contratos', 'Leasing operativo', 'Uso interno', 'Disponible',
  'Mantención', 'Taller', 'Fuera de servicio', 'Habilitación', 'Recepción', 'Venta',
]
const CATEGORIA_COLOR: Record<string, string> = {
  'Arriendo comercial': '#16A34A', 'Contratos': '#15803D', 'Leasing operativo': '#4F46E5',
  'Uso interno': '#0891B2', 'Disponible': '#2563EB', 'Mantención': '#F59E0B',
  'Taller': '#FB923C', 'Fuera de servicio': '#DC2626', 'Habilitación': '#A855F7',
  'Recepción': '#06B6D4', 'Venta': '#9333EA',
}

// ─── Helpers ───────────────────────────────────────────
const fmtPct = (v: number | null | undefined, digits = 1) =>
  v == null ? '—' : `${(Number(v) * 100).toFixed(digits)}%`
const fmtNum = (v: number | null | undefined, digits = 1) =>
  v == null ? '—' : Number(v).toFixed(digits)
const fmtInt = (v: number | null | undefined) => (v == null ? '—' : String(Math.round(Number(v))))

function colorOEE(v: number | null | undefined): string {
  if (v == null) return 'text-gray-500'
  if (v >= 0.85) return 'text-green-600 font-semibold'
  if (v >= 0.7) return 'text-blue-600'
  if (v >= 0.5) return 'text-amber-600'
  return 'text-red-600 font-semibold'
}

function colorOEEBar(v: number): string {
  if (v >= 0.85) return '#16A34A'
  if (v >= 0.7) return '#2563EB'
  if (v >= 0.5) return '#F59E0B'
  return '#DC2626'
}

function colorDispTxt(v: number): string {
  if (v >= 0.92) return 'text-green-600'
  if (v >= 0.85) return 'text-blue-600'
  if (v >= 0.75) return 'text-amber-600'
  return 'text-red-600'
}

// ────────────────────────────────────────────────────────
// Page
// ────────────────────────────────────────────────────────
// readOnly: oculta acciones de exportación (Copiar para Outlook). Se usa al
// embeber el reporte en la Vista Comercial, que es solo de lectura.
// Export NOMBRADO (no el default de la página) para poder reutilizarlo en otras
// rutas sin chocar con el tipo PageProps de Next.
export function FiabilidadAnalisis({ readOnly = false }: { readOnly?: boolean } = {}) {
  useRequireAuth()

  const hoy = new Date()
  const primerDiaMes = `${hoy.getFullYear()}-${String(hoy.getMonth() + 1).padStart(2, '0')}-01`
  const [fechaInicio, setFechaInicio] = useState(primerDiaMes)
  const [fechaFin, setFechaFin] = useState(todayISO())
  const [filtroCat, setFiltroCat] = useState<CategoriaUso | 'todas'>('todas')
  const [filtroEstado, setFiltroEstado] = useState<string | null>(null) // bucket de la torta
  const [equipoSel, setEquipoSel] = useState<string | null>(null)
  const [copiaMsg, setCopiaMsg] = useState<string | null>(null)

  const copiarParaCorreo = async () => {
    setCopiaMsg(null)
    try { setCopiaMsg(await copiarReporteFiabilidad(fechaInicio, fechaFin)) }
    catch (e) { setCopiaMsg((e as Error).message) }
  }

  // Exporta TODA la info por patente a Excel (lo visible en el detalle)
  async function exportarExcel(
    rows: Array<ActivoFiabilidadDetalle & {
      utilizacion?: number; reincidencias?: number; calidad_taller?: number; oee?: number
    }>,
  ) {
    const ExcelJS = (await import('exceljs')).default
    const wb = new ExcelJS.Workbook()
    const ws = wb.addWorksheet('Equipos')
    ws.columns = [
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
      { header: 'Estado (GPS)', key: 'estado_dia', width: 20 },
      { header: 'Zona', key: 'zona', width: 16 },
      { header: 'Ubicación', key: 'ubicacion', width: 18 },
      { header: 'Lugar físico', key: 'lugar_fisico', width: 26 },
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
    ws.getRow(1).font = { bold: true, color: { argb: 'FFFFFFFF' } }
    ws.getRow(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF1E3A8A' } }
    // Días por letra desde la matriz diaria (incluye todas las letras: A..V).
    // UP = A,C,L,U,D,V ; DOWN = M,T,F,R,H (down operacional, incluye recepción
    // y habilitación). Suma de letras = días observados.
    const cuentaPorActivo = new Map<string, Record<string, number>>()
    for (const c of matriz) {
      const r = cuentaPorActivo.get(c.activo_id) ?? {}
      r[c.estado_codigo] = (r[c.estado_codigo] ?? 0) + 1
      cuentaPorActivo.set(c.activo_id, r)
    }
    const DOWN_LETRAS = new Set(['M', 'T', 'F', 'R', 'H'])
    for (const e of rows) {
      const code = estadoActualPorActivo.get(e.activo_id)
      const cuenta = cuentaPorActivo.get(e.activo_id) ?? {}
      const porLetra = Object.fromEntries(ESTADO_ORDEN.map((s) => [`dias_${s.toLowerCase()}`, cuenta[s] ?? 0]))
      const upCalc = ESTADO_ORDEN.reduce((a, s) => a + (DOWN_LETRAS.has(s) ? 0 : (cuenta[s] ?? 0)), 0)
      const downCalc = ESTADO_ORDEN.reduce((a, s) => a + (DOWN_LETRAS.has(s) ? (cuenta[s] ?? 0) : 0), 0)
      const totalLetras = upCalc + downCalc
      ws.addRow({
        ...e,
        ...porLetra,
        dias_up: upCalc,
        dias_down: downCalc,
        dias_letras_total: totalLetras,
        cuadre: totalLetras === Number(e.dias_observados) ? 'OK' : `≠ (${totalLetras}/${e.dias_observados})`,
        estado_dia: code ? `${code} — ${ESTADO_LABELS[code] ?? code}` : '—',
        contratos_dias_txt: (e.contratos_dias ?? []).map((c) => `${c.codigo}: ${c.dias} d`).join('; '),
        disp_inh: Math.round(Number(e.disponibilidad_inherente) * 100),
        disp_fis: Math.round(Number(e.disponibilidad_fisica) * 100),
        util_pct: e.utilizacion != null ? Math.round(e.utilizacion * 100) : '',
        reincidencias: e.reincidencias ?? 0,
        cal_taller_pct: e.calidad_taller != null ? Math.round(e.calidad_taller * 100) : '',
        oee_pct: e.oee != null ? Math.round(e.oee * 100) : '',
      })
    }
    ws.autoFilter = { from: 'A1', to: { row: 1, column: ws.columnCount } }
    ws.views = [{ state: 'frozen', ySplit: 1 }]
    const buf = await wb.xlsx.writeBuffer()
    const blob = new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `fiabilidad_equipos_${fechaInicio}_a_${fechaFin}.xlsx`
    a.click()
    URL.revokeObjectURL(url)
  }

  const { data: porCategoria = [], isLoading: loadingCat } =
    useFiabilidadFlota(fechaInicio, fechaFin)
  const { data: detalles = [], isLoading: loadingDetalle } =
    useDetalleFiabilidadFlota(fechaInicio, fechaFin)
  const { data: matriz = [], isLoading: loadingMatriz } =
    useMatrizEstadosFlota(fechaInicio, fechaFin)

  // Comparación: "resto del año" = 1-ene al día anterior al período seleccionado
  const compIni = `${fechaInicio.slice(0, 4)}-01-01`
  const compFin = (() => {
    const d = new Date(fechaInicio + 'T00:00:00'); d.setDate(d.getDate() - 1)
    return d.toISOString().slice(0, 10)
  })()
  const { data: porCategoriaComp = [] } = useFiabilidadFlota(
    compFin >= compIni ? compIni : fechaInicio,
    compFin >= compIni ? compFin : fechaInicio,
  )

  // ─── Agregados globales ────────────────────────────────
  const kpiGlobal = useMemo(() => {
    if (porCategoria.length === 0) return null
    const acc = porCategoria.reduce(
      (a, c) => ({
        total_equipos: a.total_equipos + Number(c.total_equipos),
        dias_equipo: a.dias_equipo + Number(c.dias_equipo),
        dias_up: a.dias_up + Number(c.dias_up),
        dias_down: a.dias_down + Number(c.dias_down),
        eventos_falla_total: a.eventos_falla_total + Number(c.eventos_falla_total),
      }),
      { total_equipos: 0, dias_equipo: 0, dias_up: 0, dias_down: 0, eventos_falla_total: 0 },
    )
    const disp = acc.dias_equipo > 0 ? acc.dias_up / acc.dias_equipo : 0
    const mtbf = acc.eventos_falla_total > 0 ? acc.dias_up / acc.eventos_falla_total : acc.dias_up
    // MTTR agregado = Σ(días M+T) / Σeventos = Σ(mttr_cat × eventos_cat) / Σeventos
    const mttrW = porCategoria.reduce((s, c) => s + Number(c.mttr_agregado) * Number(c.eventos_falla_total), 0)
    const mttr = acc.eventos_falla_total > 0 ? mttrW / acc.eventos_falla_total : 0
    return { ...acc, disp_fisica: disp, mtbf, mttr }
  }, [porCategoria])

  // KPIs del "resto del año" para comparar
  const kpiComparacion = useMemo(() => {
    if (porCategoriaComp.length === 0) return null
    const acc = porCategoriaComp.reduce(
      (a, c) => ({
        dias_equipo: a.dias_equipo + Number(c.dias_equipo),
        dias_up: a.dias_up + Number(c.dias_up),
        dias_down: a.dias_down + Number(c.dias_down),
        eventos: a.eventos + Number(c.eventos_falla_total),
      }),
      { dias_equipo: 0, dias_up: 0, dias_down: 0, eventos: 0 },
    )
    const disp = acc.dias_equipo > 0 ? acc.dias_up / acc.dias_equipo : 0
    const mtbf = acc.eventos > 0 ? acc.dias_up / acc.eventos : acc.dias_up
    const mttrW = porCategoriaComp.reduce((s, c) => s + Number(c.mttr_agregado) * Number(c.eventos_falla_total), 0)
    const mttr = acc.eventos > 0 ? mttrW / acc.eventos : 0
    return { disp_fisica: disp, mtbf, mttr, dias_up: acc.dias_up, dias_down: acc.dias_down }
  }, [porCategoriaComp])

  // Disponibilidad Inherente de la flota — CONGELADA = Disp. Física mientras se
  // validan los indicadores (la fórmula real sería MTBF/(MTBF+MTTR)).
  const dispInhFlota = useMemo(() => {
    if (!kpiGlobal) return 0
    return kpiGlobal.disp_fisica
  }, [kpiGlobal])


  // ─── Días con datos + estado actual por activo (último día) ──
  const diasUnicos = useMemo(
    () => Array.from(new Set(matriz.map((c) => c.fecha))).sort(),
    [matriz],
  )
  // Solo los equipos de la tabla detalle (vehículos de flota). Se excluyen
  // surtidores/bombas/estanques para que TODOS los gráficos (torta + barras)
  // usen el mismo universo y la flota se vea constante día a día.
  const idsFlota = useMemo(() => new Set(detalles.map((d) => d.activo_id)), [detalles])

  const estadoActualPorActivo = useMemo(() => {
    const m = new Map<string, string>()
    if (diasUnicos.length === 0) return m
    const ultimo = diasUnicos[diasUnicos.length - 1]
    for (const c of matriz) {
      if (c.fecha === ultimo && idsFlota.has(c.activo_id)) m.set(c.activo_id, c.estado_codigo)
    }
    return m
  }, [matriz, diasUnicos, idsFlota])

  // Días en estado 'C' (en contrato) por activo — no viene en el detalle (OEE),
  // se cuenta desde la matriz. Cuenta como utilización (A + L + C).
  const diasCporActivo = useMemo(() => {
    const m = new Map<string, number>()
    for (const c of matriz) {
      if (c.estado_codigo === 'C' && idsFlota.has(c.activo_id)) {
        m.set(c.activo_id, (m.get(c.activo_id) ?? 0) + 1)
      }
    }
    return m
  }, [matriz, idsFlota])

  // ── Calidad del trabajo (taller): penaliza FALLAS REPETIDAS en el mismo mes ──
  // Una "falla" = un episodio (racha de días consecutivos) en estado M/T/F. Si en
  // un mismo mes calendario hay 2+ episodios, los extra son "reincidencias" y
  // bajan la nota. Calidad = fallas_primarias ÷ fallas_totales (1 si no hay fallas).
  const tallerPorActivo = useMemo(() => {
    const downByActivo = new Map<string, string[]>()
    for (const c of matriz) {
      if ((c.estado_codigo === 'M' || c.estado_codigo === 'T' || c.estado_codigo === 'F') && idsFlota.has(c.activo_id)) {
        const arr = downByActivo.get(c.activo_id) ?? []
        arr.push(c.fecha.slice(0, 10))
        downByActivo.set(c.activo_id, arr)
      }
    }
    const res = new Map<string, { fallas: number; reincidencias: number; calidad: number }>()
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
      res.set(id, { fallas, reincidencias: fallas - primarias, calidad: fallas > 0 ? primarias / fallas : 1 })
    })
    return res
  }, [matriz, idsFlota])

  // OEE (único, lente del taller) = Disp. Técnica × Calidad del trabajo.
  // La Utilización (A+L+C) es comercial → se muestra aparte, NO entra al OEE.
  const detallesCalc = useMemo(() => detalles.map((d) => {
    const diasC = diasCporActivo.get(d.activo_id) ?? 0
    const dispFis = Number(d.disponibilidad_fisica ?? 0) // UP / Total (servidor, nueva def)
    const util = d.dias_observados > 0 ? (d.dias_a + d.dias_l + diasC) / d.dias_observados : 0
    const t = tallerPorActivo.get(d.activo_id)
    const calidadTaller = t?.calidad ?? 1
    return {
      ...d, dias_c: diasC, utilizacion: util,
      fallas_taller: t?.fallas ?? 0,
      reincidencias: t?.reincidencias ?? 0,
      calidad_taller: calidadTaller,
      oee: dispFis * calidadTaller,
    }
  }), [detalles, diasCporActivo, tallerPorActivo])

  // Utilización bruta de la flota = (A + L + C) ÷ días totales.
  const utilBruta = useMemo(() => {
    if (detallesCalc.length === 0) return 0
    const sumTotal = detallesCalc.reduce((s, d) => s + d.dias_observados, 0)
    const sumALC = detallesCalc.reduce((s, d) => s + d.dias_a + d.dias_l + d.dias_c, 0)
    return sumTotal > 0 ? sumALC / sumTotal : 0
  }, [detallesCalc])

  // ─── Filtrado por categoría (dropdown) / bucket de la torta (estado actual) ──
  const detallesFiltrados = useMemo(() => {
    let rows = detallesCalc
    if (filtroCat !== 'todas') rows = rows.filter((d) => d.categoria_uso === filtroCat)
    if (filtroEstado) {
      rows = rows.filter(
        (d) => ESTADO_A_CATEGORIA[estadoActualPorActivo.get(d.activo_id) ?? ''] === filtroEstado,
      )
    }
    return rows
  }, [detallesCalc, filtroCat, filtroEstado, estadoActualPorActivo])

  // ─── Rankings ──────────────────────────────────────────
  const top5Criticos = useMemo(
    () =>
      [...detalles]
        .filter((d) => d.dias_down > 0)
        .sort((a, b) => b.dias_down - a.dias_down)
        .slice(0, 5),
    [detalles],
  )

  const top5OEE = useMemo(
    () =>
      [...detallesCalc]
        .filter((d) => d.dias_observados > 0)
        .sort((a, b) => b.oee - a.oee)
        .slice(0, 5),
    [detallesCalc],
  )
  // Bottom 5 por Disponibilidad Inherente (peor confiabilidad): toda la flota
  // con datos, los 5 de menor disponibilidad inherente.
  const bottom5DispInh = useMemo(
    () =>
      [...detalles]
        .filter((d) => d.dias_observados > 0)
        .sort((a, b) => a.disponibilidad_inherente - b.disponibilidad_inherente)
        .slice(0, 5),
    [detalles],
  )

  // ─── Distribución diaria de estados ──
  const distribucionDiaria = useMemo(() => {
    const byDia: Record<string, Record<string, number>> = {}
    for (const c of matriz) {
      // Mismo universo que la torta/tabla: solo vehículos de flota.
      if (!idsFlota.has(c.activo_id)) continue
      const dia = (byDia[c.fecha] ??= {})
      dia[c.estado_codigo] = (dia[c.estado_codigo] ?? 0) + 1
    }
    return diasUnicos.map((f) => ({ dia: f.slice(8, 10), ...byDia[f] }))
  }, [matriz, diasUnicos, idsFlota])

  // ─── Distribución por estado (torta) — cada equipo en el bucket de su estado
  // del último día. Es la vista correcta para la organización. ──
  const distribucionCategoria = useMemo(() => {
    const counts: Record<string, number> = {}
    for (const est of Array.from(estadoActualPorActivo.values())) {
      const cat = ESTADO_A_CATEGORIA[est]
      if (cat) counts[cat] = (counts[cat] ?? 0) + 1
    }
    return CATEGORIA_ORDEN.filter((c) => counts[c]).map((c) => ({
      key: c, name: c, value: counts[c], color: CATEGORIA_COLOR[c],
    }))
  }, [estadoActualPorActivo])

  // ─── KPIs por Categoría — MISMA fuente que la torta: agrupa por el estado del
  // último día. Así el recuento de equipos coincide 1:1 con la torta. ──
  const kpisPorBucket = useMemo(() => {
    type Agg = { equipos: number; dias: number; up: number; mt: number; eventos: number; util: number }
    const g: Record<string, Agg> = {}
    for (const d of detallesCalc) {
      const est = estadoActualPorActivo.get(d.activo_id)
      const bucket = est ? ESTADO_A_CATEGORIA[est] : null
      if (!bucket) continue
      const a = (g[bucket] ??= { equipos: 0, dias: 0, up: 0, mt: 0, eventos: 0, util: 0 })
      a.equipos += 1
      a.dias += d.dias_observados
      a.up += d.dias_up                       // UP = A,C,L,U,D,V (servidor, nueva def)
      a.mt += d.dias_m + d.dias_t             // reparación con HH (para MTTR)
      a.eventos += d.eventos_falla
      a.util += d.dias_a + d.dias_l + d.dias_c
    }
    return CATEGORIA_ORDEN.filter((b) => g[b]).map((b) => {
      const a = g[b]
      return {
        bucket: b,
        color: CATEGORIA_COLOR[b],
        equipos: a.equipos,
        dias: a.dias,
        disp_fisica: a.dias > 0 ? a.up / a.dias : 0,
        utilizacion: a.dias > 0 ? a.util / a.dias : 0,
        eventos: a.eventos,
        mtbf: a.eventos > 0 ? a.up / a.eventos : a.up,
        mttr: a.eventos > 0 ? a.mt / a.eventos : 0,
      }
    })
  }, [detallesCalc, estadoActualPorActivo])
  const toggleBucket = (key: string) => setFiltroEstado((prev) => (prev === key ? null : key))

  // ─── Ranking por marca (según indicadores) ──
  const rankingMarcas = useMemo(() => {
    const byMarca = new Map<string, { marca: string; equipos: number; oeeSum: number; oeeN: number; up: number; dias: number }>()
    const EXCLUIR = /^(yale|ram)$/i
    for (const d of detalles) {
      if (EXCLUIR.test((d.marca ?? '').trim())) continue
      const m = d.marca ?? 'Sin marca'
      const x = byMarca.get(m) ?? { marca: m, equipos: 0, oeeSum: 0, oeeN: 0, up: 0, dias: 0 }
      x.equipos++
      if (d.oee_total != null) { x.oeeSum += Number(d.oee_total); x.oeeN++ }
      x.up += d.dias_up; x.dias += d.dias_observados
      byMarca.set(m, x)
    }
    return Array.from(byMarca.values())
      .map((x) => ({
        marca: x.marca,
        equipos: x.equipos,
        oee: x.oeeN > 0 ? x.oeeSum / x.oeeN : null,
        disp: x.dias > 0 ? x.up / x.dias : 0,
      }))
      .sort((a, b) => (b.oee ?? -1) - (a.oee ?? -1))
  }, [detalles])

  // ─── Historia del equipo seleccionado (modal) ──
  const equipoHistoria = useMemo(() => {
    if (!equipoSel) return null
    const estados: Record<string, string> = {}
    for (const c of matriz) if (c.activo_id === equipoSel) estados[c.fecha] = c.estado_codigo
    const det = detalles.find((d) => d.activo_id === equipoSel) ?? null
    return { det, estados }
  }, [equipoSel, matriz, detalles])

  const isLoading = loadingCat || loadingDetalle || loadingMatriz

  return (
    <div className="space-y-6">
      {/* ─── Header ───────────────────────────── */}
      <div className="rounded-2xl bg-gradient-to-r from-indigo-600 via-blue-600 to-cyan-600 p-6 text-white shadow-lg">
        <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
          <div>
            <h1 className="text-2xl font-bold flex items-center gap-2">
              <Activity className="h-7 w-7" />
              Análisis de Fiabilidad & OEE de Flota
            </h1>
            <p className="text-sm text-white/80 mt-1">
              MTBF · MTTR · Disponibilidad Inherente · OEE (A × P × Q) — metodología del análisis ejecutivo
            </p>
          </div>
          <div className="flex gap-2">
            <div>
              <label className="block text-[10px] uppercase text-white/70">Desde</label>
              <input
                type="date"
                className="h-9 rounded bg-white/95 px-2 text-sm text-gray-800"
                value={fechaInicio}
                onChange={(e) => setFechaInicio(e.target.value)}
              />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-white/70">Hasta</label>
              <input
                type="date"
                className="h-9 rounded bg-white/95 px-2 text-sm text-gray-800"
                value={fechaFin}
                onChange={(e) => setFechaFin(e.target.value)}
              />
            </div>
            {!readOnly && (
              <div className="flex items-end">
                <button
                  onClick={copiarParaCorreo}
                  className="h-9 rounded-lg bg-white/95 px-3 text-sm font-semibold text-indigo-700 hover:bg-white"
                  title="Copia el reporte con formato para pegarlo en Outlook"
                >
                  📋 Copiar para correo
                </button>
              </div>
            )}
          </div>
        </div>
        {copiaMsg && (
          <div className="mt-3 rounded-lg bg-white/15 px-3 py-2 text-sm text-white">{copiaMsg}</div>
        )}
      </div>

      {isLoading && (
        <div className="flex h-64 items-center justify-center">
          <Spinner className="h-8 w-8" />
        </div>
      )}

      {!isLoading && !kpiGlobal && (
        <Card>
          <CardContent className="py-10 text-center space-y-2">
            <AlertTriangle className="h-10 w-10 text-amber-500 mx-auto" />
            <h3 className="text-lg font-semibold text-gray-800">Sin datos en el período</h3>
            <p className="text-sm text-gray-500 max-w-lg mx-auto">
              Revisa que (1) las migraciones 40-42 estén aplicadas en Supabase,
              (2) el seed de categoría esté corrido y (3) haya filas en
              <code className="mx-1 rounded bg-gray-100 px-1 text-xs">estado_diario_flota</code>
              dentro del rango {fechaInicio} → {fechaFin}. Si todo está listo,
              mira la consola del navegador (F12 → Network) por errores 400/500
              en las llamadas <code className="text-xs">rpc/fn_calcular_fiabilidad_*</code>.
            </p>
          </CardContent>
        </Card>
      )}

      {!isLoading && kpiGlobal && (
        <>
          {/* ─── Evolución vs resto del año (primera mirada) ─── */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base text-gray-700">Evolución vs resto del año</CardTitle>
              <p className="text-[11px] text-gray-400">
                Período seleccionado comparado con el resto de {fechaInicio.slice(0, 4)} — ¿mejoramos o vamos más bajo?
              </p>
            </CardHeader>
            <CardContent>
              {!kpiComparacion ? (
                <p className="py-4 text-xs text-gray-400">Sin período de comparación (ajusta el rango de fechas).</p>
              ) : (
                <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
                  <CompTile label="Disponibilidad Física" actual={kpiGlobal.disp_fisica * 100} prev={kpiComparacion.disp_fisica * 100} unit="%" betterUp />
                  <CompTile label="Días DOWN (del total)" actual={(1 - kpiGlobal.disp_fisica) * 100} prev={(1 - kpiComparacion.disp_fisica) * 100} unit="%" betterUp={false} />
                  <CompTile label="MTBF" actual={kpiGlobal.mtbf} prev={kpiComparacion.mtbf} unit="d" betterUp />
                  <CompTile label="MTTR" actual={kpiGlobal.mttr} prev={kpiComparacion.mttr} unit="d" betterUp={false} />
                </div>
              )}
            </CardContent>
          </Card>

          {/* ─── KPI Tiles ───────────────────────── */}
          <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3">
            <KpiTile
              icon={<Zap className="h-4 w-4" />}
              label="Equipos"
              value={fmtInt(kpiGlobal.total_equipos)}
              tone="indigo"
            />
            <KpiTile
              icon={<Clock className="h-4 w-4" />}
              label="Días-Eq"
              value={fmtInt(kpiGlobal.dias_equipo)}
              tone="slate"
            />
            <KpiTile
              icon={<TrendingUp className="h-4 w-4" />}
              label="Días UP"
              value={fmtInt(kpiGlobal.dias_up)}
              tone="green"
            />
            <KpiTile
              icon={<TrendingDown className="h-4 w-4" />}
              label="Días DOWN"
              value={fmtInt(kpiGlobal.dias_down)}
              tone="red"
              hint={`${kpiGlobal.eventos_falla_total} eventos`}
            />
            <KpiTile
              icon={<Wrench className="h-4 w-4" />}
              label="MTBF"
              value={`${fmtNum(kpiGlobal.mtbf)} d`}
              tone="blue"
              hint="Media entre fallas"
            />
            <KpiTile
              icon={<AlertTriangle className="h-4 w-4" />}
              label="MTTR"
              value={`${fmtNum(kpiGlobal.mttr)} d`}
              tone="amber"
              hint="Media reparación"
            />
          </div>

          {/* ─── Gauges Disp Física + OEE + Util ──────────── */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <GaugeCard
              title="Disponibilidad Física"
              value={kpiGlobal.disp_fisica * 100}
              target={92}
              unit="%"
              description="Días operativos ÷ días totales · Meta ≥ 92%"
            />
            <GaugeCard
              title="Utilización Bruta"
              value={utilBruta * 100}
              target={70}
              unit="%"
              description="(Días A + C + L) ÷ días totales · Meta ≥ 70%"
            />
            <GaugeCard
              title="Disponibilidad Inherente"
              value={dispInhFlota * 100}
              target={90}
              unit="%"
              description="MTBF ÷ (MTBF + MTTR) · confiabilidad de la flota · Meta ≥ 90%"
            />
          </div>

          {/* ─── Distribución por estado + Distribución diaria ─── */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {/* Distribución por categoría (hoy) — filtro */}
            <Card>
              <CardHeader className="flex flex-col gap-2 pb-2 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <CardTitle className="text-base text-gray-700">
                    Distribución por estado{diasUnicos.length > 0 ? ` · ${diasUnicos[diasUnicos.length - 1]}` : ''}
                  </CardTitle>
                  <p className="text-[11px] text-gray-400">Equipos por estado del último día. Click para filtrar el detalle.</p>
                </div>
                {filtroEstado && (
                  <button className="text-xs text-blue-600 hover:underline" onClick={() => setFiltroEstado(null)}>
                    Limpiar filtro
                  </button>
                )}
              </CardHeader>
              <CardContent>
                <div className="h-56">
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie
                        data={distribucionCategoria}
                        cx="50%" cy="50%"
                        innerRadius={52} outerRadius={96}
                        paddingAngle={2}
                        dataKey="value"
                        cursor="pointer"
                        label={({ value }) => `${value}`}
                        onClick={(d: any) => d?.key && toggleBucket(d.key)}
                      >
                        {distribucionCategoria.map((e) => (
                          <Cell key={e.key} fill={e.color}
                            opacity={filtroEstado && filtroEstado !== e.key ? 0.3 : 1} />
                        ))}
                      </Pie>
                      <Tooltip formatter={(v: number, n: string) => [`${v} equipos`, n]} />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
                <div className="flex flex-wrap justify-center gap-x-3 gap-y-1">
                  {distribucionCategoria.map((e) => (
                    <button
                      key={e.key}
                      onClick={() => toggleBucket(e.key)}
                      className="flex items-center gap-1 text-[11px] text-gray-700 hover:underline"
                      style={{ opacity: filtroEstado && filtroEstado !== e.key ? 0.4 : 1 }}
                    >
                      <span className="inline-block h-3 w-3 rounded-sm" style={{ background: e.color }} />
                      {e.name}: <b>{e.value}</b>
                    </button>
                  ))}
                </div>
              </CardContent>
            </Card>

            {/* Distribución diaria de estados de la flota */}
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base text-gray-700">
                  Distribución diaria de estados de la flota
                </CardTitle>
                <p className="text-[11px] text-gray-400">
                  Equipos por estado, día a día — del Excel de Confiabilidad al sistema
                </p>
              </CardHeader>
              <CardContent>
                <div className="h-72">
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={distribucionDiaria} margin={{ top: 6, right: 6, bottom: 4, left: -16 }}>
                      <CartesianGrid strokeDasharray="3 3" vertical={false} />
                      <XAxis dataKey="dia" tick={{ fontSize: 9 }} interval={0} />
                      <YAxis tick={{ fontSize: 10 }} allowDecimals={false} />
                      <Tooltip
                        formatter={(v: number, n: string) => [`${v} eq`, ESTADO_LABELS[n] ?? n]}
                        labelFormatter={(l) => `Día ${l}`}
                      />
                      {ESTADO_ORDEN.map((e) => (
                        <Bar key={e} dataKey={e} stackId="estados" fill={ESTADO_COLORES[e]} name={e} />
                      ))}
                    </BarChart>
                  </ResponsiveContainer>
                </div>
                <div className="flex flex-wrap gap-x-3 gap-y-1 mt-2 justify-center">
                  {ESTADO_ORDEN.map((e) => (
                    <span key={e} className="flex items-center gap-1 text-[10px] text-gray-600">
                      <span className="inline-block w-3 h-3 rounded-sm" style={{ background: ESTADO_COLORES[e] }} />
                      {e} · {ESTADO_LABELS[e]}
                    </span>
                  ))}
                </div>
              </CardContent>
            </Card>
          </div>

          {/* ─── Rankings (Bar charts horizontales) ─── */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
            <RankingBarCard
              title="Top 5 Críticos (DOWN)"
              icon={<AlertTriangle className="h-4 w-4 text-red-600" />}
              borderClass="border-red-200"
              data={top5Criticos.map((d) => ({
                patente: d.patente,
                valor: d.dias_down,
                color: '#DC2626',
              }))}
              labelUnit="días"
            />
            <RankingBarCard
              title="Top 5 OEE"
              icon={<TrendingUp className="h-4 w-4 text-green-600" />}
              borderClass="border-green-200"
              data={top5OEE.map((d) => ({
                patente: d.patente,
                valor: Math.round(d.oee * 100),
                color: colorOEEBar(d.oee),
              }))}
              labelUnit="%"
            />
            <RankingBarCard
              title="Bottom 5 Disponibilidad Inherente"
              icon={<TrendingDown className="h-4 w-4 text-amber-600" />}
              borderClass="border-amber-200"
              data={bottom5DispInh.map((d) => ({
                patente: d.patente,
                valor: Math.round(d.disponibilidad_inherente * 100),
                color: colorOEEBar(d.disponibilidad_inherente),
              }))}
              labelUnit="%"
            />
          </div>

          {/* ─── Ranking de marcas ─── */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base text-gray-700">Ranking de marcas por desempeño</CardTitle>
              <p className="text-[11px] text-gray-400">Promedio de OEE y disponibilidad física por marca de vehículo (mejor a peor)</p>
            </CardHeader>
            <CardContent className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
                    <th className="px-2 py-2">#</th>
                    <th className="px-2 py-2">Marca</th>
                    <th className="px-2 py-2 text-right">Equipos</th>
                    <th className="px-2 py-2 text-right">OEE prom.</th>
                    <th className="px-2 py-2 text-right">Disp. física prom.</th>
                  </tr>
                </thead>
                <tbody>
                  {rankingMarcas.map((m, i) => (
                    <tr key={m.marca} className="border-b hover:bg-gray-50">
                      <td className="px-2 py-1.5 text-gray-400">{i + 1}</td>
                      <td className="px-2 py-1.5 font-semibold">{m.marca}</td>
                      <td className="px-2 py-1.5 text-right">{m.equipos}</td>
                      <td className={`px-2 py-1.5 text-right ${colorOEE(m.oee)}`}>
                        {m.oee == null ? 'N/A' : fmtPct(m.oee)}
                      </td>
                      <td className={`px-2 py-1.5 text-right ${colorDispTxt(m.disp)}`}>
                        {fmtPct(m.disp)}
                      </td>
                    </tr>
                  ))}
                  {rankingMarcas.length === 0 && (
                    <tr><td colSpan={5} className="py-6 text-center text-gray-400">Sin datos</td></tr>
                  )}
                </tbody>
              </table>
            </CardContent>
          </Card>

          {/* ─── KPIs por Categoría (mismo recuento que la torta: por estado actual) ─── */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base text-gray-700">KPIs por Categoría</CardTitle>
              <p className="text-[11px] text-gray-400">
                Cada equipo se cuenta en la categoría de su estado del último día (coincide con la torta).
              </p>
            </CardHeader>
            <CardContent className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b bg-gray-50 text-left text-gray-500 uppercase">
                    <th className="px-2 py-2">Categoría</th>
                    <th className="px-2 py-2 text-right">Equipos</th>
                    <th className="px-2 py-2 text-right">Días-Eq</th>
                    <th className="px-2 py-2 text-right">Disp. Física</th>
                    <th className="px-2 py-2 text-right">Util. (A+L+C)</th>
                    <th className="px-2 py-2 text-right">N° Fallas</th>
                    <th className="px-2 py-2 text-right">MTBF (d)</th>
                    <th className="px-2 py-2 text-right">MTTR (d)</th>
                  </tr>
                </thead>
                <tbody>
                  {kpisPorBucket.map((c) => (
                    <tr key={c.bucket} className="border-b hover:bg-gray-50">
                      <td className="px-2 py-2">
                        <span className="inline-flex items-center gap-1.5">
                          <span className="inline-block h-3 w-3 rounded-sm" style={{ background: c.color }} />
                          {c.bucket}
                        </span>
                      </td>
                      <td className="px-2 py-2 text-right font-semibold">{c.equipos}</td>
                      <td className="px-2 py-2 text-right">{c.dias}</td>
                      <td className={`px-2 py-2 text-right font-semibold ${colorDispTxt(c.disp_fisica)}`}>
                        {fmtPct(c.disp_fisica)}
                      </td>
                      <td className="px-2 py-2 text-right">{fmtPct(c.utilizacion)}</td>
                      <td className="px-2 py-2 text-right">{c.eventos}</td>
                      <td className="px-2 py-2 text-right">{fmtNum(c.mtbf)}</td>
                      <td className="px-2 py-2 text-right">{fmtNum(c.mttr)}</td>
                    </tr>
                  ))}
                  {kpisPorBucket.length === 0 && (
                    <tr><td colSpan={8} className="py-6 text-center text-gray-400">Sin datos en el período</td></tr>
                  )}
                </tbody>
              </table>
            </CardContent>
          </Card>

          {/* ─── Tabla detalle ─── */}
          <Card>
            <CardHeader className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
              <CardTitle className="text-base text-gray-700">
                Detalle por Equipo
                {filtroCat !== 'todas' && (
                  <span className="ml-2 text-xs text-gray-500">
                    · filtro: {CATEGORIA_LABELS[filtroCat as CategoriaUso]}
                  </span>
                )}
              </CardTitle>
              <div className="flex items-center gap-2">
                <select
                  className="h-9 rounded border border-gray-300 px-2 text-sm"
                  value={filtroCat}
                  onChange={(e) => setFiltroCat(e.target.value as CategoriaUso | 'todas')}
                >
                  <option value="todas">Todas las categorías</option>
                  <option value="arriendo_comercial">Arriendo Comercial</option>
                  <option value="leasing_operativo">Leasing Operativo</option>
                  <option value="uso_interno">Uso Interno</option>
                  <option value="venta">Venta</option>
                </select>
                <button
                  onClick={() => exportarExcel(detallesFiltrados)}
                  disabled={detallesFiltrados.length === 0}
                  className="inline-flex h-9 items-center gap-1.5 rounded-lg bg-green-600 px-3 text-sm font-semibold text-white hover:bg-green-700 disabled:opacity-50"
                  title="Exporta toda la información de cada patente a Excel"
                >
                  ⬇ Exportar a Excel ({detallesFiltrados.length})
                </button>
              </div>
            </CardHeader>
            <CardContent className="overflow-x-auto">
              <table className="w-full text-xs whitespace-nowrap">
                <thead>
                  <tr className="border-b bg-gray-50 text-left text-gray-500 uppercase">
                    <th className="px-2 py-2">Patente</th>
                    <th className="px-2 py-2">Equipamiento</th>
                    <th className="px-2 py-2">Cliente</th>
                    <th className="px-2 py-2">Categoría</th>
                    <th className="px-2 py-2 text-right">Tot</th>
                    <th className="px-2 py-2 text-right">A</th>
                    <th className="px-2 py-2 text-right">D</th>
                    <th className="px-2 py-2 text-right">U</th>
                    <th className="px-2 py-2 text-right">L</th>
                    <th className="px-2 py-2 text-right">M</th>
                    <th className="px-2 py-2 text-right">T</th>
                    <th className="px-2 py-2 text-right">F</th>
                    <th className="px-2 py-2 text-right">UP</th>
                    <th className="px-2 py-2 text-right">DOWN</th>
                    <th className="px-2 py-2 text-right">N°Fal</th>
                    <th className="px-2 py-2 text-right">MTBF</th>
                    <th className="px-2 py-2 text-right">MTTR</th>
                    <th className="px-2 py-2 text-right" title="Disponibilidad Física = UP ÷ Total (UP = A,C,L,U,D,V)">Disp.Fís</th>
                    <th className="px-2 py-2 text-right" title="Disponibilidad Inherente = MTBF ÷ (MTBF+MTTR)">Disp.Inh</th>
                    <th className="px-2 py-2 text-right" title="Utilización comercial = (A+L+C)/Total — informativa, NO entra al OEE">Util</th>
                    <th className="px-2 py-2 text-right" title="Fallas repetidas en el mismo mes (reincidencia)">Rep/mes</th>
                    <th className="px-2 py-2 text-right" title="Calidad del trabajo (penaliza reincidencia)">Cal.T</th>
                    <th className="px-2 py-2 text-right" title="OEE = Disp. Técnica × Calidad del trabajo">OEE</th>
                  </tr>
                </thead>
                <tbody>
                  {detallesFiltrados.map((d) => (
                    <tr key={d.activo_id} className="border-b hover:bg-gray-50">
                      <td className="px-2 py-1.5">
                        <button
                          onClick={() => setEquipoSel(d.activo_id)}
                          className="font-mono font-semibold text-blue-600 hover:underline"
                          title="Ver historia mensual del equipo"
                        >
                          {d.patente}
                        </button>
                      </td>
                      <td className="px-2 py-1.5">{d.equipamiento ?? '—'}</td>
                      <td className="px-2 py-1.5 text-gray-500 max-w-[160px] truncate">
                        {d.contrato_cliente ?? d.cliente_actual ?? d.ult_cliente ?? '—'}
                      </td>
                      <td className="px-2 py-1.5">
                        {d.categoria_uso ? (
                          <Badge className={CATEGORIA_COLORS[d.categoria_uso]}>
                            {CATEGORIA_LABELS[d.categoria_uso]}
                          </Badge>
                        ) : (
                          <span className="text-gray-400 italic">—</span>
                        )}
                      </td>
                      <td className="px-2 py-1.5 text-right">{d.dias_observados}</td>
                      <td className="px-2 py-1.5 text-right">{d.dias_a}</td>
                      <td className="px-2 py-1.5 text-right">{d.dias_d}</td>
                      <td className="px-2 py-1.5 text-right">{d.dias_u}</td>
                      <td className="px-2 py-1.5 text-right">{d.dias_l}</td>
                      <td className="px-2 py-1.5 text-right text-amber-700">{d.dias_m}</td>
                      <td className="px-2 py-1.5 text-right text-amber-700">{d.dias_t}</td>
                      <td className="px-2 py-1.5 text-right text-red-700">{d.dias_f}</td>
                      <td className="px-2 py-1.5 text-right text-green-700">{d.dias_up}</td>
                      <td className="px-2 py-1.5 text-right text-red-700">{d.dias_down}</td>
                      <td className="px-2 py-1.5 text-right">{d.eventos_falla}</td>
                      <td className="px-2 py-1.5 text-right">{fmtNum(d.mtbf_dias)}</td>
                      <td className="px-2 py-1.5 text-right">{fmtNum(d.mttr_dias)}</td>
                      <td className={`px-2 py-1.5 text-right font-semibold ${colorDispTxt(d.disponibilidad_fisica)}`}>
                        {fmtPct(d.disponibilidad_fisica, 0)}
                      </td>
                      <td className={`px-2 py-1.5 text-right ${colorDispTxt(d.disponibilidad_inherente)}`}>
                        {fmtPct(d.disponibilidad_inherente, 0)}
                      </td>
                      <td className="px-2 py-1.5 text-right text-gray-500">{fmtPct(d.utilizacion, 0)}</td>
                      <td className="px-2 py-1.5 text-right">
                        {d.reincidencias > 0
                          ? <span className="font-semibold text-red-600">{d.reincidencias}</span>
                          : <span className="text-gray-400">0</span>}
                      </td>
                      <td className={`px-2 py-1.5 text-right ${d.calidad_taller < 1 ? 'text-amber-700 font-medium' : ''}`}>
                        {fmtPct(d.calidad_taller, 0)}
                      </td>
                      <td className={`px-2 py-1.5 text-right font-semibold ${colorOEE(d.oee)}`}>
                        {fmtPct(d.oee)}
                      </td>
                    </tr>
                  ))}
                  {detallesFiltrados.length === 0 && (
                    <tr>
                      <td colSpan={23} className="py-6 text-center text-gray-400">
                        Sin equipos en esa categoría con datos en el período
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
              <div className="mt-2 space-y-1 text-[11px] text-gray-400">
                <p>
                  Columnas día-estado (nº de días): A=Arrendado · D=Disponible · U=Uso Interno · L=Leasing · M=Mantención (&gt;1d) · T=Taller (&lt;1d) · F=Fuera de Servicio.
                  <b className="text-gray-600"> UP (operativo)</b> = A,C,L,U,D,V · <b className="text-gray-600">DOWN (no disponible)</b> = M,T,F,R,H (Habilitación y Recepción bajan la disponibilidad).
                </p>
                <p>
                  <b className="text-gray-600">OEE = Disponibilidad Física × Calidad del trabajo</b> (la utilización es comercial y NO entra al OEE):
                </p>
                <ul className="ml-3 list-disc space-y-0.5">
                  <li><b className="text-gray-600">Disp. Física</b> = UP ÷ Total.</li>
                  <li><b className="text-gray-600">MTBF</b> = UP ÷ nº fallas · <b className="text-gray-600">MTTR</b> = (M + T) ÷ nº fallas (solo reparación con HH; F no es reparación) · <b className="text-gray-600">Disp. Inherente</b> = MTBF ÷ (MTBF+MTTR).</li>
                  <li><b className="text-gray-600">Cal.T — Calidad del trabajo</b> = fallas primarias ÷ fallas totales. Cada reincidencia la baja.</li>
                  <li><b className="text-gray-600">Rep/mes</b> = fallas que se repiten dentro del mismo mes (cada episodio M/T/F extra en un mes).</li>
                  <li><b className="text-gray-600">Util</b> = utilización comercial = (A + L + C) ÷ Total. Informativa, no afecta el OEE.</li>
                </ul>
              </div>
            </CardContent>
          </Card>

          {/* ─── Glosario: qué significa cada indicador (abajo) ─── */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base text-gray-700">¿Qué significa cada indicador y cómo se calcula?</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid gap-3 text-xs text-gray-600 sm:grid-cols-2 lg:grid-cols-3">
                <div><b className="text-gray-800">Días-Equipo</b> — total de días observados sumando todos los equipos.<br /><span className="text-gray-400">= Σ (equipos × días del período)</span></div>
                <div><b className="text-gray-800">Días UP (operativo)</b> — días en que el equipo pudo operar.<br /><span className="text-gray-400">Estados A, C, L, U, D, V</span></div>
                <div><b className="text-gray-800">Días DOWN (no disponible)</b> — días detenido o en preparación.<br /><span className="text-gray-400">Estados M, T, F, R, H</span></div>
                <div><b className="text-gray-800">Disponibilidad Física</b> — % del tiempo operativo.<br /><span className="text-gray-400">= Días UP ÷ Días-Equipo</span></div>
                <div><b className="text-gray-800">Utilización Bruta</b> — % del tiempo generando ingreso.<br /><span className="text-gray-400">= (Días A + C + L) ÷ Días-Equipo</span></div>
                <div><b className="text-gray-800">OEE</b> — eficiencia del equipo desde la gestión del taller.<br /><span className="text-gray-400">= Disp. Física × Calidad del trabajo</span></div>
                <div><b className="text-gray-800">Utilización</b> — % de días en arriendo (comercial, no entra al OEE).<br /><span className="text-gray-400">= (A + L + C) ÷ Total</span></div>
                <div><b className="text-gray-800">MTBF</b> — días operativo promedio entre fallas.<br /><span className="text-gray-400">= Días UP ÷ nº de fallas (falla = M/T/F)</span></div>
                <div><b className="text-gray-800">MTTR</b> — días promedio de reparación (con HH).<br /><span className="text-gray-400">= (M + T) ÷ nº de fallas. F (sin HH) no es reparación.</span></div>
                <div><b className="text-gray-800">Disponibilidad Inherente</b> — disponibilidad por confiabilidad.<br /><span className="text-gray-400">= MTBF ÷ (MTBF + MTTR)</span></div>
                <div><b className="text-gray-800">Calidad del trabajo (Cal.T)</b> — castiga fallas repetidas en el mismo mes.<br /><span className="text-gray-400">= fallas primarias ÷ fallas totales</span></div>
                <div><b className="text-gray-800">Rep/mes</b> — fallas que se repiten dentro del mismo mes (reincidencia). Cada episodio M/T/F extra en un mes.</div>
              </div>
            </CardContent>
          </Card>
        </>
      )}

      {/* ─── Modal: historia mensual del equipo ─── */}
      <Modal
        open={!!equipoSel}
        onClose={() => setEquipoSel(null)}
        title={equipoHistoria?.det ? `Historia mensual · ${equipoHistoria.det.patente}` : 'Historia del equipo'}
      >
        {equipoHistoria && (
          <div className="space-y-4">
            <div className="text-sm text-gray-600">
              {[equipoHistoria.det?.marca, equipoHistoria.det?.modelo, equipoHistoria.det?.equipamiento]
                .filter(Boolean).join(' · ') || '—'}
            </div>

            {/* Último contrato + dónde está */}
            {equipoHistoria.det && (
              <div className="grid gap-2 sm:grid-cols-2">
                <div className="rounded-lg border border-blue-100 bg-blue-50/50 p-2.5 text-xs">
                  <div className="text-[10px] uppercase tracking-wide text-gray-400">Último contrato</div>
                  <div className="font-semibold text-gray-800">
                    {[equipoHistoria.det.contrato_codigo, equipoHistoria.det.contrato_cliente ?? equipoHistoria.det.cliente_actual]
                      .filter(Boolean).join(' · ') || '—'}
                  </div>
                </div>
                <div className="rounded-lg border border-blue-100 bg-blue-50/50 p-2.5 text-xs">
                  <div className="text-[10px] uppercase tracking-wide text-gray-400">📍 Dónde está</div>
                  <div className="font-semibold text-gray-800">
                    {equipoHistoria.det.lugar_fisico ?? equipoHistoria.det.ubicacion ?? 'Sin registrar'}
                  </div>
                </div>
              </div>
            )}

            {/* Ficha técnica (planilla Data Equipo) */}
            {equipoHistoria.det && (
              <div className="grid grid-cols-2 gap-x-4 gap-y-1.5 rounded-lg border bg-gray-50 p-3 text-xs sm:grid-cols-3">
                <FichaCampo label="Patente"      value={equipoHistoria.det.patente} mono />
                <FichaCampo label="Marca"        value={equipoHistoria.det.marca} />
                <FichaCampo label="Modelo"       value={equipoHistoria.det.modelo} />
                <FichaCampo label="Equipamiento" value={equipoHistoria.det.equipamiento} />
                <FichaCampo label="Capacidad"    value={equipoHistoria.det.capacidad} />
                <FichaCampo label="Año"          value={equipoHistoria.det.anio_fabricacion != null ? String(equipoHistoria.det.anio_fabricacion) : null} />
                <FichaCampo label="Potencia (CV)" value={equipoHistoria.det.potencia} />
                <FichaCampo label="VIN (Chasis)" value={equipoHistoria.det.vin_chasis} mono />
                <FichaCampo label="N° Motor"     value={equipoHistoria.det.numero_motor} mono />
              </div>
            )}

            <div className="flex flex-wrap gap-0.5">
              {diasUnicos.map((f) => {
                const e = equipoHistoria.estados[f]
                return (
                  <div key={f} className="flex flex-col items-center">
                    <div className="text-[8px] text-gray-400">{f.slice(8, 10)}</div>
                    <div
                      className="h-5 w-5 text-center text-[10px] font-semibold leading-5"
                      style={{ background: e ? ESTADO_COLORES[e] : '#F3F4F6', color: e ? '#fff' : '#D1D5DB' }}
                      title={e ? `${f}: ${ESTADO_LABELS[e]}` : f}
                    >
                      {e ?? ''}
                    </div>
                  </div>
                )
              })}
            </div>

            <div className="flex flex-wrap gap-x-3 gap-y-1 text-xs">
              {(() => {
                const counts: Record<string, number> = {}
                for (const f of diasUnicos) { const e = equipoHistoria.estados[f]; if (e) counts[e] = (counts[e] ?? 0) + 1 }
                return ESTADO_ORDEN.filter((e) => counts[e]).map((e) => (
                  <span key={e} className="flex items-center gap-1 text-gray-700">
                    <span className="inline-block h-3 w-3 rounded-sm" style={{ background: ESTADO_COLORES[e] }} />
                    {ESTADO_LABELS[e]}: <b>{counts[e]}</b> d
                  </span>
                ))
              })()}
            </div>

            {equipoHistoria.det && (
              <div className="grid grid-cols-3 gap-2 border-t pt-3 text-xs">
                <div>OEE: <b className={colorOEE(equipoHistoria.det.oee_total)}>{equipoHistoria.det.oee_total == null ? 'N/A' : fmtPct(equipoHistoria.det.oee_total)}</b></div>
                <div>Disp. física: <b>{fmtPct(equipoHistoria.det.disponibilidad_fisica)}</b></div>
                <div>MTBF / MTTR: <b>{fmtNum(equipoHistoria.det.mtbf_dias)} / {fmtNum(equipoHistoria.det.mttr_dias)} d</b></div>
              </div>
            )}

            {/* Días en arriendo por contrato */}
            {equipoHistoria.det?.contratos_dias && equipoHistoria.det.contratos_dias.length > 0 && (
              <div className="border-t pt-3">
                <div className="mb-1.5 flex items-center justify-between text-xs font-semibold text-gray-700">
                  <span>Días en arriendo por contrato</span>
                  <span className="text-gray-500">Total: {equipoHistoria.det.dias_arriendo_total ?? 0} d</span>
                </div>
                <table className="w-full text-xs">
                  <thead>
                    <tr className="border-b text-left uppercase text-gray-400">
                      <th className="py-1">Contrato</th>
                      <th className="py-1">Cliente</th>
                      <th className="py-1 text-right">Días</th>
                    </tr>
                  </thead>
                  <tbody>
                    {equipoHistoria.det.contratos_dias.map((c, i) => (
                      <tr key={i} className="border-b last:border-0">
                        <td className="py-1 font-medium text-gray-800">{c.codigo}</td>
                        <td className="py-1 text-gray-600">{c.cliente ?? '—'}</td>
                        <td className="py-1 text-right font-semibold">{c.dias}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}
      </Modal>
    </div>
  )
}

// ─── Subcomponentes ──────────────────────────────────────
function FichaCampo({ label, value, mono }: { label: string; value: string | null | undefined; mono?: boolean }) {
  return (
    <div>
      <div className="text-[10px] uppercase tracking-wide text-gray-400">{label}</div>
      <div className={`text-gray-800 ${mono ? 'font-mono' : 'font-medium'}`}>{value || '—'}</div>
    </div>
  )
}

function CompTile({
  label, actual, prev, unit, betterUp,
}: {
  label: string
  actual: number
  prev: number
  unit: string
  betterUp: boolean
}) {
  const dec = unit === 'd' ? 1 : 0
  const delta = actual - prev
  const mejora = betterUp ? delta >= 0 : delta <= 0
  const color = Math.abs(delta) < 0.05 ? 'text-gray-400' : mejora ? 'text-green-600' : 'text-red-600'
  const arrow = delta > 0.05 ? '▲' : delta < -0.05 ? '▼' : '='
  return (
    <div className="rounded-xl border bg-white p-3 shadow-sm">
      <div className="text-[10px] uppercase tracking-wide text-gray-400">{label}</div>
      <div className="mt-0.5 text-xl font-bold text-gray-800">{actual.toFixed(dec)}{unit}</div>
      <div className={`text-[11px] ${color}`}>
        {arrow} {Math.abs(delta).toFixed(dec)}{unit} <span className="text-gray-400">vs {prev.toFixed(dec)}{unit} (resto año)</span>
      </div>
    </div>
  )
}

function KpiTile({
  icon, label, value, hint, tone,
}: {
  icon: React.ReactNode
  label: string
  value: string
  hint?: string
  tone: 'indigo' | 'slate' | 'green' | 'red' | 'blue' | 'amber'
}) {
  const toneBg: Record<string, string> = {
    indigo: 'from-indigo-50 to-white border-indigo-200 text-indigo-700',
    slate: 'from-slate-50 to-white border-slate-200 text-slate-700',
    green: 'from-green-50 to-white border-green-200 text-green-700',
    red: 'from-red-50 to-white border-red-200 text-red-700',
    blue: 'from-blue-50 to-white border-blue-200 text-blue-700',
    amber: 'from-amber-50 to-white border-amber-200 text-amber-700',
  }
  return (
    <div className={`rounded-xl border bg-gradient-to-br ${toneBg[tone]} p-3 shadow-sm transition hover:shadow-md`}>
      <div className="flex items-center justify-between">
        <span className="text-[10px] uppercase tracking-wide opacity-70">{label}</span>
        {icon}
      </div>
      <div className="mt-1 text-2xl font-bold">{value}</div>
      {hint && <div className="text-[10px] opacity-60">{hint}</div>}
    </div>
  )
}

function GaugeCard({
  title, value, target, unit, description,
}: {
  title: string
  value: number
  target: number
  unit: string
  description: string
}) {
  const pct = Math.max(0, Math.min(100, value))
  const color = pct >= target ? '#16A34A' : pct >= target * 0.85 ? '#F59E0B' : '#DC2626'
  // Semicírculo: arco superior de (20,100) a (180,100), radio 80. Longitud = π·80.
  const R = 80
  const ARC = Math.PI * R
  const dash = (pct / 100) * ARC
  const arcPath = `M 20 100 A ${R} ${R} 0 0 1 180 100`
  return (
    <Card>
      <CardHeader className="pb-0">
        <CardTitle className="flex items-center gap-2 text-sm text-gray-600">
          <GaugeIcon className="h-4 w-4" />
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div className="mx-auto" style={{ maxWidth: 240 }}>
          <svg viewBox="0 0 200 118" className="w-full">
            <path d={arcPath} fill="none" stroke="#E5E7EB" strokeWidth="16" strokeLinecap="round" />
            <path
              d={arcPath} fill="none" stroke={color} strokeWidth="16" strokeLinecap="round"
              strokeDasharray={`${dash} ${ARC}`}
            />
            <text x="100" y="90" textAnchor="middle" fontSize="34" fontWeight="700" fill={color}>
              {value.toFixed(1)}{unit}
            </text>
            <text x="100" y="112" textAnchor="middle" fontSize="11" fill="#9CA3AF">
              Meta {target}{unit}
            </text>
          </svg>
        </div>
        <p className="mt-1 text-center text-[11px] text-gray-500">{description}</p>
      </CardContent>
    </Card>
  )
}

function RankingBarCard({
  title, icon, borderClass, data, labelUnit,
}: {
  title: string
  icon: React.ReactNode
  borderClass: string
  data: Array<{ patente: string; valor: number; color: string }>
  labelUnit: string
}) {
  return (
    <Card className={borderClass}>
      <CardHeader className="pb-0">
        <CardTitle className="text-sm text-gray-700 flex items-center gap-2">
          {icon}
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent>
        {data.length === 0 ? (
          <p className="text-xs text-gray-400 text-center py-6">Sin datos</p>
        ) : (
          <div className="h-48">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart
                data={data} layout="vertical" margin={{ left: 0, right: 24, top: 6, bottom: 6 }}
              >
                <XAxis type="number" hide />
                <YAxis
                  type="category" dataKey="patente" width={80}
                  tick={{ fontSize: 11, fontFamily: 'monospace' }}
                />
                <Tooltip
                  cursor={{ fill: '#F3F4F6' }}
                  formatter={(v: number) => `${v} ${labelUnit}`}
                />
                <Bar
                  dataKey="valor" radius={[0, 4, 4, 0]}
                  label={{ position: 'right', fontSize: 11, fill: '#374151',
                           formatter: (v: number) => `${v}${labelUnit}` }}
                >
                  {data.map((entry, i) => (
                    <Cell key={i} fill={entry.color} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
