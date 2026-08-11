-- ============================================================================
-- SICOM-ICEO | 278 — La pantalla dice CUÁL de las dos firmas falta
-- ============================================================================
-- El informe lleva dos firmas (técnico ejecutor y ESM/ENEX) pero el panel solo
-- mostraba "Falta firma", sin decir cuál. Pasó al tiro: el técnico firmó su
-- link y la pantalla siguió diciendo "Falta firma" — correcto, faltaba ESM,
-- pero nadie podía saberlo mirando.
--
-- La vista ahora expone también la firma del técnico, para que el chip pueda
-- distinguir. `cumplida` no cambia: sigue siendo la firma del mandante, que es
-- la que vale para el KPI del contrato.
-- ADITIVA, IDEMPOTENTE.
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
    e.informe_pdf_url,
    -- [MIG278] La otra firma del informe: la del ejecutor de Pillado. Van al
    -- final porque CREATE OR REPLACE VIEW no admite columnas nuevas en medio.
    e.firma_tecnico_url IS NOT NULL AS firma_tecnico_lista,
    e.tecnico_nombre
   FROM enex_programaciones p
     JOIN enex_instalaciones i ON i.id = p.instalacion_id
     JOIN enex_faenas f ON f.id = i.faena_id
     LEFT JOIN enex_ejecuciones e ON e.programacion_id = p.id;

GRANT SELECT ON v_enex_panel_mensual TO authenticated;

SELECT 'MIG278 OK' AS resultado,
       (SELECT count(*) FROM v_enex_panel_mensual WHERE firma_tecnico_lista) AS con_firma_tecnico;
