-- ============================================================================
-- SICOM-ICEO | 261 — Las cuentas sembradas no podían entrar, y el planificador
--                    no podía planificar
-- ----------------------------------------------------------------------------
-- 1) Manuel pidió el usuario de Felipe López (auditor de calidad) «como el del
--    jefe de taller». Al revisarlo, Felipe YA tenía perfil (auditor_calidad) y
--    hasta contraseña en auth.users, pero nunca había podido entrar:
--
--        le falta la fila en auth.identities
--
--    Supabase resuelve el login por identidad; sin esa fila el correo/clave
--    devuelve «Invalid login credentials» aunque el usuario exista. Les pasa a
--    las 10 cuentas creadas por siembra SQL. Las creadas desde la app
--    (jefe.taller, operador.taller, vía la edge function admin-crear-usuario)
--    sí la tienen, por eso esas entran.
--
--    Cuentas sin identidad (todas inutilizables hasta ahora):
--      admin@sicom-iceo.cl · supervisor.pc · supervisor.pe · supervisor.mp
--      planificador@sicom-iceo.cl (María Isabel) · tecnico.pc · tecnico.pe
--      tecnico2.mp · bodeguero.mp · tecnico1.mp (Felipe)
--
--    Esta migración les crea la identidad y les completa el metadata. La
--    CONTRASEÑA no va aquí a propósito: se setea aparte, fuera del repositorio.
--
--    A Felipe además se le corrige el correo: quedó sembrado como
--    «tecnico1.mp@sicom-iceo.cl» (era un técnico de la siembra) y pasa a
--    «felipe.lopez@sicom-iceo.cl», siguiendo la convención de jefe.taller@.
--
-- 2) «El planificador puede planificar los equipos que se muestran como
--    disponibles»: hoy NO podía. rpc_taller_agregar_jornada_ot y
--    rpc_taller_quitar_jornada no incluían el rol 'planificador', así que al
--    arrastrar un equipo a un día le saltaba «Rol planificador no autorizado
--    para planificar taller». Curiosamente sí podía mover una jornada ya
--    puesta (rpc_taller_mover_jornada) y agregar tareas libres.
--    Confirmar la semana y liberar a ejecución siguen siendo de jefatura: son
--    el control, no la planificación.
--
-- ADITIVA, IDEMPOTENTE. No borra datos ni contiene credenciales.
-- ============================================================================

-- ── 1. Correo de Felipe ─────────────────────────────────────────────────────
DO $$
DECLARE v_id UUID; v_nuevo TEXT := 'felipe.lopez@sicom-iceo.cl';
BEGIN
    SELECT id INTO v_id FROM usuarios_perfil
     WHERE nombre_completo ILIKE 'Felipe L%pez' AND rol = 'auditor_calidad' LIMIT 1;
    IF v_id IS NULL THEN
        RAISE NOTICE 'MIG261: no está el perfil de Felipe López (auditor_calidad), se omite';
        RETURN;
    END IF;
    IF EXISTS (SELECT 1 FROM auth.users WHERE email = v_nuevo AND id <> v_id) THEN
        RAISE EXCEPTION 'MIG261: el correo % ya lo usa otra cuenta', v_nuevo;
    END IF;

    UPDATE auth.users
       SET email = v_nuevo, updated_at = NOW(),
           email_confirmed_at = COALESCE(email_confirmed_at, NOW())
     WHERE id = v_id;
    UPDATE usuarios_perfil SET email = v_nuevo, updated_at = NOW() WHERE id = v_id;
    RAISE NOTICE 'MIG261: correo de Felipe López -> %', v_nuevo;
END $$;


-- ── 2. Identidad + metadata para toda cuenta que no la tenga ────────────────
INSERT INTO auth.identities (
    id, user_id, provider, provider_id, identity_data, created_at, updated_at
)
SELECT gen_random_uuid(), u.id, 'email', u.id::text,
       jsonb_build_object(
           'sub', u.id::text,
           'email', u.email,
           'email_verified', true,
           'phone_verified', false),
       NOW(), NOW()
  FROM auth.users u
  JOIN usuarios_perfil up ON up.id = u.id AND up.activo = true
 WHERE u.email IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM auth.identities i
                    WHERE i.user_id = u.id AND i.provider = 'email');

