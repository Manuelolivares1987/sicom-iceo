-- ============================================================================
-- SICOM-ICEO | Migración 31 — Perfiles de Usuario Extendidos
-- ============================================================================
-- Propósito : Agregar los roles operacionales reales del negocio:
--             - jefe_operaciones
--             - jefe_mantenimiento
--             - comercial
--             - prevencionista
--             - colaborador
--
-- Notas:
-- * Se mantienen los roles existentes (administrador, gerencia,
--   subgerente_operaciones, supervisor, etc.) para compatibilidad.
-- * Las políticas RLS de tablas nuevas (SUSPEL/RESPEL, migración 32)
--   usan fn_user_has_any_role() para validar.
-- * Los permisos por módulo en el frontend se manejan en use-permissions.ts
--   (matriz declarativa), mientras que RLS en Postgres filtra la BD.
-- ============================================================================

-- ============================================================================
-- 1. EXTENDER rol_usuario_enum CON NUEVOS ROLES
-- ============================================================================
-- ALTER TYPE ... ADD VALUE IF NOT EXISTS es idempotente y no bloquea
-- ALTER TYPE debe correr fuera de una transacción en versiones antiguas de
-- PostgreSQL; en Supabase (PG 15+) funciona dentro de un DO block.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumlabel = 'jefe_operaciones'
          AND enumtypid = 'rol_usuario_enum'::regtype
    ) THEN
        ALTER TYPE rol_usuario_enum ADD VALUE 'jefe_operaciones';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumlabel = 'jefe_mantenimiento'
          AND enumtypid = 'rol_usuario_enum'::regtype
    ) THEN
        ALTER TYPE rol_usuario_enum ADD VALUE 'jefe_mantenimiento';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumlabel = 'comercial'
          AND enumtypid = 'rol_usuario_enum'::regtype
    ) THEN
        ALTER TYPE rol_usuario_enum ADD VALUE 'comercial';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumlabel = 'prevencionista'
          AND enumtypid = 'rol_usuario_enum'::regtype
    ) THEN
        ALTER TYPE rol_usuario_enum ADD VALUE 'prevencionista';
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumlabel = 'colaborador'
          AND enumtypid = 'rol_usuario_enum'::regtype
    ) THEN
        ALTER TYPE rol_usuario_enum ADD VALUE 'colaborador';
    END IF;
END $$;

-- ============================================================================
-- 2. HELPER: fn_user_has_any_role(roles[])
-- ============================================================================
-- Verifica si el usuario autenticado tiene cualquiera de los roles
-- especificados. Útil para políticas RLS que combinan permisos.

CREATE OR REPLACE FUNCTION fn_user_has_any_role(p_roles TEXT[])
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_rol TEXT;
BEGIN
    v_rol := fn_user_rol();
    IF v_rol IS NULL THEN RETURN false; END IF;
    RETURN v_rol = ANY(p_roles);
END;
$$;

COMMENT ON FUNCTION fn_user_has_any_role(TEXT[]) IS
    'Retorna true si el usuario autenticado tiene alguno de los roles indicados.';

-- ============================================================================
-- 3. VISTAS DE COMODIDAD: agrupaciones frecuentes de roles
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_user_is_gerencia()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
    SELECT fn_user_has_any_role(ARRAY['administrador','gerencia','subgerente_operaciones']);
$$;

CREATE OR REPLACE FUNCTION fn_user_is_operaciones()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
    SELECT fn_user_has_any_role(ARRAY[
        'administrador','gerencia','subgerente_operaciones',
        'jefe_operaciones','supervisor','planificador'
    ]);
$$;

CREATE OR REPLACE FUNCTION fn_user_is_mantenimiento()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
    SELECT fn_user_has_any_role(ARRAY[
        'administrador','gerencia','subgerente_operaciones',
        'jefe_mantenimiento','supervisor','planificador','tecnico_mantenimiento'
    ]);
