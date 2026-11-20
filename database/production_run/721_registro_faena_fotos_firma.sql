-- ============================================================================
-- MIG721 — Registro en faena igual que en el taller (19-11-2026)
-- ----------------------------------------------------------------------------
-- Manuel (19-11): «en el taller de Coquimbo siempre pide un registro; aquí se
-- debe pedir lo mismo para el mantenimiento diario y cuando se ejecuta una
-- pauta» y «que saque fotos de lo realizado».
--
-- En TODAS las pautas de Franke (diarias y servicios, camión y camioneta):
--   · foto del tablero (horómetro/km) en la primera lectura,
--   · firma de quien ejecuta al cerrar (nuevo tipo de respuesta 'firma'; viaja
--     como foto: funciona sin señal con la cola de siempre).
-- En los servicios: foto de lo realizado en cada trabajo ejecutado (cambios,
-- reemplazos, engrases, muestras, ajustes, servicios). Las inspecciones siguen
-- con foto solo si salen NO OK.
-- rpc_faena_pauta_guardar lo exige también en el servidor.
-- Coquimbo: la OT de los Mack pide foto en esos mismos trabajos
-- (items_checklist con requiere_foto, que fn_pauta_a_template ahora respeta).
-- ============================================================================

-- 1. Columna y tipo de respuesta ---------------------------------------------
ALTER TABLE public.faena_pauta_item ADD COLUMN IF NOT EXISTS foto_obligatoria BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.faena_pauta_item DROP CONSTRAINT IF EXISTS faena_pauta_item_tipo_respuesta_check;
ALTER TABLE public.faena_pauta_item ADD CONSTRAINT faena_pauta_item_tipo_respuesta_check
    CHECK (tipo_respuesta = ANY (ARRAY['ok_nok', 'numero', 'texto', 'firma']));

-- 2. Franke: foto del tablero, foto de lo realizado y firma ------------------------
DO $$
DECLARE v_faena UUID := (SELECT id FROM public.faenas WHERE codigo = 'FAE-FRANCKE');
        r RECORD; v_n INT;
