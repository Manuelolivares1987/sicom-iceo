'use client'

// ============================================================================
// Panel — Inspecciones de terreno APR (MIG685)
// ----------------------------------------------------------------------------
// Lo que prevención y la administración del contrato necesitan ver de un
// golpe: cuánto se inspecciona, dónde fallan los controles (por etapa), qué
// desviaciones siguen abiertas y quién de la cuadrilla no está habilitado.
// ============================================================================

import { useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  AlertTriangle, Ban, Camera, CheckCircle2, ClipboardCheck, ExternalLink, FileDown,
  Loader2, ShieldAlert, Smartphone, X,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Modal } from '@/components/ui/modal'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import { supabase } from '@/lib/supabase'
import {
  ESTADO_LABEL, ESTADO_REQ_LABEL, RESULTADO_LABEL,
  cerrarDesviacion, getDesviaciones, getFaenasInspeccion, getHabilitacion, getInspecciones,
  subirFotoInspeccion,
  type InspeccionResumen,
} from '@/lib/services/prevencion-inspeccion'
import type { EvidenciaArchivo } from '@/lib/services/prevencion-reportabilidad'
import { descargarPdfInspeccion } from '@/components/prevencion/pdf-inspeccion-apr'

type Tab = 'resumen' | 'inspecciones' | 'desviaciones' | 'habilitacion'

const RES_CLASE: Record<string, string> = {
  conforme: 'bg-emerald-100 text-emerald-800',
  con_desviaciones: 'bg-amber-100 text-amber-800',
  critico: 'bg-red-600 text-white',
}
const REQ_CLASE = (estado: string, ok: boolean) =>
  !ok ? 'bg-red-100 text-red-800'
  : estado.startsWith('por_vencer_7') || estado.startsWith('por_vencer_14') ? 'bg-orange-100 text-orange-800'
  : estado.startsWith('por_vencer') ? 'bg-amber-50 text-amber-800'
  : estado === 'no_aplica' ? 'bg-slate-100 text-slate-500'
  : 'bg-emerald-50 text-emerald-800'

function primerDiaMes(offset = 0) {
  const d = new Date(); d.setMonth(d.getMonth() + offset, 1)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
}
const hoyISO = () => new Date().toISOString().slice(0, 10)

function Kpi({ label, value, sub, tone }: { label: string, value: string | number, sub?: string, tone?: 'bad' | 'warn' | 'ok' }) {
  return (
    <Card><CardContent className="p-3">
      <p className="text-[11px] uppercase text-muted-foreground">{label}</p>
      <p className={cn('text-2xl font-bold',
        tone === 'bad' ? 'text-red-700' : tone === 'warn' ? 'text-amber-700' : tone === 'ok' ? 'text-emerald-700' : '')}>{value}</p>
      {sub && <p className="text-[11px] text-muted-foreground">{sub}</p>}
    </CardContent></Card>
  )
}

