// Tipos TypeScript generados desde el esquema PostgreSQL de SICOM-ICEO
// Estos tipos se sincronizan con Supabase via: npx supabase gen types typescript

// Re-export for backward compatibility — no existing imports break
export * from './enums'
export * from './entities'

// Import types needed for Database definition
import type { Contrato, Faena, Activo, OrdenTrabajo, MovimientoInventario, Producto, StockBodega } from './entities'
import type { TipoActivo, Criticidad, EstadoActivo, TipoOT, EstadoOT, Prioridad, TipoMovimiento, RolUsuario, AreaKPI, ClasificacionICEO } from './enums'

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
