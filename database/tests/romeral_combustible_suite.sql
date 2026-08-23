BEGIN;
SELECT set_config('request.jwt.claims',
  json_build_object('sub',(SELECT u.id::text FROM usuarios_perfil u WHERE u.rol='supervisor' AND u.activo LIMIT 1),
                    'role','authenticated')::text, true);
DO $$
DECLARE
  v_faena UUID := (SELECT f.id FROM faenas f WHERE f.codigo='FAE-CMP-ROMERAL');
  v_c18   UUID := (SELECT e.id FROM combustible_estanques e WHERE e.codigo='ROM-DJKL-18');
  v_c67   UUID := (SELECT e.id FROM combustible_estanques e WHERE e.codigo='ROM-FSLZ-67');
  v_mina1 UUID := (SELECT e.id FROM combustible_estanques e WHERE e.codigo='ROM-MINA-1');
  v_m18   UUID := (SELECT m.id FROM combustible_faena_medidores m JOIN combustible_estanques e ON e.id=m.estanque_id WHERE e.codigo='ROM-DJKL-18');
  v_mA    UUID := (SELECT m.id FROM combustible_faena_medidores m JOIN combustible_estanques e ON e.id=m.estanque_id WHERE e.codigo='ROM-MINA-1');
  v_mina2 UUID := (SELECT e.id FROM combustible_estanques e WHERE e.codigo='ROM-MINA-2');
  v_mB    UUID := (SELECT m.id FROM combustible_faena_medidores m JOIN combustible_estanques e ON e.id=m.estanque_id WHERE e.codigo='ROM-MINA-2');
  v_out JSONB; v_id UUID; v_ok INT := 0; v_fail INT := 0;
  PROCEDURE_ok BOOLEAN;
