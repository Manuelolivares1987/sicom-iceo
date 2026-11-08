-- 675 — Stock comprometido: lo pedido en vales abiertos ya no está disponible (Manuel 08-11-2026,
-- benchmark MaintainX: Available = In Stock − Committed).
-- destructivo-ok: DROP FUNCTION rpc_buscar_insumos para cambiar sus columnas de salida (agrega
-- comprometido y disponible); se recrea igual, con las mismas columnas primero.
--
-- El stock baja recién cuando bodega ENTREGA el vale. Mientras tanto, dos OT podían pedir el
-- último filtro y ambas lo veían «en bodega». Al 08-11: 15 productos comprometidos en 17 vales
-- abiertos y en 5 lo pedido ya superaba el stock físico.
--
--   * v_stock_disponible: por producto, físico (todas las bodegas) − comprometido (vales
--     emitidos/parciales, lo que falta entregar) = disponible.
--   * v_bodega_ticket_disponibilidad: semáforo por vale abierto. El stock se reparte por orden
--     de llegada (el vale más antiguo primero): completo / parcial / sin_stock.
--   * rpc_buscar_insumos muestra disponible además del físico.

CREATE OR REPLACE VIEW v_stock_disponible AS
WITH fis AS (
    SELECT producto_id, sum(cantidad) AS fisico FROM stock_bodega GROUP BY producto_id
), comp AS (
    SELECT ti.producto_id,
           sum(ti.cantidad_solicitada - ti.cantidad_entregada) AS comprometido,
           count(DISTINCT t.id) AS vales_abiertos
      FROM bodega_ticket_items ti
      JOIN bodega_tickets t ON t.id = ti.ticket_id
     WHERE t.estado IN ('emitido', 'parcial')
       AND ti.producto_id IS NOT NULL
       AND ti.cantidad_solicitada > ti.cantidad_entregada
     GROUP BY ti.producto_id
)
SELECT COALESCE(f.producto_id, c.producto_id) AS producto_id,
       COALESCE(f.fisico, 0) AS fisico,
       COALESCE(c.comprometido, 0) AS comprometido,
       COALESCE(f.fisico, 0) - COALESCE(c.comprometido, 0) AS disponible,
       COALESCE(c.vales_abiertos, 0) AS vales_abiertos
  FROM fis f
  FULL JOIN comp c ON c.producto_id = f.producto_id;

COMMENT ON VIEW v_stock_disponible IS
    '[MIG675] Físico − comprometido en vales abiertos. Disponible negativo = sobrecomprometido.';

CREATE OR REPLACE VIEW v_bodega_ticket_disponibilidad AS
WITH lineas AS (
    SELECT t.id AS ticket_id, t.created_at, ti.id AS item_id, ti.producto_id,
           ti.cantidad_solicitada - ti.cantidad_entregada AS pendiente
      FROM bodega_tickets t
      JOIN bodega_ticket_items ti ON ti.ticket_id = t.id
     WHERE t.estado IN ('emitido', 'parcial')
       AND ti.cantidad_solicitada > ti.cantidad_entregada
), cola AS (
    -- Lo que piden los vales MÁS ANTIGUOS por el mismo producto, antes que esta línea.
    SELECT l.*,
           COALESCE(sum(l.pendiente) OVER (PARTITION BY l.producto_id
                    ORDER BY l.created_at, l.item_id
                    ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS antes
      FROM lineas l
     WHERE l.producto_id IS NOT NULL
), linea_estado AS (
    SELECT c.ticket_id, c.item_id,
           CASE WHEN COALESCE(s.fisico, 0) - c.antes >= c.pendiente THEN 'completo'
                WHEN COALESCE(s.fisico, 0) - c.antes > 0           THEN 'parcial'
                ELSE 'sin_stock' END AS estado
      FROM cola c
      LEFT JOIN v_stock_disponible s ON s.producto_id = c.producto_id
)
SELECT l.ticket_id,
       count(*) AS lineas,
       count(*) FILTER (WHERE e.estado = 'completo') AS completas,
       count(*) FILTER (WHERE e.estado = 'parcial') AS parciales,
       count(*) FILTER (WHERE e.estado = 'sin_stock') AS sin_stock,
       count(*) FILTER (WHERE l.producto_id IS NULL) AS sin_producto,
       CASE WHEN count(*) FILTER (WHERE e.estado IN ('parcial', 'sin_stock')) = 0
                 AND count(*) FILTER (WHERE l.producto_id IS NULL) = 0 THEN 'completo'
            WHEN count(*) FILTER (WHERE e.estado IN ('completo', 'parcial')) > 0 THEN 'parcial'
            ELSE 'sin_stock' END AS disponibilidad
  FROM lineas l
  LEFT JOIN linea_estado e ON e.item_id = l.item_id
 GROUP BY l.ticket_id;

COMMENT ON VIEW v_bodega_ticket_disponibilidad IS
    '[MIG675] Semáforo por vale abierto: el stock se reparte por orden de llegada.';

GRANT SELECT ON v_stock_disponible, v_bodega_ticket_disponibilidad TO authenticated;

DROP FUNCTION IF EXISTS public.rpc_buscar_insumos(text, integer);

CREATE FUNCTION public.rpc_buscar_insumos(p_q text, p_limit integer DEFAULT 10)
 RETURNS TABLE(id uuid, codigo character varying, nombre character varying, unidad_medida character varying,
               stock numeric, comprometido numeric, disponible numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT p.id, p.codigo, p.nombre, p.unidad_medida,
           COALESCE(s.fisico, 0)       AS stock,
           COALESCE(s.comprometido, 0) AS comprometido,
           COALESCE(s.disponible, 0)   AS disponible
      FROM productos p
      LEFT JOIN v_stock_disponible s ON s.producto_id = p.id
     WHERE btrim(COALESCE(p_q,'')) <> ''
       AND (p.codigo ILIKE '%'||btrim(p_q)||'%' OR p.nombre ILIKE '%'||btrim(p_q)||'%')
     ORDER BY (COALESCE(s.disponible, 0) > 0) DESC, (COALESCE(s.fisico, 0) > 0) DESC, p.nombre
     LIMIT GREATEST(COALESCE(p_limit, 10), 1);
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_buscar_insumos(text, integer) TO authenticated;

NOTIFY pgrst, 'reload schema';
