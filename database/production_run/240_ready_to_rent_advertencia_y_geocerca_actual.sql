-- ============================================================================
-- SICOM-ICEO | 240 — Ready-to-rent = advertencia (no bloqueo) + lugar por GPS
-- ----------------------------------------------------------------------------
-- Pedido Manuel (2026-07-22):
--   1) El gate ready-to-rent (marcar 'disponible' sin verificación) dejaba de
--      ser un BLOQUEO duro. Esa pega la hace el planificador; el sistema solo
--      debe ADVERTIR y registrar que se marcó disponible sin verificación
--      vigente, no impedirlo.
--   2) El modal de cambio de estado debe poder mostrar el LUGAR donde está el
--      equipo (nombre, no coordenada) usando el GPS: la geocerca en la que se
--      encuentra según su última posición.
--
-- Cambios:
--   A) fn_validar_cambio_disponible: REGLA A pasa de RAISE EXCEPTION a
--      RAISE WARNING (queda en el log de Postgres) + sigue vinculando la
--      verificación si existe. REGLA B (invalidar al salir de operativo),
--      REGLA C (invalidar al cambiar contrato) y REGLA D (LEY DS 298, >15 años
--      hazmat) se conservan INTACTAS — la legal sigue bloqueando.
--   B) fn_activo_geocerca_actual(p_activo_id): devuelve la geocerca actual del
--      equipo (nombre + ts del GPS) desde su última posición. NULL si no tiene
--      GPS o está fuera de toda geocerca.
--
-- IDEMPOTENTE (CREATE OR REPLACE).
-- ============================================================================

-- ── A. Gate de DISPONIBLE: de bloqueo a advertencia ─────────────────────────
CREATE OR REPLACE FUNCTION public.fn_validar_cambio_disponible()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- ═══════════════════════════════════════════════════════════════
    -- REGLA A: marcar 'disponible' sin verificacion vigente.
    --   YA NO BLOQUEA (decisión Manuel 2026-07-22): la verificación la
    --   gestiona el planificador. Se ADVIERTE y se registra en el log,
    --   pero se permite el cambio.
    -- ═══════════════════════════════════════════════════════════════
    IF NEW.estado_comercial = 'disponible'
       AND (OLD.estado_comercial IS NULL OR OLD.estado_comercial != 'disponible')
    THEN
        -- Vincular la verificacion vigente si existe.
        SELECT vd.id, vd.vigente_hasta
        INTO NEW.ultima_verificacion_id, NEW.verificacion_vigente_hasta
        FROM verificaciones_disponibilidad vd
        WHERE vd.activo_id = NEW.id
          AND vd.resultado = 'aprobado'
          AND vd.vigente_hasta > NOW()
        ORDER BY vd.vigente_hasta DESC
        LIMIT 1;

        -- Si no hay verificacion vigente: advertir (no bloquear).
        IF NEW.ultima_verificacion_id IS NULL THEN
            RAISE WARNING
                'READY-TO-RENT: el equipo % se marca DISPONIBLE sin verificacion '
                'de disponibilidad vigente. El planificador debe gestionarla.',
                COALESCE(NEW.patente, NEW.codigo, NEW.id::text);
        END IF;
    END IF;

    -- ═══════════════════════════════════════════════════════════════
    -- REGLA B: al salir de 'operativo' invalidar la verificacion vigente.
    -- ═══════════════════════════════════════════════════════════════
    IF TG_OP = 'UPDATE'
       AND OLD.estado = 'operativo'
       AND NEW.estado IN ('en_mantenimiento', 'fuera_servicio')
    THEN
        UPDATE verificaciones_disponibilidad
           SET vigente_hasta = NOW()
         WHERE activo_id = NEW.id
           AND resultado = 'aprobado'
           AND vigente_hasta > NOW();

        NEW.ultima_verificacion_id := NULL;
        NEW.verificacion_vigente_hasta := NULL;
    END IF;

    -- ═══════════════════════════════════════════════════════════════
    -- REGLA C: al cambiar contrato, invalidar verificacion anterior.
    -- ═══════════════════════════════════════════════════════════════
    IF TG_OP = 'UPDATE'
       AND OLD.contrato_id IS DISTINCT FROM NEW.contrato_id
       AND NEW.contrato_id IS NOT NULL
    THEN
        UPDATE verificaciones_disponibilidad
           SET vigente_hasta = NOW()
         WHERE activo_id = NEW.id
           AND resultado = 'aprobado'
           AND vigente_hasta > NOW();

        NEW.ultima_verificacion_id := NULL;
        NEW.verificacion_vigente_hasta := NULL;
    END IF;

    -- ═══════════════════════════════════════════════════════════════
    -- REGLA D (LEY DS 298): bloqueo por antiguedad > 15 anios en transporte
    -- de sustancias peligrosas. SIEMPRE ACTIVA (control legal, sigue bloqueando).
    -- ═══════════════════════════════════════════════════════════════
    IF NEW.anio_fabricacion IS NOT NULL
       AND (EXTRACT(YEAR FROM CURRENT_DATE) - NEW.anio_fabricacion) > 15
       AND NEW.estado_comercial IN ('disponible', 'arrendado')
       AND NEW.tipo IN ('camion_cisterna', 'camion')
    THEN
        RAISE EXCEPTION
            'BLOQUEO DS 298: vehiculo ano % supera 15 anios de antiguedad. '
            'No puede operar en transporte de sustancias peligrosas.',
            NEW.anio_fabricacion;
    END IF;

    RETURN NEW;
