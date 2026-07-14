'use client'

// Informes ENEX — buscador de los PDF generados por las ejecuciones de
// mantención y calibración (formato del mandante). Se filtra por mes, día
// específico, faena y tipo de servicio; cada fila lleva al PDF guardado.

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import {
  ArrowLeft, ChevronLeft, ChevronRight, FileText, Printer, CheckCircle2, Clock,
  FileSpreadsheet, X,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getFaenas, getInformesMes, MESES,
  type EnexPanelRow, type TipoServicio,
} from '@/lib/services/enex'
import { generarYGuardarInformeEnex } from '@/components/enex/pdf-informe-enex'

const hoy = () => { const d = new Date(); return { anio: d.getFullYear(), mes: d.getMonth() + 1 } }

function fmtFecha(iso?: string | null): string {
  if (!iso) return '—'
  const [y, m, d] = iso.slice(0, 10).split('-')
  return `${d}-${m}-${y}`
}

export default function EnexInformesPage() {
  useRequireAuth()
  const toast = useToast()
  const [{ anio, mes }, setPeriodo] = useState(hoy())
  const [faenaSel, setFaenaSel] = useState<string>('')
  const [tipoSel, setTipoSel] = useState<'' | TipoServicio>('')
  const [dia, setDia] = useState<string>('')          // yyyy-mm-dd opcional
  const [buscar, setBuscar] = useState('')
  const [generando, setGenerando] = useState<string | null>(null)

  const { data: faenas = [] } = useQuery({ queryKey: ['enex-faenas'], queryFn: getFaenas, staleTime: 5 * 60_000 })
  const { data: informes = [], isLoading, refetch } = useQuery({
    queryKey: ['enex-informes', anio, mes, faenaSel],
    queryFn: () => getInformesMes(anio, mes, faenaSel || undefined),
    staleTime: 15_000,
  })

  function cambiarMes(delta: number) {
    let m = mes + delta, a = anio
    if (m < 1) { m = 12; a-- } else if (m > 12) { m = 1; a++ }
    setPeriodo({ anio: a, mes: m })
    setDia('')
  }

  const filtrados = useMemo(() => {
    const q = buscar.trim().toLowerCase()
    return informes
      .filter((r) => !tipoSel || r.tipo_servicio === tipoSel)
      .filter((r) => !dia || (r.fecha_ejecucion ?? '').slice(0, 10) === dia)
      .filter((r) => !q || r.instalacion.toLowerCase().includes(q) ||
        (r.ot_numero ?? '').toLowerCase().includes(q) || (r.ejecutor ?? '').toLowerCase().includes(q))
  }, [informes, tipoSel, dia, buscar])

  const conPdf = filtrados.filter((r) => r.informe_pdf_url).length

  async function generar(r: EnexPanelRow) {
    if (!r.ejecucion_id) return
    setGenerando(r.ejecucion_id)
    try {
      const url = await generarYGuardarInformeEnex(r.ejecucion_id)
      toast.success('Informe PDF generado')
      window.open(url, '_blank')
      refetch()
    } catch (e) { toast.error((e as Error).message) } finally { setGenerando(null) }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <Link href="/dashboard/enex" className="inline-flex items-center gap-1 text-xs text-gray-500 hover:text-gray-700">
            <ArrowLeft className="h-3.5 w-3.5" /> Control ENEX
          </Link>
          <h1 className="text-xl font-bold flex items-center gap-2">
            <FileText className="h-5 w-5 text-blue-700" /> Informes ENEX
          </h1>
          <p className="text-sm text-gray-500 mt-0.5">
            Certificados de calibración y OT de mantenimiento generados en terreno — busca por mes, día o instalación.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={() => cambiarMes(-1)} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50"><ChevronLeft className="h-4 w-4" /></button>
          <span className="min-w-[130px] text-center text-sm font-semibold">{MESES[mes - 1]} {anio}</span>
          <button onClick={() => cambiarMes(1)} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50"><ChevronRight className="h-4 w-4" /></button>
        </div>
      </div>

      {/* Filtros */}
      <Card>
        <CardContent className="flex flex-wrap items-end gap-3 p-3">
          <div>
            <label className="text-xs font-medium">Faena</label>
            <select value={faenaSel} onChange={(e) => setFaenaSel(e.target.value)}
                    className="block h-9 rounded border px-2 text-sm">
              <option value="">Todas</option>
              {faenas.map((f) => <option key={f.id} value={f.id}>{f.nombre}</option>)}
            </select>
          </div>
          <div>
            <label className="text-xs font-medium">Servicio</label>
            <select value={tipoSel} onChange={(e) => setTipoSel(e.target.value as '' | TipoServicio)}
                    className="block h-9 rounded border px-2 text-sm">
              <option value="">Todos</option>
              <option value="mantencion">Mantención</option>
              <option value="calibracion">Calibración</option>
            </select>
          </div>
          <div>
            <label className="text-xs font-medium">Día específico</label>
            <div className="flex items-center gap-1">
              <Input type="date" value={dia} onChange={(e) => setDia(e.target.value)} className="h-9" />
              {dia && (
                <button onClick={() => setDia('')} title="Quitar filtro de día"
                        className="rounded border p-2 text-gray-400 hover:text-gray-600"><X className="h-4 w-4" /></button>
              )}
            </div>
          </div>
          <div className="flex-1 min-w-[180px]">
            <label className="text-xs font-medium">Buscar</label>
            <Input value={buscar} onChange={(e) => setBuscar(e.target.value)}
                   placeholder="Instalación, N° OT o ejecutor…" className="h-9" />
          </div>
          <div className="text-xs text-gray-500 pb-2">
            {filtrados.length} servicio{filtrados.length !== 1 ? 's' : ''} · {conPdf} con PDF
          </div>
        </CardContent>
      </Card>

      {/* Lista */}
      <Card>
        <CardContent className="p-0">
          {isLoading ? (
            <div className="flex justify-center py-10"><Spinner /></div>
          ) : filtrados.length === 0 ? (
            <p className="py-10 text-center text-sm text-gray-400">
              No hay servicios ejecutados en {MESES[mes - 1]} {anio}{dia ? ` el día ${fmtFecha(dia)}` : ''} con estos filtros.
            </p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-xs text-gray-500">
                    <th className="p-2 text-left">Fecha ejec.</th>
                    <th className="p-2 text-left">Instalación</th>
                    <th className="p-2 text-left">Faena</th>
                    <th className="p-2 text-left">Servicio</th>
                    <th className="p-2 text-left">N° OT</th>
                    <th className="p-2 text-left">Ejecutor</th>
                    <th className="p-2 text-center">Estado</th>
                    <th className="p-2 text-center">Informe</th>
                  </tr>
                </thead>
                <tbody>
                  {filtrados.map((r) => (
                    <tr key={r.programacion_id} className="border-b hover:bg-gray-50/50">
                      <td className="p-2 whitespace-nowrap">{fmtFecha(r.fecha_ejecucion)}</td>
                      <td className="p-2 font-medium">{r.instalacion}{r.patente ? ` · ${r.patente}` : ''}</td>
                      <td className="p-2 text-gray-500">{r.faena}</td>
                      <td className="p-2">{r.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención'}</td>
                      <td className="p-2 font-mono text-xs">{r.ot_numero ?? '—'}</td>
                      <td className="p-2 text-gray-600">{r.ejecutor ?? '—'}</td>
                      <td className="p-2 text-center">
                        {r.cumplida
                          ? <span className="inline-flex items-center gap-1 rounded-full bg-green-100 px-2 py-0.5 text-[11px] font-semibold text-green-700"><CheckCircle2 className="h-3 w-3" /> Cumplida</span>
                          : <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-semibold text-amber-800"><Clock className="h-3 w-3" /> Falta firma</span>}
                      </td>
                      <td className="p-2 text-center">
                        <div className="flex items-center justify-center gap-1.5">
                          {r.informe_pdf_url ? (
                            <Button size="sm" variant="primary" onClick={() => window.open(r.informe_pdf_url!, '_blank')}>
                              <FileSpreadsheet className="h-3.5 w-3.5 mr-1" /> PDF
                            </Button>
                          ) : r.ejecucion_id ? (
                            <Button size="sm" variant="outline" disabled={generando === r.ejecucion_id}
                                    onClick={() => generar(r)}>
                              {generando === r.ejecucion_id ? <Spinner className="h-3.5 w-3.5 mr-1" /> : <FileSpreadsheet className="h-3.5 w-3.5 mr-1" />}
                              Generar
                            </Button>
                          ) : null}
                          {r.ejecucion_id && (
                            <button title="Vista imprimible" onClick={() => window.open(`/enex-reporte/${r.ejecucion_id}`, '_blank')}
                                    className="rounded border p-1.5 text-gray-400 hover:text-gray-600">
                              <Printer className="h-3.5 w-3.5" />
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
