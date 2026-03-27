'use client'

import { useState, useEffect } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useCreateOT } from '@/hooks/use-ordenes-trabajo'
import { useAuth } from '@/contexts/auth-context'
import { getActivos } from '@/lib/services/activos'
import { supabase } from '@/lib/supabase'
import type { TipoOT, Prioridad } from '@/types/database'

// ---------------------------------------------------------------------------
// Zod schema
// ---------------------------------------------------------------------------
const crearOTSchema = z.object({
  tipo: z.enum([
    'inspeccion',
    'preventivo',
    'correctivo',
    'abastecimiento',
    'lubricacion',
    'inventario',
    'regularizacion',
  ]),
  activo_id: z.string().min(1, 'Seleccione un activo'),
  prioridad: z.enum(['emergencia', 'urgente', 'alta', 'normal', 'baja']),
  fecha_programada: z.string().optional(),
  responsable_id: z.string().optional(),
  observaciones: z.string().optional(),
})

type CrearOTForm = z.infer<typeof crearOTSchema>

// ---------------------------------------------------------------------------
// Option lists
// ---------------------------------------------------------------------------
const tipoOptions: { value: TipoOT; label: string }[] = [
  { value: 'inspeccion', label: 'Inspección' },
  { value: 'preventivo', label: 'Preventivo' },
  { value: 'correctivo', label: 'Correctivo' },
  { value: 'abastecimiento', label: 'Abastecimiento' },
  { value: 'lubricacion', label: 'Lubricación' },
  { value: 'inventario', label: 'Inventario' },
  { value: 'regularizacion', label: 'Regularización' },
]

