-- 676 — Menos ruido en la campanita + un resumen diario (Manuel 08-11-2026, benchmark MaintainX).
--
-- En 30 días: 2.791 alertas y 128 leídas (4,6 %). La campanita era ruido:
--   * no_conformidad: 855 alertas para 45 NC. Cada NO OK del checklist mandaba UNA alerta a
--     CADA uno de los 19 usuarios de jefatura (un checklist con 12 NO OK = 228 avisos).
--   * stock_minimo: 1.035 alertas SIN destinatario: nadie las veía (la campanita filtra por
--     destinatario). Sólo engordaban la tabla.
-- Ahora:
--   1. NC: una alerta por EQUIPO, por día y por persona («RSCY-85: 12 NC nuevas hoy»). Si ya
--      hay una sin leer de hoy para ese equipo, se actualiza el conteo en vez de crear otra.
--   2. stock_minimo deja de insertar filas sin destinatario; va en el resumen diario.
--   3. fn_resumen_diario_cron(p_secreto): lo que pide acción, en un correo al día
--      (/api/notificaciones/resumen-diario, cron 'resumen-diario' lun-sáb 08:00 Chile).

-- ── 1. NC agrupadas por equipo y día ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_nc_crear_alertas()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_patente TEXT;
    v_sev     TEXT;
    v_n       INT;
    v_obs     INT;
    v_titulo  TEXT;
    v_msg     TEXT;
    v_u       RECORD;
BEGIN
    SELECT COALESCE(a.patente, a.codigo) INTO v_patente FROM activos a WHERE a.id = NEW.activo_id;

    -- Cuántas NC nuevas tiene HOY este equipo (incluida esta).
    SELECT count(*), count(*) FILTER (WHERE diferible)
      INTO v_n, v_obs
      FROM no_conformidades
     WHERE activo_id = NEW.activo_id
       AND created_at >= date_trunc('day', NOW() AT TIME ZONE 'America/Santiago') AT TIME ZONE 'America/Santiago';

    v_sev := CASE LOWER(COALESCE(NEW.severidad, ''))
                  WHEN 'critica' THEN 'critical'
                  WHEN 'alta'    THEN 'warning'
                  ELSE 'info' END;
    v_titulo := COALESCE(v_patente, 'Equipo') || ': '
        || CASE WHEN v_n = 1 THEN '1 NC nueva hoy' ELSE v_n || ' NC nuevas hoy' END
        || CASE WHEN v_obs > 0 THEN ' (' || v_obs || ' observación' || CASE WHEN v_obs > 1 THEN 'es' ELSE '' END || ')' ELSE '' END;
    v_msg := 'Última: ' || COALESCE(NEW.descripcion, 'sin descripción')
        || CASE WHEN NEW.origen IS NOT NULL THEN ' · origen: ' || NEW.origen ELSE '' END;

    FOR v_u IN
        SELECT id FROM usuarios_perfil
         WHERE activo = true
           AND rol IN ('administrador','supervisor','planificador',
                       'jefe_mantenimiento','subgerente_operaciones')
    LOOP
        UPDATE alertas
           SET titulo = v_titulo, mensaje = v_msg,
               severidad = CASE WHEN v_sev = 'critical' OR severidad = 'critical' THEN 'critical'
                                WHEN v_sev = 'warning' OR severidad = 'warning' THEN 'warning'
                                ELSE 'info' END
         WHERE tipo = 'no_conformidad' AND entidad_tipo = 'activo' AND entidad_id = NEW.activo_id
           AND destinatario_id = v_u.id AND NOT COALESCE(leida, false)
           AND created_at >= date_trunc('day', NOW() AT TIME ZONE 'America/Santiago') AT TIME ZONE 'America/Santiago';
        IF NOT FOUND THEN
            INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                                 destinatario_id, leida, created_at)
            VALUES ('no_conformidad', v_titulo, v_msg, v_sev, 'activo', NEW.activo_id,
                    v_u.id, false, NOW());
        END IF;
    END LOOP;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Nunca bloquear la creación de la NC por un fallo en la notificación.
    RETURN NEW;
END;
$function$;

-- ── 2. stock_minimo: sin filas huérfanas ────────────────────────────────────
-- El job insertaba una alerta por producto sin destinatario (nadie la veía). Ahora no
-- inserta: el resumen diario lista los productos bajo mínimo.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'alertas-stock-minimo') THEN
        PERFORM cron.unschedule('alertas-stock-minimo');
    END IF;
END $$;

