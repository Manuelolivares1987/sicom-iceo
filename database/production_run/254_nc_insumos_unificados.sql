-- ============================================================================
-- SICOM-ICEO | 254 — Un solo lugar para pedir insumos a bodega desde la NC
-- ----------------------------------------------------------------------------
-- Manuel (2026-07-29): «está enredado, a cada NC solicitar los insumos a
-- bodega; investiga esa parte y mejórala, hazla más intuitiva».
--
-- DIAGNÓSTICO. Desde la ficha de una NC hay HOY TRES caminos distintos para
-- pedirle algo a bodega, y el jefe tiene que adivinar cuál usar:
--
--   camino                              tabla                     uso real
--   ----------------------------------  ------------------------  ---------
--   «Materiales de esta NC» (select)    nc_materiales             0 filas
--   toggle «no hay» -> solicitud        bodega_solicitudes        0 filas
--   «Insumos del taller» (+Ítem)        ot_recursos_solicitados   11 filas
--
-- Dos de los tres NUNCA se usaron en producción. Los tres desembocan en el
-- MISMO vale (rpc_crear_ticket_bodega junta nc_materiales + recursos), pero la
-- UI no lo dice en ninguna parte. Y al elegir un material el jefe NO ve si hay
-- stock: tiene que marcar «no hay» a ojo.
--
-- SOLUCIÓN: una sola lista por NC y un solo botón.
--   1. ot_recursos_solicitados.no_conformidad_id: el pedido queda amarrado a la
--      NC de forma explícita (antes solo se podía inferir por el ítem de
--      checklist, y las NC manuales/ad-hoc/de nota no tenían cómo).
--   2. v_nc_insumos: UNA vista que junta las tres fuentes con forma común,
--      estado normalizado y el stock disponible al lado.
--   3. rpc_nc_insumo_agregar / rpc_nc_insumo_quitar: el jefe agrega y el
--      sistema decide dónde guardarlo (si la NC ya tiene OT va al circuito de
--      recursos; si no, queda como material de la NC). Los dos terminan en el
--      mismo vale.
--   4. rpc_nc_informe_recobro pasa a leer la lista unificada — si no, lo que el
--      jefe agregue por el camino nuevo no llegaría al informe de recobro.
-- ADITIVA, IDEMPOTENTE. No borra datos.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_nc_informe_recobro') THEN
        RAISE EXCEPTION 'STOP — falta MIG251/253.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='ot_recursos_solicitados' AND column_name='instance_item_id') THEN
        RAISE EXCEPTION 'STOP — falta MIG199.';
    END IF;
END $$;


