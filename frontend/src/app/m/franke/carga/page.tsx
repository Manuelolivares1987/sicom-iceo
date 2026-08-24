'use client'

// ============================================================================
// Carga del camión en la estación de servicio — Franke (MIG369)
// ----------------------------------------------------------------------------
// Es el lado de las entradas del balance: en julio fueron 221.683 litros, todos
// por el surtidor 3 de EDS Mina. Sin este registro el balance sólo tiene
// salidas y no cierra contra nada.
//
// SE PIDEN LOS DOS NÚMEROS A PROPÓSITO
// Lo que marcó el surtidor y lo que entró según el medidor del camión. La
// pantalla los pone uno al lado del otro y muestra la diferencia apenas están
// los dos — con el camión todavía en la estación, que es cuando se puede
// preguntar. Guardar uno solo hace desaparecer la diferencia.
//
// EL SUPERVISOR, NO EL CONDUCTOR
// Lo que entra es lo que después se factura. Es la misma puerta que Romeral le
// pone a la recepción de flota primaria (MIG343).
// ============================================================================

import { useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, Camera, X, Check, CloudOff, Truck, Ticket, Gauge, Fuel, AlertTriangle,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { useNetworkStatus } from '@/hooks/use-calama-offline'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { cn, errorMessage } from '@/lib/utils'
import { FAENA_FRANKE, getFaenaId } from '@/lib/services/faena-pauta'
import {
  registrarRecepcion, getRecepcionesDia, subirFotoMedicion, getPuntosMedicion,
  type PuntoMedicion, type Recepcion,
} from '@/lib/services/combustible-cierre'

const hoyISO = () => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}
const horaAhora = () => {
  const d = new Date()
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}
const miles = (n: number | null | undefined) =>
  n == null || Number.isNaN(Number(n)) ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 0 })

// Los que la faena usa. En julio se cargó exclusivamente por el 3 de EDS Mina.
const EDS = ['Mina', 'Planta']
const SURTIDORES = ['1', '3']

