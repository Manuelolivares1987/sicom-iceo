-- ============================================================================
-- MIG358 · Las pautas de Franke, y el programa de mantención que se ejecuta
-- ----------------------------------------------------------------------------
-- Cuatro pautas, que son las que la faena hace de verdad:
--
--   FRK-DIA-CP   diaria del camión abastecedor   Mack GU 813 6×4
--   FRK-DIA-CA   diaria de la camioneta          Toyota Hilux 2.8 4×4
--   FRK-PM-300   servicio programado 300 h       Mack GU 813 6×4
--   FRK-PM-10K   servicio programado 10.000 km   Toyota Hilux 2.8 4×4
--
-- DE DÓNDE SALE CADA ÍTEM
-- Las diarias salen de lo que el mecánico ya declara que hace —«revisión de
-- fluidos y niveles», «revisión de luces en general», «revisión de balatas por
-- visor»— abierto en lo que efectivamente se mira, más lo propio del servicio:
-- manguera, pistola, cuentalitros, ticket printer, seguros del metter y de
-- escotilla. Un camión abastecedor con la pértiga suelta o el extintor vencido
-- no despacha, y por eso esos ítems van marcados como críticos.
--
-- El servicio de 300 h sale literal de la orden ejecutada sobre el HHWB-44 el
-- 11-08-2026, con una corrección: el filtro de combustible de trampa de agua
-- entra como ítem propio y con su repuesto declarado. En esa mantención no se
-- cambió porque no vino en el kit, y quedó anotado en el PDF sin que nadie
-- quedara a cargo. Ahora el kit se arma desde la pauta.
--
-- La de la camioneta incluye la lámina de seguridad del parabrisas, que el
-- turno B reportó con desgaste. Es el tipo de hallazgo que hoy aparece una vez
-- en un documento y desaparece.
--
-- ─────────────────────────────────────────────────────────────────────────
-- EL PROGRAMA DE MANTENCIÓN: DOS CALENDARIOS PARA EL MISMO CAMIÓN
-- La faena corre los camiones a 300 h. SICOM tenía cargados los cuatro
-- servicios de fábrica Mack —SL 250 h, SM1 500 h, SM2 1.000 h, SM3 3.000 h— y
-- nadie compara los dos calendarios. La camioneta, que en faena se atiende cada
-- 10.000 km, no tenía ningún plan cargado: cero.
--
-- Se resuelve dejando mandar al programa de faena, que es el que se ejecuta:
--   · entra «Servicio de faena Franke · 300 h» con el horómetro real de cada
--     camión y su última ejecución conocida;
--   · entra «Servicio de faena Franke · 10.000 km» para la camioneta;
--   · se apagan SL y SM1, que quedan por debajo del de 300 h y que éste
--     absorbe;
--   · quedan vivos SM2 y SM3, que son servicios mayores que el de 300 h NO
--     reemplaza — apagarlos sería perder una obligación real del fabricante.
--
-- Si el criterio acordado con la marca es otro, se cambia en la ficha del plan
-- desde la pantalla de mantención, sin tocar una migración.
--
-- LOS NÚMEROS DE PARTIDA, Y DE DÓNDE SALEN
--   HHWB-44   últ. 11-08-2026 · 25.585 h · 194.758 km   próx. 25.885 h
--   LCSX-78   últ. 03-08-2026 ·  9.345 h ·  88.517 km   próx.  9.645 h
--   HHWB-42   últ.            · 24.963 h                próx. 25.263 h
--   LLBP-96   últ. 25-06-2026 · 95.556 km               próx. 105.556 km
-- Los tres primeros salen del «Programa de Mantenimiento» de la entrega de
-- turno B; el del HHWB-42, del «Formato km hr» de la misma semana.
-- ============================================================================

BEGIN;

DO $pautas$
DECLARE
    v_faena  UUID;
    v_mack   UUID;
    v_hilux  UUID;
    v_p      UUID;
