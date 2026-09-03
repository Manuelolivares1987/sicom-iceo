-- ============================================================================
-- MIG508 · La OS se abre como una OT y muestra SUS actividades
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 03-09-2026, mirando /m/taller: «necesito que sea igual que cuando revisa las
-- actividades el operador cuando se planifica OT, y además tiene que ver qué
-- actividades — hoy no sale nada».
--
-- La tarjeta de la OS era un letrero: no se podía abrir. Acá se agrega el
-- detalle que alimenta la página /m/taller/os/[id]: la cabecera de la OS y sus
-- ACTIVIDADES — las no conformidades que resuelve, con la foto y la
-- observación del hallazgo (la de la NC, o la del ítem del checklist de donde
-- nació si la NC no la trae).
--
-- Solo lectura, para cualquier cuenta autenticada (regla MIG507: ver el
-- trabajo no es personal; mover el reloj sí). `mi_asignada` dice si la OS es
-- del técnico detrás de la sesión, para que la página muestre el reloj.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION rpc_taller_os_detalle(p_os_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_os JSONB; v_acts JSONB;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    SELECT jsonb_build_object(
             'os_id', o.id,
             'folio', o.folio,
             'titulo', o.titulo,
             'descripcion', o.descripcion,
             'estado', o.estado,
             'fecha_programada', o.fecha_programada,
             'horas_estimadas', o.horas_estimadas,
             'es_externo', COALESCE(o.es_externo, FALSE),
             'ot_id', ot.id,
             'ot_folio', ot.folio,
             'patente', a.patente,
             'equipo', a.nombre,
             'responsable', tt.nombre,
             'mi_asignada', EXISTS (
                 SELECT 1 FROM taller_os_asignacion x
                  WHERE x.os_id = o.id AND x.hasta IS NULL
                    AND x.tecnico_id = fn_taller_mi_tecnico_id()),
             'asignados', (
                 SELECT COALESCE(jsonb_agg(t2.nombre ORDER BY t2.nombre), '[]'::jsonb)
                   FROM taller_os_asignacion x JOIN taller_tecnicos t2 ON t2.id = x.tecnico_id
                  WHERE x.os_id = o.id AND x.hasta IS NULL))
      INTO v_os
      FROM taller_os o
      JOIN ordenes_trabajo ot ON ot.id = o.ot_id
      JOIN activos a ON a.id = ot.activo_id
      LEFT JOIN taller_tecnicos tt ON tt.id = o.responsable_id
     WHERE o.id = p_os_id;

    IF v_os IS NULL THEN RAISE EXCEPTION 'Esa OS no existe.'; END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'nc_id', nc.id,
             'descripcion', nc.descripcion,
             'severidad', nc.severidad,
             'foto_url', COALESCE(nc.foto_url, ii.foto_url),
             'observacion', ii.observacion,
             'resuelto', COALESCE(nc.resuelto, FALSE))
             ORDER BY COALESCE(nc.resuelto, FALSE), nc.created_at), '[]'::jsonb)
      INTO v_acts
      FROM taller_os_nc x
      JOIN no_conformidades nc ON nc.id = x.no_conformidad_id
      LEFT JOIN checklist_v2_instance_item ii ON ii.id = nc.checklist_item_ref
     WHERE x.os_id = p_os_id;

    RETURN v_os || jsonb_build_object('actividades', v_acts);
END;
$$;

REVOKE ALL ON FUNCTION rpc_taller_os_detalle(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_os_detalle(UUID) TO authenticated;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v JSONB; v_id UUID;
BEGIN
    SELECT id INTO v_id FROM taller_os WHERE estado NOT IN ('finalizada','anulada') LIMIT 1;
    IF v_id IS NULL THEN RAISE NOTICE 'sin OS abiertas para probar'; RETURN; END IF;
    -- Como superusuario auth.uid() es NULL: probar solo la consulta interna.
    SELECT jsonb_agg(jsonb_build_object('nc', nc.descripcion, 'foto', COALESCE(nc.foto_url, ii.foto_url) IS NOT NULL))
      INTO v
      FROM taller_os_nc x
      JOIN no_conformidades nc ON nc.id = x.no_conformidad_id
      LEFT JOIN checklist_v2_instance_item ii ON ii.id = nc.checklist_item_ref
     WHERE x.os_id = v_id;
    RAISE NOTICE 'actividades de la OS de prueba: %', COALESCE(v::text, '[]');
END
$mig$;

COMMIT;
