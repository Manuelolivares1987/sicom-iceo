-- ============================================================================
-- SICOM-ICEO | 274b — Corrección: los puntos de Lomas van en LB_LUB
-- ============================================================================
-- La MIG274 buscó la faena con ILIKE '%lomas%' LIMIT 1 y hay DOS: "Lomas Bayas
-- — Combustibles" (LB_COMB) y "Lomas Bayas — Lubricantes" (LB_LUB). Cayó en la
-- de combustibles, que estaba vacía: creó ahí los 7 truck shops y dejó los 9
-- registros reales de LB_LUB sin tocar.
--
-- Aquí se borran los 7 mal ubicados (ninguno tiene programaciones ni trabajo) y
-- se normaliza de verdad LB_LUB.
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. Fuera los puntos creados en la faena equivocada ──────────────────────
DELETE FROM enex_instalaciones i
 USING enex_faenas f
 WHERE f.id = i.faena_id
   AND f.codigo = 'LB_COMB'
   AND i.tipo = 'truck_shop'
   AND NOT EXISTS (SELECT 1 FROM enex_programaciones p WHERE p.instalacion_id = i.id);


-- ── 2. Normalizar los 7 puntos reales en LB_LUB ─────────────────────────────
DO $$
DECLARE
    v_faena UUID;
    v_id    UUID;
    r       TEXT[];
    -- nombre_final , codigo , area , orden , nombre_previo
    puntos CONSTANT TEXT[][] := ARRAY[
        ARRAY['Truck Shop Lomas 1 - Rack 1',        'LB-TS1-R1', 'Truck Shop Lomas 1', '1',
              'Truck Shop Lomas 1 - RACK 1'],
        ARRAY['Truck Shop Lomas 1 - Rack 2',        'LB-TS1-R2', 'Truck Shop Lomas 1', '2',
              'Truck Shop Lomas 1 - Rack 2'],
        ARRAY['Truck Shop Lomas 1 - Microfiltrado', 'LB-TS1-MF', 'Truck Shop Lomas 1', '3',
              'Truck Shop Lomas 1 - Microfiltrado'],
        ARRAY['Truck Shop Lomas 2 - Rack 1',        'LB-TS2-R1', 'Truck Shop Lomas 2', '4',
              'Truck Shop Lomas 2 - Rack 1'],
        ARRAY['Truck Shop Lomas 2 - Rack 2',        'LB-TS2-R2', 'Truck Shop Lomas 2', '5',
              'TruckShop2/ Rack 2'],
        ARRAY['Truck Shop Lomas 2 - Rack 3',        'LB-TS2-R3', 'Truck Shop Lomas 2', '6',
              'Truck shop 2 / Rack 3'],
        ARRAY['Truck Shop Lomas 2 - Microfiltrado', 'LB-TS2-MF', 'Truck Shop Lomas 2', '7',
              'Truck Shop Lomas 2 -  Microfiltrado']
    ];
BEGIN
    SELECT id INTO v_faena FROM enex_faenas WHERE codigo = 'LB_LUB' LIMIT 1;
    IF v_faena IS NULL THEN RAISE EXCEPTION 'MIG274b: no existe la faena LB_LUB'; END IF;

    FOREACH r SLICE 1 IN ARRAY puntos LOOP
        -- Por código (si ya se corrió), luego por nombre previo o final. Ante
        -- duplicados gana el que tenga trabajo: el histórico no se parte.
        SELECT id INTO v_id FROM enex_instalaciones
         WHERE faena_id = v_faena AND codigo = r[2] LIMIT 1;

        IF v_id IS NULL THEN
            SELECT id INTO v_id FROM enex_instalaciones
             WHERE faena_id = v_faena
               AND (regexp_replace(lower(nombre), '\s+', ' ', 'g') = regexp_replace(lower(r[5]), '\s+', ' ', 'g')
                 OR regexp_replace(lower(nombre), '\s+', ' ', 'g') = regexp_replace(lower(r[1]), '\s+', ' ', 'g'))
             ORDER BY (SELECT count(*) FROM enex_programaciones p WHERE p.instalacion_id = enex_instalaciones.id) DESC,
                      created_at
             LIMIT 1;
        END IF;

        IF v_id IS NULL THEN
            INSERT INTO enex_instalaciones (faena_id, nombre, codigo, area, tipo, linea,
                                            frecuencia_meses, orden, activo)
            VALUES (v_faena, r[1], r[2], r[3], 'truck_shop', 'lubricante', 3, r[4]::int, TRUE);
            RAISE NOTICE 'MIG274b: punto creado %', r[1];
        ELSE
            UPDATE enex_instalaciones
               SET nombre = r[1], codigo = r[2], area = r[3], orden = r[4]::int,
                   tipo = 'truck_shop', linea = 'lubricante', activo = TRUE
             WHERE id = v_id;
            RAISE NOTICE 'MIG274b: punto normalizado %', r[1];
        END IF;
    END LOOP;

    -- Los que sobran (genérico "Truck shop 2" y el Rack 2 duplicado) se
    -- desactivan: pueden tener programaciones y el histórico debe seguir legible.
    UPDATE enex_instalaciones
       SET activo = FALSE
     WHERE faena_id = v_faena
       AND (codigo IS NULL OR codigo <> ALL (ARRAY['LB-TS1-R1','LB-TS1-R2','LB-TS1-MF',
                                                   'LB-TS2-R1','LB-TS2-R2','LB-TS2-R3','LB-TS2-MF']))
       AND activo;
END $$;


-- ── 3. Validación ───────────────────────────────────────────────────────────
SELECT f.codigo AS faena, i.codigo, i.nombre, i.area, i.orden, i.activo
  FROM enex_instalaciones i JOIN enex_faenas f ON f.id = i.faena_id
 WHERE f.codigo IN ('LB_LUB','LB_COMB')
 ORDER BY f.codigo, i.activo DESC, i.orden;
