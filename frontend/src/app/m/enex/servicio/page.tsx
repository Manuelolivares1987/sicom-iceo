'use client'

// Ejecución de un servicio ENEX: /m/enex/servicio/?id=<programacion_id>.
//
// Es una página fija y el servicio va en la URL como parámetro. Con la ruta
// /m/enex/<id> cada servicio era una página distinta para el teléfono, y solo
// abrían sin señal los que se habían abierto antes con señal: los demás caían
// en «Sin conexión» teniendo todo descargado.

import { Suspense } from 'react'
import { useSearchParams } from 'next/navigation'
import { EjecutarServicio } from '@/components/enex/ejecutar-servicio'

function Servicio() {
  const id = useSearchParams()?.get('id') ?? ''
  if (!id) return <div className="p-6 text-center text-sm text-gray-400">Falta el servicio a abrir.</div>
  return <EjecutarServicio key={id} progId={id} />
}

export default function EnexServicioPage() {
  return (
    <Suspense fallback={<div className="p-6 text-center text-sm text-gray-400">Cargando…</div>}>
      <Servicio />
    </Suspense>
  )
}
