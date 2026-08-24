'use client'

// ============================================================================
// La jornada del mecánico — Franke (MIG357-359)
// ----------------------------------------------------------------------------
// Lo que reemplaza esta pantalla es esto, escrito siete veces seguidas en la
// entrega de turno:
//
//     · Revisión de equipos de faena.
//     · Toma de km y horas de equipos.
//     · Revisión de fluidos y niveles de equipos.
//
// Decisiones de diseño, todas por la misma razón — que se use:
//
//   · EL MECÁNICO NO ELIGE QUÉ REVISAR. El sistema le pone la jornada delante:
//     un equipo por tarjeta, con lo que le toca hoy. Elegir de una lista es
//     donde se pierde la mitad del trabajo.
//   · LO PROGRAMADO VA ARRIBA Y CON EL NÚMERO. «Faltan 119 h» pesa distinto que
//     «servicio de 300 h». El número es la razón por la que alguien se mueve.
//   · LO QUE YA SE HIZO SE VE HECHO. Sin eso el mecánico no sabe si le falta o
//     si lo cerró el otro turno, y la respuesta segura —volver a hacerla— es la
//     que hace que se marque todo OK sin mirar.
// ============================================================================

import { useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ClipboardList, Truck, Wrench, CheckCircle2, AlertTriangle, ChevronRight,
  Ban, RefreshCw, CalendarDays, CloudOff, Download,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { cn, errorMessage } from '@/lib/utils'
import { useNetworkStatus } from '@/hooks/use-calama-offline'
import {
  FAENA_FRANKE, TURNOS_FRANKE, getFaenaId, textoSenal, type PautaAgenda,
} from '@/lib/services/faena-pauta'
import {
  getAgendaOffline, descargarTodo, ultimaDescarga, sincronizar, pendientesCount,
} from '@/lib/offline/faena-pauta-offline'

const hoyISO = () => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}
const K_TURNO = 'franke-turno'

const COLOR_SENAL: Record<PautaAgenda['senal'], string> = {
  vencida:    'bg-red-100 text-red-800 border-red-200',
  por_vencer: 'bg-amber-100 text-amber-800 border-amber-200',
  al_dia:     'bg-emerald-50 text-emerald-800 border-emerald-200',
  sin_datos:  'bg-gray-100 text-gray-700 border-gray-200',
  diaria:     'bg-blue-50 text-blue-800 border-blue-200',
}

