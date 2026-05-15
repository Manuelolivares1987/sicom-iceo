'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, CheckCircle2, X, Send, AlertTriangle, Camera, PenLine,
  Clock, MapPin, ClipboardCheck, RefreshCw, Eye,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { useCalamaPlanificaciones } from '@/hooks/use-calama'
import {
  useJornadasPendientesSupervision, useEvidenciasPorOT, useFirmasPorJornada,
  useSupervisarJornada, useDevolverJornadaCorreccion,
} from '@/hooks/use-calama-supervision'
import type { JornadaPendienteSupervision } from '@/lib/services/calama-supervision'

const fmtHms = (s: number | null) => {
  if (!s || s <= 0) return '—'
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  return h > 0 ? `${h}h ${m}m` : `${m}m`
}

export default function AceptacionesPage() {
  useRequireAuth()
  const toast = useToast()

  const { data: planificaciones } = useCalamaPlanificaciones()
  const [planFiltro, setPlanFiltro] = useState<string>('')
  const filtro = useMemo(
    () => (planFiltro ? { planificacionId: planFiltro } : undefined),
    [planFiltro],
  )

  const { data: jornadas, isLoading, error, refetch, isFetching } =
    useJornadasPendientesSupervision(filtro)

  const [detalleAbierto, setDetalleAbierto] = useState<JornadaPendienteSupervision | null>(null)
  const [aceptarAbierto, setAceptarAbierto] = useState<JornadaPendienteSupervision | null>(null)
  const [devolverAbierto, setDevolverAbierto] = useState<JornadaPendienteSupervision | null>(null)
  const [comentario, setComentario] = useState('')
  const [motivoDev, setMotivoDev] = useState('')
  const [obsDev, setObsDev] = useState('')

  const supervisar = useSupervisarJornada()
  const devolver = useDevolverJornadaCorreccion()

  const ejecutarAceptar = () => {
    if (!aceptarAbierto) return
    supervisar.mutate(
      { plan_semanal_ot_id: aceptarAbierto.plan_semanal_ot_id, comentario: comentario || undefined },
      {
        onSuccess: (d) => {
          const estado = (d as { estado_plan_nuevo?: string } | null)?.estado_plan_nuevo ?? 'aceptada'
          toast.success(`Jornada ${estado} (OT ${aceptarAbierto.folio.slice(-12)})`)
          setAceptarAbierto(null)
          setDetalleAbierto(null)
          setComentario('')
        },
        onError: (e) => {
          toast.error(e instanceof Error ? e.message : 'Error al supervisar')
        },
      },
    )
  }

  const ejecutarDevolver = () => {
    if (!devolverAbierto || !motivoDev.trim()) return
    devolver.mutate(
      {
        plan_semanal_ot_id: devolverAbierto.plan_semanal_ot_id,
        motivo: motivoDev.trim(),
        observacion: obsDev || undefined,
      },
      {
        onSuccess: () => {
          toast.success(`Jornada devuelta para corrección (OT ${devolverAbierto.folio.slice(-12)})`)
          setDevolverAbierto(null)
          setDetalleAbierto(null)
          setMotivoDev('')
          setObsDev('')
        },
        onError: (e) => {
          toast.error(e instanceof Error ? e.message : 'Error al devolver')
        },
      },
    )
  }

  return (
    <div className="space-y-4">
      <Link
        href="/dashboard/operacion-calama"
        className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700"
      >
        <ArrowLeft className="h-4 w-4" />
        Volver al dashboard
      </Link>

      <div className="rounded-2xl bg-gradient-to-r from-emerald-700 to-teal-600 p-6 text-white shadow-lg">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <ClipboardCheck className="h-6 w-6" />
          Aceptaciones — OK supervisor
        </h1>
        <p className="text-sm text-white/90 mt-1">
          Jornadas que esperan revisión interna. Aprueba o devuelve al operador con motivo.
        </p>
      </div>

      <Card>
        <CardContent className="p-3 flex flex-wrap gap-3 items-end">
          <div className="flex-1 min-w-[220px]">
            <label className="text-xs text-gray-500">Planificación</label>
            <select
              value={planFiltro}
              onChange={(e) => setPlanFiltro(e.target.value)}
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
            >
              <option value="">Todas</option>
              {(planificaciones ?? []).map((p) => (
                <option key={p.id} value={p.id}>
                  {p.codigo} — {p.nombre}
                </option>
              ))}
            </select>
          </div>
          <Button variant="secondary" onClick={() => refetch()} disabled={isFetching}>
            <RefreshCw className={`h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} /> Refrescar
          </Button>
        </CardContent>
      </Card>

      {isLoading && (
        <div className="flex items-center gap-2 text-sm text-gray-500">
          <Spinner className="h-4 w-4" /> Cargando jornadas pendientes…
        </div>
      )}
      {error && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          Error: {error instanceof Error ? error.message : 'desconocido'}
        </div>
      )}

      {jornadas && jornadas.length === 0 && (
        <Card>
          <CardContent className="p-8 text-center text-sm text-gray-500">
            <CheckCircle2 className="h-8 w-8 mx-auto text-emerald-400 mb-2" />
            No hay jornadas pendientes de aceptación.
          </CardContent>
        </Card>
      )}

      <div className="space-y-2">
        {(jornadas ?? []).map((j) => (
          <JornadaCard
            key={j.plan_semanal_ot_id}
            j={j}
            onRevisar={() => setDetalleAbierto(j)}
            onAprobar={() => setAceptarAbierto(j)}
            onDevolver={() => setDevolverAbierto(j)}
          />
        ))}
      </div>

      {/* Modal detalle */}
      {detalleAbierto && (
        <DetalleJornadaModal
          j={detalleAbierto}
          onClose={() => setDetalleAbierto(null)}
          onAprobar={() => setAceptarAbierto(detalleAbierto)}
          onDevolver={() => setDevolverAbierto(detalleAbierto)}
        />
      )}

      {/* Modal aceptar */}
      <Modal
        open={!!aceptarAbierto}
        onClose={() => !supervisar.isPending && (setAceptarAbierto(null), setComentario(''))}
        title="OK supervisor"
      >
        {aceptarAbierto && (
          <div className="space-y-3 text-sm">
            <div className="rounded border bg-gray-50 p-2 text-xs">
              <div className="font-mono text-gray-500">{aceptarAbierto.folio}</div>
              <div className="text-gray-900 mt-0.5">{aceptarAbierto.titulo ?? '—'}</div>
              <div className="mt-1 text-gray-600">
                Avance: <strong>{Number(aceptarAbierto.avance_pct ?? 0).toFixed(0)}%</strong> ·{' '}
                Estado destino: <strong>
                  {Number(aceptarAbierto.avance_pct ?? 0) >= 100 ? 'cerrada' : 'aceptada'}
                </strong>
              </div>
            </div>
            <div>
              <label className="text-xs text-gray-500">Comentario (opcional)</label>
              <textarea
                rows={3}
                value={comentario}
                onChange={(e) => setComentario(e.target.value)}
                placeholder="Ej: trabajo conforme, cumple inspección visual…"
                className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
              />
            </div>
          </div>
        )}
        <ModalFooter className="-mx-6 -mb-6 mt-4 px-6 pb-6 pt-4 border-t border-gray-100">
          <Button
            variant="secondary"
            onClick={() => { setAceptarAbierto(null); setComentario('') }}
            disabled={supervisar.isPending}
          >
            <X className="h-4 w-4" /> Cancelar
          </Button>
          <Button variant="primary" onClick={ejecutarAceptar} loading={supervisar.isPending}>
            <CheckCircle2 className="h-4 w-4" /> Confirmar OK supervisor
          </Button>
        </ModalFooter>
      </Modal>

      {/* Modal devolver */}
      <Modal
        open={!!devolverAbierto}
        onClose={() => !devolver.isPending && (setDevolverAbierto(null), setMotivoDev(''), setObsDev(''))}
        title="Devolver para corrección"
      >
        {devolverAbierto && (
          <div className="space-y-3 text-sm">
            <div className="rounded border bg-amber-50 p-2 text-xs text-amber-900">
              <div className="flex items-center gap-1 font-medium">
                <AlertTriangle className="h-4 w-4" />
                Esto reabrirá la OT para que el operador corrija
              </div>
              <div className="mt-1 font-mono text-amber-700">{devolverAbierto.folio}</div>
            </div>
            <div>
              <label className="text-xs text-gray-500">Motivo *</label>
              <input
                value={motivoDev}
                onChange={(e) => setMotivoDev(e.target.value)}
                placeholder="Ej: foto despues no muestra el sello, falta firma…"
                className="mt-1 w-full rounded border border-orange-300 px-3 py-2 text-sm"
              />
            </div>
            <div>
              <label className="text-xs text-gray-500">Observación (opcional)</label>
              <textarea
                rows={3}
                value={obsDev}
                onChange={(e) => setObsDev(e.target.value)}
                className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
              />
            </div>
          </div>
        )}
        <ModalFooter className="-mx-6 -mb-6 mt-4 px-6 pb-6 pt-4 border-t border-gray-100">
          <Button
            variant="secondary"
            onClick={() => { setDevolverAbierto(null); setMotivoDev(''); setObsDev('') }}
            disabled={devolver.isPending}
          >
            <X className="h-4 w-4" /> Cancelar
          </Button>
          <Button
            variant="danger"
            onClick={ejecutarDevolver}
            disabled={!motivoDev.trim()}
            loading={devolver.isPending}
          >
            <Send className="h-4 w-4" /> Devolver al operador
          </Button>
        </ModalFooter>
      </Modal>
    </div>
  )
}

function JornadaCard({
  j, onRevisar, onAprobar, onDevolver,
}: {
  j: JornadaPendienteSupervision
  onRevisar: () => void
  onAprobar: () => void
  onDevolver: () => void
}) {
  return (
    <Card>
      <CardContent className="p-3">
        <div className="flex flex-wrap items-start gap-3 justify-between">
          <div className="flex-1 min-w-[220px]">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="font-mono text-xs text-gray-500">{j.folio}</span>
              <span className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${
                j.estado_plan === 'pendiente_aprobacion'
                  ? 'bg-amber-100 text-amber-700'
                  : 'bg-sky-100 text-sky-700'
              }`}>{j.estado_plan}</span>
              <span className="text-[10px] text-gray-500 uppercase">{j.linea_negocio}</span>
            </div>
            <div className="text-sm text-gray-900 mt-1">{j.titulo ?? '—'}</div>
            <div className="text-xs text-gray-500 mt-1 flex flex-wrap gap-3">
              {j.fecha_jornada && <span>📅 {j.nombre_dia} {j.fecha_jornada}</span>}
              {j.responsable_email && <span>👷 {j.responsable_email}</span>}
              <span>Avance: <strong>{Number(j.avance_pct ?? 0).toFixed(0)}%</strong></span>
              <span>Efectivo: <strong>{fmtHms(j.tiempo_efectivo_trabajo_segundos)}</strong></span>
            </div>
            <div className="text-xs text-gray-500 mt-1 flex gap-3">
              <span><Camera className="inline h-3 w-3" /> Antes: {j.evid_antes}</span>
              <span><Camera className="inline h-3 w-3" /> Durante: {j.evid_durante}</span>
              <span><Camera className="inline h-3 w-3" /> Después: {j.evid_despues}</span>
              <span><PenLine className="inline h-3 w-3" /> Firma op: {j.firmas_operador}</span>
            </div>
          </div>
          <div className="flex gap-1 flex-wrap">
            <Button variant="secondary" onClick={onRevisar}>
              <Eye className="h-4 w-4" /> Revisar
            </Button>
            <Button variant="primary" onClick={onAprobar}>
              <CheckCircle2 className="h-4 w-4" /> OK
            </Button>
            <Button variant="danger" onClick={onDevolver}>
              <Send className="h-4 w-4" /> Devolver
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

function DetalleJornadaModal({
  j, onClose, onAprobar, onDevolver,
}: {
  j: JornadaPendienteSupervision
  onClose: () => void
  onAprobar: () => void
  onDevolver: () => void
}) {
  const { data: evidencias } = useEvidenciasPorOT(j.ot_id)
  const { data: firmas } = useFirmasPorJornada(j.plan_semanal_ot_id)

  const evGroup = useMemo(() => {
    const g: Record<string, typeof evidencias> = {}
    for (const e of evidencias ?? []) {
      g[e.contexto] = g[e.contexto] ?? []
      g[e.contexto]!.push(e)
    }
    return g
  }, [evidencias])

  const tiempos = [
    ['En faena',       j.tiempo_en_faena_segundos],
    ['Operativo',      j.tiempo_operativo_bruto_segundos],
    ['Efectivo',       j.tiempo_efectivo_trabajo_segundos],
    ['Pausado',        j.tiempo_pausado_segundos],
    ['Colación',       j.tiempo_colacion_segundos],
    ['Interferencia',  j.tiempo_interferencia_mandante_segundos],
  ] as const

  return (
    <Modal open onClose={onClose} title={`Revisar jornada — ${j.folio}`}>
      <div className="space-y-4 text-sm max-h-[70vh] overflow-y-auto pr-1">
        <section>
          <div className="text-xs uppercase text-gray-500 mb-1">Identificación</div>
          <div className="rounded border bg-gray-50 p-2 space-y-1">
            <div className="font-mono text-xs text-gray-500">{j.folio}</div>
            <div className="text-gray-900">{j.titulo ?? '—'}</div>
            <div className="text-xs text-gray-600">
              {j.linea_negocio} · Plan {j.planificacion_codigo}
            </div>
            <div className="text-xs text-gray-600">
              {j.fecha_jornada && <span>📅 {j.nombre_dia} {j.fecha_jornada} · </span>}
              {j.responsable_email && <span>👷 {j.responsable_email} · </span>}
              <span>Avance: <strong>{Number(j.avance_pct ?? 0).toFixed(0)}%</strong></span>
            </div>
          </div>
        </section>

        <section>
          <div className="text-xs uppercase text-gray-500 mb-1 flex items-center gap-1">
            <Clock className="h-3 w-3" /> Tiempos
          </div>
          <div className="grid grid-cols-3 gap-2">
            {tiempos.map(([label, seg]) => (
              <div key={label} className="rounded border bg-white p-2 text-xs">
                <div className="text-gray-500">{label}</div>
                <div className="font-medium text-gray-900 mt-0.5">{fmtHms(seg)}</div>
              </div>
            ))}
          </div>
        </section>

        <section>
          <div className="text-xs uppercase text-gray-500 mb-1 flex items-center gap-1">
            <Camera className="h-3 w-3" /> Evidencias por momento ({(evidencias ?? []).length})
          </div>
          {['llegada_faena', 'jornada_antes', 'jornada_durante', 'jornada_despues',
            'interferencia_mandante', 'jornada_rechazo'].map((ctx) => {
            const arr = evGroup[ctx] ?? []
            if (arr.length === 0) return null
            return (
              <div key={ctx} className="mb-2">
                <div className="text-[10px] uppercase text-gray-400 mb-1">{ctx}</div>
                <div className="grid grid-cols-3 sm:grid-cols-4 gap-2">
                  {arr.map((e) => (
                    <a
                      key={e.id}
                      href={e.archivo_url}
                      target="_blank"
                      rel="noreferrer"
                      className="block aspect-square rounded border border-gray-200 overflow-hidden bg-gray-50 hover:ring-2 hover:ring-emerald-400 relative"
                    >
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img src={e.archivo_url} alt={e.contexto} className="w-full h-full object-cover" />
                      {e.gps_lat && e.gps_lng && (
                        <span className="absolute bottom-0 left-0 right-0 bg-black/50 text-white text-[9px] px-1 py-0.5 flex items-center gap-0.5">
                          <MapPin className="h-2.5 w-2.5" /> GPS
                        </span>
                      )}
                    </a>
                  ))}
                </div>
              </div>
            )
          })}
          {(evidencias ?? []).length === 0 && (
            <div className="rounded border border-dashed border-red-200 bg-red-50 p-3 text-xs text-red-700">
              ⚠ No hay evidencias registradas en BD para esta OT. Revisa sincronización offline (ver D1_diagnostico_evidencias_calama.sql).
            </div>
          )}
        </section>

        <section>
          <div className="text-xs uppercase text-gray-500 mb-1 flex items-center gap-1">
            <PenLine className="h-3 w-3" /> Firmas ({(firmas ?? []).length})
          </div>
          <div className="grid grid-cols-2 gap-2">
            {(firmas ?? []).map((f) => (
              <div key={f.id} className="rounded border p-2 bg-white">
                <div className="flex items-center justify-between text-xs">
                  <span className="font-medium">{f.firmante_tipo}</span>
                  <span className="text-gray-500">{f.contexto ?? '—'}</span>
                </div>
                {f.firmante_nombre && <div className="text-xs text-gray-700">{f.firmante_nombre}</div>}
                <a href={f.firma_url} target="_blank" rel="noreferrer" className="block mt-1 border rounded bg-gray-50 overflow-hidden">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={f.firma_url} alt="firma" className="w-full h-24 object-contain" />
                </a>
                {f.observacion && <div className="text-[10px] text-gray-500 mt-1 italic">{f.observacion}</div>}
              </div>
            ))}
            {(firmas ?? []).length === 0 && (
              <div className="col-span-2 rounded border border-dashed border-gray-200 p-3 text-xs text-gray-400">
                Sin firmas registradas para esta jornada.
              </div>
            )}
          </div>
        </section>
      </div>
      <ModalFooter className="-mx-6 -mb-6 mt-4 px-6 pb-6 pt-4 border-t border-gray-100">
        <Button variant="secondary" onClick={onClose}>
          <X className="h-4 w-4" /> Cerrar
        </Button>
        <Button variant="danger" onClick={onDevolver}>
          <Send className="h-4 w-4" /> Devolver para corrección
        </Button>
        <Button variant="primary" onClick={onAprobar}>
          <CheckCircle2 className="h-4 w-4" /> OK supervisor
        </Button>
      </ModalFooter>
    </Modal>
  )
}

