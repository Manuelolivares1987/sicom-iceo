import { z } from 'zod'

/**
 * Zod schemas para movimientos y varillaje de combustible.
 */

const destinoEnum = z.enum(['vehiculo_flota', 'equipo_externo', 'bidon', 'otro'])

export const movimientoIngresoSchema = z
  .object({
    estanque_id: z.string().uuid('Seleccione un estanque'),
    medidor_id: z.string().uuid('Seleccione un medidor'),
    lectura_inicial_lt: z
      .number({ invalid_type_error: 'Ingrese la lectura inicial' })
      .nonnegative('La lectura inicial no puede ser negativa'),
    lectura_final_lt: z
      .number({ invalid_type_error: 'Ingrese la lectura final' })
      .nonnegative('La lectura final no puede ser negativa'),
    foto_medidor_url: z.string().url('Debe adjuntar foto del medidor'),
    proveedor: z.string().min(2, 'Ingrese el proveedor').max(200),
    numero_factura: z.string().min(1, 'Ingrese el numero de factura'),
    costo_unitario_clp: z
      .number({ invalid_type_error: 'Ingrese el costo por litro' })
      .positive('El costo debe ser mayor a 0'),
    observaciones: z.string().optional().nullable(),
  })
  .refine((v) => v.lectura_final_lt > v.lectura_inicial_lt, {
    message: 'La lectura final debe ser mayor a la inicial',
    path: ['lectura_final_lt'],
  })

export const movimientoDespachoSchema = z
  .object({
    estanque_id: z.string().uuid('Seleccione un estanque'),
    medidor_id: z.string().uuid('Seleccione un medidor'),
    lectura_inicial_lt: z
      .number({ invalid_type_error: 'Ingrese la lectura inicial' })
      .nonnegative('La lectura inicial no puede ser negativa'),
    lectura_final_lt: z
      .number({ invalid_type_error: 'Ingrese la lectura final' })
      .nonnegative('La lectura final no puede ser negativa'),
    foto_medidor_url: z.string().url('Debe adjuntar foto del medidor'),
    destino_tipo: destinoEnum,
    vehiculo_activo_id: z.string().uuid().optional().nullable(),
    destino_descripcion: z.string().max(200).optional().nullable(),
    horometro_vehiculo: z.number().nonnegative().optional().nullable(),
    kilometraje_vehiculo: z.number().nonnegative().optional().nullable(),
    observaciones: z.string().optional().nullable(),
  })
  .refine((v) => v.lectura_final_lt > v.lectura_inicial_lt, {
    message: 'La lectura final debe ser mayor a la inicial',
    path: ['lectura_final_lt'],
  })
  .refine(
    (v) => v.destino_tipo !== 'vehiculo_flota' || !!v.vehiculo_activo_id,
    { message: 'Seleccione el vehiculo de flota', path: ['vehiculo_activo_id'] }
  )
  .refine(
    (v) =>
      v.destino_tipo === 'vehiculo_flota' ||
      (!!v.destino_descripcion && v.destino_descripcion.trim().length > 0),
    {
      message: 'Describa el destino (equipo, bidon, etc.)',
      path: ['destino_descripcion'],
    }
  )

export const varillajeSchema = z.object({
  estanque_id: z.string().uuid('Seleccione un estanque'),
  medicion_fisica_lt: z
    .number({ invalid_type_error: 'Ingrese la medicion' })
    .nonnegative('La medicion no puede ser negativa'),
  turno: z.enum(['dia', 'noche', 'unico']).optional().nullable(),
  generar_ajuste: z.boolean().default(false),
  foto_varilla_url: z.string().url().optional().nullable(),
  observaciones: z.string().optional().nullable(),
})

export type MovimientoIngresoInput = z.infer<typeof movimientoIngresoSchema>
export type MovimientoDespachoInput = z.infer<typeof movimientoDespachoSchema>
export type VarillajeInput = z.infer<typeof varillajeSchema>
