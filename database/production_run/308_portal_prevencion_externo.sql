-- ============================================================================
-- MIG308 · Portal de prevención para el mandante (externo, sin cuenta)
-- ----------------------------------------------------------------------------
-- PARA QUÉ
--   Romeral (CMP / ESMAX) pide la documentación de prevención de lo que tiene
--   en faena: los exámenes y licencias de la gente, y los papeles de los
--   camiones. Hoy eso se responde por correo, a mano, cuando lo piden. El
--   portal lo deja disponible en un link: la misma verdad de la base, al día,
--   sin darle una cuenta al externo ni mostrarle nada de otras faenas.
--
-- CÓMO SE PROTEGE
--   · El link lleva un token secreto y revocable. Sin token no hay dato.
--   · El token trae escrito SU alcance: una faena y una lista de equipos.
--     La función no acepta que el navegador pida otra cosa — no recibe
--     parámetros de filtro. El alcance no es negociable desde afuera.
--   · Los respaldos de exámenes viven en un bucket privado. El portal sólo
--     entrega la ruta si el portal tiene encendido ver_archivos_personal,
--     y el link firmado lo emite el servidor, nunca el navegador.
--   · Cada consulta deja rastro (usos, last_used_at).
--
-- ALCANCE DEL PORTAL ROMERAL (se siembra al final)
--   Faena ROMERAL (15 personas) + DJKL-18, FSLZ-67 y la camioneta RZPC-83,
--   que es el otro equipo Pillado en esa faena.
--   Nota: el usuario pidió "DFKL18"; la patente real en el maestro es DJKL-18.
-- ============================================================================

BEGIN;

-- ── 1. El portal y su alcance ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.portales_prevencion (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token                  TEXT NOT NULL UNIQUE,
    nombre                 TEXT NOT NULL,              -- lo que se lee arriba del portal
    cliente                TEXT,                       -- a quién se le entregó
    faena_codigo           TEXT,                       -- alcance del personal
    activo_ids             UUID[] NOT NULL DEFAULT '{}',  -- alcance de los equipos
    ver_archivos_personal  BOOLEAN NOT NULL DEFAULT false,
    activo                 BOOLEAN NOT NULL DEFAULT true,
    expira_at              TIMESTAMPTZ,
    usos                   INTEGER NOT NULL DEFAULT 0,
    last_used_at           TIMESTAMPTZ,
    observacion            TEXT,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by             UUID,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.portales_prevencion IS
  'Links de solo lectura para que un mandante externo revise la documentación de prevención de SU faena y SUS equipos. El alcance vive en la fila, no en la petición.';

ALTER TABLE public.portales_prevencion ENABLE ROW LEVEL SECURITY;

-- El token es una credencial: quien lo lee puede repartirlo. Por eso la fila
-- sólo la ve quien ADMINISTRA el control documental (MIG298), no todo el que
-- puede mirarlo. El externo nunca consulta esta tabla: su token va en la URL.
DROP POLICY IF EXISTS pol_portales_prevencion_admin ON public.portales_prevencion;
CREATE POLICY pol_portales_prevencion_admin ON public.portales_prevencion
    FOR ALL TO authenticated
    USING (public.fn_prevencion_personal_puede_editar())
    WITH CHECK (public.fn_prevencion_personal_puede_editar());

GRANT SELECT, INSERT, UPDATE ON public.portales_prevencion TO authenticated;

-- ── 1b. Máscara de RUT ─────────────────────────────────────────────────────
-- El mandante controla acceso por persona: le basta reconocer el RUT para
-- cruzarlo con su registro de ingreso, no necesita el número completo.
CREATE OR REPLACE FUNCTION public.fn_portal_prevencion_rut_mascara(p_rut text)
RETURNS text LANGUAGE sql IMMUTABLE AS $f$
    -- 18483927-K  ->  18••••••-K. Sin regex a proposito: los backreferences
    -- se pierden al pasar el archivo por scripts y el bug es silencioso:
    -- queda una mascara sin ningun digito, que ya no identifica a nadie.
    SELECT CASE
             WHEN p_rut IS NULL OR length(p_rut) < 5 THEN NULL
             ELSE left(p_rut, 2) || repeat(chr(8226), 6) || right(p_rut, 2)
           END;
$f$;

-- ── 2. Resolver el token (interno, no se expone) ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_portal_prevencion_resolver(p_token text)
RETURNS public.portales_prevencion
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT p.* FROM portales_prevencion p
     WHERE p.token = p_token
       AND p.activo
       AND (p.expira_at IS NULL OR p.expira_at > NOW())
     LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.fn_portal_prevencion_resolver(text) FROM PUBLIC, anon, authenticated;

-- ── 3. El contenido del portal ─────────────────────────────────────────────
-- Devuelve TODO lo que la página necesita en un viaje. No acepta filtros:
-- el alcance sale de la fila del token.
CREATE OR REPLACE FUNCTION public.fn_portal_prevencion_publico(p_token text)
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

    SELECT jsonb_build_object(
      'portal', jsonb_build_object(
          'nombre',                v_p.nombre,
          'cliente',               v_p.cliente,
          'faena_codigo',          v_p.faena_codigo,
          'ver_archivos_personal', v_p.ver_archivos_personal,
          'generado_at',           NOW()
      ),

      -- ── Equipos: el último documento por tipo, con vigencia real ────────
      'equipos', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'activo_id', a.id,
            'patente',   COALESCE(a.patente, a.codigo),
            'codigo',    a.codigo,
            'nombre',    a.nombre,
            'tipo',      a.tipo,
            'ubicacion', a.ubicacion_actual,
            'estado_codigo', ep.estado_codigo,
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
            ), '[]'::jsonb)
          ) ORDER BY COALESCE(a.patente, a.codigo))
        FROM activos a
        LEFT JOIN v_activos_estado_planificador ep ON ep.activo_id = a.id
        WHERE a.id = ANY(v_p.activo_ids)
      ), '[]'::jsonb),

      -- ── Personal: estado de exámenes y licencias de esa faena ───────────
      -- Se entrega vigencia y estado, nunca el resultado clínico. El RUT va
      -- enmascarado: el mandante controla acceso por persona, no necesita el
      -- dígito completo para eso.
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

    -- Rastro de uso. Nunca puede tumbar la consulta.
    BEGIN
        UPDATE portales_prevencion
           SET usos = usos + 1, last_used_at = NOW()
         WHERE id = v_p.id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN v_out;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_portal_prevencion_publico(text) TO anon, authenticated;

