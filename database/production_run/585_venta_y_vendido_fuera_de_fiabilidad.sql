-- ############################################################################
-- MIG585 · En venta y vendido salen del status de fiabilidad
-- ----------------------------------------------------------------------------
-- QUÉ PASABA
-- Un equipo en venta ('V') se contaba como día ARRIBA en fiabilidad: no estaba
-- en M/T/F/R/H, así que inflaba la disponibilidad de la flota y seguía
-- apareciendo en el status (hoy DCHD-83, FJTJ-61 y GCHT-12). Y un equipo
-- vendido no tenía cómo marcarse desde Sugerencias GPS: había que ir a la
-- ficha y darlo de baja a mano, y mientras tanto seguía pidiendo cierre diario.
--
-- LA REGLA (la misma de 'S', MIG306)
--   · 'V' en venta  → el equipo sigue siendo nuestro, pero dejó de ser flota
--                     operable. Sus días NO cuentan ni como arriba ni como
--                     caídos: salen del denominador.
--   · 'B' vendido   → código nuevo. Se elige en Sugerencias GPS con un motivo
--                     obligatorio (comprador, factura). La ficha pasa a
--                     'dado_baja', los días posteriores ya registrados pasan a
--                     'B', y desde el día siguiente el equipo deja de aparecer
--                     en Sugerencias, en el cierre automático y en fiabilidad.
--
-- QUÉ NO CAMBIA
--   · Los días en que el equipo SÍ operó (antes de pasar a venta) siguen
--     contando en su periodo. Esto no reescribe la historia.
--   · 'S' sigue igual.
--   · Un 'B' por error se deshace el MISMO día en Sugerencias: el equipo sigue
--     visible ese día y al confirmar otro código la ficha vuelve.
-- ############################################################################

BEGIN;

-- ── 1. El código 'B' ─────────────────────────────────────────────────────
ALTER TABLE public.estado_diario_flota DROP CONSTRAINT IF EXISTS chk_estado_codigo;
ALTER TABLE public.estado_diario_flota
    ADD CONSTRAINT chk_estado_codigo
    CHECK (estado_codigo IN ('A','C','D','H','R','M','T','F','V','U','L','S','B'));

COMMENT ON CONSTRAINT chk_estado_codigo ON public.estado_diario_flota IS
    'A arrendado · C contrato · D disponible · H habilitación · R recepción · '
    'M mantención · T taller · F fuera de servicio · V venta · U uso interno · '
    'L leasing · S siniestrado/robado (MIG306) · B vendido (MIG585). '
    'S, V y B no cuentan en disponibilidad: salen del denominador.';

-- ── 2. Mapeos a la ficha ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_estado_ficha_desde_codigo(p_codigo character)
 RETURNS estado_activo_enum
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE p_codigo
             WHEN 'M' THEN 'en_mantenimiento'
             WHEN 'T' THEN 'en_mantenimiento'
             WHEN 'H' THEN 'en_mantenimiento'
             WHEN 'F' THEN 'fuera_servicio'
             WHEN 'S' THEN 'fuera_servicio'   -- robo / siniestro (MIG306)
             WHEN 'B' THEN 'dado_baja'        -- vendido (MIG585)
             ELSE        'operativo'
           END::estado_activo_enum;
$function$;

CREATE OR REPLACE FUNCTION public.fn_categoria_uso_desde_codigo(p_codigo character)
 RETURNS categoria_uso_enum
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE p_codigo
             WHEN 'A' THEN 'arriendo_comercial'::categoria_uso_enum
             WHEN 'C' THEN 'arriendo_comercial'::categoria_uso_enum
             WHEN 'L' THEN 'leasing_operativo'::categoria_uso_enum
             WHEN 'U' THEN 'uso_interno'::categoria_uso_enum
             WHEN 'V' THEN 'venta'::categoria_uso_enum
             WHEN 'B' THEN 'venta'::categoria_uso_enum   -- MIG585
             ELSE NULL
           END;
