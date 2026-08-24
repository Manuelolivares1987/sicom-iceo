-- ============================================================================
-- MIG370 · «Faltan 1 folio(s)»
-- ----------------------------------------------------------------------------
-- La advertencia del informe salía con el paréntesis de plural que se pone
-- cuando no se quiere resolver la concordancia. Este texto lo lee el
-- Administrador de Contrato antes de emitirle el informe a CM Cenizas, y un
-- «Faltan 1 folio(s)» le baja el precio a todo lo demás que dice la pantalla.
--
-- Es un detalle, y por eso mismo se arregla: el informe es un documento hacia
-- afuera y ahí la prolijidad se lee como cuidado en el resto.
-- ============================================================================

BEGIN;

DO $patch$
DECLARE
    v_def TEXT;
BEGIN
    SELECT pg_get_functiondef('public.fn_faena_informe_mensual(uuid,date,date)'::regprocedure)
      INTO v_def;

    v_def := replace(v_def,
      $o$('Faltan ' || (v_bal->'folios'->>'faltantes') || ' folio(s) en la numeración: revisar si son tickets anulados o cargas sin registrar.')::text$o$,
      $n$(CASE WHEN (v_bal->'folios'->>'faltantes')::int = 1
               THEN 'Falta 1 folio en la numeración: revisar si es un ticket anulado o una carga sin registrar.'
               ELSE 'Faltan ' || (v_bal->'folios'->>'faltantes')
                    || ' folios en la numeración: revisar si son tickets anulados o cargas sin registrar.'
          END)::text$n$);

    IF v_def LIKE '%folio(s)%' THEN
        RAISE EXCEPTION 'MIG370: no se pudo reemplazar el texto de folios';
    END IF;

    EXECUTE v_def;
END
$patch$;

COMMIT;
