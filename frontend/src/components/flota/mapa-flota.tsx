'use client'

import { useEffect, useMemo, useRef } from 'react'
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'

export type PosicionFlota = {
  activo_id: string
  activo_codigo: string
  activo_patente: string | null
  activo_nombre: string | null
  activo_tipo: string
  tipo_equipamiento: string
  activo_estado: string | null
  activo_estado_comercial: string | null
  km_actual: number | null
  horas_actual: number | null
  contrato_id: string | null
  contrato_codigo: string | null
  cliente: string | null
  gps_device_id: string
  gps_device_name: string | null
  ts_gps: string | null
  latitud: number | null
  longitud: number | null
  velocidad_kmh: number | null
  heading: number | null
  ignicion: boolean | null
  movimiento: string | null
  conexion: string | null
  odometro_km: number | null
  horometro_hrs: number | null
  bateria_pct: number | null
  gsm_red: string | null
  estado_pin: 'sin_datos' | 'sin_senal' | 'en_ruta' | 'detenido_motor_on' | 'detenido'
  minutos_desde_reporte: number | null
}

const COLOR_BY_ESTADO: Record<PosicionFlota['estado_pin'], string> = {
  en_ruta:            '#16A34A',
  detenido_motor_on:  '#F59E0B',
  detenido:           '#6B7280',
  sin_senal:          '#DC2626',
  sin_datos:          '#A1A1AA',
}

const LABEL_BY_ESTADO: Record<PosicionFlota['estado_pin'], string> = {
  en_ruta:            'En ruta',
  detenido_motor_on:  'Detenido (motor ON)',
  detenido:           'Detenido',
  sin_senal:          'Sin senal >2h',
  sin_datos:          'Sin datos GPS',
}

function iconoVehiculo(estado: PosicionFlota['estado_pin'], heading: number | null): L.DivIcon {
  const color = COLOR_BY_ESTADO[estado]
  const rotate = heading ?? 0
  return L.divIcon({
    className: '',
    html: `
      <div style="position:relative;width:28px;height:28px;">
        <div style="position:absolute;inset:0;background:${color};border:2px solid white;
                    border-radius:50%;box-shadow:0 2px 6px rgba(0,0,0,.35);"></div>
        <div style="position:absolute;top:-4px;left:50%;width:0;height:0;
                    border-left:6px solid transparent;border-right:6px solid transparent;
                    border-bottom:10px solid ${color};
                    transform:translateX(-50%) rotate(${rotate}deg);
                    transform-origin:50% 18px;"></div>
      </div>`,
    iconSize: [28, 28],
    iconAnchor: [14, 14],
    popupAnchor: [0, -14],
  })
}

function AjustarBounds({ posiciones }: { posiciones: PosicionFlota[] }) {
  const map = useMap()
  const ranOnce = useRef(false)

  useEffect(() => {
    if (ranOnce.current) return
    const validas = posiciones.filter((p) => p.latitud != null && p.longitud != null)
    if (validas.length === 0) return
    const bounds = L.latLngBounds(validas.map((p) => [p.latitud!, p.longitud!] as [number, number]))
    map.fitBounds(bounds, { padding: [40, 40], maxZoom: 12 })
    ranOnce.current = true
  }, [posiciones, map])

  return null
}

function formatHaceMin(min: number | null): string {
  if (min == null) return 'sin datos'
  if (min < 1) return 'hace segundos'
  if (min < 60) return `hace ${min} min`
  const h = Math.floor(min / 60)
  if (h < 24) return `hace ${h} h`
  const d = Math.floor(h / 24)
  return `hace ${d} d`
}

export function MapaFlota({ posiciones }: { posiciones: PosicionFlota[] }) {
  const validas = useMemo(
    () => posiciones.filter((p) => p.latitud != null && p.longitud != null),
    [posiciones]
  )

  // Centro inicial: Chile norte (Calama) por defecto
  const centro: [number, number] = useMemo(() => {
    if (validas.length === 0) return [-22.46, -68.93]
    const sumLat = validas.reduce((s, p) => s + (p.latitud ?? 0), 0)
    const sumLng = validas.reduce((s, p) => s + (p.longitud ?? 0), 0)
    return [sumLat / validas.length, sumLng / validas.length]
  }, [validas])

  return (
    <MapContainer
      center={centro}
      zoom={6}
      style={{ height: '100%', width: '100%', minHeight: 500, borderRadius: 8 }}
      scrollWheelZoom
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <AjustarBounds posiciones={validas} />
      {validas.map((p) => (
        <Marker
          key={p.activo_id}
          position={[p.latitud!, p.longitud!]}
          icon={iconoVehiculo(p.estado_pin, p.heading)}
        >
          <Popup>
            <div style={{ minWidth: 240, fontSize: 13 }}>
              <div style={{ fontWeight: 600, fontSize: 15, marginBottom: 2 }}>
                {p.activo_codigo}
                {p.activo_patente ? ` · ${p.activo_patente}` : ''}
              </div>
              {p.activo_nombre && (
                <div style={{ fontSize: 12, color: '#6B7280', marginBottom: 4 }}>{p.activo_nombre}</div>
              )}
              <div style={{ color: COLOR_BY_ESTADO[p.estado_pin], fontWeight: 500, marginBottom: 6 }}>
                {LABEL_BY_ESTADO[p.estado_pin]}
              </div>
              {p.cliente && (
                <div>Cliente: <b>{p.cliente}</b>{p.contrato_codigo && ` (${p.contrato_codigo})`}</div>
              )}
              <div>Velocidad: <b>{p.velocidad_kmh != null ? `${p.velocidad_kmh.toFixed(0)} km/h` : '—'}</b></div>
              <div>Motor: <b>{p.ignicion == null ? '—' : (p.ignicion ? 'Encendido' : 'Apagado')}</b></div>
              <div>Ultimo reporte: <b>{formatHaceMin(p.minutos_desde_reporte)}</b></div>
              <hr style={{ margin: '6px 0', border: 'none', borderTop: '1px solid #E5E7EB' }} />
              <div>Odometro: <b>{p.odometro_km != null ? `${p.odometro_km.toFixed(0)} km` : '—'}</b></div>
              <div>Horometro: <b>{p.horometro_hrs != null ? `${p.horometro_hrs.toFixed(1)} h` : '—'}</b></div>
              <div>Bateria: <b>{p.bateria_pct != null ? `${p.bateria_pct}%` : '—'}</b></div>
              <div>Red: <b>{p.gsm_red ?? '—'}</b></div>
            </div>
          </Popup>
        </Marker>
      ))}
    </MapContainer>
  )
}

