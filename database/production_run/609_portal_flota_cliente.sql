-- ============================================================================
-- 609_portal_flota_cliente.sql
-- ----------------------------------------------------------------------------
-- Portal de flota para el cliente (primero: ESMAX). Entra con correo y
-- contraseña, ve por patente toda la documentación del camión (ver y
-- descargar) y el registro de mantenciones. Sin costos, sin HH, sin recobros.
--
-- POR QUÉ NO USA SUPABASE AUTH
--   Una sesión de Supabase deja al usuario como `authenticated`, y en esta
--   base `authenticated` lee casi todo: 128 tablas con política `true`
--   (activos, ordenes_trabajo, contratos con su valor, movimientos de
--   inventario con costos), 217 vistas que corren como su dueño y 611
--   funciones SECURITY DEFINER. Darle eso a un cliente es abrirle el sistema.
--
--   Aquí el cliente nunca recibe un JWT: queda como `anon`, igual que quien
--   escanea el QR del camión. El usuario y la contraseña viven en
--   `portal_flota_cuentas`; el ingreso entrega un token de sesión (se guarda
--   sólo su hash) y CADA función del portal lo valida y resuelve el alcance
--   desde la fila de la cuenta — la petición no puede pedir otro contrato.
--
-- ALCANCE: los equipos cuyo `contrato_id` está en `contratos_ids` de la
--   cuenta, vivos (sin fecha_baja) y que no son de prueba. Si un camión
--   cambia de contrato, deja de verse solo.
--
-- FUENTES: documentos = rpc_documentos_activo_publico (el mismo del QR,
--   ver gotcha_qr_calcula_estados_aparte); historial =
--   rpc_historial_mantenimiento_publico. No se repite la lógica de estados.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Cuentas ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS portal_flota_cuentas (
    id                     UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    email                  TEXT         NOT NULL,
    nombre                 TEXT         NOT NULL,
    empresa                TEXT,
    password_hash          TEXT         NOT NULL,
    contratos_ids          UUID[]       NOT NULL DEFAULT '{}',
    activo                 BOOLEAN      NOT NULL DEFAULT true,
    debe_cambiar_password  BOOLEAN      NOT NULL DEFAULT true,
    intentos_fallidos      INT          NOT NULL DEFAULT 0,
    bloqueado_hasta        TIMESTAMPTZ,
    ultimo_acceso_at       TIMESTAMPTZ,
    password_cambiada_at   TIMESTAMPTZ,
    notas                  TEXT,
    created_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    created_by             UUID,
    updated_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_portal_flota_cuentas_email
    ON portal_flota_cuentas (lower(email));

-- ── 2. Sesiones (sólo el hash del token) ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS portal_flota_sesiones (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    cuenta_id    UUID         NOT NULL REFERENCES portal_flota_cuentas(id) ON DELETE CASCADE,
    token_hash   TEXT         NOT NULL UNIQUE,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    expira_at    TIMESTAMPTZ  NOT NULL,
    cerrada_at   TIMESTAMPTZ,
    ultima_vista TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_portal_flota_sesiones_cuenta
    ON portal_flota_sesiones (cuenta_id);

-- ── 3. Registro: quién miró y descargó qué ───────────────────────────────────
-- Un cliente que audita necesita poder decir "lo descargué el 20 y estaba
-- vigente"; nosotros, poder decir quién lo vio.
CREATE TABLE IF NOT EXISTS portal_flota_eventos (
    id         BIGSERIAL    PRIMARY KEY,
    cuenta_id  UUID         REFERENCES portal_flota_cuentas(id) ON DELETE CASCADE,
    email      TEXT,
    evento     TEXT         NOT NULL,   -- login | login_fallido | ver_equipo | descargar | cambiar_password | logout
    activo_id  UUID,
    detalle    TEXT,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_portal_flota_eventos_cuenta
    ON portal_flota_eventos (cuenta_id, created_at DESC);

-- Nadie las lee directo: sólo a través de las funciones de abajo.
ALTER TABLE portal_flota_cuentas  ENABLE ROW LEVEL SECURITY;
ALTER TABLE portal_flota_sesiones ENABLE ROW LEVEL SECURITY;
ALTER TABLE portal_flota_eventos  ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON portal_flota_cuentas, portal_flota_sesiones, portal_flota_eventos FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE portal_flota_eventos_id_seq FROM PUBLIC, anon, authenticated;


-- ============================================================================
-- 4. Internas (no se exponen)
-- ============================================================================

-- Resuelve el token a la cuenta. Sin sesión vigente o con la cuenta apagada,
-- no hay datos: el filtro está en la base.
CREATE OR REPLACE FUNCTION fn_portal_flota_cuenta(p_token TEXT)
RETURNS portal_flota_cuentas
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_c   portal_flota_cuentas;
    v_s   UUID;
    v_cid UUID;
BEGIN
    SELECT s.id, s.cuenta_id INTO v_s, v_cid
      FROM portal_flota_sesiones s
     WHERE s.token_hash = encode(extensions.digest(COALESCE(p_token, ''), 'sha256'), 'hex')
       AND s.cerrada_at IS NULL
       AND s.expira_at > NOW();

    SELECT * INTO v_c FROM portal_flota_cuentas WHERE id = v_cid AND activo;

    IF v_c.id IS NULL THEN
        RAISE EXCEPTION 'Su sesión expiró. Vuelva a ingresar.' USING ERRCODE = '42501';
    END IF;

    UPDATE portal_flota_sesiones SET ultima_vista = NOW() WHERE id = v_s;
    RETURN v_c;
END;
$$;

-- Los equipos que la cuenta puede ver. Un solo lugar para el alcance.
CREATE OR REPLACE FUNCTION fn_portal_flota_activos(p_cuenta portal_flota_cuentas)
RETURNS SETOF UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT a.id
      FROM activos a
     WHERE a.contrato_id = ANY(p_cuenta.contratos_ids)
       AND a.fecha_baja IS NULL
       AND NOT COALESCE(a.es_prueba, false);
$$;

CREATE OR REPLACE FUNCTION fn_portal_flota_validar_password(p TEXT)
RETURNS VOID
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p IS NULL OR length(p) < 8 OR p !~ '[0-9]' OR p !~ '[A-Za-z]' THEN
        RAISE EXCEPTION 'La contraseña debe tener al menos 8 caracteres, con letras y números.'
            USING ERRCODE = '22023';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION fn_portal_flota_cuenta(TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_portal_flota_activos(portal_flota_cuentas) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_portal_flota_validar_password(TEXT) FROM PUBLIC, anon, authenticated;


-- ============================================================================
-- 5. Lo que llama el portal (anon)
-- ============================================================================

-- ── Ingreso ──────────────────────────────────────────────────────────────────
-- 5 intentos fallidos bloquean la cuenta 15 minutos. El mensaje de error es
-- el mismo exista o no el correo: no se le confirma a nadie qué cuentas hay.
CREATE OR REPLACE FUNCTION rpc_portal_flota_login(p_email TEXT, p_password TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_c      portal_flota_cuentas;
    v_token  TEXT;
    v_expira TIMESTAMPTZ := NOW() + INTERVAL '12 hours';
BEGIN
    SELECT * INTO v_c FROM portal_flota_cuentas
     WHERE lower(email) = lower(trim(COALESCE(p_email, '')));

    IF v_c.id IS NOT NULL AND v_c.bloqueado_hasta > NOW() THEN
        RAISE EXCEPTION 'Demasiados intentos. Espere 15 minutos o contacte a Pillado.'
            USING ERRCODE = '42501';
    END IF;

    IF v_c.id IS NULL OR NOT v_c.activo
       OR v_c.password_hash <> extensions.crypt(COALESCE(p_password, ''), v_c.password_hash) THEN
        IF v_c.id IS NOT NULL THEN
            UPDATE portal_flota_cuentas
               SET intentos_fallidos = intentos_fallidos + 1,
                   bloqueado_hasta = CASE WHEN intentos_fallidos + 1 >= 5
                                          THEN NOW() + INTERVAL '15 minutes' END
             WHERE id = v_c.id;
        END IF;
        INSERT INTO portal_flota_eventos (cuenta_id, email, evento)
        VALUES (v_c.id, lower(trim(COALESCE(p_email, ''))), 'login_fallido');
        -- El RAISE desharía el registro del intento: se devuelve el error
        -- como dato para que el contador sí quede escrito.
        RETURN jsonb_build_object('error', 'Correo o contraseña incorrectos.');
    END IF;

    v_token := 'pf_' || encode(extensions.gen_random_bytes(32), 'hex');

    INSERT INTO portal_flota_sesiones (cuenta_id, token_hash, expira_at)
    VALUES (v_c.id, encode(extensions.digest(v_token, 'sha256'), 'hex'), v_expira);

    UPDATE portal_flota_cuentas
       SET intentos_fallidos = 0, bloqueado_hasta = NULL, ultimo_acceso_at = NOW()
     WHERE id = v_c.id;

    INSERT INTO portal_flota_eventos (cuenta_id, email, evento)
    VALUES (v_c.id, v_c.email, 'login');

    -- Limpieza oportunista: sesiones viejas no sirven a nadie.
    DELETE FROM portal_flota_sesiones WHERE expira_at < NOW() - INTERVAL '30 days';

    RETURN jsonb_build_object(
        'token',          v_token,
        'expira_at',      v_expira,
        'nombre',         v_c.nombre,
        'empresa',        v_c.empresa,
        'email',          v_c.email,
        'debe_cambiar',   v_c.debe_cambiar_password
    );
END;
$$;

CREATE OR REPLACE FUNCTION rpc_portal_flota_logout(p_token TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    UPDATE portal_flota_sesiones
       SET cerrada_at = NOW()
     WHERE token_hash = encode(extensions.digest(COALESCE(p_token, ''), 'sha256'), 'hex')
       AND cerrada_at IS NULL;
$$;

CREATE OR REPLACE FUNCTION rpc_portal_flota_cambiar_password(
    p_token TEXT, p_actual TEXT, p_nueva TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_c portal_flota_cuentas;
BEGIN
    v_c := fn_portal_flota_cuenta(p_token);

    IF v_c.password_hash <> extensions.crypt(COALESCE(p_actual, ''), v_c.password_hash) THEN
        RAISE EXCEPTION 'La contraseña actual no es correcta.' USING ERRCODE = '42501';
    END IF;
    PERFORM fn_portal_flota_validar_password(p_nueva);
    IF p_nueva = p_actual THEN
        RAISE EXCEPTION 'La contraseña nueva debe ser distinta de la actual.' USING ERRCODE = '22023';
    END IF;

    UPDATE portal_flota_cuentas
       SET password_hash = extensions.crypt(p_nueva, extensions.gen_salt('bf')),
           debe_cambiar_password = false,
           password_cambiada_at = NOW(),
           updated_at = NOW()
     WHERE id = v_c.id;

    INSERT INTO portal_flota_eventos (cuenta_id, email, evento)
    VALUES (v_c.id, v_c.email, 'cambiar_password');
END;
$$;

-- ── Flota: la lista por patente ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_portal_flota_equipos(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_c portal_flota_cuentas;
BEGIN
    v_c := fn_portal_flota_cuenta(p_token);

    RETURN jsonb_build_object(
        'cuenta', jsonb_build_object(
            'nombre', v_c.nombre, 'empresa', v_c.empresa, 'email', v_c.email,
            'debe_cambiar', v_c.debe_cambiar_password),
        'generado_at', NOW(),
        'equipos', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'activo_id',     a.id,
                'patente',       COALESCE(a.patente, a.codigo),
                'codigo',        a.codigo,
                'nombre',        a.nombre,
                'tipo',          COALESCE(a.tipo_equipamiento::text, a.tipo::text),
                'marca_modelo',  NULLIF(trim(concat_ws(' ', mar.nombre, mo.nombre)), ''),
                'anio',          a.anio_fabricacion,
                'docs_total',    d.total,
                'docs_vencidos', d.vencidos,
                'docs_por_vencer', d.por_vencer,
                'docs_sin_fecha',  d.sin_fecha,
                'ultima_mantencion', h.fecha
              ) ORDER BY COALESCE(a.patente, a.codigo))
              FROM activos a
              LEFT JOIN modelos mo  ON mo.id  = a.modelo_id
              LEFT JOIN marcas  mar ON mar.id = mo.marca_id
              CROSS JOIN LATERAL (
                  SELECT count(*)                                   AS total,
                         count(*) FILTER (WHERE x.estado = 'vencido')    AS vencidos,
                         count(*) FILTER (WHERE x.estado = 'por_vencer') AS por_vencer,
                         count(*) FILTER (WHERE x.estado = 'sin_fecha')  AS sin_fecha
                    FROM rpc_documentos_activo_publico(a.id) x
              ) d
              LEFT JOIN LATERAL (
                  SELECT max(y.fecha) AS fecha FROM rpc_historial_mantenimiento_publico(a.id) y
              ) h ON true
             WHERE a.id IN (SELECT fn_portal_flota_activos(v_c))
        ), '[]'::jsonb)
    );
END;
$$;

-- ── Ficha de un equipo: datos + documentos + mantenciones ────────────────────
CREATE OR REPLACE FUNCTION rpc_portal_flota_equipo(p_token TEXT, p_activo_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_c   portal_flota_cuentas;
    v_out JSONB;
BEGIN
    v_c := fn_portal_flota_cuenta(p_token);

    IF NOT EXISTS (SELECT 1 FROM fn_portal_flota_activos(v_c) id WHERE id = p_activo_id) THEN
        RAISE EXCEPTION 'Equipo no disponible para su cuenta.' USING ERRCODE = '42501';
    END IF;

    SELECT jsonb_build_object(
        'equipo', jsonb_build_object(
            'activo_id',    a.id,
            'patente',      COALESCE(a.patente, a.codigo),
            'codigo',       a.codigo,
            'nombre',       a.nombre,
            'tipo',         COALESCE(a.tipo_equipamiento::text, a.tipo::text),
            'marca_modelo', NULLIF(trim(concat_ws(' ', mar.nombre, mo.nombre)), ''),
            'anio',         a.anio_fabricacion,
            'vin',          a.vin_chasis,
            'motor',        a.numero_motor,
            'capacidad',    a.capacidad,
            'kilometraje',  a.kilometraje_actual,
            'horometro',    a.horas_uso_actual
        ),
        'documentos', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'tipo',              x.tipo,
                'etiqueta',          x.etiqueta,
                'numero',            x.numero_certificado,
                'entidad',           x.entidad,
                'fecha_emision',     x.fecha_emision,
                'fecha_vencimiento', x.fecha_vencimiento,
                'dias_restantes',    x.dias_restantes,
                'estado',            x.estado,
                'archivo_url',       x.archivo_url
              ) ORDER BY
                CASE x.estado WHEN 'vencido' THEN 0 WHEN 'sin_fecha' THEN 1
                              WHEN 'por_vencer' THEN 2 WHEN 'vigente' THEN 3 ELSE 4 END,
                x.etiqueta)
              FROM rpc_documentos_activo_publico(a.id) x
        ), '[]'::jsonb),
        'mantenciones', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'fecha', y.fecha, 'tipo', y.tipo, 'titulo', y.titulo, 'detalle', y.detalle,
                'folio', y.folio, 'km', y.kilometraje, 'horas', y.horometro,
                'con_observacion', y.con_observacion
              ) ORDER BY y.fecha DESC NULLS LAST)
              FROM rpc_historial_mantenimiento_publico(a.id) y
        ), '[]'::jsonb)
    ) INTO v_out
      FROM activos a
      LEFT JOIN modelos mo  ON mo.id  = a.modelo_id
      LEFT JOIN marcas  mar ON mar.id = mo.marca_id
     WHERE a.id = p_activo_id;

    INSERT INTO portal_flota_eventos (cuenta_id, email, evento, activo_id)
    VALUES (v_c.id, v_c.email, 'ver_equipo', p_activo_id);

    RETURN v_out;
