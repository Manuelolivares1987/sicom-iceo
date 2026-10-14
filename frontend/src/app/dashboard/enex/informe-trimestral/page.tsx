'use client'

// Informe trimestral ENEX (MIG590) — consolida los informes de servicio
// generados en el período. Pedido para Lomas Bayas Lubricantes; sirve para
// cualquier faena. Lo que se ve en pantalla es lo que sale en el PDF.

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import { ChevronLeft, ChevronRight, FileDown, FileText, Loader2, CalendarRange, AlertTriangle } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import {
  getFaenas, getInstalaciones, getPanelVentana, getItemsDeEjecuciones, getRequerimientosDeEjecuciones,
  getReprogramacionesDeProgramaciones, getEjecucionesMeta, getItemsDePautas, MESES, REQ_PRIORIDAD_LABEL, REQ_TIPO_LABEL,
  getLugarItems, getActividadesTrimestre, sincronizarTrimestre,
} from '@/lib/services/enex'
import { ventanaTrimestre, inicioTrimestreContractual, isoDe } from '@/lib/enex-avance'
import { armarInformeTrimestral } from '@/lib/enex-informe-trimestral'
import { descargarInformeTrimestral } from '@/components/enex/pdf-informe-trimestral-enex'

type Ancla = 'calendario' | 'contractual'
const pct = (n: number | null) => (n == null ? '—' : `${n.toLocaleString('es-CL', { maximumFractionDigits: 1 })} %`)
const fecha = (iso?: string | null) => (iso ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}` : '—')

/** Inicio del trimestre que se informa: el anterior si el actual recién empieza (primer mes). */
function inicioPorDefecto(hoy: string, ancla: Ancla): { anio: number; mes: number } {
  const [y, m] = hoy.split('-').map(Number)
  const cur = ancla === 'contractual' ? inicioTrimestreContractual(hoy) : { anio: y, mes: Math.floor((m - 1) / 3) * 3 + 1 }
  if (cur.anio === y && cur.mes === m) {
    let mm = cur.mes - 3, a = cur.anio
    if (mm < 1) { mm += 12; a-- }
    return { anio: a, mes: mm }
  }
  return cur
}

export default function InformeTrimestralPage() {
  const { perfil } = useRequireAuth()
  const toast = useToast()
  const [hoy, setHoy] = useState('')
  const [ancla, setAncla] = useState<Ancla>('calendario')
  const [inicio, setInicio] = useState<{ anio: number; mes: number } | null>(null)
  const [faenaId, setFaenaId] = useState<string | null>(null)
  const [comentarios, setComentarios] = useState('')
  const [generando, setGenerando] = useState(false)
  useEffect(() => { const h = isoDe(new Date()); setHoy(h); setInicio(inicioPorDefecto(h, 'calendario')) }, [])

  const { data: faenas = [] } = useQuery({ queryKey: ['enex-faenas'], queryFn: getFaenas, staleTime: 5 * 60_000 })
  // Por defecto Lomas Bayas Lubricantes (el pedido original).
  useEffect(() => {
    if (!faenaId && faenas.length) setFaenaId((faenas.find((f) => f.codigo === 'LB_LUB') ?? faenas[0]).id)
  }, [faenas, faenaId])
  const faena = faenas.find((f) => f.id === faenaId) ?? null
  const ventana = useMemo(() => (inicio ? ventanaTrimestre(inicio.anio, inicio.mes) : null), [inicio])

  const { data: instalaciones = [] } = useQuery({
    queryKey: ['enex-inst', faenaId], queryFn: () => getInstalaciones(faenaId ?? undefined), enabled: !!faenaId, staleTime: 60_000,
  })

  const { data: inf, isLoading, error } = useQuery({
    queryKey: ['enex-informe-trimestral', faenaId, ventana?.desde],
    enabled: !!faenaId && !!ventana,
    staleTime: 30_000,
    queryFn: async () => {
      const rows = await getPanelVentana(ventana!.meses, faenaId!)
      const eids = rows.map((r) => r.ejecucion_id).filter(Boolean) as string[]
      const [items, reqs, reprogs, metas] = await Promise.all([
        getItemsDeEjecuciones(eids), getRequerimientosDeEjecuciones(eids),
        getReprogramacionesDeProgramaciones(rows.map((r) => r.programacion_id)), getEjecucionesMeta(eids),
      ])
      const pautaItems = await getItemsDePautas(Array.from(new Set(metas.map((m) => m.pauta_id).filter(Boolean))) as string[])
      // Pauta por lugar (Lomas): avance por actividad del trimestre que parte en `desde`.
      const lugarItems = await getLugarItems(faenaId!)
      let actividades: Awaited<ReturnType<typeof getActividadesTrimestre>> = []
      if (lugarItems.length > 0) {
        try { await sincronizarTrimestre(faenaId!, ventana!.desde) } catch { /* se muestra lo guardado */ }
        actividades = await getActividadesTrimestre(lugarItems.map((i) => i.lugar_item_id), ventana!.desde)
      }
      return { rows, items, reqs, reprogs, metas, pautaItems, lugarItems, actividades }
    },
  })

  const informe = useMemo(() => {
    if (!inf || !ventana) return null
    const area = new Map(instalaciones.map((i) => [i.id, i.area]))
    return armarInformeTrimestral({ ...inf, meses: ventana.meses, areaDe: (id) => area.get(id) ?? null, hoy })
  }, [inf, ventana, instalaciones, hoy])

  function mover(delta: number) {
    if (!inicio) return
    let m = inicio.mes + delta, a = inicio.anio
    while (m < 1) { m += 12; a-- }
    while (m > 12) { m -= 12; a++ }
    setInicio({ anio: a, mes: m })
  }
  function cambiarAncla(a: Ancla) { setAncla(a); if (hoy) setInicio(inicioPorDefecto(hoy, a)) }

  if (!ventana || !hoy) return <div className="flex justify-center p-10"><Spinner /></div>
  const m0 = ventana.meses[0], m2 = ventana.meses[2]
  const periodo = `${MESES[m0.mes - 1]}${m0.anio !== m2.anio ? ` ${m0.anio}` : ''} – ${MESES[m2.mes - 1]} ${m2.anio}`

  async function pdf() {
    if (!informe || !faena || !ventana) return
    setGenerando(true)
    try {
      await descargarInformeTrimestral({
        inf: informe, faena, periodo, desde: ventana.desde, hasta: ventana.hasta, comentarios,
        elaboradoPor: perfil?.nombre_completo ?? '', emitido: hoy,
      })
      toast.success('Informe trimestral descargado')
    } catch (e) { toast.error((e as Error).message) } finally { setGenerando(false) }
  }

  const r = informe?.resumen
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-xl font-bold"><FileText className="h-5 w-5 text-blue-700" /> Informe trimestral ENEX</h1>
          <p className="mt-0.5 text-sm text-gray-500">Consolidado de los informes de servicio del período: cumplimiento, cobertura de pauta, hallazgos y requerimientos.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link href="/dashboard/enex/planificacion"><Button variant="outline"><CalendarRange className="mr-1 h-4 w-4" /> Planificación</Button></Link>
          <Link href="/dashboard/enex/informes"><Button variant="outline"><FileText className="mr-1 h-4 w-4" /> Informes por servicio</Button></Link>
          <Button disabled={!informe || generando || (r?.programados ?? 0) === 0} onClick={pdf}>
            {generando ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : <FileDown className="mr-1 h-4 w-4" />} Descargar PDF
          </Button>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <select value={faenaId ?? ''} onChange={(e) => setFaenaId(e.target.value)} className="rounded-lg border px-2 py-1.5 text-sm">
          {faenas.map((f) => <option key={f.id} value={f.id}>{f.nombre}</option>)}
        </select>
        <div className="flex overflow-hidden rounded-lg border">
          {([['calendario', 'Trimestre calendario'], ['contractual', 'Trimestre ENEX (Feb)']] as const).map(([k, l]) => (
            <button key={k} onClick={() => cambiarAncla(k)}
                    className={`px-2.5 py-1.5 text-xs font-semibold ${ancla === k ? 'bg-blue-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'}`}>{l}</button>
          ))}
        </div>
        <button onClick={() => mover(-3)} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50" aria-label="Trimestre anterior"><ChevronLeft className="h-4 w-4" /></button>
        <span className="min-w-[200px] text-center text-sm font-semibold capitalize">{periodo}</span>
        <button onClick={() => mover(3)} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50" aria-label="Trimestre siguiente"><ChevronRight className="h-4 w-4" /></button>
        {isLoading && <Spinner className="h-4 w-4" />}
      </div>

      {error && <p className="text-sm text-red-600">{(error as Error).message}</p>}

      {informe && r && (
        r.programados === 0 ? (
          <Card><CardContent className="p-8 text-center text-sm text-gray-500">No hay servicios programados para {faena?.nombre} en {periodo}.</CardContent></Card>
        ) : (
        <>
          <div className="grid grid-cols-2 gap-2 md:grid-cols-4">
            <Kpi t="Cumplimiento contractual" v={pct(r.pctCumplimiento)} s={`${r.cumplidos} de ${r.programados} con firma · ${r.tramo.etiqueta}`} />
            <Kpi t="Ejecución en terreno" v={pct(r.pctEjecucion)} s={`${r.ejecutados} ejecutados · ${r.sinFirma} sin firma`} />
            <Kpi t="Actividades registradas" v={String(r.actividades)} s={`${r.informesPdf} informes PDF · ${r.horasTerreno.toLocaleString('es-CL')} h con cronómetro`} />
            <Kpi t="Hallazgos / requerimientos" v={`${r.hallazgos} / ${r.requerimientos}`} s={`${r.requerimientosAlta} alta · ${r.reprogramaciones} reprogramaciones`} />
          </div>

          <Card><CardContent className="space-y-3 p-4">
            <h2 className="text-sm font-semibold">Resumen ejecutivo</h2>
            <p className="text-sm leading-relaxed text-gray-700">{informe.conclusion}</p>
            <div>
              <label className="text-xs font-medium text-gray-600">Comentarios del administrador de contrato (salen en el PDF)</label>
              <textarea value={comentarios} onChange={(e) => setComentarios(e.target.value)} rows={3}
                        className="mt-1 w-full rounded border px-2 py-1.5 text-sm" placeholder="Contexto del trimestre, acuerdos con ESM, próximos pasos…" />
            </div>
          </CardContent></Card>

          <Seccion titulo="Cumplimiento por mes">
            <table className="w-full text-sm">
              <thead><tr className="border-b text-xs text-gray-500"><th className="p-2 text-left">Mes</th><th className="p-2 text-right">Programados</th><th className="p-2 text-right">Ejecutados</th><th className="p-2 text-right">Cumplidos (firma)</th><th className="p-2 text-right">KPI</th></tr></thead>
              <tbody>{informe.porMes.map((m) => (
                <tr key={`${m.anio}-${m.mes}`} className="border-b"><td className="p-2 capitalize">{MESES[m.mes - 1]} {m.anio}</td><td className="p-2 text-right">{m.programados}</td><td className="p-2 text-right">{m.ejecutados}</td><td className="p-2 text-right">{m.cumplidos}</td><td className="p-2 text-right font-semibold">{pct(m.pct)}</td></tr>
              ))}</tbody>
            </table>
          </Seccion>

          <Seccion titulo="Detalle por punto">
            <table className="w-full text-sm">
              <thead><tr className="border-b text-xs text-gray-500">
                <th className="p-2 text-left">Punto</th><th className="p-2 text-center">Prog.</th><th className="p-2 text-center">Ejec.</th><th className="p-2 text-center">Firma</th>
                <th className="p-2 text-left">Fechas</th><th className="p-2 text-center">Actividades</th><th className="p-2 text-center">NO OK</th><th className="p-2 text-center">Req.</th><th className="p-2 text-left">Informes</th>
              </tr></thead>
              <tbody>{informe.puntos.map((p) => (
                <tr key={p.instalacion_id} className="border-b align-top">
                  <td className="p-2 font-medium">{p.instalacion}<div className="text-[11px] font-normal text-gray-500">{p.tecnicos.join(' / ')}</div></td>
                  <td className="p-2 text-center">{p.programados}</td><td className="p-2 text-center">{p.ejecutados}</td>
                  <td className={`p-2 text-center ${p.cumplidos < p.ejecutados ? 'text-amber-700' : ''}`}>{p.cumplidos}</td>
                  <td className="p-2 text-xs">{p.fechas.map(fecha).join(', ') || '—'}</td>
                  <td className="p-2 text-center">{p.actividades}</td>
                  <td className={`p-2 text-center ${p.hallazgos ? 'font-semibold text-red-700' : ''}`}>{p.hallazgos}</td>
                  <td className="p-2 text-center">{p.requerimientos}</td>
                  <td className="p-2 text-xs">{p.informes.length === 0 ? '—' : p.informes.map((i) => (
                    <a key={i.url} href={i.url} target="_blank" rel="noreferrer" className="mr-2 text-blue-600 underline">{fecha(i.fecha)}</a>
                  ))}</td>
                </tr>
              ))}</tbody>
            </table>
          </Seccion>

          {informe.pautaLugar && (
            <Seccion titulo="Avance de la pauta trimestral por lugar">
              <div className="space-y-3 p-3">
                <div className="grid gap-2 md:grid-cols-3">
                  {[...informe.pautaLugar.areas, ...(informe.pautaLugar.areas.length > 1 ? [informe.pautaLugar.total] : [])].map((a) => (
                    <div key={a.area} className={`rounded-lg border p-2 ${a.area === 'Total' ? 'border-blue-300 bg-blue-50/40' : ''}`}>
                      <div className="text-xs font-semibold text-gray-700">{a.area === 'Total' ? 'Total faena' : a.area}</div>
                      <div className="text-xl font-bold tabular-nums">{pct(a.pctReal)} <span className="text-sm font-semibold text-blue-700">· proy. {pct(a.pctProyectado)}</span></div>
                      <div className="text-[11px] text-gray-500">{a.ejecutadas} de {a.total} ejecutadas{a.noAplica ? ` · ${a.noAplica} n/a` : ''}{a.atrasadas ? ` · ${a.atrasadas} atrasadas` : ''}</div>
                    </div>
                  ))}
                </div>
                {informe.pautaLugar.sinInforme.length > 0 && (
                  <div className="rounded-lg border border-amber-200 bg-amber-50 p-2 text-xs text-amber-900">
                    <div className="mb-1 flex items-center gap-1 font-semibold"><AlertTriangle className="h-3.5 w-3.5" /> Ejecutadas según planilla, sin informe de terreno en SICOM ({informe.pautaLugar.sinInforme.length})</div>
                    <ul className="grid gap-0.5 md:grid-cols-2">{informe.pautaLugar.sinInforme.map((x, i) => <li key={i}>{x.area.replace('Truck Shop ', '')} · {x.lugar} · <b>{x.codigo}</b> {x.descripcion} {x.fecha ? `(${fecha(x.fecha)})` : ''}</li>)}</ul>
                  </div>
                )}
                {informe.pautaLugar.faltantes.length > 0 && (
                  <div className="rounded-lg border p-2 text-xs text-gray-700">
                    <div className="mb-1 font-semibold">Sin ejecutar en el trimestre ({informe.pautaLugar.faltantes.length})</div>
                    <ul className="grid gap-0.5 md:grid-cols-2">{informe.pautaLugar.faltantes.map((x, i) => <li key={i}>{x.area.replace('Truck Shop ', '')} · {x.lugar} · <b>{x.codigo}</b> {x.descripcion}{x.estado !== 'pendiente' ? ` — ${x.estado}${x.fecha ? ` ${fecha(x.fecha)}` : ''}` : ''}</li>)}</ul>
                  </div>
                )}
              </div>
            </Seccion>
          )}

          {!informe.pautaLugar && <Seccion titulo="Cobertura de la pauta trimestral">
            <div className="space-y-2 p-3">
              {informe.cobertura.length === 0 ? <p className="text-sm text-gray-400">Sin ejecuciones con pauta en el período.</p> : informe.cobertura.map((c) => (
                <div key={c.pauta_id}>
                  <p className="text-sm"><b>{c.hechas}</b> de <b>{c.trimestrales - c.noAplica}</b> actividades trimestrales aplicables registradas ({pct(c.pct)}){c.noAplica ? ` · ${c.noAplica} «no aplica»` : ''}.</p>
                  {c.pendientes.length > 0 && (
                    <div className="mt-1 rounded-lg border border-amber-200 bg-amber-50 p-2 text-xs text-amber-900">
                      <div className="mb-1 flex items-center gap-1 font-semibold"><AlertTriangle className="h-3.5 w-3.5" /> Sin registro en el período</div>
                      <ul className="grid gap-0.5 md:grid-cols-2">{c.pendientes.map((x, i) => <li key={i}><b>{x.codigo}</b> {x.descripcion}</li>)}</ul>
                    </div>
                  )}
                </div>
              ))}
            </div>
          </Seccion>}

          <Seccion titulo={`Hallazgos (${informe.hallazgos.length})`}>
            <table className="w-full text-sm">
              <thead><tr className="border-b text-xs text-gray-500"><th className="p-2 text-left">Fecha</th><th className="p-2 text-left">Punto</th><th className="p-2 text-left">Actividad</th><th className="p-2 text-left">Observación</th></tr></thead>
              <tbody>{informe.hallazgos.length === 0 ? <tr><td colSpan={4} className="p-3 text-center text-gray-400">Sin hallazgos.</td></tr> : informe.hallazgos.map((h, i) => (
                <tr key={i} className="border-b align-top"><td className="p-2">{fecha(h.fecha)}</td><td className="p-2">{h.instalacion}</td><td className="p-2"><b>{h.codigo}</b> {h.descripcion}</td><td className="p-2 text-gray-600">{h.observacion ?? '—'}{h.medicion ? ` · ${h.medicion}` : ''}</td></tr>
              ))}</tbody>
            </table>
          </Seccion>

          <Seccion titulo={`Requerimientos y comentarios (${informe.requerimientos.length})`}>
            <table className="w-full text-sm">
              <thead><tr className="border-b text-xs text-gray-500"><th className="p-2 text-left">Fecha</th><th className="p-2 text-left">Punto</th><th className="p-2 text-left">Tipo</th><th className="p-2 text-left">Prioridad</th><th className="p-2 text-left">Detalle</th></tr></thead>
              <tbody>{informe.requerimientos.length === 0 ? <tr><td colSpan={5} className="p-3 text-center text-gray-400">Sin requerimientos.</td></tr> : informe.requerimientos.map((q) => (
                <tr key={q.id} className="border-b align-top">
                  <td className="p-2">{fecha(q.fecha)}</td><td className="p-2">{q.instalacion}</td><td className="p-2">{REQ_TIPO_LABEL[q.tipo]}</td>
                  <td className={`p-2 ${q.prioridad === 'alta' ? 'font-semibold text-red-700' : ''}`}>{REQ_PRIORIDAD_LABEL[q.prioridad]}</td>
                  <td className="p-2">{q.titulo ? <b>{q.titulo} — </b> : null}{q.descripcion}</td>
                </tr>
              ))}</tbody>
            </table>
          </Seccion>

          {informe.reprogramaciones.length > 0 && (
            <Seccion titulo={`Reprogramaciones (${informe.reprogramaciones.length})`}>
              <ul className="space-y-1 p-3 text-sm">{informe.reprogramaciones.map((x) => (
                <li key={x.id}><b>{x.instalacion ?? x.patente}</b> · {fecha(x.fecha_original)} → {fecha(x.nueva_fecha)} · {x.descripcion}</li>
              ))}</ul>
            </Seccion>
          )}
        </>
        )
      )}
    </div>
  )
}

function Kpi({ t, v, s }: { t: string; v: string; s: string }) {
  return (
    <div className="rounded-xl border bg-white p-3">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-gray-500">{t}</div>
      <div className="mt-0.5 text-2xl font-bold tabular-nums text-gray-900">{v}</div>
      <div className="text-[11px] text-gray-500">{s}</div>
    </div>
  )
}

function Seccion({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <Card><CardContent className="p-0">
      <h2 className="border-b px-3 py-2 text-sm font-semibold">{titulo}</h2>
      <div className="overflow-x-auto">{children}</div>
    </CardContent></Card>
  )
}
