'use client'

// ============================================================================
// Cierre físico del turno — Romeral (MIG317)
// ----------------------------------------------------------------------------
// Esto reemplaza la hoja del día que hoy se llena a mano. Lo usa gente que
// lleva veinte años midiendo con varilla y a la que el sistema le tiene que
// estorbar lo menos posible. De ahí las decisiones de diseño:
//
//   · UN PUNTO A LA VEZ. No una tabla de siete filas por seis columnas, que en
//     un teléfono es imposible y en papel al menos se ve entera. Una tarjeta
//     grande, se avanza con un botón, se puede volver.
//   · SE PREGUNTA EN CASTELLANO DE TERRENO. "¿Cuánto marca la varilla ahora?",
//     no "medición final". El que mide no tiene por qué aprender el nombre que
//     le puso la base de datos.
//   · EL SISTEMA PONE LO QUE YA SABE. La medición inicial llega con el valor de
//     ayer; el numeral inicial, con la última lectura. Nadie transcribe lo que
//     el sistema ya tiene.
//   · RESPUESTA INMEDIATA. Al terminar el punto dice "cuadra" o "revise", con
//     la diferencia en litros. Ese es el control cruzado de la sección 3.1 del
//     instructivo, hecho cuando la persona todavía está frente al estanque.
//   · NADA SE PIERDE. Cada número se guarda en el teléfono al escribirlo. La
//     subida es otra cosa y se reintenta.
//   · SE PUEDE NO PODER. "No pude medir" con motivo es una respuesta válida;
//     obligar a inventar un número es peor que registrar el hueco.
// ============================================================================

import { useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, ArrowRight, Check, CloudOff, Gauge, Download, RefreshCw,
  AlertTriangle, CheckCircle2, Ruler, Truck, Building2, Ban, Save, Camera, X,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { useNetworkStatus } from '@/hooks/use-calama-offline'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { cn, errorMessage } from '@/lib/utils'
import { FAENA_ROMERAL, TURNOS, getFaenaPorCodigo } from '@/lib/services/combustible-faena'
import {
  evaluarCuadre, TOL_CUADRA_LT,
  type PuntoMedicion, type LecturaPunto, type LecturaMedidor,
} from '@/lib/services/combustible-cierre'
import {
  descargarCatalogoCierre, getPuntosOffline, ultimaDescargaCierre,
  descargarMedicionAnterior, getMedicionAnteriorOffline,
  crearBorrador, guardarBorrador, subirBorrador,
  guardarFotoLocal, getFotoLocal, esFotoLocal,
  type BorradorCierre,
} from '@/lib/offline/combustible-cierre-offline'

const hoyISO = () => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

const miles = (n: number | null | undefined) =>
  n == null || Number.isNaN(n) ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 0 })

/** El teclado del teléfono tiene que abrir en números, no en letras. */
function CampoNumero({
  etiqueta, ayuda, valor, onChange, sufijo = 'L', autoFocus = false,
}: {
  etiqueta: string
  ayuda?: string
  valor: number | null
  onChange: (v: number | null) => void
  sufijo?: string
  autoFocus?: boolean
}) {
  return (
    <label className="block">
      <span className="block text-base font-semibold text-gray-800">{etiqueta}</span>
      {ayuda && <span className="mt-0.5 block text-sm text-gray-500">{ayuda}</span>}
      <div className="mt-2 flex items-center gap-2">
        <input
          type="text"
          inputMode="numeric"
          autoFocus={autoFocus}
          value={valor == null ? '' : String(valor)}
          onChange={(e) => {
            const limpio = e.target.value.replace(/[^\d.-]/g, '')
            onChange(limpio === '' ? null : Number(limpio))
          }}
          placeholder="0"
          className="h-16 w-full rounded-xl border-2 border-gray-300 px-4 text-right text-3xl font-bold tabular-nums text-gray-900 focus:border-emerald-500 focus:outline-none focus:ring-4 focus:ring-emerald-500/20"
        />
        <span className="w-8 shrink-0 text-lg font-semibold text-gray-400">{sufijo}</span>
      </div>
    </label>
  )
}

