-- ============================================================================
-- SICOM-ICEO | 228b — Alertas de vencimiento documental: tipos + destinatarios
-- ============================================================================
-- Fix de MIG228:
--   1. chk_alertas_tipo no permitía los tipos nuevos → se agregan.
--   2. La campanita solo muestra alertas CON destinatario_id → se genera una
--      alerta por persona: administradores, PLANIFICADORES (pedido de Manuel)
--      y jefe de mantenimiento.
-- ============================================================================

ALTER TABLE alertas DROP CONSTRAINT IF EXISTS chk_alertas_tipo;
ALTER TABLE alertas ADD CONSTRAINT chk_alertas_tipo CHECK ((tipo)::text = ANY (ARRAY[
  'vencimiento','stock_minimo','ot_vencida','incumplimiento','bloqueante',
  'antiguedad_vehiculo','semep_vencido','fatiga_conductor','rt_por_vencer',
  'hermeticidad_vencida','sec_no_vigente','sensor_fuga','accidente_no_reportado',
  'jornada_excedida','pts_faltante','disponibilidad_vencida','gps_sin_senal',
  'no_conformidad','recurso_solicitado','recurso_por_comprar','recurso_recibido',
  'vale_emitido',
  'doc_por_vencer','doc_vencido','doc_vencidos_equipo'
]::text[]));

-- Destinatarios de las alertas documentales
CREATE OR REPLACE FUNCTION fn_destinatarios_alertas_documentos()
RETURNS SETOF uuid
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
  SELECT id FROM usuarios_perfil
   WHERE COALESCE(activo, true)
     AND rol IN ('administrador', 'planificador', 'jefe_mantenimiento')
$$;

CREATE OR REPLACE FUNCTION fn_alertas_documentos_vencimiento()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_hitos INT; v_vencidos INT; v_resumen INT;
BEGIN
    -- 1. Hitos de aproximación: 30 / 15 / 7 / 1 días (1 alerta × doc × destinatario)
    INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id, destinatario_id)
    SELECT 'doc_por_vencer',
           'Documento por vencer: ' || initcap(replace(d.tipo, '_', ' ')) || ' — ' || COALESCE(d.patente, d.codigo),
           COALESCE(d.patente, d.codigo) || ': ' || initcap(replace(d.tipo, '_', ' ')) ||
             ' vence el ' || to_char(d.fecha_vencimiento, 'DD-MM-YYYY') ||
             ' (en ' || d.dias_restantes || ' día' || CASE WHEN d.dias_restantes = 1 THEN '' ELSE 's' END ||
             '). Renuévalo en Plan Semanal → Documentos con problemas.',
           'warning', 'activo', d.activo_id, u.uid
      FROM v_documentos_equipo_estado d
      CROSS JOIN (SELECT fn_destinatarios_alertas_documentos() AS uid) u
     WHERE d.dias_restantes IN (30, 15, 7, 1)
       AND d.fecha_vencimiento < DATE '2099-01-01'
       AND NOT EXISTS (
           SELECT 1 FROM alertas a
            WHERE a.tipo = 'doc_por_vencer'
              AND a.entidad_id = d.activo_id
              AND a.destinatario_id = u.uid
              AND a.titulo LIKE '%' || initcap(replace(d.tipo, '_', ' ')) || '%'
              AND a.created_at > CURRENT_DATE - 5);
    GET DIAGNOSTICS v_hitos = ROW_COUNT;

    -- 2. Recién vencidos (venció ayer)
    INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id, destinatario_id)
    SELECT 'doc_vencido',
           'Documento VENCIDO: ' || initcap(replace(d.tipo, '_', ' ')) || ' — ' || COALESCE(d.patente, d.codigo),
           COALESCE(d.patente, d.codigo) || ': ' || initcap(replace(d.tipo, '_', ' ')) ||
             ' venció el ' || to_char(d.fecha_vencimiento, 'DD-MM-YYYY') ||
             CASE WHEN d.bloqueante THEN ' — BLOQUEANTE para operar.' ELSE '. Gestionar renovación.' END,
           'critical', 'activo', d.activo_id, u.uid
      FROM v_documentos_equipo_estado d
      CROSS JOIN (SELECT fn_destinatarios_alertas_documentos() AS uid) u
     WHERE d.fecha_vencimiento = CURRENT_DATE - 1
       AND NOT EXISTS (
           SELECT 1 FROM alertas a
            WHERE a.tipo = 'doc_vencido' AND a.entidad_id = d.activo_id
              AND a.destinatario_id = u.uid
              AND a.titulo LIKE '%' || initcap(replace(d.tipo, '_', ' ')) || '%'
              AND a.created_at > CURRENT_DATE - 5);
    GET DIAGNOSTICS v_vencidos = ROW_COUNT;

    -- 3. Resumen por equipo con vencidos acumulados (se repite cada 7 días hasta resolver)
    INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id, destinatario_id)
    SELECT 'doc_vencidos_equipo',
           'Documentos vencidos: ' || COALESCE(x.patente, x.codigo) || ' (' || x.n || ')',
           COALESCE(x.patente, x.codigo) || ' tiene ' || x.n || ' documento' ||
             CASE WHEN x.n = 1 THEN '' ELSE 's' END || ' vencido' ||
             CASE WHEN x.n = 1 THEN '' ELSE 's' END || ': ' || x.lista ||
             '. Revisa Plan Semanal → Documentos con problemas.',
           'critical', 'activo', x.activo_id, u.uid
      FROM (
        SELECT d.activo_id, d.patente, d.codigo, count(*) AS n,
               string_agg(initcap(replace(d.tipo, '_', ' ')), ', ' ORDER BY d.fecha_vencimiento) AS lista
          FROM v_documentos_equipo_estado d
         WHERE d.fecha_vencimiento < CURRENT_DATE
           AND d.fecha_vencimiento > CURRENT_DATE - INTERVAL '10 years'
         GROUP BY d.activo_id, d.patente, d.codigo
      ) x
      CROSS JOIN (SELECT fn_destinatarios_alertas_documentos() AS uid) u
     WHERE NOT EXISTS (
           SELECT 1 FROM alertas a
            WHERE a.tipo = 'doc_vencidos_equipo' AND a.entidad_id = x.activo_id
              AND a.destinatario_id = u.uid
              AND a.created_at > CURRENT_DATE - 7);
    GET DIAGNOSTICS v_resumen = ROW_COUNT;

    RETURN jsonb_build_object('hitos', v_hitos, 'vencidos_ayer', v_vencidos, 'resumen_equipos', v_resumen);
END $$;

DO $$ BEGIN RAISE NOTICE 'MIG228b OK: tipos doc_* permitidos + alertas por destinatario (admin, planificador, jefe)'; END $$;
