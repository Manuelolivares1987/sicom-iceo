-- ============================================================================
-- MIG579 · El detalle del bono vuelve a abrirse, y el corte se puede cerrar
-- ============================================================================
--
-- LO QUE SE VIO
-- 28-09-2026: en /dashboard/mantenimiento/bono-taller, al abrir a cualquier
-- técnico sale «structure of query does not match function result type». No
-- se ven los trabajos de nadie, y septiembre (18 líneas) no se puede revisar.
--
-- POR QUÉ
-- MIG480 (D5, prorrateo por días en el corte) le agregó `dias_en_corte` a
-- `fn_taller_bono_periodo_calc`: 15 columnas. La puerta con candado de MIG460,
-- `fn_taller_bono_periodo`, sigue declarando 14 y hace `SELECT *`. Postgres
-- no la deja pasar. La tabla de arriba funciona porque va por el resumen.
--
-- Lo grave no es el detalle: `rpc_taller_bono_cerrar_periodo` pasa por la
-- misma puerta, así que NINGÚN corte se podía cerrar desde MIG480.
--
-- DE PASO
-- MIG480 hizo DROP + CREATE de `_calc` y al reponer los permisos se lo dio a
-- `authenticated`. Eso salta el candado de MIG460: cualquier usuario con
-- sesión podía leer el bono de todos llamando a `_calc` directo. Se cierra,
-- como sus hermanas `_resumen_calc` y `_kpi_periodo_calc`.
--
-- Y el cierre guarda `dias_en_corte`: la cartola congelada tiene que poder
-- explicar «se paga 12 de 30 días» igual que el borrador.
-- ============================================================================

BEGIN;

-- ── 1 · La puerta, con la columna que le faltaba ────────────────────────────
-- Cambia el tipo de retorno: CREATE OR REPLACE no alcanza.
DROP FUNCTION IF EXISTS fn_taller_bono_periodo(DATE, DATE);

