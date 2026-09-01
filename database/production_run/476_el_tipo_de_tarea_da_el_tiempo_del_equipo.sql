-- ============================================================================
-- MIG476 · El tipo de tarea da el tiempo total del equipo
-- ============================================================================
--
-- LO QUE DECIDIÓ MANUEL
--   A) «La opción es A»: el paraguas de la OT cubre TODO — la revisión del
--      camión y las reparaciones. Si el checklist toma 2 h, a las Órdenes de
--      Servicio les quedan las que sobran, no el total.
--   B) «Cuando planifico, en función a la tarea —MTN etc.— se da un tiempo. Ése
--      es el tiempo total para el equipo.»
--
-- LO QUE ESTO CIERRA
-- El mismo juego de parámetros que paga el bono pasa a dar el tiempo del plan.
-- Hasta hoy el concepto sólo definía PLAZOS EN DÍAS —optimizado, normal, con
-- demora— y las horas del plan las tenía que inventar el planificador, que por
-- eso no las llenaba: 0 de 49 OT abiertas tienen horas.
--
-- Ahora el planificador elige MTN y el sistema propone las horas. Puede
-- cambiarlas, pero ya no parte de una hoja en blanco.
--
-- DE DÓNDE SALEN LOS NÚMEROS: DE LA HISTORIA DE LA EMPRESA
-- No los inventé. Salen de las 229 Órdenes de Servicio históricas que tienen
-- horas de mano de obra cargadas, entre 2024 y hoy:
--
--     solo preventiva            n= 23   mediana  8,0 h   ( 6,3 trabajos)
--     solo correctivo            n=111   mediana  8,0 h   ( 8,9 trabajos)
--     preventiva + correctivo    n= 43   mediana 32,5 h   (19,8 trabajos)
--
-- Se usa la MEDIANA y no el promedio a propósito: los rangos llegan a 132 h y
-- un par de visitas eternas corren el promedio hacia arriba. La mediana dice
-- cuánto toma una visita normal, que es lo que se quiere planificar.
--
--     MPN  mantención preventiva en arriendo   →   8,0 h   (solo preventiva)
--     MTN  mantención total post arriendo      →  32,5 h   (preventiva + correctivo)
--     RCR  reparación con reemplazo            →   8,0 h   (solo correctivo)
--     RSR  reparación sin reemplazo            →   3,2 h   (ver abajo)
--
-- EL ÚNICO QUE NO SALE DE LA HISTORIA ES RSR, Y HAY QUE DECIRLO
-- El archivo histórico no separa las reparaciones con repuesto de las que no lo
-- llevan: las 111 son «correctivo» a secas. Así que RSR se deriva de la única
-- relación que el acta ya decidió: sus plazos en días son exactamente 1 a 2,5
-- contra los de RCR (2/4/8 contra 5/10/20). Aplicada esa proporción a las 8 h de
-- RCR, dan 3,2 h.
--
-- Es una derivación, no un dato. Está escrito acá para que el acta la ratifique
-- o la cambie — y cambiarla es editar una fila.
--
-- TODO ESTO SIGUE EN BORRADOR
-- Los parámetros del bono no están vigentes, así que estas horas son una
-- propuesta que el plan usa como sugerencia. Nada se paga con ellas todavía.
-- ============================================================================

BEGIN;

-- ── 1 · El estándar de horas por tipo de tarea ──────────────────────────────
ALTER TABLE taller_bono_concepto
  ADD COLUMN IF NOT EXISTS horas_estandar NUMERIC,
  ADD COLUMN IF NOT EXISTS horas_fuente   TEXT;

COMMENT ON COLUMN taller_bono_concepto.horas_estandar IS
    'Horas que el estándar le da a una visita de este tipo. Es lo que el plan '
    'propone cuando el planificador elige el concepto, y el techo del que '
    'cuelgan las Órdenes de Servicio.';

UPDATE taller_bono_concepto SET
    horas_estandar = 8.0,
    horas_fuente = 'Mediana de 23 OS históricas «solo preventiva» (2024-2026)'
 WHERE concepto = 'MPN';

UPDATE taller_bono_concepto SET
    horas_estandar = 32.5,
    horas_fuente = 'Mediana de 43 OS históricas «preventiva + correctivo» (2024-2026)'
 WHERE concepto = 'MTN';

UPDATE taller_bono_concepto SET
    horas_estandar = 8.0,
    horas_fuente = 'Mediana de 111 OS históricas «solo correctivo» (2024-2026)'
 WHERE concepto = 'RCR';

UPDATE taller_bono_concepto SET
    horas_estandar = 3.2,
    horas_fuente = 'DERIVADO, no medido: la historia no separa con y sin repuesto. '
                || 'Se aplica la proporción 1:2,5 que el acta ya fijó en los plazos '
                || '(RSR 2/4/8 días contra RCR 5/10/20) sobre las 8 h de RCR.'
 WHERE concepto = 'RSR';

