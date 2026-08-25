-- ============================================================================
-- MIG392 · El turno de Franke son siete días, y el séptimo se entrega el status
-- ----------------------------------------------------------------------------
-- Franke trabaja 7x7. El sistema ya sabe hacer la pauta diaria y la entrega de
-- turno, pero no sabe en qué día del turno está: cada día empieza igual al
-- anterior y nada avisa que mañana hay que entregar. El séptimo día llega y el
-- status de los camiones se arma de memoria, o no se arma.
--
-- EL CICLO SE CUENTA SOLO
-- Se registra cuándo entró el turno y de ahí en adelante el sistema cuenta:
-- día 1, 2, 3… hasta el 7. Nadie tiene que marcar nada cada mañana — y por eso
-- funciona incluso el día que a nadie se le ocurre marcar nada.
--
-- EL DÍA 7 NO ES UN DÍA MÁS
-- Lleva un objetivo propio: entregar el estado de los equipos al turno que
-- llega. Y ese estado no se escribe a mano: se calcula de lo que ya pasó en los
-- siete días —lo que se hizo, lo que quedó abierto, los litros y el
-- cumplimiento de las pautas—. Un status que hay que redactar termina siendo
-- una frase amable; uno que se calcula, es lo que de verdad ocurrió.
--
-- POR QUÉ NO ES UN CALENDARIO DE TAREAS
-- La tentación es escribir qué toca cada día. Pero en Franke lo que toca cada
-- día es lo mismo —la pauta del camión y la de la camioneta— y lo que cambia es
-- si se hizo o no. Un calendario que repite siete veces la misma lista no
-- ordena nada; lo que ordena es ver los siete días juntos y dónde están los
-- huecos.
--
-- SE APOYA EN LO QUE YA EXISTE
-- No inventa una tabla de tareas: lee `faena_pauta_ejecucion` (MIG357) y
-- `faena_entrega_turno` (MIG362). El ciclo es el hilo que las une.
-- ============================================================================

BEGIN;

-- ── 1. El ciclo ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.faena_ciclo (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id      UUID NOT NULL REFERENCES public.faenas(id),
    numero        INT  NOT NULL,
    turno         TEXT,
    fecha_inicio  DATE NOT NULL,
    dias          INT  NOT NULL DEFAULT 7,
    -- Derivada: con 7 días, el día 1 es el inicio y el 7 es inicio + 6.
    fecha_fin     DATE GENERATED ALWAYS AS (fecha_inicio + (dias - 1)) STORED,
    estado        TEXT NOT NULL DEFAULT 'abierto',
    entrega_id    UUID REFERENCES public.faena_entrega_turno(id),
    observacion   TEXT,
    abierto_por   UUID REFERENCES public.usuarios_perfil(id),
    cerrado_at    TIMESTAMPTZ,
    cerrado_por   UUID REFERENCES public.usuarios_perfil(id),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_faena_ciclo_estado CHECK (estado IN ('abierto', 'cerrado')),
    CONSTRAINT chk_faena_ciclo_dias   CHECK (dias BETWEEN 1 AND 31)
);

-- Un solo ciclo abierto por faena: dos turnos a la vez no existen, y si el
-- sistema los permite alguien va a registrar la pauta en el equivocado.
CREATE UNIQUE INDEX IF NOT EXISTS ux_faena_ciclo_abierto
    ON public.faena_ciclo (faena_id) WHERE estado = 'abierto';

CREATE UNIQUE INDEX IF NOT EXISTS ux_faena_ciclo_numero
    ON public.faena_ciclo (faena_id, numero);

CREATE INDEX IF NOT EXISTS idx_faena_ciclo_fechas
    ON public.faena_ciclo (faena_id, fecha_inicio DESC);

ALTER TABLE public.faena_ciclo ENABLE ROW LEVEL SECURITY;

