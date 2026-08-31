-- ============================================================================
-- MIG466 · El planificador declara qué tipo de trabajo es
-- ============================================================================
--
-- LO QUE PLANTEÓ MANUEL
-- «A la hora de planificar, el que planifica debe indicar qué tipo de tarea es
-- —MPN, etc.— y en la pantalla del planificador debiera existir visiblemente la
-- leyenda. Creo que eso nos falta.»
--
-- Falta, y por una razón de fondo que conviene dejar escrita.
--
-- EL CONCEPTO SE DEDUCÍA DESPUÉS, Y ESO NO SIRVE PARA PLANIFICAR
-- Hasta hoy el concepto salía de `fn_taller_ot_concepto`: correctivo con salida
-- de bodega es RCR, sin salida es RSR; preventivo con contrato es MPN, sin
-- contrato MTN.
--
-- El problema es CUÁNDO se sabe. Que salga o no un repuesto de bodega ocurre
-- días después de planificar. O sea: al armar el plan, el planificador no puede
-- saber contra qué estándar de días se va a medir el trabajo que está
-- programando —y ese estándar es el que decide si la OT paga optimizado, normal
-- o con demora—.
--
-- Peor: el concepto podía CAMBIAR solo. Una OT planificada como RSR se
-- convertía en RCR el día que alguien sacaba un perno de bodega, y con eso le
-- cambiaba el plazo de 2/4/8 días a 5/10/20. Nadie decidió eso; lo decidió un
-- movimiento de inventario.
--
-- LO QUE SE HACE
--
--   1. El concepto se DECLARA al planificar y queda escrito en la OT, con
--      quién lo declaró y cuándo.
--   2. La deducción no desaparece: pasa a ser una SUGERENCIA. La pantalla la
--      propone y el planificador la acepta o la cambia.
--   3. Si el declarado difiere del sugerido, hay que escribir por qué. El
--      motivo queda guardado. No se prohíbe —el que planifica sabe más que una
--      regla— pero queda dicho.
--   4. Una vez ejecutada la OT, el concepto se congela. Es la misma regla que
--      la cuadrilla: lo que decide un pago no se edita después del hecho.
--
-- POR QUÉ IMPORTA QUE SEA DECLARADO Y NO DEDUCIDO
-- El concepto es lo único del bono que hoy nadie firma. El cargo lo pone RRHH,
-- la cuadrilla la pone el jefe, el tiempo lo pone el reloj — pero el estándar de
-- días contra el que se mide el trabajo lo ponía una consulta al kárdex. Ahora
-- tiene dueño.
--
-- LA LEYENDA
-- `rpc_taller_conceptos_bono` devuelve los cuatro conceptos con sus plazos,
-- leídos del juego de parámetros vigente y no escritos a mano en la pantalla:
-- si el acta cambia un plazo, la leyenda cambia sola.
-- ============================================================================

BEGIN;

-- ── 1 · El concepto declarado vive en la OT ─────────────────────────────────
ALTER TABLE ordenes_trabajo
  ADD COLUMN IF NOT EXISTS bono_concepto        TEXT,
  ADD COLUMN IF NOT EXISTS bono_concepto_por    UUID REFERENCES usuarios_perfil(id),
  ADD COLUMN IF NOT EXISTS bono_concepto_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS bono_concepto_motivo TEXT;

DO $c$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_ot_bono_concepto') THEN
        ALTER TABLE ordenes_trabajo
          ADD CONSTRAINT chk_ot_bono_concepto
          CHECK (bono_concepto IS NULL OR bono_concepto IN ('MPN','MTN','RCR','RSR'));
    END IF;
END
$c$;

COMMENT ON COLUMN ordenes_trabajo.bono_concepto IS
    'Qué tipo de trabajo declaró el planificador. Manda sobre la deducción '
    'automática, porque el estándar de días con el que se mide el bono tiene '
    'que estar decidido ANTES de ejecutar, no después.';

-- ── 2 · La deducción pasa a ser sugerencia ──────────────────────────────────
CREATE OR REPLACE FUNCTION fn_taller_ot_concepto_sugerido(p_ot_id UUID)
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
    IF v_familia IS NULL THEN RETURN NULL; END IF;

    IF v_familia = 'correctivo' THEN
        v_repuestos := EXISTS (SELECT 1 FROM movimientos_inventario m WHERE m.ot_id = p_ot_id)
                    OR EXISTS (SELECT 1 FROM salidas_bodega s WHERE s.ot_id = p_ot_id);
        RETURN CASE WHEN v_repuestos THEN 'RCR' ELSE 'RSR' END;
    END IF;

    RETURN CASE WHEN v_contrato IS NULL THEN 'MTN' ELSE 'MPN' END;
END;
$$;

-- ── 3 · Lo declarado manda; si no hay, se usa la sugerencia ─────────────────
CREATE OR REPLACE FUNCTION fn_taller_ot_concepto(p_ot_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        (SELECT ot.bono_concepto FROM ordenes_trabajo ot WHERE ot.id = p_ot_id),
        fn_taller_ot_concepto_sugerido(p_ot_id)
    );
$$;

