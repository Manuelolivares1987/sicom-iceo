'use client'

import { useEffect, useMemo, useState } from 'react'
import { AlertTriangle, Wrench, ClipboardList, Info } from 'lucide-react'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { cn } from '@/lib/utils'
import {
  useActualizarEstadoManual,
  useEstadoDiarioActivoHoy,
  useConductores,
} from '@/hooks/use-flota'
import {
  ESTADO_DIARIO_LABELS,
  ESTADO_DIARIO_COLORS,
} from '@/lib/services/flota'

type EstadoCodigo = 'A' | 'D' | 'H' | 'R' | 'M' | 'T' | 'F' | 'V' | 'U' | 'L'
type TipoOT = 'preventivo' | 'correctivo' | 'inspeccion' | 'lubricacion'
type PrioridadOT = 'emergencia' | 'alta' | 'normal' | 'baja'

interface CambiarEstadoModalProps {
  open: boolean
  onClose: () => void
  activo: {
    id: string
    patente?: string | null
    codigo?: string | null
    nombre?: string | null
    estado_comercial?: string | null
    operacion?: string | null
    cliente_actual?: string | null
  } | null
}

const ESTADO_OPTIONS: Array<{
  value: EstadoCodigo
  label: string
  helpText: string
  group: 'productivo' | 'no_productivo' | 'mantencion'
}> = [
  { value: 'A', label: 'A — Arrendado',         group: 'productivo',     helpText: 'Equipo en faena del cliente generando ingreso' },
  { value: 'U', label: 'U — Uso Interno',       group: 'productivo',     helpText: 'En operación propia o contrato empresa' },
  { value: 'L', label: 'L — Leasing',           group: 'productivo',     helpText: 'Bajo contrato de leasing operativo' },
  { value: 'D', label: 'D — Disponible',        group: 'no_productivo',  helpText: 'Operativo y listo, sin arriendo asignado (pérdida comercial)' },
  { value: 'H', label: 'H — En Habilitación',   group: 'no_productivo',  helpText: 'En proceso de habilitación o reacondicionamiento' },
  { value: 'R', label: 'R — En Recepción',      group: 'no_productivo',  helpText: 'Recién ingresado al inventario' },
  { value: 'V', label: 'V — En Venta',          group: 'no_productivo',  helpText: 'Marcado para baja o venta' },
  { value: 'M', label: 'M — Mantención (>1 día)', group: 'mantencion',   helpText: 'Mantención programada o que dura más de un día' },
  { value: 'T', label: 'T — Taller (correctivo)', group: 'mantencion',   helpText: 'Reparación correctiva, falla operativa' },
  { value: 'F', label: 'F — Fuera de Servicio', group: 'mantencion',     helpText: 'Equipo no operativo: documentación vencida, falla mayor o restricción normativa' },
]

