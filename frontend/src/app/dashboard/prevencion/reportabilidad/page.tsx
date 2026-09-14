'use client'

// ============================================================================
// Reportabilidad de Prevención por faena (MIG546)
// ----------------------------------------------------------------------------
// El consolidado que antes se armaba pidiéndole los RIT/VAT/VCT a cada
// supervisor por correo. Cuatro pestañas:
//   · Gestión del mes ....... planificado vs real por tipo, abiertos/cerrados
//   · Registros ............. el repositorio con evidencia y cierre
//   · Indicadores ........... dotación/HH/accidentes → IF, IG y tasa (base E-200)
//   · Entregas del mes ...... checklist de reportabilidad por faena (semáforo)
// ============================================================================

import { useMemo, useState } from 'react'
import {
  AlertTriangle, CheckCircle2, ChevronDown, ChevronRight, Download,
  Eye, FileCheck, FileWarning, HardHat, Loader2, Paperclip, Plus,
  Settings2, Sparkles, Undo2, UserX,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { Modal } from '@/components/ui/modal'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/hooks/use-toast'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useAuth } from '@/contexts/auth-context'
import { cn } from '@/lib/utils'
import { RegistroTerrenoForm } from '@/components/prevencion/registro-terreno-form'
import {
  useCerrarRegistro, useConsolidadoMes, useDesmarcarEnvio, useFaenaConfig,
  useFaenasPrevencion, useIndicadoresAnio, useMarcarEnviada, useMonitoreoMes,
  useRegistros, useSupervisoresAsignables, useSupervisoresFaena,
  useToggleSupervisorFaena, useUpsertFaenaConfig, useUpsertIndicadores,
  useUpsertMeta,
} from '@/hooks/use-prevencion-reportabilidad'
import {
  subirEvidencia, urlEvidencia,
  type EvidenciaArchivo, type FaenaConfigDatos, type IndicadoresFila,
  type PrevencionRegistro, type ReportabilidadEstado,
} from '@/lib/services/prevencion-reportabilidad'
import { descargarBlob, generarEntregable } from '@/lib/entregables/prevencion-generar'

const ROLES_CREAR = ['administrador', 'prevencionista', 'supervisor',
  'jefe_operaciones', 'jefe_mantenimiento', 'subgerente_operaciones']
const ROLES_ADMIN = ['administrador', 'prevencionista', 'jefe_operaciones',
  'subgerente_operaciones']

const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
  'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']

function mesActualISO(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
}

// ── Página ───────────────────────────────────────────────────────────────────

export default function ReportabilidadPrevencionPage() {
  useRequireAuth()
  const { perfil } = useAuth()
  const puedeCrear = !!perfil?.rol && ROLES_CREAR.includes(perfil.rol)
  const puedeAdmin = !!perfil?.rol && ROLES_ADMIN.includes(perfil.rol)

  const { data: faenas } = useFaenasPrevencion()
  const [faenaId, setFaenaId] = useState<string | null>(null)
  const [periodo, setPeriodo] = useState(mesActualISO())   // 'YYYY-MM'
  const [tab, setTab] = useState<'gestion' | 'registros' | 'indicadores' | 'entregas' | 'monitoreo'>('gestion')
  const [nuevoOpen, setNuevoOpen] = useState(false)

  const anio = Number(periodo.slice(0, 4))
  const mes = Number(periodo.slice(5, 7))

  // Primera faena con reportabilidad configurada como default.
  const faenaEfectiva = faenaId ?? (faenas?.[0]?.id ?? null)

  const { data: consolidado, isLoading } = useConsolidadoMes(faenaEfectiva, anio, mes)

  const TABS = [
    { id: 'gestion' as const, label: 'Gestión del mes' },
    { id: 'registros' as const, label: 'Registros' },
    { id: 'indicadores' as const, label: 'Indicadores' },
    { id: 'entregas' as const, label: 'Entregas del mes' },
    { id: 'monitoreo' as const, label: 'Monitoreo' },
  ]

  return (
    <div className="space-y-4 p-4 md:p-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold text-gray-900">
            <HardHat className="h-6 w-6 text-pillado-green-500" />
            Reportabilidad de Prevención
          </h1>
          <p className="text-sm text-gray-500">
            RIT · VAT · VCT · charlas · E-200 — cargado por los supervisores, consolidado solo
          </p>
        </div>
        {puedeCrear && (
          <Button onClick={() => setNuevoOpen(true)}>
            <Plus className="mr-2 h-4 w-4" /> Nuevo registro
          </Button>
        )}
      </div>

      <div className="flex flex-wrap gap-3">
        <div className="w-full max-w-xs">
          <Select
            label="Faena"
            value={faenaEfectiva ?? ''}
            onChange={(e) => setFaenaId(e.target.value)}
            options={(faenas ?? []).map((f: any) => ({ value: f.id, label: f.nombre }))}
          />
        </div>
        <div>
          <Input label="Mes" type="month" value={periodo}
                 onChange={(e) => e.target.value && setPeriodo(e.target.value)} />
        </div>
      </div>

      <div className="flex gap-1 overflow-x-auto border-b border-gray-200">
        {TABS.map((t) => (
          <button key={t.id} onClick={() => setTab(t.id)}
                  className={cn(
                    'whitespace-nowrap border-b-2 px-4 py-2 text-sm font-medium transition-colors',
                    tab === t.id
                      ? 'border-pillado-green-500 text-pillado-green-600'
                      : 'border-transparent text-gray-500 hover:text-gray-700',
                  )}>
            {t.label}
          </button>
        ))}
      </div>

      {isLoading && (
        <div className="flex justify-center py-16"><Spinner className="h-8 w-8" /></div>
      )}

      {!isLoading && faenaEfectiva && (
        <>
          {tab === 'gestion' && (
            <TabGestion consolidado={consolidado} faenaId={faenaEfectiva}
                        anio={anio} mes={mes} puedeAdmin={puedeAdmin} />
          )}
          {tab === 'registros' && (
            <TabRegistros faenaId={faenaEfectiva} anio={anio} mes={mes}
                          puedeAdmin={puedeAdmin} faenas={faenas ?? []} />
          )}
          {tab === 'indicadores' && (
            <TabIndicadores faenaId={faenaEfectiva} anio={anio} mes={mes}
                            puedeAdmin={puedeAdmin} />
          )}
          {tab === 'entregas' && (
            <TabEntregas consolidado={consolidado} faenaId={faenaEfectiva}
                         anio={anio} mes={mes} puedeAdmin={puedeAdmin}
                         faenaNombre={(faenas ?? []).find((f: any) => f.id === faenaEfectiva)?.nombre ?? ''} />
          )}
          {tab === 'monitoreo' && (
            <TabMonitoreo consolidado={consolidado} faenaId={faenaEfectiva}
                          anio={anio} mes={mes} puedeAdmin={puedeAdmin} />
          )}
        </>
      )}

      <Modal open={nuevoOpen} onClose={() => setNuevoOpen(false)}
             title="Nuevo registro de terreno" className="max-w-lg">
        <RegistroTerrenoForm
          faenaIdInicial={faenaEfectiva}
          onGuardado={() => setNuevoOpen(false)}
          onCancelar={() => setNuevoOpen(false)}
        />
      </Modal>
    </div>
  )
}

