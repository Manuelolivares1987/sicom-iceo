'use client'

// ============================================================================
// Ambiental Franke (MIG554): retiro semanal de residuos + insumos del mes
// ----------------------------------------------------------------------------
// El supervisor llena la tabla completa de una vez (el 0 también se informa,
// como exige el formato del mandante). Reenviar la misma fecha corrige.
// ============================================================================

import { useMemo, useState } from 'react'
import { Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Select } from '@/components/ui/select'
import { useToast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'
import {
  useAmbientalConceptos, useFaenasPrevencion, useUpsertAmbiental,
} from '@/hooks/use-prevencion-reportabilidad'

function hoyISO() { return new Date().toISOString().slice(0, 10) }
function mesActualISO() { return hoyISO().slice(0, 7) }

export function AmbientalForm({ onGuardado, onCancelar }: {
  onGuardado?: () => void
  onCancelar?: () => void
}) {
  const toast = useToast()
  const { data: conceptos } = useAmbientalConceptos()
  const { data: faenas } = useFaenasPrevencion()
  const guardar = useUpsertAmbiental()

  // Solo las faenas que tienen catálogo ambiental (hoy: Franke).
  const faenasConAmbiental = useMemo(() => {
    const ids = new Set((conceptos ?? []).map((c) => c.faena_id))
    return (faenas ?? []).filter((f: any) => ids.has(f.id))
  }, [conceptos, faenas])

  const [faenaId, setFaenaId] = useState('')
  const faenaEfectiva = faenaId || (faenasConAmbiental[0]?.id ?? '')
  const [modo, setModo] = useState<'semanal' | 'mensual'>('semanal')
  const [fecha, setFecha] = useState(hoyISO())
  const [periodo, setPeriodo] = useState(mesActualISO())
  const [valores, setValores] = useState<Record<string, string>>({})

  const lista = useMemo(
    () => (conceptos ?? []).filter((c) =>
      c.faena_id === faenaEfectiva &&
      (modo === 'semanal' ? c.grupo === 'residuo_retiro' : c.grupo === 'insumo')),
    [conceptos, faenaEfectiva, modo],
  )

  const confirmar = async () => {
    if (!faenaEfectiva) return toast.error('No hay faena con reporte ambiental configurado')
    // El formato exige la tabla completa: lo no digitado va como 0.
    const fechaFila = modo === 'semanal' ? fecha : `${periodo}-01`
    const filas = lista.map((c) => ({
      concepto_id: c.id,
      fecha: fechaFila,
      cantidad: Number(String(valores[c.id] ?? '0').replace(',', '.')) || 0,
    }))
    if (filas.some((f) => f.cantidad < 0 || Number.isNaN(f.cantidad))) {
      return toast.error('Revise las cantidades: solo números desde 0')
    }
    try {
      await guardar.mutateAsync(filas)
      toast.success(modo === 'semanal'
        ? 'Retiro de residuos guardado'
        : 'Insumos del mes guardados')
      setValores({})
      onGuardado?.()
    } catch (e: any) {
      toast.error(e?.message ?? 'No se pudo guardar')
    }
  }

  return (
    <div className="space-y-3">
      {faenasConAmbiental.length > 1 && (
        <Select label="Faena" value={faenaEfectiva}
                onChange={(e) => setFaenaId(e.target.value)}
                options={faenasConAmbiental.map((f: any) => ({ value: f.id, label: f.nombre }))} />
      )}

      <div className="flex gap-2">
        {([['semanal', 'Retiro semanal de residuos'], ['mensual', 'Insumos del mes']] as const)
          .map(([m, label]) => (
            <button key={m} type="button" onClick={() => setModo(m)}
                    className={cn(
                      'flex-1 rounded-lg border-2 px-3 py-2 text-sm font-bold transition-colors',
                      modo === m ? 'border-gray-900 bg-gray-900 text-white'
                                 : 'border-gray-300 bg-white text-gray-700',
                    )}>
              {label}
            </button>
          ))}
      </div>

      {modo === 'semanal' ? (
        <Input label="Fecha del retiro" type="date" value={fecha} max={hoyISO()}
               onChange={(e) => setFecha(e.target.value)} />
      ) : (
        <Input label="Mes informado" type="month" value={periodo} max={mesActualISO()}
               onChange={(e) => e.target.value && setPeriodo(e.target.value)} />
      )}

      <div className="space-y-1.5">
        {lista.map((c) => (
          <div key={c.id} className="flex items-center gap-2">
            <span className="min-w-0 flex-1 text-sm text-gray-800">{c.nombre}</span>
            <input
              type="number" min={0} step="0.1" inputMode="decimal" placeholder="0"
              className="w-24 rounded-lg border border-gray-300 px-2 py-1.5 text-right text-sm"
              value={valores[c.id] ?? ''}
              onChange={(e) => setValores((p) => ({ ...p, [c.id]: e.target.value }))}
            />
            <span className="w-12 shrink-0 text-xs text-gray-500">{c.unidad}</span>
          </div>
        ))}
        {lista.length === 0 && (
          <p className="py-4 text-center text-sm text-gray-500">
            Esta faena no tiene reporte ambiental configurado.
          </p>
        )}
      </div>

      <p className="text-xs text-gray-400">
        Lo que quede vacío se informa como 0 (el formato del mandante lo exige).
        Si se equivocó, vuelva a enviar la misma fecha: se corrige solo.
      </p>

      <div className="flex gap-2">
        <Button className="flex-1" onClick={confirmar}
                disabled={guardar.isPending || lista.length === 0}>
          {guardar.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
          Guardar
        </Button>
        {onCancelar && <Button variant="outline" onClick={onCancelar}>Cancelar</Button>}
      </div>
    </div>
  )
}
