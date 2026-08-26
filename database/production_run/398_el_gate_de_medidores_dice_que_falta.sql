-- ============================================================================
-- MIG398 · El aviso de medidores dice qué falta, en vez de reventar
-- ----------------------------------------------------------------------------
-- MIG397 dejó el bloqueo puesto pero con un error de tipos: al armar la lista
-- de lo que falta hacía `v_falta := v_falta || 'el horómetro'`, y un literal sin
-- tipo contra un TEXT[] Postgres lo interpreta como literal de arreglo:
--
--     malformed array literal: "el horómetro"
--
-- El efecto era el correcto por accidente —la OT no se podía finalizar— pero
-- por la razón equivocada, y con un mensaje que no le dice nada al mecánico.
-- Se prueba en la misma transacción de MIG397: la excepción tapaba el aviso.
--
-- El resto de MIG397 quedó verificado y no se toca: guardar los medidores
-- funciona, el maestro se actualiza sólo hacia adelante, y el retroceso pide
-- confirmación en vez de bloquear.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_taller_finalizar_mecanico(
    p_ot_id uuid,
    p_firma_tecnico_url text,
    p_con_observaciones boolean DEFAULT false,
    p_observaciones text DEFAULT NULL::text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_inst RECORD; v_falta TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF p_firma_tecnico_url IS NULL OR length(trim(p_firma_tecnico_url)) = 0 THEN
        RAISE EXCEPTION 'La firma del técnico es obligatoria para finalizar'; END IF;

    -- [MIG397] Con cuánto uso volvió el equipo se anota antes de cerrar. De ese
    -- número salen la próxima preventiva y lo que se le cobra al cliente por el
    -- uso: si no queda escrito acá, no queda escrito en ninguna parte.
    SELECT i.id, i.activo_id, i.horometro, i.kilometraje
      INTO v_inst
      FROM checklist_v2_instance i
     WHERE i.ot_id = p_ot_id
     ORDER BY i.created_at DESC
     LIMIT 1;

    IF v_inst.id IS NOT NULL THEN
        -- El cast importa: un literal sin tipo contra TEXT[] se lee como
        -- literal de arreglo y revienta antes de llegar al mensaje.
        IF v_inst.horometro IS NULL THEN
            v_falta := array_append(v_falta, 'el horómetro'::TEXT);
        END IF;
        IF v_inst.kilometraje IS NULL AND fn_activo_exige_kilometraje(v_inst.activo_id) THEN
            v_falta := array_append(v_falta, 'el kilometraje'::TEXT);
        END IF;
        IF array_length(v_falta, 1) > 0 THEN
            RAISE EXCEPTION 'Falta anotar % del equipo. Está arriba de la lista de tareas, en «Medidores del equipo».',
                array_to_string(v_falta, ' y ');
        END IF;
    END IF;

    UPDATE ordenes_trabajo SET firma_tecnico_url = p_firma_tecnico_url, updated_at = NOW() WHERE id = p_ot_id;
    RETURN rpc_transicion_ot(
        p_ot_id,
        (CASE WHEN p_con_observaciones THEN 'ejecutada_con_observaciones' ELSE 'ejecutada_ok' END)::estado_ot_enum,
        v_user, NULL, NULL, p_observaciones, NULL);
END $function$;

-- Misma corrección preventiva en el armado del aviso de retroceso.
CREATE OR REPLACE FUNCTION public.rpc_taller_registrar_medidores(
    p_ot_id       uuid,
    p_horometro   numeric DEFAULT NULL,
    p_kilometraje numeric DEFAULT NULL,
    p_confirmado  boolean DEFAULT FALSE
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_inst RECORD; v_activo UUID; v_exige_km BOOLEAN;
    v_hm_ant NUMERIC; v_km_ant NUMERIC; v_retro TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('operador_taller','tecnico_mantenimiento','jefe_mantenimiento',
                     'supervisor','planificador','administrador','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Sin permiso para anotar medidores (rol: %)', v_rol; END IF;

    SELECT i.id, i.activo_id, i.horometro, i.kilometraje
      INTO v_inst
      FROM checklist_v2_instance i
     WHERE i.ot_id = p_ot_id
     ORDER BY i.created_at DESC
     LIMIT 1;
    IF v_inst.id IS NULL THEN
        RAISE EXCEPTION 'Esta OT no tiene checklist: no hay dónde anotar los medidores'; END IF;

    v_activo   := v_inst.activo_id;
    v_exige_km := fn_activo_exige_kilometraje(v_activo);

    IF p_horometro IS NOT NULL AND p_horometro < 0 THEN
        RAISE EXCEPTION 'El horómetro no puede ser negativo'; END IF;
    IF p_kilometraje IS NOT NULL AND p_kilometraje < 0 THEN
        RAISE EXCEPTION 'El kilometraje no puede ser negativo'; END IF;

    SELECT max(i.horometro), max(i.kilometraje) INTO v_hm_ant, v_km_ant
      FROM checklist_v2_instance i
     WHERE i.activo_id = v_activo AND i.id <> v_inst.id;
    v_km_ant := GREATEST(COALESCE(v_km_ant, 0),
                         COALESCE((SELECT a.kilometraje_actual FROM activos a WHERE a.id = v_activo), 0));

    IF p_horometro IS NOT NULL AND v_hm_ant IS NOT NULL AND p_horometro < v_hm_ant THEN
        v_retro := array_append(v_retro,
            format('horómetro (antes %s h, ahora %s h)', v_hm_ant, p_horometro)::TEXT);
    END IF;
    IF p_kilometraje IS NOT NULL AND v_km_ant > 0 AND p_kilometraje < v_km_ant THEN
        v_retro := array_append(v_retro,
            format('kilometraje (antes %s km, ahora %s km)', v_km_ant, p_kilometraje)::TEXT);
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
           medidores_por = v_user,
           medidores_at  = NOW(),
           observaciones = CASE
               WHEN array_length(v_retro, 1) > 0
               THEN COALESCE(observaciones || ' · ', '')
                    || 'Medidor confirmado a mano pese a retroceder: ' || array_to_string(v_retro, ' y ')
               ELSE observaciones END,
           updated_at    = NOW()
     WHERE id = v_inst.id;

    IF p_kilometraje IS NOT NULL THEN
        UPDATE activos
           SET kilometraje_actual = p_kilometraje, updated_at = NOW()
         WHERE id = v_activo
           AND COALESCE(kilometraje_actual, 0) < p_kilometraje;
    END IF;

    RETURN jsonb_build_object('success', TRUE,
        'horometro', COALESCE(p_horometro, v_inst.horometro),
        'kilometraje', COALESCE(p_kilometraje, v_inst.kilometraje),
        'exige_kilometraje', v_exige_km);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_taller_registrar_medidores(uuid,numeric,numeric,boolean) TO authenticated;

COMMIT;