BEGIN
  -- T1 · contador que retrocede
  BEGIN
    PERFORM rpc_comb_faena_guardar_cierre(v_faena, DATE '2026-08-19','Día','T','[]'::jsonb,
      jsonb_build_array(jsonb_build_object('medidor_id',v_m18,'numeral_ini',100,'numeral_fin',50)),
      NULL,false,'t1');
    v_fail:=v_fail+1; RAISE NOTICE 'T1 ✗ acepto contador que retrocede';
  EXCEPTION WHEN OTHERS THEN v_ok:=v_ok+1; RAISE NOTICE 'T1 ✓ contador que retrocede rechazado';
  END;

  -- T2 · firmar sin foto
  BEGIN
    PERFORM rpc_comb_faena_guardar_cierre(v_faena, DATE '2026-08-19','Día','T',
      jsonb_build_array(jsonb_build_object('estanque_id',v_c18,'mi',1000,'mf',500)),
      '[]'::jsonb, NULL,true,'t2');
    v_fail:=v_fail+1; RAISE NOTICE 'T2 ✗ firmo sin foto';
  EXCEPTION WHEN OTHERS THEN v_ok:=v_ok+1; RAISE NOTICE 'T2 ✓ firma sin foto rechazada';
  END;

  -- T3 · firmar sin nombre de quien midió
  BEGIN
    PERFORM rpc_comb_faena_guardar_cierre(v_faena, DATE '2026-08-18','Día',NULL,
      jsonb_build_array(jsonb_build_object('estanque_id',v_c18,'mi',1000,'mf',500,'foto_url','x')),
      '[]'::jsonb, NULL,true,'t3');
    v_fail:=v_fail+1; RAISE NOTICE 'T3 ✗ firmo sin nombre';
  EXCEPTION WHEN OTHERS THEN v_ok:=v_ok+1; RAISE NOTICE 'T3 ✓ firma sin nombre rechazada';
  END;

  -- T4 · reabrir un cierre firmado sin permiso
  PERFORM rpc_comb_faena_guardar_cierre(v_faena, DATE '2026-08-17','Día','T',
    jsonb_build_array(jsonb_build_object('estanque_id',v_c18,'mi',1000,'mf',500,'foto_url','x')),
    jsonb_build_array(jsonb_build_object('medidor_id',v_m18,'numeral_ini',0,'numeral_fin',500,'foto_url','y')),
    NULL,true,'t4');
  BEGIN
    PERFORM rpc_comb_faena_guardar_cierre(v_faena, DATE '2026-08-17','Día','T',
      jsonb_build_array(jsonb_build_object('estanque_id',v_c18,'mi',9999,'mf',1)),
      '[]'::jsonb, NULL,false,'t4');
    v_fail:=v_fail+1; RAISE NOTICE 'T4 ✗ reescribio un cierre firmado';
  EXCEPTION WHEN OTHERS THEN v_ok:=v_ok+1; RAISE NOTICE 'T4 ✓ cierre firmado protegido';
  END;

  -- T5 · litros negativos en despacho
  BEGIN
    PERFORM rpc_comb_faena_despachar(v_faena, DATE '2026-08-19','Día',v_c18,NULL,NULL,
      NULL,NULL,-50,'T',NULL,'X',NULL,NULL,NULL,NULL,NULL,'t5',NULL,NULL,NULL,NULL,'venta',NULL,NULL);
    v_fail:=v_fail+1; RAISE NOTICE 'T5 ✗ acepto litros negativos';
  EXCEPTION WHEN OTHERS THEN v_ok:=v_ok+1; RAISE NOTICE 'T5 ✓ litros negativos rechazados';
  END;

  -- T6 · reintento de despacho no duplica
  PERFORM rpc_comb_faena_despachar(v_faena, DATE '2026-08-19','Día',v_c18,NULL,NULL,
    NULL,NULL,111,'T',NULL,'EQ TEST',NULL,NULL,NULL,NULL,NULL,'t6',NULL,NULL,NULL,'777001','venta',NULL,NULL);
  PERFORM rpc_comb_faena_despachar(v_faena, DATE '2026-08-19','Día',v_c18,NULL,NULL,
    NULL,NULL,111,'T',NULL,'EQ TEST',NULL,NULL,NULL,NULL,NULL,'t6',NULL,NULL,NULL,'777001','venta',NULL,NULL);
  IF (SELECT count(*) FROM combustible_faena_despachos WHERE client_uuid='t6') = 1
     THEN v_ok:=v_ok+1; RAISE NOTICE 'T6 ✓ reintento no duplica';
     ELSE v_fail:=v_fail+1; RAISE NOTICE 'T6 ✗ duplico el despacho'; END IF;

  -- T7 · el CECO anotado no se duplica
  IF (SELECT count(*) FROM combustible_faena_cecos WHERE codigo='777001') = 1
     THEN v_ok:=v_ok+1; RAISE NOTICE 'T7 ✓ CECO anotado unico';
     ELSE v_fail:=v_fail+1; RAISE NOTICE 'T7 ✗ CECO duplicado'; END IF;

  -- T8 · confirmar CECO con rol supervisor
  SELECT id INTO v_id FROM combustible_faena_cecos WHERE codigo='777001';
  BEGIN
    v_out := rpc_comb_faena_confirmar_ceco(v_id, NULL, 'Empresa Prueba');
    v_ok:=v_ok+1; RAISE NOTICE 'T8 ✓ supervisor confirma CECO: %', v_out;
  EXCEPTION WHEN OTHERS THEN v_fail:=v_fail+1; RAISE NOTICE 'T8 ✗ supervisor no pudo: %', SQLERRM;
  END;

  -- T9 · recepcion con reparto a dos estanques
  v_out := rpc_comb_faena_recepcion(v_faena, DATE '2026-08-19',
    jsonb_build_array(jsonb_build_object('estanque_id',v_mina1,'litros',20000),
                      jsonb_build_object('estanque_id',v_c18,'litros',5000)),
    'G-1',NULL,'JA5655',NULL,25000,NULL,'T',NULL,NULL,'https://x/g.jpg',NULL,true,'t9');
  IF (v_out->>'litros_recibidos')::numeric = 25000 AND (v_out->>'diferencia_vs_guia')::numeric = 0
     THEN v_ok:=v_ok+1; RAISE NOTICE 'T9 ✓ reparto a dos estanques cuadra';
     ELSE v_fail:=v_fail+1; RAISE NOTICE 'T9 ✗ reparto mal: %', v_out; END IF;

  -- T10 · punto con TODOS sus contadores leidos y dentro de tolerancia
  PERFORM rpc_comb_faena_guardar_cierre(v_faena, DATE '2026-08-16','Día','T',
    jsonb_build_array(
      jsonb_build_object('estanque_id',v_mina1,'mi',50000,'mf',44000,'foto_url','x'),
      jsonb_build_object('estanque_id',v_mina2,'mi',20000,'mf',16000,'foto_url','x')),
    jsonb_build_array(
      jsonb_build_object('medidor_id',v_mA,'numeral_ini',0,'numeral_fin',6000,'foto_url','y'),
      jsonb_build_object('medidor_id',v_mB,'numeral_ini',0,'numeral_fin',4020,'foto_url','y')),
    NULL,true,'t10');
  IF (SELECT volumen_estado FROM v_comb_faena_control_diario WHERE fecha=DATE '2026-08-16') = 'cuadrado'
     THEN v_ok:=v_ok+1; RAISE NOTICE 'T10 ✓ isla Mina cuadrada por grupo (dif 20 L sobre 10.000)';
     ELSE v_fail:=v_fail+1; RAISE NOTICE 'T10 ✗ estado: %', (SELECT volumen_estado FROM v_comb_faena_control_diario WHERE fecha=DATE '2026-08-16'); END IF;

  -- T11 · el caso real de junio: cada tanque descuadra por miles, el grupo cuadra
  PERFORM rpc_comb_faena_guardar_cierre(v_faena, DATE '2026-08-15','Día','T',
    jsonb_build_array(
      jsonb_build_object('estanque_id',v_mina1,'mi',60000,'mf',53500,'foto_url','x'),
      jsonb_build_object('estanque_id',v_mina2,'mi',25000,'mf',19200,'foto_url','x')),
    jsonb_build_array(
      jsonb_build_object('medidor_id',v_mA,'numeral_ini',0,'numeral_fin',11678,'foto_url','y'),
      jsonb_build_object('medidor_id',v_mB,'numeral_ini',0,'numeral_fin',688,'foto_url','y')),
    NULL,true,'t11');
  IF (SELECT resultado FROM v_comb_faena_cuadre_grupo WHERE fecha=DATE '2026-08-15' AND grupo='mina') = 'cuadra'
     THEN v_ok:=v_ok+1; RAISE NOTICE 'T11 ✓ tanques que se anulan (+5178 / -5112) cuadran agrupados: dif %',
       (SELECT round(var1) FROM v_comb_faena_cuadre_grupo WHERE fecha=DATE '2026-08-15' AND grupo='mina');
     ELSE v_fail:=v_fail+1; RAISE NOTICE 'T11 ✗ %',
       (SELECT resultado||' dif '||round(var1) FROM v_comb_faena_cuadre_grupo WHERE fecha=DATE '2026-08-15' AND grupo='mina'); END IF;

  -- T12 · una diferencia real de 800 L debe seguir saltando
  PERFORM rpc_comb_faena_guardar_cierre(v_faena, DATE '2026-08-14','Día','T',
    jsonb_build_array(jsonb_build_object('estanque_id',v_c18,'mi',10000,'mf',5000,'foto_url','x')),
    jsonb_build_array(jsonb_build_object('medidor_id',v_m18,'numeral_ini',0,'numeral_fin',5800,'foto_url','y')),
    NULL,true,'t12');
  IF (SELECT resultado FROM v_comb_faena_cuadre_grupo WHERE fecha=DATE '2026-08-14' AND grupo='djkl18') = 'investigar'
     THEN v_ok:=v_ok+1; RAISE NOTICE 'T12 ✓ diferencia real de 800 L salta como investigar';
     ELSE v_fail:=v_fail+1; RAISE NOTICE 'T12 ✗ no salto'; END IF;

  RAISE NOTICE '';
  RAISE NOTICE '═══════ RESULTADO: % OK · % FALLAS ═══════', v_ok, v_fail;
END $$;
ROLLBACK;