BEGIN
    SELECT id INTO v_faena FROM public.faenas WHERE codigo = 'FAE-FRANCKE';
    IF v_faena IS NULL THEN RAISE EXCEPTION 'MIG358: no existe FAE-FRANCKE'; END IF;

    SELECT id INTO v_mack  FROM public.modelos WHERE nombre = 'GU 813 autom'   LIMIT 1;
    SELECT id INTO v_hilux FROM public.modelos WHERE nombre = 'Hilux 2.8 Autom' LIMIT 1;
    IF v_mack IS NULL OR v_hilux IS NULL THEN
        RAISE EXCEPTION 'MIG358: no se encontraron los modelos Mack GU 813 / Toyota Hilux 2.8';
    END IF;

    -- ══════════════════════════════════════════════════════════════════════
    -- FRK-DIA-CP · diaria del camión abastecedor
    -- ══════════════════════════════════════════════════════════════════════
    INSERT INTO public.faena_pauta (faena_id, codigo, nombre, tipo, modelo_id, observacion)
    VALUES (v_faena, 'FRK-DIA-CP', 'Revisión diaria · camión abastecedor Mack GU 813',
            'diaria', v_mack,
            'Reemplaza las tres viñetas de la entrega de turno del mecánico. 27 ítems, uno por lo que de verdad se mira.')
    ON CONFLICT (faena_id, lower(codigo)) DO UPDATE SET nombre = EXCLUDED.nombre, updated_at = NOW()
    RETURNING id INTO v_p;

    DELETE FROM public.faena_pauta_item WHERE pauta_id = v_p;
    INSERT INTO public.faena_pauta_item
        (pauta_id, orden, bloque, texto, ayuda, tipo_respuesta, unidad, critico, foto_si_nok)
    VALUES
      (v_p,  10, 'Lecturas', 'Horómetro',                        'El del tablero, en horas enteras.',          'numero', 'h',  FALSE, FALSE),
      (v_p,  20, 'Lecturas', 'Kilometraje',                      NULL,                                          'numero', 'km', FALSE, FALSE),
      (v_p,  30, 'Lecturas', 'Numeral del metter',               'El acumulativo del ticket printer.',          'numero', 'L',  FALSE, FALSE),

      (v_p, 110, 'Motor y fluidos', 'Nivel de aceite de motor',          'Con el motor frío y el camión en plano.', 'ok_nok', NULL, FALSE, TRUE),
      (v_p, 120, 'Motor y fluidos', 'Nivel de refrigerante',              NULL, 'ok_nok', NULL, FALSE, TRUE),
      (v_p, 130, 'Motor y fluidos', 'Nivel de aceite hidráulico',         NULL, 'ok_nok', NULL, FALSE, TRUE),
      (v_p, 140, 'Motor y fluidos', 'Nivel de dirección y líquido de frenos', NULL, 'ok_nok', NULL, TRUE,  TRUE),
      (v_p, 150, 'Motor y fluidos', 'Fugas bajo el equipo',               'Motor, caja, diferencial y estanque. Mirar el suelo antes de mover el camión.', 'ok_nok', NULL, TRUE, TRUE),
      (v_p, 160, 'Motor y fluidos', 'Correas y mangueras',                NULL, 'ok_nok', NULL, FALSE, TRUE),

      (v_p, 210, 'Rodado y frenos', 'Neumáticos: presión, cortes y tuercas', 'Revisar las marcas de giro de las tuercas.', 'ok_nok', NULL, TRUE, TRUE),
      (v_p, 220, 'Rodado y frenos', 'Balatas de freno por visor',         NULL, 'ok_nok', NULL, TRUE,  TRUE),
      (v_p, 230, 'Rodado y frenos', 'Purga de estanques de aire',         NULL, 'ok_nok', NULL, FALSE, TRUE),
      (v_p, 240, 'Rodado y frenos', 'Suspensión: paquetes de resortes y amortiguadores', 'Mirar hoja por hoja. En agosto se quebró la 3ra del lado conductor.', 'ok_nok', NULL, TRUE, TRUE),

      (v_p, 310, 'Luces y señalización', 'Luces altas, bajas, freno y viraje', NULL, 'ok_nok', NULL, FALSE, TRUE),
      (v_p, 320, 'Luces y señalización', 'Pértiga y su punto de conexión',  'Revisar sulfato en la conexión.', 'ok_nok', NULL, TRUE, TRUE),
      (v_p, 330, 'Luces y señalización', 'Baliza ámbar',                    NULL, 'ok_nok', NULL, TRUE,  TRUE),
      (v_p, 340, 'Luces y señalización', 'Focos de trocha',                 NULL, 'ok_nok', NULL, FALSE, TRUE),

      (v_p, 410, 'Sistema de despacho', 'Manguera y pistola: sin cortes ni goteo', NULL, 'ok_nok', NULL, TRUE, TRUE),
      (v_p, 420, 'Sistema de despacho', 'Cuentalitros y ticket printer: marca e imprime', 'Emitir un ticket de prueba si hay duda.', 'ok_nok', NULL, TRUE, TRUE),
      (v_p, 430, 'Sistema de despacho', 'Seguros del metter',              NULL, 'ok_nok', NULL, TRUE,  TRUE),
      (v_p, 440, 'Sistema de despacho', 'Seguros de escotilla y válvulas de fondo', NULL, 'ok_nok', NULL, TRUE, TRUE),
      (v_p, 450, 'Sistema de despacho', 'Área de carga sin derrames',      NULL, 'ok_nok', NULL, TRUE,  TRUE),

      (v_p, 510, 'Emergencia', 'Extintores: carga, sello y vigencia',      NULL, 'ok_nok', NULL, TRUE,  TRUE),
      (v_p, 520, 'Emergencia', 'Cuñas y triángulos',                       NULL, 'ok_nok', NULL, FALSE, TRUE),
      (v_p, 530, 'Emergencia', 'Botiquín de cabina',                       NULL, 'ok_nok', NULL, FALSE, TRUE),
      (v_p, 540, 'Emergencia', 'Kit antiderrame / saco absorbente',        NULL, 'ok_nok', NULL, TRUE,  TRUE),

      (v_p, 610, 'Cierre', 'Orden y aseo de cabina y equipo',              NULL, 'ok_nok', NULL, FALSE, TRUE),
      (v_p, 620, 'Cierre', 'Documentación a bordo vigente',                'Revisión técnica, seguro, permiso de circulación y certificados.', 'ok_nok', NULL, TRUE, TRUE);

    -- ══════════════════════════════════════════════════════════════════════
    -- FRK-DIA-CA · diaria de la camioneta de supervisión
    -- ══════════════════════════════════════════════════════════════════════
    INSERT INTO public.faena_pauta (faena_id, codigo, nombre, tipo, modelo_id, observacion)
    VALUES (v_faena, 'FRK-DIA-CA', 'Revisión diaria · camioneta de supervisión Hilux 2.8',
            'diaria', v_hilux,
            'Sin ítems de despacho: la camioneta no abastece. 17 ítems.')
    ON CONFLICT (faena_id, lower(codigo)) DO UPDATE SET nombre = EXCLUDED.nombre, updated_at = NOW()
    RETURNING id INTO v_p;

    DELETE FROM public.faena_pauta_item WHERE pauta_id = v_p;
    INSERT INTO public.faena_pauta_item
        (pauta_id, orden, bloque, texto, ayuda, tipo_respuesta, unidad, critico, foto_si_nok)
    VALUES
      (v_p,  10, 'Lecturas', 'Kilometraje', NULL, 'numero', 'km', FALSE, FALSE),

      (v_p, 110, 'Motor y fluidos', 'Nivel de aceite de motor',   NULL, 'ok_nok', NULL, FALSE, TRUE),
      (v_p, 120, 'Motor y fluidos', 'Nivel de refrigerante',      NULL, 'ok_nok', NULL, FALSE, TRUE),
      (v_p, 130, 'Motor y fluidos', 'Nivel de líquido de frenos', NULL, 'ok_nok', NULL, TRUE,  TRUE),
      (v_p, 140, 'Motor y fluidos', 'Agua de lavaparabrisas',     NULL, 'ok_nok', NULL, FALSE, TRUE),
      (v_p, 150, 'Motor y fluidos', 'Fugas bajo el equipo',       NULL, 'ok_nok', NULL, TRUE,  TRUE),

      (v_p, 210, 'Rodado y frenos', 'Neumáticos: presión y estado, incluido el repuesto', NULL, 'ok_nok', NULL, TRUE, TRUE),
      (v_p, 220, 'Rodado y frenos', 'Frenos: pedal y ruidos',     NULL, 'ok_nok', NULL, TRUE,  TRUE),

      (v_p, 310, 'Luces y señalización', 'Luces altas, bajas, freno y viraje', NULL, 'ok_nok', NULL, FALSE, TRUE),
      (v_p, 320, 'Luces y señalización', 'Baliza ámbar',          NULL, 'ok_nok', NULL, TRUE,  TRUE),
      (v_p, 330, 'Luces y señalización', 'Pértiga',               NULL, 'ok_nok', NULL, TRUE,  TRUE),

      (v_p, 410, 'Emergencia', 'Extintor: carga, sello y vigencia', NULL, 'ok_nok', NULL, TRUE, TRUE),
      (v_p, 420, 'Emergencia', 'Botiquín',                         NULL, 'ok_nok', NULL, FALSE, TRUE),
      (v_p, 430, 'Emergencia', 'Cuñas y triángulos',               NULL, 'ok_nok', NULL, FALSE, TRUE),
      (v_p, 440, 'Emergencia', 'Gata y llave de rueda',            NULL, 'ok_nok', NULL, FALSE, TRUE),

      (v_p, 510, 'Cierre', 'Lámina de seguridad del parabrisas',   'El turno B la reportó con desgaste en agosto 2026.', 'ok_nok', NULL, FALSE, TRUE),
      (v_p, 520, 'Cierre', 'Documentación a bordo y aseo',         NULL, 'ok_nok', NULL, TRUE, TRUE);

    -- ══════════════════════════════════════════════════════════════════════
    -- FRK-PM-300 · servicio programado del camión
    -- ══════════════════════════════════════════════════════════════════════
    INSERT INTO public.faena_pauta
        (faena_id, codigo, nombre, tipo, modelo_id, disparo_horas, aviso_horas, observacion)
    VALUES (v_faena, 'FRK-PM-300', 'Servicio programado 300 h · Mack GU 813',
            'programada', v_mack, 300, 50,
            'Sale de la orden ejecutada sobre el HHWB-44 el 11-08-2026, con el filtro de trampa de agua incorporado como ítem propio.')
    ON CONFLICT (faena_id, lower(codigo)) DO UPDATE SET nombre = EXCLUDED.nombre, updated_at = NOW()
    RETURNING id INTO v_p;

    DELETE FROM public.faena_pauta_item WHERE pauta_id = v_p;
    INSERT INTO public.faena_pauta_item
        (pauta_id, orden, bloque, texto, ayuda, tipo_respuesta, unidad, critico, foto_si_nok, repuesto)
    VALUES
      (v_p,  10, 'Lecturas', 'Horómetro al iniciar el servicio', NULL, 'numero', 'h',  FALSE, FALSE, NULL),
      (v_p,  20, 'Lecturas', 'Kilometraje al iniciar el servicio', NULL, 'numero', 'km', FALSE, FALSE, NULL),

      (v_p, 110, 'Motor', 'Cambio de aceite de motor 15W40',       NULL, 'ok_nok', NULL, TRUE,  TRUE, 'Aceite de motor 15W40'),
      (v_p, 120, 'Motor', 'Cambio de filtro de aceite de motor',   NULL, 'ok_nok', NULL, TRUE,  TRUE, 'Filtro de aceite de motor'),
      (v_p, 130, 'Motor', 'Cambio de filtro de combustible primario', NULL, 'ok_nok', NULL, TRUE, TRUE, 'Filtro de combustible primario'),
      (v_p, 140, 'Motor', 'Cambio de filtro de combustible trampa de agua',
                 'En la mantención de agosto 2026 no se cambió porque no vino en el kit. Si falta, marcar NO OK y queda con dueño.',
                 'ok_nok', NULL, TRUE, TRUE, 'Filtro de combustible trampa de agua'),
      (v_p, 150, 'Motor', 'Cambio de filtro de aire de motor',     NULL, 'ok_nok', NULL, TRUE,  TRUE, 'Filtro de aire de motor'),
      (v_p, 160, 'Motor', 'Cambio de filtro A/A de habitáculo',    NULL, 'ok_nok', NULL, FALSE, TRUE, 'Filtro A/A habitáculo'),

      (v_p, 210, 'Frenos y rodado', 'Graduación de frenos',        NULL, 'ok_nok', NULL, TRUE, TRUE, NULL),
      (v_p, 220, 'Frenos y rodado', 'Revisión de balatas por visor', NULL, 'ok_nok', NULL, TRUE, TRUE, NULL),
      (v_p, 230, 'Frenos y rodado', 'Revisión de componentes: suspensión, dirección y escape', NULL, 'ok_nok', NULL, TRUE, TRUE, NULL),
      (v_p, 240, 'Frenos y rodado', 'Engrase general',             NULL, 'ok_nok', NULL, FALSE, TRUE, 'Grasa'),

      (v_p, 310, 'Cierre', 'Horómetro de la próxima mantención en el sticker',
                 'El horómetro de hoy más 300 h.', 'numero', 'h', FALSE, FALSE, 'Sticker de mantención'),
      (v_p, 320, 'Cierre', 'Prueba de ruta y del sistema de despacho', NULL, 'ok_nok', NULL, TRUE, TRUE, NULL);

    -- ══════════════════════════════════════════════════════════════════════
    -- FRK-PM-10K · servicio programado de la camioneta
    -- ══════════════════════════════════════════════════════════════════════
    INSERT INTO public.faena_pauta
        (faena_id, codigo, nombre, tipo, modelo_id, disparo_km, aviso_km, observacion)
    VALUES (v_faena, 'FRK-PM-10K', 'Servicio programado 10.000 km · Hilux 2.8',
            'programada', v_hilux, 10000, 1000,
            'El intervalo que la faena viene ejecutando: 95.556 → 105.556 km.')
    ON CONFLICT (faena_id, lower(codigo)) DO UPDATE SET nombre = EXCLUDED.nombre, updated_at = NOW()
    RETURNING id INTO v_p;

    DELETE FROM public.faena_pauta_item WHERE pauta_id = v_p;
    INSERT INTO public.faena_pauta_item
        (pauta_id, orden, bloque, texto, tipo_respuesta, unidad, critico, foto_si_nok, repuesto)
    VALUES
      (v_p,  10, 'Lecturas', 'Kilometraje al iniciar el servicio', 'numero', 'km', FALSE, FALSE, NULL),
      (v_p, 110, 'Motor', 'Cambio de aceite de motor y filtro',    'ok_nok', NULL, TRUE,  TRUE, 'Aceite de motor y filtro'),
      (v_p, 120, 'Motor', 'Cambio de filtro de aire',              'ok_nok', NULL, TRUE,  TRUE, 'Filtro de aire'),
      (v_p, 130, 'Motor', 'Cambio de filtro de combustible',       'ok_nok', NULL, TRUE,  TRUE, 'Filtro de combustible'),
      (v_p, 140, 'Motor', 'Cambio de filtro de aire acondicionado','ok_nok', NULL, FALSE, TRUE, 'Filtro A/A'),
      (v_p, 210, 'Rodado', 'Rotación y presión de neumáticos',     'ok_nok', NULL, FALSE, TRUE, NULL),
      (v_p, 220, 'Rodado', 'Revisión de frenos',                   'ok_nok', NULL, TRUE,  TRUE, NULL),
      (v_p, 230, 'Rodado', 'Revisión de suspensión y dirección',   'ok_nok', NULL, TRUE,  TRUE, NULL),
      (v_p, 310, 'Cierre', 'Niveles y engrase',                    'ok_nok', NULL, FALSE, TRUE, NULL),
      (v_p, 320, 'Cierre', 'Kilometraje de la próxima mantención en el sticker', 'numero', 'km', FALSE, FALSE, 'Sticker de mantención');

    RAISE NOTICE 'MIG358 · pautas Franke: % pautas, % items',
        (SELECT count(*) FROM public.faena_pauta      WHERE faena_id = v_faena),
        (SELECT count(*) FROM public.faena_pauta_item i
           JOIN public.faena_pauta p2 ON p2.id = i.pauta_id WHERE p2.faena_id = v_faena);
