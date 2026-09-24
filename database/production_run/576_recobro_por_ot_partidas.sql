-- ============================================================================
-- MIG576 · Recobro por OT: el jefe arma las partidas, el planificador costea y emite
-- ============================================================================
--
-- 24-09-2026, Manuel, sobre la OT-202609-00011 (SVCZ-38): «necesito que el jefe
-- de taller pueda editar y agregar partidas, para poder recobrar y una vez que
-- esté listo, poder armar el informe de recobro». Flujo que definió:
--   «Jefe de taller da el OK y el planificador revisa, carga costos y da
--    ejecutar al informe». Los precios «los debe cargar el planificador».
--
-- Qué había: las líneas cobrables ya existían (informe_recepcion_costos), pero
-- el informe iba por EQUIPO (no por OT), las líneas solo se editaban en
-- Flota → Recepción → Emitir, NO se podían agregar, y el Word no traía montos.
--
-- Qué queda:
--   · Un informe de recobro por OT (informes_recepcion.ot_correctiva_id), con
--     a lo más UNO abierto por OT. Nace en 'borrador' (no pasa por
--     en_inspeccion → así no dispara trg_generar_nc_al_cerrar_recepcion).
--   · rpc_recobro_ot_preparar: crea/abre el informe de la OT y trae las NC
--     cobrables (cliente/compartido) de la OT que aún no estén en un informe,
--     con sus insumos y horas como partidas en $0. Idempotente.
--   · Partidas (rpc_recobro_partida_guardar / _eliminar):
--       JEFE (jefe_mantenimiento, jefe_operaciones, supervisor) agrega y edita
--       mientras no haya dado el OK; NO toca precios.
--       PLANIFICADOR edita todo, precios incluidos, hasta emitir.
--       ADMIN (administrador, gerencia, subgerente_operaciones) puede ambas.
--   · rpc_recobro_ok_jefe: el jefe da el OK (queda como quien elaboró).
--     rpc_recobro_devolver: el planificador lo devuelve al jefe con una nota.
--   · rpc_recobro_emitir: el planificador emite. Exige el OK del jefe, que toda
--     partida cobrable tenga precio, y doble firma (quien emite ≠ quien dio OK).
--   · Emitido = congelado: trigger que impide tocar partidas y hallazgos de un
--     informe emitido (antes solo lo impedía la pantalla).
-- ============================================================================

BEGIN;

ALTER TABLE informes_recepcion
    ADD COLUMN IF NOT EXISTS ok_jefe_por   UUID REFERENCES usuarios_perfil(id),
    ADD COLUMN IF NOT EXISTS ok_jefe_at    TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS ok_jefe_nota  TEXT,
    ADD COLUMN IF NOT EXISTS devuelto_nota TEXT;

COMMENT ON COLUMN informes_recepcion.ok_jefe_por IS
    '[MIG576] Jefe de taller que dio el OK a las partidas del recobro de la OT (queda como quien elaboró).';
COMMENT ON COLUMN informes_recepcion.devuelto_nota IS
    '[MIG576] Nota del planificador al devolverle el recobro al jefe.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_ir_recobro_ot_abierto
    ON informes_recepcion (ot_correctiva_id)
 WHERE ot_correctiva_id IS NOT NULL AND estado IN ('en_inspeccion', 'borrador');

-- ── Quién es quién en el recobro ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_recobro_perfil()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT CASE
        WHEN r IN ('administrador', 'gerencia', 'subgerente_operaciones') THEN 'admin'
        WHEN r = 'planificador' THEN 'planificador'
        WHEN r IN ('jefe_mantenimiento', 'jefe_operaciones', 'supervisor') THEN 'jefe'
    END
    FROM (SELECT public.fn_user_rol() AS r) x
$$;

