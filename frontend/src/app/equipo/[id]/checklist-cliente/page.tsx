'use client'

import { useEffect, useMemo, useState } from 'react'
import { useParams } from 'next/navigation'
import {
  ClipboardCheck, CheckCircle2, XCircle, MinusCircle, Camera, MapPin,
  AlertTriangle, Loader2, Truck,
} from 'lucide-react'
import { SignaturePad } from '@/components/ui/signature-pad'
import {
  getChecklistCliente, guardarChecklistCliente, subirEvidenciaChecklistCliente,
  type ChecklistClienteActivo, type ChecklistClienteItemTpl,
} from '@/lib/services/checklist-cliente'

type Res = 'ok' | 'no_ok' | 'na'

export default function ChecklistClientePublicoPage() {
  const { id } = useParams<{ id: string }>()
  const [loading, setLoading] = useState(true)
  const [activo, setActivo] = useState<ChecklistClienteActivo | null>(null)
  const [items, setItems] = useState<ChecklistClienteItemTpl[]>([])
  const [err, setErr] = useState<string | null>(null)
  const [enviado, setEnviado] = useState<null | { tiene_novedad: boolean; items_no_ok: number }>(null)
  const [saving, setSaving] = useState(false)

  // operador
  const [nombre, setNombre] = useState('')
  const [rut, setRut] = useState('')
  const [empresa, setEmpresa] = useState('')
  const [telefono, setTelefono] = useState('')
  const [horometro, setHorometro] = useState('')
  const [kilometraje, setKilometraje] = useState('')
  const [ubicacion, setUbicacion] = useState('')
  const [coords, setCoords] = useState<{ lat: number; lng: number } | null>(null)
  const [obs, setObs] = useState('')

  const [resultados, setResultados] = useState<Record<number, { resultado: Res; observacion: string; foto?: File }>>({})
  const [firma, setFirma] = useState<string | null>(null)

  useEffect(() => {
    let alive = true
    ;(async () => {
      const { data, error } = await getChecklistCliente(id)
      if (!alive) return
      if (error || !data || data.error) { setErr(data?.error || error?.message || 'No se pudo cargar el equipo'); setLoading(false); return }
      setActivo(data.activo ?? null)
      setItems(data.items ?? [])
      setLoading(false)
    })()
    return () => { alive = false }
  }, [id])

  const it = (orden: number) => resultados[orden] ?? { resultado: 'na' as Res, observacion: '' }
  const setIt = (orden: number, patch: Partial<{ resultado: Res; observacion: string; foto?: File }>) =>
    setResultados((s) => ({ ...s, [orden]: { ...it(orden), ...patch } }))

  const pendObl = useMemo(
    () => items.filter((i) => i.obligatorio && it(i.orden).resultado === 'na').length,
    [items, resultados],
  )

  const capturarGPS = () => {
    if (!navigator.geolocation) return
    navigator.geolocation.getCurrentPosition(
      (p) => setCoords({ lat: p.coords.latitude, lng: p.coords.longitude }),
      () => setErr('No se pudo obtener ubicación GPS'),
      { enableHighAccuracy: true, timeout: 8000 },
    )
  }

  const enviar = async () => {
    setErr(null)
    if (!nombre.trim() || !rut.trim()) { setErr('Ingresa tu nombre y RUT.'); return }
    if (pendObl > 0) { setErr(`Faltan ${pendObl} ítem(s) obligatorio(s) por marcar.`); return }
    if (!firma) { setErr('Falta la firma.'); return }
    setSaving(true)
    try {
      // subir firma
      const { data: firmaUrl } = await subirEvidenciaChecklistCliente(id, 'firma', firma)
      // subir fotos de items con novedad
      const itemsPayload = []
      for (const i of items) {
        const st = it(i.orden)
        let fotoUrl: string | null = null
        if (st.foto) {
          const { data: u } = await subirEvidenciaChecklistCliente(id, `item${i.orden}`, st.foto)
          fotoUrl = u
        }
        itemsPayload.push({
          orden: i.orden, categoria: i.categoria, descripcion: i.descripcion,
          resultado: st.resultado, observacion: st.observacion || null, foto_url: fotoUrl,
        })
      }
      const { data, error } = await guardarChecklistCliente({
        activo_id: id, operador_nombre: nombre, operador_rut: rut, operador_empresa: empresa,
        telefono, horometro, kilometraje, ubicacion,
        lat: coords?.lat ?? '', lng: coords?.lng ?? '',
        firma_url: firmaUrl, observaciones: obs, items: itemsPayload,
      })
      if (error) throw error
      setEnviado({ tiene_novedad: !!(data as any)?.tiene_novedad, items_no_ok: (data as any)?.items_no_ok ?? 0 })
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : 'Error al enviar')
    } finally { setSaving(false) }
  }

  if (loading) return <Centro><Loader2 className="h-8 w-8 animate-spin text-gray-400" /></Centro>
  if (err && !activo) return <Centro><div className="text-center"><AlertTriangle className="h-10 w-10 text-amber-500 mx-auto mb-2" /><p>{err}</p></div></Centro>

  if (enviado) {
    return (
      <Centro>
        <div className="text-center max-w-sm">
          <CheckCircle2 className="h-14 w-14 text-emerald-500 mx-auto mb-3" />
          <h1 className="text-xl font-bold">¡Checklist enviado!</h1>
          <p className="text-sm text-gray-600 mt-1">Gracias. El estado del equipo quedó registrado.</p>
          {enviado.tiene_novedad && (
            <div className="mt-4 rounded-lg bg-amber-50 border border-amber-200 p-3 text-sm text-amber-800">
              Reportaste {enviado.items_no_ok} novedad(es). El taller será notificado para revisarlas.
            </div>
          )}
        </div>
      </Centro>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50 pb-24">
      <div className="bg-white border-b p-4 sticky top-0 z-10">
        <div className="flex items-center gap-2">
          <Truck className="h-6 w-6 text-blue-600" />
          <div>
            <h1 className="font-bold leading-tight">{activo?.patente ?? activo?.codigo}</h1>
            <p className="text-xs text-gray-500">{activo?.nombre} · {activo?.cliente ?? 'Cliente'}</p>
          </div>
        </div>
        <p className="text-xs text-gray-500 mt-2">Checklist semanal de estado del equipo</p>
      </div>

      <div className="p-4 space-y-4 max-w-xl mx-auto">
        {/* Identificación */}
        <Seccion titulo="Tus datos">
          <Inp label="Nombre*" value={nombre} onChange={setNombre} />
          <Inp label="RUT*" value={rut} onChange={setRut} />
          <Inp label="Empresa" value={empresa} onChange={setEmpresa} />
          <Inp label="Teléfono" value={telefono} onChange={setTelefono} />
          <div className="grid grid-cols-2 gap-2">
            <Inp label="Horómetro" value={horometro} onChange={setHorometro} type="number" />
            <Inp label="Kilometraje" value={kilometraje} onChange={setKilometraje} type="number" />
          </div>
          <Inp label="Ubicación / faena" value={ubicacion} onChange={setUbicacion} />
          <button onClick={capturarGPS} type="button"
            className="text-sm flex items-center gap-1 text-blue-600">
            <MapPin className="h-4 w-4" /> {coords ? 'Ubicación GPS capturada ✓' : 'Capturar ubicación GPS'}
          </button>
        </Seccion>

        {/* Items */}
        <Seccion titulo="Estado del equipo">
          {items.map((i) => {
            const st = it(i.orden)
            return (
              <div key={i.orden} className="border-b last:border-0 py-2">
                <div className="flex items-start justify-between gap-2">
                  <span className="text-sm">{i.descripcion}{i.obligatorio && <span className="text-red-500"> *</span>}</span>
                  <div className="flex gap-1 shrink-0">
                    <Tg active={st.resultado === 'ok'} c="green" onClick={() => setIt(i.orden, { resultado: 'ok' })}><CheckCircle2 className="h-5 w-5" /></Tg>
                    <Tg active={st.resultado === 'no_ok'} c="red" onClick={() => setIt(i.orden, { resultado: 'no_ok' })}><XCircle className="h-5 w-5" /></Tg>
                    <Tg active={st.resultado === 'na'} c="gray" onClick={() => setIt(i.orden, { resultado: 'na' })}><MinusCircle className="h-5 w-5" /></Tg>
                  </div>
                </div>
                {st.resultado === 'no_ok' && (
                  <div className="mt-2 space-y-2">
                    <input className="w-full rounded border px-2 py-1.5 text-sm" placeholder="¿Qué observaste?"
                      value={st.observacion} onChange={(e) => setIt(i.orden, { observacion: e.target.value })} />
                    <label className="flex items-center gap-2 text-sm text-blue-600">
                      <Camera className="h-4 w-4" /> {st.foto ? 'Foto adjunta ✓' : 'Adjuntar foto'}
                      <input type="file" accept="image/*" capture="environment" className="hidden"
                        onChange={(e) => setIt(i.orden, { foto: e.target.files?.[0] })} />
                    </label>
                  </div>
                )}
              </div>
            )
          })}
        </Seccion>

        <Seccion titulo="Observaciones y firma">
          <textarea className="w-full rounded border px-2 py-1.5 text-sm" rows={2} placeholder="Comentarios generales (opcional)"
            value={obs} onChange={(e) => setObs(e.target.value)} />
          <SignaturePad label="Firma del operador" onCapture={setFirma} />
        </Seccion>

        {err && <div className="flex items-center gap-2 text-sm text-red-600"><AlertTriangle className="h-4 w-4" />{err}</div>}
      </div>

      <div className="fixed bottom-0 inset-x-0 bg-white border-t p-3">
        <button onClick={enviar} disabled={saving}
          className="w-full max-w-xl mx-auto block rounded-lg bg-blue-600 text-white py-3 font-medium disabled:opacity-60 flex items-center justify-center gap-2">
          {saving ? <Loader2 className="h-5 w-5 animate-spin" /> : <ClipboardCheck className="h-5 w-5" />}
          Enviar checklist
        </button>
      </div>
    </div>
  )
}

