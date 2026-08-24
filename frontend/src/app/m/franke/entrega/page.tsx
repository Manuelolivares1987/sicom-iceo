'use client'

// ============================================================================
// Entrega de turno 7×7 — Franke (MIG362)
// ----------------------------------------------------------------------------
// Lo que hoy es un PDF de diez capítulos que redacta el turno que se va, y que
// nadie del turno que entra firma.
//
// La pantalla está ordenada por las cuatro preguntas que el turno entrante hace
// igual, de palabra, apenas llega: cómo quedan los camiones, cuántos litros
// hay, qué quedó pendiente y si la bodega está cerrada. En ese orden, porque es
// el orden en que se pregunta.
//
//   · NADA SE TRANSCRIBE. Los camiones llegan con su estado, su horómetro y sus
//     desviaciones abiertas. El supervisor corrige lo que haga falta.
//   · EL CONTEO FÍSICO NO SE PUEDE SALTAR EN SILENCIO. Si no se hizo, hay que
//     decir por qué — y eso se ve el mismo día, no el 3 del mes siguiente.
//   · LOS PENDIENTES SE CONTESTAN UNO POR UNO. Lo que no se hizo necesita
//     motivo: sin eso el turno siguiente empieza de cero.
// ============================================================================

import { useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, Truck, Fuel, ListTodo, Package, PenLine, CheckCircle2, AlertTriangle,
  RefreshCw, Check, X, Clock,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useToast } from '@/contexts/toast-context'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import { cn, errorMessage } from '@/lib/utils'
import { FAENA_FRANKE, getFaenaId } from '@/lib/services/faena-pauta'
import {
  abrirEntrega, firmarEntrega, recibirEntrega, subirFirma, periodoSugerido,
  ESTADOS_EQUIPO,
  type EntregaAbierta, type EquipoEntrega, type RespuestaPendiente,
  type EstadoEquipoEntrega,
} from '@/lib/services/faena-entrega'

const miles = (n: number | null | undefined) =>
  n == null || Number.isNaN(Number(n)) ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 0 })

const RESPUESTAS = [
  { valor: 'hecho' as const,          texto: 'Hecho' },
  { valor: 'no_alcanzo' as const,     texto: 'No alcancé' },
  { valor: 'no_corresponde' as const, texto: 'No corresponde' },
]

