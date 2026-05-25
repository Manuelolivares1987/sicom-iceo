-- ============================================================================
-- 89_historial_os_legacy.sql
-- ----------------------------------------------------------------------------
-- Tabla para importar el historial de Ordenes de Servicio (OS) de
-- mantenimiento previo al sistema digital. Origen: "Historico OS Auditoria.xlsx"
-- hoja "Detalle OS" (234 OS de 2025-2026).
--
-- Decisiones de Manuel (2026-05-24):
--  - Patentes que NO matchean con activos.patente: importar igual con
--    activo_id=NULL. No aparecen en ficha de ningun activo, pero quedan
--    en consultas/reportes globales.
--  - Re-importacion: UNIQUE(os_numero) DO NOTHING. Si ya esta, se ignora.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Tabla ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS historial_os_legacy (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Identificacion OS
    anio                INT,
    os_numero           VARCHAR(20)  NOT NULL,
    os_cqbo             VARCHAR(40),

    -- Equipo
    patente_raw         VARCHAR(40),                  -- como vino del Excel
    activo_id           UUID REFERENCES activos(id),  -- matcheado por patente normalizada
    tipo_equipo         VARCHAR(80),
    marca_modelo        VARCHAR(120),

    -- Contexto
    faena               VARCHAR(120),
    cliente             VARCHAR(120),
    ubicacion           VARCHAR(120),

    -- Tiempo
    fecha_recepcion     DATE,
    fecha_entrega       DATE,

    -- Lecturas
    horometro           NUMERIC(12,2),
    kilometraje         NUMERIC(12,2),

    -- Resultado
    cumplimiento_pct    NUMERIC(5,2),
    responsable         VARCHAR(120),

    -- Flags tipo de trabajo
    flag_mant_prev      BOOLEAN NOT NULL DEFAULT false,
    flag_correctivo     BOOLEAN NOT NULL DEFAULT false,
    flag_neumaticos     BOOLEAN NOT NULL DEFAULT false,
    flag_rev_tec        BOOLEAN NOT NULL DEFAULT false,
    flag_hab_estado     BOOLEAN NOT NULL DEFAULT false,
    flag_serv_externo   BOOLEAN NOT NULL DEFAULT false,

    -- Volumen
    num_trabajos        INT,
    horas_mo            NUMERIC(8,2),

    -- Auditoria
    imported_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    imported_by         UUID REFERENCES auth.users(id),

    CONSTRAINT uq_historial_os_numero UNIQUE (os_numero)
);

CREATE INDEX IF NOT EXISTS idx_historial_os_activo
    ON historial_os_legacy (activo_id) WHERE activo_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_historial_os_patente
    ON historial_os_legacy (patente_raw);
CREATE INDEX IF NOT EXISTS idx_historial_os_fecha
    ON historial_os_legacy (fecha_recepcion DESC NULLS LAST);

COMMENT ON TABLE historial_os_legacy IS
    'Historial de OS de mantenimiento previo al sistema digital. Origen: Historico OS Auditoria.xlsx. MIG89.';


