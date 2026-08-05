-- ============================================================================
-- SICOM-ICEO | 273 — Un documento renovado deja de contar como vencido
-- ----------------------------------------------------------------------------
-- Reporte (Manuel, 2026-08-05): "cuando se actualizaban algunos papeles seguía
-- la marca de que estaba vencido el papel".
--
-- Causa: renovar un documento inserta una fila NUEVA en `certificaciones` y
-- conserva la anterior como histórico (correcto, es la trazabilidad). Pero casi
-- todos los consumidores contaban TODAS las filas, no la última de cada
-- (equipo, tipo). La versión vieja seguía marcada 'vencido' para siempre.
-- Hoy en prod ya hay 17 filas reemplazadas, las 17 marcadas vencidas.
--
-- Consumidores afectados (contaban el histórico):
--   · v_ficha_activo.cert_vencidas / cert_vigentes / cert_por_vencer
--     -> la marca roja de la ficha del equipo y del QR público
--   · v_kpi_activo.cumplimiento_doc_pct y health_score (ranking de equipos)
--   · vw_prevencion_resumen.certificaciones_vencidas / por_vencer_30d / 60d
--   · mv_certificaciones_stats (KPIs de Cumplimiento)
--   · fn_verificar_certificaciones_flota (alertas duplicadas por cada versión)
--   · verificar_certificaciones: además ponía el equipo en 'fuera_servicio' por
--     una fila bloqueante vencida AUNQUE ya estuviera renovada. El más grave.
--
-- Ya estaban correctos (usan DISTINCT ON por tipo): v_documentos_equipo_estado,
-- rpc_documentos_activo_publico y fn_alertas_documentos_vencimiento.
--
-- Fix: una sola definición de "el documento que rige hoy" —
-- `v_certificacion_actual`— y todos los consumidores apuntan ahí. El estado se
-- calcula en vivo desde fecha_vencimiento (la columna `estado` depende de un
-- job diario y puede ir un día atrasada).
-- IDEMPOTENTE. No borra ni modifica el histórico.
-- ============================================================================

-- ── 1. La versión que rige hoy de cada documento del equipo ─────────────────
CREATE OR REPLACE VIEW public.v_certificacion_actual AS
SELECT DISTINCT ON (c.activo_id, c.tipo)
       c.*,
       (CASE
          WHEN c.fecha_vencimiento IS NULL
            OR c.fecha_vencimiento >= DATE '2099-01-01'      THEN 'no_aplica'
          WHEN c.fecha_vencimiento <  CURRENT_DATE           THEN 'vencido'
          WHEN c.fecha_vencimiento <= CURRENT_DATE + 30      THEN 'por_vencer'
          ELSE 'vigente'
        END)::estado_documento_enum AS estado_real,
       (c.fecha_vencimiento - CURRENT_DATE)::INT AS dias_restantes
  FROM certificaciones c
 ORDER BY c.activo_id, c.tipo, c.fecha_vencimiento DESC NULLS LAST, c.created_at DESC;

COMMENT ON VIEW public.v_certificacion_actual IS
  'La versión vigente de cada documento por (activo, tipo). Usar SIEMPRE esto '
  'para contar vencidos: `certificaciones` guarda también las versiones '
  'reemplazadas y contarlas deja el equipo marcado vencido para siempre.';

GRANT SELECT ON public.v_certificacion_actual TO authenticated, service_role;

