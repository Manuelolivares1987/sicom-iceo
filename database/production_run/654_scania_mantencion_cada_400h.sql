-- 654 — Scania: la mantención va cada 400 h, como Volvo (2026-10-26).
--
-- Manuel: «sí, los Scania también cada 400 horas». Los papeles de mantención
-- Scania ya decían próxima = hecha + 400 (TRSS-16 869 → 1.269, TRST-57
-- 1.229 → 1.629, TTPC-47 12 → 412, TRST-58 7.004 → 7.404); con la escalera a
-- 300 el de TRSS-16 se rechazaba (MIG653) y los otros dejaban la base
-- 100 h corrida.
--
--   1. Escalera Scania S/M/L/XL 300/600/1.200/2.400 → 400/800/1.600/3.200
--      (P450B, P 410 Lubrimóvil, R 500), pautas y planes sincronizados.
--      fn_intervalo_mantencion_horas (MIG652) toma el menor peldaño de los
--      planes: los Scania quedan solos en 400 (recepción del taller y
--      certificado).
--   2. Se reprocesa el papel de mantención más nuevo de cada Scania que trae
--      horómetro de próxima: se revierte lo que movió con 300 y se aplica de
--      nuevo con 400.

CREATE TEMP TABLE _scania_escalera ON COMMIT DROP AS
SELECT p.id, p.frecuencia_horas AS h_viejo,
       CASE p.frecuencia_horas WHEN 300 THEN 400 WHEN 600 THEN 800 WHEN 1200 THEN 1600 WHEN 2400 THEN 3200 END AS h_nuevo
  FROM pautas_fabricante p
  JOIN modelos mo ON mo.id = p.modelo_id
  JOIN marcas ma ON ma.id = mo.marca_id
 WHERE ma.nombre ILIKE '%scania%'
   AND p.frecuencia_horas IN (300, 600, 1200, 2400)
   AND p.frecuencia_km IS NULL;

UPDATE pautas_fabricante p
   SET frecuencia_horas = e.h_nuevo,
       nombre = replace(p.nombre, '(' || e.h_viejo::int || 'h)', '(' || e.h_nuevo::int || 'h)')
  FROM _scania_escalera e
 WHERE e.id = p.id;

UPDATE planes_mantenimiento pm
   SET frecuencia_horas = e.h_nuevo,
       nombre = replace(pm.nombre, '(' || e.h_viejo::int || 'h)', '(' || e.h_nuevo::int || 'h)'),
       updated_at = NOW()
  FROM _scania_escalera e
 WHERE pm.pauta_fabricante_id = e.id;

DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n
      FROM planes_mantenimiento pm
      JOIN pautas_fabricante p ON p.id = pm.pauta_fabricante_id
      JOIN modelos mo ON mo.id = p.modelo_id
      JOIN marcas ma ON ma.id = mo.marca_id
     WHERE ma.nombre ILIKE '%scania%' AND pm.frecuencia_horas IS DISTINCT FROM p.frecuencia_horas;
    IF n > 0 THEN RAISE EXCEPTION 'MIG654: % planes Scania desincronizados de su pauta', n; END IF;
END $$;

-- Reprocesar los papeles Scania con horómetro de próxima.
DO $$
DECLARE r RECORD; v_res jsonb;
BEGIN
    FOR r IN
        SELECT DISTINCT ON (c.activo_id) c.id, a.patente
          FROM certificaciones c
          JOIN activos a ON a.id = c.activo_id
          JOIN modelos mo ON mo.id = a.modelo_id
          JOIN marcas ma ON ma.id = mo.marca_id
         WHERE ma.nombre ILIKE '%scania%'
           AND c.tipo::TEXT = 'mantencion' AND c.anulado_at IS NULL
           AND c.estado::TEXT <> 'no_aplica' AND c.fecha_emision <= CURRENT_DATE
         ORDER BY c.activo_id, c.fecha_emision DESC, c.created_at DESC
    LOOP
        CONTINUE WHEN (SELECT horometro_vence FROM certificaciones WHERE id = r.id) IS NULL;
        PERFORM fn_mantencion_certificado_revertir(r.id);
        v_res := fn_mantencion_desde_certificado(r.id);
        RAISE NOTICE 'MIG654 % → %', r.patente, v_res;
    END LOOP;
END $$;