BEGIN
  -- Foto del tablero: la primera lectura de cada pauta.
  UPDATE public.faena_pauta_item i
     SET foto_obligatoria = TRUE,
         ayuda = 'Foto del tablero con el horómetro y el kilometraje a la vista: es el respaldo de la lectura.'
   WHERE i.id IN (SELECT DISTINCT ON (x.pauta_id) x.id
                    FROM public.faena_pauta_item x JOIN public.faena_pauta p ON p.id = x.pauta_id
                   WHERE p.faena_id = v_faena AND x.tipo_respuesta = 'numero' AND x.bloque = 'Lecturas'
                   ORDER BY x.pauta_id, x.orden);
  GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Foto del tablero: % pautas', v_n;

  -- Foto de lo realizado: los trabajos ejecutados de los servicios.
  UPDATE public.faena_pauta_item i SET foto_obligatoria = TRUE
    FROM public.faena_pauta p
   WHERE p.id = i.pauta_id AND p.faena_id = v_faena AND p.tipo = 'programada'
     AND i.texto = ANY (ARRAY[
      'Ajuste de válvulas y freno motor',
      'Alineación de los 3 ejes',
      'Bomba de despacho: sello mecánico, rodamientos, empaquetaduras; verificar caudal',
      'Cambio de aceite de diferenciales delantero + divisor y trasero',
      'Cambio de aceite de motor y filtros (2 + 1 adicional). Si la visita es por calendario y van menos de 150 h desde el último cambio: solo nivel + muestra',
      'Cambio de elementos del filtro de despacho',
      'Cambio de fluido de transmisión',
      'Cambio de refrigerante larga vida',
      'Cambio de refrigerante si es formulado (larga vida: SM4)',
      'Correas de ventilador y accesorios + tensor y poleas',
      'DPF: limpieza; electrodo y tobera; inyector AHI; filtros y drenaje DEF',
      'Engrase de cardanes: crucetas, yugos deslizantes, soporte central',
      'Engrase de pivotes (king pins), extremos de barra y brazos de dirección',
      'Engrase de puntos de suspensión; inspección de paquetes de resortes, hojas y bujes',
      'Filtro de aire primario: reemplazo (antes si el indicador está en máximo)',
      'Filtro de aire secundario (de seguridad)',
      'Filtro de refrigerante / acondicionador',
      'Filtro de venteo del estanque de combustible del chasis',
      'Filtro de ventilación del cárter (CCV)',
      'Filtros de combustible: primario/separador y secundario',
      'Filtros de transmisión (principal + lubricación) — Allison; caja mecánica/mDRIVE: aceite según placa',
      'Fluido y filtro de dirección hidráulica',
      'Limpieza de respiraderos de diferenciales',
      'Limpieza del estanque de combustible del chasis',
      'Rotación / evaluación de reemplazo',
      'Secador de aire: cartucho',
      'Tomar muestra de aceite de motor para laboratorio (viscosidad, TBN, hollín, metales, combustible, refrigerante)',
      'Cambio de aceite de motor y filtro',
      'Cambio de filtro de aire',
      'Cambio de filtro de combustible',
      'Cambio de filtro de aire acondicionado',
      'Rotación y presión de neumáticos',
      'Niveles y engrase'
     ]);
  GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Foto de lo realizado: % ítems', v_n;

  -- Firma de quien ejecuta, al final de cada pauta.
  FOR r IN SELECT p.id, (SELECT max(orden) FROM public.faena_pauta_item WHERE pauta_id = p.id) AS mx
             FROM public.faena_pauta p WHERE p.faena_id = v_faena AND p.activo LOOP
    IF NOT EXISTS (SELECT 1 FROM public.faena_pauta_item WHERE pauta_id = r.id AND tipo_respuesta = 'firma') THEN
      INSERT INTO public.faena_pauta_item (pauta_id, orden, bloque, texto, ayuda, tipo_respuesta, obligatorio,
                                           foto_si_nok, critico, foto_obligatoria)
      VALUES (r.id, COALESCE(r.mx, 0) + 10, 'Cierre', 'Firma de quien ejecuta',
              'Firma con el dedo: confirma que lo marcado se hizo y se revisó.', 'firma', TRUE, FALSE, FALSE, TRUE);
    END IF;
  END LOOP;
END $$;