export default function FrankePautaAgendaPage() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil } = useAuth()
  const toast = useToast()

  const online = useNetworkStatus()
  const [faenaId, setFaenaId] = useState<string | null>(null)
  const [agenda, setAgenda] = useState<PautaAgenda[]>([])
  const [cargando, setCargando] = useState(true)
  const [turno, setTurno] = useState<string>('')
  const [descarga, setDescarga] = useState<string | null>(null)
  const [porSubir, setPorSubir] = useState(0)
  const [bajando, setBajando] = useState(false)
  const fecha = hoyISO()

  useEffect(() => {
    try { setTurno(localStorage.getItem(K_TURNO) ?? 'Día') } catch { setTurno('Día') }
  }, [])
  useEffect(() => {
    if (turno) { try { localStorage.setItem(K_TURNO, turno) } catch { /* modo privado */ } }
  }, [turno])

  // El id de la faena también se recuerda: sin él no se puede leer lo bajado, y
  // pedirlo es lo primero que falla cuando no hay antena.
  const cargar = useCallback(async () => {
    setCargando(true)
    try {
      let f: string | null = null
      try { f = localStorage.getItem('franke-faena-id') } catch { /* modo privado */ }
      if (online || !f) {
        const nuevo = await getFaenaId(FAENA_FRANKE).catch(() => null)
        if (nuevo) {
          f = nuevo
          try { localStorage.setItem('franke-faena-id', nuevo) } catch { /* modo privado */ }
        }
      }
      if (!f) {
        toast.error('Necesita señal una vez para bajar la jornada a este teléfono.')
        return
      }
      setFaenaId(f)
      const ag = await getAgendaOffline(f)
      setAgenda(ag ?? [])
      setDescarga(await ultimaDescarga(f))
      setPorSubir(await pendientesCount())
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo cargar la jornada'))
    } finally { setCargando(false) }
  }, [toast, online])

  useEffect(() => { void cargar() }, [cargar])

  // Al volver la señal suben solas las pautas que estaban esperando.
  useEffect(() => {
    if (!online) return
    let vivo = true
    sincronizar().then((r) => {
      if (!vivo || r.ok === 0) return
      toast.success(`Volvió la señal: se subió ${r.ok} pauta(s).`)
      void cargar()
    }).catch(() => { /* se reintenta al próximo cambio de señal */ })
    return () => { vivo = false }
  }, [online, cargar, toast])

  const bajar = async () => {
    if (!faenaId) return
    setBajando(true)
    try {
      const r = await descargarTodo(faenaId)
      setDescarga(await ultimaDescarga(faenaId))
      setAgenda((await getAgendaOffline(faenaId)) ?? [])
      toast.success(`Listo para el patio: ${r.pautas} pauta(s), ${r.items} ítems en el teléfono.`)
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo bajar la jornada'))
    } finally { setBajando(false) }
  }

  // Lo programado que ya venció o está por vencer va primero: es lo que hay que
  // ir a buscar, no lo que se hace igual todos los días.
  const programadas = useMemo(
    () => agenda.filter((a) => a.pauta_tipo === 'programada' && (a.senal === 'vencida' || a.senal === 'por_vencer')),
    [agenda],
  )
  // El equipo que la ficha declara fuera de servicio no se le exige al mecánico
  // todos los días. El HHWB-42 lleva meses en el taller de Coquimbo: pedirle que
  // entre a marcarlo «no está en faena» cada mañana es la clase de trabajo
  // inútil que hace que se marque todo OK sin mirar. Sigue visible y se puede
  // abrir —vuelve algún día—, pero aparte y sin contar en la cuenta del día.
  const enFaena = useMemo(
    () => agenda.filter((a) => a.pauta_tipo === 'diaria' && a.activo_estado !== 'en_mantenimiento'),
    [agenda],
  )
  const fueraDeFaena = useMemo(
    () => agenda.filter((a) => a.pauta_tipo === 'diaria' && a.activo_estado === 'en_mantenimiento'),
    [agenda],
  )
  const diarias = enFaena
  const otrasProgramadas = useMemo(
    () => agenda.filter((a) => a.pauta_tipo === 'programada' && a.senal !== 'vencida' && a.senal !== 'por_vencer'),
    [agenda],
  )

  const hechasHoy = diarias.filter((a) => a.ejecucion_hoy_estado === 'cerrada' || a.ejecucion_hoy_estado === 'no_aplica').length

  if (verificando) {
    return <div className="flex min-h-screen items-center justify-center bg-gray-50"><Spinner className="h-8 w-8" /></div>
  }
  if (sinSesionOffline) return <SinSesionOffline />

  return (
    <div className="min-h-screen bg-gray-50 pb-12">
      <header className="sticky top-0 z-10 border-b border-gray-200 bg-white px-4 pb-3 pt-[max(0.75rem,env(safe-area-inset-top))]">
        <div className="flex items-center gap-3">
          <div className="min-w-0 flex-1">
            <p className="text-base font-bold leading-tight text-gray-900">Revisión de equipos</p>
            <p className="text-xs text-gray-500">
              Faena Franke · {fecha}
              {perfil?.nombre_completo ? ` · ${perfil.nombre_completo}` : ''}
            </p>
          </div>
          {!online && (
            <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-amber-100 px-2 py-1 text-[11px] font-bold text-amber-800">
              <CloudOff className="h-3.5 w-3.5" /> Sin señal
            </span>
          )}
          <button onClick={() => void cargar()} aria-label="Actualizar"
                  className="shrink-0 rounded-lg p-2 text-gray-500 hover:bg-gray-100">
            <RefreshCw className={cn('h-5 w-5', cargando && 'animate-spin')} />
          </button>
        </div>

        <div className="mt-3 flex gap-2">
          {TURNOS_FRANKE.map((t) => (
            <button key={t} onClick={() => setTurno(t)}
                    className={cn(
                      'h-10 flex-1 rounded-lg border-2 text-sm font-bold transition',
                      turno === t
                        ? 'border-gray-900 bg-gray-900 text-white'
                        : 'border-gray-300 bg-white text-gray-600',
                    )}>
              Turno {t}
            </button>
          ))}
        </div>
      </header>

      <main className="space-y-6 px-4 py-5">
        {cargando && <div className="flex justify-center py-8"><Spinner /></div>}

        {!cargando && agenda.length === 0 && (
          <p className="rounded-xl border border-gray-200 bg-white p-6 text-center text-sm text-gray-500">
            No hay equipos con pauta en esta faena.
          </p>
        )}

        {programadas.length > 0 && (
          <section>
            <h2 className="mb-2 flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-amber-700">
              <Wrench className="h-4 w-4" /> Mantención programada
            </h2>
            <p className="mb-3 text-xs text-gray-500">
              Lo que hay que ir a buscar. El resto se hace igual todos los días.
            </p>
            <div className="space-y-3">
              {programadas.map((a) => <Tarjeta key={a.pauta_id + a.activo_id} a={a} turno={turno} />)}
            </div>
          </section>
        )}

        <section>
          <h2 className="mb-2 flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-600">
            <ClipboardList className="h-4 w-4" /> Revisión de hoy
            <span className="ml-auto font-mono text-xs font-semibold tabular-nums text-gray-500">
              {hechasHoy}/{diarias.length}
            </span>
          </h2>
          <div className="space-y-3">
            {diarias.map((a) => <Tarjeta key={a.pauta_id + a.activo_id} a={a} turno={turno} />)}
          </div>
        </section>

        {fueraDeFaena.length > 0 && (
          <section>
            <h2 className="mb-2 flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-500">
              <Ban className="h-4 w-4" /> Fuera de faena
            </h2>
            <p className="mb-3 text-xs text-gray-500">
              No cuentan en la revisión de hoy. Se pueden abrir igual si volvieron.
            </p>
            <div className="space-y-3 opacity-70">
              {fueraDeFaena.map((a) => <Tarjeta key={a.pauta_id + a.activo_id} a={a} turno={turno} />)}
            </div>
          </section>
        )}

        {otrasProgramadas.length > 0 && (
          <section>
            <h2 className="mb-2 flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-500">
              <CalendarDays className="h-4 w-4" /> Próximas mantenciones
            </h2>
            <div className="space-y-2">
              {otrasProgramadas.map((a) => (
                <div key={a.pauta_id + a.activo_id}
                     className="flex items-center gap-3 rounded-xl border border-gray-200 bg-white px-4 py-3">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-bold text-gray-900">
                      {a.patente ?? a.activo_codigo}
                    </p>
                    <p className="truncate text-xs text-gray-500">{a.pauta_nombre}</p>
                  </div>
                  <span className="shrink-0 font-mono text-xs font-semibold tabular-nums text-gray-600">
                    {textoSenal(a)}
                  </span>
                </div>
              ))}
            </div>
          </section>
        )}

        {/* Dejar el teléfono listo antes de subir al patio. Es lo que hay que
            tocar el lunes con señal; después la antena da lo mismo. */}
        <section className="rounded-xl border border-gray-200 bg-white p-4">
          <p className="text-sm font-bold text-gray-900">Trabajar sin señal</p>
          <p className="mt-1 text-xs text-gray-500">
            {descarga
              ? `La jornada está en este teléfono desde el ${new Date(descarga).toLocaleString('es-CL')}.`
              : 'La jornada todavía no está bajada a este teléfono.'}
          </p>
          <button onClick={() => void bajar()} disabled={bajando || !online || !faenaId}
                  className="mt-3 flex h-12 w-full items-center justify-center gap-2 rounded-xl border-2 border-gray-900 font-bold text-gray-900 disabled:opacity-40">
            {bajando ? <Spinner className="h-5 w-5" /> : <Download className="h-4 w-4" />}
            {descarga ? 'Actualizar lo bajado' : 'Bajar la jornada al teléfono'}
          </button>
          {!online && !descarga && (
            <p className="mt-2 text-xs text-amber-800">
              Necesita señal una vez para bajarla. Después funciona sin antena.
            </p>
          )}
        </section>

        {porSubir > 0 && (
          <div className="flex items-center gap-2 rounded-lg border border-amber-300 bg-amber-50 p-2.5 text-xs text-amber-800">
            <CloudOff className="h-4 w-4 shrink-0" />
            <span className="flex-1">{porSubir} pauta(s) esperando señal para subir.</span>
            {online && (
              <button onClick={async () => {
                        const r = await sincronizar()
                        toast.success(`Subieron ${r.ok}.`)
                        void cargar()
                      }}
                      className="rounded bg-amber-200 px-2 py-1 font-bold">Subir</button>
            )}
          </div>
        )}

        <p className="pt-2 text-center text-xs text-gray-400">
          Lo que salga NO OK pide foto y queda como no conformidad con dueño.
        </p>
      </main>
    </div>
  )
}

