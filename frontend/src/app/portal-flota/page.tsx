'use client'

// ============================================================================
// Portal de flota para el cliente (MIG609)
// ----------------------------------------------------------------------------
// Quien entra es el cliente (ESMAX), no un usuario del sistema. Ve por patente
// toda la documentación del camión —para leerla o descargarla— y el registro
// de mantenciones. Sin costos: es la conversación comercial, no la ficha
// técnica interna.
//
// Seguridad: el cliente no recibe sesión de Supabase (ver el encabezado de
// MIG609). Esta pantalla guarda un token y nada más; qué equipos ve lo decide
// la base desde su cuenta.
// ============================================================================

import { Suspense, useEffect, useMemo, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  AlertTriangle, ArrowLeft, Ban, ChevronDown, ChevronRight, Download, ExternalLink,
  FileArchive, FileText, KeyRound, Lock, LogIn, LogOut, Search, ShieldCheck, Truck, Wrench,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { cn, formatDate } from '@/lib/utils'
import { TIPO_DOC_LABEL } from '@/lib/services/taller-planificacion'
import {
  cambiarPassword, cargarFichaEquipo, cargarFlota, descargarZip, esSesionExpirada,
  guardarSesion, ingresar, leerSesion, nombreArchivo, registrarDescarga, salir, urlDescarga,
  type DocumentoPortal, type EquipoPortalResumen, type EstadoDocPortal, type FichaEquipoPortal,
  type MantencionPortal, type SesionPortalFlota,
} from '@/lib/services/portal-flota'

// ── Semáforo ───────────────────────────────────────────────────────────────
type Nivel = 'rojo' | 'naranjo' | 'amarillo' | 'verde' | 'gris'
const CHIP: Record<Nivel, string> = {
  rojo:     'bg-red-50 text-red-700 ring-red-200',
  naranjo:  'bg-orange-50 text-orange-700 ring-orange-200',
  amarillo: 'bg-amber-50 text-amber-800 ring-amber-200',
  verde:    'bg-emerald-50 text-emerald-700 ring-emerald-200',
  gris:     'bg-slate-100 text-slate-500 ring-slate-200',
}
// "permanente" en un papel de vehículo es que no vence (padrón, factura);
// "sin_fecha" es que el papel no la declara y la estamos confirmando. Son dos
// cosas distintas y el cliente tiene que poder distinguirlas.
const ESTADO: Record<EstadoDocPortal, { label: string; nivel: Nivel; orden: number }> = {
  vencido:    { label: 'Vencido',             nivel: 'rojo',     orden: 0 },
  sin_fecha:  { label: 'Fecha por confirmar', nivel: 'naranjo',  orden: 1 },
  por_vencer: { label: 'Por vencer',          nivel: 'amarillo', orden: 2 },
  vigente:    { label: 'Vigente',             nivel: 'verde',    orden: 3 },
  permanente: { label: 'Sin vencimiento',     nivel: 'gris',     orden: 4 },
}
const estadoUI = (e: string) => ESTADO[e as EstadoDocPortal] ?? { label: e, nivel: 'gris' as Nivel, orden: 9 }

const humanizar = (s: string | null | undefined) =>
  s ? s.charAt(0).toUpperCase() + s.slice(1).replace(/_/g, ' ') : ''

// El nombre propio del papel (p. ej. «Cert. Salfa - Frenado») manda sobre el
// del catálogo; sin él, «otra» se mostraba como «Otro».
const etiquetaDoc = (d: DocumentoPortal) =>
  d.etiqueta && d.etiqueta !== d.tipo ? d.etiqueta : TIPO_DOC_LABEL[d.tipo] ?? humanizar(d.tipo)

const num = (n: number | null | undefined) =>
  n == null ? null : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 0 })

function Chip({ nivel, children }: { nivel: Nivel; children: React.ReactNode }) {
  return (
    <span className={cn(
      'inline-flex shrink-0 items-center whitespace-nowrap rounded px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide ring-1',
      CHIP[nivel],
    )}>
      {children}
    </span>
  )
}

