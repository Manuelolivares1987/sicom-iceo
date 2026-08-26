-- ============================================================================
-- MIG405 · Seleccionar y guardar en el historial
-- ----------------------------------------------------------------------------
-- LO QUE PIDIÓ MANUEL
-- 26-08-2026: «como este mes de agosto ha sido de prueba real, me gustaría que
-- en todos los menú aparezca el concepto de seleccionar y guardar en el
-- historial, para que todo se vea más sano, más limpio. Y así tener parámetros
-- reales al respecto».
--
-- LO QUE HAY ACUMULADO
--     no_conformidades ......... 114 · las 114 abiertas · desde el 21-abr
--     ordenes_trabajo .......... 121 ·  59 abiertas ..... desde el 26-mar
--     ot_recursos_solicitados ..  31 ·  27 abiertos
--     bodega_tickets ...........  13 ·  10 emitidos ..... uno del 7-jul
--     checklist_v2_instance .... 122 · las 122 sin cerrar
--
-- Mucho de eso es la prueba, no la operación. Y mientras siga mezclado, ningún
-- indicador dice la verdad: los 47,3 h de «pedir → aprobar» o las 55 preventivas
-- vencidas cargan con meses de ensayo.
--
-- ── ARCHIVAR NO ES BORRAR ───────────────────────────────────────────────────
-- Nada se elimina. Cada registro queda con quién lo archivó, cuándo y por qué,
-- y sale de las pantallas operativas — que es lo que se pidió: que se vea más
-- limpio, no que desaparezca la historia.
--
-- ── SE ARCHIVA EN LOTES, Y EL LOTE SE PUEDE DESHACER ────────────────────────
-- Archivar 114 no conformidades de una vez y descubrir que treinta eran reales
-- tiene que tener vuelta atrás. Cada acción crea un lote con su motivo, y
-- `rpc_desarchivar_lote` revierte exactamente ese lote — no «lo de hoy», ni «lo
-- del usuario tal»: ese lote.
--
-- ── UN SOLO MECANISMO PARA TODAS LAS PANTALLAS ──────────────────────────────
-- Un RPC genérico en vez de uno por entidad. Cuatro tablas ya lo usan; agregar
-- la quinta es una línea en `fn_archivable_config`, no otro circuito paralelo
-- que se comporte distinto y haya que volver a explicar.
--
-- ── LO QUE NO HACE ──────────────────────────────────────────────────────────
-- No archiva nada por su cuenta. Elegir qué fue prueba y qué fue trabajo real
-- es un juicio de operaciones: la migración deja la herramienta, la usa una
-- persona mirando la lista.
-- ============================================================================

BEGIN;

-- ── 1. Las columnas, en cada tabla archivable ─────────────────────────────
DO $r$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['no_conformidades','ordenes_trabajo','bodega_tickets',
                             'ot_recursos_solicitados','checklist_v2_instance']
    LOOP
        EXECUTE format($f$
            ALTER TABLE public.%I
              ADD COLUMN IF NOT EXISTS archivado_at     TIMESTAMPTZ,
              ADD COLUMN IF NOT EXISTS archivado_por    UUID,
              ADD COLUMN IF NOT EXISTS archivado_motivo TEXT,
              ADD COLUMN IF NOT EXISTS archivado_lote   UUID
        $f$, t);
        -- El índice parcial: las consultas operativas preguntan siempre por lo
        -- NO archivado, que es la enorme mayoría.
        EXECUTE format(
            'CREATE INDEX IF NOT EXISTS idx_%s_no_archivado ON public.%I (id) WHERE archivado_at IS NULL',
            t, t);
    END LOOP;
END
$r$;

-- ── 2. El historial de lotes ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.archivo_lotes (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entidad       TEXT        NOT NULL,
    motivo        TEXT        NOT NULL,
    n_registros   INTEGER     NOT NULL DEFAULT 0,
    archivado_por UUID        REFERENCES public.usuarios_perfil(id),
    archivado_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revertido_at  TIMESTAMPTZ,
    revertido_por UUID        REFERENCES public.usuarios_perfil(id)
);

COMMENT ON TABLE public.archivo_lotes IS
  'MIG405: cada vez que alguien guarda registros en el historial. El lote es la unidad que se puede deshacer.';

