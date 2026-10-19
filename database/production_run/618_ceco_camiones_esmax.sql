-- 618 — Centro de costo de los 6 Renault C440 de ESMAX, tal como están en Softland.
-- Sin ceco_id el cruce Softland→equipo cae al de la patente en la descripción, y
-- Softland tiene «WB BF 22» (es WBFZ-22): su gasto quedaba sin camión.
-- OJO: la numeración de Softland NO calza con activos.codigo para los WCWR
-- (Softland CC-20-07 = WCWR-35, SICOM CC-20-07 = WCWR-25). Manda Softland para
-- el centro de costo; el código del equipo no se toca aquí.
INSERT INTO centros_costo (codigo, nombre, area, activo)
SELECT v.codigo, v.patente || ' · Aljibe Comb.', 'Flota', true
  FROM (VALUES ('CC-20-04', 'WBFZ-22'), ('CC-20-05', 'WBGD-20'), ('CC-20-06', 'WBGD-30'),
               ('CC-20-07', 'WCWR-35'), ('CC-20-08', 'WCWR-25'), ('CC-20-09', 'WCWR-33')) v(codigo, patente)
 WHERE NOT EXISTS (SELECT 1 FROM centros_costo c WHERE upper(c.codigo) = v.codigo);

UPDATE activos a
   SET ceco_id = c.id
  FROM centros_costo c
 WHERE c.codigo IN ('CC-20-04','CC-20-05','CC-20-06','CC-20-07','CC-20-08','CC-20-09')
   AND split_part(c.nombre, ' · ', 1) = a.patente
   AND a.ceco_id IS DISTINCT FROM c.id;

UPDATE softland_cc
   SET activo_id = fn_softland_cc_activo(codigo, descripcion)
 WHERE codigo LIKE 'CC-20-0%';

REFRESH MATERIALIZED VIEW mv_softland_costo_mes;

SELECT json_agg(sc.codigo || ' → ' || coalesce(a.patente, 'SIN EQUIPO') ORDER BY sc.codigo) AS mapeo
  FROM softland_cc sc LEFT JOIN activos a ON a.id = sc.activo_id
 WHERE sc.codigo LIKE 'CC-20-0%';
