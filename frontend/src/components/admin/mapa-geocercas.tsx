'use client'

import { useEffect, useMemo } from 'react'
import { MapContainer, TileLayer, Circle, useMap, useMapEvents, Popup } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { TIPO_COLORS_DEFAULT, TIPO_LABELS, type Geocerca } from '@/lib/services/geocercas'

interface Props {
  geocercas: Geocerca[]
  modoCrear: boolean
  centroNuevo: { lat: number; lng: number } | null
  radioNuevo: number
  onMapClick: (lat: number, lng: number) => void
  geocercaResaltadaId: string | null
}

function ClickHandler({ enabled, onClick }: { enabled: boolean; onClick: (lat: number, lng: number) => void }) {
  useMapEvents({
    click(e) {
      if (enabled) onClick(e.latlng.lat, e.latlng.lng)
    },
  })
  return null
}

function FlyToGeocerca({ geo }: { geo: Geocerca | null }) {
  const map = useMap()
  useEffect(() => {
    if (!geo) return
    map.flyTo([geo.centro_lat, geo.centro_lng], 14, { duration: 0.6 })
  }, [geo, map])
  return null
}

function FlyToNuevo({ punto }: { punto: { lat: number; lng: number } | null }) {
  const map = useMap()
  useEffect(() => {
    if (!punto) return
    // Solo centrar si está fuera del viewport
    const b = map.getBounds()
    if (!b.contains([punto.lat, punto.lng])) {
      map.flyTo([punto.lat, punto.lng], map.getZoom(), { duration: 0.5 })
    }
  }, [punto, map])
  return null
}

export function MapaGeocercas({
  geocercas, modoCrear, centroNuevo, radioNuevo, onMapClick, geocercaResaltadaId,
}: Props) {
  const validas = useMemo(() => geocercas.filter((g) => g.centro_lat != null && g.centro_lng != null), [geocercas])

  const centroInicial: [number, number] = useMemo(() => {
    if (validas.length === 0) return [-22.46, -68.93]  // Calama por default
    const sumLat = validas.reduce((s, g) => s + g.centro_lat, 0)
    const sumLng = validas.reduce((s, g) => s + g.centro_lng, 0)
    return [sumLat / validas.length, sumLng / validas.length]
  }, [validas])

  const resaltada = geocercas.find((g) => g.id === geocercaResaltadaId) ?? null

  return (
    <MapContainer
      center={centroInicial}
      zoom={6}
      style={{ height: '100%', width: '100%', minHeight: 400, cursor: modoCrear ? 'crosshair' : 'grab' }}
      scrollWheelZoom>
      <TileLayer
        attribution='&copy; OpenStreetMap'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />

      <ClickHandler enabled={modoCrear} onClick={onMapClick} />
      <FlyToGeocerca geo={resaltada} />
      <FlyToNuevo punto={centroNuevo} />

      {/* Geocercas existentes */}
      {validas.map((g) => {
        const color = g.color || TIPO_COLORS_DEFAULT[g.tipo]
        const esResaltada = g.id === geocercaResaltadaId
        return (
          <Circle
            key={g.id}
            center={[g.centro_lat, g.centro_lng]}
            radius={g.radio_m}
            pathOptions={{
              color,
              fillColor: color,
              fillOpacity: esResaltada ? 0.35 : 0.15,
              weight: esResaltada ? 3 : 2,
            }}>
            <Popup>
              <div style={{ minWidth: 200, fontSize: 13 }}>
                <div style={{ fontWeight: 600 }}>{g.nombre}</div>
                <div style={{ color, fontSize: 11 }}>{TIPO_LABELS[g.tipo]}</div>
                {g.cliente && <div style={{ marginTop: 4 }}>Cliente: <b>{g.cliente}</b></div>}
                <div>Radio: <b>{g.radio_m.toLocaleString('es-CL')} m</b></div>
                <div style={{ fontSize: 11, color: '#6B7280', marginTop: 4 }}>
                  {g.centro_lat.toFixed(5)}, {g.centro_lng.toFixed(5)}
                </div>
              </div>
            </Popup>
          </Circle>
        )
      })}

      {/* Preview de la nueva geocerca */}
      {modoCrear && centroNuevo && (
        <Circle
          center={[centroNuevo.lat, centroNuevo.lng]}
          radius={radioNuevo}
          pathOptions={{
            color: '#F59E0B',
            fillColor: '#FBBF24',
            fillOpacity: 0.3,
            weight: 3,
            dashArray: '8 4',
          }}
        />
      )}
    </MapContainer>
  )
}

// Util para que la página padre pueda crear los iconos sin importar Leaflet directo
export function fixLeafletIcons(): void {
  // En algunos setups SSR los iconos por defecto se rompen; aquí preserva la API.
  delete (L.Icon.Default.prototype as { _getIconUrl?: unknown })._getIconUrl
}
