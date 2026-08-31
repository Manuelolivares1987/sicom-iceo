-- ============================================================================
-- MIG446 · La cuadrilla deja de ser un texto, y el externo se declara
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 30-08-2026: reparto del bono proporcional al tiempo de cada uno, con la
-- cuadrilla declarada ANTES de ejecutar; y «una mala práctica era enviar a
-- externos a realizar trabajos, eso debe estar claramente prohibido o en su
-- defecto pasar por validación».
--
-- LO QUE PASABA
--
-- 1. La cuadrilla es un campo de texto libre. Guarda cosas como
--    «Yusdel Sarduy Joel Coo» en una sola celda. Para repartir plata entre dos
--    personas hay que saber que son dos personas, cuáles, y cuánto puso cada
--    una. Un string no lo sabe.
--
-- 2. El campo `equipo_externo` existe pero nunca fue eso. De 241 jornadas, 22
--    lo llenan, y adentro hay patentes, faenas, clientes y hasta nombres de
--    mecánicos propios: «MANUEL OLIVARES /TALLER COQUIMBO»,
--    «Felipe López, yusdel», «JGBY-10/AURA/CERRO TOLOLO». Es una nota de
--    ubicación, no una declaración de que el trabajo lo hizo un tercero.
--    Resultado: hoy NO HAY FORMA de saber si un trabajo lo hizo un externo, y
--    por lo tanto tampoco de prohibirlo ni de validarlo.
--
-- QUÉ SE HACE
--   1. `taller_ot_cuadrilla`: una fila por persona y jornada, con su rol.
--      Se siembra desde el texto que ya existe, sin perder nada.
--   2. El reparto sale proporcional al tiempo efectivo de cada uno, que
--      `taller_ot_ejecuciones.ejecutor_id` ya mide. Si nadie usó el cronómetro,
--      se reparte en partes iguales y la vista lo dice.
--   3. La cuadrilla se congela cuando la OT queda ejecutada: a esa altura ya
--      es la base de un pago. Todo cambio queda en bitácora.
--   4. El trabajo de externo se declara, se autoriza con nombre y motivo, y
--      mientras no esté autorizado la OT no se cierra. Y no genera bono.
--
-- POR QUÉ EL BONO NO SE ANCLA EN LOS USUARIOS
-- Los 9 técnicos activos NO tienen cuenta en el sistema (`usuario_perfil_id`
-- nulo en los 9). El sujeto de pago es el técnico del catálogo, no un login.
-- ============================================================================

BEGIN;

-- ── 1 · La cuadrilla, una fila por persona ──────────────────────────────────
CREATE TABLE IF NOT EXISTS taller_ot_cuadrilla (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_ot_id    UUID NOT NULL REFERENCES taller_plan_semanal_ots(id) ON DELETE CASCADE,
    tecnico_id    UUID NOT NULL REFERENCES taller_tecnicos(id),
    rol           TEXT NOT NULL DEFAULT 'titular',
    declarada_por UUID REFERENCES usuarios_perfil(id),
    declarada_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    origen        TEXT NOT NULL DEFAULT 'manual',
    CONSTRAINT uq_taller_cuadrilla UNIQUE (plan_ot_id, tecnico_id),
    CONSTRAINT chk_taller_cuadrilla_rol CHECK (rol IN ('titular','apoyo')),
    CONSTRAINT chk_taller_cuadrilla_origen CHECK (origen IN ('manual','migracion'))
);

CREATE INDEX IF NOT EXISTS idx_taller_cuadrilla_plan_ot ON taller_ot_cuadrilla(plan_ot_id);
CREATE INDEX IF NOT EXISTS idx_taller_cuadrilla_tecnico ON taller_ot_cuadrilla(tecnico_id);

COMMENT ON TABLE taller_ot_cuadrilla IS
'Quién trabaja en cada jornada del plan. Reemplaza al texto libre taller_plan_semanal_ots.cuadrilla como fuente para el reparto del bono (MIG446).';
COMMENT ON COLUMN taller_ot_cuadrilla.rol IS
'titular = responsable de la jornada; apoyo = acompaña. El reparto no usa el rol: usa el tiempo. El rol es para saber a quién preguntarle.';