// ── Tab 1: Gestión del mes ───────────────────────────────────────────────────

function TabGestion({ consolidado, faenaId, anio, mes, puedeAdmin }: {
  consolidado: any
  faenaId: string
  anio: number
  mes: number
  puedeAdmin: boolean
}) {
  const upsertMeta = useUpsertMeta()
  const toast = useToast()
  const gestion = consolidado?.gestion ?? []
  const arrastre = consolidado?.abiertos_arrastre ?? []

  const guardarMeta = async (tipo: string, valor: string) => {
    const meta = Number(valor)
    if (!Number.isFinite(meta) || meta < 0) return
    try {
      await upsertMeta.mutateAsync({ faena_id: faenaId, anio, mes, tipo_codigo: tipo, meta })
      toast.success('Meta guardada')
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo guardar la meta')
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="text-base">
            Planificado vs real — {MESES[mes - 1]} {anio}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {gestion.length === 0 ? (
            <p className="py-6 text-center text-sm text-gray-500">
              Sin metas ni registros este mes. Las metas las define prevención
              {puedeAdmin ? ' (editables aquí mismo cuando exista al menos un registro o desde el primer registro del tipo)' : ''}.
            </p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-left text-xs uppercase text-gray-500">
                    <th className="py-2 pr-3">Actividad</th>
                    <th className="py-2 pr-3 text-right">Planificado</th>
                    <th className="py-2 pr-3 text-right">Real</th>
                    <th className="py-2 pr-3 text-right">% Cumpl.</th>
                    <th className="py-2 pr-3 text-right">Abiertos</th>
                    <th className="py-2 text-right">Cerrados</th>
                  </tr>
                </thead>
                <tbody>
                  {gestion.map((g: any) => (
                    <tr key={g.tipo_codigo} className="border-b last:border-0">
                      <td className="py-2 pr-3 font-medium text-gray-900">{g.tipo_nombre}</td>
                      <td className="py-2 pr-3 text-right">
                        {puedeAdmin ? (
                          <input
                            type="number" min={0} defaultValue={g.meta}
                            className="w-20 rounded border border-gray-300 px-2 py-1 text-right text-sm"
                            onBlur={(e) => {
                              if (Number(e.target.value) !== g.meta) guardarMeta(g.tipo_codigo, e.target.value)
                            }}
                          />
                        ) : g.meta}
                      </td>
                      <td className="py-2 pr-3 text-right font-semibold">{g.realizados}</td>
                      <td className="py-2 pr-3 text-right">
                        {g.pct_cumplimiento === null ? (
                          <span className="text-gray-400">—</span>
                        ) : (
                          <span className={cn(
                            'rounded-full px-2 py-0.5 text-xs font-bold',
                            g.pct_cumplimiento >= 100 ? 'bg-green-100 text-green-700'
                              : g.pct_cumplimiento >= 80 ? 'bg-amber-100 text-amber-700'
                              : 'bg-red-100 text-red-700',
                          )}>
                            {g.pct_cumplimiento}%
                          </span>
                        )}
                      </td>
                      <td className="py-2 pr-3 text-right">
                        {g.requiere_cierre ? (
                          <span className={cn(g.abiertos > 0 && 'font-bold text-amber-600')}>
                            {g.abiertos}
                          </span>
                        ) : <span className="text-gray-300">—</span>}
                      </td>
                      <td className="py-2 text-right">
                        {g.requiere_cierre ? g.cerrados : <span className="text-gray-300">—</span>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      {arrastre.length > 0 && (
        <Card className="border-amber-200">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base text-amber-700">
              <AlertTriangle className="h-4 w-4" />
              Abiertos de meses anteriores ({arrastre.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <ul className="space-y-1 text-sm">
              {arrastre.map((r: any) => (
                <li key={r.id} className="flex flex-wrap items-center gap-2">
                  <span className="rounded bg-gray-100 px-1.5 py-0.5 text-xs font-bold">{r.tipo_codigo}</span>
                  <span className="font-medium">{r.titulo}</span>
                  <span className="text-xs text-gray-500">
                    {r.fecha_actividad} · {r.supervisor ?? 'sin responsable'}
                  </span>
                </li>
              ))}
            </ul>
            <p className="mt-2 text-xs text-gray-500">
              Se cierran desde la pestaña Registros (cambiando el mes al de la actividad).
            </p>
          </CardContent>
        </Card>
      )}
    </div>
  )
}

// ── Tab 2: Registros ─────────────────────────────────────────────────────────

function TabRegistros({ faenaId, anio, mes, puedeAdmin, faenas }: {
  faenaId: string
  anio: number
  mes: number
  puedeAdmin: boolean
  faenas: any[]
}) {
  const { perfil } = useAuth()
  const toast = useToast()
  const [filtroTipo, setFiltroTipo] = useState('')
  const [filtroEstado, setFiltroEstado] = useState('')
  const { data: registros, isLoading } = useRegistros({
    faenaId, anio, mes,
    tipoCodigo: filtroTipo || undefined,
    estado: (filtroEstado || undefined) as any,
  })
  const cerrar = useCerrarRegistro()
  const [cerrandoId, setCerrandoId] = useState<string | null>(null)
  const [obsCierre, setObsCierre] = useState('')
  const [abiertoId, setAbiertoId] = useState<string | null>(null)

  const exportarCSV = () => {
    const filas = registros ?? []
    if (!filas.length) return toast.error('No hay registros para exportar')
    const faenaNombre = faenas.find((f) => f.id === faenaId)?.nombre ?? faenaId
    const esc = (v: any) => `"${String(v ?? '').replace(/"/g, '""')}"`
    const csv = [
      ['Faena', 'Tipo', 'Fecha', 'Título', 'Descripción', 'Área', 'Estado',
       'Fecha cierre', 'Supervisor', 'Evidencias'].join(';'),
      ...filas.map((r) => [
        esc(faenaNombre), esc(r.tipo_codigo), esc(r.fecha_actividad), esc(r.titulo),
        esc(r.descripcion), esc(r.area_sector), esc(r.estado),
        esc(r.fecha_cierre?.slice(0, 10)), esc(r.supervisor_nombre),
        esc((r.evidencias ?? []).length),
      ].join(';')),
    ].join('\n')
    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = `prevencion_${anio}-${String(mes).padStart(2, '0')}.csv`
    a.click()
    URL.revokeObjectURL(a.href)
  }

  const confirmarCierre = async () => {
    if (!cerrandoId) return
    try {
      await cerrar.mutateAsync({ id: cerrandoId, observacion: obsCierre.trim() || undefined })
      toast.success('Registro cerrado')
      setCerrandoId(null); setObsCierre('')
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo cerrar (¿es suyo o tiene permiso?)')
    }
  }

  const verEvidencia = async (ev: EvidenciaArchivo) => {
    const url = await urlEvidencia(ev.path)
    if (url) window.open(url, '_blank')
    else toast.error('No se pudo abrir la evidencia')
  }

  return (
    <Card>
      <CardHeader className="flex flex-row flex-wrap items-center justify-between gap-2">
        <CardTitle className="text-base">
          Registros — {MESES[mes - 1]} {anio} ({registros?.length ?? 0})
        </CardTitle>
        <div className="flex flex-wrap items-center gap-2">
          <select className="rounded-lg border border-gray-300 px-2 py-1.5 text-sm"
                  value={filtroTipo} onChange={(e) => setFiltroTipo(e.target.value)}>
            <option value="">Todos los tipos</option>
            {['RIT', 'VAT', 'VCT', 'CHARLA', 'CAPACITACION', 'INSPECCION', 'OBSERVACION',
              'SIMULACRO', 'CAMPANA', 'HS_SAFEWORK', 'GCOM'].map((t) => (
              <option key={t} value={t}>{t}</option>
            ))}
          </select>
          <select className="rounded-lg border border-gray-300 px-2 py-1.5 text-sm"
                  value={filtroEstado} onChange={(e) => setFiltroEstado(e.target.value)}>
            <option value="">Todos</option>
            <option value="abierto">Abiertos</option>
            <option value="cerrado">Cerrados</option>
          </select>
          <Button size="sm" variant="outline" onClick={exportarCSV}>
            <Download className="mr-1 h-4 w-4" /> CSV
          </Button>
        </div>
      </CardHeader>
      <CardContent>
        {isLoading ? (
          <div className="flex justify-center py-10"><Spinner className="h-6 w-6" /></div>
        ) : !registros?.length ? (
          <p className="py-8 text-center text-sm text-gray-500">
            Nadie ha cargado registros este mes. El supervisor los carga desde su
            teléfono en <b>/m/prevencion</b> o con el botón «Nuevo registro».
          </p>
        ) : (
          <ul className="divide-y">
            {registros.map((r) => {
              const abierto = abiertoId === r.id
              const puedeCerrar = r.estado === 'abierto' &&
                (puedeAdmin || r.creado_por === perfil?.id)
              return (
                <li key={r.id} className="py-2">
                  <button className="flex w-full items-center gap-2 text-left"
                          onClick={() => setAbiertoId(abierto ? null : r.id)}>
                    {abierto ? <ChevronDown className="h-4 w-4 shrink-0 text-gray-400" />
                             : <ChevronRight className="h-4 w-4 shrink-0 text-gray-400" />}
                    <span className="w-24 shrink-0 text-xs text-gray-500">{r.fecha_actividad}</span>
                    <span className="w-24 shrink-0 rounded bg-gray-100 px-1.5 py-0.5 text-center text-xs font-bold">
                      {r.tipo_codigo}
                    </span>
                    <span className="min-w-0 flex-1 truncate text-sm font-medium text-gray-900">
                      {r.titulo}
                    </span>
                    {(r.evidencias?.length ?? 0) > 0 && (
                      <span className="flex items-center gap-0.5 text-xs text-gray-400">
                        <Paperclip className="h-3 w-3" />{r.evidencias.length}
                      </span>
                    )}
                    <span className={cn(
                      'shrink-0 rounded-full px-2 py-0.5 text-xs font-bold',
                      r.estado === 'abierto' ? 'bg-amber-100 text-amber-700' : 'bg-green-100 text-green-700',
                    )}>
                      {r.estado}
                    </span>
                  </button>

                  {abierto && (
                    <div className="ml-6 mt-2 space-y-2 rounded-lg bg-gray-50 p-3 text-sm">
                      <p className="text-xs text-gray-500">
                        Responsable: <b>{r.supervisor_nombre ?? '—'}</b>
                        {r.area_sector && <> · Área: <b>{r.area_sector}</b></>}
                        {r.duracion_minutos && <> · {r.duracion_minutos} min</>}
                        {r.asistentes != null && r.asistentes > 0 && <> · {r.asistentes} asistentes</>}
                      </p>
                      {r.descripcion && <p className="whitespace-pre-wrap">{r.descripcion}</p>}
                      {r.estado === 'cerrado' && r.cierre_observacion && (
                        <p className="text-xs text-gray-600">
                          <b>Cierre:</b> {r.cierre_observacion}
                        </p>
                      )}
                      {(r.evidencias ?? []).map((ev, i) => (
                        <button key={i} onClick={() => verEvidencia(ev)}
                                className="mr-2 inline-flex items-center gap-1 text-xs text-blue-600 underline">
                          <Paperclip className="h-3 w-3" /> {ev.nombre}
                        </button>
                      ))}
                      {puedeCerrar && (
                        <div>
                          <Button size="sm" variant="outline" onClick={() => setCerrandoId(r.id)}>
                            <CheckCircle2 className="mr-1 h-4 w-4" /> Cerrar registro
                          </Button>
                        </div>
                      )}
                    </div>
                  )}
                </li>
              )
            })}
          </ul>
        )}
      </CardContent>

      <Modal open={!!cerrandoId} onClose={() => setCerrandoId(null)}
             title="Cerrar registro" className="max-w-md">
        <div className="space-y-3">
          <label className="block text-sm font-medium text-gray-700">
            Observación de cierre (qué se hizo con el hallazgo)
          </label>
          <textarea
            className="min-h-[80px] w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
            value={obsCierre} onChange={(e) => setObsCierre(e.target.value)} />
          <div className="flex gap-2">
            <Button className="flex-1" onClick={confirmarCierre} disabled={cerrar.isPending}>
              {cerrar.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Cerrar registro
            </Button>
            <Button variant="outline" onClick={() => setCerrandoId(null)}>Cancelar</Button>
          </div>
        </div>
      </Modal>
    </Card>
  )
}

// ── Tab 3: Indicadores ───────────────────────────────────────────────────────

const CAMPOS_IND: Array<{ key: keyof IndicadoresFila; label: string }> = [
  { key: 'dotacion_hombres', label: 'Dotación hombres' },
  { key: 'dotacion_mujeres', label: 'Dotación mujeres' },
  { key: 'hh_hombres', label: 'HH hombres' },
  { key: 'hh_mujeres', label: 'HH mujeres' },
  { key: 'accidentes_ctp', label: 'Accidentes CTP' },
  { key: 'accidentes_stp', label: 'Accidentes STP' },
  { key: 'dias_perdidos', label: 'Días perdidos' },
  { key: 'accidentes_trayecto', label: 'Acc. de trayecto' },
  { key: 'enfermedades_prof', label: 'Enf. profesionales' },
  { key: 'incidentes_alto_potencial', label: 'Alto potencial' },
]

function TabIndicadores({ faenaId, anio, mes, puedeAdmin }: {
  faenaId: string
  anio: number
  mes: number
  puedeAdmin: boolean
}) {
  const toast = useToast()
  const { data: filas, isLoading } = useIndicadoresAnio(faenaId, anio)
  const upsert = useUpsertIndicadores()
  const [editando, setEditando] = useState(false)
  const [form, setForm] = useState<Record<string, string>>({})

  const filaMes = useMemo(
    () => (filas ?? []).find((f) => f.mes === mes) ?? null,
    [filas, mes],
  )

  const abrirEdicion = () => {
    const base: Record<string, string> = {}
    for (const c of CAMPOS_IND) base[c.key as string] = String(filaMes?.[c.key] ?? 0)
    base.observaciones = String(filaMes?.observaciones ?? '')
    setForm(base)
    setEditando(true)
  }

  const guardar = async () => {
    try {
      await upsert.mutateAsync({
        faena_id: faenaId, anio, mes,
        dotacion_hombres: Number(form.dotacion_hombres) || 0,
        dotacion_mujeres: Number(form.dotacion_mujeres) || 0,
        hh_hombres: Number(form.hh_hombres) || 0,
        hh_mujeres: Number(form.hh_mujeres) || 0,
        accidentes_ctp: Number(form.accidentes_ctp) || 0,
        accidentes_stp: Number(form.accidentes_stp) || 0,
        dias_perdidos: Number(form.dias_perdidos) || 0,
        accidentes_trayecto: Number(form.accidentes_trayecto) || 0,
        enfermedades_prof: Number(form.enfermedades_prof) || 0,
        incidentes_alto_potencial: Number(form.incidentes_alto_potencial) || 0,
        observaciones: form.observaciones?.trim() || null,
      })
      toast.success('Indicadores guardados')
      setEditando(false)
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo guardar')
    }
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle className="text-base">
            {MESES[mes - 1]} {anio} — dotación, HH y accidentes (base E-200)
          </CardTitle>
          {puedeAdmin && !editando && (
            <Button size="sm" onClick={abrirEdicion}>
              {filaMes ? 'Editar mes' : 'Cargar mes'}
            </Button>
          )}
        </CardHeader>
        <CardContent>
          {editando ? (
            <div className="space-y-3">
              <div className="grid grid-cols-2 gap-3 md:grid-cols-5">
                {CAMPOS_IND.map((c) => (
                  <Input key={c.key as string} label={c.label} type="number" min={0}
                         value={form[c.key as string] ?? '0'}
                         onChange={(e) => setForm((p) => ({ ...p, [c.key as string]: e.target.value }))} />
                ))}
              </div>
              <Input label="Observaciones" value={form.observaciones ?? ''}
                     onChange={(e) => setForm((p) => ({ ...p, observaciones: e.target.value }))} />
              <div className="flex gap-2">
                <Button onClick={guardar} disabled={upsert.isPending}>
                  {upsert.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                  Guardar
                </Button>
                <Button variant="outline" onClick={() => setEditando(false)}>Cancelar</Button>
              </div>
              <p className="text-xs text-gray-500">
                Los índices no se digitan: IF = CTP × 1.000.000 / HH · IG = días perdidos ×
                1.000.000 / HH · Tasa = CTP × 100 / dotación (Ley 16.744 / SERNAGEOMIN).
              </p>
            </div>
          ) : !filaMes ? (
            <p className="py-6 text-center text-sm text-gray-500">
              Este mes aún no tiene datos. {puedeAdmin ? 'Use «Cargar mes».' : 'Los carga prevención.'}
            </p>
          ) : (
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
              <Kpi label="Dotación" value={filaMes.dotacion_total ?? 0} />
              <Kpi label="HH del mes" value={filaMes.hh_total ?? 0} />
              <Kpi label="Accidentes CTP" value={filaMes.accidentes_ctp}
                   rojo={filaMes.accidentes_ctp > 0} />
              <Kpi label="Días perdidos" value={filaMes.dias_perdidos}
                   rojo={filaMes.dias_perdidos > 0} />
              <Kpi label="IF mes / acum." value={`${filaMes.indice_frecuencia ?? 0} / ${filaMes.acum_indice_frecuencia ?? 0}`} />
              <Kpi label="IG mes / acum." value={`${filaMes.indice_gravedad ?? 0} / ${filaMes.acum_indice_gravedad ?? 0}`} />
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle className="text-base">Año {anio} completo</CardTitle></CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="flex justify-center py-8"><Spinner className="h-6 w-6" /></div>
          ) : !filas?.length ? (
            <p className="py-6 text-center text-sm text-gray-500">Sin meses cargados en {anio}.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-left text-xs uppercase text-gray-500">
                    <th className="py-2 pr-3">Mes</th>
                    <th className="py-2 pr-3 text-right">Dotación</th>
                    <th className="py-2 pr-3 text-right">HH</th>
                    <th className="py-2 pr-3 text-right">CTP</th>
                    <th className="py-2 pr-3 text-right">STP</th>
                    <th className="py-2 pr-3 text-right">Días perd.</th>
                    <th className="py-2 pr-3 text-right">IF</th>
                    <th className="py-2 pr-3 text-right">IG</th>
                    <th className="py-2 pr-3 text-right">IF acum.</th>
                    <th className="py-2 text-right">IG acum.</th>
                  </tr>
                </thead>
                <tbody>
                  {filas.map((f) => (
                    <tr key={f.mes} className={cn('border-b last:border-0', f.mes === mes && 'bg-green-50')}>
                      <td className="py-1.5 pr-3 font-medium">{MESES[f.mes - 1]}</td>
                      <td className="py-1.5 pr-3 text-right">{f.dotacion_total}</td>
                      <td className="py-1.5 pr-3 text-right">{f.hh_total}</td>
                      <td className={cn('py-1.5 pr-3 text-right', f.accidentes_ctp > 0 && 'font-bold text-red-600')}>{f.accidentes_ctp}</td>
                      <td className="py-1.5 pr-3 text-right">{f.accidentes_stp}</td>
                      <td className="py-1.5 pr-3 text-right">{f.dias_perdidos}</td>
                      <td className="py-1.5 pr-3 text-right">{f.indice_frecuencia}</td>
                      <td className="py-1.5 pr-3 text-right">{f.indice_gravedad}</td>
                      <td className="py-1.5 pr-3 text-right">{f.acum_indice_frecuencia}</td>
                      <td className="py-1.5 text-right">{f.acum_indice_gravedad}</td>
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

function Kpi({ label, value, rojo }: { label: string; value: number | string; rojo?: boolean }) {
  return (
    <div className={cn('rounded-lg border p-3', rojo ? 'border-red-200 bg-red-50' : 'border-gray-200 bg-gray-50')}>
      <p className="text-xs text-gray-500">{label}</p>
      <p className={cn('text-xl font-bold', rojo ? 'text-red-700' : 'text-gray-900')}>{value}</p>
    </div>
  )
}

// ── Tab 4: Entregas del mes (checklist de reportabilidad) ────────────────────

function TabEntregas({ consolidado, faenaId, anio, mes, puedeAdmin, faenaNombre }: {
  consolidado: any
  faenaId: string
  anio: number
  mes: number
  puedeAdmin: boolean
  faenaNombre: string
}) {
  const toast = useToast()
  const marcar = useMarcarEnviada()
  const desmarcar = useDesmarcarEnvio()
  const items: ReportabilidadEstado[] = consolidado?.reportabilidad ?? []
  const [marcandoItem, setMarcandoItem] = useState<ReportabilidadEstado | null>(null)
  const [obs, setObs] = useState('')
  const [archivos, setArchivos] = useState<File[]>([])
  const [subiendo, setSubiendo] = useState(false)
  const [generando, setGenerando] = useState<string | null>(null)   // item_id
  const [progresoGen, setProgresoGen] = useState('')

  // El botón que pidió Manuel: «quisiera que todo saliera automático».
  // Junta lo cargado por supervisores + indicadores + config y produce el
  // archivo en el formato que pide ese mandante. Se descarga para revisar;
  // luego se adjunta al marcar la entrega.
  const generar = async (it: ReportabilidadEstado) => {
    if (!it.plantilla) return
    setGenerando(it.item_id)
    setProgresoGen('Preparando…')
    try {
      const { blob, filename } = await generarEntregable({
        plantilla: it.plantilla,
        itemNombre: it.nombre,
        faenaId, faenaNombre, anio, mes,
        onProgreso: setProgresoGen,
      })
      descargarBlob(blob, filename)
      toast.success(`${filename} generado — revíselo y márquelo enviado adjuntándolo`)
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo generar el entregable')
    } finally {
      setGenerando(null)
      setProgresoGen('')
    }
  }

  // Plazo: día N del MES SIGUIENTE al informado (el E-200 de agosto se declara
  // dentro de los primeros días de septiembre).
  const vencido = (it: ReportabilidadEstado) => {
    if (it.enviado || !it.dia_limite) return false
    const limite = new Date(anio, mes, it.dia_limite) // mes es 1-based → mes siguiente
    return new Date() > limite
  }

  const confirmar = async () => {
    if (!marcandoItem) return
    setSubiendo(true)
    try {
      const evidencias: EvidenciaArchivo[] = []
      for (const f of archivos) {
        const { data, error } = await subirEvidencia(f, {
          faenaId, anio, mes, carpeta: 'reportabilidad',
        })
        if (error || !data) throw error ?? new Error('No se pudo subir el respaldo')
        evidencias.push(data)
      }
      await marcar.mutateAsync({
        item_id: marcandoItem.item_id, anio, mes,
        observacion: obs.trim() || null, archivos: evidencias,
      })
      toast.success('Entrega registrada')
      setMarcandoItem(null); setObs(''); setArchivos([])
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo registrar la entrega')
    } finally {
      setSubiendo(false)
    }
  }

  const verArchivo = async (ev: EvidenciaArchivo) => {
    const url = await urlEvidencia(ev.path)
    if (url) window.open(url, '_blank')
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">
          Reportabilidad de {MESES[mes - 1]} {anio} — qué se entrega y qué falta
        </CardTitle>
      </CardHeader>
      <CardContent>
        {items.length === 0 ? (
          <p className="py-8 text-center text-sm text-gray-500">
            Esta faena no tiene reportabilidad configurada. La define prevención
            (tabla prevencion_reportabilidad_items).
          </p>
        ) : (
          <ul className="space-y-2">
            {items.map((it) => (
              <li key={it.item_id}
                  className={cn(
                    'rounded-lg border p-3',
                    it.enviado ? 'border-green-200 bg-green-50'
                      : vencido(it) ? 'border-red-200 bg-red-50'
                      : 'border-gray-200 bg-white',
                  )}>
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="flex items-center gap-2">
                    {it.enviado
                      ? <FileCheck className="h-5 w-5 shrink-0 text-green-600" />
                      : <FileWarning className={cn('h-5 w-5 shrink-0', vencido(it) ? 'text-red-500' : 'text-amber-500')} />}
                    <div>
                      <p className="text-sm font-semibold text-gray-900">{it.nombre}</p>
                      <p className="text-xs text-gray-500">
                        {it.destino && <>Destino: {it.destino} · </>}
                        {it.dia_limite
                          ? <>plazo: día {it.dia_limite} del mes siguiente</>
                          : 'sin plazo definido'}
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    {it.plantilla && (
                      <Button size="sm" variant="outline"
                              disabled={generando !== null}
                              onClick={() => generar(it)}>
                        {generando === it.item_id
                          ? <Loader2 className="mr-1 h-4 w-4 animate-spin" />
                          : <Sparkles className="mr-1 h-4 w-4" />}
                        {generando === it.item_id ? (progresoGen || 'Generando…') : 'Generar'}
                      </Button>
                    )}
                    {it.enviado ? (
                      <>
                        <span className="text-xs font-medium text-green-700">
                          Enviada el {it.fecha_envio}
                        </span>
                        {puedeAdmin && (
                          <Button size="sm" variant="ghost"
                                  onClick={async () => {
                                    try {
                                      await desmarcar.mutateAsync({ itemId: it.item_id, anio, mes })
                                      toast.success('Entrega deshecha')
                                    } catch (e: any) { toast.error(e?.message ?? 'No se pudo') }
                                  }}>
                            <Undo2 className="h-4 w-4" />
                          </Button>
                        )}
                      </>
                    ) : puedeAdmin ? (
                      <Button size="sm" onClick={() => setMarcandoItem(it)}>
                        Marcar enviada
                      </Button>
                    ) : (
                      <span className="text-xs text-gray-400">pendiente</span>
                    )}
                  </div>
                </div>
                {it.enviado && (
                  <div className="mt-1 pl-7">
                    {it.observacion && <p className="text-xs text-gray-600">{it.observacion}</p>}
                    {(it.archivos ?? []).map((a, i) => (
                      <button key={i} onClick={() => verArchivo(a)}
                              className="mr-3 inline-flex items-center gap-1 text-xs text-blue-600 underline">
                        <Paperclip className="h-3 w-3" /> {a.nombre}
                      </button>
                    ))}
                  </div>
                )}
              </li>
            ))}
          </ul>
        )}
      </CardContent>

      <Modal open={!!marcandoItem} onClose={() => setMarcandoItem(null)}
             title={`Registrar entrega — ${marcandoItem?.nombre ?? ''}`} className="max-w-md">
        <div className="space-y-3">
          <div>
            <label className="mb-1.5 block text-sm font-medium text-gray-700">
              Respaldo (el archivo enviado, comprobante o pantallazo)
            </label>
            <input type="file" multiple accept="image/*,.pdf,.xlsx,.xls,.docx"
                   onChange={(e) => setArchivos(Array.from(e.target.files ?? []))}
                   className="block w-full text-sm" />
          </div>
          <Input label="Observación" value={obs} onChange={(e) => setObs(e.target.value)}
                 placeholder="Ej: cargado en SIMIN, folio…" />
          <div className="flex gap-2">
            <Button className="flex-1" onClick={confirmar} disabled={subiendo}>
              {subiendo && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
              Registrar entrega
            </Button>
            <Button variant="outline" onClick={() => setMarcandoItem(null)}>Cancelar</Button>
          </div>
        </div>
      </Modal>
    </Card>
  )
}

// ── Tab 5: Monitoreo (lo que pidió Manuel: el prevencionista viendo quién
//    cargó, quién no, y cuánto falta para cerrar el mes) ─────────────────────

function TabMonitoreo({ consolidado, faenaId, anio, mes, puedeAdmin }: {
  consolidado: any
  faenaId: string
  anio: number
  mes: number
  puedeAdmin: boolean
}) {
  const { data: monitoreo, isLoading } = useMonitoreoMes(faenaId, anio, mes)
  const { data: esperados } = useSupervisoresFaena(faenaId)
  const [configOpen, setConfigOpen] = useState(false)
  const [asignarOpen, setAsignarOpen] = useState(false)

  const filas = monitoreo ?? []
  const cargaron = new Set(filas.map((m) => m.creado_por))
  const sinCargar = (esperados ?? []).filter((s) => !cargaron.has(s.usuario_id))
  const totalRegistros = filas.reduce((a, m) => a + m.total, 0)
  const entregas: ReportabilidadEstado[] = consolidado?.reportabilidad ?? []
  const entregasHechas = entregas.filter((e) => e.enviado).length
  const indicadoresOk = !!consolidado?.indicadores
  const metasDefinidas = (consolidado?.gestion ?? []).filter((g: any) => g.meta > 0).length

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Kpi label="Registros del mes" value={totalRegistros} />
        <Kpi label="Supervisores con carga"
             value={`${cargaron.size}${esperados?.length ? ` / ${esperados.length}` : ''}`}
             rojo={!!esperados?.length && cargaron.size < esperados.length} />
        <Kpi label="Indicadores del mes" value={indicadoresOk ? 'Cargados' : 'Faltan'}
             rojo={!indicadoresOk} />
        <Kpi label="Entregas al mandante"
             value={`${entregasHechas} / ${entregas.length}`}
             rojo={entregas.length > 0 && entregasHechas < entregas.length} />
      </div>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle className="text-base">
            Carga por supervisor — {MESES[mes - 1]} {anio}
          </CardTitle>
          {puedeAdmin && (
            <div className="flex gap-2">
              {/* [MIG548] Los rotativos de Calama cubren Lomas y Centinela:
                  acá se define a quién se le cobra la carga de ESTA faena. */}
              <Button size="sm" variant="outline" onClick={() => setAsignarOpen(true)}>
                <UserX className="mr-1 h-4 w-4" /> Asignar supervisores
              </Button>
              <Button size="sm" variant="outline" onClick={() => setConfigOpen(true)}>
                <Settings2 className="mr-1 h-4 w-4" /> Datos de la faena
              </Button>
            </div>
          )}
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="flex justify-center py-8"><Spinner className="h-6 w-6" /></div>
          ) : (
            <>
              {filas.length === 0 && (
                <p className="py-4 text-center text-sm text-gray-500">
                  Nadie ha cargado registros este mes en esta faena.
                </p>
              )}
              {filas.length > 0 && (
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b text-left text-xs uppercase text-gray-500">
                        <th className="py-2 pr-3">Supervisor</th>
                        <th className="py-2 pr-3 text-right">Total</th>
                        <th className="py-2 pr-3">Por tipo</th>
                        <th className="py-2 pr-3 text-right">Abiertos</th>
                        <th className="py-2 text-right">Última carga</th>
                      </tr>
                    </thead>
                    <tbody>
                      {filas.map((m) => (
                        <tr key={m.creado_por} className="border-b last:border-0">
                          <td className="py-2 pr-3 font-medium text-gray-900">
                            {m.supervisor}
                            {m.rol && m.rol !== 'supervisor' && (
                              <span className="ml-1 text-xs text-gray-400">({m.rol})</span>
                            )}
                          </td>
                          <td className="py-2 pr-3 text-right font-bold">{m.total}</td>
                          <td className="py-2 pr-3">
                            <div className="flex flex-wrap gap-1">
                              {Object.entries(m.por_tipo ?? {}).map(([t, n]) => (
                                <span key={t} className="rounded bg-gray-100 px-1.5 py-0.5 text-xs">
                                  {t}: <b>{n as number}</b>
                                </span>
                              ))}
                            </div>
                          </td>
                          <td className={cn('py-2 pr-3 text-right', m.abiertos > 0 && 'font-bold text-amber-600')}>
                            {m.abiertos}
                          </td>
                          <td className="py-2 text-right text-xs text-gray-500">
                            {new Date(m.ultima_carga).toLocaleDateString('es-CL')}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}

              {sinCargar.length > 0 && (
                <div className="mt-4 rounded-lg border border-red-200 bg-red-50 p-3">
                  <p className="mb-1 flex items-center gap-1.5 text-sm font-bold text-red-700">
                    <UserX className="h-4 w-4" />
                    Sin cargas este mes ({sinCargar.length})
                  </p>
                  <ul className="text-sm text-red-800">
                    {sinCargar.map((s) => (
                      <li key={s.usuario_id}>
                        {s.nombre} <span className="text-xs text-red-500">· {s.email}</span>
                      </li>
                    ))}
                  </ul>
                  <p className="mt-1 text-xs text-red-600">
                    Cargan desde el teléfono en /m/prevencion — sin su carga el consolidado sale corto.
                  </p>
                </div>
              )}
            </>
          )}
        </CardContent>
      </Card>

      <ConfigFaenaModal open={configOpen} onClose={() => setConfigOpen(false)} faenaId={faenaId} />
      <AsignarSupervisoresModal open={asignarOpen} onClose={() => setAsignarOpen(false)} faenaId={faenaId} />
    </div>
  )
}

// ── Asignar supervisores a la faena (MIG548: los rotativos de Calama) ────────

function AsignarSupervisoresModal({ open, onClose, faenaId }: {
  open: boolean
  onClose: () => void
  faenaId: string
}) {
  const toast = useToast()
  const { data: candidatos, isLoading } = useSupervisoresAsignables(faenaId, open)
  const toggle = useToggleSupervisorFaena()

  return (
    <Modal open={open} onClose={onClose}
           title="Quién debe reportar en esta faena" className="max-w-lg">
      <p className="mb-3 text-xs text-gray-500">
        Marcar a alguien lo agrega a los «esperados» del monitoreo (se le cobra
        la carga del mes). Un supervisor rotativo puede estar en varias faenas
        a la vez — los de Calama cubren Lomas Bayas y Centinela. Esto NO
        restringe dónde puede cargar registros.
      </p>
      {isLoading ? (
        <div className="flex justify-center py-8"><Spinner className="h-6 w-6" /></div>
      ) : (
        <ul className="max-h-[50vh] space-y-1 overflow-y-auto">
          {(candidatos ?? []).map((c) => (
            <li key={c.usuario_id}
                className="flex items-center gap-3 rounded-lg border border-gray-200 px-3 py-2">
              <input
                type="checkbox"
                className="h-4 w-4"
                checked={c.faena_fija || c.asignado}
                disabled={c.faena_fija || toggle.isPending}
                onChange={async (e) => {
                  try {
                    await toggle.mutateAsync({
                      usuarioId: c.usuario_id, faenaId, asignar: e.target.checked,
                    })
                  } catch (err: any) {
                    toast.error(err?.message ?? 'No se pudo cambiar la asignación')
                  }
                }}
              />
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium text-gray-900">{c.nombre}</p>
                <p className="truncate text-xs text-gray-500">
                  {c.email} · {c.rol}
                  {c.faena_fija && ' · faena fija (se cambia en Admin → usuarios)'}
                </p>
              </div>
            </li>
          ))}
        </ul>
      )}
      <div className="mt-3 border-t pt-3">
        <Button variant="outline" className="w-full" onClick={onClose}>Listo</Button>
      </div>
    </Modal>
  )
}

// ── Datos fijos de la faena (alimentan los generadores) ──────────────────────

const CONFIG_SECCIONES: Array<{ grupo: string; titulo: string; campos: Array<[string, string]> }> = [
  {
    grupo: 'mandante', titulo: 'Mandante',
    campos: [['razon_social', 'Razón social'], ['rut', 'RUT'], ['nombre_fantasia', 'Nombre fantasía'], ['region', 'Región']],
  },
  {
    grupo: 'instalacion', titulo: 'Instalación (E-200)',
    campos: [['nombre', 'Nombre'], ['estado', 'Estado'], ['tipo', 'Tipo'], ['region', 'Región'],
      ['provincia', 'Provincia'], ['comuna', 'Comuna'], ['datum', 'Datum'], ['huso', 'Huso'],
      ['cota', 'Cota (m.s.n.m.)'], ['coord_norte', 'Coordenada Norte'], ['coord_este', 'Coordenada Este']],
  },
  {
    grupo: 'contrato', titulo: 'Contrato',
    campos: [['numero', 'N° contrato / OC'], ['inicio', 'Inicio'], ['vigencia', 'Vigencia'],
      ['administrador', 'Administrador Pillado'], ['asesor_prevencion', 'Asesor prevención'],
      ['instalacion_informe', 'Instalación (informe)'], ['superintendencia', 'Superintendencia'],
      ['admin_mandante', 'Admin. contrato mandante'], ['cargo_admin_mandante', 'Cargo admin. mandante'],
      ['operador_mandante', 'Operador contrato mandante'], ['cargo_operador_mandante', 'Cargo operador']],
  },
  {
    grupo: 'experto', titulo: 'Experto / asesor SNGM',
    campos: [['nombre', 'Nombre'], ['run', 'RUN'], ['registro_sngm', 'Registro SNGM'],
      ['cargo', 'Cargo'], ['telefono', 'Teléfono'], ['email', 'E-mail']],
  },
  {
    grupo: 'empresa', titulo: 'Empresa (Pillado — común a todas)',
    campos: [['rut', 'RUT'], ['razon_social', 'Razón social'], ['nombre_fantasia', 'Nombre fantasía'],
      ['categoria', 'Categoría'], ['direccion', 'Dirección'], ['region', 'Región'],
      ['provincia', 'Provincia'], ['comuna', 'Comuna'], ['telefono', 'Teléfono'], ['email', 'E-mail'],
      ['rep_legal', 'Representante legal'], ['rep_legal_rut', 'RUT rep. legal'],
      ['rep_legal_telefono', 'Teléfono rep. legal'], ['rep_legal_email', 'E-mail rep. legal']],
  },
]

function ConfigFaenaModal({ open, onClose, faenaId }: {
  open: boolean
  onClose: () => void
  faenaId: string
}) {
  const toast = useToast()
  const { data: config } = useFaenaConfig(open ? faenaId : null)
  const guardar = useUpsertFaenaConfig()
  const [form, setForm] = useState<FaenaConfigDatos | null>(null)

  // El formulario parte del config cargado; si prevención cambia de faena con
  // el modal cerrado, al reabrir se resetea (open pasa a true de nuevo).
  const datos = form ?? config ?? {}

  const setCampo = (grupo: string, campo: string, valor: string) => {
    const base = { ...(form ?? config ?? {}) } as any
    base[grupo] = { ...(base[grupo] ?? {}), [campo]: valor }
    setForm(base)
  }

  const onGuardar = async () => {
    try {
      await guardar.mutateAsync({ faenaId, datos: (form ?? config ?? {}) as FaenaConfigDatos })
      toast.success('Datos de la faena guardados')
      setForm(null)
      onClose()
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo guardar')
    }
  }

  return (
    <Modal open={open} onClose={() => { setForm(null); onClose() }}
           title="Datos fijos de la faena (alimentan E-200 e informes)" className="max-w-2xl">
      <div className="max-h-[65vh] space-y-4 overflow-y-auto pr-1">
        <div className="space-y-1">
          <label className="block text-sm font-medium text-gray-700">Nombre oficial de la faena (E-200)</label>
          <Input value={String((datos as any).faena_nombre ?? '')}
                 onChange={(e) => {
                   const base = { ...(form ?? config ?? {}) } as any
                   base.faena_nombre = e.target.value
                   setForm(base)
                 }} />
        </div>
        {CONFIG_SECCIONES.map((sec) => (
          <div key={sec.grupo}>
            <p className="mb-1.5 text-sm font-bold text-gray-700">{sec.titulo}</p>
            <div className="grid grid-cols-2 gap-2">
              {sec.campos.map(([campo, label]) => (
                <Input key={campo} label={label}
                       value={String(((datos as any)[sec.grupo] ?? {})[campo] ?? '')}
                       onChange={(e) => setCampo(sec.grupo, campo, e.target.value)} />
              ))}
            </div>
          </div>
        ))}
      </div>
      <div className="mt-3 flex gap-2 border-t pt-3">
        <Button className="flex-1" onClick={onGuardar} disabled={guardar.isPending}>
          {guardar.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
          Guardar
        </Button>
        <Button variant="outline" onClick={() => { setForm(null); onClose() }}>Cancelar</Button>
      </div>
    </Modal>
  )
}
