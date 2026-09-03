-- ============================================================================
-- MIG500 · Mover al mecánico lo SACA de la OS anterior: no hay paralelo
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 03-09-2026, corrigiendo MIG499: «puedo planificar un mecánico para una OS,
-- salió una emergencia y lo muevo nuevamente; entonces en sistema lo debo
-- sacar de ahí y colocar en otra. NO puede estar en paralelo.»
--
-- MIG499 había cambiado asignar para que la OS anterior quedara «pausada» con
-- la asignación viva (varias OS por técnico). En terreno eso no calza con cómo
-- se mueve la gente: el jefe lo mueve, y el sistema debe reflejar DÓNDE está
-- cada uno — una sola OS asignada por persona.
--
-- QUÉ SE HACE
--   1. rpc_taller_os_asignar vuelve al cuerpo de MIG474: cierra la asignación
--      anterior (motivo escrito), cierra el reloj y deja la OS anterior
--      pausada si nadie más la tiene andando.
--   2. Se cierran las asignaciones abiertas duplicadas que hayan alcanzado a
--      crearse (se conserva la más reciente por técnico).
--   3. Vuelve el índice único: una asignación vigente por persona.
--
-- Lo demás de MIG499 queda: checks por NC, OS de externo, os_folio en la
-- bandeja, ítems del vale a la vista del bodeguero.
-- ============================================================================

BEGIN;

-- ── 1 · Asignar = mover: se le saca de donde estaba ─────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_os_asignar(
    p_os_id      UUID,
    p_tecnico_id UUID,
    p_motivo     TEXT DEFAULT NULL,
    p_arrancar   BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user  UUID := auth.uid();
    v_prev  RECORD;
    v_est   TEXT;
    v_aviso TEXT := NULL;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_taller_es_jefatura() THEN
        RAISE EXCEPTION 'Mover a alguien de un trabajo a otro es del jefe de taller. '
                        'El operador ejecuta lo que le asignaron.';
    END IF;

    SELECT estado INTO v_est FROM taller_os WHERE id = p_os_id;
    IF v_est IS NULL THEN RAISE EXCEPTION 'Esa OS no existe.'; END IF;
    IF v_est IN ('finalizada','anulada') THEN
        RAISE EXCEPTION 'Esa OS ya está %: no se le puede asignar a nadie.', v_est;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM taller_tecnicos WHERE id = p_tecnico_id AND COALESCE(activo, TRUE)) THEN
        RAISE EXCEPTION 'Ese técnico no existe o está inactivo.';
    END IF;

    -- ¿Ya estaba en esta misma OS? No se hace nada.
    IF EXISTS (SELECT 1 FROM taller_os_asignacion
                WHERE tecnico_id = p_tecnico_id AND os_id = p_os_id AND hasta IS NULL) THEN
        RETURN jsonb_build_object('success', TRUE, 'ya_estaba', TRUE);
    END IF;

    -- [MIG500] Sacarlo de donde estaba: se cierra la asignación Y el reloj.
    -- (MIG499 dejaba la anterior «pausada» en paralelo; en terreno el jefe lo
    -- MUEVE, y el sistema tiene que decir dónde está cada uno.)
    FOR v_prev IN
        SELECT a.id, a.os_id, o.folio
          FROM taller_os_asignacion a JOIN taller_os o ON o.id = a.os_id
         WHERE a.tecnico_id = p_tecnico_id AND a.hasta IS NULL
    LOOP
        UPDATE taller_os_asignacion
           SET hasta = NOW(),
               motivo_fin = 'Reasignado a otra Orden de Servicio'
         WHERE id = v_prev.id;

        UPDATE taller_os o SET estado = 'pausada', updated_at = NOW()
         WHERE o.id = v_prev.os_id AND o.estado = 'en_ejecucion'
           AND NOT EXISTS (SELECT 1 FROM taller_os_tiempo t
                            WHERE t.os_id = o.id AND t.fin IS NULL AND t.tecnico_id <> p_tecnico_id);

        v_aviso := COALESCE(v_aviso || ' ', '') || 'Se le sacó de ' || v_prev.folio || '.';
    END LOOP;

    UPDATE taller_os_tiempo
       SET fin = NOW(),
           segundos = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - inicio))::INT),
           cerrado_por_sistema = TRUE,
           motivo_cierre = 'El jefe lo movió a otro trabajo'
     WHERE tecnico_id = p_tecnico_id AND fin IS NULL;

    INSERT INTO taller_os_asignacion (os_id, tecnico_id, asignado_por, motivo)
    VALUES (p_os_id, p_tecnico_id, v_user, NULLIF(TRIM(COALESCE(p_motivo,'')),''));

    -- El responsable de la OS es siempre el que la tiene asignada ahora.
    UPDATE taller_os SET responsable_id = p_tecnico_id, updated_at = NOW() WHERE id = p_os_id;

    -- El jefe puede además dejarlo andando: «ándate a esto ahora».
    IF p_arrancar THEN
        INSERT INTO taller_os_tiempo (os_id, tecnico_id, registrado_por)
        VALUES (p_os_id, p_tecnico_id, v_user);
        UPDATE taller_os SET estado = 'en_ejecucion', updated_at = NOW() WHERE id = p_os_id;
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'aviso', v_aviso, 'arrancada', p_arrancar);
END;
$$;

-- ── 2 · Cerrar los paralelos que hayan alcanzado a existir ──────────────────
-- Se conserva la asignación abierta MÁS RECIENTE de cada técnico (es donde el
-- jefe lo puso al final); las demás se cierran con el motivo dicho.
WITH abiertas AS (
    SELECT a.id,
           row_number() OVER (PARTITION BY a.tecnico_id ORDER BY a.desde DESC) AS rn
      FROM taller_os_asignacion a
     WHERE a.hasta IS NULL
)
UPDATE taller_os_asignacion x
   SET hasta = NOW(),
       motivo_fin = 'Cerrada al volver a una sola OS por persona (MIG500)'
  FROM abiertas
 WHERE x.id = abiertas.id AND abiertas.rn > 1;

-- ── 3 · Vuelve la regla como índice, no como buena intención ────────────────
CREATE UNIQUE INDEX IF NOT EXISTS uq_os_asig_vigente_por_persona
    ON taller_os_asignacion (tecnico_id) WHERE hasta IS NULL;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM (
        SELECT tecnico_id FROM taller_os_asignacion WHERE hasta IS NULL
         GROUP BY tecnico_id HAVING count(*) > 1) d;
    IF v_n > 0 THEN RAISE EXCEPTION 'FALLO: % técnicos siguen con asignación doble', v_n; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='uq_os_asig_vigente_por_persona') THEN
        RAISE EXCEPTION 'FALLO: el índice único no quedó creado';
    END IF;

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_taller_os_asignar';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: rpc_taller_os_asignar quedó con % firmas', v_n; END IF;

    RAISE NOTICE 'una OS asignada por persona; mover = sacar de la anterior con motivo escrito';
END
$mig$;

COMMIT;
