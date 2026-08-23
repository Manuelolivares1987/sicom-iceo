-- ============================================================================
-- MIG326 · Dos bugs que encontró la prueba de punta a punta
-- ----------------------------------------------------------------------------
-- BUG 1 · LA CORRECCIÓN POR TEMPERATURA DABA UN VALOR ABSURDO
--   Con diésel de 36,5 °API medido a 18 °C, fn_comb_ctl devolvía 0,27805. O
--   sea: 6.100 litros a 18 °C serían 1.696 litros a 15 °C. El diésel no se
--   encoge a un cuarto por tres grados.
--
--   La causa es un factor 1.000. La constante K0 = 613,9723 de API MPMS 11.1
--   está definida para la densidad a 15 °C expresada en kg/m³, y la fórmula la
--   estaba alimentando con kg/L:
--
--       141,5 / (36,5 + 131,5) = 0,8423 kg/L        pero la norma quiere
--       0,8423 × 1000          = 842,26 kg/m³
--
--   Como la densidad va al cuadrado, el error no es de mil veces sino de un
--   millón, que el `* 0.001` del código original compensaba sólo a medias.
--
--   Corregido:  alpha = 613,9723 / 842,26² = 8,655e-4 por °C
--               = 0,0865 % por grado, que es el valor de literatura para
--               diésel (~0,08 %). Y 6.100 L a 18 °C son 6.084 L a 15 °C:
--               15,8 litros, no 4.404.
--
--   NOTA IMPORTANTE PARA QUIEN MANTENGA LA OTRA APLICACIÓN: este error viene de
--   ahí. Yo copié la fórmula tal cual para no reinventarla. Si en algún momento
--   se activó la corrección por temperatura en esa app (faenaConfig.corrTemp),
--   los volúmenes corregidos que haya producido no sirven.
--
-- BUG 2 · UN PUNTO QUE NADIE MIDIÓ NO TIENE "CONTADORES SIN LEER"
--   El camión 67 se marcó explícitamente como no medido, con motivo escrito
--   ("Camión en Coquimbo por mantención"), y el control lo reportó igual como
--   excepción: "faltan 1 de 1 contadores". Eso es ruido sobre una respuesta que
--   ya se dio. Un punto declarado sin medir sale del cuadre entero.
-- ============================================================================

BEGIN;

-- ── 1. CTL con la densidad en las unidades que pide la norma ───────────────
CREATE OR REPLACE FUNCTION public.fn_comb_ctl(
    p_api_gravity numeric,     -- grados API del producto
    p_t_obs_c     numeric,     -- temperatura observada
    p_t_base_c    numeric DEFAULT 15
)
RETURNS numeric
LANGUAGE sql IMMUTABLE AS $f$
    -- rho15 en kg/m3, que es la unidad de K0 = 613.9723 (API MPMS 11.1).
    -- Con kg/L el coeficiente sale un millon de veces mas grande.
    SELECT CASE
      WHEN p_api_gravity IS NULL OR p_t_obs_c IS NULL
        OR p_api_gravity <= -131.5 THEN NULL
      ELSE 1 / (1 + (613.9723 / power((141.5 / (p_api_gravity + 131.5)) * 1000, 2))
                    * (p_t_obs_c - COALESCE(p_t_base_c, 15)))
    END;
$f$;

COMMENT ON FUNCTION public.fn_comb_ctl(numeric, numeric, numeric) IS
  'Correction for Temperature of Liquid, API MPMS 11.1. Da ~0,0865 %/grado para diesel de 36,5 API. Ojo: la version anterior usaba la densidad en kg/L y devolvia 0,278 en vez de 0,9974. MIG326.';

-- ── 2. Un punto declarado sin medir sale del cuadre ────────────────────────
-- La vista pierde una columna (el marcador `cero` que sobraba), asi que hay que
-- soltarla. Sus dos dependientes se recrean identicas mas abajo.
DROP VIEW IF EXISTS public.v_comb_faena_excepciones;
DROP VIEW IF EXISTS public.v_comb_faena_control_diario;
DROP VIEW IF EXISTS public.v_comb_faena_cuadre_grupo;

