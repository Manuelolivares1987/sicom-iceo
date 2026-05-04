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


// ============================================================================
// FASE 5.3 — Ingreso/Salida formal con OC, proveedor, sellos y trazabilidad
// ============================================================================

/**
 * Ingreso formal de combustible con guia ENEX/ESMAX.
 * Refleja la tabla `ingresos_combustible` de la migracion 55.
 */
export const ingresoCombustibleFormalSchema = z
  .object({
    proveedor_id: z.string().uuid('Seleccione proveedor (ENEX, ESMAX, etc.)'),
    orden_compra_id: z.string().uuid().optional().nullable(),
    numero_guia: z
      .string()
      .trim()
      .min(1, 'Numero de guia obligatorio')
      .max(60),
    numero_pedido: z.string().trim().max(60).optional().nullable(),
    fecha_documento: z.string().min(10, 'Ingrese fecha del documento (YYYY-MM-DD)'),
    estanque_id: z.string().uuid('Seleccione estanque destino'),
    producto_combustible: z.string().trim().min(2).max(40).default('diesel'),
    volumen_carga_litros: z
      .number()
      .positive('Volumen de carga debe ser > 0')
      .optional()
      .nullable(),
    meter_inicial: z.number().nonnegative().optional().nullable(),
    meter_final: z.number().nonnegative().optional().nullable(),
    litros_entregados: z
      .number({ invalid_type_error: 'Ingrese litros entregados' })
      .positive('Litros entregados debe ser > 0'),
    conductor_nombre: z.string().trim().max(200).optional().nullable(),
    camion_patente: z.string().trim().max(20).optional().nullable(),
    cliente_nombre_documento: z.string().trim().max(200).optional().nullable(),
    evidencia_guia_url: z.string().url('Foto/PDF de la guia es obligatoria'),
    firma_conductor_url: z.string().url().optional().nullable().or(z.literal('')),
    firma_receptor_url: z.string().url().optional().nullable().or(z.literal('')),
    observacion: z.string().max(2000).optional().nullable(),
  })
  .refine(
    (v) =>
      v.meter_inicial == null ||
      v.meter_final == null ||
      v.meter_final >= v.meter_inicial,
    {
      message: 'Meter final debe ser >= meter inicial',
      path: ['meter_final'],
    }
  )
  .refine(
    (v) => {
      if (v.volumen_carga_litros == null) return true
      const diff = Math.abs(v.litros_entregados - v.volumen_carga_litros)
      return diff < 0.01 || (v.observacion != null && v.observacion.trim().length >= 5)
    },
    {
      message:
        'Diferencia entre carga documentada y litros entregados exige observacion (min 5 caracteres)',
      path: ['observacion'],
    }
  )

/**
 * Salida formal de combustible — venta externa / carga propio / despacho cliente.
 * Refleja la tabla `salidas_combustible` de la migracion 55.
 */
const tipoSalidaCombustibleEnum = z.enum([
  'venta_externa',
  'carga_equipo_propio',
  'despacho_cliente',
  'ajuste',
])

export const salidaCombustibleFormalSchema = z
  .object({
    tipo_salida: tipoSalidaCombustibleEnum,
    estanque_origen_id: z.string().uuid('Seleccione estanque origen'),
    producto_combustible: z.string().trim().max(40).default('diesel'),
    litros: z
      .number({ invalid_type_error: 'Ingrese litros' })
      .positive('Litros debe ser > 0'),
    ceco_id: z.string().uuid('CECO es obligatorio para toda salida de combustible'),
    equipo_activo_id: z.string().uuid().optional().nullable(),
    unidad_equipo_descripcion: z.string().trim().max(200).optional().nullable(),
    cliente_id: z.string().uuid().optional().nullable(),
    cliente_nombre_manual: z.string().trim().max(200).optional().nullable(),
    conductor_id: z.string().uuid().optional().nullable(),
    conductor_nombre_manual: z.string().trim().max(200).optional().nullable(),
    kilometraje: z.number().nonnegative().optional().nullable(),
    horometro: z.number().nonnegative().optional().nullable(),
    motivo: z.string().trim().min(5, 'Motivo obligatorio (min 5)').max(2000),
    pedido_por: z.string().trim().max(200).optional().nullable(),
    autorizado_por: z.string().uuid().optional().nullable(),
    retira_nombre: z.string().trim().max(200).optional().nullable(),
    evidencia_vale_url: z.string().url('Foto del vale es obligatoria'),
    observacion: z.string().max(2000).optional().nullable(),
  })
  .refine(
    (v) =>
      v.tipo_salida !== 'carga_equipo_propio' ||
      !!v.equipo_activo_id ||
      !!v.unidad_equipo_descripcion,
    {
      message: 'Carga a equipo propio requiere seleccionar equipo o describir unidad',
      path: ['equipo_activo_id'],
    }
  )
  .refine(
    (v) =>
      v.tipo_salida !== 'venta_externa' ||
      !!v.cliente_id ||
      !!v.cliente_nombre_manual,
    {
      message: 'Venta externa requiere identificar cliente',
      path: ['cliente_nombre_manual'],
    }
  )

