'use client'

// ============================================================================
// Ejecutar una pauta — Franke (MIG357)
// ----------------------------------------------------------------------------
// Se llena parado frente al camión, con guantes y con sol de plano en la
// pantalla. De ahí cada decisión:
//
//   · BOTONES GRANDES, DOS OPCIONES. OK y NO OK ocupan media pantalla cada uno.
//     Nada de listas desplegables ni de tildes de 12 píxeles.
//   · UN BLOQUE A LA VEZ, PERO TODO EN UNA PÁGINA. Se avanza con el dedo y se
//     puede volver: la pauta completa es de 28 ítems y partirla en 28 pantallas
//     es peor que la hoja de papel.
//   · NADA SE PIERDE. Cada respuesta se guarda en el teléfono al tocarla. Si se
//     cae la señal o se apaga el aparato, la pauta sigue donde iba.
//   · EL NO OK PIDE FOTO, Y LO DICE ANTES. No al final, cuando ya se guardó el
//     teléfono en el bolsillo.
//   · «NO ESTÁ EN FAENA» ES UNA RESPUESTA. El HHWB-42 lleva meses en Coquimbo y
//     en el documento de papel aparece revisado igual. Obligar a inventar un
//     tilde es peor que registrar el hueco.
// ============================================================================

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useParams, useRouter, useSearchParams } from 'next/navigation'
import Link from 'next/link'
import {
  ArrowLeft, Check, X, Camera, AlertTriangle, CheckCircle2, Ban, Save,
  ChevronDown, Package, CloudOff,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { useNetworkStatus } from '@/hooks/use-calama-offline'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { cn, errorMessage } from '@/lib/utils'
import {
  FAENA_FRANKE, getFaenaId, getAgenda, getItems, getRespuestas, guardarPauta,
  subirFotoPauta, type PautaAgenda, type PautaItem, type Respuesta,
} from '@/lib/services/faena-pauta'

const hoyISO = () => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

type Estado = Record<string, {
  resultado?: 'ok' | 'nok'
  valor?: string
  texto?: string
  observacion?: string
  fotoUrl?: string
  fotoPreview?: string
}>

export default function EjecutarPautaPage() {
  const params = useParams<{ pautaId: string; activoId: string }>()
  const search = useSearchParams()
  const router = useRouter()
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil } = useAuth()
  const online = useNetworkStatus()
  const toast = useToast()

  const pautaId = params.pautaId
  const activoId = params.activoId
  const turno = search.get('turno') || 'Día'
  const fecha = hoyISO()

  const [faenaId, setFaenaId] = useState<string | null>(null)
  const [cab, setCab] = useState<PautaAgenda | null>(null)
  const [items, setItems] = useState<PautaItem[]>([])
  const [estado, setEstado] = useState<Estado>({})
  const [obs, setObs] = useState('')
  const [cargando, setCargando] = useState(true)
  const [guardando, setGuardando] = useState(false)
  const [subiendo, setSubiendo] = useState<string | null>(null)
  const [cerrada, setCerrada] = useState(false)
  const [pidiendoMotivo, setPidiendoMotivo] = useState(false)
  const [motivoNoAplica, setMotivoNoAplica] = useState('')
  const [abierto, setAbierto] = useState<string | null>(null)

  // El borrador vive en el teléfono. Si se cae la señal o se apaga el aparato,
  // la pauta sigue donde iba.
  const K_DRAFT = `franke-pauta-${pautaId}-${activoId}-${fecha}-${turno}`
  const cargado = useRef(false)

  const cargar = useCallback(async () => {
    setCargando(true)
    try {
      const f = await getFaenaId(FAENA_FRANKE)
      if (!f) { toast.error('No se encontró la faena Franke.'); return }
      setFaenaId(f)

      const [ag, its] = await Promise.all([getAgenda(f), getItems(pautaId)])
      const fila = ag.find((a) => a.pauta_id === pautaId && a.activo_id === activoId) ?? null
      setCab(fila)
      setItems(its)
      if (its.length > 0) setAbierto(its[0].bloque)
      setCerrada(fila?.ejecucion_hoy_estado === 'cerrada' || fila?.ejecucion_hoy_estado === 'no_aplica')

      // Lo que ya está en el servidor manda sobre el borrador local: si otro
      // cerró la pauta, no se pisa con lo que quedó en este teléfono.
      let base: Estado = {}
      if (fila?.ejecucion_hoy_id) {
        for (const r of await getRespuestas(fila.ejecucion_hoy_id)) {
          base[r.item_id] = {
            resultado: (r.resultado === 'ok' || r.resultado === 'nok') ? r.resultado : undefined,
            valor: r.valor != null ? String(r.valor) : undefined,
            texto: r.texto ?? undefined,
            observacion: r.observacion ?? undefined,
            fotoUrl: r.foto_url ?? undefined,
          }
        }
      }
      if (Object.keys(base).length === 0) {
        try {
          const raw = localStorage.getItem(K_DRAFT)
          if (raw) base = JSON.parse(raw) as Estado
        } catch { /* modo privado */ }
      }
      setEstado(base)
      cargado.current = true
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo abrir la pauta'))
    } finally { setCargando(false) }
  }, [pautaId, activoId, toast, K_DRAFT])

  useEffect(() => { void cargar() }, [cargar])

  useEffect(() => {
    if (!cargado.current) return
    try { localStorage.setItem(K_DRAFT, JSON.stringify(estado)) } catch { /* modo privado */ }
  }, [estado, K_DRAFT])

  const bloques = useMemo(() => {
    const m = new Map<string, PautaItem[]>()
    for (const i of items) {
      const l = m.get(i.bloque) ?? []
      l.push(i)
      m.set(i.bloque, l)
    }
    return Array.from(m.entries())
  }, [items])

  const set = (id: string, patch: Partial<Estado[string]>) =>
    setEstado((e) => ({ ...e, [id]: { ...e[id], ...patch } }))

  const contestado = (i: PautaItem) => {
    const r = estado[i.id]
    if (!r) return false
    if (i.tipo_respuesta === 'ok_nok') return !!r.resultado
    if (i.tipo_respuesta === 'numero') return !!r.valor && r.valor.trim() !== ''
    return !!r.texto && r.texto.trim() !== ''
  }

  const faltan = items.filter((i) => i.obligatorio && !contestado(i))
  const hallazgos = items.filter((i) => estado[i.id]?.resultado === 'nok')
  const sinFoto = hallazgos.filter((i) => i.foto_si_nok && !estado[i.id]?.fotoUrl)
  const repuestos = hallazgos.map((i) => i.repuesto).filter(Boolean) as string[]

  // Lo que la pauta pide y de ahí sale para todos lados: hoy este número se
  // escribe tres veces en tres planillas.
  const lectura = (u: string) => {
    const it = items.find((i) => i.tipo_respuesta === 'numero' && i.unidad === u)
    const v = it ? Number(estado[it.id]?.valor) : NaN
    return Number.isFinite(v) && v > 0 ? v : null
  }

  // Un horómetro no retrocede y no salta mil horas en un día. Un dígito de menos
  // —2566 en vez de 25664— se aceptaba sin decir nada y envenenaba el programa
  // de mantención, que es justamente lo que esta pauta viene a arreglar.
  const revisarLectura = (i: PautaItem, texto: string): string | null => {
    const v = Number(String(texto).replace(',', '.'))
    if (!Number.isFinite(v) || texto.trim() === '') return null
    const previo = i.unidad === 'h' ? cab?.horas_uso_actual
                 : i.unidad === 'km' ? cab?.kilometraje_actual
                 : null
    if (previo == null || previo <= 0) return null
    if (v < previo) {
      return `La última lectura fue ${Math.round(previo).toLocaleString('es-CL')} ${i.unidad}. `
           + 'Un contador no retrocede: revise si le falta un dígito.'
    }
    // 24 h de operación continua es el techo físico; 2.000 km en un día
    // tampoco pasa en faena. Más que eso es un tecleo, no una lectura.
    const salto = v - previo
    if ((i.unidad === 'h' && salto > 200) || (i.unidad === 'km' && salto > 5000)) {
      return `Son ${Math.round(salto).toLocaleString('es-CL')} ${i.unidad} más que la última lectura `
           + `(${Math.round(previo).toLocaleString('es-CL')}). Revise el número.`
    }
    return null
  }

  const avisosLectura = items
    .filter((i) => i.tipo_respuesta === 'numero')
    .map((i) => ({ item: i, aviso: revisarLectura(i, estado[i.id]?.valor ?? '') }))
    .filter((x) => x.aviso)

  const tomarFoto = async (itemId: string, file: File) => {
    setSubiendo(itemId)
    try {
      set(itemId, { fotoPreview: URL.createObjectURL(file) })
      const url = await subirFotoPauta(file)
      set(itemId, { fotoUrl: url })
    } catch (e) {
      set(itemId, { fotoPreview: undefined })
      toast.error(errorMessage(e, 'No se pudo subir la foto. Reintente con señal.'))
    } finally { setSubiendo(null) }
  }

  const enviar = async (cerrar: boolean) => {
    if (!faenaId) { toast.error('Necesita señal para guardar.'); return }
    if (cerrar && faltan.length > 0) {
      toast.error(`Falta contestar ${faltan.length} ítem(s). El primero: ${faltan[0].texto}`)
      setAbierto(faltan[0].bloque)
      return
    }
    if (cerrar && sinFoto.length > 0) {
      toast.error(`Estos hallazgos necesitan foto: ${sinFoto.map((i) => i.texto).join(' · ')}`)
      setAbierto(sinFoto[0].bloque)
      return
    }
    // Una lectura imposible no se puede cerrar sin volver a mirarla: de acá
    // sale el programa de mantención de los tres camiones.
    if (cerrar && avisosLectura.length > 0) {
      toast.error(avisosLectura[0].aviso as string)
      setAbierto(avisosLectura[0].item.bloque)
      return
    }
    setGuardando(true)
    try {
      const payload: Respuesta[] = items.map((i) => ({
        item_id: i.id,
        resultado: estado[i.id]?.resultado ?? null,
        valor: estado[i.id]?.valor ? Number(estado[i.id]!.valor) : null,
        texto: estado[i.id]?.texto ?? null,
        observacion: estado[i.id]?.observacion ?? null,
        foto_url: estado[i.id]?.fotoUrl ?? null,
      }))

      const r = await guardarPauta({
        faenaId, pautaId, activoId, fecha, turno,
        items: payload,
        horometro: lectura('h'),
        kilometraje: lectura('km'),
        observacion: obs || null,
        cerrar,
        ejecutadoPorNombre: perfil?.nombre_completo ?? null,
        clientUuid: K_DRAFT,
      })

      if (cerrar) {
        try { localStorage.removeItem(K_DRAFT) } catch { /* modo privado */ }
        setCerrada(true)
        toast.success(
          r.no_conformidades
            ? `Pauta cerrada. ${r.no_conformidades} no conformidad(es) levantada(s).`
            : 'Pauta cerrada. Sin hallazgos.',
        )
        router.push('/m/franke/pauta')
      } else {
        toast.success('Guardado. Puede seguir después.')
      }
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo guardar'))
    } finally { setGuardando(false) }
  }

  const marcarNoAplica = async () => {
    if (!faenaId) return
    if (motivoNoAplica.trim().length < 5) {
      toast.error('Escriba dónde está el equipo. «No está» solo no sirve al turno que entra.')
      return
    }
    setGuardando(true)
    try {
      await guardarPauta({
        faenaId, pautaId, activoId, fecha, turno,
        items: [], cerrar: true,
        ejecutadoPorNombre: perfil?.nombre_completo ?? null,
        noAplicaMotivo: motivoNoAplica.trim(),
        clientUuid: K_DRAFT,
      })
      try { localStorage.removeItem(K_DRAFT) } catch { /* modo privado */ }
      toast.success('Registrado: el equipo no estaba en faena.')
      router.push('/m/franke/pauta')
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo registrar'))
    } finally { setGuardando(false); setPidiendoMotivo(false) }
  }

  if (verificando) {
    return <div className="flex min-h-screen items-center justify-center bg-gray-50"><Spinner className="h-8 w-8" /></div>
  }
  if (sinSesionOffline) return <SinSesionOffline />

  return (
    <div className="min-h-screen bg-gray-50 pb-40">
      <header className="sticky top-0 z-20 border-b border-gray-200 bg-white px-4 pb-3 pt-[max(0.75rem,env(safe-area-inset-top))]">
        <div className="flex items-center gap-3">
          <Link href="/m/franke/pauta" className="shrink-0 rounded-lg p-1.5 text-gray-500 hover:bg-gray-100">
            <ArrowLeft className="h-5 w-5" />
          </Link>
          <div className="min-w-0 flex-1">
            <p className="truncate text-base font-bold leading-tight text-gray-900">
              {cab?.patente ?? cab?.activo_codigo ?? 'Equipo'}
            </p>
            <p className="truncate text-xs text-gray-500">
              {cab?.pauta_nombre ?? ''} · turno {turno}
            </p>
          </div>
          {!online && (
            <span className="inline-flex shrink-0 items-center gap-1 rounded-full bg-amber-100 px-2 py-1 text-[11px] font-bold text-amber-800">
              <CloudOff className="h-3.5 w-3.5" /> Sin señal
            </span>
          )}
        </div>

        <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-gray-200">
          <div className="h-full rounded-full bg-gray-900 transition-all"
               style={{ width: `${items.length ? Math.round(100 * (items.length - faltan.length) / items.length) : 0}%` }} />
        </div>
        <p className="mt-1 font-mono text-[11px] tabular-nums text-gray-500">
          {items.length - faltan.length}/{items.length} contestados
          {hallazgos.length > 0 && ` · ${hallazgos.length} NO OK`}
        </p>
      </header>

      <main className="space-y-3 px-4 py-4">
        {cargando && <div className="flex justify-center py-10"><Spinner /></div>}

        {cerrada && (
          <div className="flex items-start gap-3 rounded-xl border-2 border-emerald-300 bg-emerald-50 p-4">
            <CheckCircle2 className="mt-0.5 h-5 w-5 shrink-0 text-emerald-700" />
            <p className="text-sm text-emerald-900">
              Esta pauta ya está cerrada por {cab?.ejecucion_hoy_por ?? 'el turno'}. Lo que
              escriba acá no se guarda.
            </p>
          </div>
        )}

        {bloques.map(([bloque, its]: [string, PautaItem[]]) => {
          const abiertoEste = abierto === bloque
          const pend = its.filter((i) => i.obligatorio && !contestado(i)).length
          const nok = its.filter((i) => estado[i.id]?.resultado === 'nok').length
          return (
            <section key={bloque} className="overflow-hidden rounded-xl border border-gray-200 bg-white">
              <button onClick={() => setAbierto(abiertoEste ? null : bloque)}
                      className="flex w-full items-center gap-3 px-4 py-3 text-left">
                <span className="min-w-0 flex-1 text-sm font-bold text-gray-900">{bloque}</span>
                {nok > 0 && (
                  <span className="rounded bg-red-100 px-1.5 py-0.5 font-mono text-[11px] font-bold text-red-800">
                    {nok} NO OK
                  </span>
                )}
                <span className={cn('font-mono text-[11px] font-semibold tabular-nums',
                                    pend > 0 ? 'text-amber-700' : 'text-emerald-700')}>
                  {pend > 0 ? `faltan ${pend}` : 'listo'}
                </span>
                <ChevronDown className={cn('h-4 w-4 shrink-0 text-gray-400 transition',
                                           abiertoEste && 'rotate-180')} />
              </button>

              {abiertoEste && (
                <div className="divide-y divide-gray-100 border-t border-gray-100">
                  {its.map((i) => (
                    <ItemFila key={i.id} item={i} valor={estado[i.id]} bloqueado={cerrada}
                              subiendo={subiendo === i.id}
                              ultima={i.unidad === 'h' ? cab?.horas_uso_actual ?? null
                                    : i.unidad === 'km' ? cab?.kilometraje_actual ?? null
                                    : null}
                              aviso={revisarLectura(i, estado[i.id]?.valor ?? '')}
                              onSet={(p) => set(i.id, p)}
                              onFoto={(f) => void tomarFoto(i.id, f)} />
                  ))}
                </div>
              )}
            </section>
          )
        })}

        {repuestos.length > 0 && (
          <section className="rounded-xl border-2 border-amber-300 bg-amber-50 p-4">
            <p className="flex items-center gap-2 text-sm font-bold text-amber-900">
              <Package className="h-4 w-4" /> Repuestos que pide esta pauta
            </p>
            <ul className="mt-2 space-y-1 text-sm text-amber-900">
              {Array.from(new Set(repuestos)).map((r) => <li key={r}>· {r}</li>)}
            </ul>
            <p className="mt-2 text-xs text-amber-800">
              Pídalos completos antes de subir el equipo al pozo. En agosto el servicio de
              300 h se hizo sin el filtro de trampa de agua porque no vino en el kit.
            </p>
          </section>
        )}

        {!cerrada && (
          <label className="block rounded-xl border border-gray-200 bg-white p-4">
            <span className="text-sm font-semibold text-gray-800">Observaciones del equipo</span>
            <textarea value={obs} onChange={(e) => setObs(e.target.value)} rows={3}
                      placeholder="Lo que hay que saber y no cabe en un ítem."
                      className="mt-1 w-full rounded-lg border-2 border-gray-300 p-3 text-sm" />
          </label>
        )}

        {!cerrada && !pidiendoMotivo && (
          <button onClick={() => setPidiendoMotivo(true)}
                  className="flex w-full items-center justify-center gap-2 rounded-xl border-2 border-dashed border-gray-300 bg-white py-3 text-sm font-semibold text-gray-600">
            <Ban className="h-4 w-4" /> El equipo no está en faena
          </button>
        )}

        {pidiendoMotivo && (
          <section className="space-y-3 rounded-xl border-2 border-gray-400 bg-white p-4">
            <p className="text-sm font-bold text-gray-900">¿Dónde está el equipo?</p>
            <input value={motivoNoAplica} onChange={(e) => setMotivoNoAplica(e.target.value)}
                   placeholder="En taller Coquimbo, no está en faena"
                   className="h-14 w-full rounded-xl border-2 border-gray-300 px-3 text-base" />
            <div className="flex gap-2">
              <button onClick={() => setPidiendoMotivo(false)}
                      className="h-12 flex-1 rounded-xl border-2 border-gray-300 font-semibold text-gray-600">
                Volver
              </button>
              <button onClick={() => void marcarNoAplica()} disabled={guardando}
                      className="h-12 flex-1 rounded-xl bg-gray-900 font-bold text-white disabled:opacity-50">
                Registrar
              </button>
            </div>
          </section>
        )}
      </main>

      {!cerrada && !cargando && (
        <div className="fixed inset-x-0 bottom-0 z-20 mx-auto max-w-[480px] border-t border-gray-200 bg-white p-3">
          {(faltan.length > 0 || sinFoto.length > 0) && (
            <p className="mb-2 flex items-start gap-1.5 text-[11px] leading-snug text-amber-800">
              <AlertTriangle className="mt-px h-3.5 w-3.5 shrink-0" />
              {sinFoto.length > 0
                ? `${sinFoto.length} hallazgo(s) sin foto. Un NO OK sin foto no se puede cerrar.`
                : `Faltan ${faltan.length} de ${items.length}.`}
            </p>
          )}
          <div className="flex gap-2">
            <button onClick={() => void enviar(false)} disabled={guardando}
                    className="flex h-14 flex-1 items-center justify-center gap-2 rounded-xl border-2 border-gray-300 font-semibold text-gray-700 disabled:opacity-50">
              <Save className="h-5 w-5" /> Guardar
            </button>
            <button onClick={() => void enviar(true)} disabled={guardando}
                    className="flex h-14 flex-[1.6] items-center justify-center gap-2 rounded-xl bg-gray-900 text-lg font-bold text-white disabled:opacity-50">
              {guardando ? <Spinner className="h-5 w-5" /> : <Check className="h-5 w-5" />}
              Cerrar pauta
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

function ItemFila({
  item, valor, bloqueado, subiendo, ultima, aviso, onSet, onFoto,
}: {
  item: PautaItem
  valor: Estado[string] | undefined
  bloqueado: boolean
  subiendo: boolean
  /** La última lectura conocida del equipo, para no teclear de memoria. */
  ultima?: number | null
  /** Lo que está mal con lo tecleado, si algo lo está. */
  aviso?: string | null
  onSet: (p: Partial<Estado[string]>) => void
  onFoto: (f: File) => void
}) {
  const nok = valor?.resultado === 'nok'

  return (
    <div className="space-y-2.5 px-4 py-3.5">
      <div className="flex items-start gap-2">
        <p className="min-w-0 flex-1 text-[15px] font-semibold leading-snug text-gray-900">
          {item.texto}
          {item.critico && (
            <span className="ml-1.5 rounded bg-red-100 px-1 py-0.5 align-middle font-mono text-[10px] font-bold text-red-800">
              CRÍTICO
            </span>
          )}
        </p>
        {item.unidad && (
          <span className="shrink-0 font-mono text-[11px] text-gray-400">{item.unidad}</span>
        )}
      </div>
      {item.ayuda && <p className="text-xs leading-snug text-gray-500">{item.ayuda}</p>}

      {item.tipo_respuesta === 'numero' && (
        <>
          <input inputMode="decimal" disabled={bloqueado}
                 value={valor?.valor ?? ''}
                 onChange={(e) => onSet({ valor: e.target.value.replace(/[^\d.,]/g, '') })}
                 placeholder={ultima != null && ultima > 0
                   ? Math.round(ultima).toLocaleString('es-CL') : '0'}
                 className={cn(
                   'h-16 w-full rounded-xl border-2 px-4 text-right text-3xl font-bold tabular-nums disabled:bg-gray-100',
                   aviso ? 'border-amber-500 bg-amber-50' : 'border-gray-300')} />
          {/* El número que el sistema ya tiene, a la vista pero sin rellenar:
              prellenarlo invita a confirmar sin mirar el tablero. */}
          {ultima != null && ultima > 0 && (
            <p className="text-right font-mono text-[11px] tabular-nums text-gray-500">
              última lectura: {Math.round(ultima).toLocaleString('es-CL')} {item.unidad}
            </p>
          )}
          {aviso && (
            <p className="flex items-start gap-1.5 rounded-lg bg-amber-50 p-2 text-xs leading-snug text-amber-900">
              <AlertTriangle className="mt-px h-3.5 w-3.5 shrink-0" /> {aviso}
            </p>
          )}
        </>
      )}

      {item.tipo_respuesta === 'texto' && (
        <input disabled={bloqueado} value={valor?.texto ?? ''}
               onChange={(e) => onSet({ texto: e.target.value })}
               className="h-14 w-full rounded-xl border-2 border-gray-300 px-3 text-base disabled:bg-gray-100" />
      )}

      {item.tipo_respuesta === 'ok_nok' && (
        <div className="flex gap-2">
          <button disabled={bloqueado} onClick={() => onSet({ resultado: 'ok' })}
                  className={cn('flex h-14 flex-1 items-center justify-center gap-2 rounded-xl border-2 text-lg font-bold transition',
                                valor?.resultado === 'ok'
                                  ? 'border-emerald-600 bg-emerald-600 text-white'
                                  : 'border-gray-300 bg-white text-gray-500')}>
            <Check className="h-5 w-5" /> OK
          </button>
          <button disabled={bloqueado} onClick={() => onSet({ resultado: 'nok' })}
                  className={cn('flex h-14 flex-1 items-center justify-center gap-2 rounded-xl border-2 text-lg font-bold transition',
                                nok
                                  ? 'border-red-600 bg-red-600 text-white'
                                  : 'border-gray-300 bg-white text-gray-500')}>
            <X className="h-5 w-5" /> NO OK
          </button>
        </div>
      )}

      {nok && (
        <div className="space-y-2 rounded-xl border-2 border-red-200 bg-red-50 p-3">
          <input disabled={bloqueado} value={valor?.observacion ?? ''}
                 onChange={(e) => onSet({ observacion: e.target.value })}
                 placeholder="¿Qué tiene? Esto va a la no conformidad."
                 className="h-12 w-full rounded-lg border-2 border-red-200 bg-white px-3 text-sm" />

          {valor?.fotoUrl || valor?.fotoPreview ? (
            <div className="relative">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={valor.fotoUrl ?? valor.fotoPreview} alt="hallazgo"
                   className="h-32 w-full rounded-lg border-2 border-red-300 object-cover" />
              {subiendo && (
                <div className="absolute inset-0 grid place-items-center rounded-lg bg-black/40">
                  <Spinner className="h-6 w-6 text-white" />
                </div>
              )}
              {!bloqueado && !subiendo && (
                <button onClick={() => onSet({ fotoUrl: undefined, fotoPreview: undefined })}
                        aria-label="Quitar foto"
                        className="absolute right-2 top-2 rounded-full bg-white/95 p-2 text-red-600 shadow">
                  <X className="h-4 w-4" />
                </button>
              )}
            </div>
          ) : (
            item.foto_si_nok && !bloqueado && (
              <label className="flex h-14 cursor-pointer items-center justify-center gap-2 rounded-lg border-2 border-dashed border-red-400 bg-white text-base font-bold text-red-700">
                <Camera className="h-5 w-5" /> Foto del hallazgo
                <input type="file" accept="image/*" capture="environment" className="hidden"
                       onChange={(e) => { const f = e.target.files?.[0]; if (f) onFoto(f) }} />
              </label>
            )
          )}

          {item.repuesto && (
            <p className="text-xs text-red-800">Repuesto: {item.repuesto}</p>
          )}
        </div>
      )}
    </div>
  )
}