-- ── 2. RPC para importacion en batch ────────────────────────────────────────
-- Recibe un jsonb array. Por cada OS:
--  - Normaliza patente (trim + uppercase)
--  - Busca activo_id en activos.patente (case-insensitive)
--  - INSERT ON CONFLICT (os_numero) DO NOTHING
-- Retorna conteos: insertadas, ignoradas, con_activo, sin_activo
CREATE OR REPLACE FUNCTION rpc_importar_historial_os_legacy(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT;
    v_os   jsonb;
    v_activo_id UUID;
    v_inserted INT := 0;
    v_ignored  INT := 0;
    v_with_a   INT := 0;
    v_without_a INT := 0;
    v_patente_norm TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para importar historial OS legacy', v_rol;
    END IF;

    IF jsonb_typeof(p_payload) <> 'array' THEN
        RAISE EXCEPTION 'p_payload debe ser un array jsonb';
    END IF;

    FOR v_os IN SELECT * FROM jsonb_array_elements(p_payload) LOOP
        v_patente_norm := UPPER(TRIM(COALESCE(v_os->>'patente_raw', '')));
        IF v_patente_norm = '' THEN
            v_activo_id := NULL;
        ELSE
            SELECT id INTO v_activo_id
              FROM activos
             WHERE UPPER(TRIM(patente)) = v_patente_norm
             LIMIT 1;
        END IF;

        IF v_activo_id IS NOT NULL THEN v_with_a := v_with_a + 1;
        ELSE                            v_without_a := v_without_a + 1;
        END IF;

        BEGIN
            INSERT INTO historial_os_legacy (
                anio, os_numero, os_cqbo,
                patente_raw, activo_id, tipo_equipo, marca_modelo,
                faena, cliente, ubicacion,
                fecha_recepcion, fecha_entrega,
                horometro, kilometraje,
                cumplimiento_pct, responsable,
                flag_mant_prev, flag_correctivo, flag_neumaticos,
                flag_rev_tec, flag_hab_estado, flag_serv_externo,
                num_trabajos, horas_mo,
                imported_by
            ) VALUES (
                NULLIF(v_os->>'anio','')::INT,
                v_os->>'os_numero',
                v_os->>'os_cqbo',
                v_os->>'patente_raw',
                v_activo_id,
                v_os->>'tipo_equipo',
                v_os->>'marca_modelo',
                v_os->>'faena',
                v_os->>'cliente',
                v_os->>'ubicacion',
                NULLIF(v_os->>'fecha_recepcion','')::DATE,
                NULLIF(v_os->>'fecha_entrega','')::DATE,
                NULLIF(v_os->>'horometro','')::NUMERIC,
                NULLIF(v_os->>'kilometraje','')::NUMERIC,
                NULLIF(v_os->>'cumplimiento_pct','')::NUMERIC,
                v_os->>'responsable',
                COALESCE((v_os->>'flag_mant_prev')::BOOLEAN, false),
                COALESCE((v_os->>'flag_correctivo')::BOOLEAN, false),
                COALESCE((v_os->>'flag_neumaticos')::BOOLEAN, false),
                COALESCE((v_os->>'flag_rev_tec')::BOOLEAN, false),
                COALESCE((v_os->>'flag_hab_estado')::BOOLEAN, false),
                COALESCE((v_os->>'flag_serv_externo')::BOOLEAN, false),
                NULLIF(v_os->>'num_trabajos','')::INT,
                NULLIF(v_os->>'horas_mo','')::NUMERIC,
                v_user
            )
            ON CONFLICT (os_numero) DO NOTHING;

            IF FOUND THEN v_inserted := v_inserted + 1;
            ELSE          v_ignored := v_ignored + 1;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            -- Si una OS falla por dato malo, no abortar todo. Solo contar.
            v_ignored := v_ignored + 1;
            RAISE NOTICE 'OS % fallo: %', v_os->>'os_numero', SQLERRM;
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'success',           true,
        'insertadas',        v_inserted,
        'ignoradas',         v_ignored,
        'con_activo_match',  v_with_a,
        'sin_activo_match',  v_without_a,
        'total_procesadas',  v_inserted + v_ignored
    );
END;
$$;

COMMENT ON FUNCTION rpc_importar_historial_os_legacy IS
    'Importa OS legacy en batch. ON CONFLICT(os_numero) DO NOTHING. Matchea activo_id por patente normalizada. MIG89.';


-- ── 3. Vista enriquecida (para la ficha del activo) ────────────────────────
DROP VIEW IF EXISTS v_historial_os_legacy_activo CASCADE;
CREATE VIEW v_historial_os_legacy_activo AS
SELECT
    h.id,
    h.activo_id,
    h.anio,
    h.os_numero,
    h.os_cqbo,
    h.patente_raw,
    h.tipo_equipo,
    h.marca_modelo,
    h.faena,
    h.cliente,
    h.ubicacion,
    h.fecha_recepcion,
    h.fecha_entrega,
    h.horometro,
    h.kilometraje,
    h.cumplimiento_pct,
    h.responsable,
    h.flag_mant_prev,
    h.flag_correctivo,
    h.flag_neumaticos,
    h.flag_rev_tec,
    h.flag_hab_estado,
    h.flag_serv_externo,
    h.num_trabajos,
    h.horas_mo,
    -- Etiqueta legible del tipo principal de trabajo
    CASE
        WHEN h.flag_mant_prev    THEN 'Mantención preventiva'
        WHEN h.flag_correctivo   THEN 'Correctivo'
        WHEN h.flag_rev_tec      THEN 'Revisión técnica'
        WHEN h.flag_hab_estado   THEN 'Habilitación/Estado'
        WHEN h.flag_neumaticos   THEN 'Neumáticos'
        WHEN h.flag_serv_externo THEN 'Servicio externo'
        ELSE                          'Otro'
    END AS tipo_principal
FROM historial_os_legacy h;

GRANT SELECT  ON historial_os_legacy           TO authenticated;
GRANT SELECT  ON v_historial_os_legacy_activo  TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_importar_historial_os_legacy(jsonb) TO authenticated;


-- ── 4. RLS ──────────────────────────────────────────────────────────────────
ALTER TABLE historial_os_legacy ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_hos_select ON historial_os_legacy;
CREATE POLICY pol_hos_select ON historial_os_legacy
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_hos_write ON historial_os_legacy;
CREATE POLICY pol_hos_write ON historial_os_legacy
    FOR ALL TO authenticated
    USING      (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'))
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'));


SELECT
    'tabla_creada'     AS check_name, EXISTS(SELECT 1 FROM information_schema.tables
                                              WHERE table_schema='public' AND table_name='historial_os_legacy') AS ok
UNION ALL SELECT 'rpc_creada',  EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_importar_historial_os_legacy')
UNION ALL SELECT 'vista_creada',EXISTS(SELECT 1 FROM information_schema.views WHERE table_name='v_historial_os_legacy_activo');

NOTIFY pgrst, 'reload schema';
