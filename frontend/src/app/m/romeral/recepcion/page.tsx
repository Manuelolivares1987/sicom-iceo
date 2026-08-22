'use client'

// ============================================================================
// Recepción de flota primaria — Romeral (MIG320)
// ----------------------------------------------------------------------------
// Se llena mientras el camión descarga, no después. Dos razones concretas:
//
//   1. LA GUÍA SE VA CON EL CAMIÓN. Si la foto no se saca ahora, no se saca.
//   2. Se piden DOS números distintos a propósito: lo que dice la guía y lo que
//      entró al estanque. Quien captura ambos suele preguntar por qué no dan
//      igual — y esa pregunta, hecha con el chofer todavía ahí, es el control.
//      Si se guarda un solo número, la diferencia desaparece.
//
// Una recepción mal registrada mueve el inventario durante días y se persigue
// como si fuera una pérdida (Anexo A.5 del instructivo).
// ============================================================================

import { useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, Camera, X, Check, CloudOff, Truck, Plus, FileText, AlertTriangle,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { useNetworkStatus } from '@/hooks/use-calama-offline'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { cn, errorMessage } from '@/lib/utils'
import { FAENA_ROMERAL, getFaenaPorCodigo } from '@/lib/services/combustible-faena'
import {
  registrarRecepcion, getRecepcionesDia, subirFotoMedicion,
  type PuntoMedicion, type Recepcion,
} from '@/lib/services/combustible-cierre'
import { getPuntosOffline, descargarCatalogoCierre } from '@/lib/offline/combustible-cierre-offline'

const hoyISO = () => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}
const miles = (n: number | null | undefined) =>
  n == null || Number.isNaN(Number(n)) ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 0 })

