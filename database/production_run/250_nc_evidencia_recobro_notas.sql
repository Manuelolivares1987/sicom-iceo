-- ============================================================================
-- SICOM-ICEO | 250 — Bandeja NC: evidencia visible, recobro y notas del operador
-- ----------------------------------------------------------------------------
-- Levantado por el Jefe de Taller (2026-07-27): «no puedo VER las no
-- conformidades» — entra a /dashboard/mantenimiento/no-conformidades y las NC
-- salen peladas: sin foto, sin quién la levantó, sin los insumos que pidió el
-- operador.
--
-- CAUSA RAÍZ (regresión): la MIG199 agregó a v_nc_recepcion las columnas
-- foto_url, checklist_item_ref y n_recursos_operador. La MIG220 (bandeja NC:
-- «las manuales también entran») hizo DROP VIEW + CREATE VIEW copiando la
-- definición VIEJA (MIG159) → borró esas 3 columnas sin querer. Desde entonces
-- el front pide nc.foto_url y llega undefined: la miniatura nunca se pinta
-- aunque las 34 NC de ejecución SÍ tienen foto en la tabla.
--
-- Lo que agrega esta MIG:
--   1. v_nc_recepcion recupera foto_url / checklist_item_ref /
--      n_recursos_operador y suma contexto para poder leerla de un vistazo:
--      observación del ítem, quién la registró, folio de la OT de origen.
--   2. RECOBRO: se expone si la NC es recobrable al cliente o la paga la
--      empresa. La fuente ya existe y nadie la estaba mirando:
--        checklist_v2_instance_item.cobrable_override  (lo que decidió terreno)
--        checklist_template_v2_item.default_cobrable   (lo que dice la pauta)
--        informe_recepcion_hallazgos.atribuible_cliente (NC de recepción)
--      + no_conformidades.recobro_override para que el jefe lo fije/corrija,
--      con rpc_nc_set_recobro (acepta varias NC = todo el equipo de una).
--   3. NOTAS DEL OPERADOR (MIG249, evidencias_ot tipo='nota'): la bandeja
--      cuenta las notas de la OT que originó la NC para que el jefe sepa que
--      hay anexos que leer (el front las despliega con texto y fotos).
-- ADITIVA, IDEMPOTENTE. No borra datos.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='no_conformidades' AND column_name='foto_url') THEN
        RAISE EXCEPTION 'STOP — falta no_conformidades.foto_url (MIG145).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='ot_recursos_solicitados' AND column_name='instance_item_id') THEN
        RAISE EXCEPTION 'STOP — falta ot_recursos_solicitados.instance_item_id (MIG199).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='default_cobrable_enum') THEN
        RAISE EXCEPTION 'STOP — falta default_cobrable_enum (MIG54).';
    END IF;
END $$;


-- ── 1. Decisión de recobro del jefe sobre la NC ──────────────────────────────
ALTER TABLE no_conformidades
    ADD COLUMN IF NOT EXISTS recobro_override    default_cobrable_enum,
    ADD COLUMN IF NOT EXISTS recobro_nota        TEXT,
    ADD COLUMN IF NOT EXISTS recobro_definido_por UUID,
    ADD COLUMN IF NOT EXISTS recobro_definido_at  TIMESTAMPTZ;

COMMENT ON COLUMN no_conformidades.recobro_override IS
    'Decisión del jefe de taller sobre quién paga: cliente=recobrable, empresa=lo asume Pillado, compartido, evaluar, na. Manda sobre lo que sugiere la pauta/checklist. MIG250.';


