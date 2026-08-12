'use client'

// Despacho de combustible en faena — app de terreno (MIG279).
//
// Reemplaza el papel del operador del camión. Pensada para usarse con guantes,
// en el camión y SIN SEÑAL: el catálogo queda bajado y cada carga se guarda en
// el teléfono y sube sola cuando aparece red.
//
// El turno, el camión y quién carga se eligen UNA vez al empezar y quedan
// fijos: en el papel tampoco se reescriben en cada línea. Y el medidor inicial
// llega puesto con el final de la carga anterior, que es como corre la corrida.

import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  Fuel, Plus, Check, WifiOff, CloudOff, RefreshCw, Search, X, Truck,
  MapPin, Trash2, CheckCircle2, Download, ChevronDown, Camera,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { useAuth } from '@/contexts/auth-context'
import { useExigirSesion } from '@/hooks/use-exigir-sesion'
import { useNetworkStatus } from '@/hooks/use-calama-offline'
import { SinSesionOffline } from '@/components/enex/sin-sesion-offline'
import {
  FAENA_ROMERAL, TURNOS,
  type CatalogoFaena, type CombEquipo, type CombDespacho,
} from '@/lib/services/combustible-faena'
import {
  getCatalogoOffline, descargarCatalogo, ultimaDescarga, guardarDespacho, guardarFotoLocal,
  sincronizar, getDiaOffline, descartarPendiente, pendientesCount,
  type DespachoPendiente,
} from '@/lib/offline/combustible-faena-offline'

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
  return Number.isFinite(n) ? n : null
}

const K_TURNO = 'romeral-turno'
const K_CAMION = 'romeral-camion'
const K_OPERADOR = 'romeral-operador'
const K_METER = 'romeral-meter'

