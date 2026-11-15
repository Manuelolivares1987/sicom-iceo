-- ============================================================================
-- MIG692 · Bodega de faena Franke: inventario con lector, salidas, mínimos por
--          bodega, alertas de stock bajo y combustible en el mismo panel
-- ----------------------------------------------------------------------------
-- Pedido de Manuel (15-11-2026): «control de bodega en Franke donde se
-- inventaree y se rebaje con una pistola el stock y lance alertas cuando llega
-- a un límite; el panel debe ver el stock de combustible y los despachos».
--
-- Decisiones:
--   * Bodega BOD-FRK-F01 (ya existía, vacía): agua, repuestos, EPP.
--   * Lector físico (actúa como teclado) + etiquetas SICOM con el código del
--     producto en Code128. Se busca por codigo_barras o por codigo.
--   * Operan: supervisores de turno de Franke + encargado de bodega (Gustavo).
--     Alerta de stock bajo a ellos + copia a Manuel.
--   * Salida: repuesto/filtro/lubricante → a un equipo (camión); el resto
--     (agua, EPP, ferretería, aseo) → a la operación (CECO FRK-OPER).
--   * Mínimo y máximo POR BODEGA (productos.stock_minimo es global y sirve a
--     Coquimbo; Franke necesita los suyos).
--   * Inventario: el supervisor cuenta con el lector y deja un conteo
--     «completado»; jefatura/bodega lo aprueba en /dashboard/inventario/conteo
--     (rpc_aprobar_conteo_inventario de siempre, con ajustes y kardex).
--   * El combustible de faena NO se toca (la varilla manda, MIG279): el panel
--     solo lo lee.
-- ============================================================================

-- ── 0. La bodega y su centro de costo ───────────────────────────────────────
UPDATE public.bodegas SET nombre = 'Bodega Faena Franke — Taltal (agua, repuestos, EPP)'
 WHERE codigo = 'BOD-FRK-F01';

INSERT INTO public.centros_costo (codigo, nombre, area, faena_id, observaciones)
SELECT 'FRK-OPER', 'Operación Franke — consumo general de faena', 'operaciones',
       '69202766-770b-4f81-ab86-35544fd3176e', 'MIG692: agua, EPP e insumos de la faena Franke'
 WHERE NOT EXISTS (SELECT 1 FROM public.centros_costo WHERE codigo = 'FRK-OPER');

-- Tipo de alerta nuevo para la campanita: conteo de bodega por aprobar.
ALTER TABLE public.alertas DROP CONSTRAINT IF EXISTS chk_alertas_tipo;
ALTER TABLE public.alertas ADD CONSTRAINT chk_alertas_tipo CHECK (tipo::text = ANY (ARRAY[
    'vencimiento', 'stock_minimo', 'ot_vencida', 'incumplimiento', 'bloqueante', 'antiguedad_vehiculo',
    'semep_vencido', 'fatiga_conductor', 'rt_por_vencer', 'hermeticidad_vencida', 'sec_no_vigente',
    'sensor_fuga', 'accidente_no_reportado', 'jornada_excedida', 'pts_faltante', 'disponibilidad_vencida',
    'gps_sin_senal', 'no_conformidad', 'recurso_solicitado', 'recurso_por_comprar', 'recurso_recibido',
    'vale_emitido', 'doc_por_vencer', 'doc_vencido', 'doc_vencidos_equipo', 'doc_sin_fecha',
    'plan_papeles_equipo', 'preventiva_horas', 'conteo_por_aprobar']));

-- ── 1. Responsables de la bodega ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bodega_responsables (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bodega_id      UUID NOT NULL REFERENCES public.bodegas(id) ON DELETE CASCADE,
    usuario_id     UUID REFERENCES public.usuarios_perfil(id) ON DELETE SET NULL,
    nombre         TEXT,
    email          TEXT,
    puede_operar   BOOLEAN NOT NULL DEFAULT true,   -- sacar, recibir, contar, fijar mínimos
    recibe_alertas BOOLEAN NOT NULL DEFAULT true,
    tipo_correo    TEXT NOT NULL DEFAULT 'para' CHECK (tipo_correo IN ('para', 'cc')),
    activo         BOOLEAN NOT NULL DEFAULT true,
    UNIQUE (bodega_id, email)
);
ALTER TABLE public.bodega_responsables ENABLE ROW LEVEL SECURITY;

