-- ============================================================================
-- MIG403 · La campanita deja de acumular para siempre
-- ----------------------------------------------------------------------------
-- LO QUE SE VE
-- El contador de la campanita marca tope. Cuando un indicador siempre dice
-- «muchos» deja de informar: nadie lo mira, y el aviso que sí importa —el vale
-- nuevo que le llegó a bodega— se pierde entre los que llevan meses sin leer.
--
-- LO QUE HAY DETRÁS, CONTADO
--   2.531 avisos sin leer en total · ~195 por persona
--   Ninguno está duplicado: son todos distintos. No es un bug de repetición.
--   El más viejo es del 10 de abril.
--
-- Y de los 1.476 marcados como «requiere acción»:
--
--     no_conformidad ......... 1.314   ← el 89%
--     vale_emitido ...........    65
--     recurso_solicitado .....    51
--     recurso_por_comprar ....    46
--
-- LO QUE SE ARREGLA ACÁ
-- La higiene: un aviso que nadie leyó en 45 días dejó de ser un aviso. Se marca
-- como leído y se corre todos los días. No se borra nada — queda con
-- `leida_en` y `motivo_cierre`, así que la trazabilidad se conserva.
--
-- LO QUE NO SE ARREGLA ACÁ, Y ES LO GRANDE
-- Los 1.314 avisos de no conformidad salen de 114 NC: cada una le avisa a once
-- personas a la vez. Y apuntan a una pantalla que YA TIENE su propio contador
-- en el menú lateral. La campanita está repitiendo 1.314 veces algo que el
-- sidebar dice una vez.
--
-- Arreglar eso es decidir A QUIÉN se le avisa de una NC —hoy es a todo
-- administrador, jefe de mantenimiento y supervisor— y esa es una decisión de
-- operaciones, no de una migración. Con la higiene de acá el número baja, pero
-- no va a bajar de verdad hasta que se tome esa decisión.
-- ============================================================================

BEGIN;

ALTER TABLE public.alertas
  ADD COLUMN IF NOT EXISTS motivo_cierre TEXT;

COMMENT ON COLUMN public.alertas.motivo_cierre IS
  'MIG403: por qué se marcó leída. NULL = la leyó una persona; «caducada» = nadie la abrió en 45 días.';

-- ── La higiene ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_alertas_caducar(p_dias integer DEFAULT 45)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_n INTEGER;
BEGIN
    UPDATE alertas
       SET leida = TRUE,
           leida_en = NOW(),
           motivo_cierre = 'caducada'
     WHERE NOT leida
       AND created_at < NOW() - (p_dias || ' days')::interval;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END $function$;

COMMENT ON FUNCTION public.fn_alertas_caducar(integer) IS
  'MIG403: da por leído lo que nadie abrió en N días. No borra: deja motivo_cierre = caducada.';

-- ── Todos los días, con el resto de la higiene ────────────────────────────
DO $r$
BEGIN
    PERFORM cron.unschedule('alertas-caducar');
EXCEPTION WHEN OTHERS THEN NULL;
END
$r$;

SELECT cron.schedule('alertas-caducar', '20 5 * * *',
                     $$SELECT public.fn_alertas_caducar(45)$$);

-- ── Pasada inicial ────────────────────────────────────────────────────────
DO $r$
DECLARE v_antes INT; v_cerradas INT; v_despues INT; r RECORD;
BEGIN
    SELECT count(*) INTO v_antes FROM alertas WHERE NOT leida;
    v_cerradas := fn_alertas_caducar(45);
    SELECT count(*) INTO v_despues FROM alertas WHERE NOT leida;
    RAISE NOTICE 'Sin leer: % → % (caducadas: %)', v_antes, v_despues, v_cerradas;

    FOR r IN
        SELECT u.nombre_completo AS quien, count(*) AS n
          FROM alertas a JOIN usuarios_perfil u ON u.id = a.destinatario_id
         WHERE NOT a.leida AND a.requiere_accion
         GROUP BY 1 ORDER BY 2 DESC LIMIT 4
    LOOP RAISE NOTICE '  accionables de %: %', r.quien, r.n; END LOOP;

    SELECT count(*) INTO v_despues FROM alertas
     WHERE NOT leida AND requiere_accion AND tipo = 'no_conformidad';
    RAISE NOTICE 'De lo que queda accionable, % son de no conformidad (114 NC avisadas a 11 personas cada una)', v_despues;
END
$r$;

COMMIT;