-- ── 2. La marca roja de la ficha del equipo y del QR público ────────────────
-- (solo cambian los 3 subselects de certificaciones; el resto es idéntico)
CREATE OR REPLACE VIEW public.v_ficha_activo AS
SELECT a.id,
    a.codigo,
    a.nombre,
    a.tipo,
    a.criticidad,
    a.estado,
    a.numero_serie,
    a.fecha_alta,
    a.anio_fabricacion,
    a.kilometraje_actual,
    a.horas_uso_actual,
    a.ciclos_actual,
    a.ubicacion_detalle,
    a.foto_url,
    a.qr_code,
    a.qr_url,
    a.valor_adquisicion,
    a.proveedor,
    a.datos_tecnicos,
    a.notas,
    m.nombre AS modelo_nombre,
    ma.nombre AS marca_nombre,
    f.nombre AS faena_nombre,
    f.codigo AS faena_codigo,
    resp.nombre_completo AS responsable_nombre,
    ap.codigo AS padre_codigo,
    ap.nombre AS padre_nombre,
    ( SELECT count(*) AS count
           FROM ordenes_trabajo ot
          WHERE ot.activo_id = a.id) AS total_ots,
    ( SELECT count(*) AS count
           FROM ordenes_trabajo ot
          WHERE ot.activo_id = a.id AND ot.tipo = 'preventivo'::tipo_ot_enum) AS ots_preventivas,
    ( SELECT count(*) AS count
           FROM ordenes_trabajo ot
          WHERE ot.activo_id = a.id AND ot.tipo = 'correctivo'::tipo_ot_enum) AS ots_correctivas,
    ( SELECT count(*) AS count
           FROM ordenes_trabajo ot
          WHERE ot.activo_id = a.id AND (ot.estado = ANY (ARRAY['creada'::estado_ot_enum, 'asignada'::estado_ot_enum, 'en_ejecucion'::estado_ot_enum, 'pausada'::estado_ot_enum]))) AS ots_abiertas,
    COALESCE(( SELECT sum(mi.cantidad * mi.costo_unitario) AS sum
           FROM movimientos_inventario mi
          WHERE mi.activo_id = a.id AND (mi.tipo = ANY (ARRAY['salida'::tipo_movimiento_enum, 'merma'::tipo_movimiento_enum]))), 0::numeric) AS costo_materiales_acumulado,
    ( SELECT max(ot.fecha_termino) AS max
           FROM ordenes_trabajo ot
          WHERE ot.activo_id = a.id AND (ot.estado = ANY (ARRAY['ejecutada_ok'::estado_ot_enum, 'ejecutada_con_observaciones'::estado_ot_enum, 'cerrada'::estado_ot_enum]))) AS ultima_mantencion,
    ( SELECT min(pm.proxima_ejecucion_fecha) AS min
           FROM planes_mantenimiento pm
          WHERE pm.activo_id = a.id AND pm.activo_plan = true) AS proxima_mantencion,
    ( SELECT count(*) AS count
           FROM v_certificacion_actual c
          WHERE c.activo_id = a.id AND c.estado_real = 'vigente'::estado_documento_enum) AS cert_vigentes,
    ( SELECT count(*) AS count
           FROM v_certificacion_actual c
          WHERE c.activo_id = a.id AND c.estado_real = 'vencido'::estado_documento_enum) AS cert_vencidas,
    ( SELECT count(*) AS count
           FROM v_certificacion_actual c
          WHERE c.activo_id = a.id AND c.estado_real = 'por_vencer'::estado_documento_enum) AS cert_por_vencer,
    ( SELECT count(*) AS count
           FROM incidentes i
          WHERE i.activo_id = a.id) AS total_incidentes,
    ( SELECT count(*) AS count
           FROM planes_mantenimiento pm
          WHERE pm.activo_id = a.id AND pm.activo_plan = true) AS planes_pm_activos,
    ( SELECT round(avg(EXTRACT(epoch FROM ot.fecha_termino - ot.fecha_inicio) / 3600.0), 1) AS round
           FROM ordenes_trabajo ot
          WHERE ot.activo_id = a.id AND ot.tipo = 'correctivo'::tipo_ot_enum AND ot.fecha_inicio IS NOT NULL AND ot.fecha_termino IS NOT NULL) AS mttr_horas,
    a.created_at,
    a.updated_at
   FROM activos a
     LEFT JOIN modelos m ON m.id = a.modelo_id
     LEFT JOIN marcas ma ON ma.id = m.marca_id
     LEFT JOIN faenas f ON f.id = a.faena_id
     LEFT JOIN usuarios_perfil resp ON resp.id = a.responsable_id
     LEFT JOIN activos ap ON ap.id = a.activo_padre_id;

