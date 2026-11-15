-- ============================================================================
-- MIG694 · Bodega ve las transacciones de la tarjeta · Franke: el encargado es
--          el supervisor · catálogo para la bodega Franke sin señal
-- ----------------------------------------------------------------------------
-- Manuel, 15-11-2026:
--   «el supervisor de Franke es el encargado» → Gustavo deja de ser responsable
--     de la bodega de Franke (ni opera ni recibe sus alertas). El conteo de
--     Franke lo aprueba administración (quien cuenta no aprueba su conteo).
--   «bodega también tiene que ver las transacciones» → las transacciones de la
--     tarjeta Aramco (MIG659-691) las ve también el rol bodega. Gustavo justifica
--     las diferencias de Coquimbo; ver el detalle es parte de su trabajo.
--     Validar (aceptar/rechazar) sigue siendo solo de jefatura.
--   «hazla funcionar sin señal como la pauta» → rpc_bodega_faena_catalogo
--     entrega todo lo que el teléfono necesita guardar.
-- ============================================================================

-- ── 1. Quién ve la tarjeta de combustible ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_comb_tarjeta_puede_ver()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT fn_costos_operacion_puede_ver()
        OR fn_tiene_permiso_modulo('inventario', 'view', ARRAY['bodeguero', 'operador_abastecimiento'])
$$;

DO $$
DECLARE
    r RECORD;
    v_def TEXT;
BEGIN
    -- Políticas de lectura de las tablas de la tarjeta.
    FOR r IN SELECT tablename, policyname FROM pg_policies
              WHERE schemaname = 'public' AND qual ILIKE '%fn_costos_operacion_puede_ver%'
                AND tablename IN ('combustible_tarjeta_importaciones', 'combustible_tarjeta_cargas',
                                  'combustible_tarjeta_excluidas', 'combustible_tarjeta_revisiones',
                                  'combustible_km_historico', 'combustible_tarjeta_api_llamadas',
                                  'combustible_tarjeta_tarjetas', 'combustible_tarjeta_reporte_destinatarios',
                                  'combustible_tarjeta_reportes')
    LOOP
        EXECUTE format('ALTER POLICY %I ON public.%I USING (public.fn_comb_tarjeta_puede_ver())', r.policyname, r.tablename);
    END LOOP;

    -- Vistas: se reescriben desde su propia definición, solo cambia la función.
    FOR r IN SELECT viewname FROM pg_views
              WHERE schemaname = 'public'
                AND viewname IN ('v_combustible_tarjeta_cargas', 'v_combustible_rendimiento_mes', 'v_combustible_tarjeta_revisiones')
    LOOP
        v_def := pg_get_viewdef(('public.' || r.viewname)::regclass, true);
        IF position('fn_costos_operacion_puede_ver()' IN v_def) > 0 THEN
            EXECUTE format('CREATE OR REPLACE VIEW public.%I AS %s', r.viewname,
                           replace(v_def, 'fn_costos_operacion_puede_ver()', 'fn_comb_tarjeta_puede_ver()'));
        END IF;
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.rpc_comb_tarjeta_diferencias_todas()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_hoy DATE := (now() AT TIME ZONE 'America/Santiago')::date;
BEGIN
    IF NOT fn_comb_tarjeta_puede_ver() THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    RETURN (SELECT coalesce(jsonb_object_agg(op, fn_comb_tarjeta_diferencias(op, v_hoy)), '{}'::jsonb)
              FROM (SELECT DISTINCT a.operacion AS op FROM combustible_tarjeta_cargas c
                      JOIN activos a ON a.id = c.activo_id WHERE a.operacion IS NOT NULL) o);
END $$;

-- ── 2. Franke: el encargado es el supervisor de turno ───────────────────────
UPDATE public.bodega_responsables r
   SET activo = false
  FROM public.bodegas b
 WHERE b.id = r.bodega_id AND b.codigo = 'BOD-FRK-F01' AND r.email = 'bodegacentral@pilladoempresas.cl';

-- Operar una bodega de faena: administración/jefatura o sus responsables. El
-- rol bodega (Coquimbo) ya no opera bodegas ajenas por defecto.
CREATE OR REPLACE FUNCTION public.fn_bodega_puede_operar(p_bodega_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT auth.uid() IS NOT NULL AND (
        EXISTS (SELECT 1 FROM usuarios_perfil u WHERE u.id = auth.uid()
                  AND u.rol::text IN ('administrador', 'subgerente_operaciones', 'jefe_operaciones'))
        OR EXISTS (SELECT 1 FROM bodega_responsables r
                    WHERE r.bodega_id = p_bodega_id AND r.usuario_id = auth.uid() AND r.activo AND r.puede_operar))
$$;

-- El aviso de conteo por aprobar va solo a administración.
DO $$
DECLARE v_def TEXT;
BEGIN
    v_def := pg_get_functiondef('public.rpc_bodega_faena_conteo(uuid, jsonb, boolean, text, uuid)'::regprocedure);
    IF position('OR u.email = ''bodegacoq@pillado.cl''' IN v_def) > 0 THEN
        EXECUTE replace(v_def, ' OR u.email = ''bodegacoq@pillado.cl''', '');
    END IF;
END $$;

-- ── 3. Catálogo para trabajar sin señal ─────────────────────────────────────
-- Todo el maestro (≈1.900 productos, ~200 KB): sin señal se puede escanear
-- cualquier etiqueta, no solo lo que ya estaba en la bodega.
CREATE OR REPLACE FUNCTION public.rpc_bodega_faena_catalogo(p_bodega_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF NOT fn_bodega_puede_ver(p_bodega_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    RETURN jsonb_build_object(
        'generado_at', NOW(),
        'puede_operar', fn_bodega_puede_operar(p_bodega_id),
        'productos', (SELECT coalesce(jsonb_agg(jsonb_build_array(
                         p.id, p.codigo, p.codigo_barras, p.nombre, p.categoria, p.unidad_medida,
                         coalesce(s.cantidad, 0), pr.minimo)), '[]'::jsonb)
                        FROM productos p
                        LEFT JOIN stock_bodega s ON s.producto_id = p.id AND s.bodega_id = p_bodega_id
                        LEFT JOIN bodega_stock_parametros pr ON pr.producto_id = p.id AND pr.bodega_id = p_bodega_id),
        'equipos', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'patente', a.patente, 'tipo', a.tipo)
                       ORDER BY a.patente), '[]'::jsonb)
                      FROM activos a WHERE a.patente IN ('HHWB-44', 'LCSX-78', 'HHWB-42', 'LLBP-96')));
END $$;
REVOKE ALL ON FUNCTION public.rpc_bodega_faena_catalogo(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_bodega_faena_catalogo(UUID) TO authenticated;

SELECT 'MIG694 OK' AS resultado;
