'use client'

// [MIG651] Cambio de programa en terreno. La cuadrilla llega y ESM pide otra
// cosa: calibrar camiones en vez de la EESS (combustible), la sala de
// microfiltrado en vez del rack (Lomas). El supervisor deja constancia de lo
// que no se hizo —queda «por reprogramar» para el planificador— y parte con lo
// nuevo. Todo funciona sin señal: se anota en el teléfono y viaja por la cola.

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { X, Truck, MapPin, Ban, Undo2, ChevronRight, Loader2 } from 'lucide-react'
import { useToast } from '@/contexts/toast-context'
import {
  getPuntosOffline, getLugaresOffline, crearServicioTerreno, marcarNoSeHizo, marcarZonaTerreno, normalizarPatente,
  type ZonaDia,
} from '@/lib/offline/enex-offline'
import {
  mundoDeLinea, TIPO_INSTALACION_LABEL,
  type EnexPendiente, type EnexPlanTarea, type EnexLugarItem, type EnexTerrenoInstalacion, type Mundo, type TipoServicio,
} from '@/lib/services/enex'

const MOTIVO_DEFECTO = 'Pedido de ESM: cambio de programa en terreno'

type Zona = { lugar_id: string; area: string; lugar: string; instalacion_ids: string[]; codigos: string[] }

/** Zonas (Lomas) armadas desde la plantilla de lugares. */
export function zonasDe(lugares: EnexLugarItem[]): Zona[] {
  const m = new Map<string, Zona>()
  for (const l of lugares) {
    let z = m.get(l.lugar_id)
    if (!z) { z = { lugar_id: l.lugar_id, area: l.area, lugar: l.lugar, instalacion_ids: l.instalacion_ids, codigos: [] }; m.set(l.lugar_id, z) }
    if (!z.codigos.includes(l.codigo)) z.codigos.push(l.codigo)
  }
  return Array.from(m.values())
}

