-- ============================================================================
-- 54_flota_estado_programado_checklists.sql
-- ----------------------------------------------------------------------------
-- ARCHIVO DE VERIFICACION + MEJORAS OPCIONALES — NO DESTRUCTIVO.
--
-- Generado en FASE 5.2 (2026-04-29).
--
-- DIAGNOSTICO INICIAL:
--   La infraestructura de "estado diario / programado de flota" YA EXISTE en
--   migraciones previas (22, 25, 30, 37, 44, 45). Los hallazgos detallados en
--   FLOTA_ESTADO_DIARIO_CHECKLISTS.md confirman que:
--
--     - estado_diario_flota tiene UNIQUE(activo_id, fecha) y soporta cualquier
--       fecha (incluida futura). Mig 30.
--     - rpc_actualizar_estado_diario_manual acepta p_fecha como parametro
--       libre y hace upsert idempotente. Mig 30 + 37.
--     - verificaciones_disponibilidad + trigger trg_validar_cambio_disponible
--       BLOQUEAN marcar 'disponible' sin checklist vigente. Mig 44.
--     - fn_iniciar_verificacion_disponibilidad / fn_aprobar_verificacion_
--       disponibilidad implementan el flujo ready-to-rent con doble firma y
--       road test. Mig 45.
--     - checklist_templates (mig 22) permite plantillas configurables por
--       tipo_ot con items JSONB.
--
-- POR LO TANTO:
--   Esta migracion NO crea tablas nuevas. Solo agrega:
--     A. Verificaciones SAFE (lectura) para auditar el estado actual.
--     B. Indices opcionales para consultas frecuentes.
--     C. Comentarios en columnas/funciones para documentar la intencion.
--     D. Plantilla SQL comentada para casos avanzados (no aplicar a ciegas).
--
-- NO ejecutar a ciegas. Revisar bloque por bloque y descomentar segun
-- corresponda.
-- ============================================================================


-- ============================================================================
-- BLOCK 0  Verificaciones de salud del sistema actual (SAFE — solo lectura)
-- ============================================================================

-- 0.1 Confirmar que estado_diario_flota tiene UNIQUE (activo_id, fecha)
-- SELECT conname, pg_get_constraintdef(c.oid)
--   FROM pg_constraint c
--   JOIN pg_class t ON t.oid = c.conrelid
--  WHERE t.relname = 'estado_diario_flota'
--    AND c.contype IN ('u','p');

-- 0.2 Listar registros de hoy (sanity check)
-- SELECT estado_codigo, COUNT(*)
--   FROM estado_diario_flota
--  WHERE fecha = CURRENT_DATE
--  GROUP BY estado_codigo
--  ORDER BY estado_codigo;

-- 0.3 Listar registros programados a futuro (deberia haber 0 o muy pocos)
-- SELECT activo_id, fecha, estado_codigo, motivo_override, override_manual
--   FROM estado_diario_flota
--  WHERE fecha > CURRENT_DATE
--  ORDER BY fecha, activo_id;

-- 0.4 Verificar que los triggers criticos esten conectados
-- SELECT trigger_name, event_manipulation, event_object_table
--   FROM information_schema.triggers
--  WHERE trigger_name IN (
--      'trg_validar_cambio_disponible',
--      'trg_recalcular_estado_por_ot'
--  )
--  ORDER BY trigger_name;

-- 0.5 Plantillas de checklist activas
-- SELECT tipo_ot, nombre, jsonb_array_length(items) AS n_items, activo
--   FROM checklist_templates
--  WHERE activo = true
--  ORDER BY tipo_ot;

-- 0.6 Equipos disponibles SIN verificacion vigente (necesitan checklist)
-- SELECT * FROM v_equipos_pendientes_verificacion ORDER BY patente;

-- 0.7 Equipos REALMENTE arrendables (con checklist vigente)
-- SELECT COUNT(*) AS arrendables FROM v_equipos_disponibles_para_arriendo;


-- ============================================================================
-- BLOCK A  Indices opcionales para consultas de programacion futura
-- ----------------------------------------------------------------------------
-- Si el modulo de "programacion futura" se usa intensivamente, estos indices
-- ayudan a filtrar por fecha futura y por activo + rango de fechas.
-- ============================================================================

-- A.1  Indice parcial para estados programados a futuro
-- BEGIN;
--   CREATE INDEX IF NOT EXISTS idx_estado_diario_futuro
--     ON estado_diario_flota (fecha, activo_id)
--     WHERE fecha > CURRENT_DATE;
-- COMMIT;

-- A.2  Indice por activo + rango (ya existe idx por activo_id, fecha en mig 25,
--      pero conviene confirmar):
-- SELECT indexname, indexdef
--   FROM pg_indexes
--  WHERE tablename = 'estado_diario_flota'
--    AND schemaname = 'public';


-- ============================================================================
-- BLOCK B  Comentarios documentales (SAFE — sin cambio funcional)
-- ============================================================================

-- B.1  Aclarar el campo `fecha` y su semantica de programacion futura
-- BEGIN;
--   COMMENT ON COLUMN estado_diario_flota.fecha IS
--       'Fecha del estado. Puede ser pasada (correccion historica) o futura '
--       '(programada). El sistema respeta override_manual=true en cualquier '
--       'fecha; la cascada automatica solo escribe sobre fechas hasta CURRENT_DATE.';
--
--   COMMENT ON COLUMN estado_diario_flota.override_manual IS
--       'TRUE = registro fijado manualmente y NO debe ser sobreescrito por '
--       'fn_aplicar_estados_diarios_automaticos. Usado para cambios manuales '
--       'del Jefe de Taller / Planificador y para programaciones futuras.';
-- COMMIT;


