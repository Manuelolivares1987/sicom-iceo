-- ============================================================================
-- MIG714 — Franke acotado a su faena + sueldos, bono y costos cerrados en la BD
-- ----------------------------------------------------------------------------
-- Manuel (18-11-2026): «solo pueden ver lo que es de Franke, mi copiloto, el
-- taller y sus activos. Nada más, no pueden ver sueldos ni cosas así».
--
-- Lo que se encontró (probado como Jacinto, supervisor, y Hernán, mecánico):
--   cualquier usuario con sesión leía por API
--     · cargos_incentivo (sueldo base por cargo), tramos_incentivo, incentivos_periodo
--       → política SELECT USING (true);
--     · taller_bono_acta/_cargo/_concepto/_parametros/_tramo_kpi → SIN RLS;
--     · v_taller_bono_reparto (190 filas, reparto del bono por persona) y
--       v_reporte_incentivos → vistas del dueño, saltan RLS;
--     · v_costos_por_ot/_activo/_faena, informe_recepcion_costos → costos.
--   El frontend no lee nada de eso directo: todo pasa por RPC SECURITY DEFINER,
--   que siguen funcionando (el dueño no queda sujeto a estas políticas).
--
-- Cambios:
--   1. fn_puede_ver_remuneraciones(): administrador, gerencia, subgerente de
--      operaciones, RRHH incentivos, o quien ya ve el bono (taller_bono_acceso).
--   2. fn_usuario_acotado(): perfil con solo_su_faena (nunca un administrador).
--   3. Sueldos/bono: política RESTRICTIVA fn_puede_ver_remuneraciones(); las vistas
--      del bono e incentivos devuelven 0 filas a quien no corresponde.
--   4. Costos: quien está acotado a su faena no los ve (vistas + informe de costos).
--   5. Marco Díaz pasa de Coquimbo a Franke (lugar de Hernán): sale del taller y del
--      bono desde hoy; Hernán deja la bodega. Los 6 de Franke quedan acotados a su faena
--      (menú y rutas: Franke, bodega, copiloto, OTs y equipos de Franke).
-- Rollback: database/rollback/714_faena_acotada_sin_sueldos_ni_costos.sql
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_puede_ver_remuneraciones()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT auth.uid() IS NOT NULL AND (
        fn_user_rol() IN ('administrador', 'gerencia', 'subgerente_operaciones', 'rrhh_incentivos')
        OR coalesce(fn_taller_bono_puede_ver(), false))
$$;
CREATE OR REPLACE FUNCTION public.fn_usuario_acotado()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT coalesce((SELECT u.solo_su_faena AND u.rol::text <> 'administrador'
                       FROM usuarios_perfil u WHERE u.id = auth.uid()), false)
$$;
REVOKE ALL ON FUNCTION public.fn_puede_ver_remuneraciones(), public.fn_usuario_acotado() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_puede_ver_remuneraciones(), public.fn_usuario_acotado() TO authenticated;

-- ── Sueldos / incentivos ────────────────────────────────────────────────────
DROP POLICY IF EXISTS mig714_rem_cargos ON public.cargos_incentivo;
CREATE POLICY mig714_rem_cargos ON public.cargos_incentivo AS RESTRICTIVE FOR SELECT TO authenticated
    USING (public.fn_puede_ver_remuneraciones());
DROP POLICY IF EXISTS mig714_rem_tramos ON public.tramos_incentivo;
CREATE POLICY mig714_rem_tramos ON public.tramos_incentivo AS RESTRICTIVE FOR SELECT TO authenticated
    USING (public.fn_puede_ver_remuneraciones());
DROP POLICY IF EXISTS mig714_rem_periodo ON public.incentivos_periodo;
CREATE POLICY mig714_rem_periodo ON public.incentivos_periodo AS RESTRICTIVE FOR SELECT TO authenticated
    USING (public.fn_puede_ver_remuneraciones());

-- ── Bono del taller: tablas sin RLS → RLS + lectura solo a quien ve el bono ──
DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['taller_bono_acta', 'taller_bono_cargo', 'taller_bono_concepto', 'taller_bono_parametros', 'taller_bono_tramo_kpi'] LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('DROP POLICY IF EXISTS mig714_rem_sel ON public.%I', t);
        EXECUTE format('CREATE POLICY mig714_rem_sel ON public.%I FOR SELECT TO authenticated USING (public.fn_puede_ver_remuneraciones())', t);
    END LOOP;
END $$;

