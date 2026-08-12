-- ============================================================================
-- SICOM-ICEO | 281 — Foto del medidor al inicio y al final de la carga
-- ============================================================================
-- Pedido de Manuel: que el operador fotografíe el medidor antes y después de
-- cargar. Es la evidencia de que los litros anotados son los que salieron —
-- el papel se puede escribir de memoria, la foto del contador no.
--
-- Las fotos se sacan sin señal: quedan en el teléfono y suben con la carga.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

ALTER TABLE combustible_faena_despachos
    ADD COLUMN IF NOT EXISTS foto_meter_inicial_url TEXT,
    ADD COLUMN IF NOT EXISTS foto_meter_final_url   TEXT,
    -- Si el operador no pudo sacarla, tiene que decir por qué: sin esto, la
    -- exigencia se convierte en un botón que nadie puede apretar en faena.
    ADD COLUMN IF NOT EXISTS sin_foto_motivo        TEXT;

COMMENT ON COLUMN combustible_faena_despachos.foto_meter_inicial_url IS
    'Foto del medidor antes de cargar. MIG281.';
COMMENT ON COLUMN combustible_faena_despachos.foto_meter_final_url IS
    'Foto del medidor al terminar. MIG281.';
COMMENT ON COLUMN combustible_faena_despachos.sin_foto_motivo IS
    'Por qué la carga quedó sin foto del medidor (escape documentado). MIG281.';


CREATE OR REPLACE FUNCTION rpc_comb_faena_despachar(
    p_faena_id     UUID,
    p_fecha        DATE,
    p_turno        TEXT,
    p_estanque_id  UUID,
    p_equipo_id    UUID,
    p_ubicacion_id UUID,
    p_meter_inicial NUMERIC,
    p_meter_final  NUMERIC,
    p_litros       NUMERIC,
    p_operador_nombre TEXT DEFAULT NULL,
    p_hora         TIME DEFAULT NULL,
    p_equipo_texto TEXT DEFAULT NULL,
    p_ubicacion_texto TEXT DEFAULT NULL,
    p_camion_patente TEXT DEFAULT NULL,
    p_horometro    NUMERIC DEFAULT NULL,
    p_kilometraje  NUMERIC DEFAULT NULL,
    p_observacion  TEXT DEFAULT NULL,
    p_client_uuid  TEXT DEFAULT NULL,
    p_foto_meter_inicial TEXT DEFAULT NULL,
    p_foto_meter_final   TEXT DEFAULT NULL,
    p_sin_foto_motivo    TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID; v_litros NUMERIC; v_ceco UUID;
BEGIN
    IF fn_user_rol() IS NULL THEN RAISE EXCEPTION 'Sesión requerida'; END IF;
    IF p_faena_id IS NULL THEN RAISE EXCEPTION 'Falta la faena'; END IF;

    -- Reintento del teléfono sin señal: si ya se guardó, se devuelve el mismo.
    IF p_client_uuid IS NOT NULL THEN
        SELECT id INTO v_id FROM combustible_faena_despachos WHERE client_uuid = p_client_uuid;
        IF v_id IS NOT NULL THEN
            -- Puede llegar primero la carga y después las fotos (subida en dos
            -- tiempos si la señal se corta a media subida).
            UPDATE combustible_faena_despachos
               SET foto_meter_inicial_url = COALESCE(p_foto_meter_inicial, foto_meter_inicial_url),
                   foto_meter_final_url   = COALESCE(p_foto_meter_final, foto_meter_final_url)
             WHERE id = v_id;
            RETURN jsonb_build_object('success', true, 'despacho_id', v_id, 'duplicado', true);
        END IF;
    END IF;

    v_litros := COALESCE(
        CASE WHEN p_meter_final IS NOT NULL AND p_meter_inicial IS NOT NULL
                  AND p_meter_final >= p_meter_inicial
             THEN p_meter_final - p_meter_inicial END,
        p_litros);
    IF v_litros IS NULL OR v_litros < 0 THEN RAISE EXCEPTION 'Litros inválidos'; END IF;

    SELECT ceco_id INTO v_ceco FROM combustible_faena_equipos WHERE id = p_equipo_id;

    INSERT INTO combustible_faena_despachos (
        faena_id, fecha, turno, estanque_id, camion_patente,
        equipo_id, equipo_texto, ceco_id, ubicacion_id, ubicacion_texto,
        meter_inicial, meter_final, litros,
        operador_id, operador_nombre, horometro, kilometraje, observacion, hora,
        client_uuid, created_by,
        foto_meter_inicial_url, foto_meter_final_url, sin_foto_motivo)
    VALUES (
        p_faena_id, COALESCE(p_fecha, CURRENT_DATE), NULLIF(TRIM(COALESCE(p_turno,'')),''),
        p_estanque_id, NULLIF(TRIM(COALESCE(p_camion_patente,'')),''),
        p_equipo_id, NULLIF(TRIM(COALESCE(p_equipo_texto,'')),''), v_ceco,
        p_ubicacion_id, NULLIF(TRIM(COALESCE(p_ubicacion_texto,'')),''),
        p_meter_inicial, p_meter_final, v_litros,
        auth.uid(), NULLIF(TRIM(COALESCE(p_operador_nombre,'')),''),
        p_horometro, p_kilometraje, NULLIF(TRIM(COALESCE(p_observacion,'')),''),
        p_hora, p_client_uuid, auth.uid(),
        NULLIF(TRIM(COALESCE(p_foto_meter_inicial,'')),''),
        NULLIF(TRIM(COALESCE(p_foto_meter_final,'')),''),
        NULLIF(TRIM(COALESCE(p_sin_foto_motivo,'')),''))
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'despacho_id', v_id, 'litros', v_litros);
END $$;

