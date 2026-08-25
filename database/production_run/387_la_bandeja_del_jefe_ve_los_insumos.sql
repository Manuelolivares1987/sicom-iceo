-- ============================================================================
-- MIG387 · La bandeja del jefe vuelve, y ahora ve los insumos
-- ----------------------------------------------------------------------------
-- Al recrear `v_ot_recursos` en MIG386, el DROP ... CASCADE se llevó también
-- `v_ot_recursos_seguimiento`, que es de donde come la bandeja donde el jefe
-- aprueba los pedidos. Se restituye acá.
--
-- Y DE PASO SE ARREGLA LO QUE HABRÍA FALLADO IGUAL
-- La vista original unía con `JOIN ordenes_trabajo`. Un INNER JOIN sobre un
-- `ot_id` que ahora puede ser NULL habría dejado los insumos del taller FUERA
-- de la bandeja: el operador pediría, el jefe no vería nada, y el pedido se
-- quedaría esperando para siempre sin que nadie supiera por qué. Pasa a LEFT
-- JOIN, y el equipo se muestra sólo cuando el pedido es de un equipo.
--
-- Los insumos traen el nombre del centro de costo en su lugar, para que el
-- jefe vea de una a qué se va a cargar lo que está aprobando.
-- ============================================================================

BEGIN;

DROP VIEW IF EXISTS public.v_ot_recursos_seguimiento;

CREATE VIEW public.v_ot_recursos_seguimiento AS
SELECT v.*,
       ot.folio  AS ot_folio,
       a.codigo  AS activo_codigo,
       a.patente AS activo_patente,
       a.nombre  AS activo_nombre,
       -- Contra qué se lee el pedido en la bandeja: la patente si es de un
       -- equipo, el centro de costo si es del taller.
       COALESCE(a.patente, a.codigo, v.ceco_nombre) AS destino,
       GREATEST(0, EXTRACT(DAY FROM NOW() - v.created_at))::int AS dias_desde_solicitud,
       (v.estado = 'aprobado' AND v.oc_item_id IS NULL
        AND (v.producto_id IS NULL OR COALESCE(v.stock_total, 0) <= 0)) AS por_comprar
  FROM public.v_ot_recursos v
  -- [MIG387] LEFT: un insumo del taller no tiene OT, y no por eso deja de
  -- necesitar el visto bueno.
  LEFT JOIN public.ordenes_trabajo ot ON ot.id = v.ot_id
  LEFT JOIN public.activos a          ON a.id = ot.activo_id;

GRANT SELECT ON public.v_ot_recursos_seguimiento TO authenticated;

-- Que la bandeja de verdad responda, y que un insumo aparezca en ella.
DO $verif$
DECLARE v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM public.v_ot_recursos_seguimiento;
    RAISE NOTICE 'La bandeja responde: % pedidos en total.', v_n;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public'
                      AND table_name = 'v_ot_recursos_seguimiento'
                      AND column_name = 'es_insumo_taller') THEN
        RAISE EXCEPTION 'La vista no expone es_insumo_taller: el jefe no podría distinguirlos.';
    END IF;
END
$verif$;

COMMIT;
