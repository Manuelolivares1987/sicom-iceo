import { z } from 'zod'

/**
 * Esquemas Zod para formularios del modulo Mantenimiento.
 * Cubre planes PM y generacion de OT desde plan.
 */

export const planMantenimientoSchema = z
  .object({
    activo_id: z.string().uuid('Seleccione un activo valido'),
    pauta_fabricante_id: z.string().uuid('Seleccione una pauta valida'),
    activo_plan: z.boolean().default(true),
    proxima_ejecucion_fecha: z.string().optional().nullable(),
    proxima_ejecucion_km: z.number().nonnegative().optional().nullable(),
    proxima_ejecucion_horas: z.number().nonnegative().optional().nullable(),
    proxima_ejecucion_ciclos: z
      .number()
      .int()
      .nonnegative()
      .optional()
      .nullable(),
    observaciones: z.string().max(2000).optional().nullable(),
  })
  .refine(
    (v) =>
      !!v.proxima_ejecucion_fecha ||
      v.proxima_ejecucion_km != null ||
      v.proxima_ejecucion_horas != null ||
      v.proxima_ejecucion_ciclos != null,
    {
      message: 'Defina al menos una condicion de proxima ejecucion (fecha/km/horas/ciclos)',
      path: ['proxima_ejecucion_fecha'],
    }
  )

export const generarOTDesdePlanSchema = z.object({
  plan_mantenimiento_id: z.string().uuid('Plan invalido'),
  fecha_programada: z
    .string()
    .min(8, 'Ingrese fecha programada (YYYY-MM-DD)'),
  responsable_id: z.string().uuid().optional().nullable(),
  prioridad: z
    .enum(['emergencia', 'urgente', 'alta', 'normal', 'baja'])
    .default('normal'),
  observaciones: z.string().max(1000).optional().nullable(),
})

export const pautaFabricanteSchema = z
  .object({
    nombre: z.string().trim().min(3, 'Nombre obligatorio').max(200),
    tipo_plan: z.enum(['preventivo', 'inspeccion', 'lubricacion']).default('preventivo'),
    frecuencia_dias: z.number().int().positive().optional().nullable(),
    frecuencia_km: z.number().int().positive().optional().nullable(),
    frecuencia_horas: z.number().int().positive().optional().nullable(),
    frecuencia_ciclos: z.number().int().positive().optional().nullable(),
    items_checklist: z.array(z.any()).default([]),
    materiales_estimados: z.array(z.any()).default([]),
  })
  .refine(
    (v) =>
      !!v.frecuencia_dias ||
      !!v.frecuencia_km ||
      !!v.frecuencia_horas ||
      !!v.frecuencia_ciclos,
    {
      message: 'Defina al menos una frecuencia (dias/km/horas/ciclos)',
      path: ['frecuencia_dias'],
    }
  )

export type PlanMantenimientoInput = z.infer<typeof planMantenimientoSchema>
export type GenerarOTDesdePlanInput = z.infer<typeof generarOTDesdePlanSchema>
export type PautaFabricanteInput = z.infer<typeof pautaFabricanteSchema>
