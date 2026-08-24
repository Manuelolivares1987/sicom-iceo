-- ============================================================================
-- MIG355 · Franke entra al módulo de faena
-- ----------------------------------------------------------------------------
-- Franke ya tenía un módulo propio (MIG130-133): camiones petroleros como
-- estanques móviles, precios de venta, cuadre diario. Nació antes que el módulo
-- de faena y quedó fuera de él: sus camiones no cuelgan de ninguna faena, y por
-- eso nada de lo que se construyó para Romeral —cierre por turno, pendientes
-- que cruzan el turno, tolerancia declarada, app de terreno sin señal— le llega.
--
-- Esto no reemplaza aquel módulo: lo enchufa. Todo el módulo de faena cuelga de
-- un faena_id, así que basta con poblar Franke bien para que las mismas piezas
-- corran ahí.
--
-- QUÉ SE POBLA, Y DE DÓNDE SALE CADA COSA
--   · Los estanques        de los tres camiones cisterna reales del contrato
--   · Los cuentalitros     del «Formato km hr» del turno B, 06-12 ago 2026
--   · Los CECO             del «resumen de ventas por CARGO» del informe julio
--   · Los equipos          de la hoja LISTADO EQUIPOS del Control de Suministro
--   · Las ubicaciones      de la columna UBICACIÓN de esa misma hoja
--
-- LO QUE APARECIÓ AL CRUZARLO, Y QUE ALGUIEN TIENE QUE MIRAR
--
-- 1. EL CATÁLOGO DE EQUIPOS TIENE CÓDIGOS REPETIDOS
--    En la hoja de equipos autorizados hay cinco códigos que aparecen dos
--    veces. Tres son el mismo equipo anotado en dos ubicaciones (CF-500,
--    CF-470, COM-02): se consolidan. Dos NO son el mismo equipo — mismo código
--    y distinta empresa:
--        MINI-02   Minicargador de Planta   y   Minicargador de Diexa
--        LUM-14    Luminaria de Planta      y   Luminaria de Cenizas
--    Se cargan separados, con la empresa en el nombre, porque cargarle a
--    Planta el combustible de Diexa es un error de facturación, no de
--    catálogo. Corregirlo en la hoja de origen queda pendiente.
--
-- 2. HAY CARGOS QUE FACTURAN Y NO ESTÁN EN EL LISTADO
--    El informe de julio factura por ocho cargos; el listado de equipos sólo
--    conoce siete, y no son los mismos. Hefaistos (12.726 L), Mina (871 L) y
--    Abastecimiento (73 L) mueven combustible y no tienen un solo equipo
--    autorizado en la hoja. Se dan de alta los diez cargos —la unión de ambas
--    listas— para que ninguna venta quede sin CECO al que imputarse.
--
-- 3. EL LCSX-78 ESTABA ASIGNADO A ROMERAL
--    El camión opera en Franke como reemplazo desde antes de julio —el informe
--    de gestión lo declara «Camión reemplazo, operativo en faena»— pero en
--    SICOM figuraba en la faena Romeral. Mientras estuviera así no contaba en
--    la disponibilidad de Franke ni en su programa de mantención.
--
-- 4. HAY DOS CAMIONES QUE NO EXISTEN
--    Los estanques JGBY-10 y KVWD-27 quedaron de la demo de MIG133. Se
--    desactivan: un camión inventado dentro de una lista de camiones reales es
--    la clase de dato que alguien termina usando.
--
-- LA CAMIONETA NO ES UN ESTANQUE
-- La LLBP-96 es de supervisión: no almacena ni despacha combustible. Entra al
-- sistema por su pauta y su mantención (MIG356), no como punto de medición.
-- ============================================================================

BEGIN;

DO $franke$
DECLARE
    v_faena UUID;
