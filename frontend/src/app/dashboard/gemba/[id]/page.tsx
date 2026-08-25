'use client'

import { useMemo, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useParams } from 'next/navigation'
import Link from 'next/link'
import { ArrowLeft, Footprints, AlertTriangle, CheckCircle2, Lock, Camera, Loader2, X } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Modal } from '@/components/ui/modal'
import { Spinner } from '@/components/ui/spinner'
import { cn } from '@/lib/utils'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { usePermissions } from '@/hooks/use-permissions'
import { useToast } from '@/hooks/use-toast'
import {
  useGembaRecorrido,
  useGembaRespuestas,
  useGembaHallazgos,
  useUpdateGembaRespuesta,
  useCreateGembaHallazgo,
  useUpdateGembaHallazgo,
  useCerrarGembaRecorrido,
} from '@/hooks/use-gemba'
import type { GembaEvaluacion, GembaRespuesta } from '@/lib/services/gemba'
import { subirFotoGemba, updateGembaRespuesta } from '@/lib/services/gemba'

const EVALS: Array<{ value: GembaEvaluacion; label: string; activeCls: string }> = [
  { value: 'cumple', label: 'Cumple', activeCls: 'bg-green-600 text-white border-green-600' },
  { value: 'no_cumple', label: 'No cumple', activeCls: 'bg-red-600 text-white border-red-600' },
  { value: 'no_aplica', label: 'N/A', activeCls: 'bg-gray-500 text-white border-gray-500' },
]