export default function RecepcionRomeralPage() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil } = useAuth()
  const online = useNetworkStatus()
  const toast = useToast()

  const [faenaId, setFaenaId] = useState<string | null>(null)
  const [puntos, setPuntos] = useState<PuntoMedicion[]>([])
  const [delDia, setDelDia] = useState<Recepcion[]>([])
  const [cargando, setCargando] = useState(true)
  const [guardando, setGuardando] = useState(false)

  const [fecha, setFecha] = useState(hoyISO())
  const [guia, setGuia] = useState('')
  const [viaje, setViaje] = useState('')
  const [camion, setCamion] = useState('')
  const [litrosGuia, setLitrosGuia] = useState('')
  const [sello, setSello] = useState('')
  const [obs, setObs] = useState('')
  const [recibidoPor, setRecibidoPor] = useState('')
  const [reparto, setReparto] = useState<Record<string, string>>({})
  const [foto, setFoto] = useState<{ file: File; preview: string } | null>(null)
  const [sinFotoMotivo, setSinFotoMotivo] = useState('')

  const cargar = useCallback(async () => {
    setCargando(true)
    try {
      const local = await getPuntosOffline()
      if (local) setPuntos(local)
      const f = await getFaenaPorCodigo(FAENA_ROMERAL)
      if (f) {
        setFaenaId(f.id)
        if (!local) setPuntos(await descargarCatalogoCierre(f.id))
        setDelDia(await getRecepcionesDia(f.id, fecha))
      }
    } catch { /* sin señal: se trabaja con lo bajado */ } finally { setCargando(false) }
  }, [fecha])

  useEffect(() => { void cargar() }, [cargar])
  useEffect(() => { if (perfil?.nombre_completo && !recibidoPor) setRecibidoPor(perfil.nombre_completo) },
    [perfil, recibidoPor])

  // Sólo los estanques fijos reciben de flota primaria; un camión aljibe se
  // llena por trasvasije desde un estanque, que es otro movimiento.
  const estanquesFijos = useMemo(() => puntos.filter((p) => p.tipo === 'fijo'), [puntos])

  const totalRepartido = useMemo(
    () => Object.values(reparto).reduce((a, v) => a + (Number(v) || 0), 0),
    [reparto],
  )
  const guiaNum = Number(litrosGuia) || 0
  const diferencia = guiaNum > 0 ? totalRepartido - guiaNum : null

  const limpiar = () => {
    setGuia(''); setViaje(''); setCamion(''); setLitrosGuia(''); setSello(''); setObs('')
    setReparto({}); setFoto(null); setSinFotoMotivo('')
  }

  const guardar = async (confirmar: boolean) => {
    if (!faenaId) { toast.error('Necesita señal una vez para cargar la faena.'); return }
    if (totalRepartido <= 0) { toast.error('Indique cuántos litros entraron y a qué estanque.'); return }
    setGuardando(true)
    try {
      let fotoUrl: string | null = null
      if (foto) fotoUrl = await subirFotoMedicion(foto.file)

      const r = await registrarRecepcion({
        faenaId, fecha,
        destinos: Object.entries(reparto)
          .filter(([, v]) => Number(v) > 0)
          .map(([estanque_id, v]) => ({ estanque_id, litros: Number(v) })),
        guia: guia || null, viaje: viaje || null, camion: camion || null,
        litrosGuia: guiaNum || null,
        recibidoPor: recibidoPor || null, sello: sello || null, observacion: obs || null,
        fotoGuia: fotoUrl, sinFotoMotivo: sinFotoMotivo || null,
        confirmar,
        clientUuid: `rec-${fecha}-${guia || Date.now()}`,
      })
      toast.success(
        confirmar
          ? `Recepción confirmada: ${miles(r.litros_recibidos)} L`
          : `Guardada: ${miles(r.litros_recibidos)} L`,
      )
      limpiar()
      setDelDia(await getRecepcionesDia(faenaId, fecha))
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo guardar la recepción'))
    } finally { setGuardando(false) }
  }

  if (verificando) return <div className="flex min-h-screen items-center justify-center bg-gray-50"><Spinner className="h-8 w-8" /></div>
  if (sinSesionOffline) return <SinSesionOffline />

  return (
    <div className="min-h-screen bg-gray-50 pb-10">
      <header className="sticky top-0 z-10 border-b border-gray-200 bg-white px-4 py-3">
        <div className="mx-auto flex max-w-lg items-center gap-3">
          <Link href="/m/romeral" className="shrink-0 rounded-lg p-1.5 text-gray-500 hover:bg-gray-100">
            <ArrowLeft className="h-5 w-5" />
          </Link>
          <div className="min-w-0 flex-1">
            <p className="text-base font-bold leading-tight text-gray-900">Recepción de camión</p>
            <p className="text-xs text-gray-500">Flota primaria · {fecha}</p>
          </div>
          {!online && (
            <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-amber-100 px-2.5 py-1 text-xs font-bold text-amber-800">
              <CloudOff className="h-3.5 w-3.5" /> Sin señal
            </span>
          )}
        </div>
      </header>

      <main className="mx-auto max-w-lg space-y-4 px-4 py-5">
        {cargando && <div className="flex justify-center py-6"><Spinner /></div>}

        {/* La guía */}
        <section className="space-y-4 rounded-xl border border-gray-200 bg-white p-4">
          <p className="flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-500">
            <FileText className="h-4 w-4" /> La guía que trae el camión
          </p>

          <div className="grid grid-cols-2 gap-3">
            <label className="block">
              <span className="text-sm font-semibold text-gray-800">N° de guía</span>
              <input value={guia} onChange={(e) => setGuia(e.target.value)} inputMode="numeric"
                     className="mt-1 h-14 w-full rounded-xl border-2 border-gray-300 px-3 text-lg font-bold tabular-nums" />
            </label>
            <label className="block">
              <span className="text-sm font-semibold text-gray-800">N° de viaje</span>
              <input value={viaje} onChange={(e) => setViaje(e.target.value)} inputMode="numeric"
                     className="mt-1 h-14 w-full rounded-xl border-2 border-gray-300 px-3 text-lg font-bold tabular-nums" />
            </label>
          </div>

          <label className="block">
            <span className="text-sm font-semibold text-gray-800">Patente del camión</span>
            <input value={camion} onChange={(e) => setCamion(e.target.value.toUpperCase())}
                   placeholder="JA5655"
                   className="mt-1 h-14 w-full rounded-xl border-2 border-gray-300 px-3 text-lg font-bold uppercase" />
          </label>

          <label className="block">
            <span className="text-sm font-semibold text-gray-800">¿Cuántos litros dice la guía?</span>
            <input value={litrosGuia} onChange={(e) => setLitrosGuia(e.target.value.replace(/[^\d]/g, ''))}
                   inputMode="numeric" placeholder="0"
                   className="mt-1 h-16 w-full rounded-xl border-2 border-gray-300 px-4 text-right text-3xl font-bold tabular-nums" />
          </label>

          {/* La foto de la guía: se va con el camión */}
          {foto ? (
            <div className="relative">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={foto.preview} alt="guía" className="h-32 w-full rounded-xl border-2 border-emerald-400 object-cover" />
              <button onClick={() => setFoto(null)}
                      className="absolute right-2 top-2 rounded-full bg-white/95 p-2 text-red-600 shadow">
                <X className="h-4 w-4" />
              </button>
            </div>
          ) : (
            <>
              <label className="flex h-14 cursor-pointer items-center justify-center gap-2 rounded-xl border-2 border-dashed border-amber-400 bg-amber-50 text-lg font-bold text-amber-800">
                <Camera className="h-5 w-5" /> Foto de la guía
                <input type="file" accept="image/*" capture="environment" className="hidden"
                       onChange={(e) => {
                         const f = e.target.files?.[0]
                         if (f) setFoto({ file: f, preview: URL.createObjectURL(f) })
                         e.target.value = ''
                       }} />
              </label>
              <input value={sinFotoMotivo} onChange={(e) => setSinFotoMotivo(e.target.value)}
                     placeholder="Si no puede sacarla, escriba por qué"
                     className="h-12 w-full rounded-xl border-2 border-gray-300 px-3 text-base" />
            </>
          )}
        </section>

        {/* Dónde quedó */}
        <section className="space-y-3 rounded-xl border border-gray-200 bg-white p-4">
          <p className="flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-500">
            <Truck className="h-4 w-4" /> ¿En qué estanque quedó?
          </p>
          <p className="text-sm text-gray-500">
            Si descargó en más de uno, ponga los litros de cada uno.
          </p>

          {estanquesFijos.map((e) => (
            <label key={e.id} className="flex items-center gap-3">
              <span className="min-w-0 flex-1 text-base font-semibold text-gray-800">{e.nombre}</span>
              <input
                value={reparto[e.id] ?? ''}
                onChange={(ev) => setReparto((r) => ({ ...r, [e.id]: ev.target.value.replace(/[^\d]/g, '') }))}
                inputMode="numeric" placeholder="0"
                className="h-14 w-32 shrink-0 rounded-xl border-2 border-gray-300 px-3 text-right text-xl font-bold tabular-nums"
              />
            </label>
          ))}

          {/* El control: la guía contra lo que entró */}
          {totalRepartido > 0 && (
            <div className={cn(
              'rounded-xl border-2 p-3',
              diferencia == null ? 'border-gray-300 bg-gray-50'
                : diferencia === 0 ? 'border-emerald-400 bg-emerald-50'
                : 'border-amber-400 bg-amber-50',
            )}>
              <p className="flex justify-between text-base text-gray-700">
                <span>Entró al estanque</span>
                <span className="font-bold tabular-nums">{miles(totalRepartido)} L</span>
              </p>
              {diferencia != null && (
                <>
                  <p className="flex justify-between text-base text-gray-700">
                    <span>Dice la guía</span>
                    <span className="font-bold tabular-nums">{miles(guiaNum)} L</span>
                  </p>
                  <p className={cn(
                    'mt-1 flex justify-between border-t pt-1 text-base font-bold',
                    diferencia === 0 ? 'border-emerald-300 text-emerald-900' : 'border-amber-300 text-amber-900',
                  )}>
                    <span>{diferencia === 0 ? 'Coinciden' : 'Diferencia'}</span>
                    <span className="tabular-nums">
                      {diferencia === 0 ? '✓' : `${diferencia > 0 ? '+' : ''}${miles(diferencia)} L`}
                    </span>
                  </p>
                  {diferencia !== 0 && (
                    <p className="mt-1 flex items-start gap-1.5 text-sm text-amber-800">
                      <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
                      Pregúntele al chofer antes de que se vaya, y anótelo abajo.
                    </p>
                  )}
                </>
              )}
            </div>
          )}
        </section>

        {/* Quién recibió */}
        <section className="space-y-3 rounded-xl border border-gray-200 bg-white p-4">
          <label className="block">
            <span className="text-sm font-semibold text-gray-800">¿Quién recibió?</span>
            <input value={recibidoPor} onChange={(e) => setRecibidoPor(e.target.value)}
                   className="mt-1 h-14 w-full rounded-xl border-2 border-gray-300 px-3 text-lg" />
          </label>
          <label className="block">
            <span className="text-sm font-semibold text-gray-800">Sello (opcional)</span>
            <input value={sello} onChange={(e) => setSello(e.target.value)}
                   className="mt-1 h-14 w-full rounded-xl border-2 border-gray-300 px-3 text-lg" />
          </label>
          <label className="block">
            <span className="text-sm font-semibold text-gray-800">Observación</span>
            <textarea value={obs} onChange={(e) => setObs(e.target.value)} rows={2}
                      placeholder="Lo que no cabe en un número"
                      className="mt-1 w-full rounded-xl border-2 border-gray-300 p-3 text-base" />
          </label>
        </section>

        <div className="space-y-2">
          <button
            onClick={() => guardar(true)}
            disabled={guardando || totalRepartido <= 0 || (!foto && !sinFotoMotivo.trim())}
            className="inline-flex h-14 w-full items-center justify-center gap-2 rounded-xl bg-emerald-600 text-lg font-bold text-white disabled:opacity-40"
          >
            {guardando ? <Spinner className="h-5 w-5" /> : <><Check className="h-5 w-5" /> Confirmar recepción</>}
          </button>
          {!foto && !sinFotoMotivo.trim() && totalRepartido > 0 && (
            <p className="text-center text-sm text-amber-700">
              Falta la foto de la guía. La guía se va con el camión.
            </p>
          )}
          <button
            onClick={() => guardar(false)}
            disabled={guardando || totalRepartido <= 0}
            className="inline-flex h-14 w-full items-center justify-center gap-2 rounded-xl border-2 border-gray-300 bg-white text-lg font-bold text-gray-700 disabled:opacity-40"
          >
            <Plus className="h-5 w-5" /> Guardar sin confirmar
          </button>
        </div>

        {/* Lo que ya se recibió hoy */}
        {delDia.length > 0 && (
          <section className="rounded-xl border border-gray-200 bg-white">
            <p className="border-b border-gray-100 px-4 py-3 text-sm font-bold uppercase tracking-wide text-gray-500">
              Recibido hoy ({delDia.length})
            </p>
            {delDia.map((r) => (
              <div key={r.id} className="flex items-center gap-3 border-b border-gray-100 px-4 py-3 last:border-0">
                <div className="min-w-0 flex-1">
                  <p className="text-base font-bold text-gray-900">
                    {miles(r.litros_recibidos)} L
                    {r.guia && <span className="ml-2 text-sm font-normal text-gray-500">guía {r.guia}</span>}
                  </p>
                  <p className="truncate text-xs text-gray-500">
                    {r.camion ?? 'sin patente'}
                    {r.destinos?.length ? ` · ${r.destinos.map((d) => d.estanque).join(', ')}` : ''}
                  </p>
                </div>
                {r.diferencia_vs_guia != null && r.diferencia_vs_guia !== 0 && (
                  <span className="shrink-0 rounded bg-amber-100 px-2 py-1 text-xs font-bold text-amber-800">
                    {r.diferencia_vs_guia > 0 ? '+' : ''}{miles(r.diferencia_vs_guia)} L
                  </span>
                )}
                <span className={cn(
                  'shrink-0 rounded px-2 py-1 text-xs font-bold',
                  r.estado === 'confirmada' ? 'bg-emerald-100 text-emerald-700' : 'bg-gray-100 text-gray-500',
                )}>
                  {r.estado === 'confirmada' ? 'Confirmada' : 'Borrador'}
                </span>
              </div>
            ))}
          </section>
        )}
      </main>
    </div>
  )
}