-- ============================================================================
-- BLOCK C  Plantilla SQL para crear checklist nuevo desde fila tabular
-- ----------------------------------------------------------------------------
-- Util para importar checklists entregados por la empresa en formato Excel.
-- Ver CHECKLISTS_FLOTA_IMPORTACION.md para el formato esperado.
--
-- Antes de ejecutar:
--   1. Reemplazar los valores en el INSERT.
--   2. Confirmar que tipo_ot exista en el enum tipo_ot_enum.
-- ============================================================================

-- C.1  Crear plantilla nueva con items dados en JSONB
/*
INSERT INTO checklist_templates (tipo_ot, nombre, descripcion, items, activo)
VALUES (
    'preventivo'::tipo_ot_enum,
    'Checklist Disponibilidad Camion Cisterna',
    'Checklist de 55 items entregado por cliente para verificacion ready-to-rent',
    '[
      {"orden": 1, "descripcion": "Verificar nivel de aceite motor", "obligatorio": true,  "requiere_foto": false},
      {"orden": 2, "descripcion": "Verificar nivel de refrigerante",  "obligatorio": true,  "requiere_foto": false},
      {"orden": 3, "descripcion": "Verificar presion de neumaticos",  "obligatorio": true,  "requiere_foto": true},
      {"orden": 4, "descripcion": "Verificar luces y direccionales",  "obligatorio": true,  "requiere_foto": false},
      {"orden": 5, "descripcion": "Verificar bombas y mangueras",     "obligatorio": true,  "requiere_foto": true}
      -- ... agregar el resto de items
    ]'::jsonb,
    true
);
*/

-- C.2  Reemplazar items de una plantilla existente (versionado simple via update)
/*
UPDATE checklist_templates
   SET items      = '[
        {"orden": 1, "descripcion": "Item nuevo 1", "obligatorio": true, "requiere_foto": false},
        {"orden": 2, "descripcion": "Item nuevo 2", "obligatorio": true, "requiere_foto": true}
       ]'::jsonb,
       updated_at = NOW()
 WHERE id = 'UUID-PLANTILLA-AQUI';
*/

-- C.3  Desactivar plantilla obsoleta (sin borrar — preserva auditoria)
/*
UPDATE checklist_templates
   SET activo     = false,
       updated_at = NOW()
 WHERE id = 'UUID-PLANTILLA-OBSOLETA';
*/


-- ============================================================================
-- BLOCK D  Versionado opcional de plantillas (DESIGN — no aplicar todavia)
-- ----------------------------------------------------------------------------
-- Si el cliente requiere versiones rastreables (ej. "v1 firmada por SEC en
-- 2026-03, v2 ajustada en 2026-08"), conviene agregar columnas de version.
-- Esto NO se aplica automaticamente — discutir con DBA primero.
-- ============================================================================

-- D.1  Agregar version y plantilla padre para versionar
-- BEGIN;
--   ALTER TABLE checklist_templates
--     ADD COLUMN IF NOT EXISTS version           INTEGER NOT NULL DEFAULT 1,
--     ADD COLUMN IF NOT EXISTS template_padre_id UUID REFERENCES checklist_templates(id),
--     ADD COLUMN IF NOT EXISTS categoria_equipo  VARCHAR(40),
--     ADD COLUMN IF NOT EXISTS valido_desde      DATE,
--     ADD COLUMN IF NOT EXISTS valido_hasta      DATE;
--
--   -- Indice unico: solo una plantilla activa por (tipo_ot, categoria_equipo)
--   CREATE UNIQUE INDEX IF NOT EXISTS uq_checklist_template_activa
--     ON checklist_templates (tipo_ot, COALESCE(categoria_equipo, ''))
--     WHERE activo = true;
-- COMMIT;

-- D.2  Helper para "promover" una plantilla a nueva version
-- (pseudocodigo — implementar como funcion plpgsql cuando se requiera)
-- 1. Marcar version actual como activo=false
-- 2. INSERT nueva fila con version+1, template_padre_id = id viejo


-- ============================================================================
-- BLOCK E  Verificaciones POST-cambio (SAFE)
-- ============================================================================

-- E.1  Confirmar que no hay activos disponibles sin verificacion
-- SELECT COUNT(*) AS pendientes_verificacion
--   FROM v_equipos_pendientes_verificacion;

-- E.2  Confirmar que las plantillas tienen items minimos
-- SELECT tipo_ot, nombre, jsonb_array_length(items) AS n_items
--   FROM checklist_templates
--  WHERE activo = true
--    AND jsonb_array_length(items) < 3;
-- (filas devueltas = plantillas con menos de 3 items, revisar)

-- E.3  Listar cambios programados para los proximos 7 dias
-- SELECT a.codigo, a.patente, edf.fecha, edf.estado_codigo, edf.motivo_override,
--        up.nombre_completo AS programado_por
--   FROM estado_diario_flota edf
--   JOIN activos a ON a.id = edf.activo_id
--   LEFT JOIN usuarios_perfil up ON up.id = edf.actualizado_por
--  WHERE edf.fecha BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
--    AND edf.override_manual = true
--  ORDER BY edf.fecha, a.codigo;


-- ============================================================================
-- FIN DEL ARCHIVO 54_flota_estado_programado_checklists.sql
-- ============================================================================
