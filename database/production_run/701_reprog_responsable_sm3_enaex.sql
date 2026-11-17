-- 701 — Responsable de 3 reprogramaciones que quedaron sin indicar (Manuel 16-11-2026).
--   Centinela, mantención SM3 del 04-11  → Operaciones ESM (papel firmado por ESM)
--   Spence, Enaex (Orica) del 02-11 ×2    → Mandante
DO $$
DECLARE n int;
BEGIN
    UPDATE enex_reprogramaciones SET responsable = 'operaciones_esm'
     WHERE id = 'c0a8f1e2-5b7d-4e3a-9f21-678000000001' AND responsable IS NULL;
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'SM3: % filas', n; END IF;

    UPDATE enex_reprogramaciones r SET responsable = 'mandante'
      FROM enex_faenas f
     WHERE f.id = r.faena_id AND f.codigo = 'SPENCE' AND r.fecha_original = DATE '2026-11-02'
       AND r.instalacion ILIKE '%Enaex%' AND r.responsable IS NULL;
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 2 THEN RAISE EXCEPTION 'Enaex: % filas', n; END IF;
END $$;

SELECT json_agg(json_build_object('faena', faena, 'inst', instalacion, 'act', actividad, 'fo', fecha_original, 'resp', responsable) ORDER BY faena, fecha_original)
  FROM enex_reprogramaciones WHERE fecha_original >= DATE '2026-10-01';
