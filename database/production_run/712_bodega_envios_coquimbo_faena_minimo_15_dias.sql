-- ============================================================================
-- MIG712 — Envíos Coquimbo → faena, mínimo = 15 días de consumo, mecánico saca
-- ----------------------------------------------------------------------------
-- Pedidos de Manuel (18-11-2026), sobre la bodega de faena Franke (MIG692/711):
--
--  1. «Gustavo envía desde Coquimbo y Franke confirma la recepción»: un solo
--     registro. Al ENVIAR sale de Coquimbo (capas FIFO, costo real) y queda «en
--     camino»; al CONFIRMAR entra a Franke con ese mismo costo. Si llega menos,
--     la diferencia queda a la vista (recibido con diferencias). Anular un envío
--     en camino lo devuelve a Coquimbo.
--  2. «El mínimo son 15 días de producto»: mínimo = consumo diario × 15,
--     máximo = × 30 (lo que se pide para reponer). Consumo diario:
--       · con ≥ 60 días de salidas propias en SICOM → esas salidas (180 d máx);
--       · si no → salidas de bodega Softland a los CECO de la faena (180 d).
--     Se recalcula una vez por semana desde el cron de alertas y con un botón.
--     Un mínimo fijado a mano no se pisa.
--  3. «El supervisor o el mecánico»: los mecánicos de Franke pueden SACAR
--     (repuestos/filtros a su camión), no recibir ni contar.
--
-- Rollback: database/rollback/712_bodega_envios_coquimbo_faena_minimo_15_dias.sql
-- ============================================================================

-- ── 0. Estructura ───────────────────────────────────────────────────────────
ALTER TABLE public.bodega_responsables ADD COLUMN IF NOT EXISTS solo_sacar BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.bodegas ADD COLUMN IF NOT EXISTS dias_minimo INT;
COMMENT ON COLUMN public.bodegas.dias_minimo IS 'MIG712: días de consumo que debe cubrir el mínimo (NULL = no se calcula).';
ALTER TABLE public.bodega_stock_parametros
    ADD COLUMN IF NOT EXISTS consumo_diario NUMERIC,
    ADD COLUMN IF NOT EXISTS origen TEXT NOT NULL DEFAULT 'manual',
    ADD COLUMN IF NOT EXISTS calculado_at TIMESTAMPTZ;
ALTER TABLE public.bodega_stock_parametros DROP CONSTRAINT IF EXISTS bodega_stock_parametros_origen_check;
ALTER TABLE public.bodega_stock_parametros ADD CONSTRAINT bodega_stock_parametros_origen_check
    CHECK (origen IN ('manual', 'auto_sicom', 'auto_softland'));
ALTER TABLE public.bodega_operaciones DROP CONSTRAINT IF EXISTS bodega_operaciones_tipo_check;
ALTER TABLE public.bodega_operaciones ADD CONSTRAINT bodega_operaciones_tipo_check
    CHECK (tipo IN ('salida', 'ingreso', 'conteo', 'envio', 'recepcion_envio'));

-- CECO de Softland cuyo consumo define el mínimo de cada bodega de faena.
CREATE TABLE IF NOT EXISTS public.bodega_cecos_consumo (
    bodega_id UUID NOT NULL REFERENCES public.bodegas(id) ON DELETE CASCADE,
    codi_cc   TEXT NOT NULL,
    PRIMARY KEY (bodega_id, codi_cc)
);
ALTER TABLE public.bodega_cecos_consumo ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bodega_cecos_consumo_sel ON public.bodega_cecos_consumo;
CREATE POLICY bodega_cecos_consumo_sel ON public.bodega_cecos_consumo
    FOR SELECT TO authenticated USING (public.fn_bodega_puede_ver(bodega_id));

