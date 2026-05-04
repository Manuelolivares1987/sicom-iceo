import { z } from 'zod'

/**
 * Esquemas Zod para Bodega (FASE 5.3): OC, recepciones parciales,
 * salidas con CECO + OT + persona, proveedores, centros de costo.
 *
 * Estos schemas estan alineados con la migracion 55_*.sql (no destructiva).
 * Listos para usar cuando se implementen formularios o se consuman desde
 * un cliente HTTP/RPC.
 */

// ── Proveedor ────────────────────────────────────────────

const tipoProveedorEnum = z.enum([
  'combustible',
  'repuestos',
  'servicios',
  'lubricantes',
  'filtros',
  'otros',
])

export const proveedorSchema = z.object({
  codigo: z.string().trim().min(2).max(30),
  nombre: z.string().trim().min(2, 'Nombre del proveedor obligatorio').max(200),
  rut: z.string().trim().max(20).optional().nullable(),
  tipo: tipoProveedorEnum.default('otros'),
  contacto: z.string().trim().max(200).optional().nullable(),
  telefono: z.string().trim().max(30).optional().nullable(),
  email: z.string().email('Email invalido').optional().nullable().or(z.literal('')),
  activo: z.boolean().default(true),
})

// ── Centro de costo (CECO) ───────────────────────────────

export const centroCostoSchema = z.object({
  codigo: z.string().trim().min(2).max(30),
  nombre: z.string().trim().min(2, 'Nombre del CECO obligatorio').max(200),
  area: z.string().trim().max(100).optional().nullable(),
  contrato_id: z.string().uuid().optional().nullable(),
  faena_id: z.string().uuid().optional().nullable(),
  activo: z.boolean().default(true),
})

// ── Orden de Compra ──────────────────────────────────────

export const ocItemSchema = z.object({
  producto_id: z.string().uuid().optional().nullable(),
  descripcion: z.string().trim().min(2, 'Descripcion obligatoria').max(500),
  unidad: z.string().trim().max(20).default('unidad'),
  cantidad_comprada: z
    .number({ invalid_type_error: 'Ingrese cantidad' })
    .positive('Cantidad debe ser mayor a 0'),
  precio_unitario_clp: z.number().nonnegative('Precio no puede ser negativo').default(0),
})

export const ocSchema = z.object({
  numero_oc: z.string().trim().min(2, 'Numero de OC obligatorio').max(40),
  proveedor_id: z.string().uuid('Seleccione proveedor'),
  fecha_oc: z.string().min(10, 'Ingrese fecha (YYYY-MM-DD)'),
  observacion: z.string().max(2000).optional().nullable(),
  items: z.array(ocItemSchema).min(1, 'La OC debe tener al menos 1 item'),
})

// ── Recepcion de bodega (parcial contra OC) ──────────────

const tipoDocumentoProveedorEnum = z.enum([
  'guia',
  'factura',
  'vale',
  'boleta',
  'otro',
])

export const recepcionItemSchema = z.object({
  oc_item_id: z.string().uuid().optional().nullable(),
  producto_id: z.string().uuid('Seleccione producto'),
  cantidad: z
    .number({ invalid_type_error: 'Ingrese cantidad recibida' })
    .positive('Cantidad debe ser mayor a 0'),
  unidad: z.string().trim().max(20).default('unidad'),
  costo_unitario: z.number().nonnegative().default(0),
  lote: z.string().trim().max(60).optional().nullable(),
  vencimiento: z.string().optional().nullable().or(z.literal('')),
  observacion: z.string().max(500).optional().nullable(),
})

export const recepcionBodegaSchema = z.object({
  orden_compra_id: z.string().uuid().optional().nullable(),
  proveedor_id: z.string().uuid('Seleccione proveedor'),
  bodega_id: z.string().uuid('Seleccione bodega'),
  documento_proveedor_tipo: tipoDocumentoProveedorEnum,
  documento_proveedor_numero: z
    .string()
    .trim()
    .min(1, 'Ingrese numero de documento del proveedor')
    .max(60),
  evidencia_url: z.string().url('Suba evidencia (foto/PDF guia)'),
  observacion: z.string().max(2000).optional().nullable(),
  permite_sobrecantidad: z.boolean().default(false),
  items: z.array(recepcionItemSchema).min(1, 'Debe recibir al menos 1 item'),
})

// ── Salida de bodega (con CECO + persona + OT) ───────────

const tipoSalidaBodegaEnum = z.enum([
  'ot',
  'persona',
  'ceco',
  'venta',
  'ajuste_autorizado',
])

export const salidaItemSchema = z.object({
  producto_id: z.string().uuid('Seleccione producto'),
  cantidad: z.number().positive('Cantidad debe ser mayor a 0'),
  unidad: z.string().trim().max(20).default('unidad'),
  lote: z.string().trim().max(60).optional().nullable(),
  observacion: z.string().max(500).optional().nullable(),
})

