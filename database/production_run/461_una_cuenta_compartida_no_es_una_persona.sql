-- ============================================================================
-- MIG461 · Una cuenta compartida no es una persona
-- ============================================================================
--
-- LO QUE AVISÓ MANUEL
-- 31-08-2026: «ahora están entrando con una cuenta genérica y eligen su OT
-- asignada, ojo con eso».
--
-- Medido en producción, es exactamente así. Las únicas cuentas que figuran
-- ejecutando OT del taller son:
--
--     Manuel Olivares   [administrador]       4 ejecuciones · 4 sin técnico
--     Jefe de Taller    [jefe_mantenimiento]  1 ejecución   · 1 sin técnico
--
-- «Jefe de Taller» es un cargo, no una persona: es la cuenta que comparte el
-- taller. Y el 100 % de las ejecuciones registradas no declara técnico.
--
-- POR QUÉ ESTO ES GRAVE AHORA Y NO LO ERA ANTES
-- Desde septiembre, cerrar una OT y medir su tiempo decide un pago. Con una
-- sesión compartida, «quién trabajó» pasa a ser una declaración de quien tenga
-- el teléfono en la mano.
--
-- LO QUE YA ESTABA BIEN, Y CONVIENE NO ROMPERLO
-- Quién COBRA no sale del teléfono: sale de `taller_ot_cuadrilla`, que sólo
-- escribe `rpc_taller_set_cuadrilla` y exige rol de jefatura. Un mecánico con
-- cuenta compartida no puede meterse en una cuadrilla. Lo que el teléfono
-- influye es CUÁNTO le toca a cada uno dentro de una cuadrilla que la jefatura
-- ya nombró.
--
-- LA BOMBA QUE SÍ HABÍA
-- `v_taller_bono_reparto` atribuía el tiempo así:
--
--     JOIN taller_tecnicos t ON t.id = e.tecnico_id
--        OR (e.tecnico_id IS NULL AND t.usuario_perfil_id = e.ejecutor_id)
--
-- Esa segunda rama dice «si no se declaró técnico, es de quien tenga la cuenta».
-- Si alguien vinculara la cuenta «Jefe de Taller» a un técnico, TODO el tiempo
-- sin declarar —hoy el 100 %— se le cargaría a esa sola persona, y el reparto
-- de la cuadrilla se lo llevaría entero. No hace falta mala fe: basta un
-- vínculo puesto para probar.
--
-- QUÉ SE HACE
--
--   1. Se marca qué cuentas son compartidas, en una tabla, no en el código.
--   2. Un trigger impide vincular una cuenta compartida a un técnico. La bomba
--      no se puede armar, ni por error.
--   3. El reparto deja de atribuir tiempo por cuenta. O el técnico se declaró,
--      o el tiempo no tiene dueño: cae a partes iguales dentro de la cuadrilla
--      que nombró la jefatura, y el aviso «reparto sin tiempo medido» ya lo
--      dice en la cartola.
--   4. Iniciar una ejecución desde una cuenta compartida EXIGE declarar el
--      técnico. Desde una cuenta personal se puede omitir, porque la cuenta ya
--      dice quién es.
--
-- LO QUE ESTO NO ARREGLA, Y HAY QUE DECIRLO
-- En un teléfono compartido, elegir «soy Joel Coo» sigue siendo una
-- declaración: nadie la verifica. El arreglo de fondo es una cuenta por
-- persona —hoy siete de nueve mecánicos no tienen—. Esto acota el daño
-- mientras tanto: el reparto no se lo puede llevar entero una cuenta, y quien
-- declara queda escrito.
-- ============================================================================

BEGIN;