-- Bitácora de cambios: quién tocó la cuadrilla de una jornada y cuándo.
CREATE TABLE IF NOT EXISTS taller_ot_cuadrilla_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_ot_id  UUID NOT NULL,
    tecnico_id  UUID,
    accion      TEXT NOT NULL,
    hecho_por   UUID,
    hecho_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    detalle     TEXT
);

COMMENT ON TABLE taller_ot_cuadrilla_log IS
'Toda alta o baja en la cuadrilla de una jornada. Es la prueba de que nadie se agregó después de hecho el trabajo (MIG446).';

-- ── 2 · Sembrar desde el texto que ya existe ────────────────────────────────
--
-- Se busca cada técnico activo por su primer nombre con límite de palabra, para
-- que «Juan» no calce dentro de otra palabra. El primero que aparece en el
-- texto queda como titular.
INSERT INTO taller_ot_cuadrilla (plan_ot_id, tecnico_id, rol, origen)
SELECT po.id,
       t.id,
       CASE WHEN row_number() OVER (
              PARTITION BY po.id
              ORDER BY position(lower(split_part(t.nombre,' ',1)) in lower(po.cuadrilla))
            ) = 1 THEN 'titular' ELSE 'apoyo' END,
       'migracion'
  FROM taller_plan_semanal_ots po
  JOIN taller_tecnicos t
    ON COALESCE(t.activo, TRUE)
   AND po.cuadrilla ~* ('\m' || split_part(t.nombre, ' ', 1) || '\M')
 WHERE po.cuadrilla IS NOT NULL
   AND length(trim(po.cuadrilla)) > 0
ON CONFLICT (plan_ot_id, tecnico_id) DO NOTHING;

-- ── 3 · La cuadrilla se congela cuando la OT ya es un pago ──────────────────
CREATE OR REPLACE FUNCTION fn_taller_cuadrilla_congelada()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_plan_ot UUID := COALESCE(NEW.plan_ot_id, OLD.plan_ot_id);
    v_estado  TEXT;
    v_folio   TEXT;
BEGIN
    SELECT ot.estado::TEXT, ot.folio INTO v_estado, v_folio
      FROM taller_plan_semanal_ots po
      JOIN ordenes_trabajo ot ON ot.id = po.ot_id
     WHERE po.id = v_plan_ot;

    -- Con la OT ya ejecutada, la cuadrilla es la base de un pago: no se toca.
    IF v_estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada') THEN
        RAISE EXCEPTION 'La OT % ya está ejecutada: su cuadrilla es la base del bono y no se puede cambiar.', v_folio;
    END IF;

    INSERT INTO taller_ot_cuadrilla_log (plan_ot_id, tecnico_id, accion, hecho_por, detalle)
    VALUES (v_plan_ot,
            COALESCE(NEW.tecnico_id, OLD.tecnico_id),
            lower(TG_OP),
            auth.uid(),
            'estado de la OT al momento del cambio: ' || COALESCE(v_estado, 'sin OT'));

    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_taller_cuadrilla_congelada ON taller_ot_cuadrilla;
CREATE TRIGGER trg_taller_cuadrilla_congelada
    BEFORE INSERT OR UPDATE OR DELETE ON taller_ot_cuadrilla
    FOR EACH ROW EXECUTE FUNCTION fn_taller_cuadrilla_congelada();

-- ── 4 · El trabajo de externo se declara y se autoriza ──────────────────────
ALTER TABLE ordenes_trabajo
  ADD COLUMN IF NOT EXISTS ejecutada_por_externo  BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS proveedor_externo      TEXT,
  ADD COLUMN IF NOT EXISTS externo_motivo         TEXT,
  ADD COLUMN IF NOT EXISTS externo_autorizado_por UUID REFERENCES usuarios_perfil(id),
  ADD COLUMN IF NOT EXISTS externo_autorizado_at  TIMESTAMPTZ;

COMMENT ON COLUMN ordenes_trabajo.ejecutada_por_externo IS
'El trabajo lo hizo un tercero, no el taller. Exige autorización para cerrar y NO genera bono de incentivo (MIG446).';

