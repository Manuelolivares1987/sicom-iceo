'use client'

// Editar un informe ENEX completo desde la oficina (MIG588).
//
// El lápiz de /dashboard/enex/informes trae aquí. Se corrige todo lo que sale
// en el PDF: datos del servicio, resultado / medición / observación de cada
// actividad, fotos del antes y del después (poner o sacar), el registro
// fotográfico complementario y la observación general.
//
// No es la pantalla de terreno: aquí no corre cronómetro, no se firma y no
// cambia el estado del servicio. Con la firma de ESM puesta queda de solo
// lectura: lo que ESM firmó es lo que ESM vio.

import { useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useParams, useRouter } from 'next/navigation'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  ArrowLeft, Check, X, Minus, Ruler, Plus, Trash2, Lock, Save, Loader2, ImagePlus, FileSpreadsheet,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getEjecucionReporte, getPautaItems, getEjecucionItems, guardarInformeEnex, subirFotoInformeEnex,
  type EnexPautaItem, type EnexInformeItemEdit,
} from '@/lib/services/enex'
import { generarYGuardarInformeEnex } from '@/components/enex/pdf-informe-enex'

type Act = { resultado: string; valor: string; obs: string; antes: string[]; despues: string[] }
const vacia = (): Act => ({ resultado: '', valor: '', obs: '', antes: [], despues: [] })
const tieneAlgo = (a: Act) =>
  !!(a.resultado || a.valor.trim() || a.obs.trim() || a.antes.length || a.despues.length)

type FilaServidor = {
  pauta_item_id: string; resultado: string | null; valor_medicion: number | string | null
  observacion: string | null; foto_url: string | null
  foto_antes_url: string | null; foto_despues_url: string | null
  fotos_antes: string[] | null; fotos_despues: string[] | null
}

function toleranciaTexto(it: EnexPautaItem): string {
  const ref = it.valor_referencia ?? 0
  const lo = it.tolerancia_min != null ? ref + it.tolerancia_min : null
  const hi = it.tolerancia_max != null ? ref + it.tolerancia_max : null
  if (lo != null && hi != null) return `${lo} a ${hi} ${it.unidad ?? ''}`
  if (hi != null) return `≤ ${hi} ${it.unidad ?? ''}`
  if (lo != null) return `≥ ${lo} ${it.unidad ?? ''}`
  return it.unidad ?? ''
}
function dentroTol(it: EnexPautaItem, v: string): boolean | null {
  if (it.tipo_campo !== 'medicion' || v.trim() === '') return null
  if (it.tolerancia_min == null && it.tolerancia_max == null) return null
  const val = Number(v), ref = it.valor_referencia ?? 0
  return (it.tolerancia_min == null || val >= ref + it.tolerancia_min)
      && (it.tolerancia_max == null || val <= ref + it.tolerancia_max)
}

/** Galería editable: miniaturas con quitar + botón para subir más. */
function Galeria({
  titulo, fotos, bloqueado, subiendo, onAgregar, onQuitar,
}: {
  titulo: string; fotos: string[]; bloqueado: boolean; subiendo: boolean
  onAgregar: (files: FileList) => void; onQuitar: (url: string) => void
}) {
  const ref = useRef<HTMLInputElement | null>(null)
  return (
    <div>
      <div className="mb-1 flex items-center justify-between">
        <span className="text-[11px] font-semibold text-gray-600">{titulo} ({fotos.length})</span>
        {!bloqueado && (
          <button type="button" onClick={() => ref.current?.click()} disabled={subiendo}
                  className="inline-flex items-center gap-1 rounded border border-gray-300 bg-white px-2 py-0.5 text-[11px] font-semibold text-gray-600 hover:bg-gray-50 disabled:opacity-50">
            {subiendo ? <Loader2 className="h-3 w-3 animate-spin" /> : <Plus className="h-3 w-3" />} Agregar
          </button>
        )}
      </div>
      <div className="flex min-h-[3.5rem] flex-wrap gap-1.5 rounded border border-dashed border-gray-200 bg-gray-50/50 p-1.5">
        {fotos.length === 0 && <span className="self-center text-[11px] text-gray-400">Sin fotos</span>}
        {fotos.map((u) => (
          <div key={u} className="group relative">
            <a href={u} target="_blank" rel="noreferrer">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={u} alt={titulo} className="h-16 w-16 rounded border object-cover" />
            </a>
            {!bloqueado && (
              <button type="button" onClick={() => onQuitar(u)} title="Sacar del informe"
                      className="absolute -right-1.5 -top-1.5 rounded-full bg-white p-0.5 shadow">
                <Trash2 className="h-3.5 w-3.5 text-red-500" />
              </button>
            )}
          </div>
        ))}
      </div>
      <input ref={ref} type="file" accept="image/*" multiple className="hidden"
             onChange={(e) => { if (e.target.files?.length) onAgregar(e.target.files); e.target.value = '' }} />
    </div>
  )
}

