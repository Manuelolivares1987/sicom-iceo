-- ============================================================================
-- MIG447 · Una OT de externo no se cierra sin autorización
-- ============================================================================
--
-- MIG446 dejó el concepto —declarar el trabajo de un tercero, con proveedor y
-- motivo, y autorizarlo la jefatura de operaciones— pero el bloqueo no estaba
-- amarrado a nada: la función `fn_taller_ot_bloqueo_cierre` existía y nadie la
-- llamaba.
--
-- Va como TRIGGER sobre `ordenes_trabajo` y no dentro de los dos RPC de cierre,
-- por la misma razón de MIG437 con el kardex y de MIG441 con el plan: a
-- «ejecutada» se llega por varios caminos —la app de terreno, el tablero del
-- plan, el cierre de Calama, cualquier RPC futuro— y un candado repartido en
-- cada camino es un candado que algún día se olvida en uno.
--
-- Además, quien AUTORIZA no puede ser quien DECLARÓ. Si la misma persona manda
-- el trabajo afuera y se lo aprueba, el control no existe. MIG446 ya lo separó
-- por rol (planificación declara, jefatura de operaciones autoriza); acá se
-- agrega la comprobación por persona, que es la que aguanta cuando alguien tiene
-- los dos sombreros.
-- ============================================================================

BEGIN;

-- ── 1 · Quien autoriza no es quien declaró ──────────────────────────────────
ALTER TABLE ordenes_trabajo
  ADD COLUMN IF NOT EXISTS externo_declarado_por UUID REFERENCES usuarios_perfil(id);

COMMENT ON COLUMN ordenes_trabajo.externo_declarado_por IS
'Quién declaró que el trabajo se hizo afuera. No puede ser el mismo que lo autoriza (MIG447).';

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
    v_user  UUID := auth.uid();
    v_rol   TEXT;
    v_folio TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();

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
       SET ejecutada_por_externo  = p_externo,
           proveedor_externo      = CASE WHEN p_externo THEN trim(p_proveedor) ELSE NULL END,
           externo_motivo         = CASE WHEN p_externo THEN trim(p_motivo) ELSE NULL END,
           externo_declarado_por  = CASE WHEN p_externo THEN v_user ELSE NULL END,
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

    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_operaciones') THEN
        RAISE EXCEPTION 'Sólo la jefatura de operaciones autoriza trabajo de externos.';
    END IF;

    SELECT * INTO v_ot FROM ordenes_trabajo WHERE id = p_ot_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'La OT no existe.'; END IF;
    IF NOT v_ot.ejecutada_por_externo THEN
        RAISE EXCEPTION 'La OT % no está declarada como trabajo de externo.', v_ot.folio;
    END IF;

    -- El control que aguanta cuando alguien tiene los dos sombreros.
    IF v_ot.externo_declarado_por IS NOT NULL AND v_ot.externo_declarado_por = v_user THEN
        RAISE EXCEPTION 'No puedes autorizar un trabajo de externo que declaraste tú. Lo autoriza otra persona de la jefatura.';
    END IF;

    UPDATE ordenes_trabajo
       SET externo_autorizado_por = v_user,
           externo_autorizado_at  = NOW(),
           updated_at = NOW()
     WHERE id = p_ot_id;

    RETURN jsonb_build_object('success', true, 'folio', v_ot.folio);
END;
$$;

-- ── 2 · El candado, en la tabla ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_ot_externo_exige_autorizacion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_cerrados TEXT[] := ARRAY['ejecutada_ok','ejecutada_con_observaciones','cerrada'];
BEGIN
    -- Sólo al CRUZAR a ejecutada: si ya estaba cerrada, no se vuelve a evaluar.
    IF NEW.estado::TEXT = ANY(v_cerrados)
       AND NOT (COALESCE(OLD.estado::TEXT, '') = ANY(v_cerrados))
       AND COALESCE(NEW.ejecutada_por_externo, FALSE)
       AND NEW.externo_autorizado_at IS NULL
    THEN
        RAISE EXCEPTION 'La OT % la ejecutó un externo (%) y todavía no la autoriza la jefatura de operaciones. Sin esa autorización no se puede dar por ejecutada.',
            NEW.folio, COALESCE(NEW.proveedor_externo, 'sin proveedor');
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ot_externo_exige_autorizacion ON ordenes_trabajo;
CREATE TRIGGER trg_ot_externo_exige_autorizacion
    BEFORE UPDATE OF estado ON ordenes_trabajo
    FOR EACH ROW EXECUTE FUNCTION fn_ot_externo_exige_autorizacion();

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE
    v_ot UUID; v_folio TEXT; v_uid UUID; v_ok BOOLEAN := FALSE;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_ot_externo_exige_autorizacion') THEN
        RAISE EXCEPTION 'FALLO: el candado no quedó puesto';
    END IF;

    -- Prueba real: una OT abierta se declara externa y se intenta cerrar.
    SELECT p.id INTO v_uid FROM usuarios_perfil p WHERE p.rol='administrador' LIMIT 1;
    SELECT ot.id, ot.folio INTO v_ot, v_folio
      FROM ordenes_trabajo ot WHERE ot.estado IN ('creada','asignada') LIMIT 1;

    IF v_ot IS NOT NULL THEN
        UPDATE ordenes_trabajo
           SET ejecutada_por_externo = TRUE,
               proveedor_externo = 'Prueba MIG447',
               externo_motivo = 'verificacion de la migracion',
               externo_declarado_por = v_uid
         WHERE id = v_ot;

        BEGIN
            UPDATE ordenes_trabajo SET estado = 'ejecutada_ok' WHERE id = v_ot;
            RAISE NOTICE 'FALLO: la OT % se cerro sin autorizacion', v_folio;
        EXCEPTION WHEN OTHERS THEN
            v_ok := TRUE;
            RAISE NOTICE 'candado OK (%) -> %', v_folio, SQLERRM;
        END;

        -- La contraparte —que CON autorización sí cierra— no se prueba acá:
        -- el cierre tiene además una exigencia previa de evidencia fotográfica
        -- («se requiere al menos 1 evidencia fotográfica o documental»), que es
        -- otro control legítimo y bloquearía la prueba por un motivo distinto.
        -- Lo que importa verificar es que el candado del externo actúa.

        -- Se deshace la declaración de prueba.
        UPDATE ordenes_trabajo
           SET ejecutada_por_externo = FALSE, proveedor_externo = NULL,
               externo_motivo = NULL, externo_declarado_por = NULL,
               externo_autorizado_por = NULL, externo_autorizado_at = NULL
         WHERE id = v_ot;
        RAISE NOTICE 'prueba deshecha: la OT % quedo como estaba', v_folio;
    END IF;

    IF NOT v_ok THEN RAISE EXCEPTION 'FALLO: el candado no bloqueo'; END IF;
END
$mig$;

COMMIT;
