-- ============================================================================
-- SICOM-ICEO | 200 — Link del informe de fiabilidad abierto por token secreto
-- ============================================================================
-- Pedido Manuel (2026-07-07): el link del informe de fiabilidad que va por
-- correo debe poder abrirlo cualquier destinatario SIN iniciar sesión.
--
-- MIG186 (hallazgo C3 de la auditoría) cerró la RPC a authenticated porque
-- exponía VIN/motor/clientes de toda la flota a internet. Decisión Manuel
-- 2026-07-07 (opción recomendada): NO volver a público abierto — el correo
-- lleva un TOKEN secreto en la URL (?t=...). Quien tiene el link ve el
-- reporte completo; sin token sigue exigiendo sesión. Revocable.
--
--   1. Tabla reporte_tokens (sin grants directos; RLS sin políticas — solo
--      se llega por RPCs SECURITY DEFINER). Se guarda el token en claro
--      (desviación consciente del diseño hash de la auditoría: quien envía
--      el correo necesita el valor para armar el link; revocación = activo
--      false o expira_at).
--   2. fn_reporte_fiabilidad_publico(p_ini, p_fin, p_token): el guard de
--      MIG186 acepta ADEMÁS un token vigente. GRANT también a anon (sin
--      token válido el guard corta igual — fail-closed).
--   3. fn_reporte_fiabilidad_link_token(): entrega el token vigente a
--      usuarios internos (para que el correo/los scripts armen el link).
--   4. Se siembra un token de 48 hex chars (192 bits) si no existe.
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. Tabla de tokens ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS reporte_tokens (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporte      TEXT NOT NULL,
    token        TEXT NOT NULL UNIQUE,
    activo       BOOLEAN NOT NULL DEFAULT true,
    expira_at    TIMESTAMPTZ,
    created_at   TIMESTAMPTZ DEFAULT now(),
    created_by   UUID REFERENCES usuarios_perfil(id),
    last_used_at TIMESTAMPTZ,
    usos         BIGINT NOT NULL DEFAULT 0
);
COMMENT ON TABLE reporte_tokens IS
    'Tokens de acceso por link a reportes (fiabilidad). Sin grants: solo RPCs SECURITY DEFINER. Revocar = activo=false. MIG200.';
ALTER TABLE reporte_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON reporte_tokens FROM PUBLIC, anon, authenticated;

-- Sembrar token vigente del reporte de fiabilidad (192 bits aleatorios)
INSERT INTO reporte_tokens (reporte, token)
SELECT 'fiabilidad', encode(gen_random_bytes(24), 'hex')
WHERE NOT EXISTS (
    SELECT 1 FROM reporte_tokens
     WHERE reporte = 'fiabilidad' AND activo
       AND (expira_at IS NULL OR expira_at > NOW()));


-- ── 2. RPC del reporte: sesión O token vigente ───────────────────────────────
DROP FUNCTION IF EXISTS public.fn_reporte_fiabilidad_publico(DATE, DATE);

