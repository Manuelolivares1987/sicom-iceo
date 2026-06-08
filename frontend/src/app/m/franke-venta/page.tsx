'use client'

import { useEffect, useMemo, useState } from 'react'
import {
  Fuel, Truck, Wifi, WifiOff, RefreshCw, CheckCircle2, AlertTriangle, Camera, MapPin,
  Loader2, Clock,
} from 'lucide-react'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useAuth } from '@/contexts/auth-context'
import { getCamionesFranke } from '@/lib/services/combustible-franke'
import {
  smartRegistrarVentaFranke, syncFrankePending, getFrankeCounters, getFrankeVentasLocales,
  cacheCamionesFranke, getCamionesCacheFranke, type VentaFrankeInput,
} from '@/lib/offline/franke-ventas-sync'

export default function FrankeVentaPage() {
  const { perfil } = useAuth()
  const [online, setOnline] = useState(true)
  const [camiones, setCamiones] = useState<any[]>([])
  const [counters, setCounters] = useState({ pendientes: 0, errores: 0, sincronizadas: 0 })
  const [locales, setLocales] = useState<any[]>([])
  const [syncing, setSyncing] = useState(false)
  const [enviando, setEnviando] = useState(false)
  const [msg, setMsg] = useState<{ t: 'ok' | 'off' | 'err'; m: string } | null>(null)

  // form
  const [camion, setCamion] = useState('')
  const [cliente, setCliente] = useState('')
  const [equipoCod, setEquipoCod] = useState('')
  const [equipoTipo, setEquipoTipo] = useState('')
  const [litros, setLitros] = useState('')
  const [precio, setPrecio] = useState('')
  const [recNombre, setRecNombre] = useState('')
  const [recRut, setRecRut] = useState('')
  const [coords, setCoords] = useState<{ lat: number; lng: number } | null>(null)
  const [firma, setFirma] = useState<Blob | null>(null)
  const [fPat, setFPat] = useState<File | null>(null)
  const [fMedI, setFMedI] = useState<File | null>(null)
  const [fMedF, setFMedF] = useState<File | null>(null)

  const refresh = async () => {
    setCounters(await getFrankeCounters())
    setLocales(await getFrankeVentasLocales())
  }

  useEffect(() => {
    setOnline(navigator.onLine)
    const on = () => { setOnline(true); syncFrankePending().then(refresh) }
    const off = () => setOnline(false)
    window.addEventListener('online', on)
    window.addEventListener('offline', off)
    return () => { window.removeEventListener('online', on); window.removeEventListener('offline', off) }
  }, [])

  useEffect(() => {
    ;(async () => {
      if (navigator.onLine) {
        const { data } = await getCamionesFranke()
        if (data?.length) { setCamiones(data); await cacheCamionesFranke(data) }
        else setCamiones(await getCamionesCacheFranke())
        const c = await getFrankeCounters()
        if (c.pendientes > 0 || c.errores > 0) await syncFrankePending()
      } else {
        setCamiones(await getCamionesCacheFranke())
      }
      await refresh()
    })()
  }, [])

  const capturarGPS = () => navigator.geolocation?.getCurrentPosition(
    (p) => setCoords({ lat: p.coords.latitude, lng: p.coords.longitude }), () => {}, { enableHighAccuracy: true, timeout: 8000 })

  const total = useMemo(() => (litros && precio ? Number(litros) * Number(precio) : 0), [litros, precio])

  const fileToBlob = (f: File | null) => f as Blob | null

  const enviar = async () => {
    setMsg(null)
    if (!camion || !cliente.trim() || !litros) { setMsg({ t: 'err', m: 'Camión, cliente y litros son obligatorios.' }); return }
    setEnviando(true)
    try {
      const cam = camiones.find((c) => c.id === camion)
      const input: VentaFrankeInput = {
        estanque_movil_id: camion, cliente_nombre: cliente.trim(), litros: Number(litros),
        equipo_codigo: equipoCod || null, equipo_tipo: equipoTipo || null,
        precio_clp_lt: precio ? Number(precio) : null,
        operador_nombre: perfil?.nombre_completo ?? null, operador_rut: perfil?.rut ?? null,
        nombre_receptor: recNombre || null, rut_receptor: recRut || null,
        lat: coords?.lat ?? null, lng: coords?.lng ?? null,
        camionLabel: cam?.patente ?? cam?.codigo ?? '',
        firma, foto_patente: fileToBlob(fPat), foto_medidor_inicial: fileToBlob(fMedI), foto_medidor_final: fileToBlob(fMedF),
      }
      const r = await smartRegistrarVentaFranke(input)
      setMsg({ t: r.mode === 'online' ? 'ok' : 'off', m: r.message })
      setCliente(''); setEquipoCod(''); setEquipoTipo(''); setLitros(''); setPrecio(''); setRecNombre(''); setRecRut('')
      setFirma(null); setFPat(null); setFMedI(null); setFMedF(null)
      await refresh()
    } catch (e) { setMsg({ t: 'err', m: e instanceof Error ? e.message : 'Error' }) } finally { setEnviando(false) }
  }

  const sincronizar = async () => { setSyncing(true); await syncFrankePending(); await refresh(); setSyncing(false) }

  return (
    <div className="min-h-screen bg-gray-50 pb-28">
      {/* Header + estado conexion */}
      <div className="bg-white border-b p-3 sticky top-0 z-10 space-y-2">
        <div className="flex items-center justify-between">
          <h1 className="font-bold flex items-center gap-2"><Fuel className="h-5 w-5 text-orange-600" /> Venta Franke</h1>
          <span className={`text-xs flex items-center gap-1 px-2 py-1 rounded-full ${online ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}`}>
            {online ? <Wifi className="h-3.5 w-3.5" /> : <WifiOff className="h-3.5 w-3.5" />} {online ? 'Con conexión' : 'Sin conexión'}
          </span>
        </div>
        {(counters.pendientes > 0 || counters.errores > 0) && (
          <div className="flex items-center justify-between text-xs">
            <span className="flex items-center gap-2">
              {counters.pendientes > 0 && <span className="flex items-center gap-1 text-amber-700"><Clock className="h-3.5 w-3.5" />{counters.pendientes} por sincronizar</span>}
              {counters.errores > 0 && <span className="text-red-600">{counters.errores} con error</span>}
            </span>
            <button onClick={sincronizar} disabled={!online || syncing} className="flex items-center gap-1 text-blue-600 disabled:opacity-50">
              <RefreshCw className={`h-3.5 w-3.5 ${syncing ? 'animate-spin' : ''}`} /> Sincronizar
            </button>
          </div>
        )}
      </div>

      <div className="p-3 space-y-3 max-w-xl mx-auto">
        <Box>
          <Sel label="Camión*" value={camion} onChange={setCamion} options={camiones.map((c) => [c.id, `${c.patente ?? c.codigo} (${Number(c.stock_teorico_lt).toLocaleString('es-CL')} L)`])} />
          <In label="Cliente*" value={cliente} onChange={setCliente} />
          <div className="grid grid-cols-2 gap-2">
            <In label="Código equipo" value={equipoCod} onChange={setEquipoCod} />
            <In label="Tipo equipo" value={equipoTipo} onChange={setEquipoTipo} />
          </div>
          <div className="grid grid-cols-2 gap-2">
            <In label="Litros*" value={litros} onChange={setLitros} type="number" />
            <In label="Precio CLP/L" value={precio} onChange={setPrecio} type="number" />
          </div>
          {total > 0 && <div className="text-sm text-right font-semibold">Total: ${total.toLocaleString('es-CL')}</div>}
        </Box>

        <Box>
          <div className="grid grid-cols-2 gap-2">
            <In label="Receptor (nombre)" value={recNombre} onChange={setRecNombre} />
            <In label="Receptor (RUT)" value={recRut} onChange={setRecRut} />
          </div>
          <div className="grid grid-cols-3 gap-2">
            <FileIn label="Foto patente" file={fPat} onChange={setFPat} />
            <FileIn label="Medidor ini." file={fMedI} onChange={setFMedI} />
            <FileIn label="Medidor fin." file={fMedF} onChange={setFMedF} />
          </div>
          <button onClick={capturarGPS} type="button" className="text-sm flex items-center gap-1 text-blue-600">
            <MapPin className="h-4 w-4" /> {coords ? 'GPS capturado ✓' : 'Capturar GPS'}
          </button>
          <SignaturePad label="Firma del receptor" onCapture={async (dataUrl) => setFirma(await (await fetch(dataUrl)).blob())} />
        </Box>

        {msg && (
          <div className={`flex items-center gap-2 text-sm rounded-lg p-2 ${msg.t === 'ok' ? 'bg-green-50 text-green-700' : msg.t === 'off' ? 'bg-amber-50 text-amber-800' : 'bg-red-50 text-red-700'}`}>
            {msg.t === 'err' ? <AlertTriangle className="h-4 w-4" /> : <CheckCircle2 className="h-4 w-4" />} {msg.m}
          </div>
        )}

        {/* Ventas locales recientes */}
        {locales.length > 0 && (
          <Box>
            <div className="text-xs font-semibold text-gray-600 mb-1">Ventas en este teléfono</div>
            {locales.slice(0, 8).map((v) => (
              <div key={v.local_id} className="flex items-center justify-between text-xs border-b last:border-0 py-1">
                <span>{v.resumen.cliente} · {Number(v.resumen.litros).toLocaleString('es-CL')} L · {v.resumen.camion}</span>
                <span className={v.sync_status === 'synced' ? 'text-green-600' : v.sync_status === 'error' ? 'text-red-600' : 'text-amber-600'}>
                  {v.sync_status === 'synced' ? '✓ sincr.' : v.sync_status === 'error' ? '✗ error' : '⏲ pendiente'}
                </span>
              </div>
            ))}
          </Box>
        )}
      </div>

      <div className="fixed bottom-0 inset-x-0 bg-white border-t p-3">
        <button onClick={enviar} disabled={enviando}
          className="w-full max-w-xl mx-auto block rounded-lg bg-orange-600 text-white py-3 font-medium disabled:opacity-60 flex items-center justify-center gap-2">
          {enviando ? <Loader2 className="h-5 w-5 animate-spin" /> : <Truck className="h-5 w-5" />} Registrar venta
        </button>
      </div>
    </div>
  )
}