DO $rls$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                    WHERE schemaname='public' AND tablename='faena_ciclo'
                      AND policyname='faena_ciclo_lectura') THEN
        CREATE POLICY faena_ciclo_lectura ON public.faena_ciclo
            FOR SELECT TO authenticated USING (TRUE);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                    WHERE schemaname='public' AND tablename='faena_ciclo'
                      AND policyname='faena_ciclo_escritura') THEN
        CREATE POLICY faena_ciclo_escritura ON public.faena_ciclo
            FOR ALL TO authenticated
            USING (public.fn_tiene_permiso_modulo('inventario', 'edit',
                     ARRAY['administrador','gerencia','subgerente_operaciones',
                           'jefe_operaciones','supervisor','planificador']))
            WITH CHECK (public.fn_tiene_permiso_modulo('inventario', 'edit',
                     ARRAY['administrador','gerencia','subgerente_operaciones',
                           'jefe_operaciones','supervisor','planificador']));
    END IF;
END
$rls$;

-- ── 2. Abrir el turno ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_faena_ciclo_abrir(
    p_faena_id     uuid,
    p_fecha_inicio date DEFAULT NULL,
    p_turno        text DEFAULT NULL,
    p_dias         int  DEFAULT 7
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_user UUID := auth.uid();
    v_num  INT;
    v_id   UUID;
    v_ini  DATE := COALESCE(p_fecha_inicio, CURRENT_DATE);
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'Sesión requerida.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'Abrir el turno le corresponde al supervisor o a jefatura.'
            USING ERRCODE = '42501';
    END IF;

    -- El anterior se cierra solo al abrir el siguiente: nadie va a acordarse de
    -- cerrar un turno el día que se va a su descanso.
    UPDATE public.faena_ciclo
       SET estado = 'cerrado', cerrado_at = NOW(), cerrado_por = v_user, updated_at = NOW()
     WHERE faena_id = p_faena_id AND estado = 'abierto';

    SELECT COALESCE(MAX(numero), 0) + 1 INTO v_num
      FROM public.faena_ciclo WHERE faena_id = p_faena_id;

    INSERT INTO public.faena_ciclo (faena_id, numero, turno, fecha_inicio, dias, abierto_por)
    VALUES (p_faena_id, v_num, NULLIF(trim(p_turno), ''), v_ini, COALESCE(p_dias, 7), v_user)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', TRUE, 'ciclo_id', v_id, 'numero', v_num,
                              'fecha_inicio', v_ini,
                              'fecha_fin', v_ini + (COALESCE(p_dias, 7) - 1));
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.rpc_faena_ciclo_abrir(uuid, date, text, int) TO authenticated;