const prioridadOptions: { value: Prioridad; label: string }[] = [
  { value: 'emergencia', label: 'Emergencia' },
  { value: 'urgente', label: 'Urgente' },
  { value: 'alta', label: 'Alta' },
  { value: 'normal', label: 'Normal' },
  { value: 'baja', label: 'Baja' },
]

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------
export interface CrearOTModalProps {
  open: boolean
  onClose: () => void
  onCreated: (ot: any) => void
  contratoId: string
  faenaId?: string
  defaultFechaProgramada?: string
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------
export function CrearOTModal({
  open,
  onClose,
  onCreated,
  contratoId,
  faenaId,
  defaultFechaProgramada,
}: CrearOTModalProps) {
  const { user } = useAuth()
  const createOT = useCreateOT()

  // Dynamic option lists loaded from Supabase
  const [activos, setActivos] = useState<{ value: string; label: string; faena_id?: string }[]>([])
  const [responsables, setResponsables] = useState<{ value: string; label: string }[]>([])
  const [loadingData, setLoadingData] = useState(false)
  const [rpcError, setRpcError] = useState<string | null>(null)

  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<CrearOTForm>({
    resolver: zodResolver(crearOTSchema),
    defaultValues: {
      tipo: 'preventivo',
      prioridad: 'normal',
      activo_id: '',
      fecha_programada: defaultFechaProgramada || '',
      responsable_id: '',
      observaciones: '',
    },
  })

  // Reset form with default date when modal opens
  useEffect(() => {
    if (open) {
      reset({
        tipo: 'preventivo',
        prioridad: 'normal',
        activo_id: '',
        fecha_programada: defaultFechaProgramada || '',
        responsable_id: '',
        observaciones: '',
      })
    }
  }, [open, defaultFechaProgramada, reset])

  // Load activos and responsables when modal opens
  useEffect(() => {
    if (!open) return

    setLoadingData(true)
    setRpcError(null)

    Promise.all([
      getActivos(faenaId ? { faena_id: faenaId } : undefined),
      supabase
        .from('usuarios_perfil')
        .select('id, nombre_completo, cargo')
        .eq('activo', true)
        .order('nombre_completo'),
    ])
      .then(([activosRes, responsablesRes]) => {
        if (activosRes.data) {
          setActivos(
            activosRes.data.map((a: any) => ({
              value: a.id,
              label: `${a.codigo} — ${a.nombre || ''}`,
              faena_id: a.faena_id,
            }))
          )
        }
        if (responsablesRes.data) {
          setResponsables(
            responsablesRes.data.map((r: any) => ({
              value: r.id,
              label: `${r.nombre_completo}${r.cargo ? ` (${r.cargo})` : ''}`,
            }))
          )
        }
      })
      .finally(() => setLoadingData(false))
  }, [open, faenaId])

  function onSubmit(values: CrearOTForm) {
    setRpcError(null)

    // Get faena from selected activo if not provided
    const selectedActivo = activos.find(a => a.value === values.activo_id)
    const resolvedFaenaId = faenaId || selectedActivo?.faena_id || ''

    createOT.mutate(
      {
        tipo: values.tipo as TipoOT,
        contrato_id: contratoId,
        faena_id: resolvedFaenaId,
        activo_id: values.activo_id,
        prioridad: values.prioridad as Prioridad,
        fecha_programada: values.fecha_programada || undefined,
        responsable_id: values.responsable_id || undefined,
        usuario_id: user?.id || undefined,
      },
      {
        onSuccess: (data) => {
          reset()
          onCreated(data)
        },
        onError: (err: any) => {
          setRpcError(err?.message || 'Error al crear la orden de trabajo')
        },
      }
    )
  }

  function handleClose() {
    reset()
    setRpcError(null)
    onClose()
  }

  return (
    <Modal open={open} onClose={handleClose} title="Nueva Orden de Trabajo">
      {loadingData ? (
        <div className="flex justify-center py-12">
          <Spinner size="md" className="text-pillado-green-500" />
        </div>
      ) : (
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {/* Tipo */}
          <div>
            <label className="mb-1 block text-sm font-medium text-gray-700">Tipo de OT</label>
            <select
              {...register('tipo')}
              className="h-10 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            >
              {tipoOptions.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
            {errors.tipo && (
              <p className="mt-1 text-xs text-red-500">{errors.tipo.message}</p>
            )}
          </div>

          {/* Activo */}
          <div>
            <label className="mb-1 block text-sm font-medium text-gray-700">Activo</label>
            <select
              {...register('activo_id')}
              className="h-10 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            >
              <option value="">Seleccione un activo...</option>
              {activos.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
            {errors.activo_id && (
              <p className="mt-1 text-xs text-red-500">{errors.activo_id.message}</p>
            )}
          </div>

          {/* Prioridad */}
          <div>
            <label className="mb-1 block text-sm font-medium text-gray-700">Prioridad</label>
            <select
              {...register('prioridad')}
              className="h-10 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            >
              {prioridadOptions.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
            {errors.prioridad && (
              <p className="mt-1 text-xs text-red-500">{errors.prioridad.message}</p>
            )}
          </div>

          {/* Fecha programada */}
          <div>
            <label className="mb-1 block text-sm font-medium text-gray-700">
              Fecha Programada
            </label>
            <input
              type="date"
              {...register('fecha_programada')}
              className="h-10 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            />
            {errors.fecha_programada && (
              <p className="mt-1 text-xs text-red-500">{errors.fecha_programada.message}</p>
            )}
          </div>

          {/* Responsable */}
          <div>
            <label className="mb-1 block text-sm font-medium text-gray-700">Responsable</label>
            <select
              {...register('responsable_id')}
              className="h-10 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            >
              <option value="">Seleccione un responsable...</option>
              {responsables.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
            {errors.responsable_id && (
              <p className="mt-1 text-xs text-red-500">{errors.responsable_id.message}</p>
            )}
          </div>

          {/* Observaciones */}
          <div>
            <label className="mb-1 block text-sm font-medium text-gray-700">
              Observaciones (opcional)
            </label>
            <textarea
              {...register('observaciones')}
              rows={3}
              placeholder="Observaciones adicionales..."
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            />
          </div>

          {/* RPC error */}
          {rpcError && (
            <div className="rounded-lg bg-red-50 p-3 text-sm text-red-700">{rpcError}</div>
          )}

          {/* Footer */}
          <ModalFooter className="px-0">
            <Button type="button" variant="secondary" onClick={handleClose}>
              Cancelar
            </Button>
            <Button type="submit" variant="primary" disabled={createOT.isPending}>
              {createOT.isPending && <Spinner size="sm" className="mr-1" />}
              Crear OT
            </Button>
          </ModalFooter>
        </form>
      )}
    </Modal>
  )
}
