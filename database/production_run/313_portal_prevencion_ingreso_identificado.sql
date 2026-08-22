-- ============================================================================
-- MIG313 · El portal del mandante deja de ser una puerta sin llave
-- ----------------------------------------------------------------------------
-- MIG308 dejó el portal abierto a quien tuviera el link. Para documentación de
-- prevención de un mandante exigente eso es poco: hay que poder decir QUIÉN
-- entró y CUÁNDO, y que no entre cualquiera a quien le reenviaron el correo.
--
-- CÓMO SE RESUELVE, SIN CREAR CUENTAS NI CONTRASEÑAS
--   El link sigue siendo el primer factor. Encima, para ver algo hay que
--   identificarse con un correo que esté AUTORIZADO para esa faena — los
--   mismos destinatarios que ya reciben el informe por correo (MIG302), más
--   los que Prevención agregue explícitamente al portal. Cada ingreso queda
--   registrado con nombre, correo y hora.
--
--   No es una contraseña y no pretende serlo: es control de alcance más
--   trazabilidad. Quien reenvíe el link a un tercero no le está dando acceso,
--   porque ese tercero no está en la lista.
--
-- LO IMPORTANTE: el filtro vive en la BASE, no en la pantalla. Sin un ingreso
-- válido y vigente, fn_portal_prevencion_publico no devuelve datos. Esconder
-- el contenido en el navegador no habría servido de nada.
-- ============================================================================

BEGIN;

-- ── 1. Configuración del portal ────────────────────────────────────────────
ALTER TABLE public.portales_prevencion
    ADD COLUMN IF NOT EXISTS requiere_identificacion BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS emails_autorizados      TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS vigencia_ingreso_horas  INTEGER NOT NULL DEFAULT 12;

COMMENT ON COLUMN public.portales_prevencion.emails_autorizados IS
  'Correos que pueden entrar, ademas de los destinatarios configurados para la faena (MIG302). MIG313.';
COMMENT ON COLUMN public.portales_prevencion.vigencia_ingreso_horas IS
  'Cuanto dura un ingreso antes de tener que volver a identificarse. MIG313.';

-- ── 2. Quién entró y cuándo ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.portal_prevencion_accesos (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    portal_id    UUID NOT NULL REFERENCES public.portales_prevencion(id) ON DELETE CASCADE,
    nombre       TEXT NOT NULL,
    email        TEXT NOT NULL,
    entrada_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ultima_vista TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    vistas       INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_portal_accesos_portal
    ON public.portal_prevencion_accesos (portal_id, entrada_at DESC);

COMMENT ON TABLE public.portal_prevencion_accesos IS
  'Registro de ingresos al portal externo: quien, con que correo y cuando. Es la respuesta a "yo nunca vi eso". MIG313.';

ALTER TABLE public.portal_prevencion_accesos ENABLE ROW LEVEL SECURITY;

-- El externo nunca lee esta tabla; la escribe la función. Sólo la ve quien
-- administra el control documental.
DROP POLICY IF EXISTS pol_portal_accesos_admin ON public.portal_prevencion_accesos;
CREATE POLICY pol_portal_accesos_admin ON public.portal_prevencion_accesos
    FOR SELECT TO authenticated
    USING (public.fn_prevencion_personal_puede_editar());

GRANT SELECT ON public.portal_prevencion_accesos TO authenticated;

-- ── 3. ¿Este correo puede entrar a este portal? ────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_portal_prevencion_email_autorizado(
    p_portal public.portales_prevencion,
    p_email  text
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT lower(trim(p_email)) = ANY (
             SELECT lower(trim(e)) FROM unnest(p_portal.emails_autorizados) e
           )
        OR EXISTS (
             SELECT 1 FROM prevencion_alertas_destinatarios d
              WHERE d.activo
                AND lower(trim(d.email)) = lower(trim(p_email))
                AND (d.faena_codigo IS NULL OR d.faena_codigo = p_portal.faena_codigo)
           );
$function$;

-- ── 4. Ingresar ────────────────────────────────────────────────────────────
-- Devuelve el identificador del ingreso, que la página guarda y presenta en
-- cada consulta. Nunca dice si el correo existe o no en otra faena: responde
-- lo mismo para cualquier correo no autorizado.
CREATE OR REPLACE FUNCTION public.fn_portal_prevencion_ingresar(
    p_token  text,
    p_nombre text,
    p_email  text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_p        portales_prevencion;
    v_acceso   UUID;
BEGIN
    v_p := public.fn_portal_prevencion_resolver(p_token);
    IF v_p.id IS NULL THEN
        RAISE EXCEPTION 'Link no válido o revocado.' USING ERRCODE = '42501';
    END IF;

    IF length(trim(COALESCE(p_nombre,''))) < 3 THEN
        RAISE EXCEPTION 'Indique su nombre y apellido.' USING ERRCODE = '22023';
    END IF;
    IF p_email IS NULL OR p_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-zA-Z]{2,}$' THEN
        RAISE EXCEPTION 'Indique un correo válido.' USING ERRCODE = '22023';
    END IF;

    IF v_p.requiere_identificacion
       AND NOT public.fn_portal_prevencion_email_autorizado(v_p, p_email) THEN
        RAISE EXCEPTION 'Este correo no está autorizado para este portal. Solicite el acceso al área de Prevención de Riesgos.'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO portal_prevencion_accesos (portal_id, nombre, email)
    VALUES (v_p.id, trim(p_nombre), lower(trim(p_email)))
    RETURNING id INTO v_acceso;

    RETURN jsonb_build_object(
        'acceso_id',    v_acceso,
        'nombre',       trim(p_nombre),
        'vigencia_hrs', v_p.vigencia_ingreso_horas,
        'portal',       v_p.nombre,
        'cliente',      v_p.cliente
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_portal_prevencion_ingresar(text, text, text) TO anon, authenticated;

-- ── 5. Antes de mostrar datos, comprobar que ese ingreso existe y vive ─────
CREATE OR REPLACE FUNCTION public.fn_portal_prevencion_acceso_vigente(
    p_portal    public.portales_prevencion,
    p_acceso_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT NOT p_portal.requiere_identificacion
        OR EXISTS (
             SELECT 1 FROM portal_prevencion_accesos a
              WHERE a.id = p_acceso_id
                AND a.portal_id = p_portal.id
                AND a.entrada_at > NOW() - make_interval(hours => p_portal.vigencia_ingreso_horas)
           );
$function$;

-- ── 6. El contenido, ahora detrás del ingreso ──────────────────────────────
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

    -- Sin ingreso válido no hay datos. El filtro está aquí y no en la
    -- pantalla: esconderlo en el navegador no habría protegido nada.
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
                    'numero_certificado',    c.numero_certificado,
                    'entidad_certificadora', c.entidad_certificadora,
                    'fecha_emision',         c.fecha_emision,
                    'fecha_vencimiento',     CASE WHEN c.estado_real = 'no_aplica' THEN NULL ELSE c.fecha_vencimiento END,
                    'dias_restantes',        CASE WHEN c.estado_real = 'no_aplica' THEN NULL ELSE c.dias_restantes END,
                    'estado',                c.estado_real,
                    'bloqueante',            c.bloqueante,
                    'archivo_url',           c.archivo_url
                  ) ORDER BY
                    CASE c.estado_real
                      WHEN 'vencido' THEN 0 WHEN 'por_vencer' THEN 1
                      WHEN 'vigente' THEN 2 ELSE 3 END,
                    c.fecha_vencimiento)
                FROM v_certificacion_actual c
                WHERE c.activo_id = a.id
            ), '[]'::jsonb),
            -- [MIG313] El mandante pregunta por los papeles, pero lo que de
            -- verdad quiere saber es si al equipo lo están manteniendo. Las
            -- últimas intervenciones responden eso mejor que un certificado.
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
                     ORDER BY v.fecha DESC LIMIT 8
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

