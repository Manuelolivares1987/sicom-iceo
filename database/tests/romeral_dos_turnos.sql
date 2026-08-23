-- ============================================================================
-- Prueba de un día con turno de día y turno de noche
-- ----------------------------------------------------------------------------
-- En Romeral se trabaja 4x4 con dos turnos. Eso cambia cosas que con un turno
-- por día no se notan:
--
--   · el turno de noche arranca del nivel que le dejó el de día, no del de ayer
--   · cada supervisor firma por SUS cargas, no por las del día completo
--   · el día no está cerrado si le falta un turno
--   · lo que queda pendiente cruza del día a la noche y de la noche al día
--
-- La prueba juega un día completo con los dos turnos y el relevo entre ellos.
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
  fa  UUID := (SELECT id FROM faenas WHERE codigo='FAE-CMP-ROMERAL');
  m1  UUID := (SELECT id FROM combustible_estanques WHERE codigo='ROM-MINA-1');
  c18 UUID := (SELECT id FROM combustible_estanques WHERE codigo='ROM-DJKL-18');
  md1 UUID := (SELECT m.id FROM combustible_faena_medidores m WHERE m.estanque_id=m1 ORDER BY m.orden LIMIT 1);
  DIA DATE := DATE '2026-10-05';
  pen UUID; o JSONB; n INT; t TEXT; v NUMERIC;
