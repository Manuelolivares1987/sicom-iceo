'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import {
  Wrench, ChevronRight, ChevronDown, RefreshCw, WifiOff, CloudOff, CheckCircle2, Play, Pause, User, LogOut,
  ArrowLeft, PackageSearch, Download,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useAuth } from '@/contexts/auth-context'
import { MECANICOS } from '@/lib/taller-grupos'
import {
  useMecanicoOTs, usePendingCount, useSyncTaller, useAutoSyncTaller, useNetworkStatus,
  useDescargarOffline,
} from '@/hooks/use-taller-mecanico'
import { useTallerTecnicos } from '@/hooks/use-taller-plan-semanal'
import type { MecanicoOT } from '@/lib/offline/taller-mecanico-sync'

const LS_KEY = 'taller-mecanico'

// Etiqueta de día para agrupar las OTs igual que el plan del jefe de taller
// (Hoy / Mañana / día de la semana + fecha). Recibe 'YYYY-MM-DD'.
function diaLabel(fecha: string | null): string {
  if (!fecha) return 'Sin fecha programada'
  const hoy = new Date(); hoy.setHours(0, 0, 0, 0)
  const [y, m, d] = fecha.split('-').map(Number)
  const f = new Date(y, (m ?? 1) - 1, d ?? 1)
  const diffDias = Math.round((f.getTime() - hoy.getTime()) / 86400000)
  const dow = f.toLocaleDateString('es-CL', { weekday: 'long' })
  const fmt = f.toLocaleDateString('es-CL', { day: 'numeric', month: 'short' })
  const cap = dow.charAt(0).toUpperCase() + dow.slice(1)
  if (diffDias === 0) return `Hoy · ${cap} ${fmt}`
  if (diffDias === 1) return `Mañana · ${cap} ${fmt}`
  if (diffDias === -1) return `Ayer · ${cap} ${fmt}`
  return `${cap} ${fmt}`
}

// Los tres estados que le importan a quien está parado en el taller. El resto
// de la máquina de estados no llega hasta acá: una OT liberada o está andando,
// o está detenida, o no ha partido.
type EstadoFiltro = 'todas' | 'en_ejecucion' | 'pausada' | 'por_iniciar'

function grupoEstado(estado: string): Exclude<EstadoFiltro, 'todas'> {
  if (estado === 'en_ejecucion') return 'en_ejecucion'
  if (estado === 'pausada') return 'pausada'
  return 'por_iniciar'
}

function estadoBadge(estado: string) {
  switch (estado) {
    case 'en_ejecucion': return { cls: 'bg-amber-100 text-amber-800', label: 'En ejecución', icon: Play }
    case 'pausada':      return { cls: 'bg-orange-100 text-orange-800', label: 'Pausada', icon: Pause }
    default:             return { cls: 'bg-blue-100 text-blue-800', label: 'Por iniciar', icon: Wrench }
  }
}

const ESTADOS: { key: EstadoFiltro; label: string }[] = [
  { key: 'todas', label: 'Todas' },
  { key: 'en_ejecucion', label: 'En ejecución' },
  { key: 'pausada', label: 'Pausadas' },
  { key: 'por_iniciar', label: 'Por iniciar' },
]

/**
 * ¿Esta OT lleva el nombre de este mecánico en la cuadrilla?
 *
 * Va aparte de `esMia` a propósito: para contar cuántas OTs trae CADA nombre
 * no sirve mirar `asignada_a_mi` —esa es de la cuenta que abrió sesión, y le
 * sumaría las mismas OTs a los diez mecánicos de la lista—.
 */
function nombreCoincide(nombre: string, o: MecanicoOT): boolean {
  const n = nombre.trim().toLowerCase()
  if (!n) return false
  const primer = n.split(/\s+/)[0] ?? ''
  const c = (o.cuadrilla ?? '').toLowerCase()
  return c.includes(n) || (primer.length >= 3 && c.includes(primer))
}

