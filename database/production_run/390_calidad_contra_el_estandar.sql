-- ============================================================================
-- MIG390 · La auditoría de calidad se hace contra el estándar, no contra 188 ítems
-- ----------------------------------------------------------------------------
-- La auditoría copiaba los 188 ítems del Check-List de Inspección y Recepción
-- V03. Un auditor frente a 188 casillas no audita: marca. Revisar todo es no
-- revisar nada, y lo que se pierde en el camino es justamente lo que importa.
--
-- LO QUE SE AUDITA AHORA SON DOS COSAS
--
--   1. EL ESTÁNDAR DEL CAMIÓN. Los 24 puntos del «Estándar Camión Aljibes de
--      Combustible» o los 22 del de «Agua Industrial», según lo que sea el
--      equipo. Es el documento que está pegado en el muro del taller y el que
--      define cómo se entrega un camión: carrete antiestático, sobrellenado
--      óptico, paradas de emergencia, extintores, logos, kit de invierno.
--
--   2. LO QUE ESE CAMIÓN TIENE ABIERTO. Sus no conformidades sin cerrar, una
--      por línea. Un camión no se entrega con hallazgos pendientes, y hasta hoy
--      el auditor tenía que ir a buscarlos a otra pantalla — o sea, no iba.
--
-- POR QUÉ EL ESTÁNDAR Y NO EL CHECKLIST
-- El V03 es una inspección de recepción: sirve para recibir un equipo que
-- vuelve de arriendo y describe su estado mecánico completo. El estándar es
-- otra cosa: es la definición de qué tiene que llevar un camión para salir. La
-- auditoría de calidad pregunta lo segundo, y por eso preguntaba mal.
-- El V03 no se toca: sigue vivo para lo suyo.
--
-- EL ESTÁNDAR VIVE EN LA BASE, NO EN EL CÓDIGO
-- Está pegado en un muro y va a cambiar. Queda en `auditoria_calidad_plantilla_items`
-- para que se edite sin migración, con `estandar` diciendo a qué familia aplica.
-- ============================================================================

BEGIN;

-- ── 1. La plantilla sabe a qué estándar pertenece cada punto ──────────────
ALTER TABLE public.auditoria_calidad_plantilla_items
    ADD COLUMN IF NOT EXISTS estandar      TEXT,
    ADD COLUMN IF NOT EXISTS bloque        TEXT,
    ADD COLUMN IF NOT EXISTS bloque_orden  INT DEFAULT 1,
    ADD COLUMN IF NOT EXISTS requiere_foto BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.auditoria_calidad_plantilla_items.estandar IS
    '[MIG390] A qué estándar pertenece: combustible, agua_industrial, o NULL para lo que aplica a todos.';

-- ── 2. Qué estándar le toca a cada equipo ─────────────────────────────────
-- Se resuelve por el nombre porque es donde vive la distinción hoy: «Aljibe
-- Comb.» contra «Agua Industrial» y «Camión de Riego». No se inventa una
-- columna nueva para algo que el maestro ya dice.
CREATE OR REPLACE FUNCTION public.fn_estandar_de_activo(p_activo_id uuid)
RETURNS TEXT
LANGUAGE sql STABLE
SET search_path TO 'public', 'pg_temp'
AS $fn$
    SELECT CASE
        WHEN a.nombre ILIKE '%aljibe comb%' OR a.nombre ILIKE '%combustible%'
            THEN 'combustible'
        WHEN a.nombre ILIKE '%agua industrial%' OR a.nombre ILIKE '%riego%'
            THEN 'agua_industrial'
        ELSE NULL
    END
    FROM public.activos a WHERE a.id = p_activo_id;
$fn$;

-- ── 3. El estándar, tal como está en el muro ──────────────────────────────
DELETE FROM public.auditoria_calidad_plantilla_items WHERE estandar IS NOT NULL;

INSERT INTO public.auditoria_calidad_plantilla_items
    (categoria, orden, descripcion, obligatorio, critico, activo, estandar, bloque, bloque_orden, requiere_foto)
