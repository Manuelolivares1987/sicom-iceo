-- ============================================================================
-- MIG569 · La secretaria técnica de Romeral renueva los exámenes de su gente
-- ============================================================================
--
-- LO QUE PASÓ (21-09-2026)
-- Catalina (catalina@pillado.cl, planificador, Romeral) quiso renovar el
-- Psicosensotécnico Riguroso de Erick Guerrero y la pantalla respondió
-- «new row violates row-level security policy». MIG565 le dio al rol
-- planificador `prevencion: view`, no `edit`: el primer paso de la renovación
-- (subir el PDF al bucket privado examenes-personal) exige
-- fn_prevencion_personal_puede_editar() y ahí se cortó.
--
-- LO QUE DECIDIÓ MANUEL
-- Solo Catalina y solo sobre trabajadores de Romeral: POR PERSONA, no por
-- rol. Dar `edit` al rol planificador habría abierto a Eduardo y María Isabel
-- la edición de exámenes, personal, destinatarios de alertas y portales de
-- cualquier faena.
--
-- LA CORRECCIÓN
-- · usuarios_perfil.prevencion_edita_faena: el faena_codigo de
--   prevencion_personal ('ROMERAL') cuya gente esa persona puede mantener.
--   NULL = nada. Va en el código de prevencion_personal y no en faenas.id
--   porque esa tabla no tiene faena_id (FAE-CMP-ROMERAL ≠ ROMERAL).
-- · fn_prevencion_edita_faena(codigo): puede_editar() de siempre O la marca
--   de la persona coincide con la faena del trabajador.
-- · Se usa en: renovar (RPC), editar el examen (lápiz), subir el respaldo
--   al bucket, y alta/edición de personal. BORRAR personal sigue siendo solo
--   de prevención: no hay política DELETE para la marca.
-- · Destinatarios de alertas y portales NO cambian: siguen con puede_editar().
-- ============================================================================

BEGIN;

ALTER TABLE public.usuarios_perfil
    ADD COLUMN IF NOT EXISTS prevencion_edita_faena TEXT;

COMMENT ON COLUMN public.usuarios_perfil.prevencion_edita_faena IS
    'MIG569: faena_codigo de prevencion_personal cuyos exámenes y fichas puede mantener esta persona aunque su rol no tenga prevencion:edit. NULL = ninguna.';