-- ── 3. cumplimiento_doc_pct y health_score del ranking de equipos ───────────
-- (solo cambia el CTE cert_stats)
CREATE OR REPLACE VIEW public.v_kpi_activo AS
WITH periodos AS (
         SELECT date_trunc('month'::text, CURRENT_DATE::timestamp with time zone)::date AS inicio,
            (date_trunc('month'::text, CURRENT_DATE::timestamp with time zone) + '1 mon'::interval - '1 day'::interval)::date AS fin,
            EXTRACT(epoch FROM date_trunc('month'::text, CURRENT_DATE::timestamp with time zone) + '1 mon'::interval - '1 day'::interval - date_trunc('month'::text, CURRENT_DATE::timestamp with time zone)) / 3600.0 AS horas_periodo
        ), ot_stats AS (
         SELECT ot.activo_id,
            count(*) AS total_ots,
            count(*) FILTER (WHERE ot.tipo = 'preventivo'::tipo_ot_enum) AS ots_pm,
            count(*) FILTER (WHERE ot.tipo = 'correctivo'::tipo_ot_enum) AS ots_cm,
            count(*) FILTER (WHERE ot.tipo = 'preventivo'::tipo_ot_enum AND (ot.estado = ANY (ARRAY['ejecutada_ok'::estado_ot_enum, 'ejecutada_con_observaciones'::estado_ot_enum, 'cerrada'::estado_ot_enum]))) AS pm_ejecutadas,
            count(*) FILTER (WHERE ot.tipo = 'preventivo'::tipo_ot_enum AND ot.estado <> 'cancelada'::estado_ot_enum) AS pm_programadas,
            avg(EXTRACT(epoch FROM ot.fecha_termino - ot.fecha_inicio) / 3600.0) FILTER (WHERE ot.tipo = 'correctivo'::tipo_ot_enum AND ot.fecha_inicio IS NOT NULL AND ot.fecha_termino IS NOT NULL) AS mttr_horas,
            COALESCE(sum(EXTRACT(epoch FROM ot.fecha_termino - ot.fecha_inicio) / 3600.0) FILTER (WHERE ot.tipo = 'correctivo'::tipo_ot_enum AND ot.fecha_inicio IS NOT NULL AND ot.fecha_termino IS NOT NULL), 0::numeric) AS downtime_horas,
            count(*) FILTER (WHERE ot.tipo = 'correctivo'::tipo_ot_enum AND (ot.estado = ANY (ARRAY['ejecutada_ok'::estado_ot_enum, 'ejecutada_con_observaciones'::estado_ot_enum, 'cerrada'::estado_ot_enum]))) AS fallas_periodo,
            COALESCE(sum(ot.costo_mano_obra), 0::numeric) + COALESCE(( SELECT sum(mi.cantidad * mi.costo_unitario) AS sum
                   FROM movimientos_inventario mi
                  WHERE mi.activo_id = ot.activo_id AND (mi.tipo = ANY (ARRAY['salida'::tipo_movimiento_enum, 'merma'::tipo_movimiento_enum]))), 0::numeric) AS costo_acumulado
           FROM ordenes_trabajo ot
          GROUP BY ot.activo_id
        ), cert_stats AS (
         SELECT c.activo_id,
            count(*) AS certs_total,
            count(*) FILTER (WHERE c.estado_real = 'vigente'::estado_documento_enum) AS certs_vigentes,
            count(*) FILTER (WHERE c.estado_real = ANY (ARRAY['vencido'::estado_documento_enum, 'por_vencer'::estado_documento_enum])) AS certs_en_riesgo
           FROM v_certificacion_actual c
          GROUP BY c.activo_id
        )
 SELECT a.id AS activo_id,
    a.codigo,
    a.nombre,
    a.tipo,
    a.criticidad,
    a.estado,
    a.faena_id,
    m.nombre AS modelo,
    ma.nombre AS marca,
    round(COALESCE(os.mttr_horas, 0::numeric), 1) AS mttr_horas,
        CASE
            WHEN COALESCE(os.fallas_periodo, 0::bigint) > 0 THEN round(((( SELECT periodos.horas_periodo
               FROM periodos)) - COALESCE(os.downtime_horas, 0::numeric)) / os.fallas_periodo::numeric, 1)
            ELSE NULL::numeric
        END AS mtbf_horas,
        CASE
            WHEN (( SELECT periodos.horas_periodo
               FROM periodos)) > 0::numeric THEN round(((( SELECT periodos.horas_periodo
               FROM periodos)) - COALESCE(os.downtime_horas, 0::numeric)) / (( SELECT periodos.horas_periodo
               FROM periodos)) * 100::numeric, 1)
            ELSE 100.0
        END AS disponibilidad_pct,
        CASE
            WHEN COALESCE(os.pm_programadas, 0::bigint) > 0 THEN round(COALESCE(os.pm_ejecutadas, 0::bigint)::numeric / os.pm_programadas::numeric * 100::numeric, 1)
            ELSE NULL::numeric
        END AS cumplimiento_pm_pct,
        CASE
            WHEN COALESCE(os.total_ots, 0::bigint) > 0 THEN round(COALESCE(os.ots_cm, 0::bigint)::numeric / os.total_ots::numeric * 100::numeric, 1)
            ELSE 0::numeric
        END AS tasa_correctivos_pct,
    COALESCE(os.costo_acumulado, 0::numeric) AS costo_acumulado,
    COALESCE(os.total_ots, 0::bigint) AS total_ots,
    COALESCE(os.ots_pm, 0::bigint) AS ots_preventivas,
    COALESCE(os.ots_cm, 0::bigint) AS ots_correctivas,
    COALESCE(os.fallas_periodo, 0::bigint) AS fallas_periodo,
    COALESCE(cs.certs_total, 0::bigint) AS certs_total,
    COALESCE(cs.certs_vigentes, 0::bigint) AS certs_vigentes,
    COALESCE(cs.certs_en_riesgo, 0::bigint) AS certs_en_riesgo,
        CASE
            WHEN COALESCE(cs.certs_total, 0::bigint) > 0 THEN round(COALESCE(cs.certs_vigentes, 0::bigint)::numeric / cs.certs_total::numeric * 100::numeric, 1)
            ELSE 100.0
        END AS cumplimiento_doc_pct,
    round(COALESCE(
        CASE
            WHEN (( SELECT periodos.horas_periodo
               FROM periodos)) > 0::numeric THEN ((( SELECT periodos.horas_periodo
               FROM periodos)) - COALESCE(os.downtime_horas, 0::numeric)) / (( SELECT periodos.horas_periodo
               FROM periodos)) * 100::numeric
            ELSE 100::numeric
        END, 100::numeric) * 0.30 + COALESCE(
        CASE
            WHEN COALESCE(os.pm_programadas, 0::bigint) > 0 THEN COALESCE(os.pm_ejecutadas, 0::bigint)::numeric / os.pm_programadas::numeric * 100::numeric
            ELSE 100::numeric
        END, 100::numeric) * 0.25 + COALESCE(
        CASE
            WHEN COALESCE(cs.certs_total, 0::bigint) > 0 THEN COALESCE(cs.certs_vigentes, 0::bigint)::numeric / cs.certs_total::numeric * 100::numeric
            ELSE 100::numeric
        END, 100::numeric) * 0.20 + (100::numeric - COALESCE(
        CASE
            WHEN COALESCE(os.total_ots, 0::bigint) > 0 THEN COALESCE(os.ots_cm, 0::bigint)::numeric / os.total_ots::numeric * 100::numeric
            ELSE 0::numeric
        END, 0::numeric)) * 0.15 +
        CASE
            WHEN COALESCE(os.mttr_horas, 0::numeric) = 0::numeric THEN 100
            WHEN os.mttr_horas <= 4::numeric THEN 100
            WHEN os.mttr_horas <= 8::numeric THEN 75
            WHEN os.mttr_horas <= 12::numeric THEN 50
            WHEN os.mttr_horas <= 24::numeric THEN 25
            ELSE 0
        END::numeric * 0.10, 1) AS health_score
   FROM activos a
     LEFT JOIN modelos m ON m.id = a.modelo_id
     LEFT JOIN marcas ma ON ma.id = m.marca_id
     LEFT JOIN ot_stats os ON os.activo_id = a.id
     LEFT JOIN cert_stats cs ON cs.activo_id = a.id;

