-- ============================================================================
-- MIG404 · «Pedir → aprobar: 0 min» era mentira, y de las que pagan sueldos
-- ----------------------------------------------------------------------------
-- CÓMO APARECIÓ
-- Mirando la pantalla nueva de tiempos como la miraría cualquiera, el primer
-- número decía:
--
--     PEDIR → APROBAR: 0 min · sobre 31 casos
--
-- Cero minutos de respuesta de la jefatura sobre treinta y un casos. Suena a
-- récord mundial. Es un artefacto.
--
-- POR QUÉ
-- De los 31 recursos, **20 los agrega la propia jefatura** con
-- `rpc_ot_recurso_agregar`, que nace ya aprobado: `created_at` y `validado_at`
-- se escriben en el mismo instante. Esos 20 miden cero por construcción, no por
-- rapidez. Al mezclarlos con los 11 que sí pidió un operador, la mediana se va
-- a cero y tapa el número real:
--
--     agregado por el jefe → 20 casos · mediana 0,00 h  (imposible que sea otra)
--     pedido por el operador → 11 casos · mediana 0,89 h · promedio 133,2 h
--
-- El tiempo de respuesta REAL es 53 minutos de mediana, con una cola muy larga.
-- Ese es el número que sirve; el otro es ruido con cara de logro.
--
-- POR QUÉ IMPORTA MÁS QUE UN DETALLE
-- Manuel dijo que estos parámetros impactan en la remuneración. Una métrica que
-- muestra cero porque está midiendo un reloj que nunca corrió es exactamente la
-- clase de número que se convierte en una decisión injusta.
--
-- QUÉ SE HACE
-- La vista expone `lo_pidio_el_operador`, y el tramo «pedir → aprobar» sólo se
-- calcula cuando efectivamente hubo alguien esperando una respuesta. Lo que
-- agrega la jefatura no desaparece —sigue en la tabla, y su tramo hacia el vale
-- y hacia la entrega se mide igual— pero deja de contaminar el tiempo de
-- respuesta.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW public.v_taller_tiempo_repuesto AS
SELECT
    r.id                        AS recurso_id,
    o.folio                     AS ot_folio,
    a.codigo                    AS activo_codigo,
    a.patente                   AS activo_patente,
    COALESCE(pr.nombre, r.descripcion) AS que_se_pidio,
    pr.codigo                   AS producto_codigo,
    r.estado,
    COALESCE(r.solicitado_nombre, us.nombre_completo) AS lo_pidio,
    uv.nombre_completo          AS lo_aprobo,
    r.created_at                AS pedido_at,
    r.validado_at               AS aprobado_at,
    bt.folio                    AS vale_folio,
    bt.created_at               AS vale_at,
    bt.entregado_at,
    -- [MIG404] Sólo hay tiempo de respuesta si alguien estuvo esperando una.
    -- Lo que la jefatura agrega nace aprobado en el mismo instante: medirlo da
    -- cero por construcción y arrastra la mediana de todos los demás.
    CASE WHEN NOT COALESCE(r.agregado_por_jefe, false)
         THEN round((EXTRACT(EPOCH FROM (r.validado_at - r.created_at)) / 3600.0)::numeric, 1)
         ELSE NULL END          AS h_pedir_a_aprobar,
    round((EXTRACT(EPOCH FROM (bt.created_at   - r.validado_at)) / 3600.0)::numeric, 1) AS h_aprobar_a_vale,
    round((EXTRACT(EPOCH FROM (bt.entregado_at - bt.created_at)) / 3600.0)::numeric, 1) AS h_vale_a_entrega,
    round((EXTRACT(EPOCH FROM (bt.entregado_at - r.created_at))  / 3600.0)::numeric, 1) AS h_total,
    CASE WHEN bt.entregado_at IS NULL
         THEN round((EXTRACT(EPOCH FROM (NOW() - r.created_at)) / 3600.0)::numeric, 1)
         ELSE NULL END          AS h_esperando,
    -- Quién lo originó, para que la pantalla pueda decirlo en vez de mezclar.
    NOT COALESCE(r.agregado_por_jefe, false) AS lo_pidio_el_operador
FROM ot_recursos_solicitados r
LEFT JOIN ordenes_trabajo o ON o.id = r.ot_id
LEFT JOIN activos a ON a.id = o.activo_id
LEFT JOIN productos pr ON pr.id = r.producto_id
LEFT JOIN usuarios_perfil us ON us.id = r.solicitado_por
LEFT JOIN usuarios_perfil uv ON uv.id = r.validado_por
LEFT JOIN bodega_tickets bt ON bt.id = r.ticket_id;

COMMENT ON VIEW public.v_taller_tiempo_repuesto IS
  'MIG404: el embudo del repuesto en horas. h_pedir_a_aprobar sólo se calcula para lo que pidió un operador: lo que agrega la jefatura nace aprobado y mide cero por construcción.';

GRANT SELECT ON public.v_taller_tiempo_repuesto TO authenticated;

DO $r$
DECLARE r RECORD;
BEGIN
    SELECT count(*) FILTER (WHERE lo_pidio_el_operador) AS del_operador,
           count(*) FILTER (WHERE NOT lo_pidio_el_operador) AS del_jefe,
           round((percentile_cont(0.5) WITHIN GROUP (ORDER BY h_pedir_a_aprobar))::numeric,2) AS mediana_real
      INTO r FROM v_taller_tiempo_repuesto;
    RAISE NOTICE 'Pedidos del operador: % · agregados por la jefatura: %', r.del_operador, r.del_jefe;
    RAISE NOTICE 'Tiempo de respuesta real (mediana): % h — antes la pantalla decía 0 min', r.mediana_real;
END
$r$;

COMMIT;
