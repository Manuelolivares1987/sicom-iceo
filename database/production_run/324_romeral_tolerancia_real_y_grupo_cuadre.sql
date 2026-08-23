-- ============================================================================
-- MIG324 · La tolerancia sale de los archivos, no de mi cabeza
-- ----------------------------------------------------------------------------
-- LO QUE HABÍA HECHO MAL
--   Puse ±0,5 % con piso de 50 L. Lo inventé. La tolerancia ya estaba definida
--   en la aplicación que se construyó para Romeral, en litros absolutos y con
--   tres niveles, no dos:
--
--       function varClass(v) {
--         if (Math.abs(v) < 200) return 'pos';    // verde
--         if (Math.abs(v) < 500) return 'warn';   // ámbar
--         return 'neg';                           // rojo
--       }
--
--   Un umbral porcentual además era peor para este caso: castiga los días de
--   poco movimiento y perdona los de mucho, cuando el error de leer una varilla
--   no depende de cuánto se despachó ese día — depende del tanque.
--
-- LOS 9 DÍAS DE JUNIO LE DAN LA RAZÓN AL UMBRAL DE ELLOS
--   Puntos con contador propio (Bimodal, Casa Fuerza, los 3 camiones),
--   22 mediciones: mediana 31 L, p90 223 L, máximo 274 L.
--   19 de 22 bajo 200 L. Los 22 bajo 500 L. Ni uno solo se pasó.
--   Los tres que superaron 200 son Bimodal, que tiene cinco contadores y es la
--   estación de más movimiento. El umbral está bien calibrado.
--
-- EL HALLAZGO GRANDE: MINA 1 Y MINA 2 NO SON DOS PUNTOS DE CUADRE
--   Los 15 casos "rojos" de junio son todos de la Estación Isla Mina, y se
--   cancelan entre sí día tras día:
--
--       08-06   mina1 +5.178   mina2 −5.112   suma  +66
--       07-06   mina1 +4.067   mina2 −3.855   suma +212
--       01-06   mina1 +2.701   mina2 −2.416   suma +285
--
--   La razón es física: los dos tanques despachan por los MISMOS dos contadores
--   de la isla. El contador no sabe de cuál de los dos salió el litro. Asignarle
--   todo el consumo a un tanque y nada al otro fabrica dos errores enormes que
--   se anulan — y de paso deja 15 alarmas falsas de miles de litros.
--
--   Comparados juntos, los mismos 9 días van de 66 a 584 L. De miles a
--   centenas. Eso ya no es ruido de modelo: es el error real de leer dos
--   varillas en tanques de 75.000 y 30.000 litros.
--
--   Por eso el cuadre pasa a ser por GRUPO, no por tanque. Es además como lo
--   ven el libro ("Estación Isla Mina") y el FORM AC 066 ("KPI Pesados",
--   105.000 = 75.000 + 30.000).
--
-- Y LA CORRECCIÓN POR TEMPERATURA TAMPOCO FALTABA
--   La app ya la tiene, con la fórmula de API MPMS 11.1 sobre grados API. La
--   incorporo con la misma fórmula en vez de proponerla como si no existiera.
-- ============================================================================

BEGIN;

-- ── 1. La tolerancia de ellos, en litros y con tres niveles ────────────────
ALTER TABLE public.combustible_faena_config
    ADD COLUMN IF NOT EXISTS tolerancia_ok_lt     NUMERIC NOT NULL DEFAULT 200,
    ADD COLUMN IF NOT EXISTS tolerancia_alerta_lt NUMERIC NOT NULL DEFAULT 500;

COMMENT ON COLUMN public.combustible_faena_config.tolerancia_ok_lt IS
  'Bajo esto, cuadra. Viene de varClass() de la app de Romeral, validado con 9 dias de junio: 19 de 22 mediciones con contador propio quedaron bajo 200 L. MIG324.';
COMMENT ON COLUMN public.combustible_faena_config.tolerancia_alerta_lt IS
  'Sobre esto, hay que investigar. Ninguna medicion con contador propio de junio supero 500 L. MIG324.';

-- Acotado a Romeral: los umbrales salen de SU aplicacion y estan validados con
-- SUS datos. Sin el WHERE, el dia que otra faena configure los suyos, volver a
-- correr esta migracion se los pisaria.
UPDATE public.combustible_faena_config c
   SET tolerancia_ok_lt = 200, tolerancia_alerta_lt = 500,
       observacion = 'Umbrales tomados de la aplicacion de Romeral (varClass) y validados con los 9 dias de junio 2026.',
       updated_at = NOW()
  FROM faenas f
 WHERE f.id = c.faena_id AND f.codigo = 'FAE-CMP-ROMERAL';