-- ── 4. Módulo Prevención: documentos bloqueantes vencidos / por vencer ──────
CREATE OR REPLACE VIEW public.vw_prevencion_resumen AS
SELECT ( SELECT count(*) AS count
           FROM v_certificacion_actual certificaciones
          WHERE certificaciones.bloqueante = true AND certificaciones.fecha_vencimiento < CURRENT_DATE) AS certificaciones_vencidas,
    ( SELECT count(*) AS count
           FROM v_certificacion_actual certificaciones
          WHERE certificaciones.bloqueante = true AND certificaciones.fecha_vencimiento >= CURRENT_DATE AND certificaciones.fecha_vencimiento <= (CURRENT_DATE + '30 days'::interval)) AS certificaciones_por_vencer_30d,
    ( SELECT count(*) AS count
           FROM v_certificacion_actual certificaciones
          WHERE certificaciones.bloqueante = true AND certificaciones.fecha_vencimiento >= CURRENT_DATE AND certificaciones.fecha_vencimiento <= (CURRENT_DATE + '60 days'::interval)) AS certificaciones_por_vencer_60d,
    ( SELECT count(*) AS count
           FROM suspel_productos
          WHERE suspel_productos.activo = true AND suspel_productos.hds_proxima_revision < (CURRENT_DATE + '90 days'::interval)) AS hds_por_revisar,
    ( SELECT count(*) AS count
           FROM suspel_productos
          WHERE suspel_productos.activo = true) AS productos_suspel_activos,
    ( SELECT count(*) AS count
           FROM suspel_bodegas
          WHERE suspel_bodegas.activo = true) AS bodegas_total,
    ( SELECT count(*) AS count
           FROM suspel_bodegas
          WHERE suspel_bodegas.activo = true AND suspel_bodegas.autorizacion_vencimiento < CURRENT_DATE) AS bodegas_autorizacion_vencida,
    ( SELECT count(*) AS count
           FROM suspel_bodegas
          WHERE suspel_bodegas.activo = true AND suspel_bodegas.proxima_inspeccion < CURRENT_DATE) AS bodegas_inspeccion_vencida,
    ( SELECT COALESCE(sum(respel_movimientos.cantidad), 0::numeric) AS "coalesce"
           FROM respel_movimientos
          WHERE respel_movimientos.tipo_movimiento::text = 'generacion'::text AND respel_movimientos.fecha >= date_trunc('month'::text, CURRENT_DATE::timestamp with time zone)::date) AS respel_generado_mes_kg,
    ( SELECT COALESCE(sum(respel_movimientos.cantidad), 0::numeric) AS "coalesce"
           FROM respel_movimientos
          WHERE respel_movimientos.tipo_movimiento::text = 'retiro'::text AND respel_movimientos.fecha >= date_trunc('month'::text, CURRENT_DATE::timestamp with time zone)::date) AS respel_retirado_mes_kg,
    ( SELECT count(*) AS count
           FROM respel_movimientos
          WHERE respel_movimientos.tipo_movimiento::text = 'retiro'::text AND respel_movimientos.numero_sidrep IS NULL) AS retiros_sin_sidrep,
    ( SELECT count(*) AS count
           FROM conductores
          WHERE conductores.activo = true AND (conductores.semep_vencimiento IS NULL OR conductores.semep_vencimiento < CURRENT_DATE)) AS conductores_semep_vencido,
    ( SELECT count(*) AS count
           FROM conductores
          WHERE conductores.activo = true AND conductores.semep_vencimiento >= CURRENT_DATE AND conductores.semep_vencimiento <= (CURRENT_DATE + '60 days'::interval)) AS conductores_semep_por_vencer,
    ( SELECT count(*) AS count
           FROM conductores
          WHERE conductores.activo = true AND conductores.horas_espera_mes_actual >= 88::numeric) AS conductores_fatiga_critica,
    ( SELECT count(*) AS count
           FROM normativa_documentos
          WHERE normativa_documentos.activo = true AND normativa_documentos.fecha_vencimiento < CURRENT_DATE) AS documentos_vencidos,
    ( SELECT count(*) AS count
           FROM normativa_documentos
          WHERE normativa_documentos.activo = true AND normativa_documentos.fecha_vencimiento >= CURRENT_DATE AND normativa_documentos.fecha_vencimiento <= (CURRENT_DATE + '30 days'::interval)) AS documentos_por_vencer;

