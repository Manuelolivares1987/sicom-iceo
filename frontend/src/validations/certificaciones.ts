import { z } from 'zod'

/**
 * Esquemas Zod para formularios del modulo Cumplimiento / Certificaciones.
 * Refleja los campos de la tabla `certificaciones`.
 */

const tipoCertEnum = z.enum([
  'SEC',
  'SEREMI',
  'SISS',
  'Revisión Técnica',
  'SOAP',
  'Calibración',
  'Licencia',
  'Otro',
])

const estadoCertEnum = z.enum(['vigente', 'por_vencer', 'vencido'])

export const certificacionSchema = z
  .object({
    id: z.string().uuid().optional(),
    activo_id: z.string().uuid('Seleccione un activo valido'),
    tipo: tipoCertEnum,
    numero_certificado: z
      .string()
      .trim()
      .max(100, 'Numero de certificado muy largo')
      .optional()
      .nullable(),
    entidad_certificadora: z
      .string()
      .trim()
      .max(200)
      .optional()
      .nullable(),
    fecha_emision: z
      .string()
      .min(10, 'Ingrese fecha de emision (YYYY-MM-DD)'),
    fecha_vencimiento: z
      .string()
      .min(10, 'Ingrese fecha de vencimiento (YYYY-MM-DD)'),
    estado: estadoCertEnum.optional(),
    bloqueante: z.boolean().default(false),
    archivo_url: z.string().url('Suba un archivo o deje vacio').optional().nullable().or(z.literal('')),
    notas: z.string().max(2000).optional().nullable(),
  })
  .refine(
    (v) => new Date(v.fecha_vencimiento) >= new Date(v.fecha_emision),
    {
      message: 'La fecha de vencimiento debe ser igual o posterior a la emision',
      path: ['fecha_vencimiento'],
    }
  )

export type CertificacionInput = z.infer<typeof certificacionSchema>
