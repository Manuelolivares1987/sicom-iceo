-- 623 — La camioneta de gerencia sale de los análisis de costos (Manuel 2026-10-19).
-- OC-GE-02 «Camioneta Gerencia TC RB 71» estaba como 'equipo' y quedaba 2.ª del
-- top con $7,3 M, todo gasolina 95 valorizada en Softland a $5.600–16.900/L
-- (jun–ago 2026; antes ~$1.050/L). Pasa a 'administracion', igual que OC-GE-03
-- «Camioneta Gerencia 02»: el panel y el informe la excluyen por defecto y
-- reaparece con «Incluir administración y comercial». area_manual = true para que
-- la sincronización de Softland no la reclasifique.
UPDATE softland_cc
   SET area = 'administracion', area_manual = true, updated_at = NOW()
 WHERE codigo = 'OC-GE-02';

REFRESH MATERIALIZED VIEW mv_softland_costo_mes;

SELECT codigo, descripcion, area, area_manual FROM softland_cc WHERE codigo LIKE 'OC-GE-%' ORDER BY codigo;
