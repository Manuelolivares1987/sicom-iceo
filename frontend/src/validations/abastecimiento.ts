import { z } from 'zod'

/**
 * Esquemas Zod para formularios de Abastecimiento (rutas + despachos).
 */

export const rutaDespachoSchema = z.object({
  codigo: z.string().trim().min(2, 'Codigo de ruta obligatorio').max(50),
  nombre: z.string().trim().min(3, 'Nombre de ruta obligatorio').max(200),
  fecha_programada: z
    .string()
    .min(10, 'Ingrese fecha programada (YYYY-MM-DD)'),
  conductor_id: z.string().uuid().optional().nullable(),
  vehiculo_id: z.string().uuid().optional().nullable(),
  faena_id: z.string().uuid('Seleccione una faena valida'),
  observaciones: z.string().max(2000).optional().nullable(),
})

export const updateRutaEstadoSchema = z.object({
  ruta_id: z.string().uuid(),
  nuevo_estado: z.enum([
    'programada',
    'en_ejecucion',
    'completada',
    'incompleta',
  ]),
  observaciones: z.string().max(2000).optional().nullable(),
})

export const abastecimientoSchema = z.object({
  ruta_id: z.string().uuid('Seleccione una ruta'),
  punto_id: z.string().uuid('Seleccione un punto de despacho'),
  producto_id: z.string().uuid('Seleccione un producto'),
  cantidad: z
    .number({ invalid_type_error: 'Ingrese cantidad' })
    .positive('Cantidad debe ser mayor a 0'),
  observaciones: z.string().max(1000).optional().nullable(),
})

export type RutaDespachoInput = z.infer<typeof rutaDespachoSchema>
export type UpdateRutaEstadoInput = z.infer<typeof updateRutaEstadoSchema>
export type AbastecimientoInput = z.infer<typeof abastecimientoSchema>