CREATE VIEW public.v_comb_faena_cuadre_grupo AS
SELECT
    p.faena_id,
    p.fecha,
    p.turno,
    MAX(p.estado)                            AS estado,
    COALESCE(e.grupo_cuadre, p.clave_cierre) AS grupo,
    string_agg(DISTINCT p.estanque_nombre, ' + ' ORDER BY p.estanque_nombre) AS puntos,
    COUNT(*)::int                            AS tanques,
    SUM(p.v_fis)                             AS v_fis,
    SUM(p.v_mec)                             AS v_mec,
    SUM(p.v_mec) - SUM(p.v_fis)              AS var1,
    SUM(p.medidores_total)                   AS medidores_total,
    SUM(p.medidores_leidos)                  AS medidores_leidos,
    (SUM(p.medidores_total) > 0 AND SUM(p.medidores_leidos) = SUM(p.medidores_total)) AS comparable,
    CASE
      WHEN SUM(p.medidores_total) = 0 THEN 'sin_contador'
      WHEN SUM(p.medidores_leidos) < SUM(p.medidores_total) THEN 'incompleto'
      WHEN ABS(SUM(p.v_mec) - SUM(p.v_fis)) < COALESCE(c.tolerancia_ok_lt, 200)     THEN 'cuadra'
      WHEN ABS(SUM(p.v_mec) - SUM(p.v_fis)) < COALESCE(c.tolerancia_alerta_lt, 500) THEN 'atencion'
      ELSE 'investigar'
    END AS resultado
FROM v_comb_faena_cierre_punto p
JOIN combustible_estanques e ON e.id = p.estanque_id
LEFT JOIN combustible_faena_config c ON c.faena_id = p.faena_id
-- Declarar "no pude medir" con motivo es una respuesta, no un pendiente.
WHERE NOT p.sin_medicion
GROUP BY p.faena_id, p.fecha, p.turno, COALESCE(e.grupo_cuadre, p.clave_cierre),
         c.tolerancia_ok_lt, c.tolerancia_alerta_lt;

GRANT SELECT ON public.v_comb_faena_cuadre_grupo TO authenticated;

COMMENT ON VIEW public.v_comb_faena_cuadre_grupo IS
  'Cuadre por GRUPO de estanques interconectados. Los puntos declarados sin medir quedan fuera: ya dieron su respuesta. MIG324/326.';

-- ── 3. Dejar dicho cómo se cargan los aljibes en esta faena ────────────────
-- En Romeral el trasvasije desde un estanque fijo a un camión SÍ pasa por el
-- cuentalitros del estanque: en junio, el contador de Mina 1 marcó 22.701 L el
-- día 01 y los trasvasijes de ese día sumaron 22.700. Por eso la ecuación no
-- resta las salidas por trasvasije — ya están en los dos lados.
--
-- Se deja explícito porque en otra faena puede no ser así, y ahí la ecuación
-- tendría que cambiar.
ALTER TABLE public.combustible_estanques
    ADD COLUMN IF NOT EXISTS trasvasije_por_contador BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN public.combustible_estanques.trasvasije_por_contador IS
  'true = cargar un aljibe desde este estanque pasa por su cuentalitros, asi que el trasvasije aparece tanto en la varilla como en el contador y no hay que restarlo. Verificado en Romeral con los datos de junio 2026. MIG326.';

-- ── 5. El control diario usa el grupo y el umbral en litros ────────────────
DROP VIEW IF EXISTS public.v_comb_faena_control_diario;

