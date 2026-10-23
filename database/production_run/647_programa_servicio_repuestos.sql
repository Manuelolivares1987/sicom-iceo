-- MIG647 · Programa de servicio por modelo: qué se hace en cada servicio y con qué repuestos
-- ============================================================================
-- 23-10, Manuel: el servicio va CADA 300 h (no las 394 h de Volvo: +31 % de
-- intervalo es demasiado), pero lo que se hace en cada uno sigue la pauta
-- Volvo. Volvo cuenta servicios: el aceite va en todos, el filtro AdBlue cada
-- 2, el secador cada 3, el completo cada 4, la caja cada 6… Eso no cabe en la
-- escalera 300/600/1.200/2.400 h, así que se modela como Volvo:
--
--   programa_servicio            un modelo, su intervalo (300 h)
--   programa_servicio_operacion  operación + «cada N servicios»
--   programa_servicio_repuesto   N° de parte, cantidad y producto de bodega
--
-- El servicio N° n de un equipo toca las operaciones con mod(n, cada) = 0, y
-- su kit es la suma de los repuestos de esas operaciones. El n sale del
-- horómetro al que toca el servicio (escalera, MIG642/646): n = round(H / 300).
-- La escalera sigue diciendo CUÁNDO; el programa dice QUÉ.
--
-- v_servicios_proyectados: los próximos servicios de cada equipo con
-- programa (hasta 120 días al ritmo de 30 días) → jefe de taller y compras.
--
-- Las operaciones Volvo (FMX 420, FMX 540, VM 350) se cargan de los Service
-- Graph del 19-10-2026. Los PDF NO traen números de parte: los repuestos se
-- cargan a medida que el fabricante entregue la lista.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS programa_servicio (
    modelo_id       UUID PRIMARY KEY REFERENCES modelos(id) ON DELETE CASCADE,
    intervalo_horas NUMERIC NOT NULL DEFAULT 300 CHECK (intervalo_horas BETWEEN 50 AND 2000),
    fuente          TEXT,
    notas           TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by      UUID
);

CREATE TABLE IF NOT EXISTS programa_servicio_operacion (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    modelo_id      UUID NOT NULL REFERENCES programa_servicio(modelo_id) ON DELETE CASCADE,
    orden          INT NOT NULL DEFAULT 0,
    operacion      TEXT NOT NULL CHECK (length(btrim(operacion)) >= 3),
    accion         TEXT NOT NULL DEFAULT 'sustituir'
                   CHECK (accion IN ('sustituir','lubricar','ajustar','inspeccionar','otro')),
    cada_servicios INT NOT NULL CHECK (cada_servicios BETWEEN 1 AND 100),
    nota           TEXT,
    activo         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by     UUID
);
CREATE INDEX IF NOT EXISTS ix_prog_op_modelo ON programa_servicio_operacion (modelo_id) WHERE activo;

CREATE TABLE IF NOT EXISTS programa_servicio_repuesto (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    operacion_id UUID NOT NULL REFERENCES programa_servicio_operacion(id) ON DELETE CASCADE,
    orden        INT NOT NULL DEFAULT 0,
    n_parte      TEXT,
    descripcion  TEXT NOT NULL CHECK (length(btrim(descripcion)) >= 2),
    cantidad     NUMERIC NOT NULL CHECK (cantidad > 0),
    unidad       TEXT NOT NULL DEFAULT 'un',
    producto_id  UUID REFERENCES productos(id) ON DELETE SET NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by   UUID
);
CREATE INDEX IF NOT EXISTS ix_prog_rep_op ON programa_servicio_repuesto (operacion_id);

ALTER TABLE programa_servicio           ENABLE ROW LEVEL SECURITY;
ALTER TABLE programa_servicio_operacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE programa_servicio_repuesto  ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_sel ON programa_servicio;
DROP POLICY IF EXISTS pol_sel ON programa_servicio_operacion;
DROP POLICY IF EXISTS pol_sel ON programa_servicio_repuesto;
CREATE POLICY pol_sel ON programa_servicio           FOR SELECT TO authenticated USING (true);
CREATE POLICY pol_sel ON programa_servicio_operacion FOR SELECT TO authenticated USING (true);
CREATE POLICY pol_sel ON programa_servicio_repuesto  FOR SELECT TO authenticated USING (true);
REVOKE INSERT, UPDATE, DELETE ON programa_servicio, programa_servicio_operacion, programa_servicio_repuesto
    FROM anon, authenticated;