$function$;

-- ── 3. Parches por línea a las funciones vivas ───────────────────────────
-- Se parchan sobre la definición viva (pg_get_functiondef) y no se reescriben:
-- varias tienen parches acumulados de otras migraciones. Si el texto buscado
-- no está, la migración falla en vez de quedar a medias.
DO $patch$
DECLARE
    r       RECORD;
    v_def   TEXT;
    v_nuevo TEXT;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
          -- fiabilidad y OEE: S, V y B fuera del denominador
          ('fn_calcular_fiabilidad_activo',  $$edf.estado_codigo <> 'S'$$, $$edf.estado_codigo NOT IN ('S','V','B')$$),
          ('fn_calcular_fiabilidad_flota',   $$edf.estado_codigo <> 'S'$$, $$edf.estado_codigo NOT IN ('S','V','B')$$),
          ('calcular_oee_activo',            $$edf.estado_codigo <> 'S'$$, $$edf.estado_codigo NOT IN ('S','V','B')$$),
          ('fn_panel_disponibilidad',        $$e.estado_codigo <> 'S'$$,   $$e.estado_codigo NOT IN ('S','V','B')$$),
          ('fn_panel_equipos_detenidos',     $$e.estado_codigo <> 'S'$$,   $$e.estado_codigo NOT IN ('S','V','B')$$),
          ('fn_calcular_oee_fiabilidad_activo',
             $$AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin;$$,
             $$AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin
       AND edf.estado_codigo NOT IN ('S','V','B');   -- MIG585$$),
          -- el reporte: la matriz diaria (status) no muestra V ni B
          ('fn_reporte_fiabilidad_publico',
             $$WHERE e.fecha BETWEEN p_ini AND p_fin$$,
             $$WHERE e.fecha BETWEEN p_ini AND p_fin
        AND e.estado_codigo NOT IN ('V','B')   -- MIG585$$),
          -- validación de códigos en los otros dos caminos de escritura
          ('rpc_actualizar_estado_diario_manual', $$'V','U','L','S')$$, $$'V','U','L','S','B')$$),
          ('rpc_confirmar_cierre_diario',         $$'V','U','L','S')$$, $$'V','U','L','S','B')$$),
          -- sugerencia GPS: un equipo en venta se sugiere 'V' (no D/A por estar en una geocerca)
          ('fn_estado_por_geocerca',
             $$  SELECT latitud, longitud, ts_gps INTO v_lat, v_lng, v_ts$$,
             $$  -- MIG585: en venta se queda en venta, esté donde esté.
  IF (SELECT estado_comercial FROM activos WHERE id = p_activo_id) = 'en_venta' THEN
    RETURN 'V';
  END IF;

  SELECT latitud, longitud, ts_gps INTO v_lat, v_lng, v_ts$$),
          -- Sugerencias: el equipo vendido sigue visible el día en que se vendió
          -- (para poder deshacer el error); desde el día siguiente desaparece.
          ('fn_sugerencias_estado_gps',
             $$WHERE a.estado <> 'dado_baja'$$,
             $$WHERE (a.estado <> 'dado_baja'
         OR EXISTS (SELECT 1 FROM estado_diario_flota eb
                     WHERE eb.activo_id = a.id AND eb.fecha = p_fecha
                       AND eb.estado_codigo = 'B'))   -- MIG585$$)
        ) AS t(fn, viejo, nuevo)
    LOOP
        SELECT pg_get_functiondef(p.oid) INTO v_def
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = r.fn AND p.prokind = 'f';

        IF v_def IS NULL THEN
            RAISE EXCEPTION 'MIG585: no existe la función %', r.fn;
        END IF;
        IF position(r.nuevo IN v_def) > 0 THEN
            RAISE NOTICE 'MIG585: % ya estaba parchada', r.fn;
            CONTINUE;
        END IF;
        IF position(r.viejo IN v_def) = 0 THEN
            RAISE EXCEPTION 'MIG585: en % no aparece el texto a reemplazar: %', r.fn, r.viejo;
        END IF;

        v_nuevo := replace(v_def, r.viejo, r.nuevo);
        EXECUTE v_nuevo;
        RAISE NOTICE 'MIG585: % parchada', r.fn;
    END LOOP;
