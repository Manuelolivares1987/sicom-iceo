-- ============================================================================
-- SEED — Asignacion inicial de categoria_uso (MANUAL)
-- ============================================================================
-- Fuente: ABRIL.xlsx hoja "Report Diario" (abril 2026).
-- Regla aplicada: L>50% -> leasing_operativo; U>50% -> uso_interno;
--                 V>50% -> venta; resto -> arriendo_comercial.
--
-- Este archivo es un PUNTO DE PARTIDA. La categoria es manual; ajusta los
-- equipos que veas distinto antes o despues de correr este script.
--
-- Resumen derivado:
--   arriendo_comercial : 30
--   uso_interno        : 16
--   leasing_operativo  :  8
--   venta              :  1
--   TOTAL              : 55
--
-- Requiere: migracion 40 aplicada (columna activos.categoria_uso y enum).
-- ============================================================================

BEGIN;

UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'DCHD-83';
UPDATE activos SET categoria_uso = 'uso_interno'::categoria_uso_enum        WHERE patente = 'DJKL-18';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'FJTJ-60';
UPDATE activos SET categoria_uso = 'venta'::categoria_uso_enum              WHERE patente = 'FJTJ-61';
UPDATE activos SET categoria_uso = 'uso_interno'::categoria_uso_enum        WHERE patente = 'FSLZ-67';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'GCHT-12';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'GCSY-66';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'GDP 30TK';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'GGHB-32';
UPDATE activos SET categoria_uso = 'uso_interno'::categoria_uso_enum        WHERE patente = 'HHWB-42';
UPDATE activos SET categoria_uso = 'uso_interno'::categoria_uso_enum        WHERE patente = 'HHWB-44';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'HKSR-81';
UPDATE activos SET categoria_uso = 'uso_interno'::categoria_uso_enum        WHERE patente = 'JDKH-31';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'JGBY-10';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'JTYK-88';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'KCBY-30';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'KCBY-31';
UPDATE activos SET categoria_uso = 'uso_interno'::categoria_uso_enum        WHERE patente = 'KVDK-20';
UPDATE activos SET categoria_uso = 'uso_interno'::categoria_uso_enum        WHERE patente = 'KVDK-21';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'KVWD-27';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'KVWW-68';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'KVWW-69';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'LCSX-78';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'LKPY-18';
UPDATE activos SET categoria_uso = 'uso_interno'::categoria_uso_enum        WHERE patente = 'LLBP-96';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'RSCY-85';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'RSCY-86';
UPDATE activos SET categoria_uso = 'uso_interno'::categoria_uso_enum        WHERE patente = 'RZPC-83';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'SBPG-12';
UPDATE activos SET categoria_uso = 'uso_interno'::categoria_uso_enum        WHERE patente = 'SLRK-82';
UPDATE activos SET categoria_uso = 'uso_interno'::categoria_uso_enum        WHERE patente = 'SPRY-26';
UPDATE activos SET categoria_uso = 'uso_interno'::categoria_uso_enum        WHERE patente = 'SPRY-28';
UPDATE activos SET categoria_uso = 'uso_interno'::categoria_uso_enum        WHERE patente = 'SPRY-29';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'SVBJ-55';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'SVBJ-56';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'SVBJ-57';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'SVCZ-38';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'TCJV-15';
UPDATE activos SET categoria_uso = 'uso_interno'::categoria_uso_enum        WHERE patente = 'TCRB-71';
UPDATE activos SET categoria_uso = 'leasing_operativo'::categoria_uso_enum  WHERE patente = 'TGGF-56';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'TGGF-57';
UPDATE activos SET categoria_uso = 'leasing_operativo'::categoria_uso_enum  WHERE patente = 'TGGF-58';
UPDATE activos SET categoria_uso = 'leasing_operativo'::categoria_uso_enum  WHERE patente = 'TGGF-59';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'TGGF-60';
UPDATE activos SET categoria_uso = 'leasing_operativo'::categoria_uso_enum  WHERE patente = 'TRDP-96';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'TRDP-97';
UPDATE activos SET categoria_uso = 'leasing_operativo'::categoria_uso_enum  WHERE patente = 'TRSS-13';
UPDATE activos SET categoria_uso = 'leasing_operativo'::categoria_uso_enum  WHERE patente = 'TRSS-14';
UPDATE activos SET categoria_uso = 'leasing_operativo'::categoria_uso_enum  WHERE patente = 'TRSS-15';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'TRSS-16';
UPDATE activos SET categoria_uso = 'leasing_operativo'::categoria_uso_enum  WHERE patente = 'TRST-57';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'TRST-58';
UPDATE activos SET categoria_uso = 'uso_interno'::categoria_uso_enum        WHERE patente = 'TSTB-48';
UPDATE activos SET categoria_uso = 'arriendo_comercial'::categoria_uso_enum WHERE patente = 'TTPC-47';
UPDATE activos SET categoria_uso = 'uso_interno'::categoria_uso_enum        WHERE patente = 'VRST-19';

-- Verificacion: reporte de cuantos quedaron en cada categoria
SELECT categoria_uso, COUNT(*) AS equipos
  FROM activos
 WHERE categoria_uso IS NOT NULL
 GROUP BY categoria_uso
 ORDER BY equipos DESC;

COMMIT;
