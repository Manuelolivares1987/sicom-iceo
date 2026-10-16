-- ============================================================================
-- MIG607 · El camión externo entra al taller por la misma puerta que la flota
-- ============================================================================
-- Pedido Manuel (2026-10-16): cuando el planificador programa en el Plan Taller
-- un camión EXTERNO (de un cliente, fuera de la flota Pillado), que tenga lo
-- mismo que un equipo de la flota: checklist, tareas, recursos, la OT que ve el
-- jefe de taller y el mecánico en /m/taller.
--
-- Hasta hoy el externo sólo podía ir como «tarea libre» (MIG182): una fila del
-- plan sin OT, o sea sin checklist ni tareas. Y todo el camino de la OT
-- (checklist V03, NC, informe, vales, bono) cuelga de ordenes_trabajo.activo_id,
-- que es NOT NULL y lo usan ~200 funciones y vistas.
--
-- Decisión (Manuel): el externo tiene FICHA, marcada `es_externo`. Así recorre
-- exactamente el mismo camino que la flota y, si vuelve, se ve su historial.
-- Lo que cambia es que NO ES FLOTA: donde la base define «la flota» con
-- `estado <> 'dado_baja'` (KPI, disponibilidad, reporte diario, fiabilidad,
-- alertas de papeles/preventivas/antigüedad, paneles de gerencia, panel de
-- flota, posiciones, control documental) se agrega «y no es externo».
--
--   1. activos.es_externo + externo_cliente.
--   2. Marca EXTERNO con un modelo por tipo (modelo_id es NOT NULL). Sin
--      plantillas de plan → no se le siembran preventivas.
--   3. Guardas: no se le crean planes automáticos ni estado diario de flota.
--   4. Parches por línea a las funciones/vistas que cuentan flota.
--   5. rpc_registrar_equipo_externo: crea o reutiliza (por patente) la ficha.
--      Una patente de la flota Pillado NO se puede registrar como externa.
--      Después la OT se programa con rpc_programar_ot_taller, como cualquiera.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1 · La ficha sabe que es externa ────────────────────────────────────────
ALTER TABLE activos
    ADD COLUMN IF NOT EXISTS es_externo      BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS externo_cliente TEXT;

COMMENT ON COLUMN activos.es_externo IS
    'Equipo de un tercero que entra al taller (MIG607). Tiene OT, checklist y tareas como la flota, pero NO cuenta en ningún agregado de flota.';
COMMENT ON COLUMN activos.externo_cliente IS
    'Dueño/cliente del equipo externo (MIG607).';

CREATE INDEX IF NOT EXISTS idx_activos_externo ON activos (es_externo) WHERE es_externo;

-- ── 2 · Marca y modelos de los externos ─────────────────────────────────────
INSERT INTO marcas (nombre)
SELECT 'EXTERNO' WHERE NOT EXISTS (SELECT 1 FROM marcas WHERE nombre = 'EXTERNO');

INSERT INTO modelos (marca_id, nombre, tipo_activo)
SELECT ma.id, x.nombre, x.tipo::tipo_activo_enum
  FROM marcas ma
 CROSS JOIN (VALUES ('Camión externo', 'camion'),
                    ('Camión cisterna externo', 'camion_cisterna'),
                    ('Camioneta externa', 'camioneta'),
                    ('Equipo menor externo', 'equipo_menor')) x(nombre, tipo)
 WHERE ma.nombre = 'EXTERNO'
   AND NOT EXISTS (SELECT 1 FROM modelos m WHERE m.marca_id = ma.id AND m.nombre = x.nombre);

-- ── 3 · Guardas ─────────────────────────────────────────────────────────────
-- 3a. Un externo no recibe planes preventivos automáticos.
CREATE OR REPLACE FUNCTION public.fn_trg_auto_planes_activo()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- [MIG607] Un equipo externo no es nuestro: no se le planifica nada.
    IF NEW.es_externo THEN
        RETURN NEW;
    END IF;
    -- Solo dispara si hay modelo Y el activo no esta dado de baja
    IF NEW.modelo_id IS NULL OR NEW.estado = 'dado_baja' THEN
        RETURN NEW;
    END IF;
    -- En UPDATE, solo si el modelo CAMBIO (o pasa de baja a activo)
    IF TG_OP = 'UPDATE' THEN
        IF NEW.modelo_id = COALESCE(OLD.modelo_id, NEW.modelo_id)
           AND OLD.estado != 'dado_baja' THEN
            RETURN NEW;
        END IF;
    END IF;
    PERFORM fn_auto_crear_planes_activo(NEW.id);
    RETURN NEW;
END;
$function$;

-- 3b. La OT de un externo no escribe estado diario de flota (disponibilidad).
CREATE OR REPLACE FUNCTION public.trg_fn_recalcular_estado_por_ot()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_estado_calc CHAR(1);
    v_es_override BOOLEAN;
BEGIN
    -- Solo actuar cuando cambia el estado de la OT
    IF TG_OP = 'UPDATE' AND OLD.estado IS NOT DISTINCT FROM NEW.estado THEN
        RETURN NEW;
    END IF;

    -- [MIG607] El externo no es flota: no tiene estado del día.
    IF EXISTS (SELECT 1 FROM activos WHERE id = NEW.activo_id AND es_externo) THEN
        RETURN NEW;
    END IF;

    -- ¿El estado del día actual de este activo es manual? Si sí, no tocar.
    SELECT override_manual INTO v_es_override
    FROM estado_diario_flota
    WHERE activo_id = NEW.activo_id AND fecha = CURRENT_DATE;

    IF v_es_override = true THEN
        RETURN NEW;
    END IF;

    -- Recalcular y aplicar
    v_estado_calc := fn_calcular_estado_diario_automatico(NEW.activo_id, CURRENT_DATE);

    INSERT INTO estado_diario_flota (
        activo_id, fecha, estado_codigo, calculado_auto, override_manual
    ) VALUES (
        NEW.activo_id, CURRENT_DATE, v_estado_calc, true, false
    )
    ON CONFLICT (activo_id, fecha) DO UPDATE
    SET estado_codigo = EXCLUDED.estado_codigo,
        calculado_auto = true,
        updated_at = NOW()
    WHERE estado_diario_flota.override_manual = false;

    RETURN NEW;
END;
$function$;

-- 3c. Panel de costos: igual que el equipo de prueba, el externo no entra.
DO $$
DECLARE v_def TEXT;
BEGIN
    v_def := pg_get_functiondef('public.rpc_costos_operacion_panel'::regproc);
    IF position('es_externo' IN v_def) = 0 THEN
        v_def := replace(v_def, 'WHERE NOT coalesce(a.es_prueba, false)',
                         'WHERE NOT coalesce(a.es_prueba, false) AND NOT coalesce(a.es_externo, false)');
        IF position('es_externo' IN v_def) = 0 THEN
            RAISE EXCEPTION 'MIG607: no se encontró el filtro es_prueba en rpc_costos_operacion_panel';
        END IF;
        EXECUTE v_def;
    END IF;
END $$;

-- ── 4 · Donde se cuenta flota, el externo no cuenta ─────────────────────────
-- (Generado desde las definiciones vivas con database/scripts/_gen607.mjs:
--  cada `estado <> 'dado_baja'` sobre activos pasa a
--  `(estado <> 'dado_baja' AND NOT COALESCE(es_externo, false))`.)

