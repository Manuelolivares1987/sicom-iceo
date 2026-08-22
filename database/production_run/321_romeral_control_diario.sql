-- ============================================================================
-- MIG321 · Control diario: dos cierres separados, no uno que se cae entero
-- ----------------------------------------------------------------------------
-- LA DECISIÓN DE FONDO, HECHA DATO
--   El día tiene DOS estados independientes:
--
--     · CIERRE DE VOLUMEN — varilla contra cuentalitros. Se puede cerrar
--       siempre, el mismo día, porque las dos son mediciones físicas que están
--       ahí aunque se caiga la antena.
--     · CIERRE DE IMPUTACIÓN — Orpak contra cuentalitros. Depende de que
--       alguien descargue el tótem, y en agosto eso pasó una vez en nueve días.
--
--   Hoy son un solo bloque y el segundo bloquea al primero. Separarlos convierte
--   "el cierre está atrasado" en "el volumen está cerrado y faltan 8 días de
--   imputación", que es una frase con dueño y con número.
--
-- LA TOLERANCIA VIVE ACÁ
--   ±0,5 % del movimiento del día con piso de 50 L. Es una propuesta: con
--   varilla no existe el cuadre exacto, y sin umbral declarado pasa una de dos
--   cosas malas — o se persigue ruido de medición, o se normaliza cualquier
--   diferencia porque "nunca cuadra". Se acuerda con ESMAX y se cambia acá,
--   en un solo lugar.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.combustible_faena_config (
    faena_id            UUID PRIMARY KEY REFERENCES public.faenas(id) ON DELETE CASCADE,
    tolerancia_pct      NUMERIC NOT NULL DEFAULT 0.005,
    tolerancia_piso_lt  NUMERIC NOT NULL DEFAULT 50,
    hora_corte          TIME    NOT NULL DEFAULT '00:00',
    observacion         TEXT,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.combustible_faena_config IS
  'Umbrales del cuadre por faena. Sin tolerancia declarada, o se persigue ruido o se normaliza cualquier diferencia. MIG321.';

INSERT INTO public.combustible_faena_config (faena_id, observacion)
SELECT f.id, 'Valores de partida propuestos. Falta acordarlos con ESMAX.'
  FROM faenas f WHERE f.codigo = 'FAE-CMP-ROMERAL'
ON CONFLICT (faena_id) DO NOTHING;

GRANT SELECT ON public.combustible_faena_config TO authenticated;

-- ── El día completo, en una fila ───────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_control_diario AS
WITH cfg AS (
    SELECT f.id AS faena_id,
           COALESCE(c.tolerancia_pct, 0.005)     AS tol_pct,
           COALESCE(c.tolerancia_piso_lt, 50)    AS tol_piso
      FROM faenas f
      LEFT JOIN combustible_faena_config c ON c.faena_id = f.id
),
puntos AS (
    SELECT p.faena_id, p.fecha,
           SUM(p.v_fis)  AS v_fis,
           SUM(p.v_mec)  AS v_mec,
           SUM(p.var1)   AS var1,
           COUNT(*) FILTER (WHERE NOT p.sin_medicion AND p.mf IS NOT NULL)::int AS puntos_medidos,
           COUNT(*)::int                                                        AS puntos_total,
           -- Un punto fuera de tolerancia se cuenta punto por punto: sumar
           -- primero y comparar después esconde dos errores que se cancelan.
           COUNT(*) FILTER (
               WHERE NOT p.sin_medicion AND p.mf IS NOT NULL
                 AND ABS(p.var1) > GREATEST(
                       GREATEST(ABS(p.v_fis), ABS(p.v_mec)) * (SELECT tol_pct FROM cfg WHERE cfg.faena_id = p.faena_id),
                       (SELECT tol_piso FROM cfg WHERE cfg.faena_id = p.faena_id))
           )::int                                                               AS puntos_fuera_tolerancia,
           MAX(p.estado)     AS estado_cierre,
           MAX(p.medido_por) AS medido_por
      FROM v_comb_faena_cierre_punto p
     GROUP BY p.faena_id, p.fecha
),
despachos AS (
    SELECT d.faena_id, d.fecha,
           SUM(d.litros) FILTER (WHERE d.tipo_movimiento = 'venta')::numeric        AS litros_venta,
           SUM(d.litros) FILTER (WHERE d.tipo_movimiento = 'trasvasije')::numeric   AS litros_trasvasije,
           SUM(d.litros) FILTER (WHERE d.tipo_movimiento <> 'venta')::numeric       AS litros_no_venta,
           SUM(d.litros)::numeric                                                   AS litros_total,
           COUNT(*)::int                                                            AS despachos,
           COUNT(*) FILTER (WHERE d.ceco_id IS NULL)::int                           AS sin_ceco,
           COUNT(*) FILTER (WHERE d.equipo_id IS NULL AND d.equipo_texto IS NOT NULL)::int AS equipo_sin_mapear
      FROM combustible_faena_despachos d
     WHERE NOT d.anulado
     GROUP BY d.faena_id, d.fecha
),
recep AS (
    SELECT r.faena_id, r.fecha,
           SUM(r.litros_recibidos)::numeric                                     AS litros_recibidos,
           COUNT(*)::int                                                        AS recepciones,
           COUNT(*) FILTER (WHERE r.estado <> 'confirmada')::int                AS recepciones_sin_confirmar,
           COUNT(*) FILTER (WHERE r.diferencia_vs_guia IS NOT NULL
                              AND ABS(r.diferencia_vs_guia) > 0)::int           AS recepciones_con_diferencia
      FROM v_comb_faena_recepcion r
     GROUP BY r.faena_id, r.fecha
)
SELECT
    COALESCE(pu.faena_id, de.faena_id, re.faena_id)  AS faena_id,
    COALESCE(pu.fecha, de.fecha, re.fecha)           AS fecha,

    -- ── Cierre de volumen: se puede cerrar siempre ──────────────────────────
    pu.estado_cierre,
    pu.medido_por,
    pu.puntos_medidos,
    pu.puntos_total,
    pu.puntos_fuera_tolerancia,
    pu.v_fis,
    pu.v_mec,
    pu.var1,
    CASE
        WHEN pu.fecha IS NULL              THEN 'sin_cierre'
        WHEN pu.estado_cierre <> 'firmado' THEN 'borrador'
        WHEN pu.puntos_fuera_tolerancia > 0 THEN 'revisar'
        ELSE 'cuadrado'
    END AS volumen_estado,

    -- ── Cierre de imputación: depende de Orpak ──────────────────────────────
    de.despachos,
    de.litros_total,
    de.litros_venta,
    de.litros_trasvasije,
    de.sin_ceco,
    de.equipo_sin_mapear,
    CASE
        WHEN de.despachos IS NULL          THEN 'sin_datos'
        WHEN de.sin_ceco > 0               THEN 'incompleta'
        ELSE 'completa'
    END AS imputacion_estado,

    -- ── Recepciones ─────────────────────────────────────────────────────────
    re.recepciones,
    re.litros_recibidos,
    re.recepciones_sin_confirmar,
    re.recepciones_con_diferencia
FROM puntos pu
FULL JOIN despachos de ON de.faena_id = pu.faena_id AND de.fecha = pu.fecha
FULL JOIN recep     re ON re.faena_id = COALESCE(pu.faena_id, de.faena_id)
                      AND re.fecha    = COALESCE(pu.fecha, de.fecha);

GRANT SELECT ON public.v_comb_faena_control_diario TO authenticated;

COMMENT ON VIEW public.v_comb_faena_control_diario IS
  'Un dia en una fila, con los DOS cierres separados: volumen (varilla vs cuentalitros, siempre cerrable) e imputacion (a quien se cargo, depende de Orpak). MIG321.';

-- ── Excepciones abiertas: lo que hay que resolver, no lo que hay que mirar ──
CREATE OR REPLACE VIEW public.v_comb_faena_excepciones AS
-- CECO anotados en terreno esperando confirmación
SELECT c.faena_id, NULL::date AS fecha, 'ceco_por_confirmar'::text AS tipo,
       c.codigo AS referencia,
       ('CECO ' || c.codigo || ' anotado por ' || COALESCE(c.anotado_por, 'terreno'))::text AS detalle,
       c.litros, c.despachos::int AS cantidad
  FROM v_comb_faena_ceco_por_confirmar c

UNION ALL
-- Despachos sin CECO de ningún tipo: ni del catálogo ni anotado
SELECT d.faena_id, d.fecha, 'despacho_sin_ceco',
       COALESCE(e.nombre, d.equipo_texto, 'equipo sin identificar'),
       ('Carga sin CECO' || COALESCE(' a ' || COALESCE(e.nombre, d.equipo_texto), ''))::text,
       d.litros, 1
  FROM combustible_faena_despachos d
  LEFT JOIN combustible_faena_equipos e ON e.id = d.equipo_id
 WHERE NOT d.anulado AND d.ceco_id IS NULL

UNION ALL
-- Puntos fuera de tolerancia
SELECT p.faena_id, p.fecha, 'fuera_de_tolerancia',
       p.estanque_nombre,
       ('Varilla ' || round(p.v_fis) || ' L contra contador ' || round(p.v_mec) || ' L')::text,
       ABS(p.var1), 1
  FROM v_comb_faena_cierre_punto p
  LEFT JOIN combustible_faena_config c ON c.faena_id = p.faena_id
 WHERE NOT p.sin_medicion AND p.mf IS NOT NULL
   AND ABS(p.var1) > GREATEST(
         GREATEST(ABS(p.v_fis), ABS(p.v_mec)) * COALESCE(c.tolerancia_pct, 0.005),
         COALESCE(c.tolerancia_piso_lt, 50))

UNION ALL
-- Mediciones sin foto ni motivo (un cierre en borrador puede tenerlas)
-- La faena y la fecha viven en la cabecera del cierre, no en la fila del punto.
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
-- Recepciones donde la guía y lo recibido no dan lo mismo
SELECT r.faena_id, r.fecha, 'recepcion_con_diferencia',
       COALESCE(r.guia, r.camion, 'sin guía'),
       ('Guía ' || round(r.litros_guia) || ' L, recibidos ' || round(r.litros_recibidos) || ' L')::text,
       ABS(r.diferencia_vs_guia), 1
  FROM v_comb_faena_recepcion r
 WHERE r.diferencia_vs_guia IS NOT NULL AND ABS(r.diferencia_vs_guia) > 0;

GRANT SELECT ON public.v_comb_faena_excepciones TO authenticated;

COMMENT ON VIEW public.v_comb_faena_excepciones IS
  'Lo que hay que resolver. Control por excepcion: hoy se revisa el 100 %, y revisar todo es no revisar nada. MIG321.';

COMMIT;