function Tarjeta({ a, turno }: { a: PautaAgenda; turno: string }) {
  const hecha = a.ejecucion_hoy_estado === 'cerrada'
  const noAplica = a.ejecucion_hoy_estado === 'no_aplica'
  const enCurso = a.ejecucion_hoy_estado === 'borrador'

  return (
    <Link
      href={`/m/franke/pauta/${a.pauta_id}/${a.activo_id}?turno=${encodeURIComponent(turno)}`}
      className={cn(
        'flex items-center gap-3 rounded-xl border-2 bg-white p-4 transition active:scale-[0.99]',
        hecha ? 'border-emerald-300' : noAplica ? 'border-gray-300' : 'border-gray-200',
      )}
    >
      <div className={cn(
        'grid h-11 w-11 shrink-0 place-items-center rounded-lg',
        hecha ? 'bg-emerald-100 text-emerald-700'
              : noAplica ? 'bg-gray-100 text-gray-500'
              : a.senal === 'vencida' ? 'bg-red-100 text-red-700'
              : 'bg-gray-100 text-gray-600',
      )}>
        {hecha ? <CheckCircle2 className="h-6 w-6" />
               : noAplica ? <Ban className="h-6 w-6" />
               : a.senal === 'vencida' ? <AlertTriangle className="h-6 w-6" />
               : <Truck className="h-6 w-6" />}
      </div>

      <div className="min-w-0 flex-1">
        <p className="truncate text-base font-bold leading-tight text-gray-900">
          {a.patente ?? a.activo_codigo}
        </p>
        <p className="truncate text-xs text-gray-500">
          {a.modelo ?? a.activo_nombre} · {a.items} ítems
        </p>
        <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
          <span className={cn('rounded border px-1.5 py-0.5 font-mono text-[11px] font-semibold',
                              COLOR_SENAL[a.senal])}>
            {textoSenal(a)}
          </span>
          {hecha && (
            <span className="rounded border border-emerald-200 bg-emerald-50 px-1.5 py-0.5 text-[11px] font-semibold text-emerald-800">
              Hecha{a.ejecucion_hoy_turno ? ` · turno ${a.ejecucion_hoy_turno}` : ''}
            </span>
          )}
          {noAplica && (
            <span className="rounded border border-gray-300 bg-gray-50 px-1.5 py-0.5 text-[11px] font-semibold text-gray-600">
              No está en faena
            </span>
          )}
          {enCurso && (
            <span className="rounded border border-blue-200 bg-blue-50 px-1.5 py-0.5 text-[11px] font-semibold text-blue-800">
              A medias
            </span>
          )}
        </div>
      </div>

      <ChevronRight className="h-5 w-5 shrink-0 text-gray-400" />
    </Link>
  )
}
