-- ============================================================================
-- MIG453 · Los nombres y los cargos salen de la liquidación
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 31-08-2026: entregó la carpeta de liquidaciones de agosto «para que
-- actualices los nombres en sistema». El cargo es el dato que faltaba: sin él
-- no hay tope ni base de KPI, y el motor de MIG452 devolvía el trabajo contado
-- con el monto en NULL.
--
-- DE DÓNDE SALE CADA DATO
-- De las nueve liquidaciones de agosto 2026, leyendo sólo dos campos: NOMBRE y
-- CARGO. Ni montos ni datos previsionales; no hacían falta y no se leyeron.
--
-- LO QUE SE CORRIGE
-- Cuatro de los nueve estaban en el sistema con un nombre incompleto o mal
-- escrito, y uno de ellos aparece así en el tablero todos los días:
--
--   Brian          → Brian Alday        (ALDAY GONZALEZ BRIAN ANTONIO)
--   Geran          → Yeran Sanhueza     (SANHUEZA BAHAMONDES YERAN IGNACIO)
--   Juan           → Juan Valenzuela    (VALENZUELA LEMUS JUAN CRISTHIAN)
--   Marcos Diaz    → Marco Díaz         (DIAZ ORREGO MARCO ANTONIO)
--
-- «Geran» no era una abreviación: era «Yeran» mal escrito, y así lleva meses en
-- las tarjetas del plan. «Marcos» es «Marco», en singular.
--
-- LO QUE NO SE TOCA, Y POR QUÉ
--
--   · Felipe López tiene 41 jornadas en el plan —38 en Taller Coquimbo y 3 en
--     Calama— y NO tiene liquidación en esta carpeta. Existe como usuario con
--     rol auditor_calidad y cargo «Técnico Mecánico Senior». No le pongo cargo
--     de bono: o se paga en otra planilla, o es externo, o algo falta. Es una
--     pregunta para RRHH, no una suposición mía. Sin cargo, el motor lo cuenta
--     y avisa «falta el cargo del técnico» en vez de inventarle un tope.
--
--   · Ricardo Burgos aparece en las liquidaciones como JEFE DE TALLER y no
--     existe en el catálogo de técnicos. No lo agrego: la jefatura no recibe
--     plan de incentivo, así que no es un técnico del bono. Lo que sí conviene
--     mirar es que la cuenta que cierra OTs se llama «Jefe de Taller», que es
--     un cargo y no una persona. Desde septiembre el cierre decide un pago:
--     una cuenta de cargo no sirve para responder quién cerró.
--
--   · El texto histórico de la cuadrilla en OTs ya ejecutadas queda como estaba.
--     Es el registro de lo que se escribió ese día. Sólo se re-deriva el de las
--     jornadas cuya OT sigue abierta.
-- ============================================================================

BEGIN;

-- ── 1 · Los nombres, como están en la liquidación ───────────────────────────
UPDATE taller_tecnicos SET nombre = 'Brian Alday',    especialidad = 'Mecánico B'
 WHERE nombre = 'Brian';
UPDATE taller_tecnicos SET nombre = 'Yeran Sanhueza', especialidad = 'Mecánico B'
 WHERE nombre = 'Geran';
UPDATE taller_tecnicos SET nombre = 'Juan Valenzuela', especialidad = 'Mecánico A'
 WHERE nombre = 'Juan';
UPDATE taller_tecnicos SET nombre = 'Marco Díaz',     especialidad = 'Mecánico A'
 WHERE nombre = 'Marcos Diaz';

UPDATE taller_tecnicos SET especialidad = 'Mecánico A' WHERE nombre = 'Joel Coo';
UPDATE taller_tecnicos SET especialidad = 'Mecánico B' WHERE nombre = 'Yusdel Sarduy';
UPDATE taller_tecnicos SET especialidad = 'Soldador'   WHERE nombre = 'Danny Guerra';
UPDATE taller_tecnicos SET especialidad = 'Conductor operador' WHERE nombre = 'Jorge Castro';

-- ── 2 · El cargo, que es lo que decide el tope ──────────────────────────────
INSERT INTO taller_tecnico_cargo (tecnico_id, cargo, desde)
SELECT t.id, x.cargo, DATE '2026-09-01'
  FROM (VALUES
      ('Joel Coo',        'Mecanico A'),
      ('Juan Valenzuela', 'Mecanico A'),
      ('Marco Díaz',      'Mecanico A'),
      ('Brian Alday',     'Mecanico B'),
      ('Yeran Sanhueza',  'Mecanico B'),
      ('Yusdel Sarduy',   'Mecanico B'),
      ('Danny Guerra',    'Soldador'),
      ('Jorge Castro',    'Conductor')
  ) AS x(nombre, cargo)
  JOIN taller_tecnicos t ON t.nombre = x.nombre
ON CONFLICT (tecnico_id, desde) DO UPDATE SET cargo = EXCLUDED.cargo;

-- ── 3 · El texto de la cuadrilla, sólo donde todavía es plan ────────────────
UPDATE taller_plan_semanal_ots po
   SET cuadrilla = (SELECT string_agg(t.nombre, ', ' ORDER BY c.rol DESC, t.nombre)
                      FROM taller_ot_cuadrilla c
                      JOIN taller_tecnicos t ON t.id = c.tecnico_id
                     WHERE c.plan_ot_id = po.id),
       updated_at = NOW()
 WHERE EXISTS (SELECT 1 FROM taller_ot_cuadrilla c WHERE c.plan_ot_id = po.id)
   AND EXISTS (SELECT 1 FROM ordenes_trabajo ot
                WHERE ot.id = po.ot_id
                  AND ot.estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada','cancelada'));

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE
    v_con INT; v_sin TEXT; v_viejos TEXT;
BEGIN
    SELECT count(*) INTO v_con FROM taller_tecnico_cargo;
    RAISE NOTICE 'técnicos con cargo cargado: %', v_con;

    SELECT string_agg(t.nombre, ', ' ORDER BY t.nombre) INTO v_sin
      FROM taller_tecnicos t
     WHERE COALESCE(t.activo, TRUE)
       AND NOT EXISTS (SELECT 1 FROM taller_tecnico_cargo tc WHERE tc.tecnico_id = t.id);
    RAISE NOTICE 'activos que siguen SIN cargo: %', COALESCE(v_sin, '(ninguno)');

    SELECT string_agg(nombre, ', ') INTO v_viejos FROM taller_tecnicos
     WHERE nombre IN ('Brian','Geran','Juan','Marcos Diaz');
    IF v_viejos IS NOT NULL THEN
        RAISE EXCEPTION 'FALLO: quedaron nombres sin corregir: %', v_viejos;
    END IF;
    RAISE NOTICE 'nombres corregidos: Brian Alday · Yeran Sanhueza · Juan Valenzuela · Marco Díaz';

    -- El motor ya puede poner monto donde antes decía «falta el cargo»
    SELECT count(*) INTO v_con
      FROM taller_bono_cargo cg
      JOIN taller_tecnico_cargo tc ON tc.cargo = cg.cargo;
    RAISE NOTICE 'cargos que calzan con un tope del juego de parámetros: %', v_con;
END
$mig$;

COMMIT;
