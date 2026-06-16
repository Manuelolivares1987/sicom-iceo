-- ============================================================================
-- SICOM-ICEO | 142 — Checklist de Inspeccion Unificado (esquema)
-- ----------------------------------------------------------------------------
-- Parte 1 de 2. Prepara el terreno para que el "Check-List de Recepcion" del
-- Excel oficial (Camion Aljibe Agua Industrial - Revisado) sea la UNICA lista
-- de inspeccion: misma plantilla para RECEPCION y CALIDAD. De sus items no_ok
-- nacen las No Conformidades.
--
-- Aqui solo: (a) se agregan los bloques que faltan al enum, (b) se agregan las
-- columnas nuevas a los items (tiempo en minutos, orden de bloque, categoria de
-- calidad, critico, cert_tipo, tipo de prueba), (c) se registra el template
-- CL-INSPECCION-V03. El SEED de los ~190 items y el cableado de los quality
-- gates van en 143_checklist_inspeccion_unificado_seed.sql.
--
-- IMPORTANTE: Postgres no permite USAR un valor de enum recien agregado en la
-- misma transaccion. Por eso esto va en un archivo aparte (commit) y el seed que
-- referencia los nuevos bloques va en 143. Correr 142 ANTES que 143.
--
-- IDEMPOTENTE: ADD VALUE IF NOT EXISTS / ADD COLUMN IF NOT EXISTS / ON CONFLICT.
-- ============================================================================

-- ── 0. Precheck ──────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF to_regclass('public.checklist_template_v2')      IS NULL
    OR to_regclass('public.checklist_template_v2_item') IS NULL THEN
        RAISE EXCEPTION 'STOP - faltan tablas checklist_template_v2 (aplicar MIG 54).';
    END IF;
END $$;


-- ── 1. Bloques nuevos del enum (los del Excel que no existian) ───────────────
-- Excel: B1 Doc, B2 Exterior, B3 Motor, B4 ELECTRICO, B5 FUGAS, B6 Sistema
-- equipo, B7 Seguridad activa, B8 Diagnostico, B9 INVENTARIO, B10 KIT INVIERNO,
-- (NUEVO) Pruebas operativas, B11 Cierre.
-- Mapeo a enum existente: B1->b1_documentacion, B2->b2_estado_exterior,
-- B3->b3_motor_niveles, B6->b4_sistema_equipo, B7->b5_seguridad_activa,
-- B8->b6_diagnostico_electronico, B11->b7_cierre_recepcion.
-- Faltan -> se agregan aqui:
ALTER TYPE bloque_checklist_enum ADD VALUE IF NOT EXISTS 'b_sistema_electrico';
ALTER TYPE bloque_checklist_enum ADD VALUE IF NOT EXISTS 'b_fugas';
ALTER TYPE bloque_checklist_enum ADD VALUE IF NOT EXISTS 'b_inventario_seguridad';
ALTER TYPE bloque_checklist_enum ADD VALUE IF NOT EXISTS 'b_kit_invierno';
ALTER TYPE bloque_checklist_enum ADD VALUE IF NOT EXISTS 'b_pruebas_operativas';


-- ── 2. Tipo de prueba operativa (ruta / recirculacion / regadio) ─────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='prueba_operativa_enum') THEN
        CREATE TYPE prueba_operativa_enum AS ENUM (
            'ruta',          -- prueba de ruta / marcha (equipos rodantes)
            'recirculacion', -- recirculacion de producto (aljibe agua / combustible)
            'regadio'        -- regadio: aspersores / barra / canon (aljibe agua)
        );
    END IF;
END $$;


