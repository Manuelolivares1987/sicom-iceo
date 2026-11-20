-- ============================================================================
-- MIG720 — Pauta Mack GU 813 servicio severo (19-11-2026)
-- ----------------------------------------------------------------------------
-- Pedido y aprobado por Manuel (19-11): «cárgala completa»; en Franke el
-- mantenimiento es MIXTO (principalmente en faena, a veces se baja a Coquimbo).
-- Fuente: Pauta Pillado v1.0 (09-11) + datos reales de la flota
-- (research_notes/Pauta Mack severa/ — Excel de la propuesta y datos_flota_mack.md).
--
-- 1. pautas_fabricante (3 modelos Mack): SL/SM1/SM2/SM3 con las tareas nuevas
--    + SM4 (4.800 h), tope en días (30/90/365/730/1460). Escalera de la
--    compañía con absorción: cada nivel trae «<anterior> completo» (MIG494).
--    Se regeneran las plantillas de OT (fn_pauta_a_template versiona si ya
--    se usaron: las OT abiertas no cambian).
-- 2. planes de los 6 Mack: tope en días y SM4; la última ejecución se alinea
--    con la escalera (un SM3 hecho cuenta como SL/SM1/SM2). Los 3 de Franke
--    quedan SIN OT automática (el cron las duplicaría con la agenda de faena);
--    si se bajan a Coquimbo el taller abre la OT como siempre y su cierre
--    avanza el plan (trg_ot_cerrada_avanza_plan).
-- 3. Un servicio CERRADO en la app de faena avanza el plan del camión
--    (trg_faena_ejecucion_avanza_plan): faena y Coquimbo cuentan en la misma
--    escalera.
-- 4. v_faena_pauta_agenda: «lo que ocurra primero» también por días
--    (columna nueva faltan_dias al final).
-- 5. Franke: FRK-PM-300 pasa a ser el SL (0 ejecuciones: se reemplazan sus
--    ítems) + FRK-SM1-600 … FRK-SM4-4800 con los ítems acumulados.
-- 6. FRK-DIA-CP v2: 43 ítems; los actuales se actualizan EN SU LUGAR (hay un
--    borrador que los referencia) y se agregan 15.
-- ============================================================================

-- 1. Pauta del fabricante ---------------------------------------------------
DO $$
DECLARE m RECORD; v_n INT;
BEGIN
  FOR m IN SELECT id, nombre FROM public.modelos WHERE nombre IN ('GU 813 autom','GU813E Mec','GU813E Allison') LOOP
    UPDATE public.pautas_fabricante SET items_checklist = '["Horómetro, odómetro y códigos de falla activos (motor, transmisión, ABS, postratamiento) con lector — Mack PTT / lector", "Cambio de aceite de motor y filtros (2 + 1 adicional). Si la visita es por calendario y van menos de 150 h desde el último cambio: solo nivel + muestra — Mack EOS-4.5 15W40 (38–42 L) · filtros genuinos", "Tomar muestra de aceite de motor para laboratorio (viscosidad, TBN, hollín, metales, combustible, refrigerante) — Kit de muestra", "Drenar agua del separador de combustible; revisar sensor WIF", "Leer indicador de restricción del filtro de aire; reemplazar el primario si está en máximo — Indicador in H2O", "Correas de ventilador y accesorios: grietas, desgaste, tensión", "Refrigerante: nivel y concentración (refractómetro) — Refractómetro", "Radiador, intercooler y condensador: limpieza externa de polvo; mangueras y abrazaderas — Aire a baja presión", "Soportes de motor, fugas de aceite/combustible/refrigerante, arnés", "Nivel y condición del fluido de transmisión (en caliente); fugas; respiradero; temperatura en tablero — Allison TES 668/295 o según placa", "[Solo aljibe de combustible] Toma de fuerza: montaje, fugas, ruido, activación y mando en cabina", "Engrase de cardanes: crucetas, yugos deslizantes, soporte central — Grasa NLGI 2 EP", "Nivel de aceite de diferenciales, respiraderos, retenes de piñón y de cubos", "Engrase de pivotes (king pins), extremos de barra y brazos de dirección — Grasa NLGI 2 EP", "Cubos delanteros: nivel y condición del aceite", "Medir carrera de cámaras / ajustadores automáticos; engrasar ajustadores y levas S-cam — Grasa NLGI 2 EP", "Prueba de fugas de aire, gobernador (corte/entrada), freno de estacionamiento, alarma de baja presión — Manómetro calibrado", "Freno motor: prueba funcional en ruta", "Drenaje de estanques de aire y válvulas de drenaje automáticas", "Presión, desgaste, daños, torque de tuercas de rueda; registrar profundidad de banda — Torquímetro · profundímetro", "Nivel de fluido, bomba, mangueras, caja, juego libre, rótulas y extremos", "Engrase de puntos de suspensión; inspección de paquetes de resortes, hojas y bujes — Grasa NLGI 2 EP", "Baterías: bornes, sujeción, voltaje; alternador y arranque — Voltímetro", "Paradas de emergencia (cabina y zona de despacho) conectadas y funcionando; cableado protegido; caja de fusibles", "Luces, balizas, alarma de retroceso, bocina, limpiaparabrisas, tacógrafo", "[Solo aljibe de combustible] Estanque: fugas, abolladuras, corrosión, soldaduras, anclajes y cunas", "[Solo aljibe de combustible] Válvula de emergencia (de fondo) por compartimiento: cierre primario y remoto, fusible térmico", "[Solo aljibe de combustible] Válvulas de presión/vacío, venteos y arrestallamas de venteo; válvulas de descarga, tapas y candados", "[Solo aljibe de combustible] Escotillas: empaquetaduras, cierres, trabas; carga inferior API y sensor de sobrellenado", "[Solo aljibe de combustible] Bomba de despacho: sello, fugas, ruido, acople, presión/caudal, alivio; limpiar strainer", "[Solo aljibe de combustible] Medidor volumétrico: verificación con serafín y ajuste; precintos; eliminador de aire; registrador/ticket y totalizador — Serafín trazable · OIML R 117 ±0,5 %", "[Solo aljibe de combustible] Filtro/separador de despacho: ΔP, drenaje de agua, sumidero — Manómetro diferencial", "[Solo aljibe de combustible] Mangueras, pistola con cierre automático, acoples, swivels; engrase del carrete — Grasa NLGI 2", "[Solo aljibe de combustible] Puesta a tierra: cable, pinza, carrete; medir continuidad camión–manguera–pinza — Óhmetro (< 10 Ω)", "[Solo aljibe de combustible] Arrestallamas de escape, parachoques, señalización NU 1202, radio, corte general, kit de derrames, pasarela y barandas", "[Solo aljibe de combustible] Inspección mensual DS 298 con registro; documentación y certificados vigentes (hermeticidad, SEC, revisión técnica, calibración) — Control Documental de SICOM", "Prueba de ruta y del sistema de despacho; horómetro de la próxima mantención en el sticker"]'::jsonb, frecuencia_dias = 30, tipo_plan = 'mixto',
           descripcion = 'Servicio severo Mack GU 813 (MIG720): SL 300 h o 30 días, lo que ocurra primero', updated_at = NOW()
     WHERE modelo_id = m.id AND nombre = 'Mack GU813E - Servicio SL (300h)';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN RAISE EXCEPTION 'Modelo %: se esperaba 1 pauta SL y hay %', m.nombre, v_n; END IF;
    UPDATE public.pautas_fabricante SET items_checklist = '["SL completo", "Filtros de combustible: primario/separador y secundario — Filtros genuinos Mack", "Filtro de aire primario: reemplazo (antes si el indicador está en máximo) — Filtro genuino", "Filtro de venteo del estanque de combustible del chasis — Filtro genuino", "Embrague de ventilador, bomba de agua (orificio testigo)", "Escape, abrazaderas, sensores NOx/temperatura/ΔP; nivel y calidad de DEF — Refractómetro DEF 32,5 %", "Enfriador de transmisión, líneas, conectores, selector, códigos TCM — Allison DOC / Mack PTT", "Cardanes: juego de crucetas, torque de pernos, soporte central — Torquímetro", "Bloqueo de diferencial / divisor de potencia: prueba funcional", "Espesor de balatas, tambores, resortes, pasadores, cámaras", "Tiempo de recuperación del compresor (build-up)", "Mangueras, cañerías y conexiones neumáticas", "ABS: códigos, sensores de rueda, anillos dentados, cableado — Herramienta de diagnóstico", "Rotación / evaluación de reemplazo", "Torque de pernos U, bujes, amortiguadores, barras, soportes — Torquímetro", "Bastidor: fisuras, pernos sueltos, travesaños; soportes, cunas y pernos U del estanque — Torquímetro", "Conectores eléctricos: corrosión, seguros, grasa dieléctrica — Grasa dieléctrica", "Filtro de cabina, cinturones, espejos, parabrisas, asiento, extintor de cabina — Filtro de cabina", "[Solo aljibe de combustible] Cambio de elementos del filtro de despacho — Elementos según fabricante", "[Solo aljibe de combustible] Extintores PQS (2 × 40 BC): revisión semestral, presión, sello, fecha", "[Solo aljibe de combustible] Sistema de recuperación de vapores (si existe)"]'::jsonb, frecuencia_dias = 90, tipo_plan = 'mixto',
           descripcion = 'Servicio severo Mack GU 813 (MIG720): SM1 600 h o 90 días, lo que ocurra primero', updated_at = NOW()
     WHERE modelo_id = m.id AND nombre = 'Mack GU813E - Servicio SM1 (600h)';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN RAISE EXCEPTION 'Modelo %: se esperaba 1 pauta SM1 y hay %', m.nombre, v_n; END IF;
    UPDATE public.pautas_fabricante SET items_checklist = '["SM1 completo", "Cambio de aceite de diferenciales delantero + divisor y trasero — 80W90 / GO-J Plus (18 L + 15 L)", "Limpieza de respiraderos de diferenciales", "Filtro de aire secundario (de seguridad) — Filtro genuino", "Correas de ventilador y accesorios + tensor y poleas — Correas genuinas", "Filtro de ventilación del cárter (CCV) — Filtro genuino", "Filtro de refrigerante / acondicionador — Según refrigerante instalado", "Prueba de estanqueidad del intercooler (CAC) y ductos — Kit CAC", "Turbocompresor: juego axial/radial, fugas, actuador VGT", "Compresor de aire: aceite en líneas, culata, descarga", "Rodamientos de ruedas: juego, retenes, ajuste; cambio de aceite de cubos", "Alineación de los 3 ejes — Equipo de alineación", "Secador de aire: cartucho — Cartucho Bendix/Mack", "Fluido y filtro de dirección hidráulica — Según manual Mack", "Prueba de carga de baterías y salida de alternador — Probador de carga", "[Solo aljibe de combustible] Interior de compartimentos: mamparos, corrosión, sedimentos, agua; limpieza — Procedimiento de espacio confinado", "[Solo aljibe de combustible] Bomba de despacho: sello mecánico, rodamientos, empaquetaduras; verificar caudal — Kit de sello", "[Solo aljibe de combustible] Calibración certificada del sistema de medición y re-sellado — Laboratorio trazable", "[Solo aljibe de combustible] Prueba de presión de mangueras de despacho — 1,5 × presión máxima"]'::jsonb, frecuencia_dias = 365, tipo_plan = 'mixto',
           descripcion = 'Servicio severo Mack GU 813 (MIG720): SM2 1200 h o 365 días, lo que ocurra primero', updated_at = NOW()
     WHERE modelo_id = m.id AND nombre = 'Mack GU813E - Servicio SM2 (1200h)';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN RAISE EXCEPTION 'Modelo %: se esperaba 1 pauta SM2 y hay %', m.nombre, v_n; END IF;
    UPDATE public.pautas_fabricante SET items_checklist = '["SM2 completo", "Ajuste de válvulas y freno motor — Manual MP8", "Filtros de transmisión (principal + lubricación) — Allison; caja mecánica/mDRIVE: aceite según placa — Allison TES 668/295 · confirmar tipo de caja", "Limpieza del estanque de combustible del chasis", "Cambio de refrigerante si es formulado (larga vida: SM4) — 50/50 (57 L)"]'::jsonb, frecuencia_dias = 730, tipo_plan = 'mixto',
           descripcion = 'Servicio severo Mack GU 813 (MIG720): SM3 2400 h o 730 días, lo que ocurra primero', updated_at = NOW()
     WHERE modelo_id = m.id AND nombre = 'Mack GU813E - Servicio SM3 (2400h)';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 1 THEN RAISE EXCEPTION 'Modelo %: se esperaba 1 pauta SM3 y hay %', m.nombre, v_n; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.pautas_fabricante WHERE modelo_id = m.id AND nombre = 'Mack GU813E - Servicio SM4 (4800h)') THEN
      INSERT INTO public.pautas_fabricante (modelo_id, nombre, tipo_plan, frecuencia_horas, frecuencia_dias, descripcion,
                                            items_checklist, duracion_estimada_hrs, activo, duracion_es_estimada)
      VALUES (m.id, 'Mack GU813E - Servicio SM4 (4800h)', 'mixto', 4800, 1460,
              'Servicio severo Mack GU 813 (MIG720): SM4 4800 h o 1460 días, lo que ocurra primero', '["SM3 completo", "Cambio de fluido de transmisión — Allison TES 668/295 (~48 L) o según placa", "Cambio de refrigerante larga vida — ELC", "DPF: limpieza; electrodo y tobera; inyector AHI; filtros y drenaje DEF — Genuinos"]'::jsonb, 16, TRUE, TRUE);
    END IF;
  END LOOP;
  -- Plantillas de OT (versiona las que ya tienen OT: las abiertas no cambian).
  PERFORM public.fn_pauta_a_template(pf.id)
     FROM public.pautas_fabricante pf JOIN public.modelos mo ON mo.id = pf.modelo_id
    WHERE mo.nombre IN ('GU 813 autom','GU813E Mec','GU813E Allison') AND pf.activo
      AND pf.nombre LIKE 'Mack GU813E - Servicio %';
