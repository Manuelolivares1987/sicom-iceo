-- ============================================================================
-- MIG695 · Gustavo (bodega Coquimbo) vuelve a recibir las alertas de Franke
-- ----------------------------------------------------------------------------
-- Manuel, 15-11-2026: «Gustavo debe ver si falta algo o queda poco en Franke;
-- él ve todas las bodegas». El encargado de la bodega de Franke sigue siendo el
-- supervisor de turno (MIG694): Gustavo NO opera (no saca, no recibe, no
-- cuenta), pero sí recibe el aviso de stock bajo (correo + campanita) para
-- reponer desde Coquimbo. Ver todas las bodegas ya lo tiene por su rol
-- (fn_bodega_puede_ver incluye bodeguero).
-- ============================================================================
UPDATE public.bodega_responsables r
   SET activo = true, puede_operar = false, recibe_alertas = true, tipo_correo = 'para',
       nombre = 'Gustavo (bodega Coquimbo, repone)'
  FROM public.bodegas b
 WHERE b.id = r.bodega_id AND b.codigo = 'BOD-FRK-F01' AND r.email = 'bodegacentral@pilladoempresas.cl';

SELECT r.nombre, r.email, r.puede_operar, r.recibe_alertas, r.tipo_correo, r.activo, (r.usuario_id IS NOT NULL) AS con_cuenta
  FROM public.bodega_responsables r JOIN public.bodegas b ON b.id = r.bodega_id
 WHERE b.codigo = 'BOD-FRK-F01' ORDER BY r.puede_operar DESC, r.nombre;
