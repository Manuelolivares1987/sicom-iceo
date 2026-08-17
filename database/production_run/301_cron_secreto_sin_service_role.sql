-- ============================================================================
-- SICOM-ICEO | 301 — El cron del aviso no necesita el service_role
-- ============================================================================
-- La API de alerta de exámenes (MIG299) leía con SUPABASE_SERVICE_ROLE_KEY para
-- saltarse RLS sin usuario logueado. Esa clave abre TODA la base sin
-- restricción alguna: si se filtra desde las variables de Netlify, se filtra el
-- sistema completo —incluidos los datos de salud del personal—.
--
-- Es desproporcionado para lo que el cron hace: leer ~20 filas y marcarlas como
-- avisadas.
--
-- Acá el mismo secreto que ya autentica al cron (CRON_SECRET) habilita
-- EXACTAMENTE dos funciones y nada más. Se guarda su hash SHA-256, nunca el
-- secreto en claro: quien lea la tabla no puede reconstruirlo.
--
-- Es el mismo patrón que el proyecto ya usa para el link de firma remota de
-- ENEX (MIG276) y el informe de fiabilidad por token (MIG200).
--
-- ADITIVA. No modifica ni borra datos existentes.
-- ============================================================================


-- ############################################################################
-- 1. SECRETOS DEL SISTEMA
-- ############################################################################

CREATE TABLE IF NOT EXISTS sistema_secretos (
    codigo      VARCHAR(60)  PRIMARY KEY,
    hash        TEXT         NOT NULL,      -- SHA-256 en hex, nunca el secreto
    descripcion TEXT,
    rotado_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE sistema_secretos IS
    'Hashes de secretos compartidos con procesos automáticos. Nunca el valor en claro. MIG301.';

-- Nadie la lee desde la aplicación: solo las funciones SECURITY DEFINER de
-- abajo, que corren con los privilegios del dueño.
ALTER TABLE sistema_secretos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sistema_secretos FROM authenticated, anon;


-- Guarda/rota un secreto. Solo desde la conexión de administración (el script
-- de migraciones), nunca desde la aplicación.
CREATE OR REPLACE FUNCTION fn_sistema_set_secreto(p_codigo TEXT, p_secreto TEXT, p_desc TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER SET search_path = public, extensions AS $$
    INSERT INTO sistema_secretos (codigo, hash, descripcion)
    VALUES (p_codigo, encode(extensions.digest(p_secreto, 'sha256'), 'hex'), p_desc)
    ON CONFLICT (codigo) DO UPDATE SET
        hash = EXCLUDED.hash,
        descripcion = COALESCE(EXCLUDED.descripcion, sistema_secretos.descripcion),
        rotado_at = NOW();
$$;
REVOKE ALL ON FUNCTION fn_sistema_set_secreto(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION fn_sistema_set_secreto(TEXT, TEXT, TEXT) IS
    'Guarda o rota el hash de un secreto. Solo administración. MIG301.';


CREATE OR REPLACE FUNCTION fn_sistema_secreto_valido(p_codigo TEXT, p_secreto TEXT)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
    SELECT EXISTS (
        SELECT 1 FROM sistema_secretos s
         WHERE s.codigo = p_codigo
           AND p_secreto IS NOT NULL
           AND length(p_secreto) >= 16      -- un secreto corto no se acepta
           AND s.hash = encode(extensions.digest(p_secreto, 'sha256'), 'hex'));
$$;

COMMENT ON FUNCTION fn_sistema_secreto_valido(TEXT, TEXT) IS
    'Valida un secreto contra su hash. MIG301.';


-- ############################################################################
-- 2. LAS DOS FUNCIONES QUE EL CRON NECESITA
-- ############################################################################
-- Se otorgan a `anon` PORQUE están protegidas por el secreto. La clave anónima
-- por sí sola no abre nada: sin el secreto correcto, ambas fallan.

DROP FUNCTION IF EXISTS fn_prevencion_alertas_pendientes_cron(TEXT);
CREATE FUNCTION fn_prevencion_alertas_pendientes_cron(p_secreto TEXT)
RETURNS TABLE (
    examen_id       UUID,
    personal_id     UUID,
    rut             TEXT,
    persona         TEXT,
    empresa         TEXT,
    faena_codigo    TEXT,
    tipo_nombre     TEXT,
    laboratorio     TEXT,
    fecha_vencimiento DATE,
    dias_restantes  INTEGER,
    nivel           TEXT,
    cada_dias       INTEGER,
    ultima_alerta   TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido.' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY SELECT * FROM fn_prevencion_alertas_pendientes();
END $$;
GRANT EXECUTE ON FUNCTION fn_prevencion_alertas_pendientes_cron(TEXT) TO anon, authenticated;

COMMENT ON FUNCTION fn_prevencion_alertas_pendientes_cron(TEXT) IS
    'Alertas por enviar, protegida por secreto compartido en vez de service_role. MIG301.';


DROP FUNCTION IF EXISTS fn_prevencion_marcar_alertas_cron(TEXT, UUID[], TEXT);
CREATE FUNCTION fn_prevencion_marcar_alertas_cron(
    p_secreto TEXT, p_ids UUID[], p_destinatarios TEXT DEFAULT NULL)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido.' USING ERRCODE = '42501';
    END IF;
    RETURN fn_prevencion_marcar_alertas(p_ids, p_destinatarios);
END $$;
GRANT EXECUTE ON FUNCTION fn_prevencion_marcar_alertas_cron(TEXT, UUID[], TEXT) TO anon, authenticated;

COMMENT ON FUNCTION fn_prevencion_marcar_alertas_cron(TEXT, UUID[], TEXT) IS
    'Marca los avisos enviados, protegida por secreto compartido. MIG301.';