CREATE FUNCTION public.fn_taller_bono_periodo(p_desde date, p_hasta date)
 RETURNS TABLE(tecnico_id uuid, tecnico text, cargo text, ot_id uuid, ot_folio text,
               concepto text, dias numeric, tramo text, participacion numeric,
               base_reparto text, monto_formula numeric, monto_propuesto numeric,
               falta text, aviso text, dias_en_corte numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    PERFORM fn_taller_bono_exigir_vista();
    RETURN QUERY SELECT * FROM fn_taller_bono_periodo_calc(p_desde, p_hasta);
END;
$function$;

REVOKE ALL ON FUNCTION fn_taller_bono_periodo(DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_taller_bono_periodo(DATE, DATE) TO authenticated;

-- ── 2 · El cálculo crudo, otra vez detrás del candado ───────────────────────
REVOKE ALL ON FUNCTION fn_taller_bono_periodo_calc(DATE, DATE) FROM PUBLIC, anon, authenticated;

-- ── 3 · El cierre congela también los días en el corte ──────────────────────
ALTER TABLE taller_bono_periodo_detalle ADD COLUMN IF NOT EXISTS dias_en_corte NUMERIC;

CREATE OR REPLACE FUNCTION public.rpc_taller_bono_cerrar_periodo(p_nombre text, p_desde date, p_hasta date, p_disponibilidad numeric DEFAULT NULL::numeric, p_notas text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user   UUID := auth.uid();
    v_rol    TEXT;
    v_par    UUID;
    v_estado TEXT;
    v_faltan TEXT;
    v_solapa TEXT;
    v_huerf  TEXT;
    v_per    UUID;
    v_total  NUMERIC := 0;
    v_n      INT := 0;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_operaciones',
                     'jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Tu perfil no puede cerrar un período de bono.';
    END IF;

    IF p_hasta < p_desde THEN
        RAISE EXCEPTION 'El corte termina antes de empezar.';
    END IF;

    SELECT string_agg(nombre || ' (' || desde || ' a ' || hasta || ')', ', ')
      INTO v_solapa
      FROM taller_bono_periodo
     WHERE desde <= p_hasta AND hasta >= p_desde;
    IF v_solapa IS NOT NULL THEN
        RAISE EXCEPTION 'Este corte se pisa con otro que ya está cerrado: %.', v_solapa;
    END IF;

    SELECT id, estado INTO v_par, v_estado
      FROM taller_bono_parametros
     WHERE vigencia_desde <= p_hasta
       AND (vigencia_hasta IS NULL OR vigencia_hasta >= p_desde)
     ORDER BY estado = 'vigente' DESC, vigencia_desde DESC
     LIMIT 1;

    IF v_par IS NULL THEN
        RAISE EXCEPTION 'No hay parámetros del bono que cubran % a %.', p_desde, p_hasta;
    END IF;
    IF v_estado <> 'vigente' THEN
        RAISE EXCEPTION 'Los parámetros de este corte están en «%». Un período no se '
                        'cierra sobre una propuesta: primero el acta que fija topes y '
                        'curva, después el cierre.', v_estado;
    END IF;

    SELECT string_agg(DISTINCT r.tecnico || ': ' || r.falta, ' · ')
      INTO v_faltan
      FROM fn_taller_bono_resumen(p_desde, p_hasta, p_disponibilidad) r
     WHERE r.falta IS NOT NULL;
    IF v_faltan IS NOT NULL THEN
        RAISE EXCEPTION 'Falta información para cerrar. %', v_faltan;
    END IF;

    -- [MIG464] Trabajo cerrado en el corte que no le paga a nadie. Dejarlo pasar
    -- sería perder plata en silencio.
    SELECT string_agg(o.ot_folio || ' (' || o.motivo || ')', ' · ')
      INTO v_huerf
      FROM fn_taller_bono_ot_sin_dueno(p_desde, p_hasta) o;
    IF v_huerf IS NOT NULL THEN
        RAISE EXCEPTION 'Hay trabajo cerrado en el corte que no le paga a nadie: %. '
                        'Asígnales cuadrilla en el Plan Semanal, o confirma que no '
                        'corresponde pagarlas.', v_huerf;
    END IF;

    -- [MIG472] Cierres con pendientes que nadie validó. No se pagan y no se
    -- pueden dejar pasar: o se validan o se devuelven, pero se deciden.
    SELECT string_agg(ot.folio || ' (' || ot.cierre_pendientes || ' de '
                      || ot.cierre_pendientes_total || ' tareas sin hacer)', ' · ')
      INTO v_huerf
      FROM ordenes_trabajo ot
     WHERE ot.cierre_validacion_estado = 'por_validar'
       AND ot.fecha_termino::DATE BETWEEN p_desde AND p_hasta;
    IF v_huerf IS NOT NULL THEN
        RAISE EXCEPTION 'Hay cierres con tareas pendientes que la jefatura no ha validado: %. '
                        'Valídalos o devuélvelos antes de cerrar el período.', v_huerf;
    END IF;

    INSERT INTO taller_bono_periodo (
        nombre, desde, hasta, parametros_id, disponibilidad_pct,
        disponibilidad_fuente, notas, cerrado_por)
    VALUES (
        p_nombre, p_desde, p_hasta, v_par,
        COALESCE(p_disponibilidad,
                 (SELECT d.disponibilidad_pct FROM fn_taller_disponibilidad_periodo(p_desde, p_hasta) d)),
        CASE WHEN p_disponibilidad IS NULL THEN 'medida por el sistema'
             ELSE 'fijada al cerrar' END,
        p_notas, v_user)
    RETURNING id INTO v_per;

    INSERT INTO taller_bono_periodo_linea (
        periodo_id, tecnico_id, tecnico, cargo, ots, plan_formula, plan_calculado,
        plan_tope, plan_pagado, kpi_pagado, total, dias_cargo, dias_corte, tramo,
        falta, aviso)
    SELECT v_per, r.tecnico_id, r.tecnico, r.cargo, r.ots, r.plan_formula,
           r.plan_calculado, r.plan_tope, r.plan_pagado, r.kpi_pagado, r.total,
           r.dias_cargo, r.dias_corte, r.tramo, r.falta, r.aviso
      FROM fn_taller_bono_resumen(p_desde, p_hasta, p_disponibilidad) r;

    INSERT INTO taller_bono_periodo_detalle (
        periodo_id, tecnico_id, ot_id, ot_folio, concepto, dias, tramo,
        participacion, base_reparto, monto_formula, monto_propuesto, falta, aviso,
        dias_en_corte)
    SELECT v_per, b.tecnico_id, b.ot_id, b.ot_folio, b.concepto, b.dias, b.tramo,
           b.participacion, b.base_reparto, b.monto_formula, b.monto_propuesto,
           b.falta, b.aviso, b.dias_en_corte
      FROM fn_taller_bono_periodo(p_desde, p_hasta) b;

    SELECT COALESCE(sum(total), 0), count(*) INTO v_total, v_n
      FROM taller_bono_periodo_linea WHERE periodo_id = v_per;

    UPDATE taller_bono_periodo SET total_clp = v_total WHERE id = v_per;

    RETURN jsonb_build_object('success', true, 'periodo_id', v_per,
                              'personas', v_n, 'total_clp', v_total);
END;
$function$;

-- ── Verificación (solo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM fn_taller_bono_periodo_calc(DATE '2026-08-24', DATE '2026-09-23');
    RAISE NOTICE 'septiembre: % líneas de detalle', v_n;
    IF has_function_privilege('authenticated', 'fn_taller_bono_periodo_calc(date,date)', 'EXECUTE') THEN
        RAISE EXCEPTION '_calc sigue abierto a authenticated';
    END IF;
END $mig$;

COMMIT;