-- Carga el informe y valida que se pueda tocar. Devuelve el perfil del usuario.
CREATE OR REPLACE FUNCTION fn_recobro_puede_editar(p_informe_id UUID, p_con_precio BOOLEAN DEFAULT false)
RETURNS TEXT LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_perfil TEXT := fn_recobro_perfil(); v_inf RECORD;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_perfil IS NULL THEN
        RAISE EXCEPTION 'Tu perfil no puede editar el recobro' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_inf FROM informes_recepcion WHERE id = p_informe_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Informe % no existe', p_informe_id; END IF;
    IF v_inf.estado NOT IN ('en_inspeccion', 'borrador') THEN
        RAISE EXCEPTION 'El informe % ya está %: no se puede modificar', v_inf.folio, v_inf.estado;
    END IF;
    IF v_perfil = 'jefe' AND v_inf.ok_jefe_at IS NOT NULL THEN
        RAISE EXCEPTION 'Ya diste el OK: ahora lo revisa el planificador. Si hay que cambiar algo, que te lo devuelva.';
    END IF;
    IF p_con_precio AND v_perfil = 'jefe' THEN
        RAISE EXCEPTION 'Los precios los carga el planificador' USING ERRCODE = '42501';
    END IF;
    RETURN v_perfil;
END;
$$;