END;
$$;

-- ── Registro de descarga (lo llama la pantalla al bajar un papel o el ZIP) ───
CREATE OR REPLACE FUNCTION rpc_portal_flota_registrar_descarga(
    p_token TEXT, p_activo_id UUID, p_detalle TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_c portal_flota_cuentas;
BEGIN
    v_c := fn_portal_flota_cuenta(p_token);
    IF NOT EXISTS (SELECT 1 FROM fn_portal_flota_activos(v_c) id WHERE id = p_activo_id) THEN
        RETURN;
    END IF;
    INSERT INTO portal_flota_eventos (cuenta_id, email, evento, activo_id, detalle)
    VALUES (v_c.id, v_c.email, 'descargar', p_activo_id, left(p_detalle, 300));
END;
$$;

REVOKE ALL ON FUNCTION rpc_portal_flota_login(TEXT, TEXT)                       FROM PUBLIC;
REVOKE ALL ON FUNCTION rpc_portal_flota_logout(TEXT)                            FROM PUBLIC;
REVOKE ALL ON FUNCTION rpc_portal_flota_cambiar_password(TEXT, TEXT, TEXT)      FROM PUBLIC;
REVOKE ALL ON FUNCTION rpc_portal_flota_equipos(TEXT)                           FROM PUBLIC;
REVOKE ALL ON FUNCTION rpc_portal_flota_equipo(TEXT, UUID)                      FROM PUBLIC;
REVOKE ALL ON FUNCTION rpc_portal_flota_registrar_descarga(TEXT, UUID, TEXT)    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_portal_flota_login(TEXT, TEXT)                    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_portal_flota_logout(TEXT)                         TO anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_portal_flota_cambiar_password(TEXT, TEXT, TEXT)   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_portal_flota_equipos(TEXT)                        TO anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_portal_flota_equipo(TEXT, UUID)                   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_portal_flota_registrar_descarga(TEXT, UUID, TEXT) TO anon, authenticated;


-- ============================================================================
-- 6. Administración (sólo administrador, desde /dashboard/admin/portal-usuarios)
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_portal_flota_exigir_admin()
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF COALESCE(fn_user_rol(), '') <> 'administrador' THEN
        RAISE EXCEPTION 'Sólo un administrador gestiona las cuentas del portal.' USING ERRCODE = '42501';
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION fn_portal_flota_exigir_admin() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION rpc_admin_portal_flota_listar()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM fn_portal_flota_exigir_admin();
    RETURN COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'id', c.id, 'email', c.email, 'nombre', c.nombre, 'empresa', c.empresa,
            'activo', c.activo, 'debe_cambiar', c.debe_cambiar_password,
            'bloqueado', (c.bloqueado_hasta > NOW()),
            'ultimo_acceso_at', c.ultimo_acceso_at, 'created_at', c.created_at,
            'notas', c.notas,
            'contratos', COALESCE((
                SELECT jsonb_agg(jsonb_build_object('id', k.id, 'codigo', k.codigo, 'cliente', k.cliente))
                  FROM contratos k WHERE k.id = ANY(c.contratos_ids)), '[]'::jsonb),
            'n_equipos', (SELECT count(*) FROM fn_portal_flota_activos(c)),
            'n_ingresos', (SELECT count(*) FROM portal_flota_eventos e
                            WHERE e.cuenta_id = c.id AND e.evento = 'login'),
            'n_descargas', (SELECT count(*) FROM portal_flota_eventos e
                             WHERE e.cuenta_id = c.id AND e.evento = 'descargar')
          ) ORDER BY c.empresa NULLS LAST, c.nombre)
          FROM portal_flota_cuentas c
    ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION rpc_admin_portal_flota_crear(
    p_email TEXT, p_nombre TEXT, p_empresa TEXT, p_contratos UUID[],
    p_password TEXT, p_notas TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id UUID;
BEGIN
    PERFORM fn_portal_flota_exigir_admin();
    IF p_email IS NULL OR p_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-zA-Z]{2,}$' THEN
        RAISE EXCEPTION 'Correo no válido.' USING ERRCODE = '22023';
    END IF;
    IF length(trim(COALESCE(p_nombre, ''))) < 3 THEN
        RAISE EXCEPTION 'Indique el nombre de la persona.' USING ERRCODE = '22023';
    END IF;
    IF COALESCE(array_length(p_contratos, 1), 0) = 0 THEN
        RAISE EXCEPTION 'Elija al menos un contrato: sin contrato la cuenta no ve ningún equipo.' USING ERRCODE = '22023';
    END IF;
    PERFORM fn_portal_flota_validar_password(p_password);
    IF EXISTS (SELECT 1 FROM portal_flota_cuentas WHERE lower(email) = lower(trim(p_email))) THEN
        RAISE EXCEPTION 'Ya existe una cuenta con ese correo.' USING ERRCODE = '23505';
    END IF;

    INSERT INTO portal_flota_cuentas (email, nombre, empresa, contratos_ids, password_hash, notas, created_by)
    VALUES (lower(trim(p_email)), trim(p_nombre), NULLIF(trim(p_empresa), ''), p_contratos,
            extensions.crypt(p_password, extensions.gen_salt('bf')), NULLIF(trim(p_notas), ''), auth.uid())
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

