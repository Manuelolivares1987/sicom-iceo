-- ############################################################################
-- MIG306 · Estado 'S' — equipo fuera de control (robo, siniestro, incautación)
-- ----------------------------------------------------------------------------
-- CASO QUE LA MOTIVA: a SPRY-26 (CA-24-02, camioneta Toyota del contrato ESM en
-- Calama) la robaron. Quedó marcada 'F' (fuera de servicio) desde el 5 de
-- agosto, y eso hace tres daños a la vez:
--
--   1. 'F' cuenta como día caído, así que el robo castiga la disponibilidad de
--      la flota y al taller por algo que no controla ni puede reparar.
--   2. Aparece como excepción crítica en el Panel de Gerencia y crece sola
--      —14 días, 21, 28— tapando a los equipos que sí se pueden arreglar.
--   3. Esconde lo que realmente hay que gestionar: denuncia, seguro y contrato.
--      Marcado 'F' se lee como una falla mecánica.
--
-- LA REGLA: un día 'S' NO se cuenta como disponible ni como detenido. Se saca
-- del denominador. No es que el equipo esté bien o mal: es que dejó de ser
-- flota operable, y medir su disponibilidad no significa nada.
--
-- Esto NO es un maquillaje del número: el equipo no desaparece. Sale del cálculo
-- de disponibilidad y entra a un bloque propio del panel ("Fuera de flota"), que
-- lo mantiene a la vista con los días transcurridos y el motivo. Si simplemente
-- se ocultara, en tres meses nadie se acordaría de que hay un seguro abierto.
--
-- POR QUÉ NO SE USÓ UN ESTADO EXISTENTE:
--   · 'F' fuera de servicio → cuenta como caído y además dispara la creación de
--     una OT correctiva y una NC de severidad alta. No hay nada que reparar.
--   · 'D' disponible        → mentira peor: diría que se puede arrendar.
--   · 'V' en venta          → cambia categoría comercial y facturación.
--   · borrar las filas      → se pierde el rastro justo cuando hay un juicio de
--                             seguro de por medio.
--
-- ALCANCE: 'S' se excluye del denominador en TODAS las funciones que calculan
-- disponibilidad, no sólo en el panel —si no, el reporte de fiabilidad que ve
-- el cliente seguiría mostrando el robo como indisponibilidad nuestra—:
--     fn_panel_disponibilidad · fn_panel_equipos_detenidos
--     fn_calcular_fiabilidad_activo · fn_calcular_fiabilidad_flota
--     calcular_oee_activo
-- Y los dos caminos de escritura del estado del día lo aceptan:
--     rpc_actualizar_estado_diario_manual · rpc_confirmar_cierre_diario
--
-- Los cuerpos de esas siete funciones se generaron parcheando la definición
-- VIVA de producción (pg_get_functiondef), no transcribiéndolas: entre las
-- siete suman ~650 líneas tocadas por una docena de migraciones previas.
-- ############################################################################


-- ############################################################################
-- 1. EL CÓDIGO DE ESTADO
-- ############################################################################

-- El CHECK se llama `chk_estado_codigo` desde su creación, no con el nombre
-- que Postgres habría generado solo. Se buscan TODOS los constraints CHECK de
-- la tabla que mencionen estado_codigo y se reemplazan, para no depender del
-- nombre y no dejar dos reglas contradictorias conviviendo.
DO $chk$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT c.conname
          FROM pg_constraint c
         WHERE c.conrelid = 'estado_diario_flota'::regclass
           AND c.contype  = 'c'
           AND pg_get_constraintdef(c.oid) LIKE '%estado_codigo%'
    LOOP
        EXECUTE format('ALTER TABLE estado_diario_flota DROP CONSTRAINT %I', r.conname);
        RAISE NOTICE 'CHECK % eliminado para reemplazo', r.conname;
    END LOOP;
END $chk$;

ALTER TABLE estado_diario_flota
    ADD CONSTRAINT chk_estado_codigo
    CHECK (estado_codigo IN ('A','C','D','H','R','M','T','F','V','U','L','S'));

COMMENT ON COLUMN estado_diario_flota.estado_codigo IS
    'A arrendado · C contrato · D disponible · H habilitación · R recepción · '
    'M mantención · T taller · F fuera de servicio · V venta · U uso interno · '
    'L leasing · S siniestrado/fuera de control (robo, pérdida total, '
    'incautación): NO cuenta en disponibilidad, se excluye del denominador. MIG306.';


-- ############################################################################
-- 2. FUNCIONES PARCHEADAS — 'S' fuera del denominador
-- ############################################################################

