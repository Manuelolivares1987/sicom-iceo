'use client'

// ============================================================================
// Los insumos del taller que el jefe ya aprobó (MIG386)
// ----------------------------------------------------------------------------
// El operador pide, el jefe da el visto bueno, y acá se convierte en papel.
// Sin este paso los pedidos aprobados quedaban en un limbo: nadie sabía que
// estaban esperando y el operador iba a bodega con las manos vacías.
//
// UN VALE POR TALLER, NO UNO POR ARTÍCULO
// Se agrupan por centro de costo y salen juntos: el operador va una vez al
// mesón, no cinco. Un vale es de un solo destino, así que cada taller emite
// el suyo.
// ============================================================================

import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { PackageCheck, Loader2, Printer, Clock } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { useToast } from '@/contexts/toast-context'
import { errorMessage } from '@/lib/utils'
import {
  getSeguimientoRecursos, insumosAVale, type OTRecursoSeguimiento,
} from '@/lib/services/ot-recursos'

export function InsumosAprobadosCard() {
  const qc = useQueryClient()
  const toast = useToast()
  const [busy, setBusy] = useState<string | null>(null)

  const { data: todos = [] } = useQuery({
    queryKey: ['recursos-por-aprobar'],
    queryFn: getSeguimientoRecursos,
    staleTime: 20_000,
  })

  // Aprobados, del taller, y todavía sin papel.
  const porTaller = useMemo(() => {
    const listos = todos.filter(
      (r) => r.es_insumo_taller && r.estado === 'aprobado' && !r.ticket_id,
    )
    const mapa = new Map<string, { nombre: string; items: OTRecursoSeguimiento[] }>()
    for (const r of listos) {
      const k = r.ceco_id ?? 'sin-ceco'
      if (!mapa.has(k)) mapa.set(k, { nombre: r.ceco_nombre ?? 'Taller', items: [] })
      mapa.get(k)!.items.push(r)
    }
    return Array.from(mapa.entries()).map(([id, v]) => ({ id, ...v }))
  }, [todos])

  const emitir = async (cecoId: string, items: OTRecursoSeguimiento[]) => {
    setBusy(cecoId)
    try {
      const r = await insumosAVale({ recursoIds: items.map((i) => i.id) })
      toast.success(`Vale ${r.folio} emitido para ${r.ceco_nombre} — ${r.items} ítem(s).`)
      // El papel se abre solo: es lo que hay que llevar al mesón.
      window.open(`/vale/${r.ticket_id}`, '_blank')
      qc.invalidateQueries({ queryKey: ['recursos-por-aprobar'] })
      qc.invalidateQueries({ queryKey: ['bodega-tickets'] })
    } catch (e) {
      toast.error(errorMessage(e, 'No se pudo emitir el vale'))
    } finally { setBusy(null) }
  }

  if (porTaller.length === 0) return null

  return (
    <Card className="border-emerald-300 bg-emerald-50/50">
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-base text-emerald-900">
          <PackageCheck className="h-5 w-5 text-emerald-600" />
          Insumos del taller aprobados, esperando su vale
        </CardTitle>
        <p className="text-xs text-emerald-800">
          El jefe ya les dio el visto bueno. Sale un vale por taller para que el operador vaya una
          sola vez al mesón.
        </p>
      </CardHeader>
      <CardContent className="space-y-2">
        {porTaller.map((g) => (
          <div key={g.id} className="rounded-lg border border-emerald-200 bg-white p-3">
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div className="min-w-0">
                <p className="text-sm font-bold text-gray-900">{g.nombre}</p>
                <p className="text-xs text-gray-500">
                  {g.items.length} ítem{g.items.length !== 1 ? 's' : ''} aprobado
                  {g.items.length !== 1 ? 's' : ''}
                </p>
              </div>
              <Button size="sm" disabled={busy === g.id}
                      onClick={() => emitir(g.id, g.items)}
                      className="bg-emerald-600 font-bold hover:bg-emerald-700">
                {busy === g.id
                  ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />
                  : <Printer className="mr-1.5 h-4 w-4" />}
                Emitir el vale
              </Button>
            </div>

            <ul className="mt-2 space-y-1 border-t border-gray-100 pt-2">
              {g.items.map((i) => (
                <li key={i.id} className="flex items-center gap-2 text-xs">
                  <span className="min-w-0 flex-1 truncate text-gray-800">
                    {i.producto_nombre ?? i.descripcion}
                  </span>
                  {!i.producto_id && (
                    <span className="shrink-0 rounded bg-amber-100 px-1.5 text-[10px] font-semibold text-amber-800">
                      sin catálogo
                    </span>
                  )}
                  <span className="shrink-0 font-semibold tabular-nums text-gray-700">
                    {String(i.cantidad_aprobada ?? i.cantidad)} {i.unidad ?? 'un'}
                  </span>
                  {(i.dias_desde_solicitud ?? 0) >= 3 && (
                    <span className="inline-flex shrink-0 items-center gap-0.5 font-semibold text-red-600">
                      <Clock className="h-3 w-3" />{i.dias_desde_solicitud}d
                    </span>
                  )}
                </li>
              ))}
            </ul>
          </div>
        ))}
      </CardContent>
    </Card>
  )
}
