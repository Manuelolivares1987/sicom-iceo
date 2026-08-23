-- ============================================================================
-- MIG330 · El mini cierre, la variación de estación y la variación acumulada
-- ----------------------------------------------------------------------------
-- Hasta ahora el sistema cruzaba DOS medidas: la varilla contra el
-- cuentalitros. El instructivo pide TRES, y la tercera es la que faltaba
-- porque vivía en el archivo de Orpak. Con la ingesta ya cargada (MIG328) se
-- puede cerrar el triángulo:
--
--     VARILLA        cuánto combustible hay realmente en el estanque
--     CUENTALITROS   cuánto dice el mecanismo que salió
--     SIST. AUT.     cuánto registró Orpak que se vendió, y a quién
--
-- Dos de las tres siempre se parecen. La que se desvía dice qué falló:
--   · varilla ≠ contador, y Orpak coincide con el contador  -> fuga, agua,
--     error de aforo, o combustible que salió sin registrarse
--   · contador ≠ Orpak, y la varilla coincide con el contador -> problema de
--     registro: una tarjeta que no leyó, un CECO default, una transacción
--     clasificada como venta siendo trasvasije
--   · las tres distintas -> el día está mal medido, no hay conclusión
--
-- MINI CIERRE (sección 15 del instructivo, literal)
--     Stock Inicial + Recepciones − Ventas = Stock Teórico
--     Stock Físico − Stock Teórico          = Variación de Estación
--
-- POR QUÉ LA VARIACIÓN DE UN DÍA NO SIRVE PARA DECIDIR
-- Una varilla tiene ±0,3 % de incertidumbre por su propia física: el menisco,
-- la inclinación del estanque, la temperatura. En 50.000 litros eso son 150
-- litros de ruido legítimo TODOS LOS DÍAS. Un día con −180 no dice nada. Lo
-- que sí dice es el acumulado: si el ruido es ruido, se compensa y la suma del
-- mes tiende a cero. Si hay una pérdida real, la suma se va para un lado y no
-- vuelve. Por eso el instructivo pide revisar la variación de estación y por
-- eso aquí se acumula por mes.
--
-- SOBRE LA CORRECCIÓN POR TEMPERATURA (CTL) Y DÓNDE SÍ CORRESPONDE
-- El diésel se dilata ~0,086 % por grado. Deliberadamente NO se aplica al
-- cuadre diario varilla-contra-contador: las dos medidas se toman a la misma
-- temperatura ambiente y la corrección se cancela. Aplicarla ahí sería
-- ruido con aire de precisión. Donde sí importa es en dos lugares:
--   · contra la guía de recepción, que ENAP factura a 15 °C mientras el
--     estanque lo recibe a 25 °C — ahí la diferencia es real y es plata;
--   · en el acumulado del mes, porque si el mes empieza a 12 °C y termina a
--     26 °C, el mismo combustible ocupa más volumen y aparece una ganancia
--     fantasma de cientos de litros.
-- ============================================================================

BEGIN;

-- ── Lo que Orpak dice que salió de cada estanque, por día ──────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_salida_sistema AS
SELECT t.faena_id, t.dia_cierre AS fecha, t.estanque_id,
       COALESCE(sum(t.litros) FILTER (
           WHERE t.clasificacion NOT IN ('TRASVASIJE','RECIRCULACION')), 0) AS venta_sistema,
       COALESCE(sum(t.litros) FILTER (WHERE t.clasificacion = 'TRASVASIJE'), 0) AS trasvasije_sistema,
       COALESCE(sum(t.litros), 0) AS salida_sistema,
       count(*)::integer AS transacciones_sistema,
       count(*) FILTER (WHERE t.ceco_id IS NULL
                          AND t.clasificacion NOT IN ('TRASVASIJE','RECIRCULACION','CALIBRACION'))::integer
           AS sistema_sin_ceco
FROM combustible_orpak_transaccion t
GROUP BY t.faena_id, t.dia_cierre, t.estanque_id;

