'use client'

import { useState } from 'react'
import {
  ShieldAlert, Search, AlertTriangle, CheckCircle2, Clock, Ban,
  FileWarning, ChevronDown, ChevronRight, Save, Pencil,
  Upload, Paperclip, History,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  useControlDocumental, useActualizarExamen,
  useRenovarExamen, useHistorialExamen, abrirRespaldo,
} from '@/hooks/use-prevencion-personal'
import type { PersonaControl, ExamenPersona, EstadoExamen } from '@/lib/services/prevencion-personal'

// ============================================================================
// Control documental de personal — exámenes ocupacionales y licencias
// ----------------------------------------------------------------------------
// Pedido por auditoría. Antes vivía en una planilla Excel y nadie se enteraba
// de un vencimiento hasta que alguien la abría.
// ============================================================================

const ESTADO: Record<EstadoExamen, { label: string, clase: string }> = {
  vencido:       { label: 'Vencido',     clase: 'bg-red-100 text-red-800 border-red-200' },
  sin_dato:      { label: 'Sin dato',    clase: 'bg-red-50 text-red-700 border-red-200' },
  observado:     { label: 'Observado',   clase: 'bg-orange-100 text-orange-800 border-orange-200' },
  por_vencer_30: { label: '≤30 días',    clase: 'bg-amber-100 text-amber-800 border-amber-200' },
  por_vencer_60: { label: '≤60 días',    clase: 'bg-yellow-50 text-yellow-800 border-yellow-200' },
  vigente:       { label: 'Vigente',     clase: 'bg-emerald-50 text-emerald-800 border-emerald-200' },
  no_aplica:     { label: 'No aplica',   clase: 'bg-slate-100 text-slate-600 border-slate-200' },
}

const GENERAL: Record<PersonaControl['estado_general'], { label: string, clase: string, icon: any }> = {
  no_conforme: { label: 'No conforme', clase: 'border-red-300 bg-red-50',       icon: AlertTriangle },
  observado:   { label: 'Observado',   clase: 'border-orange-300 bg-orange-50', icon: FileWarning },
  por_vencer:  { label: 'Por vencer',  clase: 'border-amber-300 bg-amber-50',   icon: Clock },
  conforme:    { label: 'Conforme',    clase: 'bg-card',                        icon: CheckCircle2 },
}