-- ── Preparar el recobro de la OT ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_recobro_ot_preparar(p_ot_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
    v_user    UUID := auth.uid();
    v_perfil  TEXT := fn_recobro_perfil();
    v_ot      RECORD;
    v_activo  RECORD;
    v_inf     RECORD;
    v_nuevo   BOOLEAN := false;
    v_periodo VARCHAR(6);
    v_sec     INT;
    v_yo      TEXT;
    v_hallazgo UUID;
    v_traidas INT := 0;
    v_costos  INT := 0;
    nc  RECORD;
    mat RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_perfil IS NULL THEN
        RAISE EXCEPTION 'Tu perfil no puede armar el recobro' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_ot FROM ordenes_trabajo WHERE id = p_ot_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'OT % no existe', p_ot_id; END IF;
    SELECT * INTO v_activo FROM activos WHERE id = v_ot.activo_id;
    SELECT nombre_completo INTO v_yo FROM usuarios_perfil WHERE id = v_user;

    SELECT * INTO v_inf FROM informes_recepcion
     WHERE ot_correctiva_id = p_ot_id AND estado IN ('en_inspeccion', 'borrador');

    IF NOT FOUND THEN
        PERFORM pg_advisory_xact_lock(hashtext('ir_folio_lock'));
        v_periodo := TO_CHAR(NOW(), 'YYYYMM');
        SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)), 0) + 1
          INTO v_sec FROM informes_recepcion WHERE folio LIKE 'IR-' || v_periodo || '-%';
        INSERT INTO informes_recepcion (
            activo_id, contrato_id, cliente_nombre, fecha_recepcion, ot_correctiva_id,
            estado, folio, observaciones_finales,
            n_chasis, kilometraje, horometro, lugar_chequeo, elaborado_por
        ) VALUES (
            v_ot.activo_id, COALESCE(v_ot.contrato_id, fn_contrato_para_ot(v_ot.activo_id)),
            v_activo.cliente_actual, CURRENT_DATE, p_ot_id,
            'borrador', 'IR-' || v_periodo || '-' || LPAD(v_sec::TEXT, 5, '0'),
            'Recobro de la ' || v_ot.folio || '. El jefe de taller arma las partidas; el planificador carga los costos y emite.',
            COALESCE(v_activo.vin_chasis, v_activo.numero_serie),
            CASE WHEN v_activo.kilometraje_actual IS NOT NULL
                 THEN to_char(v_activo.kilometraje_actual, 'FM999G999G999D0') || ' km' END,
            CASE WHEN v_activo.horas_uso_actual IS NOT NULL
                 THEN to_char(v_activo.horas_uso_actual, 'FM999G999D0') || ' hrs' END,
            v_activo.ubicacion_actual, v_yo
        ) RETURNING * INTO v_inf;
        v_nuevo := true;
    ELSIF v_perfil = 'jefe' AND v_inf.ok_jefe_at IS NOT NULL THEN
        -- Ya dio el OK: no se le agregan cosas por detrás al planificador.
        RETURN jsonb_build_object('ok', true, 'informe_id', v_inf.id, 'folio', v_inf.folio,
                                  'nuevo', false, 'nc_traidas', 0, 'partidas_creadas', 0);
    END IF;

    -- NC cobrables de ESTA OT que todavía no están en ningún informe.
    FOR nc IN
        SELECT n.id, n.descripcion, n.severidad, n.foto_url, n.checklist_item_ref,
               n.horas_estimadas, n.grupo_trabajo, n.recobro_nota, v.recobro, v.observacion_item
          FROM no_conformidades n
          JOIN v_nc_recepcion v ON v.id = n.id
         WHERE (n.ot_id = p_ot_id OR n.plan_ot_id = p_ot_id)
           AND v.recobro IN ('cliente', 'compartido')
           AND n.estado_planificacion <> 'descartada'
           AND n.recobro_informe_id IS NULL
         ORDER BY n.created_at
    LOOP
        INSERT INTO informe_recepcion_hallazgos (
            informe_id, seccion, descripcion, gravedad, atribuible_cliente,
            fotos, observacion, checklist_v2_item_id, diagnostico, amerita_recobro
        ) VALUES (
            v_inf.id, 'No Conformidad del taller', nc.descripcion,
            (CASE nc.severidad WHEN 'critica' THEN 'critica' WHEN 'alta' THEN 'mayor'
                               ELSE 'menor' END)::gravedad_hallazgo_enum,
            (nc.recobro = 'cliente'),
            CASE WHEN nc.foto_url IS NOT NULL THEN jsonb_build_array(nc.foto_url) ELSE '[]'::JSONB END,
            NULLIF(concat_ws(' · ', nc.observacion_item, nc.recobro_nota), ''),
            nc.checklist_item_ref, nc.observacion_item,
            CASE nc.recobro WHEN 'cliente' THEN 'Si Amerita recobro' ELSE 'Recobro compartido' END
        ) RETURNING id INTO v_hallazgo;
        v_traidas := v_traidas + 1;

        UPDATE no_conformidades
           SET recobro_informe_id = v_inf.id, recobro_hallazgo_id = v_hallazgo, updated_at = NOW()
         WHERE id = nc.id;

        FOR mat IN
            SELECT descripcion, cantidad, unidad, producto_id
              FROM v_nc_insumos WHERE nc_id = nc.id AND estado <> 'rechazado'
        LOOP
            INSERT INTO informe_recepcion_costos (
                informe_id, tipo, producto_id, descripcion, cantidad, unidad,
                precio_unitario, cobrable_cliente, hallazgo_id, editado_por, editado_en
            ) VALUES (
                v_inf.id, 'repuesto', mat.producto_id, COALESCE(mat.descripcion, 'Material'),
                COALESCE(NULLIF(mat.cantidad, 0), 1), mat.unidad, 0, true, v_hallazgo, v_user, NOW()
            );
            v_costos := v_costos + 1;
        END LOOP;

        IF COALESCE(nc.horas_estimadas, 0) > 0 THEN
            INSERT INTO informe_recepcion_costos (
                informe_id, tipo, descripcion, cantidad, unidad,
                precio_unitario, cobrable_cliente, hallazgo_id, editado_por, editado_en
            ) VALUES (
                v_inf.id, 'mano_obra',
                'Mano de obra — ' || left(nc.descripcion, 200) || COALESCE(' (' || nc.grupo_trabajo || ')', ''),
                nc.horas_estimadas, 'HH', 0, true, v_hallazgo, v_user, NOW()
            );
            v_costos := v_costos + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object('ok', true, 'informe_id', v_inf.id, 'folio', v_inf.folio,
                              'nuevo', v_nuevo, 'nc_traidas', v_traidas, 'partidas_creadas', v_costos);
END;
$$;

