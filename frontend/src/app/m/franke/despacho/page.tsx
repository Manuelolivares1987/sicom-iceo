'use client'

// ============================================================================
// Despacho de combustible en faena — Franke (MIG363/364)
// ----------------------------------------------------------------------------
// POR QUÉ ESTA PANTALLA NO ES LA DE ROMERAL CON OTRO NOMBRE
// La lógica sí es la misma —el mismo servicio, la misma cola sin señal, el
// mismo RPC— y no se duplica nada de eso. Lo que cambia es lo que se le pide a
// la persona, y ahí las dos faenas no se parecen:
//
//   ROMERAL   despacha desde estanques fijos, la imputación llega después en el
//             archivo del tótem Orpak, y el cierre del turno es con varilla.
//   FRANKE    despacha desde el camión, cada transacción emite un TICKET con
//             folio correlativo, y ese folio es la fuente de verdad. No hay
//             tótem ni varilla.
//
// Meter las dos en una pantalla con condicionales daría una que no le sirve
// bien a ninguna de las dos.
//
// EL FOLIO VA PRIMERO Y ES OBLIGATORIO
// Es lo primero que la persona tiene en la mano cuando sale el ticket. Ponerlo
// al final es garantizar que se teclee de memoria tres cargas después. Y si un
// folio ya está usado, la carga entera se detiene: dos cargas con el mismo
// número dejan dos verdades y ninguna forma de saber cuál es.
//
// EL MEDIDOR INICIAL LLEGA PUESTO con el final de la carga anterior, que es como
// corre la corrida.
// ============================================================================

import { useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, Fuel, Plus, Check, WifiOff, CloudOff, RefreshCw, Search, X, Truck,
  MapPin, CheckCircle2, Download, Camera, Ticket, ChevronDown,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { useNetworkStatus } from '@/hooks/use-calama-offline'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { cn, errorMessage } from '@/lib/utils'
import {
  TURNOS, type CatalogoFaena, type CombEquipo, type CombDespacho,
} from '@/lib/services/combustible-faena'
import {
  getCatalogoOffline, descargarCatalogo, ultimaDescarga, guardarDespacho, guardarFotoLocal,
  sincronizar, getDiaOffline, pendientesCount,
  type DespachoPendiente,
} from '@/lib/offline/combustible-faena-offline'

const FAENA = 'FAE-FRANCKE'
const K = (s: string) => `franke-${s}`

const hoyISO = () => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}
const horaAhora = () => {
  const d = new Date()
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}
const num = (v: string): number | null => {
  const n = Number(String(v).replace(',', '.'))
  return Number.isFinite(n) && String(v).trim() !== '' ? n : null
}
const miles = (n: number | null | undefined) =>
  n == null ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 0 })

const CONCEPTOS = [
  { k: 'venta' as const,         t: 'Venta' },
  { k: 'trasvasije' as const,    t: 'Trasvasije' },
  { k: 'recirculacion' as const, t: 'Recirculación' },
  { k: 'calibracion' as const,   t: 'Calibración' },
]