-- ── 5. KPIs de Cumplimiento (vista materializada, se refresca cada hora) ────
DROP MATERIALIZED VIEW IF EXISTS public.mv_certificaciones_stats;
CREATE MATERIALIZED VIEW public.mv_certificaciones_stats AS
SELECT a.faena_id,
    a.contrato_id,
        CASE
            WHEN a.tipo = ANY (ARRAY['punto_fijo'::tipo_activo_enum, 'surtidor'::tipo_activo_enum, 'dispensador'::tipo_activo_enum, 'estanque'::tipo_activo_enum, 'bomba'::tipo_activo_enum, 'manguera'::tipo_activo_enum]) THEN 'fijo'::text
            WHEN a.tipo = ANY (ARRAY['punto_movil'::tipo_activo_enum, 'camion_cisterna'::tipo_activo_enum, 'lubrimovil'::tipo_activo_enum, 'equipo_bombeo'::tipo_activo_enum, 'camioneta'::tipo_activo_enum, 'camion'::tipo_activo_enum]) THEN 'movil'::text
            ELSE 'otro'::text
        END AS categoria_activo,
    count(*) AS total_certificaciones,
    count(*) FILTER (WHERE c.estado_real = 'vigente'::estado_documento_enum) AS vigentes,
    count(*) FILTER (WHERE c.estado_real = 'por_vencer'::estado_documento_enum) AS por_vencer,
    count(*) FILTER (WHERE c.estado_real = 'vencido'::estado_documento_enum) AS vencidas,
    count(*) FILTER (WHERE c.tipo = 'calibracion'::tipo_certificacion_enum AND c.estado_real = 'vigente'::estado_documento_enum) AS calibraciones_vigentes,
    count(*) FILTER (WHERE c.tipo = 'calibracion'::tipo_certificacion_enum) AS calibraciones_total,
    count(*) FILTER (WHERE (c.tipo = ANY (ARRAY['revision_tecnica'::tipo_certificacion_enum, 'soap'::tipo_certificacion_enum])) AND c.estado_real = 'vigente'::estado_documento_enum) AS vehiculares_vigentes,
    count(*) FILTER (WHERE c.tipo = ANY (ARRAY['revision_tecnica'::tipo_certificacion_enum, 'soap'::tipo_certificacion_enum])) AS vehiculares_total
   FROM v_certificacion_actual c
     JOIN activos a ON a.id = c.activo_id
  GROUP BY a.faena_id, a.contrato_id, (
        CASE
            WHEN a.tipo = ANY (ARRAY['punto_fijo'::tipo_activo_enum, 'surtidor'::tipo_activo_enum, 'dispensador'::tipo_activo_enum, 'estanque'::tipo_activo_enum, 'bomba'::tipo_activo_enum, 'manguera'::tipo_activo_enum]) THEN 'fijo'::text
            WHEN a.tipo = ANY (ARRAY['punto_movil'::tipo_activo_enum, 'camion_cisterna'::tipo_activo_enum, 'lubrimovil'::tipo_activo_enum, 'equipo_bombeo'::tipo_activo_enum, 'camioneta'::tipo_activo_enum, 'camion'::tipo_activo_enum]) THEN 'movil'::text
            ELSE 'otro'::text
        END);