export function CambioPrograma({ mundo, hoy, pend, planHoy, zonasDia, onClose }: {
  mundo: Mundo; hoy: string; pend: EnexPendiente[]; planHoy: EnexPlanTarea[]; zonasDia: ZonaDia[]; onClose: () => void
}) {
  const router = useRouter()
  const toast = useToast()
  const qc = useQueryClient()
  const [motivo, setMotivo] = useState(MOTIVO_DEFECTO)
  const [busy, setBusy] = useState<string | null>(null)

  const { data: puntos = [], isLoading } = useQuery({
    queryKey: ['enex-puntos-terreno'], queryFn: getPuntosOffline, networkMode: 'always', staleTime: 5 * 60_000,
  })
  const { data: lugares = [] } = useQuery({
    queryKey: ['enex-lugares-terreno'], queryFn: getLugaresOffline, networkMode: 'always', staleTime: 5 * 60_000,
  })

  const refrescar = () => {
    qc.invalidateQueries({ queryKey: ['enex-terreno'] })
    qc.invalidateQueries({ queryKey: ['enex-pending-count'] })
    qc.invalidateQueries({ queryKey: ['enex-zonas-dia'] })
  }
  const motivoOk = () => {
    if (motivo.trim().length < 5) { toast.error('Escribe el motivo (quién lo pidió y por qué)'); return false }
    return true
  }

  // ── Lo planificado hoy (de este mundo) ─────────────────────────────────────
  const deHoy = useMemo(() => pend.filter((p) => mundoDeLinea(p.linea) === mundo && !p.ejecucion_id &&
    p.fecha_programada?.slice(0, 10) === hoy && !(mundo === 'lubricante' && p.tipo_servicio === 'mantencion')), [pend, mundo, hoy])

  async function noSeHizo(p: EnexPendiente, deshacer = false) {
    if (!deshacer && !motivoOk()) return
    setBusy(p.programacion_id)
    try {
      await marcarNoSeHizo(p, motivo.trim(), deshacer)
      toast.success(deshacer ? 'Marca quitada' : 'Anotado: queda por reprogramar')
      refrescar()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(null) }
  }

  // ── Combustible: calibrar un camión ────────────────────────────────────────
  const comodines = useMemo(() => puntos.filter((i) => i.es_comodin && mundoDeLinea(i.linea) === mundo), [puntos, mundo])
  const [faenaCam, setFaenaCam] = useState('')
  const faenaSel = faenaCam || comodines[0]?.faena_id || ''
  const [patente, setPatente] = useState('')
  const patentesFaena = useMemo(() => puntos.filter((i) => i.faena_id === faenaSel && i.instalacion_tipo === 'camion' && !i.es_comodin && i.patente)
    .map((i) => i.patente as string).sort(), [puntos, faenaSel])

  async function calibrarCamion() {
    const com = comodines.find((c) => c.faena_id === faenaSel)
    if (!com) { toast.error('Elige la faena'); return }
    if (normalizarPatente(patente).length < 4) { toast.error('Anota la patente del camión'); return }
    if (!motivoOk()) return
    setBusy('camion')
    try {
      const id = await crearServicioTerreno({ punto: com, tipoServicio: 'calibracion', motivo: motivo.trim(), patente })
      refrescar()
      router.push(`/m/enex/servicio/?id=${id}`)
    } catch (e) { toast.error((e as Error).message); setBusy(null) }
  }

  // ── Otro punto (EESS, petrolera, semimóvil…) ──────────────────────────────
  const otrosPuntos = useMemo(() => puntos.filter((i) => mundoDeLinea(i.linea) === mundo && i.instalacion_tipo !== 'camion' && !i.es_comodin), [puntos, mundo])
  const [puntoId, setPuntoId] = useState('')
  const [tipoServ, setTipoServ] = useState<TipoServicio>('mantencion')

  /** Abre el servicio del mes de ese punto si existe; si no, lo crea. */
  async function abrirPunto(punto: EnexTerrenoInstalacion, tipo: TipoServicio, items?: string[]) {
    const ya = pend.find((p) => p.instalacion_id === punto.instalacion_id && p.tipo_servicio === tipo && !p.cumplida)
    const id = ya ? ya.programacion_id : await crearServicioTerreno({ punto, tipoServicio: tipo, motivo: motivo.trim() })
    refrescar()
    router.push(`/m/enex/servicio/?id=${id}${items?.length ? `&items=${encodeURIComponent(items.join(','))}` : ''}`)
  }

  async function irOtroPunto() {
    const punto = otrosPuntos.find((i) => i.instalacion_id === puntoId)
    if (!punto) { toast.error('Elige el punto'); return }
    if (!motivoOk()) return
    setBusy('punto')
    try { await abrirPunto(punto, tipoServ) } catch (e) { toast.error((e as Error).message); setBusy(null) }
  }

  // ── Lomas: zonas ───────────────────────────────────────────────────────────
  const zonas = useMemo(() => zonasDe(lugares), [lugares])
  // Zonas del plan de hoy: por área + nombre de zona (alcance de la tarea).
  const zonasPlanHoy = useMemo(() => zonas.filter((z) => planHoy.some((t) => t.area === z.area && t.alcance === z.lugar && t.estado === 'pendiente')),
    [zonas, planHoy])
  const marcaZona = (id: string) => zonasDia.find((z) => z.lugar_id === id)

  async function zonaNoSeHizo(z: Zona) {
    if (!motivoOk()) return
    setBusy(z.lugar_id)
    try {
      await marcarZonaTerreno({ lugar_id: z.lugar_id, area: z.area, lugar: z.lugar, hacer: false, motivo: motivo.trim() })
      toast.success(`${z.lugar}: queda por reprogramar`)
      refrescar()
    } catch (e) { toast.error((e as Error).message) } finally { setBusy(null) }
  }

  async function hacerZona(z: Zona, instalacionId: string) {
    if (!motivoOk()) return
    const punto = puntos.find((i) => i.instalacion_id === instalacionId)
    if (!punto) { toast.error('Ese punto no está descargado en el teléfono: ábrelo con señal una vez'); return }
    setBusy(`${z.lugar_id}|${instalacionId}`)
    try {
      await marcarZonaTerreno({ lugar_id: z.lugar_id, area: z.area, lugar: z.lugar, hacer: true, motivo: motivo.trim() })
      await abrirPunto(punto, 'mantencion', z.codigos)
    } catch (e) { toast.error((e as Error).message); setBusy(null) }
  }
  const nombrePunto = (id: string) => puntos.find((i) => i.instalacion_id === id)?.instalacion ?? 'Punto'

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto bg-gray-50">
      <div className="sticky top-0 z-10 flex items-center gap-2 border-b bg-white p-3">
        <div className="flex-1">
          <p className="text-sm font-bold">Cambio de programa</p>
          <p className="text-[11px] text-gray-500">ESM pidió otra cosa: anota qué no se hizo y parte con lo nuevo</p>
        </div>
        <button onClick={onClose} className="rounded-lg p-1.5 text-gray-500" aria-label="Cerrar"><X className="h-5 w-5" /></button>
      </div>

      <div className="space-y-4 p-3 pb-20">
        <div>
          <label className="text-xs font-semibold text-gray-700">Motivo (queda en el registro)</label>
          <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={2}
                    className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
        </div>

        {isLoading && <div className="flex justify-center py-4"><Loader2 className="h-5 w-5 animate-spin text-gray-400" /></div>}

        {/* 1. Lo que no se hará */}
        <section className="rounded-xl border border-gray-200 bg-white p-3">
          <p className="flex items-center gap-1.5 text-sm font-bold text-gray-800"><Ban className="h-4 w-4 text-orange-600" /> Lo planificado hoy que NO se hará</p>
          <p className="text-[11px] text-gray-500">Queda «por reprogramar» con el motivo; el planificador le pone fecha nueva.</p>
          <div className="mt-2 space-y-1.5">
            {deHoy.length === 0 && zonasPlanHoy.length === 0 && <p className="text-xs text-gray-400">No hay nada planificado hoy pendiente.</p>}
            {deHoy.map((p) => (
              <div key={p.programacion_id} className="flex items-center gap-2 rounded-lg border p-2 text-xs">
                <span className="flex-1">
                  <b>{p.es_comodin ? 'Camión por asignar' : p.instalacion}</b>
                  <span className="text-gray-500"> · {p.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención'}</span>
                  {p.por_reprogramar_motivo && <span className="block text-[10px] text-orange-700">No se hizo: {p.por_reprogramar_motivo}</span>}
                </span>
                {p.por_reprogramar_motivo ? (
                  <button disabled={busy !== null} onClick={() => noSeHizo(p, true)} className="flex items-center gap-1 rounded-lg border px-2 py-1 text-[11px] text-gray-600">
                    <Undo2 className="h-3 w-3" /> Deshacer
                  </button>
                ) : (
                  <button disabled={busy !== null} onClick={() => noSeHizo(p)} className="rounded-lg bg-orange-600 px-2 py-1 text-[11px] font-semibold text-white disabled:opacity-50">
                    {busy === p.programacion_id ? '…' : 'No se hizo'}
                  </button>
                )}
              </div>
            ))}
            {zonasPlanHoy.map((z) => {
              const m = marcaZona(z.lugar_id)
              return (
                <div key={z.lugar_id} className="flex items-center gap-2 rounded-lg border p-2 text-xs">
                  <span className="flex-1"><b>{z.lugar}</b> <span className="text-gray-500">· {z.area}</span>
                    {m && !m.hacer && <span className="block text-[10px] text-orange-700">No se hizo: {m.motivo}</span>}
                  </span>
                  {!(m && !m.hacer) && (
                    <button disabled={busy !== null} onClick={() => zonaNoSeHizo(z)} className="rounded-lg bg-orange-600 px-2 py-1 text-[11px] font-semibold text-white disabled:opacity-50">
                      {busy === z.lugar_id ? '…' : 'No se hizo'}
                    </button>
                  )}
                </div>
              )
            })}
          </div>
        </section>

        {/* 2. Lo que se hace en su lugar */}
        {mundo === 'combustible' ? (
          <>
            <section className="rounded-xl border-2 border-blue-300 bg-white p-3">
              <p className="flex items-center gap-1.5 text-sm font-bold text-gray-800"><Truck className="h-4 w-4 text-blue-600" /> Calibrar un camión</p>
              <p className="text-[11px] text-gray-500">La patente del camión que entregó la operación. Si no está en la lista, se agrega sola.</p>
              {comodines.length === 0 && !isLoading ? (
                <p className="mt-2 text-xs text-amber-700">No hay faenas con camiones descargadas en el teléfono. Abre la app con señal una vez.</p>
              ) : (
                <div className="mt-2 space-y-2">
                  {comodines.length > 1 && (
                    <select value={faenaSel} onChange={(e) => setFaenaCam(e.target.value)} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm">
                      {comodines.map((c) => <option key={c.faena_id} value={c.faena_id}>{c.faena}</option>)}
                    </select>
                  )}
                  <input value={patente} onChange={(e) => setPatente(e.target.value.toUpperCase())} list="patentes-cambio"
                         placeholder="Patente (ej. SZBD35)" autoCapitalize="characters"
                         className="w-full rounded-lg border border-gray-300 px-3 py-2 font-mono text-sm uppercase" />
                  <datalist id="patentes-cambio">{patentesFaena.map((p) => <option key={p} value={p} />)}</datalist>
                  {patente && normalizarPatente(patente).length >= 4 && !patentesFaena.includes(normalizarPatente(patente)) && (
                    <p className="text-[11px] text-amber-700">Patente nueva: se agrega a los camiones de la faena.</p>
                  )}
                  <button disabled={busy !== null} onClick={calibrarCamion}
                          className="flex w-full items-center justify-center gap-1 rounded-lg bg-blue-600 py-2.5 text-sm font-semibold text-white disabled:opacity-50">
                    {busy === 'camion' ? <Loader2 className="h-4 w-4 animate-spin" /> : <>Empezar calibración <ChevronRight className="h-4 w-4" /></>}
                  </button>
                  <p className="text-[10px] text-gray-500">Para otro camión, vuelve a «Cambio de programa» y repite.</p>
                </div>
              )}
            </section>

            <section className="rounded-xl border border-gray-200 bg-white p-3">
              <p className="flex items-center gap-1.5 text-sm font-bold text-gray-800"><MapPin className="h-4 w-4 text-gray-600" /> Otro punto</p>
              <div className="mt-2 space-y-2">
                <select value={puntoId} onChange={(e) => setPuntoId(e.target.value)} className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm">
                  <option value="">Elige el punto…</option>
                  {otrosPuntos.map((i) => <option key={i.instalacion_id} value={i.instalacion_id}>{i.faena} · {i.instalacion} ({TIPO_INSTALACION_LABEL[i.instalacion_tipo] ?? i.instalacion_tipo})</option>)}
                </select>
                <div className="grid grid-cols-2 gap-2">
                  {(['mantencion', 'calibracion'] as TipoServicio[]).map((t) => (
                    <button key={t} onClick={() => setTipoServ(t)}
                            className={`rounded-lg border-2 py-1.5 text-xs font-semibold ${tipoServ === t ? 'border-blue-500 bg-blue-50 text-blue-800' : 'border-gray-200 text-gray-600'}`}>
                      {t === 'mantencion' ? 'Mantención' : 'Calibración'}
                    </button>
                  ))}
                </div>
                <button disabled={busy !== null || !puntoId} onClick={irOtroPunto}
                        className="flex w-full items-center justify-center gap-1 rounded-lg bg-gray-800 py-2 text-sm font-semibold text-white disabled:opacity-40">
                  {busy === 'punto' ? <Loader2 className="h-4 w-4 animate-spin" /> : <>Abrir servicio <ChevronRight className="h-4 w-4" /></>}
                </button>
              </div>
            </section>
          </>
        ) : (
          <section className="rounded-xl border-2 border-emerald-300 bg-white p-3">
            <p className="flex items-center gap-1.5 text-sm font-bold text-gray-800"><MapPin className="h-4 w-4 text-emerald-600" /> Hacer otra zona hoy</p>
            <p className="text-[11px] text-gray-500">Abre el servicio con las actividades de esa zona.</p>
            {zonas.length === 0 && <p className="mt-2 text-xs text-amber-700">No hay zonas descargadas en el teléfono. Abre la app con señal una vez.</p>}
            <div className="mt-2 space-y-3">
              {Array.from(new Set(zonas.map((z) => z.area))).map((area) => (
                <div key={area}>
                  <p className="text-xs font-bold text-gray-700">{area}</p>
                  <div className="mt-1 space-y-1.5">
                    {zonas.filter((z) => z.area === area).map((z) => {
                      const m = marcaZona(z.lugar_id)
                      return (
                        <div key={z.lugar_id} className="rounded-lg border p-2">
                          <p className="text-xs font-semibold text-gray-800">{z.lugar}
                            <span className="ml-1 font-normal text-gray-500">· {z.codigos.length} actividades</span>
                            {m?.hacer && <span className="ml-1 rounded bg-emerald-100 px-1 text-[10px] text-emerald-700">hoy</span>}
                          </p>
                          <div className="mt-1 flex flex-wrap gap-1.5">
                            {z.instalacion_ids.map((iid) => (
                              <button key={iid} disabled={busy !== null} onClick={() => hacerZona(z, iid)}
                                      className="rounded-lg bg-emerald-600 px-2.5 py-1.5 text-[11px] font-semibold text-white disabled:opacity-50">
                                {busy === `${z.lugar_id}|${iid}` ? '…' : <>{z.instalacion_ids.length > 1 ? nombrePunto(iid) : 'Hacer esta zona'} <ChevronRight className="inline h-3 w-3" /></>}
                              </button>
                            ))}
                          </div>
                        </div>
                      )
                    })}
                  </div>
                </div>
              ))}
            </div>
          </section>
        )}
      </div>
    </div>
  )
}
