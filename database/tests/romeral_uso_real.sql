-- ============================================================================
-- Prueba de uso real: lo que pasa cuando lo usa gente, no un script
-- ----------------------------------------------------------------------------
-- La prueba de punta a punta anterior simulaba un día que sale bien. Un día que
-- sale bien no prueba casi nada. Esta prueba juega lo que de verdad ocurre en
-- un turno: el operador se equivoca, la app reintenta sola, dos personas graban
-- lo mismo, alguien firma antes de tiempo, se cambia un cuentalitros, y el
-- teléfono manda la carga cuando vuelve la señal, tres horas después.
--
-- Cada escenario dice qué DEBE pasar. Si el sistema deja pasar algo que no
-- debería, o bloquea algo que sí debería poder hacerse, es una falla — y las
-- dos cosas cuestan igual: un sistema que estorba se deja de usar tan rápido
-- como uno que miente.
--
-- Todo corre dentro de una transacción con ROLLBACK.
-- ============================================================================

BEGIN;

CREATE TEMP TABLE resultado (n int, escenario text, esperado text, ok boolean, detalle text);

CREATE OR REPLACE FUNCTION pg_temp.anotar(
    p_n int, p_esc text, p_esp text, p_ok boolean, p_det text DEFAULT NULL)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO resultado VALUES (p_n, p_esc, p_esp, p_ok, p_det);
$$;

CREATE OR REPLACE FUNCTION pg_temp.como(p_rol text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v UUID;
BEGIN
    SELECT id INTO v FROM usuarios_perfil WHERE rol::text = p_rol AND activo LIMIT 1;
    IF v IS NULL THEN RAISE EXCEPTION 'no hay usuario activo con rol %', p_rol; END IF;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v::text, 'role', 'authenticated')::text, true);
END $$;

DO $prueba$
DECLARE
  v_faena UUID := (SELECT id FROM faenas WHERE codigo='FAE-CMP-ROMERAL');
  v_m1  UUID := (SELECT id FROM combustible_estanques WHERE codigo='ROM-MINA-1');
  v_m2  UUID := (SELECT id FROM combustible_estanques WHERE codigo='ROM-MINA-2');
  v_bim UUID := (SELECT id FROM combustible_estanques WHERE codigo='ROM-BIMODAL');
  v_c18 UUID := (SELECT id FROM combustible_estanques WHERE codigo='ROM-DJKL-18');
  v_c67 UUID := (SELECT id FROM combustible_estanques WHERE codigo='ROM-FSLZ-67');
  v_c78 UUID := (SELECT id FROM combustible_estanques WHERE codigo='ROM-LCSX-78');
  v_cf  UUID := (SELECT id FROM combustible_estanques WHERE codigo='ROM-CASAF');
  m_m1  UUID := (SELECT m.id FROM combustible_faena_medidores m WHERE m.estanque_id=v_m1 ORDER BY m.orden LIMIT 1);
  m_m2  UUID := (SELECT m.id FROM combustible_faena_medidores m WHERE m.estanque_id=v_m2 ORDER BY m.orden LIMIT 1);
  m_c18 UUID := (SELECT m.id FROM combustible_faena_medidores m WHERE m.estanque_id=v_c18 ORDER BY m.orden LIMIT 1);
  m_bim UUID[] := ARRAY(SELECT m.id FROM combustible_faena_medidores m WHERE m.estanque_id=v_bim ORDER BY m.orden);
  m_cf  UUID := (SELECT m.id FROM combustible_faena_medidores m WHERE m.estanque_id=v_cf ORDER BY m.orden LIMIT 1);
  m_c67 UUID := (SELECT m.id FROM combustible_faena_medidores m WHERE m.estanque_id=v_c67 ORDER BY m.orden LIMIT 1);
  m_c78 UUID := (SELECT m.id FROM combustible_faena_medidores m WHERE m.estanque_id=v_c78 ORDER BY m.orden LIMIT 1);
  F     DATE := DATE '2026-08-20';
  v_out JSONB;
  v_id  UUID;
  v_txt TEXT;
  v_n   INT;
  v_med UUID;

BEGIN

