-- ============================================================================
-- 437_una_patente_externa_no_carga_dos_veces_el_mismo_dia.sql
-- ----------------------------------------------------------------------------
-- PROBLEMA REAL (reclamo de cliente, agosto 2026):
--   El despacho de combustible a vehiculos EXTERNOS no tenia ningun control de
--   repeticion. La misma patente se podia cargar N veces el mismo dia y cada
--   carga se facturaba. Casos encontrados en el kardex:
--     VRYT-77 (MYG)   11-ago-2026  11:40 -> 44,6 lt  |  12:16 -> 44,6 lt
--     HSFD-76 (MYG)   22-jun-2026  09:13 -> 45,6 lt  |  09:19 -> 34,8 lt
--   El primero es un duplicado exacto: se facturo dos veces al cliente.
--
-- REGLA QUE SE IMPLEMENTA:
--   Una patente externa recibe UN despacho por dia calendario (America/Santiago).
--   El segundo queda bloqueado, con el detalle del primero en el mensaje.
--
-- ESCAPE AUDITABLE:
--   Si la segunda carga es legitima, solo jefatura (administrador, supervisor,
--   subgerente_operaciones) puede autorizarla, declarando el motivo. Queda
--   grabado quien autorizo y por que, para que la facturacion lo pueda revisar.
--   El bodeguero / operador de abastecimiento NO puede levantar el bloqueo.
--
-- DONDE SE PONE EL CANDADO:
--   En un trigger BEFORE INSERT sobre combustible_kardex_valorizado, no solo en
--   el RPC: asi cualquier camino presente o futuro que inserte una salida a
--   externo queda cubierto. El RPC valida ademas el rol y el motivo, para que
--   el mensaje de error sea util y la autorizacion no se pueda falsear desde
--   el cliente.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $mig$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='combustible_kardex_valorizado') THEN
        RAISE EXCEPTION 'STOP - falta combustible_kardex_valorizado (MIG57).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_salida_combustible_valorizada') THEN
        RAISE EXCEPTION 'STOP - falta rpc_registrar_salida_combustible_valorizada (MIG78).';
    END IF;
END $mig$;


-- ============================================================================
-- 1. Columnas de la autorizacion
-- ============================================================================
ALTER TABLE combustible_kardex_valorizado
    ADD COLUMN IF NOT EXISTS recarga_dia_autorizada     BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS recarga_dia_motivo         TEXT,
    ADD COLUMN IF NOT EXISTS recarga_dia_autorizada_por UUID REFERENCES auth.users(id);

COMMENT ON COLUMN combustible_kardex_valorizado.recarga_dia_autorizada IS
    'true = jefatura autorizo expresamente una segunda carga a la misma patente externa el mismo dia (MIG437).';
COMMENT ON COLUMN combustible_kardex_valorizado.recarga_dia_motivo IS
    'Motivo declarado para la segunda carga del dia. Obligatorio si recarga_dia_autorizada (MIG437).';
COMMENT ON COLUMN combustible_kardex_valorizado.recarga_dia_autorizada_por IS
    'Usuario de jefatura que autorizo la segunda carga del dia (MIG437).';

-- Las filas historicas quedan como estan: el trigger solo mira inserts nuevos.
CREATE INDEX IF NOT EXISTS idx_kardex_externo_fecha
    ON combustible_kardex_valorizado (vehiculo_externo_id, fecha_movimiento)
    WHERE vehiculo_externo_id IS NOT NULL;


