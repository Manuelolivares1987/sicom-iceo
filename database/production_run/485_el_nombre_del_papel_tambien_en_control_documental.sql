-- ============================================================================
-- MIG485 · El nombre del papel también en Control documental
-- ============================================================================
--
-- MIG484 le puso nombre a los «otros» y arregló la ficha del equipo y el QR.
-- Falta la tercera pantalla, que es donde Manuel dijo que también lo quería:
-- /dashboard/flota/control-documental.
--
-- `v_control_documental` se arma sobre `v_certificacion_actual`, así que ya
-- hereda la separación por papel —los dos «otros» del SVBJ-57 ya no se tapan—.
-- Lo que le falta es el nombre para mostrarlo: sin esto la lista sigue diciendo
-- «Otro» dos veces, que es exactamente lo que había que terminar.
--
-- Las columnas nuevas van AL FINAL: CREATE OR REPLACE VIEW no las admite en
-- medio de la lista.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW v_control_documental AS
 SELECT a.id AS activo_id,
    COALESCE(a.patente, a.codigo) AS patente,
    a.codigo AS activo_codigo,
    a.nombre AS activo_nombre,
    a.tipo::text AS activo_tipo,
    a.estado::text AS activo_estado,
    v.id AS certificacion_id,
    v.tipo::text AS tipo,
    v.numero_certificado,
    v.entidad_certificadora,
    v.fecha_emision,
    v.fecha_vencimiento,
    v.estado_real::text AS estado,
    v.dias_restantes,
    v.archivo_url,
    v.bloqueante,
    c.fecha_origen,
    p.id AS propuesta_id,
    p.vencimiento_propuesto,
    p.emision_propuesta,
    p.confianza AS propuesta_confianza,
    p.regla AS propuesta_regla,
    p.evidencia AS propuesta_evidencia,
    p.vencimiento_propuesto IS NOT NULL AND p.vencimiento_propuesto < CURRENT_DATE AS propuesta_vencida,
    fn_certificado_tipo_permanente(v.tipo::text) AS tipo_no_caduca,
    c.vigencia_observacion,
    c.vigencia_dudosa_nota,
    c.tipo_otro,
    fn_certificado_etiqueta(v.tipo::text, c.tipo_otro) AS etiqueta
   FROM v_certificacion_actual v
     JOIN activos a ON a.id = v.activo_id
     JOIN certificaciones c ON c.id = v.id
     LEFT JOIN certificacion_propuestas p ON p.certificacion_id = v.id AND p.estado = 'pendiente'::text
  WHERE a.estado <> 'dado_baja'::estado_activo_enum;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE r RECORD; v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM v_control_documental
     WHERE activo_id = '9ca9b860-d1ac-4fb0-97e8-af68d7f24f4a' AND tipo = 'otra';
    RAISE NOTICE 'papeles «otros» del SVBJ-57 en Control documental: %', v_n;
    FOR r IN SELECT patente, etiqueta, estado FROM v_control_documental
              WHERE tipo = 'otra' ORDER BY patente
    LOOP
        RAISE NOTICE '  % · % · %', r.patente, r.etiqueta, r.estado;
    END LOOP;
END $mig$;

COMMIT;
