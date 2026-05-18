'use client'

import { useEffect, useMemo, useState } from 'react'
import dynamic from 'next/dynamic'
import Link from 'next/link'
import {
  ArrowLeft, MapPin, Plus, Save, X, Trash2, Edit2, AlertTriangle, Search,
  RefreshCw, Power, PowerOff,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  cargarGeocercas, crearGeocerca, actualizarGeocerca, eliminarGeocerca,
  cargarContratosActivos,
  TIPO_LABELS, TIPO_COLORS_DEFAULT,
  type Geocerca, type TipoGeocerca, type ContratoOption,
} from '@/lib/services/geocercas'

const MapaGeocercas = dynamic(
  () => import('@/components/admin/mapa-geocercas').then((m) => m.MapaGeocercas),
  { ssr: false, loading: () => <div className="flex h-full items-center justify-center"><Spinner /></div> }
)

type Modo = 'idle' | 'creando' | 'editando'

interface FormState {
  nombre:      string
  tipo:        TipoGeocerca
  centro_lat:  string
  centro_lng:  string
  radio_m:     number
  contrato_id: string
  color:       string
  descripcion: string
}

const FORM_INICIAL: FormState = {
  nombre: '', tipo: 'faena_cliente',
  centro_lat: '', centro_lng: '', radio_m: 500,
  contrato_id: '', color: TIPO_COLORS_DEFAULT.faena_cliente,
  descripcion: '',
}