export default function GembaRecorridoPage() {
  useRequireAuth()
  const params = useParams<{ id: string }>()
  const id = params?.id
  const toast = useToast()
  const qc = useQueryClient()
  const { canCreate } = usePermissions()

  const { data: recorrido, isLoading } = useGembaRecorrido(id)
  const { data: respuestas } = useGembaRespuestas(id)
  const { data: hallazgos } = useGembaHallazgos(id)

  const updRespuesta = useUpdateGembaRespuesta(id ?? '')
  const crearHallazgo = useCreateGembaHallazgo()
  const updHallazgo = useUpdateGembaHallazgo()
  const cerrar = useCerrarGembaRecorrido()

  const cerrado = recorrido?.estado === 'cerrado'
  // [MIG288] Un recorrido cerrado es inmutable en la BD, y quien no tiene el
  // permiso del módulo tampoco escribe: en los dos casos la pantalla es de
  // lectura, para no ofrecer botones que la base va a rechazar.
  const soloLectura = cerrado || !canCreate('prevencion')

  // ── Modal de hallazgo (al marcar No cumple o manual) ──
  const [modalRespuesta, setModalRespuesta] = useState<GembaRespuesta | null>(null)
  const [hDescripcion, setHDescripcion] = useState('')
  const [hAccion, setHAccion] = useState('')
  const [hResponsable, setHResponsable] = useState('')
  const [hCompromiso, setHCompromiso] = useState('')

  // ── Modal de cierre ──
  const [modalCierre, setModalCierre] = useState(false)
  const [obsCierre, setObsCierre] = useState('')

  const secciones = useMemo(() => {
    const map = new Map<string, GembaRespuesta[]>()
    for (const r of respuestas ?? []) {
      if (!map.has(r.seccion)) map.set(r.seccion, [])
      map.get(r.seccion)!.push(r)
    }
    return Array.from(map.entries())
  }, [respuestas])

  const stats = useMemo(() => {
    const rs = respuestas ?? []
    const cumple = rs.filter((r) => r.evaluacion === 'cumple').length
    const noCumple = rs.filter((r) => r.evaluacion === 'no_cumple').length
    const na = rs.filter((r) => r.evaluacion === 'no_aplica').length
    const pendientes = rs.filter((r) => !r.evaluacion).length
    const evaluados = cumple + noCumple
    const pct = evaluados > 0 ? Math.round((1000 * cumple) / evaluados) / 10 : null
    return { cumple, noCumple, na, pendientes, pct, total: rs.length }
  }, [respuestas])

  const setEvaluacion = async (r: GembaRespuesta, ev: GembaEvaluacion) => {
    if (soloLectura) return
    const nueva = r.evaluacion === ev ? null : ev
    try {
      await updRespuesta.mutateAsync({ id: r.id, evaluacion: nueva })
      if (nueva === 'no_cumple') {
        // Abrir modal para registrar el hallazgo en el plan de acción
        setModalRespuesta(r)
        setHDescripcion(r.item)
        setHAccion('')
        setHResponsable('')
        setHCompromiso('')
      }
    } catch (e: any) {
      toast.error(`No se pudo guardar la evaluación: ${e?.message ?? ''}`)
    }
  }

  const guardarObservacion = async (r: GembaRespuesta, obs: string) => {
    if (soloLectura || obs === (r.observacion ?? '')) return
    try {
      await updRespuesta.mutateAsync({ id: r.id, observacion: obs })
    } catch {
      toast.error('No se pudo guardar la observación')
    }
  }

  const guardarHallazgo = async () => {
    if (!id || !hDescripcion.trim()) return
    try {
      await crearHallazgo.mutateAsync({
        recorrido_id: id,
        respuesta_id: modalRespuesta?.id || undefined,
        descripcion: hDescripcion.trim(),
        accion_correctiva: hAccion || undefined,
        responsable_texto: hResponsable || undefined,
        fecha_compromiso: hCompromiso || undefined,
      })
      toast.success('Hallazgo registrado en el plan de acción')
      setModalRespuesta(null)
    } catch (e: any) {
      toast.error(`No se pudo registrar el hallazgo: ${e?.message ?? ''}`)
    }
  }

  const cerrarRecorrido = async () => {
    if (!id) return
    try {
      await cerrar.mutateAsync({ id, observaciones: obsCierre || undefined })
      toast.success('Recorrido cerrado')
      setModalCierre(false)
    } catch (e: any) {
      toast.error(`No se pudo cerrar el recorrido: ${e?.message ?? ''}`)
    }
  }

  const cambiarEstadoHallazgo = async (hid: string, estado: 'abierta' | 'en_proceso' | 'cerrada') => {
    try {
      await updHallazgo.mutateAsync({
        id: hid,
        estado,
        fecha_cierre: estado === 'cerrada' ? new Date().toISOString().split('T')[0] : null,
      })
    } catch {
      toast.error('No se pudo actualizar el hallazgo')
    }
  }

  if (isLoading || !recorrido) {
    return (
      <div className="flex h-64 items-center justify-center">
        <Spinner className="h-8 w-8" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* ── Header ── */}
      {/* Compacto en el teléfono: en terreno la pantalla la ocupa el checklist,
          no el título. */}
      <div>
        <Link
          href="/dashboard/gemba"
          className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700"
        >
          <ArrowLeft className="h-4 w-4" /> Volver
        </Link>
        <h1 className="mt-1 flex items-start gap-2 text-base font-bold leading-tight text-gray-900 sm:text-2xl">
          <Footprints className="mt-0.5 h-5 w-5 shrink-0 text-amber-500 sm:h-7 sm:w-7" />
          <span className="min-w-0">{recorrido.plantilla?.nombre ?? 'Recorrido Gemba'}</span>
          {cerrado && <Lock className="mt-0.5 h-4 w-4 shrink-0 text-gray-400" />}
        </h1>
        <p className="mt-0.5 text-xs text-gray-500 sm:text-sm">
          {recorrido.fecha} · {recorrido.lugar_tipo === 'faena' ? `Faena ${recorrido.faena?.nombre ?? ''}` : 'Taller'}
          {recorrido.sector ? ` · ${recorrido.sector}` : ''}
          {recorrido.foco ? ` · Foco: ${recorrido.foco}` : ''}
        </p>
      </div>

      {/* ── Avance, siempre a la vista ── */}
      {/* Sticky: con el teclado abierto y 12 ítems, saber cuánto falta sin
          volver arriba es la diferencia entre terminarlo y abandonarlo. */}
      <div className="sticky top-0 z-20 -mx-4 border-b border-gray-200 bg-white/95 px-4 py-2 backdrop-blur sm:mx-0 sm:rounded-lg sm:border">
        <div className="flex items-center justify-between text-xs">
          <span className="font-semibold text-gray-700">
            {stats.total - stats.pendientes} de {stats.total} ítems
          </span>
          <span className="flex items-center gap-2">
            <span className="text-green-700">{stats.cumple} ok</span>
            {stats.noCumple > 0 && <span className="font-semibold text-red-700">{stats.noCumple} no</span>}
            {stats.na > 0 && <span className="text-gray-400">{stats.na} n/a</span>}
            {stats.pct != null && <span className="font-bold text-blue-700">{stats.pct}%</span>}
          </span>
        </div>
        <div className="mt-1.5 h-1.5 w-full overflow-hidden rounded-full bg-gray-100">
          <div className="h-full rounded-full bg-amber-500 transition-all"
               style={{ width: `${stats.total ? ((stats.total - stats.pendientes) / stats.total) * 100 : 0}%` }} />
        </div>
      </div>

      {/* ── Checklist por secciones ── */}
      {secciones.map(([titulo, items]) => (
        <Card key={titulo}>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm font-semibold text-gray-700 uppercase tracking-wide">
              {titulo}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {items.map((r) => (
              <div
                key={r.id}
                className={cn(
                  'rounded-lg border p-3',
                  r.evaluacion === 'no_cumple'
                    ? 'border-red-200 bg-red-50/50'
                    : r.evaluacion === 'cumple'
                      ? 'border-green-200 bg-green-50/30'
                      : 'border-gray-200'
                )}
              >
                {/* El texto arriba y los tres botones a lo ancho: en el
                    teléfono se marca con el pulgar, sin apuntar. */}
                <p className="text-sm leading-snug text-gray-800">
                  <span className="mr-2 font-mono text-xs text-gray-400">{r.orden}.</span>
                  {r.item}
                </p>
                <div className="mt-2 grid grid-cols-3 gap-1.5">
                  {EVALS.map((ev) => (
                    <button
                      key={ev.value}
                      type="button"
                      disabled={soloLectura}
                      onClick={() => setEvaluacion(r, ev.value)}
                      className={cn(
                        'min-h-[44px] rounded-lg border text-sm font-semibold transition-colors',
                        r.evaluacion === ev.value
                          ? ev.activeCls
                          : 'border-gray-300 bg-white text-gray-600 active:bg-gray-100 hover:bg-gray-50',
                        soloLectura && 'cursor-not-allowed opacity-60'
                      )}
                    >
                      {ev.label}
                    </button>
                  ))}
                </div>
                {/* La observación solo aparece cuando hay algo que decir: 12
                    cajas de texto vacías es puro ruido para bajar. */}
                {(!soloLectura || r.observacion) && (
                  <input
                    type="text"
                    defaultValue={r.observacion ?? ''}
                    disabled={soloLectura}
                    placeholder="Observación (opcional)…"
                    onBlur={(e) => guardarObservacion(r, e.target.value)}
                    className="mt-2 min-h-[40px] w-full rounded-lg border border-gray-200 bg-white px-3 py-2 text-sm text-gray-700 placeholder:text-gray-300 focus:border-gray-400 focus:outline-none disabled:bg-gray-50"
                  />
                )}

                {/* [MIG389] La evidencia. Aparece cuando el ítem se marca «no
                    cumple» —ahí la foto ES el hallazgo— y también si ya la
                    tiene, para poder verla en un recorrido cerrado. */}
                {(r.evaluacion === 'no_cumple' || r.foto_url) && (
                  <EvidenciaItem
                    r={r}
                    recorridoId={id}
                    soloLectura={soloLectura}
                    onGuardado={() => qc.invalidateQueries({ queryKey: ['gemba-respuestas', id] })}
                  />
                )}
              </div>
            ))}
          </CardContent>
        </Card>
      ))}

      {/* ── Observaciones de cierre ── */}
      {cerrado && recorrido.observaciones && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Observaciones de cierre</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-gray-700 whitespace-pre-wrap">{recorrido.observaciones}</p>
          </CardContent>
        </Card>
      )}

      {/* ── Plan de acción del recorrido ── */}
      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle className="text-base flex items-center gap-2">
            <AlertTriangle className="h-5 w-5 text-amber-500" />
            Plan de acción ({hallazgos?.length ?? 0})
          </CardTitle>
          {!soloLectura && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                setHDescripcion('')
                setHAccion('')
                setHResponsable('')
                setHCompromiso('')
                setModalRespuesta({ id: '', recorrido_id: id!, seccion: '', orden: 0, item: '' })
              }}
            >
              Agregar hallazgo
            </Button>
          )}
        </CardHeader>
        <CardContent>
          {hallazgos && hallazgos.length > 0 ? (
            <ul className="space-y-2">
              {hallazgos.map((h) => {
                const vencido = h.estado !== 'cerrada' && !!h.fecha_compromiso &&
                  h.fecha_compromiso < new Date().toISOString().slice(0, 10)
                return (
                  <li key={h.id} className={cn('rounded-lg border p-3',
                    vencido ? 'border-red-200 bg-red-50/50' : 'border-gray-200')}>
                    <p className="text-sm font-medium text-gray-800">{h.descripcion}</p>
                    {h.accion_correctiva && (
                      <p className="mt-0.5 text-xs text-gray-600">
                        <span className="text-gray-400">Acción:</span> {h.accion_correctiva}
                      </p>
                    )}
                    <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px] text-gray-500">
                      <span>{h.responsable?.nombre_completo ?? h.responsable_texto ?? 'Sin responsable'}</span>
                      {h.fecha_compromiso && (
                        <span className={vencido ? 'font-semibold text-red-700' : ''}>
                          compromiso {h.fecha_compromiso}{vencido ? ' · vencido' : ''}
                        </span>
                      )}
                    </div>
                    {/* El plan de acción sigue vivo aunque el recorrido esté
                        cerrado: una acción se cierra semanas después. Solo se
                        mira el permiso, no el estado del recorrido. */}
                    <select
                      value={h.estado}
                      disabled={!canCreate('prevencion')}
                      onChange={(e) => cambiarEstadoHallazgo(h.id, e.target.value as any)}
                      className={cn(
                        'mt-2 min-h-[40px] w-full rounded-lg border px-2 text-sm font-medium sm:w-44',
                        h.estado === 'cerrada'
                          ? 'border-green-200 bg-green-50 text-green-700'
                          : h.estado === 'en_proceso'
                            ? 'border-blue-200 bg-blue-50 text-blue-700'
                            : 'border-amber-200 bg-amber-50 text-amber-700'
                      )}
                    >
                      <option value="abierta">Abierta</option>
                      <option value="en_proceso">En proceso</option>
                      <option value="cerrada">Cerrada</option>
                    </select>
                  </li>
                )
              })}
            </ul>
          ) : (
            <p className="text-sm text-gray-400">
              Sin hallazgos registrados. Al marcar un ítem como &quot;No cumple&quot; se abre el
              registro del hallazgo automáticamente.
            </p>
          )}
        </CardContent>
      </Card>

      {/* ── Cerrar el recorrido ── */}
      {/* Barra fija abajo: es la acción final y en el teléfono queda bajo el
          pulgar, sin tener que buscarla arriba después de bajar 12 ítems. */}
      {!soloLectura && (
        <>
          <div className="h-16 sm:h-0" />
          <div className="fixed inset-x-0 bottom-0 z-30 border-t border-gray-200 bg-white/95 p-3 backdrop-blur sm:static sm:border-0 sm:bg-transparent sm:p-0 sm:backdrop-blur-none">
            <div className="mx-auto max-w-5xl">
              <Button
                onClick={() => setModalCierre(true)}
                disabled={stats.pendientes > 0}
                className="min-h-[48px] w-full text-base sm:w-auto"
              >
                <CheckCircle2 className="h-5 w-5" />
                {stats.pendientes > 0
                  ? `Faltan ${stats.pendientes} ítem${stats.pendientes === 1 ? '' : 's'}`
                  : 'Cerrar recorrido'}
              </Button>
            </div>
          </div>
        </>
      )}

      {/* ── Modal: registrar hallazgo ── */}
      <Modal
        open={!!modalRespuesta}
        onClose={() => setModalRespuesta(null)}
        title="Registrar hallazgo en el plan de acción"
      >
        <div className="space-y-4">
          <Input
            label="Descripción del hallazgo"
            value={hDescripcion}
            onChange={(e) => setHDescripcion(e.target.value)}
            placeholder="Qué se encontró, dónde…"
          />
          <Input
            label="Acción correctiva propuesta"
            value={hAccion}
            onChange={(e) => setHAccion(e.target.value)}
            placeholder="Qué se hará para corregirlo…"
          />
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Input
              label="Responsable"
              value={hResponsable}
              onChange={(e) => setHResponsable(e.target.value)}
              placeholder="Ej: J. Pérez (Mantención)"
            />
            <Input
              label="Fecha compromiso"
              type="date"
              value={hCompromiso}
              onChange={(e) => setHCompromiso(e.target.value)}
            />
          </div>
          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={() => setModalRespuesta(null)}>
              Omitir
            </Button>
            <Button
              onClick={guardarHallazgo}
              disabled={!hDescripcion.trim()}
              loading={crearHallazgo.isPending}
            >
              Guardar hallazgo
            </Button>
          </div>
        </div>
      </Modal>

      {/* ── Modal: cerrar recorrido ── */}
      <Modal open={modalCierre} onClose={() => setModalCierre(false)} title="Cerrar recorrido">
        <div className="space-y-4">
          <p className="text-sm text-gray-600">
            Al cerrar, el checklist queda bloqueado. Resultado: {stats.cumple} cumple ·{' '}
            {stats.noCumple} no cumple · {stats.na} no aplica
            {stats.pct != null ? ` · ${stats.pct}% de cumplimiento` : ''}.
          </p>
          <Input
            label="Observaciones de cierre (opcional)"
            value={obsCierre}
            onChange={(e) => setObsCierre(e.target.value)}
            placeholder="Resumen, reconocimientos, temas escalados…"
          />
          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={() => setModalCierre(false)}>
              Cancelar
            </Button>
            <Button onClick={cerrarRecorrido} loading={cerrar.isPending}>
              Cerrar recorrido
            </Button>
          </div>
        </div>
      </Modal>
    </div>
  )
}