-- ── 2 · La leyenda del planificador ahora trae las horas ───────────────────
--
-- Se dropea antes: agregar columnas a un RETURNS TABLE es cambiarle el tipo
-- de retorno, y eso Postgres no lo hace con CREATE OR REPLACE.
DROP FUNCTION IF EXISTS rpc_taller_conceptos_bono();

CREATE OR REPLACE FUNCTION rpc_taller_conceptos_bono()
RETURNS TABLE (
    concepto        TEXT,
    descripcion     TEXT,
    dias_optimizado INT,
    dias_normal     INT,
    dias_demora     INT,
    horas_estandar  NUMERIC,
    horas_fuente    TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT co.concepto, co.descripcion, co.dias_optimizado, co.dias_normal,
           co.dias_demora, co.horas_estandar, co.horas_fuente
      FROM taller_bono_concepto co
      JOIN taller_bono_parametros p ON p.id = co.parametros_id
     WHERE p.id = (SELECT id FROM taller_bono_parametros
                    ORDER BY estado = 'vigente' DESC, vigencia_desde DESC LIMIT 1)
     ORDER BY co.concepto;
$$;

-- ── 3 · Opción A: la revisión también consume el paraguas ──────────────────
--
-- La OT es la revisión del camión y eso toma tiempo. Ese tiempo se mide en el
-- reloj propio de la OT, y hasta ahora no descontaba nada: las OS se repartían
-- el total como si revisar fuera gratis.
CREATE OR REPLACE FUNCTION fn_taller_ot_horas_revision(p_ot_id UUID)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(round(sum(COALESCE(e.tiempo_efectivo_segundos,
             GREATEST(0, EXTRACT(EPOCH FROM (NOW() - e.started_at))::INT)))::numeric / 3600.0, 2), 0)
      FROM taller_ot_ejecuciones e
     WHERE e.ot_id = p_ot_id;
$$;

COMMENT ON FUNCTION fn_taller_ot_horas_revision(UUID) IS
    'Horas que se fueron en revisar el equipo (el reloj de la OT). Salen del '
    'mismo paraguas que las Órdenes de Servicio: revisar también es trabajo.';

-- Lo que queda para repartir en OS: el techo menos lo que ya costó revisar.
CREATE OR REPLACE FUNCTION fn_taller_ot_techo_os(p_ot_id UUID)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT CASE WHEN fn_taller_ot_horas_plan(p_ot_id) IS NULL THEN NULL
                ELSE GREATEST(0, fn_taller_ot_horas_plan(p_ot_id)
                                 - fn_taller_ot_horas_revision(p_ot_id))
           END;
$$;

-- Igual que arriba: cambia lo que devuelve, así que se dropea primero.
DROP FUNCTION IF EXISTS rpc_taller_ot_presupuesto(UUID);

CREATE OR REPLACE FUNCTION rpc_taller_ot_presupuesto(p_ot_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'horas_plan',      fn_taller_ot_horas_plan(p_ot_id),
        'horas_revision',  fn_taller_ot_horas_revision(p_ot_id),
        'techo_os',        fn_taller_ot_techo_os(p_ot_id),
        'horas_checklist', fn_taller_ot_horas_estimadas(p_ot_id),
        'sin_techo',       fn_taller_ot_horas_plan(p_ot_id) IS NULL,
        'horas_en_os',     fn_taller_ot_horas_os(p_ot_id),
        'horas_libres',    GREATEST(0, COALESCE(fn_taller_ot_techo_os(p_ot_id), 0) - fn_taller_ot_horas_os(p_ot_id)),
        'excedida',        fn_taller_ot_techo_os(p_ot_id) IS NOT NULL
                           AND fn_taller_ot_horas_os(p_ot_id) > fn_taller_ot_techo_os(p_ot_id),
        'horas_reales_os', COALESCE((SELECT round(sum(COALESCE(t.segundos,
                              GREATEST(0, EXTRACT(EPOCH FROM (NOW() - t.inicio))::INT)))::numeric / 3600.0, 2)
                              FROM taller_os_tiempo t JOIN taller_os o ON o.id = t.os_id
                             WHERE o.ot_id = p_ot_id), 0));
$$;

-- ── 4 · Y el techo que se exige al crear una OS es el descontado ────────────
CREATE OR REPLACE FUNCTION rpc_taller_os_crear(
    p_ot_id           UUID,
    p_titulo          TEXT,
    p_nc_ids          UUID[] DEFAULT NULL,
    p_responsable_id  UUID   DEFAULT NULL,
    p_horas_estimadas NUMERIC DEFAULT NULL,
    p_descripcion     TEXT   DEFAULT NULL,
    p_prioridad       TEXT   DEFAULT NULL,
    p_justificacion   TEXT   DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user  UUID := auth.uid();
    v_os    UUID;
    v_folio TEXT;
    v_n     INT := 0;
    v_ajena TEXT;
    v_techo NUMERIC; v_usadas NUMERIC; v_total NUMERIC; v_rev NUMERIC;
    v_just  TEXT := NULLIF(TRIM(COALESCE(p_justificacion,'')),'');
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_taller_es_jefatura() THEN
        RAISE EXCEPTION 'Armar una Orden de Servicio es de la jefatura de taller o planificación.';
    END IF;
    IF length(COALESCE(TRIM(p_titulo),'')) < 4 THEN
        RAISE EXCEPTION 'Ponle un título a la OS: es lo que el mecánico va a leer en su teléfono.';
    END IF;

    IF p_nc_ids IS NOT NULL AND array_length(p_nc_ids, 1) > 0 THEN
        SELECT string_agg(nc.id::TEXT, ', ') INTO v_ajena
          FROM no_conformidades nc
         WHERE nc.id = ANY(p_nc_ids) AND nc.ot_id IS DISTINCT FROM p_ot_id;
        IF v_ajena IS NOT NULL THEN
            RAISE EXCEPTION 'Hay no conformidades que no son de esta OT. Una OS resuelve trabajo de un solo equipo.';
        END IF;
    END IF;

    -- [MIG476] Opción A: el techo de las OS es el del plan MENOS lo que ya costó
    -- revisar el equipo. Revisar también sale del mismo paraguas.
    v_rev    := fn_taller_ot_horas_revision(p_ot_id);
    v_techo  := fn_taller_ot_techo_os(p_ot_id);
    v_usadas := fn_taller_ot_horas_os(p_ot_id);
    v_total  := v_usadas + COALESCE(p_horas_estimadas, 0);

    IF v_techo IS NOT NULL AND v_total > v_techo AND v_just IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'requiere_justificacion', TRUE,
            'horas_plan', fn_taller_ot_horas_plan(p_ot_id),
            'horas_revision', v_rev,
            'techo_os', v_techo,
            'horas_en_os', v_usadas,
            'horas_con_esta', v_total,
            'motivo', format('El plan le dio %s h al equipo y la revisión ya se llevó %s h, '
                             || 'así que para Órdenes de Servicio quedan %s h. Con ésta suman %s h. '
                             || 'Se puede, pero escribe por qué: queda con tu nombre.',
                             fn_taller_ot_horas_plan(p_ot_id), v_rev, v_techo, v_total));
    END IF;

    v_folio := fn_taller_os_folio(p_ot_id);

    INSERT INTO taller_os (folio, ot_id, titulo, descripcion, responsable_id,
                           horas_estimadas, prioridad, creada_por, justificacion_exceso)
    VALUES (v_folio, p_ot_id, TRIM(p_titulo), NULLIF(TRIM(COALESCE(p_descripcion,'')),''),
            p_responsable_id, p_horas_estimadas, NULLIF(TRIM(COALESCE(p_prioridad,'')),''),
            v_user, CASE WHEN v_techo IS NOT NULL AND v_total > v_techo THEN v_just ELSE NULL END)
    RETURNING id INTO v_os;

    IF p_nc_ids IS NOT NULL AND array_length(p_nc_ids, 1) > 0 THEN
        INSERT INTO taller_os_nc (os_id, no_conformidad_id)
        SELECT v_os, x FROM unnest(p_nc_ids) AS x
        ON CONFLICT (no_conformidad_id) DO NOTHING;
        GET DIAGNOSTICS v_n = ROW_COUNT;
    END IF;

    IF p_responsable_id IS NOT NULL THEN
        PERFORM rpc_taller_os_asignar(v_os, p_responsable_id, 'Asignada al crear la OS', FALSE);
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'os_id', v_os, 'folio', v_folio,
                              'nc_asignadas', v_n,
                              'horas_plan', fn_taller_ot_horas_plan(p_ot_id),
                              'techo_os', v_techo, 'horas_en_os', v_total,
                              'sin_techo', v_techo IS NULL,
                              'excedida', v_techo IS NOT NULL AND v_total > v_techo);