export default function EditarInformeEnexPage() {
  useRequireAuth()
  const params = useParams()
  const router = useRouter()
  const toast = useToast()
  const qc = useQueryClient()
  const ejecucionId = params?.id as string

  const { data: rep, isLoading: cargandoRep, refetch } = useQuery({
    queryKey: ['enex-informe-editar', ejecucionId],
    queryFn: () => getEjecucionReporte(ejecucionId),
    enabled: !!ejecucionId, staleTime: 0,
  })
  const reporte = rep?.reporte ?? null
  const { data: pautaItems = [], isLoading: cargandoPauta } = useQuery({
    queryKey: ['enex-pauta-items-web', reporte?.pauta_id],
    queryFn: () => getPautaItems(reporte!.pauta_id!),
    enabled: !!reporte?.pauta_id,
  })
  const { data: filas = [], isLoading: cargandoFilas } = useQuery({
    queryKey: ['enex-ejec-items-web', ejecucionId],
    queryFn: async () => (await getEjecucionItems(ejecucionId)) as unknown as FilaServidor[],
    enabled: !!ejecucionId, staleTime: 0,
  })

  const firmado = !!reporte?.firma_mandante_url

  // ── Estado editable ────────────────────────────────────────────────────
  const [fecha, setFecha] = useState('')
  const [ot, setOt] = useState('')
  const [ejecutor, setEjecutor] = useState('')
  const [obs, setObs] = useState('')
  const [complementarias, setComplementarias] = useState<string[]>([])
  const [acts, setActs] = useState<Record<string, Act>>({})
  const enServidor = useRef<Set<string>>(new Set())
  const [listo, setListo] = useState(false)
  const [sucio, setSucio] = useState(false)
  const [subiendo, setSubiendo] = useState<string | null>(null)
  const [guardando, setGuardando] = useState(false)
  const [generando, setGenerando] = useState(false)
  // Avance de la generación (fotos procesadas): un informe con fotos tarda y,
  // sin esto, parece que la pantalla se quedó pegada.
  const [avance, setAvance] = useState('')
  // PDF listo cuando el navegador bloqueó la pestaña nueva: se ofrece el link.
  const [pdfListo, setPdfListo] = useState<string | null>(null)
  const [soloTrabajadas, setSoloTrabajadas] = useState(true)
  // Salir con cambios pide un segundo toque (sin diálogos nativos: congelan la pestaña).
  const [avisoSalir, setAvisoSalir] = useState(false)

  useEffect(() => {
    if (!reporte || cargandoFilas || listo) return
    setFecha((reporte.fecha_ejecucion ?? '').slice(0, 10))
    setOt(reporte.ot_numero ?? '')
    setEjecutor(reporte.ejecutor ?? '')
    setObs(reporte.observacion ?? '')
    setComplementarias(reporte.evidencia_urls ?? [])
    const m: Record<string, Act> = {}
    for (const f of filas) {
      const antes = f.fotos_antes?.length ? f.fotos_antes : f.foto_antes_url ? [f.foto_antes_url] : []
      // Formato viejo: una foto suelta (foto_url) se muestra como «después».
      const despues = f.fotos_despues?.length ? f.fotos_despues
        : f.foto_despues_url ? [f.foto_despues_url] : f.foto_url ? [f.foto_url] : []
      m[f.pauta_item_id] = {
        resultado: f.resultado ?? '',
        valor: f.valor_medicion != null ? String(f.valor_medicion) : '',
        obs: f.observacion ?? '',
        antes, despues,
      }
      enServidor.current.add(f.pauta_item_id)
    }
    setActs(m)
    setListo(true)
  }, [reporte, filas, cargandoFilas, listo])

  // Avisar antes de salir con cambios sin guardar.
  useEffect(() => {
    if (!sucio) return
    const h = (e: BeforeUnloadEvent) => { e.preventDefault(); e.returnValue = '' }
    window.addEventListener('beforeunload', h)
    return () => window.removeEventListener('beforeunload', h)
  }, [sucio])

  const upd = (id: string, patch: Partial<Act>) => {
    setSucio(true)
    setActs((p) => ({ ...p, [id]: { ...vacia(), ...p[id], ...patch } }))
  }

  async function subir(files: FileList, clave: string): Promise<string[]> {
    setSubiendo(clave)
    const urls: string[] = []
    try {
      for (const f of Array.from(files)) {
        try { urls.push(await subirFotoInformeEnex(f)) }
        catch (e) { toast.error(`No se pudo subir ${f.name}: ${(e as Error).message}`) }
      }
    } finally { setSubiendo(null) }
    if (urls.length) setSucio(true)
    return urls
  }
  const agregarFotos = async (id: string, tipo: 'antes' | 'despues', files: FileList) => {
    const urls = await subir(files, `${id}:${tipo}`)
    if (!urls.length) return
    setActs((p) => {
      const a = p[id] ?? vacia()
      return { ...p, [id]: { ...a, [tipo]: [...a[tipo], ...urls] } }
    })
  }
  const quitarFoto = (id: string, tipo: 'antes' | 'despues', url: string) =>
    upd(id, { [tipo]: (acts[id] ?? vacia())[tipo].filter((u) => u !== url) } as Partial<Act>)

  // ── Agrupación por bloque ─────────────────────────────────────────────
  const grupos = useMemo(() => {
    const visibles = soloTrabajadas
      ? pautaItems.filter((it) => it.bloque_orden === 0 || tieneAlgo(acts[it.id] ?? vacia()) || enServidor.current.has(it.id))
      : pautaItems
    const g: { bloque: string; items: EnexPautaItem[] }[] = []
    for (const it of visibles) {
      let x = g.find((y) => y.bloque === it.bloque)
      if (!x) { x = { bloque: it.bloque, items: [] }; g.push(x) }
      x.items.push(it)
    }
    return g
  }, [pautaItems, acts, soloTrabajadas])

  async function guardar(): Promise<boolean> {
    if (!reporte) return false
    setGuardando(true)
    try {
      const items: EnexInformeItemEdit[] = pautaItems
        .filter((it) => tieneAlgo(acts[it.id] ?? vacia()) || enServidor.current.has(it.id))
        .map((it) => {
          const a = acts[it.id] ?? vacia()
          return {
            pauta_item_id: it.id,
            resultado: a.resultado || null,
            valor_medicion: a.valor.trim() || null,
            observacion: a.obs.trim() || null,
            fotos_antes: a.antes,
            fotos_despues: a.despues,
          }
        })
      const r = await guardarInformeEnex({
        ejecucionId, fecha: fecha || null, otNumero: ot.trim() || null,
        ejecutor: ejecutor.trim() || null, observacion: obs.trim() || null,
        evidenciaUrls: complementarias, items,
      })
      enServidor.current = new Set(items.filter((i) =>
        i.resultado || i.valor_medicion || i.observacion || i.fotos_antes.length || i.fotos_despues.length,
      ).map((i) => i.pauta_item_id))
      setSucio(false)
      qc.invalidateQueries({ queryKey: ['enex-informes'] })
      toast.success(`Informe guardado · ${r.actividades} actividad(es)${r.borradas ? `, ${r.borradas} quitada(s)` : ''}`)
      return true
    } catch (e) {
      toast.error((e as Error).message)
      return false
    } finally { setGuardando(false) }
  }

  async function guardarYGenerar() {
    // La pestaña del PDF se abre AHORA, en el mismo clic. Abrirla después de
    // esperar la generación hacía que el navegador la bloqueara: el PDF se
    // guardaba, pero la pantalla se quedaba quieta sin mostrar nada.
    const w = window.open('', '_blank')
    if (w) {
      try {
        w.document.title = 'Generando informe…'
        w.document.body.innerHTML = '<p style="font:16px system-ui;padding:24px;color:#374151">Generando el informe PDF… esta pestaña lo mostrará apenas esté listo.</p>'
      } catch { /* sin acceso al documento: no importa */ }
    }
    setPdfListo(null)
    if (sucio && !(await guardar())) { w?.close(); return }
    setGenerando(true)
    setAvance('')
    try {
      const url = await generarYGuardarInformeEnex(ejecucionId, (hechas, total) =>
        setAvance(`${hechas}/${total} fotos`))
      refetch()
      qc.invalidateQueries({ queryKey: ['enex-informes'] })
      if (w && !w.closed) {
        w.location.href = url
        toast.success('Informe PDF rehecho con los cambios')
        router.push('/dashboard/enex/informes')
      } else {
        setPdfListo(url)
        toast.success('Informe PDF rehecho. Ábrelo con el botón de arriba.')
      }
    } catch (e) {
      w?.close()
      toast.error((e as Error).message)
    } finally { setGenerando(false); setAvance('') }
  }

  if (cargandoRep || (reporte && (cargandoPauta || !listo))) {
    return <div className="flex justify-center py-16"><Spinner /></div>
  }
  if (!reporte) {
    return (
      <div className="space-y-3 p-4">
        <Link href="/dashboard/enex/informes" className="inline-flex items-center gap-1 text-sm text-gray-500"><ArrowLeft className="h-4 w-4" /> Informes ENEX</Link>
        <p className="text-sm text-gray-600">No se encontró este informe.</p>
      </div>
    )
  }

  const inst = reporte.programacion?.instalacion
  const bloqueado = firmado

  return (
    <div className="space-y-4 pb-24">
      <div>
        <button type="button"
                onClick={() => {
                  if (sucio && !avisoSalir) {
                    setAvisoSalir(true)
                    toast.error('Hay cambios sin guardar. Toca «Informes ENEX» otra vez para salir sin guardar.')
                    return
                  }
                  router.push('/dashboard/enex/informes')
                }}
                className="inline-flex items-center gap-1 text-xs text-gray-500 hover:text-gray-700">
          <ArrowLeft className="h-3.5 w-3.5" /> Informes ENEX
        </button>
        <h1 className="mt-1 text-xl font-bold">Editar informe</h1>
        <p className="text-sm text-gray-500">
          {inst?.nombre}{inst?.patente ? ` · ${inst.patente}` : ''} · {inst?.faena?.nombre} ·{' '}
          {reporte.programacion?.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención'}
          {reporte.pauta ? ` · ${reporte.pauta.nombre}` : ''}
        </p>
      </div>

      {bloqueado && (
        <div className="flex items-start gap-2 rounded-lg border border-gray-300 bg-gray-50 p-3 text-sm text-gray-700">
          <Lock className="mt-0.5 h-4 w-4 flex-shrink-0" />
          <span>ESM ya firmó la recepción conforme de este informe ({reporte.firmante_mandante_nombre ?? 'mandante'}). Se puede ver, pero no cambiar lo que firmó.</span>
        </div>
      )}

      {pdfListo && (
        <div className="flex flex-wrap items-center gap-2 rounded-lg border border-green-300 bg-green-50 p-3 text-sm text-green-800">
          <FileSpreadsheet className="h-4 w-4" />
          <span className="flex-1">El informe PDF quedó rehecho con los cambios.</span>
          <a href={pdfListo} target="_blank" rel="noreferrer"
             className="rounded-md bg-green-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-green-700">Abrir PDF</a>
          <Link href="/dashboard/enex/informes"
                className="rounded-md border border-green-400 bg-white px-3 py-1.5 text-xs font-semibold text-green-700">Volver a informes</Link>
        </div>
      )}

      {/* Datos del servicio */}
      <Card>
        <CardContent className="grid gap-3 p-4 sm:grid-cols-3">
          <div>
            <label className="text-xs font-medium text-gray-700">Fecha de ejecución</label>
            <Input type="date" value={fecha} disabled={bloqueado} className="h-9"
                   onChange={(e) => { setFecha(e.target.value); setSucio(true) }} />
          </div>
          <div>
            <label className="text-xs font-medium text-gray-700">N° OT (mandante)</label>
            <Input value={ot} disabled={bloqueado} className="h-9" placeholder="N° de OT de ENEX / ESM"
                   onChange={(e) => { setOt(e.target.value); setSucio(true) }} />
          </div>
          <div>
            <label className="text-xs font-medium text-gray-700">Ejecutor</label>
            <Input value={ejecutor} disabled={bloqueado} className="h-9"
                   onChange={(e) => { setEjecutor(e.target.value); setSucio(true) }} />
          </div>
          <div className="sm:col-span-3">
            <label className="text-xs font-medium text-gray-700">Observación general del servicio</label>
            <textarea value={obs} disabled={bloqueado} rows={4}
                      onChange={(e) => { setObs(e.target.value); setSucio(true) }}
                      placeholder="Sale impresa en el bloque «Observación general del servicio» del PDF."
                      className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm disabled:bg-gray-50" />
          </div>
        </CardContent>
      </Card>

      {/* Actividades */}
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-bold text-gray-800">Actividades de la pauta</h2>
        <label className="flex items-center gap-1.5 text-xs text-gray-600">
          <input type="checkbox" checked={soloTrabajadas} onChange={(e) => setSoloTrabajadas(e.target.checked)} />
          Solo las que están en el informe
        </label>
      </div>
      {!soloTrabajadas && (
        <p className="-mt-2 text-[11px] text-gray-500">
          Las actividades que llenes aquí entran al informe. Una actividad que dejes vacía sale del informe al guardar.
        </p>
      )}

      {grupos.map((g) => (
        <Card key={g.bloque}>
          <CardContent className="p-0">
            <div className="border-b bg-gray-50 px-4 py-2 text-sm font-semibold text-gray-800">{g.bloque}</div>
            <div className="divide-y">
              {g.items.map((it) => {
                const a = acts[it.id] ?? vacia()
                const dato = it.bloque_orden === 0
                const dt = dentroTol(it, a.valor)
                return (
                  <div key={it.id} className="space-y-2 px-4 py-3">
                    <div className="flex items-start gap-2">
                      {it.codigo && <span className="mt-0.5 font-mono text-[11px] text-gray-400">{it.codigo}</span>}
                      <p className="flex-1 text-sm text-gray-800">{it.descripcion}</p>
                      {it.critico && <span className="rounded bg-red-600 px-1 py-0.5 text-[9px] font-bold text-white">CRÍTICA</span>}
                    </div>

                    {dato ? (
                      <Input value={a.obs} disabled={bloqueado} className="h-9" placeholder="Escribe aquí…"
                             onChange={(e) => upd(it.id, { obs: e.target.value })} />
                    ) : (
                      <>
                        <div className="flex flex-wrap items-center gap-2">
                          {(it.tipo_campo === 'ok_nook' || it.tipo_campo === 'si_no') && (
                            <div className="flex gap-1">
                              {(it.tipo_campo === 'ok_nook'
                                ? [['ok', 'OK', 'bg-green-500', Check], ['no_ok', 'NO OK', 'bg-red-500', X], ['na', 'N/A', 'bg-gray-400', Minus]]
                                : [['si', 'Sí', 'bg-green-500', Check], ['no', 'No', 'bg-red-500', X]]
                              ).map(([val, label, color, Icon]) => {
                                const activo = a.resultado === val
                                const I = Icon as typeof Check
                                return (
                                  <button key={val as string} type="button" disabled={bloqueado}
                                          onClick={() => upd(it.id, { resultado: activo ? '' : (val as string) })}
                                          className={`flex h-8 items-center gap-1 rounded-md border px-3 text-xs font-semibold disabled:opacity-60 ${
                                            activo ? `${color} border-transparent text-white` : 'border-gray-200 bg-white text-gray-500'}`}>
                                    <I className="h-3.5 w-3.5" /> {label as string}
                                  </button>
                                )
                              })}
                            </div>
                          )}
                          {it.tipo_campo === 'medicion' && (
                            <div className="flex items-center gap-2">
                              <Input type="number" inputMode="decimal" value={a.valor} disabled={bloqueado}
                                     onChange={(e) => upd(it.id, { valor: e.target.value })}
                                     placeholder={`valor ${it.unidad ?? ''}`} className="h-8 w-32" />
                              {(it.tolerancia_min != null || it.tolerancia_max != null) && (
                                <span className="flex items-center gap-1 text-[11px] text-gray-500"><Ruler className="h-3 w-3" /> {toleranciaTexto(it)}</span>
                              )}
                              {dt === true && <span className="rounded-full bg-green-100 px-2 py-0.5 text-[10px] font-semibold text-green-700">dentro</span>}
                              {dt === false && <span className="rounded-full bg-red-100 px-2 py-0.5 text-[10px] font-semibold text-red-700">fuera de tolerancia</span>}
                            </div>
                          )}
                        </div>
                        <Input value={a.obs} disabled={bloqueado} className="h-8 text-sm"
                               placeholder={it.tipo_campo === 'texto' ? 'Anotación' : 'Observación de la actividad (sale en el informe)'}
                               onChange={(e) => upd(it.id, { obs: e.target.value })} />
                        <div className="grid gap-3 sm:grid-cols-2">
                          {(['antes', 'despues'] as const).map((tipo) => (
                            <Galeria key={tipo} titulo={tipo === 'antes' ? 'Antes' : 'Después'}
                                     fotos={a[tipo]} bloqueado={bloqueado}
                                     subiendo={subiendo === `${it.id}:${tipo}`}
                                     onAgregar={(files) => void agregarFotos(it.id, tipo, files)}
                                     onQuitar={(u) => quitarFoto(it.id, tipo, u)} />
                          ))}
                        </div>
                      </>
                    )}
                  </div>
                )
              })}
            </div>
          </CardContent>
        </Card>
      ))}

      {/* Registro fotográfico complementario */}
      <Card>
        <CardContent className="space-y-2 p-4">
          <div className="flex items-center gap-2 text-sm font-bold text-gray-800">
            <ImagePlus className="h-4 w-4 text-gray-500" /> Registro fotográfico complementario
          </div>
          <Galeria titulo="Fotos" fotos={complementarias} bloqueado={bloqueado}
                   subiendo={subiendo === 'complementarias'}
                   onAgregar={async (files) => {
                     const urls = await subir(files, 'complementarias')
                     if (urls.length) setComplementarias((p) => [...p, ...urls])
                   }}
                   onQuitar={(u) => { setComplementarias((p) => p.filter((x) => x !== u)); setSucio(true) }} />
        </CardContent>
      </Card>

      {/* Barra de acción */}
      {!bloqueado && (
        <div className="fixed inset-x-0 bottom-0 z-20 border-t bg-white/95 px-4 py-3 backdrop-blur">
          <div className="mx-auto flex max-w-5xl items-center justify-end gap-2">
            <span className="mr-auto text-xs text-gray-500">
              {sucio ? 'Hay cambios sin guardar' : 'Sin cambios pendientes'}
            </span>
            <Button variant="outline" disabled={guardando || !sucio || !!subiendo} onClick={() => void guardar()}>
              {guardando ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : <Save className="mr-1 h-4 w-4" />} Guardar
            </Button>
            <Button variant="primary" disabled={guardando || generando || !!subiendo} onClick={() => void guardarYGenerar()}>
              {generando ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : <FileSpreadsheet className="mr-1 h-4 w-4" />}
              {generando ? (avance ? `Generando… ${avance}` : 'Generando…') : sucio ? 'Guardar y rehacer PDF' : 'Rehacer PDF'}
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
