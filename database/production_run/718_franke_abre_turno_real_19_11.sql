-- ============================================================================
-- MIG718 — Franke: abrir el turno real desde el 19-11-2026
-- ----------------------------------------------------------------------------
-- El «Turno 1» (25-08 → 31-08) se abrió al construir la pantalla (MIG392) y
-- quedó abierto: /m/franke/turno decía «Van 88 días… turno corrido». Franke
-- recién empieza a operar con SICOM; Manuel (19-11): el turno real empezó hoy.
--
-- Se usa la MISMA función que el botón del supervisor (rpc_faena_ciclo_abrir),
-- que cierra el anterior sola. Queda registrado como abierto por Manuel
-- (admin@pillado.cl). Sin letra de turno (A/B): no se informó.
-- ============================================================================

SELECT set_config('request.jwt.claims',
                  json_build_object('sub', 'd8d49f65-0bad-44a2-9565-09a4f2bd5abc', 'role', 'authenticated')::text,
                  true);

SELECT public.rpc_faena_ciclo_abrir(
    (SELECT id FROM public.faenas WHERE codigo = 'FAE-FRANCKE'),
    DATE '2026-11-19',
    NULL,
    7
) AS resultado;

SELECT c.numero, c.turno, c.fecha_inicio, c.fecha_fin, c.estado
FROM public.faena_ciclo c JOIN public.faenas f ON f.id = c.faena_id
WHERE f.codigo = 'FAE-FRANCKE' ORDER BY c.numero;