GRANT SELECT ON programa_servicio, programa_servicio_operacion, programa_servicio_repuesto TO authenticated;

-- ── Permiso de edición (mismo de «Cambiar próxima», MIG642) ─────────────────
CREATE OR REPLACE FUNCTION public.fn_programa_servicio_puede_editar()
 RETURNS BOOLEAN
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $$
    SELECT public.fn_tiene_permiso_modulo('mantenimiento', 'edit',
        ARRAY['administrador','auditor_calidad','jefe_mantenimiento','planificador']::text[])
$$;
GRANT EXECUTE ON FUNCTION fn_programa_servicio_puede_editar() TO authenticated;

-- ── Guardar / quitar una operación ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_programa_operacion_guardar(
    p_id UUID, p_modelo_id UUID, p_operacion TEXT, p_accion TEXT, p_cada INT, p_nota TEXT, p_orden INT)
 RETURNS UUID
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id UUID;
BEGIN
    IF NOT fn_programa_servicio_puede_editar() THEN
        RAISE EXCEPTION 'No autorizado para editar el programa de servicio.' USING ERRCODE = '42501';
    END IF;
    IF p_cada IS NULL OR p_cada < 1 THEN
        RAISE EXCEPTION 'Indica cada cuántos servicios se hace.' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO programa_servicio (modelo_id, updated_by) VALUES (p_modelo_id, auth.uid())
    ON CONFLICT (modelo_id) DO NOTHING;
    IF p_id IS NULL THEN
        INSERT INTO programa_servicio_operacion (modelo_id, orden, operacion, accion, cada_servicios, nota, updated_by)
        VALUES (p_modelo_id, coalesce(p_orden, 999), btrim(p_operacion), coalesce(p_accion, 'sustituir'),
                p_cada, nullif(btrim(coalesce(p_nota, '')), ''), auth.uid())
        RETURNING id INTO v_id;
    ELSE
        UPDATE programa_servicio_operacion
           SET operacion = btrim(p_operacion), accion = coalesce(p_accion, accion),
               cada_servicios = p_cada, nota = nullif(btrim(coalesce(p_nota, '')), ''),
               orden = coalesce(p_orden, orden), updated_at = NOW(), updated_by = auth.uid()
         WHERE id = p_id
        RETURNING id INTO v_id;
        IF v_id IS NULL THEN RAISE EXCEPTION 'La operación no existe.' USING ERRCODE = 'P0001'; END IF;
    END IF;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.rpc_programa_operacion_quitar(p_id UUID)
 RETURNS VOID
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT fn_programa_servicio_puede_editar() THEN
        RAISE EXCEPTION 'No autorizado para editar el programa de servicio.' USING ERRCODE = '42501';
    END IF;
    UPDATE programa_servicio_operacion SET activo = FALSE, updated_at = NOW(), updated_by = auth.uid()
     WHERE id = p_id;
END $function$;

CREATE OR REPLACE FUNCTION public.rpc_programa_intervalo(p_modelo_id UUID, p_horas NUMERIC)
 RETURNS VOID
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT fn_programa_servicio_puede_editar() THEN
        RAISE EXCEPTION 'No autorizado para editar el programa de servicio.' USING ERRCODE = '42501';
    END IF;
    INSERT INTO programa_servicio (modelo_id, intervalo_horas, updated_by)
    VALUES (p_modelo_id, p_horas, auth.uid())
    ON CONFLICT (modelo_id) DO UPDATE
       SET intervalo_horas = EXCLUDED.intervalo_horas, updated_at = NOW(), updated_by = auth.uid();
END $function$;

