'use client'

// «Listo para salir sin señal»: la revisión que Kizeo pide hacer a mano antes
// de ir a faena (abrir la app con red, bandeja vacía, espacio libre), hecha
// por la app y a la vista. Plegada cuando todo está bien; abierta si algo falta.

import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { ShieldCheck, ShieldAlert, Check, AlertTriangle, ChevronDown, ChevronRight } from 'lucide-react'
import { ultimaDescargaEnex, pantallasDisponiblesOffline, protegerAlmacenamiento } from '@/lib/offline/enex-offline'

/** Pasado esto, lo descargado puede no tener lo último del planificador. */
const DESCARGA_VIEJA_H = 24
const ESPACIO_MIN_MB = 300

type Punto = { ok: boolean; texto: string }

export function ListoSinSenal({ anio, mes, pendientes }: { anio: number; mes: number; pendientes: number }) {
  const [abierto, setAbierto] = useState(false)
  const { data } = useQuery({
    queryKey: ['enex-listo-sin-senal', anio, mes],
    queryFn: async () => {
      const [ultima, pantallas, almac] = await Promise.all([
        ultimaDescargaEnex(anio, mes), pantallasDisponiblesOffline(), protegerAlmacenamiento(),
      ])
      return { ultima, pantallas, almac }
    },
    networkMode: 'always', refetchInterval: 30_000,
  })
  if (!data) return null

  const horas = data.ultima ? (Date.now() - new Date(data.ultima).getTime()) / 3_600_000 : null
  const puntos: Punto[] = [
    { ok: data.pantallas, texto: data.pantallas ? 'Pantallas guardadas en el teléfono' : 'Faltan las pantallas: abre la app una vez con señal' },
    {
      ok: horas != null && horas < DESCARGA_VIEJA_H,
      texto: horas == null ? 'Servicios sin descargar: abre la app con señal'
        : `Servicios descargados ${horas < 1 ? 'hace menos de 1 h' : `hace ${Math.round(horas)} h`}`,
    },
    { ok: pendientes === 0, texto: pendientes === 0 ? 'Nada pendiente por enviar' : `${pendientes} por enviar desde este teléfono` },
    {
      ok: data.almac.persistente,
      texto: data.almac.persistente ? 'Datos protegidos contra borrado'
        : 'El teléfono podría borrar lo guardado: instala la app en la pantalla de inicio',
    },
  ]
  if (data.almac.libreMB != null) {
    puntos.push({
      ok: data.almac.libreMB >= ESPACIO_MIN_MB,
      texto: `${data.almac.libreMB >= 1024 ? `${(data.almac.libreMB / 1024).toFixed(1)} GB` : `${data.almac.libreMB} MB`} libres para fotos`,
    })
  }
  const todoOk = puntos.every((p) => p.ok)
  const verDetalle = abierto || !todoOk

  return (
    <div className={`rounded-lg border p-2 text-xs ${todoOk ? 'border-green-200 bg-green-50' : 'border-amber-300 bg-amber-50'}`}>
      <button onClick={() => setAbierto((a) => !a)} className="flex w-full items-center gap-1.5 text-left">
        {todoOk ? <ShieldCheck className="h-4 w-4 text-green-700" /> : <ShieldAlert className="h-4 w-4 text-amber-700" />}
        <span className={`flex-1 font-semibold ${todoOk ? 'text-green-800' : 'text-amber-900'}`}>
          {todoOk ? 'Listo para trabajar sin señal' : 'Antes de salir sin señal, revisa esto'}
        </span>
        {verDetalle ? <ChevronDown className="h-3.5 w-3.5 text-gray-400" /> : <ChevronRight className="h-3.5 w-3.5 text-gray-400" />}
      </button>
      {verDetalle && (
        <ul className="mt-1.5 space-y-0.5">
          {puntos.map((p) => (
            <li key={p.texto} className={`flex items-start gap-1.5 ${p.ok ? 'text-gray-600' : 'font-medium text-amber-900'}`}>
              {p.ok ? <Check className="mt-0.5 h-3 w-3 flex-shrink-0 text-green-600" /> : <AlertTriangle className="mt-0.5 h-3 w-3 flex-shrink-0 text-amber-600" />}
              {p.texto}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