ALTER TABLE public.archivo_lotes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS archivo_lotes_lectura ON public.archivo_lotes;
CREATE POLICY archivo_lotes_lectura ON public.archivo_lotes
  FOR SELECT TO authenticated USING (true);

-- ── 3. Qué se puede archivar, y quién ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_archivable_config(p_entidad text)
RETURNS TABLE (tabla text, roles text[])
LANGUAGE sql IMMUTABLE
AS $function$
  -- Sólo las dos columnas de la firma: con SELECT * salían tres y Postgres
  -- rechaza la función entera.
  SELECT t.tabla, t.roles FROM (VALUES
    ('no_conformidades',        'no_conformidades',        ARRAY['administrador','subgerente_operaciones','jefe_mantenimiento','planificador']),
    ('ordenes_trabajo',         'ordenes_trabajo',         ARRAY['administrador','subgerente_operaciones','jefe_mantenimiento','planificador']),
    ('bodega_tickets',          'bodega_tickets',          ARRAY['administrador','subgerente_operaciones','bodeguero','jefe_mantenimiento']),
    ('ot_recursos_solicitados', 'ot_recursos_solicitados', ARRAY['administrador','subgerente_operaciones','jefe_mantenimiento','planificador']),
    ('checklist_v2_instance',   'checklist_v2_instance',   ARRAY['administrador','subgerente_operaciones','jefe_mantenimiento'])
  ) AS t(entidad, tabla, roles)
  WHERE t.entidad = p_entidad;
$function$;

