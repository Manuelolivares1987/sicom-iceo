'use client'

import { useEffect, useMemo, useState } from 'react'
import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer, BarChart, Bar, XAxis, YAxis } from 'recharts'
import { supabase } from '@/lib/supabase'

// ── Estados ────────────────────────────────────────────────
const COLOR: Record<string, string> = {
  A: '#16A34A', C: '#15803D', L: '#4F46E5', U: '#0891B2', D: '#2563EB',
  H: '#A855F7', R: '#06B6D4', M: '#F59E0B', T: '#FB923C', F: '#DC2626', V: '#9333EA',
}
const LABEL: Record<string, string> = {
  A: 'Arrendado', C: 'En contrato', D: 'Disponible', H: 'Habilitación', R: 'Recepción',
  M: 'Mantención', T: 'Taller', F: 'Fuera de servicio', V: 'Venta', U: 'Uso interno', L: 'Leasing',
}
const ORDEN = ['A', 'C', 'L', 'U', 'D', 'M', 'T', 'F', 'H', 'R', 'V']

type Categoria = {
  categoria: string | null
  total_equipos: number; dias_equipo: number; dias_up: number; dias_down: number
  eventos_falla_total: number; disponibilidad_fisica: number; utilizacion_bruta: number
  mtbf_agregado: number; mttr_agregado: number
}
type Equipo = {
  activo_id: string; patente: string; equipamiento: string | null
  categoria_uso: string | null; cliente: string | null
  marca: string | null; modelo: string | null; anio: number | null
  capacidad: string | null; potencia: string | null; vin_chasis: string | null; numero_motor: string | null
  estado_comercial: string | null; faena: string | null; ubicacion: string | null; lugar_fisico: string | null
  zona: string | null
  contrato_codigo: string | null; contrato_cliente: string | null
  contratos_dias: Array<{ codigo: string; cliente: string | null; dias: number }> | null
  dias_arriendo_total: number | null
  ult_tipo: string | null; ult_cliente: string | null; ult_lugar: string | null
  ult_desde: string | null; ult_hasta: string | null; ult_dias: number | null; ult_vigente: boolean | null
  dias_observados: number; dias_up: number; dias_down: number; eventos_falla: number
  mtbf_dias: number; mttr_dias: number
  disponibilidad_inherente: number; disponibilidad_fisica: number
}
type Celda = { activo_id: string; fecha: string; estado: string }
type Estanque = {
  estanque_codigo: string; estanque_nombre: string; capacidad_lt: number
  stock_actual: number; stock_minimo: number; dias_cobertura: number | null
  fecha_agotamiento_estimada: string | null; severidad: string
}
type Reporte = {
  desde: string; hasta: string; categorias: Categoria[]; equipos: Equipo[]
  matriz: Celda[]; combustible: Estanque[]
}

const SEV: Record<string, [string, string]> = {
  agotado: ['Agotado', '#7f1d1d'], critico: ['Crítico', '#dc2626'],
  urgente: ['Urgente', '#ea580c'], atencion: ['Atención', '#d97706'], ok: ['OK', '#16a34a'],
}
const lt = (v: number | null | undefined) => Math.round(Number(v || 0)).toLocaleString('es-CL')

