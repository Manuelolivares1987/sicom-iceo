-- ============================================================================
-- SICOM-ICEO | 212 — Fotos en los ítems del vale (para el despacho de bodega)
-- ----------------------------------------------------------------------------
-- Pedido de Manuel (2026-07-09): el bodeguero debe gestionar el pedido en UN
-- solo lugar y viendo las fotos. La página Bodega → Pedidos consolida vales
-- por despachar + solicitudes; esta MIG le da a los ítems del vale sus fotos:
--   * la(s) foto(s) del recurso pedido por el operador/jefe (MIG197/210), o
--   * la foto de la NC si el ítem viene de nc_materiales.
-- También expone quién lo pidió y la descripción de la NC de origen.
-- Solo redefine v_bodega_ticket_items (columnas nuevas al final). IDEMPOTENTE.
-- ============================================================================

DROP VIEW IF EXISTS v_bodega_ticket_items;
CREATE VIEW v_bodega_ticket_items AS
SELECT i.id, i.ticket_id, i.producto_id, i.descripcion, i.unidad,
       i.cantidad_solicitada, i.cantidad_entregada,
       (i.cantidad_solicitada - i.cantidad_entregada) AS pendiente,
       i.nc_id, i.comentario,
       pr.codigo AS producto_codigo, pr.nombre AS producto_nombre, pr.unidad_medida,
       COALESCE(r.fotos, CASE WHEN nc.foto_url IS NOT NULL THEN ARRAY[nc.foto_url] END) AS fotos,
       r.solicitado_nombre,
       nc.descripcion AS nc_descripcion
FROM bodega_ticket_items i
LEFT JOIN productos pr ON pr.id = i.producto_id
LEFT JOIN ot_recursos_solicitados r ON r.id = i.recurso_id
LEFT JOIN no_conformidades nc ON nc.id = i.nc_id;
GRANT SELECT ON v_bodega_ticket_items TO authenticated;

-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'vista_con_fotos', (SELECT position('fotos' IN pg_get_viewdef('v_bodega_ticket_items'::regclass)) > 0),
    'items_con_foto', (SELECT count(*) FROM v_bodega_ticket_items WHERE fotos IS NOT NULL)
) AS resultado;

NOTIFY pgrst, 'reload schema';
