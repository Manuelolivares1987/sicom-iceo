import { z } from 'zod'

/**
 * Esquemas Zod para formularios de Prevencion (SUSPEL / RESPEL).
 * Modulo en piloto: validaciones minimas para evitar registros incompletos.
 */

export const suspelProductoSchema = z.object({
  codigo: z.string().trim().min(2, 'Codigo SUSPEL obligatorio').max(50),
  nombre: z.string().trim().min(3, 'Nombre del producto obligatorio').max(200),
  categoria: z.string().trim().max(100).optional().nullable(),
  unidad: z.string().trim().max(20).optional().nullable(),
  ficha_seguridad_url: z.string().url().optional().nullable().or(z.literal('')),
  bloqueante: z.boolean().default(false),
  observaciones: z.string().max(2000).optional().nullable(),
})

export const respelMovimientoSchema = z.object({
  fecha: z.string().min(10, 'Ingrese fecha (YYYY-MM-DD)'),
  tipo: z.enum(['generacion', 'retiro', 'transporte_interno', 'disposicion']),
  bodega_id: z.string().uuid('Seleccione una bodega'),
  producto_id: z.string().uuid('Seleccione un producto').optional().nullable(),
  cantidad: z
    .number({ invalid_type_error: 'Ingrese cantidad' })
    .positive('Cantidad debe ser mayor a 0'),
  documento_referencia: z.string().trim().max(200).optional().nullable(),
  guia_url: z.string().url().optional().nullable().or(z.literal('')),
  observaciones: z.string().max(2000).optional().nullable(),
})

export type SuspelProductoInput = z.infer<typeof suspelProductoSchema>
export type RespelMovimientoInput = z.infer<typeof respelMovimientoSchema>