export default function MecanicoHomePage() {
  useAutoSyncTaller()
  const online = useNetworkStatus()
  const router = useRouter()
  const { perfil, signOut } = useAuth()
  const { data: ots, isLoading, refetch, isFetching } = useMecanicoOTs()
  const { data: pendientes = 0 } = usePendingCount()
  const sync = useSyncTaller()
  const descargar = useDescargarOffline()
  const [descargaMsg, setDescargaMsg] = useState<string>('')

  // La cuenta operador_taller es COMPARTIDA por los mecánicos: ve TODAS las
  // OTs liberadas (MIG193) y cada uno elige su nombre del catálogo de técnicos
  // para filtrar/destacar las suyas (nombre en la cuadrilla del plan).
  const esOperador = perfil?.rol === 'operador_taller'
  const [soloMias, setSoloMias] = useState(false)
  const [estadoFiltro, setEstadoFiltro] = useState<EstadoFiltro>('todas')
  const { data: tecnicosCat } = useTallerTecnicos(null)

  const [mecanico, setMecanico] = useState<string>('')
  useEffect(() => {
    const saved = typeof window !== 'undefined' ? localStorage.getItem(LS_KEY) : null
    if (saved) setMecanico(saved)
  }, [])

  // Los diez nombres ocupaban tres filas encima de la lista: en un teléfono el
  // trabajo del día empezaba recién a media pantalla. Ahora el picker se abre
  // cuando se necesita — y para el operador que todavía no dice quién es, se
  // abre solo, porque ese es su primer paso.
  const [pickerAbierto, setPickerAbierto] = useState(false)
  useEffect(() => {
    if (esOperador && !mecanico) setPickerAbierto(true)
  }, [esOperador, mecanico])

  function elegir(m: string) {
    // Volver a tocar el nombre elegido lo suelta. Antes no había forma de
    // deshacer la elección: quedaba pegada en localStorage para siempre.
    const nuevo = m === mecanico ? '' : m
    setMecanico(nuevo)
    if (nuevo === '') setSoloMias(false)
    if (typeof window !== 'undefined') localStorage.setItem(LS_KEY, nuevo)
  }

  async function salir() {
    try { await signOut() } catch { /* noop */ }
    router.replace('/login')
  }

  // Nombres del selector "Soy:" del operador (catálogo real; MECANICOS de respaldo).
  const nombresPicker = useMemo(() => {
    const cat = (tecnicosCat ?? []).filter((t) => t.activo).map((t) => t.nombre)
    return cat.length > 0 ? cat : [...MECANICOS]
  }, [tecnicosCat])

  // ¿La OT es del mecánico elegido? Nombre completo o primer nombre en la
  // cuadrilla (planes antiguos usan nombres cortos), o asignación por cuenta.
  const esMia = useMemo(() => {
    return (o: MecanicoOT): boolean => {
      if (o.asignada_a_mi) return true
      return nombreCoincide(mecanico, o)
    }
  }, [mecanico])

  const todas = useMemo(() => ots ?? [], [ots])
  const conMiNombre = useMemo(() => todas.filter(esMia).length, [todas, esMia])

  // Cuánto trabajo trae cada mecánico. Sin esto el picker eran diez botones
  // mudos: había que apretarlos uno por uno para descubrir quién tenía OTs.
  const conteoPorMecanico = useMemo(() => {
    const m: Record<string, number> = {}
    for (const n of nombresPicker) m[n] = todas.filter((o) => nombreCoincide(n, o)).length
    return m
  }, [nombresPicker, todas])

  // El mecánico es el filtro grueso; el estado, el fino. Por eso los contadores
  // de estado se calculan sobre lo que ya dejó pasar el mecánico.
  const porMecanico = useMemo(
    () => (soloMias && mecanico ? todas.filter(esMia) : todas),
    [todas, soloMias, mecanico, esMia]
  )

  const conteoPorEstado = useMemo(() => {
    const c: Record<EstadoFiltro, number> = { todas: porMecanico.length, en_ejecucion: 0, pausada: 0, por_iniciar: 0 }
    for (const o of porMecanico) c[grupoEstado(o.ot_estado)] += 1
    return c
  }, [porMecanico])

  // Todos ven TODAS las OTs liberadas; el nombre sólo ordena y filtra.
  //
  // Antes, un perfil que no fuera operador_taller caía en `if (!mecanico)
  // return []` y veía la pantalla vacía: el jefe y el administrador no tenían
  // forma de mirar la ejecución del personal, ni siquiera entrando a la URL.
  // Además el filtro era por `cuadrilla`, así que las OTs sin cuadrilla
  // asignada eran invisibles para cualquier nombre que se eligiera.
  const misOts = useMemo(() => {
    const list = estadoFiltro === 'todas'
      ? porMecanico
      : porMecanico.filter((o) => grupoEstado(o.ot_estado) === estadoFiltro)
    if (soloMias) return list
    // Todas, pero las del mecánico elegido primero.
    return [...list].sort((a, b) => Number(esMia(b)) - Number(esMia(a)))
  }, [porMecanico, estadoFiltro, soloMias, esMia])

  // Agrupar por día (fecha_programada), igual que el plan del jefe de taller.
  // Los días ordenados cronológicamente; "sin fecha" al final. Dentro de cada
  // día se conserva el orden de misOts (las del mecánico primero).
  const gruposPorDia = useMemo(() => {
    const m = new Map<string, MecanicoOT[]>()
    for (const o of misOts) {
      const k = o.fecha_programada ?? ''
      const arr = m.get(k) ?? []
      arr.push(o)
      m.set(k, arr)
    }
    // [26-08] Antes se ordenaba puro cronológico, así que arriba de todo
    // quedaban las OT de julio que siguen «Por iniciar» —seis semanas
    // atrasadas— y el trabajo de hoy había que ir a buscarlo abajo, después de
    // ocho grupos. El mecánico abre su lista para ver qué le toca HOY.
    //
    // Orden: hoy · atrasadas (de la más vieja) · lo que viene · sin fecha.
    const hoyISO = (() => {
      const d = new Date()
      return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
    })()
    const rango = (f: string) => (f === hoyISO ? 0 : f < hoyISO ? 1 : 2)
    return Array.from(m.entries())
      .sort(([a], [b]) => {
        if (!a) return 1        // sin fecha al final
        if (!b) return -1
        const ra = rango(a), rb = rango(b)
        if (ra !== rb) return ra - rb
        // Dentro de las atrasadas, primero la que lleva más tiempo esperando.
        return a.localeCompare(b)
      })
      .map(([fecha, items]) => ({
        fecha: fecha || null,
        label: diaLabel(fecha || null),
        atrasado: !!fecha && fecha < hoyISO,
        diasAtraso: fecha && fecha < hoyISO
          ? Math.round((new Date(hoyISO).getTime() - new Date(fecha).getTime()) / 86400000)
          : 0,
        items,
      }))
  }, [misOts])

  // Días plegados (colapsables). Por defecto todos desplegados; el operador
  // pliega los que no le interesan para ver mejor los del día.
  const [diasPlegados, setDiasPlegados] = useState<Set<string>>(new Set())
  function toggleDia(clave: string) {
    setDiasPlegados((prev) => {
      const next = new Set(prev)
      if (next.has(clave)) next.delete(clave)
      else next.add(clave)
      return next
    })
  }

  const chip = (activo: boolean) =>
    `rounded-full border px-2.5 py-1 text-xs transition ${
      activo ? 'border-orange-600 bg-orange-600 font-medium text-white'
             : 'border-gray-300 bg-white text-gray-700 active:bg-gray-100'}`

  const puedeDescargar = (esOperador || mecanico) && misOts.length > 0 && online

  return (
    <div className="p-3 space-y-3">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-orange-600 text-white">
            <Wrench className="h-5 w-5" />
          </div>
          <div>
            <h1 className="text-base font-bold text-gray-900 leading-tight">Taller — Mecánico</h1>
            <p className="text-[11px] text-gray-500">
              {esOperador ? (mecanico || 'Elige tu nombre') : 'Supervisión de ejecución'}
            </p>
          </div>
        </div>
        {esOperador ? (
          <button onClick={salir} aria-label="Cerrar sesión" className="text-gray-400 hover:text-gray-600">
            <LogOut className="h-5 w-5" />
          </button>
        ) : (
          <Link href="/dashboard" aria-label="Volver al panel" title="Volver al panel"
                className="text-gray-400 hover:text-gray-600"><ArrowLeft className="h-5 w-5" /></Link>
        )}
      </div>

      {/* Una sola barra para todo lo que es estado de la app —conexión, lo que
          falta subir, la descarga offline—. Antes eran tres bloques apilados
          entre el encabezado y el trabajo. */}
      <div className={`flex flex-wrap items-center gap-x-2 gap-y-1.5 rounded-lg border p-2 text-xs ${
        online ? 'border-green-200 bg-green-50 text-green-700' : 'border-amber-300 bg-amber-50 text-amber-800'}`}>
        {online ? <CheckCircle2 className="h-4 w-4 shrink-0" /> : <WifiOff className="h-4 w-4 shrink-0" />}
        <span className="font-medium">{online ? 'En línea' : 'Sin conexión — se guardará local'}</span>
        {pendientes > 0 && (
          <span className="flex items-center gap-1">
            <CloudOff className="h-3.5 w-3.5" /> {pendientes} por sincronizar
          </span>
        )}
        <div className="ml-auto flex items-center gap-1.5">
          {online && pendientes > 0 && (
            <button onClick={() => sync.mutate()} disabled={sync.isPending}
                    className="rounded-md border border-green-300 bg-white px-2 py-1 text-green-700 disabled:opacity-50">
              {sync.isPending ? 'Sincronizando…' : 'Sincronizar'}
            </button>
          )}
          {puedeDescargar && (
            <button
              onClick={() => descargar.mutate(misOts.map((o) => o.ot_id), {
                onSuccess: (n) => setDescargaMsg(`${n} OTs guardadas en el teléfono`),
              })}
              disabled={descargar.isPending}
              className="flex items-center gap-1 rounded-md border border-orange-300 bg-white px-2 py-1 font-medium text-orange-700 disabled:opacity-50">
              {descargar.isPending ? <Spinner className="h-3.5 w-3.5" /> : <Download className="h-3.5 w-3.5" />}
              Guardar sin internet
            </button>
          )}
        </div>
      </div>
      {descargaMsg && <p className="text-center text-xs text-green-600">{descargaMsg}</p>}

      {/* [MIG386] Lo del taller que no es de ningún equipo. Vive fuera de las OT
          a propósito: quien busca guantes no está buscando una orden. */}
      <Link href="/m/taller/insumos"
            className="flex items-center gap-2 rounded-lg border border-gray-300 bg-white px-3 py-2 active:bg-gray-50">
        <PackageSearch className="h-4 w-4 shrink-0 text-gray-600" />
        <span className="text-sm font-semibold text-gray-900">Pedir insumos</span>
        <span className="truncate text-[11px] text-gray-500">guantes, trapos, discos</span>
        <ChevronRight className="ml-auto h-4 w-4 shrink-0 text-gray-400" />
      </Link>

      {/* ── Filtros ──────────────────────────────────────────────────────────
          Antes el único filtro era «Todas / Del mecánico elegido», y con nadie
          elegido decía «(0)»: se leía como que no había trabajo. Lo que se mira
          de verdad al llegar al taller es qué está andando y qué no ha partido.
      */}
      <div className="space-y-2">
        <div className="flex flex-wrap gap-1.5">
          {ESTADOS.map((e) => (
            <button key={e.key} onClick={() => setEstadoFiltro(e.key)} className={chip(estadoFiltro === e.key)}>
              {e.label}{' '}
              <span className={estadoFiltro === e.key ? 'text-white/80' : 'text-gray-400'}>
                {conteoPorEstado[e.key]}
              </span>
            </button>
          ))}
        </div>

        <div className="flex flex-wrap items-center gap-1.5">
          <button onClick={() => setPickerAbierto((v) => !v)}
                  aria-expanded={pickerAbierto}
                  className="flex items-center gap-1 rounded-full border border-gray-300 bg-white px-2.5 py-1 text-xs text-gray-700 active:bg-gray-100">
            <User className="h-3.5 w-3.5 text-gray-400" />
            {esOperador ? 'Soy:' : 'Mecánico:'}
            <span className="font-medium text-gray-900">{mecanico || 'todos'}</span>
            <ChevronDown className={`h-3.5 w-3.5 text-gray-400 transition-transform ${pickerAbierto ? '' : '-rotate-90'}`} />
          </button>

          {/* Sólo tiene sentido preguntar «todas o las suyas» cuando ya hay un
              «suyas». Con nadie elegido, este par de botones era ruido. */}
          {mecanico && (
            <div className="flex gap-1.5">
              <button onClick={() => setSoloMias(false)} className={chip(!soloMias)}>Todas</button>
              <button onClick={() => setSoloMias(true)} className={chip(soloMias)}>
                {esOperador ? 'Sólo las mías' : `Sólo ${mecanico.split(' ')[0]}`}{' '}
                <span className={soloMias ? 'text-white/80' : 'text-gray-400'}>{conMiNombre}</span>
              </button>
            </div>
          )}
        </div>

        {pickerAbierto && (
          <div className="flex flex-wrap gap-1.5 rounded-lg border border-gray-200 bg-white p-2">
            {nombresPicker.map((m) => {
              const n = conteoPorMecanico[m] ?? 0
              return (
                <button key={m} onClick={() => elegir(m)}
                        className={`rounded-full border px-2.5 py-1 text-xs transition ${
                          mecanico === m ? 'border-orange-600 bg-orange-600 font-medium text-white'
                          : n === 0 ? 'border-gray-200 bg-gray-50 text-gray-400'
                                    : 'border-gray-300 bg-white text-gray-700 active:bg-gray-100'}`}>
                  {m} <span className={mecanico === m ? 'text-white/80' : 'text-gray-400'}>{n}</span>
                </button>
              )
            })}
            <p className="w-full pt-1 text-[10px] text-gray-400">
              El número es cuántas OTs liberadas trae ese nombre en la cuadrilla. Tócalo de nuevo para soltarlo.
            </p>
          </div>
        )}
      </div>

      {/* Lista */}
      <div className="flex items-center justify-between pt-1">
        <h2 className="text-sm font-semibold text-gray-700">
          {soloMias && mecanico
            ? (esOperador ? 'OTs con mi nombre' : `OTs de ${mecanico}`)
            : 'OTs liberadas a ejecución'}
          <span className="ml-1.5 font-normal text-gray-400">{misOts.length}</span>
        </h2>
        <button onClick={() => refetch()} aria-label="Actualizar"
                className="text-gray-400 hover:text-gray-600" disabled={isFetching}>
          <RefreshCw className={`h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} />
        </button>
      </div>

      {isLoading ? (
        <div className="flex justify-center py-8"><Spinner /></div>
      ) : misOts.length === 0 ? (
        <div className="py-8 text-center text-sm text-gray-400">
          {/* El vacío tiene que decir cuál de los filtros lo dejó vacío, y
              ofrecer soltarlo. Antes decía «no hay OTs» y punto. */}
          {estadoFiltro !== 'todas' ? (
            <>
              <p>
                No hay OTs «{ESTADOS.find((e) => e.key === estadoFiltro)?.label.toLowerCase()}»
                {soloMias && mecanico ? ` de ${mecanico}` : ''}.
              </p>
              <button onClick={() => setEstadoFiltro('todas')} className="mt-2 text-xs font-medium text-orange-600 underline">
                Ver todos los estados
              </button>
            </>
          ) : soloMias && mecanico ? (
            <>
              <p>Ninguna OT liberada trae el nombre de {mecanico}.</p>
              <button onClick={() => setSoloMias(false)} className="mt-2 text-xs font-medium text-orange-600 underline">
                Ver todas
              </button>
            </>
          ) : (
            <p>No hay OTs liberadas a ejecución. Libéralas desde el Plan Taller.</p>
          )}
        </div>
      ) : (
        <div className="space-y-4">
          {gruposPorDia.map((grupo) => {
            const clave = grupo.fecha ?? 'sin-fecha'
            const plegado = diasPlegados.has(clave)
            return (
            <div key={clave} className="space-y-2">
              {/* Encabezado del día — pulsable para plegar/desplegar */}
              <button
                type="button"
                onClick={() => toggleDia(clave)}
                aria-expanded={!plegado}
                className={`sticky top-0 z-10 flex w-full items-center gap-2 rounded-lg px-2.5 py-2 ${
                  grupo.atrasado ? 'bg-red-100 active:bg-red-200' : 'bg-gray-100 active:bg-gray-200'}`}>
                <ChevronDown className={`h-4 w-4 transition-transform ${plegado ? '-rotate-90' : ''} ${
                  grupo.atrasado ? 'text-red-600' : 'text-gray-500'}`} />
                <span className={`text-xs font-semibold ${grupo.atrasado ? 'text-red-800' : 'text-gray-700'}`}>
                  {grupo.label}
                </span>
                {/* Que el atraso se vea, y cuánto. Antes una OT de hace seis
                    semanas se veía igual que la de hoy. */}
                {grupo.atrasado && (
                  <span className="rounded-full bg-red-600 px-1.5 py-0.5 text-[10px] font-bold text-white">
                    {grupo.diasAtraso} día{grupo.diasAtraso !== 1 ? 's' : ''} de atraso
                  </span>
                )}
                <span className="ml-auto rounded-full bg-white px-2 py-0.5 text-[10px] font-medium text-gray-500">
                  {grupo.items.length} OT{grupo.items.length !== 1 ? 's' : ''}
                </span>
              </button>
              {!plegado && grupo.items.map((o) => {
                const b = estadoBadge(o.ot_estado)
                const Icon = b.icon
                const total = o.checklist_total ?? 0
                const hechos = o.checklist_completados ?? 0
                // El destacado NO depende del rol. Estaba detrás de
                // `esOperador`, así que el jefe y el administrador elegían un
                // nombre y no se marcaba nada: el filtro parecía roto porque su
                // único efecto era invisible. Con «sólo las suyas» activo sobra,
                // que ahí todas lo son.
                const destacada = !!mecanico && !soloMias && esMia(o)
                return (
                  <Link key={o.ot_id} href={`/m/taller/ot/${o.ot_id}`}
                        className={`block rounded-xl border bg-white p-3 active:bg-gray-50 ${
                          destacada ? 'border-orange-400 ring-1 ring-orange-200' : 'border-gray-200'}`}>
                    <div className="flex items-center gap-2">
                      <span className="font-mono text-xs font-bold text-gray-900">{o.ot_folio}</span>
                      {destacada && (
                        <span className="rounded-full bg-orange-100 px-2 py-0.5 text-[10px] font-medium text-orange-700">
                          ★ {esOperador ? 'Mi nombre' : mecanico.split(' ')[0]}
                        </span>
                      )}
                      <span className={`ml-auto flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-medium ${b.cls}`}>
                        <Icon className="h-3 w-3" /> {b.label}
                      </span>
                    </div>
                    <div className="mt-1 text-sm font-medium text-gray-800">
                      {o.activo_codigo} {o.activo_patente && <span className="text-gray-500">· {o.activo_patente}</span>}
                    </div>
                    <div className="text-xs text-gray-500">{o.activo_nombre}</div>
                    {/* Quién la tiene. Estaba en los datos y no se mostraba: para
                        supervisar había que abrir la OT una por una. */}
                    {o.cuadrilla && (
                      <div className="mt-1 truncate text-[11px] text-gray-500">
                        <User className="mr-1 inline h-3 w-3 text-gray-400" />{o.cuadrilla}
                      </div>
                    )}
                    <div className="mt-2 flex items-center justify-between">
                      <div className="text-[11px] text-gray-500">
                        {hechos}/{total} tareas · {Math.round(((o.tiempo_estimado_total_min ?? 0) / 60) * 10) / 10} h
                      </div>
                      <ChevronRight className="h-4 w-4 text-gray-400" />
                    </div>
                    {total > 0 && (
                      <div className="mt-1.5 h-1.5 w-full rounded-full bg-gray-100">
                        <div className="h-1.5 rounded-full bg-orange-500"
                             style={{ width: `${Math.min(100, Math.round((hechos / total) * 100))}%` }} />
                      </div>
                    )}
                  </Link>
                )
              })}
            </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