-- ── 3. En qué día va, y qué pasó cada día ─────────────────────────────────
-- Devuelve los 7 días con lo que se hizo en cada uno. El día que no tiene nada
-- se ve vacío, que es justamente el dato: ahí faltó la pauta.
CREATE OR REPLACE FUNCTION public.fn_faena_ciclo_calendario(p_faena_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_c    public.faena_ciclo;
    v_dias JSONB := '[]'::jsonb;
    v_d    INT;
    v_f    DATE;
    v_hoy  INT;
BEGIN
    SELECT * INTO v_c FROM public.faena_ciclo
     WHERE faena_id = p_faena_id AND estado = 'abierto'
     ORDER BY fecha_inicio DESC LIMIT 1;

    IF v_c.id IS NULL THEN
        RETURN jsonb_build_object('hay_ciclo', FALSE);
    END IF;

    v_hoy := (CURRENT_DATE - v_c.fecha_inicio) + 1;

    FOR v_d IN 1..v_c.dias LOOP
        v_f := v_c.fecha_inicio + (v_d - 1);
        v_dias := v_dias || jsonb_build_object(
            'dia', v_d,
            'fecha', v_f,
            'es_hoy', v_f = CURRENT_DATE,
            'pasado', v_f < CURRENT_DATE,
            -- El último día lleva el objetivo del turno.
            'entrega_status', v_d = v_c.dias,
            'pautas_hechas', (
                SELECT count(*) FROM public.faena_pauta_ejecucion e
                 WHERE e.faena_id = p_faena_id AND e.fecha = v_f
                   AND e.estado IN ('cerrada', 'completada')),
            'pautas_abiertas', (
                SELECT count(*) FROM public.faena_pauta_ejecucion e
                 WHERE e.faena_id = p_faena_id AND e.fecha = v_f
                   AND e.estado NOT IN ('cerrada', 'completada')),
            'equipos_revisados', (
                SELECT COALESCE(jsonb_agg(DISTINCT COALESCE(a.patente, a.codigo)), '[]'::jsonb)
                  FROM public.faena_pauta_ejecucion e
                  JOIN public.activos a ON a.id = e.activo_id
                 WHERE e.faena_id = p_faena_id AND e.fecha = v_f)
        );
    END LOOP;

    RETURN jsonb_build_object(
        'hay_ciclo', TRUE,
        'ciclo_id', v_c.id,
        'numero', v_c.numero,
        'turno', v_c.turno,
        'fecha_inicio', v_c.fecha_inicio,
        'fecha_fin', v_c.fecha_fin,
        'dias_total', v_c.dias,
        -- Fuera de rango cuando el turno se pasó de largo: se dice, no se
        -- disimula con un número que no significa nada.
        'dia_actual', CASE WHEN v_hoy BETWEEN 1 AND v_c.dias THEN v_hoy END,
        'dias_corridos', v_hoy,
        'es_dia_de_entrega', v_hoy = v_c.dias,
        'vencido', v_hoy > v_c.dias,
        'dias', v_dias);
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.fn_faena_ciclo_calendario(uuid) TO authenticated;

-- ── 4. El status de los camiones ──────────────────────────────────────────
-- No se redacta: se calcula de los siete días. Cuatro cosas, que son las que el
-- turno que llega necesita para no empezar a ciegas.
CREATE OR REPLACE FUNCTION public.fn_faena_status_camiones(
    p_faena_id uuid, p_ciclo_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
    v_c      public.faena_ciclo;
    v_equipos JSONB;
    v_comb   JSONB;
BEGIN
    IF p_ciclo_id IS NOT NULL THEN
        SELECT * INTO v_c FROM public.faena_ciclo WHERE id = p_ciclo_id;
    ELSE
        SELECT * INTO v_c FROM public.faena_ciclo
         WHERE faena_id = p_faena_id AND estado = 'abierto'
         ORDER BY fecha_inicio DESC LIMIT 1;
    END IF;
    IF v_c.id IS NULL THEN
        RETURN jsonb_build_object('hay_ciclo', FALSE);
    END IF;

    -- ══ Equipo por equipo ════════════════════════════════════════════════
    SELECT COALESCE(jsonb_agg(x ORDER BY x->>'patente'), '[]'::jsonb) INTO v_equipos
      FROM (
        SELECT jsonb_build_object(
            'activo_id', a.id,
            'patente',   COALESCE(a.patente, a.codigo),
            'nombre',    a.nombre,
            'estado',    a.estado,
            -- La última lectura del turno, no la de la ficha: la ficha puede
            -- venir de hace un mes.
            'horometro', (SELECT e.horometro FROM public.faena_pauta_ejecucion e
                           WHERE e.activo_id = a.id AND e.faena_id = p_faena_id
                             AND e.fecha BETWEEN v_c.fecha_inicio AND v_c.fecha_fin
                             AND e.horometro IS NOT NULL
                           ORDER BY e.fecha DESC LIMIT 1),
            'kilometraje', (SELECT e.kilometraje FROM public.faena_pauta_ejecucion e
                             WHERE e.activo_id = a.id AND e.faena_id = p_faena_id
                               AND e.fecha BETWEEN v_c.fecha_inicio AND v_c.fecha_fin
                               AND e.kilometraje IS NOT NULL
                             ORDER BY e.fecha DESC LIMIT 1),
            -- Cumplimiento: cuántos de los 7 días tuvo su pauta cerrada.
            'dias_con_pauta', (SELECT count(DISTINCT e.fecha) FROM public.faena_pauta_ejecucion e
                                WHERE e.activo_id = a.id AND e.faena_id = p_faena_id
                                  AND e.fecha BETWEEN v_c.fecha_inicio AND v_c.fecha_fin
                                  AND e.estado IN ('cerrada', 'completada')),
            'dias_del_turno', v_c.dias,
            'nc_abiertas', (SELECT count(*) FROM public.no_conformidades nc
                             WHERE nc.activo_id = a.id AND COALESCE(nc.resuelto, FALSE) = FALSE),
            'nc_detalle', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                                'fecha', nc.fecha_evento,
                                'severidad', nc.severidad,
                                'descripcion', left(COALESCE(nc.descripcion, ''), 140))
                                ORDER BY nc.fecha_evento DESC), '[]'::jsonb)
                             FROM public.no_conformidades nc
                            WHERE nc.activo_id = a.id AND COALESCE(nc.resuelto, FALSE) = FALSE)
        ) AS x
        FROM public.activos a
        WHERE a.faena_id = p_faena_id AND a.fecha_baja IS NULL
      ) t;

    -- ══ Los litros del turno ═════════════════════════════════════════════
    SELECT jsonb_build_object(
        'despachado_lt', COALESCE((SELECT sum(d.litros) FROM public.combustible_faena_despachos d
                                    WHERE d.faena_id = p_faena_id
                                      AND NOT COALESCE(d.anulado, FALSE)
                                      AND d.tipo_movimiento = 'venta'
                                      AND d.fecha BETWEEN v_c.fecha_inicio AND v_c.fecha_fin), 0),
        'recibido_lt',   COALESCE((SELECT sum(r.litros_guia) FROM public.combustible_faena_recepcion r
                                    WHERE r.faena_id = p_faena_id
                                      AND r.fecha BETWEEN v_c.fecha_inicio AND v_c.fecha_fin), 0),
        'estanques', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                    'codigo', e.codigo,
                                    'patente', e.patente,
                                    'stock_lt', e.stock_teorico_lt,
                                    'capacidad_lt', e.capacidad_lt) ORDER BY e.orden_cierre)
                                 FROM public.combustible_estanques e
                                WHERE e.faena_id = p_faena_id AND e.activo), '[]'::jsonb))
      INTO v_comb;

    RETURN jsonb_build_object(
        'hay_ciclo', TRUE,
        'ciclo_id', v_c.id,
        'numero', v_c.numero,
        'turno', v_c.turno,
        'desde', v_c.fecha_inicio,
        'hasta', v_c.fecha_fin,
        'equipos', v_equipos,
        'combustible', v_comb,
        'pautas_del_turno', (SELECT count(*) FROM public.faena_pauta_ejecucion e
                              WHERE e.faena_id = p_faena_id
                                AND e.fecha BETWEEN v_c.fecha_inicio AND v_c.fecha_fin),
        'pautas_cerradas', (SELECT count(*) FROM public.faena_pauta_ejecucion e
                             WHERE e.faena_id = p_faena_id
                               AND e.fecha BETWEEN v_c.fecha_inicio AND v_c.fecha_fin
                               AND e.estado IN ('cerrada', 'completada')),
        'generado_at', NOW());
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.fn_faena_status_camiones(uuid, uuid) TO authenticated;

