-- ============================================================================
-- MIG471 · El cuenta litros del aljibe de combustible
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- «En la vista de taller, los medidores que debe tomar el operador son
-- horómetro, kilometraje y, para el caso de aljibe de combustible, cuenta
-- litros infinito».
--
-- QUÉ ES «INFINITO» Y POR QUÉ IMPORTA
-- Es el totalizador del surtidor: no se reinicia nunca, sólo avanza. La misma
-- naturaleza que el horómetro y el kilometraje, y por eso se trata igual: si el
-- número que anotan es menor que la última lectura, el sistema pregunta antes
-- de guardarlo. Un totalizador que retrocede significa una de dos cosas —se
-- cambió el equipo de medición, o alguien se equivocó— y ninguna se resuelve
-- guardando el número en silencio.
--
-- POR QUÉ NO SE LE PIDE A TODOS
-- Sólo los aljibes de combustible lo tienen. Pedir un campo que no existe en el
-- equipo enseña a la gente a inventar números, que es peor que no preguntar.
-- Son 16 equipos de la flota: `tipo_equipamiento = 'aljibe_combustible'`.
--
-- DÓNDE VIVE
-- La lectura va en el checklist, junto al horómetro y el kilometraje. El
-- acumulado va en el maestro del activo, sólo hacia adelante — igual que
-- `horas_uso_actual` y `kilometraje_actual`. Ese acumulado es el que después
-- permite preguntar cuántos litros pasaron entre dos mantenciones.
-- ============================================================================

BEGIN;

-- ── 1 · Dónde se anota y dónde se acumula ───────────────────────────────────
ALTER TABLE checklist_v2_instance
  ADD COLUMN IF NOT EXISTS cuenta_litros NUMERIC;
ALTER TABLE activos
  ADD COLUMN IF NOT EXISTS cuenta_litros_actual NUMERIC;

COMMENT ON COLUMN checklist_v2_instance.cuenta_litros IS
    'Lectura del totalizador del surtidor al momento del checklist. Sólo se '
    'pide en aljibes de combustible.';
COMMENT ON COLUMN activos.cuenta_litros_actual IS
    'Último totalizador conocido. Sólo avanza, como el horómetro y el '
    'kilometraje: sirve para saber cuántos litros pasaron entre mantenciones.';

-- ── 2 · A quién se le pide ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_activo_exige_cuenta_litros(p_activo_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT a.tipo_equipamiento = 'aljibe_combustible'
       FROM activos a WHERE a.id = p_activo_id),
    FALSE);
$$;

-- ── 3 · El RPC de medidores, con el tercero ─────────────────────────────────
--
-- Se BORRA la firma vieja antes de crear la nueva. Dejar las dos convivendo
-- —una de 4 argumentos y otra de 5 con DEFAULT— hace que Postgres no sepa cuál
-- llamar y todo el módulo se cae con «function is not unique». Ya pasó en
-- MIG442 y en MIG448; no vuelve a pasar.
DROP FUNCTION IF EXISTS rpc_taller_registrar_medidores(UUID, NUMERIC, NUMERIC, BOOLEAN);