CREATE OR REPLACE FUNCTION public.fn_reporte_fiabilidad_publico(
    p_ini DATE DEFAULT date_trunc('month', CURRENT_DATE)::date,
    p_fin DATE DEFAULT CURRENT_DATE,
    p_token TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_out JSONB;
    v_token_ok BOOLEAN := false;
BEGIN
    -- Guard MIG186 + MIG200: sesión con perfil, conexión admin directa
    -- (scripts de correo / cron como postgres), o token vigente del link.
    IF p_token IS NOT NULL THEN
        SELECT EXISTS (
            SELECT 1 FROM reporte_tokens t
             WHERE t.reporte = 'fiabilidad' AND t.token = p_token AND t.activo
               AND (t.expira_at IS NULL OR t.expira_at > NOW())
        ) INTO v_token_ok;
    END IF;

    IF session_user <> 'postgres'
       AND (auth.uid() IS NULL OR public.fn_user_rol() IS NULL)
       AND NOT v_token_ok THEN
        RAISE EXCEPTION 'Acceso no autorizado.';
    END IF;

    -- Traza de uso del token (nunca bloquear el reporte por esto)
    IF v_token_ok THEN
        BEGIN
            UPDATE reporte_tokens SET last_used_at = NOW(), usos = usos + 1
             WHERE reporte = 'fiabilidad' AND token = p_token;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;

    SELECT jsonb_build_object(
    'desde', p_ini,
    'hasta', p_fin,
    'categorias', COALESCE((
      SELECT jsonb_agg(to_jsonb(k)) FROM fn_calcular_fiabilidad_flota(p_ini, p_fin) k
    ), '[]'::jsonb),
    'equipos', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'activo_id', a.id,
        'patente', COALESCE(a.patente, a.codigo),
        'equipamiento', a.nombre,
        'categoria_uso', a.categoria_uso,
        'cliente', a.cliente_actual,
        'marca', mar.nombre,
        'modelo', mod.nombre,
        'anio', a.anio_fabricacion,
        'capacidad', a.capacidad,
        'potencia', a.potencia,
        'vin_chasis', a.vin_chasis,
        'numero_motor', a.numero_motor,
        'estado_comercial', a.estado_comercial,
        'faena', NULL,
        'ubicacion', a.ubicacion_actual,
        'lugar_fisico', NULLIF(a.ubicacion_actual, ''),
        'zona', a.operacion,
        'contrato_codigo', co.codigo,
        'contrato_cliente', co.cliente,
        'contratos_dias', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'codigo',  COALESCE(cc.codigo, '(sin contrato)'),
                   'cliente', cc.cliente,
                   'dias',    d.dias
                 ) ORDER BY d.dias DESC)
          FROM (
            SELECT edf.contrato_id, COUNT(*)::int AS dias
            FROM estado_diario_flota edf
            WHERE edf.activo_id = a.id AND edf.estado_codigo IN ('A','C')
            GROUP BY edf.contrato_id
          ) d
          LEFT JOIN contratos cc ON cc.id = d.contrato_id
        ), '[]'::jsonb),
        'dias_arriendo_total', COALESCE((
          SELECT COUNT(*)::int FROM estado_diario_flota edf
          WHERE edf.activo_id = a.id AND edf.estado_codigo IN ('A','C')
        ), 0),
        'ult_tipo',    ua.tipo_uso,
        'ult_cliente', ua.cliente,
        'ult_lugar',   ua.lugar,
        'ult_desde',   ua.fecha_inicio,
        'ult_hasta',   ua.fecha_fin,
        'ult_dias',    ua.dias,
        'ult_vigente', ua.vigente,
        'dias_observados', f.dias_observados,
        'dias_up', f.dias_up,
        'dias_down', f.dias_down,
        'eventos_falla', f.eventos_falla,
        'mtbf_dias', f.mtbf_dias,
        'mttr_dias', f.mttr_dias,
        'disponibilidad_inherente', f.disponibilidad_inherente,
        'disponibilidad_fisica', f.disponibilidad_fisica
      ) ORDER BY a.patente)
      FROM activos a
      LEFT JOIN modelos mod ON mod.id = a.modelo_id
      LEFT JOIN marcas mar ON mar.id = mod.marca_id
      LEFT JOIN contratos co ON co.id = a.contrato_id
      LEFT JOIN v_activo_ultimo_arriendo ua ON ua.activo_id = a.id
      CROSS JOIN LATERAL fn_calcular_fiabilidad_activo(a.id, p_ini, p_fin) f
      WHERE a.estado <> 'dado_baja'
        AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
        AND f.dias_observados > 0
    ), '[]'::jsonb),
    'matriz', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'activo_id', e.activo_id, 'fecha', e.fecha, 'estado', e.estado_codigo
      ))
      FROM estado_diario_flota e
      JOIN activos a ON a.id = e.activo_id
      WHERE e.fecha BETWEEN p_ini AND p_fin
        AND a.estado <> 'dado_baja'
        AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
    ), '[]'::jsonb),
    'combustible', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'estanque_codigo', estanque_codigo,
        'estanque_nombre', estanque_nombre,
        'capacidad_lt', capacidad_lt,
        'stock_actual', stock_actual,
        'stock_minimo', stock_minimo,
        'dias_cobertura', dias_cobertura,
        'fecha_agotamiento_estimada', fecha_agotamiento_estimada,
        'severidad', severidad
      ) ORDER BY severidad, estanque_codigo)
      FROM v_combustible_proyeccion_stock
      WHERE estanque_codigo NOT LIKE 'CAM-%'
    ), '[]'::jsonb)
    ) INTO v_out;

    RETURN v_out;
