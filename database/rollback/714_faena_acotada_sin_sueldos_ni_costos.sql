-- Rollback MIG714: vistas a su definición original, sin políticas restrictivas, sin RLS en taller_bono_*, solo_su_faena apagado para los 5 de Franke.

CREATE OR REPLACE VIEW public.v_taller_bono_reparto AS
WITH cuadrilla AS (
         SELECT po.ot_id,
            c.tecnico_id,
            min(c.rol) AS rol,
            count(*)::numeric AS jornadas
           FROM taller_ot_cuadrilla c
             JOIN taller_plan_semanal_ots po ON po.id = c.plan_ot_id
          GROUP BY po.ot_id, c.tecnico_id
        ), tiempos AS (
         SELECT e.ot_id,
            e.tecnico_id,
            COALESCE(sum(e.tiempo_efectivo_segundos), 0::bigint)::numeric AS segundos
           FROM taller_ot_ejecuciones e
          WHERE e.tecnico_id IS NOT NULL
          GROUP BY e.ot_id, e.tecnico_id
        ), base AS (
         SELECT ot.id AS ot_id,
            ot.folio AS ot_folio,
            ot.estado::text AS ot_estado,
            ot.fecha_termino,
            ot.ejecutada_por_externo,
            cu.tecnico_id,
            t.nombre AS tecnico,
            cu.rol,
            cu.jornadas,
            COALESCE(ti.segundos, 0::numeric) AS segundos,
            count(*) OVER (PARTITION BY ot.id) AS n_cuadrilla,
            count(*) FILTER (WHERE COALESCE(ti.segundos, 0::numeric) > 0::numeric) OVER (PARTITION BY ot.id) AS n_con_tiempo,
            sum(COALESCE(ti.segundos, 0::numeric)) OVER (PARTITION BY ot.id) AS seg_total,
            sum(cu.jornadas) OVER (PARTITION BY ot.id) AS jor_total
           FROM cuadrilla cu
             JOIN ordenes_trabajo ot ON ot.id = cu.ot_id
             JOIN taller_tecnicos t ON t.id = cu.tecnico_id
             LEFT JOIN tiempos ti ON ti.ot_id = cu.ot_id AND ti.tecnico_id = cu.tecnico_id
          WHERE COALESCE(t.participa_en_bono, true)
        )
 SELECT ot_id,
    ot_folio,
    ot_estado,
    fecha_termino,
    ejecutada_por_externo,
    ejecutada_por_externo IS FALSE AS genera_bono,
    tecnico_id,
    tecnico,
    rol,
    segundos,
        CASE
            WHEN seg_total > 0::numeric AND n_con_tiempo = n_cuadrilla THEN round(segundos / seg_total, 4)
            WHEN jor_total > 0::numeric THEN round(jornadas / jor_total, 4)
            ELSE round(1.0 / n_cuadrilla::numeric, 4)
        END AS participacion,
        CASE
            WHEN seg_total > 0::numeric AND n_con_tiempo = n_cuadrilla THEN 'tiempo medido'::text
            WHEN jor_total > 0::numeric AND n_cuadrilla > 1 THEN 'jornadas asignadas'::text
            ELSE 'partes iguales'::text
        END AS base_reparto,
    jornadas
   FROM base b;

CREATE OR REPLACE VIEW public.v_reporte_incentivos AS
SELECT ip.id,
    ip.periodo_inicio,
    ip.periodo_fin,
    up.nombre_completo,
    up.rut,
    ip.cargo,
    f.nombre AS faena_nombre,
    ip.sueldo_base,
    ip.pct_incentivo_max,
    ip.iceo_valor,
    ip.iceo_clasificacion,
    ip.incentivo_habilitado,
    ip.tramo_pct_pago,
    ip.monto_incentivo_max,
    ip.monto_incentivo_real,
    ip.monto_incentivo_final,
    ip.bloqueantes_activos,
    ip.aprobado,
    ap.nombre_completo AS aprobado_por_nombre,
    ip.aprobado_en,
    ip.observaciones
   FROM incentivos_periodo ip
     JOIN usuarios_perfil up ON up.id = ip.usuario_id
     LEFT JOIN faenas f ON f.id = up.faena_id
     LEFT JOIN usuarios_perfil ap ON ap.id = ip.aprobado_por
  ORDER BY ip.periodo_inicio DESC, up.nombre_completo;

CREATE OR REPLACE VIEW public.v_costos_por_ot AS
SELECT ot.id AS ot_id,
    ot.folio,
    ot.tipo,
    ot.estado,
    ot.activo_id,
    ot.faena_id,
    ot.contrato_id,
    COALESCE(ot.costo_mano_obra, 0::numeric) AS costo_mano_obra,
    COALESCE(sum(mi.cantidad * mi.costo_unitario) FILTER (WHERE mi.tipo = ANY (ARRAY['salida'::tipo_movimiento_enum, 'merma'::tipo_movimiento_enum])), 0::numeric) AS costo_materiales_real,
    COALESCE(ot.costo_mano_obra, 0::numeric) + COALESCE(sum(mi.cantidad * mi.costo_unitario) FILTER (WHERE mi.tipo = ANY (ARRAY['salida'::tipo_movimiento_enum, 'merma'::tipo_movimiento_enum])), 0::numeric) AS costo_total_real,
    count(mi.id) FILTER (WHERE mi.tipo = ANY (ARRAY['salida'::tipo_movimiento_enum, 'merma'::tipo_movimiento_enum])) AS total_movimientos,
    ot.fecha_programada,
    ot.fecha_inicio,
    ot.fecha_termino
   FROM ordenes_trabajo ot
     LEFT JOIN movimientos_inventario mi ON mi.ot_id = ot.id
  GROUP BY ot.id;

