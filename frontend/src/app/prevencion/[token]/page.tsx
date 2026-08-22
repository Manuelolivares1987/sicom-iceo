'use client'

// ============================================================================
// Portal de documentación de prevención para el mandante (MIG308 + MIG313)
// ----------------------------------------------------------------------------
// Quien abre esto es el cliente, no un usuario del sistema. Dos consecuencias
// de diseño:
//
//   1. Primero se identifica. El link no basta: hay que entrar con un correo
//      autorizado, y el ingreso queda registrado. Un mandante que audita
//      necesita poder decir "entré el 22 y estaba vencido"; y nosotros
//      necesitamos poder decir quién miró qué y cuándo. El filtro real está en
//      la base — esta pantalla sólo lo presenta.
//
//   2. Se lee como un documento, no como un tablero. Secciones numeradas,
//      membrete con faena y fecha de consulta, y la conclusión arriba en vez
//      de doce tarjetas de colores. Es lo que un mandante espera recibir.
//
// Un documento sin respaldo cargado se muestra "En proceso": es la verdad —el
// papel existe y Prevención lo está digitalizando— y no un hueco que parezca
// descuido.
// ============================================================================

import { useEffect, useMemo, useState } from 'react'
import { useParams } from 'next/navigation'
import { useQuery } from '@tanstack/react-query'
import {
  ShieldCheck, AlertTriangle, Truck, Wrench,
  ChevronDown, ChevronRight, Ban, ExternalLink, Printer, Lock, LogIn,
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
type Intervencion = {
  folio: string
  fecha: string | null
  tipo: string
  trabajo: string | null
  km: number | null
  horas: number | null
}
type Equipo = {
  activo_id: string
  patente: string
  codigo: string
  nombre: string | null
  tipo: string
  ubicacion: string | null
  estado_codigo: string | null
  marca_modelo: string | null
  documentos: DocEquipo[]
  mantenimiento: Intervencion[]
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
type Sesion = { acceso_id: string; nombre: string; portal: string; cliente: string | null }

// ── Semáforo, un solo criterio para papeles de equipo y de persona ─────────
type Nivel = 'rojo' | 'naranjo' | 'amarillo' | 'verde' | 'gris'

const NIVEL_UI: Record<Nivel, { chip: string }> = {
  rojo:     { chip: 'bg-red-50 text-red-700 ring-red-200' },
  naranjo:  { chip: 'bg-orange-50 text-orange-700 ring-orange-200' },
  amarillo: { chip: 'bg-amber-50 text-amber-800 ring-amber-200' },
  verde:    { chip: 'bg-emerald-50 text-emerald-700 ring-emerald-200' },
  gris:     { chip: 'bg-slate-100 text-slate-500 ring-slate-200' },
}

// Los estados de examen y los de documento de equipo no se llaman igual en la
// base. Se traducen los dos al mismo semáforo porque para el mandante es la
// misma pregunta: ¿está al día o no?
const ESTADO_DOC: Record<string, { label: string; nivel: Nivel }> = {
  vencido:       { label: 'Vencido',           nivel: 'rojo' },
  sin_dato:      { label: 'En proceso',        nivel: 'naranjo' },
  por_vencer_7:  { label: 'Vence esta semana', nivel: 'rojo' },
  observado:     { label: 'Observado',         nivel: 'naranjo' },
  por_vencer_14: { label: '≤ 14 días',         nivel: 'naranjo' },
  por_vencer_30: { label: '≤ 30 días',         nivel: 'amarillo' },
  por_vencer:    { label: 'Por vencer',        nivel: 'amarillo' },
  por_vencer_60: { label: '≤ 60 días',         nivel: 'verde' },
  vigente:       { label: 'Vigente',           nivel: 'verde' },
  no_aplica:     { label: 'No aplica',         nivel: 'gris' },
}
const docUI = (estado: string) => ESTADO_DOC[estado] ?? { label: estado, nivel: 'gris' as Nivel }
const ORDEN_NIVEL: Record<Nivel, number> = { rojo: 0, naranjo: 1, amarillo: 2, verde: 3, gris: 4 }

const ESTADO_PERSONA: Record<string, { label: string; nivel: Nivel }> = {
  no_conforme: { label: 'No conforme', nivel: 'rojo' },
  critico:     { label: 'Crítico',     nivel: 'naranjo' },
  observado:   { label: 'Observado',   nivel: 'amarillo' },
  conforme:    { label: 'Conforme',    nivel: 'verde' },
}

const esPendiente = (estado: string) => {
  const n = docUI(estado).nivel
  return n === 'rojo' || n === 'naranjo'
}

const num = (n: number | null | undefined) =>
  n == null ? null : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 0 })