-- ── La regla, en un solo lugar ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_prevencion_edita_faena(p_faena_codigo TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT fn_prevencion_personal_puede_editar()
        OR EXISTS (
            SELECT 1 FROM usuarios_perfil up
             WHERE up.id = auth.uid() AND up.activo
               AND up.prevencion_edita_faena IS NOT NULL
               AND up.prevencion_edita_faena = p_faena_codigo);
$$;

CREATE OR REPLACE FUNCTION public.fn_prevencion_edita_persona(p_personal_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT fn_prevencion_personal_puede_editar()
        OR EXISTS (
            SELECT 1 FROM prevencion_personal pp
             WHERE pp.id = p_personal_id
               AND fn_prevencion_edita_faena(pp.faena_codigo));
$$;

REVOKE ALL ON FUNCTION public.fn_prevencion_edita_faena(TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_prevencion_edita_persona(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_prevencion_edita_faena(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_prevencion_edita_persona(UUID) TO authenticated;

-- ── Exámenes: el lápiz escribe directo a la tabla ──────────────────────────
DROP POLICY IF EXISTS prev_examenes_write ON public.prevencion_examenes;
CREATE POLICY prev_examenes_write ON public.prevencion_examenes
    FOR ALL TO authenticated
    USING (fn_prevencion_personal_puede_editar())
    WITH CHECK (fn_prevencion_personal_puede_editar());

DROP POLICY IF EXISTS prev_examenes_update_faena ON public.prevencion_examenes;
CREATE POLICY prev_examenes_update_faena ON public.prevencion_examenes
    FOR UPDATE TO authenticated
    USING (fn_prevencion_edita_persona(personal_id))
    WITH CHECK (fn_prevencion_edita_persona(personal_id));

-- ── Personal: alta y edición de su faena, sin borrar ───────────────────────
DROP POLICY IF EXISTS prev_personal_insert_faena ON public.prevencion_personal;
CREATE POLICY prev_personal_insert_faena ON public.prevencion_personal
    FOR INSERT TO authenticated
    WITH CHECK (fn_prevencion_edita_faena(faena_codigo));

DROP POLICY IF EXISTS prev_personal_update_faena ON public.prevencion_personal;
CREATE POLICY prev_personal_update_faena ON public.prevencion_personal
    FOR UPDATE TO authenticated
    USING (fn_prevencion_edita_faena(faena_codigo))
    WITH CHECK (fn_prevencion_edita_faena(faena_codigo));

-- ── Respaldo: la ruta es personal/<personal_id>/<tipo>/<stamp>.<ext> ────────
DROP POLICY IF EXISTS exam_personal_storage_insert ON storage.objects;
CREATE POLICY exam_personal_storage_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'examenes-personal'
        AND (
            fn_prevencion_personal_puede_editar()
            OR (
                (storage.foldername(name))[1] = 'personal'
                AND (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                AND fn_prevencion_edita_persona(((storage.foldername(name))[2])::uuid)
            )
        ));

-- ── Renovar: misma función, el permiso ahora mira al trabajador ────────────
CREATE OR REPLACE FUNCTION public.fn_prevencion_renovar_examen(
    p_examen_id uuid, p_fecha_vencimiento date, p_fecha_emision date DEFAULT NULL::date,
    p_laboratorio text DEFAULT NULL::text, p_archivo_path text DEFAULT NULL::text,
    p_archivo_nombre text DEFAULT NULL::text, p_observacion text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_prev prevencion_examenes%ROWTYPE;
    v_new  prevencion_examenes%ROWTYPE;
BEGIN
    IF p_fecha_vencimiento IS NULL THEN
        RAISE EXCEPTION 'La fecha de vencimiento del nuevo examen es obligatoria.'
            USING ERRCODE = '23514';
    END IF;
    -- Un examen que ya nace vencido no es una renovación: es un error de tipeo,
    -- y dejarlo pasar apagaría la alerta sin que nadie renueve nada.
    IF p_fecha_vencimiento <= CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de vencimiento (%) no puede ser hoy ni pasada.', p_fecha_vencimiento
            USING ERRCODE = '23514';
    END IF;

    SELECT * INTO v_prev FROM prevencion_examenes WHERE id = p_examen_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El examen no existe.' USING ERRCODE = 'P0002';
    END IF;

    -- [MIG569] Prevención puede con todos; quien tiene la marca por persona,
    -- solo con la gente de su faena.
    IF NOT fn_prevencion_edita_persona(v_prev.personal_id) THEN
        RAISE EXCEPTION 'No autorizado para renovar exámenes de este trabajador.' USING ERRCODE = '42501';
    END IF;

    -- Se archiva la versión anterior solo si tenía contenido.
    IF v_prev.fecha_vencimiento IS NOT NULL OR v_prev.archivo_path IS NOT NULL THEN
        INSERT INTO prevencion_examen_historial (
            examen_id, personal_id, tipo_codigo, laboratorio,
            fecha_vencimiento, observacion, archivo_path, reemplazado_por, motivo)
        VALUES (v_prev.id, v_prev.personal_id, v_prev.tipo_codigo, v_prev.laboratorio,
                v_prev.fecha_vencimiento, v_prev.observacion, v_prev.archivo_path,
                auth.uid(), 'Renovación');
    END IF;

    UPDATE prevencion_examenes SET
        fecha_vencimiento  = p_fecha_vencimiento,
        fecha_emision_real = COALESCE(p_fecha_emision, fecha_emision_real),
        laboratorio        = COALESCE(NULLIF(trim(p_laboratorio), ''), laboratorio),
        archivo_path       = COALESCE(p_archivo_path, archivo_path),
        archivo_nombre     = COALESCE(p_archivo_nombre, archivo_nombre),
        observacion        = NULLIF(trim(COALESCE(p_observacion, '')), ''),
        -- Renovar limpia el bloqueo del mandante: si el examen nuevo también
        -- viniera de un laboratorio no aceptado, se vuelve a marcar a mano.
        observacion_bloqueante = false,
        aplica             = true,
        renovado_at        = NOW(),
        renovado_por       = auth.uid()
     WHERE id = p_examen_id
    RETURNING * INTO v_new;

    -- La renovación reinicia el ciclo de avisos.
    DELETE FROM prevencion_alertas_enviadas WHERE examen_id = p_examen_id;

    RETURN to_jsonb(v_new);
END $function$;

-- ── La marca: Catalina, Romeral ─────────────────────────────────────────────
UPDATE public.usuarios_perfil SET prevencion_edita_faena = 'ROMERAL'
 WHERE email = 'catalina@pillado.cl';

-- ── Verificación como Catalina y como Eduardo ──────────────────────────────
DO $ver$
DECLARE v_cat UUID; v_edu UUID; v_romeral UUID; v_ok BOOLEAN;
BEGIN
    SELECT id INTO v_cat FROM usuarios_perfil WHERE email = 'catalina@pillado.cl';
    SELECT id INTO v_edu FROM usuarios_perfil WHERE email = 'planificador@pillado.cl';
    SELECT id INTO v_romeral FROM prevencion_personal WHERE faena_codigo = 'ROMERAL' LIMIT 1;
    IF v_cat IS NULL OR v_romeral IS NULL THEN RAISE EXCEPTION 'faltan datos para verificar'; END IF;

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_cat, 'role', 'authenticated')::text, true);
    SELECT fn_prevencion_edita_persona(v_romeral) INTO v_ok;
    IF NOT v_ok THEN RAISE EXCEPTION 'FALLO: Catalina no puede editar a un trabajador de Romeral'; END IF;
    IF fn_prevencion_edita_faena('OTRA-FAENA') THEN RAISE EXCEPTION 'FALLO: Catalina edita otra faena'; END IF;
    IF fn_prevencion_personal_puede_editar() THEN RAISE EXCEPTION 'FALLO: Catalina quedó con edit de rol'; END IF;

    IF v_edu IS NOT NULL THEN
        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_edu, 'role', 'authenticated')::text, true);
        IF fn_prevencion_edita_persona(v_romeral) THEN RAISE EXCEPTION 'FALLO: Eduardo también puede editar'; END IF;
    END IF;
    PERFORM set_config('request.jwt.claims', '', true);
    RAISE NOTICE 'OK: Catalina edita Romeral, no otras faenas; Eduardo no edita';
END $ver$;

COMMIT;
