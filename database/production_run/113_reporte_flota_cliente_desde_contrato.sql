-- ============================================================================
-- SICOM-ICEO | 113 — Reporte de flota lee el cliente del CONTRATO actual
-- ============================================================================
-- Problema: al cambiar el contrato de un equipo (rpc_cambiar_contrato_activo)
-- el cambio no se reflejaba en el reporte de flota, porque:
--   a) el reporte leia el cliente de estado_diario_flota.cliente, que el
--      confirmar de la bandeja GPS (rpc_confirmar_estado_dia) deja en NULL.
--   b) cambiar el contrato no actualizaba activos.cliente_actual.
--
-- Fix:
--   1) fn_reporte_flota_publico deriva el cliente del contrato actual del activo
--      (activos.contrato_id -> contratos.cliente), no de la foto diaria.
--   2) rpc_cambiar_contrato_activo sincroniza activos.cliente_actual con el
--      cliente del nuevo contrato (consistencia en todo el sistema).
-- ============================================================================

-- ── 1. Reporte: cliente desde el contrato actual ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_reporte_flota_publico()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
AS $function$
WITH veh AS (
  SELECT a.id, a.patente, a.nombre,
         COALESCE(c.cliente, 'Sin contrato') AS cliente_actual
    FROM activos a
    LEFT JOIN contratos c ON c.id = a.contrato_id
   WHERE a.estado <> 'dado_baja'
     AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
),
ult AS (
  SELECT max(fecha) AS f FROM estado_diario_flota WHERE activo_id IN (SELECT id FROM veh)
),
hoy AS (
  SELECT v.cliente_actual AS cliente, e.estado_codigo, e.operacion
    FROM estado_diario_flota e JOIN veh v ON v.id = e.activo_id
   WHERE e.fecha = (SELECT f FROM ult)
),
mes AS (
  SELECT count(*) AS dias,
         count(*) FILTER (WHERE estado_codigo IN ('A','C','D','L','U')) AS up,
         count(*) FILTER (WHERE estado_codigo IN ('A','C','L')) AS util
    FROM estado_diario_flota e JOIN veh v ON v.id = e.activo_id
   WHERE e.fecha >= date_trunc('month', (SELECT f FROM ult))
)
SELECT jsonb_build_object(
  'fecha',          (SELECT f FROM ult),
  'total',          (SELECT count(*) FROM hoy),
  'por_estado',     (SELECT jsonb_object_agg(estado_codigo, n) FROM (SELECT estado_codigo, count(*) n FROM hoy GROUP BY 1) s),
  'por_operacion',  (SELECT jsonb_object_agg(coalesce(operacion,'Sin asignar'), n) FROM (SELECT operacion, count(*) n FROM hoy GROUP BY 1) s),
  'por_cliente',    (SELECT jsonb_agg(jsonb_build_object('cliente', cliente, 'equipos', n) ORDER BY n DESC) FROM (SELECT cliente, count(*) n FROM hoy GROUP BY 1) s),
  'disponibilidad', (SELECT round(100.0 * up / nullif(dias,0), 1) FROM mes),
  'utilizacion',    (SELECT round(100.0 * util / nullif(dias,0), 1) FROM mes),
  'equipos',        (
    SELECT jsonb_agg(jsonb_build_object(
             'patente', q.patente, 'equipamiento', q.equipamiento, 'estado', q.estado,
             'dias_arrendado', q.dias, 'ultimo_cliente', q.ultimo_cliente, 'dias_sin_arriendo', q.dias_sin
           ) ORDER BY q.dias DESC)
    FROM (
      SELECT v.patente, v.nombre AS equipamiento,
        (SELECT e.estado_codigo FROM estado_diario_flota e WHERE e.activo_id=v.id AND e.fecha<=(SELECT f FROM ult) ORDER BY e.fecha DESC LIMIT 1) AS estado,
        (SELECT count(*)::int FROM estado_diario_flota e WHERE e.activo_id=v.id AND e.fecha >= date_trunc('year',(SELECT f FROM ult)) AND e.fecha<=(SELECT f FROM ult) AND e.estado_codigo IN ('A','C')) AS dias,
        v.cliente_actual AS ultimo_cliente,
        (SELECT ((SELECT f FROM ult) - max(e.fecha))::int FROM estado_diario_flota e WHERE e.activo_id=v.id AND e.estado_codigo IN ('A','C') AND e.fecha<=(SELECT f FROM ult)) AS dias_sin
      FROM veh v
    ) q
  )
);
$function$;

-- ── 2. Cambiar contrato sincroniza cliente_actual ──────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_cambiar_contrato_activo(
    p_activo_id uuid, p_nuevo_contrato_id uuid, p_razon text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_activo  RECORD;
    v_id_hist BIGINT;
BEGIN
    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF v_activo.id IS NULL THEN
        RAISE EXCEPTION 'Activo % no encontrado', p_activo_id;
    END IF;

    IF p_nuevo_contrato_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM contratos WHERE id = p_nuevo_contrato_id) THEN
            RAISE EXCEPTION 'Contrato % no existe', p_nuevo_contrato_id;
        END IF;
    END IF;

    IF v_activo.contrato_id IS NOT DISTINCT FROM p_nuevo_contrato_id THEN
        RETURN jsonb_build_object('ok', true, 'sin_cambio', true);
    END IF;

    -- Aplicar el cambio + sincronizar cliente_actual con el nuevo contrato
    UPDATE activos
       SET contrato_id   = p_nuevo_contrato_id,
           cliente_actual = CASE WHEN p_nuevo_contrato_id IS NOT NULL
                                 THEN (SELECT cliente FROM contratos WHERE id = p_nuevo_contrato_id)
                                 ELSE 'Sin contrato' END
     WHERE id = p_activo_id;

    SELECT id INTO v_id_hist
      FROM historico_contrato_activo
     WHERE activo_id = p_activo_id
     ORDER BY cambio_at DESC, id DESC
     LIMIT 1;

    IF v_id_hist IS NOT NULL AND p_razon IS NOT NULL THEN
        UPDATE historico_contrato_activo SET razon = p_razon WHERE id = v_id_hist;
    END IF;

    RETURN jsonb_build_object(
        'ok', true, 'activo_id', p_activo_id,
        'contrato_anterior', v_activo.contrato_id,
        'contrato_nuevo', p_nuevo_contrato_id,
        'historico_id', v_id_hist
    );
END;
$function$;

-- ── Verificacion ───────────────────────────────────────────────────────────
DO $$
DECLARE v JSONB;
BEGIN
    v := fn_reporte_flota_publico();
    RAISE NOTICE '== Reporte flota por cliente (desde contrato) ==';
    RAISE NOTICE '%', jsonb_pretty(v->'por_cliente');
END $$;
