/**
 * Punto unico de import para esquemas Zod del proyecto.
 *
 * Cada modulo expone schemas + tipos inferidos. Importar via:
 *   import { crearOTSchema, salidaSchema, ... } from '@/validations'
 *
 * Cobertura por dominio (FASE 6):
 *   - ot               formularios y transiciones de orden de trabajo
 *   - inventario       movimientos: entrada, salida, ajuste
 *   - combustible      ingreso, despacho, varillaje
 *   - flota            cambio de estado diario / verificacion ready-to-rent
 *   - checklists       plantillas + respuestas (FASE 5.2)
 *   - activos          alta y edicion de equipos
 *   - mantenimiento    planes PM + generacion OT desde plan
 *   - certificaciones  alta y edicion de certificaciones
 *   - abastecimiento   rutas y despachos
 *   - prevencion       SUSPEL / RESPEL
 *   - contratos        alta y edicion (modulo de solo lectura hoy)
 *   - admin            edicion de usuarios y perfiles
 *
 * Ver VALIDACIONES_FORMULARIOS.md para el detalle de aplicacion en
 * formularios reales y los pendientes documentados.
 */

export * from './ot'
export * from './inventario'
export * from './combustible'
export * from './flota'
export * from './checklists'
export * from './activos'
export * from './mantenimiento'
export * from './certificaciones'
export * from './abastecimiento'
export * from './prevencion'
export * from './contratos'
export * from './admin'
export * from './bodega'
