-- ============================================================================
-- SICOM-ICEO | 231b — ENEX: informe_pdf_url visible en el panel mensual
-- ============================================================================

CREATE OR REPLACE VIEW v_enex_panel_mensual AS
 SELECT p.id AS programacion_id,
    p.periodo_anio,
    p.periodo_mes,
    p.tipo_servicio,
    p.fecha_programada,
    p.observacion AS prog_observacion,
    i.id AS instalacion_id,
    i.nombre AS instalacion,
    i.tipo AS instalacion_tipo,
    i.codigo AS instalacion_codigo,
    i.linea,
    i.patente,
    f.id AS faena_id,
    f.codigo AS faena_codigo,
    f.nombre AS faena,
    e.id AS ejecucion_id,
    e.estado,
    e.fecha_ejecucion,
    e.ot_numero,
    e.ejecutor,
    e.observacion AS ejec_observacion,
    e.evidencia_urls,
    e.firma_mandante_url,
    e.firmante_mandante_nombre,
    e.firmante_mandante_at,
    e.firma_mandante_url IS NOT NULL AS cumplida,
    e.informe_pdf_url
   FROM enex_programaciones p
     JOIN enex_instalaciones i ON i.id = p.instalacion_id
     JOIN enex_faenas f ON f.id = i.faena_id
     LEFT JOIN enex_ejecuciones e ON e.programacion_id = p.id;

DO $$ BEGIN RAISE NOTICE 'MIG231b OK: informe_pdf_url en v_enex_panel_mensual'; END $$;
