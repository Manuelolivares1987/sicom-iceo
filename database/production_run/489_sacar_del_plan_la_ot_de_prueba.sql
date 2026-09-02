-- ============================================================================
-- MIG489 · Sacar del plan la OT de prueba OT-202608-00015
-- ============================================================================
--
-- Manuel, 02-09-2026: «esta OT la voy a eliminar del plan semanal, pero necesito
-- que también salga del plan taller; es una prueba y quiero volver a hacer otra».
--
-- Se usa la función de MIG488 —no un UPDATE a mano— para que quede el mismo
-- rastro que dejaría hacerlo desde la pantalla.
--
-- LO QUE SE VA
--   · Las 5 jornadas del 07 al 11 de septiembre.
--   · La ejecución pausada (15 minutos), que se cancela con su tiempo escrito.
--   · La OT queda cancelada, así no vuelve por «viene de semanas anteriores».
--
-- LO QUE NO SE VA
--   · Las 2 no conformidades siguen abiertas: «sistema de dirección - sin
--     fugas» y «alta corrosión exterior estanque combustible». La segunda no
--     parece un dato de prueba, y una NC nace de mirar el equipo, no de
--     planificarlo. Quedan en la bandeja por agendar para que Manuel decida.
--   · El despacho de bodega (1 kg de trapo, ticket TKT-202608-00009). El trapo
--     salió; ese movimiento no se deshace desde acá.
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_admin UUID;
    v_r JSONB;
    r RECORD;
BEGIN
    SELECT id INTO v_admin FROM usuarios_perfil
     WHERE email = 'molivares.codoceo@gmail.com' OR rol = 'administrador'
     ORDER BY (email = 'molivares.codoceo@gmail.com') DESC LIMIT 1;

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);

    v_r := rpc_taller_sacar_ot_del_plan(
        'fcc5732f-6fd3-49b1-940b-989eb895cbdd',
        TRUE,
        'Era una prueba del flujo del plan taller. Se rehace con otra OT.',
        TRUE);

    RAISE NOTICE '%', v_r;

    FOR r IN
        SELECT nc.descripcion, nc.severidad::TEXT AS sev
          FROM no_conformidades nc
         WHERE nc.ot_id = 'fcc5732f-6fd3-49b1-940b-989eb895cbdd'
           AND COALESCE(nc.resuelto, FALSE) = FALSE
    LOOP
        RAISE NOTICE '  NC que queda abierta (%): %', r.sev, r.descripcion;
    END LOOP;
END $$;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_j INT; v_b INT; v_est TEXT;
BEGIN
    SELECT count(*) INTO v_j FROM taller_plan_semanal_ots
     WHERE ot_id = 'fcc5732f-6fd3-49b1-940b-989eb895cbdd';
    SELECT count(*) INTO v_b FROM v_taller_ot_backlog
     WHERE ot_id = 'fcc5732f-6fd3-49b1-940b-989eb895cbdd';
    SELECT estado::TEXT INTO v_est FROM ordenes_trabajo
     WHERE id = 'fcc5732f-6fd3-49b1-940b-989eb895cbdd';
    RAISE NOTICE 'jornadas en el plan: % · en el arrastre del taller: % · la OT quedó «%»',
                 v_j, v_b, v_est;
END $mig$;

COMMIT;
