-- ============================================================================
-- SICOM-ICEO  |  Fase 2 - Schema PostgreSQL
-- Sistema Integral de Control Operacional - Indice Compuesto de Excelencia
-- Operacional
-- ----------------------------------------------------------------------------
-- Archivo : 01_tipos_y_enums.sql
-- Propósito : Extensiones requeridas y definición de todos los tipos
--             enumerados (ENUM) utilizados por el sistema.
-- Alcance   : Contratos de servicio minero (administración de combustibles y
--             lubricantes, mantenimiento de plataformas fijas y móviles),
--             órdenes de trabajo, inventario valorizado con lector de código
--             de barras, KPI e ICEO, cumplimiento documental,
--             certificaciones y gestión de activos.
-- ============================================================================

-- ============================================================================
-- 1. EXTENSIONES
-- ============================================================================

-- Generación de UUID v4
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Funciones criptográficas (hashing, generación de tokens, etc.)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Tareas programadas (cron jobs dentro de PostgreSQL).
-- NOTA: En Supabase esta extensión debe habilitarse manualmente desde el
--       Dashboard > Database > Extensions > pg_cron.  No se puede crear
--       con CREATE EXTENSION en proyectos hosted.
-- CREATE EXTENSION IF NOT EXISTS "pg_cron";

-- ============================================================================
-- 2. TIPOS ENUMERADOS (ENUM)
-- ============================================================================

-- 2.1  Tipo de activo gestionado por el sistema
CREATE TYPE tipo_activo_enum AS ENUM (
    'punto_fijo',
    'punto_movil',
    'surtidor',
    'dispensador',
    'estanque',
    'bomba',
    'manguera',
    'camion_cisterna',
    'lubrimovil',
    'equipo_bombeo',
    'herramienta_critica',
    'pistola_captura',
    'camioneta',
    'camion',
    'equipo_menor'
);

-- 2.2  Nivel de criticidad del activo u operación
CREATE TYPE criticidad_enum AS ENUM (
    'critica',
    'alta',
    'media',
    'baja'
);

-- 2.3  Estado del ciclo de vida de un activo
CREATE TYPE estado_activo_enum AS ENUM (
    'operativo',
    'en_mantenimiento',
    'fuera_servicio',
    'dado_baja',
    'en_transito'
);

-- 2.4  Tipo de orden de trabajo
CREATE TYPE tipo_ot_enum AS ENUM (
    'inspeccion',
    'preventivo',
    'correctivo',
    'abastecimiento',
    'lubricacion',
    'inventario',
    'regularizacion'
);

-- 2.5  Estado del flujo de una orden de trabajo
CREATE TYPE estado_ot_enum AS ENUM (
    'creada',
    'asignada',
    'en_ejecucion',
    'pausada',
    'ejecutada_ok',
    'ejecutada_con_observaciones',
    'no_ejecutada',
    'cancelada'
);

-- 2.6  Prioridad de una orden de trabajo o solicitud
CREATE TYPE prioridad_enum AS ENUM (
    'emergencia',
    'urgente',
    'alta',
    'normal',
    'baja'
);

-- 2.7  Tipo de movimiento de inventario
CREATE TYPE tipo_movimiento_enum AS ENUM (
    'entrada',
    'salida',
    'ajuste_positivo',
    'ajuste_negativo',
    'transferencia_entrada',
    'transferencia_salida',
    'merma',
    'devolucion'
);

-- 2.8  Método de valorización de inventario
CREATE TYPE metodo_valorizacion_enum AS ENUM (
    'cpp',
    'fifo',
    'ultimo_costo'
);

-- 2.9  Tipo de conteo de inventario
CREATE TYPE tipo_conteo_enum AS ENUM (
    'ciclico',
    'general',
    'selectivo'
);

-- 2.10 Estado de un documento o certificación
CREATE TYPE estado_documento_enum AS ENUM (
    'vigente',
    'por_vencer',
    'vencido',
    'no_aplica'
);

-- 2.11 Frecuencia de ejecución de planes o tareas programadas
CREATE TYPE frecuencia_enum AS ENUM (
    'diario',
    'semanal',
    'quincenal',
    'mensual',
    'bimestral',
    'trimestral',
    'semestral',
    'anual'
);

-- 2.12 Tipo de plan de mantenimiento preventivo
CREATE TYPE tipo_plan_pm_enum AS ENUM (
    'por_tiempo',
    'por_kilometraje',
    'por_horas',
    'por_ciclos',
    'mixto'
);

-- 2.13 Clasificación del Índice Compuesto de Excelencia Operacional (ICEO)
CREATE TYPE clasificacion_iceo_enum AS ENUM (
    'deficiente',
    'aceptable',
    'bueno',
    'excelencia'
);

-- 2.14 Efecto que produce un incumplimiento sobre el incentivo contractual
CREATE TYPE efecto_bloqueante_enum AS ENUM (
    'anular',
    'penalizar',
    'descontar',
    'bloquear_incentivo'
);

-- 2.15 Rol de usuario en el sistema
CREATE TYPE rol_usuario_enum AS ENUM (
    'administrador',
    'gerencia',
    'subgerente_operaciones',
    'supervisor',
    'planificador',
    'tecnico_mantenimiento',
    'bodeguero',
    'operador_abastecimiento',
    'auditor',
    'rrhh_incentivos'
);

-- 2.16 Causa de no ejecución de una orden de trabajo
CREATE TYPE causa_no_ejecucion_enum AS ENUM (
    'equipo_no_disponible',
    'falta_repuestos',
    'condicion_climatica',
    'prioridad_operacional',
    'problema_acceso',
    'personal_no_disponible',
    'otra'
);

-- 2.17 Tipo de certificación o permiso regulatorio
CREATE TYPE tipo_certificacion_enum AS ENUM (
    'sec',
    'seremi',
    'siss',
    'revision_tecnica',
    'soap',
    'permiso_municipal',
    'calibracion',
    'licencia_especial',
    'otra'
);

-- 2.18 Área de KPI para agrupación de indicadores
CREATE TYPE area_kpi_enum AS ENUM (
    'administracion_combustibles',
    'mantenimiento_fijos',
    'mantenimiento_moviles'
);

-- 2.19 Tipo de incidente reportable
CREATE TYPE tipo_incidente_enum AS ENUM (
    'ambiental',
    'seguridad',
    'operacional',
    'vehicular'
);

-- ============================================================================
-- Fin de 01_tipos_y_enums.sql
-- ============================================================================
