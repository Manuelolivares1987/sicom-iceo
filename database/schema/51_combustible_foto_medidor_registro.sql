-- ============================================================================
-- SICOM-ICEO | Migracion 51 — Foto obligatoria al registrar medidor
-- ============================================================================
-- Para reducir riesgo de adulteracion de la lectura inicial declarada,
-- se exige una foto del totalizador al dar de alta un medidor.
-- La foto sella la "linea base" contra la cual se validan movimientos.
-- ============================================================================

ALTER TABLE combustible_medidores
    ADD COLUMN IF NOT EXISTS foto_registro_url TEXT;

COMMENT ON COLUMN combustible_medidores.foto_registro_url IS
    'Foto del totalizador al momento del alta del medidor. Evidencia de la lectura_acumulada_actual inicial declarada.';

-- Check diferido: la foto queda obligatoria para altas nuevas (NOT VALID evita
-- romper registros previos al migrar; se aplica a todas las filas nuevas).
ALTER TABLE combustible_medidores
    DROP CONSTRAINT IF EXISTS chk_cm_foto_registro;

ALTER TABLE combustible_medidores
    ADD CONSTRAINT chk_cm_foto_registro CHECK (foto_registro_url IS NOT NULL) NOT VALID;


-- ============================================================================
-- SMOKE TEST
-- ============================================================================

DO $$
DECLARE
    v_col_ok BOOLEAN;
    v_con_ok BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_name = 'combustible_medidores'
           AND column_name = 'foto_registro_url'
    ) INTO v_col_ok;

    SELECT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
         WHERE table_name = 'combustible_medidores'
           AND constraint_name = 'chk_cm_foto_registro'
    ) INTO v_con_ok;

    RAISE NOTICE '== Migracion 51 ==';
    RAISE NOTICE 'Columna foto_registro_url ............... %', v_col_ok;
    RAISE NOTICE 'Constraint chk_cm_foto_registro ......... %', v_con_ok;

    IF NOT (v_col_ok AND v_con_ok) THEN
        RAISE EXCEPTION 'Migracion 51 incompleta.';
    END IF;
END $$;
