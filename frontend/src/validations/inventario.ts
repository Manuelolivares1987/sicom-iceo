import { z } from 'zod'

/**
 * Zod validation schemas for inventory movement forms.
 */

export const salidaSchema = z.object({
  bodega_id: z.string().uuid('Seleccione una bodega'),
  producto_id: z.string().uuid('Seleccione un producto'),
  cantidad: z.number().positive('La cantidad debe ser mayor a 0'),
  ot_id: z.string().uuid('Debe asociar una OT valida'),
  motivo: z.string().optional(),
})

export const entradaSchema = z.object({
  bodega_id: z.string().uuid('Seleccione una bodega'),
  producto_id: z.string().uuid('Seleccione un producto'),
  cantidad: z.number().positive('La cantidad debe ser mayor a 0'),
  costo_unitario: z.number().positive('El costo unitario debe ser mayor a 0'),
  documento_referencia: z
    .string()
    .min(1, 'El documento de referencia es obligatorio'),
  lote: z.string().optional(),
  fecha_vencimiento: z.string().optional(),
})

export const ajusteSchema = z.object({
  bodega_id: z.string().uuid('Seleccione una bodega'),
  producto_id: z.string().uuid('Seleccione un producto'),
  cantidad: z.number().refine((v) => v !== 0, 'La cantidad no puede ser 0'),
  motivo: z.string().min(1, 'El motivo es obligatorio para todo ajuste'),
  ot_id: z.string().uuid().optional(),
})

export type SalidaInput = z.infer<typeof salidaSchema>
export type EntradaInput = z.infer<typeof entradaSchema>
export type AjusteInput = z.infer<typeof ajusteSchema>