-- ── Partidas ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_recobro_partida_guardar(
    p_informe_id      UUID,
    p_partida_id      UUID,
    p_tipo            TEXT,
    p_descripcion     TEXT,
    p_cantidad        NUMERIC,
    p_unidad          TEXT DEFAULT NULL,
    p_cobrable        BOOLEAN DEFAULT true,
    p_precio_unitario NUMERIC DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_perfil TEXT := fn_recobro_puede_editar(p_informe_id, false);
    v_id     UUID;
    v_precio NUMERIC;
BEGIN
    IF COALESCE(trim(p_descripcion), '') = '' THEN RAISE EXCEPTION 'La partida necesita una descripción'; END IF;
    IF COALESCE(p_cantidad, 0) <= 0 THEN RAISE EXCEPTION 'La cantidad debe ser mayor que cero'; END IF;
    IF p_tipo NOT IN ('repuesto', 'mano_obra', 'servicio_externo', 'otro') THEN
        RAISE EXCEPTION 'Tipo de partida inválido: %', p_tipo;
    END IF;
    IF p_precio_unitario IS NOT NULL AND p_precio_unitario < 0 THEN
        RAISE EXCEPTION 'El precio no puede ser negativo';
    END IF;

    IF p_partida_id IS NULL THEN
        v_precio := CASE WHEN v_perfil = 'jefe' THEN 0 ELSE COALESCE(p_precio_unitario, 0) END;
        INSERT INTO informe_recepcion_costos (
            informe_id, tipo, descripcion, cantidad, unidad, precio_unitario,
            cobrable_cliente, editado_por, editado_en
        ) VALUES (
            p_informe_id, p_tipo::tipo_costo_recepcion_enum, left(trim(p_descripcion), 300),
            p_cantidad, NULLIF(trim(p_unidad), ''), v_precio, COALESCE(p_cobrable, true), auth.uid(), NOW()
        ) RETURNING id INTO v_id;
    ELSE
        UPDATE informe_recepcion_costos
           SET tipo             = p_tipo::tipo_costo_recepcion_enum,
               descripcion      = left(trim(p_descripcion), 300),
               cantidad         = p_cantidad,
               unidad           = NULLIF(trim(p_unidad), ''),
               cobrable_cliente = COALESCE(p_cobrable, true),
               -- El jefe no toca precios: se conserva lo que haya puesto el planificador.
               precio_unitario  = CASE WHEN v_perfil = 'jefe' THEN precio_unitario
                                       ELSE COALESCE(p_precio_unitario, precio_unitario) END,
               editado_por      = auth.uid(),
               editado_en       = NOW()
         WHERE id = p_partida_id AND informe_id = p_informe_id
        RETURNING id INTO v_id;
        IF v_id IS NULL THEN RAISE EXCEPTION 'La partida no pertenece a este informe'; END IF;
    END IF;
    RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION rpc_recobro_partida_eliminar(p_partida_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_informe UUID;
BEGIN
    SELECT informe_id INTO v_informe FROM informe_recepcion_costos WHERE id = p_partida_id;
    IF v_informe IS NULL THEN RAISE EXCEPTION 'La partida no existe'; END IF;
    PERFORM fn_recobro_puede_editar(v_informe, false);
    DELETE FROM informe_recepcion_costos WHERE id = p_partida_id;
END;
$$;

-- ── OK del jefe / devolver ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_recobro_ok_jefe(p_informe_id UUID, p_nota TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_perfil TEXT := fn_recobro_puede_editar(p_informe_id, false);
BEGIN
    IF v_perfil = 'planificador' THEN
        RAISE EXCEPTION 'El OK lo da el jefe de taller' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM informe_recepcion_costos WHERE informe_id = p_informe_id AND cobrable_cliente) THEN
        RAISE EXCEPTION 'No hay ninguna partida cobrable al cliente: agrega al menos una antes de dar el OK';
    END IF;
    UPDATE informes_recepcion
       SET ok_jefe_por = auth.uid(), ok_jefe_at = NOW(), ok_jefe_nota = NULLIF(trim(p_nota), ''),
           inspector_id = auth.uid(), devuelto_nota = NULL,
           elaborado_por = COALESCE((SELECT nombre_completo FROM usuarios_perfil WHERE id = auth.uid()), elaborado_por)
     WHERE id = p_informe_id;
    RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION rpc_recobro_devolver(p_informe_id UUID, p_nota TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_perfil TEXT := fn_recobro_puede_editar(p_informe_id, false);
BEGIN
    IF v_perfil = 'jefe' THEN RAISE EXCEPTION 'Lo devuelve el planificador' USING ERRCODE = '42501'; END IF;
    IF COALESCE(trim(p_nota), '') = '' THEN RAISE EXCEPTION 'Escribe qué hay que corregir'; END IF;
    UPDATE informes_recepcion
       SET ok_jefe_por = NULL, ok_jefe_at = NULL, devuelto_nota = trim(p_nota)
     WHERE id = p_informe_id AND ok_jefe_at IS NOT NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'El jefe todavía no ha dado el OK'; END IF;
    RETURN jsonb_build_object('ok', true);
END;
$$;

-- ── Emitir ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_recobro_emitir(p_informe_id UUID, p_observaciones TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_perfil TEXT := fn_recobro_puede_editar(p_informe_id, true);
    v_inf    RECORD;
    v_sin_precio INT;
BEGIN
    SELECT * INTO v_inf FROM informes_recepcion WHERE id = p_informe_id;
    IF v_inf.ok_jefe_at IS NULL THEN
        RAISE EXCEPTION 'Falta el OK del jefe de taller a las partidas';
    END IF;
    IF v_inf.ok_jefe_por = auth.uid() THEN
        RAISE EXCEPTION 'Doble firma: quien dio el OK no puede emitir el mismo informe';
    END IF;
    SELECT count(*) INTO v_sin_precio FROM informe_recepcion_costos
     WHERE informe_id = p_informe_id AND cobrable_cliente AND precio_unitario <= 0;
    IF v_sin_precio > 0 THEN
        RAISE EXCEPTION 'Faltan precios en % partida(s) cobrable(s)', v_sin_precio;
    END IF;
    UPDATE informes_recepcion
       SET estado = 'emitido', encargado_cobros_id = auth.uid(),
           observaciones_finales = COALESCE(NULLIF(trim(p_observaciones), ''), observaciones_finales),
           emitido_en = NOW()
     WHERE id = p_informe_id;
    SELECT * INTO v_inf FROM informes_recepcion WHERE id = p_informe_id;
    RETURN jsonb_build_object('ok', true, 'folio', v_inf.folio, 'total', v_inf.total,
                              'total_cobrable', v_inf.total_cobrable_cliente);
END;
$$;

-- ── Emitido = congelado (antes solo lo cuidaba la pantalla) ─────────────────
CREATE OR REPLACE FUNCTION fn_trg_informe_emitido_congelado()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_estado TEXT;
BEGIN
    SELECT estado INTO v_estado FROM informes_recepcion
     WHERE id = COALESCE(NEW.informe_id, OLD.informe_id);
    IF v_estado = 'emitido' THEN
        RAISE EXCEPTION 'El informe ya fue emitido: sus partidas y hallazgos no se pueden modificar';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_costos_informe_emitido ON informe_recepcion_costos;
CREATE TRIGGER trg_costos_informe_emitido
    BEFORE INSERT OR UPDATE OR DELETE ON informe_recepcion_costos
    FOR EACH ROW EXECUTE FUNCTION fn_trg_informe_emitido_congelado();
DROP TRIGGER IF EXISTS trg_hallazgos_informe_emitido ON informe_recepcion_hallazgos;
CREATE TRIGGER trg_hallazgos_informe_emitido
    BEFORE INSERT OR UPDATE OR DELETE ON informe_recepcion_hallazgos
    FOR EACH ROW EXECUTE FUNCTION fn_trg_informe_emitido_congelado();

REVOKE ALL ON FUNCTION rpc_recobro_ot_preparar(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_recobro_partida_guardar(UUID, UUID, TEXT, TEXT, NUMERIC, TEXT, BOOLEAN, NUMERIC) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_recobro_partida_eliminar(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_recobro_ok_jefe(UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_recobro_devolver(UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_recobro_emitir(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_recobro_ot_preparar(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_recobro_partida_guardar(UUID, UUID, TEXT, TEXT, NUMERIC, TEXT, BOOLEAN, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_recobro_partida_eliminar(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_recobro_ok_jefe(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_recobro_devolver(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_recobro_emitir(UUID, TEXT) TO authenticated;

COMMIT;
