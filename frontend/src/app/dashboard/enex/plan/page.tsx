'use client'

// Plan semanal ENEX (MIG274) — el trabajo de la semana repartido por día y por
// área. Se importa del Excel que llega de faena ("PLAN 07.08.xlsx"), se corrige
// aquí y se publica: recién publicado lo ve el técnico en su teléfono.

import { useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  ArrowLeft, CalendarDays, ChevronLeft, ChevronRight, Upload, Plus, Trash2,
  Send, Lock, FileSpreadsheet, AlertTriangle, CheckCircle2, X, Pencil,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getFaenas, getInstalaciones, getPautas, getPautaItems,
  getPlanSemana, getPlanTareas, crearPlan, importarPlanTareas, guardarPlanTarea,
  eliminarPlanTarea, cambiarEstadoPlan, lunesDe, MESES,
  type EnexPlanTarea, type EnexTareaImport, type EnexPlanEstado,
} from '@/lib/services/enex'
import { leerPlanExcel, type PlanPreview } from '@/lib/importers/enex-plan-importer'

const DIAS = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo']

function hoyISO(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}
function sumarDias(iso: string, n: number): string {
  const [y, m, d] = iso.split('-').map(Number)
  const dt = new Date(y, m - 1, d + n)
  return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`
}
function fmtDia(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number)
  const dt = new Date(y, m - 1, d)
  return `${DIAS[(dt.getDay() + 6) % 7]} ${d}/${String(m).padStart(2, '0')}`
}

const ESTADO_CHIP: Record<string, string> = {
  pendiente: 'bg-gray-100 text-gray-600',
  en_proceso: 'bg-blue-100 text-blue-700',
  hecha: 'bg-green-100 text-green-700',
  no_realizada: 'bg-red-100 text-red-700',
}
const PLAN_CHIP: Record<EnexPlanEstado, string> = {
  borrador: 'bg-amber-100 text-amber-800',
  publicado: 'bg-green-100 text-green-700',
  cerrado: 'bg-gray-200 text-gray-600',
}

export default function EnexPlanPage() {
  useRequireAuth()
  const toast = useToast()
  const qc = useQueryClient()
  const fileRef = useRef<HTMLInputElement>(null)

  const [semana, setSemana] = useState(() => lunesDe(hoyISO()))
  const [faenaSel, setFaenaSel] = useState<string>('')
  const [preview, setPreview] = useState<PlanPreview | null>(null)
  const [importando, setImportando] = useState(false)
  const [nueva, setNueva] = useState<{ fecha: string; area: string; instalacionId: string; itemId: string; alcance: string; comentario: string } | null>(null)

  const { data: faenas = [] } = useQuery({ queryKey: ['enex-faenas'], queryFn: getFaenas, staleTime: 5 * 60_000 })
  // Por defecto la faena de lubricantes: es la que trabaja con plan semanal.
  const faenaId = faenaSel || faenas.find((f) => f.codigo === 'LB_LUB')?.id || faenas[0]?.id || ''

  const { data: instalaciones = [] } = useQuery({
    queryKey: ['enex-inst', faenaId], queryFn: () => getInstalaciones(faenaId),
    enabled: !!faenaId, staleTime: 5 * 60_000,
  })
  const { data: pautas = [] } = useQuery({ queryKey: ['enex-pautas'], queryFn: getPautas, staleTime: 5 * 60_000 })
  const pautaLub = pautas.find((p) => p.codigo === 'PAUTA-LUB')
  const { data: itemsPauta = [] } = useQuery({
    queryKey: ['enex-pauta-items', pautaLub?.id], queryFn: () => getPautaItems(pautaLub!.id),
    enabled: !!pautaLub, staleTime: 5 * 60_000,
  })

  const { data: plan, isLoading: cargandoPlan } = useQuery({
    queryKey: ['enex-plan', faenaId, semana], queryFn: () => getPlanSemana(faenaId, semana),
    enabled: !!faenaId,
  })
  const { data: tareas = [], isLoading: cargandoTareas } = useQuery({
    queryKey: ['enex-plan-tareas', plan?.id], queryFn: () => getPlanTareas(plan!.id),
    enabled: !!plan?.id,
  })

  const areas = useMemo(
    () => Array.from(new Set(instalaciones.map((i) => i.area).filter(Boolean) as string[])).sort(),
    [instalaciones])

  // Grilla: un bloque por día, y dentro las tareas agrupadas por área.
  const dias = useMemo(() => {
    const out: { fecha: string; grupos: { area: string; items: EnexPlanTarea[] }[] }[] = []
    for (let k = 0; k < 7; k++) {
      const fecha = sumarDias(semana, k)
      const delDia = tareas.filter((t) => t.fecha.slice(0, 10) === fecha)
      const grupos: { area: string; items: EnexPlanTarea[] }[] = []
      for (const t of delDia) {
        const a = t.area || t.instalacion || 'Sin área'
        let g = grupos.find((x) => x.area === a)
        if (!g) { g = { area: a, items: [] }; grupos.push(g) }
        g.items.push(t)
      }
      out.push({ fecha, grupos })
    }
    return out
  }, [tareas, semana])

  const totalTareas = tareas.length
  const hechas = tareas.filter((t) => t.estado === 'hecha').length
  const sinActividad = tareas.filter((t) => !t.pauta_item_id).length

  function recargar() {
    qc.invalidateQueries({ queryKey: ['enex-plan', faenaId, semana] })
    qc.invalidateQueries({ queryKey: ['enex-plan-tareas'] })
  }

  async function elegirArchivo(f: File) {
    try {
      const anio = Number(semana.slice(0, 4))
      const p = await leerPlanExcel(f, anio)
      setPreview(p)
      if (p.validas === 0) toast.error('No se reconoció ninguna fila del archivo')
    } catch (e) { toast.error(`No se pudo leer el archivo: ${(e as Error).message}`) }
  }

  async function confirmarImportacion() {
    if (!preview || !faenaId) return
    setImportando(true)
    try {
      // La semana del plan sale de la primera fecha del archivo, no del selector:
      // así el planificador no carga el lunes 10 dentro de la semana equivocada.
      const primera = preview.fechas[0] ?? semana
      const semanaDestino = lunesDe(primera)
      const { plan_id } = await crearPlan({ faenaId, semana: semanaDestino, nombre: `Plan semana ${fmtDia(semanaDestino)}` })

      // El alcance ("RACK 1/ RACK 2") se reparte en puntos concretos: así el
      // técnico entra directo al rack y publicar el plan puede dejarle el
      // servicio programado. Sin alcance, la tarea queda a nivel de área.
      const tareasImport: EnexTareaImport[] = preview.filas
        .filter((f) => !f.problema)
        .flatMap((f) => {
          const area = mapArea(f.area, areas)
          const puntos = puntosDeAlcance(f.alcance, area, instalaciones)
          const base = { fecha: f.fecha!, area, codigo_item: f.codigoItem, alcance: f.alcance, comentario: f.comentario }
          return puntos.length > 0
            ? puntos.map((p) => ({ ...base, instalacion_id: p }))
            : [base]
        })
      const r = await importarPlanTareas(plan_id, tareasImport, true)
      setSemana(semanaDestino)
      setPreview(null)
      recargar()
      toast.success(`${r.tareas} tareas cargadas${r.sin_actividad > 0 ? ` · ${r.sin_actividad} sin actividad reconocida` : ''}`)
    } catch (e) { toast.error((e as Error).message) } finally { setImportando(false) }
  }

  async function agregarTarea() {
    if (!nueva || !faenaId) return
    try {
      let planId = plan?.id
      if (!planId) planId = (await crearPlan({ faenaId, semana })).plan_id
      await guardarPlanTarea({
        planId, fecha: nueva.fecha, area: nueva.area || null,
        instalacionId: nueva.instalacionId || null, pautaItemId: nueva.itemId || null,
        alcance: nueva.alcance || null, comentario: nueva.comentario || null,
      })
      setNueva(null); recargar(); toast.success('Tarea agregada')
    } catch (e) { toast.error((e as Error).message) }
  }

  async function borrar(t: EnexPlanTarea) {
    try { await eliminarPlanTarea(t.id); recargar() }
    catch (e) { toast.error((e as Error).message) }
  }

  async function cambiarEstado(estado: EnexPlanEstado) {
    if (!plan?.id) return
    try {
      await cambiarEstadoPlan(plan.id, estado)
      recargar()
      toast.success(estado === 'publicado' ? 'Plan publicado — ya se ve en terreno' : `Plan ${estado}`)
    } catch (e) { toast.error((e as Error).message) }
  }

  const mesLabel = `${MESES[Number(semana.slice(5, 7)) - 1]} ${semana.slice(0, 4)}`

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <Link href="/dashboard/enex" className="inline-flex items-center gap-1 text-xs text-gray-500 hover:text-gray-700">
            <ArrowLeft className="h-3.5 w-3.5" /> Control ENEX
          </Link>
          <h1 className="text-xl font-bold flex items-center gap-2">
            <CalendarDays className="h-5 w-5 text-blue-700" /> Plan semanal
          </h1>
          <p className="mt-0.5 text-sm text-gray-500">
            Qué se hace cada día y en qué área. Publícalo y el técnico lo ve en su teléfono.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <select value={faenaId} onChange={(e) => setFaenaSel(e.target.value)}
                  className="h-9 rounded border px-2 text-sm">
            {faenas.map((f) => <option key={f.id} value={f.id}>{f.nombre}</option>)}
          </select>
          <button onClick={() => setSemana(sumarDias(semana, -7))} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50"><ChevronLeft className="h-4 w-4" /></button>
          <span className="min-w-[190px] text-center text-sm font-semibold">
            {fmtDia(semana)} al {fmtDia(sumarDias(semana, 6))}
            <span className="ml-1 text-xs font-normal text-gray-400">{mesLabel}</span>
          </span>
          <button onClick={() => setSemana(sumarDias(semana, 7))} className="rounded-lg border px-2 py-1.5 hover:bg-gray-50"><ChevronRight className="h-4 w-4" /></button>
          <Button size="sm" variant="outline" onClick={() => setSemana(lunesDe(hoyISO()))}>Esta semana</Button>
        </div>
      </div>

      {/* Barra de estado del plan */}
      <Card>
        <CardContent className="flex flex-wrap items-center gap-3 p-3">
          {cargandoPlan ? <Spinner /> : plan ? (
            <>
              <span className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ${PLAN_CHIP[plan.estado]}`}>
                {plan.estado === 'publicado' ? 'PUBLICADO' : plan.estado.toUpperCase()}
              </span>
              <span className="text-sm text-gray-600">
                {totalTareas} tarea{totalTareas !== 1 ? 's' : ''} · {hechas} hecha{hechas !== 1 ? 's' : ''}
              </span>
              {sinActividad > 0 && (
                <span className="flex items-center gap-1 text-xs text-amber-700">
                  <AlertTriangle className="h-3.5 w-3.5" /> {sinActividad} sin actividad de la pauta reconocida
                </span>
              )}
              <div className="ml-auto flex gap-2">
                {plan.estado !== 'publicado' && (
                  <Button size="sm" variant="primary" onClick={() => cambiarEstado('publicado')}>
                    <Send className="mr-1 h-3.5 w-3.5" /> Publicar a terreno
                  </Button>
                )}
                {plan.estado === 'publicado' && (
                  <>
                    <Button size="sm" variant="outline" onClick={() => cambiarEstado('borrador')}>Volver a borrador</Button>
                    <Button size="sm" variant="outline" onClick={() => cambiarEstado('cerrado')}>
                      <Lock className="mr-1 h-3.5 w-3.5" /> Cerrar semana
                    </Button>
                  </>
                )}
              </div>
            </>
          ) : (
            <span className="text-sm text-gray-500">
              No hay plan cargado para esta semana. Importa el Excel de faena o agrega tareas a mano.
            </span>
          )}
          <div className={plan ? 'w-full border-t pt-3' : 'ml-auto'}>
            <div className="flex flex-wrap gap-2">
              <input ref={fileRef} type="file" accept=".xlsx,.xls" className="hidden"
                     onChange={(e) => { const f = e.target.files?.[0]; if (f) void elegirArchivo(f); e.target.value = '' }} />
              <Button size="sm" variant="outline" onClick={() => fileRef.current?.click()}>
                <Upload className="mr-1 h-3.5 w-3.5" /> Importar Excel del plan
              </Button>
              <Button size="sm" variant="outline"
                      onClick={() => setNueva({ fecha: semana, area: areas[0] ?? '', instalacionId: '', itemId: '', alcance: '', comentario: '' })}>
                <Plus className="mr-1 h-3.5 w-3.5" /> Agregar tarea
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Preview de la importación */}
      {preview && (
        <Card className="border-blue-300">
          <CardContent className="p-3">
            <div className="mb-2 flex items-center gap-2">
              <FileSpreadsheet className="h-4 w-4 text-blue-700" />
              <h2 className="text-sm font-bold">Revisión del archivo</h2>
              <button onClick={() => setPreview(null)} className="ml-auto text-gray-400 hover:text-gray-600"><X className="h-4 w-4" /></button>
            </div>
            <p className="text-sm text-gray-600">
              {preview.validas} fila{preview.validas !== 1 ? 's' : ''} lista{preview.validas !== 1 ? 's' : ''} para cargar
              {preview.conProblema > 0 && <span className="text-amber-700"> · {preview.conProblema} con problema (se omiten)</span>}
              {preview.fechas.length > 0 && <> · días: {preview.fechas.map((f) => fmtDia(f)).join(', ')}</>}
              {preview.areas.length > 0 && <> · áreas: {preview.areas.join(', ')}</>}
            </p>
            {preview.advertencias.map((a, i) => (
              <p key={i} className="mt-1 flex items-center gap-1 text-xs text-amber-700"><AlertTriangle className="h-3.5 w-3.5" /> {a}</p>
            ))}
            <div className="mt-2 max-h-64 overflow-auto rounded border">
              <table className="w-full text-xs">
                <thead className="sticky top-0 bg-gray-50">
                  <tr className="text-left text-gray-500">
                    <th className="p-1.5">Fila</th><th className="p-1.5">Día</th><th className="p-1.5">Área</th>
                    <th className="p-1.5">Punto</th><th className="p-1.5">Alcance</th><th className="p-1.5">Comentario</th>
                  </tr>
                </thead>
                <tbody>
                  {preview.filas.map((f) => (
                    <tr key={f.fila} className={`border-t ${f.problema ? 'bg-amber-50' : ''}`}>
                      <td className="p-1.5 text-gray-400">{f.fila}</td>
                      <td className="p-1.5">{f.fecha ? fmtDia(f.fecha) : <span className="text-amber-700">{f.fechaTexto || '—'}</span>}</td>
                      <td className="p-1.5">{f.area ?? '—'}</td>
                      <td className="p-1.5 font-mono">{f.codigoItem ?? '—'}</td>
                      <td className="p-1.5 text-gray-500">{f.alcance ?? '—'}</td>
                      <td className="p-1.5 text-gray-500">
                        {f.problema ? <span className="text-amber-700">{f.problema}</span> : (f.comentario ?? '—')}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="mt-3 flex items-center gap-2">
              <Button size="sm" variant="primary" disabled={importando || preview.validas === 0} onClick={confirmarImportacion}>
                {importando ? <Spinner className="mr-1 h-3.5 w-3.5" /> : <CheckCircle2 className="mr-1 h-3.5 w-3.5" />}
                Cargar {preview.validas} tareas
              </Button>
              <span className="text-xs text-gray-500">Reemplaza las tareas pendientes de esa semana; lo ya trabajado no se toca.</span>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Alta manual */}
      {nueva && (
        <Card className="border-gray-300">
          <CardContent className="flex flex-wrap items-end gap-2 p-3">
            <div>
              <label className="text-xs font-medium">Día</label>
              <Input type="date" value={nueva.fecha} onChange={(e) => setNueva({ ...nueva, fecha: e.target.value })} className="h-9" />
            </div>
            <div>
              <label className="text-xs font-medium">Área</label>
              <select value={nueva.area} onChange={(e) => setNueva({ ...nueva, area: e.target.value, instalacionId: '' })}
                      className="block h-9 rounded border px-2 text-sm">
                <option value="">—</option>
                {areas.map((a) => <option key={a} value={a}>{a}</option>)}
              </select>
            </div>
            <div>
              <label className="text-xs font-medium">Punto (opcional)</label>
              <select value={nueva.instalacionId} onChange={(e) => setNueva({ ...nueva, instalacionId: e.target.value })}
                      className="block h-9 rounded border px-2 text-sm">
                <option value="">Toda el área</option>
                {instalaciones.filter((i) => !nueva.area || i.area === nueva.area)
                  .map((i) => <option key={i.id} value={i.id}>{i.nombre}</option>)}
              </select>
            </div>
            <div className="min-w-[260px] flex-1">
              <label className="text-xs font-medium">Actividad de la pauta</label>
              <select value={nueva.itemId} onChange={(e) => setNueva({ ...nueva, itemId: e.target.value })}
                      className="block h-9 w-full rounded border px-2 text-sm">
                <option value="">—</option>
                {itemsPauta.filter((i) => /^\d/.test(i.codigo ?? '')).map((i) => (
                  <option key={i.id} value={i.id}>
                    {i.codigo} · {i.descripcion} ({i.periodicidad})
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="text-xs font-medium">Alcance</label>
              <Input value={nueva.alcance} onChange={(e) => setNueva({ ...nueva, alcance: e.target.value })}
                     placeholder="Rack 1 / Rack 2" className="h-9" />
            </div>
            <div className="min-w-[180px] flex-1">
              <label className="text-xs font-medium">Comentario</label>
              <Input value={nueva.comentario} onChange={(e) => setNueva({ ...nueva, comentario: e.target.value })} className="h-9" />
            </div>
            <Button size="sm" variant="primary" onClick={agregarTarea}>Agregar</Button>
            <Button size="sm" variant="outline" onClick={() => setNueva(null)}>Cancelar</Button>
          </CardContent>
        </Card>
      )}

      {/* Grilla de la semana */}
      {cargandoTareas ? (
        <div className="flex justify-center py-10"><Spinner /></div>
      ) : (
        <div className="grid gap-3 lg:grid-cols-2 xl:grid-cols-3">
          {dias.filter((d) => d.grupos.length > 0 || d.fecha >= hoyISO()).map((d) => {
            const esHoy = d.fecha === hoyISO()
            const n = d.grupos.reduce((s, g) => s + g.items.length, 0)
            return (
              <Card key={d.fecha} className={esHoy ? 'border-blue-400' : ''}>
                <CardContent className="p-3">
                  <div className="mb-2 flex items-center gap-2">
                    <h3 className={`text-sm font-bold ${esHoy ? 'text-blue-700' : ''}`}>{fmtDia(d.fecha)}</h3>
                    {esHoy && <span className="rounded-full bg-blue-600 px-1.5 py-0.5 text-[10px] font-bold text-white">HOY</span>}
                    <span className="ml-auto text-xs text-gray-400">{n || 'sin tareas'}</span>
                    <button title="Agregar tarea este día"
                            onClick={() => setNueva({ fecha: d.fecha, area: areas[0] ?? '', instalacionId: '', itemId: '', alcance: '', comentario: '' })}
                            className="text-gray-400 hover:text-blue-600"><Plus className="h-3.5 w-3.5" /></button>
                  </div>
                  {d.grupos.length === 0 ? (
                    <p className="py-3 text-center text-xs text-gray-300">—</p>
                  ) : d.grupos.map((g) => (
                    <div key={g.area} className="mb-2">
                      <p className="text-[11px] font-semibold uppercase tracking-wide text-gray-500">{g.area}</p>
                      <ul className="mt-1 space-y-1">
                        {g.items.map((t) => (
                          <li key={t.id} className="group flex items-start gap-1.5 rounded border border-gray-100 px-1.5 py-1 text-xs">
                            <span className="font-mono text-[11px] text-gray-500">{t.codigo_item ?? '?'}</span>
                            <span className="flex-1">
                              {t.actividad ?? <span className="text-amber-700">actividad no reconocida</span>}
                              {t.alcance && <span className="text-gray-400"> · {t.alcance}</span>}
                              {t.instalacion && <span className="block text-[10px] text-gray-400">{t.instalacion}</span>}
                              {t.comentario && <span className="block text-[10px] italic text-gray-400">{t.comentario}</span>}
                            </span>
                            <span className={`rounded-full px-1.5 py-0.5 text-[9px] font-semibold ${ESTADO_CHIP[t.estado]}`}>
                              {t.estado === 'pendiente' ? '' : t.estado === 'en_proceso' ? 'en curso' : t.estado === 'hecha' ? 'hecha' : 'no realizada'}
                            </span>
                            {t.estado === 'pendiente' && !t.ejecucion_id && (
                              <button onClick={() => borrar(t)} title="Quitar del plan"
                                      className="text-gray-300 opacity-0 transition group-hover:opacity-100 hover:text-red-600">
                                <Trash2 className="h-3.5 w-3.5" />
                              </button>
                            )}
                          </li>
                        ))}
                      </ul>
                    </div>
                  ))}
                </CardContent>
              </Card>
            )
          })}
        </div>
      )}

      <p className="flex items-center gap-1.5 text-xs text-gray-400">
        <Pencil className="h-3.5 w-3.5" />
        El plan organiza la semana. El cumplimiento del contrato se sigue midiendo en el panel de control por
        servicio programado del trimestre.
      </p>
    </div>
  )
}

/**
 * "RACK 1/ RACK 2" → los puntos de esa área. El Excel de faena escribe el
 * alcance en texto libre; si no se reconoce nada, la tarea queda de área y el
 * técnico elige el punto.
 */
function puntosDeAlcance(
  alcance: string | null,
  area: string | null,
  instalaciones: { id: string; nombre: string; area: string | null }[],
): string[] {
  if (!alcance) return []
  const delArea = instalaciones.filter((i) => !area || i.area === area)
  if (delArea.length === 0) return []
  const txt = alcance.toUpperCase()
  const ids: string[] = []

  if (/MICRO|FILTRADO|SALA/.test(txt)) {
    const mf = delArea.find((i) => /MICROFILTRADO/i.test(i.nombre))
    if (mf) ids.push(mf.id)
  }
  const re = /RACK\s*N?°?\s*(\d+)/g
  let m: RegExpExecArray | null
  while ((m = re.exec(txt)) !== null) {
    const n = m[1]
    const p = delArea.find((i) => new RegExp(`RACK\\s*${n}\\b`, 'i').test(i.nombre))
    if (p && !ids.includes(p.id)) ids.push(p.id)
  }
  return ids
}

/** "LOMAS 2" del Excel → el área tal como está en el catálogo de puntos. */
function mapArea(area: string | null, areas: string[]): string | null {
  if (!area) return null
  const n = area.toUpperCase().replace(/\s+/g, ' ').trim()
  const num = n.match(/(\d+)/)?.[1]
  const encontrada = areas.find((a) => {
    const an = a.toUpperCase()
    if (an === n) return true
    return num ? an.includes(num) && (an.includes('LOMAS') || n.includes('LOMAS')) : false
  })
  return encontrada ?? area
}