// ── La evidencia de un hallazgo (MIG389) ────────────────────────────────────
// La foto lleva la fecha y la hora estampadas encima: pegada en un correo o
// impresa en el informe, una foto sin fecha no prueba nada.
//
// Y hay una salida escrita para lo que no se puede fotografiar —un ruido, un
// olor, algo que ya se retiró—. Sin ella la gente termina sacando una foto del
// piso para poder avanzar, y eso es peor que no tener foto: es evidencia falsa.
function EvidenciaItem({ r, recorridoId, soloLectura, onGuardado }: {
  r: GembaRespuesta
  recorridoId?: string
  soloLectura: boolean
  onGuardado: () => void
}) {
  const toast = useToast()
  const [subiendo, setSubiendo] = useState(false)

  const tomar = async (file: File) => {
    if (!recorridoId) return
    setSubiendo(true)
    try {
      const f = await subirFotoGemba(recorridoId, file, r.item.slice(0, 40))
      const { error } = await updateGembaRespuesta(r.id, {
        foto_url: f.url,
        foto_tomada_at: f.tomadaAt,
        foto_lat: f.lat,
        foto_lng: f.lng,
        sin_foto_motivo: null,
      })
      if (error) throw error
      onGuardado()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'No se pudo subir la foto')
    } finally {
      setSubiendo(false)
    }
  }

  const guardarMotivo = async (texto: string) => {
    if (texto.trim() === (r.sin_foto_motivo ?? '')) return
    const { error } = await updateGembaRespuesta(r.id, { sin_foto_motivo: texto.trim() || null })
    if (error) toast.error('No se pudo guardar el motivo')
    else onGuardado()
  }

  const quitar = async () => {
    const { error } = await updateGembaRespuesta(r.id, {
      foto_url: null, foto_tomada_at: null, foto_lat: null, foto_lng: null,
    })
    if (error) toast.error('No se pudo quitar la foto')
    else onGuardado()
  }

  if (r.foto_url) {
    return (
      <div className="mt-2 flex items-center gap-2 rounded-lg border border-gray-200 bg-white p-2">
        <a href={r.foto_url} target="_blank" rel="noreferrer" className="shrink-0">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={r.foto_url} alt="Evidencia" className="h-16 w-16 rounded object-cover hover:opacity-80" />
        </a>
        <div className="min-w-0 flex-1">
          <p className="text-[11px] font-semibold text-gray-700">Evidencia</p>
          {r.foto_tomada_at && (
            <p className="text-[11px] text-gray-500">
              {new Date(r.foto_tomada_at).toLocaleString('es-CL', {
                day: '2-digit', month: '2-digit', year: 'numeric',
                hour: '2-digit', minute: '2-digit',
              })}
            </p>
          )}
          {r.foto_lat != null && r.foto_lng != null && (
            <p className="font-mono text-[10px] text-gray-400">
              {Number(r.foto_lat).toFixed(5)}, {Number(r.foto_lng).toFixed(5)}
            </p>
          )}
        </div>
        {!soloLectura && (
          <button type="button" onClick={quitar} aria-label="Quitar la foto"
                  className="shrink-0 text-gray-400 hover:text-red-600">
            <X className="h-4 w-4" />
          </button>
        )}
      </div>
    )
  }

  if (soloLectura) {
    return r.sin_foto_motivo ? (
      <p className="mt-2 rounded-lg bg-gray-50 p-2 text-[11px] italic text-gray-600">
        Sin foto: {r.sin_foto_motivo}
      </p>
    ) : null
  }

  return (
    <div className="mt-2 space-y-1.5">
      <label className="flex min-h-[44px] cursor-pointer items-center justify-center gap-2 rounded-lg border-2 border-dashed border-red-300 bg-white text-sm font-semibold text-red-700">
        {subiendo ? (
          <><Loader2 className="h-4 w-4 animate-spin" /> Subiendo…</>
        ) : (
          <><Camera className="h-4 w-4" /> Foto del hallazgo</>
        )}
        <input type="file" accept="image/*" capture="environment" className="hidden"
               disabled={subiendo}
               onChange={(e) => { const f = e.target.files?.[0]; if (f) tomar(f) }} />
      </label>
      <input
        type="text"
        defaultValue={r.sin_foto_motivo ?? ''}
        placeholder="…o escriba por qué no se puede fotografiar"
        onBlur={(e) => guardarMotivo(e.target.value)}
        className="min-h-[38px] w-full rounded-lg border border-gray-200 bg-white px-3 py-2 text-xs text-gray-700 placeholder:text-gray-300 focus:border-gray-400 focus:outline-none"
      />
      <p className="text-[10px] leading-snug text-gray-500">
        La foto queda con la fecha y la hora encima. Sin foto ni motivo, el recorrido no se puede
        cerrar.
      </p>
    </div>
  )
}