$$;

CREATE OR REPLACE FUNCTION fn_user_is_prevencion()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
    SELECT fn_user_has_any_role(ARRAY[
        'administrador','gerencia','subgerente_operaciones','prevencionista'
    ]);
$$;

CREATE OR REPLACE FUNCTION fn_user_is_comercial()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
    SELECT fn_user_has_any_role(ARRAY[
        'administrador','gerencia','subgerente_operaciones','comercial'
    ]);
$$;

-- ============================================================================
-- 4. PERMITIR OVERRIDE DE ESTADO SOLO A OPERACIONES / MANTENIMIENTO / ADMIN
-- ============================================================================
-- Refactorizamos rpc_actualizar_estado_diario_manual (creada en migración 30)
-- para que valide el rol antes de escribir.

CREATE OR REPLACE FUNCTION rpc_actualizar_estado_diario_manual(
    p_activo_id        UUID,
    p_fecha            DATE,
    p_nuevo_estado     CHAR(1),
    p_motivo           TEXT,
    p_crear_ot         BOOLEAN DEFAULT false,
    p_ot_tipo          tipo_ot_enum DEFAULT NULL,
    p_ot_prioridad     prioridad_enum DEFAULT 'normal',
    p_ot_responsable_id UUID DEFAULT NULL,
    p_ot_descripcion   TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_activo RECORD;
    v_ot_id UUID;
    v_ot_folio VARCHAR;
    v_existente UUID;
BEGIN
    -- Validar rol: solo operaciones, mantenimiento, gerencia o admin
    IF NOT fn_user_has_any_role(ARRAY[
        'administrador','gerencia','subgerente_operaciones',
        'jefe_operaciones','jefe_mantenimiento','supervisor','planificador'
    ]) THEN
        RAISE EXCEPTION 'No tiene permisos para modificar el estado de equipos. Rol actual: %', fn_user_rol();
    END IF;

    v_user_id := auth.uid();

    IF p_nuevo_estado NOT IN ('A','D','H','R','M','T','F','V','U','L') THEN
        RAISE EXCEPTION 'Estado código inválido: %', p_nuevo_estado;
    END IF;

    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id;
    END IF;

    IF p_crear_ot AND p_nuevo_estado IN ('M','T') THEN
        IF p_ot_tipo IS NULL THEN
            p_ot_tipo := CASE WHEN p_nuevo_estado = 'T' THEN 'correctivo'
                              ELSE 'preventivo' END;
        END IF;

        v_ot_folio := 'OT-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS') || '-' ||
                      SUBSTRING(p_activo_id::TEXT, 1, 4);

        INSERT INTO ordenes_trabajo (
            folio, tipo, contrato_id, faena_id, activo_id,
            prioridad, estado, responsable_id,
            fecha_programada, observaciones,
            generada_automaticamente, created_by
        ) VALUES (
            v_ot_folio, p_ot_tipo,
            v_activo.contrato_id, v_activo.faena_id, p_activo_id,
            p_ot_prioridad, 'creada', p_ot_responsable_id,
            p_fecha, COALESCE(p_ot_descripcion, p_motivo),
            true, v_user_id
        )
        RETURNING id INTO v_ot_id;
    END IF;

    SELECT id INTO v_existente
    FROM estado_diario_flota
    WHERE activo_id = p_activo_id AND fecha = p_fecha;

    IF v_existente IS NULL THEN
        INSERT INTO estado_diario_flota (
            activo_id, fecha, contrato_id, estado_codigo,
            cliente, ubicacion, operacion,
            override_manual, motivo_override, calculado_auto,
            actualizado_por, actualizado_at,
            ot_relacionada_id, observacion, registrado_por
        ) VALUES (
            p_activo_id, p_fecha, v_activo.contrato_id, p_nuevo_estado,
            v_activo.cliente_actual, v_activo.ubicacion_actual, v_activo.operacion,
            true, p_motivo, false,
            v_user_id, NOW(),
            v_ot_id, p_motivo, v_user_id
        );
    ELSE
        UPDATE estado_diario_flota
        SET estado_codigo = p_nuevo_estado,
            override_manual = true,
            motivo_override = p_motivo,
            actualizado_por = v_user_id,
            actualizado_at = NOW(),
            ot_relacionada_id = COALESCE(v_ot_id, ot_relacionada_id),
            observacion = p_motivo,
            updated_at = NOW()
        WHERE id = v_existente;
    END IF;

    IF p_nuevo_estado = 'F' AND v_activo.estado_comercial = 'arrendado' THEN
        INSERT INTO no_conformidades (
            activo_id, fecha_evento, tipo, severidad, descripcion, created_by
        ) VALUES (
            p_activo_id, p_fecha, 'falla_en_terreno', 'alta',
            'Equipo arrendado pasa a fuera de servicio: ' || COALESCE(p_motivo,'sin motivo'),
            v_user_id
        )
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'estado_aplicado', p_nuevo_estado,
        'ot_creada', v_ot_id IS NOT NULL,
        'ot_id', v_ot_id,
        'ot_folio', v_ot_folio
    );
