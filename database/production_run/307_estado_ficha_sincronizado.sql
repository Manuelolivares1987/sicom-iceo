-- ============================================================================
-- MIG307 · El estado de la ficha del equipo deja de contradecir al planificador
-- ----------------------------------------------------------------------------
-- QUÉ PASABA
--   Hay dos caminos para fijar el estado del día de un equipo:
--     1. El modal "Cambiar Estado" (rpc_actualizar_estado_diario_manual), que
--        SÍ sincroniza activos.estado.
--     2. El botón Confirmar / Cerrar día de Sugerencias GPS
--        (rpc_confirmar_estado_dia), que NO lo sincronizaba.
--   Como el planificador cierra el día por Sugerencias (55 equipos cada día),
--   la ficha se quedó pegada en el estado con que se cargó el maestro. Hoy
--   FSLZ-67 aparece "Fuera de Servicio" en /dashboard/activos mientras el
--   planificador lo tiene en C (En contrato), y hay 30 equipos más así.
--
-- QUÉ HACE ESTA MIGRACIÓN
--   a) rpc_confirmar_estado_dia sincroniza activos.estado igual que el modal.
--      Sigue SIN tocar estado_comercial: eso dispara los gates de checklist y
--      ready-to-rent, que son para la acción deliberada del modal, no para
--      registrar la realidad diaria.
--   b) Sólo sincroniza cuando la fecha confirmada es la última registrada del
--      equipo. Cargar días pasados (backfill) no puede reescribir el hoy.
--   c) fn_reconciliar_estado_ficha_desde_matriz reconoce 'S' (siniestrado,
--      MIG306) y trabaja sobre el último día <= hoy, no sobre el futuro.
--   d) Vista v_activos_estado_planificador: el estado del planificador listo
--      para leerlo desde la ficha y desde el listado de Activos, con el mismo
--      vocabulario (A/C/D/H/R/M/T/F/V/U/L/S) que ve el planificador.
--   e) Reconcilia de una vez los equipos que ya quedaron desalineados.
-- ============================================================================

BEGIN;

