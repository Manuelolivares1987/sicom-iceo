-- ============================================================================
-- SICOM-ICEO | 114 — Completar tiempos HH faltantes en pautas_fabricante
-- ============================================================================
-- Hallazgo: las "pautas duplicadas" NO eran duplicados — son el mismo servicio
-- para MODELOS distintos (Actros 3336K vs 3341, Mack autom/Allison/Mec, etc.).
-- No se borra nada.
--
-- Acción: completar las 29 pautas con duracion_estimada_hrs NULL usando el
-- estándar de tiempos de la hoja Actros de la Maestra (SL 2.7 / SM1 4.2 /
-- SM2 6.4 / SM3 10.8) por analogía de nivel de servicio. Se marcan como
-- ESTIMADAS (duracion_es_estimada=true) para que el jefe de taller las valide.
-- ============================================================================

ALTER TABLE pautas_fabricante
  ADD COLUMN IF NOT EXISTS duracion_es_estimada BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN pautas_fabricante.duracion_es_estimada IS
  'TRUE = duracion_estimada_hrs fue estimada por analogia (validar con jefe de taller).';

-- Mack GU813E por nivel de servicio
UPDATE pautas_fabricante SET duracion_estimada_hrs = 2.7,  duracion_es_estimada = true WHERE duracion_estimada_hrs IS NULL AND nombre LIKE 'Mack%SL %';
UPDATE pautas_fabricante SET duracion_estimada_hrs = 4.2,  duracion_es_estimada = true WHERE duracion_estimada_hrs IS NULL AND nombre LIKE 'Mack%SM1%';
UPDATE pautas_fabricante SET duracion_estimada_hrs = 6.4,  duracion_es_estimada = true WHERE duracion_estimada_hrs IS NULL AND nombre LIKE 'Mack%SM2%';
UPDATE pautas_fabricante SET duracion_estimada_hrs = 10.8, duracion_es_estimada = true WHERE duracion_estimada_hrs IS NULL AND nombre LIKE 'Mack%SM3%';

-- Renault C440 por nivel
UPDATE pautas_fabricante SET duracion_estimada_hrs = 4.2,  duracion_es_estimada = true WHERE duracion_estimada_hrs IS NULL AND nombre LIKE 'Renault%basico%';
UPDATE pautas_fabricante SET duracion_estimada_hrs = 6.4,  duracion_es_estimada = true WHERE duracion_estimada_hrs IS NULL AND nombre LIKE 'Renault%intermedio%';
UPDATE pautas_fabricante SET duracion_estimada_hrs = 10.8, duracion_es_estimada = true WHERE duracion_estimada_hrs IS NULL AND nombre LIKE 'Renault%mayor%';
UPDATE pautas_fabricante SET duracion_estimada_hrs = 15.0, duracion_es_estimada = true WHERE duracion_estimada_hrs IS NULL AND nombre LIKE 'Renault%overhaul%';
UPDATE pautas_fabricante SET duracion_estimada_hrs = 2.0,  duracion_es_estimada = true WHERE duracion_estimada_hrs IS NULL AND nombre LIKE 'Renault%refriger%';

-- Tareas genéricas (sub-servicios)
UPDATE pautas_fabricante SET duracion_estimada_hrs = 2.0,  duracion_es_estimada = true WHERE duracion_estimada_hrs IS NULL AND nombre = 'Cambio de aceite motor';
UPDATE pautas_fabricante SET duracion_estimada_hrs = 1.0,  duracion_es_estimada = true WHERE duracion_estimada_hrs IS NULL AND nombre = 'Engrase general';
UPDATE pautas_fabricante SET duracion_estimada_hrs = 1.0,  duracion_es_estimada = true WHERE duracion_estimada_hrs IS NULL AND nombre = 'Filtros de aire y combustible';
UPDATE pautas_fabricante SET duracion_estimada_hrs = 3.0,  duracion_es_estimada = true WHERE duracion_estimada_hrs IS NULL AND nombre LIKE 'Frenos%hidr%';

-- ── Verificación ───────────────────────────────────────────────────────────
DO $$
DECLARE v_null INT; v_estimadas INT;
BEGIN
    SELECT count(*) INTO v_null      FROM pautas_fabricante WHERE duracion_estimada_hrs IS NULL;
    SELECT count(*) INTO v_estimadas FROM pautas_fabricante WHERE duracion_es_estimada;
    RAISE NOTICE '== Completar tiempos pautas ==';
    RAISE NOTICE 'Pautas sin tiempo restantes: % (debe ser 0)', v_null;
    RAISE NOTICE 'Pautas con tiempo ESTIMADO (validar): %', v_estimadas;
END $$;
