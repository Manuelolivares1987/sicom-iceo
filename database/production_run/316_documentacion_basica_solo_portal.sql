-- ============================================================================
-- MIG316 · La "documentación básica" es del portal, no de todo el sistema
-- ----------------------------------------------------------------------------
-- QUÉ ESTABA MAL EN MIG315
--   Se resolvió bien el problema equivocado de alcance. La petición era que EL
--   PORTAL DE ROMERAL mostrara primero lo básico; MIG315 lo convirtió en una
--   regla global: un catálogo `documento_tipos_config` para toda la empresa y
--   un reordenamiento del QR público de los 68 equipos.
--
--   Eso está mal por dos razones, no sólo por exceso de alcance:
--     1. "Básico" no es una propiedad del documento, es una exigencia del
--        mandante. CMP pide TC8 y hermeticidad; otro cliente puede pedir
--        tacógrafo, o no pedir póliza. Una lista global obliga a todos a
--        compartir el criterio de uno.
--     2. El QR público lo escanea el operador parado frente al camión. Ese
--        orden ya lo conocía; cambiárselo de paso, sin que nadie lo pidiera,
--        es mover el piso por un requerimiento ajeno.
--
-- QUÉ HACE ESTA MIGRACIÓN
--   Mueve la lista al portal que la necesita (`portales_prevencion.
--   documentos_basicos`), la siembra para Romeral, y deshace lo global:
--   el QR público vuelve exactamente a como estaba y el catálogo se retira.
--
--   Portal sin lista configurada = todos sus documentos se muestran juntos,
--   como antes. No inventa una clasificación que nadie pidió.
-- ============================================================================

BEGIN;

-- ── 1. La lista vive en el portal ──────────────────────────────────────────
ALTER TABLE public.portales_prevencion
    ADD COLUMN IF NOT EXISTS documentos_basicos TEXT[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN public.portales_prevencion.documentos_basicos IS
  'Que documentos exige este mandante como habilitantes, en orden de lectura. Vacio = no se separan. Es una exigencia del contrato, no una propiedad del documento. MIG316.';

-- Lo que CMP / ESMAX pide para Romeral: la carpeta de circulación, la
-- identidad del vehículo y —por ser aljibe de combustible— TC8 y hermeticidad.
UPDATE public.portales_prevencion
   SET documentos_basicos = ARRAY[
         'permiso_circulacion',
         'soap',
         'revision_tecnica',
         'analisis_gases',
         'padron',
         'inscripcion_rnvm',
         'seguro_rc',
         'tc8_sec',
         'hermeticidad'
       ],
       updated_at = NOW()
 WHERE faena_codigo = 'ROMERAL';

-- ── 2. El portal clasifica con SU lista ────────────────────────────────────
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
    v_p        portales_prevencion;
    v_basicos  TEXT[];
    v_out      JSONB;
BEGIN
    v_p := public.fn_portal_prevencion_resolver(p_token);

    IF v_p.id IS NULL THEN
        RAISE EXCEPTION 'Link no válido o revocado.' USING ERRCODE = '42501';
    END IF;

    IF NOT public.fn_portal_prevencion_acceso_vigente(v_p, p_acceso_id) THEN
        RAISE EXCEPTION 'Identifíquese para ver esta documentación.' USING ERRCODE = '42501';
    END IF;

    v_basicos := COALESCE(v_p.documentos_basicos, '{}');

    SELECT jsonb_build_object(
      'portal', jsonb_build_object(
          'nombre',                v_p.nombre,
          'cliente',               v_p.cliente,
          'faena_codigo',          v_p.faena_codigo,
          'ver_archivos_personal', v_p.ver_archivos_personal,
          -- Le dice a la pantalla si este portal separa o no. Sin lista, no
          -- hay dos secciones: se muestra todo junto, como antes.
          'separa_basicos',        (array_length(v_basicos, 1) > 0),
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
                    'basico',                (array_position(v_basicos, c.tipo::text) IS NOT NULL),
                    'numero_certificado',    c.numero_certificado,
                    'entidad_certificadora', c.entidad_certificadora,
                    'fecha_emision',         c.fecha_emision,
                    'fecha_vencimiento',     CASE WHEN c.estado_real = 'no_aplica' THEN NULL ELSE c.fecha_vencimiento END,
                    'dias_restantes',        CASE WHEN c.estado_real = 'no_aplica' THEN NULL ELSE c.dias_restantes END,
                    'estado',                c.estado_real,
                    'bloqueante',            c.bloqueante,
                    'archivo_url',           c.archivo_url
                  ) ORDER BY
                    -- Los que el mandante exige, en el orden en que los pide;
                    -- después el resto, con lo vencido arriba.
                    COALESCE(array_position(v_basicos, c.tipo::text), 999),
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

-- ── 3. El QR público vuelve exactamente a como estaba ──────────────────────
-- Misma firma, mismas columnas, mismo umbral de 45 días, mismo orden por tipo.
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
    archivo_url text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT DISTINCT ON (c.tipo) c.tipo::text, c.numero_certificado::text, c.entidad_certificadora::text,
         c.fecha_emision, c.fecha_vencimiento, (c.fecha_vencimiento - CURRENT_DATE)::int,
         CASE
           WHEN c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= DATE '2099-01-01' THEN 'permanente'
           WHEN c.fecha_vencimiento < CURRENT_DATE THEN 'vencido'
           WHEN c.fecha_vencimiento <= CURRENT_DATE + 45 THEN 'por_vencer'
           ELSE 'vigente'
         END, c.archivo_url
    FROM certificaciones c
   WHERE c.activo_id = p_activo_id
   ORDER BY c.tipo, c.fecha_vencimiento DESC NULLS LAST, c.created_at DESC
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_documentos_activo_publico(uuid) TO anon, authenticated;

-- ── 4. Retirar el catálogo global ──────────────────────────────────────────
-- destructivo-ok: documento_tipos_config nace y muere hoy. La creó MIG315 hace
-- minutos, no la referencia ninguna otra tabla, vista o función, y no guarda
-- dato de operación: es la lista de tipos que ahora vive en la fila del portal.
-- Dejarla como tabla vacía y huérfana invita a que alguien la vuelva a usar y
-- reponga la regla global que este archivo viene a deshacer.
DROP FUNCTION IF EXISTS public.fn_documento_es_basico(text);
DROP FUNCTION IF EXISTS public.fn_documento_orden(text);
DROP TABLE IF EXISTS public.documento_tipos_config;

COMMIT;
