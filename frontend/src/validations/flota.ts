import { z } from 'zod'

/**
 * Esquemas Zod para formularios de Flota.
 * Cubre el cambio de estado diario (con fecha programable, FASE 5.2)
 * y la verificacion ready-to-rent.
 */

const estadoCodigoEnum = z.enum([
  'A', // Arrendado
  'D', // Disponible
  'H', // En Habilitacion
  'R', // En Recepcion
  'M', // Mantencion
  'T', // Taller (correctivo)
  'F', // Fuera de Servicio
  'V', // En Venta
  'U', // Uso Interno
  'L', // Leasing
])

const tipoOTAutoEnum = z.enum([
  'preventivo',
  'correctivo',
  'inspeccion',
  'lubricacion',
])

const prioridadOTEnum = z.enum([
  'emergencia',
  'urgente',
  'alta',
  'normal',
  'baja',
])

/**
 * Cambio de estado diario / programado (mig 30, 37 + FASE 5.2).
 * - p_fecha puede ser hoy o futura para usuarios normales.
 * - Solo administrador puede pasar fechas pasadas (la app filtra antes de
 *   llegar aqui; esta validacion hace defensa adicional pero no rechaza
 *   pasado para no acoplar al rol).
 * - Si nuevo_estado es 'D' (Disponible), exige verificacion vigente — pero
 *   esa logica vive en el trigger trg_validar_cambio_disponible (mig 44),
 *   no aqui.
 */
export const cambiarEstadoFlotaSchema = z
  .object({
    activo_id: z.string().uuid('Activo invalido'),
    fecha: z.string().min(10, 'Ingrese fecha (YYYY-MM-DD)'),
    nuevo_estado: estadoCodigoEnum,
    motivo: z
      .string()
      .trim()
      .min(5, 'Motivo es obligatorio (min 5 caracteres)')
      .max(500, 'Motivo muy largo (max 500)'),
    crear_ot: z.boolean().default(false),
    ot_tipo: tipoOTAutoEnum.optional().nullable(),
    ot_prioridad: prioridadOTEnum.default('normal'),
    ot_responsable_id: z.string().uuid().optional().nullable(),
    ot_descripcion: z.string().max(1000).optional().nullable(),
  })
  .refine(
    (v) =>
      !v.crear_ot || ['M', 'T', 'F'].includes(v.nuevo_estado),
    {
      message: 'Solo se puede crear OT automatica para estados M, T o F',
      path: ['crear_ot'],
    }
  )
  .refine(
    (v) =>
      !v.crear_ot ||
      (typeof v.ot_descripcion === 'string' && v.ot_descripcion.trim().length > 0),
    {
      message: 'Ingrese descripcion del trabajo cuando crea OT automatica',
      path: ['ot_descripcion'],
    }
  )

/**
 * Aprobacion de verificacion ready-to-rent (mig 45).
 * Doble firma: el aprobador no puede ser el mismo que ejecuta — eso lo
 * valida la BD via chk_doble_firma.
 */
export const aprobarVerificacionSchema = z
  .object({
    ot_id: z.string().uuid(),
    horometro_inicial: z
      .number({ invalid_type_error: 'Ingrese horometro inicial' })
      .nonnegative('Horometro no puede ser negativo'),
    horometro_final: z
      .number({ invalid_type_error: 'Ingrese horometro final' })
      .nonnegative('Horometro no puede ser negativo'),
    km_inicial: z.number().nonnegative().optional().nullable(),
    km_final: z.number().nonnegative().optional().nullable(),
    road_test_minutos: z
      .number({ invalid_type_error: 'Ingrese duracion del road test' })
      .int('Debe ser un numero entero')
      .min(5, 'Road test minimo 5 minutos'),
    road_test_observacion: z.string().max(1000).optional().nullable(),
    firma_tecnico_url: z.string().url('Falta firma del tecnico').optional().nullable(),
    firma_aprobador_url: z.string().url('Falta firma del aprobador').optional().nullable(),
    dias_vigencia: z.number().int().positive().default(3),
  })
  .refine((v) => v.horometro_final > v.horometro_inicial, {
    message: 'Horometro final debe ser mayor al inicial',
    path: ['horometro_final'],
  })

export type CambiarEstadoFlotaInput = z.infer<typeof cambiarEstadoFlotaSchema>
export type AprobarVerificacionInput = z.infer<typeof aprobarVerificacionSchema>
