'use client'

import { estadoFlotaColor, estadoFlotaLabel } from '@/lib/estado-flota'

// La píldora de estado del planificador. Misma forma y mismo color en
// Sugerencias GPS, en el listado de Activos y en la ficha, para que nadie
// tenga que traducir mentalmente entre pantallas.
export function EstadoFlotaPill({
  codigo,
  soloCodigo = false,
  className = '',
  title,
}: {
  codigo: string | null | undefined
  soloCodigo?: boolean
  className?: string
  title?: string
}) {
  if (!codigo) {
    return <span className={`text-gray-300 ${className}`}>—</span>
  }
  return (
    <span
      title={title ?? estadoFlotaLabel(codigo)}
      className={`inline-flex items-center gap-1 rounded px-2 py-0.5 text-xs font-semibold text-white ${className}`}
      style={{ background: estadoFlotaColor(codigo) }}
    >
      {soloCodigo ? codigo : `${codigo} · ${estadoFlotaLabel(codigo)}`}
    </span>
  )
}
