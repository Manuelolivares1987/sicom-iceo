-- ============================================================================
-- MIG315 · Documentación básica del equipo: lo que se mira primero
-- ----------------------------------------------------------------------------
-- EL PROBLEMA
--   Un camión aljibe tiene 21 documentos cargados. Al mandante le tiramos los
--   21 en una tabla y ahí, entre el "Cert. Torque Ruedas" y el "Inventario de
--   Neumáticos", se pierde lo único que de verdad pregunta: si el camión puede
--   circular. SOAP, revisión técnica y permiso de circulación quedaban al mismo
--   nivel visual que la ficha técnica.
--
-- POR QUÉ NO SIRVE LA COLUMNA `bloqueante` QUE YA EXISTÍA
--   Está mal curada, y de una forma que engaña: hermeticidad marcada en 14 de
--   25 cisternas, TC8 SEC en 14 de 17, análisis de gases en 1 de 39. Dos
--   camiones idénticos mostrarían "documentación básica" distinta según cómo
--   se cargó el papel. No se toca esa columna acá —la leen las alertas y los
--   gates— pero deja de mandar en lo que se muestra.
--
-- LO QUE SE HACE
--   Un catálogo de tipos: cuáles son básicos y en qué orden se leen. Es una
--   tabla y no un CASE en el código porque cada mandante pide su propio set:
--   agregar uno es un INSERT, no una migración. Mismo criterio que MIG298.
--
--   Básicos = lo que habilita al vehículo a circular y operar:
--     · Permiso de circulación, SOAP, revisión técnica y análisis de gases
--       — la carpeta que pide Carabineros en la ruta.
--     · Padrón y póliza de seguro — de quién es y quién responde.
--     · TC8 SEC y hermeticidad — sin eso un aljibe no mueve combustible.
--   Todo lo demás es certificación técnica: importa, pero es la segunda
--   pregunta, no la primera.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.documento_tipos_config (
    tipo    TEXT PRIMARY KEY,
    basico  BOOLEAN NOT NULL DEFAULT false,
    orden   INTEGER NOT NULL DEFAULT 100,
    nota    TEXT
);

COMMENT ON TABLE public.documento_tipos_config IS
  'Que documentos son "basicos" (habilitan a circular y operar) y en que orden se leen. Configurable: cada mandante pide su set. MIG315.';

INSERT INTO public.documento_tipos_config (tipo, basico, orden, nota) VALUES
    ('permiso_circulacion', true,  10, 'Habilita la circulación del vehículo'),
    ('soap',                true,  20, 'Seguro obligatorio de accidentes personales'),
    ('revision_tecnica',    true,  30, 'Revisión técnica al día'),
    ('analisis_gases',      true,  40, 'Va junto a la revisión técnica en vehículos diésel'),
    ('padron',              true,  50, 'Identidad e inscripción del vehículo'),
    ('inscripcion_rnvm',    true,  55, 'Inscripción en el Registro Nacional de Vehículos Motorizados'),
    ('seguro_rc',           true,  60, 'Póliza de responsabilidad civil exigida por contrato'),
    ('tc8_sec',             true,  70, 'Sin TC8 vigente un aljibe no puede mover combustible'),
    ('hermeticidad',        true,  80, 'Estanqueidad del estanque: exigencia SEC / DS 298')
ON CONFLICT (tipo) DO UPDATE
   SET basico = EXCLUDED.basico, orden = EXCLUDED.orden, nota = EXCLUDED.nota;

GRANT SELECT ON public.documento_tipos_config TO authenticated;

-- ¿Este tipo de documento es de los básicos? Fail-safe: lo que no está en el
-- catálogo se considera técnico, no básico. Si mañana entra un tipo nuevo,
-- aparece en la segunda sección, no desaparece.
CREATE OR REPLACE FUNCTION public.fn_documento_es_basico(p_tipo text)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path TO 'public', 'pg_temp'
AS $f$
    SELECT COALESCE((SELECT c.basico FROM documento_tipos_config c WHERE c.tipo = p_tipo), false);
$f$;