const fmtPct = (v: number | null | undefined, d = 1) => v == null ? '—' : `${(Number(v) * 100).toFixed(d)}%`
const fmtNum = (v: number | null | undefined, d = 1) => v == null ? '—' : Number(v).toFixed(d)
const firstOfMonth = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01` }
const todayStr = () => new Date().toISOString().slice(0, 10)

function colorDisp(v: number): string {
  if (v >= 0.92) return 'text-green-600'; if (v >= 0.85) return 'text-blue-600'
  if (v >= 0.75) return 'text-amber-600'; return 'text-red-600'
}

export default function ReporteFiabilidadPublicoPage() {
  const [desde, setDesde] = useState(firstOfMonth())
  const [hasta, setHasta] = useState(todayStr())
  const [data, setData] = useState<Reporte | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [cargando, setCargando] = useState(true)
  const [equipoSel, setEquipoSel] = useState<string | null>(null)
  const [filtroEstado, setFiltroEstado] = useState<string | null>(null)
  const [msg, setMsg] = useState<string | null>(null)

  // Permitir fijar el período por URL (?desde=...&hasta=...) desde el correo
  useEffect(() => {
    const q = new URLSearchParams(window.location.search)
    const d = q.get('desde'); const h = q.get('hasta')
    if (d) setDesde(d); if (h) setHasta(h)
  }, [])

  useEffect(() => {
    let cancel = false
    setCargando(true); setError(null)
    ;(async () => {
      const { data, error } = await supabase.rpc('fn_reporte_fiabilidad_publico', { p_ini: desde, p_fin: hasta })
      if (cancel) return
      if (error) setError(error.message)
      else setData(data as Reporte)
      setCargando(false)
    })()
    return () => { cancel = true }
  }, [desde, hasta])

  const equipos = data?.equipos ?? []
  const matriz = data?.matriz ?? []
  // Excluir camiones Franke (codigo CAM-*): solo se ven en la sección Franke.
  const combustible = (data?.combustible ?? []).filter((e) => !e.estanque_codigo?.startsWith('CAM-'))
  const combTot = combustible.reduce((a, e) => ({
    cap: a.cap + Number(e.capacidad_lt || 0), st: a.st + Number(e.stock_actual || 0),
    min: a.min + Number(e.stock_minimo || 0),
  }), { cap: 0, st: 0, min: 0 })

  const diasUnicos = useMemo(
    () => Array.from(new Set(matriz.map((c) => c.fecha.slice(0, 10)))).sort(),
    [matriz],
  )
  const estadoActual = useMemo(() => {
    const m = new Map<string, string>()
    if (diasUnicos.length === 0) return m
    const ultimo = diasUnicos[diasUnicos.length - 1]
    for (const c of matriz) if (c.fecha.slice(0, 10) === ultimo) m.set(c.activo_id, c.estado)
    return m
  }, [matriz, diasUnicos])

  // Días por estado (letra) por equipo, calculado desde la matriz diaria.
  // Por construcción la suma de letras = días observados; M+T+F = días DOWN;
  // el resto = días UP — así cuadra con dias_up/dias_down del backend.
  const diasPorLetra = useMemo(() => {
    const m = new Map<string, Record<string, number>>()
    for (const c of matriz) {
      const r = m.get(c.activo_id) ?? {}
      r[c.estado] = (r[c.estado] ?? 0) + 1
      m.set(c.activo_id, r)
    }
    return m
  }, [matriz])

  const distEstado = useMemo(() => {
    const counts: Record<string, number> = {}
    for (const e of Array.from(estadoActual.values())) counts[e] = (counts[e] ?? 0) + 1
    return ORDEN.filter((s) => counts[s]).map((s) => ({ key: s, name: LABEL[s], value: counts[s], color: COLOR[s] }))
  }, [estadoActual])

  // Distribución DIARIA de estados de la flota (barras apiladas por día).
  const distribucionDiaria = useMemo(() => {
    const byDia: Record<string, Record<string, number>> = {}
    for (const c of matriz) {
      const dia = (byDia[c.fecha.slice(0, 10)] ??= {})
      dia[c.estado] = (dia[c.estado] ?? 0) + 1
    }
    return diasUnicos.map((f) => ({ dia: f.slice(8, 10), ...byDia[f] }))
  }, [matriz, diasUnicos])
  const estadosPresentes = useMemo(() => {
    const set = new Set<string>()
    for (const c of matriz) set.add(c.estado)
    return ORDEN.filter((s) => set.has(s))
  }, [matriz])

  const kpi = useMemo(() => {
    const cats = data?.categorias ?? []
    if (cats.length === 0) return null
    const s = cats.reduce((a, c) => ({
      equipos: a.equipos + Number(c.total_equipos),
      dias: a.dias + Number(c.dias_equipo),
      up: a.up + Number(c.dias_up),
      down: a.down + Number(c.dias_down),
      ev: a.ev + Number(c.eventos_falla_total),
    }), { equipos: 0, dias: 0, up: 0, down: 0, ev: 0 })
    const dispFis = s.dias > 0 ? s.up / s.dias : 0
    const util = s.dias > 0 ? cats.reduce((a, c) => a + Number(c.utilizacion_bruta) * Number(c.dias_equipo), 0) / s.dias : 0
    const mtbf = s.ev > 0 ? s.up / s.ev : s.up
    const mttr = s.ev > 0 ? s.down / s.ev : 0
    const dispInh = mtbf + mttr > 0 ? mtbf / (mtbf + mttr) : 1
    return { ...s, dispFis, util, mtbf, mttr, dispInh }
  }, [data])

  const equiposFiltrados = useMemo(
    () => filtroEstado ? equipos.filter((e) => estadoActual.get(e.activo_id) === filtroEstado) : equipos,
    [equipos, filtroEstado, estadoActual],
  )

  const histSel = useMemo(() => {
    if (!equipoSel) return null
    const estados: Record<string, string> = {}
    for (const c of matriz) if (c.activo_id === equipoSel) estados[c.fecha.slice(0, 10)] = c.estado
    const det = equipos.find((e) => e.activo_id === equipoSel) ?? null
    return { det, estados }
  }, [equipoSel, matriz, equipos])

  // ── Reporte para correo: arma un HTML con formato y lo deja en el portapapeles
  // (o lo abre en otra pestaña como respaldo) para pegar directo en Outlook. ──
  function buildEmailHtml(): string {
    const k = kpi!
    const cats = data?.categorias ?? []
    const link = `${window.location.origin}/reporte-fiabilidad?desde=${desde}&hasta=${hasta}`
    const peores = [...equipos].sort((a, b) => Number(a.disponibilidad_inherente) - Number(b.disponibilidad_inherente)).slice(0, 5)
    const esc = (s: unknown) => String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c] as string))
    const td = (t: string, r = false) => `<td style="padding:8px;border:1px solid #e5e7eb;text-align:${r ? 'right' : 'left'}">${t}</td>`
    const th = (t: string, r = false) => `<th style="padding:8px;border:1px solid #e5e7eb;text-align:${r ? 'right' : 'left'};background:#f1f5f9;color:#475569">${t}</th>`
    const kpiTd = (label: string, val: string) => `<td style="padding:10px;border:1px solid #e5e7eb;text-align:center;background:#f8fafc"><div style="font-size:11px;color:#64748b;text-transform:uppercase">${label}</div><div style="font-size:20px;font-weight:700;color:#0b2a4a">${val}</div></td>`
    return `<div style="max-width:780px;font-family:Segoe UI,Arial,sans-serif;color:#1f2937">
  <div style="background:#0b2a4a;color:#fff;padding:18px 22px;border-radius:8px 8px 0 0">
    <div style="font-size:19px;font-weight:700">Análisis de Fiabilidad de Flota — Pillado</div>
    <div style="font-size:12px;opacity:.85">MTBF · MTTR · Disponibilidad Inherente · ${esc(desde)} a ${esc(hasta)}</div>
  </div>
  <div style="padding:16px 22px;border:1px solid #e5e7eb;border-top:none">
    <table style="width:100%;border-collapse:separate;border-spacing:5px"><tr>
      ${kpiTd('Equipos', String(k.equipos))}${kpiTd('Disp. física', fmtPct(k.dispFis))}${kpiTd('Disp. inherente', fmtPct(k.dispInh))}${kpiTd('MTBF', fmtNum(k.mtbf) + ' d')}${kpiTd('MTTR', fmtNum(k.mttr) + ' d')}
    </tr></table>
    <div style="text-align:center;margin:16px 0 6px">
      <a href="${link}" style="display:inline-block;background:#16a34a;color:#fff;text-decoration:none;font-weight:700;font-size:14px;padding:12px 24px;border-radius:8px">▶ Ver reporte interactivo — click en cada patente para su historial</a>
    </div>
    <h3 style="color:#0b2a4a;font-size:14px;margin:16px 0 6px">KPIs por categoría</h3>
    <table style="width:100%;border-collapse:collapse;font-size:13px"><tr>${th('Categoría')}${th('Equipos', true)}${th('Disp. física', true)}${th('N° fallas', true)}${th('MTBF', true)}${th('MTTR', true)}</tr>
      ${cats.map((c) => `<tr>${td(esc(c.categoria ?? 'Sin categoría'))}${td(String(c.total_equipos), true)}${td(fmtPct(c.disponibilidad_fisica), true)}${td(String(c.eventos_falla_total), true)}${td(Number(c.mtbf_agregado).toFixed(1), true)}${td(Number(c.mttr_agregado).toFixed(1), true)}</tr>`).join('')}
    </table>
    <h3 style="color:#0b2a4a;font-size:14px;margin:16px 0 6px">Stock de combustible</h3>
    <table style="width:100%;border-collapse:collapse;font-size:13px"><tr>${th('Estanque')}${th('Capacidad', true)}${th('Stock', true)}${th('% lleno', true)}</tr>
      ${combustible.map((e) => { const cap = Number(e.capacidad_lt || 0), st = Number(e.stock_actual || 0); return `<tr>${td(esc(e.estanque_codigo))}${td(lt(cap) + ' L', true)}${td(lt(st) + ' L', true)}${td((cap > 0 ? Math.round(st / cap * 100) : 0) + '%', true)}</tr>` }).join('')}
      <tr style="background:#0b2a4a;color:#fff;font-weight:700">${td('CONSOLIDADO')}${td(lt(combTot.cap) + ' L', true)}${td(lt(combTot.st) + ' L', true)}${td((combTot.cap > 0 ? Math.round(combTot.st / combTot.cap * 100) : 0) + '%', true)}</tr>
    </table>
    <h3 style="color:#0b2a4a;font-size:14px;margin:16px 0 6px">Menor disponibilidad inherente</h3>
    <table style="width:100%;border-collapse:collapse;font-size:13px"><tr>${th('Patente')}${th('Equipo')}${th('Días fuera', true)}${th('Disp. inherente', true)}</tr>
      ${peores.map((e) => `<tr>${td('<b>' + esc(e.patente) + '</b>')}${td(esc(e.equipamiento))}${td(String(e.dias_down), true)}${td(fmtPct(e.disponibilidad_inherente), true)}</tr>`).join('')}
    </table>
    <p style="font-size:11px;color:#94a3b8;margin-top:12px">El detalle por patente y el historial diario están en el reporte interactivo (botón verde). Disp. inherente = MTBF ÷ (MTBF + MTTR).</p>
  </div>
