'use client'

// ============================================================================
// Pasar combustible de un estanque a otro (MIG378/382)
// ----------------------------------------------------------------------------
// Es como se carga un camión aljibe. La recepción sólo acepta estaciones fijas
// —un aljibe no se llena del camión proveedor— así que el camión se llena desde
// una estación, y eso es esto.
//
// ANTES ESTABA ESCONDIDO
// Vivía dentro de la pantalla de despacho: había que entrar por «despachar»,
// elegir la estación como si fuera el camión del que se despacha, y recién ahí
// marcar el destino. Nadie lo iba a encontrar. Ahora es su propio camino y se
// lee como lo que es: de dónde sale, a dónde entra, cuántos litros.
//
// ESTO SÍ MUEVE LOS LITROS
// El despacho de Romeral no descuenta stock a propósito: el stock lo fija la
// varilla en cada cierre. Pero un trasvasije no consume, redistribuye entre dos
// puntos de la misma faena, y el neto es cero. Por eso acá los números se
// mueven al instante, y la pantalla muestra cómo queda cada estanque antes de
// confirmar.
// ============================================================================

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import {
  ArrowRight, Camera, Loader2, ChevronLeft, X, AlertTriangle, Fuel, Truck,
} from 'lucide-react'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useAuth } from '@/contexts/auth-context'
import {
  getFaenaPorCodigo, getEstanquesAhora, litrosAhora,
  FAENA_ROMERAL, type EstanqueAhora,
} from '@/lib/services/combustible-faena'
import { guardarTrasvasije, guardarFotoLocal } from '@/lib/offline/combustible-faena-offline'
import { cn } from '@/lib/utils'

const TURNOS = ['dia', 'noche'] as const