END;
$$;

REVOKE ALL ON FUNCTION fn_taller_ot_horas_revision(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_taller_ot_techo_os(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_taller_ot_horas_revision(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_taller_ot_techo_os(UUID) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE r RECORD; v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM taller_bono_concepto WHERE horas_estandar IS NULL;
    IF v_n > 0 THEN RAISE EXCEPTION 'FALLO: quedaron % conceptos sin horas estándar', v_n; END IF;

    RAISE NOTICE '=== el tiempo que el tipo de tarea le da al equipo ===';
    FOR r IN SELECT * FROM rpc_taller_conceptos_bono() LOOP
        RAISE NOTICE '  % · % h · normal hasta %d · %',
            r.concepto, r.horas_estandar, r.dias_normal, left(r.horas_fuente, 62);
    END LOOP;

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_taller_os_crear';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: rpc_taller_os_crear quedó con % firmas', v_n; END IF;

    -- Cuánto se ha ido en revisar, hoy.
    SELECT round(sum(fn_taller_ot_horas_revision(ot.id)),1) INTO v_n
      FROM ordenes_trabajo ot WHERE ot.estado::TEXT NOT IN ('cerrada','cancelada');
    RAISE NOTICE 'horas de revisión medidas en las OT abiertas: % (ahora descuentan del paraguas)',
        COALESCE(v_n::text,'0');
END
$mig$;

COMMIT;
