-- ============================================================================
-- SICOM-ICEO | 187 — Combustible: salidas y traspasos vuelven a actualizar
--                    valor_total_stock (Fase 0 auditoría C5)
-- ----------------------------------------------------------------------------
-- Problema (validado en prod 2026-07-03):
--   MIG40 actualizaba combustible_estanques.valor_total_stock en cada salida.
--   MIG77/78 reescribieron rpc_registrar_salida_combustible_valorizada y el
--   UPDATE final quedó SOLO con stock_teorico_lt: el valor CLP del estanque no
--   baja nunca en salidas. El kardex (valor_stock_despues) sí queda correcto.
--   Lo mismo ocurre en rpc_registrar_traspaso_combustible (MIG76/93/99):
--   calcula v_val_ori_post / v_val_dst_post para el kardex pero no los escribe
--   en los estanques. Evidencia en prod: EST-1K valor almacenado 94.700 vs
--   55,93 según kardex; CAM-DEMO-1 con stock 0 y valor 16.000.000.
--
-- Fix (SOLO comportamiento futuro; la regularización histórica va aparte en
-- 188_recalculo_valor_stock_combustible.sql, que NO se aplica junto a esta):
--   1. rpc_registrar_salida_combustible_valorizada: el UPDATE del estanque
--      vuelve a escribir valor_total_stock = v_valor_post (stock_post × CPP,
--      mismo redondeo a 2 decimales del kardex). Cuerpo idéntico al vigente
--      (MIG78, verificado contra pg_get_functiondef en prod) + SET search_path.
--   2. rpc_registrar_traspaso_combustible: ambos UPDATE escriben el valor ya
--      calculado para el kardex (v_val_ori_post / v_val_dst_post).
--   3. rpc_registrar_despacho_combustible_con_sellos delega la salida en (1),
--      no toca estanques: no requiere cambio de lógica. Solo REVOKE anon.
--   4. REVOKE PUBLIC/anon en las tres (ya validaban auth internamente, pero el
--      EXECUTE default de PUBLIC permitía invocarlas a anónimos hasta el guard).
--
-- Consistencia garantizada dentro de la MISMA transacción y con la fila del
-- estanque bloqueada (FOR UPDATE ya existente): no hay carrera entre litros y
-- valor. Stock negativo sigue bloqueado por la validación de stock existente.
-- No genera movimientos adicionales ni altera históricos.
--
-- IDEMPOTENTE. Rollback: re-aplicar 78_combustible_kilometraje_externo_
-- obligatorio.sql (secciones 2 y GRANTs) y la versión previa del traspaso
-- (76/93/99) — restaura el comportamiento con bug.
-- ============================================================================