END $$;

COMMENT ON FUNCTION public.fn_reporte_fiabilidad_publico(DATE, DATE, TEXT) IS
    'Reporte de fiabilidad (página /reporte-fiabilidad y correo). Acceso: sesión '
    'con perfil, conexión admin directa, o token vigente del link (?t=..., MIG200).';

REVOKE ALL ON FUNCTION public.fn_reporte_fiabilidad_publico(DATE, DATE, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_reporte_fiabilidad_publico(DATE, DATE, TEXT) TO authenticated, anon;


-- ── 3. El personal interno obtiene el token para armar el link del correo ────
CREATE OR REPLACE FUNCTION public.fn_reporte_fiabilidad_link_token()
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF session_user <> 'postgres'
       AND (auth.uid() IS NULL OR public.fn_user_rol() IS NULL) THEN
        RAISE EXCEPTION 'Acceso no autorizado.';
    END IF;
    RETURN (SELECT token FROM reporte_tokens
             WHERE reporte = 'fiabilidad' AND activo
               AND (expira_at IS NULL OR expira_at > NOW())
             ORDER BY created_at DESC LIMIT 1);
END $$;
COMMENT ON FUNCTION public.fn_reporte_fiabilidad_link_token() IS
    'Token vigente del link del reporte de fiabilidad (solo personal interno; para armar el correo). MIG200.';
REVOKE ALL ON FUNCTION public.fn_reporte_fiabilidad_link_token() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_reporte_fiabilidad_link_token() TO authenticated;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
DO $$
DECLARE v JSONB; v_tok TEXT;
BEGIN
    SELECT token INTO v_tok FROM reporte_tokens WHERE reporte='fiabilidad' AND activo LIMIT 1;
    IF v_tok IS NULL THEN RAISE EXCEPTION 'FALLO: no se sembró token'; END IF;

    -- postgres pasa el guard sin token (smoke test del contrato)
    v := public.fn_reporte_fiabilidad_publico(date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE);
    IF NOT (v ? 'categorias' AND v ? 'equipos' AND v ? 'matriz' AND v ? 'combustible') THEN
        RAISE EXCEPTION 'FALLO contrato: faltan claves en la respuesta';
    END IF;
    RAISE NOTICE 'MIG200 OK: token sembrado (%…) · equipos=% · combustible=%',
        left(v_tok, 6), jsonb_array_length(v->'equipos'), jsonb_array_length(v->'combustible');

    IF NOT has_function_privilege('anon', 'public.fn_reporte_fiabilidad_publico(date, date, text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'FALLO: anon no puede ejecutar la RPC (el token no serviría)';
    END IF;
    IF has_function_privilege('anon', 'public.fn_reporte_fiabilidad_link_token()', 'EXECUTE') THEN
        RAISE EXCEPTION 'FALLO: anon puede leer el token (no debe)';
    END IF;
END $$;

SELECT 'MIG200 OK' AS resultado;
NOTIFY pgrst, 'reload schema';