-- ── Repuestos de una operación: la lista completa se reemplaza ──────────────
-- p_items = [{n_parte, descripcion, cantidad, unidad, producto_id?}]. Si no
-- viene producto_id y el N° de parte aparece en UN solo producto de bodega
-- (código o nombre), se enlaza solo.
CREATE OR REPLACE FUNCTION public.rpc_programa_repuestos_guardar(p_operacion_id UUID, p_items JSONB)
 RETURNS INT
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    it    JSONB;
    v_np  TEXT;
    v_pid UUID;
    v_n   INT := 0;
BEGIN
    IF NOT fn_programa_servicio_puede_editar() THEN
        RAISE EXCEPTION 'No autorizado para editar el programa de servicio.' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM programa_servicio_operacion WHERE id = p_operacion_id) THEN
        RAISE EXCEPTION 'La operación no existe.' USING ERRCODE = 'P0001';
    END IF;
    IF jsonb_typeof(coalesce(p_items, '[]')) <> 'array' THEN
        RAISE EXCEPTION 'Formato de repuestos inválido.' USING ERRCODE = 'P0001';
    END IF;

    DELETE FROM programa_servicio_repuesto WHERE operacion_id = p_operacion_id;

    FOR it IN SELECT * FROM jsonb_array_elements(coalesce(p_items, '[]'))
    LOOP
        v_np  := nullif(btrim(coalesce(it->>'n_parte', '')), '');
        v_pid := nullif(it->>'producto_id', '')::UUID;
        IF v_pid IS NULL AND v_np IS NOT NULL AND length(v_np) >= 5 THEN
            SELECT CASE WHEN count(*) = 1 THEN min(p.id::text)::UUID END INTO v_pid
              FROM productos p
             WHERE p.codigo = v_np
                OR p.nombre ILIKE '%' || v_np || '%';
        END IF;
        IF nullif(btrim(coalesce(it->>'descripcion', '')), '') IS NULL THEN
            RAISE EXCEPTION 'Cada repuesto necesita una descripción (fila %).', v_n + 1 USING ERRCODE = 'P0001';
        END IF;
        IF coalesce((it->>'cantidad')::NUMERIC, 0) <= 0 THEN
            RAISE EXCEPTION 'Cantidad inválida en «%».', it->>'descripcion' USING ERRCODE = 'P0001';
        END IF;
        INSERT INTO programa_servicio_repuesto
               (operacion_id, orden, n_parte, descripcion, cantidad, unidad, producto_id, created_by)
        VALUES (p_operacion_id, v_n, v_np, btrim(it->>'descripcion'), (it->>'cantidad')::NUMERIC,
                coalesce(nullif(btrim(coalesce(it->>'unidad', '')), ''), 'un'), v_pid, auth.uid());
        v_n := v_n + 1;
    END LOOP;
    RETURN v_n;
END $function$;

