-- ============================================================================
-- MIG397 · Al recibir un equipo, el horómetro y el kilometraje se anotan
-- ----------------------------------------------------------------------------
-- LO QUE PIDIÓ MANUEL
-- 26-08-2026: «cada vez que voy a recibir un equipo, el mecánico debe anotar
-- horómetro y kilometraje».
--
-- LO QUE PASABA
-- Las columnas existían desde siempre —`checklist_v2_instance.horometro` y
-- `.kilometraje`, las dos numéricas— pero **el mecánico no tenía dónde
-- escribirlas**. Se llenaban solas al crear el checklist, arrastrando el último
-- valor conocido, o quedaban nulas. Nadie las miraba y nada las exigía.
--
-- El resultado, contado:
--
--   120 checklists de recepción · 74 con medidores · 46 SIN NINGUNO (38%)
--
-- Los 46 son de camiones cisterna y camiones que volvieron de arriendo sin que
-- nadie anotara con cuánto uso volvieron. Eso es el dato que decide cuándo toca
-- la próxima preventiva y cuánto se le facturó al cliente por el uso.
--
-- QUÉ SE HACE
--   1. Un RPC para que el mecánico los anote desde su teléfono, con quién y
--      cuándo (hoy no se sabe si el número lo escribió alguien o lo arrastró
--      el sistema).
--   2. Finalizar la OT los EXIGE. Es la misma puerta donde ya vive la foto
--      obligatoria del hallazgo NO OK: si el equipo salió a terreno, el número
--      se anota antes de cerrar.
--   3. El kilometraje se pide sólo a los equipos que ruedan. Un surtidor o una
--      bomba no tienen odómetro, y exigírselo sería obligar a inventar un cero.
--
-- POR QUÉ NO SE BLOQUEA UN NÚMERO QUE BAJA
-- Un horómetro que retrocede casi siempre es un dedo equivocado, pero a veces
-- es un medidor que se cambió de verdad. Bloquearlo dejaría al mecánico sin
-- forma de registrar la realidad. Se avisa y se pide confirmar: el RPC rechaza
-- el retroceso salvo que venga confirmado, y deja escrito en la observación que
-- se confirmó a mano.
--
-- LO QUE NO SE TOCA
-- Los 46 checklists viejos se dejan como están. Rellenarlos con un número
-- inventado sería peor que el hueco: quedan visibles como lo que son.
-- ============================================================================

BEGIN;

-- ── 1. Quién anotó y cuándo ───────────────────────────────────────────────
ALTER TABLE public.checklist_v2_instance
  ADD COLUMN IF NOT EXISTS medidores_por UUID REFERENCES public.usuarios_perfil(id),
  ADD COLUMN IF NOT EXISTS medidores_at  TIMESTAMPTZ;

COMMENT ON COLUMN public.checklist_v2_instance.medidores_por IS
  'MIG397: quién anotó horómetro/kilometraje. NULL = el valor lo arrastró el sistema al crear el checklist, no lo leyó una persona.';

-- ── 2. Qué equipos tienen odómetro ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_activo_exige_kilometraje(p_activo_id uuid)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT a.tipo IN ('camion','camion_cisterna','camioneta','lubrimovil')
       FROM activos a WHERE a.id = p_activo_id),
    FALSE);
$function$;

COMMENT ON FUNCTION public.fn_activo_exige_kilometraje(uuid) IS
  'MIG397: TRUE sólo para equipos que ruedan. Surtidores, bombas y estanques no tienen odómetro: pedirles kilometraje obliga a inventar un cero.';

-- ── 3. El mecánico los anota ──────────────────────────────────────────────
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
    v_hm_ant NUMERIC; v_km_ant NUMERIC; v_retro TEXT[] := '{}';
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

    -- Última lectura conocida del equipo, para detectar el dedo equivocado.
    SELECT max(i.horometro), max(i.kilometraje) INTO v_hm_ant, v_km_ant
      FROM checklist_v2_instance i
     WHERE i.activo_id = v_activo AND i.id <> v_inst.id;
    v_km_ant := GREATEST(COALESCE(v_km_ant, 0),
                         COALESCE((SELECT a.kilometraje_actual FROM activos a WHERE a.id = v_activo), 0));

    IF p_horometro IS NOT NULL AND v_hm_ant IS NOT NULL AND p_horometro < v_hm_ant THEN
        v_retro := v_retro || format('horómetro (antes %s h, ahora %s h)', v_hm_ant, p_horometro);
    END IF;
    IF p_kilometraje IS NOT NULL AND v_km_ant > 0 AND p_kilometraje < v_km_ant THEN
        v_retro := v_retro || format('kilometraje (antes %s km, ahora %s km)', v_km_ant, p_kilometraje);
    END IF;

    -- Un medidor que baja casi siempre es un error de tipeo, pero a veces es un
    -- medidor cambiado de verdad. Se avisa y se deja pasar si lo confirman.
    IF array_length(v_retro,1) > 0 AND NOT p_confirmado THEN
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
               WHEN array_length(v_retro,1) > 0
               THEN COALESCE(observaciones || ' · ', '')
                    || 'Medidor confirmado a mano pese a retroceder: ' || array_to_string(v_retro, ' y ')
               ELSE observaciones END,
           updated_at    = NOW()
     WHERE id = v_inst.id;

    -- El maestro se mantiene al día, pero sólo hacia adelante: el kilometraje
    -- de un equipo no baja porque alguien anotó mal en una recepción.
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

-- ── 4. Finalizar los exige ────────────────────────────────────────────────
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
    v_inst RECORD; v_falta TEXT[] := '{}';
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
        IF v_inst.horometro IS NULL THEN
            v_falta := v_falta || 'el horómetro';
        END IF;
        IF v_inst.kilometraje IS NULL AND fn_activo_exige_kilometraje(v_inst.activo_id) THEN
            v_falta := v_falta || 'el kilometraje';
        END IF;
        IF array_length(v_falta,1) > 0 THEN
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

-- ── 5. El hueco, medido ───────────────────────────────────────────────────
DO $r$
DECLARE v_sin INT; v_tot INT; v_abiertas INT;
BEGIN
    SELECT count(*) FILTER (WHERE horometro IS NULL OR kilometraje IS NULL), count(*)
      INTO v_sin, v_tot
      FROM checklist_v2_instance WHERE momento_uso::text = 'recepcion_devolucion';
    RAISE NOTICE 'Recepciones sin medidores completos: % de % (el histórico se deja como está)', v_sin, v_tot;

    SELECT count(*) INTO v_abiertas
      FROM checklist_v2_instance i
      JOIN ordenes_trabajo o ON o.id = i.ot_id
     WHERE (i.horometro IS NULL OR (i.kilometraje IS NULL AND fn_activo_exige_kilometraje(i.activo_id)))
       AND o.estado NOT IN ('cerrada','ejecutada_ok','ejecutada_con_observaciones');
    RAISE NOTICE 'OT todavía abiertas que van a pedir el número al finalizar: %', v_abiertas;
END
$r$;

COMMIT;