END;
$$;

-- ============================================================================
-- 5. DOCUMENTACIÓN DE LA MATRIZ DE PERMISOS POR ROL NUEVO
-- ============================================================================
-- Esta tabla es solo documentación viva. No se usa en lógica.

CREATE TABLE IF NOT EXISTS _roles_matriz_permisos (
    rol           VARCHAR(40) PRIMARY KEY,
    modulo_flota  VARCHAR(20),
    modulo_ots    VARCHAR(20),
    modulo_kpis   VARCHAR(20),
    modulo_normativa VARCHAR(20),
    modulo_comercial VARCHAR(20),
    modulo_admin  VARCHAR(20),
    notas         TEXT
);

INSERT INTO _roles_matriz_permisos VALUES
    ('administrador',        'admin','admin','admin','admin','admin','admin', 'Acceso total'),
    ('gerencia',             'read','read','read','read','read','read',       'Gerencia general, solo lectura'),
    ('subgerente_operaciones','read','write','write','read','read','read',    'Gerencia operacional'),
    ('jefe_operaciones',     'write','write','read','read','none','none',     'Cambia estados, asigna OTs'),
    ('jefe_mantenimiento',   'read','write','read','read','none','none',      'Crea y cierra OTs'),
    ('comercial',            'read','none','none','none','write','none',      'Solo ve flota + comercial'),
    ('prevencionista',       'read','read','none','write','none','none',      'Gestiona SUSPEL / RESPEL / cert.'),
    ('colaborador',          'read','read','none','none','none','none',       'Solo lectura básica'),
    ('supervisor',           'read','write','read','read','none','none',      'Supervisor de faena'),
    ('planificador',         'read','write','read','read','none','none',      'Planifica mantenciones'),
    ('tecnico_mantenimiento','none','write','none','none','none','none',      'Ejecuta OTs asignadas'),
    ('bodeguero',            'none','read','none','none','none','none',       'Solo inventario'),
    ('operador_abastecimiento','none','read','none','none','none','none',     'Combustibles'),
    ('auditor',              'read','read','read','read','read','none',       'Solo lectura auditor'),
    ('rrhh_incentivos',      'none','none','read','none','none','none',       'Solo KPIs')
ON CONFLICT (rol) DO UPDATE SET
    modulo_flota    = EXCLUDED.modulo_flota,
    modulo_ots      = EXCLUDED.modulo_ots,
    modulo_kpis     = EXCLUDED.modulo_kpis,
    modulo_normativa = EXCLUDED.modulo_normativa,
    modulo_comercial = EXCLUDED.modulo_comercial,
    modulo_admin    = EXCLUDED.modulo_admin,
    notas           = EXCLUDED.notas;