GRANT SELECT ON public.v_comb_faena_salida_sistema TO authenticated;

-- ── Lo que la app de terreno registró que salió ────────────────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_salida_terreno AS
SELECT d.faena_id, d.fecha, d.estanque_id,
       COALESCE(sum(d.litros) FILTER (WHERE d.tipo_movimiento = 'venta'), 0)      AS venta_terreno,
       COALESCE(sum(d.litros) FILTER (WHERE d.tipo_movimiento = 'trasvasije'), 0) AS trasvasije_terreno,
       COALESCE(sum(d.litros), 0) AS salida_terreno,
       count(*)::integer AS transacciones_terreno,
       count(*) FILTER (WHERE d.ceco_id IS NULL AND d.tipo_movimiento = 'venta')::integer AS terreno_sin_ceco
FROM combustible_faena_despachos d
WHERE NOT d.anulado
GROUP BY d.faena_id, d.fecha, d.estanque_id;

GRANT SELECT ON public.v_comb_faena_salida_terreno TO authenticated;

-- ── El mini cierre, por punto de medición ──────────────────────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_mini_cierre AS
WITH base AS (
    SELECT p.faena_id, p.fecha, p.turno, p.estado, p.estanque_id,
           p.estanque_nombre, e.grupo_cuadre, p.sin_medicion,
           p.mi, p.rfp, p.rt, p.mf, p.temperatura_c,
           COALESCE(p.mi, 0)  AS stock_inicial,
           COALESCE(p.rfp, 0) + COALESCE(p.rt, 0) AS recepciones,
           p.mf               AS stock_fisico,
           p.v_fis, p.v_mec, p.var1,
           p.medidores_total, p.medidores_leidos,
           COALESCE(ss.salida_sistema, 0)  AS salida_sistema,
           COALESCE(ss.venta_sistema, 0)   AS venta_sistema,
           ss.transacciones_sistema,
           ss.sistema_sin_ceco,
           COALESCE(st.salida_terreno, 0)  AS salida_terreno,
           COALESCE(st.venta_terreno, 0)   AS venta_terreno,
           st.transacciones_terreno,
           -- Orpak controla las estaciones fijas. Los camiones aljibe los
           -- registra la app de terreno. Cada estanque tiene una sola fuente
           -- de salida: la que efectivamente tiene movimientos ese día.
           CASE WHEN COALESCE(ss.transacciones_sistema, 0) > 0 THEN 'orpak'
                WHEN COALESCE(st.transacciones_terreno, 0) > 0 THEN 'terreno'
                ELSE 'sin_registro' END AS fuente_salida
      FROM v_comb_faena_cierre_punto p
      JOIN combustible_estanques e ON e.id = p.estanque_id
      LEFT JOIN v_comb_faena_salida_sistema ss
             ON ss.faena_id = p.faena_id AND ss.fecha = p.fecha AND ss.estanque_id = p.estanque_id
      LEFT JOIN v_comb_faena_salida_terreno st
             ON st.faena_id = p.faena_id AND st.fecha = p.fecha AND st.estanque_id = p.estanque_id
)
SELECT b.*,
       CASE b.fuente_salida WHEN 'orpak' THEN b.salida_sistema
                            WHEN 'terreno' THEN b.salida_terreno
                            ELSE 0 END AS salida_registrada,
       b.stock_inicial + b.recepciones
         - CASE b.fuente_salida WHEN 'orpak' THEN b.salida_sistema
                                WHEN 'terreno' THEN b.salida_terreno
                                ELSE 0 END AS stock_teorico,
       b.stock_fisico
         - (b.stock_inicial + b.recepciones
            - CASE b.fuente_salida WHEN 'orpak' THEN b.salida_sistema
                                   WHEN 'terreno' THEN b.salida_terreno
                                   ELSE 0 END) AS variacion_estacion,
       -- El tercer lado del triángulo: el mecanismo contra el sistema.
       b.v_mec - CASE b.fuente_salida WHEN 'orpak' THEN b.salida_sistema
                                      WHEN 'terreno' THEN b.salida_terreno
                                      ELSE 0 END AS contador_menos_sistema
