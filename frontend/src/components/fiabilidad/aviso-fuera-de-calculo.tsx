'use client'

import { Info } from 'lucide-react'

export type FueraDeCalculo = { patente: string | null; codigo: string | null; desde: string; hasta: string | null; motivo: string }

const fecha = (iso: string) => new Date(iso.slice(0, 10) + 'T12:00:00').toLocaleDateString('es-CL', { day: '2-digit', month: 'short' })

/**
 * [MIG633] Equipos que no cuentan para la fiabilidad en el período (por ejemplo,
 * camiones nuevos que se están equipando). Se avisa para que se entienda por
 * qué no aparecen; se sacan y se dan de alta en Flota → Sugerencias GPS.
 */
export function AvisoFueraDeCalculo({ items }: { items: FueraDeCalculo[] }) {
  if (items.length === 0) return null
  return (
    <div className="flex gap-2 rounded-lg border border-sky-200 bg-sky-50 px-3 py-2 text-sm text-gray-700">
      <Info className="mt-0.5 h-4 w-4 shrink-0 text-sky-600" />
      <div>
        <b>{items.length} equipo{items.length === 1 ? '' : 's'} fuera del cálculo en este período</b>{' '}
        <span className="text-gray-500">(sus días no cuentan ni arriba ni abajo):</span>
        <ul className="mt-1 space-y-0.5 text-xs">
          {items.map((x, i) => (
            <li key={i}>
              <b className="font-mono">{x.patente ?? x.codigo}</b>
              {x.codigo && x.patente ? ` (${x.codigo})` : ''} · desde el {fecha(x.desde)}
              {x.hasta ? ` hasta el ${fecha(x.hasta)}` : ''} · {x.motivo}
            </li>
          ))}
        </ul>
      </div>
    </div>
  )
}