INSERT INTO public.bodega_responsables (bodega_id, usuario_id, nombre, email, puede_operar, recibe_alertas, tipo_correo)
SELECT b.id, u.id, x.nombre, x.email, x.operar, true, x.tipo
  FROM public.bodegas b
  CROSS JOIN (VALUES
      ('mespinosa@pillado.cl',  'Marcelo Espinosa Ríos (supervisor turno B)', 'mespinosa@pillado.cl', true,  'para'),
      ('earqueros@pillado.cl',  'Edison Arqueros (supervisor turno A, R)',    'earqueros@pillado.cl', true,  'para'),
      ('jsimon@pillado.cl',     'Jacinto Simón Saldaña (supervisor turno A)', 'jsimon@pillado.cl',    true,  'para'),
      ('bodegacoq@pillado.cl',  'Gustavo (encargado de bodega)',              'bodegacentral@pilladoempresas.cl', true, 'para'),
      (NULL,                    'Manuel Olivares',                            'manuel.olivares@pilladoempresas.cl', false, 'cc')
  ) AS x(login, nombre, email, operar, tipo)
  LEFT JOIN public.usuarios_perfil u ON u.email = x.login
 WHERE b.codigo = 'BOD-FRK-F01'
ON CONFLICT (bodega_id, email) DO NOTHING;