BEGIN
    SELECT id INTO v_faena FROM public.faenas WHERE codigo = 'FAE-FRANCKE';
    IF v_faena IS NULL THEN
        RAISE EXCEPTION 'MIG355: no existe la faena FAE-FRANCKE';
    END IF;

    -- ── 1. Umbrales del cuadre ────────────────────────────────────────────
    -- Los mismos que Romeral, y por la misma razón: sin umbral declarado, o se
    -- persigue ruido de medición o se normaliza cualquier diferencia. Julio
    -- cerró con -0,101 % y se declaró aceptable sin que el criterio estuviera
    -- escrito en ninguna parte. Queda escrito acá, y se acuerda con CM Cenizas.
    INSERT INTO public.combustible_faena_config
           (faena_id, tolerancia_pct, tolerancia_piso_lt, observacion)
    VALUES (v_faena, 0.005, 50,
            'Valores de partida tomados de Romeral. Falta acordarlos con CM Cenizas.')
    ON CONFLICT (faena_id) DO NOTHING;

    -- ── 2. Los camiones cisterna, amarrados a la faena ────────────────────
    -- orden_cierre es el orden en que se recorren al cerrar el turno: primero
    -- el camión oficial, después el de reemplazo. El standby va al final
    -- porque está en Coquimbo y no se mide.
    UPDATE public.combustible_estanques e SET
        faena_id     = v_faena,
        operacion    = 'Franke',
        orden_cierre = CASE e.patente WHEN 'HHWB-44' THEN 10
                                      WHEN 'LCSX-78' THEN 20 ELSE 90 END,
        clave_cierre = CASE e.patente WHEN 'HHWB-44' THEN 'CP-44'
                                      WHEN 'LCSX-78' THEN 'CP-78' ELSE 'CP-42' END,
        grupo_cuadre = 'camiones',
        -- En un camión cisterna no se varilla: el conteo físico se hace
        -- trasvasijando todo a otro camión y leyendo el cuentalitros. Es
        -- exactamente lo que hoy se hace con los tickets de trasvasije de
        -- inicio y fin de turno.
        trasvasije_por_contador = TRUE,
        activo_id    = (SELECT a.id FROM public.activos a
                         WHERE a.patente = e.patente ORDER BY a.created_at LIMIT 1),
        es_demo      = FALSE,
        updated_at   = NOW()
    WHERE e.patente IN ('HHWB-44', 'LCSX-78', 'HHWB-42');

    -- La capacidad del LCSX-78 estaba en 10.000 L y la ficha del activo dice
    -- 15.000 L. Manda la ficha, que sale de la documentación del camión.
    UPDATE public.combustible_estanques
       SET capacidad_lt = 15000
     WHERE patente = 'LCSX-78' AND capacidad_lt <> 15000;

    -- 90 % de la capacidad nominal: es lo que de verdad se puede cargar.
    UPDATE public.combustible_estanques
       SET capacidad_llenado_lt = ROUND(capacidad_lt * 0.90, 0)
     WHERE patente IN ('HHWB-44', 'LCSX-78', 'HHWB-42');

    -- Camiones de la demo de MIG133 que nunca existieron.
    UPDATE public.combustible_estanques
       SET activo = FALSE,
           observaciones = COALESCE(observaciones || ' · ', '')
             || 'Desactivado en MIG355: dato de demo, no es un camion del contrato Franke.'
     WHERE patente IN ('JGBY-10', 'KVWD-27');

    -- ── 3. El cuentalitros de cada camión ─────────────────────────────────
    -- Un solo contador por camión: el «metter» del ticket printer. El numeral
    -- es el del cierre del turno B, 12-08-2026, y sale de dos fuentes que
    -- coinciden — el «Formato km hr» y los tickets de trasvasije 21514 y 21706
    -- de la Carga TK Camión. El CP-42 parte en cero: está en Coquimbo.
    INSERT INTO public.combustible_faena_medidores
           (estanque_id, surtidor, numero, etiqueta, orden, ultimo_numeral)
    SELECT e.id, 'S1', 'Metter', v.etiqueta, v.orden, v.numeral
      FROM (VALUES
              ('HHWB-44', 'CP-44 · metter ticket printer', 10, 13600261::numeric),
              ('LCSX-78', 'CP-78 · metter ticket printer', 20,  2279830::numeric),
              ('HHWB-42', 'CP-42 · metter ticket printer', 90,        0::numeric)
           ) AS v(patente, etiqueta, orden, numeral)
      JOIN public.combustible_estanques e ON e.patente = v.patente
     WHERE NOT EXISTS (
           SELECT 1 FROM public.combustible_faena_medidores m
            WHERE m.estanque_id = e.id AND m.surtidor = 'S1'
              AND m.numero = 'Metter' AND m.activo);

    -- ── 4. Los CECO: los cargos a los que se factura ──────────────────────
    -- Los ocho del informe de julio más los dos que sólo aparecen en el
    -- listado de equipos. Los tres que facturan sin equipos autorizados nacen
    -- SIN confirmar, que es como el módulo marca «esto opera, pero alguien
    -- tiene que mirarlo».
    INSERT INTO public.combustible_faena_cecos
           (faena_id, codigo, empresa, origen, confirmado, observacion)
    VALUES
      (v_faena, 'Sotramin',       'Sotramin',   'maestro', TRUE,  'Movimiento de mina. 75.440 L en julio 2026.'),
      (v_faena, 'Diexa',          'Diexa',      'maestro', TRUE,  'Perforación y tronadura. 72.546 L en julio 2026.'),
      (v_faena, 'Rentamaq',       'Rentamaq',   'maestro', TRUE,  'Arriendo de equipos. 43.553 L en julio 2026.'),
      (v_faena, 'Planta',         'CM Cenizas', 'maestro', TRUE,  'Equipos de planta de CM Cenizas. 20.906 L en julio 2026.'),
      (v_faena, 'Hefaistos',      NULL,         'maestro', FALSE, 'Factura 12.726 L en julio y no tiene equipos en el listado autorizado. Falta la ficha.'),
      (v_faena, 'Warner',         'Warner',     'maestro', TRUE,  'Generador en Garita China. 1.306 L en julio 2026.'),
      (v_faena, 'Mina',           'CM Cenizas', 'maestro', FALSE, 'Factura 871 L en julio y no tiene equipos en el listado autorizado. Falta la ficha.'),
      (v_faena, 'Abastecimiento', NULL,         'maestro', FALSE, 'Factura 73 L en julio. Consumo del propio servicio; falta definir si es venta o consumo interno.'),
      (v_faena, 'Cenizas',        'CM Cenizas', 'maestro', TRUE,  'Equipos de CM Cenizas fuera de planta.'),
      (v_faena, 'Gohe',           'Gohe',       'maestro', TRUE,  'Excavadora y picaroca. Sin ventas registradas en julio 2026.')
    ON CONFLICT (faena_id, codigo) DO NOTHING;

    -- ── 5. Las ubicaciones donde se abastece ──────────────────────────────
    INSERT INTO public.combustible_faena_ubicaciones (faena_id, nombre, orden)
    SELECT v_faena, v.nombre, v.orden
      FROM (VALUES
    ('A. Humeda', 10),
    ('A. Seca', 20),
    ('Apilados', 30),
    ('B. Japon', 40),
    ('Basal Este', 50),
    ('Basal Oeste', 60),
    ('Bodega', 70),
    ('Botadero F3', 80),
    ('Botaderos', 90),
    ('Campamento', 100),
    ('Canchas', 110),
    ('Ch. Primario', 120),
    ('EW', 130),
    ('Garita China', 140),
    ('Instalaciones rentamaq', 150),
    ('JAPON', 160),
    ('M. Mina', 170),
    ('M. Planta', 180),
    ('Mina', 190),
    ('Planta Diexa', 200),
    ('Planta Piloto', 210),
    ('Plato 12', 220),
    ('Remanejo', 230),
    ('Ripios', 240),
    ('Stock Sulfuro', 250)
           ) AS v(nombre, orden)
    ON CONFLICT (faena_id, lower(nombre)) DO NOTHING;

    -- ── 6. Los equipos autorizados a cargar ───────────────────────────────
    -- 87 equipos de 10 empresas. El nombre es el código con que el operador lo
    -- va a buscar en el teléfono; el tipo va en la descripción para que la
    -- búsqueda por «excavadora» también encuentre.
    INSERT INTO public.combustible_faena_equipos
           (faena_id, nombre, descripcion, tipo, ceco_id, origen, confirmado)
    SELECT v_faena, v.nombre, v.tipo || ' · ' || v.ubicacion, v.tipo, c.id, 'maestro', TRUE
      FROM (VALUES
    ('GEN-08', 'GEN-08', 'Generador', 'Cenizas', 'Campamento'),
    ('GH-02B', 'GH-02B', 'Grua Horquilla', 'Cenizas', 'Bodega'),
    ('LUM-14 (Cenizas)', 'LUM-14', 'Luminaria', 'Cenizas', 'Canchas'),
    ('LUM-16', 'LUM-16', 'Luminaria', 'Cenizas', 'B. Japon'),
    ('LUM-18', 'LUM-18', 'Luminaria', 'Cenizas', 'B. Japon'),
    ('LUM-TI07', 'LUM-TI07', 'Luminaria', 'Cenizas', 'Botadero F3'),
    ('LUM-TI09', 'LUM-TI09', 'Luminaria', 'Cenizas', 'Botadero F3'),
    ('SOLD-04', 'SOLD-04', 'Soldadora', 'Cenizas', 'M. Mina'),
    ('FAB-22', 'FAB-22', 'Camion Fabrica', 'Diexa', 'Planta Diexa'),
    ('FAB-26', 'FAB-26', 'Camion Fabrica', 'Diexa', 'Planta Diexa'),
    ('FAB-95', 'FAB-95', 'Camion Fabrica', 'Diexa', 'Planta Diexa'),
    ('GEN-02', 'GEN-02', 'Generador', 'Diexa', 'Planta Diexa'),
    ('MINI-02 (Diexa)', 'MINI-02', 'Minicargador', 'Diexa', 'Mina'),
    ('MINI-226', 'MINI-226', 'Minicargador', 'Diexa', 'Planta Diexa'),
    ('PERFO-05', 'PERFO-05', 'Perforadora', 'Diexa', 'Mina'),
    ('PERFO-06', 'PERFO-06', 'Perforadora', 'Diexa', 'Mina'),
    ('PERFO-07', 'PERFO-07', 'Perforadora', 'Diexa', 'Mina'),
    ('POL-27', 'POL-27', 'Camion Polvorin', 'Diexa', 'Planta Diexa'),
    ('POL-51', 'POL-51', 'Camion Polvorin', 'Diexa', 'Planta Diexa'),
    ('EXC-300', 'EXC-300', 'Excavadora', 'Gohe', 'Stock Sulfuro'),
    ('PR-210', 'PR-210', 'Pica Roca', 'Gohe', 'Canchas'),
    ('COM-02', 'COM-02', 'Compresor', 'Planta', 'EW'),
    ('COM-408', 'COM-408', 'Compresor', 'Planta', 'Ch. Primario'),
    ('CSS-CK53', 'CSS-CK53', 'Super Sucker', 'Planta', 'A. Seca'),
    ('GEN-06', 'GEN-06', 'Generador', 'Planta', 'EW'),
    ('GEN-11', 'GEN-11', 'Generador', 'Planta', 'M. Planta'),
    ('GEN-235', 'GEN-235', 'Generador', 'Planta', 'Apilados'),
    ('GEN-28', 'GEN-28', 'Generador', 'Planta', 'Apilados'),
    ('GGR-51', 'GGR-51', 'Grua Grove', 'Planta', 'M. Planta'),
    ('GH-01H', 'GH-01H', 'Grua Horquilla', 'Planta', 'EW'),
    ('GT-780', 'GT-780', 'Grua Terex', 'Planta', 'M. Planta'),
    ('HL-1', 'HL-1', 'Hidrolavadora', 'Planta', 'EW'),
    ('LUM-08', 'LUM-08', 'Luminaria', 'Planta', 'Plato 12'),
    ('LUM-09', 'LUM-09', 'Luminaria', 'Planta', 'Basal Este'),
    ('LUM-10', 'LUM-10', 'Luminaria', 'Planta', 'Basal Oeste'),
    ('LUM-11', 'LUM-11', 'Luminaria', 'Planta', 'A. Humeda'),
    ('LUM-12', 'LUM-12', 'Luminaria', 'Planta', 'A. Humeda'),
    ('LUM-13', 'LUM-13', 'Luminaria', 'Planta', 'A. Humeda'),
    ('LUM-14 (Planta)', 'LUM-14', 'Luminaria', 'Planta', 'EW'),
    ('LUM-15', 'LUM-15', 'Luminaria', 'Planta', 'EW'),
    ('MAN-02', 'MAN-02', 'Manitu', 'Planta', 'M. Planta'),
    ('MAN-160', 'MAN-160', 'Manitu', 'Planta', 'A. Seca'),
    ('MC-03', 'MC-03', 'Motocompresor', 'Planta', 'M. Planta'),
    ('MINI-01', 'MINI-01', 'Minicargador', 'Planta', 'M. Planta'),
    ('MINI-02 (Planta)', 'MINI-02', 'Minicargador', 'Planta', 'M. Planta'),
    ('MINI-04', 'MINI-04', 'Minicargador', 'Planta', 'M. Planta'),
    ('RETRO-18', 'RETRO-18', 'Retroexcavadora', 'Planta', 'Planta Piloto'),
    ('RETRO-21', 'RETRO-21', 'Retroexcavadora', 'Planta', 'Apilados'),
    ('BULL-01', 'BULL-01', 'Bulldozer', 'Rentamaq', 'Botaderos'),
    ('BULL-17', 'BULL-17', 'Bulldozer', 'Rentamaq', 'Botaderos'),
    ('BULL-18', 'BULL-18', 'Bulldozer', 'Rentamaq', 'Botaderos'),
    ('BZ-28', 'BZ-28', 'Bulldozer', 'Rentamaq', 'Instalaciones rentamaq'),
    ('CF-25', 'CF-25', 'Cargador Frontal', 'Rentamaq', 'Apilados'),
    ('CF-470', 'CF-470', 'Cargador Frontal', 'Rentamaq', 'Remanejo'),
    ('CF-500', 'CF-500', 'Cargador Frontal', 'Rentamaq', 'Ripios'),
    ('CF-980', 'CF-980', 'Cargador Frontal', 'Rentamaq', 'Ripios'),
    ('CT-01', 'CT-01', 'Camion Tolva', 'Rentamaq', 'Remanejo'),
    ('CT-02', 'CT-02', 'Camion Tolva', 'Rentamaq', 'Remanejo'),
    ('CT-03', 'CT-03', 'Camion Tolva', 'Rentamaq', 'Remanejo'),
    ('EXC-13', 'EXC-13', 'Excavadora', 'Rentamaq', 'Ripios'),
    ('EXC-15', 'EXC-15', 'Excavadora', 'Rentamaq', 'Ripios'),
    ('MOTO-06', 'MOTO-06', 'Motoniveladora', 'Rentamaq', 'Mina'),
    ('PR-13', 'PR-13', 'Pica Roca', 'Rentamaq', 'Canchas'),
    ('BULL-T01', 'BULL-T01', 'Bulldozer', 'Sotramin', 'Mina'),
    ('BULL-T02', 'BULL-T02', 'Bulldozer', 'Sotramin', 'Mina'),
    ('BULL-T03', 'BULL-T03', 'Bulldozer', 'Sotramin', 'Mina'),
    ('CF-600', 'CF-600', 'Cargador Frontal', 'Sotramin', 'Mina'),
    ('CF-99', 'CF-99', 'Cargador Frontal', 'Sotramin', 'Mina'),
    ('CL-34', 'CL-34', 'Camion Lubricador', 'Sotramin', 'JAPON'),
    ('CM-591', 'CM-591', 'Caex', 'Sotramin', 'Mina'),
    ('CM-593', 'CM-593', 'Caex', 'Sotramin', 'Mina'),
    ('CM-597', 'CM-597', 'Caex', 'Sotramin', 'Mina'),
    ('COM-01', 'COM-01', 'Compresor', 'Sotramin', 'M. Mina'),
    ('COM-185', 'COM-185', 'Compresor', 'Sotramin', 'M. Mina'),
    ('CT-21', 'CT-21', 'Camion Tolva', 'Sotramin', 'Mina'),
    ('CT-63', 'CT-63', 'Camion Tolva', 'Sotramin', 'Mina'),
    ('CT-81', 'CT-81', 'Camion Tolva', 'Sotramin', 'Mina'),
    ('DEP-01', 'DEP-01', 'Deposito 200 Lts.', 'Sotramin', 'M. Mina'),
    ('EXC-11', 'EXC-11', 'Excavadora', 'Sotramin', 'Mina'),
    ('GH-MM', 'GH-MM', 'Grua Horquilla', 'Sotramin', 'M. Mina'),
    ('MOTO-02', 'MOTO-02', 'Motoniveladora', 'Sotramin', 'Mina'),
    ('MOTO-03', 'MOTO-03', 'Motoniveladora', 'Sotramin', 'Mina'),
    ('MOTO-770', 'MOTO-770', 'Motoniveladora', 'Sotramin', 'Mina'),
    ('PALA-09', 'PALA-09', 'Excavadora', 'Sotramin', 'Mina'),
    ('PR-340', 'PR-340', 'Pica Roca', 'Sotramin', 'Canchas'),
    ('PR-HYUNDAI', 'PR-HYUNDAI', 'Pica Roca', 'Sotramin', 'Canchas'),
    ('GEN-P2', 'GEN-P2', 'Generador', 'Warner', 'Garita China')
           ) AS v(nombre, codigo, tipo, cargo, ubicacion)
      LEFT JOIN public.combustible_faena_cecos c
             ON c.faena_id = v_faena AND c.codigo = v.cargo
    ON CONFLICT (faena_id, lower(nombre)) DO NOTHING;

    RAISE NOTICE 'MIG355 · Franke poblado: % equipos, % CECO, % ubicaciones, % estanques',
        (SELECT count(*) FROM public.combustible_faena_equipos      WHERE faena_id = v_faena),
        (SELECT count(*) FROM public.combustible_faena_cecos        WHERE faena_id = v_faena),
        (SELECT count(*) FROM public.combustible_faena_ubicaciones  WHERE faena_id = v_faena),
        (SELECT count(*) FROM public.combustible_estanques          WHERE faena_id = v_faena AND activo);