-- La identidad guarda el correo: si cambió (Felipe), hay que reflejarlo.
UPDATE auth.identities i
   SET identity_data = i.identity_data || jsonb_build_object('email', u.email),
       updated_at = NOW()
  FROM auth.users u
 WHERE u.id = i.user_id
   AND i.provider = 'email'
   AND COALESCE(i.identity_data->>'email','') IS DISTINCT FROM u.email;

-- Metadata que la app espera de un usuario creado desde la propia plataforma.
UPDATE auth.users u
   SET raw_app_meta_data = COALESCE(u.raw_app_meta_data,'{}'::jsonb)
                           || jsonb_build_object('provider','email','providers', jsonb_build_array('email')),
       raw_user_meta_data = COALESCE(u.raw_user_meta_data,'{}'::jsonb)
                           || jsonb_build_object('nombre_completo', up.nombre_completo, 'rol', up.rol::text),
       updated_at = NOW()
  FROM usuarios_perfil up
 WHERE up.id = u.id AND up.activo = true
   AND (COALESCE(u.raw_app_meta_data->>'provider','') <> 'email'
        OR COALESCE(u.raw_user_meta_data->>'rol','') IS DISTINCT FROM up.rol::text);


-- ── 3. El planificador puede planificar ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_taller_agregar_jornada_ot(
    p_plan_semanal_id uuid,
    p_ot_id uuid,
    p_fecha date,
    p_responsable_id uuid DEFAULT NULL::uuid,
    p_cuadrilla character varying DEFAULT NULL::character varying,
    p_horas_planificadas numeric DEFAULT NULL::numeric,
    p_avance_objetivo numeric DEFAULT NULL::numeric,
    p_observaciones text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_dia_id UUID;
    v_plan_ot_id UUID;
    v_secuencia INT;
    v_rol TEXT;
    v_faena_taller UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    -- [MIG261] 'planificador' agregado: su trabajo es justamente este.
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','planificador') THEN
        RAISE EXCEPTION 'Rol % no autorizado para planificar taller', v_rol;
    END IF;

    SELECT id INTO v_dia_id FROM taller_plan_semanal_dias
     WHERE plan_semanal_id = p_plan_semanal_id AND fecha = p_fecha;
    IF v_dia_id IS NULL THEN
        RAISE EXCEPTION 'Fecha % no pertenece al plan_semanal %', p_fecha, p_plan_semanal_id;
    END IF;

    -- Secuencia incremental por (plan, ot)
    SELECT COALESCE(MAX(secuencia_jornada), 0) + 1
      INTO v_secuencia
      FROM taller_plan_semanal_ots
     WHERE plan_semanal_id = p_plan_semanal_id AND ot_id = p_ot_id;

    INSERT INTO taller_plan_semanal_ots(
        plan_semanal_id, plan_dia_id, ot_id, responsable_id, cuadrilla,
        horas_planificadas, avance_objetivo_pct, secuencia_jornada,
        estado_plan, observaciones, created_by
    ) VALUES (
        p_plan_semanal_id, v_dia_id, p_ot_id, p_responsable_id, p_cuadrilla,
        p_horas_planificadas, p_avance_objetivo, v_secuencia,
        CASE WHEN p_responsable_id IS NULL THEN 'planificada' ELSE 'asignada' END,
        p_observaciones, v_user
    )
    ON CONFLICT (plan_semanal_id, ot_id, plan_dia_id) DO UPDATE
       SET responsable_id    = EXCLUDED.responsable_id,
           cuadrilla         = EXCLUDED.cuadrilla,
           horas_planificadas = EXCLUDED.horas_planificadas,
           avance_objetivo_pct = EXCLUDED.avance_objetivo_pct,
           observaciones     = COALESCE(EXCLUDED.observaciones, taller_plan_semanal_ots.observaciones),
           updated_at        = NOW()
    RETURNING id INTO v_plan_ot_id;

    -- [MIG224] La OT agendada en el taller pasa a la faena del taller: sus
    -- vales se despachan desde la bodega del taller, no la del arriendo.
    SELECT fn_faena_taller_para_activo(o.activo_id) INTO v_faena_taller
      FROM ordenes_trabajo o WHERE o.id = p_ot_id AND o.activo_id IS NOT NULL;
    IF v_faena_taller IS NOT NULL THEN
        UPDATE ordenes_trabajo
           SET faena_id = v_faena_taller, updated_at = NOW()
         WHERE id = p_ot_id AND faena_id IS DISTINCT FROM v_faena_taller;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'plan_ot_id', v_plan_ot_id,
        'secuencia', v_secuencia
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_taller_quitar_jornada(p_plan_ot_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_estado VARCHAR; v_rol TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    -- [MIG261] quien planifica también puede sacar del plan lo que no va.
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','planificador') THEN
        RAISE EXCEPTION 'Rol % no autorizado', v_rol;
    END IF;
    SELECT estado_plan INTO v_estado FROM taller_plan_semanal_ots WHERE id = p_plan_ot_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Jornada % no existe', p_plan_ot_id; END IF;
    IF v_estado IN ('en_ejecucion','finalizada') THEN
        RAISE EXCEPTION 'No se puede quitar jornada en estado %', v_estado;
    END IF;
    DELETE FROM taller_plan_semanal_ots WHERE id = p_plan_ot_id;
    RETURN jsonb_build_object('success', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_taller_agregar_jornada_ot(uuid,uuid,date,uuid,character varying,numeric,numeric,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_taller_agregar_jornada_ot(uuid,uuid,date,uuid,character varying,numeric,numeric,text) TO authenticated;
REVOKE ALL ON FUNCTION public.rpc_taller_quitar_jornada(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_taller_quitar_jornada(uuid) TO authenticated;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE v_sin_identidad INT; v_felipe TEXT; v_gate TEXT;
BEGIN
    SELECT count(*) INTO v_sin_identidad
      FROM auth.users u
      JOIN usuarios_perfil up ON up.id = u.id AND up.activo = true
     WHERE NOT EXISTS (SELECT 1 FROM auth.identities i
                        WHERE i.user_id = u.id AND i.provider='email');
    IF v_sin_identidad > 0 THEN
        RAISE EXCEPTION 'FALLO — quedan % cuentas activas sin identidad', v_sin_identidad;
    END IF;

    SELECT u.email INTO v_felipe FROM auth.users u
      JOIN usuarios_perfil up ON up.id=u.id
     WHERE up.nombre_completo ILIKE 'Felipe L%pez';
    IF v_felipe IS DISTINCT FROM 'felipe.lopez@sicom-iceo.cl' THEN
        RAISE EXCEPTION 'FALLO — el correo de Felipe quedó en %', v_felipe;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM auth.identities i
                    JOIN auth.users u ON u.id=i.user_id
                   WHERE u.email='felipe.lopez@sicom-iceo.cl'
                     AND i.identity_data->>'email' = 'felipe.lopez@sicom-iceo.cl') THEN
        RAISE EXCEPTION 'FALLO — la identidad de Felipe no quedó con su correo nuevo';
    END IF;

    SELECT substring(pg_get_functiondef(oid) from 'v_rol NOT IN \([^)]*\)') INTO v_gate
      FROM pg_proc WHERE proname='rpc_taller_agregar_jornada_ot';
    IF v_gate NOT LIKE '%planificador%' THEN
        RAISE EXCEPTION 'FALLO — el planificador sigue sin poder agregar al plan';
    END IF;

    RAISE NOTICE 'MIG261 OK — 0 cuentas sin identidad, Felipe en %, planificador habilitado para planificar',
        v_felipe;
END $$;

NOTIFY pgrst, 'reload schema';
