-- ============================================================================
-- MIG515 · v_activo_certificados aprende las columnas de vigencia por horas
-- ============================================================================
-- Complemento de MIG514: la vista del certificado impreso se creó con `c.*`
-- (MIG219) y ese asterisco se expandió AL CREARLA — las columnas nuevas
-- (horometro_emision, vigencia_horas) no existían y no están en la vista.
-- Se recrea igual, para que la página /certificado/[id] pueda imprimir
-- «válido por N horas desde el horómetro X».
-- ============================================================================

BEGIN;

DROP VIEW IF EXISTS v_activo_certificados;
CREATE VIEW v_activo_certificados AS
SELECT c.*,
       t.titulo, t.cuerpo, t.seccion, t.campos,
       a.codigo   AS activo_codigo,
       a.nombre   AS activo_nombre,
       a.patente  AS activo_patente,
       mo.nombre  AS modelo_nombre,
       ma.nombre  AS marca_nombre,
       ot.folio   AS ot_folio
FROM activo_certificados c
JOIN certificado_tipos t ON t.codigo = c.tipo_codigo
JOIN activos a           ON a.id = c.activo_id
LEFT JOIN modelos mo     ON mo.id = a.modelo_id
LEFT JOIN marcas  ma     ON ma.id = mo.marca_id
LEFT JOIN ordenes_trabajo ot ON ot.id = c.ot_id;
GRANT SELECT ON v_activo_certificados TO authenticated;

DO $mig$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_name = 'v_activo_certificados' AND column_name = 'vigencia_horas'
    ) THEN
        RAISE EXCEPTION 'FALLO: la vista sigue sin vigencia_horas';
    END IF;
    RAISE NOTICE 'MIG515 OK · la vista del certificado trae la vigencia por horas';
END
$mig$;

COMMIT;