GRANT SELECT ON public.mv_certificaciones_stats TO anon, authenticated, service_role;


-- ── Alertas normativas: una alerta por documento, no por versión ────────────
CREATE OR REPLACE FUNCTION public.fn_verificar_certificaciones_flota()
RETURNS INTEGER
LANGUAGE plpgsql
AS $function$
DECLARE
    v_count INTEGER := 0;
    v_cert RECORD;
BEGIN
    FOR v_cert IN
        SELECT
            c.id, c.tipo, c.fecha_vencimiento, c.bloqueante,
            a.id AS activo_id, a.patente, a.nombre AS activo_nombre,
            CASE
                WHEN c.fecha_vencimiento < CURRENT_DATE THEN 'vencida'
                WHEN c.fecha_vencimiento < CURRENT_DATE + INTERVAL '45 days' THEN 'por_vencer'
            END AS estado_cert
        -- [MIG273] Solo la versión vigente: antes alertaba también por cada
        -- versión antigua ya renovada.
        FROM v_certificacion_actual c
        JOIN activos a ON a.id = c.activo_id
        WHERE a.estado != 'dado_baja'
          AND c.estado_real != 'vencido'
          AND c.fecha_vencimiento < CURRENT_DATE + INTERVAL '45 days'
          AND c.tipo IN ('revision_tecnica', 'hermeticidad', 'tc8_sec', 'inscripcion_sec',
                         'soap', 'permiso_circulacion', 'seguro_rc')
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM alertas
            WHERE entidad_id = v_cert.id
              AND tipo IN ('rt_por_vencer', 'hermeticidad_vencida', 'sec_no_vigente', 'vencimiento')
              AND created_at > CURRENT_DATE - INTERVAL '7 days'
        ) THEN
            INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
            VALUES (
                CASE v_cert.tipo
                    WHEN 'revision_tecnica' THEN 'rt_por_vencer'
                    WHEN 'hermeticidad' THEN 'hermeticidad_vencida'
                    WHEN 'tc8_sec' THEN 'sec_no_vigente'
                    WHEN 'inscripcion_sec' THEN 'sec_no_vigente'
                    ELSE 'vencimiento'
                END,
                format('%s: %s — %s %s',
                    CASE WHEN v_cert.estado_cert = 'vencida' THEN 'BLOQUEO' ELSE 'ALERTA' END,
                    v_cert.tipo,
                    v_cert.activo_nombre,
                    COALESCE('(PPU: ' || v_cert.patente || ')', '')),
                format('Certificación %s del equipo %s %s el %s.',
                    v_cert.tipo, v_cert.activo_nombre,
                    CASE WHEN v_cert.estado_cert = 'vencida' THEN 'VENCIÓ' ELSE 'vence' END,
                    v_cert.fecha_vencimiento),
                CASE WHEN v_cert.estado_cert = 'vencida' THEN 'critical' ELSE 'warning' END,
                'certificacion',
                v_cert.id
            );
            v_count := v_count + 1;
        END IF;
    END LOOP;
    RETURN v_count;