function Box({ children }: { children: React.ReactNode }) {
  return <div className="bg-white rounded-xl border p-3 space-y-2">{children}</div>
}
function In({ label, value, onChange, type = 'text' }: { label: string; value: string; onChange: (v: string) => void; type?: string }) {
  return <label className="block text-sm"><span className="text-gray-600">{label}</span>
    <input type={type} value={value} onChange={(e) => onChange(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1.5" /></label>
}
function Sel({ label, value, onChange, options }: { label: string; value: string; onChange: (v: string) => void; options: [string, string][] }) {
  return <label className="block text-sm"><span className="text-gray-600">{label}</span>
    <select value={value} onChange={(e) => onChange(e.target.value)} className="mt-0.5 w-full rounded border px-2 py-1.5">
      <option value="">—</option>{options.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
    </select></label>
}
function FileIn({ label, file, onChange }: { label: string; file: File | null; onChange: (f: File | null) => void }) {
  return <label className="text-xs border rounded px-2 py-1.5 cursor-pointer text-blue-600 flex items-center gap-1 justify-center">
    <Camera className="h-3.5 w-3.5" /> {file ? '✓' : label}
    <input type="file" accept="image/*" capture="environment" className="hidden" onChange={(e) => onChange(e.target.files?.[0] ?? null)} />
  </label>
}
