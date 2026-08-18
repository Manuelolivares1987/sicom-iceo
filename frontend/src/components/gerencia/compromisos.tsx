'use client'

import { useMemo, useState } from 'react'
import {
  CalendarClock, Check, CircleSlash, RotateCcw, Target, UserRound,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import type { Compromiso } from '@/lib/services/panel-gerencia'
import { fmtFecha } from './comunes'

// ============================================================================
// Compromisos de la semana (MIG305)
// ----------------------------------------------------------------------------
// Los planes de acción estaban escondidos, uno dentro de cada equipo y de cada
// faena. Aquí se ven todos juntos y —lo que faltaba— se pueden cerrar. Un
// compromiso que no se puede marcar cumplido no es un compromiso: es una nota.
//
// Lo pendiente arrastra de semanas anteriores; lo cerrado sólo aparece en su
// semana, para que la lista no se convierta en un archivo histórico.
// ============================================================================

function Fila({ c, guardando, onEstado }: {
  c: Compromiso
  guardando: boolean
  onEstado: (id: string, estado: 'pendiente' | 'cumplido' | 'anulado') => void
}) {
  const cerrado = c.compromiso_estado !== 'pendiente'
  const porVencer = !c.vencido && c.dias_restantes != null
    && c.dias_restantes >= 0 && c.dias_restantes <= 2

  return (
    <div className={`flex items-start gap-3 rounded-lg border px-3 py-2
      ${c.vencido ? 'border-red-300 bg-red-50/60'
        : cerrado ? 'border-emerald-200 bg-emerald-50/40'
        : porVencer ? 'border-amber-300 bg-amber-50/50' : 'bg-card'}`}>

      <button
        onClick={() => onEstado(c.id, c.compromiso_estado === 'cumplido' ? 'pendiente' : 'cumplido')}
        disabled={guardando}
        title={c.compromiso_estado === 'cumplido' ? 'Reabrir' : 'Marcar cumplido'}
        className={`mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded border-2
          ${c.compromiso_estado === 'cumplido'
            ? 'border-emerald-600 bg-emerald-600 text-white'
            : 'border-muted-foreground/40 hover:border-emerald-600'}`}
      >
        {c.compromiso_estado === 'cumplido' && <Check className="h-3.5 w-3.5" />}
      </button>

      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-x-2 gap-y-0.5">
          <span className="rounded bg-muted px-1.5 py-0.5 text-[10px] font-semibold">
            {c.referencia}
          </span>
          {c.vencido && (
            <span className="rounded bg-red-600 px-1.5 py-0.5 text-[10px] font-bold text-white">
              VENCIDO {Math.abs(c.dias_restantes ?? 0)} d
            </span>
          )}
          {c.compromiso_estado === 'anulado' && (
            <span className="rounded bg-slate-200 px-1.5 py-0.5 text-[10px] font-semibold text-slate-600">
              ANULADO
            </span>
          )}
        </div>

        <p className={`text-sm leading-snug ${cerrado ? 'text-muted-foreground line-through' : ''}`}>
          {c.plan_accion}
        </p>

        <div className="mt-0.5 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-[11px] text-muted-foreground">
          <span className="inline-flex items-center gap-1">
            <UserRound className="h-3 w-3" />
            {c.responsable?.trim() || <i className="text-amber-700">sin responsable</i>}
          </span>
          <span className="inline-flex items-center gap-1">
            <CalendarClock className="h-3 w-3" />
            {c.fecha_compromiso
              ? fmtFecha(c.fecha_compromiso)
              : <i className="text-amber-700">sin fecha</i>}
          </span>
          {c.antiguedad_dias > 7 && !cerrado && (
            <span>comprometido hace {c.antiguedad_dias} días</span>
          )}
        </div>
      </div>

      {!cerrado && (
        <button
          onClick={() => onEstado(c.id, 'anulado')}
          disabled={guardando}
          title="Anular: ya no aplica"
          className="mt-0.5 shrink-0 text-muted-foreground hover:text-red-600"
        >
          <CircleSlash className="h-3.5 w-3.5" />
        </button>
      )}
      {cerrado && c.compromiso_estado === 'anulado' && (
        <button
          onClick={() => onEstado(c.id, 'pendiente')}
          disabled={guardando}
          title="Reabrir"
          className="mt-0.5 shrink-0 text-muted-foreground hover:text-foreground"
        >
          <RotateCcw className="h-3.5 w-3.5" />
        </button>
      )}
    </div>
  )
}

export function PanelCompromisos({ compromisos, guardando, onEstado }: {
  compromisos: Compromiso[]
  guardando: boolean
  onEstado: (id: string, estado: 'pendiente' | 'cumplido' | 'anulado') => void
}) {
  const [verCerrados, setVerCerrados] = useState(false)

  const { pendientes, cerrados, vencidos } = useMemo(() => {
    const p = compromisos.filter((c) => c.compromiso_estado === 'pendiente')
    return {
      pendientes: p,
      cerrados: compromisos.filter((c) => c.compromiso_estado !== 'pendiente'),
      vencidos: p.filter((c) => c.vencido).length,
    }
  }, [compromisos])

  return (
    <Card>
      <CardHeader className="pb-2">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <Target className="h-4 w-4" />
            Compromisos
            {vencidos > 0 && (
              <span className="rounded bg-red-600 px-2 py-0.5 text-xs font-bold text-white">
                {vencidos} vencido{vencidos === 1 ? '' : 's'}
              </span>
            )}
          </CardTitle>
          {cerrados.length > 0 && (
            <Button size="sm" variant="ghost" onClick={() => setVerCerrados((v) => !v)}>
              {verCerrados ? 'Ocultar' : 'Ver'} {cerrados.length} cerrado{cerrados.length === 1 ? '' : 's'}
            </Button>
          )}
        </div>
        <p className="text-xs text-muted-foreground">
          Todo lo comprometido en el panel —equipos, faenas y cuadrantes— en una
          sola lista. Lo pendiente arrastra hasta que alguien lo cierre.
        </p>
      </CardHeader>

      <CardContent className="space-y-2">
        {pendientes.length === 0 && cerrados.length === 0 && (
          <div className="rounded-lg border border-dashed py-6 text-center">
            <p className="text-sm font-medium">Todavía no hay compromisos escritos.</p>
            <p className="mt-1 text-xs text-muted-foreground">
              Se crean escribiendo un plan de acción con responsable y fecha en
              «Requiere decisión» o en el detalle de un equipo o faena.
            </p>
          </div>
        )}

        {pendientes.map((c) => (
          <Fila key={c.id} c={c} guardando={guardando} onEstado={onEstado} />
        ))}

        {verCerrados && cerrados.map((c) => (
          <Fila key={c.id} c={c} guardando={guardando} onEstado={onEstado} />
        ))}
      </CardContent>
    </Card>
  )
}
