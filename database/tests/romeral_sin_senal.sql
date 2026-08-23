-- ============================================================================
-- Prueba de un turno completo sin señal
-- ----------------------------------------------------------------------------
-- Romeral tiene mala señal. No «a veces»: es la condición normal del lugar, y
-- todo lo que exija estar en línea a una hora fija se va a dejar de usar.
--
-- Esta prueba juega el peor día realista:
--
--   06:30  Llega el camión de flota primaria. No hay señal.
--   Turno  El operador carga equipos. Sigue sin señal.
--   18:00  El supervisor varilla y anota numerales. Sigue sin señal.
--   18:30  Cierra el turno en el teléfono, revisando las 2 cargas que alcanzó
--          a ver, y responde lo que quedó pendiente.
--   21:00  Vuelve la señal. Todo sube — pero mientras tanto OTRO operador
--          sincronizó una tercera carga que el supervisor nunca vio.
--
-- Lo que se verifica: que el turno cierre igual, que no se pierda nada, y que
-- la carga que el supervisor no alcanzó a ver quede MARCADA en vez de tumbar
-- el cierre. Un control que impide trabajar se desactiva; uno que muestra el
-- hueco se usa.
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
  c18 UUID := (SELECT id FROM combustible_estanques WHERE codigo='ROM-DJKL-18');
  DIA DATE := DATE '2026-09-14';
  pen UUID; o JSONB; n INT; t TEXT;
  varilla JSONB := jsonb_build_array(jsonb_build_object(
    'estanque_id', m1, 'mi', 22000, 'rfp', 30000, 'mf', 51200,
    'foto_url', 'local-subida-despues.jpg'));