-- ── 1 · Qué cuentas son compartidas ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS usuarios_cuenta_compartida (
    usuario_perfil_id UUID PRIMARY KEY REFERENCES usuarios_perfil(id) ON DELETE CASCADE,
    nota              TEXT,
    creado_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE usuarios_cuenta_compartida IS
    'Cuentas que usa más de una persona. No pueden vincularse a un técnico ni '
    'servir para atribuir trabajo a nadie en particular.';

-- Una cuenta cuyo nombre es un cargo no es de nadie.
INSERT INTO usuarios_cuenta_compartida (usuario_perfil_id, nota)
SELECT up.id, 'El taller entra por acá. Es un cargo, no una persona.'
  FROM usuarios_perfil up
 WHERE up.nombre_completo = 'Jefe de Taller'
ON CONFLICT (usuario_perfil_id) DO NOTHING;

ALTER TABLE usuarios_cuenta_compartida ENABLE ROW LEVEL SECURITY;

-- ── 2 · No se puede vincular una cuenta compartida a un técnico ─────────────
CREATE OR REPLACE FUNCTION fn_taller_tecnico_no_cuenta_compartida()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_nombre TEXT;
BEGIN
    IF NEW.usuario_perfil_id IS NULL THEN RETURN NEW; END IF;

    IF EXISTS (SELECT 1 FROM usuarios_cuenta_compartida c
                WHERE c.usuario_perfil_id = NEW.usuario_perfil_id) THEN
        SELECT up.nombre_completo INTO v_nombre
          FROM usuarios_perfil up WHERE up.id = NEW.usuario_perfil_id;
        RAISE EXCEPTION
            '«%» es una cuenta compartida del taller, no una persona. Vincularla a % '
            'haría que todo el trabajo sin técnico declarado se le cargara a él. '
            'Hay que crearle una cuenta propia.', v_nombre, NEW.nombre;
    END IF;

    -- Y una cuenta personal tampoco puede ser dos técnicos a la vez.
    IF EXISTS (SELECT 1 FROM taller_tecnicos t
                WHERE t.usuario_perfil_id = NEW.usuario_perfil_id
                  AND t.id <> NEW.id AND COALESCE(t.activo, TRUE)) THEN
        RAISE EXCEPTION 'Esa cuenta ya está vinculada a otro técnico.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tecnico_no_cuenta_compartida ON taller_tecnicos;
CREATE TRIGGER trg_tecnico_no_cuenta_compartida
    BEFORE INSERT OR UPDATE OF usuario_perfil_id ON taller_tecnicos
    FOR EACH ROW EXECUTE FUNCTION fn_taller_tecnico_no_cuenta_compartida();

-- ── 3 · El reparto no atribuye tiempo por cuenta ────────────────────────────
--
-- O el técnico se declaró, o el tiempo no tiene dueño. Atribuir por cuenta es
-- justo lo que falla cuando la cuenta es de todos.
CREATE OR REPLACE VIEW v_taller_bono_reparto AS
 WITH cuadrilla AS (
         SELECT po.ot_id,
            c.tecnico_id,
            min(c.rol) AS rol
           FROM taller_ot_cuadrilla c
             JOIN taller_plan_semanal_ots po ON po.id = c.plan_ot_id
          GROUP BY po.ot_id, c.tecnico_id
        ), tiempos AS (
         SELECT e.ot_id,
            e.tecnico_id,
            COALESCE(sum(e.tiempo_efectivo_segundos), 0::bigint)::numeric AS segundos
           FROM taller_ot_ejecuciones e
          WHERE e.tecnico_id IS NOT NULL
          GROUP BY e.ot_id, e.tecnico_id
        )
 SELECT ot.id AS ot_id,
    ot.folio AS ot_folio,
    ot.estado::text AS ot_estado,
    ot.fecha_termino,
    ot.ejecutada_por_externo,
    ot.ejecutada_por_externo IS FALSE AS genera_bono,
    cu.tecnico_id,
    t.nombre AS tecnico,
    cu.rol,
    COALESCE(ti.segundos, 0::numeric) AS segundos,
        CASE
            WHEN sum(COALESCE(ti.segundos, 0::numeric)) OVER (PARTITION BY ot.id) > 0::numeric
            THEN round(COALESCE(ti.segundos, 0::numeric) / sum(COALESCE(ti.segundos, 0::numeric)) OVER (PARTITION BY ot.id), 4)
            ELSE round(1.0 / count(*) OVER (PARTITION BY ot.id)::numeric, 4)
        END AS participacion,
        CASE
            WHEN sum(COALESCE(ti.segundos, 0::numeric)) OVER (PARTITION BY ot.id) > 0::numeric
            THEN 'tiempo medido'::text
            ELSE 'partes iguales'::text
        END AS base_reparto
   FROM cuadrilla cu
     JOIN ordenes_trabajo ot ON ot.id = cu.ot_id
     JOIN taller_tecnicos t ON t.id = cu.tecnico_id
     LEFT JOIN tiempos ti ON ti.ot_id = cu.ot_id AND ti.tecnico_id = cu.tecnico_id;

-- ── 4 · Desde una cuenta compartida hay que decir quién trabaja ─────────────
CREATE OR REPLACE FUNCTION fn_taller_exigir_tecnico_declarado(p_tecnico_id UUID)
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_tecnico_id IS NOT NULL THEN RETURN; END IF;

    IF EXISTS (SELECT 1 FROM usuarios_cuenta_compartida c WHERE c.usuario_perfil_id = auth.uid()) THEN
        RAISE EXCEPTION 'Estás en la cuenta compartida del taller: elige tu nombre antes de '
                        'empezar. El tiempo que se mide decide el bono, y una cuenta de todos '
                        'no dice quién trabajó.';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION fn_taller_exigir_tecnico_declarado(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_taller_exigir_tecnico_declarado(UUID) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE
    v_n INT; v_seg NUMERIC; r RECORD;
BEGIN
    SELECT count(*) INTO v_n FROM usuarios_cuenta_compartida;
    IF v_n = 0 THEN RAISE EXCEPTION 'FALLO: no se marcó ninguna cuenta compartida'; END IF;
    FOR r IN SELECT up.nombre_completo n, up.rol::text rol
               FROM usuarios_cuenta_compartida c JOIN usuarios_perfil up ON up.id = c.usuario_perfil_id LOOP
        RAISE NOTICE 'cuenta compartida: % [%]', r.n, r.rol;
    END LOOP;

    SELECT count(*) INTO v_n FROM taller_tecnicos t
      JOIN usuarios_cuenta_compartida c ON c.usuario_perfil_id = t.usuario_perfil_id;
    IF v_n > 0 THEN
        RAISE EXCEPTION 'FALLO: % técnicos ya estaban vinculados a una cuenta compartida', v_n;
    END IF;
    RAISE NOTICE 'ningún técnico está vinculado a una cuenta compartida, y ya no se puede';

    -- Cuánto tiempo queda sin dueño hoy. Es la medida del problema de fondo.
    SELECT count(*) FILTER (WHERE tecnico_id IS NULL),
           COALESCE(sum(tiempo_efectivo_segundos) FILTER (WHERE tecnico_id IS NULL), 0)
      INTO v_n, v_seg FROM taller_ot_ejecuciones;
    RAISE NOTICE 'ejecuciones sin técnico declarado: % (% minutos). Reparten en partes iguales.',
        v_n, round(v_seg / 60.0);

    SELECT count(*) INTO v_n FROM v_taller_bono_reparto WHERE base_reparto = 'tiempo medido';
    RAISE NOTICE 'lineas de reparto con tiempo medido de verdad: %', v_n;
END
$mig$;

-- ── 5 · Una cuenta compartida tampoco ve el bono ────────────────────────────
--
-- APARECIÓ AL APLICAR ESTA MISMA MIGRACIÓN, Y ES UNA CONTRADICCIÓN REAL
-- La cuenta compartida del taller tiene rol `jefe_mantenimiento`, que MIG460
-- puso en la lista de quienes ven el bono —porque Manuel pidió que lo viera el
-- jefe de taller—. Pero esa cuenta NO es el jefe de taller: es la que usa todo
-- el taller para entrar y elegir su OT.
--
-- O sea, el candado de MIG460 dejaba el cálculo del bono abierto en el teléfono
-- del piso, que es exactamente lo que se acababa de cerrar.
--
-- El rol dice qué puede hacer un cargo; la cuenta compartida dice que ahí no
-- hay un cargo, hay cualquiera. Manda lo segundo. Para que el jefe de taller
-- vea el bono, necesita su propia cuenta.
CREATE OR REPLACE FUNCTION fn_taller_bono_puede_ver()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM taller_bono_acceso a
         WHERE a.rol = fn_user_rol() AND a.puede_ver
    )
    AND NOT EXISTS (
        SELECT 1 FROM usuarios_cuenta_compartida c WHERE c.usuario_perfil_id = auth.uid()
    );
$$;

-- ── 6 · Iniciar sin decir quién trabaja, desde la cuenta de todos, no ───────
--
-- El cuerpo de MIG448 no se toca: se le pone un envoltorio con el candado. Es
-- lo mismo que se hizo con el cálculo del bono en MIG460. El rename va con
-- guarda para que esta migración se pueda volver a correr sin romperse.
DO $ren$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'rpc_taller_iniciar_ejecucion_ot_base'
    ) THEN
        ALTER FUNCTION rpc_taller_iniciar_ejecucion_ot(UUID, TEXT, UUID)
            RENAME TO rpc_taller_iniciar_ejecucion_ot_base;
    END IF;
