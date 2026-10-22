-- MIG638 · Bitácora y QR público con el mismo estado de papel que Control Documental
-- ============================================================================
-- Cuarta y quinta copia de la regla «qué papel rige y en qué estado» (la
-- ficha del equipo y Cumplimiento ya leen v_control_documental, PR #431):
--
--  · v_bitacora_equipo (rama documento): miraba solo la fecha. Un 2099 con
--    archivo decía «sin vencimiento» (Control Documental: «falta la fecha»),
--    la vigencia por horas no existía y las versiones renovadas se veían
--    igual que la vigente. Ahora: estado de v_certificacion_actual, horas
--    cuando vence por horómetro, y «reemplazado» para las versiones viejas.
--
--  · rpc_documentos_activo_publico (QR del cliente): «el tipo vence» salía
--    de fn_certificado_tipo_permanente y no de v_certificado_tipo_vence, y
--    avisaba «por vencer» a 45 días en vez de 30. Ahora lee la vista; solo
--    traduce no_aplica → 'permanente' (lo que esperan /equipo/[id]) y sigue
--    ocultando la factura (MIG611) y la fecha cuando no vale.
--
-- Mismas columnas y firma: ningún consumidor cambia.
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
 SELECT c.activo_id,
    'documento'::text AS tipo_registro,
    c.id AS ref_id,
    COALESCE(c.fecha_emision::timestamp with time zone, c.created_at) AS fecha,
    fn_certificado_etiqueta(c.tipo::text, c.tipo_otro)::character varying AS titulo,
        CASE
            -- [MIG638] Mismo estado que Control Documental (v_certificacion_actual).
            WHEN va.id IS NULL THEN 'reemplazado'
                 || COALESCE(' · vencía el ' || to_char(NULLIF(c.fecha_vencimiento, DATE '2099-12-31'), 'DD-MM-YYYY'), '')
            WHEN va.horometro_vence IS NOT NULL THEN
                 CASE WHEN va.estado_real::text = 'vencido' THEN 'venció a las ' ELSE 'vence a las ' END
                 || to_char(va.horometro_vence, 'FM999G999') || ' h'
            WHEN va.estado_real::text = 'sin_fecha' THEN 'falta la fecha — revisar el archivo'
            WHEN va.estado_real::text = 'no_aplica' THEN 'sin vencimiento'
            WHEN va.estado_real::text = 'vencido' THEN 'venció el ' || to_char(c.fecha_vencimiento, 'DD-MM-YYYY')
            WHEN va.estado_real::text = 'por_vencer' THEN 'por vencer: vence el ' || to_char(c.fecha_vencimiento, 'DD-MM-YYYY')
            ELSE 'vence el ' || to_char(c.fecha_vencimiento, 'DD-MM-YYYY')
        END || COALESCE(' · '::text || NULLIF(c.entidad_certificadora::text, ''::text), ''::text) AS subtitulo,
    NULLIF(concat_ws(' · '::text, NULLIF('N° '::text || NULLIF(c.numero_certificado::text, ''::text), 'N° '::text), NULLIF(c.notas, ''::text)), ''::text) AS detalle,
    NULL::numeric AS costo,
    ( SELECT up.nombre_completo
           FROM usuarios_perfil up
          WHERE up.id = c.created_by) AS responsable
   FROM certificaciones c
     LEFT JOIN v_certificacion_actual va ON va.id = c.id
  WHERE c.anulado_at IS NULL;

CREATE OR REPLACE FUNCTION public.rpc_documentos_activo_publico(p_activo_id uuid)
 RETURNS TABLE(tipo text, numero_certificado text, entidad text, fecha_emision date, fecha_vencimiento date, dias_restantes integer, estado text, archivo_url text, etiqueta text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT v.tipo::text, v.numero_certificado::text, v.entidad_certificadora::text,
         v.fecha_emision,
         -- La fecha no se muestra cuando no es la que manda (por horas, dudosa, 2099).
         CASE WHEN v.horometro_vence IS NOT NULL OR c.vigencia_dudosa
                OR v.fecha_vencimiento >= DATE '2099-01-01' THEN NULL
              ELSE v.fecha_vencimiento END,
         CASE WHEN v.horometro_vence IS NOT NULL OR c.vigencia_dudosa
                OR v.fecha_vencimiento >= DATE '2099-01-01' THEN NULL
              ELSE v.dias_restantes END,
         CASE WHEN v.estado_real::text = 'no_aplica' THEN 'permanente'
              ELSE v.estado_real::text END,
         v.archivo_url,
         v.etiqueta
    FROM v_certificacion_actual v
    JOIN certificaciones c ON c.id = v.id
   WHERE v.activo_id = p_activo_id
     -- [MIG611] La factura de compra no se muestra al cliente.
     AND NOT fn_portal_flota_tipo_oculto(v.tipo::text)
   ORDER BY v.doc_clave
$function$;

COMMIT;