CREATE OR REPLACE FUNCTION public.fn_documento_orden(p_tipo text)
RETURNS integer
LANGUAGE sql STABLE
SET search_path TO 'public', 'pg_temp'
AS $f$
    SELECT COALESCE((SELECT c.orden FROM documento_tipos_config c WHERE c.tipo = p_tipo), 100);
$f$;

GRANT EXECUTE ON FUNCTION public.fn_documento_es_basico(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_documento_orden(text) TO anon, authenticated;

-- ── El portal marca cada documento y trae más historial ────────────────────
-- Al ver un camión se ve su documentación Y lo que se le ha hecho, juntos.
-- Antes estaban en pestañas separadas y había que ir a buscar la segunda.
CREATE OR REPLACE FUNCTION public.fn_portal_prevencion_publico(
    p_token     text,
    p_acceso_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_p   portales_prevencion;
    v_out JSONB;
BEGIN
    v_p := public.fn_portal_prevencion_resolver(p_token);

    IF v_p.id IS NULL THEN
        RAISE EXCEPTION 'Link no válido o revocado.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.fn_portal_prevencion_acceso_vigente(v_p, p_acceso_id) THEN
        RAISE EXCEPTION 'Identifíquese para ver esta documentación.' USING ERRCODE = '42501';
    END IF;

    SELECT jsonb_build_object(
      'portal', jsonb_build_object(
          'nombre',                v_p.nombre,
          'cliente',               v_p.cliente,
          'faena_codigo',          v_p.faena_codigo,
          'ver_archivos_personal', v_p.ver_archivos_personal,
          'generado_at',           NOW()
      ),

      'equipos', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'activo_id', a.id,
            'patente',   COALESCE(a.patente, a.codigo),
            'codigo',    a.codigo,
            'nombre',    a.nombre,
            'tipo',      a.tipo,
            'ubicacion', a.ubicacion_actual,
            'estado_codigo', ep.estado_codigo,
            'marca_modelo', NULLIF(trim(concat_ws(' ', mar.nombre, mod.nombre)), ''),
            'documentos', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'tipo',                  c.tipo,
                    'basico',                fn_documento_es_basico(c.tipo::text),
                    'numero_certificado',    c.numero_certificado,
                    'entidad_certificadora', c.entidad_certificadora,
                    'fecha_emision',         c.fecha_emision,
                    'fecha_vencimiento',     CASE WHEN c.estado_real = 'no_aplica' THEN NULL ELSE c.fecha_vencimiento END,
                    'dias_restantes',        CASE WHEN c.estado_real = 'no_aplica' THEN NULL ELSE c.dias_restantes END,
                    'estado',                c.estado_real,
                    'bloqueante',            c.bloqueante,
                    'archivo_url',           c.archivo_url
                  ) ORDER BY
                    -- Primero los básicos en su orden de lectura; después el
                    -- resto, y dentro de cada grupo lo vencido arriba.
                    fn_documento_es_basico(c.tipo::text) DESC,
                    fn_documento_orden(c.tipo::text),
                    CASE c.estado_real
                      WHEN 'vencido' THEN 0 WHEN 'por_vencer' THEN 1
                      WHEN 'vigente' THEN 2 ELSE 3 END,
                    c.fecha_vencimiento)
                FROM v_certificacion_actual c
                WHERE c.activo_id = a.id
            ), '[]'::jsonb),
            'mantenimiento', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'folio',    m.folio,
                    'fecha',    m.fecha,
                    'tipo',     m.tipo,
                    'trabajo',  m.trabajo_realizado,
                    'km',       m.km_al_cierre,
                    'horas',    m.horas_al_cierre
                  ) ORDER BY m.fecha DESC)
                FROM (
                    SELECT * FROM v_historial_mantenimiento_equipo v
                     WHERE v.activo_id = a.id
                     ORDER BY v.fecha DESC LIMIT 15
                ) m
            ), '[]'::jsonb)
          ) ORDER BY COALESCE(a.patente, a.codigo))
        FROM activos a
        LEFT JOIN v_activos_estado_planificador ep ON ep.activo_id = a.id
        LEFT JOIN modelos mod ON mod.id = a.modelo_id
        LEFT JOIN marcas  mar ON mar.id = mod.marca_id
        WHERE a.id = ANY(v_p.activo_ids)
      ), '[]'::jsonb),

      'personal', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'personal_id',    pe.personal_id,
            'nombre',         pe.nombres || ' ' || pe.apellidos,
            'rut_enmascarado', public.fn_portal_prevencion_rut_mascara(pe.rut),
            'cargo',          pe.cargo,
            'empresa',        pe.empresa,
            'estado_general', pe.estado_general,
            'documentos', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'examen_id',        ex.id,
                    'tipo_codigo',      ex.tipo_codigo,
                    'tipo_nombre',      ex.tipo_nombre,
                    'categoria',        ex.categoria,
                    'laboratorio',      ex.laboratorio,
                    'fecha_vencimiento', ex.fecha_vencimiento,
                    'dias_restantes',   ex.dias_restantes,
                    'estado',           ex.estado,
                    'aplica',           ex.aplica,
                    'motivo_no_aplica', ex.motivo_no_aplica,
                    'tiene_archivo',    (ex.archivo_path IS NOT NULL)
                  ) ORDER BY ex.categoria, ex.orden)
                FROM v_prevencion_examenes_estado ex
                WHERE ex.personal_id = pe.personal_id
            ), '[]'::jsonb)
          ) ORDER BY
            CASE pe.estado_general
              WHEN 'no_conforme' THEN 0 WHEN 'critico' THEN 1
              WHEN 'observado' THEN 2 ELSE 3 END,
            pe.apellidos, pe.nombres)
        FROM v_prevencion_personal_estado pe
        WHERE v_p.faena_codigo IS NOT NULL
          AND pe.faena_codigo = v_p.faena_codigo
          AND pe.activo
      ), '[]'::jsonb)
    ) INTO v_out;

    BEGIN
        UPDATE portales_prevencion
           SET usos = usos + 1, last_used_at = NOW()
         WHERE id = v_p.id;
        IF p_acceso_id IS NOT NULL THEN
            UPDATE portal_prevencion_accesos
               SET vistas = vistas + 1, ultima_vista = NOW()
             WHERE id = p_acceso_id;
        END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN v_out;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_portal_prevencion_publico(text, uuid) TO anon, authenticated;