END
$ren$;

CREATE OR REPLACE FUNCTION rpc_taller_iniciar_ejecucion_ot(
    p_ot_id       UUID,
    p_observacion TEXT DEFAULT NULL,
    p_tecnico_id  UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_res JSONB;
BEGIN
    -- [MIG461] El tiempo que se mide decide un pago. Desde una cuenta que usa
    -- todo el taller, «quién trabajó» tiene que declararse.
    PERFORM fn_taller_exigir_tecnico_declarado(p_tecnico_id);
    v_res := rpc_taller_iniciar_ejecucion_ot_base(p_ot_id, p_observacion, p_tecnico_id);
    RETURN v_res;
END;
$$;

REVOKE ALL ON FUNCTION rpc_taller_iniciar_ejecucion_ot(UUID, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_iniciar_ejecucion_ot(UUID, TEXT, UUID) TO authenticated;
REVOKE ALL ON FUNCTION rpc_taller_iniciar_ejecucion_ot_base(UUID, TEXT, UUID) FROM PUBLIC, anon, authenticated;

-- ── Verificación de esta parte ──────────────────────────────────────────────
DO $mig2$
DECLARE v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname = 'rpc_taller_iniciar_ejecucion_ot';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: rpc_taller_iniciar_ejecucion_ot quedó con % firmas', v_n; END IF;

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname = 'rpc_taller_iniciar_ejecucion_ot_base'
       AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
    IF v_n <> 0 THEN RAISE EXCEPTION 'FALLO: el cuerpo sin candado quedó alcanzable'; END IF;

    RAISE NOTICE 'iniciar ejecución desde la cuenta compartida ahora exige declarar técnico';
    RAISE NOTICE 'la cuenta compartida ya no ve el cálculo del bono, aunque su rol esté en la lista';
END
$mig2$;

COMMIT;
