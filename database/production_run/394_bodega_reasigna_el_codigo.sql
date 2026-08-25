-- ============================================================================
-- MIG394 · Bodega puede corregir el código, no solo ponerlo la primera vez
-- ----------------------------------------------------------------------------
-- LO QUE PIDE BODEGA
-- Gustavo (Bodega Coquimbo), 25-08-2026: «que tenga la opción de reasignar otro
-- código para el ítem que pide el solicitante, ya que existen varios códigos de
-- un solo producto en varios ítem».
--
-- Y tiene razón, porque el catálogo está lleno de familias con muchos códigos:
--   · «CHALECO GEOLOGO CANVAS NARANJA» son 5 códigos (S, M, L, XL, XXL)
--   · «PLUMON PERMANENTE PILOT JUMBO 6600» son 4 (azul, negro, rojo, verde)
--   · «ADBLUE» son 5 productos distintos: el bidón de 20 L, el filtro, la tapa,
--     la cubierta protectora y el logo adhesivo
--
-- Quien pide escribe «adblue» o elige la talla que se le ocurre. Quien sabe cuál
-- es el código que hay que descontar es bodega, y lo sabe cuando tiene el vale
-- en la mano. Hasta hoy solo podía decirlo si el ítem venía SIN producto: una
-- vez amarrado, el código quedaba congelado aunque estuviera mal.
--
-- EL BACKEND YA LO PERMITÍA
-- `rpc_ticket_item_producto` nunca exigió que el producto estuviera vacío; sus
-- guardas son las correctas (vale no entregado ni anulado, y sin entrega parcial
-- —cambiar el producto después de descontar dejaría el descuento en otro
-- artículo). Lo que bloqueaba era la interfaz. Esta migración arregla las dos
-- cosas que sí estaban mal del lado de la base:
--
--   1. LA UNIDAD SE QUEDABA PEGADA. `COALESCE(unidad, ...)` sólo escribía la
--      unidad cuando estaba nula. Al reasignar de un producto «un» a uno «lt»,
--      el ítem seguía diciendo «un» y bodega descontaba en la unidad del
--      producto anterior.
--
--   2. EL RASTRO SE VOLVÍA MENTIRA. Al reasignar, «Pedido como: X» copiaba el
--      nombre del producto ANTERIOR —no lo que pidió el solicitante, que ya se
--      había perdido en el primer amarre—. Ahora la primera vez guarda lo que
--      se pidió, y los cambios posteriores se anotan como cambio de código.
--
--   3. EL RECURSO DE ORIGEN QUEDABA DESALINEADO. El ítem del vale y el recurso
--      del taller (`ot_recursos_solicitados`) son la misma decisión física. Si
--      bodega corrige el código en el vale, el seguimiento de repuestos seguía
--      mostrando el producto equivocado. Ahora se sincroniza.
-- ============================================================================

BEGIN;

