-- ============================================================================
-- 613_alerta_portal_documentos_exigidos.sql
-- ----------------------------------------------------------------------------
-- Manuel 2026-10-19: «el objetivo de tener esto en el portal es que lance
-- alertas tempranas ante los vencimientos» → Juan Pablo Gómez y Manuel.
--
-- Los VENCIMIENTOS ya los avisa el correo diario de papeles de flota (MIG575,
-- DOCS_FLOTA_EMAIL_TO incluye a los dos) y los 6 camiones de ESMAX ya entran.
-- Lo que no avisaba nadie es lo que el contrato EXIGE y no está cargado
-- (documentos_exigidos, MIG612): un camión sin RT no tiene fecha que vencer,
-- así que nunca aparecía. Esto lo suma como sección propia del mismo correo.
--
-- Un pendiente es [NUEVO] el primer día que aparece (dispara el correo); después
-- va en el recordatorio de los lunes hasta que el papel se cargue.
-- Sin service_role: mismo secreto 'cron_alertas' que fn_docs_flota_cron.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

CREATE TABLE IF NOT EXISTS portal_flota_pendientes_avisados (
    cuenta_id  UUID        NOT NULL REFERENCES portal_flota_cuentas(id) ON DELETE CASCADE,
    activo_id  UUID        NOT NULL REFERENCES activos(id) ON DELETE CASCADE,
    tipo       TEXT        NOT NULL,
    avisado_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (cuenta_id, activo_id, tipo)
);
ALTER TABLE portal_flota_pendientes_avisados ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON portal_flota_pendientes_avisados FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION fn_portal_flota_pendientes_cron(p_secreto TEXT)
RETURNS TABLE(cuenta_id UUID, empresa TEXT, activo_id UUID, patente TEXT, codigo TEXT,
              zona TEXT, faena TEXT, tipo TEXT, nuevo BOOLEAN)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido';
    END IF;
    RETURN QUERY
    SELECT c.id, COALESCE(c.empresa, c.nombre), a.id, a.patente::TEXT, a.codigo::TEXT,
           COALESCE(NULLIF(TRIM(a.operacion::TEXT), ''), 'Sin zona'),
           COALESCE(f.nombre::TEXT, a.ubicacion_actual::TEXT),
           t, (av.tipo IS NULL)
      FROM portal_flota_cuentas c
      JOIN LATERAL fn_portal_flota_activos(c) act(id) ON true
      JOIN activos a ON a.id = act.id
      LEFT JOIN faenas f ON f.id = a.faena_id
      CROSS JOIN LATERAL unnest(c.documentos_exigidos) t
      LEFT JOIN portal_flota_pendientes_avisados av
             ON av.cuenta_id = c.id AND av.activo_id = a.id AND av.tipo = t
     WHERE c.activo
       AND NOT EXISTS (SELECT 1 FROM rpc_documentos_activo_publico(a.id) x WHERE x.tipo = t)
     ORDER BY 2, a.patente, array_position(c.documentos_exigidos, t);
END;
$$;

-- Se marca DESPUÉS de que el correo salió. Lo que ya se cargó se borra: si
-- vuelve a faltar (papel anulado), vuelve a avisarse como nuevo.
CREATE OR REPLACE FUNCTION fn_portal_flota_pendientes_marcar_cron(p_secreto TEXT, p_items JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido';
    END IF;
    DELETE FROM portal_flota_pendientes_avisados av
     WHERE NOT EXISTS (
         SELECT 1 FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) i
          WHERE (i->>'cuenta_id')::uuid = av.cuenta_id
            AND (i->>'activo_id')::uuid = av.activo_id
            AND i->>'tipo' = av.tipo);
    INSERT INTO portal_flota_pendientes_avisados (cuenta_id, activo_id, tipo)
    SELECT (i->>'cuenta_id')::uuid, (i->>'activo_id')::uuid, i->>'tipo'
      FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) i
    ON CONFLICT DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION fn_portal_flota_pendientes_cron(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_portal_flota_pendientes_marcar_cron(TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_portal_flota_pendientes_cron(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_portal_flota_pendientes_marcar_cron(TEXT, JSONB) TO anon, authenticated;

-- Verificación sin secreto: cuántos pendientes hay hoy.
SELECT count(*) AS pendientes_hoy
  FROM portal_flota_cuentas c
  JOIN LATERAL fn_portal_flota_activos(c) act(id) ON true
  CROSS JOIN LATERAL unnest(c.documentos_exigidos) t
 WHERE c.activo
   AND NOT EXISTS (SELECT 1 FROM rpc_documentos_activo_publico(act.id) x WHERE x.tipo = t);
