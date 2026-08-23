-- ============================================================================
-- Prueba de punta a punta: un día completo de Romeral
-- ----------------------------------------------------------------------------
-- Simula el 12-08-2026 con los actores reales y en el orden real: llega el
-- camión de flota primaria, el aljibe se carga desde Mina, sale a terreno a
-- abastecer equipos, y a las 18:00 el encargado de estación varilla y anota
-- numerales. Todo dentro de una transacción que hace ROLLBACK: producción no
-- se toca.
--
-- Los números están construidos para que el cuadre DEBA dar bien:
--   Mina 1:  38.400 + 30.000 recibidos − 12.000 al camión − 6.100 a equipos
--            = 50.300  ·  contador Mina 1: +18.100 (el trasvasije al aljibe
--            TAMBIÉN pasa por el cuentalitros — verificado con junio 2026)
--   Mina 2:  16.700 − 800  = 15.900      ·  contador Mina 2: +770
--   Grupo Mina: varilla 18.900 vs contador 18.870 → dif −30 L → cuadra
--   Camión 18: 1.320 + 12.000 − 3.437 = 9.883  ·  contador: +3.437 → dif 0
-- ============================================================================
BEGIN;

SELECT set_config('request.jwt.claims',
  json_build_object('sub',(SELECT u.id::text FROM usuarios_perfil u WHERE u.rol='supervisor' AND u.activo LIMIT 1),
                    'role','authenticated')::text, true);

DO $blk$
DECLARE
  v_faena UUID := (SELECT f.id FROM faenas f WHERE f.codigo='FAE-CMP-ROMERAL');
  v_mina1 UUID := (SELECT e.id FROM combustible_estanques e WHERE e.codigo='ROM-MINA-1');
  v_mina2 UUID := (SELECT e.id FROM combustible_estanques e WHERE e.codigo='ROM-MINA-2');
  v_bim   UUID := (SELECT e.id FROM combustible_estanques e WHERE e.codigo='ROM-BIMODAL');
  v_c18   UUID := (SELECT e.id FROM combustible_estanques e WHERE e.codigo='ROM-DJKL-18');
  v_c67   UUID := (SELECT e.id FROM combustible_estanques e WHERE e.codigo='ROM-FSLZ-67');
  v_eq    UUID := (SELECT q.id FROM combustible_faena_equipos q WHERE q.faena_id=v_faena AND q.ceco_id IS NOT NULL LIMIT 1);
  m_mina1 UUID := (SELECT m.id FROM combustible_faena_medidores m JOIN combustible_estanques e ON e.id=m.estanque_id WHERE e.codigo='ROM-MINA-1');
  m_mina2 UUID := (SELECT m.id FROM combustible_faena_medidores m JOIN combustible_estanques e ON e.id=m.estanque_id WHERE e.codigo='ROM-MINA-2');
  m_c18   UUID := (SELECT m.id FROM combustible_faena_medidores m JOIN combustible_estanques e ON e.id=m.estanque_id WHERE e.codigo='ROM-DJKL-18');
  v_bimm  UUID;
  v_out   JSONB;