END;
$function$;


-- ── B. Lugar actual por GPS: geocerca donde está el equipo ──────────────────
CREATE OR REPLACE FUNCTION public.fn_activo_geocerca_actual(p_activo_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_lat numeric; v_lng numeric; v_ts timestamptz;
    v_contrato uuid; v_nombre text;
BEGIN
    SELECT latitud, longitud, ts_gps INTO v_lat, v_lng, v_ts
      FROM gps_estado_actual WHERE activo_id = p_activo_id;
    IF v_lat IS NULL THEN
        RETURN jsonb_build_object('nombre', NULL, 'ts_gps', NULL, 'motivo', 'sin_gps');
    END IF;

    SELECT contrato_id INTO v_contrato FROM activos WHERE id = p_activo_id;

    -- Misma prioridad que fn_estado_por_geocerca: geocerca del contrato,
    -- luego faena_cliente, luego el radio menor.
    SELECT g.nombre INTO v_nombre
    FROM gps_geocercas g
    WHERE g.activo AND fn_punto_en_geocerca(v_lat, v_lng, g.id)
    ORDER BY (g.contrato_id IS NOT DISTINCT FROM v_contrato) DESC,
             (g.tipo = 'faena_cliente') DESC, g.radio_m ASC
    LIMIT 1;

    RETURN jsonb_build_object(
        'nombre', v_nombre,
        'ts_gps', v_ts,
        'lat', v_lat,
        'lng', v_lng,
        'motivo', CASE WHEN v_nombre IS NULL THEN 'fuera_de_geocercas' ELSE NULL END
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_activo_geocerca_actual(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_activo_geocerca_actual(uuid) TO authenticated;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE v_def text; r RECORD; n int;
BEGIN
    v_def := pg_get_functiondef('public.fn_validar_cambio_disponible()'::regprocedure);
    IF v_def LIKE '%RAISE EXCEPTION%BLOQUEO READY-TO-RENT%' THEN
        RAISE EXCEPTION 'FALLO: REGLA A sigue bloqueando';
    END IF;
    IF v_def NOT LIKE '%DS 298%' THEN
        RAISE EXCEPTION 'FALLO: se perdió REGLA D (DS 298)';
    END IF;
    RAISE NOTICE 'MIG240 OK: gate disponible = advertencia · DS298 intacto';

    -- Smoke test geocerca sobre algún equipo con GPS
    SELECT count(*) INTO n FROM gps_estado_actual WHERE latitud IS NOT NULL;
    RAISE NOTICE 'equipos con GPS: %', n;
    FOR r IN
        SELECT a.patente, fn_activo_geocerca_actual(a.id) AS geo
        FROM activos a JOIN gps_estado_actual g ON g.activo_id=a.id
        WHERE g.latitud IS NOT NULL LIMIT 8
    LOOP
        RAISE NOTICE '  % -> %', r.patente, r.geo->>'nombre';
    END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
