import { z } from 'zod'

/**
 * Esquemas Zod para formularios de Contratos.
 * Hoy el modulo es solo lectura desde frontend; este schema queda listo
 * para cuando se incorpore CRUD de contratos.
 */

const estadoContratoEnum = z.enum(['activo', 'pausado', 'finalizado'])

export const contratoSchema = z
  .object({
    codigo: z.string().trim().min(2, 'Codigo del contrato obligatorio').max(50),
    cliente: z.string().trim().min(2, 'Nombre del cliente obligatorio').max(200),
    region: z.string().trim().max(100).optional().nullable(),
    fecha_inicio: z.string().min(10, 'Ingrese fecha de inicio (YYYY-MM-DD)'),
    fecha_fin: z.string().min(10, 'Ingrese fecha de fin (YYYY-MM-DD)'),
    estado: estadoContratoEnum.default('activo'),
    monto_mensual_clp: z
      .number()
      .nonnegative('Monto no puede ser negativo')
      .optional()
      .nullable(),
    observaciones: z.string().max(5000).optional().nullable(),
  })
  .refine((v) => new Date(v.fecha_fin) > new Date(v.fecha_inicio), {
    message: 'La fecha de fin debe ser posterior a la de inicio',
    path: ['fecha_fin'],
  })

export type ContratoInput = z.infer<typeof contratoSchema>