// ── Piezas ─────────────────────────────────────────────────────────────────
function Chip({ nivel, children }: { nivel: Nivel; children: React.ReactNode }) {
  return (
    <span className={cn(
      'inline-flex shrink-0 items-center rounded px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide ring-1',
      NIVEL_UI[nivel].chip,
    )}>
      {children}
    </span>
  )
}

function Seccion({ n, titulo, bajada, children }: {
  n: number; titulo: string; bajada?: string; children: React.ReactNode
}) {
  return (
    <section className="space-y-3">
      <div className="border-b border-slate-200 pb-2">
        <h2 className="text-sm font-bold uppercase tracking-wide text-slate-800">
          <span className="text-slate-400">{n}.</span> {titulo}
        </h2>
        {bajada && <p className="mt-0.5 text-xs text-slate-500">{bajada}</p>}
      </div>
      {children}
    </section>
  )
}

// ── Puerta de entrada ──────────────────────────────────────────────────────
function Ingreso({ token, onEntrar }: { token: string; onEntrar: (s: Sesion) => void }) {
  const [nombre, setNombre] = useState('')
  const [email, setEmail] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  const entrar = async (e: React.FormEvent) => {
    e.preventDefault()
    setEnviando(true)
    setError(null)
    const { data, error } = await supabase.rpc('fn_portal_prevencion_ingresar', {
      p_token: token,
      p_nombre: nombre,
      p_email: email,
    })
    setEnviando(false)
    if (error) { setError(error.message); return }
    const s = data as Sesion
    sessionStorage.setItem(`portal-prev-${token}`, JSON.stringify(s))
    onEntrar(s)
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-100 px-4 py-10">
      <div className="w-full max-w-sm overflow-hidden rounded-2xl bg-white shadow-lg ring-1 ring-slate-200">
        <div className="flex flex-col items-center gap-2 border-b border-slate-100 px-8 py-7">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/images/logo_empresa_2.png" alt="Pillado Empresas" className="h-11 object-contain" />
          <p className="text-center text-[11px] font-semibold uppercase tracking-widest text-slate-400">
            Documentación de Prevención
          </p>
        </div>

        <form onSubmit={entrar} className="space-y-4 px-8 py-7">
          <div className="flex items-start gap-2 rounded-lg bg-slate-50 px-3 py-2.5 text-[11px] leading-relaxed text-slate-600">
            <Lock className="mt-0.5 h-3.5 w-3.5 shrink-0 text-slate-400" />
            <span>
              Acceso restringido a las personas autorizadas por el contrato. Su ingreso queda
              registrado.
            </span>
          </div>

          <div>
            <label className="mb-1 block text-xs font-medium text-slate-600">Nombre y apellido</label>
            <input
              value={nombre}
              onChange={(e) => setNombre(e.target.value)}
              required
              autoComplete="name"
              placeholder="Nombre completo"
              className="h-10 w-full rounded-lg border border-slate-300 px-3 text-sm focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/20"
            />
          </div>

          <div>
            <label className="mb-1 block text-xs font-medium text-slate-600">Correo corporativo</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              autoComplete="email"
              placeholder="nombre@empresa.cl"
              className="h-10 w-full rounded-lg border border-slate-300 px-3 text-sm focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/20"
            />
          </div>

          {error && (
            <p className="rounded-lg bg-red-50 px-3 py-2 text-xs leading-relaxed text-red-700">{error}</p>
          )}

          <button
            type="submit"
            disabled={enviando}
            className="inline-flex h-10 w-full items-center justify-center gap-2 rounded-lg bg-slate-900 text-sm font-semibold text-white transition-colors hover:bg-slate-800 disabled:opacity-50"
          >
            {enviando ? <Spinner className="h-4 w-4" /> : <><LogIn className="h-4 w-4" /> Ingresar</>}
          </button>

          <p className="text-center text-[10px] leading-relaxed text-slate-400">
            ¿Sin acceso? Solicítelo al área de Prevención de Riesgos de Pillado Empresas.
          </p>
        </form>
      </div>
    </div>
  )
}

