-- ============================================================================
-- SICOM-ICEO | 270 — Una OT nueva sobre un equipo ya inspeccionado arrastra
--                    SOLO las no conformidades
-- ============================================================================
-- Pedido del Jefe de Taller (2026-08-03, OT 7e73ce08):
--   "Cuando habrá una nueva O/T para el mismo equipo en el cual ya se generó el
--    checklist completo, debiera solo incluir las no conformidades."
--
-- Hoy (MIG157/MIG177): el trigger fn_auto_checklist_ot le cuelga a TODA OT
-- nueva una instancia completa del checklist V03 (hasta 188 ítems). Cuando la
-- recepción ya se inspeccionó de punta a punta y de ahí nacieron 5 correctivos,
-- cada uno de esos 5 vuelve a pedir la inspección entera. Ruido puro: el jefe
-- termina marcando bloques "no aplica" a mano.
--
-- Qué hace esta migración:
--   1. Columnas de trazabilidad del arrastre (instancia e ítem).
--   2. fn_checklist_v3_arrastrar_nc(instancia): busca la última inspección
--      COMPLETA del mismo equipo (ventana de 60 días) y, si tuvo hallazgos,
--      deja activos SOLO los ítems que salieron NO OK; el resto queda
--      `excluido` (no se borra: el jefe lo restaura cuando quiera).
--   3. El trigger la invoca al crear la instancia nueva — y también cuando
--      reengancha una instancia libre que no tiene ni una respuesta (cascarón
--      vacío); si la instancia libre sí trae respuestas es la inspección en
--      curso del terreno y se engancha entera.
--   4. La vista v_taller_ot_checklist_v3 expone el arrastre + la observación y
--      la foto de la inspección anterior, para que el mecánico sepa qué mirar.
--   5. Dos escapes para el jefe (edición del checklist):
--      - rpc_taller_v3_arrastrar_nc(ot)      → "dejar solo las no conformidades"
--      - rpc_taller_v3_restaurar_completo(ot) → "incluir el checklist completo"
--
-- Criterio de "inspección completa": ningún ítem incluido quedó en 'pendiente'.
-- No se usa estado='cerrado' porque las instancias colgadas de una OT nunca se
-- cierran formalmente (el cierre exige firma de operador, MIG144 §6).
--
-- SIN backfill: no se toca ninguna OT existente. Las que ya arrastran el
-- checklist entero se ajustan con el botón "dejar solo las no conformidades".
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Trazabilidad del arrastre ────────────────────────────────────────────
ALTER TABLE checklist_v2_instance
    ADD COLUMN IF NOT EXISTS arrastre_de_instance_id UUID REFERENCES checklist_v2_instance(id);

ALTER TABLE checklist_v2_instance_item
    ADD COLUMN IF NOT EXISTS arrastre_de_item_id UUID REFERENCES checklist_v2_instance_item(id);

CREATE INDEX IF NOT EXISTS idx_cl_inst_arrastre
    ON checklist_v2_instance(arrastre_de_instance_id) WHERE arrastre_de_instance_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cl_item_arrastre
    ON checklist_v2_instance_item(arrastre_de_item_id) WHERE arrastre_de_item_id IS NOT NULL;

COMMENT ON COLUMN checklist_v2_instance.arrastre_de_instance_id IS
    'Inspección anterior de la que este checklist arrastra solo las NC. MIG270.';
COMMENT ON COLUMN checklist_v2_instance_item.arrastre_de_item_id IS
    'Ítem NO OK de la inspección anterior que originó esta tarea. MIG270.';


