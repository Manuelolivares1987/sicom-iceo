-- ============================================================================
-- MIG528 · El historial del QR público cuenta la historia completa
-- ============================================================================
--
-- LO QUE PREGUNTÓ MANUEL (04-09-2026)
-- «El DJKL-18 está en el portal de Romeral que puede ver el historial de
-- mantenimiento — ¿esto también se ve ahí?»
--
-- Se veía A MEDIAS. rpc_historial_mantenimiento_publico (MIG284) quedó
-- escrito antes de dos cosas:
--   1. El congelado del trabajo (MIG310/527): mostraba como detalle las
--      OBSERVACIONES de la OT («Trabajaron, Juan Valenzuela…») en vez del
--      resumen real de lo ejecutado, y sin medidores al cierre.
--   2. El historial pre-SICOM (MIG310-312): las OS legacy (CQBO) no estaban
--      en el QR — y en equipos como el DJKL-18 son la mayor parte del 2026.
--      El cliente veía un historial con hoyos que el escritorio no tiene.
--
-- QUÉ SE HACE — misma disciplina del gotcha «el QR calcula estados aparte»:
--   · El detalle de la OT es el trabajo congelado (fallback: observaciones).
--   · Los medidores al cierre (MIG527) se muestran.
--   · Las OS legacy entran al QR, con su detalle y medidores. Sin costos,
--     como todo lo público (MIG284).
-- ============================================================================

BEGIN;

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
                ELSE initcap(replace(ot.tipo::text, '_', ' '))
           END AS tipo,
           CASE ot.tipo::text
                WHEN 'preventivo' THEN 'Mantención programada'
                ELSE 'Trabajo en taller'
           END AS titulo,
           -- [MIG528] Lo que el cliente lee es LO QUE SE HIZO (congelado al
           -- cerrar, MIG527); las observaciones quedan de respaldo.
           COALESCE(NULLIF(TRIM(ot.trabajo_realizado), ''),
                    NULLIF(TRIM(ot.observaciones), '')) AS detalle,
           ot.folio::text AS folio,
           ot.km_al_cierre, ot.horas_al_cierre,
           (ot.estado::text = 'ejecutada_con_observaciones') AS con_observacion
      FROM ordenes_trabajo ot
      JOIN permitido p ON p.id = ot.activo_id
     WHERE ot.estado::text IN ('cerrada', 'ejecutada_ok', 'ejecutada_con_observaciones')

    UNION ALL

    -- ── Historial pre-SICOM (OS legacy) ─────────────────────────────────────
    SELECT h.fecha_recepcion,
           CASE WHEN h.flag_mant_prev THEN 'Mantención preventiva'
                WHEN h.flag_correctivo THEN 'Reparación'
                ELSE 'Servicio' END,
           'Orden de servicio',
           COALESCE(NULLIF(TRIM(h.detalle_trabajos), ''), NULLIF(TRIM(h.observacion), '')),
           ('OS ' || COALESCE(h.os_cqbo, h.os_numero, left(h.id::text, 8)))::text,
           h.kilometraje::numeric,
           h.horometro::numeric,
           false
      FROM historial_os_legacy h
      JOIN permitido p ON p.id = h.activo_id
     WHERE h.fecha_recepcion <= CURRENT_DATE

    UNION ALL

    -- ── Informes de intervención emitidos ───────────────────────────────────
    SELECT COALESCE(ii.fecha_termino::date, ii.cerrado_at::date, ii.fecha_ingreso::date),
           'Informe de intervención',
           COALESCE(initcap(replace(NULLIF(TRIM(ii.tipo_intervencion::text), ''), '_', ' ')), 'Intervención en taller'),
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

-- ── Verificación con el DJKL-18 (solo lectura) ──────────────────────────────
DO $mig$
DECLARE v_activo UUID; v_n INT; v_legacy INT; r RECORD;
BEGIN
    SELECT id INTO v_activo FROM activos WHERE COALESCE(patente, codigo) = 'DJKL-18';

    SELECT count(*) INTO v_n FROM rpc_historial_mantenimiento_publico(v_activo);
    SELECT count(*) INTO v_legacy FROM rpc_historial_mantenimiento_publico(v_activo) h
     WHERE h.folio LIKE 'OS %';
    RAISE NOTICE 'DJKL-18 por el QR: % filas (% OS pre-SICOM)', v_n, v_legacy;
    IF v_legacy = 0 THEN RAISE EXCEPTION 'FALLO: las OS legacy siguen fuera del QR'; END IF;

    SELECT h.detalle, h.horometro INTO r
      FROM rpc_historial_mantenimiento_publico(v_activo) h
     WHERE h.folio = 'OT-202608-00009';
    RAISE NOTICE 'OT-202608-00009 en el QR: horometro=% · detalle=%', r.horometro, left(coalesce(r.detalle,''), 80);
    IF r.detalle IS NULL OR r.detalle NOT LIKE 'Ejecutado:%' THEN
        RAISE EXCEPTION 'FALLO: la OT sigue mostrando observaciones y no el trabajo (%)', left(coalesce(r.detalle,''), 60);
    END IF;
    RAISE NOTICE 'MIG528 OK · el QR cuenta la historia completa: OT congeladas + OS pre-SICOM + informes';
END
$mig$;

COMMIT;