-- Ver: jefatura/bodega en general, o responsable de esa bodega.
CREATE OR REPLACE FUNCTION public.fn_bodega_puede_ver(p_bodega_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT auth.uid() IS NOT NULL AND (
        EXISTS (SELECT 1 FROM usuarios_perfil u WHERE u.id = auth.uid()
                  AND u.rol::text IN ('administrador', 'gerencia', 'subgerente_operaciones', 'jefe_operaciones',
                                      'jefe_mantenimiento', 'bodeguero', 'operador_abastecimiento'))
        OR EXISTS (SELECT 1 FROM bodega_responsables r
                    WHERE r.bodega_id = p_bodega_id AND r.usuario_id = auth.uid() AND r.activo))
$$;

-- Operar: administración/bodega, o responsable con puede_operar.
CREATE OR REPLACE FUNCTION public.fn_bodega_puede_operar(p_bodega_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT auth.uid() IS NOT NULL AND (
        EXISTS (SELECT 1 FROM usuarios_perfil u WHERE u.id = auth.uid()
                  AND u.rol::text IN ('administrador', 'subgerente_operaciones', 'jefe_operaciones', 'bodeguero'))
        OR EXISTS (SELECT 1 FROM bodega_responsables r
                    WHERE r.bodega_id = p_bodega_id AND r.usuario_id = auth.uid() AND r.activo AND r.puede_operar))
$$;

DROP POLICY IF EXISTS bodega_resp_ver ON public.bodega_responsables;
CREATE POLICY bodega_resp_ver ON public.bodega_responsables
    FOR SELECT TO authenticated USING (public.fn_bodega_puede_ver(bodega_id));

-- ── 2. Mínimo y máximo por bodega ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bodega_stock_parametros (
    bodega_id   UUID NOT NULL REFERENCES public.bodegas(id) ON DELETE CASCADE,
    producto_id UUID NOT NULL REFERENCES public.productos(id) ON DELETE CASCADE,
    minimo      NUMERIC(12,3) NOT NULL DEFAULT 0 CHECK (minimo >= 0),
    maximo      NUMERIC(12,3) CHECK (maximo IS NULL OR maximo >= minimo),
    updated_by  UUID DEFAULT auth.uid(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (bodega_id, producto_id)
);
ALTER TABLE public.bodega_stock_parametros ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bodega_param_ver ON public.bodega_stock_parametros;
CREATE POLICY bodega_param_ver ON public.bodega_stock_parametros
    FOR SELECT TO authenticated USING (public.fn_bodega_puede_ver(bodega_id));

-- ── 3. Alertas de stock bajo ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bodega_alertas_stock (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bodega_id     UUID NOT NULL REFERENCES public.bodegas(id) ON DELETE CASCADE,
    producto_id   UUID NOT NULL REFERENCES public.productos(id) ON DELETE CASCADE,
    stock         NUMERIC(12,3) NOT NULL,
    minimo        NUMERIC(12,3) NOT NULL,
    estado        TEXT NOT NULL DEFAULT 'abierta' CHECK (estado IN ('abierta', 'resuelta')),
    creada_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notificada_at TIMESTAMPTZ,
    resuelta_at   TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_bodega_alerta_abierta
    ON public.bodega_alertas_stock (bodega_id, producto_id) WHERE estado = 'abierta';
ALTER TABLE public.bodega_alertas_stock ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bodega_alerta_ver ON public.bodega_alertas_stock;
CREATE POLICY bodega_alerta_ver ON public.bodega_alertas_stock
    FOR SELECT TO authenticated USING (public.fn_bodega_puede_ver(bodega_id));

-- Evalúa un producto en una bodega con mínimo propio: abre, actualiza o resuelve.
CREATE OR REPLACE FUNCTION public.fn_bodega_evaluar_alerta(p_bodega_id UUID, p_producto_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_min   NUMERIC;
    v_stock NUMERIC;
    v_nuevo UUID;
    v_prod  TEXT;
    v_bod   TEXT;
BEGIN
    SELECT minimo INTO v_min FROM bodega_stock_parametros
     WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id;
    IF v_min IS NULL OR v_min <= 0 THEN
        UPDATE bodega_alertas_stock SET estado = 'resuelta', resuelta_at = NOW()
         WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id AND estado = 'abierta';
        RETURN;
    END IF;
    SELECT coalesce(sum(cantidad), 0) INTO v_stock FROM stock_bodega
     WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id;

    IF v_stock <= v_min THEN
        INSERT INTO bodega_alertas_stock (bodega_id, producto_id, stock, minimo)
        VALUES (p_bodega_id, p_producto_id, v_stock, v_min)
        ON CONFLICT (bodega_id, producto_id) WHERE estado = 'abierta'
        DO UPDATE SET stock = EXCLUDED.stock, minimo = EXCLUDED.minimo
        RETURNING CASE WHEN xmax = 0 THEN id END INTO v_nuevo;
        -- Campanita para los responsables con cuenta, solo cuando la alerta nace.
        IF v_nuevo IS NOT NULL THEN
            SELECT nombre INTO v_prod FROM productos WHERE id = p_producto_id;
            SELECT nombre INTO v_bod FROM bodegas WHERE id = p_bodega_id;
            INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id, destinatario_id, requiere_accion)
            SELECT 'stock_minimo', 'Stock bajo en ' || split_part(v_bod, ' (', 1) || ': ' || v_prod,
                   'Quedan ' || trim(to_char(v_stock, 'FM999999990.###')) || '; mínimo ' ||
                   trim(to_char(v_min, 'FM999999990.###')) || '. Hay que reponer.',
                   CASE WHEN v_stock <= 0 THEN 'critical' ELSE 'warning' END, 'producto', p_producto_id, r.usuario_id, true
              FROM bodega_responsables r
             WHERE r.bodega_id = p_bodega_id AND r.activo AND r.recibe_alertas AND r.usuario_id IS NOT NULL;
        END IF;
    ELSE
        UPDATE bodega_alertas_stock SET estado = 'resuelta', resuelta_at = NOW(), stock = v_stock
         WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id AND estado = 'abierta';
    END IF;
END $$;
REVOKE ALL ON FUNCTION public.fn_bodega_evaluar_alerta(UUID, UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_trg_bodega_stock_alerta()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM bodega_stock_parametros p
                WHERE p.bodega_id = NEW.bodega_id AND p.producto_id = NEW.producto_id) THEN
        PERFORM fn_bodega_evaluar_alerta(NEW.bodega_id, NEW.producto_id);
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_bodega_stock_alerta ON public.stock_bodega;
CREATE TRIGGER trg_bodega_stock_alerta AFTER INSERT OR UPDATE OF cantidad ON public.stock_bodega
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_bodega_stock_alerta();

CREATE OR REPLACE FUNCTION public.fn_trg_bodega_param_alerta()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    PERFORM fn_bodega_evaluar_alerta(NEW.bodega_id, NEW.producto_id);
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_bodega_param_alerta ON public.bodega_stock_parametros;
CREATE TRIGGER trg_bodega_param_alerta AFTER INSERT OR UPDATE ON public.bodega_stock_parametros
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_bodega_param_alerta();

-- ── 4. Operaciones idempotentes (el lector y la red de faena repiten) ───────
CREATE TABLE IF NOT EXISTS public.bodega_operaciones (
    client_uuid UUID PRIMARY KEY,
    bodega_id   UUID NOT NULL REFERENCES public.bodegas(id),
    tipo        TEXT NOT NULL CHECK (tipo IN ('salida', 'ingreso', 'conteo')),
    resultado   JSONB,
    created_by  UUID DEFAULT auth.uid(),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.bodega_operaciones ENABLE ROW LEVEL SECURITY;

-- ── 5. Buscar por lector o por texto ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_bodega_faena_buscar(p_bodega_id UUID, p_texto TEXT)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_t TEXT := btrim(coalesce(p_texto, ''));
BEGIN
    IF NOT fn_bodega_puede_ver(p_bodega_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    IF length(v_t) < 2 THEN RETURN '[]'::jsonb; END IF;
    RETURN (
        SELECT coalesce(jsonb_agg(x ORDER BY exacto DESC, nombre), '[]'::jsonb) FROM (
            SELECT jsonb_build_object(
                     'producto_id', p.id, 'codigo', p.codigo, 'codigo_barras', p.codigo_barras,
                     'nombre', p.nombre, 'categoria', p.categoria, 'unidad', p.unidad_medida,
                     'stock', coalesce(s.cantidad, 0), 'minimo', pr.minimo, 'maximo', pr.maximo,
                     'exige_equipo', p.categoria IN ('repuesto', 'filtro', 'lubricante'),
                     'exacto', upper(p.codigo) = upper(v_t) OR upper(p.codigo_barras) = upper(v_t)) AS x,
                   (upper(p.codigo) = upper(v_t) OR upper(p.codigo_barras) = upper(v_t)) AS exacto, p.nombre
              FROM productos p
              LEFT JOIN stock_bodega s ON s.producto_id = p.id AND s.bodega_id = p_bodega_id
              LEFT JOIN bodega_stock_parametros pr ON pr.producto_id = p.id AND pr.bodega_id = p_bodega_id
             WHERE upper(p.codigo) = upper(v_t) OR upper(p.codigo_barras) = upper(v_t)
                OR (length(v_t) >= 3 AND (p.nombre ILIKE '%' || v_t || '%' OR p.codigo ILIKE v_t || '%'))
             ORDER BY 2 DESC, (s.cantidad IS NULL), p.nombre
             LIMIT 25) q);
END $$;
REVOKE ALL ON FUNCTION public.rpc_bodega_faena_buscar(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_bodega_faena_buscar(UUID, TEXT) TO authenticated;

-- ── 6. Salida con lector ────────────────────────────────────────────────────
-- p_items: [{producto_id, cantidad}]. p_activo_id obligatorio si algún ítem es
-- repuesto/filtro/lubricante. Todo o nada.
CREATE OR REPLACE FUNCTION public.rpc_bodega_faena_salida(
    p_bodega_id UUID, p_items JSONB, p_activo_id UUID, p_motivo TEXT, p_entregado_a TEXT, p_client_uuid UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_prev   JSONB;
    v_ceco   UUID;
    v_it     RECORD;
    v_stock  RECORD;
    v_mov    UUID;
    v_nuevo  NUMERIC;
    v_total  NUMERIC := 0;
    v_n      INT := 0;
    v_bajo   JSONB := '[]'::jsonb;
    v_min    NUMERIC;
    v_res    JSONB;
BEGIN
    IF NOT fn_bodega_puede_operar(p_bodega_id) THEN
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
        -- costo_total es columna generada (cantidad × costo_unitario).
        INSERT INTO movimientos_inventario (id, bodega_id, producto_id, tipo, cantidad, costo_unitario,
                                            activo_id, ceco_id, motivo, documento_referencia, usuario_id, created_at)
        VALUES (v_mov, p_bodega_id, v_it.producto_id, 'salida', v_it.cantidad, coalesce(v_stock.costo_promedio, 0),
                p_activo_id, v_ceco,
                left(concat_ws(' · ', nullif(btrim(p_motivo), ''),
                               CASE WHEN nullif(btrim(p_entregado_a), '') IS NOT NULL THEN 'entregado a ' || btrim(p_entregado_a) END), 500),
                'LECTOR-' || p_client_uuid::text, auth.uid(), NOW());
        UPDATE stock_bodega SET cantidad = v_nuevo, ultimo_movimiento = NOW(), updated_at = NOW()
         WHERE bodega_id = p_bodega_id AND producto_id = v_it.producto_id;
        INSERT INTO kardex (id, bodega_id, producto_id, movimiento_id, fecha, tipo, cantidad_movimiento,
                            cantidad_anterior, cantidad_posterior, costo_unitario, costo_promedio_anterior,
                            costo_promedio_posterior, valor_movimiento, valor_stock_posterior)
        VALUES (gen_random_uuid(), p_bodega_id, v_it.producto_id, v_mov, NOW(), 'salida', v_it.cantidad,
                v_stock.cantidad, v_nuevo, coalesce(v_stock.costo_promedio, 0), v_stock.costo_promedio,
                v_stock.costo_promedio, v_it.cantidad * coalesce(v_stock.costo_promedio, 0),
                v_nuevo * coalesce(v_stock.costo_promedio, 0));
        v_total := v_total + v_it.cantidad * coalesce(v_stock.costo_promedio, 0);
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
END $$;
REVOKE ALL ON FUNCTION public.rpc_bodega_faena_salida(UUID, JSONB, UUID, TEXT, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_bodega_faena_salida(UUID, JSONB, UUID, TEXT, TEXT, UUID) TO authenticated;

-- ── 7. Recepción (lo que llega a la faena) ──────────────────────────────────
-- Costo: el promedio de la bodega de Coquimbo si existe; si no, el del maestro.
CREATE OR REPLACE FUNCTION public.rpc_bodega_faena_ingreso(
    p_bodega_id UUID, p_items JSONB, p_origen TEXT, p_documento TEXT, p_client_uuid UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_prev  JSONB;
    v_it    RECORD;
    v_stock RECORD;
    v_costo NUMERIC;
    v_mov   UUID;
    v_cant0 NUMERIC;
    v_cpp0  NUMERIC;
    v_cant1 NUMERIC;
    v_cpp1  NUMERIC;
    v_n     INT := 0;
    v_res   JSONB;
BEGIN
    IF NOT fn_bodega_puede_operar(p_bodega_id) THEN
        RAISE EXCEPTION 'No tiene permiso para recibir en esta bodega.' USING ERRCODE = '42501';
    END IF;
    SELECT resultado INTO v_prev FROM bodega_operaciones WHERE client_uuid = p_client_uuid;
    IF v_prev IS NOT NULL THEN RETURN v_prev || jsonb_build_object('repetida', true); END IF;
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'No hay productos escaneados.'; END IF;
    IF length(btrim(coalesce(p_origen, ''))) < 3 THEN RAISE EXCEPTION 'Indique de dónde viene (ej. envío desde Coquimbo, compra local).'; END IF;

    FOR v_it IN
        SELECT x.producto_id, x.cantidad, p.nombre, p.costo_unitario_actual
          FROM jsonb_to_recordset(p_items) AS x(producto_id UUID, cantidad NUMERIC)
          JOIN productos p ON p.id = x.producto_id
    LOOP
        IF v_it.cantidad IS NULL OR v_it.cantidad <= 0 THEN RAISE EXCEPTION 'Cantidad inválida para «%».', v_it.nombre; END IF;
        SELECT nullif(s.costo_promedio, 0) INTO v_costo FROM stock_bodega s JOIN bodegas b ON b.id = s.bodega_id
         WHERE b.codigo = 'BOD-CQB-F01' AND s.producto_id = v_it.producto_id;
        v_costo := coalesce(v_costo, nullif(v_it.costo_unitario_actual, 0), 0);
        SELECT cantidad, costo_promedio INTO v_stock FROM stock_bodega
         WHERE bodega_id = p_bodega_id AND producto_id = v_it.producto_id FOR UPDATE;
        v_cant0 := coalesce(v_stock.cantidad, 0);
        v_cpp0 := coalesce(v_stock.costo_promedio, 0);
        v_cant1 := v_cant0 + v_it.cantidad;
        v_cpp1 := CASE WHEN v_cant1 > 0 THEN (v_cant0 * v_cpp0 + v_it.cantidad * v_costo) / v_cant1 ELSE v_costo END;
        v_mov := gen_random_uuid();
        INSERT INTO movimientos_inventario (id, bodega_id, producto_id, tipo, cantidad, costo_unitario,
                                            motivo, documento_referencia, usuario_id, created_at)
        VALUES (v_mov, p_bodega_id, v_it.producto_id, 'entrada', v_it.cantidad, v_costo,
                left(btrim(p_origen), 300), coalesce(nullif(btrim(p_documento), ''), 'LECTOR-' || p_client_uuid::text),
                auth.uid(), NOW());
        INSERT INTO stock_bodega (bodega_id, producto_id, cantidad, costo_promedio, ultimo_movimiento)
        VALUES (p_bodega_id, v_it.producto_id, v_cant1, v_cpp1, NOW())
        ON CONFLICT (bodega_id, producto_id) DO UPDATE
           SET cantidad = EXCLUDED.cantidad, costo_promedio = EXCLUDED.costo_promedio,
               ultimo_movimiento = NOW(), updated_at = NOW();
        INSERT INTO kardex (id, bodega_id, producto_id, movimiento_id, fecha, tipo, cantidad_movimiento,
                            cantidad_anterior, cantidad_posterior, costo_unitario, costo_promedio_anterior,
                            costo_promedio_posterior, valor_movimiento, valor_stock_posterior)
        VALUES (gen_random_uuid(), p_bodega_id, v_it.producto_id, v_mov, NOW(), 'entrada', v_it.cantidad,
                v_cant0, v_cant1, v_costo, v_cpp0, v_cpp1, v_it.cantidad * v_costo, v_cant1 * v_cpp1);
        v_n := v_n + 1;
    END LOOP;
    IF v_n <> jsonb_array_length(p_items) THEN RAISE EXCEPTION 'Algún producto escaneado no existe.'; END IF;
    v_res := jsonb_build_object('ok', true, 'items', v_n);
    INSERT INTO bodega_operaciones (client_uuid, bodega_id, tipo, resultado) VALUES (p_client_uuid, p_bodega_id, 'ingreso', v_res);
    RETURN v_res;
END $$;
REVOKE ALL ON FUNCTION public.rpc_bodega_faena_ingreso(UUID, JSONB, TEXT, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_bodega_faena_ingreso(UUID, JSONB, TEXT, TEXT, UUID) TO authenticated;

-- ── 8. Conteo físico con lector → queda para aprobación ─────────────────────
-- p_items: [{producto_id, cantidad}] (cantidad = lo que hay físicamente).
-- p_completo: true = inventario general (lo NO escaneado se cuenta como 0).
CREATE OR REPLACE FUNCTION public.rpc_bodega_faena_conteo(
    p_bodega_id UUID, p_items JSONB, p_completo BOOLEAN, p_observacion TEXT, p_client_uuid UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_prev   JSONB;
    v_conteo UUID;
    v_n      INT;
    v_dif    INT;
    v_res    JSONB;
BEGIN
    IF NOT fn_bodega_puede_operar(p_bodega_id) THEN
        RAISE EXCEPTION 'No tiene permiso para contar esta bodega.' USING ERRCODE = '42501';
    END IF;
    SELECT resultado INTO v_prev FROM bodega_operaciones WHERE client_uuid = p_client_uuid;
    IF v_prev IS NOT NULL THEN RETURN v_prev || jsonb_build_object('repetida', true); END IF;
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN RAISE EXCEPTION 'No hay productos contados.'; END IF;

    INSERT INTO conteos_inventario (bodega_id, tipo, fecha_inicio, fecha_fin, estado, responsable_id, observaciones, created_by)
    VALUES (p_bodega_id, CASE WHEN p_completo THEN 'general' ELSE 'selectivo' END::tipo_conteo_enum, NOW(), NOW(),
            'completado', auth.uid(), left(concat_ws(' · ', 'Conteo con lector (MIG692)', nullif(btrim(p_observacion), '')), 500),
            auth.uid())
    RETURNING id INTO v_conteo;

    WITH f AS (
        SELECT x.producto_id, sum(x.cantidad) AS fisico
          FROM jsonb_to_recordset(p_items) AS x(producto_id UUID, cantidad NUMERIC)
         WHERE x.cantidad >= 0 GROUP BY 1
    ), todos AS (
        SELECT f.producto_id, f.fisico FROM f
        UNION ALL
        SELECT s.producto_id, 0 FROM stock_bodega s
         WHERE p_completo AND s.bodega_id = p_bodega_id AND s.cantidad <> 0
           AND s.producto_id NOT IN (SELECT producto_id FROM f)
    )
    -- diferencia es columna generada (físico − sistema).
    INSERT INTO conteo_detalle (conteo_id, producto_id, stock_sistema, stock_fisico, diferencia_valorizada, ajuste_aplicado)
    SELECT v_conteo, t.producto_id, coalesce(s.cantidad, 0), t.fisico,
           (t.fisico - coalesce(s.cantidad, 0)) * coalesce(nullif(s.costo_promedio, 0), p.costo_unitario_actual, 0), false
      FROM todos t JOIN productos p ON p.id = t.producto_id
      LEFT JOIN stock_bodega s ON s.bodega_id = p_bodega_id AND s.producto_id = t.producto_id;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    SELECT count(*) INTO v_dif FROM conteo_detalle WHERE conteo_id = v_conteo AND diferencia <> 0;

    -- Aviso a quien aprueba (administración y bodega con cuenta).
    INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id, destinatario_id, requiere_accion)
    SELECT 'conteo_por_aprobar', 'Conteo de bodega Franke por aprobar',
           v_n || ' productos contados, ' || v_dif || ' con diferencia. Apruébelo en Inventario → Conteo.',
           'info', 'conteo_inventario', v_conteo, u.id, true
      FROM usuarios_perfil u
     WHERE u.activo AND (u.rol::text = 'administrador' OR u.email = 'bodegacoq@pillado.cl');

    v_res := jsonb_build_object('ok', true, 'conteo_id', v_conteo, 'productos', v_n, 'con_diferencia', v_dif);
    INSERT INTO bodega_operaciones (client_uuid, bodega_id, tipo, resultado) VALUES (p_client_uuid, p_bodega_id, 'conteo', v_res);
    RETURN v_res;
END $$;
REVOKE ALL ON FUNCTION public.rpc_bodega_faena_conteo(UUID, JSONB, BOOLEAN, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_bodega_faena_conteo(UUID, JSONB, BOOLEAN, TEXT, UUID) TO authenticated;

-- ── 9. Mínimos y productos nuevos ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_bodega_set_parametro(p_bodega_id UUID, p_producto_id UUID, p_minimo NUMERIC, p_maximo NUMERIC)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF NOT fn_bodega_puede_operar(p_bodega_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    IF p_minimo IS NULL OR p_minimo < 0 THEN RAISE EXCEPTION 'El mínimo debe ser 0 o más.'; END IF;
    IF p_maximo IS NOT NULL AND p_maximo < p_minimo THEN RAISE EXCEPTION 'El máximo no puede ser menor que el mínimo.'; END IF;
    INSERT INTO bodega_stock_parametros (bodega_id, producto_id, minimo, maximo, updated_by, updated_at)
    VALUES (p_bodega_id, p_producto_id, p_minimo, p_maximo, auth.uid(), NOW())
    ON CONFLICT (bodega_id, producto_id) DO UPDATE
       SET minimo = EXCLUDED.minimo, maximo = EXCLUDED.maximo, updated_by = auth.uid(), updated_at = NOW();
END $$;
REVOKE ALL ON FUNCTION public.rpc_bodega_set_parametro(UUID, UUID, NUMERIC, NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_bodega_set_parametro(UUID, UUID, NUMERIC, NUMERIC) TO authenticated;

-- Producto que no está en el maestro (ej. un bidón de agua de 20 L): código FRK-0001…
CREATE OR REPLACE FUNCTION public.rpc_bodega_faena_producto_nuevo(
    p_bodega_id UUID, p_nombre TEXT, p_categoria TEXT, p_unidad TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_cod TEXT; v_id UUID;
BEGIN
    IF NOT fn_bodega_puede_operar(p_bodega_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    IF length(btrim(coalesce(p_nombre, ''))) < 4 THEN RAISE EXCEPTION 'Escriba el nombre del producto.'; END IF;
    IF p_categoria NOT IN ('repuesto', 'filtro', 'lubricante', 'ferreteria', 'implementos_de_seguridad',
                           'implementos_de_aseo_y_fungibles', 'articulos_de_oficina') THEN
        RAISE EXCEPTION 'Categoría no válida.';
    END IF;
    IF EXISTS (SELECT 1 FROM productos WHERE upper(btrim(nombre)) = upper(btrim(p_nombre))) THEN
        RAISE EXCEPTION 'Ya existe un producto con ese nombre: búsquelo por nombre.';
    END IF;
    SELECT 'FRK-' || lpad((coalesce(max(substring(codigo FROM 5)::int), 0) + 1)::text, 4, '0') INTO v_cod
      FROM productos WHERE codigo ~ '^FRK-[0-9]{4}$';
    INSERT INTO productos (codigo, nombre, categoria, unidad_medida, stock_minimo, created_by)
    VALUES (v_cod, upper(btrim(p_nombre)), p_categoria, coalesce(nullif(btrim(p_unidad), ''), 'un'), 0, auth.uid())
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('producto_id', v_id, 'codigo', v_cod);
END $$;
REVOKE ALL ON FUNCTION public.rpc_bodega_faena_producto_nuevo(UUID, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_bodega_faena_producto_nuevo(UUID, TEXT, TEXT, TEXT) TO authenticated;

-- ── 10. Panel: stock, movimientos y combustible de la faena ─────────────────
CREATE OR REPLACE FUNCTION public.rpc_bodega_panel(p_bodega_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_faena UUID;
BEGIN
    IF NOT fn_bodega_puede_ver(p_bodega_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    SELECT faena_id INTO v_faena FROM bodegas WHERE id = p_bodega_id;
    RETURN jsonb_build_object(
        'bodega', (SELECT jsonb_build_object('id', id, 'codigo', codigo, 'nombre', nombre, 'faena_id', faena_id)
                     FROM bodegas WHERE id = p_bodega_id),
        'puede_operar', fn_bodega_puede_operar(p_bodega_id),
        'stock', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                     'producto_id', p.id, 'codigo', p.codigo, 'nombre', p.nombre, 'categoria', p.categoria,
                     'unidad', p.unidad_medida, 'stock', coalesce(s.cantidad, 0),
                     'costo', s.costo_promedio, 'valor', round(coalesce(s.cantidad, 0) * coalesce(s.costo_promedio, 0)),
                     'minimo', pr.minimo, 'maximo', pr.maximo,
                     'estado', CASE WHEN pr.minimo IS NULL OR pr.minimo = 0 THEN 'sin_minimo'
                                    WHEN coalesce(s.cantidad, 0) <= 0 THEN 'agotado'
                                    WHEN coalesce(s.cantidad, 0) <= pr.minimo THEN 'bajo'
                                    ELSE 'ok' END,
                     'ultimo_movimiento', s.ultimo_movimiento) ORDER BY p.nombre), '[]'::jsonb)
                    FROM productos p
                    LEFT JOIN stock_bodega s ON s.producto_id = p.id AND s.bodega_id = p_bodega_id
                    LEFT JOIN bodega_stock_parametros pr ON pr.producto_id = p.id AND pr.bodega_id = p_bodega_id
                   WHERE s.producto_id IS NOT NULL OR pr.producto_id IS NOT NULL),
        'movimientos', (SELECT coalesce(jsonb_agg(m ORDER BY m->>'fecha' DESC), '[]'::jsonb) FROM (
                    SELECT jsonb_build_object('fecha', mi.created_at, 'tipo', mi.tipo, 'producto', p.nombre,
                             'codigo', p.codigo, 'cantidad', mi.cantidad, 'unidad', p.unidad_medida,
                             'equipo', a.patente, 'ceco', cc.codigo, 'motivo', mi.motivo,
                             'usuario', u.nombre_completo, 'valor', round(coalesce(mi.costo_total, mi.cantidad * mi.costo_unitario))) AS m
                      FROM movimientos_inventario mi JOIN productos p ON p.id = mi.producto_id
                      LEFT JOIN activos a ON a.id = mi.activo_id
                      LEFT JOIN centros_costo cc ON cc.id = mi.ceco_id
                      LEFT JOIN usuarios_perfil u ON u.id = mi.usuario_id
                     WHERE mi.bodega_id = p_bodega_id AND mi.created_at > NOW() - interval '60 days'
                     ORDER BY mi.created_at DESC LIMIT 300) q),
        'alertas', (SELECT coalesce(jsonb_agg(jsonb_build_object('producto', p.nombre, 'codigo', p.codigo,
                       'stock', a.stock, 'minimo', a.minimo, 'desde', a.creada_at, 'notificada', a.notificada_at)
                       ORDER BY a.creada_at), '[]'::jsonb)
                      FROM bodega_alertas_stock a JOIN productos p ON p.id = a.producto_id
                     WHERE a.bodega_id = p_bodega_id AND a.estado = 'abierta'),
        'conteos_por_aprobar', (SELECT count(*) FROM conteos_inventario
                                 WHERE bodega_id = p_bodega_id AND estado = 'completado'),
        'equipos', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'patente', a.patente, 'tipo', a.tipo)
                       ORDER BY a.patente), '[]'::jsonb)
                      FROM activos a WHERE a.patente IN ('HHWB-44', 'LCSX-78', 'HHWB-42', 'LLBP-96')),
        'combustible', CASE WHEN v_faena IS NULL THEN NULL ELSE jsonb_build_object(
            'estanques', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                             'codigo', e.codigo, 'nombre', e.nombre, 'patente', e.patente, 'capacidad', e.capacidad_lt,
                             'stock', round(e.stock_teorico_lt), 'llenado_pct', e.llenado_pct, 'estimable', e.estimable,
                             'medido_desde', e.medido_desde) ORDER BY e.orden_cierre NULLS LAST, e.codigo), '[]'::jsonb)
                            FROM v_comb_faena_estanque_ahora e WHERE e.faena_id = v_faena AND e.activo),
            'despachos', (SELECT coalesce(jsonb_agg(d ORDER BY d->>'fecha' DESC, d->>'hora' DESC), '[]'::jsonb) FROM (
                             SELECT jsonb_build_object('fecha', x.fecha, 'hora', x.hora, 'turno', x.turno,
                                      'camion', x.camion_patente, 'equipo', coalesce(a.patente, x.equipo_texto),
                                      'litros', x.litros, 'operador', x.operador_nombre, 'folio', x.folio_ticket,
                                      'tipo', x.tipo_movimiento, 'ubicacion', x.ubicacion_texto) AS d
                               FROM combustible_faena_despachos x LEFT JOIN activos a ON a.id = x.equipo_id
                              WHERE x.faena_id = v_faena AND NOT coalesce(x.anulado, false)
                                AND x.fecha > (NOW() AT TIME ZONE 'America/Santiago')::date - 30
                              ORDER BY x.fecha DESC, x.hora DESC NULLS LAST LIMIT 300) q),
            'litros_30d', (SELECT round(coalesce(sum(litros), 0)) FROM combustible_faena_despachos x
                            WHERE x.faena_id = v_faena AND NOT coalesce(x.anulado, false)
                              AND x.fecha > (NOW() AT TIME ZONE 'America/Santiago')::date - 30
                              AND coalesce(x.tipo_movimiento, 'despacho') = 'despacho'))
        END);
END $$;
REVOKE ALL ON FUNCTION public.rpc_bodega_panel(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_bodega_panel(UUID) TO authenticated;

-- ── 11. Correo de stock bajo (cron cada 15 min, solo lo nuevo) ──────────────
CREATE OR REPLACE FUNCTION public.fn_bodega_alertas_cron(p_secreto TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501';
    END IF;
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
END $$;
REVOKE ALL ON FUNCTION public.fn_bodega_alertas_cron(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_bodega_alertas_cron(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_bodega_alertas_marcar_cron(p_secreto TEXT, p_ids UUID[])
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501';
    END IF;
    UPDATE bodega_alertas_stock SET notificada_at = NOW() WHERE id = ANY(p_ids) AND notificada_at IS NULL;
END $$;
REVOKE ALL ON FUNCTION public.fn_bodega_alertas_marcar_cron(TEXT, UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_bodega_alertas_marcar_cron(TEXT, UUID[]) TO anon, authenticated;

DO $$
DECLARE v_cmd TEXT;
BEGIN
    SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'documentos-flota-diario';
    IF v_cmd IS NULL OR position('/api/notificaciones/documentos-flota/' IN v_cmd) = 0 THEN
        RAISE EXCEPTION 'No encuentro el cron documentos-flota-diario para copiar su configuración.';
    END IF;
    PERFORM cron.unschedule(jobname) FROM cron.job WHERE jobname = 'bodega-stock-bajo';
    PERFORM cron.schedule('bodega-stock-bajo', '*/15 * * * *',
        replace(v_cmd, '/api/notificaciones/documentos-flota/', '/api/notificaciones/bodega-stock/'));
END $$;

SELECT 'MIG692 OK' AS resultado;