// Base sin refines (extensible). Las reglas cruzadas se aplican abajo via refine().
const salidaBodegaBaseSchema = z.object({
  tipo_salida: tipoSalidaBodegaEnum,
  bodega_id: z.string().uuid('Seleccione bodega'),
  ceco_id: z.string().uuid('CECO es obligatorio para toda salida'),
  ot_id: z.string().uuid().optional().nullable(),
  entregado_a: z.string().trim().max(200).optional().nullable(),
  entregado_a_perfil_id: z.string().uuid().optional().nullable(),
  autorizado_por: z.string().uuid().optional().nullable(),
  motivo: z.string().trim().min(5, 'Motivo obligatorio (min 5 caracteres)').max(2000),
  evidencia_url: z.string().url().optional().nullable().or(z.literal('')),
  observacion: z.string().max(2000).optional().nullable(),
  items: z.array(salidaItemSchema).min(1, 'La salida debe tener al menos 1 item'),
})

export const salidaBodegaSchema = salidaBodegaBaseSchema
  .refine((v) => v.tipo_salida !== 'ot' || !!v.ot_id, {
    message: 'Salida tipo OT requiere seleccionar la OT',
    path: ['ot_id'],
  })
  .refine(
    (v) =>
      v.tipo_salida !== 'persona' ||
      !!v.entregado_a ||
      !!v.entregado_a_perfil_id,
    {
      message: 'Salida tipo persona requiere "Entregado a"',
      path: ['entregado_a'],
    }
  )

export type ProveedorInput = z.infer<typeof proveedorSchema>
export type CentroCostoInput = z.infer<typeof centroCostoSchema>
export type OCItemInput = z.infer<typeof ocItemSchema>
export type OCInput = z.infer<typeof ocSchema>
export type RecepcionBodegaInput = z.infer<typeof recepcionBodegaSchema>
export type SalidaBodegaInput = z.infer<typeof salidaBodegaSchema>


// ============================================================================
// FASE 5.4-A — FIFO: validaciones especificas de costeo y override
// ============================================================================

/**
 * Recepcion FIFO con regla adicional:
 * - Si el costo unitario recibido difiere de la OC, exige override + justificacion.
 * - Solo administrador puede pasar `permite_precio_distinto=true`.
 */
export const recepcionFifoSchema = recepcionBodegaSchema
  .extend({
    permite_precio_distinto: z.boolean().default(false),
    justificacion_override: z.string().trim().optional().nullable(),
  })
  .refine(
    (v) =>
      !(v.permite_sobrecantidad || v.permite_precio_distinto) ||
      (typeof v.justificacion_override === 'string' &&
        v.justificacion_override.trim().length >= 10),
    {
      message:
        'Override (sobrecantidad o precio distinto) requiere justificacion administrador (min 10 caracteres)',
      path: ['justificacion_override'],
    }
  )

/**
 * Validacion de salida FIFO: el costo NO se acepta del cliente (lo asigna
 * el sistema). Solo se acepta `metodo_costeo='fifo'` o `'manual_autorizado'`
 * con justificacion + autorizado_por (rol administrador).
 */
const metodoCosteoEnum = z.enum(['fifo', 'promedio_ponderado', 'manual_autorizado'])

export const salidaFifoSchema = salidaBodegaBaseSchema
  .extend({
    metodo_costeo: metodoCosteoEnum.default('fifo'),
    costo_unitario_manual: z
      .number()
      .nonnegative('Costo manual no puede ser negativo')
      .optional()
      .nullable(),
    justificacion_costo_manual: z.string().trim().optional().nullable(),
  })
  .refine((v) => v.tipo_salida !== 'ot' || !!v.ot_id, {
    message: 'Salida tipo OT requiere seleccionar la OT',
    path: ['ot_id'],
  })
  .refine(
    (v) =>
      v.tipo_salida !== 'persona' ||
      !!v.entregado_a ||
      !!v.entregado_a_perfil_id,
    {
      message: 'Salida tipo persona requiere "Entregado a"',
      path: ['entregado_a'],
    }
  )
  .refine(
    (v) =>
      v.metodo_costeo !== 'manual_autorizado' ||
      (v.costo_unitario_manual != null &&
        v.autorizado_por != null &&
        typeof v.justificacion_costo_manual === 'string' &&
        v.justificacion_costo_manual.trim().length >= 10),
    {
      message:
        'Costeo manual requiere costo_unitario_manual, autorizado_por y justificacion (min 10)',
      path: ['justificacion_costo_manual'],
    }
  )
  .refine(
    (v) => v.metodo_costeo !== 'fifo' || v.costo_unitario_manual == null,
    {
      message: 'No se acepta costo manual cuando metodo_costeo es FIFO',
      path: ['costo_unitario_manual'],
    }
  )

/**
 * Capa FIFO — schema para mostrar en UI (no para crear; las capas las
 * crea automaticamente la RPC al recibir).
 */
export const capaInventarioReadSchema = z.object({
  id: z.string().uuid(),
  producto_id: z.string().uuid(),
  bodega_id: z.string().uuid(),
  fecha_recepcion: z.string(),
  folio_recepcion: z.string().nullable(),
  numero_oc: z.string().nullable(),
  cantidad_inicial: z.number(),
  cantidad_disponible: z.number(),
  costo_unitario: z.number(),
  costo_total_disponible: z.number(),
  proveedor_id: z.string().uuid().nullable(),
  lote: z.string().nullable(),
  vencimiento: z.string().nullable(),
  estado: z.enum(['disponible', 'agotada', 'bloqueada', 'ajustada']),
})

export type RecepcionFifoInput = z.infer<typeof recepcionFifoSchema>
export type SalidaFifoInput = z.infer<typeof salidaFifoSchema>
export type CapaInventarioRead = z.infer<typeof capaInventarioReadSchema>
