-- ============================================================================
-- MIG465 · El chequeo de calidad también es trabajo
-- ============================================================================
--
-- LA DECISIÓN
-- Manuel, 31-08-2026: «cuando Juan hace el chequeo, esa jornada sí cuenta,
-- porque él está revisando los equipos y detectando fallas».
--
-- Queda resuelto lo que MIG464 dejó abierto: revisar un equipo es trabajo de
-- taller y entra al plan de incentivo. Lo que no entra es el AUDITOR —Felipe
-- López, que audita y no ejecuta—; cuando el chequeo lo hace un mecánico, es
-- trabajo suyo y se le paga.
--
-- LO QUE FALTABA PARA QUE ESO FUNCIONE
-- `fn_taller_ot_concepto` sólo sabía clasificar tres tipos de OT: correctivo,
-- preventivo e inspeccion. Los otros dos que existen en el sistema quedaban en
-- NULL, y una OT sin concepto dice «no se pudo deducir el concepto», que
-- BLOQUEA el cierre del período:
--
--     verificacion_disponibilidad   4 OT (las cuatro canceladas)
--     inspeccion_recepcion          1 OT · OT-202607-00049, ejecutada
--
-- Hoy el daño es chico porque casi todas están canceladas. Pero son justo los
-- tipos de OT que produce un chequeo de equipos: con la decisión tomada, van a
-- empezar a cerrarse con cuadrilla, y cada una habría trabado el cierre del
-- corte hasta que alguien tocara SQL.
--
-- Y OT-202607-00049 ya está ejecutada y sin concepto: es una de las siete que
-- MIG464 detectó como «no le paga a nadie».
--
-- QUÉ SE HACE, Y POR QUÉ ASÍ
-- La correspondencia entre tipo de OT y familia de concepto pasa a una tabla.
-- Es una decisión de criterio —qué clase de trabajo es cada cosa— y las
-- decisiones de criterio cambian una fila, no una función. Cuando aparezca un
-- tipo de OT nuevo, clasificarlo es un INSERT:
--
--     INSERT INTO taller_bono_tipo_ot (tipo, familia, nota)
--     VALUES ('mi_tipo_nuevo', 'preventivo', 'por qué');
--
--     familia 'correctivo'  → RCR si salió algo de bodega, RSR si no
--     familia 'preventivo'  → MTN si el equipo no tiene contrato, MPN si tiene
--
-- Las dos inspecciones nuevas entran como 'preventivo', igual que `inspeccion`,
-- que ya se trataba así y nadie objetó. Si en la práctica el plazo no calza
-- —una verificación de disponibilidad no debería tomar los 5 a 20 días de una
-- mantención total— eso se corrige agregando su propio concepto en el juego de
-- parámetros, que también es una fila. Queda anotado para el acta.
-- ============================================================================

BEGIN;

-- ── 1 · Qué clase de trabajo es cada tipo de OT ─────────────────────────────
CREATE TABLE IF NOT EXISTS taller_bono_tipo_ot (
    tipo    TEXT PRIMARY KEY,
    familia TEXT NOT NULL,
    nota    TEXT,
    CONSTRAINT chk_bono_tipo_familia CHECK (familia IN ('correctivo','preventivo'))
);

COMMENT ON TABLE taller_bono_tipo_ot IS
    'Tipo de OT → familia de concepto del bono. correctivo da RCR/RSR según si '
    'salió algo de bodega; preventivo da MTN/MPN según si el equipo tiene '
    'contrato. Un tipo que no esté acá deja la OT sin concepto, y una OT sin '
    'concepto bloquea el cierre del período: clasificarlo es un INSERT.';

INSERT INTO taller_bono_tipo_ot (tipo, familia, nota) VALUES
    ('correctivo',                  'correctivo',
     'Reparación. Con repuesto de bodega es RCR, sin repuesto RSR.'),
    ('preventivo',                  'preventivo',
     'Mantención de pauta.'),
    ('inspeccion',                  'preventivo',
     'Ya se trataba así desde MIG452.'),
    ('verificacion_disponibilidad', 'preventivo',
     'Revisar un equipo y detectar fallas es trabajo de taller (decisión de Manuel, 31-08-2026).'),
    ('inspeccion_recepcion',        'preventivo',
     'Recepción de equipo: se revisa y se detectan fallas, igual que un chequeo.')
ON CONFLICT (tipo) DO UPDATE SET familia = EXCLUDED.familia, nota = EXCLUDED.nota;