/**
 * La foto de una medición. En combustible no es un adjunto: es el documento.
 * Un nivel de varilla o un numeral no se pueden volver a verificar — mañana el
 * estanque tiene otro nivel. Por eso se saca junto con el número y no después.
 *
 * Se guarda en el teléfono al instante y sube cuando hay señal. Si no se puede
 * sacar (cámara mojada, sin batería, lugar donde no se saca el teléfono), se
 * escribe por qué: obligar a una foto imposible termina en mediciones sin
 * registrar, que es peor.
 */
function FotoMedicion({
  valor, motivo, onFoto, onMotivo, etiqueta = 'Foto de la medición',
}: {
  valor?: string | null
  motivo?: string | null
  onFoto: (ref: string | null) => void
  onMotivo: (m: string) => void
  etiqueta?: string
}) {
  const [preview, setPreview] = useState<string | null>(null)

  // La foto que espera en el teléfono también se tiene que poder mirar.
  useEffect(() => {
    let vivo = true
    let url: string | null = null
    if (!valor) { setPreview(null); return }
    if (esFotoLocal(valor)) {
      getFotoLocal(valor).then((b) => {
        if (!vivo || !b) return
        url = URL.createObjectURL(b)
        setPreview(url)
      })
    } else {
      setPreview(valor)
    }
    return () => { vivo = false; if (url) URL.revokeObjectURL(url) }
  }, [valor])

  return (
    <div className="space-y-2">
      {valor ? (
        <div className="relative">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={preview ?? ''}
            alt={etiqueta}
            className="h-32 w-full rounded-xl border-2 border-emerald-400 object-cover"
          />
          <button
            onClick={() => onFoto(null)}
            className="absolute right-2 top-2 rounded-full bg-white/95 p-2 text-red-600 shadow"
            aria-label="Quitar la foto"
          >
            <X className="h-4 w-4" />
          </button>
          <span className="absolute bottom-2 left-2 rounded bg-emerald-600 px-2 py-0.5 text-xs font-bold text-white">
            Foto lista
          </span>
        </div>
      ) : (
        <>
          <label className="flex h-14 cursor-pointer items-center justify-center gap-2 rounded-xl border-2 border-dashed border-amber-400 bg-amber-50 text-lg font-bold text-amber-800">
            <Camera className="h-5 w-5" />
            {etiqueta}
            <input
              type="file"
              accept="image/*"
              capture="environment"
              className="hidden"
              onChange={async (e) => {
                const f = e.target.files?.[0]
                if (f) onFoto(await guardarFotoLocal(f))
                e.target.value = ''
              }}
            />
          </label>
          <input
            value={motivo ?? ''}
            onChange={(e) => onMotivo(e.target.value)}
            placeholder="Si no puede sacarla, escriba por qué"
            className="h-12 w-full rounded-xl border-2 border-gray-300 px-3 text-base"
          />
        </>
      )}
    </div>
  )
}

function BotonGrande({
  children, onClick, variante = 'primario', disabled, icono: Icono,
}: {
  children: React.ReactNode
  onClick: () => void
  variante?: 'primario' | 'secundario' | 'peligro'
  disabled?: boolean
  icono?: any
}) {
  const estilos = {
    primario: 'bg-emerald-600 text-white hover:bg-emerald-700 active:bg-emerald-800',
    secundario: 'border-2 border-gray-300 bg-white text-gray-700 hover:bg-gray-50',
    peligro: 'border-2 border-amber-300 bg-amber-50 text-amber-800 hover:bg-amber-100',
  }
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={cn(
        'inline-flex h-14 w-full items-center justify-center gap-2 rounded-xl text-lg font-bold transition-colors disabled:opacity-40',
        estilos[variante],
      )}
    >
      {Icono && <Icono className="h-5 w-5" />}
      {children}
    </button>
  )
}