// ── Documento de un equipo ─────────────────────────────────────────────────
function FilaDocEquipo({ d }: { d: DocEquipo }) {
  const ui = docUI(d.estado)
  return (
    <tr className="border-b border-slate-100 last:border-0">
      <td className="py-2 pr-3">
        <p className="text-xs font-medium text-slate-800">
          {TIPO_DOC_LABEL[d.tipo] ?? d.tipo}
          {d.bloqueante && (
            <span className="ml-1.5 text-[9px] font-bold uppercase tracking-wide text-slate-400">
              habilitante
            </span>
          )}
        </p>
        {d.entidad_certificadora && (
          <p className="text-[10px] text-slate-400">{d.entidad_certificadora}</p>
        )}
      </td>
      <td className="whitespace-nowrap py-2 pr-3 text-[11px] text-slate-500">
        {d.estado === 'no_aplica'
          ? '—'
          : d.fecha_vencimiento
            ? formatDate(d.fecha_vencimiento)
            : 'sin fecha'}
      </td>
      <td className="whitespace-nowrap py-2 pr-3 text-[11px] tabular-nums text-slate-500">
        {d.dias_restantes == null
          ? '—'
          : d.dias_restantes < 0
            ? <span className="font-semibold text-red-600">{Math.abs(d.dias_restantes)} d. vencido</span>
            : `en ${d.dias_restantes} d.`}
      </td>
      <td className="py-2 pr-3"><Chip nivel={ui.nivel}>{ui.label}</Chip></td>
      <td className="py-2 text-right">
        {/* Un papel vigente sin archivo cargado no está "sin PDF": está en
            proceso de digitalización. Decirlo así es exacto. */}
        {d.archivo_url ? (
          <a
            href={d.archivo_url}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1 rounded border border-slate-300 px-2 py-1 text-[10px] font-semibold text-slate-700 hover:border-slate-400 hover:bg-slate-50"
          >
            Ver <ExternalLink className="h-3 w-3" />
          </a>
        ) : (
          <span className="text-[10px] italic text-slate-400">En proceso</span>
        )}
      </td>
    </tr>
  )
}

