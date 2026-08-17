-- ============================================================================
-- SICOM-ICEO | 302 — Destinatarios del aviso, acotados por faena
-- ============================================================================
-- El aviso de exámenes (MIG299) usaba una lista plana de correos: todos
-- recibían todo. Eso no sirve cuando hay destinatarios EXTERNOS.
--
-- Caso concreto: Karen es externa y solo le compete CMP Romeral. Con la lista
-- plana, en cuanto se cargue personal de otra faena empezaría a recibir
-- nombres, RUT y estado de salud de trabajadores que no le competen. Eso es
-- una filtración de datos sensibles a un tercero, y no se arregla "recordando"
-- sacarla a tiempo: se arregla en el diseño.
--
-- Acá cada destinatario declara SU ALCANCE:
--     faena_codigo = NULL   → interno, recibe todas las faenas
--     faena_codigo = 'X'    → recibe SOLO la faena X
--
-- Y el correo se arma por faena: quien tiene alcance acotado recibe un correo
-- que contiene únicamente su faena. No hay forma de que vea otra.
--
-- Se marca además `externo` para que quede explícito en la tabla quién no es
-- de la empresa — un dato que hay que poder auditar sin adivinar por el dominio
-- del correo.
--
-- ADITIVA. No modifica ni borra datos existentes.
-- ============================================================================

CREATE TABLE IF NOT EXISTS prevencion_alertas_destinatarios (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    email        VARCHAR(200) NOT NULL,
    nombre       VARCHAR(160),
    cargo        VARCHAR(160),

    -- NULL = todas las faenas (personal interno).
    -- Con valor = SOLO esa faena. Es el control de alcance.
    faena_codigo VARCHAR(60),

    -- Externo a la empresa. No cambia el comportamiento por sí solo, pero deja
    -- explícito a quién se le está entregando información de terceros.
    externo      BOOLEAN      NOT NULL DEFAULT false,

    -- 'para' | 'copia'
    modo         VARCHAR(10)  NOT NULL DEFAULT 'para',

    activo       BOOLEAN      NOT NULL DEFAULT true,
    observacion  TEXT,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_pad_modo  CHECK (modo IN ('para','copia')),
    CONSTRAINT chk_pad_email CHECK (position('@' IN email) > 1),
    CONSTRAINT uq_pad_email_faena UNIQUE (email, faena_codigo),

    -- Un externo SIN faena recibiría todo. Se prohíbe: si alguna vez hace
    -- falta, hay que declararlo a propósito quitando esta restricción, no por
    -- descuido al cargar una fila.
    CONSTRAINT chk_pad_externo_acotado
        CHECK (NOT externo OR faena_codigo IS NOT NULL)
);

COMMENT ON TABLE prevencion_alertas_destinatarios IS
    'Quién recibe el aviso de exámenes y de qué faenas. Los externos van siempre acotados. MIG302.';
COMMENT ON COLUMN prevencion_alertas_destinatarios.faena_codigo IS
    'NULL = todas las faenas (interno). Con valor = solo esa faena. MIG302.';

CREATE INDEX IF NOT EXISTS idx_pad_faena
    ON prevencion_alertas_destinatarios (faena_codigo, activo);

DROP TRIGGER IF EXISTS trg_pad_updated_at ON prevencion_alertas_destinatarios;
CREATE TRIGGER trg_pad_updated_at
    BEFORE UPDATE ON prevencion_alertas_destinatarios
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE prevencion_alertas_destinatarios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pad_select ON prevencion_alertas_destinatarios;
CREATE POLICY pad_select ON prevencion_alertas_destinatarios
    FOR SELECT TO authenticated USING (fn_prevencion_personal_puede_ver());

DROP POLICY IF EXISTS pad_write ON prevencion_alertas_destinatarios;
CREATE POLICY pad_write ON prevencion_alertas_destinatarios
    FOR ALL TO authenticated
    USING (fn_prevencion_personal_puede_editar())
    WITH CHECK (fn_prevencion_personal_puede_editar());

GRANT SELECT, INSERT, UPDATE, DELETE ON prevencion_alertas_destinatarios TO authenticated;


-- ############################################################################
-- Destinatarios de una faena, protegido por el secreto del cron
-- ############################################################################
-- Devuelve quién debe recibir el aviso de ESA faena: los internos (alcance
-- todas) más los acotados a ella.

DROP FUNCTION IF EXISTS fn_prevencion_destinatarios_cron(TEXT, TEXT);
CREATE FUNCTION fn_prevencion_destinatarios_cron(p_secreto TEXT, p_faena TEXT)
RETURNS TABLE (email TEXT, nombre TEXT, modo TEXT, externo BOOLEAN)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido.' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
        SELECT d.email::TEXT, d.nombre::TEXT, d.modo::TEXT, d.externo
          FROM prevencion_alertas_destinatarios d
         WHERE d.activo
           AND (d.faena_codigo IS NULL
                OR d.faena_codigo IS NOT DISTINCT FROM p_faena)
         ORDER BY d.externo, d.email;
END $$;
GRANT EXECUTE ON FUNCTION fn_prevencion_destinatarios_cron(TEXT, TEXT) TO anon, authenticated;

COMMENT ON FUNCTION fn_prevencion_destinatarios_cron(TEXT, TEXT) IS
    'Destinatarios del aviso de una faena: internos + los acotados a ella. MIG302.';
