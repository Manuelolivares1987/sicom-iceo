-- ============================================================================
-- MIG337 · Lo primero de la lista de «CECO por dar de alta» no era un CECO
-- ----------------------------------------------------------------------------
-- Abriendo la pantalla de carga de Orpak, la lista de códigos que no están en
-- el maestro empezaba así:
--
--     79588870-5 ESMAX     118.636 L   24 movimientos
--     99520000-7 COPEC      16.284 L   43 movimientos
--
-- Ninguno de los dos es un CECO que haya que dar de alta. El primero es el RUT
-- de ESMAX y aparece porque el trasvasije de Mina a los camiones aljibe se
-- registra a su nombre: es combustible que se mueve entre estanques de la
-- misma faena, no se le vende a nadie. El segundo es Copec y son las
-- transacciones de calibración, que existen para verificar el surtidor.
--
-- Los dos juntos son 134.920 litros y 67 movimientos encabezando una lista que
-- debería mostrar transportistas. El daño no es cosmético: quien la abra va a
-- empezar por arriba, va a intentar crear una ficha para «ESMAX» y va a
-- terminar imputándole a un tercero un movimiento interno.
--
-- Un movimiento que por definición no se imputa no tiene por qué aparecer en
-- la lista de lo que falta imputar.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW public.v_comb_orpak_ceco_desconocido AS
SELECT t.faena_id, t.ceco_codigo,
       min(t.departamento) AS departamento,
       count(*) AS transacciones,
       sum(t.litros) AS litros,
       min(t.dia_cierre) AS desde, max(t.dia_cierre) AS hasta
FROM combustible_orpak_transaccion t
WHERE t.ceco_id IS NULL AND t.ceco_codigo IS NOT NULL
  -- El trasvasije mueve combustible entre estanques de la misma faena y la
  -- calibracion verifica el surtidor: ninguno se le cobra a nadie.
  AND t.clasificacion NOT IN ('TRASVASIJE', 'RECIRCULACION', 'CALIBRACION')
GROUP BY t.faena_id, t.ceco_codigo;

