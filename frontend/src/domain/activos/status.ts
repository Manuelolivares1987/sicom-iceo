import type { EstadoActivo, Criticidad } from '@/types/database'

/**
 * Asset status rules - pure business logic, no Supabase imports.
 */

const SEMAFORO_COLORS: Record<EstadoActivo, string> = {
  operativo: 'text-semaforo-verde',
  en_mantenimiento: 'text-semaforo-amarillo',
  fuera_servicio: 'text-semaforo-rojo',
  dado_baja: 'text-gray-400',
  en_transito: 'text-semaforo-azul',
}

const SEMAFORO_DOTS: Record<EstadoActivo, string> = {
  operativo: 'bg-semaforo-verde',
  en_mantenimiento: 'bg-semaforo-amarillo',
  fuera_servicio: 'bg-semaforo-rojo',
  dado_baja: 'bg-gray-400',
  en_transito: 'bg-semaforo-azul',
}

const CRITICIDAD_COLORS: Record<Criticidad, string> = {
  critica: 'bg-red-600 text-white',
  alta: 'bg-orange-500 text-white',
  media: 'bg-yellow-400 text-yellow-900',
  baja: 'bg-green-500 text-white',
}

const CRITICIDAD_LABELS: Record<Criticidad, string> = {
  critica: 'Critica',
  alta: 'Alta',
  media: 'Media',
  baja: 'Baja',
}

const ESTADO_ACTIVO_LABELS: Record<EstadoActivo, string> = {
  operativo: 'Operativo',
  en_mantenimiento: 'En Mantenimiento',
  fuera_servicio: 'Fuera de Servicio',
  dado_baja: 'Dado de Baja',
  en_transito: 'En Transito',
}

const TIPO_CERTIFICACION_LABELS: Record<string, string> = {
  sec: 'Inscripcion SEC',
  seremi: 'SEREMI',
  siss: 'SISS',
  revision_tecnica: 'Revision Tecnica',
  soap: 'SOAP (Seguro Obligatorio)',
  permiso_municipal: 'Permiso Municipal',
  calibracion: 'Calibracion',
  licencia_especial: 'Licencia Especial',
  permiso_circulacion: 'Permiso de Circulacion',
  hermeticidad: 'Cert. Hermeticidad',
  tc8_sec: 'TC8 / SEC',
  inscripcion_sec: 'Inscripcion SEC (TC-10A)',
  seguro_rc: 'Seguro Resp. Civil',
  fops_rops: 'FOPS/ROPS',
  cert_gancho: 'Cert. Gancho',
  otra: 'Otra',
}

const ESTADO_COMERCIAL_LABELS: Record<string, string> = {
  arrendado: 'Arrendado',
  disponible: 'Disponible',
  uso_interno: 'Uso Interno',
  leasing: 'Leasing',
  en_recepcion: 'En Recepcion',
  en_venta: 'En Venta',
  comprometido: 'Comprometido',
}

const ESTADO_COMERCIAL_COLORS: Record<string, string> = {
  arrendado: 'bg-green-100 text-green-700',
  disponible: 'bg-blue-100 text-blue-700',
  uso_interno: 'bg-cyan-100 text-cyan-700',
  leasing: 'bg-indigo-100 text-indigo-700',
  en_recepcion: 'bg-purple-100 text-purple-700',
  en_venta: 'bg-gray-100 text-gray-700',
  comprometido: 'bg-amber-100 text-amber-700',
}

const TIPO_ACTIVO_LABELS: Record<string, string> = {
  punto_fijo: 'Punto Fijo',
  punto_movil: 'Punto Movil',
  surtidor: 'Surtidor',
  dispensador: 'Dispensador',
  estanque: 'Estanque',
  bomba: 'Bomba',
  manguera: 'Manguera',
  camion_cisterna: 'Camion Cisterna',
  lubrimovil: 'Lubrimovil',
  equipo_bombeo: 'Equipo de Bombeo',
  herramienta_critica: 'Herramienta Critica',
  pistola_captura: 'Pistola de Captura',
  camioneta: 'Camioneta',
  camion: 'Camion',
  equipo_menor: 'Equipo Menor',
}

const TIPO_ACTIVO_ICONS: Record<string, string> = {
  punto_fijo: 'Building2',
  punto_movil: 'Truck',
  surtidor: 'Fuel',
  dispensador: 'Droplets',
  estanque: 'Container',
  bomba: 'Cog',
  manguera: 'Cable',
  camion_cisterna: 'Truck',
  lubrimovil: 'Truck',
  equipo_bombeo: 'Cog',
  herramienta_critica: 'Wrench',
  pistola_captura: 'ScanBarcode',
  camioneta: 'Car',
  camion: 'Truck',
  equipo_menor: 'Package',
}

/**
 * Get the text color class for an asset state (semaforo).
 */
export function getSemaforoColor(estado: EstadoActivo): string {
  return SEMAFORO_COLORS[estado] ?? 'text-gray-400'
}

/**
 * Get the background dot class for an asset state.
 */
export function getSemaforoDot(estado: EstadoActivo): string {
  return SEMAFORO_DOTS[estado] ?? 'bg-gray-400'
}

/**
 * Get the badge color classes for a criticality level.
 */
export function getCriticidadColor(criticidad: Criticidad): string {
  return CRITICIDAD_COLORS[criticidad] ?? 'bg-gray-400'
}

/**
 * Get the Spanish label for a criticality level.
 */
export function getCriticidadLabel(criticidad: Criticidad): string {
  return CRITICIDAD_LABELS[criticidad] ?? criticidad
}

/**
 * Get the Spanish label for an asset state.
 */
export function getEstadoActivoLabel(estado: EstadoActivo): string {
  return ESTADO_ACTIVO_LABELS[estado] ?? estado
}

/**
 * Convert a snake_case asset type to a readable Spanish label.
 * e.g. camion_cisterna -> "Camion Cisterna"
 */
export function getTipoActivoLabel(tipo: string): string {
  if (TIPO_ACTIVO_LABELS[tipo]) return TIPO_ACTIVO_LABELS[tipo]
  // Fallback: capitalize each word from snake_case
  return tipo
    .split('_')
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ')
}

/**
 * Get the Lucide icon name for an asset type.
 */
export function getTipoActivoIcon(tipo: string): string {
  return TIPO_ACTIVO_ICONS[tipo] ?? 'Box'
}

export function getTipoCertificacionLabel(tipo: string): string {
  return TIPO_CERTIFICACION_LABELS[tipo] ?? tipo.replace(/_/g, ' ')
}

export function getEstadoComercialLabel(estado: string): string {
  return ESTADO_COMERCIAL_LABELS[estado] ?? estado
}

export function getEstadoComercialColor(estado: string): string {
  return ESTADO_COMERCIAL_COLORS[estado] ?? 'bg-gray-100 text-gray-700'
}