END $$;

-- 2. Planes de los 6 Mack --------------------------------------------------------
DO $$
DECLARE v_n INT;
BEGIN
  -- Tope en días y tipo mixto, copiados de la pauta (los planes copian la frecuencia).
  UPDATE public.planes_mantenimiento pm
     SET frecuencia_dias = pf.frecuencia_dias, tipo_plan = 'mixto', updated_at = NOW()
    FROM public.pautas_fabricante pf
   WHERE pm.pauta_fabricante_id = pf.id AND pf.nombre LIKE 'Mack GU813E - Servicio %';

  -- SM4 para cada Mack que tiene la escalera (base = su último servicio registrado).
  INSERT INTO public.planes_mantenimiento (activo_id, pauta_fabricante_id, nombre, tipo_plan, frecuencia_horas, frecuencia_dias,
                                           anticipacion_dias, prioridad, ultima_ejecucion_fecha, ultima_ejecucion_km,
                                           ultima_ejecucion_horas, activo_plan)
  SELECT sl.activo_id, sm4.id, sm4.nombre, 'mixto', 4800, 1460, sl.anticipacion_dias, sl.prioridad,
         b.ultima_ejecucion_fecha, b.ultima_ejecucion_km, b.ultima_ejecucion_horas, sl.activo_plan
    FROM public.planes_mantenimiento sl
    JOIN public.pautas_fabricante psl ON psl.id = sl.pauta_fabricante_id AND psl.nombre = 'Mack GU813E - Servicio SL (300h)'
    JOIN public.pautas_fabricante sm4 ON sm4.modelo_id = psl.modelo_id AND sm4.nombre = 'Mack GU813E - Servicio SM4 (4800h)'
    CROSS JOIN LATERAL (SELECT x.ultima_ejecucion_fecha, x.ultima_ejecucion_km, x.ultima_ejecucion_horas
                          FROM public.planes_mantenimiento x
                         WHERE x.activo_id = sl.activo_id AND x.ultima_ejecucion_horas > 0
                         ORDER BY (x.frecuencia_horas >= 2400) DESC, x.ultima_ejecucion_horas DESC LIMIT 1) b
   WHERE NOT EXISTS (SELECT 1 FROM public.planes_mantenimiento z WHERE z.activo_id = sl.activo_id AND z.pauta_fabricante_id = sm4.id);
  GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'SM4 creados: %', v_n;

  -- Absorción en la línea base: un servicio mayor hecho cuenta para los menores
  -- (frecuencia múltiplo). Nunca hacia atrás.
  UPDATE public.planes_mantenimiento p
     SET (ultima_ejecucion_horas, ultima_ejecucion_km, ultima_ejecucion_fecha) = (
            SELECT x.ultima_ejecucion_horas, COALESCE(x.ultima_ejecucion_km, p.ultima_ejecucion_km),
                   COALESCE(x.ultima_ejecucion_fecha, p.ultima_ejecucion_fecha)
              FROM public.planes_mantenimiento x
             WHERE x.activo_id = p.activo_id AND x.frecuencia_horas > 0 AND x.ultima_ejecucion_horas > 0
               AND x.frecuencia_horas % p.frecuencia_horas = 0
             ORDER BY x.ultima_ejecucion_horas DESC LIMIT 1),
         updated_at = NOW()
   WHERE p.frecuencia_horas > 0
     AND p.activo_id IN (SELECT pm.activo_id FROM public.planes_mantenimiento pm
                           JOIN public.pautas_fabricante pf ON pf.id = pm.pauta_fabricante_id
                          WHERE pf.nombre LIKE 'Mack GU813E - Servicio %')
     AND COALESCE(p.ultima_ejecucion_horas, 0) < (
            SELECT max(x.ultima_ejecucion_horas) FROM public.planes_mantenimiento x
             WHERE x.activo_id = p.activo_id AND x.frecuencia_horas > 0
               AND x.frecuencia_horas % p.frecuencia_horas = 0);
  GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Bases alineadas por absorción: %', v_n;

  -- Franke: sin OT automáticas (mixto, principalmente en faena).
  UPDATE public.planes_mantenimiento pm SET activo_plan = FALSE, updated_at = NOW()
    FROM public.activos a JOIN public.faenas f ON f.id = a.faena_id
   WHERE pm.activo_id = a.id AND f.codigo = 'FAE-FRANCKE' AND pm.frecuencia_horas > 0 AND pm.activo_plan;
  GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Planes Franke sin OT automática: %', v_n;
END $$;

-- 3. Servicio cerrado en faena avanza el plan ----------------------------------
CREATE OR REPLACE FUNCTION public.fn_faena_ejecucion_avanza_plan()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE p RECORD;
BEGIN
    IF NEW.estado IS DISTINCT FROM 'cerrada' OR (TG_OP = 'UPDATE' AND OLD.estado = 'cerrada') THEN
        RETURN NEW;
    END IF;
    SELECT tipo, disparo_horas, disparo_km INTO p FROM public.faena_pauta WHERE id = NEW.pauta_id;
    IF p.tipo IS DISTINCT FROM 'programada' THEN RETURN NEW; END IF;

    -- Escalera con absorción: avanza el plan de igual frecuencia y los menores
    -- (frecuencia que divide al disparo). Nunca hacia atrás.
    IF p.disparo_horas IS NOT NULL AND NEW.horometro > 0 THEN
        UPDATE public.planes_mantenimiento pm
           SET ultima_ejecucion_horas = NEW.horometro,
               ultima_ejecucion_km    = COALESCE(NULLIF(NEW.kilometraje, 0), pm.ultima_ejecucion_km),
               ultima_ejecucion_fecha = NEW.fecha,
               updated_at = NOW()
         WHERE pm.activo_id = NEW.activo_id AND pm.frecuencia_horas > 0
           AND p.disparo_horas % pm.frecuencia_horas = 0
           AND COALESCE(pm.ultima_ejecucion_horas, 0) < NEW.horometro;
    ELSIF p.disparo_km IS NOT NULL AND NEW.kilometraje > 0 THEN
        UPDATE public.planes_mantenimiento pm
           SET ultima_ejecucion_km = NEW.kilometraje,
               ultima_ejecucion_horas = COALESCE(NULLIF(NEW.horometro, 0), pm.ultima_ejecucion_horas),
               ultima_ejecucion_fecha = NEW.fecha,
               updated_at = NOW()
         WHERE pm.activo_id = NEW.activo_id AND pm.frecuencia_km > 0
           AND p.disparo_km % pm.frecuencia_km = 0
           AND COALESCE(pm.ultima_ejecucion_km, 0) < NEW.kilometraje;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_faena_ejecucion_avanza_plan ON public.faena_pauta_ejecucion;
CREATE TRIGGER trg_faena_ejecucion_avanza_plan
    AFTER INSERT OR UPDATE OF estado ON public.faena_pauta_ejecucion
    FOR EACH ROW EXECUTE FUNCTION public.fn_faena_ejecucion_avanza_plan();

-- 4. Agenda de faena: también por días ------------------------------------------
CREATE OR REPLACE VIEW public.v_faena_pauta_agenda AS
SELECT a.faena_id,
    a.id AS activo_id,
    a.codigo AS activo_codigo,
    a.patente,
    a.nombre AS activo_nombre,
    a.estado AS activo_estado,
    mo.nombre AS modelo,
    a.horas_uso_actual,
    a.kilometraje_actual,
    p.id AS pauta_id,
    p.codigo AS pauta_codigo,
    p.nombre AS pauta_nombre,
    p.tipo AS pauta_tipo,
    p.disparo_horas,
    p.disparo_km,
    p.aviso_horas,
    p.aviso_km,
    (( SELECT count(*) AS count
           FROM faena_pauta_item i
          WHERE i.pauta_id = p.id))::integer AS items,
    u.horometro AS ultima_horometro,
    u.kilometraje AS ultima_kilometraje,
    u.fecha AS ultima_fecha,
    u.origen AS origen_ultima,
        CASE
            WHEN p.disparo_horas IS NOT NULL THEN round(u.horometro + p.disparo_horas - COALESCE(a.horas_uso_actual, 0::numeric), 1)
            ELSE NULL::numeric
        END AS faltan_horas,
        CASE
            WHEN p.disparo_km IS NOT NULL THEN round(u.kilometraje + p.disparo_km - COALESCE(a.kilometraje_actual, 0::numeric), 1)
            ELSE NULL::numeric
        END AS faltan_km,
        CASE
            WHEN p.tipo = 'diaria'::text THEN 'diaria'::text
            WHEN u.horometro IS NULL AND u.kilometraje IS NULL THEN 'sin_datos'::text
            WHEN p.disparo_horas IS NOT NULL AND (u.horometro + p.disparo_horas) <= COALESCE(a.horas_uso_actual, 0::numeric)
              OR p.disparo_km IS NOT NULL AND (u.kilometraje + p.disparo_km) <= COALESCE(a.kilometraje_actual, 0::numeric)
              OR p.disparo_dias IS NOT NULL AND u.fecha IS NOT NULL AND (u.fecha::date + p.disparo_dias) <= CURRENT_DATE THEN 'vencida'::text
            WHEN p.disparo_horas IS NOT NULL AND (u.horometro + p.disparo_horas - COALESCE(a.horas_uso_actual, 0::numeric)) <= p.aviso_horas
              OR p.disparo_km IS NOT NULL AND (u.kilometraje + p.disparo_km - COALESCE(a.kilometraje_actual, 0::numeric)) <= p.aviso_km
              OR p.disparo_dias IS NOT NULL AND u.fecha IS NOT NULL AND (u.fecha::date + p.disparo_dias) - CURRENT_DATE <= 7 THEN 'por_vencer'::text
            ELSE 'al_dia'::text
        END AS senal,
    hoy.id AS ejecucion_hoy_id,
    hoy.estado AS ejecucion_hoy_estado,
    hoy.turno AS ejecucion_hoy_turno,
    hoy.ejecutado_por_nombre AS ejecucion_hoy_por,
        CASE
            WHEN p.disparo_dias IS NOT NULL AND u.fecha IS NOT NULL THEN (u.fecha::date + p.disparo_dias) - CURRENT_DATE
            ELSE NULL::integer
        END AS faltan_dias
   FROM activos a
     JOIN faena_pauta p ON p.faena_id = a.faena_id AND p.activo AND (p.modelo_id IS NULL OR p.modelo_id = a.modelo_id)
     LEFT JOIN modelos mo ON mo.id = a.modelo_id
     -- Última pauta de faena cerrada.
     LEFT JOIN LATERAL ( SELECT e.horometro,
            e.kilometraje,
            e.fecha
           FROM faena_pauta_ejecucion e
          WHERE e.pauta_id = p.id AND e.activo_id = a.id AND e.estado = 'cerrada'::text
          ORDER BY e.fecha DESC, e.cerrada_at DESC
         LIMIT 1) ult ON true
     -- Último servicio de Coquimbo que cubre el disparo (frecuencia múltiplo).
     LEFT JOIN LATERAL ( SELECT pm2.id,
            pm2.ultima_ejecucion_horas,
            pm2.ultima_ejecucion_km,
            pm2.ultima_ejecucion_fecha
           FROM planes_mantenimiento pm2
          WHERE pm2.activo_id = a.id
            AND (   (p.disparo_horas IS NOT NULL AND pm2.frecuencia_horas IS NOT NULL AND pm2.frecuencia_horas > 0
                     AND pm2.frecuencia_horas % p.disparo_horas = 0 AND pm2.ultima_ejecucion_horas IS NOT NULL)
                 OR (p.disparo_km IS NOT NULL AND pm2.frecuencia_km IS NOT NULL AND pm2.frecuencia_km > 0
                     AND pm2.frecuencia_km % p.disparo_km = 0 AND pm2.ultima_ejecucion_km IS NOT NULL))
          ORDER BY CASE WHEN p.disparo_horas IS NOT NULL THEN pm2.ultima_ejecucion_horas ELSE pm2.ultima_ejecucion_km END DESC NULLS LAST,
                   pm2.ultima_ejecucion_fecha DESC NULLS LAST
         LIMIT 1) pm ON true
     -- Gana la más nueva de las dos.
     LEFT JOIN LATERAL ( SELECT
            CASE WHEN usa_plan THEN COALESCE(pm.ultima_ejecucion_horas, ult.horometro) ELSE COALESCE(ult.horometro, pm.ultima_ejecucion_horas) END AS horometro,
            CASE WHEN usa_plan THEN COALESCE(pm.ultima_ejecucion_km, ult.kilometraje) ELSE COALESCE(ult.kilometraje, pm.ultima_ejecucion_km) END AS kilometraje,
            CASE WHEN usa_plan THEN COALESCE(pm.ultima_ejecucion_fecha, ult.fecha::timestamp with time zone) ELSE COALESCE(ult.fecha::timestamp with time zone, pm.ultima_ejecucion_fecha) END AS fecha,
            CASE WHEN usa_plan THEN 'plan'::text ELSE 'ejecucion'::text END AS origen
           FROM ( SELECT pm.id IS NOT NULL AND NOT COALESCE(
                        CASE WHEN p.disparo_horas IS NOT NULL THEN ult.horometro >= pm.ultima_ejecucion_horas
                             ELSE ult.kilometraje >= pm.ultima_ejecucion_km END, false) AS usa_plan) s
         ) u ON true
     LEFT JOIN LATERAL ( SELECT e2.id,
            e2.estado,
            e2.turno,
            e2.ejecutado_por_nombre
           FROM faena_pauta_ejecucion e2
          WHERE e2.pauta_id = p.id AND e2.activo_id = a.id AND e2.fecha = CURRENT_DATE
          ORDER BY e2.updated_at DESC
         LIMIT 1) hoy ON true
  WHERE a.fecha_baja IS NULL;

