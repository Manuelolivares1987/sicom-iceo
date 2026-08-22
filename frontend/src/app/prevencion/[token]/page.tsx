'use client'

// ============================================================================
// Portal de prevención para el mandante (MIG308)
// ----------------------------------------------------------------------------
// Lo abre alguien de afuera, sin cuenta, con el link que le entregó Prevención.
// No es un dashboard: es la respuesta a una pregunta concreta —"¿está al día lo
// que tengo en mi faena?"— y por eso lo primero que se ve es lo que NO está al
// día. El resto queda abajo, ordenado, para revisarlo cuando toque auditoría.
//
// Todo lo que se muestra viene de un solo RPC que ya trae el alcance recortado
// por el token. Esta página no puede pedir más de lo que le corresponde.
// ============================================================================

import { useMemo, useState } from 'react'
import { useParams } from 'next/navigation'
import { useQuery } from '@tanstack/react-query'
import {
  ShieldCheck, AlertTriangle, FileText, Truck, HardHat,
  ChevronDown, ChevronRight, Clock, Ban, ExternalLink, Printer,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { cn, formatDate } from '@/lib/utils'
import { supabase } from '@/lib/supabase'
import { TIPO_DOC_LABEL } from '@/lib/services/taller-planificacion'
import { estadoFlotaLabel, estadoFlotaColor } from '@/lib/estado-flota'

// ── Tipos del RPC ──────────────────────────────────────────────────────────
type DocEquipo = {
  tipo: string
  numero_certificado: string | null
  entidad_certificadora: string | null
  fecha_emision: string | null
  fecha_vencimiento: string | null
  dias_restantes: number | null
  estado: 'vigente' | 'por_vencer' | 'vencido' | 'no_aplica'
  bloqueante: boolean
  archivo_url: string | null
}
type Equipo = {
  activo_id: string
  patente: string
  codigo: string
  nombre: string | null
  tipo: string
  ubicacion: string | null
  estado_codigo: string | null
  documentos: DocEquipo[]
}
type DocPersona = {
  examen_id: string
  tipo_codigo: string
  tipo_nombre: string
  categoria: string
  laboratorio: string | null
  fecha_vencimiento: string | null
  dias_restantes: number | null
  estado: string
  aplica: boolean
  motivo_no_aplica: string | null
  tiene_archivo: boolean
}
type Persona = {
  personal_id: string
  nombre: string
  rut_enmascarado: string | null
  cargo: string | null
  empresa: string | null
  estado_general: string
  documentos: DocPersona[]
}
type PortalData = {
  portal: {
    nombre: string
    cliente: string | null
    faena_codigo: string | null
    ver_archivos_personal: boolean
    generado_at: string
  }
  equipos: Equipo[]
  personal: Persona[]
}

// ── Semáforo, un solo criterio para papeles de equipo y de persona ─────────
type Nivel = 'rojo' | 'naranjo' | 'amarillo' | 'verde' | 'gris'

const NIVEL_UI: Record<Nivel, { chip: string; punto: string }> = {
  rojo:    { chip: 'bg-red-100 text-red-800 ring-red-200',        punto: 'bg-red-500' },
  naranjo: { chip: 'bg-orange-100 text-orange-800 ring-orange-200', punto: 'bg-orange-500' },
  amarillo:{ chip: 'bg-amber-100 text-amber-800 ring-amber-200',   punto: 'bg-amber-400' },
  verde:   { chip: 'bg-emerald-100 text-emerald-800 ring-emerald-200', punto: 'bg-emerald-500' },
  gris:    { chip: 'bg-gray-100 text-gray-500 ring-gray-200',      punto: 'bg-gray-300' },
}

// Los estados de examen (v_prevencion_examenes_estado) y los de documento de
// equipo (v_certificacion_actual) no se llaman igual. Aquí se traducen los dos
// al mismo semáforo, porque para el mandante es la misma pregunta.
const ESTADO_DOC: Record<string, { label: string; nivel: Nivel }> = {
  vencido:       { label: 'Vencido',      nivel: 'rojo' },
  sin_dato:      { label: 'Sin registro', nivel: 'rojo' },
  por_vencer_7:  { label: 'Vence esta semana', nivel: 'rojo' },
  observado:     { label: 'Observado',    nivel: 'naranjo' },
  por_vencer_14: { label: '≤ 14 días',    nivel: 'naranjo' },
  por_vencer_30: { label: '≤ 30 días',    nivel: 'amarillo' },
  por_vencer:    { label: 'Por vencer',   nivel: 'amarillo' },
  por_vencer_60: { label: '≤ 60 días',    nivel: 'verde' },
  vigente:       { label: 'Vigente',      nivel: 'verde' },
  no_aplica:     { label: 'No aplica',    nivel: 'gris' },
}
const docUI = (estado: string) => ESTADO_DOC[estado] ?? { label: estado, nivel: 'gris' as Nivel }

const ORDEN_NIVEL: Record<Nivel, number> = { rojo: 0, naranjo: 1, amarillo: 2, verde: 3, gris: 4 }

const ESTADO_PERSONA: Record<string, { label: string; nivel: Nivel }> = {
  no_conforme: { label: 'No conforme', nivel: 'rojo' },
  critico:     { label: 'Crítico',     nivel: 'naranjo' },
  observado:   { label: 'Observado',   nivel: 'amarillo' },
  conforme:    { label: 'Conforme',    nivel: 'verde' },
}

// Cuenta como "pendiente" lo que el mandante tendría que reclamar hoy.
const esPendiente = (estado: string) => {
  const n = docUI(estado).nivel
  return n === 'rojo' || n === 'naranjo'
}

// ── Piezas de UI ───────────────────────────────────────────────────────────
function Chip({ nivel, children }: { nivel: Nivel; children: React.ReactNode }) {
  return (
    <span className={cn('inline-flex shrink-0 items-center rounded-full px-2 py-0.5 text-[10px] font-bold ring-1', NIVEL_UI[nivel].chip)}>
      {children}
    </span>
  )
}

function KPI({ valor, label, nivel }: { valor: number; label: string; nivel: Nivel }) {
  return (
    <div className="rounded-xl border border-gray-200 bg-white px-4 py-3">
      <div className="flex items-center gap-2">
        <span className={cn('h-2.5 w-2.5 rounded-full', NIVEL_UI[nivel].punto)} />
        <span className="text-2xl font-bold tabular-nums text-gray-900">{valor}</span>
      </div>
      <p className="mt-0.5 text-[11px] leading-tight text-gray-500">{label}</p>
    </div>
  )
}

function FilaDocEquipo({ d, patente }: { d: DocEquipo; patente: string }) {
  const ui = docUI(d.estado)
  return (
    <div className="flex items-center gap-2 border-b border-gray-100 py-2 last:border-0">
      <FileText className="h-4 w-4 shrink-0 text-gray-300" />
      <div className="min-w-0 flex-1">
        <p className="truncate text-xs font-medium text-gray-800">
          {TIPO_DOC_LABEL[d.tipo] ?? d.tipo}
          {d.bloqueante && (
            <span className="ml-1.5 align-middle text-[9px] font-bold uppercase tracking-wide text-gray-400">
              habilitante
            </span>
          )}
        </p>
        <p className="text-[10px] text-gray-400">
          {d.estado === 'no_aplica'
            ? 'Sin vencimiento'
            : d.fecha_vencimiento
              ? `Vence ${formatDate(d.fecha_vencimiento)}${
                  d.dias_restantes != null && d.dias_restantes < 0
                    ? ` · ${Math.abs(d.dias_restantes)} días atrasado`
                    : d.dias_restantes != null
                      ? ` · en ${d.dias_restantes} días`
                      : ''
                }`
              : 'Sin fecha registrada'}
          {d.entidad_certificadora ? ` · ${d.entidad_certificadora}` : ''}
        </p>
      </div>
      <Chip nivel={ui.nivel}>{ui.label}</Chip>
      {d.archivo_url ? (
        <a
          href={d.archivo_url}
          target="_blank"
          rel="noreferrer"
          className="inline-flex shrink-0 items-center gap-1 rounded-lg border border-gray-300 px-2 py-1 text-[10px] font-semibold text-gray-700 hover:border-gray-400 hover:bg-gray-50"
          aria-label={`Abrir ${TIPO_DOC_LABEL[d.tipo] ?? d.tipo} de ${patente}`}
        >
          Ver <ExternalLink className="h-3 w-3" />
        </a>
      ) : (
        <span className="shrink-0 text-[9px] text-gray-300">sin PDF</span>
      )}
    </div>
  )
}

function TarjetaEquipo({ eq }: { eq: Equipo }) {
  const [abierto, setAbierto] = useState(false)
  const docs = useMemo(
    () =>
      [...eq.documentos].sort(
        (a, b) =>
          ORDEN_NIVEL[docUI(a.estado).nivel] - ORDEN_NIVEL[docUI(b.estado).nivel] ||
          (TIPO_DOC_LABEL[a.tipo] ?? a.tipo).localeCompare(TIPO_DOC_LABEL[b.tipo] ?? b.tipo, 'es'),
      ),
    [eq.documentos],
  )
  const pendientes = docs.filter((d) => esPendiente(d.estado))
  const visibles = abierto ? docs : pendientes

  return (
    <section className="overflow-hidden rounded-2xl border border-gray-200 bg-white">
      <header className="flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-gray-100 px-4 py-3">
        <Truck className="h-5 w-5 shrink-0 text-gray-400" />
        <div className="min-w-0 flex-1">
          <p className="font-mono text-base font-bold tracking-tight text-gray-900">{eq.patente}</p>
          <p className="truncate text-xs text-gray-500">
            {eq.nombre ?? eq.codigo}
            {eq.ubicacion ? ` · ${eq.ubicacion}` : ''}
          </p>
        </div>
        {eq.estado_codigo && (
          <span
            className="shrink-0 rounded px-2 py-0.5 text-[10px] font-semibold text-white"
            style={{ background: estadoFlotaColor(eq.estado_codigo) }}
          >
            {estadoFlotaLabel(eq.estado_codigo)}
          </span>
        )}
        <Chip nivel={pendientes.length ? 'rojo' : 'verde'}>
          {pendientes.length ? `${pendientes.length} por regularizar` : 'Al día'}
        </Chip>
      </header>

      <div className="px-4 py-1">
        {visibles.length === 0 ? (
          <p className="py-4 text-center text-xs text-gray-400">
            Sin documentos por regularizar en este equipo.
          </p>
        ) : (
          visibles.map((d) => <FilaDocEquipo key={d.tipo} d={d} patente={eq.patente} />)
        )}
      </div>

      <button
        onClick={() => setAbierto((v) => !v)}
        className="flex w-full items-center justify-center gap-1 border-t border-gray-100 py-2 text-[11px] font-semibold text-gray-500 hover:bg-gray-50 hover:text-gray-700"
      >
        {abierto ? <ChevronDown className="h-3.5 w-3.5" /> : <ChevronRight className="h-3.5 w-3.5" />}
        {abierto ? 'Ocultar los documentos al día' : `Ver los ${docs.length} documentos del equipo`}
      </button>
    </section>
  )
}

function FilaPersona({
  p,
  token,
  verArchivos,
}: {
  p: Persona
  token: string
  verArchivos: boolean
}) {
  const [abierto, setAbierto] = useState(false)
  const [abriendo, setAbriendo] = useState<string | null>(null)
  const [errorArchivo, setErrorArchivo] = useState<string | null>(null)

  const ui = ESTADO_PERSONA[p.estado_general] ?? { label: p.estado_general, nivel: 'gris' as Nivel }
  const docs = useMemo(
    () =>
      [...p.documentos].sort(
        (a, b) =>
          ORDEN_NIVEL[docUI(a.estado).nivel] - ORDEN_NIVEL[docUI(b.estado).nivel] ||
          a.tipo_nombre.localeCompare(b.tipo_nombre, 'es'),
      ),
    [p.documentos],
  )
  const pendientes = docs.filter((d) => esPendiente(d.estado))

  // El respaldo vive en un bucket privado: se pide al servidor un link firmado
  // que caduca. Nunca se expone la ruta ni la credencial.
  const abrirRespaldo = async (examenId: string) => {
    setAbriendo(examenId)
    setErrorArchivo(null)
    try {
      // Con la barra final: next.config usa trailingSlash, y sin ella el POST
      // se va en un 308 antes de llegar.
      const r = await fetch('/api/prevencion/portal-archivo/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token, examen_id: examenId }),
      })
      const j = await r.json()
      if (!r.ok || !j.url) throw new Error(j.error ?? 'No se pudo abrir el documento.')
      window.open(j.url, '_blank', 'noopener')
    } catch (e) {
      setErrorArchivo(e instanceof Error ? e.message : 'No se pudo abrir el documento.')
    } finally {
      setAbriendo(null)
    }
  }

  return (
    <div className="border-b border-gray-100 last:border-0">
      <button
        onClick={() => setAbierto((v) => !v)}
        className="flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-gray-50"
      >
        {abierto ? (
          <ChevronDown className="h-4 w-4 shrink-0 text-gray-400" />
        ) : (
          <ChevronRight className="h-4 w-4 shrink-0 text-gray-400" />
        )}
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-medium text-gray-900">{p.nombre}</p>
          <p className="text-[11px] text-gray-400">
            {p.rut_enmascarado ?? '—'}
            {p.cargo ? ` · ${p.cargo}` : ''}
          </p>
        </div>
        {pendientes.length > 0 && (
          <span className="shrink-0 text-[11px] font-semibold text-red-600 tabular-nums">
            {pendientes.length}
          </span>
        )}
        <Chip nivel={ui.nivel}>{ui.label}</Chip>
      </button>

      {abierto && (
        <div className="space-y-1 bg-gray-50/70 px-4 pb-3 pt-1">
          {errorArchivo && (
            <p className="rounded-lg bg-red-50 px-2 py-1 text-[11px] text-red-700">{errorArchivo}</p>
          )}
          {docs.map((d) => {
            const dui = docUI(d.estado)
            return (
              <div key={d.examen_id} className="flex items-center gap-2 rounded-lg bg-white px-2.5 py-1.5">
                <div className="min-w-0 flex-1">
                  <p className="truncate text-[11px] font-medium text-gray-800">{d.tipo_nombre}</p>
                  <p className="text-[10px] text-gray-400">
                    {d.estado === 'no_aplica' || !d.aplica
                      ? d.motivo_no_aplica ?? 'No aplica al cargo'
                      : d.fecha_vencimiento
                        ? `Vence ${formatDate(d.fecha_vencimiento)}`
                        : 'Sin registro'}
                    {d.laboratorio ? ` · ${d.laboratorio}` : ''}
                  </p>
                </div>
                <Chip nivel={dui.nivel}>{dui.label}</Chip>
                {verArchivos && d.tiene_archivo && (
                  <button
                    onClick={() => abrirRespaldo(d.examen_id)}
                    disabled={abriendo === d.examen_id}
                    className="inline-flex shrink-0 items-center gap-1 rounded-lg border border-gray-300 px-2 py-1 text-[10px] font-semibold text-gray-700 hover:border-gray-400 hover:bg-gray-50 disabled:opacity-50"
                  >
                    {abriendo === d.examen_id ? <Spinner className="h-3 w-3" /> : <>Ver <ExternalLink className="h-3 w-3" /></>}
                  </button>
                )}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

// ── Página ─────────────────────────────────────────────────────────────────
export default function PortalPrevencionPage() {
  const token = useParams()?.token as string
  const [tab, setTab] = useState<'equipos' | 'personal'>('equipos')

  const { data, isLoading, error } = useQuery({
    queryKey: ['portal-prevencion', token],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('fn_portal_prevencion_publico', { p_token: token })
      if (error) throw error
      return data as PortalData
    },
    enabled: !!token,
    staleTime: 60_000,
    retry: false,
  })

  const resumen = useMemo(() => {
    if (!data) return null
    const docsEq = data.equipos.flatMap((e) => e.documentos)
    const docsPe = data.personal.flatMap((p) => p.documentos)
    const cuenta = (docs: { estado: string }[], niveles: Nivel[]) =>
      docs.filter((d) => niveles.includes(docUI(d.estado).nivel)).length
    return {
      equipos: data.equipos.length,
      personas: data.personal.length,
      eqPendientes: cuenta(docsEq, ['rojo', 'naranjo']),
      eqPorVencer: cuenta(docsEq, ['amarillo']),
      pePendientes: cuenta(docsPe, ['rojo', 'naranjo']),
      pePorVencer: cuenta(docsPe, ['amarillo']),
      personasNoConformes: data.personal.filter(
        (p) => p.estado_general === 'no_conforme' || p.estado_general === 'critico',
      ).length,
    }
  }, [data])

  if (isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gray-100">
        <Spinner className="h-7 w-7" />
      </div>
    )
  }

  if (error || !data) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gray-100 px-6">
        <div className="max-w-sm rounded-2xl bg-white px-6 py-8 text-center shadow">
          <Ban className="mx-auto mb-3 h-8 w-8 text-gray-300" />
          <p className="text-sm font-semibold text-gray-800">Este link no está disponible</p>
          <p className="mt-1 text-xs text-gray-500">
            Puede haber sido revocado o haber vencido. Solicite uno nuevo al área de Prevención de
            Riesgos de Pillado Empresas.
          </p>
        </div>
      </div>
    )
  }

  const totalPendientes = (resumen?.eqPendientes ?? 0) + (resumen?.pePendientes ?? 0)

  return (
    <div className="min-h-screen bg-gray-100 pb-16">
      {/* ── Cabecera ── */}
      <header className="border-b border-gray-200 bg-white">
        <div className="mx-auto flex max-w-3xl flex-wrap items-center gap-3 px-5 py-4">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/images/logo_empresa_2.png" alt="Pillado Empresas" className="h-9 object-contain" />
          <div className="min-w-0 flex-1">
            <h1 className="truncate text-base font-bold text-gray-900">{data.portal.nombre}</h1>
            <p className="truncate text-[11px] text-gray-500">
              {data.portal.cliente ?? ''}
              {' · '}
              Consultado el {formatDate(data.portal.generado_at)}
            </p>
          </div>
          <button
            onClick={() => window.print()}
            className="hidden shrink-0 items-center gap-1 rounded-lg border border-gray-300 px-2.5 py-1.5 text-[11px] font-semibold text-gray-600 hover:bg-gray-50 sm:inline-flex"
          >
            <Printer className="h-3.5 w-3.5" /> Imprimir
          </button>
        </div>
      </header>

      <main className="mx-auto max-w-3xl space-y-5 px-5 py-5">
        {/* ── Lo primero: qué hay que reclamar ── */}
        <div
          className={cn(
            'flex items-start gap-3 rounded-2xl border px-4 py-3',
            totalPendientes > 0 ? 'border-red-200 bg-red-50' : 'border-emerald-200 bg-emerald-50',
          )}
        >
          {totalPendientes > 0 ? (
            <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-red-500" />
          ) : (
            <ShieldCheck className="mt-0.5 h-5 w-5 shrink-0 text-emerald-600" />
          )}
          <div>
            <p className={cn('text-sm font-semibold', totalPendientes > 0 ? 'text-red-800' : 'text-emerald-800')}>
              {totalPendientes > 0
                ? `${totalPendientes} documento${totalPendientes > 1 ? 's' : ''} por regularizar`
                : 'Toda la documentación de la faena está al día'}
            </p>
            <p className={cn('mt-0.5 text-xs', totalPendientes > 0 ? 'text-red-700' : 'text-emerald-700')}>
              {totalPendientes > 0
                ? 'Vencidos, observados o con vencimiento dentro de los próximos 14 días.'
                : 'Sin vencidos ni observados a la fecha de esta consulta.'}
            </p>
          </div>
        </div>

        {/* ── Cifras ── */}
        {resumen && (
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <KPI valor={resumen.equipos} label="Equipos en faena" nivel="gris" />
            <KPI valor={resumen.eqPendientes} label="Papeles de equipo por regularizar" nivel={resumen.eqPendientes ? 'rojo' : 'verde'} />
            <KPI valor={resumen.personas} label="Personas acreditadas" nivel="gris" />
            <KPI valor={resumen.personasNoConformes} label="Personas con documentación pendiente" nivel={resumen.personasNoConformes ? 'rojo' : 'verde'} />
          </div>
        )}

        {/* ── Tabs ── */}
        <div className="flex gap-1 rounded-xl bg-gray-200/70 p-1">
          {([
            { k: 'equipos' as const, icon: Truck, label: `Equipos (${data.equipos.length})` },
            { k: 'personal' as const, icon: HardHat, label: `Personal (${data.personal.length})` },
          ]).map(({ k, icon: Icon, label }) => (
            <button
              key={k}
              onClick={() => setTab(k)}
              className={cn(
                'flex flex-1 items-center justify-center gap-1.5 rounded-lg px-3 py-2 text-xs font-semibold transition-colors',
                tab === k ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-500 hover:text-gray-700',
              )}
            >
              <Icon className="h-4 w-4" /> {label}
            </button>
          ))}
        </div>

        {tab === 'equipos' ? (
          <div className="space-y-4">
            {data.equipos.length === 0 ? (
              <p className="py-10 text-center text-sm text-gray-400">Sin equipos asociados a este portal.</p>
            ) : (
              data.equipos.map((eq) => <TarjetaEquipo key={eq.activo_id} eq={eq} />)
            )}
          </div>
        ) : (
          <div className="overflow-hidden rounded-2xl border border-gray-200 bg-white">
            {data.personal.length === 0 ? (
              <p className="py-10 text-center text-sm text-gray-400">Sin personal acreditado en esta faena.</p>
            ) : (
              data.personal.map((p) => (
                <FilaPersona
                  key={p.personal_id}
                  p={p}
                  token={token}
                  verArchivos={data.portal.ver_archivos_personal}
                />
              ))
            )}
          </div>
        )}

        {/* ── Pie ── */}
        <footer className="space-y-2 pt-2 text-[11px] leading-relaxed text-gray-400">
          <p className="flex items-start gap-1.5">
            <Clock className="mt-0.5 h-3.5 w-3.5 shrink-0" />
            Este portal lee directo del sistema de gestión de Pillado Empresas: lo que ve aquí es el
            estado de hoy, no una copia enviada por correo.
          </p>
          <p>
            Contiene datos personales de trabajadores entregados para el control de acceso a faena.
            Su uso está limitado a ese fin. Para renovaciones o respaldos adicionales, contactar a
            Prevención de Riesgos de Pillado Empresas.
          </p>
        </footer>
      </main>
    </div>
  )
}