ALTER TABLE taller_bono_tipo_ot ENABLE ROW LEVEL SECURITY;
-- Sin políticas: se lee sólo desde fn_taller_ot_concepto, que es SECURITY DEFINER.

-- ── 2 · El concepto sale de la tabla ────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_taller_ot_concepto(p_ot_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tipo      TEXT;
    v_contrato  UUID;
    v_familia   TEXT;
    v_repuestos BOOLEAN;
BEGIN
    SELECT ot.tipo::TEXT, ot.contrato_id INTO v_tipo, v_contrato
      FROM ordenes_trabajo ot WHERE ot.id = p_ot_id;
    IF v_tipo IS NULL THEN RETURN NULL; END IF;

    SELECT f.familia INTO v_familia FROM taller_bono_tipo_ot f WHERE f.tipo = v_tipo;
    -- Un tipo sin clasificar no se adivina: devuelve NULL y el motor dice «no se
    -- pudo deducir el concepto». Prefiero que frene el cierre a que invente una
    -- categoría y pague por ella.
    IF v_familia IS NULL THEN RETURN NULL; END IF;

    IF v_familia = 'correctivo' THEN
        -- ¿Salió algo de bodega por esta OT? Es lo que separa una reparación con
        -- reemplazo de una sin reemplazo, y hoy depende de que el mecánico se
        -- acuerde. El kárdex se acuerda siempre.
        v_repuestos := EXISTS (SELECT 1 FROM movimientos_inventario m WHERE m.ot_id = p_ot_id)
                    OR EXISTS (SELECT 1 FROM salidas_bodega s WHERE s.ot_id = p_ot_id);
        RETURN CASE WHEN v_repuestos THEN 'RCR' ELSE 'RSR' END;
    END IF;

    -- La mantención total es la que se hace cuando el equipo vuelve de arriendo:
    -- sin contrato vigente asociado.
    RETURN CASE WHEN v_contrato IS NULL THEN 'MTN' ELSE 'MPN' END;
END;
$$;

REVOKE ALL ON FUNCTION fn_taller_ot_concepto(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_taller_ot_concepto(UUID) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE
    r RECORD; v_n INT; v_sin INT;
BEGIN
    -- Ningún tipo de OT que exista en la base puede quedar sin clasificar.
    v_sin := 0;
    FOR r IN
        SELECT DISTINCT ot.tipo::TEXT t FROM ordenes_trabajo ot
         WHERE NOT EXISTS (SELECT 1 FROM taller_bono_tipo_ot f WHERE f.tipo = ot.tipo::TEXT)
    LOOP
        v_sin := v_sin + 1;
        RAISE NOTICE 'tipo de OT SIN clasificar: «%» — agrégalo a taller_bono_tipo_ot', r.t;
    END LOOP;
    IF v_sin > 0 THEN
        RAISE EXCEPTION 'FALLO: quedaron % tipos de OT sin clasificar', v_sin;
    END IF;

    SELECT count(*) INTO v_n FROM taller_bono_tipo_ot;
    RAISE NOTICE 'tipos de OT clasificados: %', v_n;

    -- Lo que antes no se podía clasificar y ahora sí.
    SELECT count(*) INTO v_n FROM ordenes_trabajo ot
     WHERE ot.tipo::TEXT IN ('verificacion_disponibilidad','inspeccion_recepcion')
       AND fn_taller_ot_concepto(ot.id) IS NOT NULL;
    RAISE NOTICE 'OT de chequeo que ahora tienen concepto: %', v_n;

    FOR r IN SELECT ot.folio, ot.tipo::TEXT t, ot.estado::TEXT e, fn_taller_ot_concepto(ot.id) c
               FROM ordenes_trabajo ot
              WHERE ot.tipo::TEXT IN ('verificacion_disponibilidad','inspeccion_recepcion')
              ORDER BY ot.folio
    LOOP
        RAISE NOTICE '   % · % · % → %', rpad(r.folio,20), rpad(r.t,28), rpad(r.e,12), r.c;
    END LOOP;

    -- Y que no quede ninguna OT viva sin concepto.
    SELECT count(*) INTO v_n FROM ordenes_trabajo ot
     WHERE ot.estado::TEXT <> 'cancelada' AND fn_taller_ot_concepto(ot.id) IS NULL;
    RAISE NOTICE 'OT no canceladas que siguen sin concepto: %', v_n;
END
$mig$;

COMMIT;
