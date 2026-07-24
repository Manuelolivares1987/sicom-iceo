-- ============================================================================
-- SICOM-ICEO | 249 — Notas con foto del operador de taller (anexo a la OT)
-- ----------------------------------------------------------------------------
-- Pedido Manuel: el operador de taller (/m/taller/ot/[id]) debe poder agregar
-- NOTAS con foto como anexo de la OT, visibles para el jefe de taller, por si
-- se escapa algo del checklist.
--
-- Se reutiliza la tabla evidencias_ot (ya la muestra la pestaña Evidencias de la
-- ficha de OT). Una nota = una fila tipo='nota': descripcion=texto,
-- archivo_url=primera foto (o '' si no hay), metadata.fotos=todas las fotos +
-- autor + origen + client_uuid (idempotencia offline).
--
-- El operador NO tiene INSERT RLS sobre evidencias_ot → se inserta vía RPC
-- SECURITY DEFINER que whitelistea los roles de taller (mismo patrón que
-- rpc_ot_recurso_solicitar, MIG197). Fotos en bucket evidencias-verificacion.
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. Permitir tipo='nota' en evidencias_ot ────────────────────────────────
ALTER TABLE evidencias_ot DROP CONSTRAINT IF EXISTS evidencias_ot_tipo_check;
ALTER TABLE evidencias_ot ADD CONSTRAINT evidencias_ot_tipo_check
  CHECK (tipo::text = ANY (ARRAY[
    'foto_antes','foto_durante','foto_despues','documento','firma','nota'
  ]::text[]));

-- archivo_url puede ir vacío en notas de solo texto.
ALTER TABLE evidencias_ot ALTER COLUMN archivo_url DROP NOT NULL;


-- ── 2. RPC: el operador agrega una nota (SECURITY DEFINER) ──────────────────
CREATE OR REPLACE FUNCTION public.rpc_ot_nota_agregar(
    p_ot_id       uuid,
    p_texto       text,
    p_fotos       text[] DEFAULT '{}',
    p_autor       text   DEFAULT NULL,
    p_client_uuid uuid   DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_rol       text;
    v_estado    text;
    v_id        uuid;
    v_existente uuid;
BEGIN
    -- Autorización: roles de taller (mismo criterio que recursos del operador).
    v_rol := public.fn_user_rol();
    IF v_rol IS NULL OR v_rol NOT IN (
        'operador_taller','tecnico_mantenimiento','jefe_mantenimiento',
        'planificador','supervisor','administrador') THEN
        RAISE EXCEPTION 'No autorizado para agregar notas a la OT' USING ERRCODE='42501';
    END IF;

    IF p_texto IS NULL OR length(trim(p_texto)) = 0 THEN
        RAISE EXCEPTION 'La nota no puede estar vacía';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ordenes_trabajo WHERE id = p_ot_id) THEN
        RAISE EXCEPTION 'OT % no existe', p_ot_id;
    END IF;

    -- Idempotencia offline: si ya existe una nota con este client_uuid, devolverla.
    IF p_client_uuid IS NOT NULL THEN
        SELECT id INTO v_existente FROM evidencias_ot
         WHERE ot_id = p_ot_id AND tipo = 'nota'
           AND metadata->>'client_uuid' = p_client_uuid::text
         LIMIT 1;
        IF v_existente IS NOT NULL THEN
            RETURN jsonb_build_object('ok', true, 'id', v_existente, 'duplicado', true);
        END IF;
    END IF;

    INSERT INTO evidencias_ot (ot_id, tipo, archivo_url, descripcion, metadata, created_by)
    VALUES (
        p_ot_id, 'nota',
        COALESCE(p_fotos[1], ''),
        trim(p_texto),
        jsonb_build_object(
            'fotos',       to_jsonb(COALESCE(p_fotos, '{}')),
            'origen',      'operador',
            'autor',       p_autor,
            'client_uuid', p_client_uuid
        ),
        auth.uid()
    )
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('ok', true, 'id', v_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_ot_nota_agregar(uuid, text, text[], text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_ot_nota_agregar(uuid, text, text[], text, uuid) TO authenticated;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE v_ot uuid; v_user uuid; v_res jsonb;
BEGIN
    SELECT id INTO v_ot FROM ordenes_trabajo ORDER BY created_at DESC LIMIT 1;
    SELECT id INTO v_user FROM usuarios_perfil WHERE rol='operador_taller' LIMIT 1;
    IF v_ot IS NULL OR v_user IS NULL THEN
        RAISE NOTICE 'MIG249: sin datos para smoke test (ok)'; RETURN;
    END IF;
    PERFORM set_config('request.jwt.claims', json_build_object('sub',v_user,'role','authenticated')::text, true);
    v_res := public.rpc_ot_nota_agregar(v_ot, 'MIG249 smoke test', ARRAY['http://x/f.jpg'], 'Test', gen_random_uuid());
    IF NOT (v_res->>'ok')::boolean THEN RAISE EXCEPTION 'FALLO smoke'; END IF;
    RAISE NOTICE 'MIG249 OK: operador insertó nota id=%', v_res->>'id';
    RAISE EXCEPTION 'rollback-smoke';  -- no dejar la nota de prueba
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'rollback-smoke' THEN RAISE NOTICE 'Smoke revertido (ok)';
    ELSE RAISE; END IF;
END $$;

NOTIFY pgrst, 'reload schema';
