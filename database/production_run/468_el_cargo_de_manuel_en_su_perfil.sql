-- ============================================================================
-- MIG468 · El cargo de Manuel en su perfil
-- ============================================================================
--
-- POR QUÉ IMPORTA AHORA Y ANTES NO
-- Desde MIG467 el certificado propone el nombre y el CARGO desde el perfil de
-- quien emite. El perfil de Manuel decía «Administrador de Contrato», pero en
-- el certificado que llenó a mano firmó como «Subgerente de Operaciones» — que
-- es su cargo real. Confirmado por él: «Subgerente Operaciones».
--
-- Mientras el cargo era decorativo, la diferencia no molestaba a nadie. Ahora
-- sale impreso en un papel que se presenta ante terceros, así que el perfil
-- tiene que decir la verdad o el formulario propone algo que hay que corregir
-- cada vez.
--
-- SE ESCRIBE CON «DE», que es como aparece en el certificado ya emitido y como
-- se escribe el cargo en la documentación de la empresa. Si se prefiere sin
-- preposición, es un UPDATE de una fila.
-- ============================================================================

BEGIN;

UPDATE usuarios_perfil
   SET cargo = 'Subgerente de Operaciones'
 WHERE nombre_completo = 'Manuel Olivares'
   AND cargo IS DISTINCT FROM 'Subgerente de Operaciones';

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE r RECORD; v_n INT := 0;
BEGIN
    FOR r IN SELECT nombre_completo, cargo, rol::TEXT rol FROM usuarios_perfil
              WHERE nombre_completo = 'Manuel Olivares' LOOP
        v_n := v_n + 1;
        RAISE NOTICE '% · cargo=«%» · rol=%', r.nombre_completo, r.cargo, r.rol;
        IF r.cargo IS DISTINCT FROM 'Subgerente de Operaciones' THEN
            RAISE EXCEPTION 'FALLO: el cargo quedó como «%»', r.cargo;
        END IF;
    END LOOP;
    IF v_n = 0 THEN RAISE EXCEPTION 'FALLO: no se encontró el perfil'; END IF;
    RAISE NOTICE 'el certificado va a proponer ese cargo por defecto';
END
$mig$;

COMMIT;