-- ── 3. Datos del resumen diario ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_resumen_diario_cron(p_secreto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_desde TIMESTAMPTZ := NOW() - interval '24 hours';
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido';
    END IF;

    RETURN jsonb_build_object(
      -- NC registradas en las últimas 24 h, por equipo (sin archivadas)
      'nc_por_equipo', COALESCE((
        SELECT jsonb_agg(x ORDER BY x->>'patente') FROM (
          SELECT jsonb_build_object(
                   'activo_id', n.activo_id,
                   'patente', COALESCE(a.patente, a.codigo),
                   'nuevas', count(*),
                   'observaciones', count(*) FILTER (WHERE n.diferible),
                   'ejemplos', (array_agg(left(n.descripcion, 90) ORDER BY n.created_at))[1:3]) x
            FROM no_conformidades n JOIN activos a ON a.id = n.activo_id
           WHERE n.created_at >= v_desde AND n.archivado_at IS NULL
           GROUP BY n.activo_id, a.patente, a.codigo) s), '[]'::jsonb),
      -- Preventivas por horas vencidas o próximas
      'preventivas', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                 'patente', COALESCE(h.patente, h.codigo), 'pauta', h.proxima_pauta,
                 'horas_faltan', round(h.horas_faltan), 'estado', h.estado_preventiva,
                 'ot_abierta', h.ot_abierta) ORDER BY h.horas_faltan)
          FROM v_equipo_horas h WHERE h.estado_preventiva IN ('vencida', 'proxima')), '[]'::jsonb),
      -- OT que debían empezar y no han empezado
      'ot_atrasadas', COALESCE((
        SELECT jsonb_agg(x ORDER BY (x->>'dias')::int DESC) FROM (
          SELECT jsonb_build_object('folio', o.folio, 'patente', COALESCE(a.patente, a.codigo),
                   'tipo', o.tipo, 'dias', CURRENT_DATE - o.fecha_programada::date) x
            FROM ordenes_trabajo o LEFT JOIN activos a ON a.id = o.activo_id
           WHERE o.estado IN ('creada', 'asignada') AND o.fecha_programada::date < CURRENT_DATE
             AND COALESCE(a.es_prueba, false) = false
           ORDER BY o.fecha_programada LIMIT 15) s), '[]'::jsonb),
      'ot_atrasadas_total', (SELECT count(*) FROM ordenes_trabajo o LEFT JOIN activos a ON a.id = o.activo_id
                              WHERE o.estado IN ('creada', 'asignada') AND o.fecha_programada::date < CURRENT_DATE
                                AND COALESCE(a.es_prueba, false) = false),
      -- Vales por despachar a los que no les alcanza el stock (MIG675)
      'vales_sin_stock', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('folio', t.folio, 'patente', COALESCE(a.patente, a.codigo),
                 'disponibilidad', d.disponibilidad, 'dias', CURRENT_DATE - t.created_at::date)
                 ORDER BY t.created_at)
          FROM v_bodega_ticket_disponibilidad d
          JOIN bodega_tickets t ON t.id = d.ticket_id
          LEFT JOIN activos a ON a.id = t.activo_id
         WHERE d.disponibilidad <> 'completo'), '[]'::jsonb),
      -- Productos bajo su mínimo (suma de bodegas)
      'stock_minimo', COALESCE((
        SELECT jsonb_agg(x ORDER BY x->>'nombre') FROM (
          SELECT jsonb_build_object('nombre', p.nombre, 'stock', COALESCE(s.fisico, 0),
                   'minimo', p.stock_minimo, 'disponible', COALESCE(s.disponible, 0)) x
            FROM productos p LEFT JOIN v_stock_disponible s ON s.producto_id = p.id
           WHERE COALESCE(p.stock_minimo, 0) > 0 AND COALESCE(s.fisico, 0) < p.stock_minimo
             AND COALESCE(s.fisico, 0) > 0
           LIMIT 40) s), '[]'::jsonb),
      'stock_minimo_total', (SELECT count(*) FROM productos p LEFT JOIN v_stock_disponible s ON s.producto_id = p.id
                              WHERE COALESCE(p.stock_minimo, 0) > 0 AND COALESCE(s.fisico, 0) < p.stock_minimo
                                AND COALESCE(s.fisico, 0) > 0),
      -- Trabajo parado esperando algo (MIG672)
      'pausas_espera', COALESCE((
        SELECT jsonb_agg(x) FROM (
          SELECT jsonb_build_object('patente', COALESCE(a.patente, a.codigo), 'motivo', t.motivo_tipo,
                   'detalle', t.motivo_cierre, 'os', os.folio) x
            FROM taller_os_tiempo t
            JOIN taller_os os ON os.id = t.os_id
            LEFT JOIN ordenes_trabajo o ON o.id = os.ot_id
            LEFT JOIN activos a ON a.id = o.activo_id
           WHERE t.fin >= v_desde AND t.motivo_tipo IN ('espera_repuesto', 'equipo_no_disponible')
          UNION ALL
          SELECT jsonb_build_object('patente', COALESCE(a.patente, a.codigo), 'motivo', e.motivo_tipo,
                   'detalle', e.comentario, 'ot', o.folio)
            FROM taller_ot_ejecucion_eventos e
            JOIN ordenes_trabajo o ON o.id = e.ot_id
            LEFT JOIN activos a ON a.id = o.activo_id
           WHERE e.tipo = 'pause' AND e.created_at >= v_desde
             AND e.motivo_tipo IN ('espera_repuesto', 'equipo_no_disponible')) s), '[]'::jsonb)
    );
END $function$;

REVOKE ALL ON FUNCTION public.fn_resumen_diario_cron(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_resumen_diario_cron(text) TO anon, authenticated;

-- ── 4. Cron: lunes a sábado 11:00 UTC (08:00 Chile verano) ──────────────────
-- Se copia el encabezado del cron de papeles (que ya lleva el secreto) para no escribir el
-- secreto en el repositorio. La ruta no envía nada mientras RESUMEN_EMAIL_TO no esté.
DO $$
DECLARE v_cmd TEXT;
BEGIN
    SELECT replace(command, '/api/notificaciones/documentos-flota/', '/api/notificaciones/resumen-diario/')
      INTO v_cmd FROM cron.job WHERE jobname = 'documentos-flota-diario';
    IF v_cmd IS NULL OR v_cmd NOT LIKE '%/resumen-diario/%' THEN
        RAISE EXCEPTION 'No encontré el cron de papeles para copiar su encabezado';
    END IF;
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'resumen-diario') THEN
        PERFORM cron.unschedule('resumen-diario');
    END IF;
    PERFORM cron.schedule('resumen-diario', '0 11 * * 1-6', v_cmd);
END $$;

NOTIFY pgrst, 'reload schema';
