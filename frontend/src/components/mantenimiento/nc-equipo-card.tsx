'use client'

// La misma fila de la bandeja de no conformidades, pero para el teléfono.
//
// El jefe de taller trabaja en terreno: la tabla de siete columnas obliga a
// arrastrar de lado y no se lee. Aquí cada equipo es una tarjeta con lo que
// necesita decidir —qué paso falta, cuántas NC, y los botones— y el detalle
// de los hallazgos se despliega debajo.

import { ChevronDown, ChevronRight, Package, Wrench, Receipt, Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'

export type NcEquipoCardProps = {
  patente: string
  nombre: string | null
  nNc: number
  sevMax: string
  pasoLabel: string
  pasoHacer: string
  pasoColor: string
  nPendientes: number
  nRecobrables: number
  nInsumosOperador: number
  recursosTxt: string
  abierto: boolean
  ocupado: boolean
  onToggle: () => void
  onRecursos: () => void
  onPlanificar: () => void
  onRecobro: () => void
  children?: React.ReactNode
}

export function NcEquipoCard(p: NcEquipoCardProps) {
  return (
    <div className="rounded-lg border bg-white">
      <button onClick={p.onToggle} className="flex w-full items-start gap-2 p-3 text-left">
        {p.abierto
          ? <ChevronDown className="mt-0.5 h-4 w-4 shrink-0 text-gray-400" />
          : <ChevronRight className="mt-0.5 h-4 w-4 shrink-0 text-gray-400" />}
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="text-base font-bold">{p.patente}</span>
            <span className="rounded-full bg-orange-100 px-2 py-0.5 text-[11px] font-bold text-orange-700">
              {p.nNc} NC
            </span>
            <Badge variant={p.sevMax as never} className="text-[10px]">{p.sevMax}</Badge>
          </div>
          {p.nombre && <p className="truncate text-xs text-muted-foreground">{p.nombre}</p>}

          {/* Lo primero que tiene que saber: qué falta hacer con este equipo. */}
          <p className="mt-1.5">
            <span className={cn('inline-block rounded-full px-2.5 py-1 text-[11px] font-bold text-white', p.pasoColor)}>
              {p.pasoLabel}
            </span>
          </p>
          <p className="mt-1 text-[11px] leading-snug text-muted-foreground">{p.pasoHacer}</p>

          <p className="mt-1 text-[11px] text-muted-foreground">{p.recursosTxt}</p>
          {p.nInsumosOperador > 0 && (
            <span className="mt-1 inline-block rounded bg-orange-100 px-1.5 py-0.5 text-[10px] font-semibold text-orange-700">
              {p.nInsumosOperador} insumo{p.nInsumosOperador > 1 ? 's' : ''} pedido{p.nInsumosOperador > 1 ? 's' : ''} por el operador
            </span>
          )}
        </div>
      </button>

      {/* Botones anchos: se aprietan con el dedo. */}
      <div className="flex flex-wrap gap-1.5 border-t px-3 py-2">
        <Button size="sm" variant="outline" className="flex-1 py-2" onClick={p.onRecursos}>
          <Package className="mr-1 h-3.5 w-3.5" /> Recursos
        </Button>
        {p.nPendientes > 0 ? (
          <Button size="sm" className="flex-1 py-2" disabled={p.ocupado} onClick={p.onPlanificar}>
            {p.ocupado ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Wrench className="mr-1 h-3.5 w-3.5" />}
            Planificar ({p.nPendientes})
          </Button>
        ) : (
          <Badge variant="en_ejecucion" className="flex-1 justify-center py-1.5 text-[10px]">OT creada</Badge>
        )}
        {p.nRecobrables > 0 && (
          <Button size="sm" variant="outline" onClick={p.onRecobro}
                  className="border-violet-300 py-2 text-violet-700 hover:bg-violet-50">
            <Receipt className="mr-1 h-3.5 w-3.5" /> Recobro ({p.nRecobrables})
          </Button>
        )}
      </div>

      {p.abierto && p.children && <div className="border-t bg-muted/20 p-2">{p.children}</div>}
    </div>
  )
}
