-- ============================================================================
-- MIG483 · D2 · El trabajo compartido se paga por tiempo medido
-- ============================================================================
--
-- LO QUE DECIDIÓ MANUEL
-- 01-09-2026, después de ver los escenarios: «por lo tanto mantenemos como hoy,
-- por reparto con tiempo medido».
--
-- QUÉ SIGNIFICA
-- Cuando dos o más personas trabajan el mismo trabajo, la línea se reparte
-- entre ellas en proporción al tiempo que cada una marcó. No hay un bono
-- adicional para el segundo: los dos cobran, del mismo trabajo.
--
-- Ojo con el malentendido que traía la planilla: ahí la opción «no» significaba
-- que el titular se llevaba la línea entera y el segundo no recibía nada. Acá
-- no es eso. Los dos cobran; lo que no se hace es pagar 1,5 trabajos por un
-- trabajo.
--
-- LO QUE COSTABA LA ALTERNATIVA
-- Medido sobre una MTN cerrada en plazo óptimo, Mecánico A + Mecánico B con
-- 60/40 de tiempo: reparto $33.636 · titular se lleva todo $36.364 · segundo
-- con 50% encima $51.136. Y no es un caso raro: de 31 OT con reparto, 12 tienen
-- dos o más personas.
--
-- LO QUE QUEDA ANOTADO PARA DESPUÉS
-- Hoy esas 12 OT reparten por «jornadas asignadas», no por tiempo medido,
-- porque hasta ayer nadie tenía cuenta propia (MIG478). Cuando haya un corte
-- con tiempo real por persona, vale la pena mirar si algún ayudante queda con
-- una participación demasiado chica; si pasa, la respuesta es un PISO por
-- persona —una fila de parámetros—, no un bono aparte.
--
-- CON ESTO NO QUEDAN DECISIONES BLOQUEANTES ABIERTAS.
-- ============================================================================

BEGIN;

UPDATE taller_bono_acta
   SET decision = 'No genera bono propio: la línea se reparte entre quienes trabajaron, '
                  'en proporción al tiempo medido de cada uno. Los dos cobran del mismo trabajo.',
       estado = 'resuelta',
       resuelta_por = 'Manuel Olivares',
       resuelta_at = NOW(),
       nota = 'Escenarios medidos sobre una MTN en plazo óptimo (Mec A + Mec B, 60/40): '
              'reparto $33.636 · titular se lleva todo $36.364 · segundo con 50% encima $51.136. '
              'Pagar encima crea el incentivo de sumar nombres a la cuadrilla. '
              'Pendiente de mirar con tiempo real: si un ayudante queda con participación muy '
              'chica, la respuesta es un piso por persona, no un bono aparte.'
 WHERE codigo = 'D2';

UPDATE taller_bono_parametros
   SET notas = replace(notas,
        'D2 sigue abierta y no impide calcular: rige el reparto por tiempo medido.',
        'D2 resuelta el 01-09: el trabajo compartido se reparte por tiempo medido, sin bono adicional.')
 WHERE estado = 'vigente';

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_ab INT; r RECORD;
BEGIN
    SELECT count(*) INTO v_ab FROM taller_bono_acta WHERE estado = 'abierta' AND bloqueante;
    FOR r IN SELECT codigo, estado FROM taller_bono_acta ORDER BY codigo LOOP
        RAISE NOTICE '  % · %', r.codigo, r.estado;
    END LOOP;
    RAISE NOTICE 'decisiones bloqueantes abiertas: %', v_ab;
END $mig$;

COMMIT;