export default function EntregaTurnoPage() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil } = useAuth()
  const toast = useToast()

  const sugerido = useMemo(() => periodoSugerido(), [])
  const [faenaId, setFaenaId] = useState<string | null>(null)
  const [desde, setDesde] = useState(sugerido.desde)
  const [hasta, setHasta] = useState(sugerido.hasta)
  const [saliente, setSaliente] = useState('B')
  const [entrante, setEntrante] = useState('A')

  const [datos, setDatos] = useState<EntregaAbierta | null>(null)
  const [cargando, setCargando] = useState(false)
  const [guardando, setGuardando] = useState(false)

  const [equipos, setEquipos] = useState<EquipoEntrega[]>([])
  const [respuestas, setRespuestas] = useState<Record<string, RespuestaPendiente>>({})
  const [conteoHecho, setConteoHecho] = useState(true)
  const [stockFisico, setStockFisico] = useState('')
  const [ticket, setTicket] = useState('')
  const [conteoMotivo, setConteoMotivo] = useState('')
  const [invCerrado, setInvCerrado] = useState(true)
  const [invObs, setInvObs] = useState('')
  const [obs, setObs] = useState('')
  const [firma, setFirma] = useState<string | null>(null)
  const [reparos, setReparos] = useState('')

  useEffect(() => { getFaenaId(FAENA_FRANKE).then(setFaenaId).catch(() => {}) }, [])

  const abrir = useCallback(async () => {
    if (!faenaId) return
    setCargando(true); setFirma(null)
    try {
      const d = await abrirEntrega({
        faenaId, desde, hasta, turnoSaliente: saliente, turnoEntrante: entrante,
      })
      setDatos(d)
      setEquipos(d.equipos ?? [])
      const e = d.entrega
      setConteoHecho(e.conteo_fisico_hecho ?? true)
      setStockFisico(e.stock_fisico_lt != null ? String(e.stock_fisico_lt) : '')
      setTicket(e.ticket_verificacion ?? '')
      setConteoMotivo(e.conteo_omitido_motivo ?? '')
      setInvCerrado(e.inventario_cerrado ?? true)
      setInvObs(e.inventario_observacion ?? '')
      setObs(e.observacion_entrega ?? '')
      setRespuestas({})
    } catch (er) {
      toast.error(errorMessage(er, 'No se pudo abrir la entrega'))
    } finally { setCargando(false) }
  }, [faenaId, desde, hasta, saliente, entrante, toast])

  const setEquipo = (id: string, patch: Partial<EquipoEntrega>) =>
    setEquipos((l) => l.map((e) => (e.activo_id === id ? { ...e, ...patch } : e)))

  const entrega = datos?.entrega
  const pendientes = datos?.pendientes ?? []
  const resumen = datos?.resumen
  const yaEntregada = entrega?.estado === 'entregada' || entrega?.estado === 'recibida'
  const yaRecibida = entrega?.estado === 'recibida'
  const sinContestar = pendientes.filter((p) => !respuestas[p.id])

  const firmarLaEntrega = async () => {
    if (!datos || !firma) { toast.error('Falta la firma de quien entrega.'); return }
    setGuardando(true)
    try {
      const blob = await (await fetch(firma)).blob()
      const url = await subirFirma(blob)
      const r = await firmarEntrega({
        entregaId: datos.entrega_id,
        nombre: perfil?.nombre_completo ?? 'Supervisor',
        firmaUrl: url,
        equipos,
        pendientes: Object.values(respuestas),
        stockFisico: conteoHecho && stockFisico ? Number(stockFisico) : null,
        ticket: ticket || null,
        conteoHecho,
        conteoOmitidoMotivo: conteoHecho ? null : conteoMotivo,
        inventarioCerrado: invCerrado,
        inventarioObservacion: invObs || null,
        observacion: obs || null,
      })
      // Sin inicial verificado no hay diferencia que mostrar. Un cero ahí sería
      // una pérdida inventada, y es la que después alguien tiene que explicar.
      if (r.comparable && r.diferencia != null) {
        toast.success(
          `Turno entregado. Físico ${miles(r.stock_fisico)} L contra teórico ${miles(r.stock_teorico)} L: ${r.diferencia >= 0 ? '+' : ''}${miles(r.diferencia)} L.`)
      } else if (r.por_que_no_comparable) {
        toast.success(`Turno entregado. ${r.por_que_no_comparable}`)
      } else {
        toast.success('Turno entregado.')
      }
      await abrir()
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo firmar la entrega'))
    } finally { setGuardando(false) }
  }

  const firmarLaRecepcion = async () => {
    if (!datos || !firma) { toast.error('Falta la firma de quien recibe.'); return }
    setGuardando(true)
    try {
      const blob = await (await fetch(firma)).blob()
      const url = await subirFirma(blob)
      await recibirEntrega({
        entregaId: datos.entrega_id,
        nombre: perfil?.nombre_completo ?? 'Supervisor',
        firmaUrl: url,
        reparos: reparos || null,
      })
      toast.success(reparos
        ? 'Turno recibido con reparos. El reparo quedó como pendiente con dueño.'
        : 'Turno recibido.')
      await abrir()
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo firmar la recepción'))
    } finally { setGuardando(false) }
  }

  if (verificando) {
    return <div className="flex min-h-screen items-center justify-center bg-gray-50"><Spinner className="h-8 w-8" /></div>
  }
  if (sinSesionOffline) return <SinSesionOffline />

  return (
    <div className="min-h-screen bg-gray-50 pb-16">
      <header className="sticky top-0 z-10 border-b border-gray-200 bg-white px-4 pb-3 pt-[max(0.75rem,env(safe-area-inset-top))]">
        <div className="flex items-center gap-3">
          <Link href="/m/franke" className="shrink-0 rounded-lg p-1.5 text-gray-500 hover:bg-gray-100">
            <ArrowLeft className="h-5 w-5" />
          </Link>
          <div className="min-w-0 flex-1">
            <p className="text-base font-bold leading-tight text-gray-900">Entrega de turno</p>
            <p className="text-xs text-gray-500">Faena Franke · régimen 7×7</p>
          </div>
          {entrega && (
            <span className={cn('shrink-0 rounded-full px-2.5 py-1 text-[11px] font-bold',
                                yaRecibida ? 'bg-emerald-100 text-emerald-800'
                                : yaEntregada ? 'bg-blue-100 text-blue-800'
                                : 'bg-amber-100 text-amber-800')}>
              {yaRecibida ? 'Recibida' : yaEntregada ? 'Falta recibir' : 'Abierta'}
            </span>
          )}
        </div>
      </header>

      <main className="space-y-4 px-4 py-4">
        {/* ── El periodo ──────────────────────────────────────────────── */}
        <section className="space-y-3 rounded-xl border border-gray-200 bg-white p-4">
          <p className="text-sm font-bold uppercase tracking-wide text-gray-500">El periodo</p>
          <div className="grid grid-cols-2 gap-3">
            <label className="block">
              <span className="text-xs font-semibold text-gray-700">Desde</span>
              <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)}
                     className="mt-1 h-12 w-full rounded-lg border-2 border-gray-300 px-2 text-sm" />
            </label>
            <label className="block">
              <span className="text-xs font-semibold text-gray-700">Hasta</span>
              <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)}
                     className="mt-1 h-12 w-full rounded-lg border-2 border-gray-300 px-2 text-sm" />
            </label>
            <label className="block">
              <span className="text-xs font-semibold text-gray-700">Entrega el turno</span>
              <select value={saliente} onChange={(e) => setSaliente(e.target.value)}
                      className="mt-1 h-12 w-full rounded-lg border-2 border-gray-300 px-2 text-sm font-bold">
                <option value="A">A</option><option value="B">B</option>
              </select>
            </label>
            <label className="block">
              <span className="text-xs font-semibold text-gray-700">Recibe el turno</span>
              <select value={entrante} onChange={(e) => setEntrante(e.target.value)}
                      className="mt-1 h-12 w-full rounded-lg border-2 border-gray-300 px-2 text-sm font-bold">
                <option value="A">A</option><option value="B">B</option>
              </select>
            </label>
          </div>
          <button onClick={() => void abrir()} disabled={cargando || !faenaId}
                  className="flex h-12 w-full items-center justify-center gap-2 rounded-xl bg-gray-900 font-bold text-white disabled:opacity-50">
            {cargando ? <Spinner className="h-5 w-5" /> : <RefreshCw className="h-4 w-4" />}
            {datos ? 'Actualizar' : 'Abrir la entrega'}
          </button>
        </section>

        {!datos && !cargando && (
          <p className="rounded-xl border border-dashed border-gray-300 bg-white p-6 text-center text-sm text-gray-500">
            Elija el periodo y los turnos, y el sistema arma la entrega con lo que ya sabe.
          </p>
        )}

        {datos && (
          <>
            {/* ── Cómo va el turno ─────────────────────────────────────── */}
            {resumen && (
              <section className="rounded-xl border border-gray-200 bg-white p-4">
                <p className="mb-3 flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-500">
                  <Clock className="h-4 w-4" /> Cómo fue el turno
                </p>
                <div className="grid grid-cols-2 gap-3">
                  <Cifra k="Litros vendidos" v={miles(resumen.litros?.venta)} u="L" />
                  <Cifra k="Cargas registradas" v={miles(resumen.litros?.cargas)} />
                  <Cifra k="Trasvasijes" v={miles(resumen.litros?.trasvasije)} u="L" />
                  <Cifra k="Revisiones cerradas" v={miles(resumen.pauta?.ejecuciones)} />
                  <Cifra k="Hallazgos NO OK" v={miles(resumen.pauta?.hallazgos)}
                         alerta={(resumen.pauta?.hallazgos ?? 0) > 0} />
                  <Cifra k="Pendientes abiertos" v={miles(resumen.pendientes?.abiertos)}
                         alerta={(resumen.pendientes?.atascados ?? 0) > 0} />
                </div>
                {resumen.litros_por_dia?.length > 0 && (
                  <div className="mt-4 overflow-x-auto">
                    <table className="w-full text-xs">
                      <thead className="text-left text-gray-500">
                        <tr><th className="py-1">Fecha</th><th className="py-1 text-right">Día</th><th className="py-1 text-right">Noche</th></tr>
                      </thead>
                      <tbody className="divide-y divide-gray-100">
                        {resumen.litros_por_dia.map((d) => (
                          <tr key={d.fecha}>
                            <td className="py-1.5 tabular-nums text-gray-700">{d.fecha}</td>
                            <td className="py-1.5 text-right tabular-nums text-gray-900">{miles(d.dia)}</td>
                            <td className="py-1.5 text-right tabular-nums text-gray-900">{miles(d.noche)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </section>
            )}

            {/* ── 1. Los camiones ──────────────────────────────────────── */}
            <section className="rounded-xl border border-gray-200 bg-white p-4">
              <p className="mb-1 flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-500">
                <Truck className="h-4 w-4" /> 1 · Cómo quedan los camiones
              </p>
              <p className="mb-3 text-xs text-gray-500">
                Llegan con lo que el sistema ya sabe. Corrija lo que haga falta.
              </p>
              <div className="space-y-3">
                {equipos.map((e) => (
                  <div key={e.activo_id} className="rounded-lg border border-gray-200 p-3">
                    <div className="flex items-baseline justify-between gap-2">
                      <p className="font-bold text-gray-900">{e.patente ?? e.equipo}</p>
                      <p className="font-mono text-[11px] tabular-nums text-gray-500">
                        {e.horometro != null && `${miles(e.horometro)} h`}
                        {e.kilometraje != null && ` · ${miles(e.kilometraje)} km`}
                      </p>
                    </div>
                    {(e.faltan_horas != null || e.faltan_km != null) && (
                      <p className="mt-0.5 font-mono text-[11px] text-gray-500">
                        próxima mantención: faltan{' '}
                        {e.faltan_horas != null ? `${miles(e.faltan_horas)} h` : `${miles(e.faltan_km)} km`}
                      </p>
                    )}
                    <select value={e.estado} disabled={yaEntregada}
                            onChange={(ev) => setEquipo(e.activo_id, { estado: ev.target.value as EstadoEquipoEntrega })}
                            className="mt-2 h-11 w-full rounded-lg border-2 border-gray-300 px-2 text-sm font-semibold disabled:bg-gray-100">
                      {ESTADOS_EQUIPO.map((s) => <option key={s.valor} value={s.valor}>{s.texto}</option>)}
                    </select>
                    {e.desviaciones > 0 && (
                      <p className="mt-2 rounded-lg bg-red-50 p-2 text-xs leading-snug text-red-800">
                        <strong>{e.desviaciones} desviación(es) abierta(s):</strong> {e.desviaciones_detalle}
                      </p>
                    )}
                    <input value={e.observacion ?? ''} disabled={yaEntregada}
                           onChange={(ev) => setEquipo(e.activo_id, { observacion: ev.target.value })}
                           placeholder="Observación para el turno que entra"
                           className="mt-2 h-11 w-full rounded-lg border-2 border-gray-300 px-2 text-sm disabled:bg-gray-100" />
                  </div>
                ))}
              </div>
            </section>

            {/* ── 2. Los litros ────────────────────────────────────────── */}
            <section className="space-y-3 rounded-xl border border-gray-200 bg-white p-4">
              <p className="flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-500">
                <Fuel className="h-4 w-4" /> 2 · Cuántos litros quedan
              </p>
              <div className="flex gap-2">
                <button disabled={yaEntregada} onClick={() => setConteoHecho(true)}
                        className={cn('h-12 flex-1 rounded-xl border-2 text-sm font-bold',
                                      conteoHecho ? 'border-emerald-600 bg-emerald-600 text-white'
                                                  : 'border-gray-300 bg-white text-gray-500')}>
                  Se hizo el conteo
                </button>
                <button disabled={yaEntregada} onClick={() => setConteoHecho(false)}
                        className={cn('h-12 flex-1 rounded-xl border-2 text-sm font-bold',
                                      !conteoHecho ? 'border-red-600 bg-red-600 text-white'
                                                   : 'border-gray-300 bg-white text-gray-500')}>
                  No se hizo
                </button>
              </div>

              {conteoHecho ? (
                <>
                  <label className="block">
                    <span className="text-sm font-semibold text-gray-800">Litros según el trasvasije de conteo</span>
                    <input value={stockFisico} disabled={yaEntregada} inputMode="numeric"
                           onChange={(e) => setStockFisico(e.target.value.replace(/[^\d]/g, ''))}
                           placeholder="0"
                           className="mt-1 h-16 w-full rounded-xl border-2 border-gray-300 px-4 text-right text-3xl font-bold tabular-nums disabled:bg-gray-100" />
                  </label>
                  <label className="block">
                    <span className="text-sm font-semibold text-gray-800">N° de ticket del trasvasije</span>
                    <input value={ticket} disabled={yaEntregada} inputMode="numeric"
                           onChange={(e) => setTicket(e.target.value)} placeholder="21706"
                           className="mt-1 h-12 w-full rounded-xl border-2 border-gray-300 px-3 text-lg font-bold tabular-nums disabled:bg-gray-100" />
                  </label>
                </>
              ) : (
                <label className="block">
                  <span className="text-sm font-semibold text-red-800">¿Por qué no se hizo?</span>
                  <input value={conteoMotivo} disabled={yaEntregada}
                         onChange={(e) => setConteoMotivo(e.target.value)}
                         placeholder="El camión de reemplazo no llegó a tiempo"
                         className="mt-1 h-12 w-full rounded-xl border-2 border-red-300 px-3 text-sm disabled:bg-gray-100" />
                  <span className="mt-1 block text-xs text-red-700">
                    En julio no se hizo y se supo un mes después, en el informe al mandante.
                  </span>
                </label>
              )}
            </section>

            {/* ── 3. Los pendientes ────────────────────────────────────── */}
            <section className="rounded-xl border border-gray-200 bg-white p-4">
              <p className="mb-1 flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-500">
                <ListTodo className="h-4 w-4" /> 3 · Qué pasó con lo pendiente
                <span className="ml-auto font-mono text-xs text-gray-500">
                  {pendientes.length - sinContestar.length}/{pendientes.length}
                </span>
              </p>
              {pendientes.length === 0 ? (
                <p className="py-3 text-sm text-gray-500">No hay pendientes abiertos.</p>
              ) : (
                <div className="space-y-3">
                  {pendientes.map((p) => {
                    const r = respuestas[p.id]
                    return (
                      <div key={p.id} className={cn('rounded-lg border-2 p-3',
                                                    p.senal === 'atascado' ? 'border-red-300 bg-red-50'
                                                    : p.senal === 'arrastrando' ? 'border-amber-300 bg-amber-50'
                                                    : 'border-gray-200')}>
                        <div className="mb-1.5 flex flex-wrap items-center gap-1.5">
                          <span className="rounded bg-white px-1.5 py-0.5 font-mono text-[10px] font-bold uppercase text-gray-600">
                            {p.origen}
                          </span>
                          {p.turnos_sin_hacer > 0 && (
                            <span className="rounded bg-white px-1.5 py-0.5 font-mono text-[10px] font-bold text-red-700">
                              cruzó {p.turnos_sin_hacer} turno(s)
                            </span>
                          )}
                          <span className="font-mono text-[10px] text-gray-500">{p.dias_abierto} días</span>
                        </div>
                        <p className="text-sm leading-snug text-gray-900">{p.texto}</p>
                        {p.ultimo_comentario && (
                          <p className="mt-1.5 text-xs italic text-gray-600">
                            Último turno ({p.ultimo_turno_por}): {p.ultimo_comentario}
                          </p>
                        )}
                        {!yaEntregada && (
                          <>
                            <div className="mt-2 flex gap-1.5">
                              {RESPUESTAS.map((op) => (
                                <button key={op.valor}
                                        onClick={() => setRespuestas((s) => ({
                                          ...s, [p.id]: { pendiente_id: p.id, respuesta: op.valor,
                                                          comentario: s[p.id]?.comentario ?? '' },
                                        }))}
                                        className={cn('h-10 flex-1 rounded-lg border-2 text-xs font-bold',
                                                      r?.respuesta === op.valor
                                                        ? 'border-gray-900 bg-gray-900 text-white'
                                                        : 'border-gray-300 bg-white text-gray-600')}>
                                  {op.texto}
                                </button>
                              ))}
                            </div>
                            {r && r.respuesta !== 'hecho' && (
                              <input value={r.comentario ?? ''}
                                     onChange={(e) => setRespuestas((s) => ({
                                       ...s, [p.id]: { ...s[p.id], comentario: e.target.value },
                                     }))}
                                     placeholder="¿Qué se intentó? Sin esto el turno que entra empieza de cero."
                                     className="mt-2 h-11 w-full rounded-lg border-2 border-gray-300 bg-white px-2 text-sm" />
                            )}
                          </>
                        )}
                      </div>
                    )
                  })}
                </div>
              )}
            </section>

            {/* ── 4. La bodega ─────────────────────────────────────────── */}
            <section className="space-y-3 rounded-xl border border-gray-200 bg-white p-4">
              <p className="flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-500">
                <Package className="h-4 w-4" /> 4 · La bodega
              </p>
              <label className="flex items-center gap-3">
                <input type="checkbox" checked={invCerrado} disabled={yaEntregada}
                       onChange={(e) => setInvCerrado(e.target.checked)}
                       className="h-6 w-6 rounded border-2 border-gray-400" />
                <span className="text-sm font-semibold text-gray-800">
                  El inventario de bodega y oficina quedó cerrado
                </span>
              </label>
              <input value={invObs} disabled={yaEntregada} onChange={(e) => setInvObs(e.target.value)}
                     placeholder="Lo consumido, lo repuesto, lo que falta"
                     className="h-12 w-full rounded-lg border-2 border-gray-300 px-3 text-sm disabled:bg-gray-100" />
            </section>

            {/* ── Firmas ───────────────────────────────────────────────── */}
            {!yaEntregada && (
              <section className="space-y-3 rounded-xl border-2 border-gray-900 bg-white p-4">
                <p className="flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-700">
                  <PenLine className="h-4 w-4" /> Firma de quien entrega
                </p>
                <textarea value={obs} onChange={(e) => setObs(e.target.value)} rows={2}
                          placeholder="Observaciones del turno"
                          className="w-full rounded-lg border-2 border-gray-300 p-3 text-sm" />
                <SignaturePad onCapture={setFirma} label={perfil?.nombre_completo ?? 'Supervisor saliente'} />
                {sinContestar.length > 0 && (
                  <p className="flex items-start gap-1.5 text-xs text-amber-800">
                    <AlertTriangle className="mt-px h-3.5 w-3.5 shrink-0" />
                    Faltan {sinContestar.length} pendiente(s) por contestar. El turno no se entrega sin decir
                    qué pasó con cada uno.
                  </p>
                )}
                <button onClick={() => void firmarLaEntrega()} disabled={guardando || !firma}
                        className="flex h-14 w-full items-center justify-center gap-2 rounded-xl bg-gray-900 text-lg font-bold text-white disabled:opacity-50">
                  {guardando ? <Spinner className="h-5 w-5" /> : <Check className="h-5 w-5" />}
                  Entregar el turno
                </button>
              </section>
            )}

            {yaEntregada && (
              <section className="rounded-xl border-2 border-blue-300 bg-blue-50 p-4">
                <p className="flex items-center gap-2 text-sm font-bold text-blue-900">
                  <CheckCircle2 className="h-4 w-4" /> Entregado por {entrega?.entrega_nombre}
                </p>
                <p className="mt-1 text-xs text-blue-800">
                  {entrega?.entregado_at?.slice(0, 16).replace('T', ' ')}
                  {entrega?.stock_fisico_lt != null && ` · ${miles(entrega.stock_fisico_lt)} L verificados`}
                  {!entrega?.conteo_fisico_hecho && ' · sin conteo físico'}
                </p>
                {!entrega?.conteo_fisico_hecho && entrega?.conteo_omitido_motivo && (
                  <p className="mt-2 rounded bg-white p-2 text-xs text-red-800">
                    No se contó: {entrega.conteo_omitido_motivo}
                  </p>
                )}
              </section>
            )}

            {yaEntregada && !yaRecibida && (
              <section className="space-y-3 rounded-xl border-2 border-gray-900 bg-white p-4">
                <p className="flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-gray-700">
                  <PenLine className="h-4 w-4" /> Firma de quien recibe
                </p>
                <p className="text-xs text-gray-600">
                  Firma el supervisor del turno {entrega?.turno_entrante}. Si no está, el Administrador
                  de Contrato. Quien entregó no puede firmar acá.
                </p>
                <textarea value={reparos} onChange={(e) => setReparos(e.target.value)} rows={2}
                          placeholder="Reparos: algo que no coincide con lo que se entregó"
                          className="w-full rounded-lg border-2 border-gray-300 p-3 text-sm" />
                <SignaturePad onCapture={setFirma} label={perfil?.nombre_completo ?? 'Supervisor entrante'} />
                <button onClick={() => void firmarLaRecepcion()} disabled={guardando || !firma}
                        className="flex h-14 w-full items-center justify-center gap-2 rounded-xl bg-gray-900 text-lg font-bold text-white disabled:opacity-50">
                  {guardando ? <Spinner className="h-5 w-5" /> : <Check className="h-5 w-5" />}
                  Recibir el turno
                </button>
              </section>
            )}

            {yaRecibida && (
              <section className="rounded-xl border-2 border-emerald-300 bg-emerald-50 p-4">
                <p className="flex items-center gap-2 text-sm font-bold text-emerald-900">
                  <CheckCircle2 className="h-4 w-4" /> Recibido por {entrega?.recibe_nombre}
                </p>
                <p className="mt-1 text-xs text-emerald-800">
                  {entrega?.recibido_at?.slice(0, 16).replace('T', ' ')}
                </p>
                {entrega?.reparos && (
                  <p className="mt-2 rounded bg-white p-2 text-xs text-amber-900">
                    <X className="mr-1 inline h-3 w-3" /> Con reparos: {entrega.reparos}
                  </p>
                )}
              </section>
            )}
          </>
        )}
      </main>
    </div>
  )
}

function Cifra({ k, v, u, alerta }: { k: string; v: string; u?: string; alerta?: boolean }) {
  return (
    <div className="rounded-lg bg-gray-50 p-2.5">
      <p className={cn('font-mono text-xl font-bold tabular-nums',
                       alerta ? 'text-red-700' : 'text-gray-900')}>
        {v}{u && <span className="ml-1 text-xs font-normal text-gray-500">{u}</span>}
      </p>
      <p className="mt-0.5 text-[11px] leading-tight text-gray-500">{k}</p>
    </div>
  )
}