export default function RomeralTerrenoPage() {
  const { verificando, sinSesionOffline } = useExigirSesion()
  const { perfil } = useAuth()
  const online = useNetworkStatus()
  const toast = useToast()

  const [cat, setCat] = useState<CatalogoFaena | null>(null)
  const [cargando, setCargando] = useState(true)
  const [fecha, setFecha] = useState('')
  const [descarga, setDescarga] = useState<string | null>(null)
  const [porSubir, setPorSubir] = useState(0)

  // Cabecera del turno — se pregunta una vez
  const [turno, setTurno] = useState('')
  const [camionId, setCamionId] = useState('')
  const [camionOtro, setCamionOtro] = useState('')
  const [operador, setOperador] = useState('')
  const [cabeceraAbierta, setCabeceraAbierta] = useState(false)

  // Formulario de la carga
  const [abierto, setAbierto] = useState(false)
  const [buscar, setBuscar] = useState('')
  const [equipo, setEquipo] = useState<CombEquipo | null>(null)
  const [equipoTexto, setEquipoTexto] = useState('')
  const [ubicacionId, setUbicacionId] = useState('')
  const [meterIni, setMeterIni] = useState('')
  const [meterFin, setMeterFin] = useState('')
  const [litrosManual, setLitrosManual] = useState('')
  const [obs, setObs] = useState('')
  const [guardando, setGuardando] = useState(false)
  type Foto = { file: File; preview: string }
  const [fotoIni, setFotoIni] = useState<Foto | null>(null)
  const [fotoFin, setFotoFin] = useState<Foto | null>(null)
  const [sinFotoMotivo, setSinFotoMotivo] = useState('')

  const [servidor, setServidor] = useState<CombDespacho[]>([])
  const [locales, setLocales] = useState<DespachoPendiente[]>([])

  useEffect(() => { setFecha(hoyISO()) }, [])

  // Recordar cabecera del turno entre cargas y entre reinicios de la app
  useEffect(() => {
    try {
      setTurno(localStorage.getItem(K_TURNO) ?? '')
      setCamionId(localStorage.getItem(K_CAMION) ?? '')
      setOperador(localStorage.getItem(K_OPERADOR) ?? '')
    } catch { /* modo privado */ }
  }, [])
  useEffect(() => { try { localStorage.setItem(K_TURNO, turno) } catch { /* no-op */ } }, [turno])
  useEffect(() => { try { localStorage.setItem(K_CAMION, camionId) } catch { /* no-op */ } }, [camionId])
  useEffect(() => { try { localStorage.setItem(K_OPERADOR, operador) } catch { /* no-op */ } }, [operador])
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
    let cancel = false
    ;(async () => {
      setCargando(true)
      const c = await getCatalogoOffline(FAENA_ROMERAL)
      if (cancel) return
      setCat(c)
      setDescarga(await ultimaDescarga(FAENA_ROMERAL))
      if (c) await refrescar(c.faena.id, fecha)
      setCargando(false)
      if (!c) setCabeceraAbierta(true)
    })()
    return () => { cancel = true }
  }, [fecha, refrescar])

  // Al recuperar señal: subir lo pendiente
  useEffect(() => {
    const trySync = async () => {
      if (typeof navigator === 'undefined' || !navigator.onLine) return
      const r = await sincronizar()
      if ((r.ok > 0 || r.failed > 0) && cat && fecha) {
        await refrescar(cat.faena.id, fecha)
        if (r.ok > 0) toast.success(`${r.ok} carga(s) subida(s)`)
      }
    }
    window.addEventListener('online', trySync)
    void trySync()
    const t = setInterval(trySync, 60_000)
    return () => { window.removeEventListener('online', trySync); clearInterval(t) }
  }, [cat, fecha, refrescar, toast])

  const camion = cat?.camiones.find((c) => c.id === camionId) ?? null
  const camionLabel = camion ? (camion.patente ?? camion.nombre) : (camionOtro || null)

  const equiposFiltrados = useMemo(() => {
    if (!cat) return []
    const q = buscar.trim().toLowerCase()
    if (!q) return cat.equipos.slice(0, 40)
    return cat.equipos.filter((e) =>
      e.nombre.toLowerCase().includes(q) ||
      (e.descripcion ?? '').toLowerCase().includes(q) ||
      (e.ceco ?? '').toLowerCase().includes(q)).slice(0, 40)
  }, [cat, buscar])

  const litrosCalc = useMemo(() => {
    const a = num(meterIni), b = num(meterFin)
    if (a != null && b != null && b >= a) return +(b - a).toFixed(2)
    return null
  }, [meterIni, meterFin])
  const litrosFinales = litrosCalc ?? num(litrosManual)

  const totalDia = useMemo(
    () => servidor.filter((d) => !d.anulado).reduce((s, d) => s + Number(d.litros), 0)
        + locales.reduce((s, d) => s + Number(d.litros), 0),
    [servidor, locales])

  function abrirNueva() {
    if (!turno || (!camionId && !camionOtro) || !operador.trim()) {
      setCabeceraAbierta(true)
      toast.error('Primero completa turno, camión y quién carga')
      return
    }
    // El medidor inicial viene del final de la carga anterior: así corre la
    // corrida y el operador no lo escribe dos veces.
    let ini = ''
    try { ini = localStorage.getItem(K_METER) ?? '' } catch { /* no-op */ }
    setMeterIni(ini); setMeterFin(''); setLitrosManual('')
    setEquipo(null); setEquipoTexto(''); setBuscar(''); setUbicacionId(''); setObs('')
    setFotoIni(null); setFotoFin(null); setSinFotoMotivo('')
    setAbierto(true)
  }

  async function guardar() {
    if (!cat) return
    if (!equipo && !equipoTexto.trim()) { toast.error('Indica a quién estás cargando'); return }
    if (litrosFinales == null || litrosFinales <= 0) { toast.error('Faltan los litros o el medidor'); return }
    if ((!fotoIni || !fotoFin) && !sinFotoMotivo.trim()) {
      toast.error('Saca la foto del medidor, o escribe por qué no pudiste')
      return
    }
    setGuardando(true)
    try {
      const ubic = cat.ubicaciones.find((u) => u.id === ubicacionId) ?? null
      // Las fotos quedan en el teléfono y suben con la carga cuando haya señal.
      const blobIni = fotoIni ? await guardarFotoLocal(fotoIni.file) : null
      const blobFin = fotoFin ? await guardarFotoLocal(fotoFin.file) : null
      const { enviado } = await guardarDespacho({
        faenaId: cat.faena.id,
        fecha,
        turno,
        estanqueId: camionId || null,
        camionPatente: camionId ? null : (camionOtro.trim() || null),
        equipoId: equipo?.id ?? null,
        equipoTexto: equipo ? null : equipoTexto.trim(),
        ubicacionId: ubicacionId || null,
        meterInicial: num(meterIni),
        meterFinal: num(meterFin),
        litros: litrosFinales,
        operadorNombre: operador.trim(),
        hora: horaAhora(),
        observacion: obs.trim() || null,
        sinFotoMotivo: (!fotoIni || !fotoFin) ? sinFotoMotivo.trim() : null,
      }, {
        equipo_nombre: equipo?.nombre ?? equipoTexto.trim(),
        ceco_nombre: equipo?.ceco ?? null,
        ubicacion_nombre: ubic?.nombre ?? null,
        camion_nombre: camionLabel,
        foto_ini_blob: blobIni,
        foto_fin_blob: blobFin,
      })
      // El medidor final queda listo para la próxima carga
      if (num(meterFin) != null) { try { localStorage.setItem(K_METER, meterFin) } catch { /* no-op */ } }
      setAbierto(false)
      await refrescar(cat.faena.id, fecha)
      toast.success(enviado ? 'Carga registrada' : 'Guardada en el teléfono — sube sola con señal')
    } catch (e) { toast.error((e as Error).message) } finally { setGuardando(false) }
  }

  if (sinSesionOffline) return <SinSesionOffline />
  if (verificando || cargando) return <div className="flex justify-center py-16"><Spinner /></div>

  if (!cat) {
    return (
      <div className="p-4 text-center">
        <CloudOff className="mx-auto h-10 w-10 text-gray-300" />
        <p className="mt-3 text-sm text-gray-600">
          No hay catálogo descargado en este teléfono y no hay señal para bajarlo.
        </p>
        <p className="mt-1 text-xs text-gray-500">
          Conéctate una vez a internet para dejar la faena lista y después trabajas sin señal.
        </p>
      </div>
    )
  }

  const cabeceraLista = !!turno && (!!camionId || !!camionOtro.trim()) && !!operador.trim()

  return (
    <div className="space-y-3 p-3 pb-24">
      {/* Encabezado */}
      <div className="flex items-center gap-2">
        <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-orange-600 text-white">
          <Fuel className="h-5 w-5" />
        </div>
        <div className="flex-1">
          <h1 className="text-base font-bold leading-tight">Despacho de combustible</h1>
          <p className="text-[11px] text-gray-500">{cat.faena.nombre}</p>
        </div>
        <div className={`flex items-center gap-1 rounded-full px-2 py-1 text-[10px] font-semibold ${
          online ? 'bg-green-100 text-green-700' : 'bg-amber-100 text-amber-800'}`}>
          {online ? <CheckCircle2 className="h-3 w-3" /> : <WifiOff className="h-3 w-3" />}
          {online ? 'En línea' : 'Sin señal'}
        </div>
      </div>

      {porSubir > 0 && (
        <div className="flex items-center gap-2 rounded-lg border border-amber-300 bg-amber-50 p-2 text-xs text-amber-800">
          <CloudOff className="h-4 w-4 flex-shrink-0" />
          <span className="flex-1">{porSubir} carga(s) guardada(s) en el teléfono, aún sin subir.</span>
          {online && (
            <button onClick={async () => {
                      const r = await sincronizar()
                      await refrescar(cat.faena.id, fecha)
                      toast.success(r.ok > 0 ? `${r.ok} subida(s)` : 'No se pudo subir todavía')
                    }}
                    className="rounded border border-amber-400 bg-white px-2 py-1 font-semibold">
              Subir
            </button>
          )}
        </div>
      )}

      {/* Cabecera del turno */}
      <div className={`rounded-xl border-2 bg-white ${cabeceraLista ? 'border-gray-200' : 'border-orange-400'}`}>
        <button onClick={() => setCabeceraAbierta((v) => !v)}
                className="flex w-full items-center gap-2 p-3 text-left">
          <Truck className="h-4 w-4 flex-shrink-0 text-gray-500" />
          <div className="flex-1">
            {cabeceraLista ? (
              <>
                <p className="text-sm font-bold text-gray-800">
                  {camionLabel} · Turno {turno}
                </p>
                <p className="text-[11px] text-gray-500">Carga: {operador}</p>
              </>
            ) : (
              <p className="text-sm font-bold text-orange-700">Completa turno, camión y quién carga</p>
            )}
          </div>
          <ChevronDown className={`h-4 w-4 text-gray-400 transition ${cabeceraAbierta ? 'rotate-180' : ''}`} />
        </button>

        {cabeceraAbierta && (
          <div className="space-y-3 border-t p-3">
            <div>
              <label className="text-[11px] font-semibold text-gray-600">Turno</label>
              <div className="mt-1 grid grid-cols-2 gap-2">
                {TURNOS.map((t) => (
                  <button key={t} onClick={() => setTurno(t)}
                          className={`rounded-lg border-2 py-3 text-sm font-bold ${
                            turno === t ? 'border-orange-500 bg-orange-50 text-orange-800' : 'border-gray-200 text-gray-600'}`}>
                    {t}
                  </button>
                ))}
              </div>
            </div>
            <div>
              <label className="text-[11px] font-semibold text-gray-600">Camión que despacha</label>
              <div className="mt-1 space-y-2">
                {cat.camiones.map((c) => (
                  <button key={c.id} onClick={() => { setCamionId(c.id); setCamionOtro('') }}
                          className={`flex w-full items-center gap-2 rounded-lg border-2 px-3 py-2.5 text-left text-sm font-semibold ${
                            camionId === c.id ? 'border-orange-500 bg-orange-50 text-orange-800' : 'border-gray-200 text-gray-700'}`}>
                    <Truck className="h-4 w-4" /> {c.patente ?? c.nombre}
                  </button>
                ))}
                {/* Puede despachar un camión que no está en el catálogo */}
                <div className={`rounded-lg border-2 px-3 py-2 ${!camionId && camionOtro ? 'border-orange-500 bg-orange-50' : 'border-gray-200'}`}>
                  <label className="text-[11px] text-gray-500">Otro camión (escribe la patente)</label>
                  <input value={camionOtro}
                         onChange={(e) => { setCamionOtro(e.target.value.toUpperCase()); if (e.target.value) setCamionId('') }}
                         placeholder="Ej: HHWB-42"
                         className="w-full bg-transparent py-1 text-sm font-semibold uppercase outline-none" />
                </div>
              </div>
            </div>
            <div>
              <label className="text-[11px] font-semibold text-gray-600">¿Quién carga?</label>
              <input value={operador} onChange={(e) => setOperador(e.target.value)}
                     placeholder="Nombre del operador"
                     className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2.5 text-sm" />
            </div>
            {cabeceraLista && (
              <button onClick={() => setCabeceraAbierta(false)}
                      className="w-full rounded-lg bg-gray-800 py-2.5 text-sm font-bold text-white">
                Listo
              </button>
            )}
          </div>
        )}
      </div>

      {/* Resumen del día */}
      <div className="flex items-center gap-3 rounded-xl border border-gray-200 bg-white p-3">
        <div className="flex-1">
          <p className="text-[11px] text-gray-500">Cargas de hoy</p>
          <p className="text-lg font-bold text-gray-900">{servidor.filter((d) => !d.anulado).length + locales.length}</p>
        </div>
        <div className="flex-1">
          <p className="text-[11px] text-gray-500">Litros del día</p>
          <p className="text-lg font-bold text-orange-700">{totalDia.toLocaleString('es-CL')} L</p>
        </div>
        <button onClick={async () => {
                  try {
                    const n = await descargarCatalogo(FAENA_ROMERAL)
                    setCat(await getCatalogoOffline(FAENA_ROMERAL))
                    setDescarga(new Date().toISOString())
                    toast.success(`${n} equipos listos para trabajar sin señal`)
                  } catch { toast.error('Sin señal para actualizar el catálogo') }
                }}
                className="rounded-lg border p-2 text-gray-400" title="Actualizar catálogo">
          <Download className="h-4 w-4" />
        </button>
      </div>
      {descarga && (
        <p className="text-center text-[10px] text-gray-400">
          {cat.equipos.length} equipos y {cat.ubicaciones.length} lugares en el teléfono ·
          {' '}actualizado {new Date(descarga).toLocaleDateString('es-CL')}
        </p>
      )}

      {/* Cargas del día */}
      <div className="space-y-2">
        {locales.map((d) => (
          <div key={d.local_id} className="rounded-xl border border-amber-300 bg-amber-50/60 p-3">
            <div className="flex items-start gap-2">
              <div className="flex-1">
                <p className="text-sm font-bold text-gray-800">{d.equipo_nombre}</p>
                <p className="text-[11px] text-gray-500">
                  {d.ceco_nombre ? `CECO ${d.ceco_nombre}` : 'sin CECO'}
                  {d.ubicacion_nombre ? ` · ${d.ubicacion_nombre}` : ''}
                  {d.hora ? ` · ${d.hora}` : ''}
                </p>
              </div>
              <div className="text-right">
                <p className="text-base font-bold text-orange-700">{Number(d.litros).toLocaleString('es-CL')} L</p>
                <p className="flex items-center gap-1 text-[10px] text-amber-700"><CloudOff className="h-3 w-3" /> sin subir</p>
              </div>
              <button onClick={async () => {
                        await descartarPendiente(d.local_id)
                        await refrescar(cat.faena.id, fecha)
                        toast.success('Carga descartada')
                      }}
                      className="text-gray-300 hover:text-red-600" title="Descartar (aún no sube)">
                <Trash2 className="h-4 w-4" />
              </button>
            </div>
          </div>
        ))}
        {servidor.map((d) => (
          <div key={d.id} className={`rounded-xl border bg-white p-3 ${d.anulado ? 'opacity-50' : 'border-gray-200'}`}>
            <div className="flex items-start gap-2">
              <div className="flex-1">
                <p className={`text-sm font-bold text-gray-800 ${d.anulado ? 'line-through' : ''}`}>{d.equipo}</p>
                <p className="text-[11px] text-gray-500">
                  {d.ceco ? `CECO ${d.ceco}` : 'sin CECO'}
                  {d.ubicacion ? ` · ${d.ubicacion}` : ''}
                  {d.hora ? ` · ${d.hora.slice(0, 5)}` : ''}
                  {d.turno ? ` · ${d.turno}` : ''}
                </p>
                {d.meter_inicial != null && d.meter_final != null && (
                  <p className="text-[10px] text-gray-400">
                    medidor {Number(d.meter_inicial).toLocaleString('es-CL')} → {Number(d.meter_final).toLocaleString('es-CL')}
                  </p>
                )}
              </div>
              <div className="text-right">
                <p className="text-base font-bold text-gray-800">{Number(d.litros).toLocaleString('es-CL')} L</p>
                <p className="flex items-center justify-end gap-1 text-[10px] text-green-600"><Check className="h-3 w-3" /> guardada</p>
              </div>
            </div>
          </div>
        ))}
        {servidor.length === 0 && locales.length === 0 && (
          <p className="py-10 text-center text-sm text-gray-400">
            Todavía no hay cargas hoy. Aprieta el botón naranjo para anotar la primera.
          </p>
        )}
      </div>

      {/* Botón grande de nueva carga */}
      <button onClick={abrirNueva}
              className="fixed bottom-4 left-3 right-3 flex items-center justify-center gap-2 rounded-2xl bg-orange-600 py-4 text-base font-bold text-white shadow-lg active:bg-orange-700">
        <Plus className="h-5 w-5" /> Nueva carga
      </button>

      {/* Formulario de carga */}
      {abierto && (
        <div className="fixed inset-0 z-50 flex flex-col bg-white">
          <div className="flex items-center gap-2 border-b p-3">
            <h2 className="flex-1 text-base font-bold">Nueva carga</h2>
            <button onClick={() => setAbierto(false)} className="rounded-lg border p-2 text-gray-500">
              <X className="h-5 w-5" />
            </button>
          </div>

          <div className="flex-1 space-y-4 overflow-y-auto p-3 pb-28">
            {/* A quién se carga */}
            <div>
              <label className="text-xs font-bold text-gray-700">¿A quién estás cargando?</label>
              {equipo ? (
                <div className="mt-1 flex items-center gap-2 rounded-lg border-2 border-orange-400 bg-orange-50 p-3">
                  <div className="flex-1">
                    <p className="text-sm font-bold text-gray-900">{equipo.nombre}</p>
                    <p className="text-[11px] text-gray-600">
                      {equipo.descripcion ?? ''}{equipo.ceco ? ` · CECO ${equipo.ceco}` : ''}
                      {equipo.ceco_empresa ? ` · ${equipo.ceco_empresa}` : ''}
                    </p>
                  </div>
                  <button onClick={() => { setEquipo(null); setBuscar('') }} className="text-gray-400">
                    <X className="h-4 w-4" />
                  </button>
                </div>
              ) : (
                <>
                  <div className="relative mt-1">
                    <Search className="absolute left-3 top-3.5 h-4 w-4 text-gray-400" />
                    <input value={buscar} onChange={(e) => setBuscar(e.target.value)}
                           placeholder="Busca: pala, generador, CAEX, CECO…"
                           className="w-full rounded-lg border border-gray-300 py-3 pl-9 pr-3 text-sm" />
                  </div>
                  <div className="mt-1 max-h-64 overflow-y-auto rounded-lg border">
                    {equiposFiltrados.map((e) => (
                      <button key={e.id} onClick={() => { setEquipo(e); setEquipoTexto('') }}
                              className="flex w-full items-center gap-2 border-b px-3 py-2.5 text-left last:border-0 active:bg-orange-50">
                        <div className="flex-1">
                          <p className="text-sm font-semibold text-gray-800">{e.nombre}</p>
                          <p className="text-[10px] text-gray-500">
                            {e.descripcion ?? ''}{e.ceco ? ` · ${e.ceco}` : ''}
                          </p>
                        </div>
                      </button>
                    ))}
                    {equiposFiltrados.length === 0 && (
                      <div className="p-3">
                        <p className="text-xs text-gray-500">No aparece en la lista. Escríbelo:</p>
                        <input value={equipoTexto} onChange={(e) => setEquipoTexto(e.target.value)}
                               placeholder="Nombre del equipo"
                               className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2.5 text-sm" />
                      </div>
                    )}
                  </div>
                </>
              )}
            </div>

            {/* Lugar */}
            <div>
              <label className="text-xs font-bold text-gray-700">¿Dónde?</label>
              <select value={ubicacionId} onChange={(e) => setUbicacionId(e.target.value)}
                      className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-3 text-sm">
                <option value="">— Elige el lugar —</option>
                {cat.ubicaciones.map((u) => <option key={u.id} value={u.id}>{u.nombre}</option>)}
              </select>
            </div>

            {/* Medidor: número y foto, uno al lado del otro */}
            <div>
              <label className="text-xs font-bold text-gray-700">Medidor del camión</label>
              <div className="mt-1 grid grid-cols-2 gap-2">
                {([
                  { k: 'ini' as const, label: 'Inicial', val: meterIni, set: setMeterIni,
                    foto: fotoIni, setFoto: setFotoIni },
                  { k: 'fin' as const, label: 'Final', val: meterFin, set: setMeterFin,
                    foto: fotoFin, setFoto: setFotoFin },
                ]).map((m) => (
                  <div key={m.k}>
                    <p className="text-[10px] text-gray-500">{m.label}</p>
                    <input value={m.val} onChange={(e) => m.set(e.target.value)}
                           inputMode="decimal" placeholder="0"
                           className="w-full rounded-lg border border-gray-300 px-3 py-3 text-lg font-bold" />
                    {/* La foto del contador es la prueba de los litros: el papel
                        se puede escribir de memoria, la foto no. */}
                    <label className={`mt-1 flex cursor-pointer items-center justify-center gap-1.5 rounded-lg border-2 py-2.5 text-xs font-bold ${
                      m.foto ? 'border-green-400 bg-green-50 text-green-700' : 'border-orange-300 bg-orange-50 text-orange-700'}`}>
                      {m.foto ? <Check className="h-4 w-4" /> : <Camera className="h-4 w-4" />}
                      {m.foto ? 'Foto lista' : 'Foto medidor'}
                      <input type="file" accept="image/*" capture="environment" className="hidden"
                             onChange={(e) => {
                               const f = e.target.files?.[0]
                               if (f) m.setFoto({ file: f, preview: URL.createObjectURL(f) })
                               e.target.value = ''
                             }} />
                    </label>
                    {m.foto && (
                      <div className="relative mt-1">
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <img src={m.foto.preview} alt={`medidor ${m.label}`}
                             className="h-20 w-full rounded-lg border object-cover" />
                        <button onClick={() => m.setFoto(null)}
                                className="absolute right-1 top-1 rounded-full bg-white/90 p-1 text-red-600">
                          <X className="h-3 w-3" />
                        </button>
                      </div>
                    )}
                  </div>
                ))}
              </div>

              {/* Sin las dos fotos no se guarda… salvo que diga por qué. En
                  faena una cámara mojada o sin batería no puede dejar la carga
                  sin registrar. */}
              {(!fotoIni || !fotoFin) && (
                <div className="mt-2 rounded-lg border border-amber-300 bg-amber-50 p-2">
                  <p className="text-[11px] font-semibold text-amber-900">
                    Faltan las fotos del medidor{!fotoIni && !fotoFin ? '' : !fotoIni ? ' (la inicial)' : ' (la final)'}.
                  </p>
                  <input value={sinFotoMotivo} onChange={(e) => setSinFotoMotivo(e.target.value)}
                         placeholder="Si no puedes sacarla, escribe por qué"
                         className="mt-1 w-full rounded border border-amber-300 px-2 py-2 text-xs" />
                </div>
              )}
              {litrosCalc != null ? (
                <p className="mt-2 rounded-lg bg-orange-50 p-3 text-center text-lg font-bold text-orange-800">
                  {litrosCalc.toLocaleString('es-CL')} litros
                </p>
              ) : (
                <div className="mt-2">
                  <p className="text-[10px] text-gray-500">
                    Si el medidor no sirve, escribe los litros a mano
                  </p>
                  <input value={litrosManual} onChange={(e) => setLitrosManual(e.target.value)}
                         inputMode="decimal" placeholder="Litros"
                         className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-3 text-lg font-bold" />
                </div>
              )}
            </div>

            <div>
              <label className="text-xs font-bold text-gray-700">Observación (opcional)</label>
              <input value={obs} onChange={(e) => setObs(e.target.value)}
                     className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2.5 text-sm" />
            </div>

            <p className="flex items-center gap-1.5 text-[11px] text-gray-400">
              <MapPin className="h-3.5 w-3.5" />
              {camionLabel} · Turno {turno} · {operador}
            </p>
          </div>

          <div className="border-t bg-white p-3">
            <button onClick={guardar}
                    disabled={guardando || litrosFinales == null || litrosFinales <= 0
                              || ((!fotoIni || !fotoFin) && !sinFotoMotivo.trim())}
                    className="flex w-full items-center justify-center gap-2 rounded-2xl bg-orange-600 py-4 text-base font-bold text-white disabled:opacity-40">
              {guardando ? <Spinner className="h-5 w-5" /> : <Check className="h-5 w-5" />}
              Guardar carga{litrosFinales ? ` · ${litrosFinales.toLocaleString('es-CL')} L` : ''}
            </button>
            {!online && (
              <p className="mt-1 flex items-center justify-center gap-1 text-[11px] text-amber-700">
                <RefreshCw className="h-3 w-3" /> sin señal: queda en el teléfono y sube sola
              </p>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