export default function FrankeDespachoPage() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil } = useAuth()
  const online = useNetworkStatus()
  const toast = useToast()

  const [cat, setCat] = useState<CatalogoFaena | null>(null)
  const [cargando, setCargando] = useState(true)
  const [fecha, setFecha] = useState('')
  const [descarga, setDescarga] = useState<string | null>(null)
  const [porSubir, setPorSubir] = useState(0)

  // La cabecera se pregunta una vez y queda fija: en el papel tampoco se
  // reescribe en cada línea.
  const [turno, setTurno] = useState('')
  const [camionId, setCamionId] = useState('')
  const [operador, setOperador] = useState('')
  const [cabAbierta, setCabAbierta] = useState(false)

  const [abierto, setAbierto] = useState(false)
  const [folio, setFolio] = useState('')
  const [tipoMov, setTipoMov] = useState<typeof CONCEPTOS[number]['k']>('venta')
  const [destinoId, setDestinoId] = useState('')
  const [buscar, setBuscar] = useState('')
  const [equipo, setEquipo] = useState<CombEquipo | null>(null)
  const [equipoTexto, setEquipoTexto] = useState('')
  const [cecoTexto, setCecoTexto] = useState('')
  const [ubicacionId, setUbicacionId] = useState('')
  const [meterIni, setMeterIni] = useState('')
  const [meterFin, setMeterFin] = useState('')
  const [litrosManual, setLitrosManual] = useState('')
  const [obs, setObs] = useState('')
  const [guardando, setGuardando] = useState(false)
  type Foto = { file: File; preview: string }
  const [fotoFin, setFotoFin] = useState<Foto | null>(null)
  const [sinFotoMotivo, setSinFotoMotivo] = useState('')

  const [servidor, setServidor] = useState<CombDespacho[]>([])
  const [locales, setLocales] = useState<DespachoPendiente[]>([])

  useEffect(() => { setFecha(hoyISO()) }, [])

  useEffect(() => {
    try {
      setTurno(localStorage.getItem(K('turno')) ?? '')
      setCamionId(localStorage.getItem(K('camion')) ?? '')
      setOperador(localStorage.getItem(K('operador')) ?? '')
    } catch { /* modo privado */ }
  }, [])
  useEffect(() => { try { localStorage.setItem(K('turno'), turno) } catch { /* no-op */ } }, [turno])
  useEffect(() => { try { localStorage.setItem(K('camion'), camionId) } catch { /* no-op */ } }, [camionId])
  useEffect(() => { try { localStorage.setItem(K('operador'), operador) } catch { /* no-op */ } }, [operador])
  useEffect(() => {
    if (!operador && perfil?.nombre_completo) setOperador(perfil.nombre_completo)
  }, [perfil, operador])

  const refrescar = useCallback(async (faenaId: string, f: string) => {
    const { servidor: s, locales: l } = await getDiaOffline(faenaId, f)
    setServidor(s); setLocales(l)
    setPorSubir(await pendientesCount())
  }, [])

  useEffect(() => {
    if (!fecha) return
    let vivo = true
    ;(async () => {
      setCargando(true)
      try {
        const c = await getCatalogoOffline(FAENA)
        if (!vivo) return
        setCat(c)
        setDescarga(await ultimaDescarga(FAENA))
        if (c) await refrescar(c.faena.id, fecha)
      } catch { /* sin señal: se trabaja con lo bajado */ }
      finally { if (vivo) setCargando(false) }
    })()
    return () => { vivo = false }
  }, [fecha, refrescar])

  // Al volver la señal suben solas las cargas que estaban esperando.
  useEffect(() => {
    if (!online || !cat) return
    let vivo = true
    sincronizar().then((r) => {
      if (!vivo || r.ok === 0) return
      toast.success(`Volvió la señal: se subieron ${r.ok} carga(s).`)
      void refrescar(cat.faena.id, fecha)
    }).catch(() => { /* se reintenta al próximo cambio de señal */ })
    return () => { vivo = false }
  }, [online, cat, fecha, refrescar, toast])

  const camion = useMemo(
    () => cat?.camiones.find((c) => c.id === camionId) ?? null, [cat, camionId])
  const camionLabel = camion ? `${camion.nombre}${camion.patente ? ` · ${camion.patente}` : ''}` : ''

  const equipos = useMemo(() => {
    if (!cat) return []
    const q = buscar.trim().toLowerCase()
    if (!q) return cat.equipos.slice(0, 40)
    return cat.equipos.filter((e) =>
      e.nombre.toLowerCase().includes(q)
      || (e.descripcion ?? '').toLowerCase().includes(q)
      || (e.ceco ?? '').toLowerCase().includes(q)).slice(0, 40)
  }, [cat, buscar])

  const litrosCalc = useMemo(() => {
    const a = num(meterIni), b = num(meterFin)
    return a != null && b != null && b >= a ? Math.round((b - a) * 10) / 10 : null
  }, [meterIni, meterFin])
  const litros = litrosCalc ?? num(litrosManual)

  const nuevaCarga = () => {
    let ini = ''
    try { ini = localStorage.getItem(K('meter')) ?? '' } catch { /* no-op */ }
    setFolio(''); setTipoMov('venta'); setDestinoId('')
    setEquipo(null); setEquipoTexto(''); setCecoTexto(''); setBuscar('')
    setUbicacionId(''); setMeterIni(ini); setMeterFin(''); setLitrosManual('')
    setObs(''); setFotoFin(null); setSinFotoMotivo('')
    setAbierto(true)
  }

  const guardar = async () => {
    if (!cat) return
    if (!turno || !camionId || !operador.trim()) {
      toast.error('Falta el turno, el camión o quién carga.'); setCabAbierta(true); return
    }
    if (!folio.trim()) { toast.error('Escriba el folio del ticket. Es lo que amarra la carga al papel.'); return }
    if (!equipo && !equipoTexto.trim()) { toast.error('¿A quién se cargó?'); return }
    if (litros == null || litros <= 0) { toast.error('Faltan los litros o el medidor.'); return }
    if (tipoMov === 'trasvasije' && !destinoId) { toast.error('¿A qué camión se trasvasijó?'); return }
    if (!fotoFin && !sinFotoMotivo.trim()) {
      toast.error('Saque la foto del medidor, o escriba por qué no pudo.'); return
    }

    setGuardando(true)
    try {
      const ubic = cat.ubicaciones.find((u) => u.id === ubicacionId) ?? null
      const blobFin = fotoFin ? await guardarFotoLocal(fotoFin.file) : null
      const { enviado } = await guardarDespacho({
        faenaId: cat.faena.id,
        fecha, turno,
        estanqueId: camionId,
        equipoId: equipo?.id ?? null,
        equipoTexto: equipo ? null : equipoTexto.trim(),
        cecoTexto: equipo?.ceco ? null : (cecoTexto.trim() || null),
        tipoMovimiento: tipoMov,
        destinoEstanqueId: tipoMov === 'trasvasije' ? destinoId : null,
        ubicacionId: ubicacionId || null,
        meterInicial: num(meterIni),
        meterFinal: num(meterFin),
        litros,
        folioTicket: Number(folio.trim()),
        operadorNombre: operador.trim(),
        hora: horaAhora(),
        observacion: obs.trim() || null,
        sinFotoMotivo: !fotoFin ? sinFotoMotivo.trim() : null,
      }, {
        equipo_nombre: equipo?.nombre ?? equipoTexto.trim(),
        ceco_nombre: equipo?.ceco ?? (cecoTexto.trim() || null),
        ubicacion_nombre: ubic?.nombre ?? null,
        camion_nombre: camionLabel,
        foto_ini_blob: null,
        foto_fin_blob: blobFin,
      })
      if (num(meterFin) != null) { try { localStorage.setItem(K('meter'), meterFin) } catch { /* no-op */ } }
      setAbierto(false)
      await refrescar(cat.faena.id, fecha)
      toast.success(enviado
        ? `Ticket ${folio} registrado · ${miles(litros)} L`
        : `Ticket ${folio} guardado en el teléfono — sube solo con señal`)
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo guardar la carga'))
    } finally { setGuardando(false) }
  }

  if (verificando) {
    return <div className="flex min-h-screen items-center justify-center bg-gray-50"><Spinner className="h-8 w-8" /></div>
  }
  if (sinSesionOffline) return <SinSesionOffline />

  const totalDia = servidor.filter((d) => !d.anulado).reduce((a, d) => a + Number(d.litros ?? 0), 0)
    + locales.reduce((a, d) => a + Number(d.litros ?? 0), 0)

  return (
    <div className="min-h-screen bg-gray-50 pb-28">
      <header className="sticky top-0 z-10 border-b border-gray-200 bg-white px-4 pb-3 pt-[max(0.75rem,env(safe-area-inset-top))]">
        <div className="flex items-center gap-3">
          <Link href="/m/franke" className="shrink-0 rounded-lg p-1.5 text-gray-500 hover:bg-gray-100">
            <ArrowLeft className="h-5 w-5" />
          </Link>
          <div className="min-w-0 flex-1">
            <p className="text-base font-bold leading-tight text-gray-900">Despacho de combustible</p>
            <p className="truncate text-[11px] text-gray-500">
              {cat?.faena.nombre ?? 'Faena Franke'} · {fecha}
            </p>
          </div>
          <span className={cn('flex shrink-0 items-center gap-1 rounded-full px-2 py-1 text-[10px] font-bold',
                              online ? 'bg-emerald-100 text-emerald-700' : 'bg-amber-100 text-amber-800')}>
            {online ? <CheckCircle2 className="h-3 w-3" /> : <WifiOff className="h-3 w-3" />}
            {online ? 'En línea' : 'Sin señal'}
          </span>
        </div>
      </header>

      <main className="space-y-3 px-4 py-4">
        {cargando && <div className="flex justify-center py-10"><Spinner /></div>}

        {!cargando && !cat && (
          <div className="space-y-3 rounded-xl border-2 border-amber-300 bg-amber-50 p-4 text-center">
            <p className="text-sm text-amber-900">
              El catálogo de la faena no está en este teléfono. Descárguelo con señal antes de subir.
            </p>
            <button onClick={async () => {
                      try {
                        const n = await descargarCatalogo(FAENA)
                        setCat(await getCatalogoOffline(FAENA))
                        setDescarga(await ultimaDescarga(FAENA))
                        toast.success(`Catálogo descargado: ${n} equipos.`)
                      } catch (e) { toast.error(errorMessage(e, 'No se pudo descargar')) }
                    }}
                    className="h-12 w-full rounded-xl bg-gray-900 font-bold text-white">
              Descargar catálogo
            </button>
          </div>
        )}

        {cat && (
          <>
            {/* ── La cabecera del turno ─────────────────────────────────── */}
            <section className="rounded-xl border border-gray-200 bg-white">
              <button onClick={() => setCabAbierta(!cabAbierta)}
                      className="flex w-full items-center gap-3 px-4 py-3 text-left">
                <Truck className="h-5 w-5 shrink-0 text-gray-400" />
                <div className="min-w-0 flex-1">
                  {turno && camionId ? (
                    <>
                      <p className="truncate text-sm font-bold text-gray-900">{camionLabel}</p>
                      <p className="truncate text-[11px] text-gray-500">
                        Turno {turno} · {operador}
                      </p>
                    </>
                  ) : (
                    <p className="text-sm font-bold text-amber-700">Falta decir turno, camión y quién carga</p>
                  )}
                </div>
                <ChevronDown className={cn('h-4 w-4 shrink-0 text-gray-400 transition',
                                           cabAbierta && 'rotate-180')} />
              </button>

              {cabAbierta && (
                <div className="space-y-3 border-t border-gray-100 p-4">
                  <div className="flex gap-2">
                    {TURNOS.map((t) => (
                      <button key={t} onClick={() => setTurno(t)}
                              className={cn('h-12 flex-1 rounded-xl border-2 font-bold',
                                            turno === t ? 'border-gray-900 bg-gray-900 text-white'
                                                        : 'border-gray-300 bg-white text-gray-600')}>
                        {t}
                      </button>
                    ))}
                  </div>
                  <select value={camionId} onChange={(e) => setCamionId(e.target.value)}
                          className="h-14 w-full rounded-xl border-2 border-gray-300 px-3 text-base font-semibold">
                    <option value="">¿Desde qué camión?</option>
                    {cat.camiones.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.nombre}{c.patente ? ` · ${c.patente}` : ''}
                      </option>
                    ))}
                  </select>
                  <input value={operador} onChange={(e) => setOperador(e.target.value)}
                         placeholder="¿Quién carga?"
                         className="h-14 w-full rounded-xl border-2 border-gray-300 px-3 text-base" />
                </div>
              )}
            </section>

            {porSubir > 0 && (
              <div className="flex items-center gap-2 rounded-lg border border-amber-300 bg-amber-50 p-2.5 text-xs text-amber-800">
                <CloudOff className="h-4 w-4 shrink-0" />
                <span className="flex-1">{porSubir} carga(s) esperando señal.</span>
                {online && (
                  <button onClick={async () => {
                            const r = await sincronizar()
                            toast.success(`Subieron ${r.ok}.`)
                            if (cat) await refrescar(cat.faena.id, fecha)
                          }}
                          className="rounded bg-amber-200 px-2 py-1 font-bold">Subir</button>
                )}
              </div>
            )}

            {/* ── Lo del día ────────────────────────────────────────────── */}
            <section className="rounded-xl border border-gray-200 bg-white p-4">
              <div className="flex items-baseline justify-between">
                <p className="text-sm font-bold uppercase tracking-wide text-gray-500">Cargas de hoy</p>
                <p className="font-mono text-lg font-bold tabular-nums text-gray-900">
                  {miles(totalDia)} <span className="text-xs font-normal text-gray-500">L</span>
                </p>
              </div>
              <div className="mt-3 space-y-2">
                {[...locales, ...servidor].length === 0 && (
                  <p className="py-3 text-center text-sm text-gray-400">Todavía no hay cargas hoy.</p>
                )}
                {locales.map((d) => (
                  <Fila key={d.local_id} folio={d.folioTicket ?? null} equipo={d.equipo_nombre ?? '—'}
                        litros={d.litros} pendiente hora={d.hora ?? null} />
                ))}
                {servidor.filter((d) => !d.anulado).map((d) => (
                  <Fila key={d.id} folio={(d as unknown as { folio_ticket?: number }).folio_ticket ?? null}
                        equipo={d.equipo ?? d.equipo_descripcion ?? '—'}
                        litros={d.litros} hora={d.hora} />
                ))}
              </div>
            </section>

            <p className="text-center text-[11px] text-gray-400">
              Catálogo bajado {descarga ? new Date(descarga).toLocaleString('es-CL') : 'nunca'} ·{' '}
              <button onClick={async () => {
                        try {
                          const n = await descargarCatalogo(FAENA)
                          setCat(await getCatalogoOffline(FAENA))
                          setDescarga(await ultimaDescarga(FAENA))
                          toast.success(`Actualizado: ${n} equipos.`)
                        } catch (e) { toast.error(errorMessage(e, 'No se pudo actualizar')) }
                      }}
                      className="underline">actualizar</button>
            </p>
          </>
        )}
      </main>

      {/* ── Botón de nueva carga ───────────────────────────────────────── */}
      {cat && !abierto && (
        <div className="fixed inset-x-0 bottom-0 z-20 mx-auto max-w-[480px] border-t border-gray-200 bg-white p-3">
          <button onClick={nuevaCarga}
                  className="flex h-16 w-full items-center justify-center gap-2 rounded-xl bg-gray-900 text-xl font-bold text-white">
            <Plus className="h-6 w-6" /> Nueva carga
          </button>
        </div>
      )}

      {/* ── El formulario ──────────────────────────────────────────────── */}
      {abierto && cat && (
        <div className="fixed inset-0 z-30 mx-auto max-w-[480px] overflow-y-auto bg-white">
          <header className="sticky top-0 z-10 flex items-center gap-3 border-b border-gray-200 bg-white px-4 py-3">
            <button onClick={() => setAbierto(false)} aria-label="Cerrar"
                    className="shrink-0 rounded-lg p-1.5 text-gray-500 hover:bg-gray-100">
              <X className="h-5 w-5" />
            </button>
            <p className="flex-1 text-base font-bold text-gray-900">Nueva carga</p>
          </header>

          <div className="space-y-4 p-4 pb-32">
            {/* El folio, primero */}
            <label className="block">
              <span className="flex items-center gap-1.5 text-sm font-bold text-gray-900">
                <Ticket className="h-4 w-4" /> Folio del ticket
              </span>
              <input value={folio} onChange={(e) => setFolio(e.target.value.replace(/[^\d]/g, ''))}
                     inputMode="numeric" placeholder="21707" autoFocus
                     className="mt-1 h-16 w-full rounded-xl border-2 border-gray-900 px-4 text-right text-3xl font-bold tabular-nums" />
              <span className="mt-1 block text-xs text-gray-500">
                El número que salió impreso. Es lo que amarra esta carga al papel.
              </span>
            </label>

            {/* Concepto */}
            <div>
              <p className="mb-1.5 text-sm font-semibold text-gray-800">¿Qué movimiento es?</p>
              <div className="grid grid-cols-2 gap-2">
                {CONCEPTOS.map((c) => (
                  <button key={c.k} onClick={() => setTipoMov(c.k)}
                          className={cn('h-12 rounded-xl border-2 text-sm font-bold',
                                        tipoMov === c.k ? 'border-gray-900 bg-gray-900 text-white'
                                                        : 'border-gray-300 bg-white text-gray-600')}>
                    {c.t}
                  </button>
                ))}
              </div>
              {tipoMov !== 'venta' && (
                <p className="mt-1.5 text-xs text-amber-800">
                  No es venta: no descuenta inventario ni se le factura a nadie.
                </p>
              )}
            </div>

            {tipoMov === 'trasvasije' && (
              <label className="block">
                <span className="text-sm font-semibold text-gray-800">¿A qué camión?</span>
                <select value={destinoId} onChange={(e) => setDestinoId(e.target.value)}
                        className="mt-1 h-14 w-full rounded-xl border-2 border-gray-300 px-3 text-base font-semibold">
                  <option value="">Elegir…</option>
                  {cat.camiones.filter((c) => c.id !== camionId).map((c) => (
                    <option key={c.id} value={c.id}>{c.nombre}{c.patente ? ` · ${c.patente}` : ''}</option>
                  ))}
                </select>
              </label>
            )}

            {/* El equipo */}
            <div>
              <p className="mb-1.5 text-sm font-semibold text-gray-800">
                {tipoMov === 'venta' ? '¿A quién se cargó?' : '¿A qué equipo o destino?'}
              </p>
              {equipo ? (
                <div className="flex items-center gap-2 rounded-xl border-2 border-emerald-500 bg-emerald-50 p-3">
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-bold text-gray-900">{equipo.nombre}</p>
                    <p className="truncate text-xs text-gray-600">
                      {equipo.descripcion}{equipo.ceco ? ` · CECO ${equipo.ceco}` : ''}
                    </p>
                  </div>
                  <button onClick={() => setEquipo(null)} aria-label="Cambiar"
                          className="shrink-0 rounded-full bg-white p-2 text-gray-500">
                    <X className="h-4 w-4" />
                  </button>
                </div>
              ) : (
                <>
                  <div className="relative">
                    <Search className="pointer-events-none absolute left-3 top-1/2 h-5 w-5 -translate-y-1/2 text-gray-400" />
                    <input value={buscar} onChange={(e) => setBuscar(e.target.value)}
                           placeholder="Buscar por código, tipo o empresa"
                           className="h-14 w-full rounded-xl border-2 border-gray-300 pl-11 pr-3 text-base" />
                  </div>
                  <div className="mt-2 max-h-56 space-y-1 overflow-y-auto">
                    {equipos.map((e) => (
                      <button key={e.id} onClick={() => { setEquipo(e); setBuscar('') }}
                              className="flex w-full items-center gap-2 rounded-lg border border-gray-200 p-2.5 text-left active:bg-gray-50">
                        <div className="min-w-0 flex-1">
                          <p className="truncate text-sm font-bold text-gray-900">{e.nombre}</p>
                          <p className="truncate text-[11px] text-gray-500">
                            {e.descripcion}{e.ceco ? ` · ${e.ceco}` : ''}
                          </p>
                        </div>
                      </button>
                    ))}
                  </div>
                  <input value={equipoTexto} onChange={(e) => setEquipoTexto(e.target.value)}
                         placeholder="…o escríbalo si no está en la lista"
                         className="mt-2 h-12 w-full rounded-xl border-2 border-dashed border-gray-300 px-3 text-sm" />
                  {equipoTexto.trim() && (
                    <input value={cecoTexto} onChange={(e) => setCecoTexto(e.target.value)}
                           placeholder="CECO o empresa, si la sabe"
                           className="mt-2 h-12 w-full rounded-xl border-2 border-dashed border-gray-300 px-3 text-sm" />
                  )}
                </>
              )}
            </div>

            {/* Ubicación */}
            <label className="block">
              <span className="flex items-center gap-1.5 text-sm font-semibold text-gray-800">
                <MapPin className="h-4 w-4" /> ¿Dónde?
              </span>
              <select value={ubicacionId} onChange={(e) => setUbicacionId(e.target.value)}
                      className="mt-1 h-14 w-full rounded-xl border-2 border-gray-300 px-3 text-base">
                <option value="">Sin indicar</option>
                {cat.ubicaciones.map((u) => <option key={u.id} value={u.id}>{u.nombre}</option>)}
              </select>
            </label>

            {/* El medidor */}
            <div className="space-y-2 rounded-xl border-2 border-gray-300 p-3">
              <p className="flex items-center gap-1.5 text-sm font-bold text-gray-900">
                <Fuel className="h-4 w-4" /> El medidor
              </p>
              <div className="grid grid-cols-2 gap-2">
                <label className="block">
                  <span className="text-xs font-semibold text-gray-600">Inicial</span>
                  <input value={meterIni} onChange={(e) => setMeterIni(e.target.value)} inputMode="decimal"
                         className="mt-1 h-14 w-full rounded-lg border-2 border-gray-300 px-2 text-right text-xl font-bold tabular-nums" />
                </label>
                <label className="block">
                  <span className="text-xs font-semibold text-gray-600">Final</span>
                  <input value={meterFin} onChange={(e) => setMeterFin(e.target.value)} inputMode="decimal"
                         className="mt-1 h-14 w-full rounded-lg border-2 border-gray-300 px-2 text-right text-xl font-bold tabular-nums" />
                </label>
              </div>
              {litrosCalc != null ? (
                <p className="rounded-lg bg-emerald-50 p-2 text-center font-mono text-2xl font-bold tabular-nums text-emerald-800">
                  {miles(litrosCalc)} L
                </p>
              ) : (
                <label className="block">
                  <span className="text-xs font-semibold text-gray-600">
                    O escriba los litros directo, si el medidor no se pudo leer
                  </span>
                  <input value={litrosManual} onChange={(e) => setLitrosManual(e.target.value)}
                         inputMode="decimal" placeholder="0"
                         className="mt-1 h-14 w-full rounded-lg border-2 border-gray-300 px-3 text-right text-xl font-bold tabular-nums" />
                </label>
              )}
            </div>

            {/* La foto */}
            {fotoFin ? (
              <div className="relative">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={fotoFin.preview} alt="medidor"
                     className="h-36 w-full rounded-xl border-2 border-emerald-400 object-cover" />
                <button onClick={() => setFotoFin(null)} aria-label="Quitar foto"
                        className="absolute right-2 top-2 rounded-full bg-white/95 p-2 text-red-600 shadow">
                  <X className="h-4 w-4" />
                </button>
              </div>
            ) : (
              <>
                <label className="flex h-14 cursor-pointer items-center justify-center gap-2 rounded-xl border-2 border-dashed border-amber-400 bg-amber-50 text-base font-bold text-amber-800">
                  <Camera className="h-5 w-5" /> Foto del medidor
                  <input type="file" accept="image/*" capture="environment" className="hidden"
                         onChange={(e) => {
                           const f = e.target.files?.[0]
                           if (f) setFotoFin({ file: f, preview: URL.createObjectURL(f) })
                         }} />
                </label>
                <input value={sinFotoMotivo} onChange={(e) => setSinFotoMotivo(e.target.value)}
                       placeholder="…o escriba por qué no pudo sacarla"
                       className="h-12 w-full rounded-xl border-2 border-dashed border-gray-300 px-3 text-sm" />
              </>
            )}

            <input value={obs} onChange={(e) => setObs(e.target.value)}
                   placeholder="Observación (opcional)"
                   className="h-12 w-full rounded-xl border-2 border-gray-300 px-3 text-sm" />
          </div>

          <div className="fixed inset-x-0 bottom-0 mx-auto max-w-[480px] border-t border-gray-200 bg-white p-3">
            <button onClick={() => void guardar()} disabled={guardando}
                    className="flex h-16 w-full items-center justify-center gap-2 rounded-xl bg-gray-900 text-xl font-bold text-white disabled:opacity-50">
              {guardando ? <Spinner className="h-6 w-6" /> : <Check className="h-6 w-6" />}
              Guardar carga
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

function Fila({ folio, equipo, litros, hora, pendiente }: {
  folio: number | null; equipo: string; litros: number; hora: string | null; pendiente?: boolean
}) {
  return (
    <div className={cn('flex items-center gap-2 rounded-lg border p-2.5',
                       pendiente ? 'border-amber-300 bg-amber-50' : 'border-gray-200')}>
      <span className="w-14 shrink-0 font-mono text-xs font-bold tabular-nums text-gray-500">
        {folio ?? '—'}
      </span>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-semibold text-gray-900">{equipo}</p>
        {hora && <p className="text-[11px] text-gray-500">{hora.slice(0, 5)}</p>}
      </div>
      {pendiente && <CloudOff className="h-4 w-4 shrink-0 text-amber-600" />}
      <span className="shrink-0 font-mono text-sm font-bold tabular-nums text-gray-900">
        {miles(litros)} L
      </span>
    </div>
  )
}
