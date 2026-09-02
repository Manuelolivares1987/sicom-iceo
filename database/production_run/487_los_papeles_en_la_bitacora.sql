-- ============================================================================
-- MIG487 · Los papeles del equipo, también en la bitácora
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 01-09-2026: «necesito que también se pueda editar... lo mismo en Bitácora», y
-- al preguntarle qué parte: «la parte documental de los equipos».
--
-- LO QUE FALTABA
-- La bitácora junta siete fuentes —OT, OS históricas, auditorías, recepciones,
-- pendientes, checklist del cliente e informes técnicos—. Los papeles del equipo
-- no estaban. Y son historia igual que lo demás: cuándo se emitió la revisión
-- técnica, cuándo se renovó el seguro, cuándo se cargó el certificado que hoy
-- está vigente. Sin eso, la línea de tiempo del camión tiene un hueco.
--
-- QUÉ ENTRA
-- Cada carga de un papel, fechada el día en que se emitió. Todas, no sólo la
-- vigente: una renovación es un evento del equipo y la anterior también lo fue.
-- Lo anulado no entra (MIG486): salió de circulación.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW v_bitacora_equipo AS
 SELECT o.activo_id,
    'ot'::text AS tipo_registro,
    o.id AS ref_id,
    COALESCE(o.fecha_termino, o.fecha_cierre_supervisor, o.fecha_inicio, o.fecha_programada::timestamp with time zone, o.created_at) AS fecha,
    o.folio AS titulo,
    (o.tipo::text || ' · '::text) || o.estado::text AS subtitulo,
    NULLIF(o.observaciones, ''::text) AS detalle,
    o.costo_total AS costo,
    up.nombre_completo AS responsable
   FROM ordenes_trabajo o
     LEFT JOIN usuarios_perfil up ON up.id = o.responsable_id
UNION ALL
 SELECT h.activo_id,
    'os_legacy'::text AS tipo_registro,
    h.id AS ref_id,
    h.fecha_recepcion::timestamp with time zone AS fecha,
    'OS '::text || COALESCE(h.os_cqbo, h.os_numero, h.id::text::character varying)::text AS titulo,
        CASE
            WHEN h.flag_correctivo THEN 'correctivo '::text
            WHEN h.flag_mant_prev THEN 'preventivo '::text
            ELSE ''::text
        END || COALESCE('· '::text || h.faena::text, ''::text) AS subtitulo,
    ((COALESCE(('Cliente '::text || h.cliente::text) || '. '::text, ''::text) || COALESCE(('Horómetro '::text || h.horometro) || '. '::text, ''::text)) || COALESCE(h.num_trabajos::text || ' trabajos. '::text, ''::text)) || COALESCE(('Cumpl. '::text || h.cumplimiento_pct) || '%'::text, ''::text) AS detalle,
    NULL::numeric AS costo,
    h.responsable
   FROM historial_os_legacy h
  WHERE h.activo_id IS NOT NULL
UNION ALL
 SELECT ac.activo_id,
    'auditoria'::text AS tipo_registro,
    ac.id AS ref_id,
    COALESCE(ac.fecha_auditoria, ac.created_at) AS fecha,
    'Auditoría de calidad'::character varying AS titulo,
    ac.resultado::text AS subtitulo,
    NULLIF(COALESCE(ac.motivo_rechazo, ac.observaciones), ''::text) AS detalle,
    NULL::numeric AS costo,
    NULL::text AS responsable
   FROM auditorias_calidad ac
UNION ALL
 SELECT ir.activo_id,
    'recepcion'::text AS tipo_registro,
    ir.id AS ref_id,
    COALESCE(ir.fecha_recepcion::timestamp with time zone, ir.created_at) AS fecha,
    'Recepción '::text || COALESCE(ir.folio, ''::character varying)::text AS titulo,
    ir.estado::text AS subtitulo,
    NULLIF(ir.cliente_nombre::text, ''::text) AS detalle,
    ir.total AS costo,
    NULL::text AS responsable
   FROM informes_recepcion ir
UNION ALL
 SELECT d.activo_id,
    'diferido'::text AS tipo_registro,
    d.id AS ref_id,
    d.fecha_diferimiento AS fecha,
    'Pendiente: '::text || d.descripcion AS titulo,
    (d.estado::text || ' · '::text) || d.severidad::text AS subtitulo,
        CASE
            WHEN d.diferible THEN ((('Plazo '::text || COALESCE(d.plazo_fecha_limite::text, 's/d'::text)) || ' ('::text) || COALESCE(d.plazo_origen, 's/d'::character varying)::text) || ')'::text
            ELSE 'No diferible (bloquea operativo)'::text
        END AS detalle,
    NULL::numeric AS costo,
    NULL::text AS responsable
   FROM items_diferidos d