const fmt = (s: string | null) =>
  s ? new Date(s + 'T12:00:00').toLocaleDateString('es-CL',
    { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

function Kpi({ label, value, tone, sub }: {
  label: string, value: number, tone: 'bad' | 'warn' | 'ok' | 'neutral', sub?: string
}) {
  const color = { bad: 'text-red-600', warn: 'text-amber-600', ok: 'text-emerald-600', neutral: '' }[tone]
  return (
    <div className="rounded-lg border bg-card px-3 py-2">
      <div className="text-[11px] uppercase tracking-wide text-muted-foreground">{label}</div>
      <div className={`text-2xl font-bold leading-tight ${color}`}>{value}</div>
      {sub && <div className="text-[11px] text-muted-foreground">{sub}</div>}
    </div>
  )
}

/** Edición inline de un examen. Sin modal: en auditoría se corrigen varios seguidos. */
function FilaExamen({ e, faena }: { e: ExamenPersona, faena: string | null }) {
  const [editando, setEditando] = useState(false)
  const [renovando, setRenovando] = useState(false)
  const [verHistorial, setVerHistorial] = useState(false)
  const [lab, setLab] = useState(e.laboratorio ?? '')
  const [venc, setVenc] = useState(e.fecha_vencimiento ?? '')
  const [obs, setObs] = useState(e.observacion ?? '')
  const [bloq, setBloq] = useState(e.observacion_bloqueante)
  const guardar = useActualizarExamen(faena)

  // ── renovación ──
  const renovar = useRenovarExamen(faena)
  const [nVenc, setNVenc] = useState('')
  const [nEmision, setNEmision] = useState('')
  const [nLab, setNLab] = useState(e.laboratorio ?? '')
  const [nObs, setNObs] = useState('')
  const [archivo, setArchivo] = useState<File | null>(null)

  const historial = useHistorialExamen(verHistorial ? e.id : null)

  const st = ESTADO[e.estado]

  return (
    <div className="rounded-md border bg-card px-2.5 py-1.5">
      <div className="flex flex-wrap items-center gap-2">
        <span className="min-w-[190px] flex-1 text-xs font-medium">{e.tipo_nombre}</span>
        <span className={`rounded border px-1.5 py-0.5 text-[10px] font-semibold ${st.clase}`}>
          {st.label}
        </span>
        <span className="text-xs text-muted-foreground">{e.laboratorio ?? '—'}</span>
        <span className="w-[110px] text-right text-xs font-medium">
          {e.aplica ? fmt(e.fecha_vencimiento) : '—'}
        </span>
        <span className="w-[70px] text-right text-[11px] text-muted-foreground">
          {e.aplica && e.dias_restantes != null
            ? (e.dias_restantes < 0 ? `hace ${-e.dias_restantes} d` : `en ${e.dias_restantes} d`)
            : ''}
        </span>
        <div className="flex items-center gap-1.5">
          {e.archivo_path && (
            <button onClick={() => abrirRespaldo(e.archivo_path!)}
              title={e.archivo_nombre ?? 'Ver respaldo'}
              className="text-[11px] font-medium text-blue-700 underline">
              <Paperclip className="inline h-3 w-3" />
            </button>
          )}
          {(e.versiones_anteriores ?? 0) > 0 && (
            <button onClick={() => setVerHistorial((v) => !v)}
              title={`${e.versiones_anteriores} versión(es) anterior(es)`}
              className="text-[11px] text-muted-foreground underline">
              <History className="inline h-3 w-3" /> {e.versiones_anteriores}
            </button>
          )}
          <Button size="sm" variant="outline" className="h-6 px-2 text-[11px]"
            onClick={() => { setRenovando((v) => !v); setEditando(false) }}>
            <Upload className="mr-1 h-3 w-3" /> Renovar
          </Button>
          <button onClick={() => { setEditando((v) => !v); setRenovando(false) }}
            className="text-[11px] font-medium text-blue-700 underline">
            <Pencil className="inline h-3 w-3" />
          </button>
        </div>
      </div>

      {/* ── Renovar: subir el nuevo examen ── */}
      {renovando && (
        <div className="mt-2 space-y-2 rounded-md border-2 border-emerald-300 bg-emerald-50/60 p-2">
          <div className="text-xs font-semibold text-emerald-900">
            Renovar {e.tipo_nombre}
          </div>
          <p className="text-[11px] text-emerald-800">
            El examen actual pasa al historial, no se borra: hay que poder
            demostrar si estaba vigente en la fecha de un incidente.
          </p>
          <div className="grid gap-2 sm:grid-cols-3">
            <label className="block">
              <span className="text-[10px] uppercase text-muted-foreground">Nuevo vencimiento *</span>
              <Input type="date" value={nVenc} onChange={(ev) => setNVenc(ev.target.value)}
                className="h-8 text-sm" />
            </label>
            <label className="block">
              <span className="text-[10px] uppercase text-muted-foreground">Fecha del examen</span>
              <Input type="date" value={nEmision} onChange={(ev) => setNEmision(ev.target.value)}
                className="h-8 text-sm" />
            </label>
            <label className="block">
              <span className="text-[10px] uppercase text-muted-foreground">Laboratorio</span>
              <Input value={nLab} onChange={(ev) => setNLab(ev.target.value)} className="h-8 text-sm" />
            </label>
          </div>
          <label className="block">
            <span className="text-[10px] uppercase text-muted-foreground">
              Respaldo (PDF o foto) — se guarda en un repositorio privado
            </span>
            <input type="file" accept=".pdf,image/*"
              onChange={(ev) => setArchivo(ev.target.files?.[0] ?? null)}
              className="block w-full text-xs file:mr-2 file:rounded file:border-0
                         file:bg-emerald-600 file:px-2 file:py-1 file:text-white" />
          </label>
          <label className="block">
            <span className="text-[10px] uppercase text-muted-foreground">Observación</span>
            <Input value={nObs} onChange={(ev) => setNObs(ev.target.value)} className="h-8 text-sm" />
          </label>
          <div className="flex items-center justify-between">
            <span className="text-[11px] text-muted-foreground">
              {archivo ? `Adjunto: ${archivo.name}` : 'Sin archivo adjunto'}
            </span>
            <div className="flex gap-2">
              <Button size="sm" variant="outline" onClick={() => setRenovando(false)}>Cancelar</Button>
              <Button size="sm" variant="primary" disabled={!nVenc || renovar.isPending}
                onClick={() => renovar.mutate({
                  examenId: e.id, personalId: e.personal_id, tipoCodigo: e.tipo_codigo,
                  fechaVencimiento: nVenc, fechaEmision: nEmision || null,
                  laboratorio: nLab, observacion: nObs, archivo,
                }, { onSuccess: () => { setRenovando(false); setArchivo(null); setNVenc('') } })}>
                <Upload className="mr-1 h-3.5 w-3.5" />
                {renovar.isPending ? 'Subiendo…' : 'Renovar'}
              </Button>
            </div>
          </div>
          {renovar.error && (
            <div className="rounded bg-red-100 px-2 py-1 text-[11px] text-red-800">
              {renovar.error.message}
            </div>
          )}
        </div>
      )}

      {/* ── Historial de versiones ── */}
      {verHistorial && (
        <div className="mt-2 space-y-1 rounded-md border bg-muted/40 p-2">
          <div className="text-[10px] font-semibold uppercase text-muted-foreground">
            Versiones anteriores
          </div>
          {historial.isLoading && <div className="text-[11px] text-muted-foreground">Cargando…</div>}
          {historial.data?.map((h) => (
            <div key={h.id} className="flex flex-wrap items-center gap-2 text-[11px]">
              <span className="text-muted-foreground">
                {new Date(h.reemplazado_at).toLocaleDateString('es-CL')}
              </span>
              <span>vencía {fmt(h.fecha_vencimiento)}</span>
              <span className="text-muted-foreground">{h.laboratorio ?? '—'}</span>
              {h.archivo_path && (
                <button onClick={() => abrirRespaldo(h.archivo_path!)}
                  className="font-medium text-blue-700 underline">
                  <Paperclip className="inline h-3 w-3" /> ver
                </button>
              )}
            </div>
          ))}
          {historial.data?.length === 0 && (
            <div className="text-[11px] text-muted-foreground">Sin versiones anteriores.</div>
          )}
        </div>
      )}

      {!e.aplica && e.motivo_no_aplica && (
        <div className="mt-1 flex items-start gap-1 text-[11px] text-slate-600">
          <Ban className="mt-0.5 h-3 w-3 shrink-0" />
          Exento: {e.motivo_no_aplica}
        </div>
      )}
      {e.observacion_bloqueante && e.observacion && (
        <div className="mt-1 rounded bg-orange-50 px-1.5 py-1 text-[11px] text-orange-900">
          <b>Invalida el examen aunque la fecha esté vigente:</b> {e.observacion}
        </div>
      )}

      {editando && (
        <div className="mt-2 space-y-2 rounded-md border border-blue-300 bg-blue-50/60 p-2">
          <div className="grid gap-2 sm:grid-cols-2">
            <label className="block">
              <span className="text-[10px] uppercase text-muted-foreground">Laboratorio</span>
              <Input value={lab} onChange={(ev) => setLab(ev.target.value)} className="h-8 text-sm" />
            </label>
            <label className="block">
              <span className="text-[10px] uppercase text-muted-foreground">Vencimiento</span>
              <Input type="date" value={venc ?? ''} onChange={(ev) => setVenc(ev.target.value)}
                className="h-8 text-sm" />
            </label>
          </div>
          <label className="block">
            <span className="text-[10px] uppercase text-muted-foreground">Observación</span>
            <Input value={obs} onChange={(ev) => setObs(ev.target.value)} className="h-8 text-sm" />
          </label>
          <label className="flex items-center gap-2 text-[11px]">
            <input type="checkbox" checked={bloq} onChange={(ev) => setBloq(ev.target.checked)} />
            El mandante no acepta este examen (lo invalida aunque la fecha esté vigente)
          </label>
          <div className="flex justify-end gap-2">
            <Button size="sm" variant="outline" onClick={() => setEditando(false)}>Cancelar</Button>
            <Button size="sm" variant="primary" disabled={guardar.isPending}
              onClick={() => guardar.mutate({
                examenId: e.id, laboratorio: lab, fechaVencimiento: venc,
                observacion: obs, observacionBloqueante: bloq,
              }, { onSuccess: () => setEditando(false) })}>
              <Save className="mr-1 h-3.5 w-3.5" />
              {guardar.isPending ? 'Guardando…' : 'Guardar'}
            </Button>
          </div>
          {guardar.error && (
            <div className="rounded bg-red-100 px-2 py-1 text-[11px] text-red-800">
              {guardar.error.message}
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function FilaPersona({ p, faena }: { p: PersonaControl, faena: string | null }) {
  const [abierto, setAbierto] = useState(p.estado_general === 'no_conforme')
  const g = GENERAL[p.estado_general]
  const Icon = g.icon

  return (
    <div className={`rounded-lg border ${g.clase}`}>
      <button onClick={() => setAbierto((v) => !v)}
        className="flex w-full items-center gap-2 px-3 py-2 text-left">
        {abierto ? <ChevronDown className="h-4 w-4 shrink-0" />
                 : <ChevronRight className="h-4 w-4 shrink-0" />}
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="font-semibold">{p.nombres} {p.apellidos}</span>
            <span className="text-xs text-muted-foreground">{p.rut}</span>
          </div>
          <div className="truncate text-[11px] text-muted-foreground">
            {p.empresa}{p.faena_codigo && <> · {p.faena_codigo}</>}
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-1.5">
          {p.vencidos > 0 && (
            <span className="rounded bg-red-600 px-1.5 py-0.5 text-[10px] font-bold text-white">
              {p.vencidos} vencido{p.vencidos === 1 ? '' : 's'}
            </span>
          )}
          {p.sin_dato > 0 && (
            <span className="rounded bg-red-100 px-1.5 py-0.5 text-[10px] font-semibold text-red-800">
              {p.sin_dato} sin dato
            </span>
          )}
          {p.observados > 0 && (
            <span className="rounded bg-orange-200 px-1.5 py-0.5 text-[10px] font-semibold text-orange-900">
              {p.observados} observado{p.observados === 1 ? '' : 's'}
            </span>
          )}
          {p.por_vencer_30 > 0 && (
            <span className="rounded bg-amber-200 px-1.5 py-0.5 text-[10px] font-semibold text-amber-900">
              {p.por_vencer_30} ≤30d
            </span>
          )}
          <span className="flex items-center gap-1 text-[11px] font-medium">
            <Icon className="h-3.5 w-3.5" /> {g.label}
          </span>
        </div>
      </button>

      {abierto && (
        <div className="space-y-1 border-t px-3 py-2">
          {p.examenes.map((e) => <FilaExamen key={e.id} e={e} faena={faena} />)}
          {p.observacion && (
            <div className="rounded bg-muted px-2 py-1 text-[11px] text-muted-foreground">
              Observación de la planilla: {p.observacion}
            </div>
          )}
        </div>
      )}
    </div>
  )
}

export default function ControlDocumentalPersonalPage() {
  useRequireAuth()
  const [faena, setFaena] = useState<string | null>(null)
  const [q, setQ] = useState('')
  const [soloProblemas, setSoloProblemas] = useState(false)

  const { data, isLoading, error } = useControlDocumental(faena)

  const personas = (data?.personas ?? []).filter((p) => {
    if (soloProblemas && p.estado_general === 'conforme') return false
    if (!q.trim()) return true
    const t = q.trim().toLowerCase()
    return [p.nombres, p.apellidos, p.rut, p.empresa]
      .some((c) => (c ?? '').toLowerCase().includes(t))
  })

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-bold">
          <ShieldAlert className="h-6 w-6 text-amber-500" />
          Control documental de personal
        </h1>
        <p className="text-sm text-muted-foreground">
          Exámenes ocupacionales y licencias, con vencimiento y semáforo.
          Un examen sin registro cuenta como incumplimiento, no como conforme.
        </p>
      </div>

      {isLoading && <div className="flex justify-center py-16"><Spinner /></div>}
      {error && (
        <div className="rounded-lg border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">
          {error.message}
        </div>
      )}

      {data && (
        <>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
            <Kpi label="Personas" value={data.resumen.personas} tone="neutral" />
            <Kpi label="No conformes" value={data.resumen.no_conformes} tone="bad"
              sub="vencidos o sin dato" />
            <Kpi label="Observados" value={data.resumen.observados} tone="warn"
              sub="mandante no acepta" />
            <Kpi label="Por vencer" value={data.resumen.por_vencer} tone="warn" sub="≤30 días" />
            <Kpi label="Conformes" value={data.resumen.conformes} tone="ok" />
            <Kpi label="Exámenes vencidos" value={data.resumen.examenes_vencidos} tone="bad" />
          </div>

          {data.resumen.no_conformes > 0 && (
            <div className="flex items-start gap-2 rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-900">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              <span>
                <b>{data.resumen.no_conformes} persona{data.resumen.no_conformes === 1 ? '' : 's'} no
                puede{data.resumen.no_conformes === 1 ? '' : 'n'} acreditar documentación al día</b> —
                {' '}{data.resumen.examenes_vencidos} exámenes vencidos
                {data.resumen.examenes_sin_dato > 0 && <> y {data.resumen.examenes_sin_dato} sin registro</>}.
                Es lo primero que va a mirar una auditoría.
              </span>
            </div>
          )}

          <div className="flex flex-wrap items-center gap-2">
            <div className="relative min-w-[220px] flex-1">
              <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input value={q} onChange={(e) => setQ(e.target.value)}
                placeholder="Buscar por nombre, RUT o empresa…" className="pl-9" />
            </div>
            <Button size="sm" variant={faena === null ? 'primary' : 'outline'}
              onClick={() => setFaena(null)}>Todas</Button>
            {data.faenas.map((f) => (
              <Button key={f.faena} size="sm"
                variant={faena === f.faena ? 'primary' : 'outline'}
                onClick={() => setFaena(f.faena)}>
                {f.faena} ({f.personas})
              </Button>
            ))}
            <Button size="sm" variant={soloProblemas ? 'primary' : 'outline'}
              onClick={() => setSoloProblemas((v) => !v)}>
              Solo con brechas
            </Button>
          </div>

          <div className="space-y-1.5">
            {personas.map((p) => <FilaPersona key={p.personal_id} p={p} faena={faena} />)}
            {personas.length === 0 && (
              <Card><CardContent className="py-10 text-center text-sm text-muted-foreground">
                Ninguna persona coincide con el filtro.
              </CardContent></Card>
            )}
          </div>

          <p className="text-center text-[11px] text-muted-foreground">
            {personas.length} de {data.personas.length} personas ·
            generado {new Date(data.generado_at).toLocaleString('es-CL')}
          </p>
        </>
      )}
    </div>
  )
}