function FichaEquipo({ eq }: { eq: Equipo }) {
  const [ver, setVer] = useState<'pendientes' | 'todo' | 'mantenimiento'>('pendientes')

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
  const visibles = ver === 'todo' ? docs : pendientes

  return (
    <article className="overflow-hidden rounded-xl border border-slate-200 bg-white">
      <header className="flex flex-wrap items-center gap-x-4 gap-y-2 border-b border-slate-100 bg-slate-50/60 px-4 py-3">
        <Truck className="h-5 w-5 shrink-0 text-slate-400" />
        <div className="min-w-0 flex-1">
          <p className="font-mono text-base font-bold tracking-tight text-slate-900">{eq.patente}</p>
          <p className="truncate text-[11px] text-slate-500">
            {[eq.marca_modelo, eq.nombre, eq.ubicacion].filter(Boolean).join(' · ')}
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
          {pendientes.length ? `${pendientes.length} por regularizar` : 'Documentación al día'}
        </Chip>
      </header>

      <nav className="flex gap-4 border-b border-slate-100 px-4">
        {([
          ['pendientes', `Por regularizar (${pendientes.length})`],
          ['todo', `Documentación (${docs.length})`],
          ['mantenimiento', `Mantenimiento (${eq.mantenimiento.length})`],
        ] as const).map(([k, label]) => (
          <button
            key={k}
            onClick={() => setVer(k)}
            className={cn(
              '-mb-px border-b-2 py-2 text-[11px] font-semibold transition-colors',
              ver === k
                ? 'border-slate-800 text-slate-900'
                : 'border-transparent text-slate-400 hover:text-slate-600',
            )}
          >
            {label}
          </button>
        ))}
      </nav>

      <div className="px-4 py-2">
        {ver === 'mantenimiento' ? (
          eq.mantenimiento.length === 0 ? (
            <p className="py-6 text-center text-xs text-slate-400">
              Sin intervenciones registradas para este equipo.
            </p>
          ) : (
            <ol className="space-y-2 py-1">
              {eq.mantenimiento.map((m, idx) => (
                <li key={idx} className="flex gap-3 border-b border-slate-100 pb-2 last:border-0">
                  <Wrench className="mt-0.5 h-3.5 w-3.5 shrink-0 text-slate-300" />
                  <div className="min-w-0 flex-1">
                    <p className="text-[11px] font-semibold text-slate-700">
                      {m.folio}
                      <span className="ml-2 font-normal text-slate-400">
                        {m.fecha ? formatDate(m.fecha) : ''} · {m.tipo}
                        {m.km ? ` · ${num(m.km)} km` : ''}
                        {m.horas ? ` · ${num(m.horas)} hrs` : ''}
                      </span>
                    </p>
                    {m.trabajo && (
                      <p className="mt-0.5 text-[11px] leading-relaxed text-slate-600">{m.trabajo}</p>
                    )}
                  </div>
                </li>
              ))}
            </ol>
          )
        ) : visibles.length === 0 ? (
          <p className="py-6 text-center text-xs text-slate-400">
            No hay documentos por regularizar en este equipo.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-slate-200 text-left text-[10px] font-semibold uppercase tracking-wide text-slate-400">
                  <th className="py-1.5 pr-3">Documento</th>
                  <th className="py-1.5 pr-3">Vence</th>
                  <th className="py-1.5 pr-3">Plazo</th>
                  <th className="py-1.5 pr-3">Estado</th>
                  <th className="py-1.5 text-right">Respaldo</th>
                </tr>
              </thead>
              <tbody>
                {visibles.map((d) => <FilaDocEquipo key={d.tipo} d={d} />)}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </article>
  )
}

// ── Persona ────────────────────────────────────────────────────────────────
function FilaPersona({
  p, token, acceso, verArchivos,
}: {
  p: Persona; token: string; acceso: string; verArchivos: boolean
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

  const abrirRespaldo = async (examenId: string) => {
    setAbriendo(examenId)
    setErrorArchivo(null)
    try {
      // Con barra final: next.config usa trailingSlash y sin ella el POST se
      // va en un 308 antes de llegar.
      const r = await fetch('/api/prevencion/portal-archivo/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token, examen_id: examenId, acceso_id: acceso }),
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
    <div className="border-b border-slate-100 last:border-0">
      <button
        onClick={() => setAbierto((v) => !v)}
        className="flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-slate-50"
      >
        {abierto ? <ChevronDown className="h-4 w-4 shrink-0 text-slate-400" />
                 : <ChevronRight className="h-4 w-4 shrink-0 text-slate-400" />}
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-medium text-slate-900">{p.nombre}</p>
          <p className="text-[11px] text-slate-400">
            {p.rut_enmascarado ?? '—'}
            {p.cargo ? ` · ${p.cargo}` : ''}
            {p.empresa ? ` · ${p.empresa}` : ''}
          </p>
        </div>
        {pendientes.length > 0 && (
          <span className="shrink-0 text-[11px] font-semibold tabular-nums text-red-600">
            {pendientes.length}
          </span>
        )}
        <Chip nivel={ui.nivel}>{ui.label}</Chip>
      </button>

      {abierto && (
        <div className="space-y-1 bg-slate-50/70 px-4 pb-3 pt-1">
          {errorArchivo && (
            <p className="rounded bg-red-50 px-2 py-1 text-[11px] text-red-700">{errorArchivo}</p>
          )}
          {docs.map((d) => {
            const dui = docUI(d.estado)
            const noAplica = d.estado === 'no_aplica' || !d.aplica
            return (
              <div key={d.examen_id} className="flex items-center gap-2 rounded bg-white px-2.5 py-1.5">
                <div className="min-w-0 flex-1">
                  <p className="truncate text-[11px] font-medium text-slate-800">{d.tipo_nombre}</p>
                  <p className="text-[10px] text-slate-400">
                    {noAplica
                      ? d.motivo_no_aplica ?? 'No aplica al cargo'
                      : d.fecha_vencimiento
                        ? `Vence ${formatDate(d.fecha_vencimiento)}`
                        : 'Documento en proceso de carga'}
                    {d.laboratorio ? ` · ${d.laboratorio}` : ''}
                  </p>
                </div>
                <Chip nivel={dui.nivel}>{dui.label}</Chip>
                {verArchivos && !noAplica && (
                  d.tiene_archivo ? (
                    <button
                      onClick={() => abrirRespaldo(d.examen_id)}
                      disabled={abriendo === d.examen_id}
                      className="inline-flex shrink-0 items-center gap-1 rounded border border-slate-300 px-2 py-1 text-[10px] font-semibold text-slate-700 hover:border-slate-400 hover:bg-slate-50 disabled:opacity-50"
                    >
                      {abriendo === d.examen_id ? <Spinner className="h-3 w-3" /> : <>Ver <ExternalLink className="h-3 w-3" /></>}
                    </button>
                  ) : (
                    <span className="shrink-0 text-[10px] italic text-slate-400">En proceso</span>
                  )
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
  const [sesion, setSesion] = useState<Sesion | null | undefined>(undefined)

  // Un refresco dentro de la misma pestaña no obliga a identificarse de nuevo.
  useEffect(() => {
    if (!token) return
    const raw = sessionStorage.getItem(`portal-prev-${token}`)
    setSesion(raw ? (JSON.parse(raw) as Sesion) : null)
  }, [token])

  const { data, isLoading, error } = useQuery({
    queryKey: ['portal-prevencion', token, sesion?.acceso_id],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('fn_portal_prevencion_publico', {
        p_token: token,
        p_acceso_id: sesion!.acceso_id,
      })
      if (error) throw error
      return data as PortalData
    },
    enabled: !!token && !!sesion?.acceso_id,
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
      pePendientes: cuenta(docsPe, ['rojo', 'naranjo']),
      porVencer: cuenta(docsEq, ['amarillo']) + cuenta(docsPe, ['amarillo']),
    }
  }, [data])

  // Se lee la sesión del navegador antes de decidir qué mostrar.
  if (sesion === undefined) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-100">
        <Spinner className="h-7 w-7" />
      </div>
    )
  }

  if (!sesion) return <Ingreso token={token} onEntrar={setSesion} />

  if (isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-100">
        <Spinner className="h-7 w-7" />
      </div>
    )
  }

  if (error || !data) {
    const expirado = (error as Error | undefined)?.message?.includes('Identifíquese')
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-100 px-6">
        <div className="max-w-sm rounded-2xl bg-white px-6 py-8 text-center shadow ring-1 ring-slate-200">
          <Ban className="mx-auto mb-3 h-8 w-8 text-slate-300" />
          <p className="text-sm font-semibold text-slate-800">
            {expirado ? 'Su sesión expiró' : 'Este link no está disponible'}
          </p>
          <p className="mt-1 text-xs leading-relaxed text-slate-500">
            {expirado
              ? 'Por seguridad el acceso caduca. Vuelva a identificarse para continuar.'
              : 'Puede haber sido revocado o haber vencido. Solicite uno nuevo al área de Prevención de Riesgos de Pillado Empresas.'}
          </p>
          <button
            onClick={() => { sessionStorage.removeItem(`portal-prev-${token}`); setSesion(null) }}
            className="mt-4 inline-flex h-9 items-center rounded-lg bg-slate-900 px-4 text-xs font-semibold text-white hover:bg-slate-800"
          >
            Volver a ingresar
          </button>
        </div>
      </div>
    )
  }

  const totalPendientes = (resumen?.eqPendientes ?? 0) + (resumen?.pePendientes ?? 0)

  return (
    <div className="min-h-screen bg-slate-100 pb-16">
      {/* ── Membrete ── */}
      <header className="border-b-2 border-slate-800 bg-white">
        <div className="mx-auto max-w-4xl px-6 py-5">
          <div className="flex flex-wrap items-start gap-4">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/images/logo_empresa_2.png" alt="Pillado Empresas" className="h-10 object-contain" />
            <div className="min-w-0 flex-1">
              <h1 className="text-lg font-bold leading-tight text-slate-900">{data.portal.nombre}</h1>
              <p className="text-xs text-slate-500">{data.portal.cliente}</p>
            </div>
            <button
              onClick={() => window.print()}
              className="hidden shrink-0 items-center gap-1.5 rounded-lg border border-slate-300 px-3 py-1.5 text-[11px] font-semibold text-slate-600 hover:bg-slate-50 sm:inline-flex"
            >
              <Printer className="h-3.5 w-3.5" /> Imprimir
            </button>
          </div>

          <dl className="mt-4 grid grid-cols-2 gap-x-6 gap-y-1.5 border-t border-slate-100 pt-3 text-[11px] sm:grid-cols-4">
            {[
              ['Faena', data.portal.faena_codigo ?? '—'],
              ['Equipos en faena', String(resumen?.equipos ?? 0)],
              ['Personas acreditadas', String(resumen?.personas ?? 0)],
              ['Consultado', formatDate(data.portal.generado_at)],
            ].map(([k, v]) => (
              <div key={k}>
                <dt className="font-semibold uppercase tracking-wide text-slate-400">{k}</dt>
                <dd className="text-slate-800">{v}</dd>
              </div>
            ))}
          </dl>

          <p className="mt-3 text-[10px] text-slate-400">
            Consultado por {sesion.nombre}. Este portal lee en línea el sistema de gestión de Pillado
            Empresas: refleja el estado de hoy, no una copia enviada por correo.
          </p>
        </div>
      </header>

      <main className="mx-auto max-w-4xl space-y-8 px-6 py-6">
        {/* ── 1. La conclusión primero ── */}
        <Seccion n={1} titulo="Estado de cumplimiento">
          <div
            className={cn(
              'flex items-start gap-3 rounded-xl border px-4 py-3.5',
              totalPendientes > 0 ? 'border-red-200 bg-red-50' : 'border-emerald-200 bg-emerald-50',
            )}
          >
            {totalPendientes > 0
              ? <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-red-500" />
              : <ShieldCheck className="mt-0.5 h-5 w-5 shrink-0 text-emerald-600" />}
            <div>
              <p className={cn('text-sm font-semibold', totalPendientes > 0 ? 'text-red-800' : 'text-emerald-800')}>
                {totalPendientes > 0
                  ? `${totalPendientes} documento${totalPendientes > 1 ? 's' : ''} por regularizar`
                  : 'Toda la documentación de la faena está al día'}
              </p>
              <p className={cn('mt-0.5 text-xs leading-relaxed', totalPendientes > 0 ? 'text-red-700' : 'text-emerald-700')}>
                {totalPendientes > 0
                  ? `Vencidos, observados, en proceso de carga o con vencimiento dentro de los próximos 14 días. ${resumen?.eqPendientes ?? 0} corresponden a equipos y ${resumen?.pePendientes ?? 0} a personal.`
                  : 'Sin vencidos ni observados a la fecha de esta consulta.'}
                {(resumen?.porVencer ?? 0) > 0 && ` Además, ${resumen!.porVencer} vencen dentro de 30 días.`}
              </p>
            </div>
          </div>
        </Seccion>

        {/* ── 2. Equipos ── */}
        <Seccion
          n={2}
          titulo="Equipos en faena"
          bajada="Documentación habilitante e historial de mantenimiento de cada equipo."
        >
          {data.equipos.length === 0 ? (
            <p className="py-8 text-center text-sm text-slate-400">Sin equipos asociados a este portal.</p>
          ) : (
            <div className="space-y-4">
              {data.equipos.map((eq) => <FichaEquipo key={eq.activo_id} eq={eq} />)}
            </div>
          )}
        </Seccion>

        {/* ── 3. Personal ── */}
        <Seccion
          n={3}
          titulo="Personal acreditado"
          bajada="Exámenes ocupacionales y licencias internas. Se informa vigencia y estado; no se entregan resultados clínicos."
        >
          <div className="overflow-hidden rounded-xl border border-slate-200 bg-white">
            {data.personal.length === 0 ? (
              <p className="py-8 text-center text-sm text-slate-400">Sin personal acreditado en esta faena.</p>
            ) : (
              data.personal.map((p) => (
                <FilaPersona
                  key={p.personal_id}
                  p={p}
                  token={token}
                  acceso={sesion.acceso_id}
                  verArchivos={data.portal.ver_archivos_personal}
                />
              ))
            )}
          </div>
        </Seccion>

        {/* ── Pie ── */}
        <footer className="space-y-2 border-t border-slate-200 pt-4 text-[10px] leading-relaxed text-slate-400">
          <p>
            <strong className="text-slate-500">Documentos en proceso:</strong> el respaldo digital está
            en carga. El documento existe y su vigencia es la informada; solicite la copia a Prevención
            de Riesgos si la necesita antes.
          </p>
          <p>
            Contiene datos personales de trabajadores entregados para el control de acceso a faena. Su
            uso está limitado a ese fin. Pillado Empresas · Trayectoria y Compromiso.
          </p>
        </footer>
      </main>
    </div>
  )
}
