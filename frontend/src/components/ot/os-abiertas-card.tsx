'use client'

// [21-09] Todas las órdenes de servicio abiertas del taller, en el panel.
//
// Pedido del jefe de taller: «poder abrir las órdenes de servicio y revisarlas
// para que la ejecuten, y no la estén buscando por el día que se realizó».
// Hasta ahora en el escritorio la OS sólo se veía dentro de su OT, y en el
// teléfono había que dar con el día en la tira semanal. Acá salen todas juntas
// (atrasadas primero, lo mismo que ordena rpc_taller_os_abiertas) y cada una se
// abre en la misma página que ejecuta el mecánico.

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import { ChevronDown, ChevronRight, Wrench } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { getOSAbiertas, ESTADO_OS_LABEL } from '@/lib/services/taller-os'

const ESTADO_CLS: Record<string, string> = {
  en_ejecucion: 'bg-green-100 text-green-800',
  pausada: 'bg-amber-100 text-amber-900',
}

function hoyISO() {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

function fechaCorta(f: string) {
  return new Date(`${f}T00:00:00`).toLocaleDateString('es-CL', { weekday: 'short', day: '2-digit', month: '2-digit' })
}

export function OSAbiertasCard() {
  const [abierta, setAbierta] = useState(true)
  const [buscar, setBuscar] = useState('')
  const { data: oss = [], isLoading, error } = useQuery({
    queryKey: ['os-abiertas-taller'],
    queryFn: getOSAbiertas,
    staleTime: 30_000,
    retry: false,
  })

  const hoy = hoyISO()
  const atrasadas = oss.filter((o) => o.fecha_programada && o.fecha_programada < hoy).length

  const filtradas = useMemo(() => {
    const s = buscar.trim().toLowerCase()
    if (!s) return oss
    return oss.filter((o) =>
      [o.folio, o.titulo, o.patente, o.equipo, o.ot_folio, o.responsable]
        .some((v) => (v ?? '').toLowerCase().includes(s)))
  }, [oss, buscar])

  if (error) return null

  return (
    <Card>
      <CardContent className="p-4">
        <button type="button" onClick={() => setAbierta(!abierta)}
                className="flex w-full items-center gap-2 text-left">
          {abierta ? <ChevronDown className="h-4 w-4 text-gray-400" /> : <ChevronRight className="h-4 w-4 text-gray-400" />}
          <Wrench className="h-4 w-4 text-blue-600" />
          <span className="text-sm font-bold text-gray-900">Órdenes de servicio abiertas</span>
          <span className="rounded-full bg-blue-100 px-2 py-0.5 text-xs font-semibold text-blue-800">
            {isLoading ? '…' : oss.length}
          </span>
          {atrasadas > 0 && (
            <span className="rounded-full bg-red-100 px-2 py-0.5 text-xs font-semibold text-red-700">
              {atrasadas} atrasada{atrasadas === 1 ? '' : 's'}
            </span>
          )}
        </button>

        {abierta && !isLoading && (
          oss.length === 0 ? (
            <p className="mt-3 text-sm text-gray-400">No hay órdenes de servicio pendientes.</p>
          ) : (
            <>
              <input value={buscar} onChange={(e) => setBuscar(e.target.value)}
                     placeholder="Buscar OS, patente, OT, mecánico…"
                     className="mt-3 h-9 w-full rounded-lg border border-gray-300 px-3 text-sm focus:border-pillado-green-500 focus:outline-none sm:max-w-xs" />
              <div className="mt-2 max-h-80 divide-y divide-gray-100 overflow-y-auto rounded-lg border border-gray-200">
                {filtradas.map((os) => {
                  const atrasada = !!os.fecha_programada && os.fecha_programada < hoy
                  return (
                    <Link key={os.os_id} href={`/m/taller/os/${os.os_id}?desde=panel`}
                          className="flex flex-wrap items-center gap-x-3 gap-y-1 px-3 py-2 text-sm hover:bg-blue-50">
                      <span className="font-mono text-xs font-bold text-gray-600">{os.folio}</span>
                      <span className="min-w-0 flex-1 truncate font-medium text-gray-800">{os.titulo}</span>
                      <span className="font-mono text-xs font-semibold text-gray-900">{os.patente ?? os.equipo ?? '—'}</span>
                      <span className="text-xs text-gray-500">{os.ot_folio}</span>
                      <span className="text-xs text-gray-600">{os.es_externo ? 'Externo' : (os.responsable ?? 'Sin asignar')}</span>
                      <span className={`text-xs ${atrasada ? 'font-semibold text-red-600' : os.fecha_programada === hoy ? 'font-semibold text-green-700' : 'text-gray-500'}`}>
                        {os.fecha_programada ? (os.fecha_programada === hoy ? 'Hoy' : fechaCorta(os.fecha_programada)) : 'Sin día'}
                      </span>
                      <span className={`rounded px-1.5 py-0.5 text-[11px] font-medium ${ESTADO_CLS[os.estado] ?? 'bg-blue-100 text-blue-800'}`}>
                        {ESTADO_OS_LABEL[os.estado] ?? os.estado}
                      </span>
                      <span className="text-xs text-gray-400">{os.ncs} NC</span>
                    </Link>
                  )
                })}
                {filtradas.length === 0 && (
                  <p className="px-3 py-4 text-center text-sm text-gray-400">Ninguna coincide con «{buscar}».</p>
                )}
              </div>
            </>
          )
        )}
      </CardContent>
    </Card>
  )
}