-- calcular_kpi_a4(uuid,uuid,date,date)
CREATE OR REPLACE FUNCTION public.calcular_kpi_a4(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
    v_vigentes    NUMERIC;
    v_requeridas  NUMERIC;
BEGIN
    SELECT
        COALESCE(COUNT(*) FILTER (WHERE c.estado = 'vigente'), 0),
        COALESCE(NULLIF(COUNT(*) FILTER (WHERE c.estado <> 'no_aplica'), 0), 1)
    INTO v_vigentes, v_requeridas
    FROM certificaciones c
    JOIN activos a ON a.id = c.activo_id
    WHERE a.faena_id = p_faena_id
      AND a.contrato_id = p_contrato_id
      AND (a.estado <> 'dado_baja' AND NOT COALESCE(a.es_externo, false));

    RETURN ROUND(v_vigentes / v_requeridas * 100, 2);
END;
$function$;

-- calcular_kpi_b1(uuid,uuid,date,date)
CREATE OR REPLACE FUNCTION public.calcular_kpi_b1(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
    v_total_activos       NUMERIC;
    v_horas_periodo       NUMERIC;
    v_horas_programadas   NUMERIC;
    v_horas_downtime      NUMERIC;
BEGIN
    -- Tipos considerados punto fijo
    -- Contar activos fijos activos en la faena
    SELECT COUNT(*)
    INTO v_total_activos
    FROM activos a
    WHERE a.faena_id    = p_faena_id
      AND a.contrato_id = p_contrato_id
      AND a.tipo IN ('punto_fijo', 'surtidor', 'dispensador', 'estanque',
                      'bomba', 'manguera', 'equipo_bombeo',
                      'herramienta_critica', 'pistola_captura')
      AND (a.estado <> 'dado_baja' AND NOT COALESCE(a.es_externo, false));

    IF v_total_activos = 0 THEN
        RETURN 100.00;  -- Sin activos, no hay indisponibilidad
    END IF;

    -- Horas del periodo (24h por dia)
    v_horas_periodo := (p_periodo_fin - p_periodo_inicio + 1) * 24.0;
    v_horas_programadas := v_total_activos * v_horas_periodo;

    -- Horas de downtime: sumar duracion de OTs correctivas para activos fijos
    SELECT COALESCE(SUM(
        EXTRACT(EPOCH FROM (
            COALESCE(ot.fecha_termino, NOW()) - ot.fecha_inicio
        )) / 3600.0
    ), 0)
    INTO v_horas_downtime
    FROM ordenes_trabajo ot
    JOIN activos a ON a.id = ot.activo_id
    WHERE ot.contrato_id = p_contrato_id
      AND ot.faena_id    = p_faena_id
      AND ot.tipo        = 'correctivo'
      AND a.tipo IN ('punto_fijo', 'surtidor', 'dispensador', 'estanque',
                      'bomba', 'manguera', 'equipo_bombeo',
                      'herramienta_critica', 'pistola_captura')
      AND ot.fecha_inicio IS NOT NULL
      AND ot.fecha_inicio >= p_periodo_inicio
      AND ot.fecha_inicio <  (p_periodo_fin + INTERVAL '1 day');

    IF v_horas_programadas = 0 THEN
        RETURN 100.00;
    END IF;

    RETURN ROUND((v_horas_programadas - v_horas_downtime) / v_horas_programadas * 100, 2);
END;
$function$;

-- calcular_kpi_b4(uuid,uuid,date,date)
CREATE OR REPLACE FUNCTION public.calcular_kpi_b4(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
    v_vigentes    NUMERIC;
    v_requeridas  NUMERIC;
BEGIN
    SELECT
        COALESCE(COUNT(*) FILTER (WHERE c.estado = 'vigente'), 0),
        COALESCE(NULLIF(COUNT(*) FILTER (WHERE c.estado <> 'no_aplica'), 0), 1)
    INTO v_vigentes, v_requeridas
    FROM certificaciones c
    JOIN activos a ON a.id = c.activo_id
    WHERE a.faena_id    = p_faena_id
      AND a.contrato_id = p_contrato_id
      AND a.tipo IN ('punto_fijo', 'surtidor', 'dispensador', 'estanque',
                      'bomba', 'manguera', 'equipo_bombeo',
                      'herramienta_critica', 'pistola_captura')
      AND (a.estado <> 'dado_baja' AND NOT COALESCE(a.es_externo, false));

    RETURN ROUND(v_vigentes / v_requeridas * 100, 2);
END;
$function$;

-- calcular_kpi_c1(uuid,uuid,date,date)
CREATE OR REPLACE FUNCTION public.calcular_kpi_c1(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
    v_total_activos       NUMERIC;
    v_horas_periodo       NUMERIC;
    v_horas_programadas   NUMERIC;
    v_horas_downtime      NUMERIC;
BEGIN
    SELECT COUNT(*)
    INTO v_total_activos
    FROM activos a
    WHERE a.faena_id    = p_faena_id
      AND a.contrato_id = p_contrato_id
      AND a.tipo IN ('punto_movil', 'camion_cisterna', 'lubrimovil',
                      'camioneta', 'camion', 'equipo_menor')
      AND (a.estado <> 'dado_baja' AND NOT COALESCE(a.es_externo, false));

    IF v_total_activos = 0 THEN
        RETURN 100.00;
    END IF;

    v_horas_periodo := (p_periodo_fin - p_periodo_inicio + 1) * 24.0;
    v_horas_programadas := v_total_activos * v_horas_periodo;

    SELECT COALESCE(SUM(
        EXTRACT(EPOCH FROM (
            COALESCE(ot.fecha_termino, NOW()) - ot.fecha_inicio
        )) / 3600.0
    ), 0)
    INTO v_horas_downtime
    FROM ordenes_trabajo ot
    JOIN activos a ON a.id = ot.activo_id
    WHERE ot.contrato_id = p_contrato_id
      AND ot.faena_id    = p_faena_id
      AND ot.tipo        = 'correctivo'
      AND a.tipo IN ('punto_movil', 'camion_cisterna', 'lubrimovil',
                      'camioneta', 'camion', 'equipo_menor')
      AND ot.fecha_inicio IS NOT NULL
      AND ot.fecha_inicio >= p_periodo_inicio
      AND ot.fecha_inicio <  (p_periodo_fin + INTERVAL '1 day');

    IF v_horas_programadas = 0 THEN
        RETURN 100.00;
    END IF;

    RETURN ROUND((v_horas_programadas - v_horas_downtime) / v_horas_programadas * 100, 2);
END;
$function$;

-- calcular_kpi_c6(uuid,uuid,date,date)
CREATE OR REPLACE FUNCTION public.calcular_kpi_c6(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
    v_vigentes    NUMERIC;
    v_requeridas  NUMERIC;
BEGIN
    SELECT
        COALESCE(COUNT(*) FILTER (WHERE c.estado = 'vigente'), 0),
        COALESCE(NULLIF(COUNT(*) FILTER (WHERE c.estado <> 'no_aplica'), 0), 1)
    INTO v_vigentes, v_requeridas
    FROM certificaciones c
    JOIN activos a ON a.id = c.activo_id
    WHERE a.faena_id    = p_faena_id
      AND a.contrato_id = p_contrato_id
      AND a.tipo IN ('punto_movil', 'camion_cisterna', 'lubrimovil',
                      'camioneta', 'camion', 'equipo_menor')
      AND (a.estado <> 'dado_baja' AND NOT COALESCE(a.es_externo, false));

    RETURN ROUND(v_vigentes / v_requeridas * 100, 2);
END;
$function$;

-- calcular_oee_flota(uuid,date,date,character varying)
CREATE OR REPLACE FUNCTION public.calcular_oee_flota(p_contrato_id uuid, p_fecha_inicio date, p_fecha_fin date, p_operacion character varying DEFAULT NULL::character varying)
 RETURNS TABLE(operacion character varying, total_equipos bigint, disponibilidad_promedio numeric, utilizacion_promedio numeric, calidad_promedio numeric, oee_promedio numeric, clasificacion character varying)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    WITH activos_flota AS (
        SELECT a.id
        FROM activos a
        WHERE (a.contrato_id = p_contrato_id OR p_contrato_id IS NULL)
          AND (a.estado != 'dado_baja' AND NOT COALESCE(a.es_externo, false))
          AND a.tipo IN ('camion_cisterna', 'camion', 'camioneta', 'lubrimovil')
          AND (p_operacion IS NULL OR a.operacion = p_operacion)
    ),
    oee_por_activo AS (
        SELECT
            o.disponibilidad_mecanica,
            o.utilizacion_operativa,
            o.calidad_servicio,
            o.oee
        FROM activos_flota af
        CROSS JOIN LATERAL calcular_oee_activo(af.id, p_fecha_inicio, p_fecha_fin) o
    )
    SELECT
        COALESCE(p_operacion, 'TOTAL')::VARCHAR,
        COUNT(*)::BIGINT,
        ROUND(AVG(opa.disponibilidad_mecanica), 2),
        ROUND(AVG(opa.utilizacion_operativa), 2),
        ROUND(AVG(opa.calidad_servicio), 2),
        ROUND(AVG(opa.oee), 2),
        CASE
            WHEN AVG(opa.oee) >= 80 THEN 'Clase Mundial'
            WHEN AVG(opa.oee) >= 64 THEN 'Bueno'
            WHEN AVG(opa.oee) >= 50 THEN 'Aceptable'
            ELSE 'Deficiente'
        END::VARCHAR
    FROM oee_por_activo opa;
END;
$function$;

-- fn_aplicar_estado_geocerca(date)
CREATE OR REPLACE FUNCTION public.fn_aplicar_estado_geocerca(p_fecha date DEFAULT CURRENT_DATE)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_n integer := 0;
BEGIN
  WITH calc AS (
    SELECT a.id AS activo_id, fn_estado_por_geocerca(a.id) AS est
    FROM activos a WHERE (a.estado <> 'dado_baja' AND NOT COALESCE(a.es_externo, false))
  )
  INSERT INTO estado_diario_flota (activo_id, fecha, estado_codigo, calculado_auto, override_manual, motivo_override)
  SELECT activo_id, p_fecha, est, true, false, 'Auto geocerca'
  FROM calc WHERE est IS NOT NULL
  ON CONFLICT (activo_id, fecha) DO UPDATE
    SET estado_codigo = EXCLUDED.estado_codigo, calculado_auto = true, updated_at = now()
    WHERE estado_diario_flota.override_manual = false;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $function$;

-- fn_aplicar_estados_diarios_automaticos(date)
CREATE OR REPLACE FUNCTION public.fn_aplicar_estados_diarios_automaticos(p_fecha date DEFAULT CURRENT_DATE)
 RETURNS TABLE(procesados integer, nuevos integer, actualizados integer, saltados_override integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_activo RECORD;
    v_estado_calculado CHAR(1);
    v_estado_actual CHAR(1);
    v_override BOOLEAN;
    v_procesados INTEGER := 0;
    v_nuevos INTEGER := 0;
    v_actualizados INTEGER := 0;
    v_saltados INTEGER := 0;
BEGIN
    FOR v_activo IN
        SELECT id, contrato_id, cliente_actual, ubicacion_actual, operacion
        FROM activos
        WHERE (estado != 'dado_baja' AND NOT COALESCE(es_externo, false))
    LOOP
        v_procesados := v_procesados + 1;

        -- ¿Existe ya un registro para este activo en esa fecha?
        SELECT estado_codigo, override_manual
        INTO v_estado_actual, v_override
        FROM estado_diario_flota
        WHERE activo_id = v_activo.id AND fecha = p_fecha;

        -- Si existe override manual, no tocar
        IF v_override = true THEN
            v_saltados := v_saltados + 1;
            CONTINUE;
        END IF;

        -- Calcular estado nuevo
        v_estado_calculado := fn_calcular_estado_diario_automatico(v_activo.id, p_fecha);

        IF v_estado_actual IS NULL THEN
            -- INSERT nuevo
            INSERT INTO estado_diario_flota (
                activo_id, fecha, contrato_id, estado_codigo,
                cliente, ubicacion, operacion,
                calculado_auto, override_manual
            ) VALUES (
                v_activo.id, p_fecha, v_activo.contrato_id, v_estado_calculado,
                v_activo.cliente_actual, v_activo.ubicacion_actual, v_activo.operacion,
                true, false
            )
            ON CONFLICT (activo_id, fecha) DO NOTHING;
            v_nuevos := v_nuevos + 1;
        ELSIF v_estado_actual != v_estado_calculado THEN
            -- UPDATE solo si cambió
            UPDATE estado_diario_flota
            SET estado_codigo = v_estado_calculado,
                calculado_auto = true,
                updated_at = NOW()
            WHERE activo_id = v_activo.id AND fecha = p_fecha;
            v_actualizados := v_actualizados + 1;
        END IF;
    END LOOP;

    RETURN QUERY SELECT v_procesados, v_nuevos, v_actualizados, v_saltados;
END;
$function$;

-- fn_calcular_fiabilidad_flota(date,date,categoria_uso_enum)
CREATE OR REPLACE FUNCTION public.fn_calcular_fiabilidad_flota(p_fecha_inicio date, p_fecha_fin date, p_categoria categoria_uso_enum DEFAULT NULL::categoria_uso_enum)
 RETURNS TABLE(categoria categoria_uso_enum, total_equipos bigint, dias_equipo bigint, dias_up bigint, dias_down bigint, eventos_falla_total bigint, disponibilidad_fisica numeric, utilizacion_bruta numeric, mtbf_agregado numeric, mttr_agregado numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    WITH base AS (
        SELECT a.id, a.categoria_uso, edf.fecha, edf.estado_codigo
          FROM activos a
          JOIN estado_diario_flota edf ON edf.activo_id = a.id
         WHERE (a.estado != 'dado_baja' AND NOT COALESCE(a.es_externo, false))
           AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
           AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin
           AND edf.estado_codigo NOT IN ('S','B')
           AND (p_categoria IS NULL OR a.categoria_uso = p_categoria)
    ),
    por_activo AS (
        SELECT id, categoria_uso,
               COUNT(*) AS dias_obs,
               COUNT(*) FILTER (WHERE estado_codigo IN ('M','T','F','R','H')) AS dias_dn,
               COUNT(*) FILTER (WHERE estado_codigo NOT IN ('M','T','F','R','H')) AS dias_ok,
               COUNT(*) FILTER (WHERE estado_codigo IN ('M','T')) AS dias_mt,
               COUNT(*) FILTER (WHERE estado_codigo IN ('A','L','C')) AS dias_util
          FROM base
         GROUP BY id, categoria_uso
    ),
    eventos_por_activo AS (
        SELECT id, categoria_uso, COUNT(DISTINCT grupo) AS eventos
          FROM (
            SELECT id, categoria_uso, fecha,
                   SUM(CASE WHEN prev_fecha IS NULL OR (fecha - prev_fecha) > 1 THEN 1 ELSE 0 END)
                     OVER (PARTITION BY id ORDER BY fecha) AS grupo
              FROM (
                SELECT id, categoria_uso, fecha,
                       LAG(fecha) OVER (PARTITION BY id ORDER BY fecha) AS prev_fecha
                  FROM base
                 WHERE estado_codigo IN ('M','T','F')
              ) t
          ) g
         GROUP BY id, categoria_uso
    ),
    combinado AS (
        SELECT pa.categoria_uso, pa.id, pa.dias_obs, pa.dias_ok, pa.dias_dn,
               pa.dias_mt, pa.dias_util, COALESCE(ep.eventos, 0) AS eventos
          FROM por_activo pa
          LEFT JOIN eventos_por_activo ep ON ep.id = pa.id
    )
    SELECT c.categoria_uso,
           COUNT(DISTINCT c.id)::BIGINT AS total_equipos,
           SUM(c.dias_obs)::BIGINT AS dias_equipo,
           SUM(c.dias_ok)::BIGINT AS dias_up,
           SUM(c.dias_dn)::BIGINT AS dias_down,
           SUM(c.eventos)::BIGINT AS eventos_falla_total,
           ROUND(CASE WHEN SUM(c.dias_obs) > 0 THEN SUM(c.dias_ok)::NUMERIC / SUM(c.dias_obs) ELSE 0 END, 4) AS disponibilidad_fisica,
           ROUND(CASE WHEN SUM(c.dias_obs) > 0 THEN SUM(c.dias_util)::NUMERIC / SUM(c.dias_obs) ELSE 0 END, 4) AS utilizacion_bruta,
           ROUND(CASE WHEN SUM(c.eventos) > 0 THEN SUM(c.dias_ok)::NUMERIC / SUM(c.eventos) ELSE SUM(c.dias_ok) END, 4) AS mtbf_agregado,
           ROUND(CASE WHEN SUM(c.eventos) > 0 THEN SUM(c.dias_mt)::NUMERIC / SUM(c.eventos) ELSE 0 END, 4) AS mttr_agregado
      FROM combinado c
     GROUP BY c.categoria_uso
     ORDER BY c.categoria_uso;
END;
$function$;

-- fn_certificados_escalar_sin_fecha()
CREATE OR REPLACE FUNCTION public.fn_certificados_escalar_sin_fecha()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    r RECORD; u RECORD; v_nuevos INT := 0; v_actualizados INT := 0; v_upd INT;
    v_msg TEXT; v_sev TEXT;
BEGIN
    FOR r IN
        SELECT a.id AS activo_id,
               COALESCE(a.patente, a.codigo) AS patente,
               count(*) AS n,
               max(CURRENT_DATE - c.created_at::date) AS dias_max,
               string_agg(DISTINCT replace(v.tipo::text, '_', ' '), ', '
                          ORDER BY replace(v.tipo::text, '_', ' ')) AS tipos
          FROM v_certificacion_actual v
          JOIN certificaciones c ON c.id = v.id
          JOIN activos a ON a.id = v.activo_id
         WHERE v.estado_real::text = 'sin_fecha'
           AND (a.estado <> 'dado_baja'::estado_activo_enum AND NOT COALESCE(a.es_externo, false))
           AND (CURRENT_DATE - c.created_at::date) >= 30
         GROUP BY 1, 2
    LOOP
        v_sev := CASE WHEN r.dias_max >= 60 THEN 'critical' ELSE 'warning' END;
        v_msg := r.n || ' papel' || CASE WHEN r.n <> 1 THEN 'es' ELSE '' END
              || ' del ' || r.patente || ' están cargados sin fecha de vencimiento: '
              || left(r.tipos, 180)
              || '. Nadie sabe si están vigentes. Se resuelven de una vez en '
              || 'Flota → Control documental.';

        FOR u IN
            SELECT id FROM usuarios_perfil
             WHERE activo = true
               AND rol IN ('administrador','subgerente_operaciones','jefe_mantenimiento','prevencionista')
        LOOP
            -- Un solo aviso abierto por camión y persona: si sigue sin leer, se
            -- reescribe con el conteo de hoy en vez de apilar otro.
            UPDATE alertas
               SET mensaje = v_msg, severidad = v_sev, created_at = NOW()
             WHERE tipo = 'doc_sin_fecha' AND entidad_tipo = 'activo'
               AND entidad_id = r.activo_id AND destinatario_id = u.id AND NOT leida;
            GET DIAGNOSTICS v_upd = ROW_COUNT;

            IF v_upd > 0 THEN
                v_actualizados := v_actualizados + 1;
            ELSE
                INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                                     destinatario_id, requiere_accion, leida, created_at)
                VALUES ('doc_sin_fecha',
                        'Papeles sin vigencia: ' || r.patente,
                        v_msg, v_sev, 'activo', r.activo_id, u.id, true, false, NOW());
                v_nuevos := v_nuevos + 1;
            END IF;
        END LOOP;
    END LOOP;

    RETURN jsonb_build_object('avisos_nuevos', v_nuevos, 'avisos_actualizados', v_actualizados);
END $function$;

-- fn_comercial_equipos(date,date)
CREATE OR REPLACE FUNCTION public.fn_comercial_equipos(p_ini date, p_fin date)
 RETURNS TABLE(activo_id uuid, patente text, equipamiento text, estado_actual character, cliente_actual text, dias_arrendado integer, ultimo_cliente text, fecha_ultimo_arriendo date, dias_sin_arriendo integer)
 LANGUAGE sql
 STABLE
AS $function$
  WITH veh AS (
    SELECT id, patente, nombre
    FROM activos
    WHERE (estado <> 'dado_baja' AND NOT COALESCE(es_externo, false)) AND NOT COALESCE(es_prueba, false)
      AND tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
  )
  SELECT
    v.id,
    v.patente,
    v.nombre,
    (SELECT e.estado_codigo FROM estado_diario_flota e
       WHERE e.activo_id = v.id AND e.fecha <= p_fin ORDER BY e.fecha DESC LIMIT 1),
    (SELECT e.cliente FROM estado_diario_flota e
       WHERE e.activo_id = v.id AND e.fecha <= p_fin ORDER BY e.fecha DESC LIMIT 1),
    (SELECT count(*)::int FROM estado_diario_flota e
       WHERE e.activo_id = v.id AND e.fecha BETWEEN p_ini AND p_fin
         AND e.estado_codigo IN ('A','C')),
    (SELECT e.cliente FROM estado_diario_flota e
       WHERE e.activo_id = v.id AND e.estado_codigo IN ('A','C') AND e.fecha <= p_fin
       ORDER BY e.fecha DESC LIMIT 1),
    (SELECT max(e.fecha) FROM estado_diario_flota e
       WHERE e.activo_id = v.id AND e.estado_codigo IN ('A','C') AND e.fecha <= p_fin),
    (SELECT (p_fin - max(e.fecha))::int FROM estado_diario_flota e
       WHERE e.activo_id = v.id AND e.estado_codigo IN ('A','C') AND e.fecha <= p_fin)
  FROM veh v
  ORDER BY v.patente;
$function$;

-- fn_flota_en_mantenimiento()
CREATE OR REPLACE FUNCTION public.fn_flota_en_mantenimiento()
 RETURNS TABLE(activo_id uuid, patente text, equipamiento text, estado_codigo text, dias_mantencion integer, ultimo_contrato text, motivo text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
    WITH ed AS (
        SELECT e.activo_id, e.fecha, e.estado_codigo, e.cliente,
               e.motivo_override, e.observacion,
               ROW_NUMBER() OVER (PARTITION BY e.activo_id ORDER BY e.fecha DESC) AS rn
        FROM estado_diario_flota e
    ),
    ult AS (  -- ultimo dia por activo, solo flota en M/T/F
        SELECT ed.*
        FROM ed
        JOIN activos a ON a.id = ed.activo_id
        WHERE ed.rn = 1
          AND ed.estado_codigo IN ('M','T','F')
          AND (a.estado <> 'dado_baja' AND NOT COALESCE(a.es_externo, false))
          AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
    ),
    primer_no_mant AS (  -- rn del dia mas reciente NO-mantencion por activo
        SELECT activo_id, MIN(rn) AS rn0
        FROM ed
        WHERE estado_codigo NOT IN ('M','T','F')
        GROUP BY activo_id
    )
    SELECT
        u.activo_id,
        a.patente,
        a.tipo_equipamiento::text,
        u.estado_codigo::text,
        COALESCE(p.rn0 - 1, (SELECT COUNT(*)::int FROM ed WHERE ed.activo_id = u.activo_id))::int AS dias_mantencion,
        COALESCE(
            NULLIF(TRIM(ct.codigo || ' · ' || ct.cliente), '·'),
            NULLIF(u.cliente, ''),
            'Sin contrato'
        ) AS ultimo_contrato,
        CASE
            WHEN u.motivo_override IS NULL OR u.motivo_override ILIKE 'Importado reportabilidad%'
                THEN COALESCE(NULLIF(TRIM(u.observacion), ''), '—')
            ELSE u.motivo_override
        END AS motivo
    FROM ult u
    JOIN activos a       ON a.id = u.activo_id
    LEFT JOIN contratos ct ON ct.id = a.contrato_id
    LEFT JOIN primer_no_mant p ON p.activo_id = u.activo_id
    ORDER BY dias_mantencion DESC, a.patente
$function$;

-- fn_generar_reporte_diario(date)
CREATE OR REPLACE FUNCTION public.fn_generar_reporte_diario(p_fecha date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_payload     JSONB;
    v_inicio_mes  DATE := date_trunc('month', p_fecha)::DATE;
    v_inicio_dia  TIMESTAMPTZ := (p_fecha::TIMESTAMP)::TIMESTAMPTZ;
    v_fin_dia     TIMESTAMPTZ := ((p_fecha + 1)::TIMESTAMP)::TIMESTAMPTZ;
BEGIN
    SELECT jsonb_build_object(
        'fecha', p_fecha,
        'generado_en', NOW(),

        -- ── FLOTA ─────────────────────────────────────────────────────────
        'flota', jsonb_build_object(
            'total_equipos', (
                SELECT COUNT(*) FROM activos WHERE (estado != 'dado_baja' AND NOT COALESCE(es_externo, false))
                  AND tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
            ),
            'por_estado_hoy', (
                SELECT jsonb_object_agg(estado_codigo, cantidad)
                FROM (SELECT estado_codigo, COUNT(*)::INTEGER AS cantidad
                        FROM estado_diario_flota WHERE fecha = p_fecha
                        GROUP BY estado_codigo) s
            ),
            'por_operacion', (
                SELECT jsonb_object_agg(COALESCE(operacion,'Sin asignar'), cantidad)
                FROM (SELECT operacion, COUNT(*)::INTEGER AS cantidad
                        FROM activos WHERE (estado != 'dado_baja' AND NOT COALESCE(es_externo, false)) GROUP BY operacion) s
            ),
            'cambios_24h', (
                SELECT COUNT(*) FROM estado_diario_flota
                 WHERE fecha = p_fecha AND override_manual = true
                   AND actualizado_at >= NOW() - INTERVAL '24 hours'
            )
        ),

        -- ── OEE (mes corriente) ──────────────────────────────────────────
        'oee_mes', (
            SELECT jsonb_build_object(
                'total',    (SELECT to_jsonb(t) FROM calcular_oee_flota(NULL, v_inicio_mes, p_fecha, NULL) t),
                'coquimbo', (SELECT to_jsonb(t) FROM calcular_oee_flota(NULL, v_inicio_mes, p_fecha, 'Coquimbo') t),
                'calama',   (SELECT to_jsonb(t) FROM calcular_oee_flota(NULL, v_inicio_mes, p_fecha, 'Calama') t)
            )
        ),

        -- ── MANTENIMIENTO ────────────────────────────────────────────────
        'mantenimiento', jsonb_build_object(
            'ots_abiertas', (
                SELECT COUNT(*) FROM ordenes_trabajo
                 WHERE estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada','cancelada','cerrada')
            ),
            'ots_creadas_ayer', (
                SELECT COUNT(*) FROM ordenes_trabajo WHERE created_at::DATE = p_fecha - 1
            ),
            'ots_cerradas_ayer', (
                SELECT COUNT(*) FROM ordenes_trabajo WHERE fecha_termino::DATE = p_fecha - 1
            ),
            'por_prioridad', (
                SELECT jsonb_object_agg(prioridad, cantidad)
                FROM (SELECT prioridad, COUNT(*)::INTEGER AS cantidad
                        FROM ordenes_trabajo
                       WHERE estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada','cancelada','cerrada')
                       GROUP BY prioridad) s
            ),
            'tipo_correctivo_abierto', (
                SELECT COUNT(*) FROM ordenes_trabajo
                 WHERE tipo = 'correctivo'
                   AND estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada','cancelada','cerrada')
            )
        ),

        -- ── COBERTURA PM (NUEVO MIG86) ───────────────────────────────────
        'cobertura_pm', (
            SELECT to_jsonb(v) FROM v_mantenimiento_cobertura_resumen v
        ),

        -- ── COMERCIAL ────────────────────────────────────────────────────
        'comercial', jsonb_build_object(
            'arrendados',          (SELECT COUNT(*) FROM estado_diario_flota WHERE fecha = p_fecha AND estado_codigo = 'A'),
            'disponibles_perdida', (SELECT COUNT(*) FROM estado_diario_flota WHERE fecha = p_fecha AND estado_codigo = 'D'),
            'uso_interno',         (SELECT COUNT(*) FROM estado_diario_flota WHERE fecha = p_fecha AND estado_codigo = 'U'),
            'leasing',             (SELECT COUNT(*) FROM estado_diario_flota WHERE fecha = p_fecha AND estado_codigo = 'L'),
            'por_cliente', (
                SELECT jsonb_object_agg(COALESCE(cliente,'Sin cliente'), cantidad)
                FROM (SELECT cliente, COUNT(*)::INTEGER AS cantidad
                        FROM estado_diario_flota
                       WHERE fecha = p_fecha AND estado_codigo = 'A'
                       GROUP BY cliente) s
            )
        ),

        -- ── PREVENCION ───────────────────────────────────────────────────
        'prevencion', (
            SELECT to_jsonb(v) FROM vw_prevencion_resumen v
        ),

        -- ── ALERTAS ──────────────────────────────────────────────────────
        'alertas', jsonb_build_object(
            'criticas_activas', (
                SELECT COUNT(*) FROM alertas WHERE severidad = 'critical' AND leida = false
            ),
            'total_activas', (SELECT COUNT(*) FROM alertas WHERE leida = false),
            'por_entidad_tipo', (
                SELECT jsonb_object_agg(COALESCE(entidad_tipo,'sin_entidad'), cantidad)
                FROM (SELECT entidad_tipo, COUNT(*)::INTEGER AS cantidad
                        FROM alertas WHERE leida = false
                        GROUP BY entidad_tipo) s
            )
        ),

        -- ── RESPEL ───────────────────────────────────────────────────────
        'respel_mes', jsonb_build_object(
            'generado_kg', (
                SELECT COALESCE(SUM(cantidad), 0) FROM respel_movimientos
                 WHERE tipo_movimiento = 'generacion'
                   AND fecha BETWEEN v_inicio_mes AND p_fecha
            ),
            'retirado_kg', (
                SELECT COALESCE(SUM(cantidad), 0) FROM respel_movimientos
                 WHERE tipo_movimiento = 'retiro'
                   AND fecha BETWEEN v_inicio_mes AND p_fecha
            ),
            'pendientes_sidrep', (
                SELECT COUNT(*) FROM respel_movimientos
                 WHERE tipo_movimiento = 'retiro' AND numero_sidrep IS NULL
            )
        ),

        -- ── GPS (NUEVO MIG86) ────────────────────────────────────────────
        'gps', jsonb_build_object(
            'mapeados',             (SELECT gps_mapeados            FROM v_flota_kpi_resumen),
            'sin_gps',              (SELECT sin_gps                 FROM v_flota_kpi_resumen),
            'sin_senal_24h',        (SELECT gps_sin_senal_24h       FROM v_flota_kpi_resumen),
            'en_ruta',              (SELECT gps_en_ruta             FROM v_flota_kpi_resumen),
            'detenido_motor_on',    (SELECT gps_detenido_motor_on   FROM v_flota_kpi_resumen),
            'detenido',             (SELECT gps_detenido            FROM v_flota_kpi_resumen),
            'offline',              (SELECT gps_offline             FROM v_flota_kpi_resumen),
            'bateria_baja_count', (
                SELECT COUNT(*) FROM gps_estado_actual
                 WHERE bateria_pct IS NOT NULL AND bateria_pct < 20
            ),
            'eventos_log_24h', (
                SELECT COUNT(*) FROM gps_eventos_log
                 WHERE ts_gps >= v_inicio_dia AND ts_gps < v_fin_dia
            )
        ),

        -- ── GEOCERCAS (NUEVO MIG86) ──────────────────────────────────────
        'geocercas', jsonb_build_object(
            'total_activas',         (SELECT COUNT(*) FROM gps_geocercas WHERE activo = true),
            'en_zona_esperada',      (SELECT en_zona_esperada       FROM v_flota_kpi_resumen),
            'fuera_zona_esperada',   (SELECT fuera_zona_esperada    FROM v_flota_kpi_resumen),
            'sin_dato_zona',         (SELECT sin_dato_zona          FROM v_flota_kpi_resumen),
            'eventos_dia', jsonb_build_object(
                'total',    (SELECT COUNT(*) FROM gps_geocerca_eventos WHERE ts >= v_inicio_dia AND ts < v_fin_dia),
                'entradas', (SELECT COUNT(*) FROM gps_geocerca_eventos WHERE ts >= v_inicio_dia AND ts < v_fin_dia AND tipo_evento = 'entrada'),
                'salidas',  (SELECT COUNT(*) FROM gps_geocerca_eventos WHERE ts >= v_inicio_dia AND ts < v_fin_dia AND tipo_evento = 'salida')
            ),
            'ocupacion_actual', (
                SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'geocerca', geocerca_nombre,
                    'tipo',     geocerca_tipo,
                    'activos_dentro', activos_dentro
                ) ORDER BY activos_dentro DESC), '[]'::jsonb)
                FROM (
                    SELECT geocerca_nombre,
                           geocerca_tipo::text AS geocerca_tipo,
                           COUNT(*)::INTEGER  AS activos_dentro
                      FROM v_geocerca_ocupacion
                     GROUP BY geocerca_nombre, geocerca_tipo
                ) s
            ),
            'fuera_de_zona_detalle', (
                SELECT COALESCE(jsonb_agg(jsonb_build_object(
                    'activo_codigo', activo_codigo,
                    'patente',       patente,
                    'cliente',       contrato_cliente,
                    'geocerca_esperada', geocerca_esperada,
                    'gps_estado_pin', gps_estado_pin
                )), '[]'::jsonb)
                  FROM v_flota_dashboard_unificado
                 WHERE en_zona_esperada = false
            )
        ),

        -- ── FLOTA KPI consolidado (NUEVO MIG86) ──────────────────────────
        'flota_kpi', (SELECT to_jsonb(k) FROM v_flota_kpi_resumen k)
    )
    INTO v_payload;

    RETURN v_payload;
END;
$function$;

-- fn_kpi_disponibilidad_flota_movil(uuid,uuid,date,date)
CREATE OR REPLACE FUNCTION public.fn_kpi_disponibilidad_flota_movil(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
    v_disp NUMERIC;
BEGIN
    WITH flota AS (
        SELECT a.id
          FROM activos a
         WHERE (a.estado != 'dado_baja' AND NOT COALESCE(a.es_externo, false))
           AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil')
           AND (p_contrato_id IS NULL OR a.contrato_id = p_contrato_id)
           AND (p_faena_id    IS NULL OR a.faena_id    = p_faena_id)
    ),
    por_activo AS (
        SELECT f.*
          FROM flota
     CROSS JOIN LATERAL fn_calcular_fiabilidad_activo(
                  flota.id, p_periodo_inicio, p_periodo_fin
                ) f
    )
    SELECT ROUND(AVG(disponibilidad_inherente) * 100, 2)
      INTO v_disp
      FROM por_activo;

    RETURN COALESCE(v_disp, 0);
END;
$function$;

-- fn_kpi_mttr_moviles(uuid,uuid,date,date)
CREATE OR REPLACE FUNCTION public.fn_kpi_mttr_moviles(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
    v_mttr NUMERIC;
BEGIN
    WITH flota AS (
        SELECT a.id
          FROM activos a
         WHERE (a.estado != 'dado_baja' AND NOT COALESCE(a.es_externo, false))
           AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil')
           AND (p_contrato_id IS NULL OR a.contrato_id = p_contrato_id)
           AND (p_faena_id    IS NULL OR a.faena_id    = p_faena_id)
    ),
    por_activo AS (
        SELECT f.mttr_dias
          FROM flota
     CROSS JOIN LATERAL fn_calcular_fiabilidad_activo(
                  flota.id, p_periodo_inicio, p_periodo_fin
                ) f
        -- Solo consideramos equipos que tuvieron al menos un evento de falla
         WHERE f.eventos_falla > 0
    )
    SELECT ROUND(AVG(mttr_dias), 2)
      INTO v_mttr
      FROM por_activo;

    RETURN COALESCE(v_mttr, 0);
END;
$function$;

-- fn_kpi_oee_fiabilidad_moviles(uuid,uuid,date,date)
CREATE OR REPLACE FUNCTION public.fn_kpi_oee_fiabilidad_moviles(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
    v_oee NUMERIC;
BEGIN
    WITH flota AS (
        SELECT a.id
          FROM activos a
         WHERE (a.estado != 'dado_baja' AND NOT COALESCE(a.es_externo, false))
           AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil')
           AND (p_contrato_id IS NULL OR a.contrato_id = p_contrato_id)
           AND (p_faena_id    IS NULL OR a.faena_id    = p_faena_id)
    ),
    por_activo AS (
        SELECT o.oee_total
          FROM flota
     CROSS JOIN LATERAL fn_calcular_oee_fiabilidad_activo(
                  flota.id, p_periodo_inicio, p_periodo_fin
                ) o
         WHERE o.oee_total IS NOT NULL  -- excluir equipos 100% uso interno
    )
    SELECT ROUND(AVG(oee_total) * 100, 2)
      INTO v_oee
      FROM por_activo;

    RETURN COALESCE(v_oee, 0);
END;
$function$;

-- fn_panel_disponibilidad(date,date,text)
CREATE OR REPLACE FUNCTION public.fn_panel_disponibilidad(p_desde date, p_hasta date, p_operacion text DEFAULT NULL::text)
 RETURNS TABLE(activo_id uuid, codigo text, patente text, nombre text, operacion text, dias_obs integer, dias_up integer, dias_down integer, disponibilidad_pct numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT a.id,
           a.codigo::TEXT,
           a.patente::TEXT,
           a.nombre::TEXT,
           COALESCE(e.operacion, a.operacion)::TEXT,
           count(*)::INTEGER,
           count(*) FILTER (WHERE e.estado_codigo NOT IN ('M','T','F'))::INTEGER,
           count(*) FILTER (WHERE e.estado_codigo IN ('M','T','F'))::INTEGER,
           ROUND(100.0 * count(*) FILTER (WHERE e.estado_codigo NOT IN ('M','T','F'))
                 / NULLIF(count(*), 0), 1)
      FROM estado_diario_flota e
      JOIN activos a ON a.id = e.activo_id
     WHERE e.fecha BETWEEN p_desde AND p_hasta
       AND e.estado_codigo NOT IN ('S','B')
       AND (a.estado <> 'dado_baja' AND NOT COALESCE(a.es_externo, false))   -- MIG589
       AND (p_operacion IS NULL OR COALESCE(e.operacion, a.operacion) = p_operacion)
     GROUP BY a.id, a.codigo, a.patente, a.nombre, COALESCE(e.operacion, a.operacion)
     ORDER BY 9 ASC NULLS LAST, 8 DESC;
$function$;

-- fn_panel_equipos_detenidos(date,date,text,integer,date)
CREATE OR REPLACE FUNCTION public.fn_panel_equipos_detenidos(p_desde date, p_hasta date, p_operacion text DEFAULT NULL::text, p_limit integer DEFAULT 10, p_semana date DEFAULT NULL::date)
 RETURNS TABLE(activo_id uuid, codigo text, patente text, nombre text, operacion text, dias_detenido integer, dias_obs integer, pct_detenido numeric, estado_actual text, detenido_desde date, dias_consecutivos integer, ot_folio text, ot_estado text, ot_tipo text, comentario text, plan_accion text, responsable text, fecha_compromiso date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    WITH dias AS (
        SELECT e.activo_id,
               e.fecha,
               e.estado_codigo,
               (e.estado_codigo IN ('M','T','F')) AS down
          FROM estado_diario_flota e
          JOIN activos a ON a.id = e.activo_id
         WHERE e.fecha BETWEEN p_desde AND p_hasta
           AND e.estado_codigo NOT IN ('S','B')
           AND (a.estado <> 'dado_baja' AND NOT COALESCE(a.es_externo, false))   -- MIG589
           AND (p_operacion IS NULL OR COALESCE(e.operacion, a.operacion) = p_operacion)
    ),
    agg AS (
        SELECT activo_id,
               count(*)::INTEGER                              AS dias_obs,
               count(*) FILTER (WHERE down)::INTEGER           AS dias_detenido,
               -- Último día NO detenido: lo que venga después es la racha viva.
               max(fecha) FILTER (WHERE NOT down)              AS ultimo_ok,
               max(fecha)                                      AS ultima_fecha,
               (array_agg(estado_codigo ORDER BY fecha DESC))[1] AS estado_actual,
               (array_agg(down          ORDER BY fecha DESC))[1] AS down_actual
          FROM dias
         GROUP BY activo_id
        HAVING count(*) FILTER (WHERE down) > 0
    ),
    ot AS (
        -- OT abierta más reciente por equipo. Lista blanca de estados abiertos.
        SELECT DISTINCT ON (o.activo_id)
               o.activo_id, o.folio::TEXT, o.estado::TEXT, o.tipo::TEXT
          FROM ordenes_trabajo o
         WHERE o.estado::TEXT IN ('creada','asignada','en_ejecucion','pausada')
           AND o.activo_id IS NOT NULL
         ORDER BY o.activo_id, o.created_at DESC
    )
    SELECT a.id,
           a.codigo::TEXT,
           a.patente::TEXT,
           a.nombre::TEXT,
           COALESCE(a.operacion, '—')::TEXT,
           g.dias_detenido,
           g.dias_obs,
           ROUND(100.0 * g.dias_detenido / NULLIF(g.dias_obs, 0), 1),
           g.estado_actual::TEXT,
           CASE WHEN g.down_actual THEN COALESCE(g.ultimo_ok + 1, p_desde) END,
           CASE WHEN g.down_actual
                THEN (g.ultima_fecha - COALESCE(g.ultimo_ok, p_desde - 1))::INTEGER
                ELSE 0 END,
           ot.folio, ot.estado, ot.tipo,
           c.texto, c.plan_accion, c.responsable::TEXT, c.fecha_compromiso
      FROM agg g
      JOIN activos a ON a.id = g.activo_id
      LEFT JOIN ot ON ot.activo_id = g.activo_id
      LEFT JOIN panel_comentarios c
             ON c.ambito    = 'equipo'
            AND c.activo_id = g.activo_id
            AND c.semana    = COALESCE(p_semana, date_trunc('week', p_hasta)::DATE)
     ORDER BY g.dias_detenido DESC, g.dias_obs DESC
     LIMIT GREATEST(p_limit, 1);
$function$;

-- fn_propuesta_cierre_diario(date)
CREATE OR REPLACE FUNCTION public.fn_propuesta_cierre_diario(p_fecha date DEFAULT CURRENT_DATE)
 RETURNS TABLE(activo_id uuid, patente character varying, codigo character varying, equipamiento character varying, cliente_actual character varying, contrato_id uuid, contrato_label text, estado_previo character, estado_sugerido character, geocerca_nombre character varying, gps_ts timestamp with time zone, gps_lat numeric, gps_lng numeric, ya_confirmado boolean, estado_dia_actual character)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        a.id,
        a.patente,
        a.codigo,
        a.nombre AS equipamiento,
        a.cliente_actual,
        a.contrato_id,
        (c.codigo || COALESCE(' · ' || c.cliente, ''))::text AS contrato_label,
        prev.estado_codigo AS estado_previo,
        -- Uso interno: SIEMPRE 'U' (no se sugiere cambio por geocerca).
        -- El resto: sugerido por geocerca, fallback al dia previo, luego 'D'.
        (CASE
            WHEN a.estado_comercial = 'uso_interno' THEN 'U'
            ELSE COALESCE(fn_estado_por_geocerca(a.id), prev.estado_codigo, 'D')
         END)::char(1) AS estado_sugerido,
        geo.nombre AS geocerca_nombre,
        g.ts_gps,
        g.latitud,
        g.longitud,
        (hoy.activo_id IS NOT NULL AND hoy.override_manual) AS ya_confirmado,
        hoy.estado_codigo AS estado_dia_actual
    FROM activos a
    LEFT JOIN contratos c ON c.id = a.contrato_id
    LEFT JOIN gps_estado_actual g ON g.activo_id = a.id
    LEFT JOIN LATERAL (
        SELECT e.estado_codigo
          FROM estado_diario_flota e
         WHERE e.activo_id = a.id AND e.fecha < p_fecha
         ORDER BY e.fecha DESC
         LIMIT 1
    ) prev ON true
    LEFT JOIN LATERAL (
        SELECT e.activo_id, e.estado_codigo, e.override_manual
          FROM estado_diario_flota e
         WHERE e.activo_id = a.id AND e.fecha = p_fecha
    ) hoy ON true
    LEFT JOIN LATERAL (
        SELECT gg.nombre
          FROM gps_geocercas gg
         WHERE gg.activo
           AND g.latitud IS NOT NULL
           AND fn_punto_en_geocerca(g.latitud, g.longitud, gg.id)
         ORDER BY gg.radio_m ASC
         LIMIT 1
    ) geo ON true
    WHERE (a.estado != 'dado_baja' AND NOT COALESCE(a.es_externo, false))
      AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
    ORDER BY a.patente NULLS LAST, a.codigo;
END $function$;

-- fn_reporte_fiabilidad_publico(date,date,text)
CREATE OR REPLACE FUNCTION public.fn_reporte_fiabilidad_publico(p_ini date DEFAULT (date_trunc('month'::text, (CURRENT_DATE)::timestamp with time zone))::date, p_fin date DEFAULT CURRENT_DATE, p_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
        -- NUEVO: coordenada GPS para el link al mapa
        'gps_lat', ge.latitud,
        'gps_lng', ge.longitud,
        'gps_ts',  ge.ts_gps,
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
      LEFT JOIN gps_estado_actual ge ON ge.activo_id = a.id
      CROSS JOIN LATERAL fn_calcular_fiabilidad_activo(a.id, p_ini, p_fin) f
      WHERE (a.estado <> 'dado_baja' AND NOT COALESCE(a.es_externo, false))
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
        AND e.estado_codigo <> 'B'   -- MIG585
        AND (a.estado <> 'dado_baja' AND NOT COALESCE(a.es_externo, false))
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
      WHERE es_bodega   -- MIG393: la bodega de Coquimbo, por operación y no por nombre
    ), '[]'::jsonb)
    ) INTO v_out;

    RETURN v_out;
END $function$;

-- fn_reporte_flota_publico()
CREATE OR REPLACE FUNCTION public.fn_reporte_flota_publico()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
WITH veh AS (
  SELECT a.id, a.patente, a.nombre,
         COALESCE(c.cliente, 'Sin contrato') AS cliente_actual
    FROM activos a
    LEFT JOIN contratos c ON c.id = a.contrato_id
   WHERE (a.estado <> 'dado_baja' AND NOT COALESCE(a.es_externo, false))
     AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
),
ult AS (
  SELECT max(fecha) AS f FROM estado_diario_flota WHERE activo_id IN (SELECT id FROM veh)
),
hoy AS (
  SELECT v.cliente_actual AS cliente, e.estado_codigo, e.operacion
    FROM estado_diario_flota e JOIN veh v ON v.id = e.activo_id
   WHERE e.fecha = (SELECT f FROM ult)
),
mes AS (
  SELECT count(*) AS dias,
         count(*) FILTER (WHERE estado_codigo IN ('A','C','D','L','U')) AS up,
         count(*) FILTER (WHERE estado_codigo IN ('A','C','L')) AS util
    FROM estado_diario_flota e JOIN veh v ON v.id = e.activo_id
   WHERE e.fecha >= date_trunc('month', (SELECT f FROM ult))
)
SELECT jsonb_build_object(
  'fecha',          (SELECT f FROM ult),
  'total',          (SELECT count(*) FROM hoy),
  'por_estado',     (SELECT jsonb_object_agg(estado_codigo, n) FROM (SELECT estado_codigo, count(*) n FROM hoy GROUP BY 1) s),
  'por_operacion',  (SELECT jsonb_object_agg(coalesce(operacion,'Sin asignar'), n) FROM (SELECT operacion, count(*) n FROM hoy GROUP BY 1) s),
  'por_cliente',    (SELECT jsonb_agg(jsonb_build_object('cliente', cliente, 'equipos', n) ORDER BY n DESC) FROM (SELECT cliente, count(*) n FROM hoy GROUP BY 1) s),
  'disponibilidad', (SELECT round(100.0 * up / nullif(dias,0), 1) FROM mes),
  'utilizacion',    (SELECT round(100.0 * util / nullif(dias,0), 1) FROM mes),
  'equipos',        (
    SELECT jsonb_agg(jsonb_build_object(
             'patente', q.patente, 'equipamiento', q.equipamiento, 'estado', q.estado,
             'dias_arrendado', q.dias, 'ultimo_cliente', q.ultimo_cliente, 'dias_sin_arriendo', q.dias_sin
           ) ORDER BY q.dias DESC)
    FROM (
      SELECT v.patente, v.nombre AS equipamiento,
        (SELECT e.estado_codigo FROM estado_diario_flota e WHERE e.activo_id=v.id AND e.fecha<=(SELECT f FROM ult) ORDER BY e.fecha DESC LIMIT 1) AS estado,
        (SELECT count(*)::int FROM estado_diario_flota e WHERE e.activo_id=v.id AND e.fecha >= date_trunc('year',(SELECT f FROM ult)) AND e.fecha<=(SELECT f FROM ult) AND e.estado_codigo IN ('A','C')) AS dias,
        v.cliente_actual AS ultimo_cliente,
        (SELECT ((SELECT f FROM ult) - max(e.fecha))::int FROM estado_diario_flota e WHERE e.activo_id=v.id AND e.estado_codigo IN ('A','C') AND e.fecha<=(SELECT f FROM ult)) AS dias_sin
      FROM veh v
    ) q
  )
);
$function$;

-- fn_sugerencias_estado_gps(date)
CREATE OR REPLACE FUNCTION public.fn_sugerencias_estado_gps(p_fecha date DEFAULT CURRENT_DATE)
 RETURNS TABLE(activo_id uuid, patente text, equipamiento text, estado_actual character, estado_sugerido character, estado_guardado character, zona text, gps_ts timestamp with time zone, coincide boolean, evidencia_fecha timestamp with time zone, evidencia_fuente text, evidencia_dias integer, centinela text, requiere_justificacion boolean)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT
    a.id,
    a.patente::text,
    a.nombre::text,
    prev.estado_codigo AS estado_actual,
    COALESCE(fn_estado_por_geocerca(a.id), prev.estado_codigo, 'D')::character(1) AS estado_sugerido,
    (SELECT e.estado_codigo FROM estado_diario_flota e
       WHERE e.activo_id = a.id AND e.fecha = p_fecha LIMIT 1) AS estado_guardado,
    (SELECT g.nombre FROM gps_geocercas g
       WHERE g.activo AND ga.latitud IS NOT NULL
         AND fn_punto_en_geocerca(ga.latitud, ga.longitud, g.id)
       ORDER BY (g.tipo = 'faena_cliente') DESC, g.radio_m ASC LIMIT 1) AS zona,
    ga.ts_gps,
    (prev.estado_codigo = COALESCE(fn_estado_por_geocerca(a.id), prev.estado_codigo, 'D')) AS coincide,
    pv.fecha, pv.fuente, pv.dias, pv.centinela, pv.requiere
  FROM activos a
  LEFT JOIN gps_estado_actual ga ON ga.activo_id = a.id
  LEFT JOIN LATERAL (
    SELECT e.estado_codigo
      FROM estado_diario_flota e
     WHERE e.activo_id = a.id AND e.fecha < p_fecha
     ORDER BY e.fecha DESC LIMIT 1
  ) prev ON true
  LEFT JOIN LATERAL fn_prueba_de_vida_estado(a.id) pv ON true
  WHERE ((a.estado <> 'dado_baja' AND NOT COALESCE(a.es_externo, false))
         OR EXISTS (SELECT 1 FROM estado_diario_flota eb
                     WHERE eb.activo_id = a.id AND eb.fecha = p_fecha
                       AND eb.estado_codigo = 'B'))   -- MIG585
    AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
    AND NOT COALESCE(a.es_prueba, false)   -- MIG564: el equipo de prueba no se planifica
  ORDER BY a.patente;
$function$;

-- fn_verificar_antiguedad_flota()
CREATE OR REPLACE FUNCTION public.fn_verificar_antiguedad_flota()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_anio_actual INTEGER := EXTRACT(YEAR FROM CURRENT_DATE);
    v_count INTEGER := 0;
    v_activo RECORD;
BEGIN
    FOR v_activo IN
        SELECT id, patente, anio_fabricacion, nombre
        FROM activos
        WHERE anio_fabricacion IS NOT NULL
          AND (v_anio_actual - anio_fabricacion) > 15
          AND (estado != 'dado_baja' AND NOT COALESCE(es_externo, false))
          AND tipo IN ('camion_cisterna', 'camion', 'camioneta', 'lubrimovil')
    LOOP
        -- Crear alerta si no existe una reciente
        IF NOT EXISTS (
            SELECT 1 FROM alertas
            WHERE entidad_id = v_activo.id
              AND tipo = 'antiguedad_vehiculo'
              AND created_at > CURRENT_DATE - INTERVAL '30 days'
        ) THEN
            INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
            VALUES (
                'antiguedad_vehiculo',
                'BLOQUEO DS 298: Vehículo supera 15 años',
                format('El vehículo %s (PPU: %s, año %s) tiene %s años de antigüedad. '
                       'Según DS 298, no puede operar en transporte de sustancias peligrosas. '
                       'Requiere evaluación especial o dar de baja.',
                       v_activo.nombre, v_activo.patente, v_activo.anio_fabricacion,
                       v_anio_actual - v_activo.anio_fabricacion),
                'critical',
                'activo',
                v_activo.id
            );
            v_count := v_count + 1;
        END IF;
    END LOOP;
    RETURN v_count;
END;
$function$;

-- fn_verificar_certificaciones_flota()
CREATE OR REPLACE FUNCTION public.fn_verificar_certificaciones_flota()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_count INTEGER := 0;
    v_cert RECORD;
BEGIN
    FOR v_cert IN
        SELECT
            c.id, c.tipo, c.fecha_vencimiento, c.bloqueante,
            a.id AS activo_id, a.patente, a.nombre AS activo_nombre,
            CASE
                WHEN c.fecha_vencimiento < CURRENT_DATE THEN 'vencida'
                WHEN c.fecha_vencimiento < CURRENT_DATE + INTERVAL '45 days' THEN 'por_vencer'
            END AS estado_cert
        -- [MIG273] Solo la versión vigente: antes alertaba también por cada
        -- versión antigua ya renovada.
        FROM v_certificacion_actual c
        JOIN activos a ON a.id = c.activo_id
        WHERE (a.estado != 'dado_baja' AND NOT COALESCE(a.es_externo, false))
          AND c.estado_real != 'vencido'
          AND c.fecha_vencimiento < CURRENT_DATE + INTERVAL '45 days'
          AND c.tipo IN ('revision_tecnica', 'hermeticidad', 'tc8_sec', 'inscripcion_sec',
                         'soap', 'permiso_circulacion', 'seguro_rc')
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM alertas
            WHERE entidad_id = v_cert.id
              AND tipo IN ('rt_por_vencer', 'hermeticidad_vencida', 'sec_no_vigente', 'vencimiento')
              AND created_at > CURRENT_DATE - INTERVAL '7 days'
        ) THEN
            INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
            VALUES (
                CASE v_cert.tipo
                    WHEN 'revision_tecnica' THEN 'rt_por_vencer'
                    WHEN 'hermeticidad' THEN 'hermeticidad_vencida'
                    WHEN 'tc8_sec' THEN 'sec_no_vigente'
                    WHEN 'inscripcion_sec' THEN 'sec_no_vigente'
                    ELSE 'vencimiento'
                END,
                format('%s: %s — %s %s',
                    CASE WHEN v_cert.estado_cert = 'vencida' THEN 'BLOQUEO' ELSE 'ALERTA' END,
                    v_cert.tipo,
                    v_cert.activo_nombre,
                    COALESCE('(PPU: ' || v_cert.patente || ')', '')),
                format('Certificación %s del equipo %s %s el %s.',
                    v_cert.tipo, v_cert.activo_nombre,
                    CASE WHEN v_cert.estado_cert = 'vencida' THEN 'VENCIÓ' ELSE 'vence' END,
                    v_cert.fecha_vencimiento),
                CASE WHEN v_cert.estado_cert = 'vencida' THEN 'critical' ELSE 'warning' END,
                'certificacion',
                v_cert.id
            );
            v_count := v_count + 1;
        END IF;
    END LOOP;
    RETURN v_count;
END;
$function$;

-- fn_verificar_disponibilidad_vigente()
CREATE OR REPLACE FUNCTION public.fn_verificar_disponibilidad_vigente()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_count INTEGER := 0;
    v_activo RECORD;
BEGIN
    FOR v_activo IN
        SELECT a.id, a.patente, a.nombre, a.estado_comercial,
               a.verificacion_vigente_hasta
        FROM activos a
        WHERE (a.estado != 'dado_baja' AND NOT COALESCE(a.es_externo, false))
          AND a.estado_comercial = 'disponible'
          AND (a.verificacion_vigente_hasta IS NULL
               OR a.verificacion_vigente_hasta < NOW())
    LOOP
        -- Marcar como ya no disponible: requiere re-verificación
        UPDATE activos
        SET estado_comercial = 'en_recepcion'  -- Fuerza re-verificación
        WHERE id = v_activo.id
          AND estado_comercial = 'disponible';

        INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
        VALUES (
            'disponibilidad_vencida',
            format('Verificación vencida: %s retirado de disponibles',
                   COALESCE(v_activo.patente, v_activo.nombre)),
            format('El equipo %s (PPU: %s) tenía checklist vigente hasta %s. '
                   'Ha sido retirado de disponibles. Requiere nueva verificación.',
                   v_activo.nombre, v_activo.patente, v_activo.verificacion_vigente_hasta),
            'warning',
            'activo',
            v_activo.id
        );
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$function$;

-- fn_verificar_planes_preventivos()
CREATE OR REPLACE FUNCTION public.fn_verificar_planes_preventivos()
 RETURNS TABLE(plan_id uuid, activo_id uuid, patente character varying, plan_nombre character varying, tipo_plan character varying, km_actual numeric, km_ultima_ejecucion numeric, km_proxima numeric, km_restantes numeric, hrs_actual numeric, hrs_ultima numeric, hrs_proxima numeric, hrs_restantes numeric, fecha_proxima date, dias_restantes integer, estado_plan character varying)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        pm.id AS plan_id,
        a.id AS activo_id,
        a.patente,
        pm.nombre::VARCHAR AS plan_nombre,
        pm.tipo_plan::VARCHAR,

        COALESCE(a.kilometraje_actual, 0) AS km_actual,
        COALESCE(pm.ultima_ejecucion_km, 0) AS km_ultima_ejecucion,
        COALESCE(pm.ultima_ejecucion_km, 0) + COALESCE(pm.frecuencia_km, 0) AS km_proxima,
        CASE WHEN pm.frecuencia_km IS NOT NULL
             THEN (COALESCE(pm.ultima_ejecucion_km, 0) + pm.frecuencia_km) - COALESCE(a.kilometraje_actual, 0)
             ELSE NULL END AS km_restantes,

        COALESCE(a.horas_uso_actual, 0) AS hrs_actual,
        COALESCE(pm.ultima_ejecucion_horas, 0) AS hrs_ultima,
        COALESCE(pm.ultima_ejecucion_horas, 0) + COALESCE(pm.frecuencia_horas, 0) AS hrs_proxima,
        CASE WHEN pm.frecuencia_horas IS NOT NULL
             THEN (COALESCE(pm.ultima_ejecucion_horas, 0) + pm.frecuencia_horas) - COALESCE(a.horas_uso_actual, 0)
             ELSE NULL END AS hrs_restantes,

        pm.proxima_ejecucion_fecha AS fecha_proxima,
        CASE WHEN pm.proxima_ejecucion_fecha IS NOT NULL
             THEN (pm.proxima_ejecucion_fecha - CURRENT_DATE)::INTEGER
             ELSE NULL END AS dias_restantes,

        CASE
            WHEN pm.frecuencia_km IS NOT NULL
                 AND COALESCE(a.kilometraje_actual, 0) >= (COALESCE(pm.ultima_ejecucion_km, 0) + pm.frecuencia_km)
                 THEN 'VENCIDO_KM'
            WHEN pm.frecuencia_horas IS NOT NULL
                 AND COALESCE(a.horas_uso_actual, 0) >= (COALESCE(pm.ultima_ejecucion_horas, 0) + pm.frecuencia_horas)
                 THEN 'VENCIDO_HRS'
            WHEN pm.proxima_ejecucion_fecha IS NOT NULL
                 AND pm.proxima_ejecucion_fecha <= CURRENT_DATE
                 THEN 'VENCIDO_FECHA'
            WHEN pm.frecuencia_km IS NOT NULL
                 AND COALESCE(a.kilometraje_actual, 0) >= (COALESCE(pm.ultima_ejecucion_km, 0) + pm.frecuencia_km - 1000)
                 THEN 'PROXIMO_KM'
            WHEN pm.proxima_ejecucion_fecha IS NOT NULL
                 AND pm.proxima_ejecucion_fecha <= CURRENT_DATE + pm.anticipacion_dias
                 THEN 'PROXIMO_FECHA'
            ELSE 'OK'
        END::VARCHAR AS estado_plan

    FROM planes_mantenimiento pm
    JOIN activos a ON a.id = pm.activo_id
    WHERE pm.activo_plan = true
      AND (a.estado != 'dado_baja' AND NOT COALESCE(a.es_externo, false))
    ORDER BY
        CASE
            WHEN pm.frecuencia_km IS NOT NULL
                 AND COALESCE(a.kilometraje_actual, 0) >= (COALESCE(pm.ultima_ejecucion_km, 0) + pm.frecuencia_km)
                 THEN 0  -- Vencido por km primero
            WHEN pm.proxima_ejecucion_fecha IS NOT NULL
                 AND pm.proxima_ejecucion_fecha <= CURRENT_DATE
                 THEN 1  -- Vencido por fecha
            ELSE 2
        END,
        COALESCE(
            CASE WHEN pm.frecuencia_km IS NOT NULL
                 THEN (COALESCE(pm.ultima_ejecucion_km, 0) + pm.frecuencia_km) - COALESCE(a.kilometraje_actual, 0)
                 ELSE NULL END,
            999999
        );
END;
$function$;

-- rpc_admin_sembrar_planes_faltantes()
CREATE OR REPLACE FUNCTION public.rpc_admin_sembrar_planes_faltantes()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT;
    v_a    RECORD;
    v_tot_activos INT := 0;
    v_tot_creados INT := 0;
    v_creados_act INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para sembrar planes', v_rol;
    END IF;

    FOR v_a IN
        SELECT id, codigo FROM activos
         WHERE (estado != 'dado_baja' AND NOT COALESCE(es_externo, false))
           AND modelo_id IS NOT NULL
         ORDER BY codigo
    LOOP
        v_creados_act := fn_auto_crear_planes_activo(v_a.id);
        v_tot_activos := v_tot_activos + 1;
        v_tot_creados := v_tot_creados + v_creados_act;
    END LOOP;

    RETURN jsonb_build_object(
        'success',         true,
        'activos_revisados', v_tot_activos,
        'planes_creados',  v_tot_creados
    );
END;
$function$;

-- VIEW v_control_documental
CREATE OR REPLACE VIEW public.v_control_documental AS
 SELECT a.id AS activo_id,
    COALESCE(a.patente, a.codigo) AS patente,
    a.codigo AS activo_codigo,
    a.nombre AS activo_nombre,
    (a.tipo)::text AS activo_tipo,
    (a.estado)::text AS activo_estado,
    v.id AS certificacion_id,
    (v.tipo)::text AS tipo,
    v.numero_certificado,
    v.entidad_certificadora,
    v.fecha_emision,
    v.fecha_vencimiento,
    (v.estado_real)::text AS estado,
    v.dias_restantes,
    v.archivo_url,
    v.bloqueante,
    c.fecha_origen,
    p.id AS propuesta_id,
    p.vencimiento_propuesto,
    p.emision_propuesta,
    p.confianza AS propuesta_confianza,
    p.regla AS propuesta_regla,
    p.evidencia AS propuesta_evidencia,
    ((p.vencimiento_propuesto IS NOT NULL) AND (p.vencimiento_propuesto < CURRENT_DATE)) AS propuesta_vencida,
    fn_certificado_tipo_permanente((v.tipo)::text) AS tipo_no_caduca,
    c.vigencia_observacion,
    c.vigencia_dudosa_nota,
    c.tipo_otro,
    fn_certificado_etiqueta((v.tipo)::text, c.tipo_otro) AS etiqueta,
    c.notas AS descripcion,
    v.horometro_emision,
    v.horometro_vence,
    v.horas_restantes
   FROM (((v_certificacion_actual v
     JOIN activos a ON ((a.id = v.activo_id)))
     JOIN certificaciones c ON ((c.id = v.id)))
     LEFT JOIN certificacion_propuestas p ON (((p.certificacion_id = v.id) AND (p.estado = 'pendiente'::text))))
  WHERE ((a.estado <> 'dado_baja'::estado_activo_enum AND NOT COALESCE(a.es_externo, false)));

-- VIEW v_documentos_equipo_estado
CREATE OR REPLACE VIEW public.v_documentos_equipo_estado AS
 WITH ult AS (
         SELECT DISTINCT ON (c.activo_id, c.tipo) c.activo_id,
            c.tipo,
            c.fecha_emision,
            c.fecha_vencimiento,
            c.estado,
            c.archivo_url,
            c.numero_certificado,
            c.entidad_certificadora,
            c.bloqueante
           FROM certificaciones c
          ORDER BY c.activo_id, c.tipo, c.fecha_vencimiento DESC NULLS LAST
        )
 SELECT u.activo_id,
    a.patente,
    a.codigo,
    a.nombre,
    a.estado AS activo_estado,
    a.operacion,
    (u.tipo)::text AS tipo,
    u.fecha_emision,
    u.fecha_vencimiento,
    u.estado AS estado_documento,
    u.bloqueante,
    u.archivo_url,
    u.numero_certificado,
    u.entidad_certificadora,
    (u.fecha_vencimiento - CURRENT_DATE) AS dias_restantes
   FROM (ult u
     JOIN activos a ON ((a.id = u.activo_id)))
  WHERE (((a.estado <> 'dado_baja'::estado_activo_enum AND NOT COALESCE(a.es_externo, false))) AND (u.fecha_vencimiento IS NOT NULL));

-- VIEW v_flota_posiciones
CREATE OR REPLACE VIEW public.v_flota_posiciones AS
 SELECT a.id AS activo_id,
    a.codigo AS activo_codigo,
    a.patente AS activo_patente,
    a.nombre AS activo_nombre,
    a.tipo AS activo_tipo,
    a.tipo_equipamiento,
    a.estado AS activo_estado,
    a.estado_comercial AS activo_estado_comercial,
    a.kilometraje_actual AS km_actual,
    a.horas_uso_actual AS horas_actual,
    c.id AS contrato_id,
    c.codigo AS contrato_codigo,
    c.cliente,
    gam.gps_device_id,
    gam.gps_device_name,
    gam.imei,
    p.nombre AS proveedor,
    e.ts_gps,
    e.ts_actualizado,
    e.latitud,
    e.longitud,
    e.velocidad_kmh,
    e.heading,
    e.ignicion,
    e.movimiento,
    e.conexion,
    e.odometro_km,
    e.horometro_hrs,
    e.bateria_pct,
    e.gsm_red,
        CASE
            WHEN ((e.ts_gps IS NULL) OR (e.conexion IS NULL)) THEN 'sin_datos'::text
            WHEN ((e.conexion)::text = 'offline'::text) THEN 'sin_senal'::text
            WHEN (COALESCE(e.velocidad_kmh, (0)::numeric) >= (5)::numeric) THEN 'en_ruta'::text
            WHEN (e.ignicion = true) THEN 'detenido_motor_on'::text
            ELSE 'detenido'::text
        END AS estado_pin,
        CASE
            WHEN (e.ts_gps IS NULL) THEN NULL::integer
            ELSE ((EXTRACT(epoch FROM (now() - e.ts_gps)))::integer / 60)
        END AS minutos_desde_reporte
   FROM ((((gps_activo_mapeo gam
     JOIN config_gps_proveedor p ON ((p.id = gam.proveedor_id)))
     JOIN activos a ON ((a.id = gam.activo_id)))
     LEFT JOIN gps_estado_actual e ON ((e.activo_id = a.id)))
     LEFT JOIN contratos c ON ((c.id = a.contrato_id)))
  WHERE ((gam.activo = true) AND (p.activo = true) AND ((a.estado <> 'dado_baja'::estado_activo_enum AND NOT COALESCE(a.es_externo, false))));

-- VIEW v_mantenimiento_cobertura_resumen
CREATE OR REPLACE VIEW public.v_mantenimiento_cobertura_resumen AS
 WITH activos_vivos AS (
         SELECT a.id,
            a.modelo_id,
            a.tipo
           FROM activos a
          WHERE (((a.estado <> 'dado_baja'::estado_activo_enum AND NOT COALESCE(a.es_externo, false))) AND (NOT COALESCE(a.es_prueba, false)))
        ), con_modelo AS (
         SELECT activos_vivos.id,
            activos_vivos.modelo_id,
            activos_vivos.tipo
           FROM activos_vivos
          WHERE (activos_vivos.modelo_id IS NOT NULL)
        ), con_pautas AS (
         SELECT DISTINCT av.id
           FROM (activos_vivos av
             JOIN pautas_fabricante pf ON (((pf.modelo_id = av.modelo_id) AND (pf.activo = true))))
        ), con_plan AS (
         SELECT DISTINCT pm.activo_id AS id
           FROM planes_mantenimiento pm
          WHERE (pm.activo_plan = true)
        ), sin_plan AS (
         SELECT con_pautas.id
           FROM con_pautas
        EXCEPT
         SELECT con_plan.id
           FROM con_plan
        )
 SELECT ( SELECT count(*) AS count
           FROM activos_vivos) AS activos_totales,
    ( SELECT count(*) AS count
           FROM con_modelo) AS activos_con_modelo,
    ( SELECT count(*) AS count
           FROM con_pautas) AS activos_con_pautas_disponibles,
    ( SELECT count(*) AS count
           FROM con_plan) AS activos_con_plan,
    ( SELECT count(*) AS count
           FROM sin_plan) AS activos_sin_plan,
        CASE
            WHEN (( SELECT count(*) AS count
               FROM con_pautas) > 0) THEN round((((( SELECT count(*) AS count
               FROM con_plan))::numeric * (100)::numeric) / (NULLIF(( SELECT count(*) AS count
               FROM con_pautas), 0))::numeric), 1)
            ELSE (0)::numeric
        END AS cobertura_pct,
    ( SELECT count(*) AS count
           FROM pautas_fabricante
          WHERE (pautas_fabricante.activo = true)) AS pautas_disponibles,
    ( SELECT count(*) AS count
           FROM planes_mantenimiento
          WHERE (planes_mantenimiento.activo_plan = true)) AS planes_activos;

-- VIEW v_flota_dashboard_unificado
CREATE OR REPLACE VIEW public.v_flota_dashboard_unificado AS
 WITH ult_estado AS (
         SELECT DISTINCT ON (estado_diario_flota.activo_id) estado_diario_flota.activo_id,
            estado_diario_flota.fecha,
            estado_diario_flota.estado_codigo,
            estado_diario_flota.horas_operativas,
            estado_diario_flota.km_recorridos
           FROM estado_diario_flota
          ORDER BY estado_diario_flota.activo_id, estado_diario_flota.fecha DESC
        ), pm_resumen AS (
         SELECT planes_mantenimiento.activo_id,
            count(*) AS planes_total,
            count(*) FILTER (WHERE (planes_mantenimiento.proxima_ejecucion_fecha < CURRENT_DATE)) AS planes_vencidos,
            count(*) FILTER (WHERE ((planes_mantenimiento.proxima_ejecucion_fecha >= CURRENT_DATE) AND (planes_mantenimiento.proxima_ejecucion_fecha <= (CURRENT_DATE + 7)))) AS planes_proxima_semana,
            min(planes_mantenimiento.proxima_ejecucion_fecha) AS pm_proxima_fecha
           FROM planes_mantenimiento
          WHERE (planes_mantenimiento.activo_plan = true)
          GROUP BY planes_mantenimiento.activo_id
        ), ot_correctivas_abiertas AS (
         SELECT ordenes_trabajo.activo_id,
            count(*) AS ots_correctivas_abiertas
           FROM ordenes_trabajo
          WHERE ((ordenes_trabajo.tipo = 'correctivo'::tipo_ot_enum) AND (ordenes_trabajo.estado <> ALL (ARRAY['ejecutada_ok'::estado_ot_enum, 'ejecutada_con_observaciones'::estado_ot_enum, 'no_ejecutada'::estado_ot_enum, 'cancelada'::estado_ot_enum, 'cerrada'::estado_ot_enum])))
          GROUP BY ordenes_trabajo.activo_id
        ), alertas_act AS (
         SELECT alertas.entidad_id AS activo_id,
            count(*) AS alertas_activas,
            count(*) FILTER (WHERE ((alertas.severidad)::text = 'critical'::text)) AS alertas_criticas
           FROM alertas
          WHERE ((alertas.leida = false) AND ((alertas.entidad_tipo)::text = 'activo'::text) AND (alertas.entidad_id IS NOT NULL))
          GROUP BY alertas.entidad_id
        ), geo_dentro AS (
         SELECT v.activo_id,
            v.geocerca_id AS geocerca_esperada_id,
            v.geocerca_nombre AS geocerca_esperada,
                CASE
                    WHEN ((v.geocerca_lat IS NULL) OR (g_1.latitud IS NULL)) THEN NULL::boolean
                    ELSE (fn_distancia_haversine(g_1.latitud, g_1.longitud, v.geocerca_lat, v.geocerca_lng) <= v.geocerca_radio_m)
                END AS en_zona_esperada
           FROM (v_activo_geocerca_esperada v
             LEFT JOIN gps_estado_actual g_1 ON ((g_1.activo_id = v.activo_id)))
        )
 SELECT a.id AS activo_id,
    a.codigo AS activo_codigo,
    a.nombre AS activo_nombre,
    a.patente,
    a.tipo AS activo_tipo,
    a.estado AS estado_operacional,
    a.estado_comercial,
    a.operacion,
    a.modelo_id,
    m.nombre AS modelo_nombre,
    ma.nombre AS modelo_marca,
    a.contrato_id,
    c.codigo AS contrato_codigo,
    c.cliente AS contrato_cliente,
    a.faena_id,
    f.nombre AS faena_nombre,
    a.kilometraje_actual,
    a.horas_uso_actual,
    a.anio_fabricacion,
    ue.fecha AS estado_ultima_fecha,
    ue.estado_codigo AS estado_codigo_hoy,
    ue.horas_operativas AS horas_op_ultimo_dia,
    ue.km_recorridos AS km_ultimo_dia,
    COALESCE(pm.planes_total, (0)::bigint) AS pm_planes_total,
    COALESCE(pm.planes_vencidos, (0)::bigint) AS pm_planes_vencidos,
    COALESCE(pm.planes_proxima_semana, (0)::bigint) AS pm_planes_proxima_semana,
    pm.pm_proxima_fecha,
        CASE
            WHEN (pm.planes_total IS NULL) THEN 'sin_planes'::text
            WHEN (pm.planes_vencidos > 0) THEN 'vencido'::text
            WHEN (pm.planes_proxima_semana > 0) THEN 'proximo'::text
            ELSE 'al_dia'::text
        END AS pm_status,
    COALESCE(oc.ots_correctivas_abiertas, (0)::bigint) AS ots_correctivas_abiertas,
    COALESCE(al.alertas_activas, (0)::bigint) AS alertas_activas,
    COALESCE(al.alertas_criticas, (0)::bigint) AS alertas_criticas,
    gm.gps_device_id,
    gm.gps_device_name AS gps_device_nombre,
    g.ts_gps AS gps_ultima_senal,
    (EXTRACT(epoch FROM (now() - g.ts_gps)) / (60)::numeric) AS gps_minutos_offline,
    g.latitud AS gps_lat,
    g.longitud AS gps_lng,
    g.velocidad_kmh AS gps_velocidad_kmh,
    g.ignicion AS gps_ignicion,
    g.movimiento AS gps_movimiento,
    g.conexion AS gps_conexion,
    g.bateria_pct AS gps_bateria_pct,
        CASE
            WHEN (gm.gps_device_id IS NULL) THEN 'sin_gps'::text
            WHEN (g.ts_gps IS NULL) THEN 'sin_datos'::text
            WHEN (g.ts_gps < (now() - '24:00:00'::interval)) THEN 'sin_senal_24h'::text
            WHEN ((g.conexion)::text = 'offline'::text) THEN 'offline'::text
            WHEN (g.velocidad_kmh >= (5)::numeric) THEN 'en_ruta'::text
            WHEN (g.ignicion = true) THEN 'detenido_motor_on'::text
            ELSE 'detenido'::text
        END AS gps_estado_pin,
    gd.geocerca_esperada_id,
    gd.geocerca_esperada,
    gd.en_zona_esperada,
    a.created_at AS activo_creado_at,
    a.updated_at AS activo_actualizado_at
   FROM (((((((((((activos a
     LEFT JOIN modelos m ON ((m.id = a.modelo_id)))
     LEFT JOIN marcas ma ON ((ma.id = m.marca_id)))
     LEFT JOIN contratos c ON ((c.id = a.contrato_id)))
     LEFT JOIN faenas f ON ((f.id = a.faena_id)))
     LEFT JOIN ult_estado ue ON ((ue.activo_id = a.id)))
     LEFT JOIN pm_resumen pm ON ((pm.activo_id = a.id)))
     LEFT JOIN ot_correctivas_abiertas oc ON ((oc.activo_id = a.id)))
     LEFT JOIN alertas_act al ON ((al.activo_id = a.id)))
     LEFT JOIN gps_activo_mapeo gm ON (((gm.activo_id = a.id) AND (gm.activo = true))))
     LEFT JOIN gps_estado_actual g ON ((g.activo_id = a.id)))
     LEFT JOIN geo_dentro gd ON ((gd.activo_id = a.id)))
  WHERE ((a.estado <> 'dado_baja'::estado_activo_enum AND NOT COALESCE(a.es_externo, false)));


-- ── 5 · Registrar (o reutilizar) la ficha del camión externo ────────────────
CREATE OR REPLACE FUNCTION public.rpc_registrar_equipo_externo(
    p_patente           TEXT,
    p_cliente           TEXT,
    p_descripcion       TEXT DEFAULT NULL,
    p_tipo_equipamiento tipo_equipamiento_enum DEFAULT 'generico',
    p_operacion         TEXT DEFAULT 'Coquimbo'
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    v_rol      TEXT := fn_user_rol();
    v_norm     TEXT;
    v_patente  TEXT;
    v_cliente  TEXT := NULLIF(btrim(p_cliente), '');
    v_desc     TEXT := NULLIF(btrim(p_descripcion), '');
    v_tipo     tipo_activo_enum;
    v_modelo   UUID;
    v_nombre   TEXT;
    v_act      RECORD;
    v_nuevo    BOOLEAN := FALSE;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento',
                     'jefe_operaciones','supervisor','planificador') THEN
        RAISE EXCEPTION 'Sin permiso para programar equipos externos (rol: %)', v_rol;
    END IF;

    v_norm := upper(regexp_replace(COALESCE(p_patente, ''), '[^A-Za-z0-9]', '', 'g'));
    IF length(v_norm) < 4 THEN
        RAISE EXCEPTION 'Escribe la patente del camión externo (al menos 4 letras/números).';
    END IF;
    IF v_cliente IS NULL OR length(v_cliente) < 2 THEN
        RAISE EXCEPTION 'Escribe de quién es el camión (cliente o empresa).';
    END IF;
    IF COALESCE(p_operacion, '') NOT IN ('Coquimbo', 'Calama') THEN
        RAISE EXCEPTION 'La operación debe ser Coquimbo o Calama.';
    END IF;
    -- Patente chilena con guion (ABCD-12) si calza el patrón; si no, tal cual.
    v_patente := CASE WHEN v_norm ~ '^[A-Z]{2,4}[0-9]{2}$'
                      THEN left(v_norm, length(v_norm) - 2) || '-' || right(v_norm, 2)
                      ELSE v_norm END;

    v_tipo := CASE p_tipo_equipamiento
                  WHEN 'aljibe_agua'        THEN 'camion_cisterna'
                  WHEN 'aljibe_combustible' THEN 'camion_cisterna'
                  WHEN 'camioneta'          THEN 'camioneta'
                  WHEN 'grua_horquilla'     THEN 'equipo_menor'
                  ELSE 'camion' END::tipo_activo_enum;
    SELECT m.id INTO v_modelo
      FROM modelos m JOIN marcas ma ON ma.id = m.marca_id
     WHERE ma.nombre = 'EXTERNO' AND m.tipo_activo = v_tipo
     LIMIT 1;
    IF v_modelo IS NULL THEN RAISE EXCEPTION 'MIG607: falta el modelo EXTERNO para %', v_tipo; END IF;

    v_nombre := left('EXTERNO · ' || v_cliente || ' · ' || COALESCE(v_desc, 'Camión') || ' ' || v_patente, 200);

    -- ¿La patente ya existe?
    SELECT id, codigo, nombre, es_externo, estado INTO v_act
      FROM activos
     WHERE upper(regexp_replace(COALESCE(patente, ''), '[^A-Za-z0-9]', '', 'g')) = v_norm
     ORDER BY es_externo DESC, created_at
     LIMIT 1;

    IF v_act.id IS NOT NULL AND NOT v_act.es_externo THEN
        RAISE EXCEPTION 'La patente % es del equipo % de la flota Pillado (%). Prográmalo desde la lista de patentes.',
            v_patente, v_act.codigo, v_act.nombre;
    END IF;

    IF v_act.id IS NOT NULL THEN
        -- Vuelve un externo conocido: se actualiza con lo que se escribió hoy.
        UPDATE activos
           SET externo_cliente   = v_cliente,
               nombre            = v_nombre,
               tipo              = v_tipo,
               modelo_id         = v_modelo,
               tipo_equipamiento = p_tipo_equipamiento,
               operacion         = p_operacion,
               estado            = CASE WHEN estado = 'dado_baja' THEN 'operativo' ELSE estado END,
               fecha_baja        = NULL,
               updated_at        = NOW()
         WHERE id = v_act.id;
    ELSE
        INSERT INTO activos (
            codigo, nombre, tipo, modelo_id, patente, operacion, tipo_equipamiento,
            criticidad, estado, fecha_alta, qr_publico_habilitado,
            es_externo, externo_cliente, notas, created_by
        ) VALUES (
            'EXT-' || v_norm, v_nombre, v_tipo, v_modelo, v_patente, p_operacion, p_tipo_equipamiento,
            'baja', 'operativo', CURRENT_DATE, FALSE,
            TRUE, v_cliente,
            'Equipo externo registrado desde el Plan Taller (MIG607). No es flota Pillado.',
            auth.uid()
        )
        RETURNING id, codigo, nombre, es_externo, estado INTO v_act;
        v_nuevo := TRUE;
    END IF;

    RETURN jsonb_build_object(
        'activo_id', v_act.id,
        'codigo',    'EXT-' || v_norm,
        'patente',   v_patente,
        'nombre',    v_nombre,
        'nuevo',     v_nuevo
    );
END $$;

REVOKE ALL ON FUNCTION public.rpc_registrar_equipo_externo(TEXT, TEXT, TEXT, tipo_equipamiento_enum, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_registrar_equipo_externo(TEXT, TEXT, TEXT, tipo_equipamiento_enum, TEXT) TO authenticated;

-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'columna', EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_name = 'activos' AND column_name = 'es_externo'),
    'modelos_externos', (SELECT count(*) FROM modelos m JOIN marcas ma ON ma.id = m.marca_id
                          WHERE ma.nombre = 'EXTERNO'),
    'objetos_con_filtro', (SELECT count(*) FROM pg_proc
                            WHERE pronamespace = 'public'::regnamespace AND prokind = 'f'
                              AND prosrc LIKE '%es_externo%')
                        + (SELECT count(*) FROM pg_views
                            WHERE schemaname = 'public' AND definition LIKE '%es_externo%'),
    'flota_dashboard', (SELECT count(*) FROM v_flota_dashboard_unificado),
    'rpc', EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_registrar_equipo_externo')
) AS resultado;

NOTIFY pgrst, 'reload schema';