VALUES
-- ══ Estándar Camión Aljibes de Combustible (24 puntos) ══════════════════
('tecnica',  1, 'Carrete antiestático, con perno de cobre.', TRUE, TRUE, TRUE, 'combustible', 'Estándar del camión', 1, TRUE),
('tecnica',  2, 'Sistema de sobrellenado óptico con perno inteligente (excepto las unidades de 5 m³).', TRUE, TRUE, TRUE, 'combustible', 'Estándar del camión', 1, TRUE),
('tecnica',  3, 'Escalas de acceso al lomo del estanque con argollas de anclaje para arnés de seguridad.', TRUE, TRUE, TRUE, 'combustible', 'Estándar del camión', 1, TRUE),
('tecnica',  4, '1 o 2 soportes y sus neumáticos de repuesto con su sistema de montaje.', TRUE, FALSE, TRUE, 'combustible', 'Estándar del camión', 1, FALSE),
('tecnica',  5, '3 paradas de emergencia señalizadas (2 a cada lado de la cabina y 1 en la parte trasera).', TRUE, TRUE, TRUE, 'combustible', 'Estándar del camión', 1, TRUE),
('tecnica',  6, '1 cortacorriente con caja y punto de bloqueo.', TRUE, TRUE, TRUE, 'combustible', 'Estándar del camión', 1, TRUE),
('tecnica',  7, 'Láminas anti-impacto certificadas en las ventanillas laterales y parabrisas.', TRUE, FALSE, TRUE, 'combustible', 'Estándar del camión', 1, FALSE),
('tecnica',  8, '2 conos reflectantes naranjas de 28" con su soporte.', TRUE, FALSE, TRUE, 'combustible', 'Estándar del camión', 1, FALSE),
('tecnica',  9, '2 cuñas plásticas amarillas con sus soportes.', TRUE, FALSE, TRUE, 'combustible', 'Estándar del camión', 1, FALSE),
('tecnica', 10, '2 extintores externos de 10 kg en sus gabinetes cerrados.', TRUE, TRUE, TRUE, 'combustible', 'Estándar del camión', 1, TRUE),
('tecnica', 11, '2 focos neblineros LED delanteros.', TRUE, FALSE, TRUE, 'combustible', 'Estándar del camión', 1, FALSE),
('tecnica', 12, '1 foco faenero LED trasero.', TRUE, FALSE, TRUE, 'combustible', 'Estándar del camión', 1, FALSE),
('tecnica', 13, '2 logos corporativos en ambas puertas y 2 en ambos costados del estanque.', TRUE, FALSE, TRUE, 'combustible', 'Estándar del camión', 1, TRUE),
('tecnica', 14, 'Logos de identificación de sustancia: Número ONU (NCh 2190) y Rombo NFPA 704 (NCh 1411/4) en los 4 costados del equipo.', TRUE, TRUE, TRUE, 'combustible', 'Estándar del camión', 1, TRUE),
('tecnica', 15, 'Logo con la palabra "Combustible" en ambos lados del estanque y en el frontis de la cabina.', TRUE, FALSE, TRUE, 'combustible', 'Estándar del camión', 1, TRUE),
('tecnica', 16, '1 pértiga minera y 2 balizas.', TRUE, FALSE, TRUE, 'combustible', 'Estándar del camión', 1, FALSE),
('tecnica', 17, 'Kit cabina: gata de 20 ton, 1 chaleco amarillo reflectante, llave de rueda con barrote, extintor de cabina, botiquín.', TRUE, FALSE, TRUE, 'combustible', 'Estándar del camión', 1, TRUE),
('tecnica', 18, 'Cinta eslinga para ambas puertas.', TRUE, FALSE, TRUE, 'combustible', 'Estándar del camión', 1, FALSE),
('tecnica', 19, 'Check point para las tuercas de rueda (cantidad según modelo).', TRUE, FALSE, TRUE, 'combustible', 'Estándar del camión', 1, FALSE),
('tecnica', 20, 'Disco diario, semanal o rollo de termoimpresión para tacógrafo, según el modelo.', TRUE, FALSE, TRUE, 'combustible', 'Estándar del camión', 1, FALSE),
('tecnica', 21, 'Seguros "R" en las aldabas porta candados.', TRUE, FALSE, TRUE, 'combustible', 'Estándar del camión', 1, FALSE),
('tecnica', 22, '1 pistola surtidora tipo 7H y/o Wiggins según corresponda.', TRUE, TRUE, TRUE, 'combustible', 'Estándar del camión', 1, TRUE),
('tecnica', 23, 'Neumáticos Pantaneros MT (sólo marcas Kuhmo, Michelin o Westlake).', TRUE, FALSE, TRUE, 'combustible', 'Estándar del camión', 1, FALSE),
('tecnica', 24, 'Kit de invierno completo: saco yute, alcohol, 1 kg de sal gruesa, 2 frazadas, linterna con 2 pilas, chuzo o picota, pala, plumillas de repuesto, cadenas para nieve y tensores (eje motriz), lanza o estrobo con 2 grilletes certificados.', TRUE, FALSE, TRUE, 'combustible', 'Estándar del camión', 1, TRUE),

