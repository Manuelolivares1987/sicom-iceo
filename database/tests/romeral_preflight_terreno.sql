-- ============================================================================
-- Revisión previa a la entrega en terreno
-- ----------------------------------------------------------------------------
-- Lo que hay que poder responder ANTES de que un operador tenga el teléfono en
-- la mano: ¿ve lo que necesita? ¿puede hacer su trabajo? ¿y puede hacer, sin
-- querer, algo que no le corresponde?
--
-- Las dos preguntas pesan igual. Un sistema que le bloquea el trabajo al turno
-- se deja de usar el martes; uno que le deja reescribir un mes de imputación
-- desde la cabina de un camión se descubre cuando ya es tarde.
--
-- Corre en una transacción con ROLLBACK.
-- ============================================================================
BEGIN;
CREATE TEMP TABLE r(n int, paso text, ok boolean, det text);
CREATE OR REPLACE FUNCTION pg_temp.an(a int,b text,c boolean,d text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$ INSERT INTO r VALUES(a,b,c,d) $$;
CREATE OR REPLACE FUNCTION pg_temp.como(p text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v UUID; BEGIN
  SELECT id INTO v FROM usuarios_perfil WHERE rol::text=p AND activo LIMIT 1;
  PERFORM set_config('request.jwt.claims', json_build_object('sub',v::text,'role','authenticated')::text, true);
END $$;

DO $b$
DECLARE
  f UUID := (SELECT id FROM faenas WHERE codigo='FAE-CMP-ROMERAL');
  c18 UUID := (SELECT id FROM combustible_estanques WHERE codigo='ROM-DJKL-18');
  m1 UUID := (SELECT id FROM combustible_estanques WHERE codigo='ROM-MINA-1');
  n INT; o JSONB;
BEGIN
  PERFORM pg_temp.como('operador_combustible');

  SELECT count(*) INTO n FROM combustible_estanques WHERE faena_id=f AND activo;
  PERFORM pg_temp.an(1,'El operador ve los estanques de la faena', n>=5, n||' estanques');

  SELECT count(*) INTO n FROM combustible_faena_equipos WHERE faena_id=f AND activo;
  PERFORM pg_temp.an(2,'El operador ve el catalogo de equipos', n>0, n||' equipos');

  SELECT count(*) INTO n FROM combustible_faena_cecos WHERE faena_id=f AND activo;
  PERFORM pg_temp.an(3,'El operador ve los CECO', n>0, n||' CECO');

  SELECT count(*) INTO n FROM combustible_faena_medidores m
    JOIN combustible_estanques e ON e.id=m.estanque_id WHERE e.faena_id=f AND m.activo;
  PERFORM pg_temp.an(4,'El operador ve los cuentalitros', n>0, n||' contadores');

  BEGIN
    PERFORM rpc_comb_faena_despachar(f, DATE '2026-08-24','Día', c18, NULL, NULL,
      0, 400, NULL, 'Operador Camion', '08:00', 'CAT25', NULL, 'DJKL-18', NULL, NULL, NULL,
      'pre-1', 'https://x/a.jpg','https://x/b.jpg', NULL, '115037','venta','Flota Caex Romeral', NULL);
    PERFORM pg_temp.an(5,'El operador registra un despacho', true,'ok');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.an(5,'El operador registra un despacho', false, left(SQLERRM,70)); END;

  BEGIN
    o := rpc_comb_faena_guardar_cierre(f, DATE '2026-08-24','Día','Yusdel Sarduy',
      jsonb_build_array(jsonb_build_object('estanque_id',m1,'mi',47000,'mf',46600,'foto_url','https://x/v.jpg')),
      '[]'::jsonb, NULL, false, 'pre-c');
    PERFORM pg_temp.an(6,'El operador guarda el cierre como borrador', true,'ok');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.an(6,'El operador guarda el cierre como borrador', false, left(SQLERRM,70)); END;

  BEGIN
    o := rpc_comb_faena_guardar_cierre(f, DATE '2026-08-24','Día','Yusdel Sarduy',
      '[]'::jsonb, '[]'::jsonb, NULL, true, 'pre-c');
    PERFORM pg_temp.an(7,'El operador FIRMA el cierre del dia', true,'LO PERMITE');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.an(7,'El operador FIRMA el cierre del dia', false, left(SQLERRM,64)); END;

  BEGIN
    o := rpc_comb_faena_recepcion(f, DATE '2026-08-24',
      jsonb_build_array(jsonb_build_object('estanque_id', m1, 'litros', 20000)),
      '999','1','JA5655','Copec',20000,'07:00','Operador','SELLO-1',NULL,'https://x/g.jpg',NULL,false,'pre-r');
    PERFORM pg_temp.an(8,'El operador recibe la flota primaria', true,'LO PERMITE');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.an(8,'El operador recibe la flota primaria', false, left(SQLERRM,64)); END;

  BEGIN
    o := rpc_comb_orpak_cargar(f,'x','[]'::jsonb);
    PERFORM pg_temp.an(9,'El operador puede cargar Orpak', true,'lo permite');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.an(9,'El operador puede cargar Orpak', false, left(SQLERRM,60)); END;

  -- ── El supervisor de turno: recibe, mide, verifica y firma ──
  PERFORM pg_temp.como('supervisor');
  BEGIN
    o := rpc_comb_faena_recepcion(f, DATE '2026-08-24',
      jsonb_build_array(jsonb_build_object('estanque_id', m1, 'litros', 20000)),
      '999','1','JA5655','Copec',20000,'07:00','Supervisor','SELLO-1',NULL,'https://x/g.jpg',NULL,true,'pre-rs');
    PERFORM pg_temp.an(13,'El supervisor recibe la flota primaria', true,'ok');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.an(13,'El supervisor recibe la flota primaria', false, left(SQLERRM,64)); END;

  -- Deja una carga en el dia para que haya algo que verificar.
  PERFORM rpc_comb_faena_despachar(f, DATE '2026-08-25','Día', c18, NULL, NULL,
    0, 700, NULL, 'Operador', '10:00', 'CAT25', NULL, 'DJKL-18', NULL, NULL, NULL,
    'pre-v1', 'https://x/a.jpg','https://x/b.jpg', NULL, '115037','venta','Flota Caex Romeral', NULL);

  BEGIN
    o := rpc_comb_faena_guardar_cierre(f, DATE '2026-08-25','Día','Supervisor de turno',
      jsonb_build_array(jsonb_build_object('estanque_id',m1,'mi',47000,'mf',46300,'foto_url','https://x/v.jpg')),
      '[]'::jsonb, NULL, true, 'pre-v', jsonb_build_object('despachos', 5, 'litros', 9999));
    PERFORM pg_temp.an(14,'Firma diciendo que reviso 5 cargas y hay 1', true,'LO PERMITE');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.an(14,'Firma diciendo que reviso 5 cargas y hay 1', false, left(SQLERRM,64)); END;

  BEGIN
    o := rpc_comb_faena_guardar_cierre(f, DATE '2026-08-25','Día','Supervisor de turno',
      jsonb_build_array(jsonb_build_object('estanque_id',m1,'mi',47000,'mf',46300,'foto_url','https://x/v.jpg')),
      '[]'::jsonb, NULL, true, 'pre-v', jsonb_build_object('despachos', 1, 'litros', 700));
    SELECT count(*) INTO n FROM combustible_faena_cierre
     WHERE faena_id=f AND fecha=DATE '2026-08-25' AND verificado_at IS NOT NULL;
    PERFORM pg_temp.an(15,'Firma verificando la carga que realmente hay', n=1, 'verificado='||n);
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.an(15,'Firma verificando la carga que realmente hay', false, left(SQLERRM,64)); END;

  -- Quien no opera combustible no registra despachos: ese registro es la
  -- evidencia con la que se le cobra al mandante.
  PERFORM pg_temp.como('prevencionista');
  BEGIN
    PERFORM rpc_comb_faena_despachar(f, DATE '2026-08-24','Día', c18, NULL, NULL,
      400, 500, NULL, 'Prevencionista', '09:00', 'CAT25', NULL, 'DJKL-18', NULL, NULL, NULL,
      'pre-3', 'https://x/a.jpg','https://x/b.jpg', NULL, '115037','venta',NULL, NULL);
    PERFORM pg_temp.an(11,'Un prevencionista registra un despacho', true,'LO PERMITE');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.an(11,'Un prevencionista registra un despacho', false, left(SQLERRM,60)); END;

  -- Solo debe existir UNA version del RPC de despacho. Una firma vieja que
  -- sobreviva la puede llamar un telefono con la app cacheada, y como
  -- tipo_movimiento tiene DEFAULT 'venta', un trasvasije se guardaria como
  -- venta: el Ejemplo 1 del instructivo.
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public' AND p.proname='rpc_comb_faena_despachar';
  PERFORM pg_temp.an(12,'Existe una sola version del RPC de despacho', n=1, n||' version(es)');

  -- Alguien sin rol de combustible
  PERFORM pg_temp.como('bodeguero');
  BEGIN
    PERFORM rpc_comb_faena_despachar(f, DATE '2026-08-24','Día', c18, NULL, NULL,
      400, 500, NULL, 'Bodeguero', '09:00', 'CAT25', NULL, 'DJKL-18', NULL, NULL, NULL,
      'pre-2', 'https://x/a.jpg','https://x/b.jpg', NULL, '115037','venta',NULL, NULL);
    PERFORM pg_temp.an(10,'Un bodeguero registra un despacho de combustible', true,'lo permite');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.an(10,'Un bodeguero registra un despacho de combustible', false, left(SQLERRM,60)); END;
END $b$;

SELECT n AS "#", rpad(paso,52) AS paso,
       CASE WHEN ok THEN 'SI ' ELSE 'NO ' END AS puede, left(COALESCE(det,''),62) AS detalle
FROM r ORDER BY n;
ROLLBACK;