REVOKE ALL ON FUNCTION rpc_programa_operacion_guardar(UUID, UUID, TEXT, TEXT, INT, TEXT, INT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_programa_operacion_quitar(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_programa_intervalo(UUID, NUMERIC) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_programa_repuestos_guardar(UUID, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_programa_operacion_guardar(UUID, UUID, TEXT, TEXT, INT, TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_programa_operacion_quitar(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_programa_intervalo(UUID, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_programa_repuestos_guardar(UUID, JSONB) TO authenticated;

-- ── Repuestos con su producto y el stock total de bodega ────────────────────
CREATE OR REPLACE VIEW v_programa_repuesto WITH (security_invoker = true) AS
SELECT r.id, r.operacion_id, o.modelo_id, r.orden, r.n_parte, r.descripcion, r.cantidad, r.unidad,
       r.producto_id, p.codigo AS producto_codigo, p.nombre AS producto_nombre,
       p.costo_unitario_actual,
       (SELECT coalesce(sum(s.cantidad), 0) FROM stock_bodega s WHERE s.producto_id = r.producto_id) AS stock_total
  FROM programa_servicio_repuesto r
  JOIN programa_servicio_operacion o ON o.id = r.operacion_id
  LEFT JOIN productos p ON p.id = r.producto_id;
GRANT SELECT ON v_programa_repuesto TO authenticated;

-- ── Los próximos servicios de cada equipo con programa ──────────────────────
-- Cuándo: el horómetro al que toca según la escalera (v_equipo_horas). Sin
-- escalera usable (sin plan / revisar base): el próximo múltiplo del intervalo.
-- Después, uno cada intervalo. Fecha al ritmo de 30 días (piso 0,5 h/día).
CREATE OR REPLACE VIEW v_servicios_proyectados WITH (security_invoker = true) AS
WITH hoy AS (SELECT (NOW() AT TIME ZONE 'America/Santiago')::DATE AS d),
base AS (
    SELECT e.activo_id, e.patente, e.codigo, e.nombre, e.faena, a.modelo_id, m.nombre AS modelo,
           ps.intervalo_horas AS intervalo, e.horometro, e.horas_por_dia, e.ot_abierta,
           e.proxima_pauta AS pauta_escalera,
           CASE WHEN e.estado_preventiva IN ('vencida','proxima','atento','al_dia') AND e.horas_faltan IS NOT NULL
                THEN e.horometro + e.horas_faltan
                ELSE (floor(coalesce(e.horometro, 0) / ps.intervalo_horas) + 1) * ps.intervalo_horas END AS h_proximo
      FROM v_equipo_horas e
      JOIN activos a ON a.id = e.activo_id
      JOIN programa_servicio ps ON ps.modelo_id = a.modelo_id
      JOIN modelos m ON m.id = a.modelo_id
     WHERE coalesce(e.horometro, 0) > 0
)
SELECT b.activo_id, b.patente, b.codigo, b.nombre, b.faena, b.modelo_id, b.modelo, b.intervalo,
       b.horometro, b.horas_por_dia, b.ot_abierta, b.pauta_escalera,
       k AS orden,
       greatest(1, round((b.h_proximo + k * b.intervalo) / b.intervalo))::INT AS n_servicio,
       round(b.h_proximo + k * b.intervalo, 1) AS horas_servicio,
       round(b.h_proximo + k * b.intervalo - b.horometro, 1) AS horas_faltan,
       CASE WHEN b.h_proximo + k * b.intervalo <= b.horometro THEN (SELECT d FROM hoy)
            WHEN coalesce(b.horas_por_dia, 0) <= 0 THEN NULL
            ELSE (SELECT d FROM hoy)
                 + ceil((b.h_proximo + k * b.intervalo - b.horometro) / greatest(b.horas_por_dia, 0.5))::INT
       END AS fecha_estimada
  FROM base b
  CROSS JOIN generate_series(0, 15) k
 WHERE k = 0
    OR (coalesce(b.horas_por_dia, 0) > 0
        AND (b.h_proximo + k * b.intervalo - b.horometro) / greatest(b.horas_por_dia, 0.5) <= 120);
GRANT SELECT ON v_servicios_proyectados TO authenticated;

-- ── Carga inicial: operaciones Volvo (Service Graph 19-10-2026) ─────────────
DO $$
DECLARE
    v_fmx  TEXT[][] := ARRAY[
        ['Servicio básico (inspección según pauta Volvo)', 'inspeccionar', '1', NULL],
        ['Motor: aceite y filtro(s), sustituir',           'sustituir',    '1', NULL],
        ['Filtro de combustible, sustituir',               'sustituir',    '1', NULL],
        ['Filtro separador de agua, sustituir',            'sustituir',    '1', NULL],
        ['Filtro de aire primario, sustituir',             'sustituir',    '1', NULL],
        ['Filtro ventilación estanque de combustible, sustituir', 'sustituir', '1', NULL],
        ['Cojinetes suspensión ballestas, lubricar',       'lubricar',     '1', NULL],
        ['Leva del freno, lubricar',                       'lubricar',     '1', NULL],
        ['Filtro bomba AdBlue, sustituir',                 'sustituir',    '2', NULL],
        ['Filtro de aire acondicionado, sustituir',        'sustituir',    '2', NULL],
        ['Cartucho secador de aire, sustituir',            'sustituir',    '3', NULL],
        ['Correa del alternador, sustituir',               'sustituir',    '3', NULL],
        ['Correa del ventilador, sustituir',               'sustituir',    '3', NULL],
        ['Servicio completo (inspección completa Volvo)',  'inspeccionar', '4', NULL],
        ['Tensor correa alternador, sustituir',            'sustituir',    '6', NULL],
        ['Tensor correa ventilador, sustituir',            'sustituir',    '6', NULL],
        ['Válvulas e inyectores-bomba, ajustar',           'ajustar',      '6', NULL],
        ['Caja de cambios: aceite y filtro, sustituir',    'sustituir',    '6', NULL],
        ['Reducción de cubo: aceite, sustituir',           'sustituir',    '6', NULL],
        ['Filtro de aire secundario, sustituir',           'sustituir',    '18', NULL],
        ['Refrigerante, sustituir',                        'sustituir',    '20', 'Volvo: una vez en 6 años (~servicio 20)']];
    v_vm   TEXT[][] := ARRAY[
        ['Servicio básico (inspección según pauta Volvo)', 'inspeccionar', '1', NULL],
        ['Motor: aceite y filtro(s), sustituir',           'sustituir',    '1', NULL],
        ['Filtro de combustible, sustituir',               'sustituir',    '1', NULL],
        ['Filtro separador de agua, sustituir',            'sustituir',    '1', NULL],
        ['Lubricación de puntos según esquema',            'lubricar',     '1', NULL],
        ['Filtro de aire primario, sustituir',             'sustituir',    '3', NULL],
        ['Cartucho secador de aire, sustituir',            'sustituir',    '3', NULL],
        ['Filtro de aire acondicionado, sustituir',        'sustituir',    '3', 'Volvo alterna cada 3 y 4 servicios (~5 meses)'],
        ['Caja de cambios: aceite y filtro, sustituir',    'sustituir',    '4', NULL],
        ['Válvulas, ajustar',                              'ajustar',      '4', NULL],
        ['Reducción de cubo: aceite, sustituir',           'sustituir',    '4', NULL],
        ['Servicio completo (inspección completa Volvo)',  'inspeccionar', '7', NULL],
        ['Correa del ventilador, sustituir',               'sustituir',    '7', NULL],
        ['Tensor correa ventilador, sustituir',            'sustituir',    '7', NULL],
        ['Polea loca correa ventilador, sustituir',        'sustituir',    '15', NULL],
        ['Refrigerante, sustituir',                        'sustituir',    '31', 'Volvo: una vez en 5 años (~servicio 31)']];
    v_mod  RECORD;
    v_ops  TEXT[][];
    i      INT;
BEGIN
    FOR v_mod IN
        SELECT m.id, m.nombre FROM modelos m
          JOIN marcas ma ON ma.id = m.marca_id
         WHERE ma.nombre ILIKE 'volvo%' AND m.nombre IN ('FMX 420', 'FMX 540', 'VM 350')
    LOOP
        CONTINUE WHEN EXISTS (SELECT 1 FROM programa_servicio WHERE modelo_id = v_mod.id);
        INSERT INTO programa_servicio (modelo_id, intervalo_horas, fuente, notas)
        VALUES (v_mod.id, 300, 'Volvo Service Graph 19-10-2026',
                'Intervalo SICOM 300 h (Volvo 394 h). Operaciones y cadencias según Volvo.');
        v_ops := CASE WHEN v_mod.nombre = 'VM 350' THEN v_vm ELSE v_fmx END;
        FOR i IN 1 .. array_length(v_ops, 1) LOOP
            INSERT INTO programa_servicio_operacion (modelo_id, orden, operacion, accion, cada_servicios, nota)
            VALUES (v_mod.id, i, v_ops[i][1], v_ops[i][2], v_ops[i][3]::INT, v_ops[i][4]);
        END LOOP;
        RAISE NOTICE '% → % operaciones', v_mod.nombre, array_length(v_ops, 1);
    END LOOP;
END $$;

SELECT patente, modelo, n_servicio, horas_servicio, horas_faltan, fecha_estimada
  FROM v_servicios_proyectados WHERE orden = 0 ORDER BY fecha_estimada NULLS LAST;

COMMIT;
