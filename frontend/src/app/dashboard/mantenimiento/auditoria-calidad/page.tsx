'use client'

import { useMemo, useState } from 'react'
import {
  ShieldCheck, AlertTriangle, CheckCircle2, XCircle, MinusCircle,
  ClipboardList, Clock, PlusCircle, FileWarning, Gauge,
  Calendar, ChevronLeft, ChevronRight, Play, Trash2, Layers,
} from 'lucide-react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Input } from '@/components/ui/input'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { usePermissions } from '@/hooks/use-permissions'
import {
  useAuditoriasPendientes, useAuditoriaItems, useEquiposParaAuditar,
  useIniciarAuditoria, useResolverAuditoria, useDiferidosActivo,
  useDiferirItem, useGenerarOtPendientes, useKpiCalidadTaller,
} from '@/hooks/use-control-calidad'
import {
  getTareasSemanaCalidad, agregarTareaCalidad, actualizarTareaCalidad, eliminarTareaCalidad,
  lunesDeIsoCalidad, CALIDAD_TIPO_LABEL,
  type CalidadPlanTarea, type CalidadTareaTipo,
} from '@/lib/services/calidad-plan'
import { subirFirma } from '@/lib/services/verificacion'
import { supabase } from '@/lib/supabase'
import { cn } from '@/lib/utils'

type Res = 'ok' | 'no_ok' | 'na' | 'pendiente'