-- ══ Estándar Camión Aljibes de Agua Industrial (22 puntos) ══════════════
('tecnica',  1, 'Escalas de acceso al lomo del estanque con argollas de anclaje para arnés de seguridad (se excluyen las del Tipo MEL).', TRUE, TRUE, TRUE, 'agua_industrial', 'Estándar del camión', 1, TRUE),
('tecnica',  2, '1 o 2 soportes y sus neumáticos de repuesto con su sistema de montaje.', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, FALSE),
('tecnica',  3, '2 paradas de emergencia señalizadas (2 a cada lado de la cabina).', TRUE, TRUE, TRUE, 'agua_industrial', 'Estándar del camión', 1, TRUE),
('tecnica',  4, '1 cortacorriente con caja y punto de bloqueo.', TRUE, TRUE, TRUE, 'agua_industrial', 'Estándar del camión', 1, TRUE),
('tecnica',  5, 'Láminas anti-impacto certificadas en las ventanillas laterales y parabrisas.', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, FALSE),
('tecnica',  6, '2 conos reflectantes naranjas de 28" con su soporte.', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, FALSE),
('tecnica',  7, '2 cuñas plásticas amarillas con sus soportes.', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, FALSE),
('tecnica',  8, '2 extintores externos de 10 kg en sus gabinetes cerrados.', TRUE, TRUE, TRUE, 'agua_industrial', 'Estándar del camión', 1, TRUE),
('tecnica',  9, '2 focos neblineros LED delanteros.', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, FALSE),
('tecnica', 10, '1 foco faenero LED trasero.', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, FALSE),
('tecnica', 11, '2 logos corporativos en ambas puertas y 2 en ambos costados del estanque.', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, TRUE),
('tecnica', 12, 'Logos de identificación "Agua Industrial" a ambos costados del estanque.', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, TRUE),
('tecnica', 13, 'Logos en ambos lados del estanque con: tara, carga máxima o PBV, capacidad máxima del estanque en litros, y altura máxima del camión (con barandas superiores incluidas).', TRUE, TRUE, TRUE, 'agua_industrial', 'Estándar del camión', 1, TRUE),
('tecnica', 14, '1 pértiga minera y 2 balizas.', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, FALSE),
('tecnica', 15, 'Kit cabina: gata de 20 ton, 1 chaleco amarillo reflectante, llave de rueda con barrote, extintor de cabina, botiquín.', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, TRUE),
('tecnica', 16, 'Cinta eslinga para ambas puertas.', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, FALSE),
('tecnica', 17, 'Check point para las tuercas de rueda (cantidad según modelo).', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, FALSE),
('tecnica', 18, 'Disco diario, semanal o rollo de termoimpresión para tacógrafo, según el modelo.', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, FALSE),
('tecnica', 19, 'Seguros "R" en las aldabas porta candados.', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, FALSE),
('tecnica', 20, 'Neumáticos Pantaneros MT (sólo marcas Kuhmo, Michelin o Westlake).', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, FALSE),
('tecnica', 21, 'Caja de herramientas con capacidad suficiente para contener hasta 2 juegos de cadena para nieve.', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, FALSE),
('tecnica', 22, 'Kit de invierno completo: saco yute, alcohol, 1 kg de sal gruesa, 2 frazadas, linterna con 2 pilas, chuzo o picota, pala, plumillas de repuesto, cadenas para nieve y tensores (eje motriz), lanza o estrobo con 2 grilletes certificados.', TRUE, FALSE, TRUE, 'agua_industrial', 'Estándar del camión', 1, TRUE);