-- 5. Franke: SL…SM4 en la app del mecánico ---------------------------------------
DO $$
DECLARE v_faena UUID := (SELECT id FROM public.faenas WHERE codigo = 'FAE-FRANCKE');
        v_modelo UUID := (SELECT modelo_id FROM public.faena_pauta WHERE codigo = 'FRK-PM-300');
        v_pid UUID; v_ej INT;
BEGIN
  SELECT count(*) INTO v_ej FROM public.faena_pauta_ejecucion e JOIN public.faena_pauta p ON p.id = e.pauta_id WHERE p.codigo = 'FRK-PM-300';
  IF v_ej > 0 THEN RAISE EXCEPTION 'FRK-PM-300 ya tiene % ejecuciones: no se reemplazan sus ítems', v_ej; END IF;
  UPDATE public.faena_pauta SET nombre = 'Servicio SL 300 h · Mack GU 813 (severo)', disparo_horas = 300, disparo_dias = 30, activo = TRUE,
         observacion = 'MIG720: escalera severa (SL de la escalera; absorción por SM1…SM4)', updated_at = NOW()
   WHERE codigo = 'FRK-PM-300' RETURNING id INTO v_pid;
  DELETE FROM public.faena_pauta_item WHERE pauta_id = v_pid;
  INSERT INTO public.faena_pauta_item (pauta_id, orden, bloque, texto, tipo_respuesta, unidad, obligatorio, foto_si_nok, critico, repuesto, ayuda) VALUES
    (v_pid, 10, 'Lecturas', 'Horómetro al iniciar el servicio', 'numero', 'h', TRUE, FALSE, FALSE, NULL, NULL),
    (v_pid, 20, 'Lecturas', 'Kilometraje al iniciar el servicio', 'numero', 'km', TRUE, FALSE, FALSE, NULL, NULL),
    (v_pid, 30, 'Lecturas', 'Códigos de falla activos (motor, transmisión, ABS, postratamiento) leídos con lector y registrados', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Mack PTT / lector; Por qué: Códigos ABS/motor/transmisión activos en HHWB-42/44 sin registro'),
    (v_pid, 40, 'Motor', 'Cambio de aceite de motor y filtros (2 + 1 adicional). Si la visita es por calendario y van menos de 150 h desde el último cambio: solo nivel + muestra', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Mack EOS-4.5 15W40 (38–42 L) · filtros genuinos', 'Especificación: Mack EOS-4.5 15W40 (38–42 L) · filtros genuinos; Por qué: Servicio severo (>30 % ralentí); sin análisis de aceite no se extiende'),
    (v_pid, 50, 'Motor', 'Tomar muestra de aceite de motor para laboratorio (viscosidad, TBN, hollín, metales, combustible, refrigerante)', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Kit de muestra; Por qué: Habilita extender el aceite a 600 h con 3 análisis OK'),
    (v_pid, 60, 'Motor', 'Drenar agua del separador de combustible; revisar sensor WIF', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 70, 'Motor', 'Leer indicador de restricción del filtro de aire; reemplazar el primario si está en máximo', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Indicador in H2O; Por qué: Polvo de faena'),
    (v_pid, 80, 'Motor', 'Correas de ventilador y accesorios: grietas, desgaste, tensión', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 90, 'Motor', 'Refrigerante: nivel y concentración (refractómetro)', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Refractómetro'),
    (v_pid, 100, 'Motor', 'Radiador, intercooler y condensador: limpieza externa de polvo; mangueras y abrazaderas', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Aire a baja presión; Por qué: Polvo de faena'),
    (v_pid, 110, 'Motor', 'Soportes de motor, fugas de aceite/combustible/refrigerante, arnés', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 120, 'Transmisión', 'Nivel y condición del fluido de transmisión (en caliente); fugas; respiradero; temperatura en tablero', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Allison TES 668/295 o según placa; Por qué: HHWB-42 sin temperatura de transmisión en tablero'),
    (v_pid, 130, 'PTO', 'Toma de fuerza: montaje, fugas, ruido, activación y mando en cabina', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: La PTO mueve la bomba: su falla detiene el despacho'),
    (v_pid, 140, 'Tren motriz', 'Engrase de cardanes: crucetas, yugos deslizantes, soporte central', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Grasa NLGI 2 EP', 'Especificación: Grasa NLGI 2 EP'),
    (v_pid, 150, 'Tren motriz', 'Nivel de aceite de diferenciales, respiraderos, retenes de piñón y de cubos', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: 4 retenes de cubo pedidos en HHWB-44'),
    (v_pid, 160, 'Tren motriz', 'Engrase de pivotes (king pins), extremos de barra y brazos de dirección', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Grasa NLGI 2 EP', 'Especificación: Grasa NLGI 2 EP'),
    (v_pid, 170, 'Tren motriz', 'Cubos delanteros: nivel y condición del aceite', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 180, 'Frenos', 'Medir carrera de cámaras / ajustadores automáticos; engrasar ajustadores y levas S-cam', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Grasa NLGI 2 EP; Por qué: Frenado brusco en HHWB-44'),
    (v_pid, 190, 'Frenos', 'Prueba de fugas de aire, gobernador (corte/entrada), freno de estacionamiento, alarma de baja presión', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Manómetro calibrado'),
    (v_pid, 200, 'Frenos', 'Freno motor: prueba funcional en ruta', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: Freno motor débil en HHWB-44'),
    (v_pid, 210, 'Frenos', 'Drenaje de estanques de aire y válvulas de drenaje automáticas', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 220, 'Neumáticos', 'Presión, desgaste, daños, torque de tuercas de rueda; registrar profundidad de banda', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro · profundímetro; Por qué: No hay registro de profundidad de banda'),
    (v_pid, 230, 'Dirección', 'Nivel de fluido, bomba, mangueras, caja, juego libre, rótulas y extremos', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 240, 'Suspensión', 'Engrase de puntos de suspensión; inspección de paquetes de resortes, hojas y bujes', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Grasa NLGI 2 EP', 'Especificación: Grasa NLGI 2 EP; Por qué: Paquete de resortes roto y bujes en HHWB-44'),
    (v_pid, 250, 'Eléctrico', 'Baterías: bornes, sujeción, voltaje; alternador y arranque', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Voltímetro'),
    (v_pid, 260, 'Eléctrico', 'Paradas de emergencia (cabina y zona de despacho) conectadas y funcionando; cableado protegido; caja de fusibles', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: 9 de 33 fallas de HHWB-44 fueron eléctricas, incluidas las 2 paradas de emergencia desconectadas'),
    (v_pid, 270, 'Eléctrico', 'Luces, balizas, alarma de retroceso, bocina, limpiaparabrisas, tacógrafo', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 298'),
    (v_pid, 280, 'Estanque', 'Estanque: fugas, abolladuras, corrosión, soldaduras, anclajes y cunas', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160 art. 177 d) y 203'),
    (v_pid, 290, 'Válvulas', 'Válvula de emergencia (de fondo) por compartimiento: cierre primario y remoto, fusible térmico', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: DS 160 art. 186'),
    (v_pid, 300, 'Válvulas', 'Válvulas de presión/vacío, venteos y arrestallamas de venteo; válvulas de descarga, tapas y candados', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: DS 160'),
    (v_pid, 310, 'Estanque', 'Escotillas: empaquetaduras, cierres, trabas; carga inferior API y sensor de sobrellenado', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160'),
    (v_pid, 320, 'Bomba', 'Bomba de despacho: sello, fugas, ruido, acople, presión/caudal, alivio; limpiar strainer', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 330, 'Medición', 'Medidor volumétrico: verificación con serafín y ajuste; precintos; eliminador de aire; registrador/ticket y totalizador', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Serafín trazable · OIML R 117 ±0,5 %; Por qué: Medidor y Liquid Control con lectura errónea en HHWB-44'),
    (v_pid, 340, 'Filtración', 'Filtro/separador de despacho: ΔP, drenaje de agua, sumidero', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Manómetro diferencial'),
    (v_pid, 350, 'Mangueras', 'Mangueras, pistola con cierre automático, acoples, swivels; engrase del carrete', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Grasa NLGI 2; Por qué: DS 160 art. 200'),
    (v_pid, 360, 'Puesta a tierra', 'Puesta a tierra: cable, pinza, carrete; medir continuidad camión–manguera–pinza', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Óhmetro (< 10 Ω); Por qué: DS 160 art. 190'),
    (v_pid, 370, 'Seguridad', 'Arrestallamas de escape, parachoques, señalización NU 1202, radio, corte general, kit de derrames, pasarela y barandas', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160 / DS 298'),
    (v_pid, 380, 'Cumplimiento', 'Inspección mensual DS 298 con registro; documentación y certificados vigentes (hermeticidad, SEC, revisión técnica, calibración)', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Control Documental de SICOM; Por qué: LCSX-78 opera con certificados vencidos'),
    (v_pid, 390, 'Cierre', 'Prueba de ruta y del sistema de despacho', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 400, 'Cierre', 'Horómetro de la próxima mantención en el sticker', 'numero', 'h', TRUE, FALSE, FALSE, 'Sticker de mantención', 'El horómetro de hoy más 300 h.');
  SELECT id INTO v_pid FROM public.faena_pauta WHERE faena_id = v_faena AND codigo = 'FRK-SM1-600';
  IF v_pid IS NULL THEN
    INSERT INTO public.faena_pauta (faena_id, codigo, nombre, tipo, modelo_id, disparo_horas, disparo_dias, aviso_horas, activo, observacion)
    VALUES (v_faena, 'FRK-SM1-600', 'Servicio SM1 600 h · Mack GU 813 (severo)', 'programada', v_modelo, 600, 90, 50, TRUE, 'MIG720: incluye completos los niveles menores')
    RETURNING id INTO v_pid;
  ELSE DELETE FROM public.faena_pauta_item WHERE pauta_id = v_pid; END IF;
  INSERT INTO public.faena_pauta_item (pauta_id, orden, bloque, texto, tipo_respuesta, unidad, obligatorio, foto_si_nok, critico, repuesto, ayuda) VALUES
    (v_pid, 10, 'Lecturas', 'Horómetro al iniciar el servicio', 'numero', 'h', TRUE, FALSE, FALSE, NULL, NULL),
    (v_pid, 20, 'Lecturas', 'Kilometraje al iniciar el servicio', 'numero', 'km', TRUE, FALSE, FALSE, NULL, NULL),
    (v_pid, 30, 'SL · Lecturas', 'Códigos de falla activos (motor, transmisión, ABS, postratamiento) leídos con lector y registrados', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Mack PTT / lector; Por qué: Códigos ABS/motor/transmisión activos en HHWB-42/44 sin registro'),
    (v_pid, 40, 'SL · Motor', 'Cambio de aceite de motor y filtros (2 + 1 adicional). Si la visita es por calendario y van menos de 150 h desde el último cambio: solo nivel + muestra', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Mack EOS-4.5 15W40 (38–42 L) · filtros genuinos', 'Especificación: Mack EOS-4.5 15W40 (38–42 L) · filtros genuinos; Por qué: Servicio severo (>30 % ralentí); sin análisis de aceite no se extiende'),
    (v_pid, 50, 'SL · Motor', 'Tomar muestra de aceite de motor para laboratorio (viscosidad, TBN, hollín, metales, combustible, refrigerante)', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Kit de muestra; Por qué: Habilita extender el aceite a 600 h con 3 análisis OK'),
    (v_pid, 60, 'SL · Motor', 'Drenar agua del separador de combustible; revisar sensor WIF', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 70, 'SL · Motor', 'Leer indicador de restricción del filtro de aire; reemplazar el primario si está en máximo', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Indicador in H2O; Por qué: Polvo de faena'),
    (v_pid, 80, 'SL · Motor', 'Correas de ventilador y accesorios: grietas, desgaste, tensión', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 90, 'SL · Motor', 'Refrigerante: nivel y concentración (refractómetro)', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Refractómetro'),
    (v_pid, 100, 'SL · Motor', 'Radiador, intercooler y condensador: limpieza externa de polvo; mangueras y abrazaderas', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Aire a baja presión; Por qué: Polvo de faena'),
    (v_pid, 110, 'SL · Motor', 'Soportes de motor, fugas de aceite/combustible/refrigerante, arnés', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 120, 'SL · Transmisión', 'Nivel y condición del fluido de transmisión (en caliente); fugas; respiradero; temperatura en tablero', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Allison TES 668/295 o según placa; Por qué: HHWB-42 sin temperatura de transmisión en tablero'),
    (v_pid, 130, 'SL · PTO', 'Toma de fuerza: montaje, fugas, ruido, activación y mando en cabina', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: La PTO mueve la bomba: su falla detiene el despacho'),
    (v_pid, 140, 'SL · Tren motriz', 'Engrase de cardanes: crucetas, yugos deslizantes, soporte central', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Grasa NLGI 2 EP', 'Especificación: Grasa NLGI 2 EP'),
    (v_pid, 150, 'SL · Tren motriz', 'Nivel de aceite de diferenciales, respiraderos, retenes de piñón y de cubos', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: 4 retenes de cubo pedidos en HHWB-44'),
    (v_pid, 160, 'SL · Tren motriz', 'Engrase de pivotes (king pins), extremos de barra y brazos de dirección', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Grasa NLGI 2 EP', 'Especificación: Grasa NLGI 2 EP'),
    (v_pid, 170, 'SL · Tren motriz', 'Cubos delanteros: nivel y condición del aceite', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 180, 'SL · Frenos', 'Medir carrera de cámaras / ajustadores automáticos; engrasar ajustadores y levas S-cam', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Grasa NLGI 2 EP; Por qué: Frenado brusco en HHWB-44'),
    (v_pid, 190, 'SL · Frenos', 'Prueba de fugas de aire, gobernador (corte/entrada), freno de estacionamiento, alarma de baja presión', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Manómetro calibrado'),
    (v_pid, 200, 'SL · Frenos', 'Freno motor: prueba funcional en ruta', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: Freno motor débil en HHWB-44'),
    (v_pid, 210, 'SL · Frenos', 'Drenaje de estanques de aire y válvulas de drenaje automáticas', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 220, 'SL · Neumáticos', 'Presión, desgaste, daños, torque de tuercas de rueda; registrar profundidad de banda', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro · profundímetro; Por qué: No hay registro de profundidad de banda'),
    (v_pid, 230, 'SL · Dirección', 'Nivel de fluido, bomba, mangueras, caja, juego libre, rótulas y extremos', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 240, 'SL · Suspensión', 'Engrase de puntos de suspensión; inspección de paquetes de resortes, hojas y bujes', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Grasa NLGI 2 EP', 'Especificación: Grasa NLGI 2 EP; Por qué: Paquete de resortes roto y bujes en HHWB-44'),
    (v_pid, 250, 'SL · Eléctrico', 'Baterías: bornes, sujeción, voltaje; alternador y arranque', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Voltímetro'),
    (v_pid, 260, 'SL · Eléctrico', 'Paradas de emergencia (cabina y zona de despacho) conectadas y funcionando; cableado protegido; caja de fusibles', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: 9 de 33 fallas de HHWB-44 fueron eléctricas, incluidas las 2 paradas de emergencia desconectadas'),
    (v_pid, 270, 'SL · Eléctrico', 'Luces, balizas, alarma de retroceso, bocina, limpiaparabrisas, tacógrafo', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 298'),
    (v_pid, 280, 'SL · Estanque', 'Estanque: fugas, abolladuras, corrosión, soldaduras, anclajes y cunas', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160 art. 177 d) y 203'),
    (v_pid, 290, 'SL · Válvulas', 'Válvula de emergencia (de fondo) por compartimiento: cierre primario y remoto, fusible térmico', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: DS 160 art. 186'),
    (v_pid, 300, 'SL · Válvulas', 'Válvulas de presión/vacío, venteos y arrestallamas de venteo; válvulas de descarga, tapas y candados', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: DS 160'),
    (v_pid, 310, 'SL · Estanque', 'Escotillas: empaquetaduras, cierres, trabas; carga inferior API y sensor de sobrellenado', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160'),
    (v_pid, 320, 'SL · Bomba', 'Bomba de despacho: sello, fugas, ruido, acople, presión/caudal, alivio; limpiar strainer', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 330, 'SL · Medición', 'Medidor volumétrico: verificación con serafín y ajuste; precintos; eliminador de aire; registrador/ticket y totalizador', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Serafín trazable · OIML R 117 ±0,5 %; Por qué: Medidor y Liquid Control con lectura errónea en HHWB-44'),
    (v_pid, 340, 'SL · Filtración', 'Filtro/separador de despacho: ΔP, drenaje de agua, sumidero', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Manómetro diferencial'),
    (v_pid, 350, 'SL · Mangueras', 'Mangueras, pistola con cierre automático, acoples, swivels; engrase del carrete', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Grasa NLGI 2; Por qué: DS 160 art. 200'),
    (v_pid, 360, 'SL · Puesta a tierra', 'Puesta a tierra: cable, pinza, carrete; medir continuidad camión–manguera–pinza', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Óhmetro (< 10 Ω); Por qué: DS 160 art. 190'),
    (v_pid, 370, 'SL · Seguridad', 'Arrestallamas de escape, parachoques, señalización NU 1202, radio, corte general, kit de derrames, pasarela y barandas', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160 / DS 298'),
    (v_pid, 380, 'SL · Cumplimiento', 'Inspección mensual DS 298 con registro; documentación y certificados vigentes (hermeticidad, SEC, revisión técnica, calibración)', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Control Documental de SICOM; Por qué: LCSX-78 opera con certificados vencidos'),
    (v_pid, 390, 'SL · Cierre', 'Prueba de ruta y del sistema de despacho', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 400, 'SM1 · Motor', 'Filtros de combustible: primario/separador y secundario', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtros genuinos Mack', 'Especificación: Filtros genuinos Mack'),
    (v_pid, 410, 'SM1 · Motor', 'Filtro de aire primario: reemplazo (antes si el indicador está en máximo)', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtro genuino', 'Especificación: Filtro genuino'),
    (v_pid, 420, 'SM1 · Motor', 'Filtro de venteo del estanque de combustible del chasis', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtro genuino', 'Especificación: Filtro genuino'),
    (v_pid, 430, 'SM1 · Motor', 'Embrague de ventilador, bomba de agua (orificio testigo)', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 440, 'SM1 · Postratamiento', 'Escape, abrazaderas, sensores NOx/temperatura/ΔP; nivel y calidad de DEF', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Refractómetro DEF 32,5 %'),
    (v_pid, 450, 'SM1 · Transmisión', 'Enfriador de transmisión, líneas, conectores, selector, códigos TCM', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Allison DOC / Mack PTT'),
    (v_pid, 460, 'SM1 · Tren motriz', 'Cardanes: juego de crucetas, torque de pernos, soporte central', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro'),
    (v_pid, 470, 'SM1 · Tren motriz', 'Bloqueo de diferencial / divisor de potencia: prueba funcional', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 480, 'SM1 · Frenos', 'Espesor de balatas, tambores, resortes, pasadores, cámaras', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 490, 'SM1 · Frenos', 'Tiempo de recuperación del compresor (build-up)', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 500, 'SM1 · Frenos', 'Mangueras, cañerías y conexiones neumáticas', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 510, 'SM1 · Frenos', 'ABS: códigos, sensores de rueda, anillos dentados, cableado', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Herramienta de diagnóstico; Por qué: Código ABS activo en HHWB-44'),
    (v_pid, 520, 'SM1 · Neumáticos', 'Rotación / evaluación de reemplazo', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 530, 'SM1 · Suspensión', 'Torque de pernos U, bujes, amortiguadores, barras, soportes', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro'),
    (v_pid, 540, 'SM1 · Estructura', 'Bastidor: fisuras, pernos sueltos, travesaños; soportes, cunas y pernos U del estanque', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro; Por qué: Zona crítica en aljibe'),
    (v_pid, 550, 'SM1 · Eléctrico', 'Conectores eléctricos: corrosión, seguros, grasa dieléctrica', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Grasa dieléctrica'),
    (v_pid, 560, 'SM1 · Cabina', 'Filtro de cabina, cinturones, espejos, parabrisas, asiento, extintor de cabina', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Filtro de cabina'),
    (v_pid, 570, 'SM1 · Filtración', 'Cambio de elementos del filtro de despacho', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Elementos según fabricante', 'Especificación: Elementos según fabricante'),
    (v_pid, 580, 'SM1 · Seguridad', 'Extintores PQS (2 × 40 BC): revisión semestral, presión, sello, fecha', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160 art. 198'),
    (v_pid, 590, 'SM1 · Seguridad', 'Sistema de recuperación de vapores (si existe)', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 600, 'Cierre', 'Horómetro de la próxima mantención en el sticker', 'numero', 'h', TRUE, FALSE, FALSE, 'Sticker de mantención', 'El horómetro de hoy más 600 h.');
  SELECT id INTO v_pid FROM public.faena_pauta WHERE faena_id = v_faena AND codigo = 'FRK-SM2-1200';
  IF v_pid IS NULL THEN
    INSERT INTO public.faena_pauta (faena_id, codigo, nombre, tipo, modelo_id, disparo_horas, disparo_dias, aviso_horas, activo, observacion)
    VALUES (v_faena, 'FRK-SM2-1200', 'Servicio SM2 1.200 h · Mack GU 813 (severo)', 'programada', v_modelo, 1200, 365, 50, TRUE, 'MIG720: incluye completos los niveles menores')
    RETURNING id INTO v_pid;
  ELSE DELETE FROM public.faena_pauta_item WHERE pauta_id = v_pid; END IF;
  INSERT INTO public.faena_pauta_item (pauta_id, orden, bloque, texto, tipo_respuesta, unidad, obligatorio, foto_si_nok, critico, repuesto, ayuda) VALUES
    (v_pid, 10, 'Lecturas', 'Horómetro al iniciar el servicio', 'numero', 'h', TRUE, FALSE, FALSE, NULL, NULL),
    (v_pid, 20, 'Lecturas', 'Kilometraje al iniciar el servicio', 'numero', 'km', TRUE, FALSE, FALSE, NULL, NULL),
    (v_pid, 30, 'SL · Lecturas', 'Códigos de falla activos (motor, transmisión, ABS, postratamiento) leídos con lector y registrados', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Mack PTT / lector; Por qué: Códigos ABS/motor/transmisión activos en HHWB-42/44 sin registro'),
    (v_pid, 40, 'SL · Motor', 'Cambio de aceite de motor y filtros (2 + 1 adicional). Si la visita es por calendario y van menos de 150 h desde el último cambio: solo nivel + muestra', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Mack EOS-4.5 15W40 (38–42 L) · filtros genuinos', 'Especificación: Mack EOS-4.5 15W40 (38–42 L) · filtros genuinos; Por qué: Servicio severo (>30 % ralentí); sin análisis de aceite no se extiende'),
    (v_pid, 50, 'SL · Motor', 'Tomar muestra de aceite de motor para laboratorio (viscosidad, TBN, hollín, metales, combustible, refrigerante)', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Kit de muestra; Por qué: Habilita extender el aceite a 600 h con 3 análisis OK'),
    (v_pid, 60, 'SL · Motor', 'Drenar agua del separador de combustible; revisar sensor WIF', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 70, 'SL · Motor', 'Leer indicador de restricción del filtro de aire; reemplazar el primario si está en máximo', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Indicador in H2O; Por qué: Polvo de faena'),
    (v_pid, 80, 'SL · Motor', 'Correas de ventilador y accesorios: grietas, desgaste, tensión', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 90, 'SL · Motor', 'Refrigerante: nivel y concentración (refractómetro)', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Refractómetro'),
    (v_pid, 100, 'SL · Motor', 'Radiador, intercooler y condensador: limpieza externa de polvo; mangueras y abrazaderas', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Aire a baja presión; Por qué: Polvo de faena'),
    (v_pid, 110, 'SL · Motor', 'Soportes de motor, fugas de aceite/combustible/refrigerante, arnés', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 120, 'SL · Transmisión', 'Nivel y condición del fluido de transmisión (en caliente); fugas; respiradero; temperatura en tablero', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Allison TES 668/295 o según placa; Por qué: HHWB-42 sin temperatura de transmisión en tablero'),
    (v_pid, 130, 'SL · PTO', 'Toma de fuerza: montaje, fugas, ruido, activación y mando en cabina', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: La PTO mueve la bomba: su falla detiene el despacho'),
    (v_pid, 140, 'SL · Tren motriz', 'Engrase de cardanes: crucetas, yugos deslizantes, soporte central', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Grasa NLGI 2 EP', 'Especificación: Grasa NLGI 2 EP'),
    (v_pid, 150, 'SL · Tren motriz', 'Nivel de aceite de diferenciales, respiraderos, retenes de piñón y de cubos', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: 4 retenes de cubo pedidos en HHWB-44'),
    (v_pid, 160, 'SL · Tren motriz', 'Engrase de pivotes (king pins), extremos de barra y brazos de dirección', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Grasa NLGI 2 EP', 'Especificación: Grasa NLGI 2 EP'),
    (v_pid, 170, 'SL · Tren motriz', 'Cubos delanteros: nivel y condición del aceite', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 180, 'SL · Frenos', 'Medir carrera de cámaras / ajustadores automáticos; engrasar ajustadores y levas S-cam', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Grasa NLGI 2 EP; Por qué: Frenado brusco en HHWB-44'),
    (v_pid, 190, 'SL · Frenos', 'Prueba de fugas de aire, gobernador (corte/entrada), freno de estacionamiento, alarma de baja presión', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Manómetro calibrado'),
    (v_pid, 200, 'SL · Frenos', 'Freno motor: prueba funcional en ruta', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: Freno motor débil en HHWB-44'),
    (v_pid, 210, 'SL · Frenos', 'Drenaje de estanques de aire y válvulas de drenaje automáticas', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 220, 'SL · Neumáticos', 'Presión, desgaste, daños, torque de tuercas de rueda; registrar profundidad de banda', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro · profundímetro; Por qué: No hay registro de profundidad de banda'),
    (v_pid, 230, 'SL · Dirección', 'Nivel de fluido, bomba, mangueras, caja, juego libre, rótulas y extremos', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 240, 'SL · Suspensión', 'Engrase de puntos de suspensión; inspección de paquetes de resortes, hojas y bujes', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Grasa NLGI 2 EP', 'Especificación: Grasa NLGI 2 EP; Por qué: Paquete de resortes roto y bujes en HHWB-44'),
    (v_pid, 250, 'SL · Eléctrico', 'Baterías: bornes, sujeción, voltaje; alternador y arranque', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Voltímetro'),
    (v_pid, 260, 'SL · Eléctrico', 'Paradas de emergencia (cabina y zona de despacho) conectadas y funcionando; cableado protegido; caja de fusibles', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: 9 de 33 fallas de HHWB-44 fueron eléctricas, incluidas las 2 paradas de emergencia desconectadas'),
    (v_pid, 270, 'SL · Eléctrico', 'Luces, balizas, alarma de retroceso, bocina, limpiaparabrisas, tacógrafo', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 298'),
    (v_pid, 280, 'SL · Estanque', 'Estanque: fugas, abolladuras, corrosión, soldaduras, anclajes y cunas', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160 art. 177 d) y 203'),
    (v_pid, 290, 'SL · Válvulas', 'Válvula de emergencia (de fondo) por compartimiento: cierre primario y remoto, fusible térmico', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: DS 160 art. 186'),
    (v_pid, 300, 'SL · Válvulas', 'Válvulas de presión/vacío, venteos y arrestallamas de venteo; válvulas de descarga, tapas y candados', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: DS 160'),
    (v_pid, 310, 'SL · Estanque', 'Escotillas: empaquetaduras, cierres, trabas; carga inferior API y sensor de sobrellenado', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160'),
    (v_pid, 320, 'SL · Bomba', 'Bomba de despacho: sello, fugas, ruido, acople, presión/caudal, alivio; limpiar strainer', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 330, 'SL · Medición', 'Medidor volumétrico: verificación con serafín y ajuste; precintos; eliminador de aire; registrador/ticket y totalizador', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Serafín trazable · OIML R 117 ±0,5 %; Por qué: Medidor y Liquid Control con lectura errónea en HHWB-44'),
    (v_pid, 340, 'SL · Filtración', 'Filtro/separador de despacho: ΔP, drenaje de agua, sumidero', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Manómetro diferencial'),
    (v_pid, 350, 'SL · Mangueras', 'Mangueras, pistola con cierre automático, acoples, swivels; engrase del carrete', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Grasa NLGI 2; Por qué: DS 160 art. 200'),
    (v_pid, 360, 'SL · Puesta a tierra', 'Puesta a tierra: cable, pinza, carrete; medir continuidad camión–manguera–pinza', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Óhmetro (< 10 Ω); Por qué: DS 160 art. 190'),
    (v_pid, 370, 'SL · Seguridad', 'Arrestallamas de escape, parachoques, señalización NU 1202, radio, corte general, kit de derrames, pasarela y barandas', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160 / DS 298'),
    (v_pid, 380, 'SL · Cumplimiento', 'Inspección mensual DS 298 con registro; documentación y certificados vigentes (hermeticidad, SEC, revisión técnica, calibración)', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Control Documental de SICOM; Por qué: LCSX-78 opera con certificados vencidos'),
    (v_pid, 390, 'SL · Cierre', 'Prueba de ruta y del sistema de despacho', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 400, 'SM1 · Motor', 'Filtros de combustible: primario/separador y secundario', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtros genuinos Mack', 'Especificación: Filtros genuinos Mack'),
    (v_pid, 410, 'SM1 · Motor', 'Filtro de aire primario: reemplazo (antes si el indicador está en máximo)', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtro genuino', 'Especificación: Filtro genuino'),
    (v_pid, 420, 'SM1 · Motor', 'Filtro de venteo del estanque de combustible del chasis', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtro genuino', 'Especificación: Filtro genuino'),
    (v_pid, 430, 'SM1 · Motor', 'Embrague de ventilador, bomba de agua (orificio testigo)', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 440, 'SM1 · Postratamiento', 'Escape, abrazaderas, sensores NOx/temperatura/ΔP; nivel y calidad de DEF', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Refractómetro DEF 32,5 %'),
    (v_pid, 450, 'SM1 · Transmisión', 'Enfriador de transmisión, líneas, conectores, selector, códigos TCM', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Allison DOC / Mack PTT'),
    (v_pid, 460, 'SM1 · Tren motriz', 'Cardanes: juego de crucetas, torque de pernos, soporte central', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro'),
    (v_pid, 470, 'SM1 · Tren motriz', 'Bloqueo de diferencial / divisor de potencia: prueba funcional', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 480, 'SM1 · Frenos', 'Espesor de balatas, tambores, resortes, pasadores, cámaras', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 490, 'SM1 · Frenos', 'Tiempo de recuperación del compresor (build-up)', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 500, 'SM1 · Frenos', 'Mangueras, cañerías y conexiones neumáticas', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 510, 'SM1 · Frenos', 'ABS: códigos, sensores de rueda, anillos dentados, cableado', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Herramienta de diagnóstico; Por qué: Código ABS activo en HHWB-44'),
    (v_pid, 520, 'SM1 · Neumáticos', 'Rotación / evaluación de reemplazo', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 530, 'SM1 · Suspensión', 'Torque de pernos U, bujes, amortiguadores, barras, soportes', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro'),
    (v_pid, 540, 'SM1 · Estructura', 'Bastidor: fisuras, pernos sueltos, travesaños; soportes, cunas y pernos U del estanque', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro; Por qué: Zona crítica en aljibe'),
    (v_pid, 550, 'SM1 · Eléctrico', 'Conectores eléctricos: corrosión, seguros, grasa dieléctrica', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Grasa dieléctrica'),
    (v_pid, 560, 'SM1 · Cabina', 'Filtro de cabina, cinturones, espejos, parabrisas, asiento, extintor de cabina', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Filtro de cabina'),
    (v_pid, 570, 'SM1 · Filtración', 'Cambio de elementos del filtro de despacho', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Elementos según fabricante', 'Especificación: Elementos según fabricante'),
    (v_pid, 580, 'SM1 · Seguridad', 'Extintores PQS (2 × 40 BC): revisión semestral, presión, sello, fecha', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160 art. 198'),
    (v_pid, 590, 'SM1 · Seguridad', 'Sistema de recuperación de vapores (si existe)', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 600, 'SM2 · Tren motriz', 'Cambio de aceite de diferenciales delantero + divisor y trasero', 'ok_nok', NULL, TRUE, TRUE, TRUE, '80W90 / GO-J Plus (18 L + 15 L)', 'Especificación: 80W90 / GO-J Plus (18 L + 15 L); Por qué: Mack off-highway 1.200 h / 12 meses (hoy está en SM1: se ajusta)'),
    (v_pid, 610, 'SM2 · Tren motriz', 'Limpieza de respiraderos de diferenciales', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 620, 'SM2 · Motor', 'Filtro de aire secundario (de seguridad)', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtro genuino', 'Especificación: Filtro genuino'),
    (v_pid, 630, 'SM2 · Motor', 'Correas de ventilador y accesorios + tensor y poleas', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Correas genuinas', 'Especificación: Correas genuinas; Por qué: Hoy en SM3: el servicio severo pide 12 meses'),
    (v_pid, 640, 'SM2 · Motor', 'Filtro de ventilación del cárter (CCV)', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtro genuino', 'Especificación: Filtro genuino'),
    (v_pid, 650, 'SM2 · Motor', 'Filtro de refrigerante / acondicionador', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Según refrigerante instalado', 'Especificación: Según refrigerante instalado'),
    (v_pid, 660, 'SM2 · Motor', 'Prueba de estanqueidad del intercooler (CAC) y ductos', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Kit CAC'),
    (v_pid, 670, 'SM2 · Motor', 'Turbocompresor: juego axial/radial, fugas, actuador VGT', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 680, 'SM2 · Motor', 'Compresor de aire: aceite en líneas, culata, descarga', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 690, 'SM2 · Tren motriz', 'Rodamientos de ruedas: juego, retenes, ajuste; cambio de aceite de cubos', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 700, 'SM2 · Tren motriz', 'Alineación de los 3 ejes', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Equipo de alineación'),
    (v_pid, 710, 'SM2 · Frenos', 'Secador de aire: cartucho', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Cartucho Bendix/Mack', 'Especificación: Cartucho Bendix/Mack'),
    (v_pid, 720, 'SM2 · Dirección', 'Fluido y filtro de dirección hidráulica', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Según manual Mack', 'Especificación: Según manual Mack'),
    (v_pid, 730, 'SM2 · Eléctrico', 'Prueba de carga de baterías y salida de alternador', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Probador de carga'),
    (v_pid, 740, 'SM2 · Estanque', 'Interior de compartimentos: mamparos, corrosión, sedimentos, agua; limpieza', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Procedimiento de espacio confinado; Por qué: DS 160 art. 202 f)'),
    (v_pid, 750, 'SM2 · Bomba', 'Bomba de despacho: sello mecánico, rodamientos, empaquetaduras; verificar caudal', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Kit de sello', 'Especificación: Kit de sello'),
    (v_pid, 760, 'SM2 · Medición', 'Calibración certificada del sistema de medición y re-sellado', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Laboratorio trazable; Por qué: Certificado anual'),
    (v_pid, 770, 'SM2 · Mangueras', 'Prueba de presión de mangueras de despacho', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: 1,5 × presión máxima'),
    (v_pid, 780, 'Cierre', 'Horómetro de la próxima mantención en el sticker', 'numero', 'h', TRUE, FALSE, FALSE, 'Sticker de mantención', 'El horómetro de hoy más 1200 h.');
  SELECT id INTO v_pid FROM public.faena_pauta WHERE faena_id = v_faena AND codigo = 'FRK-SM3-2400';
  IF v_pid IS NULL THEN
    INSERT INTO public.faena_pauta (faena_id, codigo, nombre, tipo, modelo_id, disparo_horas, disparo_dias, aviso_horas, activo, observacion)
    VALUES (v_faena, 'FRK-SM3-2400', 'Servicio SM3 2.400 h · Mack GU 813 (severo)', 'programada', v_modelo, 2400, 730, 50, TRUE, 'MIG720: incluye completos los niveles menores')
    RETURNING id INTO v_pid;
  ELSE DELETE FROM public.faena_pauta_item WHERE pauta_id = v_pid; END IF;
  INSERT INTO public.faena_pauta_item (pauta_id, orden, bloque, texto, tipo_respuesta, unidad, obligatorio, foto_si_nok, critico, repuesto, ayuda) VALUES
    (v_pid, 10, 'Lecturas', 'Horómetro al iniciar el servicio', 'numero', 'h', TRUE, FALSE, FALSE, NULL, NULL),
    (v_pid, 20, 'Lecturas', 'Kilometraje al iniciar el servicio', 'numero', 'km', TRUE, FALSE, FALSE, NULL, NULL),
    (v_pid, 30, 'SL · Lecturas', 'Códigos de falla activos (motor, transmisión, ABS, postratamiento) leídos con lector y registrados', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Mack PTT / lector; Por qué: Códigos ABS/motor/transmisión activos en HHWB-42/44 sin registro'),
    (v_pid, 40, 'SL · Motor', 'Cambio de aceite de motor y filtros (2 + 1 adicional). Si la visita es por calendario y van menos de 150 h desde el último cambio: solo nivel + muestra', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Mack EOS-4.5 15W40 (38–42 L) · filtros genuinos', 'Especificación: Mack EOS-4.5 15W40 (38–42 L) · filtros genuinos; Por qué: Servicio severo (>30 % ralentí); sin análisis de aceite no se extiende'),
    (v_pid, 50, 'SL · Motor', 'Tomar muestra de aceite de motor para laboratorio (viscosidad, TBN, hollín, metales, combustible, refrigerante)', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Kit de muestra; Por qué: Habilita extender el aceite a 600 h con 3 análisis OK'),
    (v_pid, 60, 'SL · Motor', 'Drenar agua del separador de combustible; revisar sensor WIF', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 70, 'SL · Motor', 'Leer indicador de restricción del filtro de aire; reemplazar el primario si está en máximo', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Indicador in H2O; Por qué: Polvo de faena'),
    (v_pid, 80, 'SL · Motor', 'Correas de ventilador y accesorios: grietas, desgaste, tensión', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 90, 'SL · Motor', 'Refrigerante: nivel y concentración (refractómetro)', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Refractómetro'),
    (v_pid, 100, 'SL · Motor', 'Radiador, intercooler y condensador: limpieza externa de polvo; mangueras y abrazaderas', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Aire a baja presión; Por qué: Polvo de faena'),
    (v_pid, 110, 'SL · Motor', 'Soportes de motor, fugas de aceite/combustible/refrigerante, arnés', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 120, 'SL · Transmisión', 'Nivel y condición del fluido de transmisión (en caliente); fugas; respiradero; temperatura en tablero', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Allison TES 668/295 o según placa; Por qué: HHWB-42 sin temperatura de transmisión en tablero'),
    (v_pid, 130, 'SL · PTO', 'Toma de fuerza: montaje, fugas, ruido, activación y mando en cabina', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: La PTO mueve la bomba: su falla detiene el despacho'),
    (v_pid, 140, 'SL · Tren motriz', 'Engrase de cardanes: crucetas, yugos deslizantes, soporte central', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Grasa NLGI 2 EP', 'Especificación: Grasa NLGI 2 EP'),
    (v_pid, 150, 'SL · Tren motriz', 'Nivel de aceite de diferenciales, respiraderos, retenes de piñón y de cubos', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: 4 retenes de cubo pedidos en HHWB-44'),
    (v_pid, 160, 'SL · Tren motriz', 'Engrase de pivotes (king pins), extremos de barra y brazos de dirección', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Grasa NLGI 2 EP', 'Especificación: Grasa NLGI 2 EP'),
    (v_pid, 170, 'SL · Tren motriz', 'Cubos delanteros: nivel y condición del aceite', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 180, 'SL · Frenos', 'Medir carrera de cámaras / ajustadores automáticos; engrasar ajustadores y levas S-cam', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Grasa NLGI 2 EP; Por qué: Frenado brusco en HHWB-44'),
    (v_pid, 190, 'SL · Frenos', 'Prueba de fugas de aire, gobernador (corte/entrada), freno de estacionamiento, alarma de baja presión', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Manómetro calibrado'),
    (v_pid, 200, 'SL · Frenos', 'Freno motor: prueba funcional en ruta', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: Freno motor débil en HHWB-44'),
    (v_pid, 210, 'SL · Frenos', 'Drenaje de estanques de aire y válvulas de drenaje automáticas', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 220, 'SL · Neumáticos', 'Presión, desgaste, daños, torque de tuercas de rueda; registrar profundidad de banda', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro · profundímetro; Por qué: No hay registro de profundidad de banda'),
    (v_pid, 230, 'SL · Dirección', 'Nivel de fluido, bomba, mangueras, caja, juego libre, rótulas y extremos', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 240, 'SL · Suspensión', 'Engrase de puntos de suspensión; inspección de paquetes de resortes, hojas y bujes', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Grasa NLGI 2 EP', 'Especificación: Grasa NLGI 2 EP; Por qué: Paquete de resortes roto y bujes en HHWB-44'),
    (v_pid, 250, 'SL · Eléctrico', 'Baterías: bornes, sujeción, voltaje; alternador y arranque', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Voltímetro'),
    (v_pid, 260, 'SL · Eléctrico', 'Paradas de emergencia (cabina y zona de despacho) conectadas y funcionando; cableado protegido; caja de fusibles', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: 9 de 33 fallas de HHWB-44 fueron eléctricas, incluidas las 2 paradas de emergencia desconectadas'),
    (v_pid, 270, 'SL · Eléctrico', 'Luces, balizas, alarma de retroceso, bocina, limpiaparabrisas, tacógrafo', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 298'),
    (v_pid, 280, 'SL · Estanque', 'Estanque: fugas, abolladuras, corrosión, soldaduras, anclajes y cunas', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160 art. 177 d) y 203'),
    (v_pid, 290, 'SL · Válvulas', 'Válvula de emergencia (de fondo) por compartimiento: cierre primario y remoto, fusible térmico', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: DS 160 art. 186'),
    (v_pid, 300, 'SL · Válvulas', 'Válvulas de presión/vacío, venteos y arrestallamas de venteo; válvulas de descarga, tapas y candados', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: DS 160'),
    (v_pid, 310, 'SL · Estanque', 'Escotillas: empaquetaduras, cierres, trabas; carga inferior API y sensor de sobrellenado', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160'),
    (v_pid, 320, 'SL · Bomba', 'Bomba de despacho: sello, fugas, ruido, acople, presión/caudal, alivio; limpiar strainer', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 330, 'SL · Medición', 'Medidor volumétrico: verificación con serafín y ajuste; precintos; eliminador de aire; registrador/ticket y totalizador', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Serafín trazable · OIML R 117 ±0,5 %; Por qué: Medidor y Liquid Control con lectura errónea en HHWB-44'),
    (v_pid, 340, 'SL · Filtración', 'Filtro/separador de despacho: ΔP, drenaje de agua, sumidero', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Manómetro diferencial'),
    (v_pid, 350, 'SL · Mangueras', 'Mangueras, pistola con cierre automático, acoples, swivels; engrase del carrete', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Grasa NLGI 2; Por qué: DS 160 art. 200'),
    (v_pid, 360, 'SL · Puesta a tierra', 'Puesta a tierra: cable, pinza, carrete; medir continuidad camión–manguera–pinza', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Óhmetro (< 10 Ω); Por qué: DS 160 art. 190'),
    (v_pid, 370, 'SL · Seguridad', 'Arrestallamas de escape, parachoques, señalización NU 1202, radio, corte general, kit de derrames, pasarela y barandas', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160 / DS 298'),
    (v_pid, 380, 'SL · Cumplimiento', 'Inspección mensual DS 298 con registro; documentación y certificados vigentes (hermeticidad, SEC, revisión técnica, calibración)', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Control Documental de SICOM; Por qué: LCSX-78 opera con certificados vencidos'),
    (v_pid, 390, 'SL · Cierre', 'Prueba de ruta y del sistema de despacho', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 400, 'SM1 · Motor', 'Filtros de combustible: primario/separador y secundario', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtros genuinos Mack', 'Especificación: Filtros genuinos Mack'),
    (v_pid, 410, 'SM1 · Motor', 'Filtro de aire primario: reemplazo (antes si el indicador está en máximo)', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtro genuino', 'Especificación: Filtro genuino'),
    (v_pid, 420, 'SM1 · Motor', 'Filtro de venteo del estanque de combustible del chasis', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtro genuino', 'Especificación: Filtro genuino'),
    (v_pid, 430, 'SM1 · Motor', 'Embrague de ventilador, bomba de agua (orificio testigo)', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 440, 'SM1 · Postratamiento', 'Escape, abrazaderas, sensores NOx/temperatura/ΔP; nivel y calidad de DEF', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Refractómetro DEF 32,5 %'),
    (v_pid, 450, 'SM1 · Transmisión', 'Enfriador de transmisión, líneas, conectores, selector, códigos TCM', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Allison DOC / Mack PTT'),
    (v_pid, 460, 'SM1 · Tren motriz', 'Cardanes: juego de crucetas, torque de pernos, soporte central', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro'),
    (v_pid, 470, 'SM1 · Tren motriz', 'Bloqueo de diferencial / divisor de potencia: prueba funcional', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 480, 'SM1 · Frenos', 'Espesor de balatas, tambores, resortes, pasadores, cámaras', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 490, 'SM1 · Frenos', 'Tiempo de recuperación del compresor (build-up)', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 500, 'SM1 · Frenos', 'Mangueras, cañerías y conexiones neumáticas', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 510, 'SM1 · Frenos', 'ABS: códigos, sensores de rueda, anillos dentados, cableado', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Herramienta de diagnóstico; Por qué: Código ABS activo en HHWB-44'),
    (v_pid, 520, 'SM1 · Neumáticos', 'Rotación / evaluación de reemplazo', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 530, 'SM1 · Suspensión', 'Torque de pernos U, bujes, amortiguadores, barras, soportes', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro'),
    (v_pid, 540, 'SM1 · Estructura', 'Bastidor: fisuras, pernos sueltos, travesaños; soportes, cunas y pernos U del estanque', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro; Por qué: Zona crítica en aljibe'),
    (v_pid, 550, 'SM1 · Eléctrico', 'Conectores eléctricos: corrosión, seguros, grasa dieléctrica', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Grasa dieléctrica'),
    (v_pid, 560, 'SM1 · Cabina', 'Filtro de cabina, cinturones, espejos, parabrisas, asiento, extintor de cabina', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Filtro de cabina'),
    (v_pid, 570, 'SM1 · Filtración', 'Cambio de elementos del filtro de despacho', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Elementos según fabricante', 'Especificación: Elementos según fabricante'),
    (v_pid, 580, 'SM1 · Seguridad', 'Extintores PQS (2 × 40 BC): revisión semestral, presión, sello, fecha', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160 art. 198'),
    (v_pid, 590, 'SM1 · Seguridad', 'Sistema de recuperación de vapores (si existe)', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 600, 'SM2 · Tren motriz', 'Cambio de aceite de diferenciales delantero + divisor y trasero', 'ok_nok', NULL, TRUE, TRUE, TRUE, '80W90 / GO-J Plus (18 L + 15 L)', 'Especificación: 80W90 / GO-J Plus (18 L + 15 L); Por qué: Mack off-highway 1.200 h / 12 meses (hoy está en SM1: se ajusta)'),
    (v_pid, 610, 'SM2 · Tren motriz', 'Limpieza de respiraderos de diferenciales', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 620, 'SM2 · Motor', 'Filtro de aire secundario (de seguridad)', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtro genuino', 'Especificación: Filtro genuino'),
    (v_pid, 630, 'SM2 · Motor', 'Correas de ventilador y accesorios + tensor y poleas', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Correas genuinas', 'Especificación: Correas genuinas; Por qué: Hoy en SM3: el servicio severo pide 12 meses'),
    (v_pid, 640, 'SM2 · Motor', 'Filtro de ventilación del cárter (CCV)', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtro genuino', 'Especificación: Filtro genuino'),
    (v_pid, 650, 'SM2 · Motor', 'Filtro de refrigerante / acondicionador', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Según refrigerante instalado', 'Especificación: Según refrigerante instalado'),
    (v_pid, 660, 'SM2 · Motor', 'Prueba de estanqueidad del intercooler (CAC) y ductos', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Kit CAC'),
    (v_pid, 670, 'SM2 · Motor', 'Turbocompresor: juego axial/radial, fugas, actuador VGT', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 680, 'SM2 · Motor', 'Compresor de aire: aceite en líneas, culata, descarga', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 690, 'SM2 · Tren motriz', 'Rodamientos de ruedas: juego, retenes, ajuste; cambio de aceite de cubos', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 700, 'SM2 · Tren motriz', 'Alineación de los 3 ejes', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Equipo de alineación'),
    (v_pid, 710, 'SM2 · Frenos', 'Secador de aire: cartucho', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Cartucho Bendix/Mack', 'Especificación: Cartucho Bendix/Mack'),
    (v_pid, 720, 'SM2 · Dirección', 'Fluido y filtro de dirección hidráulica', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Según manual Mack', 'Especificación: Según manual Mack'),
    (v_pid, 730, 'SM2 · Eléctrico', 'Prueba de carga de baterías y salida de alternador', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Probador de carga'),
    (v_pid, 740, 'SM2 · Estanque', 'Interior de compartimentos: mamparos, corrosión, sedimentos, agua; limpieza', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Procedimiento de espacio confinado; Por qué: DS 160 art. 202 f)'),
    (v_pid, 750, 'SM2 · Bomba', 'Bomba de despacho: sello mecánico, rodamientos, empaquetaduras; verificar caudal', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Kit de sello', 'Especificación: Kit de sello'),
    (v_pid, 760, 'SM2 · Medición', 'Calibración certificada del sistema de medición y re-sellado', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Laboratorio trazable; Por qué: Certificado anual'),
    (v_pid, 770, 'SM2 · Mangueras', 'Prueba de presión de mangueras de despacho', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: 1,5 × presión máxima'),
    (v_pid, 780, 'SM3 · Motor', 'Ajuste de válvulas y freno motor', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Manual MP8'),
    (v_pid, 790, 'SM3 · Transmisión', 'Filtros de transmisión (principal + lubricación) — Allison; caja mecánica/mDRIVE: aceite según placa', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Allison TES 668/295 · confirmar tipo de caja', 'Especificación: Allison TES 668/295 · confirmar tipo de caja; Por qué: LCSX-78 marcó ''na'' en aceite Allison: confirmar caja antes de comprar'),
    (v_pid, 800, 'SM3 · Motor', 'Limpieza del estanque de combustible del chasis', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 810, 'SM3 · Motor', 'Cambio de refrigerante si es formulado (larga vida: SM4)', 'ok_nok', NULL, TRUE, TRUE, TRUE, '50/50 (57 L)', 'Especificación: 50/50 (57 L); Por qué: Confirmar tipo de refrigerante'),
    (v_pid, 820, 'Cierre', 'Horómetro de la próxima mantención en el sticker', 'numero', 'h', TRUE, FALSE, FALSE, 'Sticker de mantención', 'El horómetro de hoy más 2400 h.');
  SELECT id INTO v_pid FROM public.faena_pauta WHERE faena_id = v_faena AND codigo = 'FRK-SM4-4800';
  IF v_pid IS NULL THEN
    INSERT INTO public.faena_pauta (faena_id, codigo, nombre, tipo, modelo_id, disparo_horas, disparo_dias, aviso_horas, activo, observacion)
    VALUES (v_faena, 'FRK-SM4-4800', 'Servicio SM4 4.800 h · Mack GU 813 (severo)', 'programada', v_modelo, 4800, 1460, 50, TRUE, 'MIG720: incluye completos los niveles menores')
    RETURNING id INTO v_pid;
  ELSE DELETE FROM public.faena_pauta_item WHERE pauta_id = v_pid; END IF;
  INSERT INTO public.faena_pauta_item (pauta_id, orden, bloque, texto, tipo_respuesta, unidad, obligatorio, foto_si_nok, critico, repuesto, ayuda) VALUES
    (v_pid, 10, 'Lecturas', 'Horómetro al iniciar el servicio', 'numero', 'h', TRUE, FALSE, FALSE, NULL, NULL),
    (v_pid, 20, 'Lecturas', 'Kilometraje al iniciar el servicio', 'numero', 'km', TRUE, FALSE, FALSE, NULL, NULL),
    (v_pid, 30, 'SL · Lecturas', 'Códigos de falla activos (motor, transmisión, ABS, postratamiento) leídos con lector y registrados', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Mack PTT / lector; Por qué: Códigos ABS/motor/transmisión activos en HHWB-42/44 sin registro'),
    (v_pid, 40, 'SL · Motor', 'Cambio de aceite de motor y filtros (2 + 1 adicional). Si la visita es por calendario y van menos de 150 h desde el último cambio: solo nivel + muestra', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Mack EOS-4.5 15W40 (38–42 L) · filtros genuinos', 'Especificación: Mack EOS-4.5 15W40 (38–42 L) · filtros genuinos; Por qué: Servicio severo (>30 % ralentí); sin análisis de aceite no se extiende'),
    (v_pid, 50, 'SL · Motor', 'Tomar muestra de aceite de motor para laboratorio (viscosidad, TBN, hollín, metales, combustible, refrigerante)', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Kit de muestra; Por qué: Habilita extender el aceite a 600 h con 3 análisis OK'),
    (v_pid, 60, 'SL · Motor', 'Drenar agua del separador de combustible; revisar sensor WIF', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 70, 'SL · Motor', 'Leer indicador de restricción del filtro de aire; reemplazar el primario si está en máximo', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Indicador in H2O; Por qué: Polvo de faena'),
    (v_pid, 80, 'SL · Motor', 'Correas de ventilador y accesorios: grietas, desgaste, tensión', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 90, 'SL · Motor', 'Refrigerante: nivel y concentración (refractómetro)', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Refractómetro'),
    (v_pid, 100, 'SL · Motor', 'Radiador, intercooler y condensador: limpieza externa de polvo; mangueras y abrazaderas', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Aire a baja presión; Por qué: Polvo de faena'),
    (v_pid, 110, 'SL · Motor', 'Soportes de motor, fugas de aceite/combustible/refrigerante, arnés', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 120, 'SL · Transmisión', 'Nivel y condición del fluido de transmisión (en caliente); fugas; respiradero; temperatura en tablero', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Allison TES 668/295 o según placa; Por qué: HHWB-42 sin temperatura de transmisión en tablero'),
    (v_pid, 130, 'SL · PTO', 'Toma de fuerza: montaje, fugas, ruido, activación y mando en cabina', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: La PTO mueve la bomba: su falla detiene el despacho'),
    (v_pid, 140, 'SL · Tren motriz', 'Engrase de cardanes: crucetas, yugos deslizantes, soporte central', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Grasa NLGI 2 EP', 'Especificación: Grasa NLGI 2 EP'),
    (v_pid, 150, 'SL · Tren motriz', 'Nivel de aceite de diferenciales, respiraderos, retenes de piñón y de cubos', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: 4 retenes de cubo pedidos en HHWB-44'),
    (v_pid, 160, 'SL · Tren motriz', 'Engrase de pivotes (king pins), extremos de barra y brazos de dirección', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Grasa NLGI 2 EP', 'Especificación: Grasa NLGI 2 EP'),
    (v_pid, 170, 'SL · Tren motriz', 'Cubos delanteros: nivel y condición del aceite', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 180, 'SL · Frenos', 'Medir carrera de cámaras / ajustadores automáticos; engrasar ajustadores y levas S-cam', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Grasa NLGI 2 EP; Por qué: Frenado brusco en HHWB-44'),
    (v_pid, 190, 'SL · Frenos', 'Prueba de fugas de aire, gobernador (corte/entrada), freno de estacionamiento, alarma de baja presión', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Manómetro calibrado'),
    (v_pid, 200, 'SL · Frenos', 'Freno motor: prueba funcional en ruta', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: Freno motor débil en HHWB-44'),
    (v_pid, 210, 'SL · Frenos', 'Drenaje de estanques de aire y válvulas de drenaje automáticas', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 220, 'SL · Neumáticos', 'Presión, desgaste, daños, torque de tuercas de rueda; registrar profundidad de banda', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro · profundímetro; Por qué: No hay registro de profundidad de banda'),
    (v_pid, 230, 'SL · Dirección', 'Nivel de fluido, bomba, mangueras, caja, juego libre, rótulas y extremos', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 240, 'SL · Suspensión', 'Engrase de puntos de suspensión; inspección de paquetes de resortes, hojas y bujes', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Grasa NLGI 2 EP', 'Especificación: Grasa NLGI 2 EP; Por qué: Paquete de resortes roto y bujes en HHWB-44'),
    (v_pid, 250, 'SL · Eléctrico', 'Baterías: bornes, sujeción, voltaje; alternador y arranque', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Voltímetro'),
    (v_pid, 260, 'SL · Eléctrico', 'Paradas de emergencia (cabina y zona de despacho) conectadas y funcionando; cableado protegido; caja de fusibles', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: 9 de 33 fallas de HHWB-44 fueron eléctricas, incluidas las 2 paradas de emergencia desconectadas'),
    (v_pid, 270, 'SL · Eléctrico', 'Luces, balizas, alarma de retroceso, bocina, limpiaparabrisas, tacógrafo', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 298'),
    (v_pid, 280, 'SL · Estanque', 'Estanque: fugas, abolladuras, corrosión, soldaduras, anclajes y cunas', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160 art. 177 d) y 203'),
    (v_pid, 290, 'SL · Válvulas', 'Válvula de emergencia (de fondo) por compartimiento: cierre primario y remoto, fusible térmico', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: DS 160 art. 186'),
    (v_pid, 300, 'SL · Válvulas', 'Válvulas de presión/vacío, venteos y arrestallamas de venteo; válvulas de descarga, tapas y candados', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Por qué: DS 160'),
    (v_pid, 310, 'SL · Estanque', 'Escotillas: empaquetaduras, cierres, trabas; carga inferior API y sensor de sobrellenado', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160'),
    (v_pid, 320, 'SL · Bomba', 'Bomba de despacho: sello, fugas, ruido, acople, presión/caudal, alivio; limpiar strainer', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 330, 'SL · Medición', 'Medidor volumétrico: verificación con serafín y ajuste; precintos; eliminador de aire; registrador/ticket y totalizador', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Serafín trazable · OIML R 117 ±0,5 %; Por qué: Medidor y Liquid Control con lectura errónea en HHWB-44'),
    (v_pid, 340, 'SL · Filtración', 'Filtro/separador de despacho: ΔP, drenaje de agua, sumidero', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Manómetro diferencial'),
    (v_pid, 350, 'SL · Mangueras', 'Mangueras, pistola con cierre automático, acoples, swivels; engrase del carrete', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Grasa NLGI 2; Por qué: DS 160 art. 200'),
    (v_pid, 360, 'SL · Puesta a tierra', 'Puesta a tierra: cable, pinza, carrete; medir continuidad camión–manguera–pinza', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Óhmetro (< 10 Ω); Por qué: DS 160 art. 190'),
    (v_pid, 370, 'SL · Seguridad', 'Arrestallamas de escape, parachoques, señalización NU 1202, radio, corte general, kit de derrames, pasarela y barandas', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160 / DS 298'),
    (v_pid, 380, 'SL · Cumplimiento', 'Inspección mensual DS 298 con registro; documentación y certificados vigentes (hermeticidad, SEC, revisión técnica, calibración)', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Control Documental de SICOM; Por qué: LCSX-78 opera con certificados vencidos'),
    (v_pid, 390, 'SL · Cierre', 'Prueba de ruta y del sistema de despacho', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 400, 'SM1 · Motor', 'Filtros de combustible: primario/separador y secundario', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtros genuinos Mack', 'Especificación: Filtros genuinos Mack'),
    (v_pid, 410, 'SM1 · Motor', 'Filtro de aire primario: reemplazo (antes si el indicador está en máximo)', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtro genuino', 'Especificación: Filtro genuino'),
    (v_pid, 420, 'SM1 · Motor', 'Filtro de venteo del estanque de combustible del chasis', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtro genuino', 'Especificación: Filtro genuino'),
    (v_pid, 430, 'SM1 · Motor', 'Embrague de ventilador, bomba de agua (orificio testigo)', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 440, 'SM1 · Postratamiento', 'Escape, abrazaderas, sensores NOx/temperatura/ΔP; nivel y calidad de DEF', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Refractómetro DEF 32,5 %'),
    (v_pid, 450, 'SM1 · Transmisión', 'Enfriador de transmisión, líneas, conectores, selector, códigos TCM', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Allison DOC / Mack PTT'),
    (v_pid, 460, 'SM1 · Tren motriz', 'Cardanes: juego de crucetas, torque de pernos, soporte central', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro'),
    (v_pid, 470, 'SM1 · Tren motriz', 'Bloqueo de diferencial / divisor de potencia: prueba funcional', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 480, 'SM1 · Frenos', 'Espesor de balatas, tambores, resortes, pasadores, cámaras', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 490, 'SM1 · Frenos', 'Tiempo de recuperación del compresor (build-up)', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 500, 'SM1 · Frenos', 'Mangueras, cañerías y conexiones neumáticas', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, NULL),
    (v_pid, 510, 'SM1 · Frenos', 'ABS: códigos, sensores de rueda, anillos dentados, cableado', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Herramienta de diagnóstico; Por qué: Código ABS activo en HHWB-44'),
    (v_pid, 520, 'SM1 · Neumáticos', 'Rotación / evaluación de reemplazo', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 530, 'SM1 · Suspensión', 'Torque de pernos U, bujes, amortiguadores, barras, soportes', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro'),
    (v_pid, 540, 'SM1 · Estructura', 'Bastidor: fisuras, pernos sueltos, travesaños; soportes, cunas y pernos U del estanque', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Torquímetro; Por qué: Zona crítica en aljibe'),
    (v_pid, 550, 'SM1 · Eléctrico', 'Conectores eléctricos: corrosión, seguros, grasa dieléctrica', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Grasa dieléctrica'),
    (v_pid, 560, 'SM1 · Cabina', 'Filtro de cabina, cinturones, espejos, parabrisas, asiento, extintor de cabina', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Filtro de cabina'),
    (v_pid, 570, 'SM1 · Filtración', 'Cambio de elementos del filtro de despacho', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Elementos según fabricante', 'Especificación: Elementos según fabricante'),
    (v_pid, 580, 'SM1 · Seguridad', 'Extintores PQS (2 × 40 BC): revisión semestral, presión, sello, fecha', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Por qué: DS 160 art. 198'),
    (v_pid, 590, 'SM1 · Seguridad', 'Sistema de recuperación de vapores (si existe)', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 600, 'SM2 · Tren motriz', 'Cambio de aceite de diferenciales delantero + divisor y trasero', 'ok_nok', NULL, TRUE, TRUE, TRUE, '80W90 / GO-J Plus (18 L + 15 L)', 'Especificación: 80W90 / GO-J Plus (18 L + 15 L); Por qué: Mack off-highway 1.200 h / 12 meses (hoy está en SM1: se ajusta)'),
    (v_pid, 610, 'SM2 · Tren motriz', 'Limpieza de respiraderos de diferenciales', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 620, 'SM2 · Motor', 'Filtro de aire secundario (de seguridad)', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtro genuino', 'Especificación: Filtro genuino'),
    (v_pid, 630, 'SM2 · Motor', 'Correas de ventilador y accesorios + tensor y poleas', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Correas genuinas', 'Especificación: Correas genuinas; Por qué: Hoy en SM3: el servicio severo pide 12 meses'),
    (v_pid, 640, 'SM2 · Motor', 'Filtro de ventilación del cárter (CCV)', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Filtro genuino', 'Especificación: Filtro genuino'),
    (v_pid, 650, 'SM2 · Motor', 'Filtro de refrigerante / acondicionador', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Según refrigerante instalado', 'Especificación: Según refrigerante instalado'),
    (v_pid, 660, 'SM2 · Motor', 'Prueba de estanqueidad del intercooler (CAC) y ductos', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Kit CAC'),
    (v_pid, 670, 'SM2 · Motor', 'Turbocompresor: juego axial/radial, fugas, actuador VGT', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 680, 'SM2 · Motor', 'Compresor de aire: aceite en líneas, culata, descarga', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 690, 'SM2 · Tren motriz', 'Rodamientos de ruedas: juego, retenes, ajuste; cambio de aceite de cubos', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 700, 'SM2 · Tren motriz', 'Alineación de los 3 ejes', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Equipo de alineación'),
    (v_pid, 710, 'SM2 · Frenos', 'Secador de aire: cartucho', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Cartucho Bendix/Mack', 'Especificación: Cartucho Bendix/Mack'),
    (v_pid, 720, 'SM2 · Dirección', 'Fluido y filtro de dirección hidráulica', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Según manual Mack', 'Especificación: Según manual Mack'),
    (v_pid, 730, 'SM2 · Eléctrico', 'Prueba de carga de baterías y salida de alternador', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Probador de carga'),
    (v_pid, 740, 'SM2 · Estanque', 'Interior de compartimentos: mamparos, corrosión, sedimentos, agua; limpieza', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, 'Especificación: Procedimiento de espacio confinado; Por qué: DS 160 art. 202 f)'),
    (v_pid, 750, 'SM2 · Bomba', 'Bomba de despacho: sello mecánico, rodamientos, empaquetaduras; verificar caudal', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Kit de sello', 'Especificación: Kit de sello'),
    (v_pid, 760, 'SM2 · Medición', 'Calibración certificada del sistema de medición y re-sellado', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Laboratorio trazable; Por qué: Certificado anual'),
    (v_pid, 770, 'SM2 · Mangueras', 'Prueba de presión de mangueras de despacho', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: 1,5 × presión máxima'),
    (v_pid, 780, 'SM3 · Motor', 'Ajuste de válvulas y freno motor', 'ok_nok', NULL, TRUE, TRUE, TRUE, NULL, 'Especificación: Manual MP8'),
    (v_pid, 790, 'SM3 · Transmisión', 'Filtros de transmisión (principal + lubricación) — Allison; caja mecánica/mDRIVE: aceite según placa', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Allison TES 668/295 · confirmar tipo de caja', 'Especificación: Allison TES 668/295 · confirmar tipo de caja; Por qué: LCSX-78 marcó ''na'' en aceite Allison: confirmar caja antes de comprar'),
    (v_pid, 800, 'SM3 · Motor', 'Limpieza del estanque de combustible del chasis', 'ok_nok', NULL, TRUE, TRUE, FALSE, NULL, NULL),
    (v_pid, 810, 'SM3 · Motor', 'Cambio de refrigerante si es formulado (larga vida: SM4)', 'ok_nok', NULL, TRUE, TRUE, TRUE, '50/50 (57 L)', 'Especificación: 50/50 (57 L); Por qué: Confirmar tipo de refrigerante'),
    (v_pid, 820, 'SM4 · Transmisión', 'Cambio de fluido de transmisión', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'Allison TES 668/295 (~48 L) o según placa', 'Especificación: Allison TES 668/295 (~48 L) o según placa'),
    (v_pid, 830, 'SM4 · Motor', 'Cambio de refrigerante larga vida', 'ok_nok', NULL, TRUE, TRUE, TRUE, 'ELC', 'Especificación: ELC'),
    (v_pid, 840, 'SM4 · Postratamiento', 'DPF: limpieza; electrodo y tobera; inyector AHI; filtros y drenaje DEF', 'ok_nok', NULL, TRUE, TRUE, FALSE, 'Genuinos', 'Especificación: Genuinos; Por qué: Mack servicio pesado 4.500 h'),
    (v_pid, 850, 'Cierre', 'Horómetro de la próxima mantención en el sticker', 'numero', 'h', TRUE, FALSE, FALSE, 'Sticker de mantención', 'El horómetro de hoy más 4800 h.');
END $$;

-- 6. Diaria FRK-DIA-CP v2 (en su lugar + 15 nuevos) -------------------------------
DO $$
DECLARE v_pid UUID := (SELECT id FROM public.faena_pauta WHERE codigo = 'FRK-DIA-CP'); v_n INT;
BEGIN
  UPDATE public.faena_pauta_item SET texto = 'Neumáticos: presión, cortes, tuercas (marcas) y piedras entre duales', critico = TRUE WHERE pauta_id = v_pid AND orden = 210;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'FRK-DIA-CP: no está el ítem de orden 210'; END IF;
  UPDATE public.faena_pauta_item SET texto = 'Purga de estanques de aire; presión de corte normal; sin alarma', critico = TRUE WHERE pauta_id = v_pid AND orden = 230;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'FRK-DIA-CP: no está el ítem de orden 230'; END IF;
  UPDATE public.faena_pauta_item SET texto = 'Manguera y pistola: sin cortes ni goteo; cierre automático; carrete retrae', critico = TRUE WHERE pauta_id = v_pid AND orden = 410;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'FRK-DIA-CP: no está el ítem de orden 410'; END IF;
  UPDATE public.faena_pauta_item SET texto = 'Documentación a bordo vigente (hermeticidad, SEC, revisión técnica, SOAP)', critico = TRUE WHERE pauta_id = v_pid AND orden = 620;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'FRK-DIA-CP: no está el ítem de orden 620'; END IF;
  INSERT INTO public.faena_pauta_item (pauta_id, orden, bloque, texto, tipo_respuesta, unidad, obligatorio, foto_si_nok, critico)
  SELECT * FROM (VALUES
    (v_pid, 50, 'Tablero', 'Luces testigo y códigos de falla activos (motor, transmisión, ABS)', 'ok_nok', NULL, TRUE, TRUE, TRUE),
    (v_pid, 60, 'Tablero', 'Temperatura de transmisión visible y en rango', 'ok_nok', NULL, TRUE, TRUE, FALSE),
    (v_pid, 122, 'Motor y fluidos', 'Nivel de fluido de transmisión (indicador)', 'ok_nok', NULL, TRUE, TRUE, FALSE),
    (v_pid, 124, 'Motor y fluidos', 'Nivel de DEF', 'ok_nok', NULL, TRUE, TRUE, FALSE),
    (v_pid, 152, 'Motor y fluidos', 'Drenar separador de agua del combustible del motor', 'ok_nok', NULL, TRUE, TRUE, FALSE),
    (v_pid, 154, 'Motor y fluidos', 'Indicador de restricción del filtro de aire', 'ok_nok', NULL, TRUE, TRUE, FALSE),
    (v_pid, 225, 'Rodado y frenos', 'Prueba de freno de servicio, estacionamiento y freno motor', 'ok_nok', NULL, TRUE, TRUE, TRUE),
    (v_pid, 245, 'Rodado y frenos', 'Dirección: juego libre normal, sin ruidos ni dureza', 'ok_nok', NULL, TRUE, TRUE, TRUE),
    (v_pid, 350, 'Luces y señalización', 'Alarma de retroceso, bocina, espejos, limpiaparabrisas', 'ok_nok', NULL, TRUE, TRUE, FALSE),
    (v_pid, 360, 'Luces y señalización', 'Tacógrafo operativo y radio con cobertura', 'ok_nok', NULL, TRUE, TRUE, FALSE),
    (v_pid, 442, 'Sistema de despacho', 'Válvula de emergencia: accionamiento y cierre; mando remoto accesible', 'ok_nok', NULL, TRUE, TRUE, TRUE),
    (v_pid, 444, 'Sistema de despacho', 'Puesta a tierra: cable y pinza íntegros, carrete funciona', 'ok_nok', NULL, TRUE, TRUE, TRUE),
    (v_pid, 446, 'Sistema de despacho', 'Filtro de despacho: ΔP en rango, sumidero drenado', 'ok_nok', NULL, TRUE, TRUE, FALSE),
    (v_pid, 505, 'Emergencia', 'Paradas de emergencia (cabina y despacho) operativas', 'ok_nok', NULL, TRUE, TRUE, TRUE),
    (v_pid, 506, 'Emergencia', 'Arrestallamas de escape instalado; escape sin fugas', 'ok_nok', NULL, TRUE, TRUE, TRUE)
  ) n(pauta_id, orden, bloque, texto, tipo_respuesta, unidad, obligatorio, foto_si_nok, critico)
  WHERE NOT EXISTS (SELECT 1 FROM public.faena_pauta_item i WHERE i.pauta_id = v_pid AND i.orden = n.orden);
  UPDATE public.faena_pauta SET nombre = 'Revisión diaria · camión abastecedor Mack GU 813 (v2 severo)', updated_at = NOW() WHERE id = v_pid;
END $$;

-- Resultado
SELECT p.codigo, p.nombre, p.disparo_horas, p.disparo_dias, (SELECT count(*) FROM public.faena_pauta_item i WHERE i.pauta_id = p.id) AS items
  FROM public.faena_pauta p JOIN public.faenas f ON f.id = p.faena_id
 WHERE f.codigo = 'FAE-FRANCKE' ORDER BY p.tipo, p.disparo_horas NULLS FIRST, p.codigo;