export default function AuditoriaCalidadPage() {
  useRequireAuth()
  const { rol, canApprove } = usePermissions()
  const puedeAuditar = rol === 'auditor_calidad' || rol === 'administrador' || canApprove('mantenimiento')

  const [backfillRunning, setBackfillRunning] = useState(false)
  const [backfillMsg, setBackfillMsg] = useState<string | null>(null)
  const pasarDisponiblesPorCalidad = async () => {
    if (!window.confirm('Se creará una OT de inspección (con su checklist de calidad) para cada equipo disponible. ¿Continuar?')) return
    setBackfillRunning(true); setBackfillMsg(null)
    try {
      const { data, error } = await supabase.rpc('fn_crear_ot_inspeccion_disponibles')
      if (error) throw error
      const r = data as { ot_creadas: number; omitidos_ya_en_proceso: number; omitidos_sin_contrato_faena: number }
      setBackfillMsg(`OT creadas: ${r.ot_creadas} · ya en proceso: ${r.omitidos_ya_en_proceso} · sin contrato/faena: ${r.omitidos_sin_contrato_faena}`)
    } catch (e) {
      setBackfillMsg(`Error: ${(e as Error).message}`)
    } finally {
      setBackfillRunning(false)
    }
  }

  const { data: kpi } = useKpiCalidadTaller()
  const { data: pendientes = [], isLoading: loadingPend } = useAuditoriasPendientes()
  const { data: equipos = [] } = useEquiposParaAuditar()
  const iniciar = useIniciarAuditoria()

  const [sel, setSel] = useState<{ auditoria_id: string; activo_id: string; label: string } | null>(null)
  const [tab, setTab] = useState<'auditorias' | 'plan'>('auditorias')

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <ShieldCheck className="h-6 w-6 text-emerald-600" /> Auditoría de calidad (pre-operativo)
        </h1>
        <p className="text-sm text-muted-foreground">
          Liberación a servicio. El auditor de calidad aprueba la calidad técnica + la
          documentación del equipo. Su firma es el visto bueno de calidad (ready-to-rent).
        </p>
        {puedeAuditar && tab === 'auditorias' && (
          <div className="mt-3 flex flex-wrap items-center gap-3">
            <Button size="sm" variant="outline" disabled={backfillRunning}
              onClick={pasarDisponiblesPorCalidad}>
              <ClipboardList className="h-4 w-4 mr-1" />
              {backfillRunning ? 'Generando…' : 'Pasar disponibles por calidad'}
            </Button>
            {backfillMsg && <span className="text-xs text-muted-foreground">{backfillMsg}</span>}
          </div>
        )}
      </div>

      {/* Tabs: Auditorías | Plan semanal */}
      <div className="flex gap-2 border-b">
        {([['auditorias', 'Auditorías', ShieldCheck], ['plan', 'Plan semanal', Layers]] as const).map(([id, label, Icon]) => (
          <button key={id} onClick={() => setTab(id)}
                  className={cn('flex items-center gap-1 px-3 py-2 text-sm font-medium border-b-2 transition-colors',
                    tab === id ? 'border-emerald-600 text-emerald-700' : 'border-transparent text-gray-500 hover:text-gray-700')}>
            <Icon className="h-4 w-4" /> {label}
          </button>
        ))}
      </div>

      {tab === 'plan' && <PlanSemanalCalidad puedeAuditar={puedeAuditar} />}

      {tab === 'auditorias' && <>
      {/* KPIs */}
      {kpi && (
        <div className="grid gap-3 grid-cols-2 md:grid-cols-4 lg:grid-cols-6">
          <Kpi label="Audit pass rate (30d)" value={`${kpi.aud_pass_rate_pct ?? '—'}%`} icon={Gauge} />
          <Kpi label="Chequeo OK 1ª vez" value={`${kpi.cc_first_time_ok_pct ?? '—'}%`} icon={CheckCircle2} />
          <Kpi label="Diferidos pendientes" value={kpi.diferidos_pendientes ?? 0} icon={Clock} />
          <Kpi label="Diferidos vencidos" value={kpi.diferidos_vencidos ?? 0} icon={AlertTriangle} warn={(kpi.diferidos_vencidos ?? 0) > 0} />
          <Kpi label="Pendientes críticos" value={kpi.diferidos_criticos ?? 0} icon={FileWarning} warn={(kpi.diferidos_criticos ?? 0) > 0} />
          <Kpi label="NCR abiertas" value={kpi.nc_abiertas ?? 0} icon={ShieldCheck} />
        </div>
      )}

      {!puedeAuditar && (
        <Card><CardContent className="py-4 text-sm text-amber-700 flex items-center gap-2">
          <AlertTriangle className="h-4 w-4" /> Solo el rol Auditor de Calidad puede resolver auditorías. Tienes vista de lectura.
        </CardContent></Card>
      )}

      <div className="grid gap-6 lg:grid-cols-[340px_1fr]">
        <div className="space-y-6">
          {/* Iniciar auditoría */}
          <Card>
            <CardHeader><CardTitle className="text-base">Equipos para auditar</CardTitle></CardHeader>
            <CardContent className="space-y-2 max-h-72 overflow-auto">
              {equipos.length === 0 && <p className="text-sm text-muted-foreground py-4 text-center">Sin equipos en mantención.</p>}
              {equipos.map((e: any) => (
                <div key={e.id} className="flex items-center justify-between rounded border p-2 text-sm">
                  <div>
                    <div className="font-medium">{e.patente ?? e.codigo}</div>
                    <div className="text-xs text-muted-foreground flex items-center gap-1">
                      {e.estado}
                      {e.estado_comercial === 'disponible' && <Badge variant="operativo" className="text-[9px]">disponible</Badge>}
                    </div>
                  </div>
                  <Button size="sm" variant="outline" disabled={!puedeAuditar || iniciar.isPending}
                    onClick={async () => {
                      const r: any = await iniciar.mutateAsync({ activo_id: e.id })
                      if (r?.auditoria_id) setSel({ auditoria_id: r.auditoria_id, activo_id: e.id, label: e.patente ?? e.codigo })
                    }}>
                    <PlusCircle className="h-4 w-4 mr-1" /> Iniciar
                  </Button>
                </div>
              ))}
            </CardContent>
          </Card>

          {/* Auditorías en curso */}
          <Card>
            <CardHeader><CardTitle className="text-base">Auditorías pendientes ({pendientes.length})</CardTitle></CardHeader>
            <CardContent className="space-y-2">
              {loadingPend && <Spinner className="h-5 w-5" />}
              {pendientes.map((a: any) => (
                <button key={a.id}
                  onClick={() => setSel({ auditoria_id: a.id, activo_id: a.activo_id, label: a.patente ?? a.codigo })}
                  className={cn('w-full text-left rounded-lg border p-3 text-sm transition-colors',
                    sel?.auditoria_id === a.id ? 'border-emerald-500 bg-emerald-50' : 'hover:bg-muted')}>
                  <div className="font-semibold">{a.patente ?? a.codigo}</div>
                  <div className="text-xs text-muted-foreground">{a.items_total} ítems · {a.folio ?? 'sin OT'}</div>
                </button>
              ))}
            </CardContent>
          </Card>
        </div>

        {/* Detalle */}
        {sel
          ? <AuditoriaDetalle key={sel.auditoria_id} sel={sel} puedeAuditar={puedeAuditar} onDone={() => setSel(null)} />
          : <Card><CardContent className="py-16 text-center text-muted-foreground">
              <ShieldCheck className="h-10 w-10 mx-auto mb-2 opacity-40" />
              Inicia o selecciona una auditoría.
            </CardContent></Card>}
      </div>
      </>}
    </div>
  )
}