CREATE OR REPLACE FUNCTION rpc_taller_registrar_medidores(
    p_ot_id        UUID,
    p_horometro    NUMERIC DEFAULT NULL,
    p_kilometraje  NUMERIC DEFAULT NULL,
    p_confirmado   BOOLEAN DEFAULT FALSE,
    p_cuenta_litros NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_inst RECORD; v_activo UUID; v_exige_km BOOLEAN; v_exige_cl BOOLEAN;
    v_hm_ant NUMERIC; v_km_ant NUMERIC; v_cl_ant NUMERIC;
    v_retro TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('operador_taller','tecnico_mantenimiento','jefe_mantenimiento',
                     'supervisor','planificador','administrador','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Sin permiso para anotar medidores (rol: %)', v_rol; END IF;

    SELECT i.id, i.activo_id, i.horometro, i.kilometraje, i.cuenta_litros
      INTO v_inst
      FROM checklist_v2_instance i
     WHERE i.ot_id = p_ot_id
     ORDER BY i.created_at DESC
     LIMIT 1;
    IF v_inst.id IS NULL THEN
        RAISE EXCEPTION 'Esta OT no tiene checklist: no hay dónde anotar los medidores'; END IF;

    v_activo   := v_inst.activo_id;
    v_exige_km := fn_activo_exige_kilometraje(v_activo);
    v_exige_cl := fn_activo_exige_cuenta_litros(v_activo);

    IF p_horometro IS NOT NULL AND p_horometro < 0 THEN
        RAISE EXCEPTION 'El horómetro no puede ser negativo'; END IF;
    IF p_kilometraje IS NOT NULL AND p_kilometraje < 0 THEN
        RAISE EXCEPTION 'El kilometraje no puede ser negativo'; END IF;
    IF p_cuenta_litros IS NOT NULL AND p_cuenta_litros < 0 THEN
        RAISE EXCEPTION 'El cuenta litros no puede ser negativo'; END IF;

    -- El cuenta litros sólo se guarda donde existe: si el equipo no lo tiene, se
    -- ignora en vez de dejar un número suelto que nadie sabe de dónde salió.
    IF p_cuenta_litros IS NOT NULL AND NOT v_exige_cl THEN
        p_cuenta_litros := NULL;
    END IF;

    SELECT max(i.horometro), max(i.kilometraje), max(i.cuenta_litros)
      INTO v_hm_ant, v_km_ant, v_cl_ant
      FROM checklist_v2_instance i
     WHERE i.activo_id = v_activo AND i.id <> v_inst.id;
    v_hm_ant := GREATEST(COALESCE(v_hm_ant, 0),
                         COALESCE((SELECT a.horas_uso_actual FROM activos a WHERE a.id = v_activo), 0));
    v_km_ant := GREATEST(COALESCE(v_km_ant, 0),
                         COALESCE((SELECT a.kilometraje_actual FROM activos a WHERE a.id = v_activo), 0));
    v_cl_ant := GREATEST(COALESCE(v_cl_ant, 0),
                         COALESCE((SELECT a.cuenta_litros_actual FROM activos a WHERE a.id = v_activo), 0));

    IF p_horometro IS NOT NULL AND v_hm_ant > 0 AND p_horometro < v_hm_ant THEN
        v_retro := array_append(v_retro,
            format('horómetro (antes %s h, ahora %s h)', v_hm_ant, p_horometro)::TEXT);
    END IF;
    IF p_kilometraje IS NOT NULL AND v_km_ant > 0 AND p_kilometraje < v_km_ant THEN
        v_retro := array_append(v_retro,
            format('kilometraje (antes %s km, ahora %s km)', v_km_ant, p_kilometraje)::TEXT);
    END IF;
    IF p_cuenta_litros IS NOT NULL AND v_cl_ant > 0 AND p_cuenta_litros < v_cl_ant THEN
        v_retro := array_append(v_retro,
            format('cuenta litros (antes %s L, ahora %s L)', v_cl_ant, p_cuenta_litros)::TEXT);
    END IF;

    IF array_length(v_retro, 1) > 0 AND NOT p_confirmado THEN
        RETURN jsonb_build_object(
            'success', FALSE, 'requiere_confirmacion', TRUE,
            'motivo', 'El número es menor que la última lectura: ' || array_to_string(v_retro, ' y ') ||
                      '. Si el medidor se cambió, confirma; si no, corrige el número.');
    END IF;

    UPDATE checklist_v2_instance
       SET horometro     = COALESCE(p_horometro, horometro),
           kilometraje   = COALESCE(p_kilometraje, kilometraje),
           cuenta_litros = COALESCE(p_cuenta_litros, cuenta_litros),
           medidores_por = v_user,
           medidores_at  = NOW(),
           observaciones = CASE
               WHEN array_length(v_retro, 1) > 0
               THEN COALESCE(observaciones || ' · ', '')
                    || 'Medidor confirmado a mano pese a retroceder: ' || array_to_string(v_retro, ' y ')
               ELSE observaciones END,
           updated_at    = NOW()
     WHERE id = v_inst.id;

    -- [MIG399] El maestro, con las lecturas. Sólo hacia adelante.
    IF p_horometro IS NOT NULL THEN
        UPDATE activos SET horas_uso_actual = p_horometro, updated_at = NOW()
         WHERE id = v_activo AND COALESCE(horas_uso_actual, 0) < p_horometro;
    END IF;
    IF p_kilometraje IS NOT NULL THEN
        UPDATE activos SET kilometraje_actual = p_kilometraje, updated_at = NOW()
         WHERE id = v_activo AND COALESCE(kilometraje_actual, 0) < p_kilometraje;
    END IF;
    IF p_cuenta_litros IS NOT NULL THEN
        UPDATE activos SET cuenta_litros_actual = p_cuenta_litros, updated_at = NOW()
         WHERE id = v_activo AND COALESCE(cuenta_litros_actual, 0) < p_cuenta_litros;
    END IF;

    RETURN jsonb_build_object('success', TRUE,
        'horometro', COALESCE(p_horometro, v_inst.horometro),
        'kilometraje', COALESCE(p_kilometraje, v_inst.kilometraje),
        'cuenta_litros', COALESCE(p_cuenta_litros, v_inst.cuenta_litros),
        'exige_kilometraje', v_exige_km,
        'exige_cuenta_litros', v_exige_cl);
END;
$$;

REVOKE ALL ON FUNCTION fn_activo_exige_cuenta_litros(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_activo_exige_cuenta_litros(UUID) TO authenticated;
REVOKE ALL ON FUNCTION rpc_taller_registrar_medidores(UUID, NUMERIC, NUMERIC, BOOLEAN, NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_registrar_medidores(UUID, NUMERIC, NUMERIC, BOOLEAN, NUMERIC) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_n INT; r RECORD;
BEGIN
    -- Una sola firma: dos con DEFAULT sería «function is not unique».
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_taller_registrar_medidores';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: el RPC de medidores quedó con % firmas', v_n; END IF;

    SELECT count(*) INTO v_n FROM activos WHERE fn_activo_exige_cuenta_litros(id);
    RAISE NOTICE 'equipos a los que se les va a pedir el cuenta litros: %', v_n;

    FOR r IN SELECT a.patente, a.nombre FROM activos a
              WHERE fn_activo_exige_cuenta_litros(a.id) ORDER BY a.patente LIMIT 6 LOOP
        RAISE NOTICE '   % · %', rpad(COALESCE(r.patente,'(sin patente)'),12), r.nombre;
    END LOOP;

    -- Y que a los demás no se les pida.
    SELECT count(*) INTO v_n FROM activos WHERE NOT fn_activo_exige_cuenta_litros(id);
    RAISE NOTICE 'equipos a los que NO se les pide: % (siguen con horómetro y kilometraje)', v_n;
END
$mig$;

COMMIT;