CREATE VIEW public.v_comb_faena_control_diario AS
WITH grupos AS (
    SELECT g.faena_id, g.fecha,
           SUM(g.v_fis) AS v_fis,
           SUM(g.v_mec) AS v_mec,
           SUM(g.var1)  AS var1,
           COUNT(*) FILTER (WHERE g.resultado = 'investigar')::int  AS grupos_investigar,
           COUNT(*) FILTER (WHERE g.resultado = 'atencion')::int    AS grupos_atencion,
           COUNT(*) FILTER (WHERE g.resultado = 'incompleto')::int  AS grupos_sin_contador,
           MAX(g.estado) AS estado_cierre
      FROM v_comb_faena_cuadre_grupo g
     GROUP BY g.faena_id, g.fecha
),
puntos AS (
    SELECT p.faena_id, p.fecha,
           COUNT(*) FILTER (WHERE NOT p.sin_medicion AND p.mf IS NOT NULL)::int AS puntos_medidos,
           COUNT(*)::int      AS puntos_total,
           MAX(p.medido_por)  AS medido_por
      FROM v_comb_faena_cierre_punto p
     GROUP BY p.faena_id, p.fecha
),
despachos AS (
    SELECT d.faena_id, d.fecha,
           SUM(d.litros) FILTER (WHERE d.tipo_movimiento = 'venta')::numeric      AS litros_venta,
           SUM(d.litros) FILTER (WHERE d.tipo_movimiento = 'trasvasije')::numeric AS litros_trasvasije,
           SUM(d.litros)::numeric AS litros_total,
           COUNT(*)::int          AS despachos,
           COUNT(*) FILTER (WHERE d.ceco_id IS NULL AND d.tipo_movimiento = 'venta')::int AS sin_ceco,
           COUNT(*) FILTER (WHERE d.equipo_id IS NULL AND d.equipo_texto IS NOT NULL)::int AS equipo_sin_mapear
      FROM combustible_faena_despachos d
     WHERE NOT d.anulado
     GROUP BY d.faena_id, d.fecha
),
recep AS (
    SELECT r.faena_id, r.fecha,
           SUM(r.litros_recibidos)::numeric                          AS litros_recibidos,
           COUNT(*)::int                                             AS recepciones,
           COUNT(*) FILTER (WHERE r.estado <> 'confirmada')::int      AS recepciones_sin_confirmar,
           COUNT(*) FILTER (WHERE r.diferencia_vs_guia IS NOT NULL
                              AND ABS(r.diferencia_vs_guia) > 0)::int AS recepciones_con_diferencia
      FROM v_comb_faena_recepcion r
     GROUP BY r.faena_id, r.fecha
)
SELECT
    COALESCE(gr.faena_id, de.faena_id, re.faena_id) AS faena_id,
    COALESCE(gr.fecha, de.fecha, re.fecha)          AS fecha,
    gr.estado_cierre,
    pu.medido_por,
    pu.puntos_medidos,
    pu.puntos_total,
    gr.grupos_investigar AS puntos_fuera_tolerancia,
    gr.grupos_atencion,
    gr.grupos_sin_contador AS puntos_sin_contador,
    gr.v_fis,
    gr.v_mec,
    gr.var1,
    CASE
        WHEN gr.fecha IS NULL               THEN 'sin_cierre'
        WHEN gr.estado_cierre <> 'firmado'  THEN 'borrador'
        WHEN gr.grupos_investigar > 0       THEN 'revisar'
        WHEN gr.grupos_sin_contador > 0     THEN 'incompleto'
        ELSE 'cuadrado'
    END AS volumen_estado,
    de.despachos,
    de.litros_total,
    de.litros_venta,
    de.litros_trasvasije,
    de.sin_ceco,
    de.equipo_sin_mapear,
    CASE
        WHEN de.despachos IS NULL THEN 'sin_datos'
        WHEN de.sin_ceco > 0      THEN 'incompleta'
        ELSE 'completa'
    END AS imputacion_estado,
    re.recepciones,
    re.litros_recibidos,
    re.recepciones_sin_confirmar,
    re.recepciones_con_diferencia
