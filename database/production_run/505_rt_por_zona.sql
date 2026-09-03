-- ============================================================================
-- MIG505 · El aviso de revisión técnica se ordena POR ZONA
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 03-09-2026: «el de revisión técnica debe ser de los equipos, pero por zona».
--
-- La zona es la FAENA donde el equipo está físicamente (activos.faena_id →
-- faenas.nombre; si no hay faena, la ubicación de texto; si no, «Sin zona»).
-- Así el correo del lunes se lee como se coordina la RT: por lugar — los de
-- Spence juntos, los del taller Coquimbo juntos — y no como una lista plana.
--
-- La firma de la función cambia de columnas → hay que DROPear antes de crear
-- (CREATE OR REPLACE no puede cambiar el tipo de retorno).
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS fn_rt_por_vencer_cron(TEXT);

CREATE FUNCTION fn_rt_por_vencer_cron(p_secreto TEXT)
RETURNS TABLE (
    activo_id         UUID,
    patente           TEXT,
    codigo            TEXT,
    nombre            TEXT,
    cliente           TEXT,
    zona              TEXT,
    fecha_vencimiento DATE,
    dias_restantes    INT,
    estado            TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido';
    END IF;
    RETURN QUERY
    SELECT a.id,
           a.patente::TEXT, a.codigo::TEXT, a.nombre::TEXT,
           a.cliente_actual::TEXT,
           COALESCE(f.nombre::TEXT, NULLIF(a.ubicacion_actual::TEXT, ''), 'Sin zona') AS zona,
           c.fecha_vencimiento,
           c.dias_restantes::INT,
           c.estado_real::TEXT
      FROM v_certificacion_actual c
      JOIN activos a ON a.id = c.activo_id AND a.fecha_baja IS NULL
      LEFT JOIN faenas f ON f.id = a.faena_id
     WHERE c.tipo::TEXT = 'revision_tecnica'
       AND c.estado_real IN ('vencido', 'por_vencer')
     ORDER BY 6, (c.estado_real = 'vencido') DESC, c.dias_restantes NULLS FIRST, a.patente;
END;
$$;

REVOKE ALL ON FUNCTION fn_rt_por_vencer_cron(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_rt_por_vencer_cron(TEXT) TO anon, authenticated;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_n INT; v_zonas INT; v_sec TEXT; v_cmd TEXT;
BEGIN
    -- La función responde con el secreto vigente del cron (prueba real).
    SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'revision-tecnica-por-vencer';
    v_sec := substring(v_cmd FROM 'x-cron-secret'', ''([^'']+)');
    IF v_sec IS NULL THEN RAISE EXCEPTION 'FALLO: no está el cron de RT'; END IF;

    SELECT count(*), count(DISTINCT zona) INTO v_n, v_zonas
      FROM fn_rt_por_vencer_cron(v_sec);
    RAISE NOTICE 'RT por zona OK · % equipos en % zonas', v_n, v_zonas;
END
$mig$;

COMMIT;
