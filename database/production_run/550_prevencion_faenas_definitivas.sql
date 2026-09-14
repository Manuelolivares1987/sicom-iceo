-- ============================================================================
-- MIG550 · Prevención: las 6 faenas definitivas (Lomas partida en dos)
-- ============================================================================
-- Manuel (2026-09-14): «Spence Combustible, Centinela Combustible, Lomas
-- Bayas Combustible, Lomas Bayas Lubricantes, CMP Romeral y Franke — estas
-- son las faenas definitivas.»
--
--   1. Renombres (solo el NOMBRE; el código y el id no cambian, así ningún
--      módulo que referencia por id/código se ve afectado):
--         Lomas Bayas   → Lomas Bayas — Combustible
--         Centinela     → Centinela — Combustible
--         Spence — Boart Longyear → Spence — Combustible
--   2. Alta de la faena NUEVA «Lomas Bayas — Lubricantes» (FAE-LOMASBAYAS-LUB)
--      heredando ubicación, comuna, coordenadas y contrato de Lomas. Es el
--      mismo yacimiento con dos servicios distintos — coincide con lo ya
--      conocido en ENEX («2 faenas Lomas, filtrar por LB_LUB»).
--   3. Reparto de la reportabilidad de Lomas:
--         Lubricantes  ← «PPT Lubricantes y Combustible — Anexo 10.2» (su
--                        respaldo real de la carpeta era del lubricante ARNOL)
--                        + su propio E-200.
--         Combustible  ← conserva E-200, SAFEWORK y GCOM.
--   4. Ficha de la nueva faena (empresa Pillado + experto César, zona
--      Calama) y rotativos de Calama asignados.
--
-- Los registros/metas/indicadores ya cargados en «Lomas Bayas» quedan en
-- Lomas Bayas — Combustible (misma fila, solo cambió el nombre).
-- IDEMPOTENTE. Editable después desde «Datos de la faena».
-- ============================================================================

BEGIN;

-- ── 1. Renombres ────────────────────────────────────────────────────────────
UPDATE faenas SET nombre = 'Lomas Bayas — Combustible', updated_at = NOW()
 WHERE codigo = 'FAE-LOMASBAYAS' AND nombre <> 'Lomas Bayas — Combustible';
UPDATE faenas SET nombre = 'Centinela — Combustible', updated_at = NOW()
 WHERE codigo = 'FAE-CENTINELA' AND nombre <> 'Centinela — Combustible';
UPDATE faenas SET nombre = 'Spence — Combustible', updated_at = NOW()
 WHERE codigo = 'FAE-SPENCE' AND nombre <> 'Spence — Combustible';

-- ── 2..4. Lomas Bayas — Lubricantes ─────────────────────────────────────────
DO $seed$
DECLARE
    v_lomas   faenas%ROWTYPE;
    v_lub     UUID;
    v_empresa JSONB;
BEGIN
    SELECT * INTO v_lomas FROM faenas WHERE codigo = 'FAE-LOMASBAYAS';
    IF v_lomas.id IS NULL THEN
        RAISE EXCEPTION 'FAE-LOMASBAYAS no existe';
    END IF;

    -- Alta (idempotente por código)
    SELECT id INTO v_lub FROM faenas WHERE codigo = 'FAE-LOMASBAYAS-LUB';
    IF v_lub IS NULL THEN
        INSERT INTO faenas (contrato_id, codigo, nombre, ubicacion, region, comuna,
                            coordenadas_lat, coordenadas_lng, estado)
        VALUES (v_lomas.contrato_id, 'FAE-LOMASBAYAS-LUB', 'Lomas Bayas — Lubricantes',
                v_lomas.ubicacion, v_lomas.region, v_lomas.comuna,
                v_lomas.coordenadas_lat, v_lomas.coordenadas_lng, 'activa')
        RETURNING id INTO v_lub;
    END IF;

    -- Ficha: mismo bloque empresa que las demás (lo comparte toda la compañía)
    SELECT datos->'empresa' INTO v_empresa
      FROM prevencion_faena_config WHERE faena_id = v_lomas.id;

    INSERT INTO prevencion_faena_config (faena_id, datos) VALUES (v_lub, jsonb_build_object(
        'empresa', COALESCE(v_empresa, '{}'::jsonb),
        'experto', jsonb_build_object(
            'nombre', 'César', 'run', '', 'registro_sngm', '',
            'cargo', 'Asesor en Prevención de Riesgos', 'telefono', '', 'email', ''),
        'mandante', jsonb_build_object('rut','','razon_social','','nombre_fantasia','','region','Antofagasta'),
        'faena_nombre', 'Lomas Bayas',
        'instalacion', jsonb_build_object('nombre','','estado','Activa','region','Antofagasta',
            'provincia','','comuna','Sierra Gorda','tipo','','datum','','huso','','cota','',
            'coord_norte','','coord_este',''),
        'contrato', jsonb_build_object('numero','','inicio','','vigencia','','administrador','',
            'asesor_prevencion','','instalacion_informe','','superintendencia','',
            'admin_mandante','','cargo_admin_mandante','','operador_mandante','','cargo_operador_mandante',''),
        'mutual', ''
    ))
    ON CONFLICT (faena_id) DO NOTHING;

    -- El Anexo 10.2 se muda a Lubricantes (con sus envíos históricos, si los
    -- hubiera: el UPDATE arrastra item_id y los envíos cuelgan del item).
    UPDATE prevencion_reportabilidad_items
       SET faena_id = v_lub
     WHERE faena_id = v_lomas.id
       AND nombre = 'PPT Lubricantes y Combustible — Anexo 10.2';

    -- E-200 propio de Lubricantes
    INSERT INTO prevencion_reportabilidad_items
        (faena_id, nombre, descripcion, fuente, destino, dia_limite, orden, plantilla)
    VALUES
        (v_lub, 'E-200 SERNAGEOMIN',
         'Declaración mensual de accidentabilidad (con o sin accidentes). DS 132 art. 36.',
         'Dotación y HH del personal de lubricantes en Lomas Bayas', 'SIMIN — simin.sernageomin.cl', 10, 5, 'e200')
    ON CONFLICT (faena_id, nombre) DO NOTHING;

    -- Rotativos de Calama también responden por esta faena
    INSERT INTO prevencion_supervisor_faenas (usuario_id, faena_id)
    SELECT up.id, v_lub FROM usuarios_perfil up
     WHERE up.email IN ('supcalama@pillado.cl', 'hcorey@pillado.cl') AND up.activo
    ON CONFLICT (usuario_id, faena_id) DO NOTHING;
END $seed$;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN: las 6 definitivas con su reportabilidad
-- ============================================================================
SELECT f.nombre, string_agg(it.nombre, ' · ' ORDER BY it.orden) AS reportabilidad
FROM prevencion_reportabilidad_items it
JOIN faenas f ON f.id = it.faena_id
WHERE it.activo
GROUP BY f.nombre ORDER BY f.nombre;
