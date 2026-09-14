-- ============================================================================
-- MIG547 · Prevención fase 2: entregables automáticos + monitoreo supervisores
-- ============================================================================
-- Manuel (2026-09-14, sobre el PR #329): «Le agregaría a la fase 2 todos los
-- entregables por faena —por ejemplo, Lomas pide una presentación— quisiera
-- que todo saliera automático, que cada supervisor pueda ingresar la
-- información y que el prevencionista pueda ir monitoreando.»
--
-- Tres piezas (ADITIVAS, IDEMPOTENTES):
--
--   1. prevencion_faena_config ....... los datos fijos que cada entregable
--      repite mes a mes (RUT y dirección de Pillado, mandante, instalación,
--      coordenadas del E-200, contrato, experto SNGM). Se digitan UNA vez y
--      el generador los toma de aquí. Seed con lo que traen los formatos
--      reales de la carpeta PREVENCION (E-200 Franke agosto 2026 e informe
--      TA.DPR.IN.SS-0005); lo que no aparece en esos documentos queda vacío
--      y editable —no se inventa un RUT ni una coordenada—.
--   2. prevencion_reportabilidad_items.plantilla ... qué generador produce
--      cada entregable: 'e200' (Excel), 'grp_cmp' (PDF formato CMP Romeral),
--      'informe_franke' (Excel TA.DPR), 'ppt_evidencias' (PPT con las fotos
--      del mes — el Anexo 10.2 de Lomas). NULL = sin generador (se adjunta a
--      mano, como el GCOM que vive en plataforma del mandante).
--   3. v_prevencion_monitoreo_supervisores ... cuántos registros cargó cada
--      supervisor por faena y mes (y de qué tipo, y cuándo fue el último).
--      Con usuarios_perfil (rol supervisor + faena_id) el panel muestra
--      también QUIÉN NO ha cargado nada.
-- ============================================================================

BEGIN;

-- ############################################################################
-- 1. CONFIGURACIÓN POR FAENA (datos fijos de los entregables)
-- ############################################################################

CREATE TABLE IF NOT EXISTS prevencion_faena_config (
    faena_id    UUID PRIMARY KEY REFERENCES faenas(id),
    -- Un solo jsonb y no 40 columnas: cada mandante pide campos distintos y
    -- esto lo edita prevención desde el panel, no por SQL.
    datos       JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_by  UUID REFERENCES auth.users(id),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE prevencion_faena_config IS
    'Datos fijos por faena para generar entregables (empresa, mandante, instalación E-200, contrato, experto). Editables por prevención. MIG547.';

ALTER TABLE prevencion_faena_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_cfg_select ON prevencion_faena_config;
CREATE POLICY prev_cfg_select ON prevencion_faena_config
    FOR SELECT TO authenticated
    USING ((fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear())
           AND fn_prevencion_faena_visible(faena_id));

DROP POLICY IF EXISTS prev_cfg_admin ON prevencion_faena_config;
CREATE POLICY prev_cfg_admin ON prevencion_faena_config
    FOR ALL TO authenticated
    USING (fn_prevencion_reporta_puede_admin())
    WITH CHECK (fn_prevencion_reporta_puede_admin());

GRANT SELECT, INSERT, UPDATE ON prevencion_faena_config TO authenticated;

-- ── Seed: SOLO lo que traen los documentos reales de la carpeta ─────────────
DO $seed$
DECLARE
    v_id UUID;
    -- Bloque empresa: idéntico en todos los E-200 (viene del formulario real).
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
    v_experto JSONB := jsonb_build_object(
        'nombre', 'Anyulin Pabla Cortés Cortés',
        'run', '18.483.927-k',
        'registro_sngm', '',
        'cargo', 'Asesor en Prevención de Riesgos',
        'telefono', '+56975389902',
        'email', 'prevencion@pilladoempresas.cl'
    );
BEGIN
    -- FRANKE: todo sale del E-200 de agosto 2026 y del informe TA.DPR.
    SELECT id INTO v_id FROM faenas WHERE codigo = 'FAE-FRANCKE';
    IF v_id IS NOT NULL THEN
        INSERT INTO prevencion_faena_config (faena_id, datos) VALUES (v_id, jsonb_build_object(
            'empresa', v_empresa,
            'experto', v_experto,
            'mandante', jsonb_build_object(
                'rut', '76.051.610-4',
                'razon_social', 'SOCIEDAD CONTRACTUAL MINERA FRANKE LTDA',
                'nombre_fantasia', 'SCM FRANKE',
                'region', 'Antofagasta'),
            'faena_nombre', 'Mina Franke',
            'instalacion', jsonb_build_object(
                'nombre', 'Minera SCM Franke',
                'estado', 'Activa',
                'region', 'Antofagasta',
                'provincia', 'Taltal',
                'comuna', 'Taltal',
                'tipo', '',
                'datum', 'PSAD-56',
                'huso', '19',
                'cota', '1.645',
                'coord_norte', '7.143.359',
                'coord_este', '412.098'),
            'contrato', jsonb_build_object(
                'numero', 'C 220-2024',
                'inicio', '2024-09-01',
                'vigencia', '2026-09-28',
                'administrador', 'Rodrigo Cortés',
                'asesor_prevencion', 'Anyulin Cortés',
                'instalacion_informe', 'Planta - Mina',
                'superintendencia', 'Mina',
                'admin_mandante', 'John Perez',
                'cargo_admin_mandante', 'Superintendente mina',
                'operador_mandante', 'Alex Maya',
                'cargo_operador_mandante', 'Jefe de Operaciones'),
            'mutual', ''
        ))
        ON CONFLICT (faena_id) DO NOTHING;
    END IF;

    -- ROMERAL / LOMAS / CENTINELA: bloque empresa + experto; el resto lo
    -- completa prevención desde el panel (no está en los documentos y no se
    -- inventa).
    FOR v_id IN
        SELECT id FROM faenas WHERE codigo IN ('FAE-CMP-ROMERAL','FAE-LOMASBAYAS','FAE-CENTINELA')
    LOOP
        INSERT INTO prevencion_faena_config (faena_id, datos) VALUES (v_id, jsonb_build_object(
            'empresa', v_empresa,
            'experto', v_experto,
            'mandante', jsonb_build_object('rut','','razon_social','','nombre_fantasia','','region',''),
            'faena_nombre', '',
            'instalacion', jsonb_build_object('nombre','','estado','Activa','region','','provincia','',
                'comuna','','tipo','','datum','','huso','','cota','','coord_norte','','coord_este',''),
            'contrato', jsonb_build_object('numero','','inicio','','vigencia','','administrador','',
                'asesor_prevencion','Anyulin Cortés','instalacion_informe','','superintendencia','',
                'admin_mandante','','cargo_admin_mandante','','operador_mandante','','cargo_operador_mandante',''),
            'mutual', ''
        ))
        ON CONFLICT (faena_id) DO NOTHING;
    END LOOP;
END $seed$;

-- ############################################################################
-- 2. PLANTILLA POR ENTREGABLE
-- ############################################################################

ALTER TABLE prevencion_reportabilidad_items
    ADD COLUMN IF NOT EXISTS plantilla VARCHAR(30)
    CHECK (plantilla IS NULL OR plantilla IN ('e200','grp_cmp','informe_franke','ppt_evidencias'));

COMMENT ON COLUMN prevencion_reportabilidad_items.plantilla IS
    'Generador automático del entregable: e200 (Excel SERNAGEOMIN), grp_cmp (PDF informe CMP), informe_franke (Excel TA.DPR), ppt_evidencias (PPT con fotos del mes). NULL = se adjunta a mano. MIG547.';

-- Asignación según lo que pide cada mandante (documento de reportabilidad):
UPDATE prevencion_reportabilidad_items SET plantilla = 'e200'
 WHERE nombre = 'E-200 SERNAGEOMIN' AND plantilla IS DISTINCT FROM 'e200';

UPDATE prevencion_reportabilidad_items it SET plantilla = 'grp_cmp'
  FROM faenas f
 WHERE f.id = it.faena_id AND f.codigo = 'FAE-CMP-ROMERAL'
   AND it.nombre = 'Informe de Gestión Mensual GRP';

UPDATE prevencion_reportabilidad_items it SET plantilla = 'informe_franke'
  FROM faenas f
 WHERE f.id = it.faena_id AND f.codigo = 'FAE-FRANCKE'
   AND it.nombre = 'Informe de Gestión Mensual';

-- Los entregables que son «evidencias del mes en láminas»: el Anexo 10.2 de
-- Lomas, las actividades HS para SAFEWORK y la documentación ambiental Franke.
UPDATE prevencion_reportabilidad_items it SET plantilla = 'ppt_evidencias'
  FROM faenas f
 WHERE f.id = it.faena_id
   AND ((f.codigo = 'FAE-LOMASBAYAS' AND it.nombre IN
            ('PPT Lubricantes y Combustible — Anexo 10.2', 'Actividades HS — SAFEWORK'))
     OR (f.codigo = 'FAE-FRANCKE' AND it.nombre = 'Documentación ambiental'));

-- ############################################################################
-- 3. MONITOREO: QUÉ CARGÓ CADA SUPERVISOR
-- ############################################################################

-- security_invoker: hereda el RLS de prevencion_registros (el supervisor con
-- solo_su_faena ve su faena; prevención ve todo).
CREATE OR REPLACE VIEW v_prevencion_monitoreo_supervisores
WITH (security_invoker = true) AS
WITH base AS (
    SELECT faena_id,
           EXTRACT(YEAR  FROM fecha_actividad)::int AS anio,
           EXTRACT(MONTH FROM fecha_actividad)::int AS mes,
           creado_por, tipo_codigo, estado, created_at, supervisor_nombre
    FROM prevencion_registros
),
tipos AS (
    -- {"VCT": 12, "RIT": 4, ...} para pintar la fila sin N queries.
    SELECT faena_id, anio, mes, creado_por,
           jsonb_object_agg(tipo_codigo, n) AS por_tipo
    FROM (SELECT faena_id, anio, mes, creado_por, tipo_codigo, COUNT(*) AS n
            FROM base GROUP BY 1, 2, 3, 4, 5) s
    GROUP BY 1, 2, 3, 4
)
SELECT
    b.faena_id, b.anio, b.mes, b.creado_por,
    COALESCE(up.nombre_completo, MAX(b.supervisor_nombre), '(sin nombre)') AS supervisor,
    up.rol,
    COUNT(*)                                   AS total,
    COUNT(*) FILTER (WHERE b.estado='abierto') AS abiertos,
    MAX(b.created_at)                          AS ultima_carga,
    t.por_tipo
FROM base b
LEFT JOIN usuarios_perfil up ON up.id = b.creado_por
LEFT JOIN tipos t ON t.faena_id = b.faena_id AND t.anio = b.anio
                 AND t.mes = b.mes AND t.creado_por = b.creado_por
GROUP BY b.faena_id, b.anio, b.mes, b.creado_por, up.nombre_completo, up.rol, t.por_tipo;

GRANT SELECT ON v_prevencion_monitoreo_supervisores TO authenticated;

-- Los supervisores QUE DEBERÍAN reportar en una faena (para marcar faltantes).
-- SECURITY DEFINER acotado: expone solo id/nombre/email de supervisores
-- activos de ESA faena, y únicamente a quien puede ver el módulo.
CREATE OR REPLACE FUNCTION public.rpc_prevencion_supervisores_faena(p_faena_id UUID)
RETURNS TABLE (usuario_id UUID, nombre TEXT, email TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
BEGIN
    IF NOT (fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear()) THEN
        RAISE EXCEPTION 'Sin permiso';
    END IF;
    IF NOT fn_prevencion_faena_visible(p_faena_id) THEN
        RAISE EXCEPTION 'Sin acceso a esta faena';
    END IF;
    RETURN QUERY
    SELECT up.id, up.nombre_completo::text, up.email::text
      FROM usuarios_perfil up
     WHERE up.activo
       AND up.rol IN ('supervisor','jefe_operaciones','jefe_mantenimiento')
       AND up.faena_id = p_faena_id
     ORDER BY up.nombre_completo;
END $function$;

GRANT EXECUTE ON FUNCTION rpc_prevencion_supervisores_faena(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION rpc_prevencion_supervisores_faena(UUID) FROM anon;

-- ############################################################################
-- 4. EL CONSOLIDADO AHORA TRAE LA PLANTILLA DE CADA ENTREGABLE
-- ############################################################################
-- (reemplaza la versión MIG546: mismo contrato + campo 'plantilla' para que
--  el panel sepa qué botón «Generar» mostrar)

CREATE OR REPLACE FUNCTION public.rpc_prevencion_consolidado_mes(
    p_faena_id UUID, p_anio INTEGER, p_mes INTEGER
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
    v_out jsonb;
BEGIN
    IF NOT (fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear()) THEN
        RAISE EXCEPTION 'Sin permiso para ver la reportabilidad de prevención';
    END IF;
    IF NOT fn_prevencion_faena_visible(p_faena_id) THEN
        RAISE EXCEPTION 'Sin acceso a esta faena';
    END IF;

    SELECT jsonb_build_object(
        'gestion', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'tipo_codigo', g.tipo_codigo, 'tipo_nombre', g.tipo_nombre,
                'requiere_cierre', g.requiere_cierre,
                'meta', g.meta, 'realizados', g.realizados,
                'abiertos', g.abiertos, 'cerrados', g.cerrados,
                'pct_cumplimiento', g.pct_cumplimiento
            ) ORDER BY g.tipo_orden)
            FROM v_prevencion_gestion_mensual g
            WHERE g.faena_id = p_faena_id AND g.anio = p_anio AND g.mes = p_mes
        ), '[]'::jsonb),
        'indicadores', (
            SELECT to_jsonb(v.*) FROM v_prevencion_indicadores v
            WHERE v.faena_id = p_faena_id AND v.anio = p_anio AND v.mes = p_mes
        ),
        'reportabilidad', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'item_id', it.id, 'nombre', it.nombre, 'destino', it.destino,
                'fuente', it.fuente, 'dia_limite', it.dia_limite,
                'plantilla', it.plantilla,
                'enviado', (e.id IS NOT NULL),
                'fecha_envio', e.fecha_envio, 'archivos', e.archivos,
                'observacion', e.observacion
            ) ORDER BY it.orden)
            FROM prevencion_reportabilidad_items it
            LEFT JOIN prevencion_reportabilidad_envios e
              ON e.item_id = it.id AND e.anio = p_anio AND e.mes = p_mes
            WHERE it.faena_id = p_faena_id AND it.activo
        ), '[]'::jsonb),
        'abiertos_arrastre', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'id', r.id, 'tipo_codigo', r.tipo_codigo, 'titulo', r.titulo,
                'fecha_actividad', r.fecha_actividad,
                'supervisor', r.supervisor_nombre
            ) ORDER BY r.fecha_actividad)
            FROM prevencion_registros r
            WHERE r.faena_id = p_faena_id AND r.estado = 'abierto'
              AND r.fecha_actividad < make_date(p_anio, p_mes, 1)
        ), '[]'::jsonb)
    ) INTO v_out;

    RETURN v_out;