-- ── 4. Guardar en el historial ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_archivar(
    p_entidad text,
    p_ids     uuid[],
    p_motivo  text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_cfg RECORD; v_lote UUID; v_n INTEGER; v_motivo TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    SELECT * INTO v_cfg FROM fn_archivable_config(p_entidad);
    IF v_cfg.tabla IS NULL THEN
        RAISE EXCEPTION 'No se puede archivar «%»: no está en la lista de entidades archivables', p_entidad;
    END IF;
    IF NOT (v_rol = ANY (v_cfg.roles)) THEN
        RAISE EXCEPTION 'Tu rol (%) no puede guardar % en el historial', v_rol, p_entidad;
    END IF;

    IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'No seleccionaste ningún registro';
    END IF;

    -- El motivo es obligatorio: dentro de seis meses, «por qué desapareció esto
    -- de la lista» tiene que tener respuesta escrita.
    v_motivo := NULLIF(btrim(COALESCE(p_motivo, '')), '');
    IF v_motivo IS NULL OR length(v_motivo) < 4 THEN
        RAISE EXCEPTION 'Escribe por qué se guarda en el historial (por ejemplo: «prueba de agosto»)';
    END IF;

    INSERT INTO archivo_lotes (entidad, motivo, archivado_por)
    VALUES (p_entidad, v_motivo, v_user)
    RETURNING id INTO v_lote;

    -- Sólo lo que todavía no está archivado: repetir la acción no vuelve a
    -- contar ni reescribe quién lo archivó la primera vez.
    EXECUTE format($f$
        UPDATE public.%I
           SET archivado_at = NOW(), archivado_por = $1,
               archivado_motivo = $2, archivado_lote = $3
         WHERE id = ANY($4) AND archivado_at IS NULL
    $f$, v_cfg.tabla) USING v_user, v_motivo, v_lote, p_ids;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    UPDATE archivo_lotes SET n_registros = v_n WHERE id = v_lote;

    IF v_n = 0 THEN
        DELETE FROM archivo_lotes WHERE id = v_lote;
        RETURN jsonb_build_object('success', false, 'archivados', 0,
            'mensaje', 'Todos los seleccionados ya estaban en el historial');
    END IF;

    RETURN jsonb_build_object('success', true, 'archivados', v_n,
        'lote_id', v_lote, 'entidad', p_entidad, 'motivo', v_motivo);
END $function$;

-- ── 5. Deshacer un lote ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_desarchivar_lote(p_lote uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_lote RECORD; v_cfg RECORD; v_n INTEGER;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    SELECT * INTO v_lote FROM archivo_lotes WHERE id = p_lote;
    IF v_lote.id IS NULL THEN RAISE EXCEPTION 'Ese lote no existe'; END IF;
    IF v_lote.revertido_at IS NOT NULL THEN
        RAISE EXCEPTION 'Ese lote ya se había devuelto el %', to_char(v_lote.revertido_at, 'DD-MM-YYYY HH24:MI');
    END IF;

    SELECT * INTO v_cfg FROM fn_archivable_config(v_lote.entidad);
    IF NOT (v_rol = ANY (v_cfg.roles)) THEN
        RAISE EXCEPTION 'Tu rol (%) no puede devolver % desde el historial', v_rol, v_lote.entidad;
    END IF;

    -- Sólo lo de ESE lote. Si algo se archivó después por otra razón, se queda.
    EXECUTE format($f$
        UPDATE public.%I
           SET archivado_at = NULL, archivado_por = NULL,
               archivado_motivo = NULL, archivado_lote = NULL
         WHERE archivado_lote = $1
    $f$, v_cfg.tabla) USING p_lote;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    UPDATE archivo_lotes SET revertido_at = NOW(), revertido_por = v_user WHERE id = p_lote;

    RETURN jsonb_build_object('success', true, 'devueltos', v_n, 'entidad', v_lote.entidad);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_archivar(text, uuid[], text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_desarchivar_lote(uuid) TO authenticated;

-- ── 6. El historial, para verlo ───────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_archivo_lotes AS
SELECT l.id, l.entidad, l.motivo, l.n_registros,
       l.archivado_at, COALESCE(u.nombre_completo, 'Sin nombre') AS archivado_por_nombre,
       l.revertido_at, ur.nombre_completo AS revertido_por_nombre,
       (l.revertido_at IS NULL) AS vigente
  FROM archivo_lotes l
  LEFT JOIN usuarios_perfil u  ON u.id  = l.archivado_por
  LEFT JOIN usuarios_perfil ur ON ur.id = l.revertido_por;

GRANT SELECT ON public.v_archivo_lotes TO authenticated;

-- ── 7. Las pantallas pueden saber qué está archivado ──────────────────────
-- La vista de la bandeja de NC gana las dos columnas. Se reescribe desde su
-- propia definición en vez de transcribir sus 62 líneas a mano: copiarlas para
-- agregar dos columnas es la forma segura de romper otra cosa.
DO $r$
DECLARE v_def TEXT; v_pos INT; v_nueva TEXT;
BEGIN
    SELECT pg_get_viewdef('public.v_nc_recepcion'::regclass, true) INTO v_def;

    IF position('nc.archivado_at' IN v_def) > 0 THEN
        RAISE NOTICE 'v_nc_recepcion ya expone lo archivado. Nada que hacer.';
        RETURN;
    END IF;

    -- El FROM de primer nivel: pg_get_viewdef lo deja con exactamente tres
    -- espacios de sangría; los de las subconsultas van más adentro.
    v_pos := position(E'
   FROM ' IN v_def);
    IF v_pos = 0 THEN
        RAISE EXCEPTION 'No se encontró el FROM de primer nivel en v_nc_recepcion: revisar a mano';
    END IF;

    v_nueva := 'CREATE OR REPLACE VIEW public.v_nc_recepcion AS '
            || substr(v_def, 1, v_pos - 1)
            || ',' || E'
    nc.archivado_at,' || E'
    nc.archivado_motivo'
            || substr(v_def, v_pos);

    EXECUTE v_nueva;
    RAISE NOTICE 'v_nc_recepcion ahora expone archivado_at y archivado_motivo.';
END
$r$;

-- ── 8. Cómo queda ─────────────────────────────────────────────────────────
DO $r$
DECLARE v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM information_schema.columns
     WHERE table_schema='public' AND table_name='v_nc_recepcion'
       AND column_name IN ('archivado_at','archivado_motivo');
    IF v_n <> 2 THEN RAISE EXCEPTION 'v_nc_recepcion quedó sin las columnas de archivo'; END IF;

    RAISE NOTICE 'Entidades archivables: %',
      (SELECT string_agg(e, ', ') FROM (VALUES ('no_conformidades'),('ordenes_trabajo'),
        ('bodega_tickets'),('ot_recursos_solicitados'),('checklist_v2_instance')) v(e));
    RAISE NOTICE 'Nada se archivó: elegir qué fue prueba y qué fue trabajo real lo hace una persona mirando la lista.';
END
$r$;

COMMIT;
