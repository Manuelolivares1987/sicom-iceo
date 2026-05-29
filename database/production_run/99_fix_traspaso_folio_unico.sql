-- ============================================================================
-- 99_fix_traspaso_folio_unico.sql
-- ----------------------------------------------------------------------------
-- BUG: rpc_registrar_traspaso_combustible (MIG76) genera el folio como
--   'TRA-' || TO_CHAR(v_fecha, 'YYYYMMDD-HH24MISS')
-- usando v_fecha = la fecha del traspaso. Pero el formulario SIEMPRE envia la
-- hora en 00:00:00 (fecha_traspaso = `${fecha}T00:00:00Z`), por lo que el
-- HHMMSS es siempre '000000'. Como combustible_traspasos.folio es UNIQUE, el
-- PRIMER traspaso de un dia funciona y CUALQUIER traspaso adicional el MISMO
-- dia falla con "duplicate key value violates unique constraint ..._folio_key".
-- (Por eso 15K->1K funciono una vez por dia, pero un segundo traspaso ese dia
--  -ej. 15K->600- reventaba.)
--
-- FIX: el folio conserva la FECHA de negocio (v_fecha) pero toma la HORA del
-- reloj real de insercion (clock_timestamp con milisegundos) + 3 chars random,
-- garantizando unicidad aunque haya varios traspasos el mismo dia/segundo.
-- Se trae la definicion viva y se reemplaza solo esa expresion (patron MIG93),
-- para no re-transcribir las ~250 lineas. Idempotente.
-- ============================================================================

DO $mig99$
DECLARE
    v_def TEXT;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE p.proname = 'rpc_registrar_traspaso_combustible'
       AND n.nspname = 'public'
     LIMIT 1;

    IF v_def IS NULL THEN
        RAISE EXCEPTION 'rpc_registrar_traspaso_combustible no existe';
    END IF;

    -- Idempotencia: si ya esta corregida (usa clock_timestamp en el folio), no tocar.
    IF position('clock_timestamp(), ''HH24MISSMS''' IN v_def) > 0 THEN
        RAISE NOTICE 'Folio ya corregido (clock_timestamp presente). Sin cambios.';
        RETURN;
    END IF;

    IF position('TO_CHAR(v_fecha, ''YYYYMMDD-HH24MISS'')' IN v_def) = 0 THEN
        RAISE EXCEPTION 'Patron del folio no encontrado; revisar manualmente la funcion.';
    END IF;

    v_def := replace(
        v_def,
        'TO_CHAR(v_fecha, ''YYYYMMDD-HH24MISS'')',
        'TO_CHAR(v_fecha, ''YYYYMMDD'') || ''-'' || TO_CHAR(clock_timestamp(), ''HH24MISSMS'') || ''-'' || upper(substr(md5(random()::text), 1, 3))'
    );
    EXECUTE v_def;
    RAISE NOTICE 'rpc_registrar_traspaso_combustible: folio ahora unico por traspaso.';
END
$mig99$;

-- Verificacion: la funcion debe contener la nueva expresion del folio.
SELECT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.proname = 'rpc_registrar_traspaso_combustible'
      AND pg_get_functiondef(p.oid) LIKE '%clock_timestamp(), ''HH24MISSMS''%'
) AS folio_unico_aplicado;

NOTIFY pgrst, 'reload schema';