/**
 * Despacho con 3 sellos (al SALIR del taller).
 * Refleja la tabla `despachos_combustible` de la migracion 55.
 */
export const despachoSalidaSellosSchema = z.object({
  salida_combustible_id: z.string().uuid('Salida origen invalida'),
  camion_activo_id: z.string().uuid('Seleccione camion'),
  conductor_id: z.string().uuid('Seleccione conductor'),
  destino_cliente: z.string().trim().max(200).optional().nullable(),
  destino_faena_id: z.string().uuid().optional().nullable(),
  sello_1_numero: z.string().trim().min(1, 'Sello 1 obligatorio').max(40),
  sello_2_numero: z.string().trim().min(1, 'Sello 2 obligatorio').max(40),
  sello_3_numero: z.string().trim().min(1, 'Sello 3 obligatorio').max(40),
  foto_sello_1_salida_url: z.string().url('Foto sello 1 (salida) obligatoria'),
  foto_sello_2_salida_url: z.string().url('Foto sello 2 (salida) obligatoria'),
  foto_sello_3_salida_url: z.string().url('Foto sello 3 (salida) obligatoria'),
  litros_cargados: z.number().positive('Litros cargados debe ser > 0'),
})

/**
 * Confirmacion de entrega del despacho.
 */
export const despachoEntregaSchema = z.object({
  despacho_id: z.string().uuid(),
  foto_sello_1_entrega_url: z.string().url('Foto sello 1 (entrega) obligatoria'),
  foto_sello_2_entrega_url: z.string().url('Foto sello 2 (entrega) obligatoria'),
  foto_sello_3_entrega_url: z.string().url('Foto sello 3 (entrega) obligatoria'),
  sellos_intactos: z.boolean(),
  litros_entregados: z.number().positive('Litros entregados debe ser > 0'),
  receptor_nombre: z.string().trim().min(2, 'Nombre del receptor obligatorio').max(200),
  receptor_rut: z.string().trim().max(20).optional().nullable(),
  firma_receptor_url: z.string().url('Firma del receptor obligatoria'),
  observacion_entrega: z.string().max(2000).optional().nullable(),
})

export type IngresoCombustibleFormalInput = z.infer<typeof ingresoCombustibleFormalSchema>
export type SalidaCombustibleFormalInput = z.infer<typeof salidaCombustibleFormalSchema>
export type DespachoSalidaSellosInput = z.infer<typeof despachoSalidaSellosSchema>
export type DespachoEntregaInput = z.infer<typeof despachoEntregaSchema>


// ============================================================================
// FASE 5.4-B — Combustible con CPP movil + trazabilidad valorizada
// ============================================================================

/**
 * Stock inicial controlado por estanque (mig 57 BLOCK B + F).
 * Solo administrador / subgerente_operaciones puede registrar.
 */
export const stockInicialCombustibleSchema = z.object({
  estanque_id: z.string().uuid('Seleccione estanque'),
  fecha: z.string().min(10, 'Ingrese fecha (YYYY-MM-DD)'),
  litros_iniciales: z
    .number({ invalid_type_error: 'Ingrese litros iniciales' })
    .positive('Litros iniciales debe ser > 0'),
  costo_unitario_inicial: z
    .number({ invalid_type_error: 'Ingrese costo unitario' })
    .nonnegative('Costo unitario no puede ser negativo'),
  documento_respaldo_url: z.string().url().optional().nullable().or(z.literal('')),
  observacion: z
    .string()
    .trim()
    .min(5, 'Observacion obligatoria para auditoria (min 5 caracteres)')
    .max(2000),
})

/**
 * Ingreso de combustible valorizado (mig 57 BLOCK G).
 * El sistema recalcula CPP automaticamente; el cliente NO envia CPP.
 */