export default function TrasvasijePage() {
  useRequireAuth()
  const { perfil } = useAuth()
  const router = useRouter()
  const toast = useToast()

  const [faenaId, setFaenaId] = useState<string | null>(null)
  const [estanques, setEstanques] = useState<EstanqueAhora[]>([])
  const [cargando, setCargando] = useState(true)

  const [origenId, setOrigenId] = useState('')
  const [destinoId, setDestinoId] = useState('')
  const [litros, setLitros] = useState('')
  const [meterIni, setMeterIni] = useState('')
  const [meterFin, setMeterFin] = useState('')
  const [operador, setOperador] = useState('')
  const [turno, setTurno] = useState<string>('dia')
  const [fotoIni, setFotoIni] = useState<{ file: File; url: string } | null>(null)
  const [fotoFin, setFotoFin] = useState<{ file: File; url: string } | null>(null)
  const [sinFoto, setSinFoto] = useState('')
  const [obs, setObs] = useState('')
  const [guardando, setGuardando] = useState(false)

  useEffect(() => {
    if (perfil?.nombre_completo && !operador) setOperador(perfil.nombre_completo)
  }, [perfil, operador])

  const cargar = async () => {
    const f = await getFaenaPorCodigo(FAENA_ROMERAL)
    if (!f) throw new Error('No se encontró la faena Romeral')
    setFaenaId(f.id)
    setEstanques(await getEstanquesAhora(f.id))
  }

  useEffect(() => {
    let cancel = false
    ;(async () => {
      try { if (!cancel) await cargar() }
      catch (e) { if (!cancel) toast.error(e instanceof Error ? e.message : 'No se pudo cargar') }
      finally { if (!cancel) setCargando(false) }
    })()
    return () => { cancel = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const origen = estanques.find((e) => e.id === origenId) ?? null
  const destino = estanques.find((e) => e.id === destinoId) ?? null

  // El medidor manda sobre lo escrito a mano: si están los dos numerales, los
  // litros son la resta, igual que en el despacho.
  const litrosFinales = useMemo(() => {
    const ini = Number(meterIni.replace(',', '.'))
    const fin = Number(meterFin.replace(',', '.'))
    if (Number.isFinite(ini) && Number.isFinite(fin) && meterIni && meterFin && fin >= ini) {
      return fin - ini
    }
    const n = Number(litros.replace(',', '.'))
    return Number.isFinite(n) && n > 0 ? n : null
  }, [meterIni, meterFin, litros])

  const stockOrigen = origen ? Number(origen.stock_teorico_lt ?? 0) : 0
  const cabeEnDestino = destino?.capacidad_lt != null
    ? Number(destino.capacidad_lt) - Number(destino.stock_teorico_lt ?? 0)
    : null

  const problema = useMemo(() => {
    if (!origen || !destino) return null
    if (origen.id === destino.id) return 'El origen y el destino no pueden ser el mismo.'
    if (litrosFinales == null) return null
    if (litrosFinales > stockOrigen) {
      return `El ${origen.codigo} tiene ${stockOrigen.toLocaleString('es-CL')} L. Si en terreno hay más, varille y corrija antes de trasvasijar.`
    }
    if (cabeEnDestino != null && litrosFinales > cabeEnDestino) {
      return `En el ${destino.patente ?? destino.codigo} sólo caben ${cabeEnDestino.toLocaleString('es-CL')} L más.`
    }
    return null
  }, [origen, destino, litrosFinales, stockOrigen, cabeEnDestino])

  const listo = !!faenaId && !!origen && !!destino && litrosFinales != null && litrosFinales > 0
    && !problema && operador.trim().length >= 3
    && (!!fotoIni || sinFoto.trim().length >= 5) && !guardando

  const guardar = async () => {
    if (!listo || !faenaId || !origen || !destino) return
    setGuardando(true)
    try {
      // Las fotos quedan en el teléfono y suben con el movimiento cuando haya
      // señal: en faena esto se hace en la estación, no en la oficina.
      const blobIni = fotoIni ? await guardarFotoLocal(fotoIni.file) : null
      const blobFin = fotoFin ? await guardarFotoLocal(fotoFin.file) : null
      const litrosTxt = Number(litrosFinales).toLocaleString('es-CL')
      const { enviado } = await guardarTrasvasije({
        faenaId,
        fecha: new Date().toISOString().slice(0, 10),
        turno,
        origenId: origen.id,
        destinoId: destino.id,
        litros: litrosFinales!,
        operador: operador.trim(),
        meterInicial: meterIni ? Number(meterIni.replace(',', '.')) : null,
        meterFinal: meterFin ? Number(meterFin.replace(',', '.')) : null,
        sinFotoMotivo: blobIni ? null : sinFoto.trim(),
        observacion: obs.trim() || null,
        hora: new Date().toTimeString().slice(0, 8),
      }, { inicial: blobIni, final: blobFin },
        `${litrosTxt} L · ${origen.codigo} → ${destino.patente ?? destino.codigo}`)

      toast.success(enviado
        ? `${litrosTxt} L del ${origen.codigo} al ${destino.patente ?? destino.codigo}.`
        : `${litrosTxt} L guardados en el teléfono. Suben solos cuando haya señal.`)
      router.push('/m/romeral')
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'No se pudo guardar')
      setGuardando(false)
    }
  }

  if (cargando) {
    return <div className="flex min-h-[60vh] items-center justify-center">
      <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
    </div>
  }

  return (
    <div className="space-y-3 p-3 pb-24">
      <div className="flex items-center gap-2">
        <Link href="/m/romeral" className="rounded-lg border border-gray-300 p-2">
          <ChevronLeft className="h-4 w-4 text-gray-600" />
        </Link>
        <div className="min-w-0 flex-1">
          <h1 className="text-base font-bold text-gray-900">Pasar combustible</h1>
          <p className="text-[11px] text-gray-500">De una estación a un camión, o entre estanques</p>
        </div>
      </div>

      <Selector titulo="1. ¿De dónde sale?" lista={estanques} valor={origenId}
                excluir={destinoId} onElegir={setOrigenId} />

      {origen && (
        <Selector titulo="2. ¿A dónde entra?" lista={estanques} valor={destinoId}
                  excluir={origenId} onElegir={setDestinoId} />
      )}

      {origen && destino && (
        <>
          <div className="rounded-xl border-2 border-gray-800 bg-white p-3">
            <p className="text-[11px] font-bold text-gray-700">3. ¿Cuántos litros?</p>

            <div className="mt-1.5 grid grid-cols-2 gap-2">
              <label className="block">
                <span className="text-[10px] font-bold text-gray-600">Medidor al empezar</span>
                <input value={meterIni} inputMode="decimal"
                       onChange={(e) => setMeterIni(e.target.value.replace(/[^\d.,]/g, ''))}
                       className="mt-0.5 w-full rounded-lg border border-gray-300 px-2 py-2 text-right text-sm tabular-nums" />
              </label>
              <label className="block">
                <span className="text-[10px] font-bold text-gray-600">Medidor al terminar</span>
                <input value={meterFin} inputMode="decimal"
                       onChange={(e) => setMeterFin(e.target.value.replace(/[^\d.,]/g, ''))}
                       className="mt-0.5 w-full rounded-lg border border-gray-300 px-2 py-2 text-right text-sm tabular-nums" />
              </label>
            </div>

            <label className="mt-2 block">
              <span className="text-[10px] font-bold text-gray-600">
                {meterIni && meterFin ? 'Litros (los calcula el medidor)' : 'Litros a mano'}
              </span>
              <input value={meterIni && meterFin ? String(litrosFinales ?? '') : litros}
                     inputMode="decimal" disabled={!!(meterIni && meterFin)}
                     onChange={(e) => setLitros(e.target.value.replace(/[^\d.,]/g, ''))}
                     placeholder="0"
                     className="mt-0.5 w-full rounded-lg border border-gray-300 px-2 py-2.5 text-right text-lg font-bold tabular-nums disabled:bg-gray-50" />
            </label>

            {/* Cómo queda cada uno: se ve antes de confirmar, no después. */}
            {litrosFinales != null && litrosFinales > 0 && (
              <div className="mt-2 flex items-center gap-2 rounded-lg bg-gray-50 p-2 text-[11px]">
                <div className="min-w-0 flex-1 text-center">
                  <p className="truncate font-bold text-gray-700">{origen.codigo}</p>
                  <p className="tabular-nums text-gray-500">
                    {stockOrigen.toLocaleString('es-CL')} →{' '}
                    <span className="font-bold text-gray-900">
                      {(stockOrigen - litrosFinales).toLocaleString('es-CL')} L
                    </span>
                  </p>
                </div>
                <ArrowRight className="h-4 w-4 shrink-0 text-gray-400" />
                <div className="min-w-0 flex-1 text-center">
                  <p className="truncate font-bold text-gray-700">{destino.patente ?? destino.codigo}</p>
                  <p className="tabular-nums text-gray-500">
                    {Number(destino.stock_teorico_lt ?? 0).toLocaleString('es-CL')} →{' '}
                    <span className="font-bold text-gray-900">
                      {(Number(destino.stock_teorico_lt ?? 0) + litrosFinales).toLocaleString('es-CL')} L
                    </span>
                  </p>
                </div>
              </div>
            )}

            {problema && (
              <p className="mt-2 flex items-start gap-1.5 rounded-lg bg-amber-50 p-2 text-[11px] leading-snug text-amber-900">
                <AlertTriangle className="mt-px h-3.5 w-3.5 shrink-0" /> {problema}
              </p>
            )}
          </div>

          <div className="rounded-xl border-2 border-gray-300 bg-white p-3">
            <p className="text-[11px] font-bold text-gray-700">4. Respaldo</p>
            <div className="mt-1.5 grid grid-cols-2 gap-2">
              <FotoCampo etiqueta="Medidor inicial" foto={fotoIni}
                         onSet={(f) => { setFotoIni(f); if (f) setSinFoto('') }} />
              <FotoCampo etiqueta="Medidor final" foto={fotoFin} onSet={setFotoFin} />
            </div>
            {!fotoIni && (
              <input value={sinFoto} onChange={(e) => setSinFoto(e.target.value)}
                     placeholder="…o escriba por qué no hay foto"
                     className="mt-1.5 w-full rounded-lg border border-gray-300 px-2 py-1.5 text-xs" />
            )}

            <div className="mt-2 grid grid-cols-2 gap-2">
              <label className="block">
                <span className="text-[10px] font-bold text-gray-600">¿Quién lo hizo?</span>
                <input value={operador} onChange={(e) => setOperador(e.target.value)}
                       className="mt-0.5 w-full rounded-lg border border-gray-300 px-2 py-2 text-sm" />
              </label>
              <label className="block">
                <span className="text-[10px] font-bold text-gray-600">Turno</span>
                <select value={turno} onChange={(e) => setTurno(e.target.value)}
                        className="mt-0.5 h-[38px] w-full rounded-lg border border-gray-300 px-2 text-sm">
                  {TURNOS.map((t) => <option key={t} value={t}>{t === 'dia' ? 'Día' : 'Noche'}</option>)}
                </select>
              </label>
            </div>

            <input value={obs} onChange={(e) => setObs(e.target.value)}
                   placeholder="Observación — opcional"
                   className="mt-2 w-full rounded-lg border border-gray-300 px-2 py-2 text-sm" />
          </div>

          <button onClick={guardar} disabled={!listo}
                  className="flex w-full items-center justify-center gap-2 rounded-xl bg-gray-900 px-4 py-3 text-sm font-bold text-white disabled:opacity-40">
            {guardando ? <Loader2 className="h-4 w-4 animate-spin" /> : <ArrowRight className="h-4 w-4" />}
            Confirmar el traspaso
          </button>
          {!listo && !guardando && !problema && (
            <p className="text-center text-[11px] text-gray-500">
              {litrosFinales == null ? 'Faltan los litros.'
                : !fotoIni && sinFoto.trim().length < 5 ? 'Falta la foto del medidor o el motivo.'
                : operador.trim().length < 3 ? 'Falta quién lo hizo.' : ''}
            </p>
          )}
        </>
      )}
    </div>
  )
}

function Selector({ titulo, lista, valor, excluir, onElegir }: {
  titulo: string
  lista: EstanqueAhora[]
  valor: string
  excluir: string
  onElegir: (id: string) => void
}) {
  return (
    <div>
      <p className="text-[11px] font-bold text-gray-700">{titulo}</p>
      <div className="mt-1 space-y-1.5">
        {lista.filter((e) => e.id !== excluir).map((e) => {
          const sel = e.id === valor
          const enVivo = litrosAhora(e)
          const esCamion = e.tipo === 'movil'
          return (
            <button key={e.id} type="button" onClick={() => onElegir(e.id)}
                    className={cn('flex w-full items-center gap-2.5 rounded-xl border-2 p-2.5 text-left',
                      sel ? 'border-orange-500 bg-orange-50' : 'border-gray-200 bg-white')}>
              <div className={cn('flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-white',
                sel ? 'bg-orange-600' : 'bg-gray-400')}>
                {esCamion ? <Truck className="h-4 w-4" /> : <Fuel className="h-4 w-4" />}
              </div>
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-bold text-gray-900">{e.patente ?? e.codigo}</p>
                <p className="truncate text-[10px] text-gray-500">{e.nombre}</p>
              </div>
              <div className="shrink-0 text-right">
                <p className="text-sm font-bold tabular-nums text-gray-900">
                  {Number(e.stock_teorico_lt ?? 0).toLocaleString('es-CL')} L
                </p>
                {enVivo != null && Math.abs(enVivo - Number(e.stock_teorico_lt ?? 0)) >= 1 && (
                  <p className="text-[10px] tabular-nums text-gray-400">
                    ~{enVivo.toLocaleString('es-CL')} estimado
                  </p>
                )}
                {!e.tiene_momento_cero && (
                  <p className="text-[10px] font-semibold text-amber-600">sin momento cero</p>
                )}
              </div>
            </button>
          )
        })}
      </div>
    </div>
  )
}

function FotoCampo({ etiqueta, foto, onSet }: {
  etiqueta: string
  foto: { file: File; url: string } | null
  onSet: (f: { file: File; url: string } | null) => void
}) {
  if (foto) {
    return (
      <div className="relative">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={foto.url} alt={etiqueta} className="h-20 w-full rounded-lg object-cover" />
        <button type="button" onClick={() => onSet(null)} aria-label="Quitar"
                className="absolute right-1 top-1 rounded-full bg-white/90 p-1">
          <X className="h-3.5 w-3.5 text-gray-700" />
        </button>
      </div>
    )
  }
  return (
    <label className="flex h-20 flex-col items-center justify-center gap-1 rounded-lg border-2 border-dashed border-gray-300 text-[10px] font-semibold text-gray-500">
      <Camera className="h-4 w-4" /> {etiqueta}
      <input type="file" accept="image/*" capture="environment" className="hidden"
             onChange={(e) => {
               const f = e.target.files?.[0]
               if (f) onSet({ file: f, url: URL.createObjectURL(f) })
             }} />
    </label>
  )
}
