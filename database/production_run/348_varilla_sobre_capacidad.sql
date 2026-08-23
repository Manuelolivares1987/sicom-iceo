-- ============================================================================
-- MIG348 · Una varilla mal tecleada reventaba el cierre con un error ilegible
-- ----------------------------------------------------------------------------
-- Probando un turno sin señal apareció esto: si la medición final supera la
-- capacidad del estanque, el trigger que sincroniza el stock choca contra
-- `chk_ce_stock_capacidad` y el cierre entero falla con:
--
--     new row for relation "combustible_estanques" violates check constraint
--     "chk_ce_stock_capacidad"
--
-- Un supervisor que teclea 78.000 en vez de 7.800 —que es el error de dedo más
-- común que existe: un cero de más— recibe eso, a las 18:00, con el turno
-- terminado. No dice qué punto, no dice qué número, y no dice qué hacer.
--
-- DOS ARREGLOS, PORQUE SON DOS PROBLEMAS
--
-- 1. EL MENSAJE. Antes de guardar se avisa con nombre y número:
--       «Estación Isla Mina — Tanque 1: anotó 78.000 L y el estanque es de
--        75.000 L. Revise el número.»
--
-- 2. EL TRIGGER NO PUEDE TUMBAR EL CIERRE. La medición física es un dato del
--    turno; el stock del maestro es una consecuencia. Si por lo que sea el
--    número no cabe, se guarda el cierre igual y el stock se deja tope, no se
--    pierde el turno completo por sincronizar una columna derivada.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_comb_sincronizar_stock()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NEW.estado = 'firmado' AND COALESCE(OLD.estado,'') <> 'firmado' THEN
        -- El stock es una consecuencia de la medicion, no al reves. Si el
        -- numero no cabe en el estanque se topa aca y el cierre igual se
        -- guarda: perder el turno entero por sincronizar una columna derivada
        -- seria el peor intercambio posible.
        UPDATE combustible_estanques e
           SET stock_teorico_lt = LEAST(p.mf, e.capacidad_lt), updated_at = NOW()
          FROM combustible_faena_cierre_punto p
         WHERE p.cierre_id = NEW.id AND p.estanque_id = e.id
           AND NOT p.sin_medicion AND p.mf IS NOT NULL;
    END IF;
    RETURN NEW;
END;
$function$;

-- ── El aviso, con nombre y número ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_comb_revisar_capacidad(p_cierre_id uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_txt TEXT;
BEGIN
    SELECT string_agg(
             -- El separador de miles de to_char sale del locale del servidor,
             -- que aca es el ingles. Se cambia a punto para que el numero se
             -- lea como se escribe en Chile.
             e.nombre || ': anotó ' || replace(to_char(p.mf, 'FM999G999'), ',', '.') ||
             ' L y el estanque es de ' ||
             replace(to_char(e.capacidad_lt, 'FM999G999'), ',', '.') || ' L',
             ' · ' ORDER BY e.orden_cierre)
      INTO v_txt
      FROM combustible_faena_cierre_punto p
      JOIN combustible_estanques e ON e.id = p.estanque_id
     WHERE p.cierre_id = p_cierre_id AND NOT p.sin_medicion
       AND p.mf IS NOT NULL AND e.capacidad_lt IS NOT NULL
       AND p.mf > e.capacidad_lt;

    IF v_txt IS NOT NULL THEN
        RAISE EXCEPTION 'La medición no cabe en el estanque. %. Revise el número.',
            v_txt USING ERRCODE = '22023';
    END IF;
END;
$function$;

-- El aviso se dispara al firmar, junto con las otras revisiones.
CREATE OR REPLACE FUNCTION public.fn_comb_al_firmar_revisar()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NEW.estado = 'firmado' AND COALESCE(OLD.estado,'') <> 'firmado' THEN
        PERFORM public.fn_comb_revisar_capacidad(NEW.id);
    END IF;
    RETURN NEW;
END;
$function$;

-- Corre ANTES que el de sincronizar el stock, para que el mensaje que llegue
-- sea el legible y no el del CHECK.
DROP TRIGGER IF EXISTS trg_comb_al_firmar_revisar ON public.combustible_faena_cierre;
CREATE TRIGGER trg_comb_al_firmar_revisar
    BEFORE UPDATE OF estado ON public.combustible_faena_cierre
    FOR EACH ROW EXECUTE FUNCTION public.fn_comb_al_firmar_revisar();

COMMIT;
