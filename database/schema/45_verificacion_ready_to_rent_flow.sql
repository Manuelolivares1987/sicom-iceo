-- ============================================================================
-- SICOM-ICEO | Migracion 45 — Flujo Ready-to-Rent completo
-- ============================================================================
-- Completa el flujo de certificacion pre-arriendo:
--
--  (1) Amplia verificaciones_disponibilidad con campos de road test y
--      evidencias.
--  (2) CHECK: el aprobador NO puede ser el mismo que ejecuta (doble firma
--      obligatoria, como en MRO aeronautico y Ryder).
--  (3) RPC fn_iniciar_verificacion_disponibilidad: crea OT tipo
--      'verificacion_disponibilidad' (auto-asigna los 55 items de la
--      plantilla via logica existente en mig 22) y devuelve ot_id.
--  (4) RPC fn_aprobar_verificacion_disponibilidad: valida el checklist
--      (todos los obligatorios en 'ok'), exige road test completo,
--      impone doble firma, crea la verificacion vigente por N dias
--      (default 3 = 72h, estandar rental), y cierra la OT.
--  (5) Vista v_verificaciones_pendientes: OTs de verificacion en curso
--      para el Jefe de Taller.
-- ============================================================================

-- ============================================================================
-- 1. AMPLIAR verificaciones_disponibilidad
-- ============================================================================

ALTER TABLE verificaciones_disponibilidad
    ADD COLUMN IF NOT EXISTS horometro_inicial     NUMERIC(12,2),
    ADD COLUMN IF NOT EXISTS horometro_final       NUMERIC(12,2),
    ADD COLUMN IF NOT EXISTS km_inicial            NUMERIC(12,2),
    ADD COLUMN IF NOT EXISTS km_final              NUMERIC(12,2),
    ADD COLUMN IF NOT EXISTS road_test_minutos     INTEGER,
    ADD COLUMN IF NOT EXISTS road_test_observacion TEXT,
    ADD COLUMN IF NOT EXISTS evidencias_fotos      JSONB NOT NULL DEFAULT '[]'::JSONB,
    ADD COLUMN IF NOT EXISTS firma_tecnico_url     TEXT,
    ADD COLUMN IF NOT EXISTS firma_aprobador_url   TEXT;

-- Default de vigencia 3 dias (72h) — estandar rental industry.
ALTER TABLE verificaciones_disponibilidad
    ALTER COLUMN dias_vigencia SET DEFAULT 3;

-- Constraint de doble firma: el tecnico ejecutor no puede aprobar su
-- propia verificacion.
ALTER TABLE verificaciones_disponibilidad
    DROP CONSTRAINT IF EXISTS chk_doble_firma;

ALTER TABLE verificaciones_disponibilidad
    ADD CONSTRAINT chk_doble_firma
    CHECK (
        aprobado_por IS NULL
        OR verificado_por IS NULL
        OR aprobado_por != verificado_por
    );

COMMENT ON CONSTRAINT chk_doble_firma ON verificaciones_disponibilidad IS
    'CAR-145 / ISO 55000: el que ejecuta la verificacion no puede firmar '
    'la aprobacion. Doble firma obligatoria.';