-- ══ 1. Un operador de terreno guarda su turno, pero no puede firmarlo ══════
-- Medir lo hace quien está en el estanque. Firmar es declarar ante el mandante
-- cuánto combustible se movió, y eso lo responde otro.
PERFORM pg_temp.como('colaborador');
BEGIN
  v_out := rpc_comb_faena_guardar_cierre(v_faena, F, 'Día', 'Juan de terreno',
    jsonb_build_array(jsonb_build_object('estanque_id', v_m1, 'mi', 50000, 'mf', 49000,
                                         'foto_url','https://x/1.jpg')),
    '[]'::jsonb, NULL, false, 'uso-1');
  PERFORM pg_temp.anotar(1, 'Un colaborador guarda su turno sin firmar',
    'lo deja guardar', true, 'guardado como borrador');
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.anotar(1, 'Un colaborador guarda su turno sin firmar',
    'lo deja guardar', false, SQLERRM);
END;

BEGIN
  v_out := rpc_comb_faena_guardar_cierre(v_faena, F, 'Día', 'Juan de terreno',
    '[]'::jsonb, '[]'::jsonb, NULL, true, 'uso-1');
  PERFORM pg_temp.anotar(2, 'El mismo colaborador intenta FIRMAR',
    'lo bloquea', false, 'firmo sin tener permiso');
EXCEPTION WHEN insufficient_privilege THEN
  PERFORM pg_temp.anotar(2, 'El mismo colaborador intenta FIRMAR',
    'lo bloquea', true, left(SQLERRM, 70));
WHEN OTHERS THEN
  PERFORM pg_temp.anotar(2, 'El mismo colaborador intenta FIRMAR',
    'lo bloquea', false, 'error distinto: ' || left(SQLERRM, 60));
END;

-- ══ 2. La app sin señal reintenta el mismo despacho tres veces ════════════
-- El teléfono no sabe si el primer envío llegó. Manda de nuevo. Si el sistema
-- no reconoce que es el mismo, el estanque queda descuadrado por triplicado.
PERFORM pg_temp.como('supervisor');
BEGIN
  FOR v_n IN 1..3 LOOP
    PERFORM rpc_comb_faena_despachar(v_faena, F, 'Día', v_c18, NULL, NULL,
      0, 500, NULL, 'Operador', '08:00', 'CAT25', NULL, 'DJKL-18', NULL, NULL, NULL,
      'reintento-mismo-uuid', 'https://x/a.jpg', 'https://x/b.jpg', NULL,
      '115037', 'venta', 'Flota Caex Romeral', NULL);
  END LOOP;
  SELECT count(*) INTO v_n FROM combustible_faena_despachos
   WHERE client_uuid = 'reintento-mismo-uuid' AND NOT anulado;
  PERFORM pg_temp.anotar(3, 'Sin señal, la app manda el mismo despacho 3 veces',
    'queda 1 solo', v_n = 1, v_n || ' registro(s)');
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.anotar(3, 'Sin señal, la app manda el mismo despacho 3 veces',
    'queda 1 solo', false, left(SQLERRM, 70));
END;

-- ══ 3. Un numeral que baja: dedo, no realidad ═════════════════════════════
BEGIN
  v_out := rpc_comb_faena_guardar_cierre(v_faena, F, 'Día', 'Encargado',
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('medidor_id', m_m1,
      'numeral_ini', 24418837, 'numeral_fin', 24418000, 'foto_url','https://x/c.jpg')),
    NULL, false, 'uso-1');
  PERFORM pg_temp.anotar(4, 'Anota un numeral final MENOR que el inicial',
    'lo bloquea y explica', false, 'lo acepto');
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.anotar(4, 'Anota un numeral final MENOR que el inicial',
    'lo bloquea y explica', SQLERRM LIKE '%no puede bajar%', left(SQLERRM, 78));
END;

-- ══ 4. El mismo numeral bajo, pero porque cambiaron el cuentalitros ═══════
-- Es un evento normal de faena. Si el sistema no lo contempla, el día del
-- cambio nadie puede cerrar.
BEGIN
  v_out := rpc_comb_faena_guardar_cierre(v_faena, F, 'Día', 'Encargado',
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('medidor_id', m_m1,
      'numeral_ini', 24418837, 'numeral_fin', 1240, 'foto_url','https://x/c.jpg',
      'reinicio_contador', true,
      'motivo_reinicio', 'Se reemplazo el cuentalitros el 20-08, serie nueva ORP-99231')),
    NULL, false, 'uso-1');
  PERFORM pg_temp.anotar(5, 'Numeral bajo, declarado como cambio de contador',
    'lo acepta con el motivo escrito', true, 'aceptado');
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.anotar(5, 'Numeral bajo, declarado como cambio de contador',
    'lo acepta con el motivo escrito', false, left(SQLERRM, 78));