export function CambiarEstadoModal({ open, onClose, activo }: CambiarEstadoModalProps) {
  const today = new Date().toISOString().split('T')[0]

  // ── Cargar estado actual del día ──
  const { data: estadoHoy, isLoading: loadingEstadoHoy } = useEstadoDiarioActivoHoy(activo?.id)
  const { data: conductores } = useConductores(true)
  const mutation = useActualizarEstadoManual()

  // ── Form state ──
  const [nuevoEstado, setNuevoEstado] = useState<EstadoCodigo>('A')
  const [motivo, setMotivo] = useState('')
  const [crearOT, setCrearOT] = useState(false)
  const [otTipo, setOtTipo] = useState<TipoOT>('correctivo')
  const [otPrioridad, setOtPrioridad] = useState<PrioridadOT>('normal')
  const [otResponsableId, setOtResponsableId] = useState<string>('')
  const [otDescripcion, setOtDescripcion] = useState('')
  const [errorMsg, setErrorMsg] = useState<string | null>(null)

  // ── Reset al abrir ──
  useEffect(() => {
    if (open && activo) {
      const estadoActual = (estadoHoy?.estado_codigo as EstadoCodigo) || 'A'
      setNuevoEstado(estadoActual)
      setMotivo('')
      setCrearOT(false)
      setOtTipo('correctivo')
      setOtPrioridad('normal')
      setOtResponsableId('')
      setOtDescripcion('')
      setErrorMsg(null)
    }
  }, [open, activo?.id, estadoHoy?.estado_codigo])

  // ── Pre-marcar Crear OT cuando se selecciona M, T o F ──
  useEffect(() => {
    if (nuevoEstado === 'T') {
      setOtTipo('correctivo')
      setOtPrioridad('normal')
      setCrearOT(true)
    } else if (nuevoEstado === 'M') {
      setOtTipo('preventivo')
      setOtPrioridad('normal')
      setCrearOT(true)
    } else if (nuevoEstado === 'F') {
      setOtTipo('correctivo')
      setOtPrioridad('alta')
      setCrearOT(true)
    } else {
      setCrearOT(false)
    }
  }, [nuevoEstado])

  const requiereOT = nuevoEstado === 'M' || nuevoEstado === 'T' || nuevoEstado === 'F'

  const handleSubmit = async () => {
    setErrorMsg(null)
    if (!activo) return
    if (!motivo.trim()) {
      setErrorMsg('Debe ingresar un motivo del cambio')
      return
    }
    if (requiereOT && crearOT && !otDescripcion.trim()) {
      setErrorMsg('Debe ingresar una descripción para la OT')
      return
    }

    try {
      const result = await mutation.mutateAsync({
        activo_id: activo.id,
        fecha: today,
        nuevo_estado: nuevoEstado,
        motivo: motivo.trim(),
        crear_ot: crearOT && requiereOT,
        ot_tipo: requiereOT && crearOT ? otTipo : undefined,
        ot_prioridad: requiereOT && crearOT ? otPrioridad : undefined,
        ot_responsable_id: otResponsableId || undefined,
        ot_descripcion: otDescripcion.trim() || undefined,
      })

      if (result?.success) {
        onClose()
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Error al actualizar estado'
      setErrorMsg(message)
    }
  }

  const estadoActualBadge = useMemo(() => {
    const code = (estadoHoy?.estado_codigo as string) || null
    if (!code) return null
    return (
      <span
        className={cn(
          'inline-block rounded px-2 py-0.5 text-xs font-semibold',
          ESTADO_DIARIO_COLORS[code] || 'bg-gray-200 text-gray-700',
        )}
      >
        {code} — {ESTADO_DIARIO_LABELS[code]}
      </span>
    )
  }, [estadoHoy?.estado_codigo])

  if (!activo) return null

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Cambiar Estado del Equipo"
      description={`${activo.patente || activo.codigo} — ${activo.nombre || ''}`}
      className="sm:max-w-2xl"
    >
      <div className="space-y-5">
        {/* ── Contexto del activo ── */}
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-3 text-xs space-y-1">
          <div className="flex items-center justify-between">
            <span className="text-gray-500">Estado del día (hoy):</span>
            {loadingEstadoHoy ? (
              <Spinner className="h-3 w-3" />
            ) : (
              estadoActualBadge || <span className="text-gray-400">Sin registro</span>
            )}
          </div>
          {estadoHoy?.override_manual && (
            <div className="text-amber-700 flex items-center gap-1">
              <Info className="h-3 w-3" />
              Estado ya tiene un override manual de hoy
            </div>
          )}
          {activo.cliente_actual && (
            <div className="text-gray-600">
              <span className="text-gray-500">Cliente actual:</span> {activo.cliente_actual}
            </div>
          )}
          {activo.operacion && (
            <div className="text-gray-600">
              <span className="text-gray-500">Operación:</span> {activo.operacion}
            </div>
          )}
        </div>

        {/* ── Nuevo estado ── */}
        <Select
          label="Nuevo estado"
          value={nuevoEstado}
          onChange={(e) => setNuevoEstado(e.target.value as EstadoCodigo)}
          helperText={ESTADO_OPTIONS.find((o) => o.value === nuevoEstado)?.helpText}
        >
          <optgroup label="Productivo (genera ingreso)">
            {ESTADO_OPTIONS.filter((o) => o.group === 'productivo').map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </optgroup>
          <optgroup label="No productivo">
            {ESTADO_OPTIONS.filter((o) => o.group === 'no_productivo').map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </optgroup>
          <optgroup label="Mantención / Servicio">
            {ESTADO_OPTIONS.filter((o) => o.group === 'mantencion').map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </optgroup>
        </Select>

        {/* ── Motivo ── */}
        <div>
          <label className="mb-1.5 block text-sm font-medium text-gray-700">
            Motivo del cambio <span className="text-red-500">*</span>
          </label>
          <textarea
            className="min-h-[80px] w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            placeholder="Ej: Falla en bomba hidráulica detectada en faena CMP Romeral"
            value={motivo}
            onChange={(e) => setMotivo(e.target.value)}
            maxLength={500}
          />
          <div className="mt-1 text-xs text-gray-400 text-right">{motivo.length}/500</div>
        </div>

        {/* ── Sección Crear OT ── */}
        {requiereOT && (
          <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 space-y-3">
            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="crear-ot"
                checked={crearOT}
                onChange={(e) => setCrearOT(e.target.checked)}
                className="h-4 w-4 rounded border-amber-300 text-amber-600 focus:ring-amber-500"
              />
              <label htmlFor="crear-ot" className="text-sm font-medium text-amber-900 flex items-center gap-1">
                <Wrench className="h-4 w-4" />
                Crear orden de trabajo automáticamente
              </label>
            </div>

            {crearOT && (
              <div className="space-y-3 pl-6">
                <div className="grid grid-cols-2 gap-3">
                  <Select
                    label="Tipo OT"
                    value={otTipo}
                    onChange={(e) => setOtTipo(e.target.value as TipoOT)}
                  >
                    <option value="correctivo">Correctivo</option>
                    <option value="preventivo">Preventivo</option>
                    <option value="inspeccion">Inspección</option>
                    <option value="lubricacion">Lubricación</option>
                  </Select>
                  <Select
                    label="Prioridad"
                    value={otPrioridad}
                    onChange={(e) => setOtPrioridad(e.target.value as PrioridadOT)}
                  >
                    <option value="emergencia">Emergencia</option>
                    <option value="alta">Alta</option>
                    <option value="normal">Normal</option>
                    <option value="baja">Baja</option>
                  </Select>
                </div>

                <Select
                  label="Responsable (opcional)"
                  value={otResponsableId}
                  onChange={(e) => setOtResponsableId(e.target.value)}
                >
                  <option value="">Sin asignar</option>
                  {conductores?.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.nombre_completo} ({c.tipo_licencia})
                    </option>
                  ))}
                </Select>

                <div>
                  <label className="mb-1.5 block text-sm font-medium text-gray-700">
                    Descripción del trabajo <span className="text-red-500">*</span>
                  </label>
                  <textarea
                    className="min-h-[60px] w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
                    placeholder="Detalle del trabajo a realizar"
                    value={otDescripcion}
                    onChange={(e) => setOtDescripcion(e.target.value)}
                    maxLength={1000}
                  />
                </div>
              </div>
            )}
          </div>
        )}

        {/* ── Aviso si pasa a F estando arrendado ── */}
        {nuevoEstado === 'F' && activo.cliente_actual && (
          <div className="flex gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">
            <AlertTriangle className="h-5 w-5 shrink-0" />
            <div>
              <strong>Atención:</strong> al pasar este equipo a Fuera de Servicio
              estando con cliente, se generará automáticamente una <em>no
              conformidad</em> que afectará el indicador de Calidad de Servicio.
            </div>
          </div>
        )}

        {/* ── Resumen del impacto ── */}
        <div className="flex gap-2 rounded-lg border border-blue-200 bg-blue-50 p-3 text-xs text-blue-800">
          <ClipboardList className="h-4 w-4 shrink-0" />
          <div>
            Este cambio se registra como <strong>override manual</strong> del día
            de hoy. El sistema NO recalculará el estado automáticamente sobre
            este día. Para volver al cálculo automático, edite y vuelva a marcar
            el estado correcto.
          </div>
        </div>

        {errorMsg && (
          <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
            {errorMsg}
          </div>
        )}
      </div>

      <ModalFooter className="-mx-6 -mb-6 mt-6">
        <Button variant="ghost" onClick={onClose} disabled={mutation.isPending}>
          Cancelar
        </Button>
        <Button
          variant="primary"
          onClick={handleSubmit}
          loading={mutation.isPending}
        >
          Guardar cambio
        </Button>
      </ModalFooter>
    </Modal>
  )
}
