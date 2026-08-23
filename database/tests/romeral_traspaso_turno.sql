-- ============================================================================
-- Prueba del traspaso de turno
-- ----------------------------------------------------------------------------
-- La queja del mandante: se le pide algo al turno de día, el turno de noche no
-- lo hace, y nadie se entera. Esta prueba juega esa historia completa:
--
--   El mandante pide algo el lunes por la mañana.
--   El turno de día no alcanza y lo dice.
--   El turno de noche intenta cerrar SIN decir nada  -> el sistema lo detiene.
--   El turno de noche dice que no alcanzó, sin motivo -> lo detiene otra vez.
--   El turno de noche dice que no alcanzó y por qué   -> cierra, y el pendiente
--                                                        sigue vivo con dos
--                                                        turnos encima.
--   El martes de día lo hacen                         -> se cierra.
--
-- Al final se mira la cadena completa, que es lo que el mandante pide ver: no
-- «¿lo anotaron?» sino «¿cuántos turnos lleva y quién lo dejó pasar cada vez?».
--
-- Corre en una transacción con ROLLBACK.
-- ============================================================================

BEGIN;

CREATE TEMP TABLE r(n int, escenario text, ok boolean, det text);
CREATE OR REPLACE FUNCTION pg_temp.an(a int, b text, c boolean, d text DEFAULT NULL)
RETURNS void LANGUAGE sql AS $$ INSERT INTO r VALUES (a,b,c,d) $$;
CREATE OR REPLACE FUNCTION pg_temp.como(p text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v UUID; BEGIN
  SELECT id INTO v FROM usuarios_perfil WHERE rol::text=p AND activo LIMIT 1;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub',v::text,'role','authenticated')::text, true);
END $$;

DO $b$
DECLARE
  f   UUID := (SELECT id FROM faenas WHERE codigo='FAE-CMP-ROMERAL');
  m1  UUID := (SELECT id FROM combustible_estanques WHERE codigo='ROM-MINA-1');
  L   DATE := DATE '2026-09-07';   -- lunes
  M   DATE := DATE '2026-09-08';   -- martes
  p1  UUID; p2 UUID; o JSONB; n INT; t TEXT;
  varilla JSONB := jsonb_build_array(jsonb_build_object(
    'estanque_id', m1, 'mi', 47000, 'mf', 46800, 'foto_url', 'https://x/v.jpg'));
BEGIN
  PERFORM pg_temp.como('supervisor');

  -- ══ El mandante pide dos cosas el lunes por la mañana ══
  o := rpc_comb_pendiente_crear(f,
        'Drenar agua del estanque Mina 1 antes del proximo despacho',
        'mandante', 'Karen (ESMAX)', 'alta');
  p1 := (o->>'pendiente_id')::uuid;

  o := rpc_comb_pendiente_crear(f,
        'Calibrar el surtidor 2 del Bimodal, quedo pendiente de la semana pasada',
        'mandante', 'Karen (ESMAX)', 'normal');
  p2 := (o->>'pendiente_id')::uuid;

  SELECT count(*) INTO n FROM v_comb_faena_pendientes_abiertos WHERE faena_id=f;
  PERFORM pg_temp.an(1, 'El mandante deja dos pendientes', n=2, n||' abiertos');

  -- ══ Turno de dia: hace uno, el otro no alcanza ══
  BEGIN
    o := rpc_comb_faena_guardar_cierre(f, L, 'Día', 'Supervisor Dia', varilla,
      '[]'::jsonb, NULL, true, 'trasp-d', NULL,
      jsonb_build_array(
        jsonb_build_object('pendiente_id', p1, 'respuesta','hecho',
                           'comentario','Drenado, salieron 40 L de agua'),
        jsonb_build_object('pendiente_id', p2, 'respuesta','no_alcanzo',
                           'comentario','No vino el tecnico de calibracion')));
    PERFORM pg_temp.an(2, 'El turno de dia contesta los dos', true, 'cerro el turno');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.an(2, 'El turno de dia contesta los dos', false, left(SQLERRM,66));
  END;

  SELECT count(*) INTO n FROM v_comb_faena_pendientes_abiertos WHERE faena_id=f;
  PERFORM pg_temp.an(3, 'El que se hizo se cierra solo', n=1, n||' sigue(n) abierto(s)');

  -- ══ Turno de noche: intenta cerrar sin decir nada ══
  BEGIN
    o := rpc_comb_faena_guardar_cierre(f, L, 'Noche', 'Supervisor Noche', varilla,
      '[]'::jsonb, NULL, true, 'trasp-n', NULL, NULL);
    -- Si llega hasta aca es que lo dejo cerrar sin contestar: eso es la falla.
    PERFORM pg_temp.an(4, 'Cerrar IGNORANDO el pendiente queda bloqueado',
                       false, 'LO DEJO CERRAR SIN CONTESTAR');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.an(4, 'Cerrar IGNORANDO el pendiente queda bloqueado',
                       SQLERRM LIKE '%Falta decir qué pasó%', left(SQLERRM,62));
  END;

  -- ══ Dice que no alcanzo, pero sin motivo ══
  BEGIN
    o := rpc_comb_faena_guardar_cierre(f, L, 'Noche', 'Supervisor Noche', varilla,
      '[]'::jsonb, NULL, true, 'trasp-n', NULL,
      jsonb_build_array(jsonb_build_object('pendiente_id', p2, 'respuesta','no_alcanzo')));
    PERFORM pg_temp.an(5, 'Decir "no alcance" sin motivo queda bloqueado',
                       false, 'LO ACEPTO SIN MOTIVO');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.an(5, 'Decir "no alcance" sin motivo queda bloqueado',
                       SQLERRM LIKE '%por qué no se alcanzó%', left(SQLERRM,62));
  END;

  -- ══ Ahora si: no alcanzo, y dice por que ══
  BEGIN
    o := rpc_comb_faena_guardar_cierre(f, L, 'Noche', 'Supervisor Noche', varilla,
      '[]'::jsonb, NULL, true, 'trasp-n', NULL,
      jsonb_build_array(jsonb_build_object('pendiente_id', p2, 'respuesta','no_alcanzo',
        'comentario','De noche no se calibra, queda para el turno de dia')));
    PERFORM pg_temp.an(6, 'No alcanzo y dice por que', true, 'cerro el turno');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.an(6, 'No alcanzo y dice por que', false, left(SQLERRM,66));
  END;

  SELECT turnos_sin_hacer, senal INTO n, t
    FROM v_comb_faena_pendientes_abiertos WHERE id = p2;
  PERFORM pg_temp.an(7, 'El pendiente arrastra los turnos que lleva',
                     n=2, n||' turnos · senal: '||t);

  -- ══ Martes de dia: lo hacen ══
  BEGIN
    o := rpc_comb_faena_guardar_cierre(f, M, 'Día', 'Supervisor Dia', varilla,
      '[]'::jsonb, NULL, true, 'trasp-d2', NULL,
      jsonb_build_array(jsonb_build_object('pendiente_id', p2, 'respuesta','hecho',
        'comentario','Vino el tecnico y se calibro el surtidor 2')));
    SELECT count(*) INTO n FROM v_comb_faena_pendientes_abiertos WHERE faena_id=f;
    PERFORM pg_temp.an(8, 'Al martes lo hacen y se cierra', n=0, n||' abiertos');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.an(8, 'Al martes lo hacen y se cierra', false, left(SQLERRM,66));
  END;

  SELECT count(*) INTO n FROM combustible_faena_pendiente_traspaso WHERE pendiente_id=p2;
  PERFORM pg_temp.an(9, 'Queda la cadena completa de quien lo dejo pasar',
                     n=3, n||' respuestas de turno');
END $b$;

SELECT n AS "#", rpad(escenario, 50) AS escenario,
       CASE WHEN ok THEN 'OK   ' ELSE 'FALLA' END AS res,
       left(COALESCE(det,''), 66) AS detalle
  FROM r ORDER BY n;

SELECT '=== LA CADENA, QUE ES LO QUE EL MANDANTE PIDE VER ===' AS paso;
SELECT left(texto, 44) AS pendiente, pedido_por,
       to_char(fecha,'DD-MM') AS dia, turno, respuesta,
       left(COALESCE(comentario,''), 46) AS dijo, respondido_por
  FROM v_comb_faena_pendiente_historia
 WHERE faena_id = (SELECT id FROM faenas WHERE codigo='FAE-CMP-ROMERAL')
   AND fecha IS NOT NULL
 ORDER BY pendiente, respondido_at;

SELECT count(*) FILTER (WHERE ok) || ' de ' || count(*) || ' escenarios OK'
       || CASE WHEN count(*) FILTER (WHERE NOT ok) > 0
               THEN '  ·  ' || count(*) FILTER (WHERE NOT ok) || ' FALLAS' ELSE '' END
       AS "RESULTADO" FROM r;

ROLLBACK;
