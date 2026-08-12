'use client'

// Despacho de combustible en faena — vista de oficina (MIG279).
// Lo que el operador anota en terreno llega acá: el detalle por carga y el
// consumo acumulado por CECO, que es lo que el cliente pide para su control.

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import {
  ArrowLeft, Fuel, ChevronLeft, ChevronRight, FileSpreadsheet, Ban, Truck, Search, Camera,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  FAENA_ROMERAL, getFaenaPorCodigo, getDespachosRango, getConsumoPorCeco, anularDespacho,
} from '@/lib/services/combustible-faena'
import { MESES } from '@/lib/services/enex'

const hoy = () => { const d = new Date(); return { anio: d.getFullYear(), mes: d.getMonth() + 1 } }
const pad = (n: number) => String(n).padStart(2, '0')
const finDeMes = (a: number, m: number) => new Date(a, m, 0).getDate()

function fmtFecha(iso?: string | null): string {
  if (!iso) return '—'
  const [y, m, d] = iso.slice(0, 10).split('-')
  return `${d}-${m}-${y}`
}
const L = (n: number | string | null | undefined) =>
  Math.round(Number(n ?? 0)).toLocaleString('es-CL')

export default function RomeralOficinaPage() {
  useRequireAuth()
  const toast = useToast()
  const [{ anio, mes }, setPeriodo] = useState(hoy())
  const [buscar, setBuscar] = useState('')
  const [vista, setVista] = useState<'detalle' | 'ceco'>('detalle')
  const [anulando, setAnulando] = useState<string | null>(null)
  const [motivo, setMotivo] = useState('')
  const [exportando, setExportando] = useState(false)

  const desde = `${anio}-${pad(mes)}-01`
  const hasta = `${anio}-${pad(mes)}-${pad(finDeMes(anio, mes))}`

  const { data: faena } = useQuery({
    queryKey: ['faena', FAENA_ROMERAL], queryFn: () => getFaenaPorCodigo(FAENA_ROMERAL), staleTime: 60 * 60_000,
  })
  const { data: despachos = [], isLoading, refetch } = useQuery({
    queryKey: ['comb-faena-desp', faena?.id, desde, hasta],
    queryFn: () => getDespachosRango(faena!.id, desde, hasta),
    enabled: !!faena?.id, staleTime: 15_000,
  })
  const { data: porCeco = [] } = useQuery({
    queryKey: ['comb-faena-ceco', faena?.id, desde],
    queryFn: () => getConsumoPorCeco(faena!.id, desde),
    enabled: !!faena?.id, staleTime: 15_000,
  })

  function cambiarMes(d: number) {
    let m = mes + d, a = anio
    if (m < 1) { m = 12; a-- } else if (m > 12) { m = 1; a++ }
    setPeriodo({ anio: a, mes: m })
  }

  const filtrados = useMemo(() => {
    const q = buscar.trim().toLowerCase()
    if (!q) return despachos
    return despachos.filter((d) =>
      (d.equipo ?? '').toLowerCase().includes(q) ||
      (d.ceco ?? '').toLowerCase().includes(q) ||
      (d.ubicacion ?? '').toLowerCase().includes(q) ||
      (d.operador_nombre ?? '').toLowerCase().includes(q) ||
      (d.camion_patente ?? '').toLowerCase().includes(q))
  }, [despachos, buscar])

  const totalLitros = filtrados.filter((d) => !d.anulado).reduce((s, d) => s + Number(d.litros), 0)
  const porDia = useMemo(() => {
    const m = new Map<string, number>()
    for (const d of despachos) if (!d.anulado) m.set(d.fecha, (m.get(d.fecha) ?? 0) + Number(d.litros))
    return Array.from(m.entries()).sort((a, b) => b[0].localeCompare(a[0]))
  }, [despachos])

  /**
   * Excel del registro: una hoja con el detalle de cada carga, otra con el
   * consumo por CECO y otra con el total por día. Es lo que se le pasa al
   * cliente y lo que reemplaza al papel que hoy se transcribe a mano.
   */
  async function exportar() {
    setExportando(true)
    try {
      const ExcelJS = (await import('exceljs')).default
      const wb = new ExcelJS.Workbook()
      wb.creator = 'SICOM-ICEO · Pillado y Cía. Ltda.'
      wb.created = new Date()
      const titulo = `${MESES[mes - 1]} ${anio}`

      const encabezar = (ws: import('exceljs').Worksheet, cols: string[]) => {
        const row = ws.getRow(1)
        cols.forEach((c, i) => { row.getCell(i + 1).value = c })
        row.font = { bold: true, color: { argb: 'FFFFFFFF' } }
        row.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFC2410C' } }
        row.alignment = { vertical: 'middle' }
        ws.views = [{ state: 'frozen', ySplit: 1 }]
      }

      // Detalle
      const d1 = wb.addWorksheet(`Despachos ${titulo}`)
      encabezar(d1, ['Fecha', 'Hora', 'Turno', 'Camión', 'Equipo', 'Descripción', 'CECO',
                     'Empresa', 'Lugar', 'Medidor inicial', 'Medidor final', 'Litros',
                     'Operador', 'Foto inicial', 'Foto final', 'Sin foto: motivo',
                     'Estado', 'Motivo anulación', 'Observación'])
      for (const d of filtrados) {
        d1.addRow([
          fmtFecha(d.fecha), d.hora ? d.hora.slice(0, 5) : '', d.turno ?? '', d.camion_patente ?? '',
          d.equipo ?? '', d.equipo_descripcion ?? '', d.ceco ?? '', d.ceco_empresa ?? '',
          d.ubicacion ?? '', d.meter_inicial != null ? Number(d.meter_inicial) : null,
          d.meter_final != null ? Number(d.meter_final) : null, Number(d.litros),
          d.operador_nombre ?? '',
          d.foto_meter_inicial_url ?? '', d.foto_meter_final_url ?? '', d.sin_foto_motivo ?? '',
          d.anulado ? 'ANULADO' : 'Vigente', d.anulado_motivo ?? '', d.observacion ?? '',
        ])
      }
      d1.columns.forEach((c, i) => { c.width = [11, 7, 8, 11, 20, 26, 14, 22, 20, 14, 14, 10, 20, 34, 34, 24, 10, 24, 26][i] ?? 14 })
      d1.getColumn(12).numFmt = '#,##0'
      // Total solo de lo vigente: lo anulado no suma, como en el papel tachado.
      const totalRow = d1.addRow(['', '', '', '', '', '', '', '', '', '', 'TOTAL', totalLitros])
      totalRow.font = { bold: true }
      totalRow.getCell(12).numFmt = '#,##0'

      // Consumo por CECO
      const d2 = wb.addWorksheet('Consumo por CECO')
      encabezar(d2, ['CECO', 'Empresa', 'Equipos', 'Cargas', 'Litros', '% del mes'])
      for (const c of porCeco) {
        d2.addRow([c.ceco ?? '(sin CECO)', c.ceco_empresa ?? '', Number(c.equipos),
                   Number(c.despachos), Number(c.litros),
                   totalLitros > 0 ? Number(c.litros) / totalLitros : 0])
      }
      d2.columns.forEach((c, i) => { c.width = [16, 28, 10, 10, 12, 11][i] ?? 14 })
      d2.getColumn(5).numFmt = '#,##0'
      d2.getColumn(6).numFmt = '0%'

      // Total por día
      const d3 = wb.addWorksheet('Por día')
      encabezar(d3, ['Fecha', 'Cargas', 'Litros'])
      for (const [f, litros] of porDia) {
        d3.addRow([fmtFecha(f), despachos.filter((x) => x.fecha === f && !x.anulado).length, litros])
      }
      d3.columns.forEach((c, i) => { c.width = [14, 10, 12][i] ?? 14 })
      d3.getColumn(3).numFmt = '#,##0'

      const buf = await wb.xlsx.writeBuffer()
      const blob = new Blob([buf], {
        type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      })
      const a = document.createElement('a')
      a.href = URL.createObjectURL(blob)
      a.download = `Romeral_despachos_${anio}-${pad(mes)}.xlsx`
      a.click()
      URL.revokeObjectURL(a.href)
      toast.success('Excel descargado')
    } catch (e) { toast.error(`No se pudo generar el Excel: ${(e as Error).message}`) }
    finally { setExportando(false) }
  }

  // El motivo se pide en la propia pantalla: window.prompt congela la pestaña.
  async function anular() {
    if (!anulando || !motivo.trim()) return
    try {
      await anularDespacho(anulando, motivo.trim())
      toast.success('Carga anulada')
      setAnulando(null); setMotivo(''); refetch()
    } catch (e) { toast.error((e as Error).message) }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <Link href="/dashboard/combustible" className="inline-flex items-center gap-1 text-xs text-gray-500 hover:text-gray-700">
            <ArrowLeft className="h-3.5 w-3.5" /> Combustible
          </Link>
          <h1 className="flex items-center gap-2 text-xl font-bold">
            <Fuel className="h-5 w-5 text-orange-600" /> Despachos en faena — Romeral
          </h1>
          <p className="mt-0.5 text-sm text-gray-500">
            Lo que el operador registra en terreno, con su CECO y lugar.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={() => cambiarMes(-1)} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50"><ChevronLeft className="h-4 w-4" /></button>
          <span className="min-w-[130px] text-center text-sm font-semibold">{MESES[mes - 1]} {anio}</span>
          <button onClick={() => cambiarMes(1)} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50"><ChevronRight className="h-4 w-4" /></button>
          <Button variant="outline" onClick={exportar} disabled={filtrados.length === 0 || exportando}>
            {exportando ? <Spinner className="mr-1 h-4 w-4" /> : <FileSpreadsheet className="mr-1 h-4 w-4" />}
            Descargar Excel
          </Button>
        </div>
      </div>

      {/* Totales */}
      <div className="grid grid-cols-2 gap-2 md:grid-cols-4">
        {[
          { l: 'Litros del mes', v: `${L(totalLitros)} L`, c: 'text-orange-700' },
          { l: 'Cargas', v: L(filtrados.filter((d) => !d.anulado).length), c: 'text-gray-900' },
          { l: 'Días con despacho', v: L(porDia.length), c: 'text-gray-900' },
          { l: 'CECOs con consumo', v: L(porCeco.length), c: 'text-gray-900' },
        ].map((k, i) => (
          <Card key={i}><CardContent className="p-3">
            <p className="text-xs text-gray-500">{k.l}</p>
            <p className={`text-xl font-bold ${k.c}`}>{k.v}</p>
          </CardContent></Card>
        ))}
      </div>

      <Card>
        <CardContent className="flex flex-wrap items-center gap-3 p-3">
          <div className="flex overflow-hidden rounded-lg border">
            {([['detalle', 'Detalle'], ['ceco', 'Consumo por CECO']] as const).map(([id, label]) => (
              <button key={id} onClick={() => setVista(id)}
                      className={`px-3 py-1.5 text-xs font-semibold ${
                        vista === id ? 'bg-orange-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>
                {label}
              </button>
            ))}
          </div>
          <div className="relative min-w-[220px] flex-1">
            <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-gray-400" />
            <Input value={buscar} onChange={(e) => setBuscar(e.target.value)}
                   placeholder="Equipo, CECO, lugar, operador o camión…" className="h-9 pl-8" />
          </div>
        </CardContent>
      </Card>

      {/* Anular una carga: se registra el motivo, no se borra. El papel tampoco
          se rompe — se tacha y se explica. */}
      {anulando && (
        <Card className="border-red-300">
          <CardContent className="flex flex-wrap items-end gap-2 p-3">
            <div className="min-w-[260px] flex-1">
              <label className="text-xs font-semibold text-red-800">¿Por qué se anula esta carga?</label>
              <Input value={motivo} onChange={(e) => setMotivo(e.target.value)}
                     placeholder="Ej: se anotó dos veces / litros equivocados" className="h-9" autoFocus />
            </div>
            <Button size="sm" variant="primary" disabled={!motivo.trim()} onClick={anular}>Anular</Button>
            <Button size="sm" variant="outline" onClick={() => { setAnulando(null); setMotivo('') }}>Cancelar</Button>
          </CardContent>
        </Card>
      )}

      {isLoading ? (
        <div className="flex justify-center py-10"><Spinner /></div>
      ) : vista === 'ceco' ? (
        <Card><CardContent className="p-0">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-xs text-gray-500">
                <th className="p-2 text-left">CECO</th>
                <th className="p-2 text-left">Empresa</th>
                <th className="p-2 text-right">Equipos</th>
                <th className="p-2 text-right">Cargas</th>
                <th className="p-2 text-right">Litros</th>
                <th className="p-2 text-right">% del mes</th>
              </tr>
            </thead>
            <tbody>
              {porCeco.map((c) => (
                <tr key={c.ceco_id ?? 'sin'} className="border-b hover:bg-gray-50/50">
                  <td className="p-2 font-mono text-xs font-semibold">{c.ceco ?? '(sin CECO)'}</td>
                  <td className="p-2 text-gray-600">{c.ceco_empresa ?? '—'}</td>
                  <td className="p-2 text-right text-gray-600">{c.equipos}</td>
                  <td className="p-2 text-right text-gray-600">{c.despachos}</td>
                  <td className="p-2 text-right font-bold">{L(c.litros)} L</td>
                  <td className="p-2 text-right text-gray-500">
                    {totalLitros > 0 ? `${Math.round((Number(c.litros) / totalLitros) * 100)}%` : '—'}
                  </td>
                </tr>
              ))}
              {porCeco.length === 0 && (
                <tr><td colSpan={6} className="py-10 text-center text-sm text-gray-400">
                  Sin despachos registrados en {MESES[mes - 1]} {anio}.
                </td></tr>
              )}
            </tbody>
          </table>
        </CardContent></Card>
      ) : (
        <Card><CardContent className="p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-xs text-gray-500">
                  <th className="p-2 text-left">Fecha</th>
                  <th className="p-2 text-left">Turno</th>
                  <th className="p-2 text-left">Camión</th>
                  <th className="p-2 text-left">Equipo</th>
                  <th className="p-2 text-left">CECO</th>
                  <th className="p-2 text-left">Lugar</th>
                  <th className="p-2 text-right">Medidor</th>
                  <th className="p-2 text-right">Litros</th>
                  <th className="p-2 text-left">Operador</th>
                  <th className="p-2" />
                </tr>
              </thead>
              <tbody>
                {filtrados.map((d) => (
                  <tr key={d.id} className={`border-b hover:bg-gray-50/50 ${d.anulado ? 'opacity-50' : ''}`}>
                    <td className="whitespace-nowrap p-2">
                      {fmtFecha(d.fecha)}
                      {d.hora && <span className="text-gray-400"> {d.hora.slice(0, 5)}</span>}
                    </td>
                    <td className="p-2 text-gray-600">{d.turno ?? '—'}</td>
                    <td className="p-2">
                      <span className="inline-flex items-center gap-1 text-xs text-gray-600">
                        <Truck className="h-3 w-3" />{d.camion_patente ?? '—'}
                      </span>
                    </td>
                    <td className="p-2 font-medium">
                      {d.anulado ? <span className="line-through">{d.equipo}</span> : d.equipo}
                      {d.equipo_descripcion && <span className="block text-[10px] text-gray-400">{d.equipo_descripcion}</span>}
                    </td>
                    <td className="p-2 font-mono text-xs">{d.ceco ?? '—'}</td>
                    <td className="p-2 text-gray-600">{d.ubicacion ?? '—'}</td>
                    <td className="whitespace-nowrap p-2 text-right text-[11px] text-gray-500">
                      {d.meter_inicial != null && d.meter_final != null
                        ? `${L(d.meter_inicial)} → ${L(d.meter_final)}` : '—'}
                      {/* La foto del contador es lo que respalda los litros */}
                      <span className="mt-0.5 flex items-center justify-end gap-1">
                        {[d.foto_meter_inicial_url, d.foto_meter_final_url].map((u, i) => (
                          u ? (
                            <button key={i} onClick={() => window.open(u, '_blank')}
                                    title={i === 0 ? 'Foto del medidor inicial' : 'Foto del medidor final'}
                                    className="text-green-600 hover:text-green-800">
                              <Camera className="h-3.5 w-3.5" />
                            </button>
                          ) : <Camera key={i} className="h-3.5 w-3.5 text-gray-200" />
                        ))}
                      </span>
                      {d.sin_foto_motivo && (
                        <span className="block text-[9px] italic text-amber-700" title={d.sin_foto_motivo}>
                          sin foto
                        </span>
                      )}
                    </td>
                    <td className="p-2 text-right font-bold">{L(d.litros)}</td>
                    <td className="p-2 text-gray-600">{d.operador_nombre ?? '—'}</td>
                    <td className="p-2 text-right">
                      {!d.anulado && (
                        <button onClick={() => { setAnulando(d.id); setMotivo('') }} title="Anular esta carga"
                                className="text-gray-300 hover:text-red-600">
                          <Ban className="h-4 w-4" />
                        </button>
                      )}
                      {d.anulado && <span className="text-[10px] text-red-600">anulada</span>}
                    </td>
                  </tr>
                ))}
                {filtrados.length === 0 && (
                  <tr><td colSpan={10} className="py-10 text-center text-sm text-gray-400">
                    Sin despachos en {MESES[mes - 1]} {anio}.
                  </td></tr>
                )}
              </tbody>
            </table>
          </div>
        </CardContent></Card>
      )}
    </div>
  )
}
