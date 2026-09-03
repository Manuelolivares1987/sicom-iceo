'use client'

// [03-09] Las solicitudes de repuestos del operador, como ADVERTENCIA.
//
// Antes este bloque traía los botones Aprobar/Rechazar arriba de la bandeja.
// Manuel lo dio vuelta: arriba va solo el aviso — la APROBACIÓN se hace al
// ANALIZAR cada NC, donde el jefe ve la evidencia completa (foto del hallazgo,
// quién paga, qué más necesita el equipo) y no un pedido suelto fuera de
// contexto. Desde MIG497 el pedido del operador cae amarrado a su NC, así que
// la ficha de la NC lo muestra y ahí mismo se aprueba o se ajusta.
//
// Los pedidos que no cuelgan de ningún equipo (insumos del taller) se siguen
// validando en el Plan Taller, como siempre.

import { useQuery } from '@tanstack/react-query'
import { AlertTriangle, Camera, Clock } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { getSeguimientoRecursos } from '@/lib/services/ot-recursos'
import { cn } from '@/lib/utils'

export function RepuestosPorAprobar({ onCambio }: { onCambio?: () => void }) {
  void onCambio // la advertencia no decide nada: no hay cambio que avisar

  const { data: todos = [] } = useQuery({
    queryKey: ['recursos-por-aprobar'],
    queryFn: getSeguimientoRecursos,
    staleTime: 20_000,
  })
  const pendientes = todos.filter((r) => r.estado === 'solicitado')

  if (pendientes.length === 0) return null

  return (
    <Card className="border-amber-300 bg-amber-50/70">
      <CardContent className="p-3 sm:p-4">
        <div className="flex items-center gap-2">
          <AlertTriangle className="h-5 w-5 shrink-0 text-amber-600" />
          <h2 className="text-base font-bold text-amber-900">
            El operador pidió repuestos: {pendientes.length} pedido{pendientes.length > 1 ? 's' : ''} sin aprobar
          </h2>
        </div>
        <p className="mt-1 text-xs text-amber-800">
          Se aprueban <b>al analizar la NC</b>: abre el equipo abajo y entra a la ficha del
          hallazgo — ahí está el pedido con su foto, junto a la evidencia y el recobro.
          Los insumos del taller (sin equipo) se validan en el Plan Taller.
        </p>

        <div className="mt-2 flex flex-wrap gap-1.5">
          {pendientes.map((r) => {
            const espera = r.dias_desde_solicitud ?? 0
            return (
              <span key={r.id}
                    className="inline-flex items-center gap-1.5 rounded-full border border-amber-200 bg-white px-2.5 py-1 text-[11px] text-gray-700">
                <b className="text-gray-900">
                  {r.es_insumo_taller ? (r.ceco_nombre ?? 'Taller') : (r.activo_patente ?? r.activo_codigo ?? r.ot_folio ?? '—')}
                </b>
                <span className="max-w-[180px] truncate">
                  {r.cantidad} {r.unidad ?? 'un'} · {r.producto_nombre ?? r.descripcion ?? 'sin descripción'}
                </span>
                {r.fotos?.[0] && <Camera className="h-3 w-3 text-gray-400" />}
                {espera > 0 && (
                  <span className={cn('inline-flex items-center gap-0.5 text-gray-500',
                                      espera >= 3 && 'font-semibold text-red-600')}>
                    <Clock className="h-3 w-3" /> {espera} d
                  </span>
                )}
              </span>
            )
          })}
        </div>
      </CardContent>
    </Card>
  )
}