function Centro({ children }: { children: React.ReactNode }) {
  return <div className="min-h-screen flex items-center justify-center p-6 bg-gray-50">{children}</div>
}
function Seccion({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <div className="bg-white rounded-xl border p-4 space-y-3">
      <h2 className="font-semibold text-sm text-gray-700">{titulo}</h2>
      {children}
    </div>
  )
}
function Inp({ label, value, onChange, type = 'text' }: { label: string; value: string; onChange: (v: string) => void; type?: string }) {
  return (
    <label className="block text-sm">
      <span className="text-gray-600">{label}</span>
      <input type={type} value={value} onChange={(e) => onChange(e.target.value)}
        className="mt-0.5 w-full rounded border px-2 py-1.5" />
    </label>
  )
}
function Tg({ active, c, onClick, children }: { active: boolean; c: 'green' | 'red' | 'gray'; onClick: () => void; children: React.ReactNode }) {
  const colors = {
    green: active ? 'bg-green-600 text-white' : 'text-green-600 border-green-300',
    red: active ? 'bg-red-600 text-white' : 'text-red-600 border-red-300',
    gray: active ? 'bg-gray-400 text-white' : 'text-gray-400 border-gray-300',
  }[c]
  return <button type="button" onClick={onClick} className={`rounded border p-1.5 ${colors}`}>{children}</button>
}