-- ── El QR público del equipo también ordena por lo básico ──────────────────
-- Es la misma pregunta hecha desde el otro lado: el operador escanea el camión
-- y quiere ver si está al día, no la lista completa de certificados.
--
-- Se conserva EXACTO lo que ya devolvía (mismas columnas, mismo umbral de 45
-- días para "por vencer", mismo 'permanente'): cambiar eso de paso movería el
-- semáforo que la gente ya conoce. Sólo se agrega `basico` y el orden.
DROP FUNCTION IF EXISTS public.rpc_documentos_activo_publico(uuid);

CREATE FUNCTION public.rpc_documentos_activo_publico(p_activo_id uuid)
RETURNS TABLE(
    tipo text,
    numero_certificado text,
    entidad text,
    fecha_emision date,
    fecha_vencimiento date,
    dias_restantes integer,
    estado text,
    archivo_url text,
    basico boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT * FROM (
      SELECT DISTINCT ON (c.tipo)
             c.tipo::text, c.numero_certificado::text, c.entidad_certificadora::text,
             c.fecha_emision, c.fecha_vencimiento, (c.fecha_vencimiento - CURRENT_DATE)::int,
             CASE
               WHEN c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= DATE '2099-01-01' THEN 'permanente'
               WHEN c.fecha_vencimiento < CURRENT_DATE THEN 'vencido'
               WHEN c.fecha_vencimiento <= CURRENT_DATE + 45 THEN 'por_vencer'
               ELSE 'vigente'
             END, c.archivo_url,
             fn_documento_es_basico(c.tipo::text)
        FROM certificaciones c
       WHERE c.activo_id = p_activo_id
       ORDER BY c.tipo, c.fecha_vencimiento DESC NULLS LAST, c.created_at DESC
  ) d(tipo, numero_certificado, entidad, fecha_emision, fecha_vencimiento,
      dias_restantes, estado, archivo_url, basico)
  ORDER BY d.basico DESC, fn_documento_orden(d.tipo), d.tipo;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_documentos_activo_publico(uuid) TO anon, authenticated;

COMMIT;