END
$franke$;

-- ── 7. El LCSX-78 vuelve a la faena donde opera ───────────────────────────
-- Se deja la nota en la ficha: el camión es de Coquimbo, está en Franke como
-- reemplazo, y el día que vuelva alguien va a querer saber desde cuándo.
UPDATE public.activos a
   SET faena_id = (SELECT id FROM public.faenas WHERE codigo = 'FAE-FRANCKE'),
       notas    = COALESCE(a.notas || E'\n', '')
                || '[MIG355 · 2026-08-24] Reasignado a faena Franke: opera como camion de '
                || 'reemplazo del contrato FRK 220/2024 desde antes de julio 2026. '
                || 'Antes figuraba en Romeral.',
       updated_at = NOW()
 WHERE a.patente = 'LCSX-78'
   AND a.faena_id IS DISTINCT FROM (SELECT id FROM public.faenas WHERE codigo = 'FAE-FRANCKE');

COMMIT;

-- ── Verificación ──────────────────────────────────────────────────────────
-- SELECT e.clave_cierre, e.patente, e.capacidad_lt, e.capacidad_llenado_lt,
--        m.etiqueta, m.ultimo_numeral
--   FROM combustible_estanques e
--   JOIN faenas f ON f.id = e.faena_id AND f.codigo = 'FAE-FRANCKE'
--   LEFT JOIN combustible_faena_medidores m ON m.estanque_id = e.id AND m.activo
--  ORDER BY e.orden_cierre;
--
-- SELECT c.codigo, c.empresa, c.confirmado, count(eq.id) AS equipos
--   FROM combustible_faena_cecos c
--   JOIN faenas f ON f.id = c.faena_id AND f.codigo = 'FAE-FRANCKE'
--   LEFT JOIN combustible_faena_equipos eq ON eq.ceco_id = c.id
--  GROUP BY c.codigo, c.empresa, c.confirmado ORDER BY 4 DESC;
