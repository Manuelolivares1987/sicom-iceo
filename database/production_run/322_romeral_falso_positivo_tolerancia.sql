-- ============================================================================
-- MIG322 · "Fuera de tolerancia" y "contador sin leer" no son lo mismo
-- ----------------------------------------------------------------------------
-- LO QUE SALIÓ EN LA PRUEBA
--   Se firmó un cierre midiendo la varilla de Mina 1 pero sin leer sus dos
--   contadores. El control lo reportó como:
--
--       Fuera de tolerancia · Estación Isla Mina — Tanque 1
--       Varilla 8.250 L contra contador 0 L
--
--   Eso es falso. No hay una diferencia de 8.250 L: hay un contador que nadie
--   leyó. Son dos problemas distintos, con dos acciones distintas —investigar
--   una pérdida contra ir a anotar un número— y mezclarlos tiene un costo
--   conocido: cuando las alertas mienten, se dejan de mirar. Y el día que una
--   diga la verdad, tampoco se va a mirar.
--
--   El libro de agosto ya tenía este caso: los días 7 y 8 hay varilla sin
--   numeral. No es que hayan cuadrado ni que hayan descuadrado — es que no se
--   puede saber.
--
-- LA REGLA
--   La tolerancia sólo se evalúa cuando el punto tiene TODOS sus contadores
--   leídos. Si le faltan, la excepción es "contador sin leer". Si el punto no
--   tiene contador propio —Mina 2 despacha por los de Mina 1— no es una
--   excepción de nada: es cómo está construida la estación.
--
-- DE PASO
--   El módulo de permiso para confirmar CECO pasa de 'combustible', que no
--   existe en ninguna otra parte del sistema, a 'inventario', que sí. Un módulo
--   inventado hace que configurar permisos desde Admin no tenga efecto acá.
-- ============================================================================

BEGIN;

-- ── 1. El control diario distingue los dos casos ───────────────────────────
-- Se agrega una columna en medio, asi que la vista se recrea: CREATE OR
-- REPLACE no permite insertar columnas, solo agregarlas al final.
DROP VIEW IF EXISTS public.v_comb_faena_control_diario;