UNION ALL
 SELECT cc.activo_id,
    'checklist_cliente'::text AS tipo_registro,
    cc.id AS ref_id,
    cc.fecha::timestamp with time zone AS fecha,
    'Checklist del cliente'::character varying AS titulo,
        CASE
            WHEN cc.tiene_novedad THEN cc.items_no_ok::text || ' novedad(es)'::text
            ELSE 'sin novedad'::text
        END AS subtitulo,
    NULLIF(COALESCE('Operador '::text || cc.operador_nombre::text, cc.observaciones), ''::text) AS detalle,
    NULL::numeric AS costo,
    cc.operador_nombre AS responsable
   FROM checklist_cliente_semanal cc
UNION ALL
 SELECT ii.activo_id,
    'informe_tecnico'::text AS tipo_registro,
    ii.id AS ref_id,
    COALESCE(ii.cerrado_at, ii.aprobado_at, ii.created_at) AS fecha,
    (('Informe técnico '::text || ii.folio::text) || ' v'::text) || ii.version::text AS titulo,
    ii.estado::text || COALESCE(' · '::text || ii.estado_salida::text, ''::text) AS subtitulo,
    NULLIF(ii.trabajo_realizado_resumen, ''::text) AS detalle,
    (( SELECT COALESCE(sum(m.costo_total), 0::numeric) AS "coalesce"
           FROM informe_intervencion_materiales m
          WHERE m.informe_id = ii.id)) + (( SELECT COALESCE(sum(mo.costo_total_snapshot), 0::numeric) AS "coalesce"
           FROM informe_intervencion_manoobra mo
          WHERE mo.informe_id = ii.id)) AS costo,
    upe.nombre_completo AS responsable
   FROM informes_intervencion ii
     LEFT JOIN usuarios_perfil upe ON upe.id = ii.ejecutor_principal_id
  WHERE ii.es_version_vigente AND ii.estado::text <> 'anulado'::text
UNION ALL
-- 8. [MIG487] Los papeles del equipo
SELECT
    c.activo_id,
    'documento'::text                       AS tipo_registro,
    c.id                                    AS ref_id,
    COALESCE(c.fecha_emision::timestamptz, c.created_at) AS fecha,
    fn_certificado_etiqueta(c.tipo::text, c.tipo_otro)::character varying AS titulo,
    (CASE
        WHEN c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= DATE '2099-01-01'
            THEN 'sin vencimiento'
        WHEN c.fecha_vencimiento < CURRENT_DATE
            THEN 'venció el ' || to_char(c.fecha_vencimiento, 'DD-MM-YYYY')
        ELSE 'vence el ' || to_char(c.fecha_vencimiento, 'DD-MM-YYYY')
     END
     || COALESCE(' · ' || NULLIF(c.entidad_certificadora, ''), ''))  AS subtitulo,
    NULLIF(concat_ws(' · ',
        NULLIF('N° ' || NULLIF(c.numero_certificado, ''), 'N° '),
        NULLIF(c.notas, '')), '')           AS detalle,
    NULL::numeric                           AS costo,
    (SELECT up.nombre_completo FROM usuarios_perfil up WHERE up.id = c.created_by) AS responsable
FROM certificaciones c
WHERE c.anulado_at IS NULL;


COMMENT ON VIEW v_bitacora_equipo IS
    'La historia completa de un equipo: OT, OS históricas, auditorías, '
    'recepciones, pendientes, checklist del cliente, informes técnicos y sus '
    'papeles. Es una vista de sólo lectura sobre ocho fuentes: lo que se corrige '
    'acá se corrige en su módulo.';

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_doc INT; v_tot INT; v_svbj INT;
BEGIN
    SELECT count(*) INTO v_doc FROM v_bitacora_equipo WHERE tipo_registro = 'documento';
    SELECT count(*) INTO v_tot FROM v_bitacora_equipo;
    SELECT count(*) INTO v_svbj FROM v_bitacora_equipo
     WHERE tipo_registro = 'documento'
       AND activo_id = '9ca9b860-d1ac-4fb0-97e8-af68d7f24f4a';
    RAISE NOTICE 'papeles en la bitácora: % de % eventos · el SVBJ-57 tiene %',
                 v_doc, v_tot, v_svbj;
END $mig$;

COMMIT;
