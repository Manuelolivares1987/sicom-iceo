-- 672 — Por qué se para el trabajo en el taller (Manuel 08-11-2026, benchmark MaintainX).
-- destructivo-ok: el DROP FUNCTION reemplaza rpc_taller_os_pausar de 3 argumentos por la de 4
-- (el 4º con DEFAULT): dejar las dos haría ambigua la llamada con 3 argumentos nombrados.
--
-- Hasta hoy, de 53 pausas del reloj de OT 46 no tenían motivo y 7 decían «otro»; la pausa
-- de la Orden de Servicio ni siquiera guardaba un tipo. Sin eso no se puede medir cuántas
-- horas se pierden esperando un repuesto o un equipo. El mecánico ahora elige con un toque
-- (fin de jornada, colación, espera repuesto, equipo no disponible, otro + frase).
-- Los códigos son los mismos que ya valida rpc_taller_pausar_ejecucion.

ALTER TABLE taller_os_tiempo ADD COLUMN IF NOT EXISTS motivo_tipo TEXT
    CHECK (motivo_tipo IN ('fin_jornada','colacion','espera_repuesto','equipo_no_disponible','otro'));

COMMENT ON COLUMN taller_os_tiempo.motivo_tipo IS
    '[MIG672] Por qué se cerró este tramo del reloj (pausa del mecánico). NULL = cierre del sistema o cliente antiguo.';

DROP FUNCTION IF EXISTS public.rpc_taller_os_pausar(uuid, uuid, text);

CREATE OR REPLACE FUNCTION public.rpc_taller_os_pausar(
    p_os_id uuid, p_tecnico_id uuid, p_motivo text DEFAULT NULL::text, p_motivo_tipo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_mio  UUID := fn_taller_mi_tecnico_id();
    v_n    INT;
    v_tipo TEXT := NULLIF(TRIM(COALESCE(p_motivo_tipo, '')), '');
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    IF NOT fn_taller_es_jefatura() AND p_tecnico_id IS DISTINCT FROM v_mio THEN
        RAISE EXCEPTION 'Sólo puedes parar tu propio reloj. El de otro lo para el jefe de taller.';
    END IF;

    IF v_tipo IS NOT NULL AND v_tipo NOT IN
       ('fin_jornada','colacion','espera_repuesto','equipo_no_disponible','otro') THEN
        RAISE EXCEPTION 'Motivo de pausa desconocido: %', v_tipo;
    END IF;
    -- «Otro» sin frase no dice nada: se exige el texto. (NULL se sigue aceptando para no
    -- romper teléfonos con la versión anterior en caché.)
    IF v_tipo = 'otro' AND length(TRIM(COALESCE(p_motivo, ''))) < 3 THEN
        RAISE EXCEPTION 'Escribe por qué se pausa: «otro» sin explicación no sirve.';
    END IF;

    UPDATE taller_os_tiempo
       SET fin = NOW(),
           segundos = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - inicio))::INT),
           motivo_cierre = NULLIF(TRIM(COALESCE(p_motivo,'')),''),
           motivo_tipo = v_tipo
     WHERE os_id = p_os_id AND tecnico_id = p_tecnico_id AND fin IS NULL;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    UPDATE taller_os SET estado = 'pausada', updated_at = NOW()
     WHERE id = p_os_id AND estado = 'en_ejecucion'
       AND NOT EXISTS (SELECT 1 FROM taller_os_tiempo WHERE os_id = p_os_id AND fin IS NULL);

    RETURN jsonb_build_object('success', TRUE, 'tramos_cerrados', v_n, 'motivo_tipo', v_tipo);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_taller_os_pausar(uuid, uuid, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
