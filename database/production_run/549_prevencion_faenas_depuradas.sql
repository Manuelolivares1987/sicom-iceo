-- ============================================================================
-- MIG549 · Prevención: solo las faenas con personal Pillado (+ alta de Spence)
-- ============================================================================
-- Manuel (2026-09-14, recién entrado al portal): «depura las faenas: las que
-- trabaja la compañía con personal son CMP Romeral, Franke, Lomas Bayas,
-- Centinela y Spence».
--
-- El selector del módulo mostraba las 23 faenas del sistema (talleres, faenas
-- de arriendo puro, históricas). La regla queda así: EL MÓDULO DE PREVENCIÓN
-- OFRECE SOLO LAS FAENAS CON REPORTABILIDAD CONFIGURADA (tienen ítems en
-- prevencion_reportabilidad_items) — que son exactamente las que tienen
-- personal propio. El frontend deja de listar el resto (cambio en
-- getFaenasPrevencion, mismo PR).
--
-- Spence (FAE-SPENCE) tenía personal pero no estaba configurada: se le crea
-- la ficha (empresa Pillado + experto César — zona Calama) y su E-200, que es
-- el mínimo legal (DS 132 art. 36: declaración mensual por instalación).
-- Mandante/instalación quedan vacíos para completar en «Datos de la faena»
-- (no se inventan RUT ni coordenadas). Más entregables de Spence se agregan
-- cuando el mandante los pida.
-- IDEMPOTENTE, ADITIVA — no borra ninguna faena (las usan otros módulos).
-- ============================================================================

BEGIN;

DO $seed$
DECLARE
    v_spence UUID;
    v_empresa JSONB := jsonb_build_object(
        'rut', '77.316.540-8',
        'razon_social', 'Pillado y Cía. Ltda.',
        'nombre_fantasia', 'Pillado Empresas',
        'categoria', 'C',
        'direccion', 'Gerónimo Méndez',
        'region', 'Cuarta',
        'provincia', 'Elqui',
        'comuna', 'La Serena',
        'telefono', '512232249',
        'email', 'contacto@pilladoempresas.cl',
        'rep_legal', 'Javier Pillado Olavarria',
        'rep_legal_rut', '14.107.232-3',
        'rep_legal_telefono', '966299715',
        'rep_legal_email', 'Javier.pillado@pilladoempresas.cl'
    );
BEGIN
    SELECT id INTO v_spence FROM faenas WHERE codigo = 'FAE-SPENCE';
    IF v_spence IS NULL THEN
        RAISE EXCEPTION 'FAE-SPENCE no existe en faenas — revisar código';
    END IF;

    -- Ficha de la faena (zona Calama → César, igual que Lomas y Centinela).
    INSERT INTO prevencion_faena_config (faena_id, datos) VALUES (v_spence, jsonb_build_object(
        'empresa', v_empresa,
        'experto', jsonb_build_object(
            'nombre', 'César', 'run', '', 'registro_sngm', '',
            'cargo', 'Asesor en Prevención de Riesgos', 'telefono', '', 'email', ''),
        'mandante', jsonb_build_object('rut','','razon_social','','nombre_fantasia','','region','Antofagasta'),
        'faena_nombre', 'Spence',
        'instalacion', jsonb_build_object('nombre','','estado','Activa','region','Antofagasta','provincia','',
            'comuna','','tipo','','datum','','huso','','cota','','coord_norte','','coord_este',''),
        'contrato', jsonb_build_object('numero','','inicio','','vigencia','','administrador','',
            'asesor_prevencion','','instalacion_informe','','superintendencia','',
            'admin_mandante','','cargo_admin_mandante','','operador_mandante','','cargo_operador_mandante',''),
        'mutual', ''
    ))
    ON CONFLICT (faena_id) DO NOTHING;

    -- El mínimo legal: E-200 mensual. Con esto Spence entra al selector.
    INSERT INTO prevencion_reportabilidad_items
        (faena_id, nombre, descripcion, fuente, destino, dia_limite, orden, plantilla)
    VALUES
        (v_spence, 'E-200 SERNAGEOMIN',
         'Declaración mensual de accidentabilidad (con o sin accidentes). DS 132 art. 36.',
         'Dotación y HH del personal en Spence', 'SIMIN — simin.sernageomin.cl', 10, 10, 'e200')
    ON CONFLICT (faena_id, nombre) DO NOTHING;

    -- Los rotativos de Calama también responden por Spence (editable en
    -- «Asignar supervisores»).
    INSERT INTO prevencion_supervisor_faenas (usuario_id, faena_id)
    SELECT up.id, v_spence
      FROM usuarios_perfil up
     WHERE up.email IN ('supcalama@pillado.cl', 'hcorey@pillado.cl') AND up.activo
    ON CONFLICT (usuario_id, faena_id) DO NOTHING;
END $seed$;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN: las faenas que ofrecerá el módulo
-- ============================================================================
SELECT f.nombre, COUNT(it.id) AS reportabilidades
FROM prevencion_reportabilidad_items it
JOIN faenas f ON f.id = it.faena_id
WHERE it.activo
GROUP BY f.nombre ORDER BY f.nombre;