COMMENT ON FUNCTION rpc_comb_faena_despachar(UUID, DATE, TEXT, UUID, UUID, UUID, NUMERIC, NUMERIC,
    NUMERIC, TEXT, TIME, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT) IS
    'Registra un despacho en faena. Solo inserta: no descuenta stock ni genera kardex. MIG279/281.';

GRANT EXECUTE ON FUNCTION rpc_comb_faena_despachar(UUID, DATE, TEXT, UUID, UUID, UUID, NUMERIC, NUMERIC,
    NUMERIC, TEXT, TIME, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- La versión sin fotos queda fuera para que nadie la llame por error.
DROP FUNCTION IF EXISTS rpc_comb_faena_despachar(UUID, DATE, TEXT, UUID, UUID, UUID, NUMERIC, NUMERIC,
    NUMERIC, TEXT, TIME, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, TEXT, TEXT);

-- La vista muestra las fotos junto al resto del registro.
CREATE OR REPLACE VIEW v_comb_faena_despachos AS
SELECT d.id, d.faena_id, f.nombre AS faena, d.fecha, d.hora, d.turno,
       d.estanque_id, e.nombre AS camion, COALESCE(e.patente, d.camion_patente) AS camion_patente,
       d.equipo_id, COALESCE(eq.nombre, d.equipo_texto) AS equipo, eq.descripcion AS equipo_descripcion,
       d.ceco_id, c.codigo AS ceco, c.empresa AS ceco_empresa,
       d.ubicacion_id, COALESCE(u.nombre, d.ubicacion_texto) AS ubicacion,
       d.meter_inicial, d.meter_final, d.litros,
       d.operador_nombre, d.horometro, d.kilometraje, d.observacion,
       d.anulado, d.anulado_motivo, d.created_at,
       d.foto_meter_inicial_url, d.foto_meter_final_url, d.sin_foto_motivo
  FROM combustible_faena_despachos d
  JOIN faenas f ON f.id = d.faena_id
  LEFT JOIN combustible_estanques e ON e.id = d.estanque_id
  LEFT JOIN combustible_faena_equipos eq ON eq.id = d.equipo_id
  LEFT JOIN combustible_faena_cecos c ON c.id = d.ceco_id
  LEFT JOIN combustible_faena_ubicaciones u ON u.id = d.ubicacion_id;

GRANT SELECT ON v_comb_faena_despachos TO authenticated;

SELECT 'MIG281 OK' AS resultado;