END;

BEGIN
  v_out := rpc_comb_faena_guardar_cierre(v_faena, F, 'Noche', 'Encargado',
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('medidor_id', m_m2,
      'numeral_ini', 20101242, 'numeral_fin', 500, 'reinicio_contador', true)),
    NULL, false, 'uso-x');
  PERFORM pg_temp.anotar(6, 'Marca "cambio de contador" pero no escribe el motivo',
    'lo bloquea', false, 'lo acepto sin motivo');
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.anotar(6, 'Marca "cambio de contador" pero no escribe el motivo',
    'lo bloquea', true, left(SQLERRM, 60));
END;

-- ══ 5. Intenta firmar sin la foto de la varilla ═══════════════════════════
-- En combustible la medición no se puede volver a verificar: mañana el
-- estanque tiene otro nivel. La foto es la única prueba.
PERFORM pg_temp.como('supervisor');
BEGIN
  v_out := rpc_comb_faena_guardar_cierre(v_faena, F, 'Día', 'Encargado',
    jsonb_build_array(jsonb_build_object('estanque_id', v_bim, 'mi', 44000, 'mf', 43000)),
    '[]'::jsonb, NULL, true, 'uso-1');
  PERFORM pg_temp.anotar(7, 'Firma con un punto medido sin foto',
    'lo bloquea y dice cual', false, 'firmo sin foto');
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.anotar(7, 'Firma con un punto medido sin foto',
    'lo bloquea y dice cual', SQLERRM LIKE '%foto de la varilla%', left(SQLERRM, 78));
END;

-- ══ 6. El día completo, bien hecho, y firmado ═════════════════════════════
BEGIN
  v_out := rpc_comb_faena_guardar_cierre(v_faena, F, 'Día', 'Yusdel Sarduy',
    jsonb_build_array(
      jsonb_build_object('estanque_id', v_m1, 'mi', 50000, 'mf', 49000,
        'agua_mm', 4, 'temperatura_c', 19, 'densidad_api', 36.5, 'foto_url','https://x/1.jpg'),
      jsonb_build_object('estanque_id', v_m2, 'mi', 16000, 'mf', 16000,
        'agua_mm', 2, 'foto_url','https://x/2.jpg'),
      jsonb_build_object('estanque_id', v_bim, 'mi', 44000, 'mf', 43000, 'foto_url','https://x/3.jpg'),
      jsonb_build_object('estanque_id', v_cf,  'mi', 26900, 'mf', 26900, 'foto_url','https://x/4.jpg'),
      jsonb_build_object('estanque_id', v_c18, 'mi', 3000, 'mf', 2500, 'foto_url','https://x/5.jpg'),
      jsonb_build_object('estanque_id', v_c67, 'sin_medicion', true,
        'motivo_sin_medicion', 'En Coquimbo por mantencion'),
      jsonb_build_object('estanque_id', v_c78, 'sin_medicion', true,
        'motivo_sin_medicion', 'Fuera de faena')),
    jsonb_build_array(
      jsonb_build_object('medidor_id', m_m1, 'numeral_ini', 1240, 'numeral_fin', 2240, 'foto_url','https://x/c1.jpg'),
      jsonb_build_object('medidor_id', m_m2, 'numeral_ini', 20101242, 'numeral_fin', 20101242, 'foto_url','https://x/c2.jpg'),
      jsonb_build_object('medidor_id', m_bim[1], 'numeral_ini', 4580150, 'numeral_fin', 4581150, 'foto_url','https://x/c3.jpg'),
      jsonb_build_object('medidor_id', m_bim[2], 'numeral_ini', 3486348, 'numeral_fin', 3486348, 'foto_url','https://x/c4.jpg'),
      jsonb_build_object('medidor_id', m_bim[3], 'numeral_ini', 48887, 'numeral_fin', 48887, 'foto_url','https://x/c5.jpg'),
      jsonb_build_object('medidor_id', m_bim[4], 'numeral_ini', 44905, 'numeral_fin', 44905, 'foto_url','https://x/c6.jpg'),
      jsonb_build_object('medidor_id', m_bim[5], 'numeral_ini', 989449, 'numeral_fin', 989449, 'foto_url','https://x/c7.jpg'),
      jsonb_build_object('medidor_id', m_cf,  'numeral_ini', 366632, 'numeral_fin', 366632, 'foto_url','https://x/c8.jpg'),
      jsonb_build_object('medidor_id', m_c18, 'numeral_ini', 2797808, 'numeral_fin', 2798308, 'foto_url','https://x/c9.jpg')),
    'Turno normal.', true, 'uso-1');
  v_id := (v_out->>'cierre_id')::uuid;
  PERFORM pg_temp.anotar(8, 'El dia completo, con fotos y motivos, se firma',
    'queda firmado', (v_out->>'firmado')::boolean, v_out::text);
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.anotar(8, 'El dia completo, con fotos y motivos, se firma',
    'queda firmado', false, left(SQLERRM, 78));