-- Los 14 de siempre (documentación y técnica general) pasan a su propio bloque.
UPDATE public.auditoria_calidad_plantilla_items
   SET bloque = CASE WHEN categoria = 'documentacion' THEN 'Documentación' ELSE 'Verificación general' END,
       bloque_orden = CASE WHEN categoria = 'documentacion' THEN 2 ELSE 3 END
 WHERE estandar IS NULL;

-- ── 4. La auditoría se arma con el estándar y con lo que el camión debe ───
CREATE OR REPLACE FUNCTION public.fn_iniciar_auditoria_calidad(
    p_activo_id uuid, p_ot_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_user     UUID := auth.uid();
    v_aud      UUID;
    v_tot      INT := 0;
    v_n        INT;
    v_estandar TEXT;
    v_ncs      INT := 0;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM activos WHERE id = p_activo_id) THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id;
    END IF;

    -- [MIG271] Retomar en vez de duplicar: cada clic en «Iniciar» creaba una
    -- auditoría nueva y el auditor perdía de vista lo avanzado.
    SELECT id INTO v_aud FROM auditorias_calidad
     WHERE activo_id = p_activo_id AND resultado = 'pendiente' AND anulada = FALSE
     ORDER BY created_at DESC LIMIT 1;
    IF v_aud IS NOT NULL THEN
        IF p_ot_id IS NOT NULL THEN
            UPDATE auditorias_calidad SET ot_id = COALESCE(ot_id, p_ot_id) WHERE id = v_aud;
        END IF;
        RETURN jsonb_build_object(
            'auditoria_id', v_aud, 'retomada', TRUE,
            'items_total', (SELECT count(*) FROM auditoria_calidad_items WHERE auditoria_id = v_aud),
            'items_marcados', (SELECT count(*) FROM auditoria_calidad_items
                                WHERE auditoria_id = v_aud AND resultado <> 'pendiente'),
            'fuente', 'auditoría en curso');
    END IF;

    v_estandar := public.fn_estandar_de_activo(p_activo_id);

    INSERT INTO auditorias_calidad (activo_id, ot_id, iniciada_por, created_by)
    VALUES (p_activo_id, p_ot_id, v_user, v_user)
    RETURNING id INTO v_aud;

    -- ══ Bloque 1: el estándar del camión ═════════════════════════════════
    INSERT INTO auditoria_calidad_items
        (auditoria_id, categoria, orden, descripcion, obligatorio, critico,
         resultado, bloque, bloque_orden, requiere_foto, aplica_tipo)
    SELECT v_aud, p.categoria, p.orden, p.descripcion, p.obligatorio, p.critico,
           'pendiente', p.bloque, 1, p.requiere_foto, TRUE
      FROM auditoria_calidad_plantilla_items p
     WHERE p.activo AND p.estandar IS NOT NULL
       AND p.estandar = v_estandar
     ORDER BY p.orden;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_tot := v_tot + v_n;

    -- ══ Bloque 2: lo que este camión tiene abierto ═══════════════════════
    -- Una línea por no conformidad sin cerrar. Un camión no se entrega con
    -- hallazgos pendientes, y antes había que ir a buscarlos a otra pantalla
    -- —o sea, no se iba—.
    INSERT INTO auditoria_calidad_items
        (auditoria_id, categoria, orden, descripcion, obligatorio, critico,
         resultado, bloque, bloque_orden, requiere_foto, aplica_tipo)
    SELECT v_aud, 'tecnica',
           row_number() OVER (ORDER BY nc.fecha_evento, nc.created_at),
           'NC del ' || to_char(COALESCE(nc.fecha_evento, nc.created_at::date), 'DD-MM-YYYY')
             || ': ' || left(COALESCE(nc.descripcion, 'sin descripción'), 180),
           TRUE,
           COALESCE(lower(nc.severidad::text) IN ('critica', 'alta', 'mayor'), FALSE),
           'pendiente', 'No conformidades abiertas', 2, TRUE, TRUE
      FROM no_conformidades nc
     WHERE nc.activo_id = p_activo_id
       AND COALESCE(nc.resuelto, FALSE) = FALSE;
    GET DIAGNOSTICS v_ncs = ROW_COUNT;
    v_tot := v_tot + v_ncs;

    -- ══ Bloque 3: documentación y verificación general ═══════════════════
    INSERT INTO auditoria_calidad_items
        (auditoria_id, categoria, orden, descripcion, obligatorio, critico,
         referencia_cert_id, resultado, bloque, bloque_orden, requiere_foto, aplica_tipo)
    SELECT v_aud, p.categoria, p.orden, p.descripcion, p.obligatorio, p.critico,
           c.cert_id,
           CASE WHEN p.categoria = 'documentacion' AND p.cert_tipo IS NOT NULL THEN
                    CASE WHEN c.estado = 'vigente' THEN 'ok'
                         WHEN c.estado IS NULL THEN 'pendiente'
                         ELSE 'no_ok' END
                ELSE 'pendiente' END,
           COALESCE(p.bloque, 'Verificación general'),
           COALESCE(p.bloque_orden, 3), COALESCE(p.requiere_foto, FALSE), TRUE
      FROM auditoria_calidad_plantilla_items p
      LEFT JOIN LATERAL (
            SELECT cc.id AS cert_id, cc.estado AS estado
              FROM certificaciones cc
             WHERE cc.activo_id = p_activo_id
               AND p.cert_tipo IS NOT NULL
               AND cc.tipo::TEXT = p.cert_tipo
             ORDER BY cc.fecha_vencimiento DESC NULLS LAST LIMIT 1
      ) c ON TRUE
     WHERE p.activo AND p.estandar IS NULL
     ORDER BY p.bloque_orden, p.categoria, p.orden;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_tot := v_tot + v_n;

    UPDATE auditorias_calidad SET items_total = v_tot WHERE id = v_aud;

    RETURN jsonb_build_object(
        'auditoria_id', v_aud, 'retomada', FALSE,
        'items_total', v_tot,
        'estandar', COALESCE(v_estandar, 'sin estándar propio'),
        'nc_abiertas', v_ncs,
        'fuente', CASE WHEN v_estandar IS NULL
                       THEN 'documentación y verificación general'
                       ELSE 'estándar de ' || v_estandar || ' + NC del equipo' END);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.fn_iniciar_auditoria_calidad(uuid, uuid) TO authenticated;

-- ── 5. Lo que quedó ───────────────────────────────────────────────────────
DO $r$
DECLARE v_c INT; v_a INT; v_g INT;
BEGIN
    SELECT count(*) FILTER (WHERE estandar = 'combustible'),
           count(*) FILTER (WHERE estandar = 'agua_industrial'),
           count(*) FILTER (WHERE estandar IS NULL)
      INTO v_c, v_a, v_g
      FROM auditoria_calidad_plantilla_items WHERE activo;
    RAISE NOTICE 'Estándar combustible: % puntos · agua industrial: % · generales: %', v_c, v_a, v_g;

    IF v_c <> 24 OR v_a <> 22 THEN
        RAISE EXCEPTION 'El estándar no quedó completo (24 y 22 esperados).';
    END IF;

    SELECT count(*) INTO v_c FROM activos a
     WHERE a.fecha_baja IS NULL AND public.fn_estandar_de_activo(a.id) = 'combustible';
    SELECT count(*) INTO v_a FROM activos a
     WHERE a.fecha_baja IS NULL AND public.fn_estandar_de_activo(a.id) = 'agua_industrial';
    RAISE NOTICE 'Equipos que caen en cada estándar -> combustible: %, agua: %', v_c, v_a;
END
$r$;

COMMIT;