-- ── 5. El primer ciclo de Franke ──────────────────────────────────────────
-- Se deja abierto para que la faena tenga dónde pararse desde el día uno. La
-- fecha real la corrige el supervisor al abrir el próximo turno.
INSERT INTO public.faena_ciclo (faena_id, numero, turno, fecha_inicio, dias, observacion)
SELECT f.id, 1, 'Turno A', CURRENT_DATE, 7,
       'Primer ciclo, creado en MIG392. Al abrir el siguiente turno se corrige la fecha real de cambio.'
  FROM public.faenas f
 WHERE f.codigo = 'FAE-FRANCKE'
   AND NOT EXISTS (SELECT 1 FROM public.faena_ciclo c WHERE c.faena_id = f.id);

DO $r$
DECLARE v_r JSONB; v_f UUID;
BEGIN
    SELECT id INTO v_f FROM public.faenas WHERE codigo = 'FAE-FRANCKE';
    v_r := public.fn_faena_ciclo_calendario(v_f);
    RAISE NOTICE 'Ciclo % · del % al % · hoy es el día %',
        v_r->>'numero', v_r->>'fecha_inicio', v_r->>'fecha_fin', v_r->>'dia_actual';
    v_r := public.fn_faena_status_camiones(v_f);
    RAISE NOTICE 'El status alcanza a % equipos', jsonb_array_length(v_r->'equipos');
END
$r$;

COMMIT;