-- Las columnas porcentuales que había inventado quedan sin uso. No se borran
-- todavía: si mañana se acuerda con ESMAX un criterio porcentual, están.
COMMENT ON COLUMN public.combustible_faena_config.tolerancia_pct IS
  'SIN USO desde MIG324. El cuadre se evalua en litros absolutos. Se conserva por si se acuerda un criterio porcentual con ESMAX.';

-- ── 2. Grupo de cuadre ─────────────────────────────────────────────────────
ALTER TABLE public.combustible_estanques
    ADD COLUMN IF NOT EXISTS grupo_cuadre TEXT;

COMMENT ON COLUMN public.combustible_estanques.grupo_cuadre IS
  'Tanques que comparten contadores se cuadran juntos. El contador no sabe de que tanque salio el litro. MIG324.';

-- Mina 1 y Mina 2 despachan por los mismos contadores de la isla.
UPDATE public.combustible_estanques SET grupo_cuadre = 'mina'
 WHERE codigo IN ('ROM-MINA-1','ROM-MINA-2');

-- El resto se cuadra solo: cada uno con su propio contador.
UPDATE public.combustible_estanques e
   SET grupo_cuadre = e.clave_cierre
  FROM faenas f
 WHERE f.id = e.faena_id AND f.codigo = 'FAE-CMP-ROMERAL'
   AND e.grupo_cuadre IS NULL;

-- ── 3. Corrección por temperatura, con la fórmula que ya usaban ────────────
-- API MPMS Cap. 11.1 / ASTM D1250 para productos refinados.
CREATE OR REPLACE FUNCTION public.fn_comb_ctl(
    p_api_gravity numeric,     -- grados API del producto
    p_t_obs_c     numeric,     -- temperatura observada
    p_t_base_c    numeric DEFAULT 15
)
RETURNS numeric
LANGUAGE sql IMMUTABLE AS $f$
    SELECT CASE
      WHEN p_api_gravity IS NULL OR p_t_obs_c IS NULL THEN NULL
      ELSE 1 / (1 + ((613.9723 / power(141.5 / (p_api_gravity + 131.5), 2)) * 0.001)
                    * (p_t_obs_c - COALESCE(p_t_base_c, 15)))
    END;
$f$;

COMMENT ON FUNCTION public.fn_comb_ctl(numeric, numeric, numeric) IS
  'Correction for Temperature of Liquid. Misma formula que ya usa la app de Romeral (API MPMS 11.1). El diesel se dilata ~0,08 % por grado. MIG324.';

GRANT EXECUTE ON FUNCTION public.fn_comb_ctl(numeric, numeric, numeric) TO authenticated;

ALTER TABLE public.combustible_faena_cierre_punto
    ADD COLUMN IF NOT EXISTS densidad_api NUMERIC;

-- ── 4. El cuadre se evalúa por grupo ───────────────────────────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_cuadre_grupo AS
SELECT
    p.faena_id,
    p.fecha,
    p.turno,
    MAX(p.estado)                                   AS estado,
    COALESCE(e.grupo_cuadre, p.clave_cierre)        AS grupo,
    string_agg(DISTINCT p.estanque_nombre, ' + ' ORDER BY p.estanque_nombre) AS puntos,
    COUNT(*)::int                                   AS tanques,
    SUM(p.v_fis)                                    AS v_fis,
    SUM(p.v_mec)                                    AS v_mec,
    SUM(p.v_fis) - SUM(p.v_fis)                     AS cero,   -- marcador de forma
    SUM(p.v_mec) - SUM(p.v_fis)                     AS var1,
    SUM(p.medidores_total)                          AS medidores_total,
    SUM(p.medidores_leidos)                         AS medidores_leidos,
    BOOL_OR(p.sin_medicion)                         AS algun_punto_sin_medir,
    -- Un grupo es comparable cuando tiene contadores Y están todos leídos.
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
GROUP BY p.faena_id, p.fecha, p.turno, COALESCE(e.grupo_cuadre, p.clave_cierre),
         c.tolerancia_ok_lt, c.tolerancia_alerta_lt;

GRANT SELECT ON public.v_comb_faena_cuadre_grupo TO authenticated;

COMMENT ON VIEW public.v_comb_faena_cuadre_grupo IS
  'El cuadre por GRUPO. Mina 1 y Mina 2 comparten contadores: separados dan errores de miles de litros que se cancelan; juntos dan centenas. MIG324.';

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
