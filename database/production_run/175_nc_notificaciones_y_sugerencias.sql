-- ============================================================================
-- 175_nc_notificaciones_y_sugerencias.sql
-- ----------------------------------------------------------------------------
-- (P3) Las No Conformidades hoy solo aparecen en la bandeja (polling). No
-- avisan. Esta migracion:
--   1. Amplia el CHECK de alertas.tipo para admitir 'no_conformidad'.
--   2. Trigger AFTER INSERT en no_conformidades -> crea una alerta in-app
--      (campanita del header) por cada usuario destinatario (admin/supervisor/
--      planificador). Reliable, sin configuracion.
--   3. Columna no_conformidades.email_notificada_at: control del envio por
--      correo (digest). La API /api/notificaciones/nc-digest marca aqui.
--
-- (P5) Tabla sugerencias: la "ampolleta" de mejoras que el usuario manda; la
--   API /api/sugerencias la guarda y la envia por correo en formato prompt.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Ampliar CHECK de alertas.tipo (agregar 'no_conformidad') ─────────────
DO $$
DECLARE v_conname TEXT;
BEGIN
    SELECT conname INTO v_conname
      FROM pg_constraint
     WHERE conrelid = 'alertas'::regclass AND contype = 'c'
       AND pg_get_constraintdef(oid) LIKE '%gps_sin_senal%';
    IF v_conname IS NOT NULL THEN
        EXECUTE format('ALTER TABLE alertas DROP CONSTRAINT %I', v_conname);
    END IF;
    ALTER TABLE alertas ADD CONSTRAINT chk_alertas_tipo CHECK (tipo IN (
        'vencimiento','stock_minimo','ot_vencida','incumplimiento','bloqueante',
        'antiguedad_vehiculo','semep_vencido','fatiga_conductor','rt_por_vencer',
        'hermeticidad_vencida','sec_no_vigente','sensor_fuga','accidente_no_reportado',
        'jornada_excedida','pts_faltante','disponibilidad_vencida','gps_sin_senal',
        'no_conformidad'));
EXCEPTION WHEN duplicate_object THEN
    NULL; -- ya existe chk_alertas_tipo con el valor
END $$;


-- ── 2. Trigger: alerta in-app por cada NC nueva ─────────────────────────────
CREATE OR REPLACE FUNCTION fn_nc_crear_alertas()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_patente TEXT;
    v_codigo  TEXT;
    v_sev     TEXT;
    v_titulo  TEXT;
    v_msg     TEXT;
    v_u       RECORD;
BEGIN
    SELECT a.patente, a.codigo INTO v_patente, v_codigo
      FROM activos a WHERE a.id = NEW.activo_id;

    -- Severidad de la alerta a partir de la severidad de la NC
    v_sev := CASE LOWER(COALESCE(NEW.severidad, ''))
                  WHEN 'critica' THEN 'critical'
                  WHEN 'alta'    THEN 'warning'
                  ELSE 'info' END;

    v_titulo := 'No conformidad'
        || CASE WHEN v_patente IS NOT NULL THEN ': ' || v_patente
                WHEN v_codigo  IS NOT NULL THEN ': ' || v_codigo
                ELSE '' END;
    v_msg := COALESCE(NEW.descripcion, 'Nueva no conformidad registrada')
        || CASE WHEN NEW.origen IS NOT NULL THEN ' · origen: ' || NEW.origen ELSE '' END
        || CASE WHEN NEW.severidad IS NOT NULL THEN ' · severidad: ' || NEW.severidad ELSE '' END;

    -- Una alerta por destinatario interno (los que gestionan taller)
    FOR v_u IN
        SELECT id FROM usuarios_perfil
         WHERE activo = true
           AND rol IN ('administrador','supervisor','planificador')
    LOOP
        INSERT INTO alertas (
            tipo, titulo, mensaje, severidad,
            entidad_tipo, entidad_id, destinatario_id, leida, created_at
        ) VALUES (
            'no_conformidad', v_titulo, v_msg, v_sev,
            'no_conformidad', NEW.id, v_u.id, false, NOW()
        );
    END LOOP;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Nunca bloquear la creacion de la NC por un fallo en la notificacion.
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_nc_crear_alertas ON no_conformidades;
CREATE TRIGGER trg_nc_crear_alertas
    AFTER INSERT ON no_conformidades
    FOR EACH ROW EXECUTE FUNCTION fn_nc_crear_alertas();


-- ── 3. Control de envio por correo (digest) ─────────────────────────────────
ALTER TABLE no_conformidades ADD COLUMN IF NOT EXISTS email_notificada_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_nc_email_pendiente
    ON no_conformidades (created_at) WHERE email_notificada_at IS NULL;


-- ── 4. (P5) Tabla de sugerencias (la ampolleta) ─────────────────────────────
CREATE TABLE IF NOT EXISTS sugerencias (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    texto             TEXT NOT NULL,
    contexto_url      TEXT,
    contexto_titulo   TEXT,
    usuario_id        UUID REFERENCES usuarios_perfil(id),
    usuario_nombre    TEXT,
    usuario_rol       TEXT,
    prompt_generado   TEXT,
    estado            VARCHAR(20) NOT NULL DEFAULT 'nueva',
    email_enviado_at  TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_sugerencia_estado CHECK (estado IN ('nueva','en_proceso','aplicada','descartada'))
);
CREATE INDEX IF NOT EXISTS idx_sugerencias_estado ON sugerencias (estado, created_at DESC);

ALTER TABLE sugerencias ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_sugerencias_select ON sugerencias;
CREATE POLICY pol_sugerencias_select ON sugerencias
    FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS pol_sugerencias_insert ON sugerencias;
CREATE POLICY pol_sugerencias_insert ON sugerencias
    FOR INSERT TO authenticated WITH CHECK (true);


-- ── Validacion ──────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_nc_crear_alertas') THEN
        RAISE EXCEPTION 'STOP - no se creo trg_nc_crear_alertas';
    END IF;
    RAISE NOTICE '== MIG175 OK == NC -> alertas in-app + email_notificada_at + tabla sugerencias';
END $$;

NOTIFY pgrst, 'reload schema';
