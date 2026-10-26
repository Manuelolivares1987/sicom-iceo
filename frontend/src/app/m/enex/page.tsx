'use client'

// Terreno ENEX — lista de instalaciones programadas por período (MIG208).
// El mantenedor elige una y ejecuta su pauta.

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import {
  Building2, ChevronRight, ChevronLeft, CheckCircle2, Clock, RefreshCw, AlertTriangle,
  WifiOff, CloudOff, Fuel, Droplets, Repeat, Check, CalendarDays, Sun,
  ClipboardList, Shuffle, Ban,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import {
  MESES, TIPO_INSTALACION_LABEL, MUNDO_LABEL, mundoDeLinea,
  type Mundo, type EnexPendiente, type EnexPlanTarea,
} from '@/lib/services/enex'
import { getPendientesOffline, prepararEnexOffline, getEnexPendingCount, ultimaDescargaEnex, getPlanDiaOffline, getZonasDia } from '@/lib/offline/enex-offline'
import { CambioPrograma } from '@/components/enex/cambio-programa'
import { useNetworkStatus } from '@/hooks/use-calama-offline'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { useAuth } from '@/contexts/auth-context'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { BandejaPorEnviar } from '@/components/enex/bandeja-por-enviar'
import { ListoSinSenal } from '@/components/enex/listo-sin-senal'

const MUNDO_KEY = 'enex-mundo-supervisor'

const hoy = () => { const d = new Date(); return { anio: d.getFullYear(), mes: d.getMonth() + 1 } }
const hoyISOf = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}` }

const DIAS_SEMANA = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado']
// "Lunes 21 de julio" a partir de un YYYY-MM-DD (sin desfase de zona horaria).
function fmtDiaLargo(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number)
  const dt = new Date(y, m - 1, d)
  return `${DIAS_SEMANA[dt.getDay()]} ${d} de ${MESES[m - 1].toLowerCase()}`
}

export default function EnexTerrenoHome() {
  // El link de terreno se reparte tal cual: si no hay sesión, al login y de
  // vuelta acá.
  const { verificando, sinSesionOffline } = useExigirSesion()
  // El período parte NULL y se fija tras el mount: la página se prerenderiza
  // en el build y usar new Date() en el primer render hidrata mal (React #418)
  // cuando la fecha del build difiere de la del teléfono.
  const [periodo, setPeriodo] = useState<{ anio: number; mes: number } | null>(null)
  const [hoyISO, setHoyISO] = useState<string>('')
  // Vista por día: "hoy" (por defecto, lo del día) o "mes" (agenda completa).
  const [vista, setVista] = useState<'hoy' | 'mes'>('hoy')
  useEffect(() => { setPeriodo(hoy()); setHoyISO(hoyISOf()) }, [])
  const anio = periodo?.anio ?? 0
  const mes = periodo?.mes ?? 1
  const online = useNetworkStatus()
  const [descargaMsg, setDescargaMsg] = useState('')

  // Mundo del supervisor (combustible / lubricantes). [MIG648] Lo fija la
  // cuenta: cada supervisor entra directo a lo suyo. Si un día cubre el otro
  // mundo y lo cambia a mano, el cambio vale solo ese día; al siguiente vuelve
  // a lo de su cuenta.
  const { perfil } = useAuth()
  const mundoCuenta = perfil?.enex_mundo ?? null
  const [mundo, setMundo] = useState<Mundo | null>(null)
  useEffect(() => {
    let elegido: { m?: string; dia?: string } = {}
    try { elegido = JSON.parse(localStorage.getItem(MUNDO_KEY) ?? '{}') ?? {} } catch {
      // Valor de antes de MIG648: texto plano, sin día.
      const viejo = typeof localStorage !== 'undefined' ? localStorage.getItem(MUNDO_KEY) : null
      elegido = { m: viejo ?? undefined }
    }
    const valido = (x?: string | null): x is Mundo => x === 'combustible' || x === 'lubricante'
    if (valido(elegido.m) && elegido.dia === hoyISOf()) setMundo(elegido.m)
    else if (valido(mundoCuenta)) setMundo(mundoCuenta)
    else setMundo(valido(elegido.m) ? elegido.m : 'combustible')
  }, [mundoCuenta])
  function elegirMundo(m: Mundo) {
    setMundo(m)
    try { localStorage.setItem(MUNDO_KEY, JSON.stringify({ m, dia: hoyISOf() })) } catch { /* no-op */ }
  }

  const { data: pend = [], isLoading, refetch, isFetching } = useQuery({
    queryKey: ['enex-terreno', anio, mes], queryFn: () => getPendientesOffline(anio, mes),
    networkMode: 'always', staleTime: 10_000, enabled: periodo !== null,
  })

  // [MIG265] Descarga automática del mes para trabajar sin señal. Antes corría
  // una sola vez por sesión y solo si ya había pendientes cargados: si el
  // mantenedor abría la app y perdía señal enseguida, se quedaba sin nada.
  // Ahora baja al abrir, al recuperar conexión y cada 10 minutos mientras esté
  // en línea. Incluye las pautas y lo ya ejecutado de cada servicio.
  const bajando = useRef(false)
  const bajar = useCallback(async (forzado: boolean) => {
    if (!periodo || bajando.current) return
    if (typeof navigator !== 'undefined' && !navigator.onLine) return
    const ultima = await ultimaDescargaEnex(anio, mes)
    const vieja = !ultima || Date.now() - new Date(ultima).getTime() > 10 * 60 * 1000
    if (!forzado && !vieja) {
      setDescargaMsg(`listo para trabajar sin señal · ${new Date(ultima!).toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit' })}`)
      return
    }
    bajando.current = true
    try {
      const n = await prepararEnexOffline(anio, mes)
      setDescargaMsg(`${n} servicios disponibles sin internet · ${new Date().toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit' })}`)
    } catch { /* si falla, queda el botón manual */ } finally { bajando.current = false }
  }, [periodo, anio, mes])

  useEffect(() => {
    if (!periodo) return
    void bajar(false)
    const t = setInterval(() => void bajar(false), 10 * 60 * 1000)
    const onOnline = () => void bajar(true)
    window.addEventListener('online', onOnline)
    return () => { clearInterval(t); window.removeEventListener('online', onOnline) }
  }, [periodo, bajar, online])
  const { data: pendientesSync = 0 } = useQuery({
    queryKey: ['enex-pending-count'], queryFn: getEnexPendingCount, networkMode: 'always', refetchInterval: 4000,
  })

  // [MIG274] Plan del día: qué actividades tocan hoy y en qué área. Queda
  // guardado en el teléfono (hoy y los dos días siguientes) para verlo sin señal.
  const { data: planHoy = [] } = useQuery({
    queryKey: ['enex-plan-dia', hoyISO], queryFn: () => getPlanDiaOffline(hoyISO),
    enabled: !!hoyISO, staleTime: 60_000, retry: false, networkMode: 'always',
  })

  // [MIG651] Cambio de programa en terreno (pedido de ESM).
  const [cambioAbierto, setCambioAbierto] = useState(false)
  const { data: zonasDia = [] } = useQuery({
    queryKey: ['enex-zonas-dia', hoyISO], queryFn: () => getZonasDia(hoyISO),
    enabled: !!hoyISO, networkMode: 'always',
  })

  // El envío de lo pendiente lo hace <EnexSyncAgent /> en el layout: corre en
  // las dos pantallas, cada minuto y al volver a la app.

  function cambiarMes(d: number) {
    let m = mes + d, a = anio
    if (m < 1) { m = 12; a-- } else if (m > 12) { m = 1; a++ }
    setPeriodo({ anio: a, mes: m })
  }

  // Filtro por mundo del supervisor (combustible = EESS/petrolera/semimóvil/
  // camión; lubricante = truck shops).
  const pendMundo = useMemo(
    () => (mundo ? pend.filter((p) => mundoDeLinea(p.linea) === mundo) : pend),
    [pend, mundo])

  // Agrupar por DÍA de visita (fecha programada). Los sin fecha van al final.
  const porDia = useMemo(() => {
    const map = new Map<string, EnexPendiente[]>()
    for (const p of pendMundo) {
      const key = p.fecha_programada ? p.fecha_programada.slice(0, 10) : 'sin'
      if (!map.has(key)) map.set(key, [])
      map.get(key)!.push(p)
    }
    return Array.from(map.entries())
      .map(([fecha, items]) => ({ fecha, items: items.sort((a, b) => Number(a.cumplida) - Number(b.cumplida)) }))
      .sort((a, b) => (a.fecha === 'sin' ? '9999-99-99' : a.fecha).localeCompare(b.fecha === 'sin' ? '9999-99-99' : b.fecha))
  }, [pendMundo])

  // Según la vista: solo hoy, o toda la agenda del mes.
  const diasVisibles = useMemo(
    () => (vista === 'hoy' ? porDia.filter((d) => d.fecha === hoyISO) : porDia),
    [porDia, vista, hoyISO])

  // El plan del día agrupado por área, con el punto y los códigos que tocan.
  // Cada grupo apunta al servicio del punto para poder ejecutarlo de una.
  // [MIG651] Agrupado por área + zona (Lomas: Instalaciones exteriores · Sala
  // de microfiltrado · Racks). Una zona con varios puntos (los racks) muestra
  // la lista de actividades una vez y un botón por punto.
  const planPorArea = useMemo(() => {
    const grupos: { clave: string; area: string; zona: string | null; tareas: EnexPlanTarea[] }[] = []
    for (const t of planHoy) {
      const clave = `${t.area ?? ''}|${t.alcance ?? t.instalacion_id ?? ''}`
      let g = grupos.find((x) => x.clave === clave)
      if (!g) { g = { clave, area: t.area || t.instalacion || 'Sin área', zona: t.alcance, tareas: [] }; grupos.push(g) }
      g.tareas.push(t)
    }
    return grupos.map((g) => {
      // Los puntos que fijó el plan; si no fijó ninguno, los del área que estén
      // programados este período (el técnico elige en cuál trabaja).
      const instIds = Array.from(new Set(g.tareas.map((t) => t.instalacion_id).filter(Boolean) as string[]))
      const candidatos = instIds.length > 0
        ? pend.filter((p) => instIds.includes(p.instalacion_id) && p.tipo_servicio === 'mantencion')
        : pend.filter((p) => p.tipo_servicio === 'mantencion' &&
            g.tareas.some((t) => t.area && p.instalacion.toLowerCase().includes(t.area.toLowerCase().replace('truck shop ', ''))))
      // Una actividad por código (el plan la repite en cada rack).
      const tareas = g.tareas.filter((t, i, arr) => arr.findIndex((x) => x.codigo_item === t.codigo_item) === i)
      const codigos = Array.from(new Set(g.tareas.map((t) => t.codigo_item).filter(Boolean) as string[]))
      const noSeHizo = zonasDia.find((z) => !z.hacer && z.area === g.area && z.lugar === g.zona) ?? null
      return { ...g, tareas, candidatos, codigos, noSeHizo }
    })
  }, [planHoy, pend, zonasDia])
  // Zonas hechas hoy por cambio de programa (no estaban en el plan).
  const zonasExtra = useMemo(
    () => zonasDia.filter((z) => z.hacer && !planPorArea.some((g) => g.area === z.area && g.zona === z.lugar)),
    [zonasDia, planPorArea])

  const pendHoy = useMemo(
    () => pendMundo.filter((p) => !p.cumplida && !p.por_reprogramar_motivo && p.fecha_programada?.slice(0, 10) === hoyISO).length,
    [pendMundo, hoyISO])
  const pendMes = pendMundo.filter((p) => !p.cumplida && !p.por_reprogramar_motivo).length
  // Lo de hoy en el OTRO mundo: con el selector recordado del día anterior se
  // veía «No tienes tareas para hoy» teniendo trabajo al lado.
  const otroMundo: Mundo = mundo === 'lubricante' ? 'combustible' : 'lubricante'
  const pendHoyOtro = useMemo(
    () => pend.filter((p) => mundoDeLinea(p.linea) === otroMundo && !p.cumplida &&
                            p.fecha_programada?.slice(0, 10) === hoyISO).length,
    [pend, otroMundo, hoyISO])
  const conteoMundo = useMemo(() => ({
    combustible: pend.filter((p) => mundoDeLinea(p.linea) === 'combustible' && !p.cumplida).length,
    lubricante: pend.filter((p) => mundoDeLinea(p.linea) === 'lubricante' && !p.cumplida).length,
  }), [pend])

  // Primer render (SSR/hidratación) sin fecha: contenido determinista.
  if (sinSesionOffline) return <SinSesionOffline />
  if (verificando) return <div className="flex justify-center py-10"><Spinner /></div>
  if (!periodo) return <div className="flex justify-center py-10"><Spinner /></div>

  return (
    <div className="p-3 space-y-3">
      <div className="flex items-center gap-2">
        <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-blue-700 text-white"><Building2 className="h-5 w-5" /></div>
        <div className="flex-1">
          <h1 className="text-base font-bold leading-tight">Terreno ENEX</h1>
          <p className="text-[11px] text-gray-500">Mantención y calibración de instalaciones</p>
        </div>
        <button onClick={() => refetch()} className="text-gray-400"><RefreshCw className={`h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} /></button>
      </div>

      {/* Selector de mundo del supervisor (combustible / lubricantes) */}
      <div className="grid grid-cols-2 gap-2">
        {(['combustible', 'lubricante'] as Mundo[]).map((m) => {
          const activo = mundo === m
          const Icon = m === 'combustible' ? Fuel : Droplets
          const color = m === 'combustible' ? 'blue' : 'emerald'
          return (
            <button key={m} onClick={() => elegirMundo(m)}
              className={`relative flex items-center gap-2 rounded-xl border-2 p-2.5 text-left transition
                ${activo
                  ? m === 'combustible' ? 'border-blue-500 bg-blue-50' : 'border-emerald-500 bg-emerald-50'
                  : 'border-gray-200 bg-white'}`}>
              <div className={`flex h-8 w-8 items-center justify-center rounded-lg text-white
                ${m === 'combustible' ? 'bg-blue-600' : 'bg-emerald-600'}`}>
                <Icon className="h-4 w-4" />
              </div>
              <div className="flex-1">
                <p className={`text-sm font-bold ${activo ? (m === 'combustible' ? 'text-blue-800' : 'text-emerald-800') : 'text-gray-700'}`}>
                  {MUNDO_LABEL[m]}
                </p>
                <p className="text-[10px] text-gray-500">{conteoMundo[m]} por ejecutar</p>
              </div>
              {activo && <Check className={`h-4 w-4 ${m === 'combustible' ? 'text-blue-600' : 'text-emerald-600'}`} />}
            </button>
          )
        })}
      </div>

      {/* Estado de conexión / cola */}
      <div className={`flex items-center gap-2 rounded-lg border p-2 text-xs ${online ? 'border-green-200 bg-green-50 text-green-700' : 'border-amber-300 bg-amber-50 text-amber-800'}`}>
        {online ? <CheckCircle2 className="h-3.5 w-3.5" /> : <WifiOff className="h-3.5 w-3.5" />}
        <span className="font-medium">{online ? 'En línea' : 'Sin conexión — se guarda local'}</span>
        {pendientesSync > 0 && <span className="ml-auto flex items-center gap-1"><CloudOff className="h-3 w-3" /> {pendientesSync} por sincronizar</span>}
      </div>
      {/* La descarga para trabajar sin señal es automática (al abrir, cada 10
          minutos y al volver la red): el botón «Descargar el mes» sobraba. */}
      {descargaMsg && <p className="text-center text-[11px] text-green-600">{descargaMsg}</p>}

      {pendientesSync > 0 && <BandejaPorEnviar />}
      <ListoSinSenal anio={anio} mes={mes} pendientes={pendientesSync} />

      {/* Vista: Hoy vs Agenda del mes */}
      <div className="grid grid-cols-2 gap-2">
        <button onClick={() => setVista('hoy')}
          className={`flex items-center justify-center gap-1.5 rounded-lg border-2 py-2 text-sm font-semibold ${vista === 'hoy' ? 'border-blue-500 bg-blue-600 text-white' : 'border-gray-200 bg-white text-gray-600'}`}>
          <Sun className="h-4 w-4" /> Hoy
          {pendHoy > 0 && <span className={`rounded-full px-1.5 text-[11px] ${vista === 'hoy' ? 'bg-white/25' : 'bg-blue-100 text-blue-700'}`}>{pendHoy}</span>}
        </button>
        <button onClick={() => setVista('mes')}
          className={`flex items-center justify-center gap-1.5 rounded-lg border-2 py-2 text-sm font-semibold ${vista === 'mes' ? 'border-blue-500 bg-blue-600 text-white' : 'border-gray-200 bg-white text-gray-600'}`}>
          <CalendarDays className="h-4 w-4" /> Agenda del mes
          {pendMes > 0 && <span className={`rounded-full px-1.5 text-[11px] ${vista === 'mes' ? 'bg-white/25' : 'bg-blue-100 text-blue-700'}`}>{pendMes}</span>}
        </button>
      </div>

      {/* En la agenda del mes: navegación de mes */}
      {vista === 'mes' && (
        <div className="flex items-center justify-center gap-3">
          <button onClick={() => cambiarMes(-1)} className="rounded-lg border bg-white px-2 py-1.5"><ChevronLeft className="h-4 w-4" /></button>
          <span className="min-w-[120px] text-center text-sm font-semibold">{MESES[mes - 1]} {anio}</span>
          <button onClick={() => cambiarMes(1)} className="rounded-lg border bg-white px-2 py-1.5"><ChevronRight className="h-4 w-4" /></button>
        </div>
      )}

      {/* [MIG651] ESM pidió otra cosa al llegar */}
      {vista === 'hoy' && mundo && (
        <button onClick={() => setCambioAbierto(true)}
                className="flex w-full items-center gap-2 rounded-xl border-2 border-dashed border-orange-300 bg-orange-50 p-2.5 text-left active:bg-orange-100">
          <Shuffle className="h-4 w-4 flex-shrink-0 text-orange-600" />
          <span className="flex-1">
            <span className="block text-sm font-bold text-orange-900">Cambio de programa</span>
            <span className="block text-[11px] text-orange-800">
              {mundo === 'combustible' ? 'ESM pidió otra cosa: calibrar camiones, otro punto…' : 'ESM pidió otra zona: la sala en vez del rack…'}
            </span>
          </span>
          <ChevronRight className="h-4 w-4 text-orange-500" />
        </button>
      )}
      {cambioAbierto && mundo && (
        <CambioPrograma mundo={mundo} hoy={hoyISO} pend={pend} planHoy={planHoy} zonasDia={zonasDia}
                        onClose={() => setCambioAbierto(false)} />
      )}
      {vista === 'hoy' && zonasExtra.length > 0 && (
        <div className="rounded-xl border border-orange-200 bg-white p-2.5 text-xs">
          <p className="font-bold text-orange-900">Hoy, por cambio de programa</p>
          {zonasExtra.map((z) => <p key={z.lugar_id} className="text-gray-700">{z.area} · <b>{z.lugar}</b></p>)}
        </div>
      )}

      {/* [MIG274] Plan del día publicado por el planificador */}
      {vista === 'hoy' && planPorArea.length > 0 && (
        <div className="rounded-xl border-2 border-emerald-300 bg-emerald-50/60 p-2.5">
          <div className="flex items-center gap-1.5">
            <ClipboardList className="h-4 w-4 text-emerald-700" />
            <p className="text-sm font-bold text-emerald-900">Plan de hoy</p>
            <span className="ml-auto text-[11px] text-emerald-700">{planHoy.length} actividades</span>
          </div>
          <div className="mt-2 space-y-2">
            {planPorArea.map((g) => (
              <div key={g.clave} className="rounded-lg border border-emerald-200 bg-white p-2">
                <p className="text-xs font-bold text-gray-800">{g.zona ? `${g.zona}` : g.area}</p>
                {g.zona && <p className="text-[11px] text-gray-500">{g.area}</p>}
                {g.noSeHizo && (
                  <p className="mt-1 rounded bg-orange-100 px-1.5 py-0.5 text-[10px] font-semibold text-orange-800">
                    No se hizo — {g.noSeHizo.motivo} (queda por reprogramar)
                  </p>
                )}
                <ul className="mt-1 space-y-0.5">
                  {g.tareas.map((t) => (
                    <li key={t.id} className="flex items-start gap-1.5 text-[11px] text-gray-600">
                      <span className="font-mono text-gray-400">{t.codigo_item}</span>
                      <span className="flex-1">{t.actividad ?? '—'}</span>
                      {t.estado === 'hecha' && <CheckCircle2 className="h-3 w-3 flex-shrink-0 text-green-600" />}
                      {t.estado === 'no_realizada' && <span className="flex-shrink-0 text-[10px] text-orange-700">no se hizo</span>}
                    </li>
                  ))}
                </ul>
                {g.tareas[0]?.comentario && (
                  <p className="mt-1 text-[10px] italic text-gray-500">{g.tareas[0].comentario}</p>
                )}
                {/* Un botón por punto candidato: entra al servicio ya filtrado
                    a las actividades del plan, sin pasar por toda la pauta. */}
                <div className="mt-1.5 flex flex-wrap gap-1.5">
                  {g.candidatos.length === 0 ? (
                    <span className="text-[10px] text-amber-700">
                      Sin servicio programado este mes para este punto — avisa al planificador
                    </span>
                  ) : g.candidatos.map((p) => (
                    <Link key={p.programacion_id}
                          href={`/m/enex/servicio/?id=${p.programacion_id}&items=${encodeURIComponent(g.codigos.join(','))}`}
                          className="rounded-lg bg-emerald-600 px-2.5 py-1.5 text-[11px] font-semibold text-white active:bg-emerald-700">
                      {g.candidatos.length > 1 || !g.zona ? p.instalacion : 'Abrir'} <ChevronRight className="inline h-3 w-3" />
                    </Link>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {isLoading ? (
        <div className="flex justify-center py-10"><Spinner /></div>
      ) : diasVisibles.length === 0 ? (
        <div className="py-10 text-center text-sm text-gray-400">
          {vista === 'hoy' ? (
            <>
              <Sun className="mx-auto mb-2 h-8 w-8 text-gray-300" />
              <p>No tienes tareas para hoy{hoyISO && <> ({fmtDiaLargo(hoyISO)})</>}
                {mundo && <> en <b>{MUNDO_LABEL[mundo]}</b></>}.</p>
              {pendHoyOtro > 0 && (
                <button onClick={() => elegirMundo(otroMundo)}
                        className="mt-2 rounded-lg border border-emerald-300 bg-emerald-50 px-3 py-1.5 text-xs font-medium text-emerald-800">
                  Hoy hay {pendHoyOtro} en {MUNDO_LABEL[otroMundo]} — ver
                </button>
              )}
              {pendMes > 0 && (
                <button onClick={() => setVista('mes')} className="mt-2 rounded-lg border border-blue-300 bg-blue-50 px-3 py-1.5 text-xs font-medium text-blue-700">
                  Ver la agenda del mes ({pendMes})
                </button>
              )}
            </>
          ) : pend.length === 0 ? (
            <>No hay servicios programados en {MESES[mes - 1]} {anio}. El planificador los programa desde el panel de control.</>
          ) : (
            <>No hay servicios de <b>{mundo ? MUNDO_LABEL[mundo] : ''}</b> este período. Cambia de mundo arriba.</>
          )}
        </div>
      ) : diasVisibles.map((dia) => {
        const esHoy = dia.fecha === hoyISO
        const porEjecutar = dia.items.filter((p) => !p.cumplida && !p.por_reprogramar_motivo).length
        return (
          <div key={dia.fecha}>
            {/* Cabecera del día */}
            <div className={`sticky top-0 z-10 flex items-center gap-2 rounded-lg px-3 py-1.5 ${esHoy ? 'bg-blue-600 text-white' : 'bg-gray-100 text-gray-700'}`}>
              <CalendarDays className="h-3.5 w-3.5" />
              <span className="text-xs font-bold">{dia.fecha === 'sin' ? 'Sin fecha asignada' : fmtDiaLargo(dia.fecha)}</span>
              {esHoy && <span className="rounded-full bg-white/25 px-1.5 py-0.5 text-[10px] font-bold">HOY</span>}
              <span className={`ml-auto text-[11px] ${esHoy ? 'text-blue-100' : 'text-gray-500'}`}>
                {porEjecutar > 0 ? `${porEjecutar} por ejecutar` : 'todo listo'}
              </span>
            </div>
            <div className="space-y-2 pt-2">
              {dia.items.map((p) => (
                <Link key={p.programacion_id} href={`/m/enex/servicio/?id=${p.programacion_id}`}
                      className="block rounded-xl border border-gray-200 bg-white p-3 active:bg-gray-50">
                  <div className="flex items-center gap-2">
                    <span className="flex-1 text-sm font-medium text-gray-800">
                      {p.es_comodin ? 'Camión por asignar' : p.instalacion}
                      {p.patente && !p.es_comodin && <span className="text-gray-500"> · {p.patente}</span>}
                    </span>
                    {p.por_reprogramar_motivo && !p.ejecucion_id
                      ? <span className="flex items-center gap-1 rounded-full bg-orange-100 px-2 py-0.5 text-[10px] font-medium text-orange-800"><Ban className="h-3 w-3" /> No se hizo</span>
                      : p.cumplida
                      ? <span className="flex items-center gap-1 rounded-full bg-green-100 px-2 py-0.5 text-[10px] font-medium text-green-700"><CheckCircle2 className="h-3 w-3" /> Cumplida</span>
                      : p.estado === 'ejecutada'
                      ? <span className="flex items-center gap-1 rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-medium text-amber-800"><Clock className="h-3 w-3" /> Falta firma</span>
                      : <span className="flex items-center gap-1 rounded-full bg-blue-100 px-2 py-0.5 text-[10px] font-medium text-blue-700"><Clock className="h-3 w-3" /> Por ejecutar</span>}
                  </div>
                  <div className="mt-1 flex items-center justify-between text-xs text-gray-500">
                    <span>
                      {p.faena} · {TIPO_INSTALACION_LABEL[p.instalacion_tipo]} · {p.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención'} · {p.pauta_items} ítems
                    </span>
                    <ChevronRight className="h-4 w-4 text-gray-400" />
                  </div>
                  {p.es_comodin && !p.cumplida && (
                    <div className="mt-1 text-[10px] text-blue-700">La patente la anotas en terreno, con el camión que entregue la operación.</div>
                  )}
                  {p.origen === 'terreno' && (
                    <div className="mt-1 text-[10px] text-orange-700">Fuera de plan · cambio de programa en terreno{p.local ? ' (por enviar)' : ''}</div>
                  )}
                  {p.por_reprogramar_motivo && !p.ejecucion_id && (
                    <div className="mt-1 text-[10px] text-orange-700">{p.por_reprogramar_motivo} — queda por reprogramar</div>
                  )}
                  {p.es_recobro && !p.cumplida && (
                    <div className="mt-1 flex items-center gap-1 rounded bg-amber-100 px-1.5 py-0.5 text-[10px] font-semibold text-amber-800">
                      <Repeat className="h-3 w-3" /> RECOBRO — repetición del trimestre (se factura a ENEX)
                    </div>
                  )}
                  {p.pauta_borrador && (
                    <div className="mt-1 flex items-center gap-1 text-[10px] text-amber-600"><AlertTriangle className="h-3 w-3" /> pauta en borrador</div>
                  )}
                  {!p.pauta_id && (
                    <div className="mt-1 flex items-center gap-1 text-[10px] text-red-600"><AlertTriangle className="h-3 w-3" /> sin pauta asignada — avisa al supervisor</div>
                  )}
                </Link>
              ))}
            </div>
          </div>
        )
      })}
    </div>
  )
}