</div>`
  }

  async function copiarParaCorreo() {
    setMsg(null)
    const html = buildEmailHtml()
    try {
      await navigator.clipboard.write([new ClipboardItem({
        'text/html': new Blob([html], { type: 'text/html' }),
        'text/plain': new Blob([`Reporte de Fiabilidad de Flota (${desde} a ${hasta}) — ${window.location.origin}/reporte-fiabilidad?desde=${desde}&hasta=${hasta}`], { type: 'text/plain' }),
      })])
      setMsg('Copiado ✓ — ahora pega en Outlook (Ctrl+V)')
    } catch {
      const w = window.open('', '_blank')
      if (w) { w.document.write(html); w.document.close() }
      setMsg('Se abrió en otra pestaña: Ctrl+A → Ctrl+C → pega en Outlook')
    }
  }

  // ── Exportar a Excel: TODA la información por patente ──
  async function exportarExcel() {
    const ExcelJS = (await import('exceljs')).default
    const wb = new ExcelJS.Workbook()
    const ws = wb.addWorksheet('Equipos')
    ws.columns = [
      { header: 'Patente', key: 'patente', width: 12 },
      { header: 'Equipamiento', key: 'equipamiento', width: 28 },
      { header: 'Categoría uso', key: 'categoria_uso', width: 18 },
      { header: 'Marca', key: 'marca', width: 14 },
      { header: 'Modelo', key: 'modelo', width: 18 },
      { header: 'Año', key: 'anio', width: 8 },
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
      { header: 'Cliente actual', key: 'cliente', width: 24 },
      { header: 'Días arriendo (total)', key: 'dias_arriendo_total', width: 16 },
      { header: 'Días por contrato', key: 'contratos_dias_txt', width: 44 },
      { header: 'Últ. arriendo cliente', key: 'ult_cliente', width: 22 },
      { header: 'Últ. arriendo lugar', key: 'ult_lugar', width: 20 },
      { header: 'Últ. arriendo desde', key: 'ult_desde', width: 14 },
      { header: 'Últ. arriendo hasta', key: 'ult_hasta', width: 14 },
      { header: 'Días observados', key: 'dias_observados', width: 14 },
      { header: 'Días UP', key: 'dias_up', width: 10 },
      { header: 'Días DOWN', key: 'dias_down', width: 10 },
      // Desglose de días por estado (letra). UP = todo salvo M/T/F; DOWN = M+T+F.
      ...ORDEN.map((s) => ({ header: `${s} — ${LABEL[s]}`, key: `dias_${s}`, width: 14 })),
      { header: 'Total letras (=Días obs)', key: 'dias_letras_total', width: 18 },
      { header: 'Cuadre (letras = días obs)', key: 'cuadre', width: 18 },
      { header: 'Eventos falla', key: 'eventos_falla', width: 12 },
      { header: 'MTBF (días)', key: 'mtbf_dias', width: 11 },
      { header: 'MTTR (días)', key: 'mttr_dias', width: 11 },
      { header: 'Disp. inherente %', key: 'disp_inh', width: 15 },
      { header: 'Disp. física %', key: 'disp_fis', width: 14 },
    ]
    ws.getRow(1).font = { bold: true }
    ws.getRow(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF0B2A4A' } }
    ws.getRow(1).font = { bold: true, color: { argb: 'FFFFFFFF' } }
    // DOWN operacional = M,T,F (fallas) + R (recepción) + H (habilitación).
    // UP = A,C,L,U,D,V. (Difiere del UP/DOWN del backend, que solo cuenta M,T,F
    // para MTBF/MTTR; aquí se recalcula desde la matriz para el Excel.)
    const DOWN_LETRAS = new Set(['M', 'T', 'F', 'R', 'H'])
    for (const e of equiposFiltrados) {
      const code = estadoActual.get(e.activo_id)
      const cuenta = diasPorLetra.get(e.activo_id) ?? {}
      const porLetra = Object.fromEntries(ORDEN.map((s) => [`dias_${s}`, cuenta[s] ?? 0]))
      const upCalc = ORDEN.reduce((a, s) => a + (DOWN_LETRAS.has(s) ? 0 : (cuenta[s] ?? 0)), 0)
      const downCalc = ORDEN.reduce((a, s) => a + (DOWN_LETRAS.has(s) ? (cuenta[s] ?? 0) : 0), 0)
      const totalLetras = upCalc + downCalc
      ws.addRow({
        ...e,
        dias_up: upCalc,
        dias_down: downCalc,
        ...porLetra,
        dias_letras_total: totalLetras,
        cuadre: totalLetras === Number(e.dias_observados) ? 'OK' : `≠ (${totalLetras}/${e.dias_observados})`,
        estado_dia: code ? `${code} — ${LABEL[code] ?? code}` : '—',
        contratos_dias_txt: (e.contratos_dias ?? []).map((c) => `${c.codigo}: ${c.dias} d`).join('; '),
        ult_desde: e.ult_desde ? String(e.ult_desde).slice(0, 10) : '',
        ult_hasta: e.ult_vigente ? 'vigente' : (e.ult_hasta ? String(e.ult_hasta).slice(0, 10) : ''),
        disp_inh: e.disponibilidad_inherente != null ? Math.round(Number(e.disponibilidad_inherente) * 100) : '',
        disp_fis: e.disponibilidad_fisica != null ? Math.round(Number(e.disponibilidad_fisica) * 100) : '',
      })
    }
    ws.autoFilter = { from: 'A1', to: { row: 1, column: ws.columnCount } }
    ws.views = [{ state: 'frozen', ySplit: 1 }]
    const buf = await wb.xlsx.writeBuffer()
    const blob = new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `fiabilidad_equipos_${desde}_a_${hasta}.xlsx`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="min-h-screen bg-gray-50 py-8">
      <div className="mx-auto max-w-5xl px-4">
        <div className="mb-5 flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 className="text-2xl font-bold text-[#0b2a4a]">Análisis de Fiabilidad de Flota — Pillado</h1>
            <p className="text-sm text-gray-500">
              MTBF · MTTR · Disponibilidad Inherente · {desde} a {hasta} · SICOM-ICEO
            </p>
            <p className="mt-1 text-xs text-gray-400">Haz click en una patente para ver su historial diario.</p>
          </div>
          <div className="flex items-end gap-2">
            <div>
              <label className="block text-[10px] uppercase text-gray-400">Desde</label>
              <input type="date" className="h-9 rounded border border-gray-300 px-2 text-sm" value={desde} onChange={(e) => setDesde(e.target.value)} />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-gray-400">Hasta</label>
              <input type="date" className="h-9 rounded border border-gray-300 px-2 text-sm" value={hasta} onChange={(e) => setHasta(e.target.value)} />
            </div>
            <button
              onClick={copiarParaCorreo}
              disabled={!kpi}
              className="h-9 rounded-lg bg-[#0b2a4a] px-4 text-sm font-semibold text-white hover:bg-[#0e3458] disabled:opacity-50"
              title="Copia el reporte con formato para pegarlo en Outlook"
            >
              📋 Copiar para correo
            </button>
          </div>
        </div>
        {msg && <div className="mb-3 rounded-lg bg-green-50 px-3 py-2 text-sm text-green-800">{msg}</div>}

        {error && <div className="rounded-lg bg-red-50 p-4 text-sm text-red-700">No se pudo cargar: {error}</div>}
        {cargando && <div className="py-20 text-center text-gray-400">Cargando…</div>}

        {!cargando && kpi && (
          <div className="space-y-5">
            {/* KPIs */}
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-6">
              <Kpi n={String(kpi.equipos)} l="Equipos" />
              <Kpi n={String(kpi.dias)} l="Días-equipo" />
              <Kpi n={fmtPct(kpi.dispFis)} l="Disp. física" />
              <Kpi n={fmtPct(kpi.dispInh)} l="Disp. inherente" />
              <Kpi n={`${fmtNum(kpi.mtbf)} d`} l="MTBF" />
              <Kpi n={`${fmtNum(kpi.mttr)} d`} l="MTTR" />
            </div>

            {/* Distribución por estado */}
            <Card title={`Distribución por estado${diasUnicos.length ? ` · ${diasUnicos[diasUnicos.length - 1]}` : ''} — click para filtrar`}>
              <div className="grid items-center gap-4 sm:grid-cols-2">
                <div className="h-56">
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie data={distEstado} cx="50%" cy="50%" innerRadius={48} outerRadius={88} paddingAngle={2}
                        dataKey="value" cursor="pointer" label={({ value }) => `${value}`}
                        onClick={(d: { key?: string }) => d?.key && setFiltroEstado(filtroEstado === d.key ? null : d.key)}>
                        {distEstado.map((e) => (
                          <Cell key={e.key} fill={e.color} opacity={filtroEstado && filtroEstado !== e.key ? 0.3 : 1} />
                        ))}
                      </Pie>
                      <Tooltip formatter={(v: number, n: string) => [`${v} equipos`, n]} />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
                <div className="space-y-1">
                  {distEstado.map((e) => (
                    <button key={e.key} onClick={() => setFiltroEstado(filtroEstado === e.key ? null : e.key)}
                      className="flex w-full items-center justify-between rounded px-1 text-sm hover:bg-gray-50"
                      style={{ opacity: filtroEstado && filtroEstado !== e.key ? 0.4 : 1 }}>
                      <span className="flex items-center gap-2">
                        <span className="inline-block h-3 w-3 rounded-sm" style={{ background: e.color }} />
                        {e.name} <span className="text-gray-400">({e.key})</span>
                      </span>
                      <b>{e.value}</b>
                    </button>
                  ))}
                </div>
              </div>
            </Card>

            {/* Distribución diaria de estados de la flota */}
            {distribucionDiaria.length > 0 && (
              <Card title="Distribución diaria de estados de la flota">
                <div className="h-64">
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart data={distribucionDiaria} margin={{ top: 5, right: 8, left: -18, bottom: 0 }}>
                      <XAxis dataKey="dia" tick={{ fontSize: 10 }} interval={0} />
                      <YAxis tick={{ fontSize: 10 }} allowDecimals={false} />
                      <Tooltip formatter={(v: number, n: string) => [`${v} equipos`, LABEL[n] ?? n]} labelFormatter={(d) => `Día ${d}`} />
                      {estadosPresentes.map((s) => (
                        <Bar key={s} dataKey={s} stackId="estados" fill={COLOR[s]} name={LABEL[s]} />
                      ))}
                    </BarChart>
                  </ResponsiveContainer>
                </div>
                <div className="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-[11px]">
                  {estadosPresentes.map((s) => (
                    <span key={s} className="flex items-center gap-1 text-gray-600">
                      <span className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: COLOR[s] }} />{LABEL[s]}
                    </span>
                  ))}
                </div>
              </Card>
            )}

            {/* Stock de combustible (debajo de la torta) */}
            {combustible.length > 0 && (
              <Card title="Stock de combustible">
                <div className="overflow-x-auto">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
                        <th className="px-2 py-2">Estanque</th>
                        <th className="px-2 py-2 text-right">Capacidad</th>
                        <th className="px-2 py-2 text-right">Stock</th>
                        <th className="px-2 py-2 text-right">% lleno</th>
                        <th className="px-2 py-2 text-right">Mínimo</th>
                        <th className="px-2 py-2 text-right">Cobertura</th>
                        <th className="px-2 py-2">Agotamiento est.</th>
                        <th className="px-2 py-2 text-center">Estado</th>
                      </tr>
                    </thead>
                    <tbody>
                      {combustible.map((e) => {
                        const cap = Number(e.capacidad_lt || 0), st = Number(e.stock_actual || 0)
                        const llen = cap > 0 ? Math.round(st / cap * 100) : 0
                        const sev = SEV[e.severidad] ?? SEV.ok
                        return (
                          <tr key={e.estanque_codigo} className="border-b">
                            <td className="px-2 py-1.5"><b>{e.estanque_codigo}</b><div className="text-[10px] text-gray-400">{e.estanque_nombre}</div></td>
                            <td className="px-2 py-1.5 text-right">{lt(cap)} L</td>
                            <td className="px-2 py-1.5 text-right font-semibold">{lt(st)} L</td>
                            <td className="px-2 py-1.5 text-right">{llen}%</td>
                            <td className="px-2 py-1.5 text-right text-gray-400">{lt(e.stock_minimo)} L</td>
                            <td className="px-2 py-1.5 text-right">{e.dias_cobertura != null ? `${Number(e.dias_cobertura).toFixed(1)} d` : '—'}</td>
                            <td className="px-2 py-1.5">{e.fecha_agotamiento_estimada ? e.fecha_agotamiento_estimada.slice(0, 10) : '—'}</td>
                            <td className="px-2 py-1.5 text-center">
                              <span className="inline-block rounded px-2 py-0.5 text-[10px] font-semibold text-white" style={{ background: sev[1] }}>{sev[0]}</span>
                            </td>
                          </tr>
                        )
                      })}
                    </tbody>
                    <tfoot>
                      <tr className="font-bold text-white" style={{ background: '#0b2a4a' }}>
                        <td className="px-2 py-2">CONSOLIDADO ({combustible.length} estanques)</td>
                        <td className="px-2 py-2 text-right">{lt(combTot.cap)} L</td>
                        <td className="px-2 py-2 text-right">{lt(combTot.st)} L</td>
                        <td className="px-2 py-2 text-right">{combTot.cap > 0 ? Math.round(combTot.st / combTot.cap * 100) : 0}%</td>
                        <td className="px-2 py-2 text-right">{lt(combTot.min)} L</td>
                        <td className="px-2 py-2 text-center" colSpan={3}>Stock total disponible</td>
                      </tr>
                    </tfoot>
                  </table>
                </div>
              </Card>
            )}

            {/* Detalle por equipo (clickable) */}
            <Card title="Detalle por equipo — click en la patente para ver su historial">
              <div className="mb-2 flex justify-end">
                <button
                  onClick={exportarExcel}
                  disabled={equiposFiltrados.length === 0}
                  className="inline-flex items-center gap-1.5 rounded-lg bg-green-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-green-700 disabled:opacity-50"
                  title="Exporta toda la información de cada patente a un Excel"
                >
                  ⬇ Exportar a Excel ({equiposFiltrados.length})
                </button>
              </div>
              {filtroEstado && (
                <div className="mb-2 flex items-center gap-2 text-xs">
                  <span className="rounded bg-blue-50 px-2 py-1 text-blue-700">
                    Filtro: {LABEL[filtroEstado] ?? filtroEstado} ({equiposFiltrados.length})
                  </span>
                  <button onClick={() => setFiltroEstado(null)} className="text-blue-600 hover:underline">Limpiar filtro</button>
                </div>
              )}
              <div className="overflow-x-auto">
                <table className="w-full text-xs whitespace-nowrap">
                  <thead>
                    <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
                      <th className="px-2 py-2">Patente</th>
                      <th className="px-2 py-2">Equipo</th>
                      <th className="px-2 py-2">Cliente</th>
                      <th className="px-2 py-2 text-right">Días</th>
                      <th className="px-2 py-2 text-right">UP</th>
                      <th className="px-2 py-2 text-right">DOWN</th>
                      <th className="px-2 py-2 text-right">N°Fal</th>
                      <th className="px-2 py-2 text-right">MTBF</th>
                      <th className="px-2 py-2 text-right">MTTR</th>
                      <th className="px-2 py-2 text-right">Disp.Inh</th>
                      <th className="px-2 py-2 text-right">Disp.Fís</th>
                    </tr>
                  </thead>
                  <tbody>
                    {equiposFiltrados.map((d) => (
                      <tr key={d.activo_id} className="border-b hover:bg-blue-50">
                        <td className="px-2 py-1.5">
                          <button onClick={() => setEquipoSel(d.activo_id)} className="font-mono font-semibold text-blue-700 hover:underline">
                            {d.patente}
                          </button>
                        </td>
                        <td className="px-2 py-1.5 text-gray-600">{d.equipamiento ?? '—'}</td>
                        <td className="px-2 py-1.5 text-gray-500 max-w-[150px] truncate">{d.contrato_cliente ?? d.cliente ?? '—'}</td>
                        <td className="px-2 py-1.5 text-right">{d.dias_observados}</td>
                        <td className="px-2 py-1.5 text-right text-green-700">{d.dias_up}</td>
                        <td className="px-2 py-1.5 text-right text-red-700">{d.dias_down}</td>
                        <td className="px-2 py-1.5 text-right">{d.eventos_falla}</td>
                        <td className="px-2 py-1.5 text-right">{fmtNum(d.mtbf_dias)}</td>
                        <td className="px-2 py-1.5 text-right">{fmtNum(d.mttr_dias)}</td>
                        <td className={`px-2 py-1.5 text-right font-semibold ${colorDisp(Number(d.disponibilidad_inherente))}`}>{fmtPct(d.disponibilidad_inherente, 0)}</td>
                        <td className={`px-2 py-1.5 text-right ${colorDisp(Number(d.disponibilidad_fisica))}`}>{fmtPct(d.disponibilidad_fisica, 0)}</td>
                      </tr>
                    ))}
                    {equiposFiltrados.length === 0 && (
                      <tr><td colSpan={11} className="py-6 text-center text-gray-400">Sin equipos en ese estado.</td></tr>
                    )}
                  </tbody>
                </table>
              </div>
            </Card>

            <p className="pt-2 text-center text-xs text-gray-400">Pillado · SICOM-ICEO · Disp. Inherente = MTBF ÷ (MTBF + MTTR)</p>
          </div>
        )}
      </div>

      {/* Modal historial */}
      {histSel && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={() => setEquipoSel(null)}>
          <div className="max-h-[85vh] w-full max-w-3xl overflow-auto rounded-2xl bg-white p-5 shadow-xl" onClick={(e) => e.stopPropagation()}>
            <div className="mb-3 flex items-start justify-between">
              <div>
                <h3 className="text-lg font-bold text-[#0b2a4a]">Historial · {histSel.det?.patente}</h3>
                <p className="text-sm text-gray-500">{histSel.det?.equipamiento ?? ''}</p>
                {(histSel.det?.contrato_codigo || histSel.det?.contrato_cliente || histSel.det?.cliente) && (
                  <p className="text-sm text-gray-700">
                    📄 Último contrato: <b>
                      {[histSel.det?.contrato_codigo, histSel.det?.contrato_cliente ?? histSel.det?.cliente]
                        .filter(Boolean).join(' · ') || '—'}
                    </b>
                  </p>
                )}
                <p className="text-sm text-gray-700">
                  📍 Dónde está: <b>{histSel.det?.lugar_fisico ?? histSel.det?.ubicacion ?? 'Sin registrar'}</b>
                </p>
              </div>
              <button onClick={() => setEquipoSel(null)} className="rounded px-2 py-1 text-gray-400 hover:bg-gray-100">✕</button>
            </div>

            <div className="flex flex-wrap gap-0.5">
              {diasUnicos.map((f) => {
                const e = histSel.estados[f]
                return (
                  <div key={f} className="flex flex-col items-center">
                    <div className="text-[8px] text-gray-400">{f.slice(8, 10)}</div>
                    <div className="h-6 w-6 text-center text-[10px] font-semibold leading-6"
                      style={{ background: e ? COLOR[e] : '#F3F4F6', color: e ? '#fff' : '#D1D5DB' }}
                      title={e ? `${f}: ${LABEL[e]}` : f}>
                      {e ?? ''}
                    </div>
                  </div>
                )
              })}
            </div>

            <div className="mt-4 flex flex-wrap gap-x-3 gap-y-1 text-xs">
              {(() => {
                const counts: Record<string, number> = {}
                for (const f of diasUnicos) { const e = histSel.estados[f]; if (e) counts[e] = (counts[e] ?? 0) + 1 }
                return ORDEN.filter((e) => counts[e]).map((e) => (
                  <span key={e} className="flex items-center gap-1 text-gray-700">
                    <span className="inline-block h-3 w-3 rounded-sm" style={{ background: COLOR[e] }} />
                    {LABEL[e]}: <b>{counts[e]}</b> d
                  </span>
                ))
              })()}
            </div>

            {histSel.det && (
              <div className="mt-4 grid grid-cols-3 gap-2 border-t pt-3 text-xs">
                <div>Disp. inherente: <b>{fmtPct(histSel.det.disponibilidad_inherente)}</b></div>
                <div>Disp. física: <b>{fmtPct(histSel.det.disponibilidad_fisica)}</b></div>
                <div>MTBF / MTTR: <b>{fmtNum(histSel.det.mtbf_dias)} / {fmtNum(histSel.det.mttr_dias)} d</b></div>
              </div>
            )}

            {/* Días en arriendo por contrato */}
            {histSel.det && histSel.det.contratos_dias && histSel.det.contratos_dias.length > 0 && (
              <div className="mt-4 border-t pt-3">
                <div className="mb-2 flex items-center justify-between text-xs font-semibold text-[#0b2a4a]">
                  <span>Días en arriendo por contrato</span>
                  <span className="text-gray-500">Total: {histSel.det.dias_arriendo_total ?? 0} d</span>
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
                    {histSel.det.contratos_dias.map((c, i) => (
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

            {/* Último arriendo: quién lo tuvo y dónde (útil al pasar a recepción/disponible) */}
            {histSel.det && (histSel.det.ult_cliente || histSel.det.ult_lugar) && (
              <div className="mt-4 rounded-lg border border-blue-200 bg-blue-50 p-3 text-xs">
                <div className="mb-1 font-semibold text-[#0b2a4a]">Último arriendo</div>
                <div className="text-gray-700">
                  <b>{histSel.det.ult_cliente ?? 'Cliente s/d'}</b>
                  {histSel.det.ult_lugar && <> en <b>{histSel.det.ult_lugar}</b></>}
                  {' · '}
                  {histSel.det.ult_desde ? String(histSel.det.ult_desde).slice(0, 10) : '—'}
                  {histSel.det.ult_vigente ? ' → vigente' : (histSel.det.ult_hasta ? ` → ${String(histSel.det.ult_hasta).slice(0, 10)}` : '')}
                  {histSel.det.ult_dias != null && ` · ${histSel.det.ult_dias} día(s)`}
                </div>
              </div>
            )}

            {/* Ficha técnica del equipo (como en la página) */}
            {histSel.det && (
              <div className="mt-4 border-t pt-3">
                <div className="mb-2 text-xs font-semibold text-[#0b2a4a]">Ficha técnica</div>
                <div className="grid grid-cols-2 gap-x-4 gap-y-1.5 text-xs sm:grid-cols-3">
                  <FichaCampo label="Marca" value={histSel.det.marca} />
                  <FichaCampo label="Modelo" value={histSel.det.modelo} />
                  <FichaCampo label="Año" value={histSel.det.anio} />
                  <FichaCampo label="Capacidad" value={histSel.det.capacidad} />
                  <FichaCampo label="Potencia (CV)" value={histSel.det.potencia} />
                  <FichaCampo label="VIN / Chasis" value={histSel.det.vin_chasis} />
                  <FichaCampo label="N° Motor" value={histSel.det.numero_motor} />
                  <FichaCampo label="Cliente" value={histSel.det.cliente} />
                  <FichaCampo label="Zona" value={histSel.det.zona} />
                  <FichaCampo label="Lugar físico" value={histSel.det.ubicacion} />
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  )
}

function Kpi({ n, l }: { n: string; l: string }) {
  return (
    <div className="rounded-xl border bg-white p-3 text-center">
      <div className="text-xl font-bold text-[#0b2a4a]">{n}</div>
      <div className="mt-1 text-[10px] uppercase tracking-wide text-gray-500">{l}</div>
    </div>
  )
}
function FichaCampo({ label, value }: { label: string; value: string | number | null | undefined }) {
  return (
    <div>
      <div className="text-[10px] uppercase tracking-wide text-gray-400">{label}</div>
      <div className="font-medium text-gray-800">{value != null && value !== '' ? value : '—'}</div>
    </div>
  )
}
function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-xl border bg-white p-4">
      <h2 className="mb-2 text-sm font-semibold text-[#0b2a4a]">{title}</h2>
      {children}
    </div>
  )
}