BEGIN
  PERFORM pg_temp.como('supervisor');

  o := rpc_comb_pendiente_crear(fa, 'Drenar el agua de Mina 1 antes del proximo despacho',
        'mandante', 'Karen (ESMAX)', 'alta');
  pen := (o->>'pendiente_id')::uuid;

  -- ══ TURNO DE DIA ══ arranca en 40.000, despacha 900, cierra en 39.100
  PERFORM rpc_comb_faena_despachar(fa, DIA,'Día', c18, NULL, NULL, 0, 900, NULL,
    'Operador dia','10:00','CAT25',NULL,'DJKL-18',NULL,NULL,NULL,'t2-d1',
    'https://x/a.jpg','https://x/b.jpg',NULL,'115037','venta','Flota Caex Romeral',NULL);

  o := rpc_comb_faena_guardar_cierre(fa, DIA, 'Día', 'Supervisor DIA',
    jsonb_build_array(jsonb_build_object('estanque_id',m1,'mi',40000,'mf',39100,
                                         'agua_mm',4,'foto_url','https://x/v1.jpg')),
    jsonb_build_array(jsonb_build_object('medidor_id',md1,'numeral_ini',30000000,
                                         'numeral_fin',30000900,'foto_url','https://x/c1.jpg')),
    NULL, true, 't2-cd', jsonb_build_object('despachos',1,'litros',900),
    jsonb_build_array(jsonb_build_object('pendiente_id',pen,'respuesta','no_alcanzo',
      'comentario','No alcanzamos, queda para el turno de noche')), false);
  PERFORM pg_temp.an(1,'El turno de dia cierra con sus 1 carga',
                     (o->>'firmado')::boolean, 'cargas no vistas: '||(o->>'cargas_no_vistas'));

  -- ══ El de noche arranca: ¿de que nivel? ══
  SELECT mf INTO v FROM rpc_comb_medicion_del_turno_anterior(fa, DIA, 'Noche')
   WHERE estanque_id = m1;
  PERFORM pg_temp.an(2,'La noche arranca del nivel que dejo el dia',
                     v = 39100, 'le ofrece '||COALESCE(v::text,'nada')||' L (el dia dejo 39.100)');

  SELECT medido_por INTO t FROM rpc_comb_medicion_del_turno_anterior(fa, DIA, 'Noche')
   WHERE estanque_id = m1;
  PERFORM pg_temp.an(3,'Y sabe de quien recibe', t = 'Supervisor DIA', 'recibe de: '||COALESCE(t,'nadie'));

  -- ══ TURNO DE NOCHE ══ dos cargas propias
  PERFORM rpc_comb_faena_despachar(fa, DIA,'Noche', c18, NULL, NULL, 900, 1500, NULL,
    'Operador noche','21:00','CARG40',NULL,'DJKL-18',NULL,NULL,NULL,'t2-n1',
    'https://x/c.jpg','https://x/d.jpg',NULL,'115202','venta','Flota Eq. Apoyo',NULL);
  PERFORM rpc_comb_faena_despachar(fa, DIA,'Noche', c18, NULL, NULL, 1500, 1900, NULL,
    'Operador noche','23:30','PERFO 23',NULL,'DJKL-18',NULL,NULL,NULL,'t2-n2',
    'https://x/e.jpg','https://x/f.jpg',NULL,'115202','venta','Flota Eq. Apoyo',NULL);

  -- El de noche firma diciendo que reviso las 3 del dia completo: tiene 2.
  BEGIN
    o := rpc_comb_faena_guardar_cierre(fa, DIA, 'Noche', 'Supervisor NOCHE',
      jsonb_build_array(jsonb_build_object('estanque_id',m1,'mi',39100,'mf',38100,
                                           'foto_url','https://x/v2.jpg')),
      '[]'::jsonb, NULL, true, 't2-cn', jsonb_build_object('despachos',3,'litros',2800),
      jsonb_build_array(jsonb_build_object('pendiente_id',pen,'respuesta','hecho',
        'comentario','Drenado en la noche')), false);
    PERFORM pg_temp.an(4,'Firmar por las cargas del OTRO turno queda bloqueado',
                       false, 'LO DEJO FIRMAR POR LAS 3');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.an(4,'Firmar por las cargas del OTRO turno queda bloqueado',
                       SQLERRM LIKE '%el turno tiene 2%', left(SQLERRM,60));
  END;

  -- Ahora con las suyas
  o := rpc_comb_faena_guardar_cierre(fa, DIA, 'Noche', 'Supervisor NOCHE',
    jsonb_build_array(jsonb_build_object('estanque_id',m1,'mi',39100,'mf',38100,
                                         'foto_url','https://x/v2.jpg')),
    '[]'::jsonb, NULL, true, 't2-cn', jsonb_build_object('despachos',2,'litros',1000),
    jsonb_build_array(jsonb_build_object('pendiente_id',pen,'respuesta','hecho',
      'comentario','Drenado en la noche')), false);
  PERFORM pg_temp.an(5,'El turno de noche firma por SUS 2 cargas',
                     (o->>'firmado')::boolean, 'firmado');

  -- ══ El dia completo ══
  SELECT turnos, turnos_firmados INTO n, t FROM v_comb_faena_turnos_del_dia
   WHERE faena_id=fa AND fecha=DIA;
  PERFORM pg_temp.an(6,'El dia tiene los dos turnos cerrados', n=2, n||' turnos');

  SELECT volumen_estado INTO t FROM v_comb_faena_control_diario
   WHERE faena_id=fa AND fecha=DIA;
  PERFORM pg_temp.an(7,'Con los dos turnos firmados el dia queda cerrado',
                     t <> 'borrador', 'estado del dia: '||COALESCE(t,'nulo'));

  SELECT despachos INTO n FROM v_comb_faena_control_diario WHERE faena_id=fa AND fecha=DIA;
  PERFORM pg_temp.an(8,'El dia suma las cargas de los dos turnos', n=3, n||' cargas en el dia');

  -- ══ El pendiente cruzo del dia a la noche y se cerro ══
  SELECT count(*) INTO n FROM combustible_faena_pendiente_traspaso WHERE pendiente_id=pen;
  PERFORM pg_temp.an(9,'El pendiente cruzo del dia a la noche', n=2, n||' respuestas de turno');

  SELECT estado INTO t FROM combustible_faena_pendiente WHERE id=pen;
  PERFORM pg_temp.an(10,'Y la noche lo cerro', t='cerrado', 'estado: '||t);

  -- ══ Con un turno abierto el dia NO puede verse cerrado ══
  UPDATE combustible_faena_cierre SET estado='borrador'
   WHERE faena_id=fa AND fecha=DIA AND turno='Noche';
  SELECT volumen_estado INTO t FROM v_comb_faena_control_diario WHERE faena_id=fa AND fecha=DIA;
  PERFORM pg_temp.an(11,'Con la noche abierta, el dia NO aparece cerrado',
                     t='borrador', 'estado del dia: '||COALESCE(t,'nulo'));

  SELECT detalle INTO t FROM v_comb_faena_turnos_del_dia WHERE faena_id=fa AND fecha=DIA;
  PERFORM pg_temp.an(12,'Y dice cual turno falta', t LIKE '%sin firmar%', t);
END $b$;

SELECT n AS "#", rpad(escenario, 50) AS escenario,
       CASE WHEN ok THEN 'OK   ' ELSE 'FALLA' END AS res,
       left(COALESCE(det,''), 58) AS detalle
  FROM r ORDER BY n;

SELECT count(*) FILTER (WHERE ok) || ' de ' || count(*) || ' escenarios OK'
       || CASE WHEN count(*) FILTER (WHERE NOT ok) > 0
               THEN '  ·  ' || count(*) FILTER (WHERE NOT ok) || ' FALLAS' ELSE '' END
       AS "RESULTADO" FROM r;

ROLLBACK;
