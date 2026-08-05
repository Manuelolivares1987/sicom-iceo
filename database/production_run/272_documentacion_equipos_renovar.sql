-- ============================================================================
-- SICOM-ICEO | 272 — Actualizar la documentación de los equipos (papeles)
-- ----------------------------------------------------------------------------
-- Reporte: "planificador y jefes intentan actualizar los papeles y no funciona".
--
-- Diagnóstico (verificado contra prod simulando el JWT de un planificador):
--   1) /dashboard/cumplimiento enviaba el tipo con la nomenclatura antigua
--      ('SEC', 'SOAP', 'Revisión Técnica'...). Ninguno de esos valores existe
--      en tipo_certificacion_enum -> TODO guardado fallaba con 22P02
--      «invalid input value for enum tipo_certificacion_enum». (fix en frontend)
--   2) Esa misma pantalla subía el archivo al bucket 'certificaciones', que no
--      existe (los buckets reales son 'documentos', 'calama-*', ...) -> "Bucket
--      not found". (fix en frontend: pasa a 'documentos/cert/...')
--   3) rpc_renovar_certificacion (el botón «Renovar» del Plan Semanal Taller)
--      NUNCA funcionó: el CASE que calcula el estado devuelve TEXT y la columna
--      certificaciones.estado es estado_documento_enum -> "column estado is of
--      type estado_documento_enum but expression is of type text" en CADA
--      llamada. Verificado en prod: 0 filas con notas='Renovado desde Plan
--      Semanal'. Se corrige con el cast explícito.
--      Además forzaba bloqueante = solo RT/SOAP/permiso de circulación e
--      ignoraba las notas, así que no servía como camino único.
--
-- Esta migración deja el RPC como ÚNICA puerta de entrada para crear/renovar
-- documentación desde cualquier pantalla:
--   · p_bloqueante: opcional; NULL mantiene el comportamiento actual (los
--     documentos legales de circulación se marcan bloqueantes solos).
--   · p_notas: opcional, para dejar el contexto de la renovación.
--   · se revoca EXECUTE a anon (el RPC ya exigía auth.uid(), pero no tenía por
--     qué estar expuesto al rol anónimo).
--
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. RPC de renovación/alta de documentación (v2) ─────────────────────────
DROP FUNCTION IF EXISTS public.rpc_renovar_certificacion(
    uuid, tipo_certificacion_enum, date, date, text, character varying, character varying);

CREATE OR REPLACE FUNCTION public.rpc_renovar_certificacion(
    p_activo_id         UUID,
    p_tipo              tipo_certificacion_enum,
    p_fecha_emision     DATE,
    p_fecha_vencimiento DATE,
    p_archivo_url       TEXT               DEFAULT NULL,
    p_numero            CHARACTER VARYING  DEFAULT NULL,
    p_entidad           CHARACTER VARYING  DEFAULT NULL,
    p_bloqueante        BOOLEAN            DEFAULT NULL,
    p_notas             TEXT               DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_id   UUID;
    v_bloq BOOLEAN;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_operaciones',
                     'jefe_mantenimiento','planificador','auditor_calidad') THEN
        RAISE EXCEPTION 'Sin permiso para actualizar documentación de equipos. Rol: %', v_rol;
    END IF;
    IF p_fecha_emision IS NULL OR p_fecha_vencimiento IS NULL THEN
        RAISE EXCEPTION 'Fecha de emisión y vencimiento son obligatorias.';
    END IF;
    IF p_fecha_vencimiento < p_fecha_emision THEN
        RAISE EXCEPTION 'El vencimiento no puede ser anterior a la emisión.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM activos WHERE id = p_activo_id) THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id;
    END IF;

    -- Por defecto, los documentos legales de circulación son bloqueantes; el
    -- que carga el papel puede marcar cualquier otro como bloqueante.
    v_bloq := COALESCE(p_bloqueante, p_tipo IN ('revision_tecnica','soap','permiso_circulacion'));

    INSERT INTO certificaciones (
        activo_id, tipo, numero_certificado, entidad_certificadora,
        fecha_emision, fecha_vencimiento, estado, archivo_url, bloqueante,
        notas, created_by
    ) VALUES (
        p_activo_id, p_tipo, p_numero, p_entidad,
        p_fecha_emision, p_fecha_vencimiento,
        -- El cast es obligatorio: sin él el CASE es TEXT y el INSERT revienta.
        (CASE WHEN p_fecha_vencimiento <= CURRENT_DATE THEN 'vencido'
              WHEN p_fecha_vencimiento <= CURRENT_DATE + 30 THEN 'por_vencer'
              ELSE 'vigente' END)::estado_documento_enum,
        p_archivo_url, v_bloq,
        COALESCE(NULLIF(btrim(p_notas), ''), 'Documento actualizado desde el sistema'),
        v_user
    ) RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'certificacion_id', v_id);
END $function$;

REVOKE ALL ON FUNCTION public.rpc_renovar_certificacion(
    uuid, tipo_certificacion_enum, date, date, text, character varying, character varying, boolean, text)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_renovar_certificacion(
    uuid, tipo_certificacion_enum, date, date, text, character varying, character varying, boolean, text)
    TO authenticated, service_role;


-- ── 2. Adjuntar el archivo a un documento ya cargado (sin duplicar la fila) ──
-- La ficha del equipo permite subir el PDF de un documento que se registró sin
-- respaldo. Ese UPDATE ya está permitido por MIG246, pero se encapsula en un
-- RPC para que el mensaje de error sea entendible y quede trazado quién lo hizo.
CREATE OR REPLACE FUNCTION public.rpc_adjuntar_archivo_certificacion(
    p_certificacion_id UUID,
    p_archivo_url      TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_operaciones',
                     'jefe_mantenimiento','planificador','auditor_calidad') THEN
        RAISE EXCEPTION 'Sin permiso para actualizar documentación de equipos. Rol: %', v_rol;
    END IF;
    IF COALESCE(btrim(p_archivo_url), '') = '' THEN
        RAISE EXCEPTION 'Falta la URL del archivo.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM certificaciones WHERE id = p_certificacion_id) THEN
        RAISE EXCEPTION 'El documento % no existe', p_certificacion_id;
    END IF;

    UPDATE certificaciones
       SET archivo_url = p_archivo_url,
           updated_at  = NOW()
     WHERE id = p_certificacion_id;

    RETURN jsonb_build_object('success', true, 'certificacion_id', p_certificacion_id);
END $function$;

REVOKE ALL ON FUNCTION public.rpc_adjuntar_archivo_certificacion(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_adjuntar_archivo_certificacion(uuid, text) TO authenticated, service_role;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE n INT;
BEGIN
    SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
     WHERE ns.nspname = 'public' AND p.proname = 'rpc_renovar_certificacion';
    IF n <> 1 THEN
        RAISE EXCEPTION 'FALLO: se esperaba 1 rpc_renovar_certificacion, hay %', n;
    END IF;

    SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
     WHERE ns.nspname = 'public' AND p.proname = 'rpc_adjuntar_archivo_certificacion';
    IF n <> 1 THEN
        RAISE EXCEPTION 'FALLO: falta rpc_adjuntar_archivo_certificacion';
    END IF;

    RAISE NOTICE 'MIG272 OK: RPCs de documentación de equipos listos';
END $$;

NOTIFY pgrst, 'reload schema';