END
$pautas$;


-- ══════════════════════════════════════════════════════════════════════════
-- EL PROGRAMA DE MANTENCIÓN QUE SE EJECUTA
-- ══════════════════════════════════════════════════════════════════════════

-- 1. El plan de mantención cuelga de una pauta de fabricante — la columna es
--    obligatoria y es de donde la OT saca su checklist. En vez de escribir el
--    contenido dos veces, la pauta de fabricante se arma DESDE la pauta de
--    faena que se acaba de sembrar: una sola fuente, y lo que el mecánico marca
--    en terreno es exactamente lo que la OT del taller pide.
INSERT INTO public.pautas_fabricante
       (modelo_id, nombre, tipo_plan, frecuencia_horas, frecuencia_km,
        descripcion, items_checklist, materiales_estimados, duracion_estimada_hrs, activo)
SELECT p.modelo_id,
       p.nombre,
       CASE WHEN p.disparo_horas IS NOT NULL THEN 'por_horas' ELSE 'por_kilometraje' END::tipo_plan_pm_enum,
       p.disparo_horas, p.disparo_km,
       'Programa que ejecuta la faena Franke. Espejo de la pauta ' || p.codigo || ' (MIG358).',
       COALESCE((SELECT jsonb_agg(jsonb_build_object(
                          'orden', i.orden,
                          'descripcion', i.texto,
                          'obligatorio', i.obligatorio,
                          'requiere_foto', i.foto_si_nok AND i.critico)
                        ORDER BY i.orden)
                   FROM public.faena_pauta_item i WHERE i.pauta_id = p.id), '[]'::jsonb),
       COALESCE((SELECT jsonb_agg(jsonb_build_object(
                          'descripcion', i.repuesto, 'cantidad', 1, 'unidad', 'unidad')
                        ORDER BY i.orden)
                   FROM public.faena_pauta_item i
                  WHERE i.pauta_id = p.id AND i.repuesto IS NOT NULL), '[]'::jsonb),
       CASE WHEN p.disparo_horas IS NOT NULL THEN 6 ELSE 3 END,
       TRUE
  FROM public.faena_pauta p
  JOIN public.faenas f ON f.id = p.faena_id AND f.codigo = 'FAE-FRANCKE'
 WHERE p.tipo = 'programada'
   AND NOT EXISTS (SELECT 1 FROM public.pautas_fabricante pf
                    WHERE pf.modelo_id = p.modelo_id AND pf.nombre = p.nombre);