-- El contador del tablero cuenta lo mismo que muestra la lista. Si no, el
-- numero y el detalle se contradicen y nadie sabe cual creer.
CREATE OR REPLACE VIEW public.v_comb_faena_control_diario AS
WITH grupos AS (
    SELECT g.faena_id, g.fecha,
           sum(g.v_fis) AS v_fis, sum(g.v_mec) AS v_mec, sum(g.var1) AS var1,
           count(*) FILTER (WHERE g.resultado = 'investigar')::integer AS grupos_investigar,
           count(*) FILTER (WHERE g.resultado = 'atencion')::integer   AS grupos_atencion,
           count(*) FILTER (WHERE g.resultado = 'incompleto')::integer AS grupos_sin_contador,
           max(g.estado) AS estado_cierre
      FROM v_comb_faena_cuadre_grupo g
     GROUP BY g.faena_id, g.fecha
), puntos AS (
    SELECT p.faena_id, p.fecha,
           count(*) FILTER (WHERE NOT p.sin_medicion AND p.mf IS NOT NULL)::integer AS puntos_medidos,
           count(*)::integer AS puntos_total,
           max(p.medido_por) AS medido_por
      FROM v_comb_faena_cierre_punto p
     GROUP BY p.faena_id, p.fecha
), despachos AS (
    SELECT d.faena_id, d.fecha,
           sum(d.litros) FILTER (WHERE d.tipo_movimiento = 'venta')      AS litros_venta,
           sum(d.litros) FILTER (WHERE d.tipo_movimiento = 'trasvasije') AS litros_trasvasije,
           sum(d.litros) AS litros_total,
           count(*)::integer AS despachos,
           count(*) FILTER (WHERE d.ceco_id IS NULL
                              AND COALESCE(d.ceco_texto,'') = ''
                              AND d.tipo_movimiento = 'venta')::integer AS sin_ceco,
           count(*) FILTER (WHERE d.equipo_id IS NULL AND d.equipo_texto IS NOT NULL)::integer
               AS equipo_sin_mapear
      FROM combustible_faena_despachos d
     WHERE NOT d.anulado
     GROUP BY d.faena_id, d.fecha
), orpak AS (
    SELECT t.faena_id, t.dia_cierre AS fecha,
           count(*)::integer AS transacciones,
           sum(t.litros) FILTER (WHERE t.clasificacion NOT IN ('TRASVASIJE','RECIRCULACION')) AS litros_venta,
           sum(t.litros) FILTER (WHERE t.clasificacion = 'TRASVASIJE') AS litros_trasvasije,
           sum(t.litros) AS litros_total,
           count(*) FILTER (WHERE t.ceco_codigo IS NULL
                              AND t.clasificacion NOT IN ('TRASVASIJE','RECIRCULACION','CALIBRACION'))::integer
               AS sin_codigo,
           count(*) FILTER (WHERE t.ceco_codigo IS NOT NULL AND t.ceco_id IS NULL
                              AND t.clasificacion NOT IN ('TRASVASIJE','RECIRCULACION','CALIBRACION'))::integer
               AS fuera_del_maestro
      FROM combustible_orpak_transaccion t
     GROUP BY t.faena_id, t.dia_cierre
), recep AS (
    SELECT r.faena_id, r.fecha,
           sum(r.litros_recibidos) AS litros_recibidos,
           count(*)::integer AS recepciones,
           count(*) FILTER (WHERE r.estado <> 'confirmada')::integer AS recepciones_sin_confirmar,
           count(*) FILTER (WHERE r.diferencia_vs_guia IS NOT NULL
                              AND abs(r.diferencia_vs_guia) > 0)::integer AS recepciones_con_diferencia
      FROM v_comb_faena_recepcion r
     GROUP BY r.faena_id, r.fecha
)
SELECT COALESCE(gr.faena_id, de.faena_id, re.faena_id, op.faena_id) AS faena_id,
       COALESCE(gr.fecha, de.fecha, re.fecha, op.fecha) AS fecha,
       gr.estado_cierre, pu.medido_por, pu.puntos_medidos, pu.puntos_total,
       gr.grupos_investigar AS puntos_fuera_tolerancia,
       gr.grupos_atencion,
       gr.grupos_sin_contador AS puntos_sin_contador,
       gr.v_fis, gr.v_mec, gr.var1,
       CASE
         WHEN gr.fecha IS NULL THEN 'sin_cierre'
         WHEN gr.estado_cierre <> 'firmado' THEN 'borrador'
         WHEN gr.grupos_investigar > 0 THEN 'revisar'
         WHEN gr.grupos_sin_contador > 0 THEN 'incompleto'
         ELSE 'cuadrado'
       END AS volumen_estado,
       COALESCE(de.despachos, 0) + COALESCE(op.transacciones, 0) AS despachos,
       COALESCE(de.litros_total, 0)      + COALESCE(op.litros_total, 0)      AS litros_total,
       COALESCE(de.litros_venta, 0)      + COALESCE(op.litros_venta, 0)      AS litros_venta,
       COALESCE(de.litros_trasvasije, 0) + COALESCE(op.litros_trasvasije, 0) AS litros_trasvasije,
       COALESCE(de.sin_ceco, 0) + COALESCE(op.sin_codigo, 0) AS sin_ceco,
       COALESCE(op.fuera_del_maestro, 0) AS ceco_fuera_del_maestro,
       de.equipo_sin_mapear,
       COALESCE(op.transacciones, 0) AS transacciones_orpak,
       CASE
         WHEN COALESCE(de.despachos, 0) + COALESCE(op.transacciones, 0) = 0 THEN 'sin_datos'
         WHEN COALESCE(de.sin_ceco, 0) + COALESCE(op.sin_codigo, 0) > 0 THEN 'incompleta'
         WHEN COALESCE(op.fuera_del_maestro, 0) > 0 THEN 'por_registrar'
         ELSE 'completa'
       END AS imputacion_estado,
       re.recepciones, re.litros_recibidos,
       re.recepciones_sin_confirmar, re.recepciones_con_diferencia
  FROM grupos gr
  LEFT JOIN puntos pu ON pu.faena_id = gr.faena_id AND pu.fecha = gr.fecha
  FULL JOIN despachos de ON de.faena_id = gr.faena_id AND de.fecha = gr.fecha
  FULL JOIN orpak op ON op.faena_id = COALESCE(gr.faena_id, de.faena_id)
                    AND op.fecha    = COALESCE(gr.fecha, de.fecha)
  FULL JOIN recep re ON re.faena_id = COALESCE(gr.faena_id, de.faena_id, op.faena_id)
                    AND re.fecha    = COALESCE(gr.fecha, de.fecha, op.fecha);

COMMIT;