-- ── fn_panel_disponibilidad ──
CREATE OR REPLACE FUNCTION public.fn_panel_disponibilidad(p_desde date, p_hasta date, p_operacion text DEFAULT NULL::text)
 RETURNS TABLE(activo_id uuid, codigo text, patente text, nombre text, operacion text, dias_obs integer, dias_up integer, dias_down integer, disponibilidad_pct numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT a.id,
           a.codigo::TEXT,
           a.patente::TEXT,
           a.nombre::TEXT,
           COALESCE(e.operacion, a.operacion)::TEXT,
           count(*)::INTEGER,
           count(*) FILTER (WHERE e.estado_codigo NOT IN ('M','T','F'))::INTEGER,
           count(*) FILTER (WHERE e.estado_codigo IN ('M','T','F'))::INTEGER,
           ROUND(100.0 * count(*) FILTER (WHERE e.estado_codigo NOT IN ('M','T','F'))
                 / NULLIF(count(*), 0), 1)
      FROM estado_diario_flota e
      JOIN activos a ON a.id = e.activo_id
     WHERE e.fecha BETWEEN p_desde AND p_hasta
       AND e.estado_codigo <> 'S'
       AND (p_operacion IS NULL OR COALESCE(e.operacion, a.operacion) = p_operacion)
     GROUP BY a.id, a.codigo, a.patente, a.nombre, COALESCE(e.operacion, a.operacion)
     ORDER BY 9 ASC NULLS LAST, 8 DESC;
$function$;

-- ── fn_panel_equipos_detenidos ──
CREATE OR REPLACE FUNCTION public.fn_panel_equipos_detenidos(p_desde date, p_hasta date, p_operacion text DEFAULT NULL::text, p_limit integer DEFAULT 10, p_semana date DEFAULT NULL::date)
 RETURNS TABLE(activo_id uuid, codigo text, patente text, nombre text, operacion text, dias_detenido integer, dias_obs integer, pct_detenido numeric, estado_actual text, detenido_desde date, dias_consecutivos integer, ot_folio text, ot_estado text, ot_tipo text, comentario text, plan_accion text, responsable text, fecha_compromiso date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    WITH dias AS (
        SELECT e.activo_id,
               e.fecha,
               e.estado_codigo,
               (e.estado_codigo IN ('M','T','F')) AS down
          FROM estado_diario_flota e
          JOIN activos a ON a.id = e.activo_id
         WHERE e.fecha BETWEEN p_desde AND p_hasta
           AND e.estado_codigo <> 'S'
           AND (p_operacion IS NULL OR COALESCE(e.operacion, a.operacion) = p_operacion)
    ),
    agg AS (
        SELECT activo_id,
               count(*)::INTEGER                              AS dias_obs,
               count(*) FILTER (WHERE down)::INTEGER           AS dias_detenido,
               -- Último día NO detenido: lo que venga después es la racha viva.
               max(fecha) FILTER (WHERE NOT down)              AS ultimo_ok,
               max(fecha)                                      AS ultima_fecha,
               (array_agg(estado_codigo ORDER BY fecha DESC))[1] AS estado_actual,
               (array_agg(down          ORDER BY fecha DESC))[1] AS down_actual
          FROM dias
         GROUP BY activo_id
        HAVING count(*) FILTER (WHERE down) > 0
    ),
    ot AS (
        -- OT abierta más reciente por equipo. Lista blanca de estados abiertos.
        SELECT DISTINCT ON (o.activo_id)
               o.activo_id, o.folio::TEXT, o.estado::TEXT, o.tipo::TEXT
          FROM ordenes_trabajo o
         WHERE o.estado::TEXT IN ('creada','asignada','en_ejecucion','pausada')
           AND o.activo_id IS NOT NULL
         ORDER BY o.activo_id, o.created_at DESC
    )
    SELECT a.id,
           a.codigo::TEXT,
           a.patente::TEXT,
           a.nombre::TEXT,
           COALESCE(a.operacion, '—')::TEXT,
           g.dias_detenido,
           g.dias_obs,
           ROUND(100.0 * g.dias_detenido / NULLIF(g.dias_obs, 0), 1),
           g.estado_actual::TEXT,
           CASE WHEN g.down_actual THEN COALESCE(g.ultimo_ok + 1, p_desde) END,
           CASE WHEN g.down_actual
                THEN (g.ultima_fecha - COALESCE(g.ultimo_ok, p_desde - 1))::INTEGER
                ELSE 0 END,
           ot.folio, ot.estado, ot.tipo,
           c.texto, c.plan_accion, c.responsable::TEXT, c.fecha_compromiso
      FROM agg g
      JOIN activos a ON a.id = g.activo_id
      LEFT JOIN ot ON ot.activo_id = g.activo_id
      LEFT JOIN panel_comentarios c
             ON c.ambito    = 'equipo'
            AND c.activo_id = g.activo_id
            AND c.semana    = COALESCE(p_semana, date_trunc('week', p_hasta)::DATE)
     ORDER BY g.dias_detenido DESC, g.dias_obs DESC
     LIMIT GREATEST(p_limit, 1);
$function$;

-- ── fn_calcular_fiabilidad_activo ──
CREATE OR REPLACE FUNCTION public.fn_calcular_fiabilidad_activo(p_activo_id uuid, p_fecha_inicio date, p_fecha_fin date)
 RETURNS TABLE(activo_id uuid, patente character varying, categoria_uso categoria_uso_enum, dias_observados integer, dias_up integer, dias_down integer, eventos_falla integer, mtbf_dias numeric, mttr_dias numeric, disponibilidad_inherente numeric, disponibilidad_fisica numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_total     INTEGER;
    v_down      INTEGER;   -- M,T,F,R,H
    v_mt        INTEGER;   -- M,T (reparación con HH)
    v_up        INTEGER;
    v_eventos   INTEGER;   -- episodios de M/T/F
    v_mtbf      NUMERIC;
    v_mttr      NUMERIC;
    v_disp_inh  NUMERIC;
    v_disp_fis  NUMERIC;
BEGIN
    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE edf.estado_codigo IN ('M','T','F','R','H')),
           COUNT(*) FILTER (WHERE edf.estado_codigo IN ('M','T'))
      INTO v_total, v_down, v_mt
      FROM estado_diario_flota edf
     WHERE edf.activo_id = p_activo_id
       AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin
               AND edf.estado_codigo <> 'S';

    v_up := GREATEST(v_total - v_down, 0);

    SELECT COUNT(DISTINCT grupo)
      INTO v_eventos
      FROM (
        SELECT f,
               SUM(CASE WHEN prev_f IS NULL OR (f - prev_f) > 1 THEN 1 ELSE 0 END)
                 OVER (ORDER BY f) AS grupo
          FROM (
            SELECT edf.fecha AS f,
                   LAG(edf.fecha) OVER (ORDER BY edf.fecha) AS prev_f
              FROM estado_diario_flota edf
             WHERE edf.activo_id = p_activo_id
               AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin
               AND edf.estado_codigo <> 'S'
               AND edf.estado_codigo IN ('M','T','F')
          ) t
      ) grouped;

    IF v_eventos = 0 THEN
        v_mtbf := v_up; v_mttr := 0;
    ELSE
        v_mtbf := ROUND(v_up::NUMERIC / v_eventos, 4);
        v_mttr := ROUND(v_mt::NUMERIC / v_eventos, 4);   -- solo M+T
    END IF;

    IF v_total > 0 THEN
        v_disp_fis := ROUND(v_up::NUMERIC / v_total, 4);
    ELSE
        v_disp_fis := 0;
    END IF;

    -- CONGELADO (en validación): Inherente = Física. La fórmula real sería
    -- v_mtbf/(v_mtbf+v_mttr); se reactiva cambiando solo esta línea.
    v_disp_inh := v_disp_fis;

    RETURN QUERY
    SELECT p_activo_id, a.patente, a.categoria_uso,
           v_total, v_up, v_down, v_eventos,
           v_mtbf, v_mttr, v_disp_inh, v_disp_fis
      FROM activos a
     WHERE a.id = p_activo_id;
END;
$function$;

-- ── fn_calcular_fiabilidad_flota ──
CREATE OR REPLACE FUNCTION public.fn_calcular_fiabilidad_flota(p_fecha_inicio date, p_fecha_fin date, p_categoria categoria_uso_enum DEFAULT NULL::categoria_uso_enum)
 RETURNS TABLE(categoria categoria_uso_enum, total_equipos bigint, dias_equipo bigint, dias_up bigint, dias_down bigint, eventos_falla_total bigint, disponibilidad_fisica numeric, utilizacion_bruta numeric, mtbf_agregado numeric, mttr_agregado numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    WITH base AS (
        SELECT a.id, a.categoria_uso, edf.fecha, edf.estado_codigo
          FROM activos a
          JOIN estado_diario_flota edf ON edf.activo_id = a.id
         WHERE a.estado != 'dado_baja'
           AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
           AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin
           AND edf.estado_codigo <> 'S'
           AND (p_categoria IS NULL OR a.categoria_uso = p_categoria)
    ),
    por_activo AS (
        SELECT id, categoria_uso,
               COUNT(*) AS dias_obs,
               COUNT(*) FILTER (WHERE estado_codigo IN ('M','T','F','R','H')) AS dias_dn,
               COUNT(*) FILTER (WHERE estado_codigo NOT IN ('M','T','F','R','H')) AS dias_ok,
               COUNT(*) FILTER (WHERE estado_codigo IN ('M','T')) AS dias_mt,
               COUNT(*) FILTER (WHERE estado_codigo IN ('A','L','C')) AS dias_util
          FROM base
         GROUP BY id, categoria_uso
    ),
    eventos_por_activo AS (
        SELECT id, categoria_uso, COUNT(DISTINCT grupo) AS eventos
          FROM (
            SELECT id, categoria_uso, fecha,
                   SUM(CASE WHEN prev_fecha IS NULL OR (fecha - prev_fecha) > 1 THEN 1 ELSE 0 END)
                     OVER (PARTITION BY id ORDER BY fecha) AS grupo
              FROM (
                SELECT id, categoria_uso, fecha,
                       LAG(fecha) OVER (PARTITION BY id ORDER BY fecha) AS prev_fecha
                  FROM base
                 WHERE estado_codigo IN ('M','T','F')
              ) t
          ) g
         GROUP BY id, categoria_uso
    ),
    combinado AS (
        SELECT pa.categoria_uso, pa.id, pa.dias_obs, pa.dias_ok, pa.dias_dn,
               pa.dias_mt, pa.dias_util, COALESCE(ep.eventos, 0) AS eventos
          FROM por_activo pa
          LEFT JOIN eventos_por_activo ep ON ep.id = pa.id
    )
    SELECT c.categoria_uso,
           COUNT(DISTINCT c.id)::BIGINT AS total_equipos,
           SUM(c.dias_obs)::BIGINT AS dias_equipo,
           SUM(c.dias_ok)::BIGINT AS dias_up,
           SUM(c.dias_dn)::BIGINT AS dias_down,
           SUM(c.eventos)::BIGINT AS eventos_falla_total,
           ROUND(CASE WHEN SUM(c.dias_obs) > 0 THEN SUM(c.dias_ok)::NUMERIC / SUM(c.dias_obs) ELSE 0 END, 4) AS disponibilidad_fisica,
           ROUND(CASE WHEN SUM(c.dias_obs) > 0 THEN SUM(c.dias_util)::NUMERIC / SUM(c.dias_obs) ELSE 0 END, 4) AS utilizacion_bruta,
           ROUND(CASE WHEN SUM(c.eventos) > 0 THEN SUM(c.dias_ok)::NUMERIC / SUM(c.eventos) ELSE SUM(c.dias_ok) END, 4) AS mtbf_agregado,
           ROUND(CASE WHEN SUM(c.eventos) > 0 THEN SUM(c.dias_mt)::NUMERIC / SUM(c.eventos) ELSE 0 END, 4) AS mttr_agregado
      FROM combinado c
     GROUP BY c.categoria_uso
     ORDER BY c.categoria_uso;
END;
$function$;

-- ── calcular_oee_activo ──
CREATE OR REPLACE FUNCTION public.calcular_oee_activo(p_activo_id uuid, p_fecha_inicio date, p_fecha_fin date)
 RETURNS TABLE(activo_id uuid, patente character varying, disponibilidad_mecanica numeric, utilizacion_operativa numeric, calidad_servicio numeric, oee numeric, dias_periodo integer, dias_operativos integer, dias_mantencion integer, dias_fuera_servicio integer, horas_productivas numeric, horas_disponibles numeric, servicios_totales bigint, servicios_no_conformes bigint)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_dias_periodo INTEGER;
    v_dias_operativos INTEGER;
    v_dias_no_disponibles INTEGER;
    v_horas_productivas NUMERIC;
    v_horas_disponibles NUMERIC;
    v_servicios_totales BIGINT;
    v_servicios_nc BIGINT;
    v_disponibilidad NUMERIC;
    v_utilizacion NUMERIC;
    v_calidad NUMERIC;
    v_oee NUMERIC;
    v_dias_mant INTEGER;
    v_dias_fs INTEGER;
BEGIN
    v_dias_periodo := (p_fecha_fin - p_fecha_inicio) + 1;

    -- Contar días por estado desde estado_diario_flota
    SELECT
        COALESCE(COUNT(*) FILTER (WHERE edf.estado_codigo IN ('M','T')), 0),
        COALESCE(COUNT(*) FILTER (WHERE edf.estado_codigo = 'F'), 0),
        COALESCE(COUNT(*) FILTER (WHERE edf.estado_codigo NOT IN ('M','T','F','H')), 0),
        COALESCE(SUM(edf.horas_operativas), 0),
        COALESCE(SUM(edf.horas_disponibles), 0)
    INTO v_dias_mant, v_dias_fs, v_dias_operativos, v_horas_productivas, v_horas_disponibles
    FROM estado_diario_flota edf
    WHERE edf.activo_id = p_activo_id
      AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin
          AND edf.estado_codigo <> 'S';

    v_dias_no_disponibles := v_dias_mant + v_dias_fs;

    -- Disponibilidad Mecánica = (Días periodo - Días no disponibles) / Días periodo
    IF v_dias_periodo > 0 THEN
        v_disponibilidad := ROUND(
            ((v_dias_periodo - v_dias_no_disponibles)::NUMERIC / v_dias_periodo) * 100, 2
        );
    ELSE
        v_disponibilidad := 0;
    END IF;

    -- Utilización Operativa = Horas productivas / Horas disponibles
    IF v_horas_disponibles > 0 THEN
        v_utilizacion := ROUND((v_horas_productivas / v_horas_disponibles) * 100, 2);
    ELSE
        -- Fallback: usar días arrendados/leasing/uso_interno como proxy
        SELECT COALESCE(COUNT(*) FILTER (WHERE edf.estado_codigo IN ('A','U','L')), 0)
        INTO v_dias_operativos
        FROM estado_diario_flota edf
        WHERE edf.activo_id = p_activo_id
          AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin
          AND edf.estado_codigo <> 'S';

        IF (v_dias_periodo - v_dias_no_disponibles) > 0 THEN
            v_utilizacion := ROUND(
                (v_dias_operativos::NUMERIC / (v_dias_periodo - v_dias_no_disponibles)) * 100, 2
            );
        ELSE
            v_utilizacion := 0;
        END IF;
    END IF;

    -- Calidad de Servicio = (Servicios totales - No conformidades) / Servicios totales
    -- Servicios = días que el equipo estuvo en operación (A, U, L)
    SELECT COUNT(*)
    INTO v_servicios_totales
    FROM estado_diario_flota edf
    WHERE edf.activo_id = p_activo_id
      AND edf.fecha BETWEEN p_fecha_inicio AND p_fecha_fin
          AND edf.estado_codigo <> 'S'
      AND edf.estado_codigo IN ('A', 'U', 'L');

    SELECT COUNT(*)
    INTO v_servicios_nc
    FROM no_conformidades nc
    WHERE nc.activo_id = p_activo_id
      AND nc.fecha_evento BETWEEN p_fecha_inicio AND p_fecha_fin;

    IF v_servicios_totales > 0 THEN
        v_calidad := ROUND(
            (GREATEST(v_servicios_totales - v_servicios_nc, 0)::NUMERIC / v_servicios_totales) * 100, 2
        );
    ELSE
        v_calidad := 100;  -- Sin servicios, no hay no conformidades
    END IF;

    -- OEE = Disponibilidad × Utilización × Calidad (como porcentaje 0-100)
    v_oee := ROUND((v_disponibilidad / 100) * (v_utilizacion / 100) * (v_calidad / 100) * 100, 2);

    RETURN QUERY SELECT
        p_activo_id,
        a.patente,
        v_disponibilidad,
        v_utilizacion,
        v_calidad,
        v_oee,
        v_dias_periodo,
        v_dias_operativos,
        v_dias_mant,
        v_dias_fs,
        v_horas_productivas,
        v_horas_disponibles,
        v_servicios_totales,
        v_servicios_nc
    FROM activos a
    WHERE a.id = p_activo_id;
END;
$function$;

-- ── rpc_actualizar_estado_diario_manual ──
CREATE OR REPLACE FUNCTION public.rpc_actualizar_estado_diario_manual(p_activo_id uuid, p_fecha date, p_nuevo_estado character, p_motivo text, p_crear_ot boolean DEFAULT false, p_ot_tipo tipo_ot_enum DEFAULT NULL::tipo_ot_enum, p_ot_prioridad prioridad_enum DEFAULT 'normal'::prioridad_enum, p_ot_responsable_id uuid DEFAULT NULL::uuid, p_ot_descripcion text DEFAULT NULL::text, p_ubicacion character varying DEFAULT NULL::character varying)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_user_id            UUID;
    v_activo             RECORD;
    v_ot_id              UUID;
    v_ot_folio           VARCHAR(20);
    v_ot_estado_inicial  estado_ot_enum;
    v_ot_contrato_id     UUID;
    v_ot_faena_id        UUID;
    v_ot_error           TEXT;
    v_periodo            VARCHAR(6);
    v_secuencia          INTEGER;
    v_existente          UUID;
    v_nuevo_estado_act   estado_activo_enum;
    v_nuevo_estado_com   estado_comercial_enum;
    v_nueva_categoria    categoria_uso_enum;
BEGIN
    -- 1. AUTH
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;

    -- 2. VALIDAR CÓDIGO  (NUEVO: 'C' = Contrato / arriendo de largo plazo)
    IF p_nuevo_estado NOT IN ('A','C','D','H','R','M','T','F','V','U','L','S') THEN
        RAISE EXCEPTION 'Estado código inválido: %', p_nuevo_estado;
    END IF;

    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id;
    END IF;

    -- 2b. LUGAR FÍSICO (texto libre) ANTES del cambio de estado.
    IF p_ubicacion IS NOT NULL AND length(trim(p_ubicacion)) > 0 THEN
        UPDATE activos SET ubicacion_actual = trim(p_ubicacion), updated_at = NOW()
         WHERE id = p_activo_id;
        v_activo.ubicacion_actual := trim(p_ubicacion);
    END IF;

    -- 3. CREAR OT AUTOMÁTICA (M, T, F)
    IF p_crear_ot AND p_nuevo_estado IN ('M','T','F') THEN
        IF p_ot_tipo IS NULL THEN
            p_ot_tipo := CASE
                WHEN p_nuevo_estado = 'T' THEN 'correctivo'
                WHEN p_nuevo_estado = 'F' THEN 'correctivo'
                ELSE 'preventivo'
            END;
        END IF;

        v_ot_contrato_id := COALESCE(v_activo.contrato_id, fn_contrato_interno_id());
        v_ot_faena_id    := COALESCE(v_activo.faena_id,    fn_faena_interna_id());

        v_ot_estado_inicial := CASE
            WHEN p_ot_responsable_id IS NOT NULL THEN 'asignada'::estado_ot_enum
            ELSE 'creada'::estado_ot_enum
        END;

        PERFORM pg_advisory_xact_lock(hashtext('ot_folio_lock'));

        v_periodo := TO_CHAR(NOW(), 'YYYYMM');
        SELECT COALESCE(MAX(
            CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)
        ), 0) + 1
        INTO v_secuencia
        FROM ordenes_trabajo
        WHERE folio LIKE 'OT-' || v_periodo || '-%';

        v_ot_folio := 'OT-' || v_periodo || '-' || LPAD(v_secuencia::TEXT, 5, '0');

        BEGIN
            INSERT INTO ordenes_trabajo (
                folio, tipo, contrato_id, faena_id, activo_id,
                prioridad, estado, responsable_id,
                fecha_programada, observaciones,
                generada_automaticamente, created_by
            ) VALUES (
                v_ot_folio, p_ot_tipo,
                v_ot_contrato_id, v_ot_faena_id, p_activo_id,
                p_ot_prioridad, v_ot_estado_inicial, p_ot_responsable_id,
                p_fecha, COALESCE(p_ot_descripcion, p_motivo),
                true, v_user_id
            )
            RETURNING id INTO v_ot_id;
        EXCEPTION WHEN OTHERS THEN
            v_ot_error := SQLERRM;
            v_ot_id := NULL;
            v_ot_folio := NULL;
        END;
    END IF;

    -- 4. UPSERT estado_diario_flota
    SELECT id INTO v_existente
    FROM estado_diario_flota
    WHERE activo_id = p_activo_id AND fecha = p_fecha;

    IF v_existente IS NULL THEN
        INSERT INTO estado_diario_flota (
            activo_id, fecha, contrato_id, estado_codigo,
            cliente, ubicacion, operacion,
            override_manual, motivo_override, calculado_auto,
            actualizado_por, actualizado_at,
            ot_relacionada_id, observacion, registrado_por
        ) VALUES (
            p_activo_id, p_fecha, v_activo.contrato_id, p_nuevo_estado,
            v_activo.cliente_actual, v_activo.ubicacion_actual, v_activo.operacion,
            true, p_motivo, false,
            v_user_id, NOW(),
            v_ot_id, p_motivo, v_user_id
        );
    ELSE
        UPDATE estado_diario_flota
        SET estado_codigo     = p_nuevo_estado,
            ubicacion         = COALESCE(v_activo.ubicacion_actual, ubicacion),
            override_manual   = true,
            motivo_override   = p_motivo,
            actualizado_por   = v_user_id,
            actualizado_at    = NOW(),
            ot_relacionada_id = COALESCE(v_ot_id, ot_relacionada_id),
            observacion       = p_motivo,
            updated_at        = NOW()
        WHERE id = v_existente;
    END IF;

    -- 5. SINCRONIZAR activos.estado + estado_comercial + categoria_uso
    v_nuevo_estado_act := CASE p_nuevo_estado
        WHEN 'M' THEN 'en_mantenimiento'::estado_activo_enum
        WHEN 'T' THEN 'en_mantenimiento'::estado_activo_enum
        WHEN 'H' THEN 'en_mantenimiento'::estado_activo_enum
        WHEN 'F' THEN 'fuera_servicio'::estado_activo_enum
        WHEN 'S' THEN 'fuera_servicio'::estado_activo_enum
        ELSE        'operativo'::estado_activo_enum
    END;

    v_nuevo_estado_com := CASE p_nuevo_estado
        WHEN 'A' THEN 'arrendado'::estado_comercial_enum
        WHEN 'C' THEN 'arrendado'::estado_comercial_enum   -- NUEVO: Contrato = arrendado
        WHEN 'D' THEN 'disponible'::estado_comercial_enum
        WHEN 'U' THEN 'uso_interno'::estado_comercial_enum
        WHEN 'L' THEN 'leasing'::estado_comercial_enum
        WHEN 'R' THEN 'en_recepcion'::estado_comercial_enum
        WHEN 'V' THEN 'en_venta'::estado_comercial_enum
        WHEN 'H' THEN NULL
        ELSE v_activo.estado_comercial
    END;

    -- Categoría comercial. Solo estados comerciales la definen; los transitorios
    -- (D,H,R,M,T,F) la dejan como está.
    v_nueva_categoria := CASE p_nuevo_estado
        WHEN 'A' THEN 'arriendo_comercial'::categoria_uso_enum
        WHEN 'C' THEN 'arriendo_comercial'::categoria_uso_enum   -- NUEVO
        WHEN 'L' THEN 'leasing_operativo'::categoria_uso_enum
        WHEN 'U' THEN 'uso_interno'::categoria_uso_enum
        WHEN 'V' THEN 'venta'::categoria_uso_enum
        ELSE NULL
    END;

    UPDATE activos
    SET estado           = v_nuevo_estado_act,
        estado_comercial = v_nuevo_estado_com,
        categoria_uso    = COALESCE(v_nueva_categoria, categoria_uso),
        updated_at       = NOW()
    WHERE id = p_activo_id;

    -- 6. NO CONFORMIDAD F+arrendado (protegida)
    IF p_nuevo_estado = 'F' AND v_activo.estado_comercial = 'arrendado' THEN
        BEGIN
            INSERT INTO no_conformidades (
                activo_id, fecha_evento, tipo, severidad, descripcion, created_by
            ) VALUES (
                p_activo_id, p_fecha, 'falla_en_terreno', 'alta',
                'Equipo arrendado pasa a fuera de servicio: ' || COALESCE(p_motivo,'sin motivo'),
                v_user_id
            )
            ON CONFLICT DO NOTHING;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;

    -- 7. RESULTADO
    RETURN jsonb_build_object(
        'success',           true,
        'estado_aplicado',   p_nuevo_estado,
        'activo_estado',     v_nuevo_estado_act,
        'activo_comercial',  v_nuevo_estado_com,
        'activo_categoria',  COALESCE(v_nueva_categoria, v_activo.categoria_uso),
        'ot_creada',         v_ot_id IS NOT NULL,
        'ot_id',             v_ot_id,
        'ot_folio',          v_ot_folio,
        'ot_estado_inicial', v_ot_estado_inicial,
        'ot_error',          v_ot_error
    );
END;
$function$;

-- ── rpc_confirmar_cierre_diario ──
CREATE OR REPLACE FUNCTION public.rpc_confirmar_cierre_diario(p_fecha date, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user      UUID := auth.uid();
    v_item      JSONB;
    v_activo    UUID;
    v_estado    CHAR(1);
    v_contrato  UUID;
    v_cliente   VARCHAR;
    v_estado_com estado_comercial_enum;
    v_n         INTEGER := 0;
BEGIN
    -- Autorización (MIG185): sesión + permiso approve sobre módulo flota.
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;
    -- Fail-closed (rev. gate): SIN fallback amplio. Cierre diario = admin-only por
    -- defecto (reescribe toda la flota). Supervisores u otros roles se habilitan
    -- SOLO con override explícito en Admin (rol_permisos_modulo, MIG126) tras
    -- ratificación individual. Alinea con rpc_confirmar_estado_dia (flota/approve).
    IF NOT public.fn_tiene_permiso_modulo(
        'flota', 'approve',
        ARRAY['administrador']
    ) THEN
        RAISE EXCEPTION 'No autorizado para confirmar el cierre diario de flota.';
    END IF;

    IF p_fecha IS NULL THEN
        RAISE EXCEPTION 'p_fecha es obligatoria';
    END IF;
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
        RAISE EXCEPTION 'p_items debe ser un arreglo JSON';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_activo   := (v_item->>'activo_id')::uuid;
        v_estado   := upper(v_item->>'estado_codigo')::char(1);
        v_contrato := NULLIF(v_item->>'contrato_id', '')::uuid;

        IF v_estado NOT IN ('A','C','D','H','R','M','T','F','V','U','L','S') THEN
            RAISE EXCEPTION 'Estado invalido % para activo %', v_estado, v_activo;
        END IF;

        -- Activo debe existir y no estar dado de baja: rechaza el lote completo
        -- (la transacción revierte todo → sin cambios parciales).
        PERFORM 1 FROM public.activos WHERE id = v_activo AND estado <> 'dado_baja';
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Activo % inexistente o dado de baja; cierre rechazado completo.', v_activo;
        END IF;
        -- Contrato, si viene, debe existir.
        IF v_contrato IS NOT NULL THEN
            PERFORM 1 FROM public.contratos WHERE id = v_contrato;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Contrato % inexistente; cierre rechazado completo.', v_contrato;
            END IF;
        END IF;

        -- Cliente: del contrato si viene; si no, el actual del activo
        v_cliente := NULL;
        IF v_contrato IS NOT NULL THEN
            SELECT cliente INTO v_cliente FROM public.contratos WHERE id = v_contrato;
        END IF;
        IF v_cliente IS NULL THEN
            SELECT cliente_actual INTO v_cliente FROM public.activos WHERE id = v_activo;
        END IF;

        -- Upsert del estado del dia (congelado como cierre)
        INSERT INTO public.estado_diario_flota (
            activo_id, fecha, contrato_id, estado_codigo, cliente,
            override_manual, motivo_override, calculado_auto,
            actualizado_por, actualizado_at, registrado_por, observacion
        ) VALUES (
            v_activo, p_fecha, v_contrato, v_estado, v_cliente,
            true, 'Cierre diario de flota', false,
            v_user, now(), v_user, 'Cierre diario confirmado'
        )
        ON CONFLICT (activo_id, fecha) DO UPDATE SET
            estado_codigo   = EXCLUDED.estado_codigo,
            contrato_id     = EXCLUDED.contrato_id,
            cliente         = EXCLUDED.cliente,
            override_manual = true,
            motivo_override = 'Cierre diario de flota',
            calculado_auto  = false,
            actualizado_por = EXCLUDED.actualizado_por,
            actualizado_at  = now(),
            updated_at      = now();

        -- Reverse-map a estado_comercial (solo codigos comerciales;
        -- M/T/F/H no cambian el comercial: un equipo arrendado en taller
        -- sigue comercialmente arrendado).
        v_estado_com := (CASE v_estado
            WHEN 'A' THEN 'arrendado'
            WHEN 'C' THEN 'arrendado'
            WHEN 'D' THEN 'disponible'
            WHEN 'U' THEN 'uso_interno'
            WHEN 'L' THEN 'leasing'
            WHEN 'R' THEN 'en_recepcion'
            WHEN 'V' THEN 'en_venta'
            ELSE NULL
        END)::estado_comercial_enum;

        -- Propagar a activos: contrato siempre; comercial + cliente solo si mapea
        UPDATE public.activos SET
            contrato_id      = v_contrato,
            estado_comercial = COALESCE(v_estado_com, estado_comercial),
            cliente_actual   = CASE WHEN v_estado_com IS NOT NULL THEN v_cliente
                                    ELSE cliente_actual END,
            updated_at       = now()
        WHERE id = v_activo;

        v_n := v_n + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'fecha', p_fecha, 'confirmados', v_n);
END $function$;


-- ############################################################################
-- 3. BLOQUE "FUERA DE FLOTA" DEL PANEL
-- ----------------------------------------------------------------------------
-- Lo que se saca del cálculo tiene que quedar a la vista en otra parte, o el
-- panel pasa de mentir por exceso a mentir por omisión. Este bloque responde
-- "¿qué equipos ya no son flota, desde cuándo y por qué?".
-- ############################################################################

DROP FUNCTION IF EXISTS fn_panel_fuera_de_flota(DATE, DATE);
CREATE FUNCTION fn_panel_fuera_de_flota(
    p_desde DATE,
    p_hasta DATE
)
RETURNS TABLE (
    activo_id       UUID,
    codigo          TEXT,
    patente         TEXT,
    nombre          TEXT,
    operacion       TEXT,
    desde           DATE,
    dias            INTEGER,
    dias_en_periodo INTEGER,
    motivo          TEXT,
    cliente_actual  TEXT,
    contrato_activo BOOLEAN
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    WITH s AS (
        SELECT e.activo_id,
               min(e.fecha)                            AS desde,
               count(*) FILTER (
                   WHERE e.fecha BETWEEN p_desde AND p_hasta)::INTEGER AS dias_periodo,
               count(*)::INTEGER                        AS dias_total,
               -- El motivo se escribe una vez, al marcar el estado; después los
               -- días siguientes vienen sin observación. Se toma el primero que
               -- exista, no el del último día.
               (array_agg(e.observacion ORDER BY e.fecha)
                  FILTER (WHERE e.observacion IS NOT NULL))[1] AS motivo
          FROM estado_diario_flota e
         WHERE e.estado_codigo = 'S'
         GROUP BY e.activo_id
    )
    SELECT a.id,
           a.codigo::TEXT,
           a.patente::TEXT,
           a.nombre::TEXT,
           COALESCE(a.operacion, '—')::TEXT,
           s.desde,
           s.dias_total,
           s.dias_periodo,
           s.motivo,
           a.cliente_actual::TEXT,
           (a.contrato_id IS NOT NULL)
      FROM s
      JOIN activos a ON a.id = s.activo_id
     -- Sólo lo que sigue fuera de control hoy: si volvió y se le cambió el
     -- estado, deja de ser noticia de gerencia.
     WHERE s.dias_periodo > 0
     ORDER BY s.desde ASC;
$$;

GRANT EXECUTE ON FUNCTION fn_panel_fuera_de_flota(DATE, DATE) TO authenticated;

COMMENT ON FUNCTION fn_panel_fuera_de_flota(DATE, DATE) IS
    'Equipos en estado S (robo/siniestro/incautación): excluidos del cálculo de '
    'disponibilidad pero visibles, con días transcurridos y motivo. MIG306.';


-- ############################################################################
-- 4. fn_panel_gerencia — se le cuelga el bloque
-- ############################################################################

CREATE OR REPLACE FUNCTION fn_panel_gerencia(p_semana DATE DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_semana     DATE;
    v_sem_fin    DATE;
    v_mes_ini    DATE;
    v_mes_fin    DATE;
    v_hoy        DATE := CURRENT_DATE;
    v_resultado  JSONB;
BEGIN
    IF NOT fn_panel_gerencia_puede_ver() THEN
        RAISE EXCEPTION 'No autorizado para ver el Panel de Gerencia.'
            USING ERRCODE = '42501';
    END IF;

    v_semana  := date_trunc('week', COALESCE(p_semana, v_hoy))::DATE;
    v_sem_fin := v_semana + 6;
    v_mes_ini := date_trunc('month', v_semana)::DATE;
    v_mes_fin := LEAST((v_mes_ini + INTERVAL '1 month - 1 day')::DATE, v_hoy);

    SELECT jsonb_build_object(
        'semana',        jsonb_build_object(
            'inicio', v_semana, 'fin', v_sem_fin,
            'mes_inicio', v_mes_ini, 'mes_fin', v_mes_fin,
            'generado_at', NOW()
        ),
        'calidad_dato',  fn_panel_calidad_dato(v_mes_ini, v_mes_fin),

        -- ── PORTADA (MIG305) ────────────────────────────────────────────────
        'resumen',       fn_panel_resumen(v_semana, v_mes_ini, v_mes_fin),
        'excepciones',   (SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.orden,
                                                    x.impacto_clp DESC NULLS LAST,
                                                    x.titulo), '[]'::JSONB)
                            FROM fn_panel_excepciones(v_semana, v_mes_ini, v_mes_fin) x),
        'compromisos',   (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::JSONB)
                            FROM fn_panel_compromisos(v_semana) x),

        -- ── FUERA DE FLOTA (MIG306) ─────────────────────────────────────────
        -- Lo que se excluyó del cálculo, para que no desaparezca sin más.
        'fuera_de_flota',(SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::JSONB)
                            FROM fn_panel_fuera_de_flota(v_mes_ini, v_mes_fin) x),

        -- ── CUADRANTE COQUIMBO ──────────────────────────────────────────────
        'coquimbo', jsonb_build_object(
            'taller',       fn_panel_taller(v_mes_ini, v_mes_fin, 'Coquimbo'),
            'combustible',  fn_panel_combustible_coquimbo(v_mes_ini, v_mes_fin),
            'disponibilidad', jsonb_build_object(
                'equipos',   (SELECT count(*) FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Coquimbo')),
                'promedio',  (SELECT ROUND(100.0 * SUM(dias_up) / NULLIF(SUM(dias_obs), 0), 1)
                                FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Coquimbo')),
                'bajo_90',   (SELECT count(*) FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Coquimbo')
                               WHERE disponibilidad_pct < 90),
                'detalle',   (SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]'::JSONB)
                                FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Coquimbo') d)
            ),
            'detenidos',    (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::JSONB)
                               FROM fn_panel_equipos_detenidos(v_mes_ini, v_mes_fin, 'Coquimbo', 10, v_semana) x),
            'comentario',   (SELECT to_jsonb(c) FROM panel_comentarios c
                              WHERE c.ambito = 'cuadrante' AND c.cuadrante = 'coquimbo'
                                AND c.semana = v_semana)
        ),

        -- ── CUADRANTE CALAMA ────────────────────────────────────────────────
        'calama', jsonb_build_object(
            'faenas',      (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::JSONB)
                              FROM fn_panel_calama_enex(
                                     EXTRACT(YEAR  FROM v_semana)::INTEGER,
                                     EXTRACT(MONTH FROM v_semana)::INTEGER,
                                     v_semana) x),
            'facturacion_total', (SELECT SUM(facturacion_mensual_clp) FROM enex_faenas WHERE activo),
            'faenas_sin_plan',   (SELECT count(*) FROM fn_panel_calama_enex(
                                     EXTRACT(YEAR  FROM v_semana)::INTEGER,
                                     EXTRACT(MONTH FROM v_semana)::INTEGER,
                                     v_semana) WHERE sin_plan),
            'taller',      fn_panel_taller(v_mes_ini, v_mes_fin, 'Calama'),
            'disponibilidad', jsonb_build_object(
                'equipos',  (SELECT count(*) FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Calama')),
                'promedio', (SELECT ROUND(100.0 * SUM(dias_up) / NULLIF(SUM(dias_obs), 0), 1)
                               FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Calama')),
                'bajo_90',  (SELECT count(*) FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Calama')
                              WHERE disponibilidad_pct < 90),
                'detalle',  (SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]'::JSONB)
                               FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Calama') d)
            ),
            'detenidos',   (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::JSONB)
                              FROM fn_panel_equipos_detenidos(v_mes_ini, v_mes_fin, 'Calama', 5, v_semana) x),
            'comentario',  (SELECT to_jsonb(c) FROM panel_comentarios c
                             WHERE c.ambito = 'cuadrante' AND c.cuadrante = 'calama'
                               AND c.semana = v_semana)
        ),

        'comentario_semana', (SELECT to_jsonb(c) FROM panel_comentarios c
                               WHERE c.ambito = 'semana' AND c.semana = v_semana)
    ) INTO v_resultado;

    RETURN v_resultado;
END $$;

GRANT EXECUTE ON FUNCTION fn_panel_gerencia(DATE) TO authenticated;

COMMENT ON FUNCTION fn_panel_gerencia(DATE) IS
    'Panel de Gerencia completo en una llamada: portada (resumen + excepciones + '
    'compromisos + fuera de flota) y detalle por cuadrante. MIG295, ampliado en '
    'MIG305 y MIG306.';


-- ############################################################################
-- 5. CORRECCIÓN DE DATOS — SPRY-26
-- ----------------------------------------------------------------------------
-- Robo confirmado. Primer día sin el vehículo: 2026-08-05, que es también el
-- primer día que el planificador marcó 'F'. Se reescriben SÓLO los días 'F'
-- de ese equipo desde esa fecha: si algún día quedó en otro estado, no se toca.
--
-- Decisión de Manuel (2026-08-18): el equipo SIGUE asociado al contrato ESM
-- hasta que responda el seguro. No se toca cliente_actual, estado_comercial ni
-- facturación; sólo deja de contarse como flota operable.
-- ############################################################################

DO $fix$
DECLARE
    v_id      UUID;
    v_desde   DATE := DATE '2026-08-05';
    v_filas   INTEGER;
    v_motivo  TEXT := 'Robo del vehículo. Denuncia y seguro en curso. '
                   || 'No cuenta en disponibilidad (MIG306): no es una falla '
                   || 'de mantenimiento y no hay nada que reparar.';
BEGIN
    SELECT id INTO v_id FROM activos WHERE patente = 'SPRY-26';

    IF v_id IS NULL THEN
        RAISE NOTICE 'SPRY-26 no existe; no hay nada que corregir.';
        RETURN;
    END IF;

    UPDATE estado_diario_flota
       SET estado_codigo   = 'S',
           observacion     = COALESCE(observacion, v_motivo),
           override_manual = TRUE,
           motivo_override = v_motivo,
           actualizado_at  = NOW()
     WHERE activo_id = v_id
       AND fecha >= v_desde
       AND estado_codigo = 'F';

    GET DIAGNOSTICS v_filas = ROW_COUNT;
    RAISE NOTICE 'SPRY-26: % días reclasificados de F a S desde %', v_filas, v_desde;

    -- El activo queda fuera de servicio (no está operativo) pero conserva su
    -- contrato y su cliente: la relación comercial se resuelve con el seguro,
    -- no con un cambio de estado.
    UPDATE activos
       SET estado     = 'fuera_servicio',
           notas      = COALESCE(NULLIF(btrim(notas), '') || E'\n', '')
                        || '[2026-08-05] ' || v_motivo,
           updated_at = NOW()
     WHERE id = v_id
       AND estado <> 'fuera_servicio';
END $fix$;
