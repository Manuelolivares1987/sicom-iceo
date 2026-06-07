-- ============================================================================
-- SICOM-ICEO | Migracion 128 — Bitacora unificada por equipo
-- ----------------------------------------------------------------------------
-- Linea de tiempo unica por activo que une TODAS las atenciones / eventos:
--   OS legacy (historico previo) + OTs del sistema + auditorias de calidad +
--   informes de recepcion + diferidos (MEL) + checklists semanales del cliente.
-- El detalle profundo de cada OT (checklist, repuestos, fotos, tiempos) se
-- consulta on-demand desde el frontend con las tablas ya existentes.
-- IDEMPOTENTE (CREATE OR REPLACE VIEW).
-- ============================================================================

CREATE OR REPLACE VIEW v_bitacora_equipo AS
-- 1. OTs del sistema (todas)
SELECT
    o.activo_id,
    'ot'::TEXT                              AS tipo_registro,
    o.id                                    AS ref_id,
    COALESCE(o.fecha_termino, o.fecha_cierre_supervisor, o.fecha_inicio,
             o.fecha_programada::timestamptz, o.created_at) AS fecha,
    o.folio                                 AS titulo,
    (o.tipo::TEXT || ' · ' || o.estado::TEXT) AS subtitulo,
    NULLIF(o.observaciones,'')              AS detalle,
    o.costo_total                           AS costo,
    up.nombre_completo                      AS responsable
FROM ordenes_trabajo o
LEFT JOIN usuarios_perfil up ON up.id = o.responsable_id

UNION ALL
-- 2. OS legacy (historico importado)
SELECT
    h.activo_id, 'os_legacy'::TEXT, h.id,
    h.fecha_recepcion::timestamptz,
    ('OS ' || COALESCE(h.os_cqbo, h.os_numero, h.id::TEXT)),
    (CASE WHEN h.flag_correctivo THEN 'correctivo '
          WHEN h.flag_mant_prev THEN 'preventivo ' ELSE '' END
     || COALESCE('· '||h.faena,'')),
    (COALESCE('Cliente '||h.cliente||'. ','') ||
     COALESCE('Horómetro '||h.horometro||'. ','') ||
     COALESCE(h.num_trabajos::TEXT||' trabajos. ','') ||
     COALESCE('Cumpl. '||h.cumplimiento_pct||'%','')),
    NULL::NUMERIC,
    h.responsable
FROM historial_os_legacy h
WHERE h.activo_id IS NOT NULL

UNION ALL
-- 3. Auditorias de calidad
SELECT
    ac.activo_id, 'auditoria'::TEXT, ac.id,
    COALESCE(ac.fecha_auditoria, ac.created_at),
    'Auditoría de calidad',
    ac.resultado::TEXT,
    NULLIF(COALESCE(ac.motivo_rechazo, ac.observaciones),''),
    NULL::NUMERIC,
    NULL::TEXT
FROM auditorias_calidad ac

UNION ALL
-- 4. Informes de recepcion
SELECT
    ir.activo_id, 'recepcion'::TEXT, ir.id,
    COALESCE(ir.fecha_recepcion::timestamptz, ir.created_at),
    ('Recepción ' || COALESCE(ir.folio,'')),
    ir.estado::TEXT,
    NULLIF(ir.cliente_nombre,''),
    ir.total,
    NULL::TEXT
FROM informes_recepcion ir

UNION ALL
-- 5. Diferidos (MEL)
SELECT
    d.activo_id, 'diferido'::TEXT, d.id,
    d.fecha_diferimiento,
    ('Pendiente: ' || d.descripcion),
    (d.estado || ' · ' || d.severidad),
    (CASE WHEN d.diferible THEN 'Plazo '||COALESCE(d.plazo_fecha_limite::TEXT,'s/d')||' ('||COALESCE(d.plazo_origen,'s/d')||')'
          ELSE 'No diferible (bloquea operativo)' END),
    NULL::NUMERIC,
    NULL::TEXT
FROM items_diferidos d

UNION ALL
-- 6. Checklist semanal del cliente
SELECT
    cc.activo_id, 'checklist_cliente'::TEXT, cc.id,
    cc.fecha::timestamptz,
    'Checklist del cliente',
    (CASE WHEN cc.tiene_novedad THEN cc.items_no_ok::TEXT||' novedad(es)' ELSE 'sin novedad' END),
    NULLIF(COALESCE('Operador '||cc.operador_nombre, cc.observaciones),''),
    NULL::NUMERIC,
    cc.operador_nombre
FROM checklist_cliente_semanal cc;

-- Validacion
SELECT
    (SELECT count(*) FROM pg_views WHERE viewname='v_bitacora_equipo') AS vista_ok,
    (SELECT count(*) FROM v_bitacora_equipo) AS eventos_totales;