END $function$;

-- ############################################################################
-- 5. EXPERTO POR ZONA (corrección Manuel 2026-09-14)
-- ############################################################################
-- «Anyulin ve Coquimbo y en Calama tenemos a César.» Romeral (Coquimbo) y
-- Franke (el E-200 real de agosto 2026 lo firma Anyulin) quedan con Anyulin;
-- Lomas Bayas y Centinela (zona Calama) pasan a César. César no tiene cuenta
-- en SICOM ni conocemos su RUN/registro: se deja solo el nombre y prevención
-- completa el resto desde «Datos de la faena» (no se inventa un RUN).
-- Idempotente: solo pisa el experto si sigue siendo el seed de Anyulin.

UPDATE prevencion_faena_config c
   SET datos = jsonb_set(c.datos, '{experto}', jsonb_build_object(
           'nombre', 'César',
           'run', '',
           'registro_sngm', '',
           'cargo', 'Asesor en Prevención de Riesgos',
           'telefono', '',
           'email', ''
       )),
       updated_at = NOW()
  FROM faenas f
 WHERE f.id = c.faena_id
   AND f.codigo IN ('FAE-LOMASBAYAS', 'FAE-CENTINELA')
   AND c.datos->'experto'->>'nombre' LIKE 'Anyulin%';

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
SELECT
    (SELECT COUNT(*) FROM prevencion_faena_config)                                   AS configs,
    (SELECT COUNT(*) FROM prevencion_reportabilidad_items WHERE plantilla IS NOT NULL) AS items_con_generador,
    (SELECT string_agg(DISTINCT plantilla, ', ') FROM prevencion_reportabilidad_items) AS plantillas;