-- 2. El servicio de faena, con los números reales de la entrega de turno B.
INSERT INTO public.planes_mantenimiento
       (activo_id, pauta_fabricante_id, nombre, tipo_plan, frecuencia_horas, frecuencia_km,
        anticipacion_dias, prioridad, ultima_ejecucion_fecha, ultima_ejecucion_horas,
        ultima_ejecucion_km, activo_plan)
SELECT a.id, pf.id, v.nombre, v.tipo::tipo_plan_pm_enum, v.horas, v.km, 7, 'alta',
       v.fecha, v.ult_h, v.ult_km, TRUE
  FROM (VALUES
        ('HHWB-44', 'FRK-PM-300', 'Servicio de faena Franke · 300 h',       'por_horas',       300::numeric, NULL::numeric, DATE '2026-08-11', 25585::numeric, 194758::numeric),
        ('LCSX-78', 'FRK-PM-300', 'Servicio de faena Franke · 300 h',       'por_horas',       300,          NULL,          DATE '2026-08-03',  9345,           88517),
        ('HHWB-42', 'FRK-PM-300', 'Servicio de faena Franke · 300 h',       'por_horas',       300,          NULL,          NULL,              24963,           NULL),
        ('LLBP-96', 'FRK-PM-10K', 'Servicio de faena Franke · 10.000 km',   'por_kilometraje', NULL,         10000,         DATE '2026-06-25',  NULL,           95556)
       ) AS v(patente, pauta_codigo, nombre, tipo, horas, km, fecha, ult_h, ult_km)
  JOIN public.activos a  ON a.patente = v.patente
  JOIN public.faena_pauta fp
        ON lower(fp.codigo) = lower(v.pauta_codigo)
       AND fp.faena_id = (SELECT id FROM public.faenas WHERE codigo = 'FAE-FRANCKE')
  JOIN public.pautas_fabricante pf
        ON pf.modelo_id = fp.modelo_id AND pf.nombre = fp.nombre
 WHERE NOT EXISTS (
       SELECT 1 FROM public.planes_mantenimiento pm
        WHERE pm.activo_id = a.id AND pm.nombre = v.nombre);

