'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import { FileText, Search, ChevronRight, Truck } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { getActivosParaBitacora, type ActivoBitacora } from '@/lib/services/bitacora'

// ============================================================================
// Índice de bitácoras — elegir de qué equipo ver el historial
// ----------------------------------------------------------------------------
// La bitácora (MIG128) solo era alcanzable entrando a la ficha del activo, que
// vive en el módulo de inventario. Prevención necesita el historial de un
// camión para investigar un incidente y no tiene por qué pasar por el
// inventario completo para llegar. Esta pantalla es esa puerta.
// ============================================================================

const ESTADO_TONO: Record<string, string> = {
  operativo: 'bg-emerald-100 text-emerald-800',
  en_mantenimiento: 'bg-amber-100 text-amber-800',
  fuera_servicio: 'bg-red-100 text-red-800',
}

export default function BitacoraIndexPage() {
  useRequireAuth()
  const [q, setQ] = useState('')

  const { data: activos = [], isLoading } = useQuery({
    queryKey: ['activos-para-bitacora'],
    queryFn: async () => {
      const { data, error } = await getActivosParaBitacora()
      if (error) throw error
      return data
    },
    staleTime: 5 * 60_000,
  })

  // Agrupado por operación: en terreno la pregunta siempre es "el camión de
  // Coquimbo" o "el de Calama", nunca "el activo número tal".
  const grupos = useMemo(() => {
    const texto = q.trim().toLowerCase()
    const filtrados = texto
      ? activos.filter((a) =>
          [a.codigo, a.patente, a.nombre, a.cliente_actual]
            .some((c) => (c ?? '').toLowerCase().includes(texto)))
      : activos

    const mapa: Record<string, ActivoBitacora[]> = {}
    for (const a of filtrados) {
      const k = a.operacion ?? 'Sin operación asignada'
      ;(mapa[k] ??= []).push(a)
    }
    return Object.entries(mapa).sort((x, y) => x[0].localeCompare(y[0]))
  }, [activos, q])

  const total = grupos.reduce((acc: number, [, xs]) => acc + xs.length, 0)

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-bold">
          <FileText className="h-6 w-6 text-blue-700" />
          Bitácora de equipos
        </h1>
        <p className="text-sm text-muted-foreground">
          Historial completo de cada equipo: intervenciones, checklists,
          hallazgos e informes en una sola línea de tiempo.
        </p>
      </div>

      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Buscar por patente, código, nombre o cliente…"
          className="pl-9"
        />
      </div>

      {isLoading && <div className="flex justify-center py-16"><Spinner /></div>}

      {!isLoading && total === 0 && (
        <Card>
          <CardContent className="py-10 text-center text-sm text-muted-foreground">
            {q ? `Ningún equipo coincide con "${q}".` : 'No hay equipos cargados.'}
          </CardContent>
        </Card>
      )}

      {!isLoading && total > 0 && (
        <>
          <p className="text-xs text-muted-foreground">
            {total} equipo{total === 1 ? '' : 's'}
          </p>
          {grupos.map(([operacion, equipos]) => (
            <div key={operacion} className="space-y-1.5">
              <div className="flex items-center gap-2 text-sm font-semibold text-muted-foreground">
                <Truck className="h-4 w-4" />
                {operacion}
                <span className="text-xs font-normal">({equipos.length})</span>
              </div>
              <div className="grid gap-1.5 sm:grid-cols-2 xl:grid-cols-3">
                {equipos.map((a) => (
                  <Link key={a.id} href={`/dashboard/flota/bitacora/${a.id}`}
                    className="flex items-center gap-2 rounded-lg border bg-card px-3 py-2
                               transition-colors hover:bg-accent">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <span className="font-semibold">{a.codigo}</span>
                        {a.patente && (
                          <span className="rounded bg-muted px-1.5 py-0.5 text-[10px] font-medium">
                            {a.patente}
                          </span>
                        )}
                        {a.estado && (
                          <span className={`rounded px-1.5 py-0.5 text-[10px] font-medium
                            ${ESTADO_TONO[a.estado] ?? 'bg-muted text-muted-foreground'}`}>
                            {a.estado.replace('_', ' ')}
                          </span>
                        )}
                      </div>
                      <div className="truncate text-xs text-muted-foreground">
                        {a.nombre}
                        {a.cliente_actual && <> · {a.cliente_actual}</>}
                      </div>
                    </div>
                    <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
                  </Link>
                ))}
              </div>
            </div>
          ))}
        </>
      )}
    </div>
  )
}