-- 3. El servidor exige el registro ------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_faena_pauta_guardar(p_faena_id uuid, p_pauta_id uuid, p_activo_id uuid, p_fecha date, p_turno text DEFAULT NULL::text, p_items jsonb DEFAULT '[]'::jsonb, p_horometro numeric DEFAULT NULL::numeric, p_kilometraje numeric DEFAULT NULL::numeric, p_observacion text DEFAULT NULL::text, p_cerrar boolean DEFAULT false, p_ejecutado_por_nombre text DEFAULT NULL::text, p_no_aplica_motivo text DEFAULT NULL::text, p_client_uuid text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_id       UUID;
    v_it       JSONB;
    v_item     RECORD;
    v_nc       UUID;
    v_faltan   TEXT[] := '{}';
    v_sin_foto TEXT[] := '{}';
    v_nok      INTEGER := 0;
    v_ncs      INTEGER := 0;
BEGIN
    IF NOT public.fn_faena_pauta_puede_ejecutar() THEN
        RAISE EXCEPTION 'La pauta de faena la ejecuta el mecánico de turno.'
            USING ERRCODE = '42501';
    END IF;

    -- Retomar, no duplicar: si ya hay una del mismo equipo, día y turno, se
    -- sigue esa.
    SELECT id INTO v_id
      FROM public.faena_pauta_ejecucion
     WHERE pauta_id = p_pauta_id AND activo_id = p_activo_id
       AND fecha = p_fecha AND COALESCE(turno, '') = COALESCE(p_turno, '');

    IF v_id IS NULL THEN
        INSERT INTO public.faena_pauta_ejecucion
               (faena_id, pauta_id, activo_id, fecha, turno, ejecutado_por,
                ejecutado_por_nombre, client_uuid)
        VALUES (p_faena_id, p_pauta_id, p_activo_id, p_fecha, p_turno, auth.uid(),
                p_ejecutado_por_nombre, p_client_uuid)
        RETURNING id INTO v_id;
    END IF;

    -- El equipo que no se pudo ver. Se cierra sin ítems y con motivo: es una
    -- respuesta, no un hueco.
    IF p_no_aplica_motivo IS NOT NULL AND length(trim(p_no_aplica_motivo)) > 0 THEN
        UPDATE public.faena_pauta_ejecucion
           SET estado = 'no_aplica', motivo_no_aplica = p_no_aplica_motivo,
               cerrada_at = NOW(), updated_at = NOW()
         WHERE id = v_id;
        RETURN jsonb_build_object('success', true, 'ejecucion_id', v_id, 'estado', 'no_aplica');
    END IF;

    -- ── Las respuestas ────────────────────────────────────────────────────
    FOR v_it IN SELECT * FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb))
    LOOP
        INSERT INTO public.faena_pauta_ejecucion_item
               (ejecucion_id, item_id, resultado, valor, texto, observacion, foto_url)
        VALUES (v_id,
                (v_it->>'item_id')::uuid,
                NULLIF(v_it->>'resultado',''),
                NULLIF(v_it->>'valor','')::numeric,
                NULLIF(v_it->>'texto',''),
                NULLIF(v_it->>'observacion',''),
                NULLIF(v_it->>'foto_url',''))
        ON CONFLICT (ejecucion_id, item_id) DO UPDATE SET
                resultado   = EXCLUDED.resultado,
                valor       = EXCLUDED.valor,
                texto       = EXCLUDED.texto,
                observacion = EXCLUDED.observacion,
                foto_url    = COALESCE(EXCLUDED.foto_url, faena_pauta_ejecucion_item.foto_url),
                respondido_at = NOW();
    END LOOP;

    UPDATE public.faena_pauta_ejecucion
       SET horometro   = COALESCE(p_horometro, horometro),
           kilometraje = COALESCE(p_kilometraje, kilometraje),
           observacion = COALESCE(p_observacion, observacion),
           ejecutado_por_nombre = COALESCE(p_ejecutado_por_nombre, ejecutado_por_nombre),
           updated_at  = NOW()
     WHERE id = v_id;

    IF NOT p_cerrar THEN
        RETURN jsonb_build_object('success', true, 'ejecucion_id', v_id, 'estado', 'borrador');
    END IF;

    -- ── Cerrar: acá es donde la pauta se pone exigente ────────────────────
    -- 1) No queda ningún obligatorio sin contestar.
    SELECT array_agg(i.texto ORDER BY i.orden) INTO v_faltan
      FROM public.faena_pauta_item i
      LEFT JOIN public.faena_pauta_ejecucion_item r
             ON r.item_id = i.id AND r.ejecucion_id = v_id
     WHERE i.pauta_id = p_pauta_id AND i.obligatorio
       AND (r.id IS NULL
            OR (i.tipo_respuesta = 'ok_nok' AND r.resultado IS NULL)
            OR (i.tipo_respuesta = 'numero' AND r.valor IS NULL)
            OR (i.tipo_respuesta = 'texto'  AND COALESCE(r.texto,'') = '')
            OR (i.tipo_respuesta = 'firma'  AND COALESCE(r.foto_url,'') = ''));

    IF v_faltan IS NOT NULL AND array_length(v_faltan, 1) > 0 THEN
        RAISE EXCEPTION 'Falta contestar: %', array_to_string(v_faltan[1:5], ' · ')
            USING ERRCODE = 'check_violation';
    END IF;

    -- 2) Todo NO OK que pide foto la tiene. Sin foto es una afirmación sin
    --    respaldo, y es la que después se discute con el mandante.
    SELECT array_agg(i.texto ORDER BY i.orden) INTO v_sin_foto
      FROM public.faena_pauta_ejecucion_item r
      JOIN public.faena_pauta_item i ON i.id = r.item_id
     WHERE r.ejecucion_id = v_id AND r.resultado = 'nok'
       AND i.foto_si_nok AND COALESCE(r.foto_url, '') = '';

    IF v_sin_foto IS NOT NULL AND array_length(v_sin_foto, 1) > 0 THEN
        RAISE EXCEPTION 'Estos hallazgos necesitan foto: %',
            array_to_string(v_sin_foto[1:5], ' · ')
            USING ERRCODE = 'check_violation';
    END IF;

    -- 2b) [MIG721] El registro: foto del tablero, foto de lo realizado y firma.
    --     Lo mismo que pide el taller de Coquimbo. Sin registro no se cierra.
    v_sin_foto := NULL;
    SELECT array_agg(i.texto ORDER BY i.orden) INTO v_sin_foto
      FROM public.faena_pauta_item i
      JOIN public.faena_pauta_ejecucion_item r ON r.item_id = i.id AND r.ejecucion_id = v_id
     WHERE i.pauta_id = p_pauta_id AND i.foto_obligatoria
       AND (r.resultado IS NOT NULL OR r.valor IS NOT NULL OR i.tipo_respuesta = 'firma')
       AND COALESCE(r.foto_url, '') = '';

    IF v_sin_foto IS NOT NULL AND array_length(v_sin_foto, 1) > 0 THEN
        RAISE EXCEPTION 'Falta el registro (foto o firma) de: %',
            array_to_string(v_sin_foto[1:5], ' · ')
            USING ERRCODE = 'check_violation';
    END IF;

    -- 3) Cada NO OK levanta su no conformidad, una sola vez.
    FOR v_item IN
        SELECT r.id AS resp_id, r.observacion, r.foto_url, i.texto, i.critico, i.bloque
          FROM public.faena_pauta_ejecucion_item r
          JOIN public.faena_pauta_item i ON i.id = r.item_id
         WHERE r.ejecucion_id = v_id AND r.resultado = 'nok' AND r.nc_id IS NULL
    LOOP
        INSERT INTO public.no_conformidades
               (activo_id, tipo, descripcion, fecha_evento, severidad, origen,
                foto_url, registrada_por, created_by, estado_planificacion, resuelto)
        VALUES (p_activo_id, 'falla_en_terreno',
                v_item.bloque || ' · ' || v_item.texto
                  || COALESCE(' — ' || NULLIF(v_item.observacion, ''), ''),
                p_fecha,
                CASE WHEN v_item.critico THEN 'alta' ELSE 'media' END,
                'pauta_faena', v_item.foto_url, auth.uid(), auth.uid(),
                'registrada', FALSE)
        RETURNING id INTO v_nc;

        UPDATE public.faena_pauta_ejecucion_item SET nc_id = v_nc WHERE id = v_item.resp_id;
        v_ncs := v_ncs + 1;
    END LOOP;

    SELECT count(*) INTO v_nok
      FROM public.faena_pauta_ejecucion_item
     WHERE ejecucion_id = v_id AND resultado = 'nok';

    UPDATE public.faena_pauta_ejecucion
       SET estado = 'cerrada', cerrada_at = NOW(), updated_at = NOW()
     WHERE id = v_id;

    -- 4) El horómetro se tomó una vez y de acá sale para todos lados. Nunca
    --    hacia atrás: un contador que retrocede es un error de tecleo, y
    --    pisarle la ficha al activo con él arrastra el error a la mantención.
    UPDATE public.activos
       SET horas_uso_actual   = GREATEST(COALESCE(horas_uso_actual, 0),   COALESCE(p_horometro, 0)),
           kilometraje_actual = GREATEST(COALESCE(kilometraje_actual, 0), COALESCE(p_kilometraje, 0)),
           updated_at = NOW()
     WHERE id = p_activo_id
       AND (p_horometro IS NOT NULL OR p_kilometraje IS NOT NULL);

    RETURN jsonb_build_object('success', true, 'ejecucion_id', v_id, 'estado', 'cerrada',
                              'hallazgos', v_nok, 'no_conformidades', v_ncs);
