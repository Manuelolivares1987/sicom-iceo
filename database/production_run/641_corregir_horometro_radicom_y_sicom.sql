-- MIG641 · Corregir horómetro / odómetro: Radicom y SICOM a la vez
-- ============================================================================
-- Desde Horas por equipo se ingresa lo que marca el tablero. La ruta
-- /api/gps/horometro lee el contador Radicom EN ESE MOMENTO (no la lectura de
-- las 05:00: entre medio el camión trabaja, error de MIG636), lo fija en
-- Radicom con tracker/counter/value/set y llama a rpc_horometro_corregir con
-- el antes y el después.
--
-- Diferencia = nuevo − contador Radicom de ese instante. Se aplica a:
--   · activos.horas_uso_actual / kilometraje_actual y gps_estado_actual;
--   · historial diario GPS (activo_horas_dia): queda en la escala nueva, así
--     el día de la corrección no marca horas fantasma ni negativas;
--   · bases de las pautas, SOLO si se pide (p_mover_bases): «lo que falta»
--     queda igual. Por defecto NO: la próxima mantención se recalcula contra
--     el horómetro corregido. Al 22-10, 9 de 43 equipos Radicom tenían en
--     SICOM otro horómetro que el GPS (activos.horas_uso_actual guarda el
--     mayor entre GPS y lo anotado en recepción: KCBY-30 25.888 vs 3.146), así
--     que las bases están en escalas mezcladas; la base mala se corrige con
--     «Registrar hecha» (MIG640).
-- Equipos con GPS de fábrica (Renault): no se corrigen, manda la ECU.
-- Todo queda en activo_horometro_correccion.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS activo_horometro_correccion (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id    UUID NOT NULL REFERENCES activos(id) ON DELETE CASCADE,
    fuente       TEXT NOT NULL,                 -- radicom | sin_gps
    horas_antes  NUMERIC,
    horas_nuevo  NUMERIC,
    km_antes     NUMERIC,
    km_nuevo     NUMERIC,
    mover_bases  BOOLEAN NOT NULL,
    nota         TEXT NOT NULL,
    radicom      JSONB,
    creado_por   UUID DEFAULT auth.uid(),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_horometro_correccion_activo
    ON activo_horometro_correccion (activo_id, created_at DESC);
ALTER TABLE activo_horometro_correccion ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS horometro_correccion_select ON activo_horometro_correccion;
CREATE POLICY horometro_correccion_select ON activo_horometro_correccion
    FOR SELECT TO authenticated USING (true);
REVOKE ALL ON activo_horometro_correccion FROM anon;
GRANT SELECT ON activo_horometro_correccion TO authenticated;

-- Credencial Radicom para la ruta del servidor (secreto cron_alertas, MIG301).
CREATE OR REPLACE FUNCTION fn_radicom_credencial_cron(p_secreto TEXT)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE p config_gps_proveedor%ROWTYPE;
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido';
    END IF;
    SELECT * INTO p FROM config_gps_proveedor WHERE nombre = 'Radicom';
    IF NOT FOUND OR p.api_token IS NULL THEN
        RETURN jsonb_build_object('activo', FALSE);
    END IF;
    RETURN jsonb_build_object('activo', p.activo, 'base_url', p.api_base_url, 'hash', p.api_token);
END $$;
REVOKE ALL ON FUNCTION fn_radicom_credencial_cron(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_radicom_credencial_cron(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION fn_horometro_puede_corregir()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT public.fn_tiene_permiso_modulo('mantenimiento', 'edit',
        ARRAY['administrador','auditor_calidad','jefe_mantenimiento','planificador']::text[]);
$$;

-- De dónde sale el horómetro del equipo y qué marca SICOM.
CREATE OR REPLACE FUNCTION public.rpc_horometro_preparar(p_activo_id UUID)
 RETURNS JSONB
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_act activos;
    v_dev TEXT;
    v_prov TEXT;
BEGIN
    IF NOT fn_horometro_puede_corregir() THEN
        RAISE EXCEPTION 'No autorizado para corregir horómetros.' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_act FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'El equipo no existe.' USING ERRCODE = 'P0001'; END IF;

    SELECT m.gps_device_id, p.nombre INTO v_dev, v_prov
      FROM gps_activo_mapeo m JOIN config_gps_proveedor p ON p.id = m.proveedor_id
     WHERE m.activo_id = p_activo_id AND m.activo
     ORDER BY (p.nombre = 'Renault rFMS') DESC
     LIMIT 1;

    RETURN jsonb_build_object(
        'fuente', CASE WHEN v_prov = 'Renault rFMS' THEN 'renault'
                       WHEN v_prov = 'Radicom' THEN 'radicom'
                       ELSE 'sin_gps' END,
        'tracker_id', CASE WHEN v_prov = 'Radicom' THEN v_dev END,
        'horas', v_act.horas_uso_actual,
        'km', v_act.kilometraje_actual);
END $function$;

CREATE OR REPLACE FUNCTION public.rpc_horometro_corregir(
    p_activo_id UUID, p_fuente TEXT,
    p_horas_antes NUMERIC, p_horas NUMERIC,
    p_km_antes NUMERIC, p_km NUMERIC,
    p_mover_bases BOOLEAN, p_nota TEXT, p_radicom JSONB DEFAULT NULL)
 RETURNS JSONB
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    d_h  NUMERIC := 0;
    d_km NUMERIC := 0;
    v_bases INT := 0;
    v_dias  INT := 0;
BEGIN
    IF NOT fn_horometro_puede_corregir() THEN
        RAISE EXCEPTION 'No autorizado para corregir horómetros.' USING ERRCODE = '42501';
    END IF;
    -- La fuente la decide la base, no quien llama: un equipo con Radicom no se
    -- corrige solo en SICOM (la lectura de las 05:00 lo devolvería a la escala vieja).
    IF (rpc_horometro_preparar(p_activo_id)->>'fuente') IS DISTINCT FROM p_fuente THEN
        RAISE EXCEPTION 'La fuente del horómetro del equipo cambió; vuelve a abrir la corrección.' USING ERRCODE = 'P0001';
    END IF;
    IF p_fuente NOT IN ('radicom', 'sin_gps') THEN
        RAISE EXCEPTION 'Este equipo toma el horómetro del computador del camión; no se corrige.' USING ERRCODE = 'P0001';
    END IF;
    IF p_fuente = 'radicom' AND NOT coalesce((p_radicom->>'ok')::BOOLEAN, FALSE) THEN
        RAISE EXCEPTION 'Radicom no confirmó el cambio; SICOM no se modifica.' USING ERRCODE = 'P0001';
    END IF;
    IF length(btrim(coalesce(p_nota, ''))) < 5 THEN
        RAISE EXCEPTION 'Escribe de dónde sale el dato (mínimo 5 caracteres), por ejemplo «tablero, foto recepción».'
            USING ERRCODE = 'P0001';
    END IF;
    IF p_horas IS NULL AND p_km IS NULL THEN
        RAISE EXCEPTION 'Indica el horómetro o el odómetro.' USING ERRCODE = 'P0001';
    END IF;
    IF (p_horas IS NOT NULL AND p_horas <= 0) OR (p_km IS NOT NULL AND p_km <= 0) THEN
        RAISE EXCEPTION 'Los valores deben ser mayores que cero.' USING ERRCODE = 'P0001';
    END IF;

    IF p_horas IS NOT NULL AND p_horas_antes IS NOT NULL THEN d_h := p_horas - p_horas_antes; END IF;
    IF p_km IS NOT NULL AND p_km_antes IS NOT NULL THEN d_km := p_km - p_km_antes; END IF;

    -- Historial GPS a la escala nueva.
    IF d_h <> 0 OR d_km <> 0 THEN
        UPDATE activo_horas_dia
           SET horometro_ini = CASE WHEN horometro_ini > 0 THEN horometro_ini + d_h ELSE horometro_ini END,
               horometro_fin = CASE WHEN horometro_fin > 0 THEN horometro_fin + d_h ELSE horometro_fin END,
               km_ini = CASE WHEN km_ini > 0 THEN km_ini + d_km ELSE km_ini END,
               km_fin = CASE WHEN km_fin > 0 THEN km_fin + d_km ELSE km_fin END,
               actualizado_at = NOW()
         WHERE activo_id = p_activo_id;
        GET DIAGNOSTICS v_dias = ROW_COUNT;
    END IF;

    UPDATE activos
       SET horas_uso_actual   = coalesce(p_horas, horas_uso_actual),
           kilometraje_actual = coalesce(p_km, kilometraje_actual)
     WHERE id = p_activo_id;

    UPDATE gps_estado_actual
       SET horometro_hrs = CASE WHEN p_horas IS NOT NULL THEN p_horas ELSE horometro_hrs END,
           odometro_km   = CASE WHEN p_km IS NOT NULL THEN p_km ELSE odometro_km END
     WHERE activo_id = p_activo_id;

    IF p_mover_bases AND (d_h <> 0 OR d_km <> 0) THEN
        UPDATE planes_mantenimiento
           SET ultima_ejecucion_horas = CASE WHEN ultima_ejecucion_horas > 0 THEN ultima_ejecucion_horas + d_h
                                             ELSE ultima_ejecucion_horas END,
               ultima_ejecucion_km    = CASE WHEN ultima_ejecucion_km > 0 THEN ultima_ejecucion_km + d_km
                                             ELSE ultima_ejecucion_km END,
               updated_at = NOW()
         WHERE activo_id = p_activo_id
           AND (ultima_ejecucion_horas > 0 OR ultima_ejecucion_km > 0);
        GET DIAGNOSTICS v_bases = ROW_COUNT;
    END IF;

    INSERT INTO activo_horometro_correccion
        (activo_id, fuente, horas_antes, horas_nuevo, km_antes, km_nuevo, mover_bases, nota, radicom)
    VALUES (p_activo_id, p_fuente, p_horas_antes, p_horas, p_km_antes, p_km,
            coalesce(p_mover_bases, FALSE), btrim(p_nota), p_radicom);

    RETURN jsonb_build_object('dif_horas', d_h, 'dif_km', d_km, 'bases_movidas', v_bases, 'dias_historial', v_dias);
END $function$;

REVOKE ALL ON FUNCTION fn_horometro_puede_corregir() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_horometro_preparar(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_horometro_corregir(UUID, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, BOOLEAN, TEXT, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_horometro_puede_corregir() TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_horometro_preparar(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_horometro_corregir(UUID, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, BOOLEAN, TEXT, JSONB) TO authenticated;

COMMIT;
