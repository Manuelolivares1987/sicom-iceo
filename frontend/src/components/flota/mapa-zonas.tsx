'use client'

import { useEffect } from 'react'
import { MapContainer, TileLayer, Circle, Tooltip, useMap, useMapEvents } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'

// ============================================================================
// Mapa de zonas de un contrato (Centinela, MIG572)
// Verde = zona guardada (sólida si está verificada) · naranjo punteado =
// sugerida por el GPS · azul = la que se está editando. Un clic en el mapa
// mueve el centro de la zona en edición.
// ============================================================================

export type ZonaCirculo = {
  key: string
  lat: number
  lng: number
  radio_m: number
  etiqueta: string
  tipo: 'guardada' | 'guardada_sin_verificar' | 'sugerida' | 'edicion'
}

const ESTILO: Record<ZonaCirculo['tipo'], L.PathOptions> = {
  guardada: { color: '#15803d', fillColor: '#22c55e', fillOpacity: 0.15, weight: 2 },
  guardada_sin_verificar: { color: '#15803d', fillColor: '#22c55e', fillOpacity: 0.08, weight: 2, dashArray: '4 4' },
  sugerida: { color: '#ea580c', fillColor: '#fb923c', fillOpacity: 0.1, weight: 2, dashArray: '6 6' },
  edicion: { color: '#1d4ed8', fillColor: '#3b82f6', fillOpacity: 0.2, weight: 3 },
}

function Encuadrar({ zonas }: { zonas: ZonaCirculo[] }) {
  const map = useMap()
  const firma = zonas.map((z) => `${z.key}:${z.lat.toFixed(3)}:${z.lng.toFixed(3)}:${Math.round(z.radio_m)}`).join('|')
  useEffect(() => {
    if (zonas.length === 0) return
    const b = L.latLngBounds([])
    for (const z of zonas) b.extend(L.latLng(z.lat, z.lng).toBounds(z.radio_m * 2))
    map.fitBounds(b, { padding: [20, 20], maxZoom: 13 })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [firma])
  return null
}

function ClicCentro({ onClic }: { onClic?: (lat: number, lng: number) => void }) {
  useMapEvents({ click: (e) => onClic?.(e.latlng.lat, e.latlng.lng) })
  return null
}

export function MapaZonas({ zonas, onClic }: {
  zonas: ZonaCirculo[]
  onClic?: (lat: number, lng: number) => void
}) {
  return (
    <MapContainer center={[-26, -70]} zoom={5} scrollWheelZoom
                  style={{ height: 360, width: '100%', borderRadius: 8 }}>
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <Encuadrar zonas={zonas} />
      <ClicCentro onClic={onClic} />
      {zonas.map((z) => (
        <Circle key={z.key} center={[z.lat, z.lng]} radius={z.radio_m} pathOptions={ESTILO[z.tipo]}>
          <Tooltip>{z.etiqueta}</Tooltip>
        </Circle>
      ))}
    </MapContainer>
  )
}