CREATE SEQUENCE IF NOT EXISTS public.bodega_envio_folio_seq;
CREATE TABLE IF NOT EXISTS public.bodega_envios (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    folio                TEXT NOT NULL UNIQUE DEFAULT 'ENV-' || lpad(nextval('public.bodega_envio_folio_seq')::text, 5, '0'),
    bodega_origen_id     UUID NOT NULL REFERENCES public.bodegas(id),
    bodega_destino_id    UUID NOT NULL REFERENCES public.bodegas(id),
    estado               TEXT NOT NULL DEFAULT 'en_camino'
                         CHECK (estado IN ('en_camino', 'recibido', 'recibido_con_diferencias', 'anulado')),
    guia                 TEXT,
    observacion          TEXT,
    creado_por           UUID REFERENCES public.usuarios_perfil(id),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    recibido_por         UUID REFERENCES public.usuarios_perfil(id),
    recibido_at          TIMESTAMPTZ,
    observacion_recepcion TEXT,
    anulado_por          UUID REFERENCES public.usuarios_perfil(id),
    anulado_at           TIMESTAMPTZ,
    CHECK (bodega_origen_id <> bodega_destino_id)
);
CREATE INDEX IF NOT EXISTS idx_bodega_envios_destino ON public.bodega_envios (bodega_destino_id, estado);
CREATE INDEX IF NOT EXISTS idx_bodega_envios_origen ON public.bodega_envios (bodega_origen_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.bodega_envio_items (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    envio_id          UUID NOT NULL REFERENCES public.bodega_envios(id) ON DELETE CASCADE,
    producto_id       UUID NOT NULL REFERENCES public.productos(id),
    cantidad_enviada  NUMERIC NOT NULL CHECK (cantidad_enviada > 0),
    cantidad_recibida NUMERIC CHECK (cantidad_recibida >= 0),
    costo_unitario    NUMERIC NOT NULL DEFAULT 0,
    UNIQUE (envio_id, producto_id)
);

-- ── 0b. Costo de referencia: el $1 de Coquimbo es semilla, no costo ──────────
-- El conteo inicial de Coquimbo (MIG563) dejó 1.539 de 1.564 capas a $1 y su CPP
-- en $1. MIG711 lo tomaba como costo real; ahora ≤ $1 se trata como «sin costo».
CREATE OR REPLACE FUNCTION public.fn_bodega_costo_referencia(p_producto_id UUID)
RETURNS NUMERIC
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
    v_cod   TEXT;
    v_base  TEXT;
    v_cqb   UUID;
    v_costo NUMERIC;
BEGIN
    SELECT codigo INTO v_cod FROM productos WHERE id = p_producto_id;
    IF v_cod IS NULL THEN RETURN 0; END IF;
    SELECT id INTO v_cqb FROM bodegas WHERE codigo = 'BOD-CQB-F01';
    SELECT costo_promedio INTO v_costo FROM stock_bodega
     WHERE bodega_id = v_cqb AND producto_id = p_producto_id AND costo_promedio > 1;
    IF v_costo IS NOT NULL THEN RETURN round(v_costo, 4); END IF;
    SELECT costo_unitario INTO v_costo FROM inventario_capas
     WHERE bodega_id = v_cqb AND producto_id = p_producto_id AND costo_unitario > 1
     ORDER BY fecha_recepcion DESC, created_at DESC LIMIT 1;
    IF v_costo IS NOT NULL THEN RETURN round(v_costo, 4); END IF;
    SELECT l.precio_unit INTO v_costo
      FROM softland_oc_linea l JOIN softland_oc o USING (num_inter_oc)
     WHERE l.cod_prod = v_cod AND o.estado = 'AP' AND l.precio_unit > 1
     ORDER BY o.fecha_oc DESC, o.num_inter_oc DESC LIMIT 1;
    IF v_costo IS NOT NULL THEN RETURN round(v_costo, 4); END IF;
    v_base := regexp_replace(v_cod, '-[^-]+$', '');
    IF v_base <> v_cod THEN
        SELECT l.precio_unit INTO v_costo
          FROM softland_oc_linea l JOIN softland_oc o USING (num_inter_oc)
         WHERE l.cod_prod = v_base AND o.estado = 'AP' AND l.precio_unit > 1
         ORDER BY o.fecha_oc DESC, o.num_inter_oc DESC LIMIT 1;
        IF v_costo IS NOT NULL THEN RETURN round(v_costo, 4); END IF;
    END IF;
    SELECT costo_unitario_actual INTO v_costo FROM productos WHERE id = p_producto_id AND costo_unitario_actual > 1;
    RETURN round(coalesce(v_costo, 0), 4);
END $$;

-- Las capas de Franke que quedaron en ≤ $1 por esa semilla (sin consumos) se revalorizan.
DO $$
DECLARE v_bod UUID; v_n INT;
BEGIN
    SELECT id INTO v_bod FROM bodegas WHERE codigo = 'BOD-FRK-F01';
    CREATE TEMP TABLE _frk_rev ON COMMIT DROP AS
    SELECT DISTINCT ic.producto_id, fn_bodega_costo_referencia(ic.producto_id) AS costo
      FROM inventario_capas ic
     WHERE ic.bodega_id = v_bod AND ic.costo_unitario <= 1
       AND NOT EXISTS (SELECT 1 FROM inventario_consumos_capas x WHERE x.capa_id = ic.id);
    DELETE FROM _frk_rev WHERE costo <= 1;
    UPDATE inventario_capas ic SET costo_unitario = r.costo FROM _frk_rev r
     WHERE ic.bodega_id = v_bod AND ic.producto_id = r.producto_id AND ic.costo_unitario <= 1
       AND NOT EXISTS (SELECT 1 FROM inventario_consumos_capas x WHERE x.capa_id = ic.id);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    PERFORM fn_bodega_sync_cpp(v_bod, producto_id) FROM _frk_rev;
    UPDATE movimientos_inventario m SET costo_unitario = r.costo FROM _frk_rev r
     WHERE m.bodega_id = v_bod AND m.producto_id = r.producto_id AND m.tipo = 'ajuste_positivo' AND m.costo_unitario <= 1;
    UPDATE kardex k SET costo_unitario = r.costo, costo_promedio_posterior = r.costo,
                        valor_movimiento = k.cantidad_movimiento * r.costo, valor_stock_posterior = k.cantidad_posterior * r.costo
      FROM movimientos_inventario m, _frk_rev r
     WHERE k.movimiento_id = m.id AND m.bodega_id = v_bod AND m.producto_id = r.producto_id AND m.tipo = 'ajuste_positivo';
    RAISE NOTICE 'MIG712: % capas de Franke en $1 revalorizadas', v_n;
END $$;

-- ── 1. Permisos ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_bodega_puede_sacar(p_bodega_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT fn_bodega_puede_operar(p_bodega_id)
        OR EXISTS (SELECT 1 FROM bodega_responsables r
                    WHERE r.bodega_id = p_bodega_id AND r.usuario_id = auth.uid() AND r.activo AND r.solo_sacar)
$$;
-- Envía desde la bodega central: el bodeguero (Gustavo) y jefaturas, o un responsable que opera esa bodega.
CREATE OR REPLACE FUNCTION public.fn_bodega_puede_enviar(p_bodega_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT auth.uid() IS NOT NULL AND (
        EXISTS (SELECT 1 FROM usuarios_perfil u WHERE u.id = auth.uid()
                  AND u.rol::text IN ('administrador', 'subgerente_operaciones', 'jefe_operaciones', 'jefe_mantenimiento', 'bodeguero'))
        OR EXISTS (SELECT 1 FROM bodega_responsables r
                    WHERE r.bodega_id = p_bodega_id AND r.usuario_id = auth.uid() AND r.activo AND r.puede_operar))
$$;
GRANT EXECUTE ON FUNCTION public.fn_bodega_puede_sacar(UUID), public.fn_bodega_puede_enviar(UUID) TO authenticated;

ALTER TABLE public.bodega_envios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bodega_envio_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bodega_envios_sel ON public.bodega_envios;
CREATE POLICY bodega_envios_sel ON public.bodega_envios FOR SELECT TO authenticated
    USING (fn_bodega_puede_ver(bodega_destino_id) OR fn_bodega_puede_enviar(bodega_origen_id));
DROP POLICY IF EXISTS bodega_envio_items_sel ON public.bodega_envio_items;
CREATE POLICY bodega_envio_items_sel ON public.bodega_envio_items FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM bodega_envios e WHERE e.id = envio_id
                    AND (fn_bodega_puede_ver(e.bodega_destino_id) OR fn_bodega_puede_enviar(e.bodega_origen_id))));

-- Mecánicos de Franke: solo sacar.
INSERT INTO public.bodega_responsables (bodega_id, usuario_id, nombre, email, puede_operar, recibe_alertas, tipo_correo, activo, solo_sacar)
SELECT b.id, u.id, u.nombre_completo || ' (mecánico, solo sacar)', u.email, false, false, 'cc', true, true
  FROM bodegas b, usuarios_perfil u
 WHERE b.codigo = 'BOD-FRK-F01' AND u.email IN ('hcortes@pillado.cl', 'yrondon@pillado.cl')
ON CONFLICT (bodega_id, email) DO UPDATE SET solo_sacar = true, activo = true, usuario_id = EXCLUDED.usuario_id;

-- ── 2. Sacar: también el mecánico (misma lógica FIFO de MIG711) ──────────────
CREATE OR REPLACE FUNCTION public.rpc_bodega_faena_salida(p_bodega_id uuid, p_items jsonb, p_activo_id uuid, p_motivo text, p_entregado_a text, p_client_uuid uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_prev   JSONB;
    v_ceco   UUID;
    v_it     RECORD;
    v_stock  RECORD;
    v_mov    UUID;
    v_nuevo  NUMERIC;
    v_fifo   JSONB;
    v_cu     NUMERIC;
    v_cpp1   NUMERIC;
    v_total  NUMERIC := 0;
    v_n      INT := 0;
    v_bajo   JSONB := '[]'::jsonb;
    v_min    NUMERIC;
    v_res    JSONB;
BEGIN
    IF NOT fn_bodega_puede_sacar(p_bodega_id) THEN   -- [MIG712] supervisor o mecánico
        RAISE EXCEPTION 'No tiene permiso para sacar de esta bodega.' USING ERRCODE = '42501';
    END IF;
    SELECT resultado INTO v_prev FROM bodega_operaciones WHERE client_uuid = p_client_uuid;
    IF v_prev IS NOT NULL THEN RETURN v_prev || jsonb_build_object('repetida', true); END IF;
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'No hay productos escaneados.'; END IF;
    IF p_activo_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM activos WHERE id = p_activo_id) THEN
        RAISE EXCEPTION 'Equipo no encontrado.';
    END IF;
    SELECT id INTO v_ceco FROM centros_costo WHERE codigo = 'FRK-OPER';

    FOR v_it IN
        SELECT x.producto_id, x.cantidad, p.nombre, p.categoria
          FROM jsonb_to_recordset(p_items) AS x(producto_id UUID, cantidad NUMERIC)
          JOIN productos p ON p.id = x.producto_id
    LOOP
        IF v_it.cantidad IS NULL OR v_it.cantidad <= 0 THEN
            RAISE EXCEPTION 'Cantidad inválida para «%».', v_it.nombre;
        END IF;
        IF v_it.categoria IN ('repuesto', 'filtro', 'lubricante') AND p_activo_id IS NULL THEN
            RAISE EXCEPTION '«%» es % : indique a qué camión o equipo va.', v_it.nombre, v_it.categoria;
        END IF;
        SELECT cantidad, costo_promedio INTO v_stock FROM stock_bodega
         WHERE bodega_id = p_bodega_id AND producto_id = v_it.producto_id FOR UPDATE;
        IF NOT FOUND OR v_stock.cantidad < v_it.cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente de «%»: hay %, pide %.',
                v_it.nombre, coalesce(v_stock.cantidad, 0), v_it.cantidad;
        END IF;
        v_nuevo := v_stock.cantidad - v_it.cantidad;
        v_mov := gen_random_uuid();
        INSERT INTO movimientos_inventario (id, bodega_id, producto_id, tipo, cantidad, costo_unitario,
                                            activo_id, ceco_id, motivo, documento_referencia, usuario_id, created_at)
        VALUES (v_mov, p_bodega_id, v_it.producto_id, 'salida', v_it.cantidad, 0,
                p_activo_id, v_ceco,
                left(concat_ws(' · ', nullif(btrim(p_motivo), ''),
                               CASE WHEN nullif(btrim(p_entregado_a), '') IS NOT NULL THEN 'entregado a ' || btrim(p_entregado_a) END), 500),
                'LECTOR-' || p_client_uuid::text, auth.uid(), NOW());
        v_fifo := fn_consumir_inventario_fifo(v_it.producto_id, p_bodega_id, v_it.cantidad,
                                              NULL, NULL, v_mov, NULL, v_ceco, auth.uid());
        v_cu := round((v_fifo->>'costo_total')::numeric / v_it.cantidad, 4);
        UPDATE movimientos_inventario SET costo_unitario = v_cu WHERE id = v_mov;
        UPDATE stock_bodega SET cantidad = v_nuevo, ultimo_movimiento = NOW(), updated_at = NOW()
         WHERE bodega_id = p_bodega_id AND producto_id = v_it.producto_id;
        v_cpp1 := coalesce(fn_bodega_sync_cpp(p_bodega_id, v_it.producto_id), v_stock.costo_promedio);
        INSERT INTO kardex (id, bodega_id, producto_id, movimiento_id, fecha, tipo, cantidad_movimiento,
                            cantidad_anterior, cantidad_posterior, costo_unitario, costo_promedio_anterior,
                            costo_promedio_posterior, valor_movimiento, valor_stock_posterior)
        VALUES (gen_random_uuid(), p_bodega_id, v_it.producto_id, v_mov, NOW(), 'salida', v_it.cantidad,
                v_stock.cantidad, v_nuevo, v_cu, v_stock.costo_promedio, v_cpp1,
                (v_fifo->>'costo_total')::numeric, v_nuevo * coalesce(v_cpp1, 0));
        v_total := v_total + (v_fifo->>'costo_total')::numeric;
        v_n := v_n + 1;
        SELECT minimo INTO v_min FROM bodega_stock_parametros WHERE bodega_id = p_bodega_id AND producto_id = v_it.producto_id;
        IF v_min > 0 AND v_nuevo <= v_min THEN
            v_bajo := v_bajo || jsonb_build_object('producto', v_it.nombre, 'stock', v_nuevo, 'minimo', v_min);
        END IF;
    END LOOP;
    IF v_n <> jsonb_array_length(p_items) THEN RAISE EXCEPTION 'Algún producto escaneado no existe.'; END IF;

    v_res := jsonb_build_object('ok', true, 'items', v_n, 'costo_total', round(v_total), 'bajo_minimo', v_bajo);
    INSERT INTO bodega_operaciones (client_uuid, bodega_id, tipo, resultado) VALUES (p_client_uuid, p_bodega_id, 'salida', v_res);
    RETURN v_res;
END $function$;

-- Catálogo del teléfono: dice si quien lo baja solo puede sacar.
CREATE OR REPLACE FUNCTION public.rpc_bodega_faena_catalogo(p_bodega_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT fn_bodega_puede_ver(p_bodega_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    RETURN jsonb_build_object(
        'generado_at', NOW(),
        'puede_operar', fn_bodega_puede_operar(p_bodega_id),
        'puede_sacar', fn_bodega_puede_sacar(p_bodega_id),
        'productos', (SELECT coalesce(jsonb_agg(jsonb_build_array(
                         p.id, p.codigo, p.codigo_barras, p.nombre, p.categoria, p.unidad_medida,
                         coalesce(s.cantidad, 0), pr.minimo)), '[]'::jsonb)
                        FROM productos p
                        LEFT JOIN stock_bodega s ON s.producto_id = p.id AND s.bodega_id = p_bodega_id
                        LEFT JOIN bodega_stock_parametros pr ON pr.producto_id = p.id AND pr.bodega_id = p_bodega_id),
        'equipos', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'patente', a.patente, 'tipo', a.tipo)
                       ORDER BY a.patente), '[]'::jsonb)
                      FROM activos a WHERE a.patente IN ('HHWB-44', 'LCSX-78', 'HHWB-42', 'LLBP-96')));