-- ============================================================================
-- 2. RPC — iniciar verificacion (crea la OT con checklist)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_iniciar_verificacion_disponibilidad(
    p_activo_id     UUID,
    p_motivo        TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id        UUID;
    v_activo         RECORD;
    v_contrato_id    UUID;
    v_faena_id       UUID;
    v_ot_id          UUID;
    v_ot_folio       VARCHAR;
    v_periodo        VARCHAR(6);
    v_secuencia      INTEGER;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;

    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id;
    END IF;

    -- Reutilizar fallback INTERNO (mig 38) si no tiene contrato/faena
    v_contrato_id := COALESCE(v_activo.contrato_id, fn_contrato_interno_id());
    v_faena_id    := COALESCE(v_activo.faena_id,    fn_faena_interna_id());

    -- Folio con patron estandar (mig 39)
    PERFORM pg_advisory_xact_lock(hashtext('ot_folio_lock'));
    v_periodo := TO_CHAR(NOW(), 'YYYYMM');
    SELECT COALESCE(MAX(
        CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)
    ), 0) + 1
    INTO v_secuencia
    FROM ordenes_trabajo
    WHERE folio LIKE 'OT-' || v_periodo || '-%';

    v_ot_folio := 'OT-' || v_periodo || '-' || LPAD(v_secuencia::TEXT, 5, '0');

    -- Crear la OT (el trigger de mig 22 asigna el checklist de 55 items
    -- automaticamente porque el tipo es verificacion_disponibilidad)
    INSERT INTO ordenes_trabajo (
        folio, tipo, contrato_id, faena_id, activo_id,
        prioridad, estado,
        fecha_programada, observaciones,
        generada_automaticamente, created_by
    ) VALUES (
        v_ot_folio, 'verificacion_disponibilidad'::tipo_ot_enum,
        v_contrato_id, v_faena_id, p_activo_id,
        'alta'::prioridad_enum, 'creada'::estado_ot_enum,
        CURRENT_DATE,
        COALESCE(p_motivo, 'Verificacion ready-to-rent antes de marcar disponible'),
        true, v_user_id
    )
    RETURNING id INTO v_ot_id;

    -- Placeholder en verificaciones_disponibilidad (estado pendiente)
    INSERT INTO verificaciones_disponibilidad (
        activo_id, ot_id, contrato_id, resultado, verificado_por,
        dias_vigencia
    ) VALUES (
        p_activo_id, v_ot_id, v_contrato_id, 'pendiente', v_user_id, 3
    );

    RETURN jsonb_build_object(
        'success', true,
        'ot_id',    v_ot_id,
        'ot_folio', v_ot_folio,
        'activo_id', p_activo_id,
        'patente',   v_activo.patente
    );
END;
$$;


