// Enums — extracted from database.ts for focused imports

export type TipoActivo = 'punto_fijo' | 'punto_movil' | 'surtidor' | 'dispensador' | 'estanque' | 'bomba' | 'manguera' | 'camion_cisterna' | 'lubrimovil' | 'equipo_bombeo' | 'herramienta_critica' | 'pistola_captura' | 'camioneta' | 'camion' | 'equipo_menor'
export type Criticidad = 'critica' | 'alta' | 'media' | 'baja'
export type EstadoActivo = 'operativo' | 'en_mantenimiento' | 'fuera_servicio' | 'dado_baja' | 'en_transito'
export type TipoOT = 'inspeccion' | 'preventivo' | 'correctivo' | 'abastecimiento' | 'lubricacion' | 'inventario' | 'regularizacion'
export type EstadoOT = 'creada' | 'asignada' | 'en_ejecucion' | 'pausada' | 'ejecutada_ok' | 'ejecutada_con_observaciones' | 'no_ejecutada' | 'cancelada' | 'cerrada'
export type Prioridad = 'emergencia' | 'urgente' | 'alta' | 'normal' | 'baja'
export type TipoMovimiento = 'entrada' | 'salida' | 'ajuste_positivo' | 'ajuste_negativo' | 'transferencia_entrada' | 'transferencia_salida' | 'merma' | 'devolucion'
export type RolUsuario = 'administrador' | 'gerencia' | 'subgerente_operaciones' | 'supervisor' | 'planificador' | 'tecnico_mantenimiento' | 'bodeguero' | 'operador_abastecimiento' | 'auditor' | 'rrhh_incentivos'
export type AreaKPI = 'administracion_combustibles' | 'mantenimiento_fijos' | 'mantenimiento_moviles'
export type ClasificacionICEO = 'deficiente' | 'aceptable' | 'bueno' | 'excelencia'
