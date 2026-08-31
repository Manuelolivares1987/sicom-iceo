-- ============================================================================
-- MIG470 · La cuadrilla que quedó guardada con UUIDs
-- ============================================================================
--
-- LO QUE REPORTÓ MANUEL
-- «En esta OT no aparecen los responsables colocados en planificación, en la
-- cuadrilla». La OT es la OT-202608-00014.
--
-- ES UNA REGRESIÓN MÍA, Y DE LAS QUE IMPORTAN
-- En MIG451 cambié el selector de mecánicos para que trabajara con IDS en vez
-- de nombres: era necesario, porque el bono tiene que saber QUIÉN es cada uno y
-- un texto con «Yusdel Sarduy Joel Coo» adentro no lo dice.
--
-- Actualicé el modal que asigna la cuadrilla, y NO actualicé las tres pantallas
-- que la escriben al planificar. Esas seguían haciendo `mecanicos.join(', ')`
-- sobre lo que ahora son ids. Resultado, en la base:
--
--     cuadrilla = «f7418871-1ee7-4d48-8495-6027832b6619, aa8dac3d-…»
--     personas en taller_ot_cuadrilla = 0
--
-- Los ids son de Joel Coo y Yeran Sanhueza, o sea el planificador SÍ los eligió.
-- En pantalla se veían UUIDs, y para el bono la OT no tenía a nadie: es
-- exactamente el caso «trabajo cerrado que no le paga a nadie» que MIG464
-- aprendió a detectar.
--
-- ALCANCE, MEDIDO ANTES DE TOCAR
-- 5 jornadas, 1 OT, las dos personas identificables. Es la primera OT que se
-- planificó después del cambio: se detectó a tiempo.
--
-- LO QUE SE HACE ACÁ
-- Convertir esos ids en personas de verdad y re-derivar el texto. El arreglo de
-- fondo —que las tres pantallas guarden personas y no texto— va en el frontend,
-- en el mismo cambio.
--
-- La conversión sólo toca jornadas de OT no ejecutadas, porque el trigger de
-- MIG446 congela la cuadrilla al ejecutar y tiene razón en hacerlo.
-- ============================================================================

BEGIN;

-- ── 1 · Los ids del texto se convierten en personas ─────────────────────────
WITH ids AS (
    SELECT po.id AS plan_ot_id, TRIM(u.raw) AS id_txt
      FROM taller_plan_semanal_ots po
      JOIN ordenes_trabajo ot ON ot.id = po.ot_id,
           LATERAL unnest(string_to_array(po.cuadrilla, ',')) AS u(raw)
     WHERE po.cuadrilla ~ '[0-9a-f]{8}-[0-9a-f]{4}-'
       AND TRIM(u.raw) ~ '^[0-9a-f-]{36}$'
       AND ot.estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada','cancelada')
)
INSERT INTO taller_ot_cuadrilla (plan_ot_id, tecnico_id, rol)
SELECT DISTINCT i.plan_ot_id, t.id, 'titular'
  FROM ids i
  JOIN taller_tecnicos t ON t.id::TEXT = i.id_txt
ON CONFLICT DO NOTHING;

-- ── 2 · Y el texto vuelve a decir nombres ───────────────────────────────────
UPDATE taller_plan_semanal_ots po
   SET cuadrilla = (SELECT string_agg(t.nombre, ', ' ORDER BY t.nombre)
                      FROM taller_ot_cuadrilla c
                      JOIN taller_tecnicos t ON t.id = c.tecnico_id
                     WHERE c.plan_ot_id = po.id),
       updated_at = NOW()
 WHERE po.cuadrilla ~ '[0-9a-f]{8}-[0-9a-f]{4}-'
   AND EXISTS (SELECT 1 FROM taller_ot_cuadrilla c WHERE c.plan_ot_id = po.id);

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE r RECORD; v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM taller_plan_semanal_ots
     WHERE cuadrilla ~ '[0-9a-f]{8}-[0-9a-f]{4}-';
    IF v_n > 0 THEN
        RAISE EXCEPTION 'FALLO: quedaron % jornadas con UUID en el texto de la cuadrilla', v_n;
    END IF;
    RAISE NOTICE 'ninguna jornada guarda ya UUIDs en el texto de la cuadrilla';

    FOR r IN
        SELECT ot.folio, count(DISTINCT po.id) jornadas,
               (SELECT string_agg(DISTINCT t.nombre, ', ')
                  FROM taller_plan_semanal_ots p2
                  JOIN taller_ot_cuadrilla c ON c.plan_ot_id = p2.id
                  JOIN taller_tecnicos t ON t.id = c.tecnico_id
                 WHERE p2.ot_id = ot.id) quienes
          FROM ordenes_trabajo ot
          JOIN taller_plan_semanal_ots po ON po.ot_id = ot.id
         WHERE ot.folio = 'OT-202608-00014'
         GROUP BY ot.id, ot.folio
    LOOP
        RAISE NOTICE '% · % jornadas · cuadrilla: %', r.folio, r.jornadas,
            COALESCE(r.quienes, '(SIGUE SIN NADIE)');
        IF r.quienes IS NULL THEN
            RAISE EXCEPTION 'FALLO: la OT reportada sigue sin cuadrilla';
        END IF;
    END LOOP;

    -- Y que el bono ya la vea.
    SELECT count(*) INTO v_n FROM v_taller_bono_reparto WHERE ot_folio = 'OT-202608-00014';
    RAISE NOTICE 'lineas de reparto del bono para esa OT: % (antes 0)', v_n;
END
$mig$;

COMMIT;
