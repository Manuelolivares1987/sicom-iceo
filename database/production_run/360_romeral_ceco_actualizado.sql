-- ============================================================================
-- MIG360 · Romeral: el maestro de CECO se pone al día
-- ----------------------------------------------------------------------------
-- Entra la planilla «CECO Actualizado» de la faena, que es la que hoy se usa
-- para imputar cada carga de Orpak a su centro de costo. El maestro que tenía
-- SICOM venía de una versión anterior: 113 equipos contra los 148 de ahora.
--
-- QUÉ CAMBIA, CONTADO
--   ·  4 CECO nuevos            110042 · 115060 · 115225 · 115476
--   ·  4 equipos cambian de CECO
--   ·  5 nombres de Orpak resultaron ser equipos que ya estaban, con otro
--      nombre — entran como ALIAS, no como equipo nuevo
--   · 58 equipos nuevos
--   · 79 quedan igual
--
-- POR QUÉ LOS ALIAS Y NO UN EQUIPO NUEVO
-- «CAT 23» en Orpak y «CAEX 23» en el sistema son el mismo camión. Cargarlo dos
-- veces parte su consumo en dos fichas y ninguna de las dos dice la verdad. La
-- tabla ya tiene una columna de alias para esto: el equipo es uno, y responde a
-- los dos nombres. Se hace sólo donde la identidad es inequívoca — el nombre
-- coincide salvo tildes, o la columna «Detalle» del archivo es exactamente el
-- nombre que el sistema ya tenía.
--
-- LOS CUATRO CAMBIOS DE CECO, UNO POR UNO
-- No son correcciones de tipeo: cambian a quién se le factura. Van explícitos
-- para que se puedan revisar y revertir:
--     GENERADOR 100-01 ESPESADOR     111078  →  111087
--     LUMINARIA 07                   521107  →  115202
--     MNEU 10                        115037  →  115202   (sale de Santa Elvira)
--     CAMION ALJIBE HUERTA JDKX77    115237  →  115202
--
-- LO QUE NO SE TOCA, Y QUEDA ANOTADO PARA QUE ALGUIEN LO MIRE
--
-- 1. HAY 30 EQUIPOS EN EL SISTEMA QUE EL ARCHIVO YA NO NOMBRA. Algunos son los
--    mismos con otro nombre (TOLVA 537 SE / SE537, CAMION SUPER SUCKER /
--    VH-BL56, GENERADOR MOLIENDA / Generador planta) y otros probablemente
--    salieron de faena. Dar de baja un equipo o fusionarlo con otro cambia
--    facturación hacia atrás: lo decide la faena, no una migración.
--
-- 2. EL CECO 4016360 ESTÁ DOS VECES. Existe como «4016360» con empresa «0070» y
--    como «4016360 0070» sin empresa: dos formas de partir el mismo texto, dos
--    fichas. Los equipos cuelgan de la segunda. Consolidarlo es un movimiento
--    de datos con efecto en reportes y va aparte.
--
-- 3. EL «CAMIÓN 85» NO EXISTE EN EL SISTEMA. Aparece en el Mini Cierre de la
--    BBDD de agosto con stock propio (1.395 L) y movimiento en 7 de 13 días.
--    Ya quedó anotado como pendiente en MIG356, junto con el LCSX-78 que sigue
--    abierto como punto de Romeral y ya no opera ahí.
-- ============================================================================

BEGIN;

DO $rom$
DECLARE
    v_faena UUID;
    v_ceco  UUID;
    v_n     INTEGER;