export const ingresoCombustibleValorizadoSchema = z
  .object({
    proveedor_id: z.string().uuid('Seleccione proveedor (ENEX, ESMAX, etc.)'),
    orden_compra_id: z.string().uuid().optional().nullable(),
    numero_guia: z.string().trim().min(1, 'Numero de guia obligatorio').max(60),
    numero_pedido: z.string().trim().max(60).optional().nullable(),
    fecha_documento: z.string().min(10, 'Ingrese fecha del documento'),
    estanque_id: z.string().uuid('Seleccione estanque destino'),
    producto_combustible: z.string().trim().min(2).max(40).default('diesel'),
    litros_ingreso: z
      .number({ invalid_type_error: 'Ingrese litros' })
      .positive('Litros debe ser > 0'),
    costo_unitario_lt: z
      .number({ invalid_type_error: 'Ingrese costo por litro' })
      .nonnegative('Costo no puede ser negativo'),
    meter_inicial: z.number().nonnegative().optional().nullable(),
    meter_final: z.number().nonnegative().optional().nullable(),
    evidencia_guia_url: z.string().url('Foto/PDF de la guia es obligatoria'),
    conductor_nombre: z.string().trim().max(200).optional().nullable(),
    camion_patente: z.string().trim().max(20).optional().nullable(),
    observacion: z.string().max(2000).optional().nullable(),
  })
  .refine(
    (v) =>
      v.meter_inicial == null ||
      v.meter_final == null ||
      v.meter_final >= v.meter_inicial,
    {
      message: 'Meter final debe ser >= meter inicial',
      path: ['meter_final'],
    }
  )
  .refine(
    (v) => {
      if (v.meter_inicial == null || v.meter_final == null) return true
      const diff = Math.abs((v.meter_final - v.meter_inicial) - v.litros_ingreso)
      return diff <= 0.5 || (v.observacion != null && v.observacion.trim().length >= 5)
    },
    {
      message:
        'Diferencia entre litros documentados y litros medidos supera tolerancia (0.5 lt). Observacion obligatoria (min 5).',
      path: ['observacion'],
    }
  )

/**
 * Salida de combustible valorizada (mig 57 BLOCK H).
 * El costo se aplica del CPP vigente; el cliente NO puede pasar costo manual.
 */
const tipoSalidaCombustibleVal = z.enum([
  'venta_externa',
  'carga_equipo_propio',
  'despacho_cliente',
  'ajuste',
])

export const salidaCombustibleValorizadaSchema = z
  .object({
    estanque_id: z.string().uuid('Seleccione estanque'),
    litros_salida: z
      .number({ invalid_type_error: 'Ingrese litros' })
      .positive('Litros debe ser > 0'),
    tipo_salida: tipoSalidaCombustibleVal,
    ceco_id: z.string().uuid('CECO obligatorio'),
    cliente_id: z.string().uuid().optional().nullable(),
    cliente_nombre_manual: z.string().trim().max(200).optional().nullable(),
    equipo_activo_id: z.string().uuid().optional().nullable(),
    unidad_equipo_descripcion: z.string().trim().max(200).optional().nullable(),
    documento_numero: z.string().trim().max(60).optional().nullable(),
    evidencia_vale_url: z.string().url('Foto del vale es obligatoria'),
    kilometraje: z.number().nonnegative().optional().nullable(),
    horometro: z.number().nonnegative().optional().nullable(),
    pedido_por: z.string().trim().max(200).optional().nullable(),
    autorizado_por: z.string().uuid().optional().nullable(),
    retira_nombre: z.string().trim().max(200).optional().nullable(),
    motivo: z.string().trim().min(5, 'Motivo obligatorio (min 5)').max(2000),
    observacion: z.string().max(2000).optional().nullable(),
    conductor_id: z.string().uuid().optional().nullable(),
    conductor_nombre_manual: z.string().trim().max(200).optional().nullable(),
  })
  .refine(
    (v) =>
      v.tipo_salida !== 'venta_externa' ||
      !!v.cliente_id ||
      !!v.cliente_nombre_manual,
    {
      message: 'Venta externa requiere cliente',
      path: ['cliente_nombre_manual'],
    }
  )
  .refine(
    (v) =>
      v.tipo_salida !== 'venta_externa' ||
      (typeof v.retira_nombre === 'string' && v.retira_nombre.trim().length >= 2),
    {
      message: 'Venta externa requiere nombre del retira',
      path: ['retira_nombre'],
    }
  )
  .refine(
    (v) =>
      v.tipo_salida !== 'carga_equipo_propio' ||
      !!v.equipo_activo_id ||
      !!v.unidad_equipo_descripcion,
    {
      message: 'Carga equipo propio requiere equipo o descripcion',
      path: ['equipo_activo_id'],
    }
  )

export type StockInicialCombustibleInput = z.infer<typeof stockInicialCombustibleSchema>
export type IngresoCombustibleValorizadoInput = z.infer<typeof ingresoCombustibleValorizadoSchema>
export type SalidaCombustibleValorizadaInput = z.infer<typeof salidaCombustibleValorizadaSchema>
