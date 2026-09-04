-- ============================================================================
-- MIG512 · v_control_documental publica la descripción del papel (MIG511)
-- ============================================================================
-- Columna nueva AL FINAL (CREATE OR REPLACE no deja reordenar).
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
    fn_certificado_etiqueta(v.tipo::text, c.tipo_otro) AS etiqueta,
    -- [MIG512] La descripción libre del papel (MIG511): se ve bajo el nombre.
    c.notas AS descripcion
   FROM v_certificacion_actual v
     JOIN activos a ON a.id = v.activo_id
     JOIN certificaciones c ON c.id = v.id
     LEFT JOIN certificacion_propuestas p ON p.certificacion_id = v.id AND p.estado = 'pendiente'::text
  WHERE a.estado <> 'dado_baja'::estado_activo_enum;

DO $mig$
BEGIN
    PERFORM descripcion FROM v_control_documental LIMIT 1;
    RAISE NOTICE 'MIG512 OK · v_control_documental publica descripcion';
END $mig$;

COMMIT;
