-- ============================================================================
-- MIG433 · Al subir un papel, la fecha también la pone una persona
-- ----------------------------------------------------------------------------
-- LO QUE PREGUNTÓ MANUEL
-- 27-08-2026: «¿ya está operativo el sistema para probar? Si actualizo el
-- sistema con un archivo, ¿este va a actualizar todo?».
--
-- Antes de responder que sí se probó el camino completo, y no estaba bien.
--
-- ── LO QUE FALTABA ─────────────────────────────────────────────────────────
-- MIG430 arregló que una fecha escrita por una persona no se borre: el trigger
-- del estándar la observa pero la respeta, y sólo descalifica lo que cargó el
-- propio sistema. Distingue una de otra por `fecha_origen`.
--
-- Pero `rpc_renovar_certificacion` —el RPC por el que pasa «Subir el papel
-- nuevo»— nunca escribió `fecha_origen`. Queda en NULL, o sea «esto lo cargó el
-- sistema», y el trigger vuelve a marcar la fila. Probado contra producción:
--
--   sube el papel con 12 meses  →  dudosa=true   la pantalla dice «sin_fecha»
--   sube el papel con 6 meses   →  dudosa=false  correcto
--
-- Es exactamente el mismo «falta la fecha» que Manuel reportó ayer, reapareciendo
-- por otra puerta. Arreglarlo en la vista y dejar abierta la puerta de al lado
-- no es arreglarlo.
--
-- ── LO QUE SE HACE ─────────────────────────────────────────────────────────
-- El RPC recibe de dónde salió la fecha y lo deja escrito:
--
--   'documento'  el lector la sacó del archivo al subirlo
--   'manual'     la escribió quien carga el papel
--
-- Por defecto 'manual', que es lo que corresponde: si alguien está subiendo un
-- papel y tecleando una fecha, esa fecha la afirmó una persona. El sistema
-- puede advertir que no calza con lo que dura el documento; no puede hacerla
-- desaparecer.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_renovar_certificacion(
    p_activo_id         uuid,
    p_tipo              tipo_certificacion_enum,
    p_fecha_emision     date,
    p_fecha_vencimiento date,
    p_archivo_url       text DEFAULT NULL,
    p_numero            text DEFAULT NULL,
    p_entidad           text DEFAULT NULL,
    p_bloqueante        boolean DEFAULT NULL,
    p_notas             text DEFAULT NULL,
    -- [MIG433] De dónde salió la fecha. Sin esto el trigger del estándar la
    -- toma por una fecha del sistema y la descalifica.
    p_origen            text DEFAULT 'manual')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_id   UUID;
    v_bloq BOOLEAN;
    v_origen TEXT;
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

    -- Sólo se aceptan los dos orígenes que significan «lo afirmó una persona».
    -- Cualquier otra cosa se trata como manual, que es lo que efectivamente
    -- está pasando: hay alguien subiendo el papel.
    v_origen := CASE WHEN p_origen = 'documento' THEN 'documento' ELSE 'manual' END;

    -- Por defecto, los documentos legales de circulación son bloqueantes; el
    -- que carga el papel puede marcar cualquier otro como bloqueante.
    v_bloq := COALESCE(p_bloqueante, p_tipo IN ('revision_tecnica','soap','permiso_circulacion'));

    INSERT INTO certificaciones (
        activo_id, tipo, numero_certificado, entidad_certificadora,
        fecha_emision, fecha_vencimiento, estado, archivo_url, bloqueante,
        fecha_origen, fecha_origen_nota, notas, created_by
    ) VALUES (
        p_activo_id, p_tipo, p_numero, p_entidad,
        p_fecha_emision, p_fecha_vencimiento,
        -- El cast es obligatorio: sin él el CASE es TEXT y el INSERT revienta.
        (CASE WHEN p_fecha_vencimiento <= CURRENT_DATE THEN 'vencido'
              WHEN p_fecha_vencimiento <= CURRENT_DATE + 30 THEN 'por_vencer'
              ELSE 'vigente' END)::estado_documento_enum,
        p_archivo_url, v_bloq,
        v_origen,
        CASE WHEN v_origen = 'documento'
             THEN 'MIG433 · fecha leída del archivo al subirlo.'
             ELSE 'MIG433 · fecha escrita por quien subió el papel.' END,
        COALESCE(NULLIF(btrim(p_notas), ''), 'Documento actualizado desde el sistema'),
        v_user
    ) RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'certificacion_id', v_id);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_renovar_certificacion(
    uuid, tipo_certificacion_enum, date, date, text, text, text, boolean, text, text) TO authenticated;

-- ── Probarlo acá mismo, no confiar en que quedó bien ──────────────────────
DO $r$
DECLARE v_activo UUID; v_r JSONB; v_id UUID; v_dud BOOL; v_obs TEXT; v_est TEXT;
BEGIN
    SELECT id INTO v_activo FROM activos WHERE COALESCE(patente,codigo)='SVBJ-57';
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub',(SELECT id FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1),
                        'role','authenticated')::text, true);

    v_r := rpc_renovar_certificacion(v_activo, 'hermeticidad'::tipo_certificacion_enum,
             CURRENT_DATE::date, (CURRENT_DATE + 365)::date, 'http://prueba433/x.pdf',
             NULL, NULL, TRUE, NULL, 'manual');
    v_id := (v_r->>'certificacion_id')::uuid;
    SELECT vigencia_dudosa, left(vigencia_observacion, 60) INTO v_dud, v_obs
      FROM certificaciones WHERE id = v_id;
    SELECT estado_real::text INTO v_est FROM v_certificacion_actual WHERE id = v_id;
    RAISE NOTICE 'Sube con 12 meses -> dudosa=% | la pantalla dice: % | advertencia: %',
        v_dud, v_est, COALESCE(v_obs,'—');

    DELETE FROM certificaciones WHERE archivo_url = 'http://prueba433/x.pdf';
END
$r$;

COMMIT;