BEGIN
  PERFORM pg_temp.como('supervisor');

  o := rpc_comb_pendiente_crear(f, 'Revisar el sello del surtidor 1 de Mina',
        'mandante', 'Karen (ESMAX)', 'alta');
  pen := (o->>'pendiente_id')::uuid;

  -- ══ 06:30 · el camion llega sin señal, sube a las 21:00 ══
  BEGIN
    o := rpc_comb_faena_recepcion(f, DIA,
      jsonb_build_array(jsonb_build_object('estanque_id', m1, 'litros', 30000)),
      'G-99120','2','JA5655','Copec',30000,'06:30','Supervisor Turno','SELLO-77',
      NULL,'https://x/guia.jpg',NULL,true,'rec-sin-senal', true);
    SELECT sin_senal INTO t FROM combustible_faena_recepcion WHERE client_uuid='rec-sin-senal';
    PERFORM pg_temp.an(1,'La recepcion tomada sin señal sube y queda marcada',
                       t::boolean, 'sin_senal='||t);
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.an(1,'La recepcion tomada sin señal sube y queda marcada',
                       false, left(SQLERRM,64));
  END;

  -- La cola reintenta: no puede duplicar.
  BEGIN
    o := rpc_comb_faena_recepcion(f, DIA,
      jsonb_build_array(jsonb_build_object('estanque_id', m1, 'litros', 30000)),
      'G-99120','2','JA5655','Copec',30000,'06:30','Supervisor Turno','SELLO-77',
      NULL,'https://x/guia.jpg',NULL,true,'rec-sin-senal', true);
    SELECT count(*) INTO n FROM combustible_faena_recepcion WHERE client_uuid='rec-sin-senal';
    PERFORM pg_temp.an(2,'La cola reintenta y no duplica la recepcion', n=1, n||' recepcion(es)');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.an(2,'La cola reintenta y no duplica la recepcion', false, left(SQLERRM,64));
  END;

  -- ══ Turno · dos cargas que el supervisor SI alcanzo a ver ══
  PERFORM rpc_comb_faena_despachar(f, DIA,'Día', c18, NULL, NULL, 0, 900, NULL,
    'Operador','09:00','CAT25',NULL,'DJKL-18',NULL,NULL,NULL,'ss-1',
    'https://x/a.jpg','https://x/b.jpg',NULL,'115037','venta','Flota Caex Romeral',NULL);
  PERFORM rpc_comb_faena_despachar(f, DIA,'Día', c18, NULL, NULL, 900, 1500, NULL,
    'Operador','12:00','CARG40',NULL,'DJKL-18',NULL,NULL,NULL,'ss-2',
    'https://x/c.jpg','https://x/d.jpg',NULL,'115202','venta','Flota Eq. Apoyo',NULL);

  -- ══ 21:00 · OTRO operador sincroniza una tercera carga que nadie vio ══
  PERFORM rpc_comb_faena_despachar(f, DIA,'Día', c18, NULL, NULL, 1500, 2100, NULL,
    'Otro operador','17:40','PERFO 23',NULL,'DJKL-18',NULL,NULL,NULL,'ss-3',
    'https://x/e.jpg','https://x/f.jpg',NULL,'115202','venta','Flota Eq. Apoyo',NULL);

  -- ══ Sube el cierre que se firmo en el telefono a las 18:30 ══
  BEGIN
    o := rpc_comb_faena_guardar_cierre(f, DIA, 'Día', 'Supervisor Turno', varilla,
      '[]'::jsonb, NULL, true, 'cierre-sin-senal',
      jsonb_build_object('despachos', 2, 'litros', 1500),
      jsonb_build_array(jsonb_build_object('pendiente_id', pen, 'respuesta','no_alcanzo',
        'comentario','Sin señal todo el turno, se revisa manana con el tecnico')),
      true);
    PERFORM pg_temp.an(3,'El cierre firmado sin señal sube igual',
                       (o->>'firmado')::boolean, 'cargas no vistas: '||(o->>'cargas_no_vistas'));
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.an(3,'El cierre firmado sin señal sube igual', false, left(SQLERRM,64));
  END;

  SELECT verificacion_delta INTO n FROM combustible_faena_cierre
   WHERE faena_id=f AND fecha=DIA AND turno='Día';
  PERFORM pg_temp.an(4,'Queda marcada la carga que el supervisor no vio',
                     n=1, 'delta='||COALESCE(n::text,'nulo'));

  SELECT count(*) INTO n FROM v_comb_faena_cierre_desactualizado WHERE fecha=DATE '2026-09-14';
  PERFORM pg_temp.an(5,'Aparece en la lista de cierres desactualizados', n=1, n||' cierre(s)');

  SELECT firmado_sin_senal INTO t FROM combustible_faena_cierre
   WHERE faena_id=f AND fecha=DIA AND turno='Día';
  PERFORM pg_temp.an(6,'Queda registrado que se cerro sin señal', t::boolean, 'sin_senal='||t);

  SELECT count(*) INTO n FROM combustible_faena_pendiente_traspaso WHERE pendiente_id=pen;
  PERFORM pg_temp.an(7,'El pendiente se respondio igual, sin señal', n=1, n||' respuesta(s)');

  -- ══ El mismo dia, pero EN LINEA: ahi si tiene que bloquear ══
  BEGIN
    o := rpc_comb_faena_guardar_cierre(f, DIA, 'Noche', 'Supervisor Noche', varilla,
      '[]'::jsonb, NULL, true, 'cierre-en-linea',
      jsonb_build_object('despachos', 2, 'litros', 1500),
      jsonb_build_array(jsonb_build_object('pendiente_id', pen, 'respuesta','hecho')),
      false);
    PERFORM pg_temp.an(8,'En linea, revisar de menos SI bloquea', false, 'LO DEJO FIRMAR');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.an(8,'En linea, revisar de menos SI bloquea',
                       SQLERRM LIKE '%vuelva a mirar%', left(SQLERRM,60));
  END;

  SELECT round(litros_recibidos) INTO n FROM v_comb_faena_control_diario
   WHERE faena_id=f AND fecha=DIA;
  PERFORM pg_temp.an(9,'Los 30.000 L del camion no se perdieron',
                     n=30000, COALESCE(n::text,'nulo')||' L recibidos');
END $b$;

SELECT n AS "#", rpad(escenario, 48) AS escenario,
       CASE WHEN ok THEN 'OK   ' ELSE 'FALLA' END AS res,
       left(COALESCE(det,''), 62) AS detalle
  FROM r ORDER BY n;

SELECT count(*) FILTER (WHERE ok) || ' de ' || count(*) || ' escenarios OK'
       || CASE WHEN count(*) FILTER (WHERE NOT ok) > 0
               THEN '  ·  ' || count(*) FILTER (WHERE NOT ok) || ' FALLAS' ELSE '' END
       AS "RESULTADO" FROM r;

ROLLBACK;