-- ── 1. El ítem del vale ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_ticket_item_producto(
    p_item_id uuid,
    p_producto_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_rol TEXT := fn_user_rol();
    v_ti  RECORD;
    v_pr  RECORD;
    v_ant RECORD;
    v_nota TEXT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','bodeguero','operador_abastecimiento',
                     'jefe_mantenimiento','supervisor','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Rol % no autorizado', v_rol;
    END IF;

    SELECT bti.*, bt.estado AS ticket_estado INTO v_ti
      FROM bodega_ticket_items bti
      JOIN bodega_tickets bt ON bt.id = bti.ticket_id
     WHERE bti.id = p_item_id;
    IF v_ti.id IS NULL THEN RAISE EXCEPTION 'El ítem no existe'; END IF;
    IF v_ti.ticket_estado IN ('entregado','anulado') THEN
        RAISE EXCEPTION 'El vale ya está %: no se puede cambiar', v_ti.ticket_estado;
    END IF;
    -- La guarda de fondo: una vez que se descontó stock, cambiar el producto
    -- dejaría ese descuento colgando del artículo equivocado.
    IF v_ti.cantidad_entregada > 0 THEN
        RAISE EXCEPTION 'Este ítem ya tiene entrega parcial: cambiarle el producto dejaría el descuento en otro artículo';
    END IF;

    SELECT * INTO v_pr FROM productos WHERE id = p_producto_id;
    IF v_pr.id IS NULL THEN RAISE EXCEPTION 'El producto no existe'; END IF;

    IF v_ti.producto_id = p_producto_id THEN
        RETURN jsonb_build_object('success', TRUE, 'producto', v_pr.nombre,
                                  'codigo', v_pr.codigo, 'sin_cambio', TRUE);
    END IF;

    -- El rastro: la primera vez se guarda lo que pidió el solicitante; después,
    -- de qué código a qué código se movió. Nunca se pisa lo anterior.
    IF v_ti.producto_id IS NULL THEN
        v_nota := CASE
            WHEN COALESCE(v_ti.descripcion, '') <> ''
             AND COALESCE(v_ti.descripcion, '') <> v_pr.nombre
            THEN 'Pedido como: ' || v_ti.descripcion
            ELSE NULL END;
    ELSE
        SELECT codigo, nombre INTO v_ant FROM productos WHERE id = v_ti.producto_id;
        v_nota := 'Código cambiado por bodega: '
               || COALESCE(v_ant.codigo, v_ant.nombre, '(sin código)')
               || ' → ' || COALESCE(v_pr.codigo, v_pr.nombre);
    END IF;

    UPDATE bodega_ticket_items
       SET producto_id = p_producto_id,
           -- La unidad es la del producto que se va a despachar, siempre. Con
           -- COALESCE se quedaba la del producto anterior y bodega descontaba
           -- litros creyendo que eran unidades.
           unidad      = COALESCE(v_pr.unidad_medida, unidad),
           descripcion = v_pr.nombre,
           comentario  = CASE
               WHEN v_nota IS NULL THEN comentario
               ELSE COALESCE(comentario || ' · ', '') || v_nota END
     WHERE id = p_item_id;

    -- El recurso del taller y el ítem del vale son la misma decisión física:
    -- si bodega corrige el código acá, el seguimiento de repuestos tiene que
    -- mostrar lo mismo o el planificador compra el producto equivocado.
    IF v_ti.recurso_id IS NOT NULL THEN
        UPDATE ot_recursos_solicitados
           SET producto_id = p_producto_id,
               unidad      = COALESCE(v_pr.unidad_medida, unidad),
               updated_at  = NOW()
         WHERE id = v_ti.recurso_id;
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'producto', v_pr.nombre,
                              'codigo', v_pr.codigo,
                              'reasignado', v_ti.producto_id IS NOT NULL);
END;
$function$;

-- ── 2. El recurso del taller ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_ot_recurso_asignar_producto(
    p_recurso_id uuid,
    p_producto_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_rol TEXT := fn_user_rol();
    v_r RECORD; v_pr RECORD;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor',
                     'planificador','operador_abastecimiento','bodeguero') THEN
        RAISE EXCEPTION 'Sin permiso (rol: %)', v_rol; END IF;

    SELECT * INTO v_r FROM ot_recursos_solicitados WHERE id = p_recurso_id;
    IF v_r.id IS NULL THEN RAISE EXCEPTION 'Recurso no existe'; END IF;
    -- En 'en_vale' el cambio se hace sobre el ítem del vale (que además valida
    -- que no haya entrega parcial) y desde allá se sincroniza hacia acá.
    IF v_r.estado NOT IN ('solicitado','aprobado') THEN
        RAISE EXCEPTION 'El recurso ya está en % — el código se corrige en el vale', v_r.estado; END IF;

    SELECT * INTO v_pr FROM productos WHERE id = p_producto_id;
    IF v_pr.id IS NULL THEN RAISE EXCEPTION 'Producto no existe en el catálogo'; END IF;

    UPDATE ot_recursos_solicitados
       SET producto_id = p_producto_id,
           -- Misma corrección que en el vale: la unidad es la del producto
           -- elegido ahora, no la que arrastraba el anterior.
           unidad      = COALESCE(v_pr.unidad_medida, unidad),
           updated_at  = NOW()
     WHERE id = p_recurso_id;

    RETURN jsonb_build_object('success', true, 'producto', v_pr.nombre,
                              'codigo', v_pr.codigo,
                              'reasignado', v_r.producto_id IS NOT NULL);
END $function$;

-- ── 3. Cómo queda ─────────────────────────────────────────────────────────
DO $r$
DECLARE v_familias INT; v_items INT;
BEGIN
    SELECT count(*) INTO v_familias FROM (
        SELECT lower(trim(nombre)) FROM productos GROUP BY 1 HAVING count(*) > 1
    ) f;
    RAISE NOTICE 'Familias de producto con más de un código en el catálogo: %', v_familias;

    SELECT count(*) INTO v_items
      FROM bodega_ticket_items bti
      JOIN bodega_tickets bt ON bt.id = bti.ticket_id
     WHERE bt.estado NOT IN ('entregado','anulado') AND bti.cantidad_entregada = 0;
    RAISE NOTICE 'Ítems de vale que bodega ya puede recodificar: %', v_items;
END
$r$;

COMMIT;
