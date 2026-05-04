import { z } from 'zod'

/**
 * Esquemas Zod para formularios de Administracion (gestion de usuarios).
 * Refleja los campos de la tabla `usuarios_perfil`.
 */

const rolEnum = z.enum([
  'administrador',
  'gerencia',
  'subgerente_operaciones',
  'jefe_operaciones',
  'jefe_mantenimiento',
  'supervisor',
  'planificador',
  'tecnico_mantenimiento',
  'bodeguero',
  'operador_abastecimiento',
  'comercial',
  'prevencionista',
  'colaborador',
  'auditor',
  'rrhh_incentivos',
])

export const editarUsuarioSchema = z.object({
  id: z.string().uuid(),
  rol: rolEnum,
  faena_id: z.string().uuid().optional().nullable().or(z.literal('')),
  cargo: z.string().trim().max(200).optional().nullable(),
  activo: z.boolean(),
})

export const crearUsuarioPerfilSchema = z.object({
  id: z.string().uuid('UUID del auth.users'),
  email: z.string().email('Email invalido'),
  nombre_completo: z
    .string()
    .trim()
    .min(2, 'Nombre completo obligatorio')
    .max(200),
  rut: z
    .string()
    .trim()
    .max(20)
    .regex(/^[0-9]{1,2}\.[0-9]{3}\.[0-9]{3}-[0-9kK]$/, 'RUT debe tener formato 12.345.678-9')
    .optional()
    .nullable()
    .or(z.literal('')),
  cargo: z.string().trim().max(200).optional().nullable(),
  rol: rolEnum,
  faena_id: z.string().uuid().optional().nullable(),
  telefono: z
    .string()
    .trim()
    .max(30)
    .optional()
    .nullable()
    .or(z.literal('')),
  activo: z.boolean().default(true),
})

export type EditarUsuarioInput = z.infer<typeof editarUsuarioSchema>
export type CrearUsuarioPerfilInput = z.infer<typeof crearUsuarioPerfilSchema>
