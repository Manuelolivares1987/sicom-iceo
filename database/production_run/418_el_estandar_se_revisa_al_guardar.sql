-- ============================================================================
-- MIG418 · El estándar se revisa al guardar, no después
-- ----------------------------------------------------------------------------
-- Mientras se corregían las hermeticidades mal cargadas, a las 22:01 entró una
-- nueva: SVBJ-57, emisión 07-08-2026, vencimiento 07-08-2027. Un año otra vez,
-- en el mismo tipo de certificado que se acababa de comprobar que dura seis
-- meses, cargada por el administrador desde la ficha del equipo.
--
-- No fue descuido. El formulario pide las dos fechas a mano y no tiene idea de
-- cuánto dura cada papel: quien carga tiene que acordarse. Eso es exactamente
-- lo que Manuel dijo que no quería — «que el sistema chequee, más que estar
-- supeditado a que alguien haga la pega».
--
-- ── DOS CANDADOS, NO UNO ───────────────────────────────────────────────────
-- En la pantalla, el formulario ahora propone el vencimiento del estándar y
-- avisa si lo que se escribe no calza. Pero la pantalla no es el único camino
-- a la tabla, y una advertencia se puede pasar de largo.
--
-- Acá va el segundo candado, en la base: si el plazo guardado no coincide con
-- el estándar del tipo, la fila queda marcada `vigencia_dudosa`. NO se corrige
-- la fecha —el papel manda, y puede decir algo distinto por una razón válida—
-- pero deja de mostrarse en verde hasta que alguien lo confirme.
--
-- Un mes de tolerancia: los certificados se emiten «a seis meses» contando
-- días corridos y eso mueve la fecha unos días para uno u otro lado.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_certificacion_revisar_estandar()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE v_meses INT; v_real NUMERIC; v_esperado DATE;
BEGIN
    -- Sin fechas reales no hay nada que comparar.
    IF NEW.fecha_vencimiento IS NULL OR NEW.fecha_emision IS NULL
       OR NEW.fecha_vencimiento >= '2099-01-01'::date
       OR NEW.fecha_emision >= '2099-01-01'::date THEN
        RETURN NEW;
    END IF;

    SELECT meses INTO v_meses FROM certificado_vigencia_estandar WHERE tipo = NEW.tipo::text;
    IF v_meses IS NULL THEN RETURN NEW; END IF;

    v_real := (NEW.fecha_vencimiento::date - NEW.fecha_emision::date) / 30.44;
    v_esperado := (NEW.fecha_emision::date + (v_meses || ' months')::INTERVAL)::date;

    IF round(v_real) <> v_meses THEN
        NEW.vigencia_dudosa := TRUE;
        NEW.vigencia_dudosa_nota :=
            'MIG418 · guardado con ' || round(v_real) || ' meses de vigencia; este documento dura '
            || v_meses || '. Según la emisión (' || to_char(NEW.fecha_emision::date,'DD-MM-YYYY')
            || ') el vencimiento sería ' || to_char(v_esperado,'DD-MM-YYYY')
            || '. Si el papel dice otra cosa, confirmar en Control documental.';
    END IF;

    RETURN NEW;
END $function$;

-- Corre DESPUÉS del que limpia la duda al anotar una fecha (MIG416): los
-- triggers BEFORE del mismo evento se disparan en orden alfabético, y
-- `trg_certificacion_z_estandar` va después de `trg_certificacion_limpiar_duda`.
-- Así, anotar una fecha limpia la marca y enseguida se vuelve a comprobar
-- contra el estándar: si la fecha nueva tampoco calza, la marca vuelve sola.
DROP TRIGGER IF EXISTS trg_certificacion_z_estandar ON public.certificaciones;
CREATE TRIGGER trg_certificacion_z_estandar
  BEFORE INSERT OR UPDATE ON public.certificaciones
  FOR EACH ROW EXECUTE FUNCTION public.fn_certificacion_revisar_estandar();

-- ── Pasar el nuevo candado por lo que ya está guardado ────────────────────
-- Incluye el SVBJ-57 que acaba de entrar con un año.
UPDATE certificaciones c
   SET updated_at = NOW()
  FROM certificado_vigencia_estandar e
 WHERE e.tipo = c.tipo::text
   AND c.fecha_emision < '2099-01-01'::date
   AND c.fecha_vencimiento < '2099-01-01'::date
   AND round((c.fecha_vencimiento::date - c.fecha_emision::date) / 30.44) <> e.meses
   AND NOT c.vigencia_dudosa;

DO $r$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT COALESCE(a.patente,a.codigo) AS patente, c.tipo::text AS tipo,
               c.fecha_emision::date AS em, c.fecha_vencimiento::date AS ve,
               c.vigencia_dudosa AS dud
          FROM certificaciones c JOIN activos a ON a.id = c.activo_id
          JOIN certificado_vigencia_estandar e ON e.tipo = c.tipo::text
         WHERE c.id IN (SELECT id FROM v_certificacion_actual)
         ORDER BY 1
    LOOP
        RAISE NOTICE '  % % : % -> %  dudosa=%', rpad(r.patente,10), rpad(r.tipo,14), r.em, r.ve, r.dud;
    END LOOP;
END
$r$;

COMMIT;