-- ── 4. Respaldo de un examen (bucket privado) ──────────────────────────────
-- Devuelve sólo la RUTA. El link firmado lo emite el servidor de la app; el
-- navegador del externo nunca ve credenciales de storage.
CREATE OR REPLACE FUNCTION public.fn_portal_prevencion_archivo(
    p_token     text,
    p_examen_id uuid
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

    IF NOT v_p.ver_archivos_personal THEN
        RAISE EXCEPTION 'Este portal no entrega respaldos de personal.' USING ERRCODE = '42501';
    END IF;

    -- El examen tiene que ser de la faena del portal. Que el id venga del
    -- navegador no lo autoriza.
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

GRANT EXECUTE ON FUNCTION public.fn_portal_prevencion_archivo(text, uuid) TO anon, authenticated;

-- ── 5. El portal de Romeral ────────────────────────────────────────────────
INSERT INTO public.portales_prevencion
    (token, nombre, cliente, faena_codigo, activo_ids, ver_archivos_personal, observacion)
SELECT
    replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
    'Documentación de Prevención — Faena Romeral',
    'Compañía Minera del Pacífico (CMP) · ESMAX',
    'ROMERAL',
    ARRAY(SELECT id FROM activos WHERE patente IN ('DJKL-18', 'FSLZ-67', 'RZPC-83')),
    true,   -- Karen Ducross ya recibe estos mismos respaldos por correo (MIG302)
    'Creado en MIG308. Alcance: personal de faena ROMERAL + los 3 equipos Pillado en esa faena.'
WHERE NOT EXISTS (
    SELECT 1 FROM public.portales_prevencion WHERE faena_codigo = 'ROMERAL'
);

COMMIT;