CREATE OR REPLACE VIEW public.v_costos_por_activo AS
SELECT a.id AS activo_id,
    a.codigo,
    a.nombre,
    a.tipo,
    a.faena_id,
    count(DISTINCT ot.id) AS total_ots,
    COALESCE(sum(ot.costo_mano_obra), 0::numeric) AS costo_mano_obra_total,
    COALESCE(sum(mi.cantidad * mi.costo_unitario) FILTER (WHERE mi.tipo = ANY (ARRAY['salida'::tipo_movimiento_enum, 'merma'::tipo_movimiento_enum])), 0::numeric) AS costo_materiales_total,
    COALESCE(sum(ot.costo_mano_obra), 0::numeric) + COALESCE(sum(mi.cantidad * mi.costo_unitario) FILTER (WHERE mi.tipo = ANY (ARRAY['salida'::tipo_movimiento_enum, 'merma'::tipo_movimiento_enum])), 0::numeric) AS costo_total,
    count(DISTINCT ot.id) FILTER (WHERE ot.tipo = 'correctivo'::tipo_ot_enum) AS ots_correctivas,
    count(DISTINCT ot.id) FILTER (WHERE ot.tipo = 'preventivo'::tipo_ot_enum) AS ots_preventivas
   FROM activos a
     LEFT JOIN ordenes_trabajo ot ON ot.activo_id = a.id
     LEFT JOIN movimientos_inventario mi ON mi.ot_id = ot.id
  GROUP BY a.id;

CREATE OR REPLACE VIEW public.v_costos_por_faena AS
SELECT f.id AS faena_id,
    f.codigo,
    f.nombre,
    count(DISTINCT ot.id) AS total_ots,
    COALESCE(sum(ot.costo_mano_obra), 0::numeric) AS costo_mano_obra_total,
    COALESCE(sum(mi.cantidad * mi.costo_unitario) FILTER (WHERE mi.tipo = ANY (ARRAY['salida'::tipo_movimiento_enum, 'merma'::tipo_movimiento_enum])), 0::numeric) AS costo_materiales_total,
    COALESCE(sum(ot.costo_mano_obra), 0::numeric) + COALESCE(sum(mi.cantidad * mi.costo_unitario) FILTER (WHERE mi.tipo = ANY (ARRAY['salida'::tipo_movimiento_enum, 'merma'::tipo_movimiento_enum])), 0::numeric) AS costo_total,
    COALESCE(( SELECT sum(sb.cantidad * sb.costo_promedio) AS sum
           FROM stock_bodega sb
             JOIN bodegas b ON b.id = sb.bodega_id
          WHERE b.faena_id = f.id), 0::numeric) AS valorizacion_inventario
   FROM faenas f
     LEFT JOIN ordenes_trabajo ot ON ot.faena_id = f.id
     LEFT JOIN movimientos_inventario mi ON mi.ot_id = ot.id
  GROUP BY f.id;

DROP POLICY IF EXISTS mig714_rem_cargos ON public.cargos_incentivo;
DROP POLICY IF EXISTS mig714_rem_tramos ON public.tramos_incentivo;
DROP POLICY IF EXISTS mig714_rem_periodo ON public.incentivos_periodo;
DROP POLICY IF EXISTS mig714_irc_acotado ON public.informe_recepcion_costos;
DO $$ DECLARE t TEXT; BEGIN
  FOREACH t IN ARRAY ARRAY['taller_bono_acta','taller_bono_cargo','taller_bono_concepto','taller_bono_parametros','taller_bono_tramo_kpi'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS mig714_rem_sel ON public.%I', t);
    EXECUTE format('ALTER TABLE public.%I DISABLE ROW LEVEL SECURITY', t);
  END LOOP; END $$;
UPDATE public.usuarios_perfil SET solo_su_faena = false
 WHERE email IN ('jsimon@pillado.cl','mespinosa@pillado.cl','earqueros@pillado.cl','hcortes@pillado.cl','yrondon@pillado.cl');
DROP FUNCTION IF EXISTS public.fn_usuario_acotado();
DROP FUNCTION IF EXISTS public.fn_puede_ver_remuneraciones();
-- Movimiento de personal: Marco vuelve al taller de Coquimbo, Hernán vuelve a la bodega
UPDATE public.usuarios_perfil SET faena_id = NULL, rol = 'operador_taller', cargo = 'Mecánico A', solo_su_faena = false
 WHERE email = 'marco.diaz@sicom-iceo.cl';
UPDATE public.taller_tecnicos SET activo = true, participa_en_bono = true, motivo_sin_bono = NULL
 WHERE usuario_perfil_id = (SELECT id FROM usuarios_perfil WHERE email = 'marco.diaz@sicom-iceo.cl');
UPDATE public.taller_tecnico_cargo SET hasta = NULL
 WHERE tecnico_id IN (SELECT t.id FROM taller_tecnicos t JOIN usuarios_perfil u ON u.id = t.usuario_perfil_id WHERE u.email = 'marco.diaz@sicom-iceo.cl')
   AND desde = '2026-08-24';
UPDATE public.bodega_responsables SET activo = true WHERE email = 'hcortes@pillado.cl';