export default function CierreRomeralPage() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil } = useAuth()
  const online = useNetworkStatus()
  const toast = useToast()

  const [faenaId, setFaenaId] = useState<string | null>(null)
  const [puntos, setPuntos] = useState<PuntoMedicion[] | null>(null)
  const [anterior, setAnterior] = useState<Record<string, number>>({})
  const [descargadoAt, setDescargadoAt] = useState<string | null>(null)
  const [descargando, setDescargando] = useState(false)

  const [borrador, setBorrador] = useState<BorradorCierre | null>(null)
  const [paso, setPaso] = useState(-1)      // -1 = quién mide · 0..n-1 = puntos · n = resumen
  const [subiendo, setSubiendo] = useState(false)

  // Encabezado del turno
  const [fecha, setFecha] = useState(hoyISO())
  const [turno, setTurno] = useState<string>(TURNOS[0])
  const [medidoPor, setMedidoPor] = useState('')

  // ── Catálogo ──────────────────────────────────────────────────────────────
  const cargar = useCallback(async () => {
    const local = await getPuntosOffline()
    if (local) setPuntos(local)
    setAnterior(await getMedicionAnteriorOffline())
    setDescargadoAt(await ultimaDescargaCierre())
  }, [])

  useEffect(() => { void cargar() }, [cargar])

  useEffect(() => {
    if (!online) return
    getFaenaPorCodigo(FAENA_ROMERAL).then((f) => setFaenaId(f?.id ?? null)).catch(() => {})
  }, [online])

  const descargar = async () => {
    if (!faenaId) { toast.error('Todavía no se identifica la faena. Intente de nuevo con señal.'); return }
    setDescargando(true)
    try {
      const p = await descargarCatalogoCierre(faenaId)
      const a = await descargarMedicionAnterior(faenaId, fecha)
      setPuntos(p); setAnterior(a)
      setDescargadoAt(await ultimaDescargaCierre())
      toast.success(`${p.length} puntos listos para medir sin señal`)
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo bajar el catálogo'))
    } finally {
      setDescargando(false)
    }
  }

  // ── Empezar el turno ──────────────────────────────────────────────────────
  const empezar = async () => {
    if (!faenaId) { toast.error('Necesita señal una vez para empezar el turno.'); return }
    if (medidoPor.trim().length < 3) { toast.error('Escriba su nombre.'); return }
    const b = await crearBorrador(faenaId, fecha, turno, medidoPor.trim())
    setBorrador(b)
    setPaso(0)
  }

  // ── Escribir un número guarda de inmediato ────────────────────────────────
  const setPunto = async (estanqueId: string, campo: keyof LecturaPunto, valor: any) => {
    if (!borrador) return
    const actual: LecturaPunto = borrador.puntos[estanqueId] ?? {
      estanque_id: estanqueId, mi: null, rfp: null, rt: null, mf: null,
      agua_mm: null, temperatura_c: null, sin_medicion: false, motivo_sin_medicion: null,
    }
    const nuevo = { ...borrador, puntos: { ...borrador.puntos, [estanqueId]: { ...actual, [campo]: valor } } }
    setBorrador(nuevo)
    await guardarBorrador(nuevo)
  }

  const setMedidor = async (medidorId: string, campo: keyof LecturaMedidor, valor: any) => {
    if (!borrador) return
    const actual: LecturaMedidor = borrador.medidores[medidorId] ?? {
      medidor_id: medidorId, numeral_ini: null, numeral_fin: null, calibracion: 0,
    }
    const nuevo = { ...borrador, medidores: { ...borrador.medidores, [medidorId]: { ...actual, [campo]: valor } } }
    setBorrador(nuevo)
    await guardarBorrador(nuevo)
  }

  // ── El control cruzado, calculado mientras se escribe ─────────────────────
  const calcPunto = useCallback((p: PuntoMedicion) => {
    const l = borrador?.puntos[p.id]
    const num = (v: number | null | undefined) => Number(v ?? 0)
    const vFis = num(l?.mi) + num(l?.rfp) + num(l?.rt) - num(l?.mf)
    let vMec = 0
    let leidos = 0
    for (const m of p.medidores) {
      const lm = borrador?.medidores[m.id]
      if (lm?.numeral_fin != null) {
        vMec += num(lm.numeral_fin) - num(lm.numeral_ini) - num(lm.calibracion)
        leidos++
      }
    }
    const completo = l?.mf != null && l?.mi != null && (p.medidores.length === 0 || leidos === p.medidores.length)
    const r = evaluarCuadre(vFis, vMec)
    return { vFis, vMec, dif: vMec - vFis, completo, leidos, resultado: r, cuadra: r === 'cuadra' }
  }, [borrador])

  const puntosOrdenados = useMemo(() => puntos ?? [], [puntos])
  const total = puntosOrdenados.length

  const resumen = useMemo(() => {
    if (!borrador) return { medidos: 0, saltados: 0, revisar: 0, sinFoto: [] as string[] }
    let medidos = 0, saltados = 0, revisar = 0
    // Lo que va a rechazar la firma, contado ANTES de apretar el botón: llegar
    // al final y que te digan que falta una foto de un estanque que quedó a
    // dos kilómetros es la mejor forma de que dejen de usar la app.
    const sinFoto: string[] = []
    for (const p of puntosOrdenados) {
      const l = borrador.puntos[p.id]
      if (l?.sin_medicion) { saltados++; continue }
      const c = calcPunto(p)
      if (c.completo) { medidos++; if (!c.cuadra) revisar++ }
      if (l?.mf != null && !l.foto_url && !(l.sin_foto_motivo ?? '').trim()) {
        sinFoto.push(p.nombre)
      }
      for (const m of p.medidores) {
        const lm = borrador.medidores[m.id]
        if (lm?.numeral_fin != null && !lm.foto_url && !(lm.sin_foto_motivo ?? '').trim()) {
          sinFoto.push(m.etiqueta ?? `${p.nombre} · ${m.surtidor} ${m.numero}`)
        }
      }
    }
    return { medidos, saltados, revisar, sinFoto }
  }, [borrador, puntosOrdenados, calcPunto])

  const subir = async (firmar: boolean) => {
    if (!borrador) return
    setSubiendo(true)
    try {
      await subirBorrador(borrador, firmar)
      toast.success(firmar ? 'Cierre firmado y enviado' : 'Guardado en el sistema')
      setBorrador({ ...borrador, sync_status: 'subido' })
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo enviar. Queda guardado en el teléfono.'))
    } finally {
      setSubiendo(false)
    }
  }

  // ── Estados de carga ──────────────────────────────────────────────────────
  if (verificando) {
    return <div className="flex min-h-screen items-center justify-center bg-gray-50"><Spinner className="h-8 w-8" /></div>
  }
  if (sinSesionOffline) return <SinSesionOffline />

  // ── Barra superior, siempre visible ───────────────────────────────────────
  const Barra = (
    <header className="sticky top-0 z-10 border-b border-gray-200 bg-white px-4 py-3">
      <div className="mx-auto flex max-w-lg items-center gap-3">
        <Link href="/m/romeral" className="shrink-0 rounded-lg p-1.5 text-gray-500 hover:bg-gray-100">
          <ArrowLeft className="h-5 w-5" />
        </Link>
        <div className="min-w-0 flex-1">
          <p className="text-base font-bold leading-tight text-gray-900">Cierre del turno</p>
          <p className="text-xs text-gray-500">
            Romeral · {fecha} · turno {turno}
          </p>
        </div>
        {!online && (
          <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-amber-100 px-2.5 py-1 text-xs font-bold text-amber-800">
            <CloudOff className="h-3.5 w-3.5" /> Sin señal
          </span>
        )}
      </div>
    </header>
  )

  // ── Paso −1: quién mide ───────────────────────────────────────────────────
  if (paso === -1) {
    return (
      <div className="min-h-screen bg-gray-50">
        {Barra}
        <main className="mx-auto max-w-lg space-y-6 px-4 py-6">
          {!puntos && (
            <div className="rounded-xl border-2 border-amber-300 bg-amber-50 p-4">
              <p className="flex items-center gap-2 text-base font-bold text-amber-900">
                <Download className="h-5 w-5" /> Primero baje los estanques
              </p>
              <p className="mt-1 text-sm text-amber-800">
                Se baja una vez, con señal. Después puede medir todo el recorrido sin conexión.
              </p>
            </div>
          )}

          <div className="rounded-xl border border-gray-200 bg-white p-4">
            <BotonGrande
              onClick={descargar}
              variante={puntos ? 'secundario' : 'primario'}
              disabled={descargando || !online}
              icono={descargando ? undefined : RefreshCw}
            >
              {descargando ? <Spinner className="h-5 w-5" /> : puntos ? 'Actualizar estanques' : 'Bajar estanques'}
            </BotonGrande>
            {descargadoAt && (
              <p className="mt-2 text-center text-xs text-gray-500">
                {puntos?.length} puntos guardados el {new Date(descargadoAt).toLocaleString('es-CL')}
              </p>
            )}
          </div>

          <div className="space-y-5 rounded-xl border border-gray-200 bg-white p-4">
            <div>
              <span className="block text-base font-semibold text-gray-800">¿Quién mide hoy?</span>
              <input
                value={medidoPor}
                onChange={(e) => setMedidoPor(e.target.value)}
                placeholder="Nombre y apellido"
                autoComplete="name"
                className="mt-2 h-14 w-full rounded-xl border-2 border-gray-300 px-4 text-lg focus:border-emerald-500 focus:outline-none focus:ring-4 focus:ring-emerald-500/20"
              />
              {perfil?.nombre_completo && medidoPor === '' && (
                <button
                  onClick={() => setMedidoPor(perfil.nombre_completo)}
                  className="mt-2 text-sm font-semibold text-emerald-700 underline"
                >
                  Soy {perfil.nombre_completo}
                </button>
              )}
            </div>

            <div>
              <span className="block text-base font-semibold text-gray-800">Turno</span>
              <div className="mt-2 grid grid-cols-2 gap-2">
                {TURNOS.map((t) => (
                  <button
                    key={t}
                    onClick={() => setTurno(t)}
                    className={cn(
                      'h-14 rounded-xl border-2 text-lg font-bold transition-colors',
                      turno === t
                        ? 'border-emerald-600 bg-emerald-50 text-emerald-800'
                        : 'border-gray-300 bg-white text-gray-600',
                    )}
                  >
                    {t}
                  </button>
                ))}
              </div>
            </div>

            <div>
              <span className="block text-base font-semibold text-gray-800">Día</span>
              <input
                type="date"
                value={fecha}
                onChange={(e) => setFecha(e.target.value)}
                className="mt-2 h-14 w-full rounded-xl border-2 border-gray-300 px-4 text-lg focus:border-emerald-500 focus:outline-none"
              />
            </div>
          </div>

          <BotonGrande onClick={empezar} disabled={!puntos || medidoPor.trim().length < 3} icono={ArrowRight}>
            Empezar el recorrido
          </BotonGrande>
        </main>
      </div>
    )
  }

  // ── Paso final: resumen y firma ───────────────────────────────────────────
  if (paso >= total) {
    return (
      <div className="min-h-screen bg-gray-50">
        {Barra}
        <main className="mx-auto max-w-lg space-y-5 px-4 py-6">
          <div className="rounded-xl border border-gray-200 bg-white p-5 text-center">
            <p className="text-sm font-semibold uppercase tracking-wide text-gray-400">Recorrido terminado</p>
            <p className="mt-2 text-4xl font-bold tabular-nums text-gray-900">
              {resumen.medidos}<span className="text-2xl text-gray-400"> de {total}</span>
            </p>
            <p className="mt-1 text-base text-gray-600">puntos medidos</p>
            {resumen.saltados > 0 && (
              <p className="mt-1 text-sm text-gray-500">{resumen.saltados} sin medir, con motivo anotado</p>
            )}
          </div>

          {resumen.revisar > 0 && (
            <div className="rounded-xl border-2 border-amber-300 bg-amber-50 p-4">
              <p className="flex items-start gap-2 text-base font-bold text-amber-900">
                <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0" />
                {resumen.revisar} punto{resumen.revisar > 1 ? 's' : ''} para revisar
              </p>
              <p className="mt-1 text-sm text-amber-800">
                La varilla y el contador no dan lo mismo. Puede volver atrás y revisar el número, o
                firmar igual y dejarlo anotado — pero conviene mirarlo ahora, que todavía está allá.
              </p>
            </div>
          )}

          <div className="rounded-xl border border-gray-200 bg-white p-4">
            <span className="block text-base font-semibold text-gray-800">¿Algo que anotar?</span>
            <textarea
              value={borrador?.observacion ?? ''}
              onChange={async (e) => {
                if (!borrador) return
                const n = { ...borrador, observacion: e.target.value }
                setBorrador(n); await guardarBorrador(n)
              }}
              rows={3}
              placeholder="Opcional. Lo que no cabe en un número."
              className="mt-2 w-full rounded-xl border-2 border-gray-300 p-3 text-base focus:border-emerald-500 focus:outline-none"
            />
          </div>

          {resumen.sinFoto.length > 0 && (
            <div className="rounded-xl border-2 border-amber-400 bg-amber-50 p-4">
              <p className="flex items-start gap-2 text-base font-bold text-amber-900">
                <Camera className="mt-0.5 h-5 w-5 shrink-0" />
                Faltan {resumen.sinFoto.length} foto{resumen.sinFoto.length > 1 ? 's' : ''}
              </p>
              <p className="mt-1 text-sm text-amber-800">
                En combustible la medición no se puede volver a verificar: mañana el estanque
                tiene otro nivel. Vuelva atrás y sáquelas, o escriba por qué no pudo.
              </p>
              <ul className="mt-2 space-y-0.5 text-sm font-medium text-amber-900">
                {resumen.sinFoto.slice(0, 6).map((n) => <li key={n}>· {n}</li>)}
                {resumen.sinFoto.length > 6 && <li>· y {resumen.sinFoto.length - 6} más</li>}
              </ul>
            </div>
          )}

          <div className="space-y-2">
            <BotonGrande
              onClick={() => subir(true)}
              disabled={subiendo || !online || resumen.sinFoto.length > 0}
              icono={Check}
            >
              {subiendo ? <Spinner className="h-5 w-5" /> : 'Firmar y enviar'}
            </BotonGrande>
            <BotonGrande onClick={() => subir(false)} variante="secundario" disabled={subiendo || !online} icono={Save}>
              Guardar sin firmar
            </BotonGrande>
            <BotonGrande onClick={() => setPaso(total - 1)} variante="secundario" icono={ArrowLeft}>
              Volver al último punto
            </BotonGrande>
          </div>

          <p className="text-center text-sm text-gray-500">
            {online
              ? 'Guardado en el teléfono. Al enviar queda en el sistema.'
              : 'Sin señal: está guardado en el teléfono. Envíelo cuando tenga conexión.'}
          </p>
        </main>
      </div>
    )
  }

  // ── Pasos 0..n−1: un punto a la vez ───────────────────────────────────────
  const p = puntosOrdenados[paso]
  const lec = borrador?.puntos[p.id]
  const c = calcPunto(p)
  const esCamion = p.tipo === 'movil'
  const propuestoInicial = anterior[p.id]

  return (
    <div className="min-h-screen bg-gray-50 pb-8">
      {Barra}

      {/* Progreso: siempre saber cuánto falta */}
      <div className="border-b border-gray-200 bg-white px-4 pb-3">
        <div className="mx-auto max-w-lg">
          <div className="flex items-center justify-between text-sm font-semibold text-gray-600">
            <span>Punto {paso + 1} de {total}</span>
            <span className="text-emerald-700">{resumen.medidos} listos</span>
          </div>
          <div className="mt-1.5 h-2 overflow-hidden rounded-full bg-gray-200">
            <div
              className="h-full rounded-full bg-emerald-500 transition-all"
              style={{ width: `${((paso + 1) / total) * 100}%` }}
            />
          </div>
        </div>
      </div>

      <main className="mx-auto max-w-lg space-y-5 px-4 py-5">
        {/* Qué estanque es */}
        <div className="flex items-center gap-3 rounded-xl border-2 border-gray-800 bg-white p-4">
          {esCamion ? <Truck className="h-7 w-7 shrink-0 text-gray-700" /> : <Building2 className="h-7 w-7 shrink-0 text-gray-700" />}
          <div className="min-w-0">
            <p className="text-xl font-bold leading-tight text-gray-900">{p.nombre}</p>
            <p className="text-sm text-gray-500">
              Capacidad {miles(p.capacidad_llenado_lt)} L
              {p.patente ? ` · ${p.patente}` : ''}
            </p>
          </div>
        </div>

        {lec?.sin_medicion ? (
          <div className="space-y-4 rounded-xl border-2 border-amber-300 bg-amber-50 p-4">
            <p className="flex items-center gap-2 text-base font-bold text-amber-900">
              <Ban className="h-5 w-5" /> Sin medir
            </p>
            <input
              value={lec.motivo_sin_medicion ?? ''}
              onChange={(e) => setPunto(p.id, 'motivo_sin_medicion', e.target.value)}
              placeholder="¿Por qué no se pudo medir?"
              className="h-14 w-full rounded-xl border-2 border-amber-300 px-4 text-base focus:border-amber-500 focus:outline-none"
            />
            <BotonGrande onClick={() => setPunto(p.id, 'sin_medicion', false)} variante="secundario">
              Sí puedo medir
            </BotonGrande>
          </div>
        ) : (
          <>
            {/* La varilla */}
            <div className="space-y-5 rounded-xl border border-gray-200 bg-white p-4">
              <p className="flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-500">
                <Ruler className="h-4 w-4" /> La varilla
              </p>

              <div>
                <CampoNumero
                  etiqueta="¿Cuánto había al empezar?"
                  ayuda={propuestoInicial != null ? `El último cierre dejó ${miles(propuestoInicial)} L` : undefined}
                  valor={lec?.mi ?? null}
                  onChange={(v) => setPunto(p.id, 'mi', v)}
                />
                {propuestoInicial != null && lec?.mi == null && (
                  <button
                    onClick={() => setPunto(p.id, 'mi', propuestoInicial)}
                    className="mt-2 h-11 w-full rounded-lg border-2 border-emerald-600 text-base font-bold text-emerald-700"
                  >
                    Usar {miles(propuestoInicial)} L
                  </button>
                )}
              </div>

              <CampoNumero
                etiqueta="¿Recibió camión de afuera?"
                ayuda="Litros de flota primaria. Si no recibió, déjelo vacío."
                valor={lec?.rfp ?? null}
                onChange={(v) => setPunto(p.id, 'rfp', v)}
              />

              <CampoNumero
                etiqueta="¿Le pasaron de otro estanque?"
                ayuda="Trasvasije que entró. Si no hubo, déjelo vacío."
                valor={lec?.rt ?? null}
                onChange={(v) => setPunto(p.id, 'rt', v)}
              />

              <CampoNumero
                etiqueta="¿Cuánto marca la varilla ahora?"
                ayuda="Esta es la medición de cierre."
                valor={lec?.mf ?? null}
                onChange={(v) => setPunto(p.id, 'mf', v)}
              />

              {/* Aviso de capacidad: el estanque no puede tener más de lo que cabe */}
              {lec?.mf != null && p.capacidad_llenado_lt != null && lec.mf > Number(p.capacidad_llenado_lt) && (
                <p className="rounded-lg bg-amber-50 px-3 py-2 text-sm font-semibold text-amber-800">
                  Ese número es mayor que la capacidad del estanque ({miles(p.capacidad_llenado_lt)} L).
                  Revíselo antes de seguir.
                </p>
              )}

              {/* La foto de la varilla. Aparece cuando ya hay un número que
                  respaldar: pedirla antes es pedir la foto de nada. */}
              {lec?.mf != null && (
                <FotoMedicion
                  etiqueta="Foto de la varilla"
                  valor={lec.foto_url}
                  motivo={lec.sin_foto_motivo}
                  onFoto={(ref) => setPunto(p.id, 'foto_url', ref)}
                  onMotivo={(m) => setPunto(p.id, 'sin_foto_motivo', m)}
                />
              )}
            </div>

            {/* Los contadores */}
            {p.medidores.length > 0 && (
              <div className="space-y-5 rounded-xl border border-gray-200 bg-white p-4">
                <p className="flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-500">
                  <Gauge className="h-4 w-4" /> {p.medidores.length === 1 ? 'El contador' : `Los ${p.medidores.length} contadores`}
                </p>

                {p.medidores.map((m) => {
                  const lm = borrador?.medidores[m.id]
                  const ini = lm?.numeral_ini ?? m.ultimo_numeral ?? null
                  const baja = lm?.numeral_fin != null && ini != null && lm.numeral_fin < ini
                  return (
                    <div key={m.id} className="space-y-3 rounded-lg bg-gray-50 p-3">
                      <p className="text-base font-bold text-gray-800">
                        {m.etiqueta ?? `${m.surtidor} ${m.numero}`}
                      </p>

                      <CampoNumero
                        etiqueta="¿Con cuánto empezó?"
                        ayuda={m.ultimo_numeral != null ? `La última vez quedó en ${miles(m.ultimo_numeral)}` : undefined}
                        valor={lm?.numeral_ini ?? m.ultimo_numeral ?? null}
                        onChange={(v) => setMedidor(m.id, 'numeral_ini', v)}
                        sufijo=""
                      />

                      <CampoNumero
                        etiqueta="¿Cuánto marca ahora?"
                        valor={lm?.numeral_fin ?? null}
                        onChange={(v) => setMedidor(m.id, 'numeral_fin', v)}
                        sufijo=""
                      />

                      {/* La validación que faltaba: un contador no retrocede */}
                      {baja && (
                        <p className="rounded-lg bg-red-50 px-3 py-2 text-sm font-bold text-red-700">
                          El contador no puede bajar. Antes marcaba {miles(ini)} y anotó {miles(lm!.numeral_fin)}.
                          Mire otra vez el número.
                        </p>
                      )}

                      {lm?.numeral_fin != null && ini != null && !baja && (
                        <p className="text-sm font-semibold text-gray-600">
                          Salieron <span className="tabular-nums text-gray-900">{miles(lm.numeral_fin - ini)}</span> L por este contador
                        </p>
                      )}

                      {lm?.numeral_fin != null && (
                        <FotoMedicion
                          etiqueta="Foto del contador"
                          valor={lm.foto_url}
                          motivo={lm.sin_foto_motivo}
                          onFoto={(ref) => setMedidor(m.id, 'foto_url', ref)}
                          onMotivo={(mm) => setMedidor(m.id, 'sin_foto_motivo', mm)}
                        />
                      )}
                    </div>
                  )
                })}
              </div>
            )}

            {/* El control cruzado, en el momento */}
            {c.completo && (
              <div
                className={cn(
                  'rounded-xl border-2 p-4',
                  c.cuadra ? 'border-emerald-400 bg-emerald-50' : 'border-amber-400 bg-amber-50',
                )}
              >
                <p className={cn('flex items-center gap-2 text-lg font-bold', c.cuadra ? 'text-emerald-800' : 'text-amber-900')}>
                  {c.cuadra ? <CheckCircle2 className="h-6 w-6" /> : <AlertTriangle className="h-6 w-6" />}
                  {c.resultado === 'cuadra' ? 'Cuadra'
                    : c.resultado === 'atencion' ? 'Revise el número'
                    : 'Diferencia grande — avise al supervisor'}
                </p>
                <div className="mt-2 space-y-1 text-base">
                  <p className="flex justify-between text-gray-700">
                    <span>Por la varilla salieron</span>
                    <span className="font-bold tabular-nums">{miles(c.vFis)} L</span>
                  </p>
                  <p className="flex justify-between text-gray-700">
                    <span>Por el contador salieron</span>
                    <span className="font-bold tabular-nums">{miles(c.vMec)} L</span>
                  </p>
                  <p className={cn('flex justify-between border-t pt-1 font-bold', c.cuadra ? 'border-emerald-300 text-emerald-900' : 'border-amber-300 text-amber-900')}>
                    <span>Diferencia</span>
                    <span className="tabular-nums">{c.dif > 0 ? '+' : ''}{miles(c.dif)} L</span>
                  </p>
                  {!c.cuadra && (
                    <p className="pt-1 text-sm text-amber-800">
                      Hasta {miles(TOL_CUADRA_LT)} L se considera normal por la lectura de la varilla.
                    </p>
                  )}
                </div>
              </div>
            )}

            {!c.completo && (
              <button
                onClick={() => setPunto(p.id, 'sin_medicion', true)}
                className="h-12 w-full rounded-xl border-2 border-gray-300 text-base font-semibold text-gray-600"
              >
                No pude medir este punto
              </button>
            )}
          </>
        )}

        {/* Navegación */}
        <div className="flex gap-2 pt-2">
          <button
            onClick={() => setPaso(paso - 1)}
            disabled={paso === 0}
            className="inline-flex h-14 w-16 shrink-0 items-center justify-center rounded-xl border-2 border-gray-300 bg-white text-gray-600 disabled:opacity-30"
            aria-label="Punto anterior"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>
          <div className="flex-1">
            <BotonGrande onClick={() => setPaso(paso + 1)} icono={ArrowRight}>
              {paso + 1 === total ? 'Terminar' : 'Siguiente'}
            </BotonGrande>
          </div>
        </div>

        <p className="text-center text-sm text-gray-400">
          Cada número queda guardado en el teléfono apenas lo escribe.
        </p>
      </main>
    </div>
  )
}
