'use client'

// Terreno ENEX — lista de instalaciones programadas por período (MIG208).
// El mantenedor elige una y ejecuta su pauta.

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Building2, ChevronRight, ChevronLeft, CheckCircle2, Clock, RefreshCw, AlertTriangle,
  WifiOff, CloudOff, Download, Fuel, Droplets, Repeat, Check, CalendarDays, Sun,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import {
  MESES, TIPO_INSTALACION_LABEL, MUNDO_LABEL, mundoDeLinea, type Mundo, type EnexPendiente,
} from '@/lib/services/enex'
import { getPendientesOffline, prepararEnexOffline, getEnexPendingCount, syncEnexPending } from '@/lib/offline/enex-offline'
import { useNetworkStatus } from '@/hooks/use-calama-offline'

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
  const qc = useQueryClient()
  const online = useNetworkStatus()
  const [descargaMsg, setDescargaMsg] = useState('')

  // Mundo del supervisor (combustible / lubricantes). Se elige y se recuerda:
  // dos supervisores usan la MISMA app y cada uno filtra su mundo según su día.
  const [mundo, setMundo] = useState<Mundo | null>(null)
  useEffect(() => {
    const saved = typeof localStorage !== 'undefined' ? localStorage.getItem(MUNDO_KEY) : null
    setMundo(saved === 'lubricante' || saved === 'combustible' ? saved : 'combustible')
  }, [])
  function elegirMundo(m: Mundo) { setMundo(m); try { localStorage.setItem(MUNDO_KEY, m) } catch { /* no-op */ } }

  const { data: pend = [], isLoading, refetch, isFetching } = useQuery({
    queryKey: ['enex-terreno', anio, mes], queryFn: () => getPendientesOffline(anio, mes),
    networkMode: 'always', staleTime: 10_000, enabled: periodo !== null,
  })

  // Descarga automática del mes para trabajar sin señal (una vez por período,
  // al estar en línea). El botón manual sigue disponible como respaldo.
  const [autoBajado, setAutoBajado] = useState<string>('')
  useEffect(() => {
    if (!periodo || !online) return
    const clave = `${anio}-${mes}`
    if (autoBajado === clave) return
    if (pend.length === 0) return
    setAutoBajado(clave)
    prepararEnexOffline(anio, mes)
      .then((n) => setDescargaMsg(`${n} servicios disponibles sin internet`))
      .catch(() => { /* si falla, queda el botón manual */ })
  }, [periodo, online, anio, mes, pend.length, autoBajado])
  const { data: pendientesSync = 0 } = useQuery({
    queryKey: ['enex-pending-count'], queryFn: getEnexPendingCount, networkMode: 'always', refetchInterval: 4000,
  })

  // Sincroniza al recuperar conexión
  useEffect(() => {
    const trySync = async () => {
      if (typeof navigator !== 'undefined' && navigator.onLine) {
        const r = await syncEnexPending()
        if (r.ok > 0 || r.failed > 0) { qc.invalidateQueries({ queryKey: ['enex-terreno'] }); qc.invalidateQueries({ queryKey: ['enex-pending-count'] }) }
      }
    }
    window.addEventListener('online', trySync); void trySync()
    return () => window.removeEventListener('online', trySync)
  }, [qc])

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

  const pendHoy = useMemo(
    () => pendMundo.filter((p) => !p.cumplida && p.fecha_programada?.slice(0, 10) === hoyISO).length,
    [pendMundo, hoyISO])
  const pendMes = pendMundo.filter((p) => !p.cumplida).length
  const conteoMundo = useMemo(() => ({
    combustible: pend.filter((p) => mundoDeLinea(p.linea) === 'combustible' && !p.cumplida).length,
    lubricante: pend.filter((p) => mundoDeLinea(p.linea) === 'lubricante' && !p.cumplida).length,
  }), [pend])

  // Primer render (SSR/hidratación) sin fecha: contenido determinista.
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
      {online && pend.length > 0 && (
        <button onClick={async () => { const n = await prepararEnexOffline(anio, mes); setDescargaMsg(`${n} servicios descargados para usar sin internet`) }}
                className="flex w-full items-center justify-center gap-2 rounded-lg border border-blue-300 bg-blue-50 py-2 text-xs font-medium text-blue-700">
          <Download className="h-4 w-4" /> Descargar el mes para trabajar sin señal
        </button>
      )}
      {descargaMsg && <p className="text-center text-[11px] text-green-600">{descargaMsg}</p>}

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

      {isLoading ? (
        <div className="flex justify-center py-10"><Spinner /></div>
      ) : diasVisibles.length === 0 ? (
        <div className="py-10 text-center text-sm text-gray-400">
          {vista === 'hoy' ? (
            <>
              <Sun className="mx-auto mb-2 h-8 w-8 text-gray-300" />
              <p>No tienes tareas para hoy{hoyISO && <> ({fmtDiaLargo(hoyISO)})</>}.</p>
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
        const porEjecutar = dia.items.filter((p) => !p.cumplida).length
        return (
          <div key={dia.fecha}>
            {/* Cabecera del día */}
            <div className={`sticky top-0 z-10 flex items-center gap-2 rounded-lg px-3 py-1.5 ${esHoy ? 'bg-blue-600 text-white' : 'bg-gray-100 text-gray-700'}`}>
              <CalendarDays className="h-3.5 w-3.5" />
              <span className="text-xs font-bold capitalize">{dia.fecha === 'sin' ? 'Sin fecha asignada' : fmtDiaLargo(dia.fecha)}</span>
              {esHoy && <span className="rounded-full bg-white/25 px-1.5 py-0.5 text-[10px] font-bold">HOY</span>}
              <span className={`ml-auto text-[11px] ${esHoy ? 'text-blue-100' : 'text-gray-500'}`}>
                {porEjecutar > 0 ? `${porEjecutar} por ejecutar` : 'todo listo'}
              </span>
            </div>
            <div className="space-y-2 pt-2">
              {dia.items.map((p) => (
                <Link key={p.programacion_id} href={`/m/enex/${p.programacion_id}`}
                      className="block rounded-xl border border-gray-200 bg-white p-3 active:bg-gray-50">
                  <div className="flex items-center gap-2">
                    <span className="flex-1 text-sm font-medium text-gray-800">
                      {p.instalacion}
                      {p.patente && <span className="text-gray-500"> · {p.patente}</span>}
                    </span>
                    {p.cumplida
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
