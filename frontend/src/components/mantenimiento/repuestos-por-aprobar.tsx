'use client'

// Las solicitudes de repuestos que el operador levantó y esperan al jefe.
//
// Antes esto solo avisaba por la campanita, y el jefe de taller —que anda en
// terreno, no frente al computador— simplemente no la mira. Ahora vive donde
// él ya entra a trabajar: arriba de la bandeja de no conformidades, con la
// foto del operador y los dos botones a mano. Se aprueba desde el teléfono
// sin abrir el Plan Taller.

import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { PackageCheck, Loader2, Camera, Clock } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { useToast } from '@/contexts/toast-context'
import { getSeguimientoRecursos, validarRecurso, type OTRecursoSeguimiento } from '@/lib/services/ot-recursos'
import { cn } from '@/lib/utils'

export function RepuestosPorAprobar({ onCambio }: { onCambio?: () => void }) {
  const qc = useQueryClient()
  const toast = useToast()
  const [busy, setBusy] = useState<string | null>(null)
  const [ajuste, setAjuste] = useState<Record<string, string>>({})

  const { data: todos = [] } = useQuery({
    queryKey: ['recursos-por-aprobar'],
    queryFn: getSeguimientoRecursos,
    staleTime: 20_000,
  })
  const pendientes = todos.filter((r) => r.estado === 'solicitado')

  async function decidir(r: OTRecursoSeguimiento, accion: 'aprobar' | 'rechazar') {
    setBusy(r.id)
    try {
      // Si el jefe corrigió la cantidad, se aprueba la que él puso.
      const txt = ajuste[r.id]
      const cant = txt !== undefined && txt !== '' ? Number(txt) : null
      if (accion === 'aprobar' && cant !== null && (!Number.isFinite(cant) || cant <= 0)) {
        toast.error('La cantidad tiene que ser mayor que cero'); return
      }
      await validarRecurso({ recursoId: r.id, accion, cantidadAprobada: accion === 'aprobar' ? cant : null })
      toast.success(accion === 'aprobar'
        ? `Aprobado: ${cant ?? r.cantidad} ${r.unidad ?? 'un'} de ${r.producto_nombre ?? r.descripcion} para ${r.activo_patente ?? r.ot_folio}`
        : `Rechazado el pedido de ${r.activo_patente ?? r.ot_folio}`)
      qc.invalidateQueries({ queryKey: ['recursos-por-aprobar'] })
      qc.invalidateQueries({ queryKey: ['vale-equipos-listos'] })
      onCambio?.()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'No se pudo registrar la decisión')
    } finally { setBusy(null) }
  }

  if (pendientes.length === 0) return null

  return (
    <Card className="border-orange-300 bg-orange-50/60">
      <CardContent className="p-3 sm:p-4">
        <div className="mb-3 flex items-center gap-2">
          <PackageCheck className="h-5 w-5 shrink-0 text-orange-600" />
          <h2 className="text-base font-bold text-orange-900">
            {pendientes.length} pedido{pendientes.length > 1 ? 's' : ''} esperando tu aprobación
          </h2>
        </div>

        <div className="grid gap-2 lg:grid-cols-2">
          {pendientes.map((r) => {
            const espera = r.dias_desde_solicitud ?? 0
            return (
              <div key={r.id} className="rounded-lg border border-orange-200 bg-white p-3">
                <div className="flex items-start gap-3">
                  {/* La foto del operador es la evidencia: grande y clickeable. */}
                  {r.fotos?.[0] ? (
                    <a href={r.fotos[0]} target="_blank" rel="noreferrer" className="shrink-0" title="Ver la foto del operador">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img src={r.fotos[0]} alt="Foto del pedido" className="h-16 w-16 rounded border object-cover hover:opacity-80" />
                    </a>
                  ) : (
                    <span className="flex h-16 w-16 shrink-0 items-center justify-center rounded border border-dashed border-gray-300 text-gray-300">
                      <Camera className="h-5 w-5" />
                    </span>
                  )}

                  <div className="min-w-0 flex-1">
                    {/* [MIG386] Un pedido va contra un equipo o contra el
                        taller. Mostrar «OT null» en los del taller dejaba al
                        jefe sin saber a qué le está dando el visto bueno. */}
                    {r.es_insumo_taller ? (
                      <p className="text-sm font-bold text-gray-900">
                        {r.ceco_nombre ?? 'Taller'}
                        <span className="ml-1.5 rounded bg-gray-100 px-1.5 py-0.5 text-[10px] font-semibold text-gray-600">
                          insumo del taller
                        </span>
                      </p>
                    ) : (
                      <p className="text-sm font-bold text-gray-900">
                        {r.activo_patente ?? r.activo_codigo ?? '—'}
                        <span className="ml-1.5 text-[11px] font-normal text-muted-foreground">OT {r.ot_folio}</span>
                      </p>
                    )}
                    <p className="text-sm text-gray-800">
                      {r.cantidad} {r.unidad ?? 'un'} · {r.producto_nombre ?? r.descripcion ?? 'Sin descripción'}
                    </p>
                    {r.comentario && <p className="mt-0.5 text-xs text-gray-600">«{r.comentario}»</p>}
                    <p className="mt-0.5 flex flex-wrap items-center gap-x-2 text-[11px] text-muted-foreground">
                      <span>{r.solicitado_nombre ?? 'Operador'}</span>
                      {espera > 0 && (
                        <span className={cn('inline-flex items-center gap-0.5', espera >= 3 && 'font-semibold text-red-600')}>
                          <Clock className="h-3 w-3" />
                          {espera} día{espera > 1 ? 's' : ''} esperando
                        </span>
                      )}
                      {r.stock_total !== null && (
                        <span className={r.stock_total > 0 ? 'text-emerald-700' : 'text-amber-700'}>
                          {r.stock_total > 0 ? `${r.stock_total} en bodega` : 'sin stock — habrá que comprarlo'}
                        </span>
                      )}
                    </p>
                  </div>
                </div>

                {/* Botones grandes: esto se aprieta con el dedo, en terreno. */}
                <div className="mt-2.5 flex items-center gap-2">
                  <input
                    type="number" inputMode="decimal" min={0} step="any"
                    placeholder={`${r.cantidad}`}
                    value={ajuste[r.id] ?? ''}
                    onChange={(e) => setAjuste((p) => ({ ...p, [r.id]: e.target.value }))}
                    title="Cambia la cantidad solo si vas a aprobar menos de lo pedido"
                    className="w-20 rounded-md border px-2 py-2 text-sm"
                  />
                  <Button size="sm" disabled={busy === r.id} onClick={() => decidir(r, 'aprobar')}
                          className="flex-1 bg-emerald-600 py-2.5 font-bold hover:bg-emerald-700">
                    {busy === r.id ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Aprobar'}
                  </Button>
                  <Button size="sm" variant="outline" disabled={busy === r.id} onClick={() => decidir(r, 'rechazar')}
                          className="border-red-300 py-2.5 text-red-700 hover:bg-red-50">
                    Rechazar
                  </Button>
                </div>
              </div>
            )
          })}
        </div>
      </CardContent>
    </Card>
  )
}