-- ── 1. El pedido sabe a qué NC pertenece ────────────────────────────────────
ALTER TABLE ot_recursos_solicitados
    ADD COLUMN IF NOT EXISTS no_conformidad_id UUID REFERENCES no_conformidades(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_ot_recursos_nc ON ot_recursos_solicitados(no_conformidad_id)
    WHERE no_conformidad_id IS NOT NULL;

COMMENT ON COLUMN ot_recursos_solicitados.no_conformidad_id IS
    'NC a la que pertenece el insumo. Antes solo se podía inferir por instance_item_id (y las NC manuales no tenían cómo). MIG254.';

-- Backfill: lo que ya está ligado al ítem de checklist se amarra a su NC
UPDATE ot_recursos_solicitados r
   SET no_conformidad_id = nc.id
  FROM no_conformidades nc
 WHERE r.no_conformidad_id IS NULL
   AND r.instance_item_id IS NOT NULL
   AND nc.checklist_item_ref = r.instance_item_id;


-- ── 2. UNA lista de insumos por NC ──────────────────────────────────────────
-- Junta las tres fuentes con forma común. `fuente` dice de dónde salió cada
-- línea (la UI no lo muestra, pero rpc_nc_insumo_quitar lo necesita para saber
-- qué tabla tocar).
CREATE OR REPLACE VIEW v_nc_insumos AS
-- (a) Recursos del circuito de OT: lo que pide el operador y lo que agrega el jefe
SELECT r.id,
       'recurso'::TEXT                        AS fuente,
       r.no_conformidad_id                    AS nc_id,
       r.ot_id,
       r.producto_id,
       COALESCE(r.descripcion, pr.nombre)     AS descripcion,
       COALESCE(r.unidad, pr.unidad_medida)   AS unidad,
       COALESCE(r.cantidad_aprobada, r.cantidad) AS cantidad,
       r.cantidad                             AS cantidad_pedida,
       r.estado                               AS estado,
       r.comentario,
       r.fotos,
       r.solicitado_nombre,
       COALESCE(r.agregado_por_jefe, false)   AS lo_agrego_el_jefe,
       r.ticket_id,
       t.folio                                AS ticket_folio,
       r.created_at
  FROM ot_recursos_solicitados r
  LEFT JOIN productos pr    ON pr.id = r.producto_id
  LEFT JOIN bodega_tickets t ON t.id = r.ticket_id
 WHERE r.no_conformidad_id IS NOT NULL

UNION ALL

-- (b) Materiales cargados en la NC (cuando todavía no hay OT donde colgarlos)
SELECT m.id,
       'material'::TEXT,
       m.no_conformidad_id,
       NULL::UUID,
       m.producto_id,
       COALESCE(m.descripcion, pr.nombre),
       pr.unidad_medida,
       m.cantidad,
       m.cantidad,
       -- Si ya viaja en un vale vigente se muestra así; si no, está listo para el vale
       CASE WHEN EXISTS (
              SELECT 1 FROM bodega_ticket_items bti
                JOIN bodega_tickets bt ON bt.id = bti.ticket_id AND bt.estado <> 'anulado'
               WHERE bti.nc_material_id = m.id)
            THEN 'en_vale' ELSE 'aprobado' END,
       m.comentario,
       NULL::TEXT[],
       NULL::VARCHAR,
       true,
       (SELECT bti.ticket_id FROM bodega_ticket_items bti
          JOIN bodega_tickets bt ON bt.id = bti.ticket_id AND bt.estado <> 'anulado'
         WHERE bti.nc_material_id = m.id LIMIT 1),
       (SELECT bt.folio FROM bodega_ticket_items bti
          JOIN bodega_tickets bt ON bt.id = bti.ticket_id AND bt.estado <> 'anulado'
         WHERE bti.nc_material_id = m.id LIMIT 1),
       m.created_at
  FROM nc_materiales m
  LEFT JOIN productos pr ON pr.id = m.producto_id

UNION ALL

-- (c) Solicitudes de compra a bodega asociadas a la NC
SELECT s.id,
       'compra'::TEXT,
       s.no_conformidad_id,
       NULL::UUID,
       NULL::UUID,
       s.descripcion,
       s.unidad,
       s.cantidad,
       s.cantidad,
       'en_compra'::VARCHAR,
       s.observacion,
       CASE WHEN s.foto_url IS NOT NULL THEN ARRAY[s.foto_url] ELSE NULL END,
       NULL::VARCHAR,
       true,
       NULL::UUID,
       NULL::VARCHAR,
       s.created_at
  FROM bodega_solicitudes s
 WHERE s.no_conformidad_id IS NOT NULL;

GRANT SELECT ON v_nc_insumos TO authenticated;


-- ── 3. Stock a la vista al momento de elegir ────────────────────────────────
-- El jefe ya no adivina si hay: la búsqueda le dice cuánto queda.
CREATE OR REPLACE FUNCTION public.rpc_buscar_insumos(p_q TEXT, p_limit INT DEFAULT 10)
RETURNS TABLE (
    id UUID, codigo VARCHAR, nombre VARCHAR, unidad_medida VARCHAR, stock NUMERIC
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT p.id, p.codigo, p.nombre, p.unidad_medida,
           COALESCE((SELECT sum(sb.cantidad) FROM stock_bodega sb WHERE sb.producto_id = p.id), 0) AS stock
      FROM productos p
     WHERE btrim(COALESCE(p_q,'')) <> ''
       AND (p.codigo ILIKE '%'||btrim(p_q)||'%' OR p.nombre ILIKE '%'||btrim(p_q)||'%')
     ORDER BY (COALESCE((SELECT sum(sb.cantidad) FROM stock_bodega sb WHERE sb.producto_id = p.id), 0) > 0) DESC,
              p.nombre
     LIMIT GREATEST(COALESCE(p_limit, 10), 1);
$function$;

REVOKE ALL ON FUNCTION public.rpc_buscar_insumos(TEXT, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_buscar_insumos(TEXT, INT) TO authenticated;


-- ── 4. Agregar un insumo: el jefe no elige circuito, lo elige el sistema ────
CREATE OR REPLACE FUNCTION public.rpc_nc_insumo_agregar(
    p_nc_id       UUID,
    p_cantidad    NUMERIC,
    p_producto_id UUID    DEFAULT NULL,
    p_descripcion TEXT    DEFAULT NULL,   -- texto libre cuando no está en el catálogo
    p_unidad      TEXT    DEFAULT NULL,
    p_comentario  TEXT    DEFAULT NULL,
    p_fotos       TEXT[]  DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user  UUID := auth.uid();
    v_rol   TEXT := public.fn_user_rol();
    v_nc    RECORD;
    v_ot    UUID;
    v_stock NUMERIC;
    v_id    UUID;
    v_nom   TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol IS NULL OR v_rol NOT IN (
        'administrador','gerencia','subgerente_operaciones','jefe_operaciones',
        'jefe_mantenimiento','planificador','supervisor') THEN
        RAISE EXCEPTION 'No autorizado para pedir insumos (rol: %)', COALESCE(v_rol,'?')
            USING ERRCODE='42501';
    END IF;

    IF COALESCE(p_cantidad, 0) <= 0 THEN RAISE EXCEPTION 'La cantidad debe ser mayor que cero'; END IF;
    IF p_producto_id IS NULL AND btrim(COALESCE(p_descripcion,'')) = '' THEN
        RAISE EXCEPTION 'Elige un producto de bodega o describe el material';
    END IF;

    SELECT id, activo_id, ot_id, plan_ot_id INTO v_nc FROM no_conformidades WHERE id = p_nc_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'La NC % no existe', p_nc_id; END IF;

    SELECT COALESCE(sum(cantidad), 0) INTO v_stock
      FROM stock_bodega WHERE producto_id = p_producto_id;
    SELECT nombre INTO v_nom FROM productos WHERE id = p_producto_id;

    -- La OT correctiva manda; si no hay, la de origen del hallazgo.
    v_ot := COALESCE(v_nc.plan_ot_id, v_nc.ot_id);

    IF v_ot IS NOT NULL THEN
        -- Circuito de recursos de la OT: ya aprobado (lo pone el jefe) y listo
        -- para el vale del equipo.
        INSERT INTO ot_recursos_solicitados (
            ot_id, no_conformidad_id, producto_id, descripcion, unidad, cantidad,
            cantidad_aprobada, comentario, estado, solicitado_por, agregado_por_jefe,
            validado_por, validado_at, fotos
        ) VALUES (
            v_ot, p_nc_id, p_producto_id,
            COALESCE(NULLIF(btrim(p_descripcion),''), v_nom),
            p_unidad, p_cantidad, p_cantidad, NULLIF(btrim(COALESCE(p_comentario,'')),''),
            'aprobado', v_user, true, v_user, NOW(), p_fotos
        ) RETURNING id INTO v_id;

        RETURN jsonb_build_object('ok', true, 'id', v_id, 'fuente', 'recurso',
                                  'stock', v_stock, 'sin_stock', (p_producto_id IS NOT NULL AND v_stock <= 0));
    END IF;

    -- Todavía no hay OT: queda como material de la NC y entra al vale en cuanto
    -- el equipo tenga una.
    INSERT INTO nc_materiales (no_conformidad_id, producto_id, descripcion, cantidad, comentario)
    VALUES (p_nc_id, p_producto_id,
            COALESCE(NULLIF(btrim(p_descripcion),''), v_nom),
            p_cantidad, NULLIF(btrim(COALESCE(p_comentario,'')),''))
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('ok', true, 'id', v_id, 'fuente', 'material',
                              'stock', v_stock, 'sin_stock', (p_producto_id IS NOT NULL AND v_stock <= 0));
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_nc_insumo_agregar(UUID,NUMERIC,UUID,TEXT,TEXT,TEXT,TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_nc_insumo_agregar(UUID,NUMERIC,UUID,TEXT,TEXT,TEXT,TEXT[]) TO authenticated;


-- ── 5. Quitar una línea (mientras no esté en un vale) ───────────────────────
CREATE OR REPLACE FUNCTION public.rpc_nc_insumo_quitar(p_id UUID, p_fuente TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := public.fn_user_rol();
    v_est  TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol IS NULL OR v_rol NOT IN (
        'administrador','gerencia','subgerente_operaciones','jefe_operaciones',
        'jefe_mantenimiento','planificador','supervisor') THEN
        RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501';
    END IF;

    IF p_fuente = 'recurso' THEN
        SELECT estado INTO v_est FROM ot_recursos_solicitados WHERE id = p_id;
        IF v_est IS NULL THEN RAISE EXCEPTION 'El insumo no existe'; END IF;
        IF v_est IN ('en_vale','entregado') THEN
            RAISE EXCEPTION 'Ya va en un vale de bodega: anula el vale para poder quitarlo';
        END IF;
        DELETE FROM ot_recursos_solicitados WHERE id = p_id;

    ELSIF p_fuente = 'material' THEN
        IF EXISTS (SELECT 1 FROM bodega_ticket_items bti
                     JOIN bodega_tickets bt ON bt.id = bti.ticket_id AND bt.estado <> 'anulado'
                    WHERE bti.nc_material_id = p_id) THEN
            RAISE EXCEPTION 'Ya va en un vale de bodega: anula el vale para poder quitarlo';
        END IF;
        DELETE FROM nc_materiales WHERE id = p_id;

    ELSIF p_fuente = 'compra' THEN
        DELETE FROM bodega_solicitudes WHERE id = p_id AND estado = 'pendiente';

    ELSE
        RAISE EXCEPTION 'Fuente desconocida: %', p_fuente;
    END IF;

    RETURN jsonb_build_object('ok', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_nc_insumo_quitar(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_nc_insumo_quitar(UUID, TEXT) TO authenticated;


-- ── 5b. Guardar SOLO la mano de obra de la NC ───────────────────────────────
-- fn_asignar_recursos_nc borra y reescribe TODOS los materiales de la NC. Ahora
-- que los insumos se agregan uno a uno desde su propio panel, guardar el
-- análisis con esa función borraría lo recién pedido. Este RPC toca únicamente
-- grupo / horas / días.
CREATE OR REPLACE FUNCTION public.rpc_nc_recursos_mo(
    p_nc_id       UUID,
    p_grupo       TEXT    DEFAULT NULL,
    p_horas       NUMERIC DEFAULT NULL,
    p_tiempo_dias NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := public.fn_user_rol();
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol IS NULL OR v_rol NOT IN (
        'administrador','gerencia','subgerente_operaciones','jefe_operaciones',
        'jefe_mantenimiento','planificador','supervisor') THEN
        RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501';
    END IF;

    UPDATE no_conformidades SET
        grupo_trabajo        = COALESCE(NULLIF(btrim(COALESCE(p_grupo,'')),''), grupo_trabajo),
        horas_estimadas      = COALESCE(p_horas, horas_estimadas),
        tiempo_estimado_dias = COALESCE(p_tiempo_dias, tiempo_estimado_dias),
        estado_planificacion = CASE WHEN estado_planificacion = 'registrada'
                                    THEN 'con_recursos' ELSE estado_planificacion END,
        updated_at = NOW()
     WHERE id = p_nc_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'La NC % no existe', p_nc_id; END IF;
    RETURN jsonb_build_object('ok', true, 'nc_id', p_nc_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_nc_recursos_mo(UUID, TEXT, NUMERIC, NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_nc_recursos_mo(UUID, TEXT, NUMERIC, NUMERIC) TO authenticated;


-- ── 6. El informe de recobro lee la lista unificada ─────────────────────────
-- Si no, lo que el jefe agregue por el camino nuevo (recursos) no llegaría al
-- informe: antes solo miraba nc_materiales.
CREATE OR REPLACE FUNCTION public.rpc_nc_informe_recobro(
    p_activo_id     UUID,
    p_nc_ids        UUID[] DEFAULT NULL,
    p_tarifa_hh_id  UUID   DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user      UUID := auth.uid();
    v_rol       TEXT := public.fn_user_rol();
    v_activo    RECORD;
    v_informe   RECORD;
    v_folio     VARCHAR;
    v_periodo   VARCHAR(6);
    v_sec       INTEGER;
    v_tarifa_id     UUID;
    v_tarifa_nombre TEXT;
    v_nuevo     BOOLEAN := false;
    v_hallazgo  UUID;
    v_creados   INT := 0;
    v_ya        INT := 0;
    v_costos    INT := 0;
    nc          RECORD;
    mat         RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol IS NULL OR v_rol NOT IN (
        'administrador','gerencia','subgerente_operaciones','jefe_operaciones',
        'jefe_mantenimiento','planificador','supervisor') THEN
        RAISE EXCEPTION 'No autorizado para armar el informe de recobro (rol: %)', COALESCE(v_rol,'?')
            USING ERRCODE='42501';
    END IF;

    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Equipo % no existe', p_activo_id; END IF;

    -- Escalares, no RECORD: si no se elige tarifa quedan NULL y la línea de mano
    -- de obra sale sin especialidad (leer un RECORD sin asignar aborta).
    IF p_tarifa_hh_id IS NOT NULL THEN
        SELECT id, nombre INTO v_tarifa_id, v_tarifa_nombre
          FROM tarifas_hh WHERE id = p_tarifa_hh_id AND activo;
    END IF;

    SELECT * INTO v_informe FROM informes_recepcion
     WHERE activo_id = p_activo_id AND estado IN ('en_inspeccion','borrador')
     ORDER BY created_at DESC LIMIT 1;

    IF NOT FOUND THEN
        PERFORM pg_advisory_xact_lock(hashtext('ir_folio_lock'));
        v_periodo := TO_CHAR(NOW(), 'YYYYMM');
        SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)), 0) + 1
          INTO v_sec FROM informes_recepcion WHERE folio LIKE 'IR-' || v_periodo || '-%';
        v_folio := 'IR-' || v_periodo || '-' || LPAD(v_sec::TEXT, 5, '0');

        INSERT INTO informes_recepcion (
            activo_id, contrato_id, cliente_nombre, fecha_recepcion,
            inspector_id, estado, folio, observaciones_finales
        ) VALUES (
            p_activo_id, fn_contrato_para_ot(p_activo_id), v_activo.cliente_actual, CURRENT_DATE,
            v_user, 'borrador', v_folio,
            'Recobro armado desde las No Conformidades del taller. Valores pendientes: los carga el planificador.'
        )
        RETURNING * INTO v_informe;
        v_nuevo := true;
    END IF;

    FOR nc IN
        SELECT n.id, n.descripcion, n.severidad, n.foto_url, n.checklist_item_ref,
               n.horas_estimadas, n.grupo_trabajo, n.recobro_hallazgo_id, n.recobro_nota,
               v.recobro, v.observacion_item
          FROM no_conformidades n
          JOIN v_nc_recepcion v ON v.id = n.id
         WHERE n.activo_id = p_activo_id
           AND (p_nc_ids IS NULL OR n.id = ANY(p_nc_ids))
           AND v.recobro IN ('cliente','compartido')
           AND n.estado_planificacion <> 'descartada'
         ORDER BY n.created_at
    LOOP
        IF nc.recobro_hallazgo_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM informe_recepcion_hallazgos
             WHERE id = nc.recobro_hallazgo_id AND informe_id = v_informe.id) THEN
            v_ya := v_ya + 1;
            CONTINUE;
        END IF;

        INSERT INTO informe_recepcion_hallazgos (
            informe_id, seccion, descripcion, gravedad, atribuible_cliente,
            fotos, observacion, checklist_v2_item_id
        ) VALUES (
            v_informe.id, 'No Conformidad del taller', nc.descripcion,
            (CASE nc.severidad WHEN 'critica' THEN 'critica'
                               WHEN 'alta'    THEN 'mayor'
                               ELSE 'menor' END)::gravedad_hallazgo_enum,
            (nc.recobro = 'cliente'),
            CASE WHEN nc.foto_url IS NOT NULL THEN jsonb_build_array(nc.foto_url) ELSE '[]'::JSONB END,
            NULLIF(concat_ws(' · ', nc.observacion_item, nc.recobro_nota), ''),
            nc.checklist_item_ref
        )
        RETURNING id INTO v_hallazgo;
        v_creados := v_creados + 1;

        UPDATE no_conformidades
           SET recobro_informe_id = v_informe.id, recobro_hallazgo_id = v_hallazgo, updated_at = NOW()
         WHERE id = nc.id;

        -- [MIG254] La lista unificada: materiales de la NC + recursos del taller.
        -- Sin valores: los precios los carga el planificador (MIG253).
        FOR mat IN
            SELECT descripcion, cantidad, unidad, producto_id
              FROM v_nc_insumos
             WHERE nc_id = nc.id AND estado <> 'rechazado'
        LOOP
            INSERT INTO informe_recepcion_costos (
                informe_id, tipo, producto_id, descripcion, cantidad, unidad,
                precio_unitario, cobrable_cliente, hallazgo_id
            ) VALUES (
                v_informe.id, 'repuesto'::tipo_costo_recepcion_enum, mat.producto_id,
                COALESCE(mat.descripcion, 'Material'), COALESCE(mat.cantidad, 1), mat.unidad,
                0, true, v_hallazgo
            );
            v_costos := v_costos + 1;
        END LOOP;

        IF COALESCE(nc.horas_estimadas, 0) > 0 THEN
            INSERT INTO informe_recepcion_costos (
                informe_id, tipo, tarifa_hh_id, descripcion, cantidad, unidad,
                precio_unitario, cobrable_cliente, hallazgo_id
            ) VALUES (
                v_informe.id, 'mano_obra'::tipo_costo_recepcion_enum, v_tarifa_id,
                'Mano de obra' || COALESCE(' — ' || v_tarifa_nombre, '') ||
                    COALESCE(' (' || nc.grupo_trabajo || ')', ''),
                nc.horas_estimadas, 'HH', 0, true, v_hallazgo
            );
            v_costos := v_costos + 1;
        END IF;
    END LOOP;

    SELECT * INTO v_informe FROM informes_recepcion WHERE id = v_informe.id;

    RETURN jsonb_build_object(
        'ok', true, 'informe_id', v_informe.id, 'folio', v_informe.folio,
        'informe_nuevo', v_nuevo, 'hallazgos_creados', v_creados, 'ya_estaban', v_ya,
        'costos_creados', v_costos,
        'total_cobrable', v_informe.total_cobrable_cliente, 'total', v_informe.total
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_nc_informe_recobro(UUID, UUID[], UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_nc_informe_recobro(UUID, UUID[], UUID) TO authenticated;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_user UUID; v_nc UUID; v_ot UUID; v_prod UUID; v_res JSONB;
    v_n INT; v_backfill INT; v_stock NUMERIC;
BEGIN
    SELECT count(*) INTO v_backfill FROM ot_recursos_solicitados WHERE no_conformidad_id IS NOT NULL;
    RAISE NOTICE 'MIG254: % recursos existentes quedaron amarrados a su NC', v_backfill;

    SELECT id INTO v_user FROM usuarios_perfil WHERE rol='jefe_mantenimiento' LIMIT 1;
    SELECT id INTO v_prod FROM productos LIMIT 1;
    IF v_user IS NULL OR v_prod IS NULL THEN
        RAISE NOTICE 'MIG254: sin datos para smoke (ok)'; RETURN;
    END IF;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_user, 'role','authenticated')::text, true);

    -- (a) NC CON OT -> circuito de recursos
    SELECT id INTO v_nc FROM no_conformidades
     WHERE COALESCE(plan_ot_id, ot_id) IS NOT NULL LIMIT 1;
    IF v_nc IS NOT NULL THEN
        v_res := public.rpc_nc_insumo_agregar(v_nc, 2, v_prod, NULL, NULL, 'smoke MIG254', NULL);
        IF (v_res->>'fuente') <> 'recurso' THEN
            RAISE EXCEPTION 'FALLO — NC con OT debería ir al circuito de recursos, fue a %', v_res->>'fuente';
        END IF;
        SELECT count(*) INTO v_n FROM v_nc_insumos WHERE nc_id = v_nc;
        RAISE NOTICE 'MIG254 OK: NC con OT -> recurso; la lista unificada muestra % insumo(s), sin_stock=%',
            v_n, v_res->>'sin_stock';
        PERFORM public.rpc_nc_insumo_quitar((v_res->>'id')::uuid, 'recurso');
    END IF;

    -- (b) NC SIN OT -> material de la NC
    SELECT id INTO v_nc FROM no_conformidades
     WHERE COALESCE(plan_ot_id, ot_id) IS NULL LIMIT 1;
    IF v_nc IS NOT NULL THEN
        v_res := public.rpc_nc_insumo_agregar(v_nc, 1, NULL, 'Repuesto fuera de catálogo', 'un', NULL, NULL);
        IF (v_res->>'fuente') <> 'material' THEN
            RAISE EXCEPTION 'FALLO — NC sin OT debería quedar como material, fue a %', v_res->>'fuente';
        END IF;
        SELECT count(*) INTO v_n FROM v_nc_insumos WHERE nc_id = v_nc AND estado = 'aprobado';
        IF v_n = 0 THEN RAISE EXCEPTION 'FALLO — el material no aparece en la lista unificada'; END IF;
        RAISE NOTICE 'MIG254 OK: NC sin OT -> material, visible en la lista unificada';
        PERFORM public.rpc_nc_insumo_quitar((v_res->>'id')::uuid, 'material');
    END IF;

    -- (c) La búsqueda trae stock
    SELECT stock INTO v_stock FROM rpc_buscar_insumos(
        (SELECT left(nombre, 4) FROM productos WHERE id = v_prod), 5) LIMIT 1;
    RAISE NOTICE 'MIG254 OK: la búsqueda de insumos devuelve stock (ej: %)', COALESCE(v_stock, 0);

    RAISE EXCEPTION 'rollback-smoke';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'rollback-smoke' THEN RAISE NOTICE 'Smoke revertido (ok)';
    ELSE RAISE; END IF;
END $$;

NOTIFY pgrst, 'reload schema';