// ── Plan semanal de Calidad (MIG225) ─────────────────────────────────────────
// El encargado de calidad programa sus tareas de la semana con un modal tipo
// "Programar tarea" del plan del taller.

const TIPO_COLOR: Record<string, string> = {
  auditoria: 'bg-emerald-100 text-emerald-800 border-emerald-300',
  chequeo_cruzado: 'bg-blue-100 text-blue-800 border-blue-300',
  inspeccion: 'bg-amber-100 text-amber-800 border-amber-300',
  documentacion: 'bg-purple-100 text-purple-800 border-purple-300',
  otro: 'bg-gray-100 text-gray-700 border-gray-300',
}
const ESTADO_CHIP: Record<string, string> = {
  pendiente: 'bg-gray-100 text-gray-600',
  en_curso: 'bg-amber-100 text-amber-800',
  hecha: 'bg-green-100 text-green-800',
  cancelada: 'bg-gray-200 text-gray-500 line-through',
}

function fmtDiaCorto(iso: string): string {
  return new Date(iso + 'T12:00:00').toLocaleDateString('es-CL', { weekday: 'long', day: '2-digit', month: 'short' })
}

function PlanSemanalCalidad({ puedeAuditar }: { puedeAuditar: boolean }) {
  const toast = useToast()
  const qc = useQueryClient()
  const [lunes, setLunes] = useState<string>(() => lunesDeIsoCalidad(new Date()))
  const [modalOpen, setModalOpen] = useState(false)
  const { data: tareas = [], isLoading } = useQuery({
    queryKey: ['calidad-plan-semana', lunes],
    queryFn: () => getTareasSemanaCalidad(lunes),
    staleTime: 15_000,
  })

  const dias = useMemo(() => Array.from({ length: 7 }, (_, i) => {
    const d = new Date(lunes + 'T12:00:00'); d.setDate(d.getDate() + i)
    return d.toISOString().slice(0, 10)
  }), [lunes])

  const navSemana = (delta: number) => {
    const d = new Date(lunes + 'T12:00:00'); d.setDate(d.getDate() + delta * 7)
    setLunes(lunesDeIsoCalidad(d))
  }
  const refetch = () => qc.invalidateQueries({ queryKey: ['calidad-plan-semana'] })

  const setEstado = async (t: CalidadPlanTarea, estado: CalidadPlanTarea['estado']) => {
    try { await actualizarTareaCalidad(t.id, { estado }); refetch() }
    catch (e) { toast.error((e as Error).message) }
  }
  const eliminar = async (t: CalidadPlanTarea) => {
    try { await eliminarTareaCalidad(t.id); toast.success('Tarea eliminada'); refetch() }
    catch (e) { toast.error((e as Error).message) }
  }

  const resumen = useMemo(() => ({
    total: tareas.length,
    hechas: tareas.filter((t) => t.estado === 'hecha').length,
  }), [tareas])

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <Button variant="outline" size="sm" onClick={() => navSemana(-1)}><ChevronLeft className="h-4 w-4" /></Button>
          <Button variant="outline" size="sm" onClick={() => setLunes(lunesDeIsoCalidad(new Date()))}>
            <Calendar className="h-4 w-4 mr-1" /> Hoy
          </Button>
          <Button variant="outline" size="sm" onClick={() => navSemana(1)}><ChevronRight className="h-4 w-4" /></Button>
          <span className="text-sm text-gray-500">Semana del <b>{fmtDiaCorto(lunes)}</b></span>
        </div>
        <div className="flex items-center gap-3">
          <span className="text-xs text-gray-500">{resumen.hechas}/{resumen.total} hechas</span>
          {puedeAuditar && (
            <Button size="sm" onClick={() => setModalOpen(true)}>
              <PlusCircle className="h-4 w-4 mr-1" /> Programar tarea
            </Button>
          )}
        </div>
      </div>

      {isLoading ? (
        <div className="flex justify-center py-10"><Spinner /></div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-7 gap-2">
          {dias.map((fecha) => {
            const delDia = tareas.filter((t) => t.fecha === fecha)
            const esHoy = fecha === new Date().toISOString().slice(0, 10)
            return (
              <div key={fecha} className={cn('rounded-lg border bg-white p-2 min-h-[120px]', esHoy && 'border-emerald-400 bg-emerald-50/40')}>
                <div className="mb-2 flex items-center justify-between">
                  <span className="text-xs font-semibold capitalize">{fmtDiaCorto(fecha)}</span>
                  {esHoy && <span className="rounded-full bg-emerald-600 px-1.5 py-0.5 text-[9px] font-bold text-white">HOY</span>}
                </div>
                <div className="space-y-1.5">
                  {delDia.length === 0 && <div className="py-3 text-center text-[11px] text-gray-300">Sin tareas</div>}
                  {delDia.map((t) => (
                    <div key={t.id} className="rounded border bg-white p-2 shadow-sm">
                      <div className="flex items-center gap-1">
                        <span className={cn('rounded border px-1 py-0.5 text-[8px] font-bold uppercase', TIPO_COLOR[t.tipo])}>
                          {CALIDAD_TIPO_LABEL[t.tipo]}
                        </span>
                        <span className={cn('rounded-full px-1.5 py-0.5 text-[9px] font-medium', ESTADO_CHIP[t.estado])}>{t.estado.replace('_', ' ')}</span>
                      </div>
                      <div className="mt-1 text-xs font-medium text-gray-800">{t.titulo}</div>
                      {t.equipo_texto && <div className="text-[10px] font-mono text-gray-500">{t.equipo_texto}</div>}
                      {t.descripcion && <div className="text-[10px] text-gray-400 line-clamp-2">{t.descripcion}</div>}
                      <div className="mt-0.5 flex items-center gap-1 text-[10px] text-gray-400">
                        {t.responsable && <span>{t.responsable}</span>}
                        {t.horas_estimadas != null && <span>· {t.horas_estimadas}h</span>}
                      </div>
                      {puedeAuditar && t.estado !== 'hecha' && t.estado !== 'cancelada' && (
                        <div className="mt-1.5 flex items-center gap-1">
                          {t.estado === 'pendiente' && (
                            <button type="button" title="Iniciar" onClick={() => setEstado(t, 'en_curso')}
                                    className="rounded border border-amber-300 bg-amber-50 p-1 text-amber-700"><Play className="h-3 w-3" /></button>
                          )}
                          <button type="button" title="Marcar hecha" onClick={() => setEstado(t, 'hecha')}
                                  className="rounded border border-green-300 bg-green-50 p-1 text-green-700"><CheckCircle2 className="h-3 w-3" /></button>
                          <button type="button" title="Eliminar" onClick={() => eliminar(t)}
                                  className="ml-auto rounded border border-red-200 bg-red-50 p-1 text-red-500"><Trash2 className="h-3 w-3" /></button>
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )
          })}
        </div>
      )}

      {modalOpen && (
        <ProgramarTareaCalidadModal
          dias={dias}
          onClose={() => setModalOpen(false)}
          onDone={() => { setModalOpen(false); refetch() }}
        />
      )}
    </div>
  )
}

function ProgramarTareaCalidadModal({ dias, onClose, onDone }: {
  dias: string[]; onClose: () => void; onDone: () => void
}) {
  const toast = useToast()
  const [tipo, setTipo] = useState<CalidadTareaTipo>('auditoria')
  const [titulo, setTitulo] = useState('')
  const [equipo, setEquipo] = useState('')
  const [descripcion, setDescripcion] = useState('')
  const [fecha, setFecha] = useState(dias[0])
  const [responsable, setResponsable] = useState('')
  const [horas, setHoras] = useState('')
  const [enviando, setEnviando] = useState(false)

  const submit = async () => {
    if (!titulo.trim()) return
    setEnviando(true)
    try {
      await agregarTareaCalidad({
        fecha, titulo: titulo.trim(), tipo,
        descripcion: descripcion.trim() || null,
        equipoTexto: equipo.trim() || null,
        responsable: responsable.trim() || null,
        horas: horas ? Number(horas) : null,
      })
      toast.success('Tarea de calidad programada')
      onDone()
    } catch (e) { toast.error((e as Error).message) } finally { setEnviando(false) }
  }

  return (
    <Modal open onClose={onClose} title="Programar tarea de calidad">
      <div className="space-y-3">
        <div>
          <label className="text-xs font-medium">Tipo de tarea</label>
          <select value={tipo} onChange={(e) => setTipo(e.target.value as CalidadTareaTipo)}
                  className="w-full border rounded px-2 py-1.5 text-sm">
            {(Object.entries(CALIDAD_TIPO_LABEL) as [CalidadTareaTipo, string][]).map(([k, l]) => (
              <option key={k} value={k}>{l}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="text-xs font-medium">Título <span className="text-red-500">*</span></label>
          <Input value={titulo} onChange={(e) => setTitulo(e.target.value)} autoFocus
                 placeholder="Ej. Auditoría pre-operativo JTYK-88" />
        </div>
        <div>
          <label className="text-xs font-medium">Equipo / lugar (opcional)</label>
          <Input value={equipo} onChange={(e) => setEquipo(e.target.value)} placeholder="Ej. JTYK-88 — Taller Coquimbo" />
        </div>
        <div>
          <label className="text-xs font-medium">Descripción</label>
          <textarea value={descripcion} onChange={(e) => setDescripcion(e.target.value)} rows={2}
                    className="w-full border rounded px-2 py-1.5 text-sm" placeholder="Detalle del trabajo" />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="text-xs font-medium">Día</label>
            <select value={fecha} onChange={(e) => setFecha(e.target.value)}
                    className="w-full border rounded px-2 py-1.5 text-sm capitalize">
              {dias.map((d) => <option key={d} value={d}>{fmtDiaCorto(d)}</option>)}
            </select>
          </div>
          <div>
            <label className="text-xs font-medium">Horas estimadas</label>
            <Input type="number" min="0" step="0.5" value={horas} onChange={(e) => setHoras(e.target.value)} placeholder="opcional" />
          </div>
        </div>
        <div>
          <label className="text-xs font-medium">Responsable</label>
          <Input value={responsable} onChange={(e) => setResponsable(e.target.value)} placeholder="Ej. Felipe López" />
        </div>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button disabled={!titulo.trim() || enviando} onClick={submit}>
          {enviando ? <Spinner className="h-4 w-4 mr-1" /> : <PlusCircle className="h-4 w-4 mr-1" />}
          Programar
        </Button>
      </ModalFooter>
    </Modal>
  )
}

function AuditoriaDetalle({ sel, puedeAuditar, onDone }: {
  sel: { auditoria_id: string; activo_id: string; label: string }; puedeAuditar: boolean; onDone: () => void
}) {
  const { data: items = [], isLoading } = useAuditoriaItems(sel.auditoria_id)
  const { data: diferidos = [] } = useDiferidosActivo(sel.activo_id)
  const resolver = useResolverAuditoria()
  const diferir = useDiferirItem()
  const generarOt = useGenerarOtPendientes()

  const [estado, setEstado] = useState<Record<string, { resultado: Res; observacion: string }>>({})
  const [obs, setObs] = useState('')
  const [motivo, setMotivo] = useState('')
  const [dias, setDias] = useState(3)
  const [firma, setFirma] = useState<string | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  // form diferir
  const [dDesc, setDDesc] = useState('')
  const [dSist, setDSist] = useState('')
  const [dSev, setDSev] = useState<'baja' | 'media' | 'alta' | 'critica'>('media')
  const [dSeg, setDSeg] = useState(false)
  const [dMot, setDMot] = useState('')

  const itemState = (id: string, dflt: Res): { resultado: Res; observacion: string } =>
    estado[id] ?? { resultado: dflt, observacion: '' }
  const setItem = (id: string, dflt: Res, patch: Partial<{ resultado: Res; observacion: string }>) =>
    setEstado((s) => ({ ...s, [id]: { ...itemState(id, dflt), ...patch } }))

  const tecnica = items.filter((i) => i.categoria === 'tecnica')
  const docs = items.filter((i) => i.categoria === 'documentacion')

  const resumen = useMemo(() => {
    let critFail = 0, oblPend = 0
    for (const it of items) {
      const r = itemState(it.id, it.resultado).resultado
      if (it.critico && r === 'no_ok') critFail++
      if (it.obligatorio && r !== 'ok' && r !== 'na') oblPend++
    }
    return { critFail, oblPend }
  }, [items, estado])

  const criticosPendientes = diferidos.filter((d: any) => d.diferible === false && d.estado === 'pendiente').length

  const enviar = async (resultado: 'aprobado' | 'aprobado_con_observaciones' | 'rechazado') => {
    setErr(null)
    if (resultado !== 'rechazado') {
      if (resumen.critFail > 0) { setErr('Hay ítems críticos en NO OK: no se puede aprobar.'); return }
      if (resumen.oblPend > 0) { setErr('Faltan ítems obligatorios por marcar.'); return }
      if (criticosPendientes > 0) { setErr(`Hay ${criticosPendientes} pendiente(s) crítico(s) sin resolver. Bloquean la liberación.`); return }
    }
    setSaving(true)
    try {
      let firmaUrl: string | null = null
      if (firma) {
        const { data, error } = await subirFirma(sel.auditoria_id, 'aprobador', firma)
        if (error) throw error
        firmaUrl = data
      }
      await resolver.mutateAsync({
        auditoria_id: sel.auditoria_id,
        resultado,
        items: items.map((it) => ({
          id: it.id,
          resultado: itemState(it.id, it.resultado).resultado === 'pendiente' ? 'na' : itemState(it.id, it.resultado).resultado,
          observacion: itemState(it.id, it.resultado).observacion || null,
        })),
        motivo_rechazo: resultado === 'rechazado' ? (motivo || 'Sin detalle') : null,
        observaciones: obs || null,
        firma_url: firmaUrl,
        dias_vigencia: dias,
      })
      onDone()
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : 'Error al resolver la auditoría')
    } finally { setSaving(false) }
  }

  const agregarDiferido = async () => {
    if (!dDesc.trim()) return
    setErr(null)
    try {
      await diferir.mutateAsync({
        activo_id: sel.activo_id, descripcion: dDesc, sistema: dSist || null,
        severidad: dSev, es_seguridad: dSeg, motivo: dMot || null,
        origen_tipo: 'auditoria', origen_auditoria_id: sel.auditoria_id,
      })
      setDDesc(''); setDSist(''); setDMot(''); setDSev('media'); setDSeg(false)
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : 'Error al diferir')
    }
  }

  const renderItems = (list: typeof items, titulo: string) => (
    <div className="space-y-2">
      <h3 className="text-sm font-semibold text-muted-foreground">{titulo}</h3>
      {list.map((it) => {
        const st = itemState(it.id, it.resultado)
        return (
          <div key={it.id} className={cn('rounded-lg border p-3 space-y-2', it.critico && 'border-red-200')}>
            <div className="flex items-start justify-between gap-3">
              <div className="text-sm">
                <span className="font-medium">{it.descripcion}</span>
                {it.critico && <Badge variant="critica" className="ml-2 text-[10px]">crítico</Badge>}
                {it.referencia_cert_id && <Badge variant="default" className="ml-2 text-[10px]">cert. vinculada</Badge>}
              </div>
              <div className="flex gap-1 shrink-0">
                <Tg active={st.resultado === 'ok'} c="green" onClick={() => setItem(it.id, it.resultado, { resultado: 'ok' })}><CheckCircle2 className="h-4 w-4" /></Tg>
                <Tg active={st.resultado === 'no_ok'} c="red" onClick={() => setItem(it.id, it.resultado, { resultado: 'no_ok' })}><XCircle className="h-4 w-4" /></Tg>
                <Tg active={st.resultado === 'na'} c="gray" onClick={() => setItem(it.id, it.resultado, { resultado: 'na' })}><MinusCircle className="h-4 w-4" /></Tg>
              </div>
            </div>
            {st.resultado === 'no_ok' && (
              <input className="w-full rounded border px-2 py-1 text-sm" placeholder="Observación del hallazgo"
                value={st.observacion} onChange={(e) => setItem(it.id, it.resultado, { observacion: e.target.value })} />
            )}
          </div>
        )
      })}
    </div>
  )

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base flex items-center justify-between">
          <span>{sel.label}</span>
          {criticosPendientes > 0 && <Badge variant="critica">{criticosPendientes} crítico(s) bloquea(n)</Badge>}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-5">
        {isLoading && <Spinner className="h-5 w-5" />}
        {renderItems(tecnica, 'Calidad técnica')}
        {renderItems(docs, 'Documentación')}

        {/* Diferidos */}
        <div className="rounded-lg border border-amber-200 bg-amber-50/50 p-3 space-y-3">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-semibold flex items-center gap-1">
              <Clock className="h-4 w-4" /> Pendientes / diferidos del equipo ({diferidos.length})
            </h3>
            {diferidos.length > 0 && (
              <Button size="sm" variant="outline" disabled={generarOt.isPending}
                onClick={() => generarOt.mutate(sel.activo_id)}>
                <ClipboardList className="h-4 w-4 mr-1" /> Agrupar en OT
              </Button>
            )}
          </div>
          {diferidos.map((d: any) => (
            <div key={d.id} className="text-xs rounded border bg-white p-2 flex items-center justify-between">
              <span>{d.descripcion} {d.sistema && `· ${d.sistema}`}</span>
              <span className="flex items-center gap-2">
                <Badge variant={d.diferible === false ? 'critica' : 'default'} className="text-[10px]">{d.severidad}</Badge>
                {d.diferible === false
                  ? <span className="text-red-600">no diferible</span>
                  : <span className={cn(d.estado === 'vencido' && 'text-red-600 font-semibold')}>
                      plazo {d.plazo_fecha_limite ?? 's/d'} ({d.plazo_origen})
                    </span>}
              </span>
            </div>
          ))}
          {/* Form diferir */}
          {puedeAuditar && (
            <div className="grid gap-2 sm:grid-cols-2 border-t pt-2">
              <input className="rounded border px-2 py-1 text-sm" placeholder="Descripción del pendiente"
                value={dDesc} onChange={(e) => setDDesc(e.target.value)} />
              <input className="rounded border px-2 py-1 text-sm" placeholder="Sistema (frenos, motor…)"
                value={dSist} onChange={(e) => setDSist(e.target.value)} />
              <select className="rounded border px-2 py-1 text-sm" value={dSev}
                onChange={(e) => setDSev(e.target.value as any)}>
                <option value="baja">Baja</option><option value="media">Media</option>
                <option value="alta">Alta</option><option value="critica">Crítica (no diferible)</option>
              </select>
              <label className="flex items-center gap-2 text-sm">
                <input type="checkbox" checked={dSeg} onChange={(e) => setDSeg(e.target.checked)} /> Es de seguridad (no diferible)
              </label>
              <input className="rounded border px-2 py-1 text-sm sm:col-span-2" placeholder="Motivo del diferimiento (decisión de compañía)"
                value={dMot} onChange={(e) => setDMot(e.target.value)} />
              <Button size="sm" variant="outline" className="sm:col-span-2" disabled={diferir.isPending || !dDesc.trim()}
                onClick={agregarDiferido}>
                <PlusCircle className="h-4 w-4 mr-1" /> Registrar pendiente
              </Button>
            </div>
          )}
        </div>

        {/* Cierre */}
        {puedeAuditar && (
          <div className="space-y-3 border-t pt-4">
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="text-sm">Observaciones
                <input value={obs} onChange={(e) => setObs(e.target.value)} className="mt-1 w-full rounded border px-2 py-1" />
              </label>
              <label className="text-sm">Vigencia (días)
                <input type="number" min={1} value={dias} onChange={(e) => setDias(Number(e.target.value))}
                  className="mt-1 w-full rounded border px-2 py-1" />
              </label>
            </div>
            <SignaturePad label="Firma del auditor de calidad" onCapture={setFirma} />
            <input className="w-full rounded border px-2 py-1 text-sm" placeholder="Motivo de rechazo (si rechaza)"
              value={motivo} onChange={(e) => setMotivo(e.target.value)} />

            {err && <div className="flex items-center gap-2 text-sm text-red-600"><AlertTriangle className="h-4 w-4" /> {err}</div>}

            <div className="flex flex-wrap gap-2">
              <Button disabled={saving} onClick={() => enviar('aprobado')}>
                <ShieldCheck className="h-4 w-4 mr-1" /> Aprobar y liberar a operativo
              </Button>
              <Button variant="outline" disabled={saving} onClick={() => enviar('aprobado_con_observaciones')}>
                Aprobar c/observaciones
              </Button>
              <Button variant="danger" disabled={saving} onClick={() => enviar('rechazado')}>
                <XCircle className="h-4 w-4 mr-1" /> Rechazar
              </Button>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  )
}

function Kpi({ label, value, icon: Icon, warn }: { label: string; value: React.ReactNode; icon: any; warn?: boolean }) {
  return (
    <Card>
      <CardContent className="p-3">
        <div className="flex items-center gap-2 text-xs text-muted-foreground"><Icon className="h-4 w-4" /> {label}</div>
        <div className={cn('text-xl font-bold mt-1', warn && 'text-red-600')}>{value}</div>
      </CardContent>
    </Card>
  )
}

function Tg({ active, c, onClick, children }: { active: boolean; c: 'green' | 'red' | 'gray'; onClick: () => void; children: React.ReactNode }) {
  const colors = {
    green: active ? 'bg-green-600 text-white' : 'text-green-600 border-green-300',
    red: active ? 'bg-red-600 text-white' : 'text-red-600 border-red-300',
    gray: active ? 'bg-gray-500 text-white' : 'text-gray-500 border-gray-300',
  }[c]
  return <button type="button" onClick={onClick} className={cn('rounded border p-1.5 transition-colors', colors)}>{children}</button>
}