END;

-- ══ 7. Ya firmado, intenta corregir sin reabrir ═══════════════════════════
BEGIN
  v_out := rpc_comb_faena_guardar_cierre(v_faena, F, 'Día', 'Yusdel Sarduy',
    jsonb_build_array(jsonb_build_object('estanque_id', v_m1, 'mi', 50000, 'mf', 48000,
                                         'foto_url','https://x/1.jpg')),
    '[]'::jsonb, NULL, false, 'uso-1');
  PERFORM pg_temp.anotar(9, 'Corrige un cierre YA firmado sin reabrirlo',
    'lo bloquea', false, 'lo dejo editar');
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.anotar(9, 'Corrige un cierre YA firmado sin reabrirlo',
    'lo bloquea', SQLERRM LIKE '%ya está firmado%', left(SQLERRM, 78));
END;

-- ══ 8. Reabrir: el motivo corto no basta ══════════════════════════════════
BEGIN
  v_out := rpc_comb_faena_reabrir_cierre(v_id, 'error');
  PERFORM pg_temp.anotar(10, 'Reabre escribiendo solo "error"',
    'exige un motivo de verdad', false, 'acepto un motivo de 5 letras');
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.anotar(10, 'Reabre escribiendo solo "error"',
    'exige un motivo de verdad', true, left(SQLERRM, 60));
END;

BEGIN
  v_out := rpc_comb_faena_reabrir_cierre(v_id,
    'La varilla de Mina 1 se anoto 49000 y era 48000, se corrige con la foto');
  v_txt := (SELECT estado FROM combustible_faena_cierre WHERE id = v_id);
  SELECT count(*) INTO v_n FROM combustible_faena_cierre_bitacora WHERE cierre_id = v_id;
  PERFORM pg_temp.anotar(11, 'Reabre con el motivo escrito',
    'vuelve a borrador y queda en bitacora',
    v_txt = 'borrador' AND v_n >= 2, 'estado=' || v_txt || ' bitacora=' || v_n);
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.anotar(11, 'Reabre con el motivo escrito',
    'vuelve a borrador y queda en bitacora', false, left(SQLERRM, 78));
END;

-- ══ 9. Corrige y vuelve a firmar ══════════════════════════════════════════
BEGIN
  v_out := rpc_comb_faena_guardar_cierre(v_faena, F, 'Día', 'Yusdel Sarduy',
    jsonb_build_array(jsonb_build_object('estanque_id', v_m1, 'mi', 50000, 'mf', 48000,
                                         'agua_mm', 4, 'foto_url','https://x/1.jpg')),
    '[]'::jsonb, 'Corregido: Mina 1 marcaba 48000.', true, 'uso-1');
  v_txt := (SELECT estado FROM combustible_faena_cierre WHERE id = v_id);
  PERFORM pg_temp.anotar(12, 'Corrige el dato y vuelve a firmar',
    'queda firmado de nuevo', v_txt = 'firmado', 'estado=' || v_txt);
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.anotar(12, 'Corrige el dato y vuelve a firmar',
    'queda firmado de nuevo', false, left(SQLERRM, 78));
END;

-- ══ 10. Un operador sin permiso intenta reabrir ═══════════════════════════
PERFORM pg_temp.como('colaborador');
BEGIN
  v_out := rpc_comb_faena_reabrir_cierre(v_id, 'quiero cambiar un numero cualquiera');
  PERFORM pg_temp.anotar(13, 'Un colaborador intenta reabrir un cierre firmado',
    'lo bloquea', false, 'lo dejo reabrir');