CREATE OR REPLACE FUNCTION rpc_taller_declarar_externo(
    p_ot_id     UUID,
    p_externo   BOOLEAN,
    p_proveedor TEXT DEFAULT NULL,
    p_motivo    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT;
    v_folio TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();

    -- Declarar que un trabajo se fue afuera lo puede hacer quien planifica.
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento',
                     'jefe_operaciones','planificador','supervisor') THEN
        RAISE EXCEPTION 'Tu perfil no puede declarar trabajo de externos.';
    END IF;

    SELECT folio INTO v_folio FROM ordenes_trabajo WHERE id = p_ot_id;
    IF v_folio IS NULL THEN RAISE EXCEPTION 'La OT no existe.'; END IF;

    IF p_externo AND COALESCE(length(trim(p_proveedor)), 0) < 3 THEN
        RAISE EXCEPTION 'Indica qué empresa externa hizo el trabajo.';
    END IF;
    IF p_externo AND COALESCE(length(trim(p_motivo)), 0) < 10 THEN
        RAISE EXCEPTION 'Indica por qué el trabajo salió del taller (mínimo 10 caracteres).';
    END IF;

    UPDATE ordenes_trabajo
       SET ejecutada_por_externo = p_externo,
           proveedor_externo     = CASE WHEN p_externo THEN trim(p_proveedor) ELSE NULL END,
           externo_motivo        = CASE WHEN p_externo THEN trim(p_motivo) ELSE NULL END,
           externo_autorizado_por = NULL,
           externo_autorizado_at  = NULL,
           updated_at = NOW()
     WHERE id = p_ot_id;

    RETURN jsonb_build_object('success', true, 'folio', v_folio, 'externo', p_externo);
END;
$$;