BEGIN
  RAISE NOTICE 'DIA COMPLETO EN ROMERAL - 12-08-2026';

  -- 06:30 Recepción de flota primaria
  v_out := rpc_comb_faena_recepcion(v_faena, DATE '2026-08-12',
    jsonb_build_array(jsonb_build_object('estanque_id', v_mina1, 'litros', 30000)),
    '24500101','2070001','JA5655','Copec',30000,'06:30','Pedro Soto','SELLO-4471',
    NULL,'https://x/guia.jpg',NULL,true,'dia-rec-1');
  RAISE NOTICE '06:30  Recepcion JA5655: % L recibidos, dif vs guia %',
    v_out->>'litros_recibidos', COALESCE(v_out->>'diferencia_vs_guia','-');

  -- 07:00 Trasvasije de Mina al camión: NO es venta
  v_out := rpc_comb_faena_despachar(v_faena, DATE '2026-08-12','Dia', v_mina1, NULL, NULL,
    NULL,NULL, 12000, 'Juan Perez','07:00','DJKL-18',NULL,NULL,NULL,NULL,NULL,'dia-tr-1',
    NULL,NULL,NULL, NULL, 'trasvasije', NULL, v_c18);
  RAISE NOTICE '07:00  Trasvasije Mina -> camion 18: % L, ceco %',
    v_out->>'litros', COALESCE(v_out->>'ceco_id','ninguno (correcto: no es venta)');

  -- 08:00 a 16:00 El camión abastece equipos
  PERFORM rpc_comb_faena_despachar(v_faena, DATE '2026-08-12','Dia', v_c18, v_eq, NULL,
    0, 850, NULL, 'Juan Perez','08:20',NULL,NULL,'DJKL-18',NULL,NULL,NULL,'dia-d-1',
    'https://x/a.jpg','https://x/b.jpg',NULL, NULL, 'venta','Flota CMP', NULL);
  PERFORM rpc_comb_faena_despachar(v_faena, DATE '2026-08-12','Dia', v_c18, NULL, NULL,
    850, 1290, NULL, 'Juan Perez','09:45','GEN TRIGO',NULL,'DJKL-18',NULL,NULL,NULL,'dia-d-2',
    'https://x/c.jpg','https://x/d.jpg',NULL, '115037', 'venta','Flota Tag Maestro', NULL);
  PERFORM rpc_comb_faena_despachar(v_faena, DATE '2026-08-12','Dia', v_c18, NULL, NULL,
    1290, 1780, NULL, 'Juan Perez','11:10','LUMI IP 208',NULL,'DJKL-18',NULL,NULL,NULL,'dia-d-3',
    'https://x/e.jpg','https://x/f.jpg',NULL, '999777', 'venta','Flota Tag Maestro', NULL);
  PERFORM rpc_comb_faena_despachar(v_faena, DATE '2026-08-12','Dia', v_c18, NULL, NULL,
    1780, 3200, NULL, 'Juan Perez','14:30','SE276',NULL,'DJKL-18',NULL,NULL,NULL,'dia-d-4',
    'https://x/g.jpg','https://x/h.jpg',NULL, '115037', 'venta','Flota contratista', NULL);
  PERFORM rpc_comb_faena_despachar(v_faena, DATE '2026-08-12','Dia', v_c18, NULL, NULL,
    3200, 3437, NULL, 'Juan Perez','16:05','GEN OLIVO',NULL,'DJKL-18',NULL,NULL,NULL,'dia-d-5',
    'https://x/i.jpg','https://x/j.jpg',NULL, NULL, 'venta','Flota Tag Maestro', NULL);
  RAISE NOTICE '08-16h  5 cargas a equipos, medidor del camion 0 -> 3437';

  -- 18:00 Cierre físico
  SELECT m.id INTO v_bimm FROM combustible_faena_medidores m
    JOIN combustible_estanques e ON e.id=m.estanque_id WHERE e.codigo='ROM-BIMODAL' ORDER BY m.orden LIMIT 1;

  v_out := rpc_comb_faena_guardar_cierre(v_faena, DATE '2026-08-12','Dia','Yusdel Sarduy',
    jsonb_build_array(
      jsonb_build_object('estanque_id',v_mina1,'mi',38400,'rfp',30000,'mf',50300,
                         'agua_mm',3,'temperatura_c',18,'densidad_api',36.5,'foto_url','https://x/v1.jpg'),
      jsonb_build_object('estanque_id',v_mina2,'mi',16700,'mf',15900,
                         'agua_mm',2,'temperatura_c',18,'foto_url','https://x/v2.jpg'),
      jsonb_build_object('estanque_id',v_bim,'mi',44150,'mf',42800,
                         'agua_mm',1,'temperatura_c',17,'foto_url','https://x/v3.jpg'),
      jsonb_build_object('estanque_id',v_c18,'mi',1320,'rt',12000,'mf',9883,'foto_url','https://x/v4.jpg'),
      jsonb_build_object('estanque_id',v_c67,'sin_medicion',true,
                         'motivo_sin_medicion','Camion en Coquimbo por mantencion')
    ),
    jsonb_build_array(
      jsonb_build_object('medidor_id',m_mina1,'numeral_ini',24400737,'numeral_fin',24418837,'foto_url','https://x/c1.jpg'),
      jsonb_build_object('medidor_id',m_mina2,'numeral_ini',20100472,'numeral_fin',20101242,'foto_url','https://x/c2.jpg'),
      jsonb_build_object('medidor_id',v_bimm,'numeral_ini',4578797,'numeral_fin',4580150,'foto_url','https://x/c3.jpg'),
      jsonb_build_object('medidor_id',m_c18,'numeral_ini',2794371,'numeral_fin',2797808,'foto_url','https://x/c4.jpg')
    ),
    'Camion 67 fuera de faena. Agua en Mina 1: 3 mm.', true, 'dia-cierre-1');
  RAISE NOTICE '18:00  Cierre firmado: %', v_out;
END $blk$;

SELECT '=== 1. CUADRE POR GRUPO ===' AS paso;
SELECT grupo, tanques, round(v_fis) varilla, round(v_mec) contador, round(var1) dif,
       medidores_leidos || '/' || medidores_total AS contadores, resultado
  FROM v_comb_faena_cuadre_grupo WHERE fecha = DATE '2026-08-12' ORDER BY grupo;

SELECT '=== 2. CONTROL DIARIO ===' AS paso;
SELECT volumen_estado, puntos_medidos || '/' || puntos_total AS puntos,
       puntos_fuera_tolerancia AS investigar, grupos_atencion AS atencion,
       imputacion_estado, despachos, round(litros_venta) ventas,
       round(litros_trasvasije) trasvasije, sin_ceco,
       recepciones, round(litros_recibidos) recibido, medido_por
  FROM v_comb_faena_control_diario WHERE fecha = DATE '2026-08-12';

SELECT '=== 3. EXCEPCIONES ===' AS paso;
SELECT tipo, referencia, left(detalle, 58) AS detalle
  FROM v_comb_faena_excepciones ORDER BY tipo;

SELECT '=== 4. EVIDENCIA FOTOGRAFICA ===' AS paso;
SELECT puntos_medidos, puntos_con_foto, puntos_no_medidos,
       medidores_leidos, medidores_con_foto
  FROM v_comb_faena_evidencia WHERE fecha = DATE '2026-08-12';

SELECT '=== 5. CTL POR TEMPERATURA (18 C, API 36.5) ===' AS paso;
SELECT round(fn_comb_ctl(36.5, 18, 15)::numeric, 5) AS ctl,
       round((6100 * fn_comb_ctl(36.5, 18, 15))::numeric, 1) AS litros_a_15c,
       round((6100 - 6100 * fn_comb_ctl(36.5, 18, 15))::numeric, 1) AS diferencia_lt;

ROLLBACK;