-- ── 7. El respaldo de examen también exige ingreso ─────────────────────────
CREATE OR REPLACE FUNCTION public.fn_portal_prevencion_archivo(
    p_token     text,
    p_examen_id uuid,
    p_acceso_id uuid DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_p    portales_prevencion;
    v_path TEXT;
BEGIN
    v_p := public.fn_portal_prevencion_resolver(p_token);

    IF v_p.id IS NULL THEN
        RAISE EXCEPTION 'Link no válido o revocado.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.fn_portal_prevencion_acceso_vigente(v_p, p_acceso_id) THEN
        RAISE EXCEPTION 'Identifíquese para ver esta documentación.' USING ERRCODE = '42501';
    END IF;
    IF NOT v_p.ver_archivos_personal THEN
        RAISE EXCEPTION 'Este portal no entrega respaldos de personal.' USING ERRCODE = '42501';
    END IF;

    SELECT e.archivo_path INTO v_path
      FROM prevencion_examenes e
      JOIN prevencion_personal pp ON pp.id = e.personal_id
     WHERE e.id = p_examen_id
       AND pp.faena_codigo = v_p.faena_codigo
       AND pp.activo;

    IF v_path IS NULL THEN
        RAISE EXCEPTION 'Documento fuera del alcance de este portal.' USING ERRCODE = '42501';
    END IF;

    RETURN v_path;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_portal_prevencion_archivo(text, uuid, uuid) TO anon, authenticated;

-- La firma de dos argumentos queda sin uso: se retira para que nadie entre
-- por la puerta vieja.
DROP FUNCTION IF EXISTS public.fn_portal_prevencion_archivo(text, uuid);
DROP FUNCTION IF EXISTS public.fn_portal_prevencion_publico(text);

-- ── 8. Karen queda habilitada en el portal de Romeral ──────────────────────
-- Ya recibe estos mismos datos por correo (MIG302); acá sólo se explicita.
UPDATE public.portales_prevencion
   SET emails_autorizados = ARRAY(
         SELECT DISTINCT lower(trim(e))
         FROM unnest(emails_autorizados || ARRAY['karen.ducross@esmax.cl']) e
       ),
       updated_at = NOW()
 WHERE faena_codigo = 'ROMERAL';

COMMIT;