-- ── a) + b) Confirmar desde Sugerencias sincroniza la ficha ────────────────
CREATE OR REPLACE FUNCTION public.rpc_confirmar_estado_dia(
    p_activo_id uuid,
    p_fecha     date,
    p_estado    character
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_ultima_fecha DATE;
    v_estado_ficha estado_activo_enum;
BEGIN
    -- [MIG189] Autorización fail-closed (flota/approve). Deniega anon,
    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.
    IF NOT public.fn_tiene_permiso_modulo('flota', 'approve', ARRAY[]::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'flota', 'flota', 'approve' USING ERRCODE = '42501';
    END IF;

    INSERT INTO estado_diario_flota
      (activo_id, fecha, estado_codigo, override_manual, calculado_auto, motivo_override, actualizado_por, actualizado_at)
    VALUES
      (p_activo_id, p_fecha, p_estado, true, false, 'Confirmado por planificador (sugerencia GPS)', auth.uid(), now())
    ON CONFLICT (activo_id, fecha) DO UPDATE
      SET estado_codigo = EXCLUDED.estado_codigo, override_manual = true, calculado_auto = false,
          motivo_override = EXCLUDED.motivo_override, actualizado_por = auth.uid(),
          actualizado_at = now(), updated_at = now();

    -- Sincronizar SOLO la categoría comercial (para el informe de Fiabilidad).
    -- NO se toca estado_comercial: hacerlo dispararía los gates de checklist /
    -- ready-to-rent y la auto-recepción, que son para la acción deliberada del
    -- modal, no para registrar la realidad diaria desde Sugerencias GPS.
    IF p_estado IN ('A','C','L','U','V') THEN
      UPDATE activos a
         SET categoria_uso = CASE p_estado
                WHEN 'A' THEN 'arriendo_comercial'::categoria_uso_enum
                WHEN 'C' THEN 'arriendo_comercial'::categoria_uso_enum
                WHEN 'L' THEN 'leasing_operativo'::categoria_uso_enum
                WHEN 'U' THEN 'uso_interno'::categoria_uso_enum
                WHEN 'V' THEN 'venta'::categoria_uso_enum
                ELSE a.categoria_uso END,
             updated_at = now()
       WHERE a.id = p_activo_id
         AND a.categoria_uso IS DISTINCT FROM (CASE p_estado
                WHEN 'A' THEN 'arriendo_comercial'::categoria_uso_enum
                WHEN 'C' THEN 'arriendo_comercial'::categoria_uso_enum
                WHEN 'L' THEN 'leasing_operativo'::categoria_uso_enum
                WHEN 'U' THEN 'uso_interno'::categoria_uso_enum
                WHEN 'V' THEN 'venta'::categoria_uso_enum END);
    END IF;

    -- [MIG307] Sincronizar el estado OPERATIVO de la ficha (activos.estado).
    -- Es el mismo mapeo que usa el modal Cambiar Estado, para que la ficha y
    -- el tablero del planificador no puedan decir cosas distintas.
    -- Sólo si esta fecha es la última registrada del equipo: confirmar un día
    -- pasado no puede reescribir el estado de hoy.
    SELECT MAX(fecha) INTO v_ultima_fecha
      FROM estado_diario_flota WHERE activo_id = p_activo_id;

    IF v_ultima_fecha IS NOT NULL AND p_fecha >= v_ultima_fecha THEN
        v_estado_ficha := CASE p_estado
                WHEN 'M' THEN 'en_mantenimiento'
                WHEN 'T' THEN 'en_mantenimiento'
                WHEN 'H' THEN 'en_mantenimiento'
                WHEN 'F' THEN 'fuera_servicio'
                WHEN 'S' THEN 'fuera_servicio'
                ELSE        'operativo'
            END::estado_activo_enum;

        UPDATE activos a
           SET estado = v_estado_ficha,
               updated_at = now()
         WHERE a.id = p_activo_id
           AND a.estado <> 'dado_baja'          -- una baja no vuelve sola
           AND a.estado IS DISTINCT FROM v_estado_ficha;
    END IF;
END $function$;

-- ── c) Reconciliador: reconoce 'S' y mira el último día <= hoy ─────────────
CREATE OR REPLACE FUNCTION public.fn_reconciliar_estado_ficha_desde_matriz()
RETURNS TABLE(revisados integer, actualizados integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    r     RECORD;
    v_est estado_activo_enum;
    v_rev INTEGER := 0;
    v_upd INTEGER := 0;
BEGIN
    FOR r IN
        SELECT a.id, a.estado AS fic_est, u.cod
        FROM activos a
        JOIN LATERAL (
            SELECT estado_codigo AS cod
            FROM estado_diario_flota e
            WHERE e.activo_id = a.id
              AND e.fecha <= CURRENT_DATE
            ORDER BY e.fecha DESC
            LIMIT 1
        ) u ON TRUE
        WHERE a.estado <> 'dado_baja'
    LOOP
        v_rev := v_rev + 1;
        v_est := CASE r.cod
                    WHEN 'M' THEN 'en_mantenimiento'
                    WHEN 'T' THEN 'en_mantenimiento'
                    WHEN 'H' THEN 'en_mantenimiento'
                    WHEN 'F' THEN 'fuera_servicio'
                    WHEN 'S' THEN 'fuera_servicio'   -- MIG306: robo / siniestro
                    ELSE 'operativo'
                 END::estado_activo_enum;

        IF v_est IS DISTINCT FROM r.fic_est THEN
            -- Solo estado operativo; estado_comercial intacto (no dispara gates).
            UPDATE activos
               SET estado = v_est, updated_at = NOW()
             WHERE id = r.id;
            v_upd := v_upd + 1;
        END IF;
    END LOOP;

    RETURN QUERY SELECT v_rev, v_upd;
END;
$function$;

-- ── d) El estado del planificador, listo para leerlo desde la UI ───────────
-- Un equipo puede no tener fila del día (aún no se cierra el día): se hereda
-- el último día cerrado y se marca confirmado_hoy = false, para que la ficha
-- pueda decir "heredado del 20-ago" en vez de inventar.
CREATE OR REPLACE VIEW public.v_activos_estado_planificador AS
SELECT
    a.id                                   AS activo_id,
    a.codigo,
    a.patente,
    u.estado_codigo,
    u.fecha                                AS fecha_estado,
    (u.fecha = CURRENT_DATE)               AS confirmado_hoy,
    (CURRENT_DATE - u.fecha)::int          AS dias_desde_confirmacion
FROM activos a
LEFT JOIN LATERAL (
    SELECT e.estado_codigo, e.fecha
      FROM estado_diario_flota e
     WHERE e.activo_id = a.id
       AND e.fecha <= CURRENT_DATE
     ORDER BY e.fecha DESC
     LIMIT 1
) u ON TRUE;

GRANT SELECT ON public.v_activos_estado_planificador TO authenticated;

-- ── e) Alinear de una vez lo que ya quedó desalineado ──────────────────────
SELECT * FROM public.fn_reconciliar_estado_ficha_desde_matriz();

COMMIT;