-- ============================================================================
-- 2. Consulta reutilizable: que se le cargo hoy a esta patente
-- ----------------------------------------------------------------------------
-- La usan el trigger (para armar el mensaje), el RPC de consulta y el
-- formulario, para que los tres digan exactamente lo mismo.
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_cargas_externo_del_dia(
    p_vehiculo_externo_id UUID,
    p_fecha_movimiento    TIMESTAMPTZ DEFAULT NULL,
    p_excluir_kardex_id   UUID DEFAULT NULL
)
RETURNS TABLE (
    kardex_id      UUID,
    folio          VARCHAR,
    hora           TEXT,
    litros         NUMERIC,
    registrado_por TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
    SELECT k.id,
           k.folio_movimiento,
           TO_CHAR(k.fecha_movimiento AT TIME ZONE 'America/Santiago', 'HH24:MI'),
           k.litros_salida,
           COALESCE(up.nombre_completo, 'usuario desconocido')
      FROM combustible_kardex_valorizado k
      LEFT JOIN usuarios_perfil up ON up.id = k.created_by
     WHERE k.vehiculo_externo_id = p_vehiculo_externo_id
       AND COALESCE(k.litros_salida, 0) > 0
       AND (k.fecha_movimiento AT TIME ZONE 'America/Santiago')::date
         = (COALESCE(p_fecha_movimiento, NOW()) AT TIME ZONE 'America/Santiago')::date
       AND (p_excluir_kardex_id IS NULL OR k.id <> p_excluir_kardex_id)
     ORDER BY k.fecha_movimiento;
$fn$;

COMMENT ON FUNCTION fn_cargas_externo_del_dia IS
    'Despachos ya registrados a una patente externa en el dia calendario chileno de la fecha dada (MIG437).';


-- ============================================================================
-- 3. El candado: trigger BEFORE INSERT
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_bloquear_recarga_externa_mismo_dia()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
    v_previas TEXT;
    v_n       INT;
BEGIN
    -- Solo aplica a salidas fisicas a una patente externa.
    IF NEW.vehiculo_externo_id IS NULL OR COALESCE(NEW.litros_salida, 0) <= 0 THEN
        RETURN NEW;
    END IF;

    SELECT COUNT(*),
           STRING_AGG(FORMAT('%s a las %s (%s lt, registro de %s)',
                             c.folio, c.hora, c.litros, c.registrado_por), ' | ')
      INTO v_n, v_previas
      FROM fn_cargas_externo_del_dia(NEW.vehiculo_externo_id, NEW.fecha_movimiento, NEW.id) c;

    IF COALESCE(v_n, 0) = 0 THEN
        -- Primera carga del dia: la marca de autorizacion no tiene sentido aqui.
        NEW.recarga_dia_autorizada     := false;
        NEW.recarga_dia_motivo         := NULL;
        NEW.recarga_dia_autorizada_por := NULL;
        RETURN NEW;
    END IF;

    IF NOT COALESCE(NEW.recarga_dia_autorizada, false) THEN
        RAISE EXCEPTION
            'Esta patente YA recibio combustible hoy: %. Un segundo despacho el mismo dia necesita autorizacion de jefatura con motivo.',
            v_previas
            USING HINT = 'Si la carga anterior fue un error, corrigela; si esta segunda carga es real, pide a un administrador o supervisor que la autorice.';
    END IF;

    IF NEW.recarga_dia_motivo IS NULL OR LENGTH(TRIM(NEW.recarga_dia_motivo)) < 10 THEN
        RAISE EXCEPTION 'Para autorizar la segunda carga del dia hay que declarar el motivo (minimo 10 caracteres).';
    END IF;

    RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_bloquear_recarga_externa_mismo_dia ON combustible_kardex_valorizado;
CREATE TRIGGER trg_bloquear_recarga_externa_mismo_dia
    BEFORE INSERT ON combustible_kardex_valorizado
    FOR EACH ROW EXECUTE FUNCTION fn_bloquear_recarga_externa_mismo_dia();


-- ============================================================================
-- 4. Lo que consulta el formulario antes de dejar guardar
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_cargas_externo_del_dia(
    p_vehiculo_externo_id UUID,
    p_fecha               DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
    v_ref   TIMESTAMPTZ;
    v_rows  JSONB;
    v_total NUMERIC;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF p_vehiculo_externo_id IS NULL THEN
        RETURN jsonb_build_object('cargas', '[]'::jsonb, 'n', 0, 'litros_total', 0,
                                  'puede_autorizar', false);
    END IF;

    -- Mediodia local: cae dentro del dia pedido sin importar el huso.
    v_ref := (COALESCE(p_fecha, (NOW() AT TIME ZONE 'America/Santiago')::date)::timestamp
              + INTERVAL '12 hours') AT TIME ZONE 'America/Santiago';

    SELECT COALESCE(JSONB_AGG(JSONB_BUILD_OBJECT(
               'kardex_id',      c.kardex_id,
               'folio',          c.folio,
               'hora',           c.hora,
               'litros',         c.litros,
               'registrado_por', c.registrado_por) ORDER BY c.hora), '[]'::jsonb),
           COALESCE(SUM(c.litros), 0)
      INTO v_rows, v_total
      FROM fn_cargas_externo_del_dia(p_vehiculo_externo_id, v_ref) c;

    RETURN jsonb_build_object(
        'cargas',          v_rows,
        'n',               JSONB_ARRAY_LENGTH(v_rows),
        'litros_total',    v_total,
        'puede_autorizar', fn_user_rol() IN ('administrador','supervisor','subgerente_operaciones')
    );
END;
$fn$;

REVOKE ALL ON FUNCTION rpc_cargas_externo_del_dia(UUID, DATE) FROM PUBLIC;
REVOKE ALL ON FUNCTION rpc_cargas_externo_del_dia(UUID, DATE) FROM anon;
GRANT EXECUTE ON FUNCTION rpc_cargas_externo_del_dia(UUID, DATE) TO authenticated;

COMMENT ON FUNCTION rpc_cargas_externo_del_dia IS
    'Cargas ya hechas hoy a una patente externa + si el usuario puede autorizar una segunda (MIG437).';


-- ============================================================================
-- 5. El RPC de salida acepta (y valida) la autorizacion
-- ----------------------------------------------------------------------------
-- Se reemplaza la version de 31 parametros por una de 33. Se dropea primero
-- para no dejar un overload ambiguo: PostgREST elige por nombre de argumento y
-- dos versiones conviviendo hacen fallar la llamada.
-- ============================================================================
DROP FUNCTION IF EXISTS rpc_registrar_salida_combustible_valorizada(
    UUID, NUMERIC, VARCHAR, TEXT,
    UUID, UUID, UUID, UUID, VARCHAR,
    TIMESTAMPTZ, TEXT, TEXT,
    UUID, TEXT, TEXT, TEXT, TEXT, VARCHAR, VARCHAR,
    NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC, NUMERIC
);

CREATE OR REPLACE FUNCTION rpc_registrar_salida_combustible_valorizada(
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
    p_vehiculo_externo_id      UUID DEFAULT NULL,
    p_foto_medidor_inicial_url TEXT DEFAULT NULL,
    p_foto_medidor_final_url   TEXT DEFAULT NULL,
    p_foto_patente_url         TEXT DEFAULT NULL,
    p_firma_receptor_url       TEXT DEFAULT NULL,
    p_nombre_receptor          VARCHAR DEFAULT NULL,
    p_rut_receptor             VARCHAR DEFAULT NULL,
    p_foto_patente_lat         NUMERIC DEFAULT NULL,
    p_foto_patente_lon         NUMERIC DEFAULT NULL,
    p_foto_patente_ts          TIMESTAMPTZ DEFAULT NULL,
    p_foto_medidor_inicial_lat NUMERIC DEFAULT NULL,
    p_foto_medidor_inicial_lon NUMERIC DEFAULT NULL,
    p_foto_medidor_inicial_ts  TIMESTAMPTZ DEFAULT NULL,
    p_foto_medidor_final_lat   NUMERIC DEFAULT NULL,
    p_foto_medidor_final_lon   NUMERIC DEFAULT NULL,
    p_foto_medidor_final_ts    TIMESTAMPTZ DEFAULT NULL,
    p_lectura_medidor_inicial_lt NUMERIC DEFAULT NULL,
    p_lectura_medidor_final_lt   NUMERIC DEFAULT NULL,
    p_kilometraje_vehiculo       NUMERIC DEFAULT NULL,
    -- MIG437: segunda carga del dia a la misma patente externa
    p_autorizar_recarga_dia      BOOLEAN DEFAULT false,
    p_motivo_recarga_dia         TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
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
    -- MIG437
    v_cargas_previas INT := 0;
    v_detalle_previo TEXT;
    v_autoriza       BOOLEAN := false;
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
    v_fecha := COALESCE(p_fecha_movimiento, NOW());

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

        -- MIG437: una patente externa = una carga por dia. El trigger es el
        -- candado; aca se resuelve si hay autorizacion valida y se dan los
        -- mensajes que el operador puede entender.
        SELECT COUNT(*),
               STRING_AGG(FORMAT('%s a las %s (%s lt, registro de %s)',
                                 c.folio, c.hora, c.litros, c.registrado_por), ' | ')
          INTO v_cargas_previas, v_detalle_previo
          FROM fn_cargas_externo_del_dia(p_vehiculo_externo_id, v_fecha) c;

        IF v_cargas_previas > 0 THEN
            IF NOT COALESCE(p_autorizar_recarga_dia, false) THEN
                RAISE EXCEPTION
                    'Esta patente YA recibio combustible hoy: %. No se puede cargar dos veces el mismo dia.',
                    v_detalle_previo
                    USING HINT = 'Si la carga anterior fue un error, corrigela antes de repetir. Si esta segunda carga es real, un administrador o supervisor debe autorizarla indicando el motivo.';
            END IF;
            IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones') THEN
                RAISE EXCEPTION
                    'Tu rol (%) no puede autorizar una segunda carga del dia a la misma patente. Esta patente ya recibio: %',
                    v_rol, v_detalle_previo;
            END IF;
            IF p_motivo_recarga_dia IS NULL OR LENGTH(TRIM(p_motivo_recarga_dia)) < 10 THEN
                RAISE EXCEPTION 'Para autorizar la segunda carga del dia hay que declarar el motivo (minimo 10 caracteres).';
            END IF;
            v_autoriza := true;
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
        kilometraje_vehiculo,
        recarga_dia_autorizada, recarga_dia_motivo, recarga_dia_autorizada_por
    ) VALUES (
        v_kardex_id, p_estanque_id, v_fecha, v_tipo_kardex, v_folio,
        p_equipo_id, p_ceco_id, p_cliente_nombre,
        0, p_litros, v_cpp_actual,
        v_stock_post, v_cpp_actual, v_valor_post,
        p_evidencia_url, p_observacion, v_user_id,
        p_vehiculo_externo_id, p_foto_medidor_inicial_url, p_foto_medidor_final_url,
        p_foto_patente_url, p_firma_receptor_url, p_nombre_receptor, p_rut_receptor,
        p_kilometraje_vehiculo,
        v_autoriza,
        CASE WHEN v_autoriza THEN TRIM(p_motivo_recarga_dia) END,
        CASE WHEN v_autoriza THEN v_user_id END
    );

    -- FIX MIG187: la columna de valor vuelve a moverse junto con los litros,
    -- en la misma transaccion y con la fila bloqueada (FOR UPDATE de arriba).
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
        'kilometraje_vehiculo', p_kilometraje_vehiculo,
        'recarga_dia_autorizada', v_autoriza
    );
END;
$fn$;

REVOKE ALL ON FUNCTION rpc_registrar_salida_combustible_valorizada(
    UUID, NUMERIC, VARCHAR, TEXT, UUID, UUID, UUID, UUID, VARCHAR,
    TIMESTAMPTZ, TEXT, TEXT, UUID, TEXT, TEXT, TEXT, TEXT, VARCHAR, VARCHAR,
    NUMERIC, NUMERIC, TIMESTAMPTZ, NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC, TIMESTAMPTZ, NUMERIC, NUMERIC, NUMERIC,
    BOOLEAN, TEXT
) FROM PUBLIC;
REVOKE ALL ON FUNCTION rpc_registrar_salida_combustible_valorizada(
    UUID, NUMERIC, VARCHAR, TEXT, UUID, UUID, UUID, UUID, VARCHAR,
    TIMESTAMPTZ, TEXT, TEXT, UUID, TEXT, TEXT, TEXT, TEXT, VARCHAR, VARCHAR,
    NUMERIC, NUMERIC, TIMESTAMPTZ, NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC, TIMESTAMPTZ, NUMERIC, NUMERIC, NUMERIC,
    BOOLEAN, TEXT
) FROM anon;
GRANT EXECUTE ON FUNCTION rpc_registrar_salida_combustible_valorizada(
    UUID, NUMERIC, VARCHAR, TEXT, UUID, UUID, UUID, UUID, VARCHAR,
    TIMESTAMPTZ, TEXT, TEXT, UUID, TEXT, TEXT, TEXT, TEXT, VARCHAR, VARCHAR,
    NUMERIC, NUMERIC, TIMESTAMPTZ, NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC, TIMESTAMPTZ, NUMERIC, NUMERIC, NUMERIC,
    BOOLEAN, TEXT
) TO authenticated;

COMMENT ON FUNCTION rpc_registrar_salida_combustible_valorizada IS
    'Salida valorizada de combustible. MIG437: una patente externa no puede recibir dos cargas el mismo dia salvo autorizacion de jefatura con motivo.';


-- ============================================================================
-- 6. Validacion
-- ============================================================================
DO $chk$
DECLARE
    v_sigs INT;
    v_trg  INT;
BEGIN
    SELECT COUNT(*) INTO v_sigs
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_registrar_salida_combustible_valorizada';
    IF v_sigs <> 1 THEN
        RAISE EXCEPTION 'STOP - quedaron % versiones del RPC de salida (debe haber 1)', v_sigs;
    END IF;

    SELECT COUNT(*) INTO v_trg
      FROM pg_trigger
     WHERE tgname = 'trg_bloquear_recarga_externa_mismo_dia' AND NOT tgisinternal;
    IF v_trg <> 1 THEN
        RAISE EXCEPTION 'STOP - el trigger de bloqueo no quedo instalado';
    END IF;

    RAISE NOTICE 'MIG437 OK: candado de recarga externa por dia instalado.';
END $chk$;

SELECT 'MIG437'                                        AS migracion,
       (SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public'
           AND p.proname IN ('fn_cargas_externo_del_dia','rpc_cargas_externo_del_dia',
                             'fn_bloquear_recarga_externa_mismo_dia'))  AS funciones_nuevas,
       (SELECT COUNT(*) FROM information_schema.columns
         WHERE table_name='combustible_kardex_valorizado'
           AND column_name LIKE 'recarga_dia%')         AS columnas_nuevas;