export default function GeocercasPage() {
  useRequireAuth()
  const [geocercas, setGeocercas]     = useState<Geocerca[]>([])
  const [contratos, setContratos]     = useState<ContratoOption[]>([])
  const [loading, setLoading]         = useState(true)
  const [error, setError]             = useState<string | null>(null)
  const [modo, setModo]               = useState<Modo>('idle')
  const [form, setForm]               = useState<FormState>(FORM_INICIAL)
  const [editandoId, setEditandoId]   = useState<string | null>(null)
  const [resaltadaId, setResaltadaId] = useState<string | null>(null)
  const [busqueda, setBusqueda]       = useState('')
  const [saving, setSaving]           = useState(false)

  const cargar = async () => {
    setLoading(true); setError(null)
    try {
      const [g, c] = await Promise.all([cargarGeocercas(), cargarContratosActivos()])
      setGeocercas(g); setContratos(c)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { cargar() }, [])

  const filtradas = useMemo(() => {
    const q = busqueda.trim().toLowerCase()
    if (!q) return geocercas
    return geocercas.filter((g) =>
      g.nombre.toLowerCase().includes(q) ||
      (g.cliente ?? '').toLowerCase().includes(q) ||
      TIPO_LABELS[g.tipo].toLowerCase().includes(q)
    )
  }, [geocercas, busqueda])

  const empezarCrear = () => {
    setForm(FORM_INICIAL); setEditandoId(null); setModo('creando'); setError(null)
  }

  const empezarEditar = (g: Geocerca) => {
    setForm({
      nombre: g.nombre,
      tipo: g.tipo,
      centro_lat: g.centro_lat.toString(),
      centro_lng: g.centro_lng.toString(),
      radio_m: g.radio_m,
      contrato_id: g.contrato_id ?? '',
      color: g.color,
      descripcion: g.descripcion ?? '',
    })
    setEditandoId(g.id); setModo('editando'); setResaltadaId(g.id); setError(null)
  }

  const cancelar = () => {
    setModo('idle'); setForm(FORM_INICIAL); setEditandoId(null); setError(null)
  }

  const onMapClick = (lat: number, lng: number) => {
    if (modo !== 'creando') return
    setForm((f) => ({ ...f, centro_lat: lat.toFixed(7), centro_lng: lng.toFixed(7) }))
  }

  const handleTipoChange = (tipo: TipoGeocerca) => {
    setForm((f) => ({
      ...f,
      tipo,
      color: TIPO_COLORS_DEFAULT[tipo],
    }))
  }

  const guardar = async () => {
    setError(null)
    const lat = parseFloat(form.centro_lat)
    const lng = parseFloat(form.centro_lng)
    if (!form.nombre.trim()) { setError('Nombre es obligatorio'); return }
    if (Number.isNaN(lat) || lat < -90 || lat > 90) { setError('Latitud inválida'); return }
    if (Number.isNaN(lng) || lng < -180 || lng > 180) { setError('Longitud inválida'); return }
    if (form.radio_m < 10 || form.radio_m > 1_000_000) { setError('Radio entre 10 y 1.000.000 m'); return }
    if (form.tipo === 'faena_cliente' && !form.contrato_id) {
      setError('Faena cliente requiere asociar un contrato'); return
    }

    setSaving(true)
    try {
      if (modo === 'editando' && editandoId) {
        await actualizarGeocerca(editandoId, {
          nombre:      form.nombre.trim(),
          tipo:        form.tipo,
          centro_lat:  lat,
          centro_lng:  lng,
          radio_m:     form.radio_m,
          contrato_id: form.contrato_id || null,
          color:       form.color,
          descripcion: form.descripcion || null,
        })
      } else {
        const nueva = await crearGeocerca({
          nombre:      form.nombre.trim(),
          tipo:        form.tipo,
          centro_lat:  lat,
          centro_lng:  lng,
          radio_m:     form.radio_m,
          contrato_id: form.contrato_id || null,
          color:       form.color,
          descripcion: form.descripcion || null,
        })
        setResaltadaId(nueva.id)
      }
      await cargar()
      cancelar()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setSaving(false)
    }
  }

  const handleEliminar = async (g: Geocerca) => {
    if (!confirm(`Eliminar geocerca "${g.nombre}"? Esto borra también su histórico de entradas/salidas.`)) return
    try {
      await eliminarGeocerca(g.id)
      await cargar()
    } catch (e) {
      setError((e as Error).message)
    }
  }

  const handleToggleActivo = async (g: Geocerca) => {
    try {
      await actualizarGeocerca(g.id, { activo: !g.activo })
      await cargar()
    } catch (e) {
      setError((e as Error).message)
    }
  }

  const centroNuevo = form.centro_lat && form.centro_lng
    ? { lat: parseFloat(form.centro_lat), lng: parseFloat(form.centro_lng) }
    : null

  return (
    <div className="space-y-4 p-4 sm:p-6">
      {/* Header */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Link href="/dashboard/admin">
            <Button variant="ghost" size="sm" className="gap-1">
              <ArrowLeft className="h-4 w-4" /> Admin
            </Button>
          </Link>
          <div>
            <h1 className="flex items-center gap-2 text-2xl font-bold">
              <MapPin className="h-6 w-6 text-blue-600" />
              Geocercas
            </h1>
            <p className="text-sm text-muted-foreground">
              Define zonas (base, faenas cliente, bodegas) para alertas y cambios de status automáticos.
            </p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button onClick={cargar} variant="outline" size="sm" className="gap-1" disabled={loading}>
            <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          </Button>
          {modo === 'idle' ? (
            <Button onClick={empezarCrear} size="sm" className="gap-1 bg-blue-600 hover:bg-blue-700">
              <Plus className="h-4 w-4" /> Nueva geocerca
            </Button>
          ) : (
            <Button onClick={cancelar} variant="outline" size="sm" className="gap-1">
              <X className="h-4 w-4" /> Cancelar
            </Button>
          )}
        </div>
      </div>

      {modo === 'creando' && (
        <Card className="border-amber-200 bg-amber-50">
          <CardContent className="flex items-center gap-2 p-3 text-sm text-amber-800">
            <MapPin className="h-4 w-4" />
            Haz <b>click en el mapa</b> para fijar el centro. Después ajusta el radio y completa el formulario.
          </CardContent>
        </Card>
      )}

      {error && (
        <Card className="border-red-200 bg-red-50">
          <CardContent className="flex items-center gap-2 p-3 text-sm text-red-700">
            <AlertTriangle className="h-4 w-4" /> {error}
          </CardContent>
        </Card>
      )}

      <div className="grid gap-4 lg:grid-cols-[280px_1fr_320px]">
        {/* Lista lateral izquierda */}
        <Card className="lg:max-h-[calc(100vh-220px)] overflow-hidden">
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Geocercas ({filtradas.length})</CardTitle>
            <div className="relative">
              <Search className="absolute left-2 top-2.5 h-4 w-4 text-gray-400" />
              <Input value={busqueda} onChange={(e) => setBusqueda(e.target.value)}
                     placeholder="Buscar..." className="pl-8 h-8" />
            </div>
          </CardHeader>
          <CardContent className="p-0 overflow-y-auto" style={{ maxHeight: 'calc(100vh - 320px)' }}>
            {loading ? (
              <div className="flex h-32 items-center justify-center"><Spinner /></div>
            ) : filtradas.length === 0 ? (
              <div className="p-3 text-center text-xs text-muted-foreground">
                Sin geocercas. Click "Nueva geocerca" arriba.
              </div>
            ) : (
              <div className="divide-y">
                {filtradas.map((g) => (
                  <div key={g.id}
                       className={`p-2 text-sm cursor-pointer transition-colors ${
                         resaltadaId === g.id ? 'bg-blue-50' : 'hover:bg-gray-50'
                       } ${!g.activo ? 'opacity-50' : ''}`}
                       onClick={() => setResaltadaId(g.id)}>
                    <div className="flex items-start gap-2">
                      <div className="mt-1 h-3 w-3 shrink-0 rounded-full border"
                           style={{ background: g.color || TIPO_COLORS_DEFAULT[g.tipo] }} />
                      <div className="flex-1 min-w-0">
                        <div className="font-medium truncate">{g.nombre}</div>
                        <div className="text-[10px] text-gray-500">{TIPO_LABELS[g.tipo]}</div>
                        {g.cliente && <div className="text-[10px] text-gray-500 truncate">{g.cliente}</div>}
                        <div className="text-[10px] text-gray-400">{g.radio_m}m</div>
                      </div>
                      <div className="flex flex-col gap-0.5">
                        <button onClick={(e) => { e.stopPropagation(); empezarEditar(g) }}
                                title="Editar" className="text-blue-600 hover:bg-blue-100 rounded p-1">
                          <Edit2 className="h-3 w-3" />
                        </button>
                        <button onClick={(e) => { e.stopPropagation(); handleToggleActivo(g) }}
                                title={g.activo ? 'Desactivar' : 'Activar'}
                                className="text-gray-500 hover:bg-gray-100 rounded p-1">
                          {g.activo ? <Power className="h-3 w-3" /> : <PowerOff className="h-3 w-3" />}
                        </button>
                        <button onClick={(e) => { e.stopPropagation(); handleEliminar(g) }}
                                title="Eliminar" className="text-red-600 hover:bg-red-100 rounded p-1">
                          <Trash2 className="h-3 w-3" />
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Mapa central */}
        <Card>
          <CardContent className="p-0">
            <div style={{ height: 'calc(100vh - 220px)', minHeight: 500 }}>
              <MapaGeocercas
                geocercas={geocercas}
                modoCrear={modo === 'creando'}
                centroNuevo={centroNuevo}
                radioNuevo={form.radio_m}
                onMapClick={onMapClick}
                geocercaResaltadaId={resaltadaId}
              />
            </div>
          </CardContent>
        </Card>

        {/* Formulario lateral derecho */}
        {modo !== 'idle' && (
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm">
                {modo === 'creando' ? 'Nueva geocerca' : 'Editar geocerca'}
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div>
                <label className="text-xs font-medium text-gray-700">Nombre *</label>
                <Input value={form.nombre} onChange={(e) => setForm({ ...form, nombre: e.target.value })}
                       placeholder="ej. Faena Spence Norte" />
              </div>

              <div>
                <label className="text-xs font-medium text-gray-700">Tipo *</label>
                <select
                  value={form.tipo}
                  onChange={(e) => handleTipoChange(e.target.value as TipoGeocerca)}
                  className="w-full h-9 rounded-md border border-gray-200 bg-white px-2 text-sm">
                  {Object.entries(TIPO_LABELS).map(([k, label]) => (
                    <option key={k} value={k}>{label}</option>
                  ))}
                </select>
              </div>

              {form.tipo === 'faena_cliente' && (
                <div>
                  <label className="text-xs font-medium text-gray-700">Contrato *</label>
                  <select
                    value={form.contrato_id}
                    onChange={(e) => setForm({ ...form, contrato_id: e.target.value })}
                    className="w-full h-9 rounded-md border border-gray-200 bg-white px-2 text-sm">
                    <option value="">— seleccionar —</option>
                    {contratos.map((c) => (
                      <option key={c.id} value={c.id}>{c.codigo} · {c.cliente}</option>
                    ))}
                  </select>
                  <p className="mt-1 text-[10px] text-gray-500">
                    El activo arrendado con este contrato hereda esta geocerca como esperada.
                  </p>
                </div>
              )}

              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="text-xs font-medium text-gray-700">Latitud *</label>
                  <Input value={form.centro_lat} onChange={(e) => setForm({ ...form, centro_lat: e.target.value })}
                         placeholder="-22.45" />
                </div>
                <div>
                  <label className="text-xs font-medium text-gray-700">Longitud *</label>
                  <Input value={form.centro_lng} onChange={(e) => setForm({ ...form, centro_lng: e.target.value })}
                         placeholder="-68.93" />
                </div>
              </div>
              {modo === 'creando' && (
                <p className="text-[10px] text-gray-500">
                  Tip: click en el mapa rellena ambos. O usa Google Maps → click derecho → copiar coords.
                </p>
              )}

              <div>
                <label className="text-xs font-medium text-gray-700">
                  Radio: <b>{form.radio_m.toLocaleString('es-CL')} m</b> ({(form.radio_m / 1000).toFixed(2)} km)
                </label>
                <input
                  type="range"
                  min={50} max={10000} step={50}
                  value={form.radio_m}
                  onChange={(e) => setForm({ ...form, radio_m: Number(e.target.value) })}
                  className="w-full"
                />
                <div className="flex justify-between text-[10px] text-gray-400">
                  <span>50m</span>
                  <span>10km</span>
                </div>
                <Input
                  type="number" min={10} max={1000000}
                  value={form.radio_m}
                  onChange={(e) => setForm({ ...form, radio_m: Number(e.target.value) })}
                  className="mt-1 h-8 text-xs" />
              </div>

              <div>
                <label className="text-xs font-medium text-gray-700">Color</label>
                <div className="flex items-center gap-2">
                  <input type="color" value={form.color}
                         onChange={(e) => setForm({ ...form, color: e.target.value })}
                         className="h-8 w-12 rounded border" />
                  <Input value={form.color} onChange={(e) => setForm({ ...form, color: e.target.value })}
                         className="flex-1 h-8 text-xs font-mono" />
                </div>
              </div>

              <div>
                <label className="text-xs font-medium text-gray-700">Descripción</label>
                <textarea
                  value={form.descripcion}
                  onChange={(e) => setForm({ ...form, descripcion: e.target.value })}
                  className="w-full rounded border border-gray-200 px-2 py-1 text-sm" rows={2}
                  placeholder="Opcional" />
              </div>

              <div className="flex gap-2 pt-2">
                <Button variant="outline" size="sm" onClick={cancelar} className="flex-1">
                  Cancelar
                </Button>
                <Button size="sm" onClick={guardar} disabled={saving}
                        className="flex-1 bg-green-600 hover:bg-green-700">
                  {saving ? <Save className="h-4 w-4 animate-pulse" /> : <Save className="h-4 w-4" />}
                  Guardar
                </Button>
              </div>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  )
}
