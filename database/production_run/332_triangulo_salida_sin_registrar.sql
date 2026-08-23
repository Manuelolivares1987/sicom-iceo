-- ============================================================================
-- MIG332 · «Sin registro» estaba tapando el hallazgo más importante
-- ----------------------------------------------------------------------------
-- Corriendo el triángulo sobre junio 2026 real, el camión 67 el día 5 quedó
-- así:
--     varilla 1.120 L · contador 1.120 L · Orpak 0 L · diagnóstico «sin_registro»
--
-- Las dos medidas físicas coinciden a la perfección: salieron 1.120 litros del
-- camión, sin ninguna duda. Y el sistema no tiene ni una transacción. Eso no
-- es «sin registro» en el sentido de «no hay datos»: es combustible que salió
-- del estanque y que nadie sabe a quién se le entregó. Es exactamente lo que
-- un control de inventario existe para detectar, y estaba etiquetado igual que
-- un punto que ese día no se usó.
--
-- Ahora se separan los dos casos, que no se parecen en nada:
--     sin movimiento        el punto no operó — no hay nada que revisar
--     salida sin registrar  salió combustible y no hay a quién imputarlo
--
-- En los nueve días de junio ese único evento explica −1.020 L de los −1.020 L
-- acumulados del camión 67, que es el 2,7 % de su flujo del mes: el único
-- grupo del cierre que quedó en «investigar».
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW public.v_comb_faena_triangulo AS
SELECT m.faena_id, m.fecha, m.grupo_cuadre AS grupo,
       string_agg(DISTINCT m.estanque_nombre, ' + ' ORDER BY m.estanque_nombre) AS puntos,
       sum(m.v_fis)             AS por_varilla,
       sum(m.v_mec)             AS por_contador,
       sum(m.salida_registrada) AS por_sistema,
       min(m.fuente_salida)     AS fuente,
       sum(m.var1)                    AS contador_menos_varilla,
       sum(m.contador_menos_sistema)  AS contador_menos_sistema,
       sum(m.salida_registrada) - sum(m.v_fis) AS sistema_menos_varilla,
       sum(m.variacion_estacion) AS variacion_estacion,
       CASE
         WHEN sum(m.medidores_leidos) < sum(m.medidores_total) THEN 'incompleto'
         -- Un punto que no operó y un punto del que salió combustible sin
         -- registrar se veían igual. No se parecen en nada.
         WHEN min(m.fuente_salida) = 'sin_registro'
              AND abs(sum(m.v_mec)) <= COALESCE(c.tolerancia_ok_lt, 200)
              AND abs(sum(m.v_fis)) <= COALESCE(c.tolerancia_ok_lt, 200)
              THEN 'sin movimiento'
         WHEN min(m.fuente_salida) = 'sin_registro' THEN 'salida sin registrar'
         WHEN abs(sum(m.var1)) <= COALESCE(c.tolerancia_ok_lt, 200)
          AND abs(sum(m.contador_menos_sistema)) <= COALESCE(c.tolerancia_ok_lt, 200)
              THEN 'las tres coinciden'
         WHEN abs(sum(m.contador_menos_sistema)) <= COALESCE(c.tolerancia_ok_lt, 200)
              THEN 'falla en el estanque'
         WHEN abs(sum(m.var1)) <= COALESCE(c.tolerancia_ok_lt, 200)
              THEN 'falla en el registro'
         ELSE 'dia mal medido'
       END AS diagnostico
FROM v_comb_faena_mini_cierre m
LEFT JOIN combustible_faena_config c ON c.faena_id = m.faena_id
GROUP BY m.faena_id, m.fecha, m.grupo_cuadre, c.tolerancia_ok_lt;

COMMENT ON VIEW public.v_comb_faena_triangulo IS
  'Dos de las tres medidas siempre se parecen; la que se desvia dice que fallo. Si el contador coincide con Orpak, el problema esta en el estanque (fuga, agua, aforo). Si coincide con la varilla, el problema esta en el registro. Si las dos fisicas coinciden y el sistema no tiene nada, salio combustible sin imputar. MIG330/MIG332.';

-- Un punto que no operó no ensucia la serie del mes.
CREATE OR REPLACE VIEW public.v_comb_faena_variacion_acumulada AS
WITH dias AS (
    SELECT t.faena_id, t.grupo, t.fecha,
           date_trunc('month', t.fecha)::date AS mes,
           t.variacion_estacion, t.contador_menos_varilla, t.por_contador,
           t.diagnostico
      FROM v_comb_faena_triangulo t
     WHERE t.diagnostico NOT IN ('incompleto', 'sin movimiento')
)
SELECT d.faena_id, d.mes, d.grupo, d.fecha,
       d.variacion_estacion AS variacion_dia,
       d.contador_menos_varilla,
       d.por_contador AS despachado_dia,
       sum(d.variacion_estacion) OVER w AS variacion_acumulada,
       sum(d.por_contador)       OVER w AS despachado_acumulado,
       CASE WHEN sum(d.por_contador) OVER w > 0
            THEN round(100 * sum(d.variacion_estacion) OVER w
                           / sum(d.por_contador) OVER w, 3)
       END AS variacion_pct,
       d.diagnostico
FROM dias d
WINDOW w AS (PARTITION BY d.faena_id, d.grupo, d.mes ORDER BY d.fecha
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW);

-- Y entra a las excepciones del día, que es donde alguien lo va a ver.
CREATE OR REPLACE VIEW public.v_comb_faena_salida_sin_imputar AS
SELECT t.faena_id, t.fecha, t.grupo, t.puntos,
       t.por_contador AS litros_sin_imputar,
       t.por_varilla  AS confirmado_por_varilla
FROM v_comb_faena_triangulo t
WHERE t.diagnostico = 'salida sin registrar';

GRANT SELECT ON public.v_comb_faena_salida_sin_imputar TO authenticated;

COMMIT;