-- ── 4 · Declararlo, con motivo si se aparta de la sugerencia ────────────────
CREATE OR REPLACE FUNCTION rpc_taller_ot_set_concepto(
    p_ot_id    UUID,
    p_concepto TEXT,
    p_motivo   TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_rol    TEXT;
    v_estado TEXT;
    v_folio  TEXT;
    v_sug    TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','jefe_operaciones','planificador') THEN
        RAISE EXCEPTION 'Tu perfil no puede declarar el tipo de trabajo de una OT.';
    END IF;

    SELECT ot.estado::TEXT, ot.folio::TEXT INTO v_estado, v_folio
      FROM ordenes_trabajo ot WHERE ot.id = p_ot_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Esa OT no existe.'; END IF;

    -- Misma regla que la cuadrilla: lo que decide un pago no se edita después.
    IF v_estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada') THEN
        RAISE EXCEPTION 'La % ya está ejecutada: el tipo de trabajo es la base del bono '
                        'y no se puede cambiar después.', v_folio;
    END IF;

    IF p_concepto IS NOT NULL AND p_concepto NOT IN ('MPN','MTN','RCR','RSR') THEN
        RAISE EXCEPTION 'Tipo de trabajo desconocido: «%».', p_concepto;
    END IF;

    v_sug := fn_taller_ot_concepto_sugerido(p_ot_id);

    IF p_concepto IS NOT NULL AND v_sug IS NOT NULL AND p_concepto <> v_sug
       AND length(COALESCE(TRIM(p_motivo), '')) < 10 THEN
        RAISE EXCEPTION 'El sistema sugiere % para esta OT y estás declarando %. '
                        'Escribe por qué: queda guardado junto al bono.', v_sug, p_concepto;
    END IF;

    UPDATE ordenes_trabajo
       SET bono_concepto        = p_concepto,
           bono_concepto_por    = CASE WHEN p_concepto IS NULL THEN NULL ELSE v_user END,
           bono_concepto_at     = CASE WHEN p_concepto IS NULL THEN NULL ELSE NOW() END,
           bono_concepto_motivo = CASE WHEN p_concepto IS NULL THEN NULL
                                       ELSE NULLIF(TRIM(COALESCE(p_motivo,'')), '') END,
           updated_at = NOW()
     WHERE id = p_ot_id;

    RETURN jsonb_build_object('success', true, 'concepto', p_concepto,
                              'sugerido', v_sug,
                              'difiere', p_concepto IS DISTINCT FROM v_sug);
END;
$$;

-- ── 5 · La leyenda, leída de los parámetros ─────────────────────────────────
--
-- La pantalla no escribe los plazos a mano: si el acta cambia uno, la leyenda
-- cambia sola.
CREATE OR REPLACE FUNCTION rpc_taller_conceptos_bono()
RETURNS TABLE (
    concepto        TEXT,
    descripcion     TEXT,
    dias_optimizado INT,
    dias_normal     INT,
    dias_demora     INT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT co.concepto, co.descripcion, co.dias_optimizado, co.dias_normal, co.dias_demora
      FROM taller_bono_concepto co
      JOIN taller_bono_parametros p ON p.id = co.parametros_id
     WHERE p.id = (SELECT id FROM taller_bono_parametros
                    ORDER BY estado = 'vigente' DESC, vigencia_desde DESC LIMIT 1)
     ORDER BY co.concepto;
$$;

REVOKE ALL ON FUNCTION fn_taller_ot_concepto_sugerido(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_taller_ot_concepto(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_ot_set_concepto(UUID, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_conceptos_bono() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_taller_ot_concepto_sugerido(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_taller_ot_concepto(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_ot_set_concepto(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_conceptos_bono() TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE
    r RECORD; v_n INT; v_dec INT;
BEGIN
    SELECT count(*) INTO v_n FROM ordenes_trabajo WHERE bono_concepto IS NOT NULL;
    RAISE NOTICE 'OT con tipo de trabajo YA declarado: % (arrancan en cero, como corresponde)', v_n;

    -- Sin declarar, el resultado tiene que ser idéntico al de antes.
    SELECT count(*) INTO v_n FROM ordenes_trabajo ot
     WHERE ot.estado::TEXT <> 'cancelada'
       AND fn_taller_ot_concepto(ot.id) IS DISTINCT FROM fn_taller_ot_concepto_sugerido(ot.id);
    IF v_n > 0 THEN
        RAISE EXCEPTION 'FALLO: % OT cambiaron de concepto sin que nadie declarara nada', v_n;
    END IF;
    RAISE NOTICE 'sin nada declarado, el concepto sigue saliendo igual que antes';

    RAISE NOTICE '=== la leyenda que va a ver el planificador ===';
    FOR r IN SELECT * FROM rpc_taller_conceptos_bono() LOOP
        RAISE NOTICE '  % · % · optimizado hasta %d, normal hasta %d, demora desde %d',
            r.concepto, rpad(r.descripcion, 42), r.dias_optimizado, r.dias_normal, r.dias_demora;
    END LOOP;

    -- Cuántas OT abiertas quedarían con la sugerencia sin confirmar.
    SELECT count(*) INTO v_dec FROM ordenes_trabajo ot
     WHERE ot.estado::TEXT NOT IN ('cerrada','cancelada','ejecutada_ok','ejecutada_con_observaciones')
       AND ot.bono_concepto IS NULL;
    RAISE NOTICE 'OT abiertas cuyo tipo de trabajo nadie ha declarado todavía: %', v_dec;
END
$mig$;

COMMIT;