-- ============================================================================
-- 3. RPC — aprobar verificacion (emite el certificado)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_aprobar_verificacion_disponibilidad(
    p_ot_id                  UUID,
    p_horometro_inicial      NUMERIC DEFAULT NULL,
    p_horometro_final        NUMERIC DEFAULT NULL,
    p_km_inicial             NUMERIC DEFAULT NULL,
    p_km_final               NUMERIC DEFAULT NULL,
    p_road_test_minutos      INTEGER DEFAULT NULL,
    p_road_test_observacion  TEXT DEFAULT NULL,
    p_firma_tecnico_url      TEXT DEFAULT NULL,
    p_firma_aprobador_url    TEXT DEFAULT NULL,
    p_dias_vigencia          INTEGER DEFAULT 3
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_aprobador_id    UUID;
    v_ot              RECORD;
    v_verif           RECORD;
    v_total_items     INTEGER;
    v_ok_items        INTEGER;
    v_no_ok_items     INTEGER;
    v_obligat_pend    INTEGER;
    v_vigente_hasta   TIMESTAMPTZ;
BEGIN
    v_aprobador_id := auth.uid();
    IF v_aprobador_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;

    -- Cargar OT y verificacion asociada
    SELECT * INTO v_ot FROM ordenes_trabajo WHERE id = p_ot_id;
    IF NOT FOUND OR v_ot.tipo != 'verificacion_disponibilidad' THEN
        RAISE EXCEPTION 'OT % no existe o no es de tipo verificacion_disponibilidad', p_ot_id;
    END IF;

    SELECT * INTO v_verif
      FROM verificaciones_disponibilidad
     WHERE ot_id = p_ot_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe verificacion asociada a la OT %', p_ot_id;
    END IF;

    -- VALIDACION 1: doble firma (aprobador != ejecutor)
    IF v_verif.verificado_por IS NOT NULL
       AND v_verif.verificado_por = v_aprobador_id THEN
        RAISE EXCEPTION 'No puede aprobar su propia verificacion. Requiere firma de un supervisor distinto.';
    END IF;

    -- VALIDACION 2: road test obligatorio
    IF p_horometro_inicial IS NULL OR p_horometro_final IS NULL
       OR p_road_test_minutos IS NULL OR p_road_test_minutos < 5 THEN
        RAISE EXCEPTION 'Road test incompleto: se requieren horometro inicial/final y minimo 5 minutos de prueba.';
    END IF;

    IF p_horometro_final <= p_horometro_inicial THEN
        RAISE EXCEPTION 'Horometro final debe ser mayor al inicial (% <= %).',
            p_horometro_final, p_horometro_inicial;
    END IF;

    -- VALIDACION 3: todos los items obligatorios del checklist en 'ok'
    SELECT COUNT(*)                                           AS total,
           COUNT(*) FILTER (WHERE resultado = 'ok')          AS ok_count,
           COUNT(*) FILTER (WHERE resultado = 'no_ok')       AS no_ok_count,
           COUNT(*) FILTER (WHERE obligatorio = true
                            AND (resultado IS NULL OR resultado != 'ok'
                                 AND resultado != 'na'))      AS obligat_pend
      INTO v_total_items, v_ok_items, v_no_ok_items, v_obligat_pend
      FROM checklist_ot
     WHERE ot_id = p_ot_id;

    IF v_total_items = 0 THEN
        RAISE EXCEPTION 'La OT no tiene items de checklist asignados.';
    END IF;

    IF v_obligat_pend > 0 THEN
        RAISE EXCEPTION 'Quedan % items obligatorios sin resultado "ok" o "na".', v_obligat_pend;
    END IF;

    IF v_no_ok_items > 0 THEN
        RAISE EXCEPTION 'Hay % items marcados como NO OK. Corregir antes de aprobar.', v_no_ok_items;
    END IF;

    -- Todo OK — emitir certificado
    v_vigente_hasta := NOW() + (COALESCE(p_dias_vigencia, 3) || ' days')::INTERVAL;

    UPDATE verificaciones_disponibilidad
       SET resultado              = 'aprobado',
           puntaje_total          = v_ok_items,
           items_total            = v_total_items,
           items_ok               = v_ok_items,
           items_no_ok            = v_no_ok_items,
           items_na               = v_total_items - v_ok_items - v_no_ok_items,
           fecha_verificacion     = NOW(),
           vigente_hasta          = v_vigente_hasta,
           dias_vigencia          = COALESCE(p_dias_vigencia, 3),
           aprobado_por           = v_aprobador_id,
           aprobado_en            = NOW(),
           horometro_inicial      = p_horometro_inicial,
           horometro_final        = p_horometro_final,
           km_inicial             = p_km_inicial,
           km_final               = p_km_final,
           road_test_minutos      = p_road_test_minutos,
           road_test_observacion  = p_road_test_observacion,
           firma_tecnico_url      = p_firma_tecnico_url,
           firma_aprobador_url    = p_firma_aprobador_url,
           updated_at             = NOW()
     WHERE id = v_verif.id;

    -- Cerrar la OT como ejecutada OK (sin disparar trigger de estado)
    UPDATE ordenes_trabajo
       SET estado        = 'ejecutada_ok',
           fecha_termino = NOW(),
           updated_at    = NOW()
     WHERE id = p_ot_id;

    -- Sincronizar el activo: registra la verificacion vigente.
    -- No cambiamos estado_comercial aqui — eso es responsabilidad de quien
    -- decida marcar el equipo disponible (generalmente comercial). El
    -- trigger de mig 44 validara la vigencia en ese momento.
    UPDATE activos
       SET ultima_verificacion_id    = v_verif.id,
           verificacion_vigente_hasta = v_vigente_hasta,
           updated_at                 = NOW()
     WHERE id = v_ot.activo_id;

    RETURN jsonb_build_object(
        'success',       true,
        'verificacion_id', v_verif.id,
        'activo_id',     v_ot.activo_id,
        'vigente_hasta', v_vigente_hasta,
        'items_ok',      v_ok_items,
        'items_total',   v_total_items
    );
END;
$$;


-- ============================================================================
-- 4. Vista: verificaciones en curso (para Jefe de Taller)
-- ============================================================================

CREATE OR REPLACE VIEW v_verificaciones_pendientes AS
SELECT
    vd.id                     AS verificacion_id,
    vd.activo_id,
    a.patente,
    a.codigo,
    a.nombre                  AS equipo,
    vd.ot_id,
    ot.folio                  AS ot_folio,
    ot.estado                 AS ot_estado,
    vd.resultado,
    vd.verificado_por,
    up.nombre_completo        AS tecnico_nombre,
    vd.created_at,
    vd.fecha_verificacion,
    -- Progreso del checklist
    (
        SELECT jsonb_build_object(
            'total', COUNT(*),
            'ok',    COUNT(*) FILTER (WHERE resultado = 'ok'),
            'no_ok', COUNT(*) FILTER (WHERE resultado = 'no_ok'),
            'na',    COUNT(*) FILTER (WHERE resultado = 'na'),
            'pendientes', COUNT(*) FILTER (WHERE resultado IS NULL)
        )
        FROM checklist_ot WHERE ot_id = vd.ot_id
    ) AS checklist_progreso
FROM verificaciones_disponibilidad vd
JOIN activos a ON a.id = vd.activo_id
LEFT JOIN ordenes_trabajo ot ON ot.id = vd.ot_id
LEFT JOIN usuarios_perfil up ON up.id = vd.verificado_por
WHERE vd.resultado = 'pendiente'
   OR (vd.resultado = 'aprobado' AND vd.vigente_hasta <= NOW());

COMMENT ON VIEW v_verificaciones_pendientes IS
    'Verificaciones en curso (pendientes) o que caducaron y requieren '
    're-verificacion. Lista de trabajo para el Jefe de Taller.';


-- ============================================================================
-- 5. SMOKE TEST
-- ============================================================================

DO $$
DECLARE
    v_ok_cols        BOOLEAN;
    v_ok_constraint  BOOLEAN;
    v_ok_fn_iniciar  BOOLEAN;
    v_ok_fn_aprobar  BOOLEAN;
    v_ok_view        BOOLEAN;
BEGIN
    SELECT COUNT(*) = 9
      INTO v_ok_cols
      FROM information_schema.columns
     WHERE table_name = 'verificaciones_disponibilidad'
       AND column_name IN (
           'horometro_inicial','horometro_final','km_inicial','km_final',
           'road_test_minutos','road_test_observacion','evidencias_fotos',
           'firma_tecnico_url','firma_aprobador_url'
       );

    SELECT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'chk_doble_firma'
    ) INTO v_ok_constraint;

    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_iniciar_verificacion_disponibilidad')
      INTO v_ok_fn_iniciar;
    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_aprobar_verificacion_disponibilidad')
      INTO v_ok_fn_aprobar;
    SELECT EXISTS (SELECT 1 FROM pg_views WHERE viewname = 'v_verificaciones_pendientes')
      INTO v_ok_view;

    RAISE NOTICE '== Migracion 45 ==';
    RAISE NOTICE 'Columnas road-test agregadas .... %', v_ok_cols;
    RAISE NOTICE 'Constraint doble firma .......... %', v_ok_constraint;
    RAISE NOTICE 'fn_iniciar_verificacion ......... %', v_ok_fn_iniciar;
    RAISE NOTICE 'fn_aprobar_verificacion ......... %', v_ok_fn_aprobar;
    RAISE NOTICE 'v_verificaciones_pendientes ..... %', v_ok_view;

    IF NOT (v_ok_cols AND v_ok_constraint AND v_ok_fn_iniciar AND v_ok_fn_aprobar AND v_ok_view) THEN
        RAISE EXCEPTION 'Migracion 45 incompleta.';
    END IF;
END $$;