-- ── 2. Motor del arrastre ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_checklist_v3_arrastrar_nc(p_instance_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    -- Ventana del arrastre: pasado este plazo la inspección anterior ya no
    -- representa al equipo y la OT nueva vuelve a pedir el checklist completo.
    c_ventana_dias CONSTANT INT := 60;
    v_activo       UUID;
    v_prev         UUID;
    v_arrastrables INT := 0;
    v_desde_tpl    INT := 0;
    v_desde_custom INT := 0;
    v_excluidos    INT := 0;
BEGIN
    SELECT activo_id INTO v_activo
      FROM checklist_v2_instance WHERE id = p_instance_id;
    IF v_activo IS NULL THEN
        RETURN jsonb_build_object('arrastre', false, 'motivo', 'instancia_no_existe');
    END IF;

    -- Última inspección COMPLETA del equipo dentro de la ventana.
    WITH cand AS (
        SELECT ci.id,
               COALESCE(ci.fecha_cierre, ci.fecha_inicio) AS ref_fecha,
               COUNT(*) FILTER (WHERE ii.excluido = false) AS incluidos,
               COUNT(*) FILTER (WHERE ii.excluido = false
                                  AND COALESCE(ii.resultado, 'pendiente') = 'pendiente') AS pendientes
          FROM checklist_v2_instance ci
          JOIN checklist_v2_instance_item ii ON ii.instance_id = ci.id
         WHERE ci.activo_id    = v_activo
           AND ci.momento_uso  = 'recepcion_devolucion'
           AND ci.id          <> p_instance_id
           AND COALESCE(ci.fecha_cierre, ci.fecha_inicio)
               >= NOW() - (c_ventana_dias || ' days')::INTERVAL
         GROUP BY ci.id, ci.fecha_cierre, ci.fecha_inicio
    )
    SELECT id INTO v_prev
      FROM cand
     WHERE incluidos > 0 AND pendientes = 0
     ORDER BY ref_fecha DESC
     LIMIT 1;

    IF v_prev IS NULL THEN
        RETURN jsonb_build_object('arrastre', false, 'motivo', 'sin_inspeccion_completa_previa');
    END IF;

    -- ¿Cuántas NC de esa inspección tienen dónde caer en esta instancia?
    SELECT
        (SELECT COUNT(*)
           FROM checklist_v2_instance_item nn
           JOIN checklist_v2_instance_item pp
             ON pp.instance_id = v_prev
            AND pp.template_item_id = nn.template_item_id
          WHERE nn.instance_id = p_instance_id
            AND nn.template_item_id IS NOT NULL
            AND pp.excluido = false AND pp.resultado = 'no_ok')
      + (SELECT COUNT(*)
           FROM checklist_v2_instance_item pp
          WHERE pp.instance_id = v_prev
            AND pp.template_item_id IS NULL
            AND pp.excluido = false AND pp.resultado = 'no_ok')
    INTO v_arrastrables;

    -- Sin hallazgos que arrastrar dejamos el checklist completo: una OT con
    -- cero tareas es peor que una con tareas de más.
    IF v_arrastrables = 0 THEN
        RETURN jsonb_build_object('arrastre', false, 'motivo', 'inspeccion_previa_sin_nc',
                                  'instancia_previa', v_prev);
    END IF;

    -- 2a. Lo que ya quedó conforme (o que el jefe declaró que no aplica al
    --     equipo) sale del checklist nuevo.
    UPDATE checklist_v2_instance_item nn
       SET excluido = true
      FROM checklist_v2_instance_item pp
     WHERE nn.instance_id       = p_instance_id
       AND nn.template_item_id IS NOT NULL
       AND pp.instance_id       = v_prev
       AND pp.template_item_id  = nn.template_item_id
       AND (pp.excluido = true OR pp.resultado IN ('ok', 'na'));
    GET DIAGNOSTICS v_excluidos = ROW_COUNT;

    -- 2b. Los NO OK quedan activos y con el link a su hallazgo original.
    UPDATE checklist_v2_instance_item nn
       SET excluido = false,
           arrastre_de_item_id = pp.id
      FROM checklist_v2_instance_item pp
     WHERE nn.instance_id       = p_instance_id
       AND nn.template_item_id IS NOT NULL
       AND pp.instance_id       = v_prev
       AND pp.template_item_id  = nn.template_item_id
       AND pp.excluido = false AND pp.resultado = 'no_ok';
    GET DIAGNOSTICS v_desde_tpl = ROW_COUNT;

    -- 2c. Las tareas que el jefe agregó a mano y salieron NO OK no existen en
    --     el maestro: se copian tal cual a la OT nueva.
    INSERT INTO checklist_v2_instance_item
        (instance_id, template_item_id, resultado, descripcion_custom,
         tiempo_min_override, arrastre_de_item_id)
    SELECT p_instance_id, NULL, 'pendiente', pp.descripcion_custom,
           pp.tiempo_min_override, pp.id
      FROM checklist_v2_instance_item pp
     WHERE pp.instance_id      = v_prev
       AND pp.template_item_id IS NULL
       AND pp.excluido = false AND pp.resultado = 'no_ok'
       AND NOT EXISTS (SELECT 1 FROM checklist_v2_instance_item x
                        WHERE x.instance_id = p_instance_id
                          AND x.arrastre_de_item_id = pp.id);
    GET DIAGNOSTICS v_desde_custom = ROW_COUNT;

    UPDATE checklist_v2_instance
       SET arrastre_de_instance_id = v_prev
     WHERE id = p_instance_id;

    RETURN jsonb_build_object(
        'arrastre', true,
        'instancia_previa', v_prev,
        'nc_arrastradas', v_desde_tpl + v_desde_custom,
        'items_excluidos', v_excluidos
    );
END $$;

COMMENT ON FUNCTION fn_checklist_v3_arrastrar_nc(UUID) IS
    'Deja en el checklist de la OT solo las NC de la última inspección completa del equipo (60 días). MIG270.';


-- ── 3. El trigger arrastra al crear la instancia nueva ──────────────────────
CREATE OR REPLACE FUNCTION fn_auto_checklist_ot()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tpl        UUID;
    v_inst       UUID;
    v_contrato   UUID;
    v_horas      NUMERIC;
    v_km         NUMERIC;
    v_entrega    UUID;
BEGIN
    BEGIN
        SELECT id INTO v_tpl FROM checklist_template_v2
         WHERE momento_uso='recepcion_devolucion' AND activo=true
         ORDER BY version DESC LIMIT 1;
        IF v_tpl IS NULL THEN RETURN NEW; END IF;

        -- ya tiene checklist propio?
        IF EXISTS (SELECT 1 FROM checklist_v2_instance WHERE ot_id = NEW.id) THEN
            RETURN NEW;
        END IF;

        -- reusar SOLO una instancia LIBRE (ot_id IS NULL) del mismo equipo
        -- (p.ej. recepcion iniciada en terreno antes de existir la OT).
        SELECT id INTO v_inst FROM checklist_v2_instance
         WHERE activo_id = NEW.activo_id
           AND momento_uso = 'recepcion_devolucion'
           AND estado = 'en_progreso'
           AND ot_id IS NULL
         ORDER BY fecha_inicio DESC LIMIT 1;
        IF v_inst IS NOT NULL THEN
            UPDATE checklist_v2_instance SET ot_id = NEW.id WHERE id = v_inst;
            -- Si esa instancia libre tiene respuestas, es LA inspeccion en curso
            -- y se engancha entera. Si no tiene ninguna, es un cascaron vacio
            -- (p.ej. el que MIG269 descolgo) y le toca el mismo arrastre que a
            -- una instancia recien creada.
            IF NOT EXISTS (SELECT 1 FROM checklist_v2_instance_item ii
                            WHERE ii.instance_id = v_inst
                              AND COALESCE(ii.resultado, 'pendiente') <> 'pendiente') THEN
                BEGIN
                    PERFORM fn_checklist_v3_arrastrar_nc(v_inst);
                EXCEPTION WHEN OTHERS THEN NULL;
                END;
            END IF;
            RETURN NEW;
        END IF;

        -- si no hay libre, crear una instancia V03 nueva para esta OT
        SELECT contrato_id, horas_uso_actual, kilometraje_actual
          INTO v_contrato, v_horas, v_km
          FROM activos WHERE id = NEW.activo_id;

        SELECT id INTO v_entrega FROM checklist_v2_instance
         WHERE activo_id = NEW.activo_id AND momento_uso='entrega_arriendo' AND estado='cerrado'
         ORDER BY fecha_cierre DESC LIMIT 1;

        v_inst := fn_inicializar_checklist_v2(
            v_tpl, NEW.activo_id, COALESCE(NEW.contrato_id, v_contrato),
            NULL, v_horas, v_km, NULL, v_entrega
        );
        UPDATE checklist_v2_instance SET ot_id = NEW.id WHERE id = v_inst;

        -- MIG270: si el equipo ya se inspeccionó completo hace poco, esta OT
        -- arrastra solo las no conformidades.
        BEGIN
            PERFORM fn_checklist_v3_arrastrar_nc(v_inst);
        EXCEPTION WHEN OTHERS THEN NULL;  -- el arrastre nunca deja la OT sin checklist
        END;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    RETURN NEW;
END $$;

COMMENT ON FUNCTION fn_auto_checklist_ot() IS
    'Al crear cualquier OT activa el checklist V03; reusa instancias libres del equipo y, si el equipo ya se inspeccionó completo, arrastra solo las NC. MIG270 (sobre MIG177).';


-- ── 4. La vista muestra de dónde viene cada tarea arrastrada ────────────────
-- CREATE OR REPLACE (no DROP): v_taller_plan_semanal_ots_full depende de esta.
CREATE OR REPLACE VIEW v_taller_ot_checklist_v3 AS
 WITH inst AS (
         SELECT DISTINCT ON (checklist_v2_instance.ot_id) checklist_v2_instance.id,
            checklist_v2_instance.ot_id,
            checklist_v2_instance.activo_id,
            checklist_v2_instance.estado,
            checklist_v2_instance.arrastre_de_instance_id
           FROM checklist_v2_instance
          WHERE checklist_v2_instance.ot_id IS NOT NULL
          ORDER BY checklist_v2_instance.ot_id, checklist_v2_instance.fecha_inicio DESC
        )
 SELECT ii.id AS instance_item_id,
    inst.id AS instance_id,
    inst.ot_id,
    inst.estado AS instance_estado,
    COALESCE(ti.bloque::text, 'Tareas adicionales'::text) AS bloque,
    COALESCE(ti.bloque_orden, 999) AS bloque_orden,
    COALESCE(ti.orden, 9999) AS orden,
    ti.codigo,
    COALESCE(ii.descripcion_custom, ti.descripcion::character varying) AS descripcion,
    COALESCE(ii.tiempo_min_override, ti.tiempo_min::numeric) AS tiempo_min,
    ii.tiempo_min_override IS NOT NULL AS tiempo_editado,
    COALESCE(ti.requiere_foto, false) AS requiere_foto,
    COALESCE(ti.obligatorio, false) AS obligatorio,
    COALESCE(ti.critico, false) AS critico,
    ti.categoria_calidad,
    ii.resultado,
    ii.observacion,
    ii.foto_url,
    ii.excluido,
    ii.template_item_id IS NULL AS es_custom,
    ii.mediciones,
    ii.foto_urls,
    -- MIG270 — arrastre desde la inspección anterior
    inst.arrastre_de_instance_id IS NOT NULL AS instance_arrastre,
    po.folio AS arrastre_ot_folio,
    COALESCE(pi.fecha_cierre, pi.fecha_inicio) AS arrastre_fecha,
    ii.arrastre_de_item_id IS NOT NULL AS arrastre,
    pii.observacion AS arrastre_observacion,
    pii.foto_url AS arrastre_foto_url
   FROM inst
     JOIN checklist_v2_instance_item ii ON ii.instance_id = inst.id
     LEFT JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
     LEFT JOIN checklist_v2_instance pi ON pi.id = inst.arrastre_de_instance_id
     LEFT JOIN ordenes_trabajo po ON po.id = pi.ot_id
     LEFT JOIN checklist_v2_instance_item pii ON pii.id = ii.arrastre_de_item_id;

COMMENT ON VIEW v_taller_ot_checklist_v3 IS
    'Checklist V03 efectivo por OT con overrides a medida y el arrastre de NC de la inspección anterior. MIG270.';
GRANT SELECT ON v_taller_ot_checklist_v3 TO authenticated;


-- ── 5. Los dos escapes del jefe de taller ───────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_v3_arrastrar_nc(p_ot_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_rol  TEXT := fn_user_rol();
    v_inst UUID;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor','planificador') THEN
        RAISE EXCEPTION 'Sin permiso (rol: %)', v_rol; END IF;

    SELECT id INTO v_inst FROM checklist_v2_instance
     WHERE ot_id = p_ot_id ORDER BY fecha_inicio DESC LIMIT 1;
    IF v_inst IS NULL THEN RAISE EXCEPTION 'Esta OT no tiene checklist'; END IF;

    RETURN fn_checklist_v3_arrastrar_nc(v_inst);
END $$;
REVOKE ALL ON FUNCTION rpc_taller_v3_arrastrar_nc(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_taller_v3_arrastrar_nc(UUID) TO authenticated;

COMMENT ON FUNCTION rpc_taller_v3_arrastrar_nc(UUID) IS
    'El jefe deja en el checklist de una OT ya creada solo las NC de la inspección anterior. MIG270.';

CREATE OR REPLACE FUNCTION rpc_taller_v3_restaurar_completo(p_ot_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_rol  TEXT := fn_user_rol();
    v_inst UUID;
    v_n    INT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor','planificador') THEN
        RAISE EXCEPTION 'Sin permiso (rol: %)', v_rol; END IF;

    SELECT id INTO v_inst FROM checklist_v2_instance
     WHERE ot_id = p_ot_id ORDER BY fecha_inicio DESC LIMIT 1;
    IF v_inst IS NULL THEN RAISE EXCEPTION 'Esta OT no tiene checklist'; END IF;

    UPDATE checklist_v2_instance_item
       SET excluido = false
     WHERE instance_id = v_inst AND excluido = true;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    -- El marcador de arrastre por ítem se conserva (contexto del hallazgo);
    -- solo se apaga el de la instancia para que el checklist deje de leerse
    -- como "solo no conformidades".
    UPDATE checklist_v2_instance SET arrastre_de_instance_id = NULL WHERE id = v_inst;

    RETURN jsonb_build_object('ok', true, 'items_restaurados', v_n);
END $$;
REVOKE ALL ON FUNCTION rpc_taller_v3_restaurar_completo(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_taller_v3_restaurar_completo(UUID) TO authenticated;

COMMENT ON FUNCTION rpc_taller_v3_restaurar_completo(UUID) IS
    'Devuelve el checklist completo a una OT que arrastraba solo las NC. MIG270.';


-- ── 6. VALIDACION ───────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'cols_arrastre', (SELECT array_agg(table_name || '.' || column_name ORDER BY table_name)
        FROM information_schema.columns
        WHERE (table_name='checklist_v2_instance'      AND column_name='arrastre_de_instance_id')
           OR (table_name='checklist_v2_instance_item' AND column_name='arrastre_de_item_id')),
    'funciones', (SELECT array_agg(proname ORDER BY proname) FROM pg_proc
        WHERE proname IN ('fn_checklist_v3_arrastrar_nc','rpc_taller_v3_arrastrar_nc',
                          'rpc_taller_v3_restaurar_completo')),
    'vista_cols_nuevas', (SELECT array_agg(column_name ORDER BY column_name)
        FROM information_schema.columns WHERE table_name='v_taller_ot_checklist_v3'
          AND column_name IN ('arrastre','instance_arrastre','arrastre_observacion',
                              'arrastre_foto_url','arrastre_ot_folio','arrastre_fecha')),
    'ots_con_arrastre', (SELECT COUNT(*) FROM checklist_v2_instance
        WHERE arrastre_de_instance_id IS NOT NULL),
    'equipos_con_inspeccion_completa_60d', (SELECT COUNT(DISTINCT ci.activo_id)
        FROM checklist_v2_instance ci
       WHERE ci.momento_uso='recepcion_devolucion'
         AND COALESCE(ci.fecha_cierre, ci.fecha_inicio) >= NOW() - INTERVAL '60 days'
         AND NOT EXISTS (SELECT 1 FROM checklist_v2_instance_item ii
                          WHERE ii.instance_id = ci.id AND ii.excluido = false
                            AND COALESCE(ii.resultado,'pendiente') = 'pendiente')
         AND EXISTS (SELECT 1 FROM checklist_v2_instance_item ii
                      WHERE ii.instance_id = ci.id AND ii.excluido = false))
) AS resultado;

NOTIFY pgrst, 'reload schema';