FROM base b
WHERE NOT b.sin_medicion;

GRANT SELECT ON public.v_comb_faena_mini_cierre TO authenticated;

COMMENT ON VIEW public.v_comb_faena_mini_cierre IS
  'Seccion 15 del instructivo: Stock Inicial + Recepciones - Ventas = Stock Teorico; Fisico - Teorico = Variacion de Estacion. Suma el tercer lado del triangulo (Orpak) que hasta MIG328 no existia. MIG330.';

-- ── El diagnóstico: cuál de las tres se desvía ─────────────────────────────
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
         WHEN min(m.fuente_salida) = 'sin_registro' THEN 'sin_registro'
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

GRANT SELECT ON public.v_comb_faena_triangulo TO authenticated;

COMMENT ON VIEW public.v_comb_faena_triangulo IS
  'Dos de las tres medidas siempre se parecen; la que se desvia dice que fallo. Si el contador coincide con Orpak, el problema esta en el estanque (fuga, agua, aforo). Si coincide con la varilla, el problema esta en el registro. MIG330.';

-- ── La variación acumulada del mes ─────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_variacion_acumulada AS
WITH dias AS (
    SELECT t.faena_id, t.grupo, t.fecha,
           date_trunc('month', t.fecha)::date AS mes,
           t.variacion_estacion, t.contador_menos_varilla, t.por_contador,
           t.diagnostico
      FROM v_comb_faena_triangulo t
     WHERE t.diagnostico <> 'incompleto'
)
SELECT d.faena_id, d.mes, d.grupo, d.fecha,
       d.variacion_estacion AS variacion_dia,
       d.contador_menos_varilla,
       d.por_contador AS despachado_dia,
       -- Suma algebraica: el ruido de la varilla se compensa solo, una perdida
       -- real no. Por eso lo que se mira es esta columna y no la del dia.
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

GRANT SELECT ON public.v_comb_faena_variacion_acumulada TO authenticated;

-- ── El semáforo del mes, que es lo que se mira ─────────────────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_variacion_mes AS
SELECT DISTINCT ON (faena_id, grupo, mes)
       faena_id, mes, grupo, fecha AS hasta,
       variacion_acumulada, despachado_acumulado, variacion_pct,
       CASE
         -- Media pulgada de tolerancia sobre el flujo del mes es el estandar
         -- de la industria para un sistema de combustible sano.
         WHEN despachado_acumulado IS NULL OR despachado_acumulado = 0 THEN 'sin_datos'
         WHEN abs(variacion_pct) <= 0.5 THEN 'normal'
         WHEN abs(variacion_pct) <= 1.0 THEN 'vigilar'
         ELSE 'investigar'
       END AS estado_mes
FROM v_comb_faena_variacion_acumulada
ORDER BY faena_id, grupo, mes, fecha DESC;

GRANT SELECT ON public.v_comb_faena_variacion_mes TO authenticated;

-- ── El CTL donde de verdad corresponde: la recepción ───────────────────────
-- ENAP factura a 15 °C. El estanque recibe a la temperatura del camión. La
-- diferencia no es un error de nadie, es física, y es plata: 30.000 litros
-- facturados a 15 °C recibidos a 25 °C ocupan unos 260 litros más.
CREATE OR REPLACE VIEW public.v_comb_faena_recepcion_ctl AS
SELECT r.id, r.faena_id, r.fecha, r.guia, r.camion, r.proveedor,
       r.litros_guia, r.litros_recibidos, r.diferencia_vs_guia,
       p.temperatura_c, p.densidad_api,
       CASE WHEN p.temperatura_c IS NOT NULL AND p.densidad_api IS NOT NULL
            THEN round(fn_comb_ctl(p.densidad_api, p.temperatura_c, 15)::numeric, 5) END AS ctl,
       CASE WHEN p.temperatura_c IS NOT NULL AND p.densidad_api IS NOT NULL
            THEN round((r.litros_recibidos * fn_comb_ctl(p.densidad_api, p.temperatura_c, 15))::numeric, 1) END
            AS recibido_a_15c,
       CASE WHEN p.temperatura_c IS NOT NULL AND p.densidad_api IS NOT NULL AND r.litros_guia IS NOT NULL
            THEN round((r.litros_recibidos * fn_comb_ctl(p.densidad_api, p.temperatura_c, 15) - r.litros_guia)::numeric, 1) END
            AS diferencia_a_15c
