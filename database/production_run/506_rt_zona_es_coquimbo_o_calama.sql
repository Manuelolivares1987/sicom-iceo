-- ============================================================================
-- MIG506 · La zona del aviso de RT es la OPERACIÓN: Coquimbo o Calama
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 03-09-2026, corrigiendo MIG505: «cuando digo por zona, es que necesito los
-- vehículos de Coquimbo y los vehículos de Calama».
--
-- MIG505 agrupó por faena (7 secciones chicas). La zona que Manuel administra
-- son los DOS cuadrantes — los mismos del Panel de Gerencia: activos.operacion
-- ('Coquimbo' / 'Calama'). La faena no se pierde: baja a ser el detalle de
-- cada fila («dónde está exactamente»), que es lo que sirve para coordinar el
-- viaje a la planta dentro de la zona.
--
-- Cambia el tipo de retorno → DROP + CREATE.
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
    faena             TEXT,
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
           -- La zona que se administra: el cuadrante del Panel de Gerencia.
           COALESCE(NULLIF(TRIM(a.operacion::TEXT), ''), 'Sin zona') AS zona,
           COALESCE(f.nombre::TEXT, NULLIF(a.ubicacion_actual::TEXT, '')) AS faena,
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
DECLARE v_sec TEXT; v_cmd TEXT; r RECORD;
BEGIN
    SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'revision-tecnica-por-vencer';
    v_sec := substring(v_cmd FROM 'x-cron-secret'', ''([^'']+)');
    IF v_sec IS NULL THEN RAISE EXCEPTION 'FALLO: no está el cron de RT'; END IF;

    FOR r IN SELECT zona, count(*) AS n FROM fn_rt_por_vencer_cron(v_sec) GROUP BY zona ORDER BY zona LOOP
        RAISE NOTICE 'zona % → % equipos', r.zona, r.n;
    END LOOP;
END
$mig$;

COMMIT;