-- 2. Se apagan los dos servicios de fábrica que el de 300 h absorbe. SM2 y SM3
--    quedan vivos: son servicios mayores, no los reemplaza nada de esto.
UPDATE public.planes_mantenimiento pm
   SET activo_plan = FALSE, updated_at = NOW()
  FROM public.activos a
 WHERE a.id = pm.activo_id
   AND a.patente IN ('HHWB-44', 'LCSX-78', 'HHWB-42')
   AND pm.nombre IN ('Mack GU813E - Servicio SL (250h / 5.000km)',
                     'Mack GU813E - Servicio SM1 (500h / 10.000km)')
   AND pm.activo_plan;

COMMIT;

-- ── Verificación ──────────────────────────────────────────────────────────
-- SELECT activo_codigo, patente, modelo, pauta_codigo, pauta_nombre, pauta_tipo,
--        items, faltan_horas, faltan_km
--   FROM v_faena_pauta_agenda
--  WHERE faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-FRANCKE')
--  ORDER BY activo_codigo, pauta_tipo, pauta_codigo;
--
-- SELECT a.patente, pm.nombre, pm.frecuencia_horas, pm.frecuencia_km, pm.activo_plan
--   FROM planes_mantenimiento pm JOIN activos a ON a.id = pm.activo_id
--  WHERE a.patente IN ('HHWB-44','LCSX-78','HHWB-42','LLBP-96')
--  ORDER BY a.patente, pm.activo_plan DESC, pm.nombre;