-- ── 2. Vista de la bandeja: evidencia + recobro + notas ──────────────────────
-- OJO al tocar esta vista: MIG199 y MIG250 agregan columnas que el front usa.
-- Si la vuelves a recrear, parte SIEMPRE de esta definición (no de una vieja).
DROP VIEW IF EXISTS v_nc_recepcion;
CREATE VIEW v_nc_recepcion AS
SELECT nc.id, nc.activo_id, a.patente, a.codigo, a.nombre AS equipo,
       nc.descripcion, nc.severidad, nc.origen, nc.estado_planificacion,
       nc.grupo_trabajo, nc.horas_estimadas, nc.tiempo_estimado_dias,
       nc.informe_recepcion_id, nc.plan_ot_id, nc.resuelto, nc.created_at,
       (SELECT count(*) FROM nc_materiales m WHERE m.no_conformidad_id = nc.id) AS n_materiales,
       nc.ot_id,

       -- [MIG199, restaurado] evidencia y vínculo con el hallazgo del checklist
       nc.foto_url,
       nc.checklist_item_ref,
       (SELECT count(*) FROM ot_recursos_solicitados r
         WHERE r.instance_item_id = nc.checklist_item_ref) AS n_recursos_operador,

       -- [MIG250] contexto para leer la NC sin abrir nada más
       ii.observacion              AS observacion_item,
       ot.folio                    AS ot_folio,
       up.nombre_completo          AS registrada_por_nombre,

       -- [MIG250] ¿se le recobra al cliente? Manda el jefe; si no se pronunció,
       -- lo que marcó terreno; si no, la pauta; si no, el informe de recepción.
       COALESCE(
           nc.recobro_override,
           ii.cobrable_override,
           ti.default_cobrable,
           CASE WHEN h.atribuible_cliente IS TRUE  THEN 'cliente'::default_cobrable_enum
                WHEN h.atribuible_cliente IS FALSE THEN 'empresa'::default_cobrable_enum END
       )                           AS recobro,
       CASE WHEN nc.recobro_override  IS NOT NULL THEN 'jefe'
            WHEN ii.cobrable_override IS NOT NULL THEN 'terreno'
            WHEN ti.default_cobrable  IS NOT NULL THEN 'pauta'
            WHEN h.atribuible_cliente IS NOT NULL THEN 'informe'
            ELSE 'sin_definir' END  AS recobro_fuente,
       nc.recobro_nota,

       -- [MIG250] notas/anexos que dejó el operador en la(s) OT de esta NC
       (SELECT count(*) FROM evidencias_ot e
         WHERE e.tipo = 'nota'
           AND (e.ot_id = nc.ot_id OR e.ot_id = nc.plan_ot_id)) AS n_notas_operador

FROM no_conformidades nc
JOIN activos a ON a.id = nc.activo_id
LEFT JOIN checklist_v2_instance_item ii ON ii.id = nc.checklist_item_ref
LEFT JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
LEFT JOIN informe_recepcion_hallazgos h  ON h.id = nc.hallazgo_id
LEFT JOIN ordenes_trabajo ot             ON ot.id = COALESCE(nc.plan_ot_id, nc.ot_id)
LEFT JOIN usuarios_perfil up             ON up.id = nc.registrada_por
-- [MIG220] 'manual' incluido: antes eran invisibles pero bloqueaban certificados (MIG219)
WHERE nc.origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot','ejecucion_ot','manual');

GRANT SELECT ON v_nc_recepcion TO authenticated;


