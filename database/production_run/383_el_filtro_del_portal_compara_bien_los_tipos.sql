-- ============================================================================
-- MIG383 · El filtro del portal compara los tipos como los compara el resto
-- ----------------------------------------------------------------------------
-- MIG379 dejó el portal de prevención reventando con:
--     operator does not exist: tipo_certificacion_enum = text
--
-- `c.tipo` es un enum y la lista de básicos del portal es `text[]`. Postgres no
-- los compara solos. La propia función ya tenía resuelto el problema dos líneas
-- más arriba —usa `array_position(v_basicos, c.tipo::text)`— y el parche de
-- MIG379 escribió `c.tipo = ANY (v_basicos)`, que es lo mismo en intención pero
-- no compila.
--
-- Se usa la forma que la función ya usaba, en vez de inventar otra: donde hay
-- una manera establecida de comparar dos cosas, la segunda manera sólo agrega
-- lugares donde equivocarse.
-- ============================================================================

BEGIN;

DO $patch$
DECLARE
    v_def TEXT;
    v_old TEXT := 'WHERE c.activo_id = a.id AND (v_p.ver_certificados_tecnicos OR c.tipo = ANY (v_basicos))';
    v_new TEXT := 'WHERE c.activo_id = a.id AND (v_p.ver_certificados_tecnicos OR array_position(v_basicos, c.tipo::text) IS NOT NULL)';
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_portal_prevencion_publico';

    IF position(v_new in v_def) > 0 THEN
        RAISE NOTICE 'Ya estaba corregido.';
        RETURN;
    END IF;
    IF position(v_old in v_def) = 0 THEN
        RAISE EXCEPTION 'No se encontró el filtro de MIG379: revisar en qué quedó la función.';
    END IF;

    EXECUTE replace(v_def, v_old, v_new);
END
$patch$;

GRANT EXECUTE ON FUNCTION public.fn_portal_prevencion_publico(text, uuid) TO anon, authenticated;

-- Que de verdad corra, y que corte lo que tiene que cortar.
DO $verif$
DECLARE
    v_tok TEXT; v_acc UUID; v_r JSONB; v_tecnicos BOOLEAN;
BEGIN
    SELECT token INTO v_tok FROM portales_prevencion WHERE faena_codigo = 'ROMERAL';
    IF v_tok IS NULL THEN RAISE NOTICE 'Sin portal de Romeral: nada que verificar.'; RETURN; END IF;

    INSERT INTO portal_prevencion_accesos (portal_id, nombre, email)
    SELECT id, 'Verificación MIG383', 'karen.ducross@esmax.cl'
      FROM portales_prevencion WHERE faena_codigo = 'ROMERAL'
    RETURNING id INTO v_acc;

    v_r := public.fn_portal_prevencion_publico(v_tok, v_acc);

    SELECT EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_r->'equipos') e,
                      jsonb_array_elements(e->'documentos') d
         WHERE d->>'tipo' IN ('torque_ruedas','aire_acondicionado','operatividad',
                              'mantencion','laminas_seguridad','inventario_neumaticos',
                              'calibracion','flujo_descarga')
    ) INTO v_tecnicos;

    IF v_tecnicos THEN
        RAISE EXCEPTION 'El portal sigue mandando certificados técnicos.';
    END IF;
    RAISE NOTICE 'El portal corre y ya no manda técnicos. Equipos: %, personas: %.',
        jsonb_array_length(v_r->'equipos'), jsonb_array_length(v_r->'personal');

    DELETE FROM portal_prevencion_accesos WHERE id = v_acc;
END
$verif$;

COMMIT;