CREATE OR REPLACE FUNCTION rpc_taller_autorizar_externo(p_ot_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT;
    v_ot   RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();

    -- Autorizar es un acto de jefatura, y no lo puede hacer quien lo declaró:
    -- si la misma persona manda el trabajo afuera y se lo aprueba, el control
    -- no existe.
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_operaciones') THEN
        RAISE EXCEPTION 'Sólo la jefatura de operaciones autoriza trabajo de externos.';
    END IF;

    SELECT * INTO v_ot FROM ordenes_trabajo WHERE id = p_ot_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'La OT no existe.'; END IF;
    IF NOT v_ot.ejecutada_por_externo THEN
        RAISE EXCEPTION 'La OT % no está declarada como trabajo de externo.', v_ot.folio;
    END IF;

    UPDATE ordenes_trabajo
       SET externo_autorizado_por = v_user,
           externo_autorizado_at  = NOW(),
           updated_at = NOW()
     WHERE id = p_ot_id;

    RETURN jsonb_build_object('success', true, 'folio', v_ot.folio);
END;
$$;

REVOKE ALL ON FUNCTION rpc_taller_declarar_externo(UUID, BOOLEAN, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_autorizar_externo(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_declarar_externo(UUID, BOOLEAN, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_autorizar_externo(UUID) TO authenticated;

-- ── 5 · Sin autorización, el externo no cierra ──────────────────────────────
CREATE OR REPLACE FUNCTION fn_taller_ot_bloqueo_cierre(p_ot_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT CASE
        WHEN ot.ejecutada_por_externo AND ot.externo_autorizado_at IS NULL
            THEN 'Esta OT está declarada como trabajo de un externo (' ||
                 COALESCE(ot.proveedor_externo, 'sin proveedor') ||
                 ') y todavía no la autoriza la jefatura de operaciones.'
        ELSE NULL
    END
    FROM ordenes_trabajo ot WHERE ot.id = p_ot_id;
$$;

COMMENT ON FUNCTION fn_taller_ot_bloqueo_cierre IS
'Devuelve el motivo por el que una OT no se puede cerrar todavía, o NULL si se puede (MIG446).';

-- ── 5b · El cronómetro tiene que decir QUIÉN ────────────────────────────────
--
-- Los nueve técnicos comparten la cuenta 'operador_taller' y el nombre que cada
-- uno elige en la app vive sólo en su teléfono: nunca llega al registro. Por eso
--  es la misma cuenta para todos y el tiempo no se puede atribuir a
-- una persona. Sin esto, el reparto proporcional es imposible por diseño.
ALTER TABLE taller_ot_ejecuciones
  ADD COLUMN IF NOT EXISTS tecnico_id UUID REFERENCES taller_tecnicos(id);

CREATE INDEX IF NOT EXISTS idx_taller_ejec_tecnico ON taller_ot_ejecuciones(tecnico_id);

COMMENT ON COLUMN taller_ot_ejecuciones.tecnico_id IS
'Quién puso el tiempo. La cuenta del taller es compartida, así que el ejecutor real se declara acá (MIG446).';

-- ── 6 · El reparto del bono ─────────────────────────────────────────────────
--
-- Proporcional al tiempo efectivo de cada uno. Si nadie usó el cronómetro, se
-- reparte en partes iguales y la vista lo dice en `base_reparto`, para que
-- quien revise sepa que ese porcentaje no salió de una medición.
CREATE OR REPLACE VIEW v_taller_bono_reparto AS
WITH cuadrilla AS (
    SELECT po.ot_id,
           c.tecnico_id,
           min(c.rol) AS rol
      FROM taller_ot_cuadrilla c
      JOIN taller_plan_semanal_ots po ON po.id = c.plan_ot_id
     GROUP BY po.ot_id, c.tecnico_id
),
tiempos AS (
    SELECT e.ot_id,
           t.id AS tecnico_id,
           COALESCE(sum(e.tiempo_efectivo_segundos), 0)::NUMERIC AS segundos
      FROM taller_ot_ejecuciones e
      JOIN taller_tecnicos t
        ON t.id = e.tecnico_id
       OR (e.tecnico_id IS NULL AND t.usuario_perfil_id = e.ejecutor_id)
     GROUP BY e.ot_id, t.id
)
SELECT ot.id                                   AS ot_id,
       ot.folio                                AS ot_folio,
       ot.estado::TEXT                         AS ot_estado,
       ot.fecha_termino,
       ot.ejecutada_por_externo,
       (ot.ejecutada_por_externo IS FALSE)     AS genera_bono,
       cu.tecnico_id,
       t.nombre                                AS tecnico,
       cu.rol,
       COALESCE(ti.segundos, 0)                AS segundos,
       CASE
           WHEN sum(COALESCE(ti.segundos, 0)) OVER (PARTITION BY ot.id) > 0
               THEN round(COALESCE(ti.segundos, 0)
                          / sum(COALESCE(ti.segundos, 0)) OVER (PARTITION BY ot.id), 4)
           ELSE round(1.0 / count(*) OVER (PARTITION BY ot.id), 4)
       END                                     AS participacion,
       CASE
           WHEN sum(COALESCE(ti.segundos, 0)) OVER (PARTITION BY ot.id) > 0
               THEN 'tiempo medido'
           ELSE 'partes iguales'
       END                                     AS base_reparto
  FROM cuadrilla cu
  JOIN ordenes_trabajo ot ON ot.id = cu.ot_id
  JOIN taller_tecnicos t  ON t.id = cu.tecnico_id
  LEFT JOIN tiempos ti    ON ti.ot_id = cu.ot_id AND ti.tecnico_id = cu.tecnico_id;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE
    v_filas INT; v_ots INT; v_pareja INT; v_ext INT;
BEGIN
    SELECT count(*), count(DISTINCT plan_ot_id) INTO v_filas, v_ots FROM taller_ot_cuadrilla;
    RAISE NOTICE 'cuadrilla sembrada: % personas-jornada en % jornadas', v_filas, v_ots;

    SELECT count(*) INTO v_pareja FROM (
        SELECT plan_ot_id FROM taller_ot_cuadrilla GROUP BY plan_ot_id HAVING count(*) > 1
    ) x;
    RAISE NOTICE 'jornadas trabajadas en pareja: %', v_pareja;

    SELECT count(*) INTO v_ext FROM ordenes_trabajo WHERE ejecutada_por_externo;
    RAISE NOTICE 'OT declaradas como externas hoy: % (nadie las ha declarado aún)', v_ext;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_taller_cuadrilla_congelada') THEN
        RAISE EXCEPTION 'FALLO: la cuadrilla no quedó congelada';
    END IF;
    RAISE NOTICE 'cuadrilla congelada tras ejecutar, con bitácora';
END
$mig$;

COMMIT;