-- Contraseña temporal nueva: obliga a cambiarla y cierra las sesiones abiertas.
CREATE OR REPLACE FUNCTION rpc_admin_portal_flota_reset_password(p_cuenta_id UUID, p_password TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM fn_portal_flota_exigir_admin();
    PERFORM fn_portal_flota_validar_password(p_password);
    UPDATE portal_flota_cuentas
       SET password_hash = extensions.crypt(p_password, extensions.gen_salt('bf')),
           debe_cambiar_password = true, intentos_fallidos = 0, bloqueado_hasta = NULL,
           updated_at = NOW()
     WHERE id = p_cuenta_id;
    UPDATE portal_flota_sesiones SET cerrada_at = NOW()
     WHERE cuenta_id = p_cuenta_id AND cerrada_at IS NULL;
END;
$$;

CREATE OR REPLACE FUNCTION rpc_admin_portal_flota_editar(
    p_cuenta_id UUID, p_activo BOOLEAN, p_contratos UUID[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM fn_portal_flota_exigir_admin();
    UPDATE portal_flota_cuentas
       SET activo = COALESCE(p_activo, activo),
           contratos_ids = COALESCE(p_contratos, contratos_ids),
           updated_at = NOW()
     WHERE id = p_cuenta_id;
    -- Apagar una cuenta corta también lo que tenga abierto en ese momento.
    IF p_activo = false THEN
        UPDATE portal_flota_sesiones SET cerrada_at = NOW()
         WHERE cuenta_id = p_cuenta_id AND cerrada_at IS NULL;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION rpc_admin_portal_flota_listar()                                    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_admin_portal_flota_crear(TEXT, TEXT, TEXT, UUID[], TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_admin_portal_flota_reset_password(UUID, TEXT)                  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_admin_portal_flota_editar(UUID, BOOLEAN, UUID[])               FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_admin_portal_flota_listar()                                    TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_admin_portal_flota_crear(TEXT, TEXT, TEXT, UUID[], TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_admin_portal_flota_reset_password(UUID, TEXT)                  TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_admin_portal_flota_editar(UUID, BOOLEAN, UUID[])               TO authenticated;


-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'tablas',     (SELECT count(*) FROM pg_class WHERE relname LIKE 'portal_flota_%' AND relkind = 'r' AND relrowsecurity),
    'anon_no_lee_cuentas', NOT has_table_privilege('anon', 'portal_flota_cuentas', 'SELECT'),
    'anon_no_resuelve',    NOT has_function_privilege('anon', 'fn_portal_flota_cuenta(text)', 'EXECUTE'),
    'anon_login',          has_function_privilege('anon', 'rpc_portal_flota_login(text,text)', 'EXECUTE'),
    'anon_no_admin',       NOT has_function_privilege('anon', 'rpc_admin_portal_flota_listar()', 'EXECUTE')
) AS verificacion;