FROM grupos gr
LEFT JOIN puntos    pu ON pu.faena_id = gr.faena_id AND pu.fecha = gr.fecha
FULL JOIN despachos de ON de.faena_id = gr.faena_id AND de.fecha = gr.fecha
FULL JOIN recep     re ON re.faena_id = COALESCE(gr.faena_id, de.faena_id)
                      AND re.fecha    = COALESCE(gr.fecha, de.fecha);

GRANT SELECT ON public.v_comb_faena_control_diario TO authenticated;

-- ── 6. Las excepciones también miran el grupo ──────────────────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_excepciones AS
SELECT c.faena_id, NULL::date AS fecha, 'ceco_por_confirmar'::text AS tipo,
       c.codigo AS referencia,
       ('CECO ' || c.codigo || ' anotado por ' || COALESCE(c.anotado_por, 'terreno'))::text AS detalle,
       c.litros, c.despachos::int AS cantidad
  FROM v_comb_faena_ceco_por_confirmar c

UNION ALL
SELECT d.faena_id, d.fecha, 'despacho_sin_ceco',
       COALESCE(e.nombre, d.equipo_texto, 'equipo sin identificar'),
       ('Carga sin CECO' || COALESCE(' a ' || COALESCE(e.nombre, d.equipo_texto), ''))::text,
       d.litros, 1
  FROM combustible_faena_despachos d
  LEFT JOIN combustible_faena_equipos e ON e.id = d.equipo_id
 WHERE NOT d.anulado AND d.ceco_id IS NULL AND d.tipo_movimiento = 'venta'

UNION ALL
-- Se investiga por grupo, no por tanque: separar Mina 1 de Mina 2 producía
-- quince alarmas falsas de miles de litros en nueve días.
SELECT g.faena_id, g.fecha, 'fuera_de_tolerancia',
       g.puntos,
       ('Varilla ' || round(g.v_fis) || ' L contra contador ' || round(g.v_mec)
        || ' L · diferencia ' || round(g.var1) || ' L')::text,
       ABS(g.var1), g.tanques
  FROM v_comb_faena_cuadre_grupo g
 WHERE g.resultado = 'investigar'

UNION ALL
SELECT g.faena_id, g.fecha, 'contador_sin_leer',
       g.puntos,
       ('Se midió la varilla pero faltan ' || (g.medidores_total - g.medidores_leidos)
        || ' de ' || g.medidores_total || ' contadores. Sin eso no hay control cruzado.')::text,
       NULL::numeric, (g.medidores_total - g.medidores_leidos)::int
  FROM v_comb_faena_cuadre_grupo g
 WHERE g.resultado = 'incompleto'

UNION ALL
SELECT c.faena_id, c.fecha, 'medicion_sin_foto',
       e.nombre,
       'Medición sin foto ni motivo escrito'::text,
       NULL::numeric, 1
  FROM combustible_faena_cierre_punto p
  JOIN combustible_faena_cierre c ON c.id = p.cierre_id
  JOIN combustible_estanques e ON e.id = p.estanque_id
 WHERE NOT p.sin_medicion AND p.mf IS NOT NULL
   AND COALESCE(p.foto_url,'') = '' AND COALESCE(p.sin_foto_motivo,'') = ''

UNION ALL
SELECT r.faena_id, r.fecha, 'recepcion_con_diferencia',
       COALESCE(r.guia, r.camion, 'sin guía'),
       ('Guía ' || round(r.litros_guia) || ' L, recibidos ' || round(r.litros_recibidos) || ' L')::text,
       ABS(r.diferencia_vs_guia), 1
  FROM v_comb_faena_recepcion r
 WHERE r.diferencia_vs_guia IS NOT NULL AND ABS(r.diferencia_vs_guia) > 0;

GRANT SELECT ON public.v_comb_faena_excepciones TO authenticated;


COMMIT;