CREATE VIEW public.v_comb_faena_control_diario AS
WITH cfg AS (
    SELECT f.id AS faena_id,
           COALESCE(c.tolerancia_pct, 0.005)  AS tol_pct,
           COALESCE(c.tolerancia_piso_lt, 50) AS tol_piso
      FROM faenas f
      LEFT JOIN combustible_faena_config c ON c.faena_id = f.id
),
-- Se resuelve por punto ANTES de agrupar: sumar primero y comparar después
-- esconde dos errores que se cancelan entre sí.
punto_eval AS (
    SELECT p.*,
           (p.medidores_total > 0 AND p.medidores_leidos = p.medidores_total) AS comparable,
           (p.medidores_total > 0 AND p.medidores_leidos < p.medidores_total)  AS falta_contador,
           GREATEST(GREATEST(ABS(p.v_fis), ABS(p.v_mec)) * g.tol_pct, g.tol_piso) AS umbral
      FROM v_comb_faena_cierre_punto p
      JOIN cfg g ON g.faena_id = p.faena_id
),
puntos AS (
    SELECT pe.faena_id, pe.fecha,
           SUM(pe.v_fis) AS v_fis,
           SUM(pe.v_mec) AS v_mec,
           SUM(pe.var1)  AS var1,
           COUNT(*) FILTER (WHERE NOT pe.sin_medicion AND pe.mf IS NOT NULL)::int AS puntos_medidos,
           COUNT(*)::int AS puntos_total,
           COUNT(*) FILTER (
               WHERE NOT pe.sin_medicion AND pe.mf IS NOT NULL
                 AND pe.comparable AND ABS(pe.var1) > pe.umbral
           )::int AS puntos_fuera_tolerancia,
           COUNT(*) FILTER (
               WHERE NOT pe.sin_medicion AND pe.mf IS NOT NULL AND pe.falta_contador
           )::int AS puntos_sin_contador,
           MAX(pe.estado)     AS estado_cierre,
           MAX(pe.medido_por) AS medido_por
      FROM punto_eval pe
     GROUP BY pe.faena_id, pe.fecha
),
despachos AS (
    SELECT d.faena_id, d.fecha,
           SUM(d.litros) FILTER (WHERE d.tipo_movimiento = 'venta')::numeric      AS litros_venta,
           SUM(d.litros) FILTER (WHERE d.tipo_movimiento = 'trasvasije')::numeric AS litros_trasvasije,
           SUM(d.litros) FILTER (WHERE d.tipo_movimiento <> 'venta')::numeric     AS litros_no_venta,
           SUM(d.litros)::numeric                                                 AS litros_total,
           COUNT(*)::int                                                          AS despachos,
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
    COALESCE(pu.faena_id, de.faena_id, re.faena_id) AS faena_id,
    COALESCE(pu.fecha, de.fecha, re.fecha)          AS fecha,
    pu.estado_cierre,
    pu.medido_por,
    pu.puntos_medidos,
    pu.puntos_total,
    pu.puntos_fuera_tolerancia,
    pu.puntos_sin_contador,
    pu.v_fis,
    pu.v_mec,
    pu.var1,
    CASE
        WHEN pu.fecha IS NULL               THEN 'sin_cierre'
        WHEN pu.estado_cierre <> 'firmado'  THEN 'borrador'
        WHEN pu.puntos_fuera_tolerancia > 0 THEN 'revisar'
        -- Un punto sin contador leído no cuadra ni descuadra: no se puede saber.
        WHEN pu.puntos_sin_contador > 0     THEN 'incompleto'
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
FROM puntos pu
FULL JOIN despachos de ON de.faena_id = pu.faena_id AND de.fecha = pu.fecha
FULL JOIN recep     re ON re.faena_id = COALESCE(pu.faena_id, de.faena_id)
                      AND re.fecha    = COALESCE(pu.fecha, de.fecha);

GRANT SELECT ON public.v_comb_faena_control_diario TO authenticated;

-- ── 2. Las excepciones también ─────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_excepciones AS
SELECT c.faena_id, NULL::date AS fecha, 'ceco_por_confirmar'::text AS tipo,
       c.codigo AS referencia,
       ('CECO ' || c.codigo || ' anotado por ' || COALESCE(c.anotado_por, 'terreno'))::text AS detalle,
       c.litros, c.despachos::int AS cantidad
  FROM v_comb_faena_ceco_por_confirmar c

UNION ALL
-- Sólo las ventas necesitan CECO. Un trasvasije sale del estanque pero no se
-- le imputa a nadie: exigirle CECO es fabricar una excepción falsa.
SELECT d.faena_id, d.fecha, 'despacho_sin_ceco',
       COALESCE(e.nombre, d.equipo_texto, 'equipo sin identificar'),
       ('Carga sin CECO' || COALESCE(' a ' || COALESCE(e.nombre, d.equipo_texto), ''))::text,
       d.litros, 1
  FROM combustible_faena_despachos d
  LEFT JOIN combustible_faena_equipos e ON e.id = d.equipo_id
 WHERE NOT d.anulado AND d.ceco_id IS NULL AND d.tipo_movimiento = 'venta'

UNION ALL
-- Fuera de tolerancia: sólo donde SE PUEDE comparar.
SELECT p.faena_id, p.fecha, 'fuera_de_tolerancia',
       p.estanque_nombre,
       ('Varilla ' || round(p.v_fis) || ' L contra contador ' || round(p.v_mec) || ' L')::text,
       ABS(p.var1), 1
  FROM v_comb_faena_cierre_punto p
  LEFT JOIN combustible_faena_config c ON c.faena_id = p.faena_id
 WHERE NOT p.sin_medicion AND p.mf IS NOT NULL
   AND p.medidores_total > 0 AND p.medidores_leidos = p.medidores_total
   AND ABS(p.var1) > GREATEST(
         GREATEST(ABS(p.v_fis), ABS(p.v_mec)) * COALESCE(c.tolerancia_pct, 0.005),
         COALESCE(c.tolerancia_piso_lt, 50))

UNION ALL
-- Contador sin leer: otro problema, otra acción. Ir a anotar un número no es
-- lo mismo que investigar una pérdida.
SELECT p.faena_id, p.fecha, 'contador_sin_leer',
       p.estanque_nombre,
       ('Se midió la varilla pero faltan ' || (p.medidores_total - p.medidores_leidos)
        || ' de ' || p.medidores_total || ' contadores. Sin eso no hay control cruzado.')::text,
       NULL::numeric, (p.medidores_total - p.medidores_leidos)
  FROM v_comb_faena_cierre_punto p
 WHERE NOT p.sin_medicion AND p.mf IS NOT NULL
   AND p.medidores_total > 0 AND p.medidores_leidos < p.medidores_total

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

-- ── 3. Un módulo de permiso que sí existe ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_comb_faena_confirmar_ceco(
    p_ceco_id uuid,
    p_codigo  text DEFAULT NULL,
    p_empresa text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_faena UUID; v_nuevo TEXT; v_existente UUID; v_movidos INT := 0;
BEGIN
    -- Anotar un CECO lo puede hacer cualquiera que despache — es registrar lo
    -- que sabe. Confirmarlo es otra cosa: decide a qué centro de costo se le
    -- imputa el combustible, y eso es una decisión contable.
    IF NOT public.fn_tiene_permiso_modulo('inventario', 'edit', ARRAY[
           'administrador','gerencia','subgerente_operaciones',
           'jefe_operaciones','supervisor','planificador'])
    THEN
        RAISE EXCEPTION 'No autorizado para confirmar CECO.' USING ERRCODE = '42501';
    END IF;

    SELECT faena_id INTO v_faena FROM combustible_faena_cecos WHERE id = p_ceco_id;
    IF v_faena IS NULL THEN RAISE EXCEPTION 'CECO no existe.'; END IF;

    v_nuevo := upper(trim(COALESCE(p_codigo, '')));

    IF length(v_nuevo) >= 2 THEN
        SELECT id INTO v_existente FROM combustible_faena_cecos
         WHERE faena_id = v_faena AND upper(trim(codigo)) = v_nuevo AND id <> p_ceco_id
         LIMIT 1;
    END IF;

    IF v_existente IS NOT NULL THEN
        UPDATE combustible_faena_despachos SET ceco_id = v_existente WHERE ceco_id = p_ceco_id;
        GET DIAGNOSTICS v_movidos = ROW_COUNT;
        UPDATE combustible_faena_cecos SET activo = false WHERE id = p_ceco_id;
        RETURN jsonb_build_object('fusionado_con', v_existente, 'despachos_movidos', v_movidos);
    END IF;

    UPDATE combustible_faena_cecos
       SET codigo     = COALESCE(NULLIF(v_nuevo,''), codigo),
           empresa    = COALESCE(NULLIF(trim(COALESCE(p_empresa,'')),''), empresa),
           confirmado = true,
           origen     = 'maestro'
     WHERE id = p_ceco_id;

    RETURN jsonb_build_object('confirmado', true, 'ceco_id', p_ceco_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_confirmar_ceco(uuid, text, text) TO authenticated;

COMMIT;
