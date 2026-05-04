import { z } from 'zod'

/**
 * Esquemas Zod para formularios del modulo Activos.
 * Reflejan los campos de la tabla `activos` (mig 02 + 14 + 25).
 *
 * Uso esperado: en cualquier formulario que cree/edite activos,
 * importar `activoSchema` y aplicarlo via zodResolver de RHF.
 */

const tipoActivoEnum = z.enum([
  'punto_fijo',
  'punto_movil',
  'surtidor',
  'dispensador',
  'estanque',
  'bomba',
  'manguera',
  'camion_cisterna',
  'lubrimovil',
  'equipo_bombeo',
  'herramienta_critica',
  'pistola_captura',
  'camioneta',
  'camion',
  'equipo_menor',
])

const criticidadEnum = z.enum(['critica', 'alta', 'media', 'baja'])

const estadoActivoEnum = z.enum([
  'operativo',
  'en_mantenimiento',
  'fuera_servicio',
  'dado_baja',
  'en_transito',
])

const anioActual = new Date().getFullYear()

export const activoCrearSchema = z.object({
  codigo: z
    .string()
    .trim()
    .min(2, 'Codigo del equipo es obligatorio (min 2 caracteres)')
    .max(50, 'Codigo no puede exceder 50 caracteres'),
  nombre: z
    .string()
    .trim()
    .min(2, 'Nombre del equipo es obligatorio')
    .max(200, 'Nombre no puede exceder 200 caracteres'),
  tipo: tipoActivoEnum,
  patente: z.string().trim().max(20).optional().nullable(),
  numero_serie: z.string().trim().max(100).optional().nullable(),
  marca_id: z.string().uuid('Seleccione una marca valida').optional().nullable(),
  modelo_id: z.string().uuid('Seleccione un modelo valido').optional().nullable(),
  anio_fabricacion: z
    .number({ invalid_type_error: 'Ingrese un anio valido' })
    .int('Anio debe ser entero')
    .min(1950, 'Anio fuera de rango')
    .max(anioActual + 1, `Anio no puede superar ${anioActual + 1}`)
    .optional()
    .nullable(),
  criticidad: criticidadEnum.default('media'),
  estado: estadoActivoEnum.default('operativo'),
  faena_id: z.string().uuid('Seleccione una faena valida').optional().nullable(),
  contrato_id: z.string().uuid().optional().nullable(),
  kilometraje_actual: z
    .number()
    .nonnegative('Kilometraje no puede ser negativo')
    .optional()
    .nullable(),
  horas_uso_actual: z
    .number()
    .nonnegative('Horas de uso no pueden ser negativas')
    .optional()
    .nullable(),
  ciclos_actual: z
    .number()
    .int('Ciclos debe ser entero')
    .nonnegative('Ciclos no pueden ser negativos')
    .optional()
    .nullable(),
  observaciones: z.string().max(2000).optional().nullable(),
})

export const activoEditarSchema = activoCrearSchema.partial()

export const actualizarMetricasSchema = z
  .object({
    activo_id: z.string().uuid(),
    kilometraje: z.number().nonnegative('Kilometraje no puede ser negativo').optional(),
    horas_uso: z.number().nonnegative('Horas de uso no pueden ser negativas').optional(),
    ciclos: z.number().int().nonnegative('Ciclos no pueden ser negativos').optional(),
  })
  .refine(
    (v) => v.kilometraje != null || v.horas_uso != null || v.ciclos != null,
    { message: 'Ingrese al menos un valor a actualizar' }
  )

export type ActivoCrearInput = z.infer<typeof activoCrearSchema>
export type ActivoEditarInput = z.infer<typeof activoEditarSchema>
export type ActualizarMetricasInput = z.infer<typeof actualizarMetricasSchema>
