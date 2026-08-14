'use client'

import { useMemo, useState } from 'react'
import { useParams } from 'next/navigation'
import Link from 'next/link'
import { ArrowLeft, Footprints, AlertTriangle, CheckCircle2, Lock } from 'lucide-react'
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
      <div>
        <Link
          href="/dashboard/prevencion/gemba"
          className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700"
        >
          <ArrowLeft className="h-4 w-4" /> Volver a recorridos
        </Link>
        <div className="mt-2 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
              <Footprints className="h-7 w-7 text-amber-500" />
              {recorrido.plantilla?.nombre ?? 'Recorrido Gemba'}
              {cerrado && <Lock className="h-5 w-5 text-gray-400" />}
            </h1>
            <p className="text-sm text-gray-500 mt-1">
              {recorrido.fecha} · {recorrido.lugar_tipo === 'faena' ? `Faena ${recorrido.faena?.nombre ?? ''}` : 'Taller'}
              {recorrido.sector ? ` · ${recorrido.sector}` : ''}
              {recorrido.foco ? ` · Foco: ${recorrido.foco}` : ''}
            </p>
          </div>
          {!soloLectura && (
            <Button onClick={() => setModalCierre(true)} disabled={stats.pendientes > 0}>
              <CheckCircle2 className="h-4 w-4" />
              {stats.pendientes > 0 ? `Faltan ${stats.pendientes} ítems` : 'Cerrar recorrido'}
            </Button>
          )}
        </div>
      </div>

      {/* ── Barra de avance ── */}
      <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
        {[
          { label: 'Cumple', value: stats.cumple, cls: 'text-green-700 bg-green-50 border-green-200' },
          { label: 'No cumple', value: stats.noCumple, cls: 'text-red-700 bg-red-50 border-red-200' },
          { label: 'No aplica', value: stats.na, cls: 'text-gray-600 bg-gray-50 border-gray-200' },
          { label: 'Pendientes', value: stats.pendientes, cls: 'text-amber-700 bg-amber-50 border-amber-200' },
          { label: '% Cumplimiento', value: stats.pct != null ? `${stats.pct}%` : '—', cls: 'text-blue-700 bg-blue-50 border-blue-200' },
        ].map((s) => (
          <div key={s.label} className={cn('rounded-lg border p-3 text-center', s.cls)}>
            <div className="text-xl font-bold">{s.value}</div>
            <div className="text-xs">{s.label}</div>
          </div>
        ))}
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
                <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
                  <p className="flex-1 text-sm text-gray-800">
                    <span className="mr-2 font-mono text-xs text-gray-400">{r.orden}.</span>
                    {r.item}
                  </p>
                  <div className="flex shrink-0 gap-1">
                    {EVALS.map((ev) => (
                      <button
                        key={ev.value}
                        type="button"
                        disabled={soloLectura}
                        onClick={() => setEvaluacion(r, ev.value)}
                        className={cn(
                          'rounded border px-2.5 py-1 text-xs font-medium transition-colors',
                          r.evaluacion === ev.value
                            ? ev.activeCls
                            : 'border-gray-300 bg-white text-gray-600 hover:bg-gray-50',
                          soloLectura && 'cursor-not-allowed opacity-60'
                        )}
                      >
                        {ev.label}
                      </button>
                    ))}
                  </div>
                </div>
                <input
                  type="text"
                  defaultValue={r.observacion ?? ''}
                  disabled={soloLectura}
                  placeholder="Observación / hallazgo concreto…"
                  onBlur={(e) => guardarObservacion(r, e.target.value)}
                  className="mt-2 w-full rounded border border-gray-200 bg-white px-2 py-1 text-xs text-gray-700 placeholder:text-gray-300 focus:border-gray-400 focus:outline-none disabled:bg-gray-50"
                />
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
        <CardContent className="overflow-x-auto">
          {hallazgos && hallazgos.length > 0 ? (
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b text-left text-gray-500 uppercase">
                  <th className="px-2 py-2">Hallazgo</th>
                  <th className="px-2 py-2">Acción correctiva</th>
                  <th className="px-2 py-2">Responsable</th>
                  <th className="px-2 py-2">Compromiso</th>
                  <th className="px-2 py-2">Estado</th>
                </tr>
              </thead>
              <tbody>
                {hallazgos.map((h) => (
                  <tr key={h.id} className="border-b hover:bg-gray-50">
                    <td className="px-2 py-2 max-w-md">{h.descripcion}</td>
                    <td className="px-2 py-2 max-w-md text-gray-600">{h.accion_correctiva || '—'}</td>
                    <td className="px-2 py-2">
                      {h.responsable?.nombre_completo ?? h.responsable_texto ?? '—'}
                    </td>
                    <td className="px-2 py-2 whitespace-nowrap">{h.fecha_compromiso ?? '—'}</td>
                    <td className="px-2 py-2">
                      {/* El plan de acción sigue vivo aunque el recorrido esté
                          cerrado: una acción se cierra semanas después. Solo
                          se mira el permiso, no el estado del recorrido. */}
                      <select
                        value={h.estado}
                        disabled={!canCreate('prevencion')}
                        onChange={(e) => cambiarEstadoHallazgo(h.id, e.target.value as any)}
                        className={cn(
                          'rounded border px-1.5 py-0.5 text-xs',
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
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-gray-400">
              Sin hallazgos registrados. Al marcar un ítem como &quot;No cumple&quot; se abre el
              registro del hallazgo automáticamente.
            </p>
          )}
        </CardContent>
      </Card>

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