END $function$;

-- ── 3. Mínimo = N días de consumo ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_bodega_recalcular_minimos(p_bodega_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
    v_dias    INT;
    v_inicio  DATE;
    v_ventana INT;
    v_fuente  TEXT;
    v_n       INT;
    v_sin     INT;
BEGIN
    SELECT dias_minimo INTO v_dias FROM bodegas WHERE id = p_bodega_id;
    IF v_dias IS NULL OR v_dias <= 0 THEN RETURN jsonb_build_object('ok', false, 'motivo', 'bodega sin días de mínimo'); END IF;

    SELECT min(created_at)::date INTO v_inicio FROM movimientos_inventario
     WHERE bodega_id = p_bodega_id AND tipo = 'salida';
    IF v_inicio IS NOT NULL AND CURRENT_DATE - v_inicio >= 60 THEN
        v_fuente := 'auto_sicom'; v_ventana := least(180, CURRENT_DATE - v_inicio);
    ELSE
        v_fuente := 'auto_softland'; v_ventana := 180;
    END IF;

    CREATE TEMP TABLE IF NOT EXISTS _bod_consumo (producto_id UUID PRIMARY KEY, diario NUMERIC) ON COMMIT DROP;
    TRUNCATE _bod_consumo;   -- destructivo-ok: tabla temporal de la función
    IF v_fuente = 'auto_sicom' THEN
        INSERT INTO _bod_consumo
        SELECT producto_id, sum(cantidad) / v_ventana FROM movimientos_inventario
         WHERE bodega_id = p_bodega_id AND tipo = 'salida' AND created_at >= CURRENT_DATE - v_ventana
         GROUP BY 1;
    ELSE
        INSERT INTO _bod_consumo
        SELECT p.id, sum(l.cantidad) / v_ventana
          FROM softland_doc d JOIN softland_linea l USING (tipo, cod_bode, nro_int)
          JOIN productos p ON p.codigo = l.cod_prod
         WHERE d.tipo = 'S' AND d.fecha >= CURRENT_DATE - v_ventana AND l.cantidad > 0
           AND d.codi_cc IN (SELECT codi_cc FROM bodega_cecos_consumo WHERE bodega_id = p_bodega_id)
         GROUP BY 1;
    END IF;

    -- Solo productos que la bodega maneja; nunca pisa un mínimo puesto a mano.
    INSERT INTO bodega_stock_parametros (bodega_id, producto_id, minimo, maximo, consumo_diario, origen, calculado_at, updated_at)
    -- Redondeo al entero: si en N días se usa menos de media unidad (consumo
    -- esporádico) no se fija mínimo; el máximo es 2N días, nunca menor al mínimo.
    SELECT p_bodega_id, c.producto_id, round(c.diario * v_dias), greatest(round(c.diario * v_dias), ceil(c.diario * v_dias * 2)),
           round(c.diario, 4), v_fuente, NOW(), NOW()
      FROM _bod_consumo c
     WHERE round(c.diario * v_dias) >= 1
       AND EXISTS (SELECT 1 FROM stock_bodega s WHERE s.bodega_id = p_bodega_id AND s.producto_id = c.producto_id)
    ON CONFLICT (bodega_id, producto_id) DO UPDATE
       SET minimo = EXCLUDED.minimo, maximo = EXCLUDED.maximo, consumo_diario = EXCLUDED.consumo_diario,
           origen = EXCLUDED.origen, calculado_at = NOW(), updated_at = NOW()
     WHERE bodega_stock_parametros.origen <> 'manual';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    -- Ya no hay consumo en la ventana: el mínimo automático vuelve a 0.
    UPDATE bodega_stock_parametros pr SET minimo = 0, maximo = NULL, consumo_diario = 0, calculado_at = NOW(), updated_at = NOW()
     WHERE pr.bodega_id = p_bodega_id AND pr.origen <> 'manual' AND pr.minimo > 0
       AND NOT EXISTS (SELECT 1 FROM _bod_consumo c WHERE c.producto_id = pr.producto_id AND round(c.diario * v_dias) >= 1);
    SELECT count(*) INTO v_sin FROM stock_bodega s
     WHERE s.bodega_id = p_bodega_id
       AND NOT EXISTS (SELECT 1 FROM bodega_stock_parametros pr WHERE pr.bodega_id = s.bodega_id AND pr.producto_id = s.producto_id AND pr.minimo > 0);
    RETURN jsonb_build_object('ok', true, 'dias', v_dias, 'fuente', v_fuente, 'ventana_dias', v_ventana,
                              'productos_calculados', v_n, 'sin_minimo', v_sin);
END $$;
REVOKE ALL ON FUNCTION public.fn_bodega_recalcular_minimos(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.rpc_bodega_recalcular_minimos(p_bodega_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF NOT (fn_bodega_puede_operar(p_bodega_id) OR fn_bodega_puede_enviar(p_bodega_id)) THEN
        RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501';
    END IF;
    RETURN fn_bodega_recalcular_minimos(p_bodega_id);
END $$;
GRANT EXECUTE ON FUNCTION public.rpc_bodega_recalcular_minimos(UUID) TO authenticated;

-- Fijar a mano = queda «manual» (el cálculo automático ya no lo toca). Mínimo 0 y sin máximo = vuelve a automático.
CREATE OR REPLACE FUNCTION public.rpc_bodega_set_parametro(p_bodega_id uuid, p_producto_id uuid, p_minimo numeric, p_maximo numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT fn_bodega_puede_operar(p_bodega_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    IF p_minimo IS NULL OR p_minimo < 0 THEN RAISE EXCEPTION 'El mínimo debe ser 0 o más.'; END IF;
    IF p_maximo IS NOT NULL AND p_maximo < p_minimo THEN RAISE EXCEPTION 'El máximo no puede ser menor que el mínimo.'; END IF;
    INSERT INTO bodega_stock_parametros (bodega_id, producto_id, minimo, maximo, origen, updated_by, updated_at)
    VALUES (p_bodega_id, p_producto_id, p_minimo, p_maximo,
            CASE WHEN p_minimo = 0 AND p_maximo IS NULL THEN 'auto_softland' ELSE 'manual' END, auth.uid(), NOW())
    ON CONFLICT (bodega_id, producto_id) DO UPDATE
       SET minimo = EXCLUDED.minimo, maximo = EXCLUDED.maximo, origen = EXCLUDED.origen,
           updated_by = auth.uid(), updated_at = NOW();
END $function$;

-- Recalculo semanal desde el cron de alertas (*/15): barato, una vez cada 7 días por bodega.
CREATE OR REPLACE FUNCTION public.fn_bodega_alertas_cron(p_secreto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_b UUID;
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501';
    END IF;
    -- [MIG712] mínimos por días de consumo, una vez por semana
    FOR v_b IN SELECT b.id FROM bodegas b
                WHERE b.dias_minimo > 0
                  AND coalesce((SELECT max(calculado_at) FROM bodega_stock_parametros pr WHERE pr.bodega_id = b.id), '-infinity') < NOW() - interval '7 days'
    LOOP
        BEGIN PERFORM fn_bodega_recalcular_minimos(v_b); EXCEPTION WHEN OTHERS THEN RAISE WARNING 'mínimos %: %', v_b, SQLERRM; END;
    END LOOP;
    RETURN (SELECT coalesce(jsonb_agg(b), '[]'::jsonb) FROM (
        SELECT jsonb_build_object(
                 'bodega_id', bo.id, 'bodega', bo.nombre,
                 'para', (SELECT coalesce(jsonb_agg(DISTINCT r.email), '[]') FROM bodega_responsables r
                           WHERE r.bodega_id = bo.id AND r.activo AND r.recibe_alertas AND r.tipo_correo = 'para' AND r.email IS NOT NULL),
                 'cc',   (SELECT coalesce(jsonb_agg(DISTINCT r.email), '[]') FROM bodega_responsables r
                           WHERE r.bodega_id = bo.id AND r.activo AND r.recibe_alertas AND r.tipo_correo = 'cc' AND r.email IS NOT NULL),
                 'nuevas', (SELECT jsonb_agg(jsonb_build_object('id', a.id, 'producto', p.nombre, 'codigo', p.codigo,
                               'unidad', p.unidad_medida, 'stock', a.stock, 'minimo', a.minimo) ORDER BY p.nombre)
                              FROM bodega_alertas_stock a JOIN productos p ON p.id = a.producto_id
                             WHERE a.bodega_id = bo.id AND a.estado = 'abierta' AND a.notificada_at IS NULL),
                 'abiertas', (SELECT count(*) FROM bodega_alertas_stock a WHERE a.bodega_id = bo.id AND a.estado = 'abierta')) AS b
          FROM bodegas bo
         WHERE EXISTS (SELECT 1 FROM bodega_alertas_stock a
                        WHERE a.bodega_id = bo.id AND a.estado = 'abierta' AND a.notificada_at IS NULL)) q);
END $function$;

-- ── 4. Envíos entre bodegas ─────────────────────────────────────────────────
-- 4.1 Enviar: sale de la bodega origen por FIFO y queda en camino.
CREATE OR REPLACE FUNCTION public.rpc_bodega_envio_crear(p_origen_id UUID, p_destino_id UUID, p_items JSONB,
                                                         p_guia TEXT, p_observacion TEXT, p_client_uuid UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_prev  JSONB;
    v_env   RECORD;
    v_dest  TEXT;
    v_it    RECORD;
    v_stock RECORD;
    v_mov   UUID;
    v_fifo  JSONB;
    v_cu    NUMERIC;
    v_nuevo NUMERIC;
    v_n     INT := 0;
    v_total NUMERIC := 0;
    v_res   JSONB;
BEGIN
    IF NOT fn_bodega_puede_enviar(p_origen_id) THEN RAISE EXCEPTION 'No tiene permiso para enviar desde esta bodega.' USING ERRCODE = '42501'; END IF;
    SELECT resultado INTO v_prev FROM bodega_operaciones WHERE client_uuid = p_client_uuid;
    IF v_prev IS NOT NULL THEN RETURN v_prev || jsonb_build_object('repetida', true); END IF;
    IF p_origen_id = p_destino_id THEN RAISE EXCEPTION 'Origen y destino no pueden ser la misma bodega.'; END IF;
    SELECT nombre INTO v_dest FROM bodegas WHERE id = p_destino_id;
    IF v_dest IS NULL THEN RAISE EXCEPTION 'Bodega destino no existe.'; END IF;
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'El envío no tiene productos.'; END IF;

    INSERT INTO bodega_envios (bodega_origen_id, bodega_destino_id, guia, observacion, creado_por)
    VALUES (p_origen_id, p_destino_id, nullif(btrim(p_guia), ''), nullif(btrim(p_observacion), ''), auth.uid())
    RETURNING id, folio INTO v_env;

    FOR v_it IN
        SELECT x.producto_id, sum(x.cantidad) AS cantidad, p.nombre
          FROM jsonb_to_recordset(p_items) AS x(producto_id UUID, cantidad NUMERIC)
          JOIN productos p ON p.id = x.producto_id
         GROUP BY x.producto_id, p.nombre
    LOOP
        IF v_it.cantidad IS NULL OR v_it.cantidad <= 0 THEN RAISE EXCEPTION 'Cantidad inválida para «%».', v_it.nombre; END IF;
        SELECT cantidad, costo_promedio INTO v_stock FROM stock_bodega
         WHERE bodega_id = p_origen_id AND producto_id = v_it.producto_id FOR UPDATE;
        IF NOT FOUND OR v_stock.cantidad < v_it.cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente de «%» en origen: hay %, envía %.', v_it.nombre, coalesce(v_stock.cantidad, 0), v_it.cantidad;
        END IF;
        v_nuevo := v_stock.cantidad - v_it.cantidad;
        v_mov := gen_random_uuid();
        INSERT INTO movimientos_inventario (id, bodega_id, producto_id, tipo, cantidad, costo_unitario,
                                            bodega_destino_id, motivo, documento_referencia, usuario_id, created_at)
        VALUES (v_mov, p_origen_id, v_it.producto_id, 'transferencia_salida', v_it.cantidad, 0,
                p_destino_id, left('Envío ' || v_env.folio || ' a ' || v_dest, 300), v_env.folio, auth.uid(), NOW());
        v_fifo := fn_consumir_inventario_fifo(v_it.producto_id, p_origen_id, v_it.cantidad,
                                              NULL, NULL, v_mov, NULL, NULL, auth.uid());
        v_cu := round((v_fifo->>'costo_total')::numeric / v_it.cantidad, 4);
        UPDATE movimientos_inventario SET costo_unitario = v_cu WHERE id = v_mov;
        UPDATE stock_bodega SET cantidad = v_nuevo, ultimo_movimiento = NOW(), updated_at = NOW()
         WHERE bodega_id = p_origen_id AND producto_id = v_it.producto_id;
        INSERT INTO kardex (id, bodega_id, producto_id, movimiento_id, fecha, tipo, cantidad_movimiento,
                            cantidad_anterior, cantidad_posterior, costo_unitario, costo_promedio_anterior,
                            costo_promedio_posterior, valor_movimiento, valor_stock_posterior)
        VALUES (gen_random_uuid(), p_origen_id, v_it.producto_id, v_mov, NOW(), 'transferencia_salida', v_it.cantidad,
                v_stock.cantidad, v_nuevo, v_cu, v_stock.costo_promedio, v_stock.costo_promedio,
                (v_fifo->>'costo_total')::numeric, v_nuevo * coalesce(v_stock.costo_promedio, 0));
        -- Lo que recibe la faena: el costo FIFO de Coquimbo, salvo que sea la semilla de $1
        -- del conteo inicial (MIG563); entonces la referencia (último precio OC Softland).
        INSERT INTO bodega_envio_items (envio_id, producto_id, cantidad_enviada, costo_unitario)
        VALUES (v_env.id, v_it.producto_id, v_it.cantidad,
                CASE WHEN v_cu <= 1 THEN greatest(fn_bodega_costo_referencia(v_it.producto_id), v_cu) ELSE v_cu END);
        v_total := v_total + v_it.cantidad * CASE WHEN v_cu <= 1 THEN greatest(fn_bodega_costo_referencia(v_it.producto_id), v_cu) ELSE v_cu END;
        v_n := v_n + 1;
    END LOOP;
    IF v_n = 0 THEN RAISE EXCEPTION 'Algún producto del envío no existe.'; END IF;

    v_res := jsonb_build_object('ok', true, 'envio_id', v_env.id, 'folio', v_env.folio, 'items', v_n, 'costo_total', round(v_total));
    INSERT INTO bodega_operaciones (client_uuid, bodega_id, tipo, resultado) VALUES (p_client_uuid, p_origen_id, 'envio', v_res);
    RETURN v_res;
END $$;
GRANT EXECUTE ON FUNCTION public.rpc_bodega_envio_crear(UUID, UUID, JSONB, TEXT, TEXT, UUID) TO authenticated;

-- Entrada a una bodega desde un envío/anulación: capa con el costo del envío.
CREATE OR REPLACE FUNCTION public.fn_bodega_entrada_transferencia(p_bodega_id UUID, p_otra_bodega UUID, p_producto_id UUID,
                                                                   p_cantidad NUMERIC, p_costo NUMERIC, p_folio TEXT, p_motivo TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_stock RECORD; v_mov UUID := gen_random_uuid(); v_cant0 NUMERIC; v_cpp0 NUMERIC; v_cpp1 NUMERIC; v_unidad TEXT;
BEGIN
    SELECT unidad_medida INTO v_unidad FROM productos WHERE id = p_producto_id;
    SELECT cantidad, costo_promedio INTO v_stock FROM stock_bodega
     WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id FOR UPDATE;
    v_cant0 := coalesce(v_stock.cantidad, 0); v_cpp0 := coalesce(v_stock.costo_promedio, 0);
    INSERT INTO movimientos_inventario (id, bodega_id, producto_id, tipo, cantidad, costo_unitario,
                                        bodega_destino_id, motivo, documento_referencia, usuario_id, created_at)
    VALUES (v_mov, p_bodega_id, p_producto_id, 'transferencia_entrada', p_cantidad, p_costo,
            p_otra_bodega, left(p_motivo, 300), p_folio, auth.uid(), NOW());
    INSERT INTO stock_bodega (bodega_id, producto_id, cantidad, costo_promedio, ultimo_movimiento)
    VALUES (p_bodega_id, p_producto_id, v_cant0 + p_cantidad, p_costo, NOW())
    ON CONFLICT (bodega_id, producto_id) DO UPDATE SET cantidad = EXCLUDED.cantidad, ultimo_movimiento = NOW(), updated_at = NOW();
    INSERT INTO inventario_capas (producto_id, bodega_id, fecha_recepcion, folio_recepcion, cantidad_inicial, cantidad_disponible,
                                  unidad, costo_unitario, estado, created_by, created_at, updated_at)
    VALUES (p_producto_id, p_bodega_id, CURRENT_DATE, left(p_folio, 50), p_cantidad, p_cantidad,
            coalesce(v_unidad, 'unidad'), p_costo, 'disponible', auth.uid(), NOW(), NOW());
    v_cpp1 := coalesce(fn_bodega_sync_cpp(p_bodega_id, p_producto_id), p_costo);
    INSERT INTO kardex (id, bodega_id, producto_id, movimiento_id, fecha, tipo, cantidad_movimiento,
                        cantidad_anterior, cantidad_posterior, costo_unitario, costo_promedio_anterior,
                        costo_promedio_posterior, valor_movimiento, valor_stock_posterior)
    VALUES (gen_random_uuid(), p_bodega_id, p_producto_id, v_mov, NOW(), 'transferencia_entrada', p_cantidad,
            v_cant0, v_cant0 + p_cantidad, p_costo, v_cpp0, v_cpp1, p_cantidad * p_costo, (v_cant0 + p_cantidad) * v_cpp1);
END $$;
REVOKE ALL ON FUNCTION public.fn_bodega_entrada_transferencia(UUID, UUID, UUID, NUMERIC, NUMERIC, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- 4.2 Confirmar recepción en la faena (lo que llegó de verdad).
CREATE OR REPLACE FUNCTION public.rpc_bodega_envio_recibir(p_envio_id UUID, p_items JSONB, p_observacion TEXT, p_client_uuid UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_prev JSONB; v_env RECORD; v_it RECORD; v_rec NUMERIC; v_dif INT := 0; v_n INT := 0; v_res JSONB; v_origen TEXT;
BEGIN
    SELECT resultado INTO v_prev FROM bodega_operaciones WHERE client_uuid = p_client_uuid;
    IF v_prev IS NOT NULL THEN RETURN v_prev || jsonb_build_object('repetida', true); END IF;
    SELECT * INTO v_env FROM bodega_envios WHERE id = p_envio_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Envío no encontrado.'; END IF;
    IF NOT fn_bodega_puede_operar(v_env.bodega_destino_id) THEN RAISE EXCEPTION 'No tiene permiso para recibir en esta bodega.' USING ERRCODE = '42501'; END IF;
    IF v_env.estado <> 'en_camino' THEN RAISE EXCEPTION 'El envío % ya está %.', v_env.folio, replace(v_env.estado, '_', ' '); END IF;
    SELECT nombre INTO v_origen FROM bodegas WHERE id = v_env.bodega_origen_id;

    FOR v_it IN SELECT i.*, p.nombre FROM bodega_envio_items i JOIN productos p ON p.id = i.producto_id WHERE i.envio_id = p_envio_id LOOP
        SELECT (x->>'cantidad')::numeric INTO v_rec FROM jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) x
         WHERE (x->>'producto_id')::uuid = v_it.producto_id LIMIT 1;
        v_rec := coalesce(v_rec, v_it.cantidad_enviada);   -- lo no informado se da por recibido completo
        IF v_rec < 0 OR v_rec > v_it.cantidad_enviada THEN
            RAISE EXCEPTION '«%»: recibido % no puede ser mayor a lo enviado (%). Lo que sobra regístrelo en «Recibir».', v_it.nombre, v_rec, v_it.cantidad_enviada;
        END IF;
        UPDATE bodega_envio_items SET cantidad_recibida = v_rec WHERE id = v_it.id;
        IF v_rec > 0 THEN
            PERFORM fn_bodega_entrada_transferencia(v_env.bodega_destino_id, v_env.bodega_origen_id, v_it.producto_id,
                                                    v_rec, v_it.costo_unitario, v_env.folio, 'Recepción ' || v_env.folio || ' desde ' || v_origen);
        END IF;
        IF v_rec < v_it.cantidad_enviada THEN v_dif := v_dif + 1; END IF;
        v_n := v_n + 1;
    END LOOP;

    UPDATE bodega_envios SET estado = CASE WHEN v_dif > 0 THEN 'recibido_con_diferencias' ELSE 'recibido' END,
           recibido_por = auth.uid(), recibido_at = NOW(), observacion_recepcion = nullif(btrim(p_observacion), '')
     WHERE id = p_envio_id;
    v_res := jsonb_build_object('ok', true, 'folio', v_env.folio, 'items', v_n, 'con_diferencia', v_dif);
    INSERT INTO bodega_operaciones (client_uuid, bodega_id, tipo, resultado) VALUES (p_client_uuid, v_env.bodega_destino_id, 'recepcion_envio', v_res);
    RETURN v_res;
END $$;
GRANT EXECUTE ON FUNCTION public.rpc_bodega_envio_recibir(UUID, JSONB, TEXT, UUID) TO authenticated;

-- 4.3 Anular un envío que no ha llegado: vuelve todo a la bodega origen con su costo.
CREATE OR REPLACE FUNCTION public.rpc_bodega_envio_anular(p_envio_id UUID, p_motivo TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_env RECORD; v_it RECORD; v_n INT := 0;
BEGIN
    SELECT * INTO v_env FROM bodega_envios WHERE id = p_envio_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Envío no encontrado.'; END IF;
    IF NOT fn_bodega_puede_enviar(v_env.bodega_origen_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    IF v_env.estado <> 'en_camino' THEN RAISE EXCEPTION 'Solo se anula un envío en camino (este está %).', replace(v_env.estado, '_', ' '); END IF;
    IF length(btrim(coalesce(p_motivo, ''))) < 5 THEN RAISE EXCEPTION 'Indique por qué se anula.'; END IF;
    FOR v_it IN SELECT * FROM bodega_envio_items WHERE envio_id = p_envio_id LOOP
        PERFORM fn_bodega_entrada_transferencia(v_env.bodega_origen_id, v_env.bodega_destino_id, v_it.producto_id,
                                                v_it.cantidad_enviada, v_it.costo_unitario, 'ANULA-' || v_env.folio,
                                                'Anulación ' || v_env.folio || ': ' || btrim(p_motivo));
        v_n := v_n + 1;
    END LOOP;
    UPDATE bodega_envios SET estado = 'anulado', anulado_por = auth.uid(), anulado_at = NOW(),
           observacion = concat_ws(' · ', observacion, 'Anulado: ' || btrim(p_motivo))
     WHERE id = p_envio_id;
    RETURN jsonb_build_object('ok', true, 'folio', v_env.folio, 'items', v_n);
END $$;
GRANT EXECUTE ON FUNCTION public.rpc_bodega_envio_anular(UUID, TEXT) TO authenticated;

-- 4.4 Listar envíos de una bodega (como origen o destino).
CREATE OR REPLACE FUNCTION public.rpc_bodega_envios(p_bodega_id UUID, p_solo_en_camino BOOLEAN DEFAULT false)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF NOT (fn_bodega_puede_ver(p_bodega_id) OR fn_bodega_puede_enviar(p_bodega_id)) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    RETURN (SELECT coalesce(jsonb_agg(e ORDER BY (e->>'created_at') DESC), '[]'::jsonb) FROM (
        SELECT jsonb_build_object(
                 'id', en.id, 'folio', en.folio, 'estado', en.estado, 'guia', en.guia, 'observacion', en.observacion,
                 'created_at', en.created_at, 'recibido_at', en.recibido_at, 'observacion_recepcion', en.observacion_recepcion,
                 'origen', jsonb_build_object('id', bo.id, 'codigo', bo.codigo, 'nombre', bo.nombre),
                 'destino', jsonb_build_object('id', bd.id, 'codigo', bd.codigo, 'nombre', bd.nombre),
                 'creado_por', uc.nombre_completo, 'recibido_por', ur.nombre_completo,
                 'valor', (SELECT round(sum(i.cantidad_enviada * i.costo_unitario)) FROM bodega_envio_items i WHERE i.envio_id = en.id),
                 'items', (SELECT jsonb_agg(jsonb_build_object('producto_id', p.id, 'codigo', p.codigo, 'nombre', p.nombre,
                                  'unidad', p.unidad_medida, 'enviada', i.cantidad_enviada, 'recibida', i.cantidad_recibida,
                                  'costo_unitario', i.costo_unitario) ORDER BY p.nombre)
                             FROM bodega_envio_items i JOIN productos p ON p.id = i.producto_id WHERE i.envio_id = en.id)) AS e
          FROM bodega_envios en
          JOIN bodegas bo ON bo.id = en.bodega_origen_id
          JOIN bodegas bd ON bd.id = en.bodega_destino_id
          LEFT JOIN usuarios_perfil uc ON uc.id = en.creado_por
          LEFT JOIN usuarios_perfil ur ON ur.id = en.recibido_por
         WHERE (en.bodega_origen_id = p_bodega_id OR en.bodega_destino_id = p_bodega_id)
           AND (en.estado = 'en_camino' OR (NOT p_solo_en_camino AND en.created_at >= NOW() - interval '90 days'))) q);
END $$;
GRANT EXECUTE ON FUNCTION public.rpc_bodega_envios(UUID, BOOLEAN) TO authenticated;

-- 4.5 Sugerido de reposición: lo que falta para llegar al máximo (30 días) contando lo en camino.
CREATE OR REPLACE FUNCTION public.rpc_bodega_envio_sugerido(p_origen_id UUID, p_destino_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF NOT fn_bodega_puede_enviar(p_origen_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    RETURN (SELECT coalesce(jsonb_agg(x ORDER BY (x->>'urgente')::boolean DESC, x->>'nombre'), '[]'::jsonb) FROM (
        SELECT jsonb_build_object(
                 'producto_id', p.id, 'codigo', p.codigo, 'nombre', p.nombre, 'unidad', p.unidad_medida,
                 'stock_destino', coalesce(sd.cantidad, 0), 'en_camino', coalesce(tr.cant, 0),
                 'minimo', pr.minimo, 'maximo', coalesce(pr.maximo, pr.minimo * 2), 'consumo_diario', pr.consumo_diario,
                 'stock_origen', coalesce(so.cantidad, 0),
                 'sugerido', least(coalesce(so.cantidad, 0),
                                   ceil(coalesce(pr.maximo, pr.minimo * 2) - coalesce(sd.cantidad, 0) - coalesce(tr.cant, 0))),
                 'falta', ceil(coalesce(pr.maximo, pr.minimo * 2) - coalesce(sd.cantidad, 0) - coalesce(tr.cant, 0)),
                 'urgente', coalesce(sd.cantidad, 0) + coalesce(tr.cant, 0) <= pr.minimo) AS x
          FROM bodega_stock_parametros pr
          JOIN productos p ON p.id = pr.producto_id
          LEFT JOIN stock_bodega sd ON sd.bodega_id = p_destino_id AND sd.producto_id = pr.producto_id
          LEFT JOIN stock_bodega so ON so.bodega_id = p_origen_id AND so.producto_id = pr.producto_id
          LEFT JOIN LATERAL (SELECT sum(i.cantidad_enviada) cant FROM bodega_envio_items i JOIN bodega_envios e ON e.id = i.envio_id
                              WHERE e.bodega_destino_id = p_destino_id AND e.estado = 'en_camino' AND i.producto_id = pr.producto_id) tr ON true
         WHERE pr.bodega_id = p_destino_id AND pr.minimo > 0
           AND coalesce(sd.cantidad, 0) + coalesce(tr.cant, 0) < coalesce(pr.maximo, pr.minimo * 2)) q);
END $$;
GRANT EXECUTE ON FUNCTION public.rpc_bodega_envio_sugerido(UUID, UUID) TO authenticated;

-- ── 5. Datos: Franke = 15 días, CECO Softland de la faena, primer cálculo ───
UPDATE public.bodegas SET dias_minimo = 15 WHERE codigo = 'BOD-FRK-F01';
INSERT INTO public.bodega_cecos_consumo (bodega_id, codi_cc)
SELECT b.id, c.codigo
  FROM bodegas b, softland_cc c
 WHERE b.codigo = 'BOD-FRK-F01'
   AND (c.codigo IN ('FK-00-00', 'FK-FK-00', 'FK-FK-01', 'FK-FK-02')
        OR c.activo_id IN (SELECT id FROM activos WHERE patente IN ('HHWB-42', 'HHWB-44', 'LCSX-78', 'LLBP-96')))
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_r JSONB; v_bajo INT;
BEGIN
    v_r := fn_bodega_recalcular_minimos((SELECT id FROM bodegas WHERE codigo = 'BOD-FRK-F01'));
    SELECT count(*) INTO v_bajo FROM bodega_alertas_stock a JOIN bodegas b ON b.id = a.bodega_id
     WHERE b.codigo = 'BOD-FRK-F01' AND a.estado = 'abierta';
    RAISE NOTICE 'MIG712 mínimos Franke: % · alertas abiertas bajo mínimo: %', v_r, v_bajo;
    IF NOT (v_r->>'ok')::boolean THEN RAISE EXCEPTION 'MIG712: no se calcularon los mínimos (%)', v_r; END IF;
END $$;