-- ── 3. El jefe fija/corrige el recobro (una NC o todo el equipo) ─────────────
CREATE OR REPLACE FUNCTION public.rpc_nc_set_recobro(
    p_nc_ids UUID[],
    p_valor  TEXT,          -- cliente | empresa | compartido | evaluar | na | (null = volver al sugerido)
    p_nota   TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_rol TEXT := public.fn_user_rol();
    v_val default_cobrable_enum;
    v_n   INT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol IS NULL OR v_rol NOT IN (
        'administrador','gerencia','subgerente_operaciones','jefe_operaciones',
        'jefe_mantenimiento','planificador','supervisor') THEN
        RAISE EXCEPTION 'No autorizado para definir el recobro (rol: %)', COALESCE(v_rol,'?')
            USING ERRCODE='42501';
    END IF;

    IF p_nc_ids IS NULL OR array_length(p_nc_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'Sin No Conformidades que actualizar';
    END IF;

    IF p_valor IS NOT NULL AND btrim(p_valor) <> '' THEN
        IF p_valor NOT IN ('cliente','empresa','compartido','evaluar','na') THEN
            RAISE EXCEPTION 'Valor de recobro inválido: %', p_valor;
        END IF;
        v_val := p_valor::default_cobrable_enum;
    END IF;  -- NULL = limpiar el override y volver a lo que sugiere la pauta

    UPDATE no_conformidades
       SET recobro_override     = v_val,
           recobro_nota         = NULLIF(btrim(COALESCE(p_nota,'')), ''),
           recobro_definido_por = CASE WHEN v_val IS NULL THEN NULL ELSE auth.uid() END,
           recobro_definido_at  = CASE WHEN v_val IS NULL THEN NULL ELSE NOW() END,
           updated_at           = NOW()
     WHERE id = ANY(p_nc_ids);
    GET DIAGNOSTICS v_n = ROW_COUNT;

    RETURN jsonb_build_object('ok', true, 'actualizadas', v_n, 'recobro', v_val);
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_nc_set_recobro(UUID[], TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_nc_set_recobro(UUID[], TEXT, TEXT) TO authenticated;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_faltan TEXT;
    v_con_foto INT; v_con_recobro INT; v_con_notas INT;
    v_nc UUID; v_user UUID; v_res JSONB;
BEGIN
    -- 1. La vista trae TODAS las columnas que el front consume
    SELECT string_agg(c, ', ') INTO v_faltan
      FROM unnest(ARRAY['foto_url','checklist_item_ref','n_recursos_operador',
                        'recobro','recobro_fuente','n_notas_operador',
                        'observacion_item','ot_folio','registrada_por_nombre']) c
     WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_name='v_nc_recepcion' AND column_name=c);
    IF v_faltan IS NOT NULL THEN
        RAISE EXCEPTION 'FALLO — v_nc_recepcion sin columnas: %', v_faltan;
    END IF;

    SELECT count(*) FILTER (WHERE foto_url IS NOT NULL),
           count(*) FILTER (WHERE recobro IS NOT NULL),
           COALESCE(sum(n_notas_operador), 0)
      INTO v_con_foto, v_con_recobro, v_con_notas
      FROM v_nc_recepcion;
    RAISE NOTICE 'MIG250: NC con foto visible=%, con recobro resuelto=%, notas del operador enlazadas=%',
        v_con_foto, v_con_recobro, v_con_notas;
    IF v_con_foto = 0 THEN
        RAISE WARNING 'MIG250: ninguna NC trae foto — revisar si es real o si el JOIN rompió algo';
    END IF;

    -- 2. Smoke del RPC con el jefe de taller (se revierte)
    SELECT id INTO v_nc   FROM no_conformidades ORDER BY created_at DESC LIMIT 1;
    SELECT id INTO v_user FROM usuarios_perfil WHERE rol='jefe_mantenimiento' LIMIT 1;
    IF v_nc IS NULL OR v_user IS NULL THEN
        RAISE NOTICE 'MIG250: sin datos para smoke del RPC (ok)'; RETURN;
    END IF;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    v_res := public.rpc_nc_set_recobro(ARRAY[v_nc], 'cliente', 'MIG250 smoke');
    IF (v_res->>'actualizadas')::int <> 1 THEN RAISE EXCEPTION 'FALLO smoke rpc_nc_set_recobro'; END IF;
    IF (SELECT recobro FROM v_nc_recepcion WHERE id = v_nc) <> 'cliente' THEN
        RAISE EXCEPTION 'FALLO — el override del jefe no manda en la vista';
    END IF;
    RAISE NOTICE 'MIG250 OK: jefe fijó recobro=cliente y la vista lo refleja';
    RAISE EXCEPTION 'rollback-smoke';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'rollback-smoke' THEN RAISE NOTICE 'Smoke revertido (ok)';
    ELSE RAISE; END IF;
END $$;

NOTIFY pgrst, 'reload schema';