FROM v_comb_faena_recepcion r
LEFT JOIN LATERAL (
    SELECT cp.temperatura_c, cp.densidad_api
      FROM combustible_faena_cierre c
      JOIN combustible_faena_cierre_punto cp ON cp.cierre_id = c.id
     WHERE c.faena_id = r.faena_id AND c.fecha = r.fecha
       AND cp.temperatura_c IS NOT NULL AND cp.densidad_api IS NOT NULL
     ORDER BY cp.updated_at DESC LIMIT 1
) p ON true
WHERE NOT r.anulada;

GRANT SELECT ON public.v_comb_faena_recepcion_ctl TO authenticated;

-- ── El stock del estanque se ancla a la medición, no a un saldo corrido ────
-- Un saldo teórico que se arrastra mes a mes acumula todos los errores de
-- registro. La varilla del cierre firmado es un dato real: eso es el stock.
CREATE OR REPLACE FUNCTION public.fn_comb_sincronizar_stock()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NEW.estado = 'firmado' AND COALESCE(OLD.estado,'') <> 'firmado' THEN
        UPDATE combustible_estanques e
           SET stock_teorico_lt = p.mf, updated_at = NOW()
          FROM combustible_faena_cierre_punto p
         WHERE p.cierre_id = NEW.id AND p.estanque_id = e.id
           AND NOT p.sin_medicion AND p.mf IS NOT NULL;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_comb_sincronizar_stock ON public.combustible_faena_cierre;
CREATE TRIGGER trg_comb_sincronizar_stock
    AFTER UPDATE OF estado ON public.combustible_faena_cierre
    FOR EACH ROW EXECUTE FUNCTION public.fn_comb_sincronizar_stock();

-- ── La hora de corte deja de ser decorativa ────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_comb_dia_cierre(p_faena_id uuid, p_fecha date, p_hora text)
RETURNS date
LANGUAGE sql STABLE
AS $f$
    -- Una carga posterior a la hora de corte pertenece al cierre del dia
    -- siguiente. Sin esto, la transaccion de las 23:50 descuadra dos dias
    -- seguidos: sobra en uno y falta en el otro.
    SELECT CASE
      WHEN p_hora IS NULL OR p_hora !~ '^[0-9]{1,2}:[0-9]{2}' THEN p_fecha
      WHEN (SELECT c.hora_corte FROM combustible_faena_config c WHERE c.faena_id = p_faena_id) IS NULL
           THEN p_fecha
      WHEN p_hora::time >= (SELECT c.hora_corte FROM combustible_faena_config c WHERE c.faena_id = p_faena_id)
           THEN p_fecha + 1
      ELSE p_fecha
    END;
$f$;

CREATE OR REPLACE VIEW public.v_comb_faena_fuera_de_corte AS
SELECT d.faena_id, d.fecha AS fecha_declarada, d.hora,
       fn_comb_dia_cierre(d.faena_id, d.fecha, d.hora::text) AS fecha_que_corresponde,
       e.nombre AS estanque, d.litros, d.equipo_texto, d.operador_nombre
FROM combustible_faena_despachos d
JOIN combustible_estanques e ON e.id = d.estanque_id
WHERE NOT d.anulado AND d.hora IS NOT NULL
  AND fn_comb_dia_cierre(d.faena_id, d.fecha, d.hora::text) <> d.fecha;

GRANT SELECT ON public.v_comb_faena_fuera_de_corte TO authenticated;

COMMIT;