-- ── 1. Salida valorizada: restaurar actualización de valor ──────────────────
CREATE OR REPLACE FUNCTION public.rpc_registrar_salida_combustible_valorizada(
    p_estanque_id      UUID,
    p_litros           NUMERIC,
    p_destino_tipo     VARCHAR,
    p_motivo           TEXT,
    p_equipo_id        UUID    DEFAULT NULL,
    p_ot_id            UUID    DEFAULT NULL,
    p_ceco_id          UUID    DEFAULT NULL,
    p_faena_id         UUID    DEFAULT NULL,
    p_cliente_nombre   VARCHAR DEFAULT NULL,
    p_fecha_movimiento TIMESTAMPTZ DEFAULT NULL,
    p_observacion      TEXT    DEFAULT NULL,
    p_evidencia_url    TEXT    DEFAULT NULL,
    p_vehiculo_externo_id      UUID    DEFAULT NULL,
    p_foto_medidor_inicial_url TEXT    DEFAULT NULL,
    p_foto_medidor_final_url   TEXT    DEFAULT NULL,
    p_foto_patente_url         TEXT    DEFAULT NULL,
    p_firma_receptor_url       TEXT    DEFAULT NULL,
    p_nombre_receptor          VARCHAR DEFAULT NULL,
    p_rut_receptor             VARCHAR DEFAULT NULL,
    p_foto_patente_lat           NUMERIC DEFAULT NULL,
    p_foto_patente_lon           NUMERIC DEFAULT NULL,
    p_foto_patente_ts            TIMESTAMPTZ DEFAULT NULL,
    p_foto_medidor_inicial_lat   NUMERIC DEFAULT NULL,
    p_foto_medidor_inicial_lon   NUMERIC DEFAULT NULL,
    p_foto_medidor_inicial_ts    TIMESTAMPTZ DEFAULT NULL,
    p_foto_medidor_final_lat     NUMERIC DEFAULT NULL,
    p_foto_medidor_final_lon     NUMERIC DEFAULT NULL,
    p_foto_medidor_final_ts      TIMESTAMPTZ DEFAULT NULL,
    p_lectura_medidor_inicial_lt NUMERIC DEFAULT NULL,
    p_lectura_medidor_final_lt   NUMERIC DEFAULT NULL,
    p_kilometraje_vehiculo       NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id     UUID := auth.uid();
    v_rol         TEXT;
    v_estanque    combustible_estanques%ROWTYPE;
    v_stock_post  NUMERIC;
    v_cpp_actual  NUMERIC;
    v_valor_post  NUMERIC;
    v_costo_total NUMERIC;
    v_kardex_id   UUID;
    v_folio       VARCHAR;
    v_fecha       TIMESTAMPTZ;
    v_tipo_kardex VARCHAR(30);
    v_externo_ok  BOOLEAN;
    v_diff_med    NUMERIC;
    v_warn_med    TEXT;
    v_es_despacho_fisico BOOLEAN;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento','bodeguero') THEN
        RAISE EXCEPTION 'Rol % no autorizado para salida de combustible', v_rol;
    END IF;

    IF p_litros IS NULL OR p_litros <= 0 THEN
        RAISE EXCEPTION 'litros debe ser > 0';
    END IF;
    IF p_motivo IS NULL OR LENGTH(TRIM(p_motivo)) < 5 THEN
        RAISE EXCEPTION 'motivo es obligatorio (min 5 caracteres)';
    END IF;
    IF p_destino_tipo NOT IN ('equipo','ot','ceco','faena','consumo_interno','venta_externa') THEN
        RAISE EXCEPTION 'destino_tipo invalido: %', p_destino_tipo;
    END IF;

    v_es_despacho_fisico := p_destino_tipo <> 'consumo_interno';

    IF p_vehiculo_externo_id IS NOT NULL THEN
        SELECT activo INTO v_externo_ok
          FROM vehiculos_autorizados_externos WHERE id = p_vehiculo_externo_id;
        IF v_externo_ok IS NULL THEN
            RAISE EXCEPTION 'Vehiculo externo % no encontrado', p_vehiculo_externo_id;
        END IF;
        IF NOT v_externo_ok THEN
            RAISE EXCEPTION 'Vehiculo externo % NO esta autorizado (activo=false)', p_vehiculo_externo_id;
        END IF;
        IF p_kilometraje_vehiculo IS NULL OR p_kilometraje_vehiculo < 0 THEN
            RAISE EXCEPTION 'Kilometraje del vehiculo es OBLIGATORIO para despachos a vehiculo externo.';
        END IF;
    END IF;

    IF v_es_despacho_fisico THEN
        IF p_foto_patente_url IS NULL OR length(trim(p_foto_patente_url)) = 0 THEN
            RAISE EXCEPTION 'Foto de la patente del vehiculo es OBLIGATORIA para todo despacho.';
        END IF;
        IF p_foto_medidor_inicial_url IS NULL OR length(trim(p_foto_medidor_inicial_url)) = 0 THEN
            RAISE EXCEPTION 'Foto del medidor INICIAL es OBLIGATORIA para todo despacho.';
        END IF;
        IF p_foto_medidor_final_url IS NULL OR length(trim(p_foto_medidor_final_url)) = 0 THEN
            RAISE EXCEPTION 'Foto del medidor FINAL es OBLIGATORIA para todo despacho.';
        END IF;
        IF p_firma_receptor_url IS NULL OR length(trim(p_firma_receptor_url)) = 0 THEN
            RAISE EXCEPTION 'Firma del receptor es OBLIGATORIA para todo despacho.';
        END IF;
        IF p_nombre_receptor IS NULL OR length(trim(p_nombre_receptor)) < 3 THEN
            RAISE EXCEPTION 'Nombre del receptor es OBLIGATORIO (min 3 caracteres).';
        END IF;
        IF p_rut_receptor IS NULL OR length(trim(p_rut_receptor)) < 7 THEN
            RAISE EXCEPTION 'RUT del receptor es OBLIGATORIO.';
        END IF;
    END IF;

    IF p_destino_tipo = 'equipo' AND p_equipo_id IS NULL AND p_vehiculo_externo_id IS NULL THEN
        RAISE EXCEPTION 'destino=equipo requiere equipo_id O vehiculo_externo_id';
    END IF;
    IF p_destino_tipo = 'ot' AND p_ot_id IS NULL THEN
        RAISE EXCEPTION 'destino=ot requiere ot_id';
    END IF;
    IF p_destino_tipo = 'ceco' AND p_ceco_id IS NULL THEN
        RAISE EXCEPTION 'destino=ceco requiere ceco_id';
    END IF;
    IF p_destino_tipo = 'faena' AND p_faena_id IS NULL THEN
        RAISE EXCEPTION 'destino=faena requiere faena_id';
    END IF;

    v_fecha := COALESCE(p_fecha_movimiento, NOW());

    SELECT * INTO v_estanque FROM combustible_estanques WHERE id = p_estanque_id FOR UPDATE;
    IF v_estanque.id IS NULL THEN
        RAISE EXCEPTION 'Estanque % no existe', p_estanque_id;
    END IF;
    IF NOT v_estanque.activo THEN
        RAISE EXCEPTION 'Estanque % no esta activo', v_estanque.codigo;
    END IF;
    IF v_estanque.stock_teorico_lt < p_litros THEN
        RAISE EXCEPTION 'Stock insuficiente en estanque %: actual % lt, solicitado % lt',
            v_estanque.codigo, v_estanque.stock_teorico_lt, p_litros;
    END IF;

    v_cpp_actual  := COALESCE(v_estanque.costo_promedio_lt, 0);
    v_costo_total := ROUND((p_litros * v_cpp_actual)::numeric, 2);
    v_stock_post  := v_estanque.stock_teorico_lt - p_litros;
    v_valor_post  := ROUND((v_stock_post * v_cpp_actual)::numeric, 2);

    v_tipo_kardex := CASE
        WHEN p_vehiculo_externo_id IS NOT NULL THEN 'salida_externa'
        WHEN p_destino_tipo = 'equipo'         THEN 'salida_equipo'
        WHEN p_destino_tipo = 'venta_externa'  THEN 'salida_venta'
        ELSE                                        'salida_despacho'
    END;

    IF p_lectura_medidor_inicial_lt IS NOT NULL
       AND p_lectura_medidor_final_lt IS NOT NULL THEN
        v_diff_med := p_lectura_medidor_final_lt - p_lectura_medidor_inicial_lt;
        IF v_diff_med > 0 AND ABS(v_diff_med - p_litros) > GREATEST(p_litros * 0.03, 1) THEN
            v_warn_med := FORMAT('Diferencia medidor %.2f lt vs declarado %.2f lt', v_diff_med, p_litros);
        END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_generar_folio_salida_combustible') THEN
        SELECT fn_generar_folio_salida_combustible() INTO v_folio;
    ELSE
        v_folio := 'SCB-' || TO_CHAR(v_fecha, 'YYYYMMDD-HH24MISS');
    END IF;

    v_kardex_id := gen_random_uuid();
    INSERT INTO combustible_kardex_valorizado (
        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        equipo_id, ceco_id, cliente_nombre_manual,
        litros_entrada, litros_salida, costo_unitario_movimiento,
        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
        evidencia_url, observacion, created_by,
        vehiculo_externo_id, foto_medidor_inicial_url, foto_medidor_final_url,
        foto_patente_url, firma_receptor_url, nombre_receptor, rut_receptor,
        kilometraje_vehiculo
    ) VALUES (
        v_kardex_id, p_estanque_id, v_fecha, v_tipo_kardex, v_folio,
        p_equipo_id, p_ceco_id, p_cliente_nombre,
        0, p_litros, v_cpp_actual,
        v_stock_post, v_cpp_actual, v_valor_post,
        p_evidencia_url, p_observacion, v_user_id,
        p_vehiculo_externo_id, p_foto_medidor_inicial_url, p_foto_medidor_final_url,
        p_foto_patente_url, p_firma_receptor_url, p_nombre_receptor, p_rut_receptor,
        p_kilometraje_vehiculo
    );

    -- FIX MIG187: la columna de valor vuelve a moverse junto con los litros,
    -- en la misma transacción y con la fila bloqueada (FOR UPDATE de arriba).
    UPDATE combustible_estanques
       SET stock_teorico_lt  = v_stock_post,
           valor_total_stock = v_valor_post,
           updated_at        = NOW()
     WHERE id = p_estanque_id;

    RETURN jsonb_build_object(
        'success',         true,
        'kardex_id',       v_kardex_id,
        'folio',           v_folio,
        'estanque_codigo', v_estanque.codigo,
        'litros_salida',   p_litros,
        'destino_tipo',    p_destino_tipo,
        'cpp_vigente',     v_cpp_actual,
        'costo_total',     v_costo_total,
        'stock_anterior',  v_estanque.stock_teorico_lt,
        'stock_nuevo',     v_stock_post,
        'valor_stock_nuevo', v_valor_post,
        'tipo_movimiento_kardex', v_tipo_kardex,
        'warning_medidor', v_warn_med,
        'kilometraje_vehiculo', p_kilometraje_vehiculo
    );
END;
$$;

COMMENT ON FUNCTION public.rpc_registrar_salida_combustible_valorizada IS
'Salida valorizada al CPP vigente. NO modifica CPP. Actualiza stock_teorico_lt '
'Y valor_total_stock en la misma transacción (fix MIG187; el valor se había '
'perdido en MIG77/78). MIG40/77/78/187.';


-- ── 2. Traspaso: escribir el valor ya calculado en ambos estanques ──────────
CREATE OR REPLACE FUNCTION public.rpc_registrar_traspaso_combustible(
    p_estanque_origen_id uuid, p_estanque_destino_id uuid, p_litros numeric,
    p_foto_medidor_origen_inicial_url text, p_foto_medidor_origen_final_url text,
    p_foto_medidor_destino_inicial_url text, p_foto_medidor_destino_final_url text,
    p_foto_manguerado_url text,
    p_nombre_operador character varying, p_rut_operador character varying,
    p_firma_operador_url text, p_motivo text,
    p_lectura_medidor_origen_inicial numeric DEFAULT NULL,
    p_lectura_medidor_origen_final numeric DEFAULT NULL,
    p_lectura_medidor_destino_inicial numeric DEFAULT NULL,
    p_lectura_medidor_destino_final numeric DEFAULT NULL,
    p_observacion text DEFAULT NULL,
    p_lat numeric DEFAULT NULL, p_lng numeric DEFAULT NULL,
    p_accuracy numeric DEFAULT NULL, p_geolocation_status character varying DEFAULT NULL,
    p_fecha_traspaso timestamp with time zone DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id      UUID := auth.uid();
    v_rol          TEXT;
    v_origen       combustible_estanques%ROWTYPE;
    v_destino      combustible_estanques%ROWTYPE;
    v_folio        VARCHAR;
    v_fecha        TIMESTAMPTZ;
    v_traspaso_id  UUID;
    v_kardex_sal   UUID;
    v_kardex_ent   UUID;
    v_cpp_origen   NUMERIC;
    v_cpp_dest_old NUMERIC;
    v_cpp_dest_new NUMERIC;
    v_stk_ori_old  NUMERIC;
    v_stk_ori_new  NUMERIC;
    v_stk_dst_old  NUMERIC;
    v_stk_dst_new  NUMERIC;
    v_val_ori_post NUMERIC;
    v_val_dst_post NUMERIC;
    v_costo_total  NUMERIC;
    v_operador_pf  UUID;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','operador_abastecimiento','bodeguero') THEN
        RAISE EXCEPTION 'Rol % no autorizado para traspaso entre estanques', v_rol;
    END IF;

    IF p_litros IS NULL OR p_litros <= 0 THEN
        RAISE EXCEPTION 'litros debe ser > 0';
    END IF;
    IF p_estanque_origen_id = p_estanque_destino_id THEN
        RAISE EXCEPTION 'Estanque origen y destino no pueden ser el mismo';
    END IF;

    IF p_foto_medidor_origen_inicial_url IS NULL OR length(trim(p_foto_medidor_origen_inicial_url)) = 0 THEN
        RAISE EXCEPTION 'Foto medidor ORIGEN INICIAL es OBLIGATORIA.';
    END IF;
    IF p_foto_medidor_origen_final_url IS NULL OR length(trim(p_foto_medidor_origen_final_url)) = 0 THEN
        RAISE EXCEPTION 'Foto medidor ORIGEN FINAL es OBLIGATORIA.';
    END IF;
    IF p_foto_medidor_destino_inicial_url IS NULL OR length(trim(p_foto_medidor_destino_inicial_url)) = 0 THEN
        RAISE EXCEPTION 'Foto medidor DESTINO INICIAL es OBLIGATORIA.';
    END IF;
    IF p_foto_medidor_destino_final_url IS NULL OR length(trim(p_foto_medidor_destino_final_url)) = 0 THEN
        RAISE EXCEPTION 'Foto medidor DESTINO FINAL es OBLIGATORIA.';
    END IF;
    IF p_foto_manguerado_url IS NULL OR length(trim(p_foto_manguerado_url)) = 0 THEN
        RAISE EXCEPTION 'Foto del manguerado entre estanques es OBLIGATORIA.';
    END IF;
    IF p_nombre_operador IS NULL OR length(trim(p_nombre_operador)) < 3 THEN
        RAISE EXCEPTION 'Nombre del operador es OBLIGATORIO (min 3 caracteres).';
    END IF;
    IF p_rut_operador IS NULL OR length(trim(p_rut_operador)) < 7 THEN
        RAISE EXCEPTION 'RUT del operador es OBLIGATORIO.';
    END IF;
    IF p_firma_operador_url IS NULL OR length(trim(p_firma_operador_url)) = 0 THEN
        RAISE EXCEPTION 'Firma del operador es OBLIGATORIA.';
    END IF;
    IF p_motivo IS NULL OR length(trim(p_motivo)) < 5 THEN
        RAISE EXCEPTION 'Motivo es OBLIGATORIO (min 5 caracteres).';
    END IF;

    v_fecha := COALESCE(p_fecha_traspaso, NOW());

    IF p_estanque_origen_id < p_estanque_destino_id THEN
        SELECT * INTO v_origen  FROM combustible_estanques WHERE id = p_estanque_origen_id  FOR UPDATE;
        SELECT * INTO v_destino FROM combustible_estanques WHERE id = p_estanque_destino_id FOR UPDATE;
    ELSE
        SELECT * INTO v_destino FROM combustible_estanques WHERE id = p_estanque_destino_id FOR UPDATE;
        SELECT * INTO v_origen  FROM combustible_estanques WHERE id = p_estanque_origen_id  FOR UPDATE;
    END IF;

    IF v_origen.id IS NULL THEN RAISE EXCEPTION 'Estanque origen no existe'; END IF;
    IF v_destino.id IS NULL THEN RAISE EXCEPTION 'Estanque destino no existe'; END IF;
    IF NOT v_origen.activo THEN RAISE EXCEPTION 'Estanque origen % no esta activo', v_origen.codigo; END IF;
    IF NOT v_destino.activo THEN RAISE EXCEPTION 'Estanque destino % no esta activo', v_destino.codigo; END IF;

    IF v_origen.stock_teorico_lt < p_litros THEN
        RAISE EXCEPTION 'Stock insuficiente en origen %: actual % lt, solicitado % lt',
            v_origen.codigo, v_origen.stock_teorico_lt, p_litros;
    END IF;

    IF (v_destino.stock_teorico_lt + p_litros) > v_destino.capacidad_lt THEN
        RAISE EXCEPTION 'Capacidad insuficiente en destino %: stock % + traspaso % > capacidad % lt',
            v_destino.codigo, v_destino.stock_teorico_lt, p_litros, v_destino.capacidad_lt;
    END IF;

    v_cpp_origen   := COALESCE(v_origen.costo_promedio_lt, 0);
    v_cpp_dest_old := COALESCE(v_destino.costo_promedio_lt, 0);
    v_stk_ori_old  := v_origen.stock_teorico_lt;
    v_stk_dst_old  := v_destino.stock_teorico_lt;

    v_stk_ori_new  := v_stk_ori_old - p_litros;
    v_stk_dst_new  := v_stk_dst_old + p_litros;
    v_costo_total  := ROUND((p_litros * v_cpp_origen)::numeric, 0);

    IF v_stk_dst_new > 0 THEN
        v_cpp_dest_new := ROUND(
            (((v_stk_dst_old * v_cpp_dest_old) + (p_litros * v_cpp_origen))::numeric / v_stk_dst_new)::numeric
        , 4);
    ELSE
        v_cpp_dest_new := v_cpp_origen;
    END IF;

    v_val_ori_post := ROUND((v_stk_ori_new * v_cpp_origen)::numeric, 2);
    v_val_dst_post := ROUND((v_stk_dst_new * v_cpp_dest_new)::numeric, 2);

    v_folio := 'TRA-' || TO_CHAR(v_fecha, 'YYYYMMDD') || '-' || TO_CHAR(clock_timestamp(), 'HH24MISSMS') || '-' || upper(substr(md5(random()::text), 1, 3));

    SELECT id INTO v_operador_pf FROM usuarios_perfil WHERE id = v_user_id LIMIT 1;

    v_traspaso_id := gen_random_uuid();
    INSERT INTO combustible_traspasos (
        id, folio, estanque_origen_id, estanque_destino_id, litros,
        cpp_origen_snapshot, costo_total_traspaso,
        lectura_medidor_origen_inicial, lectura_medidor_origen_final,
        lectura_medidor_destino_inicial, lectura_medidor_destino_final,
        foto_medidor_origen_inicial_url, foto_medidor_origen_final_url,
        foto_medidor_destino_inicial_url, foto_medidor_destino_final_url,
        foto_manguerado_url,
        nombre_operador, rut_operador, firma_operador_url,
        motivo, observacion,
        stock_origen_anterior, stock_origen_nuevo,
        stock_destino_anterior, stock_destino_nuevo,
        cpp_destino_anterior, cpp_destino_nuevo,
        lat, lng, accuracy, geolocation_status,
        fecha_traspaso, operador_id, created_by
    ) VALUES (
        v_traspaso_id, v_folio, p_estanque_origen_id, p_estanque_destino_id, p_litros,
        v_cpp_origen, v_costo_total,
        p_lectura_medidor_origen_inicial,  p_lectura_medidor_origen_final,
        p_lectura_medidor_destino_inicial, p_lectura_medidor_destino_final,
        p_foto_medidor_origen_inicial_url,  p_foto_medidor_origen_final_url,
        p_foto_medidor_destino_inicial_url, p_foto_medidor_destino_final_url,
        p_foto_manguerado_url,
        TRIM(p_nombre_operador), TRIM(p_rut_operador), p_firma_operador_url,
        TRIM(p_motivo), p_observacion,
        v_stk_ori_old, v_stk_ori_new,
        v_stk_dst_old, v_stk_dst_new,
        v_cpp_dest_old, v_cpp_dest_new,
        p_lat, p_lng, p_accuracy, p_geolocation_status,
        v_fecha, v_operador_pf, v_user_id
    );

    v_kardex_sal := gen_random_uuid();
    INSERT INTO combustible_kardex_valorizado (
        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        litros_entrada, litros_salida, costo_unitario_movimiento,
        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
        observacion, created_by, traspaso_id
    ) VALUES (
        v_kardex_sal, p_estanque_origen_id, v_fecha, 'traspaso_salida', v_folio || '-S',
        0, p_litros, v_cpp_origen,
        v_stk_ori_new, v_cpp_origen, v_val_ori_post,
        'Traspaso a ' || v_destino.codigo || ' (' || COALESCE(p_motivo,'') || ')',
        v_user_id, v_traspaso_id
    );

    v_kardex_ent := gen_random_uuid();
    INSERT INTO combustible_kardex_valorizado (
        id, estanque_id, fecha_movimiento, tipo_movimiento, folio_movimiento,
        litros_entrada, litros_salida, costo_unitario_movimiento,
        stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues,
        observacion, created_by, traspaso_id
    ) VALUES (
        v_kardex_ent, p_estanque_destino_id, v_fecha, 'traspaso_entrada', v_folio || '-E',
        p_litros, 0, v_cpp_origen,
        v_stk_dst_new, v_cpp_dest_new, v_val_dst_post,
        'Traspaso desde ' || v_origen.codigo || ' (' || COALESCE(p_motivo,'') || ')',
        v_user_id, v_traspaso_id
    );

    UPDATE combustible_traspasos
       SET kardex_salida_id  = v_kardex_sal,
           kardex_entrada_id = v_kardex_ent
     WHERE id = v_traspaso_id;

    -- FIX MIG187: los estanques reciben también el valor calculado (antes solo
    -- quedaba en el kardex y la columna divergía).
    UPDATE combustible_estanques
       SET stock_teorico_lt  = v_stk_ori_new,
           valor_total_stock = v_val_ori_post,
           updated_at        = NOW()
     WHERE id = p_estanque_origen_id;

    UPDATE combustible_estanques
       SET stock_teorico_lt   = v_stk_dst_new,
           costo_promedio_lt  = v_cpp_dest_new,
           valor_total_stock  = v_val_dst_post,
           updated_at         = NOW()
     WHERE id = p_estanque_destino_id;

    RETURN jsonb_build_object(
        'success',            true,
        'traspaso_id',        v_traspaso_id,
        'folio',              v_folio,
        'origen_codigo',      v_origen.codigo,
        'destino_codigo',     v_destino.codigo,
        'litros',             p_litros,
        'cpp_origen',         v_cpp_origen,
        'cpp_destino_antes',  v_cpp_dest_old,
        'cpp_destino_despues', v_cpp_dest_new,
        'stock_origen_antes', v_stk_ori_old,
        'stock_origen_despues', v_stk_ori_new,
        'stock_destino_antes', v_stk_dst_old,
        'stock_destino_despues', v_stk_dst_new,
        'valor_origen_despues',  v_val_ori_post,
        'valor_destino_despues', v_val_dst_post,
        'costo_total',        v_costo_total,
        'kardex_salida_id',   v_kardex_sal,
        'kardex_entrada_id',  v_kardex_ent
    );
END;
$$;

COMMENT ON FUNCTION public.rpc_registrar_traspaso_combustible IS
'Traspaso valorizado entre estanques (CPP móvil en destino). Desde MIG187 '
'actualiza también valor_total_stock de ambos estanques. MIG76/93/99/187.';


-- ── 3. Cerrar EXECUTE de anon en el flujo de salidas ────────────────────────
REVOKE ALL ON FUNCTION public.rpc_registrar_salida_combustible_valorizada(
    UUID, NUMERIC, VARCHAR, TEXT, UUID, UUID, UUID, UUID, VARCHAR, TIMESTAMPTZ,
    TEXT, TEXT, UUID, TEXT, TEXT, TEXT, TEXT, VARCHAR, VARCHAR,
    NUMERIC, NUMERIC, TIMESTAMPTZ, NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC, TIMESTAMPTZ, NUMERIC, NUMERIC, NUMERIC
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_registrar_salida_combustible_valorizada(
    UUID, NUMERIC, VARCHAR, TEXT, UUID, UUID, UUID, UUID, VARCHAR, TIMESTAMPTZ,
    TEXT, TEXT, UUID, TEXT, TEXT, TEXT, TEXT, VARCHAR, VARCHAR,
    NUMERIC, NUMERIC, TIMESTAMPTZ, NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC, TIMESTAMPTZ, NUMERIC, NUMERIC, NUMERIC
) TO authenticated;

REVOKE ALL ON FUNCTION public.rpc_registrar_traspaso_combustible(
    UUID, UUID, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, VARCHAR, VARCHAR, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, NUMERIC, NUMERIC, NUMERIC, VARCHAR, TIMESTAMPTZ
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_registrar_traspaso_combustible(
    UUID, UUID, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, VARCHAR, VARCHAR, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, NUMERIC, NUMERIC, NUMERIC, VARCHAR, TIMESTAMPTZ
) TO authenticated;

-- Despacho con sellos delega en la salida (no toca estanques): solo grants.
REVOKE ALL ON FUNCTION public.rpc_registrar_despacho_combustible_con_sellos(
    UUID, NUMERIC, VARCHAR, VARCHAR, VARCHAR, TEXT, UUID, UUID, UUID, UUID,
    VARCHAR, VARCHAR, VARCHAR, TEXT, TEXT, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, VARCHAR, TIMESTAMPTZ, TEXT, TEXT,
    UUID, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_registrar_despacho_combustible_con_sellos(
    UUID, NUMERIC, VARCHAR, VARCHAR, VARCHAR, TEXT, UUID, UUID, UUID, UUID,
    VARCHAR, VARCHAR, VARCHAR, TEXT, TEXT, TEXT, TEXT, TEXT,
    NUMERIC, NUMERIC, NUMERIC, VARCHAR, TIMESTAMPTZ, TEXT, TEXT,
    UUID, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC
) TO authenticated;


-- ── 4. Verificación (sin tocar datos) ───────────────────────────────────────
DO $$
DECLARE v_def TEXT;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_registrar_salida_combustible_valorizada';
    IF v_def NOT LIKE '%valor_total_stock = v_valor_post%' THEN
        RAISE EXCEPTION 'FALLO: la salida sigue sin actualizar valor_total_stock';
    END IF;

    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_registrar_traspaso_combustible';
    IF v_def NOT LIKE '%valor_total_stock = v_val_ori_post%'
       OR v_def NOT LIKE '%valor_total_stock  = v_val_dst_post%' THEN
        RAISE EXCEPTION 'FALLO: el traspaso sigue sin actualizar valor_total_stock';
    END IF;

    IF has_function_privilege('anon',
        (SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname='rpc_registrar_salida_combustible_valorizada'),
        'EXECUTE') THEN
        RAISE EXCEPTION 'FALLO: anon aún puede ejecutar la salida de combustible';
    END IF;
    RAISE NOTICE 'MIG187 OK: salida y traspaso actualizan valor; anon sin EXECUTE.';
END $$;

SELECT 'MIG187 aplicada' AS resultado;
