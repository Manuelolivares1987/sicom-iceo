-- ============================================================================
-- SICOM-ICEO | 284 — El cliente puede ver qué se le ha hecho al equipo
-- ============================================================================
-- Pedido de Manuel: que quien escanea el QR —el cliente— vea el historial de
-- mantenimiento del equipo, no solo sus papeles.
--
-- Va SIN plata. El cliente ve qué se hizo, cuándo y con qué kilometraje; los
-- costos, las horas hombre y los márgenes son información interna y no salen
-- de aquí. Tampoco salen las OT abiertas: un trabajo en curso todavía puede
-- cambiar, y mostrarlo a medio hacer solo genera preguntas.
--
-- Dos fuentes, en una sola línea de tiempo:
--   · las OT terminadas del equipo
--   · los informes de intervención emitidos (con su folio, que el cliente
--     puede citar)
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_historial_mantenimiento_publico(p_activo_id UUID)
RETURNS TABLE (
    fecha           DATE,
    tipo            TEXT,
    titulo          TEXT,
    detalle         TEXT,
    folio           TEXT,
    kilometraje     NUMERIC,
    horometro       NUMERIC,
    con_observacion BOOLEAN
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    WITH permitido AS (
        SELECT id FROM activos
         WHERE id = p_activo_id
           AND COALESCE(qr_publico_habilitado, true)
           AND fecha_baja IS NULL
    )
    -- ── Trabajos terminados ─────────────────────────────────────────────────
    SELECT COALESCE(ot.fecha_termino::date, ot.fecha_programada::date) AS fecha,
           CASE ot.tipo::text
                WHEN 'preventivo' THEN 'Mantención preventiva'
                WHEN 'correctivo' THEN 'Reparación'
                WHEN 'predictivo' THEN 'Inspección predictiva'
                WHEN 'inspeccion_recepcion' THEN 'Inspección de recepción'
                -- Cualquier tipo nuevo se muestra legible, no en jerga de base
                -- de datos: esto lo lee el cliente, no un técnico.
                ELSE initcap(replace(ot.tipo::text, '_', ' '))
           END AS tipo,
           CASE ot.tipo::text
                WHEN 'preventivo' THEN 'Mantención programada'
                ELSE 'Trabajo en taller'
           END AS titulo,
           NULLIF(TRIM(ot.observaciones), '') AS detalle,
           ot.folio::text AS folio,
           NULL::NUMERIC, NULL::NUMERIC,
           (ot.estado::text = 'ejecutada_con_observaciones') AS con_observacion
      FROM ordenes_trabajo ot
      JOIN permitido p ON p.id = ot.activo_id
     WHERE ot.estado::text IN ('cerrada', 'ejecutada_ok', 'ejecutada_con_observaciones')

    UNION ALL

    -- ── Informes de intervención emitidos ───────────────────────────────────
    SELECT COALESCE(ii.fecha_termino::date, ii.cerrado_at::date, ii.fecha_ingreso::date),
           'Informe de intervención',
           COALESCE(initcap(replace(NULLIF(TRIM(ii.tipo_intervencion::text), ''), '_', ' ')), 'Intervención en taller'),
           -- Lo que se hizo y lo que quedó pendiente: es lo que al cliente le
           -- sirve saber, junto con las restricciones para volver a operar.
           NULLIF(TRIM(CONCAT_WS(E'\n',
               NULLIF(TRIM(ii.trabajo_realizado_resumen), ''),
               NULLIF('Pendiente: ' || NULLIF(TRIM(ii.trabajos_pendientes_resumen), ''), 'Pendiente: '),
               NULLIF('Recomendación: ' || NULLIF(TRIM(ii.recomendaciones), ''), 'Recomendación: '))), ''),
           ii.folio::text,
           COALESCE(ii.kilometraje_salida, ii.kilometraje_ingreso),
           COALESCE(ii.horometro_salida, ii.horometro_ingreso),
           COALESCE(NULLIF(TRIM(ii.trabajos_pendientes_resumen), '') IS NOT NULL, false)
      FROM informes_intervencion ii
      JOIN permitido p ON p.id = ii.activo_id
     WHERE ii.estado::text IN ('emitido', 'cerrado', 'aprobado')
       AND COALESCE(ii.es_version_vigente, true)
       AND ii.anulado_at IS NULL

     ORDER BY 1 DESC NULLS LAST
     LIMIT 60;
$$;

COMMENT ON FUNCTION rpc_historial_mantenimiento_publico(UUID) IS
    'Historial de mantenimiento para el QR público. SIN costos ni horas hombre: '
    'el cliente ve qué se hizo y cuándo, no lo que valió. MIG284.';

GRANT EXECUTE ON FUNCTION rpc_historial_mantenimiento_publico(UUID) TO anon, authenticated;

SELECT 'MIG284 OK' AS resultado,
       (SELECT count(*) FROM rpc_historial_mantenimiento_publico(
           (SELECT id FROM activos WHERE patente = 'RSCY-86' LIMIT 1))) AS ejemplo_rscy86;
