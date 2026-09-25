-- ============================================================================
-- MIG578 · Recobro por OT: agregar tareas del CHECKLIST como partidas
-- ============================================================================
--
-- 25-09-2026, Manuel, OT-202609-00011: «¿dónde agrego más cosas que realizaron
-- en el checklist que son recobrables?». MIG576 solo traía las NC cobrables.
-- Ahora el jefe elige tareas del checklist v3 de la OT y cada una entra como:
--   · un hallazgo (bloque, tarea, observación del mecánico, sus fotos) → sale
--     en el Word con su foto, igual que las NC;
--   · una partida de mano de obra en HH (tiempo de la tarea, mínimo 0,25 HH)
--     y precio $0: el precio lo pone el planificador.
-- No se repite: el hallazgo guarda la tarea de origen (checklist_v2_item_id).
-- Mismas reglas que MIG576 (fn_recobro_puede_editar: el jefe hasta su OK, el
-- planificador hasta emitir).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION rpc_recobro_agregar_checklist(p_informe_id UUID, p_item_ids UUID[])
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_perfil   TEXT := fn_recobro_puede_editar(p_informe_id, false);
    v_ot       UUID;
    v_hallazgo UUID;
    v_agregadas INT := 0;
    v_ya       INT := 0;
    it RECORD;
BEGIN
    SELECT ot_correctiva_id INTO v_ot FROM informes_recepcion WHERE id = p_informe_id;
    IF v_ot IS NULL THEN RAISE EXCEPTION 'Este informe no está ligado a una OT'; END IF;
    IF COALESCE(array_length(p_item_ids, 1), 0) = 0 THEN RAISE EXCEPTION 'No elegiste ninguna tarea'; END IF;

    FOR it IN
        SELECT c.instance_item_id, c.bloque, c.codigo, c.descripcion, c.observacion, c.resultado,
               c.tiempo_min, c.foto_url, c.foto_urls
          FROM v_taller_ot_checklist_v3 c
         WHERE c.ot_id = v_ot AND c.instance_item_id = ANY (p_item_ids)
         ORDER BY c.bloque_orden, c.orden
    LOOP
        IF EXISTS (SELECT 1 FROM informe_recepcion_hallazgos
                    WHERE informe_id = p_informe_id AND checklist_v2_item_id = it.instance_item_id) THEN
            v_ya := v_ya + 1;
            CONTINUE;
        END IF;

        INSERT INTO informe_recepcion_hallazgos (
            informe_id, seccion, descripcion, gravedad, atribuible_cliente, fotos,
            observacion, checklist_v2_item_id, diagnostico, amerita_recobro
        ) VALUES (
            p_informe_id, left(it.bloque, 100),
            COALESCE(it.codigo || ' ', '') || it.descripcion,
            'menor', true,
            COALESCE(to_jsonb(it.foto_urls),
                     CASE WHEN it.foto_url IS NOT NULL THEN jsonb_build_array(it.foto_url) END,
                     '[]'::jsonb),
            it.observacion, it.instance_item_id,
            it.observacion, 'Si Amerita recobro'
        ) RETURNING id INTO v_hallazgo;

        INSERT INTO informe_recepcion_costos (
            informe_id, tipo, descripcion, cantidad, unidad, precio_unitario,
            cobrable_cliente, hallazgo_id, editado_por, editado_en
        ) VALUES (
            p_informe_id, 'mano_obra',
            left('Mano de obra — ' || it.descripcion, 300),
            GREATEST(round(COALESCE(it.tiempo_min, 0) / 60.0, 2), 0.25), 'HH', 0,
            true, v_hallazgo, auth.uid(), NOW()
        );
        v_agregadas := v_agregadas + 1;
    END LOOP;

    RETURN jsonb_build_object('ok', true, 'agregadas', v_agregadas, 'ya_estaban', v_ya);
END;
$$;

REVOKE ALL ON FUNCTION rpc_recobro_agregar_checklist(UUID, UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_recobro_agregar_checklist(UUID, UUID[]) TO authenticated;

-- Quitar una partida que vino del checklist también suelta su hallazgo (si ya
-- no le queda ninguna partida y no es de una NC), para que la tarea se pueda
-- volver a elegir y no salga en el Word sin nada que cobrar.
CREATE OR REPLACE FUNCTION rpc_recobro_partida_eliminar(p_partida_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_informe UUID; v_hallazgo UUID;
BEGIN
    SELECT informe_id, hallazgo_id INTO v_informe, v_hallazgo
      FROM informe_recepcion_costos WHERE id = p_partida_id;
    IF v_informe IS NULL THEN RAISE EXCEPTION 'La partida no existe'; END IF;
    PERFORM fn_recobro_puede_editar(v_informe, false);
    DELETE FROM informe_recepcion_costos WHERE id = p_partida_id;
    IF v_hallazgo IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM informe_recepcion_costos WHERE hallazgo_id = v_hallazgo)
       AND NOT EXISTS (SELECT 1 FROM no_conformidades WHERE recobro_hallazgo_id = v_hallazgo)
       AND EXISTS (SELECT 1 FROM informe_recepcion_hallazgos
                    WHERE id = v_hallazgo AND checklist_v2_item_id IS NOT NULL) THEN
        DELETE FROM informe_recepcion_hallazgos WHERE id = v_hallazgo;
    END IF;
END;
$$;

COMMIT;