export default function InspeccionesAprPage() {
  useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()
  const [tab, setTab] = useState<Tab>('resumen')
  const [desde, setDesde] = useState(primerDiaMes(-2))
  const [hasta, setHasta] = useState(hoyISO())
  const [faenaId, setFaenaId] = useState<string | null>(null)
  const [pdfId, setPdfId] = useState<string | null>(null)

  const { data: faenas } = useQuery({ queryKey: ['prev-insp-faenas'], queryFn: getFaenasInspeccion })
  const { data: insp, isLoading } = useQuery({
    queryKey: ['prev-insp-lista', desde, hasta, faenaId],
    queryFn: () => getInspecciones({ desde, hasta, faenaId }),
  })
  const { data: desv } = useQuery({ queryKey: ['prev-insp-desv'], queryFn: () => getDesviaciones({}) })
  const { data: hab } = useQuery({ queryKey: ['prev-habilitacion', 'CALAMA'], queryFn: () => getHabilitacion('CALAMA') })
  const ids = (insp ?? []).map((i) => i.id)
  const { data: items } = useQuery({
    queryKey: ['prev-insp-items', ids.join(',')],
    enabled: ids.length > 0,
    queryFn: async () => {
      const { data, error } = await supabase.from('prevencion_inspeccion_items')
        .select('inspeccion_id, item_codigo, etapa, respuesta').in('inspeccion_id', ids)
      if (error) throw error
      return data as { inspeccion_id: string, item_codigo: string, etapa: string, respuesta: string | null }[]
    },
  })

  const nombreFaena = (id: string) => (faenas ?? []).find((f) => f.faena_id === id)?.nombre ?? '—'

  const kpis = useMemo(() => {
    const l = insp ?? []
    const conPct = l.filter((i) => i.pct_cumplimiento != null)
    const prom = conPct.length ? Math.round(10 * conPct.reduce((s, i) => s + Number(i.pct_cumplimiento), 0) / conPct.length) / 10 : null
    const idsSet = new Set(l.map((i) => i.id))
    const dv = (desv ?? []).filter((d) => idsSet.has(d.inspeccion_id) || d.estado === 'abierta')
    const abiertas = (desv ?? []).filter((d) => d.estado === 'abierta')
    return {
      total: l.length,
      prom,
      criticas: l.filter((i) => i.resultado === 'critico').length,
      artPend: l.filter((i) => i.estado === 'pendiente_cierre_art').length,
      abiertas: abiertas.length,
      vencidas: abiertas.filter((d) => d.fecha_compromiso && d.fecha_compromiso < hoyISO()).length,
      dvTotal: dv.length,
    }
  }, [insp, desv])

  const porEtapa = useMemo(() => {
    const m = new Map<string, { c: number, n: number, orden: number }>()
    const ORDEN = 'TADEJCFR'
    for (const it of items ?? []) {
      const e = m.get(it.etapa) ?? { c: 0, n: 0, orden: ORDEN.indexOf(it.item_codigo[0]) }
      if (it.respuesta === 'cumple') e.c++
      if (it.respuesta === 'no_cumple') e.n++
      m.set(it.etapa, e)
    }
    return Array.from(m.entries()).sort((a, b) => a[1].orden - b[1].orden)
  }, [items])

  const porFaena = useMemo(() => {
    const m = new Map<string, InspeccionResumen[]>()
    for (const i of insp ?? []) m.set(i.faena_id, [...(m.get(i.faena_id) ?? []), i])
    return Array.from(m.entries())
  }, [insp])

  // ── Cierre de desviación ──
  const [cerrando, setCerrando] = useState<string | null>(null)
  const [obsCierre, setObsCierre] = useState('')
  const [fotoCierre, setFotoCierre] = useState<File | null>(null)
  const fileRef = useRef<HTMLInputElement>(null)
  const cerrar = useMutation({
    mutationFn: async () => {
      const d = (desv ?? []).find((x) => x.id === cerrando)
      if (!d) throw new Error('Desviación no encontrada')
      if (!obsCierre.trim()) throw new Error('Describa cómo se cerró')
      const evid: EvidenciaArchivo[] = []
      if (fotoCierre && d.prevencion_inspecciones) {
        evid.push(await subirFotoInspeccion(fotoCierre, d.prevencion_inspecciones.faena_id, hoyISO()))
      }
      await cerrarDesviacion(d.id, obsCierre.trim(), evid)
    },
    onSuccess: () => {
      toast.success('Desviación cerrada')
      setCerrando(null); setObsCierre(''); setFotoCierre(null)
      qc.invalidateQueries({ queryKey: ['prev-insp-desv'] })
    },
    onError: (e: any) => toast.error(e?.message ?? 'No se pudo cerrar'),
  })

  const pdf = async (i: InspeccionResumen) => {
    setPdfId(i.id)
    try { await descargarPdfInspeccion(i.id, nombreFaena(i.faena_id)) }
    catch (e: any) { toast.error(e?.message ?? 'No se pudo generar el PDF') }
    finally { setPdfId(null) }
  }

  const TABS: { k: Tab, l: string }[] = [
    { k: 'resumen', l: 'Resumen' },
    { k: 'inspecciones', l: `Inspecciones (${insp?.length ?? 0})` },
    { k: 'desviaciones', l: `Desviaciones abiertas (${kpis.abiertas})` },
    { k: 'habilitacion', l: 'Habilitación cuadrilla Calama' },
  ]

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold">
            <ClipboardCheck className="h-6 w-6 text-pillado-green-500" /> Inspecciones de terreno APR
          </h1>
          <p className="text-sm text-muted-foreground">
            Verificación de controles antes, durante y al término del trabajo — faenas de Calama.
          </p>
        </div>
        <Link href="/m/prevencion/inspeccion">
          <Button variant="outline" size="sm"><Smartphone className="mr-1.5 h-4 w-4" /> Abrir app de terreno</Button>
        </Link>
      </div>

      <div className="flex flex-wrap items-end gap-2">
        <Input label="Desde" type="date" value={desde} onChange={(e) => setDesde(e.target.value)} className="h-9 w-40" />
        <Input label="Hasta" type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} className="h-9 w-40" />
        <div className="flex flex-wrap gap-1.5">
          <Button size="sm" variant={faenaId === null ? 'primary' : 'outline'} onClick={() => setFaenaId(null)}>Todas</Button>
          {(faenas ?? []).map((f) => (
            <Button key={f.faena_id} size="sm" variant={faenaId === f.faena_id ? 'primary' : 'outline'}
                    onClick={() => setFaenaId(f.faena_id)}>{f.nombre}</Button>
          ))}
        </div>
      </div>

      <div className="flex gap-1 border-b">
        {TABS.map((t) => (
          <button key={t.k} onClick={() => setTab(t.k)}
                  className={cn('-mb-px border-b-2 px-3 py-2 text-sm font-medium',
                    tab === t.k ? 'border-pillado-green-500 text-gray-900' : 'border-transparent text-muted-foreground')}>
            {t.l}
          </button>
        ))}
      </div>

      {isLoading && <div className="flex justify-center py-12"><Spinner /></div>}

      {/* ── Resumen ── */}
      {tab === 'resumen' && !isLoading && (
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
            <Kpi label="Inspecciones" value={kpis.total} sub="en el período" />
            <Kpi label="Cumplimiento" value={kpis.prom == null ? '—' : `${kpis.prom}%`} sub="promedio"
                 tone={kpis.prom == null ? undefined : kpis.prom >= 90 ? 'ok' : kpis.prom >= 75 ? 'warn' : 'bad'} />
            <Kpi label="Críticas" value={kpis.criticas} sub="no habilitados o no aptos" tone={kpis.criticas ? 'bad' : 'ok'} />
            <Kpi label="Desv. abiertas" value={kpis.abiertas} tone={kpis.abiertas ? 'warn' : 'ok'} />
            <Kpi label="Desv. vencidas" value={kpis.vencidas} sub="plazo cumplido" tone={kpis.vencidas ? 'bad' : 'ok'} />
            <Kpi label="Falta cierre ART" value={kpis.artPend} sub="pendiente en Calama" tone={kpis.artPend ? 'warn' : 'ok'} />
          </div>

          <div className="grid gap-4 lg:grid-cols-2">
            <Card><CardContent className="space-y-2 p-4">
              <p className="text-sm font-semibold">Cumplimiento por etapa</p>
              <p className="text-[11px] text-muted-foreground">Dónde fallan los controles: cumple ÷ (cumple + no cumple).</p>
              {porEtapa.length === 0 && <p className="py-4 text-center text-sm text-muted-foreground">Sin datos en el período.</p>}
              {porEtapa.map(([etapa, v]) => {
                const pct = v.c + v.n ? Math.round(100 * v.c / (v.c + v.n)) : null
                return (
                  <div key={etapa}>
                    <div className="flex justify-between text-[12px]">
                      <span>{etapa}</span>
                      <span className="font-semibold">{pct == null ? '—' : `${pct}%`} <span className="font-normal text-muted-foreground">({v.n} no cumple)</span></span>
                    </div>
                    <div className="mt-0.5 h-2 overflow-hidden rounded-full bg-gray-100">
                      <div className={cn('h-full', pct == null ? '' : pct >= 90 ? 'bg-emerald-500' : pct >= 75 ? 'bg-amber-500' : 'bg-red-500')}
                           style={{ width: `${pct ?? 0}%` }} />
                    </div>
                  </div>
                )
              })}
            </CardContent></Card>

            <Card><CardContent className="p-4">
              <p className="mb-2 text-sm font-semibold">Por faena</p>
              <table className="w-full text-sm">
                <thead><tr className="text-left text-[11px] uppercase text-muted-foreground">
                  <th className="py-1">Faena</th><th className="text-right">Insp.</th><th className="text-right">Cumpl.</th><th className="text-right">Críticas</th>
                </tr></thead>
                <tbody>
                  {porFaena.map(([fid, l]) => {
                    const c = l.filter((i) => i.pct_cumplimiento != null)
                    const p = c.length ? Math.round(10 * c.reduce((s, i) => s + Number(i.pct_cumplimiento), 0) / c.length) / 10 : null
                    return (
                      <tr key={fid} className="border-t">
                        <td className="py-1.5">{nombreFaena(fid)}</td>
                        <td className="text-right">{l.length}</td>
                        <td className="text-right font-semibold">{p == null ? '—' : `${p}%`}</td>
                        <td className={cn('text-right', l.some((i) => i.resultado === 'critico') && 'font-bold text-red-700')}>
                          {l.filter((i) => i.resultado === 'critico').length}
                        </td>
                      </tr>
                    )
                  })}
                  {porFaena.length === 0 && <tr><td colSpan={4} className="py-4 text-center text-muted-foreground">Sin inspecciones en el período.</td></tr>}
                </tbody>
              </table>
            </CardContent></Card>
          </div>
        </div>
      )}

      {/* ── Inspecciones ── */}
      {tab === 'inspecciones' && !isLoading && (
        <Card><CardContent className="overflow-x-auto p-0">
          <table className="w-full text-sm">
            <thead className="bg-muted/50 text-left text-[11px] uppercase text-muted-foreground">
              <tr><th className="px-3 py-2">Fecha</th><th>Faena</th><th>Trabajo</th><th>Inspector</th>
                <th>Estado</th><th className="text-right">Cumpl.</th><th>Resultado</th><th></th></tr>
            </thead>
            <tbody>
              {(insp ?? []).map((i) => (
                <tr key={i.id} className="border-t">
                  <td className="whitespace-nowrap px-3 py-2">{i.fecha}</td>
                  <td className="whitespace-nowrap">{nombreFaena(i.faena_id)}</td>
                  <td className="max-w-[280px] truncate" title={i.trabajo}>{i.trabajo}{i.instalacion ? ` · ${i.instalacion}` : ''}</td>
                  <td className="whitespace-nowrap">{i.inspector_nombre ?? '—'}</td>
                  <td className="whitespace-nowrap text-[12px]">{ESTADO_LABEL[i.estado]}</td>
                  <td className="text-right font-semibold">{i.pct_cumplimiento == null ? '—' : `${i.pct_cumplimiento}%`}</td>
                  <td><span className={cn('rounded-full px-2 py-0.5 text-[11px] font-bold', RES_CLASE[i.resultado])}>{RESULTADO_LABEL[i.resultado]}</span></td>
                  <td className="pr-3 text-right">
                    <Button size="sm" variant="ghost" onClick={() => pdf(i)} disabled={pdfId === i.id} title="Informe PDF">
                      {pdfId === i.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <FileDown className="h-4 w-4" />}
                    </Button>
                  </td>
                </tr>
              ))}
              {!insp?.length && <tr><td colSpan={8} className="py-10 text-center text-muted-foreground">Sin inspecciones en el período.</td></tr>}
            </tbody>
          </table>
        </CardContent></Card>
      )}

      {/* ── Desviaciones ── */}
      {tab === 'desviaciones' && (
        <div className="space-y-2">
          {(desv ?? []).filter((d) => d.estado === 'abierta').map((d) => {
            const vencida = d.fecha_compromiso && d.fecha_compromiso < hoyISO()
            return (
              <Card key={d.id} className={cn(d.criticidad === 'alta' && 'border-red-300')}>
                <CardContent className="flex flex-wrap items-start gap-3 p-3">
                  <span className={cn('rounded px-1.5 py-0.5 text-[10px] font-bold uppercase',
                    d.criticidad === 'alta' ? 'bg-red-600 text-white' : d.criticidad === 'media' ? 'bg-amber-500 text-white' : 'bg-gray-400 text-white')}>
                    {d.criticidad}
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-medium">{d.descripcion}</p>
                    {d.accion && <p className="text-[12px] text-muted-foreground">Acción: {d.accion}</p>}
                    <p className="text-[11px] text-muted-foreground">
                      {d.prevencion_inspecciones?.fecha} · {nombreFaena(d.prevencion_inspecciones?.faena_id ?? '')} · {d.prevencion_inspecciones?.trabajo}
                      {d.item_codigo ? ` · punto ${d.item_codigo}` : ''} · origen: {d.origen}
                    </p>
                  </div>
                  <div className="text-right text-[12px]">
                    <p>{d.responsable ?? 'Sin responsable'}</p>
                    <p className={cn(vencida ? 'font-bold text-red-700' : 'text-muted-foreground')}>
                      {d.fecha_compromiso ? `Plazo ${d.fecha_compromiso}${vencida ? ' · VENCIDA' : ''}` : 'Sin plazo'}
                    </p>
                  </div>
                  <Button size="sm" variant="outline" onClick={() => setCerrando(d.id)}>
                    <CheckCircle2 className="mr-1 h-4 w-4" /> Cerrar
                  </Button>
                </CardContent>
              </Card>
            )
          })}
          {!(desv ?? []).some((d) => d.estado === 'abierta') && (
            <Card><CardContent className="py-10 text-center text-sm text-muted-foreground">No hay desviaciones abiertas.</CardContent></Card>
          )}
        </div>
      )}

      {/* ── Habilitación ── */}
      {tab === 'habilitacion' && (
        <div className="space-y-3">
          <div className="flex flex-wrap items-start gap-2 rounded-lg border border-blue-200 bg-blue-50 px-3 py-2 text-sm text-blue-900">
            <ShieldAlert className="mt-0.5 h-4 w-4 shrink-0" />
            <span className="flex-1">
              Lo que la inspección lee del control documental. «Sin registro» y «Vencido» dejan al trabajador
              <b> NO HABILITADO</b>. Los documentos se cargan en{' '}
              <Link href="/dashboard/prevencion/personal" className="font-semibold underline">Control documental personal <ExternalLink className="inline h-3 w-3" /></Link>
              {' '}(faena CALAMA). Si alguien no conduce, márquele «No aplica — No conduce en faena» en sus licencias.
            </span>
          </div>
          {!hab ? <div className="flex justify-center py-10"><Spinner /></div> : (
            <Card><CardContent className="overflow-x-auto p-0">
              <table className="w-full text-[12px]">
                <thead className="bg-muted/50 text-left uppercase text-muted-foreground">
                  <tr>
                    <th className="px-3 py-2 text-[11px]">Trabajador</th>
                    <th className="text-[11px]">Ejecuta</th>
                    <th className="text-[11px]">Conduce</th>
                    {hab.requisitos.map((r) => (
                      <th key={r.tipo_codigo} className="max-w-[110px] px-1 text-[10px] font-semibold normal-case" title={r.nombre}>
                        {r.nombre.split('—')[0].trim()}{r.aplica_a === 'conductor' ? ' (cond.)' : ''}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {hab.personas.map((p) => (
                    <tr key={p.personal_id} className="border-t">
                      <td className="whitespace-nowrap px-3 py-2 font-medium">
                        {p.nombre}
                        {p.rut_provisorio && <span className="ml-1 rounded bg-amber-100 px-1 text-[10px] text-amber-800">RUT pendiente</span>}
                      </td>
                      <td>{p.habilitado ? <CheckCircle2 className="h-4 w-4 text-emerald-600" /> : <Ban className="h-4 w-4 text-red-600" />}</td>
                      <td>{p.habilitado_conductor ? <CheckCircle2 className="h-4 w-4 text-emerald-600" /> : <Ban className="h-4 w-4 text-red-600" />}</td>
                      {hab.requisitos.map((r) => {
                        const q = p.requisitos.find((x) => x.tipo_codigo === r.tipo_codigo)
                        return (
                          <td key={r.tipo_codigo} className="px-1 py-1">
                            {q && <span className={cn('block rounded px-1 py-0.5 text-center text-[10px] font-semibold', REQ_CLASE(q.estado, q.ok))}
                                        title={q.vence ? `Vence ${q.vence}` : undefined}>
                              {ESTADO_REQ_LABEL[q.estado] ?? q.estado}
                            </span>}
                          </td>
                        )
                      })}
                    </tr>
                  ))}
                </tbody>
              </table>
            </CardContent></Card>
          )}
          {hab && hab.personas.some((p) => !p.habilitado) && (
            <p className="flex items-center gap-1 text-[12px] text-red-700">
              <AlertTriangle className="h-3.5 w-3.5" />
              {hab.personas.filter((p) => !p.habilitado).length} de {hab.personas.length} no pueden ejecutar hoy según el control documental.
            </p>
          )}
        </div>
      )}

      <Modal open={!!cerrando} onClose={() => setCerrando(null)} title="Cerrar desviación">
        <div className="space-y-3">
          <label className="block text-sm font-medium">¿Cómo se corrigió?</label>
          <textarea className="min-h-[80px] w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
                    value={obsCierre} onChange={(e) => setObsCierre(e.target.value)} />
          <input ref={fileRef} type="file" accept="image/*,.pdf" hidden
                 onChange={(e) => { setFotoCierre(e.target.files?.[0] ?? null); e.target.value = '' }} />
          <div className="flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={() => fileRef.current?.click()}>
              <Camera className="mr-1 h-4 w-4" /> Evidencia (opcional)
            </Button>
            {fotoCierre && (
              <span className="flex items-center gap-1 text-[12px]">{fotoCierre.name}
                <button onClick={() => setFotoCierre(null)}><X className="h-3 w-3" /></button></span>
            )}
          </div>
          <div className="flex gap-2">
            <Button className="flex-1" onClick={() => cerrar.mutate()} disabled={cerrar.isPending}>
              {cerrar.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />} Cerrar desviación
            </Button>
            <Button variant="outline" onClick={() => setCerrando(null)}>Cancelar</Button>
          </div>
        </div>
      </Modal>
    </div>
  )
}