BEGIN
    SELECT id INTO v_faena FROM public.faenas WHERE codigo = 'FAE-CMP-ROMERAL';
    IF v_faena IS NULL THEN RAISE EXCEPTION 'MIG360: no existe FAE-CMP-ROMERAL'; END IF;

    -- ── 1. Los CECO que faltaban ──────────────────────────────────────────
    -- Nacen sin confirmar: el archivo trae el código y no la razón social, y un
    -- CECO sin nombre es exactamente el que después nadie sabe a quién cobrar.
    INSERT INTO public.combustible_faena_cecos
           (faena_id, codigo, empresa, origen, confirmado, observacion)
    SELECT v_faena, v.codigo, v.empresa, 'maestro', FALSE,
           'Alta desde la planilla CECO Actualizado (MIG360). Falta la razón social.'
      FROM (VALUES
    ('110042', NULL),
    ('115060', NULL),
    ('115225', NULL),
    ('115476', NULL)
           ) AS v(codigo, empresa)
    ON CONFLICT (faena_id, codigo) DO NOTHING;

    -- ── 2. Los nombres de Orpak que ya eran un equipo conocido ────────────
    UPDATE public.combustible_faena_equipos e
       SET alias = (SELECT array_agg(DISTINCT x)
                      FROM unnest(e.alias || ARRAY[v.alias_nuevo]) AS x),
           updated_at = NOW()
      FROM (VALUES
    ('Grúa 6', 'GRUA 6'),
    ('CAEX 23', 'CAT 23'),
    ('CAEX 31', 'CAT 31'),
    ('CAEX 33', 'CAT 33'),
    ('EXCAVADORA 10', 'Excavadora RETRO10')
           ) AS v(nombre_sistema, alias_nuevo)
     WHERE e.faena_id = v_faena
       AND lower(e.nombre) = lower(v.nombre_sistema)
       AND NOT (v.alias_nuevo = ANY(e.alias));

    -- ── 3. Los cuatro que cambian de CECO ─────────────────────────────────
    UPDATE public.combustible_faena_equipos e
       SET ceco_id = c.id, updated_at = NOW()
      FROM (VALUES
    ('GENERADOR 100-01 ESPESADOR', '111078', '111087'),
    ('LUMINARIA 07', '521107', '115202'),
    ('MNEU 10', '115037', '115202'),
    ('CAMION ALJIBE HUERTA JDKX77', '115237', '115202')
           ) AS v(nombre, ceco_antes, ceco_ahora)
      JOIN public.combustible_faena_cecos c
        ON c.faena_id = (SELECT id FROM public.faenas WHERE codigo = 'FAE-CMP-ROMERAL')
       AND c.codigo = v.ceco_ahora
     WHERE e.faena_id = v_faena
       AND lower(e.nombre) = lower(v.nombre);

    -- ── 4. Los equipos nuevos ─────────────────────────────────────────────
    -- La columna «Detalle» del archivo es cómo lo llama la faena; el «Nombre
    -- Orpak» es cómo llega en el archivo del tótem. El sistema guarda el de
    -- Orpak como nombre —porque es el que tiene que calzar en la ingesta— y el
    -- de la faena como descripción, que es la que la persona reconoce.
    INSERT INTO public.combustible_faena_equipos
           (faena_id, nombre, descripcion, ceco_id, origen, confirmado)
    SELECT v_faena, v.nombre, v.detalle, c.id, 'maestro', TRUE
      FROM (VALUES
    ('TRASVASIJE MOCHILA 400', '0', NULL),
    ('RSCY85', '115225', 'CONTINGENCIA'),
    ('GEN POZO 5', '115208', 'MANTENCION MAYOR'),
    ('GEN POZO 6', '115208', 'MANTENCION MAYOR'),
    ('ANTENA GEO', '115208', 'MANTENCION MAYOR'),
    ('GEN ADMINISTRACION', '115208', 'MANTENCION MAYOR'),
    ('GEN BIMODAL', '115208', 'MANTENCION MAYOR'),
    ('GEN BODEGA', '115208', 'MANTENCION MAYOR'),
    ('LUM BOMBA 1', '115208', 'MANTENCION MAYOR'),
    ('GEN CASA FUERZA', '115208', 'MANTENCION MAYOR'),
    ('GEN CHANCADO', '115208', 'MANTENCION MAYOR'),
    ('GEN CONCENTRADORES 1', '115208', 'MANTENCION MAYOR'),
    ('GEN CONCENTRADORES 2', '115208', 'MANTENCION MAYOR'),
    ('GEN PATIO FISA', '115208', 'MANTENCION MAYOR'),
    ('GEN INSTRUMENTACION', '115208', 'MANTENCION MAYOR'),
    ('GEN LAB', '115208', 'MANTENCION MAYOR'),
    ('GEN MAESTRANZA', '115208', 'MANTENCION MAYOR'),
    ('GEN MOLIENDA', '115208', 'MANTENCION MAYOR'),
    ('GEN TRANSPORTACION', '115208', 'MANTENCION MAYOR'),
    ('GEN TRIGO 1', '115208', 'MANTENCION MAYOR'),
    ('GEN TRIGO 2', '115208', 'MANTENCION MAYOR'),
    ('GEN LOS OLIVOS', '115208', 'MANTENCION MAYOR'),
    ('COMUNIDAD', '115225', 'CONTINGENCIA'),
    ('GEN CASINO', '115208', 'MANTENCION MAYOR'),
    ('GEN EST DE BUSES', '115208', 'MANTENCION MAYOR'),
    ('GEN PLANTA', '115208', 'MANTENCION MAYOR'),
    ('GEN POLICLINICO', '115208', 'MANTENCION MAYOR'),
    ('GEN ROMANA', '115208', 'MANTENCION MAYOR'),
    ('LUM CONCEN', '115208', 'MANTENCION MAYOR'),
    ('LUM GARITA 2', '115208', 'MANTENCION MAYOR'),
    ('GEN GARITA', '115208', 'MANTENCION MAYOR'),
    ('GEN ESTACION DE SERVICIO', '115208', 'MANTENCION MAYOR'),
    ('ANTENA REPETIDORA', '115208', 'MANTENCION MAYOR'),
    ('IP 211', '115208', 'MANTENCION MAYOR'),
    ('IP 219', '115208', 'MANTENCION MAYOR'),
    ('IP177', '115208', 'MANTENCION MAYOR'),
    ('IP 888', '115208', 'MANTENCION MAYOR'),
    ('IP 92', '115208', 'MANTENCION MAYOR'),
    ('COMPRESOR LAB', '115476', NULL),
    ('EXC IMOPAC', '115225', 'CONTINGENCIA'),
    ('IP 277 CAMIONETA', '115208', 'MOCHILA'),
    ('VXLC94', '115225', 'CAMIONETA'),
    ('TZTX99', '115225', 'CAMIONETA'),
    ('TZTY12', '115060', 'CAMIONETA'),
    ('VCLL53', '110042', 'CAMIONETA'),
    ('VCLT27', '110042', 'CAMIONETA'),
    ('VWXJ55', '115060', 'CAMIONETA'),
    ('TTZY24', '115037', 'CAMIONETA'),
    ('SSPV97', '115057', 'CAMIONETA'),
    ('THSR44', '115037', 'CAMIONETA'),
    ('MINICARGADOR  E&H', '115225', NULL),
    ('IP 268', '115208', NULL),
    ('SE537', '115037', NULL),
    ('SE570', '115037', NULL),
    ('VTVW85', '115037', NULL),
    ('MOCHILA N80', '4016360 0070', NULL),
    ('VH-BL56', '115208', 'SUPER SUCKER'),
    ('Generador planta', '111087', 'GENERADOR MOLIENDA TK BLANCO')
           ) AS v(nombre, ceco, detalle)
      LEFT JOIN public.combustible_faena_cecos c
             ON c.faena_id = v_faena AND c.codigo = v.ceco
    ON CONFLICT (faena_id, lower(nombre)) DO NOTHING;

    RAISE NOTICE 'MIG360 · Romeral: % equipos, % CECO',
        (SELECT count(*) FROM public.combustible_faena_equipos WHERE faena_id = v_faena),
        (SELECT count(*) FROM public.combustible_faena_cecos   WHERE faena_id = v_faena);

    -- ── 5. Lo que queda para que lo mire la faena ─────────────────────────
    INSERT INTO public.combustible_faena_pendiente
           (faena_id, texto, origen, pedido_por, prioridad)
    SELECT v_faena, v.texto, 'sistema', 'MIG360', 'normal'
      FROM (VALUES
        ('Hay 30 equipos en el maestro que la planilla CECO Actualizado ya no nombra. Revisar cuáles '
      || 'salieron de faena y cuáles son el mismo equipo con otro nombre (TOLVA 537 SE / SE537, '
      || 'CAMION SUPER SUCKER / VH-BL56, GENERADOR MOLIENDA / Generador planta). Fusionar o dar de '
      || 'baja cambia facturación hacia atrás, por eso no se hizo solo.'),
        ('El CECO 4016360 está dos veces: como «4016360» con empresa «0070» y como «4016360 0070» sin '
      || 'empresa. Los equipos cuelgan de la segunda. Consolidar en una sola ficha.')
      ) AS v(texto)
     WHERE NOT EXISTS (
           SELECT 1 FROM public.combustible_faena_pendiente p
            WHERE p.faena_id = v_faena AND p.pedido_por = 'MIG360' AND p.estado = 'abierto');
END
$rom$;

COMMIT;

-- ── Verificación ──────────────────────────────────────────────────────────
-- SELECT e.nombre, e.descripcion, e.alias, c.codigo AS ceco
--   FROM combustible_faena_equipos e
--   LEFT JOIN combustible_faena_cecos c ON c.id = e.ceco_id
--  WHERE e.faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-CMP-ROMERAL')
--    AND (array_length(e.alias,1) > 0 OR e.nombre IN
--         ('GENERADOR 100-01 ESPESADOR','LUMINARIA 07','MNEU 10','CAMION ALJIBE HUERTA JDKX77'))
--  ORDER BY e.nombre;
