import { z } from 'zod'

/**
 * Esquemas Zod para formularios de Plantillas de Checklist.
 * (Modulo /dashboard/admin/checklist-templates).
 *
 * Regla operativa importante: una plantilla puede crearse vacia (0 items)
 * desde la UI de admin para luego agregar items, pero NO debe usarse en
 * operacion con 0 items. La validacion `checklistTemplateOperativoSchema`
 * exige al menos 1 item antes de marcar la plantilla como "lista para uso".
 */

const tipoOTEnum = z.enum([
  'preventivo',
  'correctivo',
  'inspeccion',
  'abastecimiento',
  'lubricacion',
  'inventario',
  'regularizacion',
  'verificacion_disponibilidad',
])

export const checklistItemSchema = z.object({
  orden: z.number().int().positive(),
  descripcion: z
    .string()
    .trim()
    .min(3, 'Descripcion del item obligatoria (min 3 caracteres)')
    .max(300, 'Descripcion muy larga (max 300)'),
  obligatorio: z.boolean().default(true),
  requiere_foto: z.boolean().default(false),
})

/**
 * Validacion para crear plantilla nueva (puede tener 0 items inicialmente).
 */
export const checklistTemplateCrearSchema = z.object({
  tipo_ot: tipoOTEnum,
  nombre: z
    .string()
    .trim()
    .min(3, 'Nombre de la plantilla obligatorio (min 3 caracteres)')
    .max(200, 'Nombre muy largo (max 200)'),
  descripcion: z.string().max(1000).optional().nullable(),
  items: z.array(checklistItemSchema).default([]),
  activo: z.boolean().default(true),
})

/**
 * Validacion para marcar una plantilla como operativa: exige al menos 1 item
 * y que los items tengan descripcion no vacia (defensa contra plantillas
 * "fantasma" que pasan a operacion sin contenido real).
 */
export const checklistTemplateOperativoSchema = checklistTemplateCrearSchema
  .extend({
    items: z
      .array(checklistItemSchema)
      .min(1, 'La plantilla debe tener al menos 1 item para ser operativa'),
  })
  .refine((v) => v.items.every((it) => it.descripcion.trim().length > 0), {
    message: 'Todos los items deben tener descripcion no vacia',
    path: ['items'],
  })

/**
 * Respuesta de un item de checklist en una OT en ejecucion.
 */
export const respuestaItemSchema = z.object({
  item_id: z.string().uuid(),
  resultado: z.enum(['ok', 'no_ok', 'na']).optional().nullable(),
  observacion: z.string().max(1000).optional().nullable(),
  foto_url: z.string().url().optional().nullable().or(z.literal('')),
})

export type ChecklistItem = z.infer<typeof checklistItemSchema>
export type ChecklistTemplateCrearInput = z.infer<typeof checklistTemplateCrearSchema>
export type ChecklistTemplateOperativoInput = z.infer<typeof checklistTemplateOperativoSchema>
export type RespuestaItemInput = z.infer<typeof respuestaItemSchema>