export default function CargaEdsPage() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil } = useAuth()
  const online = useNetworkStatus()
  const toast = useToast()

  const [faenaId, setFaenaId] = useState<string | null>(null)
  const [camiones, setCamiones] = useState<PuntoMedicion[]>([])
  const [delDia, setDelDia] = useState<Recepcion[]>([])
  const [cargando, setCargando] = useState(true)
  const [guardando, setGuardando] = useState(false)

  const fecha = hoyISO()
  const [camionId, setCamionId] = useState('')
  const [eds, setEds] = useState('Mina')
  const [surtidor, setSurtidor] = useState('3')
  const [folio, setFolio] = useState('')
  const [litrosSurtidor, setLitrosSurtidor] = useState('')
  const [meterIni, setMeterIni] = useState('')
  const [meterFin, setMeterFin] = useState('')
  const [obs, setObs] = useState('')
  const [foto, setFoto] = useState<{ file: File; preview: string } | null>(null)
  const [sinFotoMotivo, setSinFotoMotivo] = useState('')

  const cargar = useCallback(async () => {
    setCargando(true)
    try {
      const f = await getFaenaId(FAENA_FRANKE)
      if (!f) { toast.error('No se encontró la faena Franke.'); return }
      setFaenaId(f)
      const puntos = await getPuntosMedicion(f)
      // En Franke el combustible entra al camión, no a un estanque fijo.
      setCamiones(puntos.filter((p) => p.tipo === 'movil'))
      setDelDia(await getRecepcionesDia(f, fecha))
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo cargar'))
    } finally { setCargando(false) }
  }, [fecha, toast])

  useEffect(() => { void cargar() }, [cargar])

  const litrosMedidor = useMemo(() => {
    const a = Number(meterIni), b = Number(meterFin)
    return Number.isFinite(a) && Number.isFinite(b) && meterIni !== '' && meterFin !== '' && b >= a
      ? Math.round((b - a) * 10) / 10 : null
  }, [meterIni, meterFin])

  const litrosGuia = Number(litrosSurtidor) || null
  const diferencia = litrosGuia != null && litrosMedidor != null ? litrosGuia - litrosMedidor : null
  const camion = camiones.find((c) => c.id === camionId) ?? null

  const limpiar = () => {
    setFolio(''); setLitrosSurtidor(''); setMeterIni(''); setMeterFin('')
    setObs(''); setFoto(null); setSinFotoMotivo('')
  }

  const guardar = async () => {
    if (!faenaId) return
    if (!camionId) { toast.error('¿A qué camión se cargó?'); return }
    if (!folio.trim()) { toast.error('Escriba el folio del ticket del surtidor.'); return }
    if (!litrosGuia || litrosGuia <= 0) { toast.error('¿Cuántos litros marcó el surtidor?'); return }
    if (!foto && !sinFotoMotivo.trim()) {
      toast.error('Saque la foto del ticket, o escriba por qué no pudo. El ticket se queda en la estación.')
      return
    }
    setGuardando(true)
    try {
      const fotoUrl = foto ? await subirFotoMedicion(foto.file) : null
      const r = await registrarRecepcion({
        faenaId, fecha,
        destinos: [{ estanque_id: camionId, litros: litrosMedidor ?? litrosGuia }],
        // En Franke no hay guía de proveedor: hay un ticket de surtidor.
        guia: folio.trim(),
        camion: camion?.patente ?? camion?.nombre ?? null,
        proveedor: `EDS ${eds}`,
        litrosGuia,
        hora: horaAhora(),
        recibidoPor: perfil?.nombre_completo ?? null,
        observacion: obs.trim() || null,
        fotoGuia: fotoUrl,
        sinFotoMotivo: !foto ? sinFotoMotivo.trim() : null,
        confirmar: true,
        clientUuid: `carga-${fecha}-${folio.trim()}`,
        sinSenal: !online,
        eds: `EDS ${eds}`,
        surtidor,
        folioTicket: Number(folio.trim()),
        meterInicial: meterIni !== '' ? Number(meterIni) : null,
        meterFinal: meterFin !== '' ? Number(meterFin) : null,
      })
      toast.success(
        r.diferencia_surtidor_medidor != null && Math.abs(r.diferencia_surtidor_medidor) > 0
          ? `Carga registrada. El surtidor marcó ${miles(litrosGuia)} L y el camión recibió ${miles(r.litros_medidor)} L: ${r.diferencia_surtidor_medidor > 0 ? '+' : ''}${miles(r.diferencia_surtidor_medidor)} L de diferencia.`
          : `Carga registrada: ${miles(litrosGuia)} L.`,
      )
      limpiar()
      setDelDia(await getRecepcionesDia(faenaId, fecha))
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo registrar la carga'))
    } finally { setGuardando(false) }
  }

  if (verificando) {
    return <div className="flex min-h-screen items-center justify-center bg-gray-50"><Spinner className="h-8 w-8" /></div>
  }
  if (sinSesionOffline) return <SinSesionOffline />

  const totalDia = delDia.reduce((a, r) => a + Number(r.litros_guia ?? 0), 0)

  return (
    <div className="min-h-screen bg-gray-50 pb-28">
      <header className="sticky top-0 z-10 border-b border-gray-200 bg-white px-4 pb-3 pt-[max(0.75rem,env(safe-area-inset-top))]">
        <div className="flex items-center gap-3">
          <Link href="/m/franke" className="shrink-0 rounded-lg p-1.5 text-gray-500 hover:bg-gray-100">
            <ArrowLeft className="h-5 w-5" />
          </Link>
          <div className="min-w-0 flex-1">
            <p className="text-base font-bold leading-tight text-gray-900">Carga del camión</p>
            <p className="text-xs text-gray-500">Estación de servicio · {fecha}</p>
          </div>
          {!online && (
            <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-amber-100 px-2 py-1 text-[11px] font-bold text-amber-800">
              <CloudOff className="h-3.5 w-3.5" /> Sin señal
            </span>
          )}
        </div>
      </header>

      <main className="space-y-4 px-4 py-4">
        {cargando && <div className="flex justify-center py-8"><Spinner /></div>}

        <section className="space-y-4 rounded-xl border border-gray-200 bg-white p-4">
          <p className="flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-500">
            <Truck className="h-4 w-4" /> Dónde y a qué camión
          </p>

          <label className="block">
            <span className="text-sm font-semibold text-gray-800">Camión que se cargó</span>
            <select value={camionId} onChange={(e) => setCamionId(e.target.value)}
                    className="mt-1 h-14 w-full rounded-xl border-2 border-gray-300 px-3 text-base font-semibold">
              <option value="">Elegir…</option>
              {camiones.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.nombre}{c.patente ? ` · ${c.patente}` : ''}
                </option>
              ))}
            </select>
          </label>

          <div>
            <span className="text-sm font-semibold text-gray-800">Estación</span>
            <div className="mt-1 flex gap-2">
              {EDS.map((e) => (
                <button key={e} onClick={() => setEds(e)}
                        className={cn('h-12 flex-1 rounded-xl border-2 text-sm font-bold',
                                      eds === e ? 'border-gray-900 bg-gray-900 text-white'
                                                : 'border-gray-300 bg-white text-gray-600')}>
                  EDS {e}
                </button>
              ))}
            </div>
          </div>

          <div>
            <span className="text-sm font-semibold text-gray-800">Surtidor</span>
            <div className="mt-1 flex gap-2">
              {SURTIDORES.map((s) => (
                <button key={s} onClick={() => setSurtidor(s)}
                        className={cn('h-12 flex-1 rounded-xl border-2 text-sm font-bold',
                                      surtidor === s ? 'border-gray-900 bg-gray-900 text-white'
                                                     : 'border-gray-300 bg-white text-gray-600')}>
                  N° {s}
                </button>
              ))}
            </div>
          </div>
        </section>

        <section className="space-y-4 rounded-xl border-2 border-gray-900 bg-white p-4">
          <p className="flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-700">
            <Ticket className="h-4 w-4" /> Lo que dice el surtidor
          </p>
          <label className="block">
            <span className="text-sm font-semibold text-gray-800">Folio del ticket</span>
            <input value={folio} onChange={(e) => setFolio(e.target.value.replace(/[^\d]/g, ''))}
                   inputMode="numeric" placeholder="794"
                   className="mt-1 h-14 w-full rounded-xl border-2 border-gray-300 px-3 text-right text-2xl font-bold tabular-nums" />
          </label>
          <label className="block">
            <span className="text-sm font-semibold text-gray-800">Litros que marcó el surtidor</span>
            <input value={litrosSurtidor} onChange={(e) => setLitrosSurtidor(e.target.value.replace(/[^\d]/g, ''))}
                   inputMode="numeric" placeholder="0"
                   className="mt-1 h-16 w-full rounded-xl border-2 border-gray-300 px-4 text-right text-3xl font-bold tabular-nums" />
          </label>
        </section>

        <section className="space-y-3 rounded-xl border border-gray-200 bg-white p-4">
          <p className="flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-500">
            <Gauge className="h-4 w-4" /> Lo que recibió el camión
          </p>
          <p className="text-xs text-gray-500">
            El medidor del camión, antes y después. Son dos números distintos a propósito.
          </p>
          <div className="grid grid-cols-2 gap-2">
            <label className="block">
              <span className="text-xs font-semibold text-gray-600">Antes</span>
              <input value={meterIni} onChange={(e) => setMeterIni(e.target.value.replace(/[^\d.,]/g, ''))}
                     inputMode="decimal"
                     className="mt-1 h-14 w-full rounded-lg border-2 border-gray-300 px-2 text-right text-xl font-bold tabular-nums" />
            </label>
            <label className="block">
              <span className="text-xs font-semibold text-gray-600">Después</span>
              <input value={meterFin} onChange={(e) => setMeterFin(e.target.value.replace(/[^\d.,]/g, ''))}
                     inputMode="decimal"
                     className="mt-1 h-14 w-full rounded-lg border-2 border-gray-300 px-2 text-right text-xl font-bold tabular-nums" />
            </label>
          </div>

          {litrosMedidor != null && (
            <div className={cn('rounded-lg p-3 text-center',
                               diferencia == null || Math.abs(diferencia) === 0 ? 'bg-emerald-50'
                               : Math.abs(diferencia) <= 50 ? 'bg-amber-50' : 'bg-red-50')}>
              <p className="font-mono text-2xl font-bold tabular-nums text-gray-900">
                {miles(litrosMedidor)} L
              </p>
              {diferencia != null && (
                <p className={cn('mt-1 text-xs font-semibold',
                                 Math.abs(diferencia) === 0 ? 'text-emerald-800'
                                 : Math.abs(diferencia) <= 50 ? 'text-amber-800' : 'text-red-800')}>
                  {Math.abs(diferencia) === 0
                    ? 'Coincide con el surtidor.'
                    : `${diferencia > 0 ? 'Faltan' : 'Sobran'} ${miles(Math.abs(diferencia))} L respecto del surtidor. Pregunte ahora, con el camión todavía acá.`}
                </p>
              )}
            </div>
          )}
        </section>

        {/* La foto del ticket: se queda en la estación */}
        {foto ? (
          <div className="relative">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={foto.preview} alt="ticket"
                 className="h-36 w-full rounded-xl border-2 border-emerald-400 object-cover" />
            <button onClick={() => setFoto(null)} aria-label="Quitar foto"
                    className="absolute right-2 top-2 rounded-full bg-white/95 p-2 text-red-600 shadow">
              <X className="h-4 w-4" />
            </button>
          </div>
        ) : (
          <>
            <label className="flex h-14 cursor-pointer items-center justify-center gap-2 rounded-xl border-2 border-dashed border-amber-400 bg-amber-50 text-base font-bold text-amber-800">
              <Camera className="h-5 w-5" /> Foto del ticket
              <input type="file" accept="image/*" capture="environment" className="hidden"
                     onChange={(e) => {
                       const f = e.target.files?.[0]
                       if (f) setFoto({ file: f, preview: URL.createObjectURL(f) })
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

        {/* Lo del día */}
        <section className="rounded-xl border border-gray-200 bg-white p-4">
          <div className="flex items-baseline justify-between">
            <p className="flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-500">
              <Fuel className="h-4 w-4" /> Cargas de hoy
            </p>
            <p className="font-mono text-lg font-bold tabular-nums text-gray-900">
              {miles(totalDia)} <span className="text-xs font-normal text-gray-500">L</span>
            </p>
          </div>
          <div className="mt-3 space-y-2">
            {delDia.length === 0 && (
              <p className="py-3 text-center text-sm text-gray-400">Todavía no hay cargas hoy.</p>
            )}
            {delDia.map((r) => (
              <div key={r.id} className="flex items-center gap-2 rounded-lg border border-gray-200 p-2.5">
                <span className="w-12 shrink-0 font-mono text-xs font-bold tabular-nums text-gray-500">
                  {r.guia ?? '—'}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-semibold text-gray-900">{r.camion ?? '—'}</p>
                  <p className="truncate text-[11px] text-gray-500">
                    {r.proveedor}{r.hora ? ` · ${r.hora.slice(0, 5)}` : ''}
                  </p>
                </div>
                {r.diferencia_vs_guia != null && Math.abs(Number(r.diferencia_vs_guia)) > 0 && (
                  <AlertTriangle className="h-4 w-4 shrink-0 text-amber-600" />
                )}
                <span className="shrink-0 font-mono text-sm font-bold tabular-nums text-gray-900">
                  {miles(r.litros_guia)} L
                </span>
              </div>
            ))}
          </div>
        </section>
      </main>

      <div className="fixed inset-x-0 bottom-0 z-20 mx-auto max-w-[480px] border-t border-gray-200 bg-white p-3">
        <button onClick={() => void guardar()} disabled={guardando}
                className="flex h-16 w-full items-center justify-center gap-2 rounded-xl bg-gray-900 text-xl font-bold text-white disabled:opacity-50">
          {guardando ? <Spinner className="h-6 w-6" /> : <Check className="h-6 w-6" />}
          Registrar carga
        </button>
      </div>
    </div>
  )
}