END;
$function$;


-- ── Recalculo de estados: no sacar de servicio por un papel ya renovado ─────
CREATE OR REPLACE FUNCTION public.verificar_certificaciones()
RETURNS TABLE(certificacion_id UUID, estado_anterior TEXT, estado_nuevo TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    r RECORD;
    v_estado_nuevo estado_documento_enum;
BEGIN
    FOR r IN
        SELECT c.id, c.activo_id, c.fecha_vencimiento, c.estado, c.bloqueante,
               c.tipo, c.numero_certificado,
               -- [MIG273] ¿es la versión que rige hoy, o una ya reemplazada?
               EXISTS (SELECT 1 FROM v_certificacion_actual va WHERE va.id = c.id) AS es_actual
        FROM certificaciones c
        WHERE c.estado != 'no_aplica'
    LOOP
        IF r.fecha_vencimiento > (NOW() + INTERVAL '30 days') THEN
            v_estado_nuevo := 'vigente';
        ELSIF r.fecha_vencimiento > NOW() THEN
            v_estado_nuevo := 'por_vencer';
        ELSE
            v_estado_nuevo := 'vencido';
        END IF;

        IF r.estado IS DISTINCT FROM v_estado_nuevo THEN
            -- El histórico se mantiene al día, pero solo la versión vigente
            -- genera alertas y puede sacar el equipo de servicio.
            UPDATE certificaciones
            SET estado = v_estado_nuevo,
                updated_at = NOW()
            WHERE id = r.id;

            IF r.es_actual AND v_estado_nuevo IN ('por_vencer', 'vencido') THEN
                BEGIN
                    INSERT INTO alertas (
                        tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id, created_at
                    ) VALUES (
                        'vencimiento',
                        CASE v_estado_nuevo
                            WHEN 'por_vencer' THEN 'Certificacion proxima a vencer'
                            WHEN 'vencido'    THEN 'Certificacion VENCIDA'
                        END,
                        'La certificacion ID ' || r.id::TEXT || ' del activo ' ||
                            COALESCE(r.activo_id::TEXT, 'N/A') ||
                            CASE v_estado_nuevo
                                WHEN 'por_vencer' THEN ' vence el ' || r.fecha_vencimiento::TEXT
                                WHEN 'vencido'    THEN ' ha VENCIDO el ' || r.fecha_vencimiento::TEXT
                            END || '.',
                        CASE v_estado_nuevo
                            WHEN 'por_vencer' THEN 'warning'
                            WHEN 'vencido'    THEN 'critical'
                        END,
                        'certificacion',
                        r.id,
                        NOW()
                    );
                EXCEPTION WHEN OTHERS THEN NULL;
                END;
            END IF;

            IF r.es_actual AND r.bloqueante = true AND v_estado_nuevo = 'vencido'
               AND r.activo_id IS NOT NULL THEN
                UPDATE activos
                SET estado = 'fuera_servicio'
                WHERE id = r.activo_id;
            END IF;

            certificacion_id := r.id;
            estado_anterior := r.estado::TEXT;
            estado_nuevo := v_estado_nuevo::TEXT;
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$function$;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_total INT; v_actual INT; v_reemp INT; v_reemp_venc INT;
    v_equipos_antes INT; v_equipos_despues INT;
BEGIN
    SELECT count(*) INTO v_total  FROM certificaciones;
    SELECT count(*) INTO v_actual FROM v_certificacion_actual;
    v_reemp := v_total - v_actual;

    SELECT count(*) INTO v_reemp_venc
      FROM certificaciones c
     WHERE c.estado = 'vencido'
       AND NOT EXISTS (SELECT 1 FROM v_certificacion_actual va WHERE va.id = c.id);

    -- Equipos que la ficha marcaba con documento vencido contando el histórico
    SELECT count(DISTINCT activo_id) INTO v_equipos_antes
      FROM certificaciones WHERE estado = 'vencido';
    SELECT count(DISTINCT activo_id) INTO v_equipos_despues
      FROM v_certificacion_actual WHERE estado_real = 'vencido';

    IF v_actual > v_total THEN
        RAISE EXCEPTION 'FALLO: v_certificacion_actual devuelve mas filas que la tabla';
    END IF;

    RAISE NOTICE 'MIG273 OK - documentos: % filas, % vigentes, % reemplazadas (% marcadas vencidas)',
                 v_total, v_actual, v_reemp, v_reemp_venc;
    RAISE NOTICE 'MIG273 - equipos con documento vencido: % antes -> % ahora',
                 v_equipos_antes, v_equipos_despues;
END $$;

NOTIFY pgrst, 'reload schema';
