-- ============================================================================
-- 80_mantenimiento_auto_crear_planes.sql
-- ----------------------------------------------------------------------------
-- Trigger automatico que crea planes_mantenimiento faltantes cada vez que se
-- INSERTa un activo nuevo o se le cambia el modelo_id. Tambien expone una
-- RPC para que un admin pueda forzar el barrido completo desde la UI.
--
-- Antes: la asignacion de planes corrio una sola vez en MIG34. Activos nuevos
-- quedaban descubiertos hasta que alguien notara y disparara manualmente.
--
-- Esta migracion:
--   1. fn_auto_crear_planes_activo(activo_id) -- crea planes faltantes para 1
--   2. fn_trg_auto_planes_activo()            -- trigger AFTER INSERT/UPDATE
--   3. trg_auto_planes_activo en activos
--   4. rpc_admin_sembrar_planes_faltantes()   -- barrido manual
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. fn_auto_crear_planes_activo: crea planes faltantes para UN activo ────
CREATE OR REPLACE FUNCTION fn_auto_crear_planes_activo(p_activo_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_creados      INT := 0;
    v_activo       RECORD;
    v_pauta        RECORD;
    v_proxima_fec  DATE;
BEGIN
    SELECT id, codigo, modelo_id, kilometraje_actual, horas_uso_actual, estado
      INTO v_activo
      FROM activos
     WHERE id = p_activo_id;

    IF v_activo.id IS NULL THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id;
    END IF;
    IF v_activo.estado = 'dado_baja' THEN
        RETURN 0;
    END IF;
    IF v_activo.modelo_id IS NULL THEN
        RETURN 0;
    END IF;

    FOR v_pauta IN
        SELECT pf.id, pf.nombre, pf.tipo_plan,
               pf.frecuencia_dias, pf.frecuencia_km,
               pf.frecuencia_horas, pf.frecuencia_ciclos
          FROM pautas_fabricante pf
         WHERE pf.modelo_id = v_activo.modelo_id
           AND pf.activo = true
           AND NOT EXISTS (
               SELECT 1 FROM planes_mantenimiento pm
                WHERE pm.activo_id = p_activo_id
                  AND pm.pauta_fabricante_id = pf.id
           )
    LOOP
        v_proxima_fec := CASE
            WHEN v_pauta.frecuencia_dias IS NOT NULL AND v_pauta.frecuencia_dias > 0
            THEN CURRENT_DATE + v_pauta.frecuencia_dias
            ELSE CURRENT_DATE + 30
        END;

        INSERT INTO planes_mantenimiento (
            activo_id, pauta_fabricante_id, nombre, tipo_plan,
            frecuencia_dias, frecuencia_km, frecuencia_horas, frecuencia_ciclos,
            anticipacion_dias, prioridad,
            ultima_ejecucion_km, ultima_ejecucion_horas,
            proxima_ejecucion_fecha, activo_plan
        ) VALUES (
            p_activo_id, v_pauta.id, v_pauta.nombre, v_pauta.tipo_plan,
            v_pauta.frecuencia_dias, v_pauta.frecuencia_km,
            v_pauta.frecuencia_horas, v_pauta.frecuencia_ciclos,
            7, 'normal',
            v_activo.kilometraje_actual, v_activo.horas_uso_actual,
            v_proxima_fec, true
        );
        v_creados := v_creados + 1;
    END LOOP;

    RETURN v_creados;
END;
$$;

COMMENT ON FUNCTION fn_auto_crear_planes_activo IS
    'Crea planes_mantenimiento faltantes para un activo basado en pautas del modelo. MIG80.';


-- ── 2. Trigger: cuando se inserta o se cambia modelo_id de un activo ───────
CREATE OR REPLACE FUNCTION fn_trg_auto_planes_activo()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Solo dispara si hay modelo Y el activo no esta dado de baja
    IF NEW.modelo_id IS NULL OR NEW.estado = 'dado_baja' THEN
        RETURN NEW;
    END IF;
    -- En UPDATE, solo si el modelo CAMBIO (o pasa de baja a activo)
    IF TG_OP = 'UPDATE' THEN
        IF NEW.modelo_id = COALESCE(OLD.modelo_id, NEW.modelo_id)
           AND OLD.estado != 'dado_baja' THEN
            RETURN NEW;
        END IF;
    END IF;
    PERFORM fn_auto_crear_planes_activo(NEW.id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_planes_activo ON activos;
CREATE TRIGGER trg_auto_planes_activo
    AFTER INSERT OR UPDATE OF modelo_id, estado
    ON activos
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_auto_planes_activo();

COMMENT ON TRIGGER trg_auto_planes_activo ON activos IS
    'Auto-crea planes_mantenimiento cuando se inserta activo o cambia modelo. MIG80.';


-- ── 3. RPC admin para barrido manual de toda la flota ──────────────────────
CREATE OR REPLACE FUNCTION rpc_admin_sembrar_planes_faltantes()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT;
    v_a    RECORD;
    v_tot_activos INT := 0;
    v_tot_creados INT := 0;
    v_creados_act INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para sembrar planes', v_rol;
    END IF;

    FOR v_a IN
        SELECT id, codigo FROM activos
         WHERE estado != 'dado_baja'
           AND modelo_id IS NOT NULL
         ORDER BY codigo
    LOOP
        v_creados_act := fn_auto_crear_planes_activo(v_a.id);
        v_tot_activos := v_tot_activos + 1;
        v_tot_creados := v_tot_creados + v_creados_act;
    END LOOP;

    RETURN jsonb_build_object(
        'success',         true,
        'activos_revisados', v_tot_activos,
        'planes_creados',  v_tot_creados
    );
END;
$$;

COMMENT ON FUNCTION rpc_admin_sembrar_planes_faltantes IS
    'Barrido manual: crea planes faltantes en todos los activos vivos con modelo. MIG80.';


GRANT EXECUTE ON FUNCTION fn_auto_crear_planes_activo(UUID)             TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_admin_sembrar_planes_faltantes()          TO authenticated;


-- ── Validacion ──────────────────────────────────────────────────────────────
DO $$
DECLARE v_trg INT; v_fn INT; v_rpc INT;
BEGIN
    SELECT COUNT(*) INTO v_trg FROM pg_trigger
     WHERE tgname='trg_auto_planes_activo' AND NOT tgisinternal;
    SELECT COUNT(*) INTO v_fn  FROM pg_proc WHERE proname='fn_auto_crear_planes_activo';
    SELECT COUNT(*) INTO v_rpc FROM pg_proc WHERE proname='rpc_admin_sembrar_planes_faltantes';
    IF v_trg <> 1 THEN RAISE EXCEPTION 'STOP - trigger no creado'; END IF;
    IF v_fn  <> 1 THEN RAISE EXCEPTION 'STOP - fn no creada'; END IF;
    IF v_rpc <> 1 THEN RAISE EXCEPTION 'STOP - rpc no creada'; END IF;
    RAISE NOTICE '== MIG80 OK == trigger + fn + rpc instalados';
END $$;

NOTIFY pgrst, 'reload schema';