END $patch$;

-- ── 4. Confirmar el día: 'B' vendido ─────────────────────────────────────
-- Igual que MIG573 más:
--   · 'B' exige motivo (≥10 caracteres): quién compró, factura.
--   · 'B' da de baja la ficha aunque se marque en una fecha pasada, y los días
--     ya registrados después de esa fecha pasan a 'B'.
--   · Si ese mismo día se cambia 'B' por otro código, la ficha vuelve
--     (deshacer el error). Una baja hecha a mano en la ficha NO vuelve sola.
CREATE OR REPLACE FUNCTION public.rpc_confirmar_estado_dia(
    p_activo_id UUID, p_fecha DATE, p_estado CHARACTER, p_justificacion TEXT DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_ultima_fecha DATE;
    v_a            RECORD;
    v_error        TEXT := NULL;
    v_pv           RECORD;
    v_obs          TEXT := NULL;
    v_patente      TEXT;
    v_prev_dia     CHARACTER;
    v_estado       CHARACTER := upper(p_estado);
BEGIN
    -- [MIG189] Autorización fail-closed (flota/approve).
    IF NOT public.fn_tiene_permiso_modulo('flota', 'approve', ARRAY[]::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'flota', 'flota', 'approve' USING ERRCODE = '42501';
    END IF;

    SELECT patente INTO v_patente FROM activos WHERE id = p_activo_id;

    -- [MIG573] Prueba de vida para A/C.
    IF v_estado IN ('A', 'C') AND p_fecha >= CURRENT_DATE - 1 THEN
        SELECT * INTO v_pv FROM fn_prueba_de_vida_estado(p_activo_id);
        IF v_pv.requiere THEN
            IF length(trim(COALESCE(p_justificacion, ''))) < 10 THEN
                RAISE EXCEPTION 'PRUEBA_DE_VIDA: % no tiene evidencia de estar operando (%). Para confirmarlo como % escribe cómo sabes que está donde el cliente (mínimo 10 caracteres).',
                    v_patente,
                    CASE WHEN v_pv.fecha IS NULL THEN 'nunca hubo'
                         ELSE 'la última es de hace ' || v_pv.dias || ' días, ' || v_pv.fuente END
                    || CASE WHEN v_pv.centinela = 'critico' THEN '; tiene un crítico abierto en el Centinela' ELSE '' END,
                    v_estado
                    USING ERRCODE = 'P0001';
            END IF;
            v_obs := 'Prueba de vida: ' || trim(p_justificacion);
        END IF;
    END IF;

    -- [MIG585] Vendido: motivo obligatorio.
    IF v_estado = 'B' THEN
        IF length(trim(COALESCE(p_justificacion, ''))) < 10 THEN
            RAISE EXCEPTION 'VENDIDO: para marcar % como vendido escribe a quién se vendió o el documento de venta (mínimo 10 caracteres).',
                v_patente USING ERRCODE = 'P0001';
        END IF;
        v_obs := 'Vendido: ' || trim(p_justificacion);
    END IF;

    SELECT estado_codigo INTO v_prev_dia
      FROM estado_diario_flota WHERE activo_id = p_activo_id AND fecha = p_fecha;

    INSERT INTO estado_diario_flota
      (activo_id, fecha, estado_codigo, override_manual, calculado_auto, motivo_override,
       actualizado_por, actualizado_at, observacion)
    VALUES
      (p_activo_id, p_fecha, v_estado, true, false, 'Confirmado por planificador (sugerencia GPS)',
       auth.uid(), now(), v_obs)
    ON CONFLICT (activo_id, fecha) DO UPDATE
      SET estado_codigo = EXCLUDED.estado_codigo, override_manual = true, calculado_auto = false,
          motivo_override = EXCLUDED.motivo_override, actualizado_por = auth.uid(),
          actualizado_at = now(), updated_at = now(),
          observacion = COALESCE(EXCLUDED.observacion, estado_diario_flota.observacion);

    SELECT id, estado, estado_comercial, categoria_uso INTO v_a
      FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN RETURN; END IF;

    -- [MIG585] Vendido: los días ya registrados después también son 'B', y la
    -- ficha se da de baja aunque la venta se marque con fecha pasada.
    IF v_estado = 'B' THEN
        UPDATE estado_diario_flota
           SET estado_codigo = 'B', override_manual = true, calculado_auto = false,
               motivo_override = 'Vendido el ' || to_char(p_fecha, 'DD-MM-YYYY') || ' (MIG585)',
               actualizado_por = auth.uid(), actualizado_at = now(), updated_at = now()
         WHERE activo_id = p_activo_id AND fecha > p_fecha AND estado_codigo <> 'B';

        IF v_a.estado <> 'dado_baja' THEN
            UPDATE activos
               SET estado        = 'dado_baja',
                   categoria_uso = 'venta',
                   notas         = COALESCE(NULLIF(btrim(notas), '') || E'\n', '')
                                   || '[' || to_char(p_fecha, 'YYYY-MM-DD') || '] ' || v_obs,
                   updated_at    = now()
             WHERE id = p_activo_id;
        END IF;
        RETURN;
    END IF;

    -- La ficha sigue al planificador SOLO si esta es la última fecha registrada.
    SELECT MAX(fecha) INTO v_ultima_fecha
      FROM estado_diario_flota WHERE activo_id = p_activo_id;

    IF v_ultima_fecha IS NULL OR p_fecha < v_ultima_fecha THEN
        RETURN;
    END IF;

    -- Una baja no vuelve sola desde un cierre de día... salvo que se esté
    -- corrigiendo, ese mismo día, un 'B' marcado por error (MIG585).
    IF v_a.estado = 'dado_baja' AND v_prev_dia IS DISTINCT FROM 'B' THEN
        RETURN;
    END IF;

    BEGIN
        UPDATE activos a
           SET estado           = fn_estado_ficha_desde_codigo(v_estado),
               estado_comercial = fn_estado_comercial_desde_codigo(v_estado, a.estado_comercial),
               categoria_uso    = COALESCE(fn_categoria_uso_desde_codigo(v_estado), a.categoria_uso),
               updated_at       = now()
         WHERE a.id = p_activo_id
           AND (a.estado           IS DISTINCT FROM fn_estado_ficha_desde_codigo(v_estado)
             OR a.estado_comercial IS DISTINCT FROM fn_estado_comercial_desde_codigo(v_estado, a.estado_comercial)
             OR a.categoria_uso    IS DISTINCT FROM COALESCE(fn_categoria_uso_desde_codigo(v_estado), a.categoria_uso));
    EXCEPTION WHEN OTHERS THEN
        v_error := SQLERRM;
    END;

    UPDATE estado_diario_flota
       SET ficha_sync_error = v_error
     WHERE activo_id = p_activo_id AND fecha = p_fecha
       AND ficha_sync_error IS DISTINCT FROM v_error;
END $function$;

REVOKE ALL ON FUNCTION public.rpc_confirmar_estado_dia(UUID, DATE, CHARACTER, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_confirmar_estado_dia(UUID, DATE, CHARACTER, TEXT) TO authenticated, service_role;

COMMIT;

-- Verificación: cómo quedan hoy los equipos en venta en el mes en curso.
SELECT a.patente, f.dias_observados, f.disponibilidad_fisica
  FROM activos a
  CROSS JOIN LATERAL fn_calcular_fiabilidad_activo(a.id, date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE) f
 WHERE a.estado_comercial = 'en_venta'
 ORDER BY 1;
