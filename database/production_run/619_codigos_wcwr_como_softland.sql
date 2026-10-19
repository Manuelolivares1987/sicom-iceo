-- 619 — El código del equipo es el mismo centro de costo de Softland (Manuel
-- 2026-10-19: «la idea es que los códigos sean los mismos»). El alta de los C440
-- (PR #399) numeró los WCWR por orden de patente; Softland los tiene al revés:
--   WCWR-35 → CC-20-07 · WCWR-25 → CC-20-08 · WCWR-33 → CC-20-09
-- El resto de la flota ya calza (los otros códigos de Softland son CC antiguos).
-- activos.codigo es UNIQUE: pasa por un código temporal.
UPDATE activos SET codigo = 'TMP-' || codigo WHERE patente IN ('WCWR-25', 'WCWR-33', 'WCWR-35');

UPDATE activos a
   SET codigo = v.codigo, centro_costo = v.codigo
  FROM (VALUES ('WCWR-35', 'CC-20-07'), ('WCWR-25', 'CC-20-08'), ('WCWR-33', 'CC-20-09')) v(patente, codigo)
 WHERE a.patente = v.patente;

SELECT json_agg(a.patente || ': ' || a.codigo || ' · ceco ' || cc.codigo || ' · softland ' ||
                (SELECT string_agg(sc.codigo, ',') FROM softland_cc sc WHERE sc.activo_id = a.id) ORDER BY a.codigo) AS resultado
  FROM activos a LEFT JOIN centros_costo cc ON cc.id = a.ceco_id
 WHERE a.patente IN ('WCWR-25', 'WCWR-33', 'WCWR-35');