EXCEPTION WHEN insufficient_privilege THEN
  PERFORM pg_temp.anotar(13, 'Un colaborador intenta reabrir un cierre firmado',
    'lo bloquea', true, left(SQLERRM, 60));
WHEN OTHERS THEN
  PERFORM pg_temp.anotar(13, 'Un colaborador intenta reabrir un cierre firmado',
    'lo bloquea', false, 'error distinto: ' || left(SQLERRM, 55));
END;

-- ══ 11. El agua sobre el nivel critico ════════════════════════════════════
PERFORM pg_temp.como('supervisor');
BEGIN
  v_out := rpc_comb_faena_guardar_cierre(v_faena, F + 1, 'Día', 'Yusdel Sarduy',
    jsonb_build_array(jsonb_build_object('estanque_id', v_m1, 'mi', 48000, 'mf', 47000,
      'agua_mm', 31, 'foto_url','https://x/agua.jpg')),
    '[]'::jsonb, 'Agua alta en Mina 1.', true, 'uso-agua');
  SELECT nivel INTO v_txt FROM v_comb_faena_agua
   WHERE fecha = F + 1 AND estanque_id = v_m1;
  PERFORM pg_temp.anotar(14, '31 mm de agua en el fondo del estanque',
    'no bloquea el cierre, pero avisa', v_txt = 'critica', 'nivel=' || COALESCE(v_txt,'(nada)'));
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.anotar(14, '31 mm de agua en el fondo del estanque',
    'no bloquea el cierre, pero avisa', false, left(SQLERRM, 78));
END;

-- ══ 12. La hora de corte ══════════════════════════════════════════════════
-- Romeral cierra a las 00:00, o sea el dia de cierre ES el dia calendario.
-- Ninguna carga deberia aparecer "corrida" de dia.
BEGIN
  SELECT count(*) INTO v_n FROM v_comb_faena_fuera_de_corte WHERE faena_id = v_faena;
  PERFORM pg_temp.anotar(15, 'Con corte a las 00:00, ninguna carga se corre de dia',
    'cero cargas corridas', v_n = 0, v_n || ' carga(s) marcadas como de otro dia');
END;

-- ══ 13. Un dia sin cerrar en medio del mes ════════════════════════════════
-- El acumulado no puede romperse porque falte un dia: tiene que seguir
-- sumando los que si estan.
BEGIN
  SELECT count(*) INTO v_n FROM v_comb_faena_variacion_acumulada
   WHERE faena_id = v_faena AND mes = DATE '2026-08-01';
  PERFORM pg_temp.anotar(16, 'Faltan dias del mes sin cerrar',
    'el acumulado igual se calcula', v_n > 0, v_n || ' dia(s) en la serie de agosto');
END;

-- ══ 14. Reemplazar un cuentalitros por el RPC ═════════════════════════════
BEGIN
  v_out := rpc_comb_faena_reemplazar_medidor(m_c18, 2798308, 0, 'ORP-2026-114',
    'Cuentalitros trabado, se cambia por uno nuevo');
  v_med := (v_out->>'medidor_nuevo')::uuid;
  SELECT count(*) INTO v_n FROM combustible_faena_medidores
   WHERE estanque_id = v_c18 AND activo;
  PERFORM pg_temp.anotar(17, 'Se cambia un cuentalitros del camion',
    'el viejo se retira con su lectura y nace el nuevo en cero',
    v_med IS NOT NULL AND v_n = 1,
    'activos=' || v_n || ' retirado_en=' || (v_out->>'numeral_al_retiro'));
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.anotar(17, 'Se cambia un cuentalitros del camion',
    'el viejo se retira y nace el nuevo', false, left(SQLERRM, 78));
END;