-- ── Vistas: se envuelven con el candado (mismas columnas, mismo orden) ──────
DO $$
DECLARE v TEXT; d TEXT; cond TEXT;
BEGIN
    FOR v, cond IN VALUES ('v_taller_bono_reparto', 'public.fn_puede_ver_remuneraciones()'),
                          ('v_reporte_incentivos',  'public.fn_puede_ver_remuneraciones()'),
                          ('v_costos_por_ot',       'NOT public.fn_usuario_acotado()'),
                          ('v_costos_por_activo',   'NOT public.fn_usuario_acotado()'),
                          ('v_costos_por_faena',    'NOT public.fn_usuario_acotado()') LOOP
        d := rtrim(btrim(pg_get_viewdef(('public.' || v)::regclass, true)), ';');
        IF position('mig714' IN d) > 0 THEN CONTINUE; END IF;   -- ya envuelta
        EXECUTE format('CREATE OR REPLACE VIEW public.%I AS SELECT _mig714.* FROM (%s) _mig714 WHERE %s', v, d, cond);
    END LOOP;
END $$;

-- ── Costos de recepción: no para quien está acotado ─────────────────────────
DROP POLICY IF EXISTS mig714_irc_acotado ON public.informe_recepcion_costos;
CREATE POLICY mig714_irc_acotado ON public.informe_recepcion_costos AS RESTRICTIVE FOR SELECT TO authenticated
    USING (NOT public.fn_usuario_acotado());

-- ── Movimiento de personal (Manuel 18-11): Marco Díaz pasa a Franke en lugar de Hernán ──
-- Marco: deja el taller de Coquimbo (sale de la lista de técnicos y del bono desde hoy)
-- y queda como mecánico de faena Franke, turno A (el de Hernán), con la misma app que Yohan.
-- Sus 4 OT abiertas de Coquimbo NO se reasignan acá: las reparte el jefe de taller.
UPDATE public.usuarios_perfil
   SET faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-FRANCKE'),
       rol = 'tecnico_mantenimiento', cargo = 'Mecánico de faena · turno A', updated_at = NOW()
 WHERE email = 'marco.diaz@sicom-iceo.cl';
UPDATE public.taller_tecnicos
   SET activo = false, participa_en_bono = false, motivo_sin_bono = 'Trasladado a faena Franke el 18-11-2026', updated_at = NOW()
 WHERE usuario_perfil_id = (SELECT id FROM usuarios_perfil WHERE email = 'marco.diaz@sicom-iceo.cl');
UPDATE public.taller_tecnico_cargo SET hasta = (NOW() AT TIME ZONE 'America/Santiago')::date
 WHERE hasta IS NULL
   AND tecnico_id IN (SELECT t.id FROM taller_tecnicos t JOIN usuarios_perfil u ON u.id = t.usuario_perfil_id
                       WHERE u.email = 'marco.diaz@sicom-iceo.cl');
UPDATE public.bodega_responsables SET nombre = 'Marco Díaz (mecánico Franke, solo sacar)'
 WHERE email = 'marco.diaz@sicom-iceo.cl' AND bodega_id = (SELECT id FROM bodegas WHERE codigo = 'BOD-FRK-F01');
-- Hernán deja la bodega de Franke (su cuenta queda como está).
UPDATE public.bodega_responsables SET activo = false
 WHERE email = 'hcortes@pillado.cl' AND bodega_id = (SELECT id FROM bodegas WHERE codigo = 'BOD-FRK-F01');

-- ── Franke: acotados a su faena ─────────────────────────────────────────────
UPDATE public.usuarios_perfil SET solo_su_faena = true
 WHERE email IN ('jsimon@pillado.cl', 'mespinosa@pillado.cl', 'earqueros@pillado.cl', 'hcortes@pillado.cl', 'yrondon@pillado.cl',
                 'marco.diaz@sicom-iceo.cl')
   AND faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-FRANCKE');

DO $$
DECLARE v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM usuarios_perfil u JOIN faenas f ON f.id = u.faena_id
     WHERE f.codigo = 'FAE-FRANCKE' AND u.solo_su_faena;
    IF v_n < 6 THEN RAISE EXCEPTION 'MIG714: solo % usuarios de Franke quedaron acotados', v_n; END IF;
    IF NOT EXISTS (SELECT 1 FROM usuarios_perfil u JOIN faenas f ON f.id = u.faena_id
                    WHERE u.email = 'marco.diaz@sicom-iceo.cl' AND f.codigo = 'FAE-FRANCKE' AND u.rol = 'tecnico_mantenimiento') THEN
        RAISE EXCEPTION 'MIG714: Marco Díaz no quedó en Franke';
    END IF;
    RAISE NOTICE 'MIG714 OK: % usuarios de Franke acotados; sueldos, bono y costos cerrados', v_n;
END $$;
