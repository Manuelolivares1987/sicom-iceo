// Tipos TypeScript generados desde el esquema PostgreSQL de SICOM-ICEO
// Estos tipos se sincronizan con Supabase via: npx supabase gen types typescript

export type Database = {
  public: {
    Tables: {
      contratos: {
        Row: Contrato
        Insert: Omit<Contrato, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<Omit<Contrato, 'id'>>
      }
      faenas: {
        Row: Faena
        Insert: Omit<Faena, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<Omit<Faena, 'id'>>
      }
      activos: {
        Row: Activo
        Insert: Omit<Activo, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<Omit<Activo, 'id'>>
      }
      ordenes_trabajo: {
        Row: OrdenTrabajo
        Insert: Omit<OrdenTrabajo, 'id' | 'folio' | 'qr_code' | 'costo_total' | 'created_at' | 'updated_at'>
        Update: Partial<Omit<OrdenTrabajo, 'id' | 'folio' | 'costo_total'>>
      }
      movimientos_inventario: {
        Row: MovimientoInventario
        Insert: Omit<MovimientoInventario, 'id' | 'costo_total' | 'created_at'>
        Update: never
      }
      productos: {
        Row: Producto
        Insert: Omit<Producto, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<Omit<Producto, 'id'>>
      }
      stock_bodega: {
        Row: StockBodega
        Insert: Omit<StockBodega, 'id' | 'valor_total' | 'created_at' | 'updated_at'>
        Update: Partial<Omit<StockBodega, 'id' | 'valor_total'>>
      }
    }
    Enums: {
      tipo_activo_enum: TipoActivo
      criticidad_enum: Criticidad
      estado_activo_enum: EstadoActivo
      tipo_ot_enum: TipoOT
      estado_ot_enum: EstadoOT
      prioridad_enum: Prioridad
      tipo_movimiento_enum: TipoMovimiento
      rol_usuario_enum: RolUsuario
      area_kpi_enum: AreaKPI
      clasificacion_iceo_enum: ClasificacionICEO
    }
  }
}

// Enums
export type TipoActivo = 'punto_fijo' | 'punto_movil' | 'surtidor' | 'dispensador' | 'estanque' | 'bomba' | 'manguera' | 'camion_cisterna' | 'lubrimovil' | 'equipo_bombeo' | 'herramienta_critica' | 'pistola_captura' | 'camioneta' | 'camion' | 'equipo_menor'
export type Criticidad = 'critica' | 'alta' | 'media' | 'baja'
export type EstadoActivo = 'operativo' | 'en_mantenimiento' | 'fuera_servicio' | 'dado_baja' | 'en_transito'
export type TipoOT = 'inspeccion' | 'preventivo' | 'correctivo' | 'abastecimiento' | 'lubricacion' | 'inventario' | 'regularizacion'
export type EstadoOT = 'creada' | 'asignada' | 'en_ejecucion' | 'pausada' | 'ejecutada_ok' | 'ejecutada_con_observaciones' | 'no_ejecutada' | 'cancelada'
export type Prioridad = 'emergencia' | 'urgente' | 'alta' | 'normal' | 'baja'
export type TipoMovimiento = 'entrada' | 'salida' | 'ajuste_positivo' | 'ajuste_negativo' | 'transferencia_entrada' | 'transferencia_salida' | 'merma' | 'devolucion'
export type RolUsuario = 'administrador' | 'gerencia' | 'subgerente_operaciones' | 'supervisor' | 'planificador' | 'tecnico_mantenimiento' | 'bodeguero' | 'operador_abastecimiento' | 'auditor' | 'rrhh_incentivos'
export type AreaKPI = 'administracion_combustibles' | 'mantenimiento_fijos' | 'mantenimiento_moviles'
export type ClasificacionICEO = 'deficiente' | 'aceptable' | 'bueno' | 'excelencia'

// Entidades principales
export interface Contrato {
  id: string
  codigo: string
  nombre: string
  cliente: string | null
  descripcion: string | null
  fecha_inicio: string | null
  fecha_fin: string | null
  estado: string
  valor_contrato: number | null
  moneda: string
  sla_json: Record<string, unknown> | null
  obligaciones_json: Record<string, unknown> | null
  created_at: string
  updated_at: string
  created_by: string | null
}

export interface Faena {
  id: string
  contrato_id: string
  codigo: string
  nombre: string
  ubicacion: string | null
  region: string | null
  comuna: string | null
  coordenadas_lat: number | null
  coordenadas_lng: number | null
  estado: string
  created_at: string
  updated_at: string
  created_by: string | null
}

export interface UsuarioPerfil {
  id: string
  email: string
  nombre_completo: string
  rut: string | null
  cargo: string | null
  telefono: string | null
  rol: RolUsuario
  faena_id: string | null
  activo: boolean
  firma_url: string | null
  created_at: string
  updated_at: string
}

