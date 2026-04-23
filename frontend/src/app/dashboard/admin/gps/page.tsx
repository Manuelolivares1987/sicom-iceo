'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import {
  Satellite, Plus, Trash2, Save, AlertTriangle, Truck, Key,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { usePermissions } from '@/hooks/use-permissions'
import { supabase } from '@/lib/supabase'

type Proveedor = {
  id: string
  nombre: string
  activo: boolean
  api_base_url: string | null
  api_tipo_auth: string | null
  // NO exponemos api_token ni webhook_secret por seguridad.
}

type MapeoActivo = {
  id: string
  activo_id: string
  proveedor_id: string
  gps_device_id: string
  gps_device_name: string | null
  imei: string | null
  activo: boolean
  patente?: string | null
}

export default function GPSConfigPage() {
  useRequireAuth()
  const { canEdit } = usePermissions()
  const puedeEditar = canEdit('admin')

  const [proveedores, setProveedores] = useState<Proveedor[]>([])
  const [mapeos, setMapeos] = useState<MapeoActivo[]>([])
  const [activos, setActivos] = useState<Array<{ id: string; patente: string | null; codigo: string | null; nombre: string | null }>>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [errorMsg, setErrorMsg] = useState<string | null>(null)

  // Form de nuevo proveedor
  const [nuevoNombre, setNuevoNombre] = useState('')
  const [nuevaUrl, setNuevaUrl] = useState('')
  const [nuevoToken, setNuevoToken] = useState('')
  const [nuevoSecret, setNuevoSecret] = useState('')

  // Form de nuevo mapeo
  const [mapProvId, setMapProvId] = useState('')
  const [mapActId, setMapActId] = useState('')
  const [mapDeviceId, setMapDeviceId] = useState('')
  const [mapDeviceName, setMapDeviceName] = useState('')
  const [mapImei, setMapImei] = useState('')

  const cargar = async () => {
    setLoading(true)
    setErrorMsg(null)
    try {
      const [provRes, mapRes, actRes] = await Promise.all([
        supabase.from('config_gps_proveedor')
          .select('id, nombre, activo, api_base_url, api_tipo_auth')
          .order('nombre'),
        supabase.from('gps_activo_mapeo')
          .select('id, activo_id, proveedor_id, gps_device_id, gps_device_name, imei, activo, activo_rel:activos(patente)')
          .order('created_at', { ascending: false }),
        supabase.from('activos')
          .select('id, patente, codigo, nombre')
          .neq('estado', 'dado_baja')
          .order('patente'),
      ])
      if (provRes.error) throw provRes.error
      if (mapRes.error) throw mapRes.error
      if (actRes.error) throw actRes.error
      setProveedores((provRes.data ?? []) as Proveedor[])
      setMapeos(
        (mapRes.data ?? []).map((m: any) => ({
          id: m.id,
          activo_id: m.activo_id,
          proveedor_id: m.proveedor_id,
          gps_device_id: m.gps_device_id,
          gps_device_name: m.gps_device_name,
          imei: m.imei,
          activo: m.activo,
          patente: m.activo_rel?.patente ?? null,
        })),
      )
      setActivos(actRes.data ?? [])
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Error al cargar')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { cargar() }, [])

  const crearProveedor = async () => {
    if (!nuevoNombre || !nuevaUrl) {
      setErrorMsg('Nombre y URL de la API son obligatorios')
      return
    }
    setSaving(true)
    setErrorMsg(null)
    try {
      const { error } = await supabase.from('config_gps_proveedor').insert({
        nombre: nuevoNombre,
        api_base_url: nuevaUrl,
        api_token: nuevoToken || null,
        webhook_secret: nuevoSecret || null,
        api_tipo_auth: 'token',
        activo: true,
      })
      if (error) throw error
      setNuevoNombre(''); setNuevaUrl(''); setNuevoToken(''); setNuevoSecret('')
      await cargar()
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Error')
    } finally {
      setSaving(false)
    }
  }

  const toggleProveedor = async (id: string, activo: boolean) => {
    await supabase.from('config_gps_proveedor').update({ activo: !activo }).eq('id', id)
    await cargar()
  }

  const eliminarProveedor = async (id: string) => {
    if (!confirm('Eliminar proveedor y todos sus mapeos?')) return
    await supabase.from('gps_activo_mapeo').delete().eq('proveedor_id', id)
    await supabase.from('config_gps_proveedor').delete().eq('id', id)
    await cargar()
  }

  const crearMapeo = async () => {
    if (!mapProvId || !mapActId || !mapDeviceId) {
      setErrorMsg('Proveedor, activo y GPS device ID son obligatorios')
      return
    }
    setSaving(true)
    setErrorMsg(null)
    try {
      const { error } = await supabase.from('gps_activo_mapeo').insert({
        proveedor_id: mapProvId,
        activo_id: mapActId,
        gps_device_id: mapDeviceId,
        gps_device_name: mapDeviceName || null,
        imei: mapImei || null,
      })
      if (error) throw error
      setMapActId(''); setMapDeviceId(''); setMapDeviceName(''); setMapImei('')
      await cargar()
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Error')
    } finally {
      setSaving(false)
    }
  }

  const eliminarMapeo = async (id: string) => {
    if (!confirm('Eliminar mapeo?')) return
    await supabase.from('gps_activo_mapeo').delete().eq('id', id)
    await cargar()
  }

  if (!puedeEditar) {
    return (
      <Card>
        <CardContent className="py-10 text-center space-y-2">
          <AlertTriangle className="h-10 w-10 text-amber-500 mx-auto" />
          <h3 className="text-lg font-semibold">Sin permisos</h3>
          <p className="text-sm text-gray-500">Solo el administrador puede configurar GPS.</p>
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="space-y-6">
      <div className="rounded-2xl bg-gradient-to-r from-sky-600 to-blue-700 p-6 text-white shadow-lg">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <Satellite className="h-6 w-6" />
          Configuración GPS
        </h1>
        <p className="text-sm text-white/80 mt-1">
          Proveedores GPS y mapeo de dispositivos a equipos.
        </p>
      </div>

      {/* Aviso de seguridad */}
      <div className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900 flex gap-2">
        <Key className="h-5 w-5 shrink-0" />
        <div>
          <strong>Seguridad de la clave API:</strong> no la pegues en Slack, chat ni en el código.
          Cárgala solo desde este formulario. Si la clave se expone, rótala en la plataforma del proveedor
          y vuelve a cargarla aquí.
        </div>
      </div>

      {errorMsg && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{errorMsg}</div>
      )}

      {loading && <div className="flex justify-center py-6"><Spinner className="h-8 w-8" /></div>}

      {!loading && (
        <>
          {/* ─── Proveedores ─── */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Proveedores GPS ({proveedores.length})</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {proveedores.length === 0 ? (
                <p className="text-sm text-gray-400">Sin proveedores registrados todavía.</p>
              ) : (
                <div className="divide-y rounded border">
                  {proveedores.map((p) => (
                    <div key={p.id} className="p-2 flex items-center justify-between gap-2 text-sm">
                      <div className="flex-1 min-w-0">
                        <div className="font-semibold">{p.nombre}</div>
                        <div className="text-xs text-gray-500 truncate">{p.api_base_url ?? '—'}</div>
                      </div>
                      <Badge className={p.activo ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500'}>
                        {p.activo ? 'Activo' : 'Inactivo'}
                      </Badge>
                      <Button size="sm" variant="ghost" onClick={() => toggleProveedor(p.id, p.activo)}>
                        {p.activo ? 'Desactivar' : 'Activar'}
                      </Button>
                      <Button size="sm" variant="ghost" onClick={() => eliminarProveedor(p.id)}>
                        <Trash2 className="h-4 w-4 text-red-600" />
                      </Button>
                    </div>
                  ))}
                </div>
              )}

              <details className="rounded border border-dashed p-3">
                <summary className="cursor-pointer text-sm font-medium text-blue-600">
                  + Agregar nuevo proveedor
                </summary>
                <div className="mt-3 space-y-2">
                  <Input placeholder="Nombre (ej. Pillado Wialon)" value={nuevoNombre} onChange={(e) => setNuevoNombre(e.target.value)} />
                  <Input placeholder="API Base URL (ej. https://hst-api.wialon.com/...)" value={nuevaUrl} onChange={(e) => setNuevaUrl(e.target.value)} />
                  <Input
                    type="password"
                    placeholder="API Token / API Key (pégala aquí)"
                    value={nuevoToken}
                    onChange={(e) => setNuevoToken(e.target.value)}
                  />
                  <Input
                    type="password"
                    placeholder="Webhook secret (opcional)"
                    value={nuevoSecret}
                    onChange={(e) => setNuevoSecret(e.target.value)}
                  />
                  <Button variant="primary" size="sm" onClick={crearProveedor} loading={saving}>
                    <Save className="h-4 w-4" />
                    Guardar proveedor
                  </Button>
                  <p className="text-[11px] text-gray-500">
                    El token se guarda en DB. Se recomienda usar Supabase Vault para encriptarlo;
                    por ahora se almacena como string en config_gps_proveedor.api_token.
                  </p>
                </div>
              </details>
            </CardContent>
          </Card>

          {/* ─── Mapeos activo ↔ GPS ─── */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base flex items-center gap-2">
                <Truck className="h-5 w-5" />
                Mapeo Equipos ↔ Dispositivos GPS ({mapeos.length})
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {mapeos.length === 0 ? (
                <p className="text-sm text-gray-400">Sin mapeos. Agrega uno abajo.</p>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
                        <th className="px-2 py-1.5">Patente</th>
                        <th className="px-2 py-1.5">Proveedor</th>
                        <th className="px-2 py-1.5">Device ID</th>
                        <th className="px-2 py-1.5">Nombre GPS</th>
                        <th className="px-2 py-1.5">IMEI</th>
                        <th className="px-2 py-1.5"></th>
                      </tr>
                    </thead>
                    <tbody>
                      {mapeos.map((m) => (
                        <tr key={m.id} className="border-b">
                          <td className="px-2 py-1.5 font-mono font-semibold">{m.patente ?? '—'}</td>
                          <td className="px-2 py-1.5">{proveedores.find((p) => p.id === m.proveedor_id)?.nombre ?? '—'}</td>
                          <td className="px-2 py-1.5 font-mono">{m.gps_device_id}</td>
                          <td className="px-2 py-1.5">{m.gps_device_name ?? '—'}</td>
                          <td className="px-2 py-1.5 font-mono">{m.imei ?? '—'}</td>
                          <td className="px-2 py-1.5 text-right">
                            <button onClick={() => eliminarMapeo(m.id)} className="text-red-500 hover:text-red-700">
                              <Trash2 className="h-4 w-4" />
                            </button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}

              <details className="rounded border border-dashed p-3">
                <summary className="cursor-pointer text-sm font-medium text-blue-600">
                  + Agregar nuevo mapeo
                </summary>
                <div className="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-2">
                  <select
                    className="h-10 rounded border border-gray-300 px-2 text-sm"
                    value={mapProvId}
                    onChange={(e) => setMapProvId(e.target.value)}
                  >
                    <option value="">Proveedor…</option>
                    {proveedores.map((p) => (
                      <option key={p.id} value={p.id}>{p.nombre}</option>
                    ))}
                  </select>
                  <select
                    className="h-10 rounded border border-gray-300 px-2 text-sm"
                    value={mapActId}
                    onChange={(e) => setMapActId(e.target.value)}
                  >
                    <option value="">Equipo…</option>
                    {activos.map((a) => (
                      <option key={a.id} value={a.id}>{a.patente ?? a.codigo} — {a.nombre}</option>
                    ))}
                  </select>
                  <Input placeholder="GPS Device ID" value={mapDeviceId} onChange={(e) => setMapDeviceId(e.target.value)} />
                  <Input placeholder="Nombre GPS (opcional)" value={mapDeviceName} onChange={(e) => setMapDeviceName(e.target.value)} />
                  <Input placeholder="IMEI (opcional)" value={mapImei} onChange={(e) => setMapImei(e.target.value)} />
                </div>
                <Button variant="primary" size="sm" onClick={crearMapeo} loading={saving} className="mt-2">
                  <Plus className="h-4 w-4" />
                  Agregar mapeo
                </Button>
              </details>
            </CardContent>
          </Card>

          {/* ─── Próximos pasos ─── */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base text-gray-700">Integración pendiente</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 text-sm text-gray-600">
              <p>
                La configuración está lista. Para recibir datos GPS en tiempo real se necesita:
              </p>
              <ol className="list-decimal pl-5 space-y-1">
                <li>Rotar la clave API en la plataforma del proveedor (no uses la que pegaste en chat).</li>
                <li>Crear Supabase Edge Function que, con la clave de config_gps_proveedor, consulte
                    la API cada N minutos y escriba en <code>gps_eventos_log</code>.</li>
                <li>Alternativa: webhook entrante que el proveedor llame con los eventos. Este secret
                    ya lo tienes en config_gps_proveedor.webhook_secret.</li>
                <li>Integrar el mapa en <Link href="/dashboard/flota/jornada" className="text-blue-600 hover:underline">/dashboard/flota/jornada</Link> leyendo desde <code>gps_eventos_log</code>.</li>
              </ol>
            </CardContent>
          </Card>
        </>
      )}
    </div>
  )
}