END;
$function$;

-- 4. Coquimbo: la OT de los Mack pide foto en los mismos trabajos -----------------
CREATE OR REPLACE FUNCTION public.fn_pauta_a_template(p_pauta_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_p      RECORD;
    v_tpl    UUID;
    v_tipos  tipo_equipamiento_enum[];
    v_n      INT := 0;
    v_ver    INT;
    v_en_uso BOOLEAN := FALSE;
    it       RECORD;
BEGIN
    SELECT p.id, p.nombre, p.descripcion, p.items_checklist, p.duracion_estimada_hrs,
           p.tipo_plan, m.nombre AS modelo, p.modelo_id
      INTO v_p
      FROM pautas_fabricante p
      LEFT JOIN modelos m ON m.id = p.modelo_id
     WHERE p.id = p_pauta_id;

    IF v_p.id IS NULL THEN RAISE EXCEPTION 'Esa pauta no existe.'; END IF;
    IF v_p.items_checklist IS NULL
       OR jsonb_typeof(v_p.items_checklist) <> 'array'
       OR jsonb_array_length(v_p.items_checklist) = 0 THEN
        RETURN NULL;
    END IF;

    SELECT array_agg(e) INTO v_tipos
      FROM unnest(enum_range(NULL::tipo_equipamiento_enum)) e;

    SELECT id, version INTO v_tpl, v_ver FROM checklist_template_v2
     WHERE pauta_fabricante_id = p_pauta_id AND activo
     ORDER BY version DESC LIMIT 1;

    IF v_tpl IS NOT NULL THEN
        SELECT EXISTS (SELECT 1 FROM checklist_v2_instance i WHERE i.template_id = v_tpl)
          INTO v_en_uso;
    END IF;

    IF v_tpl IS NULL THEN
        v_ver := 1;
    ELSIF v_en_uso THEN
        UPDATE checklist_template_v2 SET activo = FALSE, updated_at = NOW() WHERE id = v_tpl;
        v_ver := v_ver + 1;
        v_tpl := NULL;
    ELSE
        UPDATE checklist_template_v2
           SET nombre = v_p.nombre, activo = TRUE, updated_at = NOW()
         WHERE id = v_tpl;
        DELETE FROM checklist_template_v2_item WHERE template_id = v_tpl;
    END IF;

    IF v_tpl IS NULL THEN
        INSERT INTO checklist_template_v2 (codigo, nombre, momento_uso, version, descripcion,
                                           activo, pauta_fabricante_id)
        VALUES ('PAUTA-' || left(replace(p_pauta_id::TEXT, '-', ''), 8)
                  || CASE WHEN v_ver > 1 THEN '-v' || v_ver ELSE '' END,
                v_p.nombre, 'preventiva', v_ver,
                COALESCE(v_p.descripcion, 'Pauta del fabricante')
                  || COALESCE(' · ' || v_p.modelo, ''),
                TRUE, p_pauta_id)
        RETURNING id INTO v_tpl;
    END IF;

    -- [MIG494] Acá está el cambio: los pasos vienen ya expandidos, así que un
    -- «SM2 completo» llega convertido en los pasos del SM2.
    FOR it IN SELECT * FROM fn_pauta_items_expandidos(p_pauta_id, 0) ORDER BY orden
    LOOP
        v_n := v_n + 1;
        INSERT INTO checklist_template_v2_item (
            template_id, bloque, orden, codigo, descripcion,
            tipos_equipamiento, obligatorio, requiere_foto, tipo_respuesta, ayuda
        ) VALUES (
            v_tpl, 'a_trabajos_ot', it.orden,
            'P' || lpad(v_n::TEXT, 3, '0'),
            -- El paso heredado dice de dónde viene: el mecánico entiende el
            -- escalón sin abrir otra pantalla.
            CASE WHEN it.viene_de IS NOT NULL
                 THEN it.viene_de || ' · ' || it.descripcion
                 ELSE it.descripcion END,
            v_tipos, TRUE,
            -- [MIG721] El paso pide foto si así viene en la pauta (objeto con
            -- requiere_foto), también cuando llega heredado de un nivel menor.
            EXISTS (SELECT 1 FROM pautas_fabricante pf2, jsonb_array_elements(pf2.items_checklist) e
                     WHERE pf2.modelo_id IS NOT DISTINCT FROM v_p.modelo_id
                       AND jsonb_typeof(pf2.items_checklist) = 'array'
                       AND jsonb_typeof(e) = 'object'
                       AND COALESCE((e ->> 'requiere_foto')::BOOLEAN, FALSE)
                       AND btrim(e ->> 'descripcion') = it.descripcion),
            'ok_no_ok',
            CASE WHEN it.viene_de IS NOT NULL
                 THEN 'Viene del servicio ' || it.viene_de || ', que este incluye completo.'
            END
        );
    END LOOP;

    RETURN v_tpl;
END;
$function$;

DO $$
DECLARE m RECORD; v_n INT;
BEGIN
  FOR m IN SELECT id FROM public.modelos WHERE nombre IN ('GU 813 autom','GU813E Mec','GU813E Allison') LOOP
    UPDATE public.pautas_fabricante SET items_checklist = '["Horómetro, odómetro y códigos de falla activos (motor, transmisión, ABS, postratamiento) con lector — Mack PTT / lector", {"descripcion": "Cambio de aceite de motor y filtros (2 + 1 adicional). Si la visita es por calendario y van menos de 150 h desde el último cambio: solo nivel + muestra — Mack EOS-4.5 15W40 (38–42 L) · filtros genuinos", "requiere_foto": true}, {"descripcion": "Tomar muestra de aceite de motor para laboratorio (viscosidad, TBN, hollín, metales, combustible, refrigerante) — Kit de muestra", "requiere_foto": true}, "Drenar agua del separador de combustible; revisar sensor WIF", "Leer indicador de restricción del filtro de aire; reemplazar el primario si está en máximo — Indicador in H2O", "Correas de ventilador y accesorios: grietas, desgaste, tensión", "Refrigerante: nivel y concentración (refractómetro) — Refractómetro", "Radiador, intercooler y condensador: limpieza externa de polvo; mangueras y abrazaderas — Aire a baja presión", "Soportes de motor, fugas de aceite/combustible/refrigerante, arnés", "Nivel y condición del fluido de transmisión (en caliente); fugas; respiradero; temperatura en tablero — Allison TES 668/295 o según placa", "[Solo aljibe de combustible] Toma de fuerza: montaje, fugas, ruido, activación y mando en cabina", {"descripcion": "Engrase de cardanes: crucetas, yugos deslizantes, soporte central — Grasa NLGI 2 EP", "requiere_foto": true}, "Nivel de aceite de diferenciales, respiraderos, retenes de piñón y de cubos", {"descripcion": "Engrase de pivotes (king pins), extremos de barra y brazos de dirección — Grasa NLGI 2 EP", "requiere_foto": true}, "Cubos delanteros: nivel y condición del aceite", "Medir carrera de cámaras / ajustadores automáticos; engrasar ajustadores y levas S-cam — Grasa NLGI 2 EP", "Prueba de fugas de aire, gobernador (corte/entrada), freno de estacionamiento, alarma de baja presión — Manómetro calibrado", "Freno motor: prueba funcional en ruta", "Drenaje de estanques de aire y válvulas de drenaje automáticas", "Presión, desgaste, daños, torque de tuercas de rueda; registrar profundidad de banda — Torquímetro · profundímetro", "Nivel de fluido, bomba, mangueras, caja, juego libre, rótulas y extremos", {"descripcion": "Engrase de puntos de suspensión; inspección de paquetes de resortes, hojas y bujes — Grasa NLGI 2 EP", "requiere_foto": true}, "Baterías: bornes, sujeción, voltaje; alternador y arranque — Voltímetro", "Paradas de emergencia (cabina y zona de despacho) conectadas y funcionando; cableado protegido; caja de fusibles", "Luces, balizas, alarma de retroceso, bocina, limpiaparabrisas, tacógrafo", "[Solo aljibe de combustible] Estanque: fugas, abolladuras, corrosión, soldaduras, anclajes y cunas", "[Solo aljibe de combustible] Válvula de emergencia (de fondo) por compartimiento: cierre primario y remoto, fusible térmico", "[Solo aljibe de combustible] Válvulas de presión/vacío, venteos y arrestallamas de venteo; válvulas de descarga, tapas y candados", "[Solo aljibe de combustible] Escotillas: empaquetaduras, cierres, trabas; carga inferior API y sensor de sobrellenado", "[Solo aljibe de combustible] Bomba de despacho: sello, fugas, ruido, acople, presión/caudal, alivio; limpiar strainer", "[Solo aljibe de combustible] Medidor volumétrico: verificación con serafín y ajuste; precintos; eliminador de aire; registrador/ticket y totalizador — Serafín trazable · OIML R 117 ±0,5 %", "[Solo aljibe de combustible] Filtro/separador de despacho: ΔP, drenaje de agua, sumidero — Manómetro diferencial", "[Solo aljibe de combustible] Mangueras, pistola con cierre automático, acoples, swivels; engrase del carrete — Grasa NLGI 2", "[Solo aljibe de combustible] Puesta a tierra: cable, pinza, carrete; medir continuidad camión–manguera–pinza — Óhmetro (< 10 Ω)", "[Solo aljibe de combustible] Arrestallamas de escape, parachoques, señalización NU 1202, radio, corte general, kit de derrames, pasarela y barandas", "[Solo aljibe de combustible] Inspección mensual DS 298 con registro; documentación y certificados vigentes (hermeticidad, SEC, revisión técnica, calibración) — Control Documental de SICOM", "Prueba de ruta y del sistema de despacho; horómetro de la próxima mantención en el sticker"]'::jsonb, updated_at = NOW()
     WHERE modelo_id = m.id AND nombre = 'Mack GU813E - Servicio SL (300h)';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN RAISE EXCEPTION 'Falta la pauta SL de un modelo Mack'; END IF;
    UPDATE public.pautas_fabricante SET items_checklist = '["SL completo", {"descripcion": "Filtros de combustible: primario/separador y secundario — Filtros genuinos Mack", "requiere_foto": true}, {"descripcion": "Filtro de aire primario: reemplazo (antes si el indicador está en máximo) — Filtro genuino", "requiere_foto": true}, {"descripcion": "Filtro de venteo del estanque de combustible del chasis — Filtro genuino", "requiere_foto": true}, "Embrague de ventilador, bomba de agua (orificio testigo)", "Escape, abrazaderas, sensores NOx/temperatura/ΔP; nivel y calidad de DEF — Refractómetro DEF 32,5 %", "Enfriador de transmisión, líneas, conectores, selector, códigos TCM — Allison DOC / Mack PTT", "Cardanes: juego de crucetas, torque de pernos, soporte central — Torquímetro", "Bloqueo de diferencial / divisor de potencia: prueba funcional", "Espesor de balatas, tambores, resortes, pasadores, cámaras", "Tiempo de recuperación del compresor (build-up)", "Mangueras, cañerías y conexiones neumáticas", "ABS: códigos, sensores de rueda, anillos dentados, cableado — Herramienta de diagnóstico", {"descripcion": "Rotación / evaluación de reemplazo", "requiere_foto": true}, "Torque de pernos U, bujes, amortiguadores, barras, soportes — Torquímetro", "Bastidor: fisuras, pernos sueltos, travesaños; soportes, cunas y pernos U del estanque — Torquímetro", "Conectores eléctricos: corrosión, seguros, grasa dieléctrica — Grasa dieléctrica", "Filtro de cabina, cinturones, espejos, parabrisas, asiento, extintor de cabina — Filtro de cabina", {"descripcion": "[Solo aljibe de combustible] Cambio de elementos del filtro de despacho — Elementos según fabricante", "requiere_foto": true}, "[Solo aljibe de combustible] Extintores PQS (2 × 40 BC): revisión semestral, presión, sello, fecha", "[Solo aljibe de combustible] Sistema de recuperación de vapores (si existe)"]'::jsonb, updated_at = NOW()
     WHERE modelo_id = m.id AND nombre = 'Mack GU813E - Servicio SM1 (600h)';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN RAISE EXCEPTION 'Falta la pauta SM1 de un modelo Mack'; END IF;
    UPDATE public.pautas_fabricante SET items_checklist = '["SM1 completo", {"descripcion": "Cambio de aceite de diferenciales delantero + divisor y trasero — 80W90 / GO-J Plus (18 L + 15 L)", "requiere_foto": true}, {"descripcion": "Limpieza de respiraderos de diferenciales", "requiere_foto": true}, {"descripcion": "Filtro de aire secundario (de seguridad) — Filtro genuino", "requiere_foto": true}, {"descripcion": "Correas de ventilador y accesorios + tensor y poleas — Correas genuinas", "requiere_foto": true}, {"descripcion": "Filtro de ventilación del cárter (CCV) — Filtro genuino", "requiere_foto": true}, {"descripcion": "Filtro de refrigerante / acondicionador — Según refrigerante instalado", "requiere_foto": true}, "Prueba de estanqueidad del intercooler (CAC) y ductos — Kit CAC", "Turbocompresor: juego axial/radial, fugas, actuador VGT", "Compresor de aire: aceite en líneas, culata, descarga", "Rodamientos de ruedas: juego, retenes, ajuste; cambio de aceite de cubos", {"descripcion": "Alineación de los 3 ejes — Equipo de alineación", "requiere_foto": true}, {"descripcion": "Secador de aire: cartucho — Cartucho Bendix/Mack", "requiere_foto": true}, {"descripcion": "Fluido y filtro de dirección hidráulica — Según manual Mack", "requiere_foto": true}, "Prueba de carga de baterías y salida de alternador — Probador de carga", "[Solo aljibe de combustible] Interior de compartimentos: mamparos, corrosión, sedimentos, agua; limpieza — Procedimiento de espacio confinado", {"descripcion": "[Solo aljibe de combustible] Bomba de despacho: sello mecánico, rodamientos, empaquetaduras; verificar caudal — Kit de sello", "requiere_foto": true}, "[Solo aljibe de combustible] Calibración certificada del sistema de medición y re-sellado — Laboratorio trazable", "[Solo aljibe de combustible] Prueba de presión de mangueras de despacho — 1,5 × presión máxima"]'::jsonb, updated_at = NOW()
     WHERE modelo_id = m.id AND nombre = 'Mack GU813E - Servicio SM2 (1200h)';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN RAISE EXCEPTION 'Falta la pauta SM2 de un modelo Mack'; END IF;
    UPDATE public.pautas_fabricante SET items_checklist = '["SM2 completo", {"descripcion": "Ajuste de válvulas y freno motor — Manual MP8", "requiere_foto": true}, {"descripcion": "Filtros de transmisión (principal + lubricación) — Allison; caja mecánica/mDRIVE: aceite según placa — Allison TES 668/295 · confirmar tipo de caja", "requiere_foto": true}, {"descripcion": "Limpieza del estanque de combustible del chasis", "requiere_foto": true}, {"descripcion": "Cambio de refrigerante si es formulado (larga vida: SM4) — 50/50 (57 L)", "requiere_foto": true}]'::jsonb, updated_at = NOW()
     WHERE modelo_id = m.id AND nombre = 'Mack GU813E - Servicio SM3 (2400h)';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN RAISE EXCEPTION 'Falta la pauta SM3 de un modelo Mack'; END IF;
    UPDATE public.pautas_fabricante SET items_checklist = '["SM3 completo", {"descripcion": "Cambio de fluido de transmisión — Allison TES 668/295 (~48 L) o según placa", "requiere_foto": true}, {"descripcion": "Cambio de refrigerante larga vida — ELC", "requiere_foto": true}, {"descripcion": "DPF: limpieza; electrodo y tobera; inyector AHI; filtros y drenaje DEF — Genuinos", "requiere_foto": true}]'::jsonb, updated_at = NOW()
     WHERE modelo_id = m.id AND nombre = 'Mack GU813E - Servicio SM4 (4800h)';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN RAISE EXCEPTION 'Falta la pauta SM4 de un modelo Mack'; END IF;
  END LOOP;
  PERFORM public.fn_pauta_a_template(pf.id)
     FROM public.pautas_fabricante pf JOIN public.modelos mo ON mo.id = pf.modelo_id
    WHERE mo.nombre IN ('GU 813 autom','GU813E Mec','GU813E Allison') AND pf.activo
      AND pf.nombre LIKE 'Mack GU813E - Servicio %';
END $$;

-- Resultado
SELECT p.codigo, count(*) AS items,
       count(*) FILTER (WHERE i.foto_obligatoria AND i.tipo_respuesta <> 'firma') AS con_foto,
       count(*) FILTER (WHERE i.tipo_respuesta = 'firma') AS firma
  FROM public.faena_pauta p JOIN public.faena_pauta_item i ON i.pauta_id = p.id
  JOIN public.faenas f ON f.id = p.faena_id
 WHERE f.codigo = 'FAE-FRANCKE' GROUP BY p.codigo ORDER BY p.codigo;