export interface Activo {
  id: string
  contrato_id: string | null
  faena_id: string | null
  modelo_id: string
  codigo: string
  nombre: string | null
  tipo: TipoActivo
  numero_serie: string | null
  criticidad: Criticidad
  estado: EstadoActivo
  fecha_alta: string | null
  fecha_baja: string | null
  ubicacion_detalle: string | null
  kilometraje_actual: number
  horas_uso_actual: number
  ciclos_actual: number
  notas: string | null
  created_at: string
  updated_at: string
  created_by: string | null
  // Joins
  modelo?: Modelo
  faena?: Faena
}

export interface Marca {
  id: string
  nombre: string
  created_at: string
}

export interface Modelo {
  id: string
  marca_id: string
  nombre: string
  tipo_activo: TipoActivo
  especificaciones: Record<string, unknown> | null
  created_at: string
  marca?: Marca
}

export interface OrdenTrabajo {
  id: string
  folio: string
  tipo: TipoOT
  contrato_id: string
  faena_id: string
  activo_id: string
  plan_mantenimiento_id: string | null
  prioridad: Prioridad
  estado: EstadoOT
  responsable_id: string | null
  cuadrilla: string | null
  fecha_programada: string | null
  fecha_inicio: string | null
  fecha_termino: string | null
  fecha_cierre_supervisor: string | null
  supervisor_cierre_id: string | null
  causa_no_ejecucion: string | null
  detalle_no_ejecucion: string | null
  observaciones: string | null
  observaciones_supervisor: string | null
  costo_mano_obra: number
  costo_materiales: number
  costo_total: number
  firma_tecnico_url: string | null
  firma_supervisor_url: string | null
  qr_code: string | null
  generada_automaticamente: boolean
  created_at: string
  updated_at: string
  created_by: string | null
  // Joins
  activo?: Activo
  faena?: Faena
  responsable?: UsuarioPerfil
}

export interface Producto {
  id: string
  codigo: string
  codigo_barras: string | null
  nombre: string
  categoria: string
  subcategoria: string | null
  unidad_medida: string
  costo_unitario_actual: number
  metodo_valorizacion: string
  stock_minimo: number
  stock_maximo: number | null
  tiene_vencimiento: boolean
  created_at: string
  updated_at: string
  created_by: string | null
}

export interface StockBodega {
  id: string
  bodega_id: string
  producto_id: string
  cantidad: number
  costo_promedio: number
  valor_total: number
  ultimo_movimiento: string | null
  created_at: string
  updated_at: string
  producto?: Producto
}

export interface MovimientoInventario {
  id: string
  bodega_id: string
  producto_id: string
  tipo: TipoMovimiento
  cantidad: number
  costo_unitario: number
  costo_total: number
  ot_id: string | null
  activo_id: string | null
  lote: string | null
  fecha_vencimiento: string | null
  documento_referencia: string | null
  motivo: string | null
  bodega_destino_id: string | null
  usuario_id: string
  created_at: string
}

export interface MedicionKPI {
  id: string
  kpi_id: string
  contrato_id: string
  faena_id: string | null
  periodo_inicio: string
  periodo_fin: string
  valor_medido: number
  porcentaje_cumplimiento: number | null
  puntaje: number
  valor_ponderado: number
  bloqueante_activado: boolean
  datos_calculo: Record<string, unknown> | null
  calculado_en: string
}

export interface ICEOPeriodo {
  id: string
  contrato_id: string
  faena_id: string | null
  periodo_inicio: string
  periodo_fin: string
  puntaje_area_a: number | null
  puntaje_area_b: number | null
  puntaje_area_c: number | null
  peso_area_a: number
  peso_area_b: number
  peso_area_c: number
  iceo_bruto: number
  iceo_final: number
  clasificacion: ClasificacionICEO
  bloqueantes_activados: Record<string, unknown> | null
  incentivo_habilitado: boolean
  observaciones: string | null
  calculado_en: string
}

export interface Certificacion {
  id: string
  activo_id: string
  tipo: string
  numero_certificado: string | null
  entidad_certificadora: string | null
  fecha_emision: string
  fecha_vencimiento: string
  estado: string
  archivo_url: string | null
  notas: string | null
  bloqueante: boolean
  created_at: string
  updated_at: string
  created_by: string | null
}

export interface Incidente {
  id: string
  contrato_id: string | null
  faena_id: string
  activo_id: string | null
  ot_id: string | null
  tipo: string
  fecha_incidente: string
  descripcion: string
  gravedad: string
  causa_raiz: string | null
  acciones_correctivas: string | null
  estado: string
  impacto_operacional: string | null
  created_at: string
}

export interface Alerta {
  id: string
  tipo: string
  titulo: string
  mensaje: string | null
  severidad: 'info' | 'warning' | 'critical'
  entidad_tipo: string | null
  entidad_id: string | null
  destinatario_id: string | null
  leida: boolean
  leida_en: string | null
  created_at: string
}
