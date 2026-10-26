'use client'

// Links viejos (/m/enex/<id>): siguen abriendo el servicio. Los nuevos van a
// /m/enex/servicio/?id=<id>, que es UNA sola página guardada en el teléfono y
// por eso abre cualquier servicio descargado sin señal.

import { useParams } from 'next/navigation'
import { EjecutarServicio } from '@/components/enex/ejecutar-servicio'

export default function EnexEjecutarPage() {
  const params = useParams()
  return <EjecutarServicio progId={params?.id as string} />
}
