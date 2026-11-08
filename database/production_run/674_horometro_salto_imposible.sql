-- 674 — El horómetro no puede subir más horas de las que pasaron (Manuel 08-11-2026,
-- benchmark MaintainX: detección de lecturas anómalas).
--
-- rpc_taller_registrar_medidores ya pedía confirmación si el número RETROCEDÍA. Ahora también
-- si salta hacia adelante más de lo físicamente posible. Casos reales que habría atajado:
-- TGGF-60 1.305 → 13.501, KCBY-30 3.146 → 25.888, FJTJ-61 1.325 → 3.599. El mecánico puede
-- confirmar (queda anotado en la observación del checklist), igual que con el retroceso.

CREATE OR REPLACE FUNCTION public.rpc_taller_registrar_medidores(p_ot_id uuid, p_horometro numeric DEFAULT NULL::numeric, p_kilometraje numeric DEFAULT NULL::numeric, p_confirmado boolean DEFAULT false, p_cuenta_litros numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_inst RECORD; v_activo UUID; v_exige_km BOOLEAN; v_exige_cl BOOLEAN;
    v_hm_ant NUMERIC; v_km_ant NUMERIC; v_cl_ant NUMERIC;
    v_retro TEXT[] := ARRAY[]::TEXT[];
    v_salto TEXT[] := ARRAY[]::TEXT[];
    v_ult   RECORD;
    v_horas_reloj NUMERIC;
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

    -- [MIG674] Salto imposible hacia adelante. Un dígito de más (1.305 → 13.501) entraba al
    -- maestro, que sólo avanza, y quedaba pegado disparando preventivas falsas: 8 de 45
    -- lecturas consecutivas tenían saltos así. Regla física: el horómetro no puede subir más
    -- horas que las que pasaron en el reloj desde la última lectura (+24 h de margen); el
    -- kilometraje, no más de 90 km por hora transcurrida (+300 km). Si la anterior era 0
    -- (equipo sin lecturas reales) no se compara.
    SELECT i.horometro, i.kilometraje, i.medidores_at INTO v_ult
      FROM checklist_v2_instance i
     WHERE i.activo_id = v_activo AND i.id <> v_inst.id AND i.medidores_at IS NOT NULL
       AND (i.horometro IS NOT NULL OR i.kilometraje IS NOT NULL)
     ORDER BY i.medidores_at DESC LIMIT 1;
    IF v_ult.medidores_at IS NOT NULL THEN
        v_horas_reloj := GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_ult.medidores_at)) / 3600.0);
        IF p_horometro IS NOT NULL AND COALESCE(v_ult.horometro, 0) > 0
           AND p_horometro - v_ult.horometro > v_horas_reloj + 24 THEN
            v_salto := array_append(v_salto, format(
                'el horómetro subió %s h (de %s a %s) y desde la última lectura pasaron sólo %s h',
                round(p_horometro - v_ult.horometro), v_ult.horometro, p_horometro, round(v_horas_reloj))::TEXT);
        END IF;
        IF p_kilometraje IS NOT NULL AND COALESCE(v_ult.kilometraje, 0) > 0
           AND p_kilometraje - v_ult.kilometraje > v_horas_reloj * 90 + 300 THEN
            v_salto := array_append(v_salto, format(
                'el kilometraje subió %s km (de %s a %s) en %s h',
                round(p_kilometraje - v_ult.kilometraje), v_ult.kilometraje, p_kilometraje, round(v_horas_reloj))::TEXT);
        END IF;
    END IF;

    IF (array_length(v_retro, 1) > 0 OR array_length(v_salto, 1) > 0) AND NOT p_confirmado THEN
        RETURN jsonb_build_object(
            'success', FALSE, 'requiere_confirmacion', TRUE,
            'motivo', CASE WHEN array_length(v_retro, 1) > 0 THEN
                          'El número es menor que la última lectura: ' || array_to_string(v_retro, ' y ') ||
                          '. Si el medidor se cambió, confirma; si no, corrige el número.'
                      ELSE
                          'Revisa el número: ' || array_to_string(v_salto, ' y ') ||
                          '. ¿Sobra un dígito? Si está bien (p. ej. la lectura anterior estaba mal), confirma.'
                      END);
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
               WHEN array_length(v_salto, 1) > 0
               THEN COALESCE(observaciones || ' · ', '')
                    || 'Medidor confirmado a mano pese a un salto: ' || array_to_string(v_salto, ' y ')
               ELSE observaciones END,
           updated_at    = NOW()
     WHERE id = v_inst.id;

    -- [MIG496] El próximo horómetro de pauta no se pregunta: la pauta es cada
    -- 300 horas, así que es la lectura que la persona acaba de anotar + 300.
    -- Se recalcula cada vez que se guardan medidores (es un derivado) y el ítem
    -- queda respondido; en pantalla sigue editable por si una pauta específica
    -- dice otra cosa.
    IF p_horometro IS NOT NULL THEN
        UPDATE checklist_v2_instance_item ii
           SET valor_numerico = p_horometro + fn_intervalo_mantencion_horas(v_activo),
               resultado      = 'ok',
               respondido_at  = NOW()
          FROM checklist_template_v2_item ti
         WHERE ii.instance_id = v_inst.id
           AND ti.id = ii.template_item_id
           AND ti.codigo = 'B11.04'
           AND COALESCE(ii.excluido, FALSE) = FALSE;
    END IF;

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
        'exige_cuenta_litros', v_exige_cl,
        'proximo_horometro_pauta', CASE WHEN p_horometro IS NOT NULL THEN p_horometro + fn_intervalo_mantencion_horas(v_activo) END);
END;
$function$;

NOTIFY pgrst, 'reload schema';