-- ── 3. Columnas nuevas en checklist_template_v2_item ─────────────────────────
ALTER TABLE checklist_template_v2_item
    ADD COLUMN IF NOT EXISTS tiempo_min        INT,                      -- minutos de la pestana Recepcion del Excel
    ADD COLUMN IF NOT EXISTS bloque_orden      INT  NOT NULL DEFAULT 99, -- orden de despliegue del bloque (no depende del enum)
    ADD COLUMN IF NOT EXISTS categoria_calidad VARCHAR(20) NOT NULL DEFAULT 'tecnica', -- para el gate de calidad: tecnica|documentacion
    ADD COLUMN IF NOT EXISTS critico           BOOLEAN NOT NULL DEFAULT false,          -- item critico: bloquea aprobacion del gate
    ADD COLUMN IF NOT EXISTS cert_tipo         TEXT,                     -- si es documentacion: tipo de certificacion a auto-validar
    ADD COLUMN IF NOT EXISTS prueba_tipo       prueba_operativa_enum;    -- solo items del bloque Pruebas operativas

DO $$ BEGIN
    BEGIN
        ALTER TABLE checklist_template_v2_item DROP CONSTRAINT IF EXISTS chk_cl_v2_categoria_calidad;
        ALTER TABLE checklist_template_v2_item ADD CONSTRAINT chk_cl_v2_categoria_calidad
            CHECK (categoria_calidad IN ('tecnica','documentacion'));
    EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

COMMENT ON COLUMN checklist_template_v2_item.tiempo_min IS
    'Minutos estimados del item (pestana Recepcion del Excel oficial). Suma por bloque = subtotal; suma total = tiempo de recepcion.';
COMMENT ON COLUMN checklist_template_v2_item.bloque_orden IS
    'Orden de despliegue del bloque (1..N). Independiente del orden del enum, que no se puede reordenar.';
COMMENT ON COLUMN checklist_template_v2_item.categoria_calidad IS
    'Mapeo al gate de calidad: documentacion (B1) | tecnica (resto). Lo usa fn_iniciar_auditoria_calidad.';


-- ── 4. Registrar el template CL-INSPECCION-V03 (sin items todavia) ───────────
-- No se activa aqui para no chocar con el indice uq_cl_v2_momento_activo mientras
-- CL-RECEPCION-V02 sigue activo. El SEED (143) desactiva V02 y activa V03.
INSERT INTO checklist_template_v2 (codigo, nombre, momento_uso, version, descripcion, activo)
VALUES (
    'CL-INSPECCION-V03',
    'Check-List Inspeccion y Recepcion V03 (oficial - Excel revisado)',
    'recepcion_devolucion',
    'V03-2026',
    'Lista UNICA de inspeccion para recepcion Y calidad. 11 bloques del Excel oficial + pruebas operativas (ruta/recirculacion/regadio segun equipo), con tiempo en minutos por item. De los items no_ok nacen las No Conformidades.',
    false
) ON CONFLICT (codigo) DO UPDATE
    SET nombre = EXCLUDED.nombre, version = EXCLUDED.version, descripcion = EXCLUDED.descripcion;


-- ── 5. Validacion ────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    -- Lee el catalogo pg_enum (texto) para NO construir los valores de enum
    -- recien agregados en la misma transaccion (evita error 55P04).
    'enum_bloques_nuevos', (SELECT COUNT(*) FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
                            WHERE t.typname='bloque_checklist_enum'
                              AND e.enumlabel IN ('b_sistema_electrico','b_fugas','b_inventario_seguridad','b_kit_invierno','b_pruebas_operativas')),
    'enum_prueba',         (SELECT EXISTS(SELECT 1 FROM pg_type WHERE typname='prueba_operativa_enum')),
    'col_tiempo_min',      (SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='checklist_template_v2_item' AND column_name='tiempo_min')),
    'col_bloque_orden',    (SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='checklist_template_v2_item' AND column_name='bloque_orden')),
    'col_categoria_calidad',(SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='checklist_template_v2_item' AND column_name='categoria_calidad')),
    'col_prueba_tipo',     (SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='checklist_template_v2_item' AND column_name='prueba_tipo')),
    'tpl_v03',             (SELECT EXISTS(SELECT 1 FROM checklist_template_v2 WHERE codigo='CL-INSPECCION-V03'))
) AS resultado;

NOTIFY pgrst, 'reload schema';