-- ══ 15. Dos personas cierran el mismo dia y turno ═════════════════════════
-- No es concurrencia real (una transaccion no ve a la otra), pero si el
-- segundo guardado crea un cierre paralelo en vez de escribir sobre el mismo,
-- el dia queda con dos verdades.
BEGIN
  PERFORM rpc_comb_faena_guardar_cierre(v_faena, F + 2, 'Día', 'Persona A',
    jsonb_build_array(jsonb_build_object('estanque_id', v_m1, 'mi', 47000, 'mf', 46000,
                                         'foto_url','https://x/a.jpg')),
    '[]'::jsonb, NULL, false, 'persona-a');
  PERFORM rpc_comb_faena_guardar_cierre(v_faena, F + 2, 'Día', 'Persona B',
    jsonb_build_array(jsonb_build_object('estanque_id', v_m1, 'mi', 47000, 'mf', 45500,
                                         'foto_url','https://x/b.jpg')),
    '[]'::jsonb, NULL, false, 'persona-b');
  SELECT count(*) INTO v_n FROM combustible_faena_cierre
   WHERE faena_id = v_faena AND fecha = F + 2 AND turno = 'Día';
  SELECT p.mf::text INTO v_txt FROM combustible_faena_cierre c
    JOIN combustible_faena_cierre_punto p ON p.cierre_id = c.id
   WHERE c.faena_id = v_faena AND c.fecha = F + 2 AND p.estanque_id = v_m1;
  PERFORM pg_temp.anotar(18, 'Dos personas cierran el mismo dia y turno',
    'un solo cierre, gana el ultimo', v_n = 1 AND v_txt = '45500',
    'cierres=' || v_n || ' mf=' || v_txt);
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.anotar(18, 'Dos personas cierran el mismo dia y turno',
    'un solo cierre, gana el ultimo', false, left(SQLERRM, 78));
END;

-- ══ 16. Un CECO que el operador anota a mano en terreno ═══════════════════
BEGIN
  PERFORM rpc_comb_faena_despachar(v_faena, F, 'Día', v_c18, NULL, NULL,
    500, 900, NULL, 'Operador', '10:00', 'PERFO 23', NULL, 'DJKL-18', NULL, NULL, NULL,
    'ceco-anotado-1', 'https://x/a.jpg', 'https://x/b.jpg', NULL,
    '888999', 'venta', 'Flota Eq. Apoyo', NULL);
  SELECT count(*) INTO v_n FROM combustible_faena_cecos
   WHERE faena_id = v_faena AND codigo = '888999' AND origen = 'terreno' AND NOT confirmado;
  PERFORM pg_temp.anotar(19, 'El operador anota un CECO que no esta en la lista',
    'lo acepta y lo deja para confirmar', v_n = 1, v_n || ' CECO por confirmar');
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.anotar(19, 'El operador anota un CECO que no esta en la lista',
    'lo acepta y lo deja para confirmar', false, left(SQLERRM, 78));
END;

-- ══ 17. Litros negativos ══════════════════════════════════════════════════
BEGIN
  PERFORM rpc_comb_faena_despachar(v_faena, F, 'Día', v_c18, NULL, NULL,
    NULL, NULL, -500, 'Operador', '11:00', 'CAT25', NULL, 'DJKL-18', NULL, NULL, NULL,
    'negativo-1', NULL, NULL, NULL, '115037', 'venta', NULL, NULL);
  PERFORM pg_temp.anotar(20, 'Registra un despacho de -500 litros',
    'lo bloquea', false, 'acepto litros negativos');
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.anotar(20, 'Registra un despacho de -500 litros',
    'lo bloquea', true, left(SQLERRM, 60));
END;

-- ══ 18. Se firma el cierre y el stock del estanque queda al dia ═══════════
BEGIN
  SELECT stock_teorico_lt::text INTO v_txt FROM combustible_estanques WHERE id = v_m1;
  PERFORM pg_temp.anotar(21, 'Al firmar, el stock del estanque se pone al dia',
    'el maestro refleja la ultima varilla', v_txt::numeric = 47000,
    'stock en el maestro=' || COALESCE(v_txt,'(nulo)'));
END;

END $prueba$;

SELECT n AS "#",
       rpad(escenario, 58) AS "escenario",
       CASE WHEN ok THEN 'OK   ' ELSE 'FALLA' END AS "res",
       left(COALESCE(detalle,''), 60) AS "detalle"
  FROM resultado ORDER BY n;

SELECT count(*) FILTER (WHERE ok) || ' de ' || count(*) || ' escenarios OK'
       || CASE WHEN count(*) FILTER (WHERE NOT ok) > 0
               THEN '  ·  ' || count(*) FILTER (WHERE NOT ok) || ' FALLAS' ELSE '' END
       AS "RESULTADO"
  FROM resultado;

ROLLBACK;
