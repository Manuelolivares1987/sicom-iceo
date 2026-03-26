import { z } from 'zod'

/**
 * Zod validation schemas for OT (Orden de Trabajo) forms.
 */

export const crearOTSchema = z.object({
  tipo: z.enum([
    'inspeccion',
    'preventivo',
    'correctivo',
    'abastecimiento',
    'lubricacion',
    'inventario',
    'regularizacion',
  ]),
  contrato_id: z.string().uuid('Seleccione un contrato valido'),
  faena_id: z.string().uuid('Seleccione una faena valida'),
  activo_id: z.string().uuid('Seleccione un activo valido'),
  prioridad: z
    .enum(['emergencia', 'urgente', 'alta', 'normal', 'baja'])
    .default('normal'),
  fecha_programada: z.string().optional(),
  responsable_id: z.string().uuid().optional(),
})

export const noEjecucionSchema = z.object({
  causa: z.string().min(1, 'La causa de no ejecucion es obligatoria'),
  detalle: z.string().optional(),
})

export const finalizarSchema = z.object({
  observaciones: z.string().optional(),
})

export const cerrarSupervisorSchema = z.object({
  observaciones: z.string().optional(),
})

export type CrearOTInput = z.infer<typeof crearOTSchema>
export type NoEjecucionInput = z.infer<typeof noEjecucionSchema>
export type FinalizarInput = z.infer<typeof finalizarSchema>
export type CerrarSupervisorInput = z.infer<typeof cerrarSupervisorSchema>