const inputCls =
  'h-10 w-full rounded-lg border border-slate-300 px-3 text-sm focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/20'

// ── Ingreso ────────────────────────────────────────────────────────────────
function Ingreso({ onEntrar }: { onEntrar: (s: SesionPortalFlota) => void }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  const entrar = async (e: React.FormEvent) => {
    e.preventDefault()
    setEnviando(true)
    setError(null)
    try {
      onEntrar(await ingresar(email, password))
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo ingresar.')
    } finally {
      setEnviando(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-100 px-4 py-10">
      <div className="w-full max-w-sm overflow-hidden rounded-2xl bg-white shadow-lg ring-1 ring-slate-200">
        <div className="flex flex-col items-center gap-2 border-b border-slate-100 px-8 py-7">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/images/logo_empresa_2.png" alt="Pillado Empresas" className="h-11 object-contain" />
          <p className="text-center text-[11px] font-semibold uppercase tracking-widest text-slate-400">
            Portal de Flota · Clientes
          </p>
        </div>

        <form onSubmit={entrar} className="space-y-4 px-8 py-7">
          <p className="text-xs leading-relaxed text-slate-600">
            Documentación vigente y registro de mantenciones de los equipos arrendados a su empresa.
          </p>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-600">Correo</label>
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required
                   autoComplete="username" placeholder="nombre@empresa.cl" className={inputCls} />
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-600">Contraseña</label>
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required
                   autoComplete="current-password" placeholder="••••••••" className={inputCls} />
          </div>

          {error && (
            <p className="rounded-lg bg-red-50 px-3 py-2 text-xs leading-relaxed text-red-700">{error}</p>
          )}

          <button type="submit" disabled={enviando}
                  className="inline-flex h-10 w-full items-center justify-center gap-2 rounded-lg bg-slate-900 text-sm font-semibold text-white transition-colors hover:bg-slate-800 disabled:opacity-50">
            {enviando ? <Spinner className="h-4 w-4" /> : <><LogIn className="h-4 w-4" /> Ingresar</>}
          </button>

          <div className="flex items-start gap-2 rounded-lg bg-slate-50 px-3 py-2.5 text-[10px] leading-relaxed text-slate-500">
            <Lock className="mt-0.5 h-3 w-3 shrink-0 text-slate-400" />
            <span>Acceso personal. Cada ingreso y descarga queda registrado. ¿Sin acceso? Solicítelo a su ejecutivo en Pillado Empresas.</span>
          </div>
        </form>
      </div>
    </div>
  )
}

// ── Cambio de contraseña (obligatorio la primera vez) ─────────────────────
function CambiarPassword({ sesion, obligatorio, onListo, onCancelar }: {
  sesion: SesionPortalFlota; obligatorio: boolean; onListo: () => void; onCancelar?: () => void
}) {
  const [actual, setActual] = useState('')
  const [nueva, setNueva] = useState('')
  const [repetir, setRepetir] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)

  const guardar = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    if (nueva !== repetir) { setError('Las contraseñas nuevas no coinciden.'); return }
    setEnviando(true)
    try {
      await cambiarPassword(sesion.token, actual, nueva)
      onListo()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'No se pudo cambiar la contraseña.')
    } finally {
      setEnviando(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-100 px-4 py-10">
      <form onSubmit={guardar} className="w-full max-w-sm space-y-4 rounded-2xl bg-white px-8 py-7 shadow-lg ring-1 ring-slate-200">
        <div className="flex items-center gap-2">
          <KeyRound className="h-5 w-5 text-slate-400" />
          <h1 className="text-sm font-bold text-slate-900">
            {obligatorio ? 'Defina su contraseña' : 'Cambiar contraseña'}
          </h1>
        </div>
        {obligatorio && (
          <p className="text-xs leading-relaxed text-slate-600">
            Ingresó con una contraseña temporal. Elija una propia para continuar: al menos 8
            caracteres, con letras y números.
          </p>
        )}
        <div>
          <label className="mb-1 block text-xs font-medium text-slate-600">
            {obligatorio ? 'Contraseña temporal' : 'Contraseña actual'}
          </label>
          <input type="password" value={actual} onChange={(e) => setActual(e.target.value)} required
                 autoComplete="current-password" className={inputCls} />
        </div>
        <div>
          <label className="mb-1 block text-xs font-medium text-slate-600">Contraseña nueva</label>
          <input type="password" value={nueva} onChange={(e) => setNueva(e.target.value)} required
                 minLength={8} autoComplete="new-password" className={inputCls} />
        </div>
        <div>
          <label className="mb-1 block text-xs font-medium text-slate-600">Repita la contraseña nueva</label>
          <input type="password" value={repetir} onChange={(e) => setRepetir(e.target.value)} required
                 minLength={8} autoComplete="new-password" className={inputCls} />
        </div>
        {error && <p className="rounded-lg bg-red-50 px-3 py-2 text-xs text-red-700">{error}</p>}
        <div className="flex gap-2">
          {onCancelar && (
            <button type="button" onClick={onCancelar}
                    className="h-10 flex-1 rounded-lg border border-slate-300 text-sm font-semibold text-slate-600 hover:bg-slate-50">
              Cancelar
            </button>
          )}
          <button type="submit" disabled={enviando}
                  className="inline-flex h-10 flex-1 items-center justify-center rounded-lg bg-slate-900 text-sm font-semibold text-white hover:bg-slate-800 disabled:opacity-50">
            {enviando ? <Spinner className="h-4 w-4" /> : 'Guardar'}
          </button>
        </div>
      </form>
    </div>
  )
}

// ── Lista de la flota ──────────────────────────────────────────────────────
function resumenDocs(e: EquipoPortalResumen): { nivel: Nivel; texto: string } {
  if (e.docs_total === 0) return { nivel: 'gris', texto: 'Documentación en carga' }
  if (e.docs_vencidos > 0) return { nivel: 'rojo', texto: `${e.docs_vencidos} vencido${e.docs_vencidos > 1 ? 's' : ''}` }
  // Un documento exigido que no está es tan pendiente como uno vencido: no
  // se puede decir «al día» a un camión sin RT.
  if (e.docs_pendientes > 0) return { nivel: 'rojo', texto: `${e.docs_pendientes} pendiente${e.docs_pendientes > 1 ? 's' : ''}` }
  if (e.docs_sin_fecha > 0) return { nivel: 'naranjo', texto: `${e.docs_sin_fecha} por confirmar` }
  if (e.docs_por_vencer > 0) return { nivel: 'amarillo', texto: `${e.docs_por_vencer} por vencer` }
  return { nivel: 'verde', texto: 'Al día' }
}

function ListaFlota({ equipos, onAbrir }: { equipos: EquipoPortalResumen[]; onAbrir: (id: string) => void }) {
  const [buscar, setBuscar] = useState('')
  const filtrados = useMemo(() => {
    const q = buscar.trim().toUpperCase().replace(/[\s-]/g, '')
    if (!q) return equipos
    return equipos.filter((e) =>
      [e.patente, e.codigo, e.nombre, e.marca_modelo]
        .some((v) => v?.toUpperCase().replace(/[\s-]/g, '').includes(q)))
  }, [equipos, buscar])

  const vencidos = equipos.reduce((s, e) => s + e.docs_vencidos, 0)
  const pendientes = equipos.reduce((s, e) => s + e.docs_pendientes, 0)
  const porVencer = equipos.reduce((s, e) => s + e.docs_por_vencer, 0)
  const conProblema = equipos.filter((e) => e.docs_vencidos > 0 || e.docs_pendientes > 0).length
  const mal = vencidos + pendientes > 0

  return (
    <div className="space-y-5">
      <div className={cn(
        'flex items-start gap-3 rounded-xl border px-4 py-3.5',
        mal ? 'border-red-200 bg-red-50' : 'border-emerald-200 bg-emerald-50',
      )}>
        {mal
          ? <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-red-500" />
          : <ShieldCheck className="mt-0.5 h-5 w-5 shrink-0 text-emerald-600" />}
        <div>
          <p className={cn('text-sm font-semibold', mal ? 'text-red-800' : 'text-emerald-800')}>
            {mal
              ? `${conProblema} de ${equipos.length} equipos con documentación pendiente`
              : `${equipos.length} equipo${equipos.length === 1 ? '' : 's'} con la documentación al día`}
          </p>
          <p className={cn('mt-0.5 text-xs', mal ? 'text-red-700' : 'text-emerald-700')}>
            {[
              pendientes > 0 && `${pendientes} documento${pendientes > 1 ? 's' : ''} exigido${pendientes > 1 ? 's' : ''} sin cargar`,
              vencidos > 0 && `${vencidos} vencido${vencidos > 1 ? 's' : ''}`,
              porVencer > 0 && `${porVencer} vence${porVencer > 1 ? 'n' : ''} dentro de 45 días`,
            ].filter(Boolean).join(' · ')}
            {mal || porVencer > 0 ? '. ' : ''}Información en línea desde el sistema de gestión de Pillado Empresas.
          </p>
        </div>
      </div>

      <div className="relative">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
        <input value={buscar} onChange={(e) => setBuscar(e.target.value)}
               placeholder="Buscar por patente…" className={cn(inputCls, 'bg-white pl-9 uppercase placeholder:normal-case')} />
      </div>

      {equipos.length === 0 ? (
        <p className="rounded-xl border border-dashed border-slate-300 bg-white py-12 text-center text-sm text-slate-400">
          Aún no hay equipos asociados a su cuenta.
        </p>
      ) : filtrados.length === 0 ? (
        <p className="py-8 text-center text-sm text-slate-400">Ninguna patente coincide con «{buscar}».</p>
      ) : (
        <ul className="divide-y divide-slate-100 overflow-hidden rounded-xl border border-slate-200 bg-white">
          {filtrados.map((e) => {
            const r = resumenDocs(e)
            return (
              <li key={e.activo_id}>
                <button onClick={() => onAbrir(e.activo_id)}
                        className="flex w-full items-center gap-3 px-4 py-3.5 text-left transition hover:bg-slate-50">
                  <Truck className="h-5 w-5 shrink-0 text-slate-300" />
                  <div className="min-w-0 flex-1">
                    <p className="font-mono text-base font-bold tracking-tight text-slate-900">{e.patente}</p>
                    <p className="truncate text-[11px] text-slate-500">
                      {[e.marca_modelo, e.anio, humanizar(e.tipo)].filter(Boolean).join(' · ')}
                    </p>
                  </div>
                  <div className="hidden text-right text-[11px] text-slate-500 sm:block">
                    <p>{e.docs_total} documentos</p>
                    <p className="text-slate-400">
                      {e.ultima_mantencion ? `Últ. mantención ${formatDate(e.ultima_mantencion)}` : 'Sin mantenciones aún'}
                    </p>
                  </div>
                  <Chip nivel={r.nivel}>{r.texto}</Chip>
                  <ChevronRight className="h-4 w-4 shrink-0 text-slate-300" />
                </button>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}

// ── Ficha del equipo ───────────────────────────────────────────────────────
function FilaDocumento({ d, patente, onDescarga }: {
  d: DocumentoPortal; patente: string; onDescarga: (detalle: string) => void
}) {
  const ui = estadoUI(d.estado)
  const etiqueta = etiquetaDoc(d)
  return (
    <li className="flex flex-wrap items-center gap-x-3 gap-y-2 px-4 py-3">
      <FileText className="h-4 w-4 shrink-0 text-slate-300" />
      <div className="min-w-0 flex-1">
        <p className="text-sm font-medium text-slate-800">{etiqueta}</p>
        <p className="text-[11px] text-slate-500">
          {[
            d.numero && `N° ${d.numero}`,
            d.entidad,
            // 2099 es el relleno de «sin fecha» en la base: no es una fecha real.
            d.fecha_emision && d.fecha_emision < '2099' && `Emitido ${formatDate(d.fecha_emision)}`,
            d.estado === 'permanente' ? null
              : d.fecha_vencimiento ? `Vence ${formatDate(d.fecha_vencimiento)}` : null,
          ].filter(Boolean).join(' · ') || '—'}
          {d.dias_restantes != null && d.dias_restantes < 0 && (
            <span className="ml-1 font-semibold text-red-600">({Math.abs(d.dias_restantes)} d. vencido)</span>
          )}
          {d.dias_restantes != null && d.dias_restantes >= 0 && d.estado === 'por_vencer' && (
            <span className="ml-1 font-semibold text-amber-700">(en {d.dias_restantes} d.)</span>
          )}
        </p>
      </div>
      <Chip nivel={ui.nivel}>{ui.label}</Chip>
      {d.archivo_url ? (
        <div className="flex shrink-0 gap-1.5">
          <a href={d.archivo_url} target="_blank" rel="noreferrer"
             onClick={() => onDescarga(`ver: ${etiqueta}`)}
             className="inline-flex items-center gap-1 rounded border border-slate-300 px-2 py-1 text-[11px] font-semibold text-slate-700 hover:bg-slate-50">
            Ver <ExternalLink className="h-3 w-3" />
          </a>
          <a href={urlDescarga(d.archivo_url, nombreArchivo(patente, etiqueta, d.archivo_url))}
             onClick={() => onDescarga(`descargar: ${etiqueta}`)}
             className="inline-flex items-center gap-1 rounded bg-slate-900 px-2 py-1 text-[11px] font-semibold text-white hover:bg-slate-800">
            <Download className="h-3 w-3" /> Descargar
          </a>
        </div>
      ) : (
        <span className="shrink-0 text-[11px] italic text-slate-400">Respaldo en carga</span>
      )}
    </li>
  )
}

function FilaMantencion({ m }: { m: MantencionPortal }) {
  const [abierto, setAbierto] = useState(false)
  const largo = (m.detalle?.length ?? 0) > 220
  return (
    <li className="flex gap-3 px-4 py-3">
      <Wrench className="mt-0.5 h-4 w-4 shrink-0 text-slate-300" />
      <div className="min-w-0 flex-1">
        <p className="text-sm font-medium text-slate-800">
          {m.tipo}
          {m.con_observacion && <span className="ml-2 align-middle"><Chip nivel="amarillo">Con observaciones</Chip></span>}
        </p>
        <p className="text-[11px] text-slate-500">
          {[m.fecha && formatDate(m.fecha), m.folio, m.km ? `${num(m.km)} km` : null, m.horas ? `${num(m.horas)} hrs` : null]
            .filter(Boolean).join(' · ')}
        </p>
        {m.detalle && (
          <p className={cn('mt-1 whitespace-pre-line text-xs leading-relaxed text-slate-600', !abierto && largo && 'line-clamp-3')}>
            {m.detalle}
          </p>
        )}
        {largo && (
          <button onClick={() => setAbierto((v) => !v)}
                  className="mt-1 inline-flex items-center gap-0.5 text-[11px] font-semibold text-slate-500 hover:text-slate-800">
            {abierto ? <ChevronDown className="h-3 w-3" /> : <ChevronRight className="h-3 w-3" />}
            {abierto ? 'Ver menos' : 'Ver detalle completo'}
          </button>
        )}
      </div>
    </li>
  )
}

function FichaEquipo({ ficha, token, onVolver }: { ficha: FichaEquipoPortal; token: string; onVolver: () => void }) {
  const [tab, setTab] = useState<'documentos' | 'mantenciones'>('documentos')
  const [zip, setZip] = useState<{ hechos: number; total: number } | null>(null)
  const [aviso, setAviso] = useState<string | null>(null)
  const eq = ficha.equipo

  const docs = useMemo(
    () => [...ficha.documentos].sort((a, b) =>
      estadoUI(a.estado).orden - estadoUI(b.estado).orden || etiquetaDoc(a).localeCompare(etiquetaDoc(b), 'es')),
    [ficha.documentos],
  )
  const conArchivo = docs.filter((d) => d.archivo_url)
  const registrar = (detalle: string) => registrarDescarga(token, eq.activo_id, detalle)

  const bajarTodo = async () => {
    setAviso(null)
    setZip({ hechos: 0, total: conArchivo.length })
    try {
      const { fallidos } = await descargarZip(
        eq.patente,
        conArchivo.map((d) => ({ etiqueta: etiquetaDoc(d), url: d.archivo_url! })),
        (hechos, total) => setZip({ hechos, total }),
      )
      registrar(`zip: ${conArchivo.length - fallidos.length} documentos`)
      if (fallidos.length) setAviso(`No se pudieron incluir: ${fallidos.join(', ')}. Descárguelos uno a uno.`)
    } catch {
      setAviso('No se pudo armar el ZIP. Descargue los documentos uno a uno.')
    } finally {
      setZip(null)
    }
  }

  const datos: [string, string | null][] = [
    ['Marca / modelo', eq.marca_modelo],
    ['Año', eq.anio ? String(eq.anio) : null],
    ['Tipo', humanizar(eq.tipo)],
    ['Capacidad', eq.capacidad],
    ['VIN / chasis', eq.vin],
    ['N° motor', eq.motor],
    ['Kilometraje', eq.kilometraje ? `${num(eq.kilometraje)} km` : null],
    ['Horómetro', eq.horometro ? `${num(eq.horometro)} hrs` : null],
  ]

  return (
    <div className="space-y-5">
      <button onClick={onVolver}
              className="inline-flex items-center gap-1 text-xs font-semibold text-slate-500 hover:text-slate-800">
        <ArrowLeft className="h-3.5 w-3.5" /> Todos los equipos
      </button>

      <section className="overflow-hidden rounded-xl border border-slate-200 bg-white">
        <header className="flex flex-wrap items-center gap-3 border-b border-slate-100 bg-slate-50/60 px-4 py-4">
          <Truck className="h-6 w-6 shrink-0 text-slate-400" />
          <div className="min-w-0 flex-1">
            <h2 className="font-mono text-xl font-bold tracking-tight text-slate-900">{eq.patente}</h2>
            <p className="truncate text-xs text-slate-500">{eq.nombre ?? eq.codigo}</p>
          </div>
          {ficha.pendientes.length > 0 || docs.some((d) => d.estado === 'vencido')
            ? <Chip nivel="rojo">Documentación pendiente</Chip>
            : <Chip nivel="verde">Documentación al día</Chip>}
        </header>
        <dl className="grid grid-cols-2 gap-x-6 gap-y-3 px-4 py-4 text-xs sm:grid-cols-4">
          {datos.filter(([, v]) => v).map(([k, v]) => (
            <div key={k} className="min-w-0">
              <dt className="text-[10px] font-semibold uppercase tracking-wide text-slate-400">{k}</dt>
              <dd className="break-words text-slate-800">{v}</dd>
            </div>
          ))}
        </dl>
      </section>

      <div className="flex gap-1 rounded-lg bg-slate-200/60 p-1">
        {([
          ['documentos', `Documentación (${docs.length}${ficha.pendientes.length ? ` · ${ficha.pendientes.length} pendiente${ficha.pendientes.length > 1 ? 's' : ''}` : ''})`],
          ['mantenciones', `Mantenciones (${ficha.mantenciones.length})`],
        ] as const).map(([k, t]) => (
          <button key={k} onClick={() => setTab(k)}
                  className={cn('flex-1 rounded-md px-3 py-2 text-xs font-semibold transition',
                    tab === k ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-700')}>
            {t}
          </button>
        ))}
      </div>

      {tab === 'documentos' ? (
        <section className="space-y-3">
          {conArchivo.length > 1 && (
            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="text-[11px] text-slate-500">
                {conArchivo.length} de {docs.length} documentos con respaldo digital.
              </p>
              <button onClick={bajarTodo} disabled={!!zip}
                      className="inline-flex items-center gap-1.5 rounded-lg border border-slate-300 bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 hover:bg-slate-50 disabled:opacity-60">
                {zip
                  ? <><Spinner className="h-3.5 w-3.5" /> Preparando {zip.hechos}/{zip.total}…</>
                  : <><FileArchive className="h-3.5 w-3.5" /> Descargar todo (ZIP)</>}
              </button>
            </div>
          )}
          {aviso && <p className="rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-800">{aviso}</p>}
          {docs.length === 0 && ficha.pendientes.length === 0 ? (
            <p className="rounded-xl border border-dashed border-slate-300 bg-white py-10 text-center text-sm text-slate-400">
              La documentación de este equipo está en proceso de carga.
            </p>
          ) : (
            <ul className="divide-y divide-slate-100 overflow-hidden rounded-xl border border-slate-200 bg-white">
              {ficha.pendientes.map((t) => (
                <li key={`pend-${t}`} className="flex flex-wrap items-center gap-x-3 gap-y-2 bg-red-50/40 px-4 py-3">
                  <FileText className="h-4 w-4 shrink-0 text-red-300" />
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-medium text-slate-800">{TIPO_DOC_LABEL[t] ?? humanizar(t)}</p>
                    <p className="text-[11px] text-slate-500">Documento exigido por el contrato, aún no cargado.</p>
                  </div>
                  <Chip nivel="rojo">Pendiente</Chip>
                </li>
              ))}
              {docs.map((d, i) => <FilaDocumento key={`${d.tipo}-${i}`} d={d} patente={eq.patente} onDescarga={registrar} />)}
            </ul>
          )}
        </section>
      ) : (
        <section>
          {ficha.mantenciones.length === 0 ? (
            <p className="rounded-xl border border-dashed border-slate-300 bg-white py-10 text-center text-sm text-slate-400">
              Este equipo aún no registra mantenciones.
            </p>
          ) : (
            <ol className="divide-y divide-slate-100 overflow-hidden rounded-xl border border-slate-200 bg-white">
              {ficha.mantenciones.map((m, i) => <FilaMantencion key={`${m.folio}-${i}`} m={m} />)}
            </ol>
          )}
        </section>
      )}
    </div>
  )
}

// ── Página ─────────────────────────────────────────────────────────────────
function PortalFlota() {
  const router = useRouter()
  const params = useSearchParams()
  const qc = useQueryClient()
  const equipoId = params.get('equipo')
  const [sesion, setSesion] = useState<SesionPortalFlota | null | undefined>(undefined)
  const [cambiando, setCambiando] = useState(false)

  useEffect(() => { setSesion(leerSesion()) }, [])

  const cerrar = async () => {
    if (sesion) await salir(sesion.token)
    guardarSesion(null)
    qc.removeQueries({ queryKey: ['portal-flota'] })
    setSesion(null)
    router.replace('/portal-flota/')
  }

  const flota = useQuery({
    queryKey: ['portal-flota', 'lista', sesion?.token],
    queryFn: () => cargarFlota(sesion!.token),
    enabled: !!sesion && !sesion.debe_cambiar,
    staleTime: 60_000,
    retry: false,
  })
  const ficha = useQuery({
    queryKey: ['portal-flota', 'ficha', sesion?.token, equipoId],
    queryFn: () => cargarFichaEquipo(sesion!.token, equipoId!),
    enabled: !!sesion && !sesion.debe_cambiar && !!equipoId,
    staleTime: 60_000,
    retry: false,
  })

  // Sesión vencida o cuenta apagada: de vuelta al ingreso, sin pantallas rotas.
  const expirada = esSesionExpirada(flota.error) || esSesionExpirada(ficha.error)
  useEffect(() => {
    if (expirada) { guardarSesion(null); setSesion(null) }
  }, [expirada])

  if (sesion === undefined) {
    return <div className="flex min-h-screen items-center justify-center bg-slate-100"><Spinner className="h-7 w-7" /></div>
  }
  if (!sesion) {
    return <Ingreso onEntrar={(s) => { guardarSesion(s); setSesion(s) }} />
  }
  if (sesion.debe_cambiar || cambiando) {
    return (
      <CambiarPassword
        sesion={sesion}
        obligatorio={sesion.debe_cambiar}
        onListo={() => {
          const s = { ...sesion, debe_cambiar: false }
          guardarSesion(s); setSesion(s); setCambiando(false)
        }}
        onCancelar={sesion.debe_cambiar ? undefined : () => setCambiando(false)}
      />
    )
  }

  const abrir = (id: string) => { router.push(`/portal-flota/?equipo=${id}`); window.scrollTo(0, 0) }
  const volver = () => router.push('/portal-flota/')
  const cargando = equipoId ? ficha.isLoading : flota.isLoading
  const error = (equipoId ? ficha.error : flota.error) as Error | null

  return (
    <div className="min-h-screen bg-slate-100 pb-16">
      <header className="border-b-2 border-slate-800 bg-white">
        <div className="mx-auto flex max-w-4xl flex-wrap items-center gap-3 px-4 py-4 sm:px-6">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/images/logo_empresa_2.png" alt="Pillado Empresas" className="h-9 object-contain" />
          <div className="min-w-0 flex-1">
            <h1 className="text-sm font-bold leading-tight text-slate-900">Portal de Flota</h1>
            <p className="truncate text-[11px] text-slate-500">
              {[sesion.empresa, sesion.nombre].filter(Boolean).join(' · ')}
            </p>
          </div>
          <button onClick={() => setCambiando(true)} title="Cambiar contraseña"
                  className="inline-flex items-center gap-1 rounded-lg px-2 py-1.5 text-[11px] font-semibold text-slate-500 hover:bg-slate-100">
            <KeyRound className="h-3.5 w-3.5" /> <span className="hidden sm:inline">Contraseña</span>
          </button>
          <button onClick={cerrar}
                  className="inline-flex items-center gap-1 rounded-lg border border-slate-300 px-2.5 py-1.5 text-[11px] font-semibold text-slate-600 hover:bg-slate-50">
            <LogOut className="h-3.5 w-3.5" /> Salir
          </button>
        </div>
      </header>

      <main className="mx-auto max-w-4xl px-4 py-6 sm:px-6">
        {cargando ? (
          <div className="flex justify-center py-20"><Spinner className="h-7 w-7" /></div>
        ) : error ? (
          <div className="mx-auto max-w-sm rounded-2xl bg-white px-6 py-8 text-center shadow-sm ring-1 ring-slate-200">
            <Ban className="mx-auto mb-3 h-8 w-8 text-slate-300" />
            <p className="text-sm font-semibold text-slate-800">No se pudo cargar la información</p>
            <p className="mt-1 text-xs text-slate-500">{error.message}</p>
            {equipoId && (
              <button onClick={volver} className="mt-4 inline-flex h-9 items-center rounded-lg bg-slate-900 px-4 text-xs font-semibold text-white">
                Volver a la flota
              </button>
            )}
          </div>
        ) : equipoId && ficha.data ? (
          <FichaEquipo ficha={ficha.data} token={sesion.token} onVolver={volver} />
        ) : flota.data ? (
          <ListaFlota equipos={flota.data.equipos} onAbrir={abrir} />
        ) : null}

        <footer className="mt-10 border-t border-slate-200 pt-4 text-[10px] leading-relaxed text-slate-400">
          Este portal lee en línea el sistema de gestión de Pillado Empresas: refleja el estado de hoy.
          Los documentos «en carga» existen y se están digitalizando; solicite la copia a su ejecutivo si
          la necesita antes. Pillado Empresas · Trayectoria y Compromiso.
        </footer>
      </main>
    </div>
  )
}

export default function PortalFlotaPage() {
  return (
    <Suspense fallback={<div className="flex min-h-screen items-center justify-center bg-slate-100"><Spinner className="h-7 w-7" /></div>}>
      <PortalFlota />
    </Suspense>
  )
}
