-- ============================================================================
-- SICOM-ICEO | 214 — Informe de recobro con TODOS los hallazgos del checklist
-- ----------------------------------------------------------------------------
-- Pedido de Manuel (2026-07-09): al realizar el checklist de un equipo, el
-- sistema debe dar la opción de crear el informe para recobros con todos los
-- hallazgos encontrados.
--
-- La base ya existe (informes_recepcion + informe_recepcion_hallazgos + PDF de
-- emisión). Lo que faltaba era el volcado en un clic: hoy los hallazgos se
-- digitan a mano o llegan solo por el diff entrega↔recepción.
--
--   * informe_recepcion_hallazgos.checklist_v2_item_id: amarra el hallazgo al
--     ítem V02 que lo originó (idempotencia — no se duplica al re-ejecutar).
--   * fn_generar_hallazgos_desde_checklist(informe): toma el checklist V02
--     vinculado al informe y crea UN hallazgo por cada ítem NO OK (sección,
--     descripción, observación y foto del ítem; gravedad 'critica' si el ítem
--     es crítico; atribuible al cliente por defecto — el encargado lo ajusta
--     al emitir). Idempotente.
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. Vínculo hallazgo ↔ ítem del checklist V02 ─────────────────────────────
ALTER TABLE informe_recepcion_hallazgos
    ADD COLUMN IF NOT EXISTS checklist_v2_item_id UUID;
COMMENT ON COLUMN informe_recepcion_hallazgos.checklist_v2_item_id IS
    'Ítem de checklist_v2_instance_item que originó el hallazgo (MIG214, sin FK rígido).';
CREATE INDEX IF NOT EXISTS idx_irh_cl2item ON informe_recepcion_hallazgos(checklist_v2_item_id);

-- ── 2. RPC — volcar los NO OK del checklist como hallazgos del informe ──────
CREATE OR REPLACE FUNCTION fn_generar_hallazgos_desde_checklist(p_informe_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_estado TEXT;
    v_inst   UUID;
    v_total  INT := 0;
    v_creados INT := 0;
    r RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;

    SELECT estado::text INTO v_estado FROM informes_recepcion WHERE id = p_informe_id;
    IF v_estado IS NULL THEN RAISE EXCEPTION 'Informe % no existe', p_informe_id; END IF;
    IF v_estado IN ('emitido','cancelado') THEN
        RAISE EXCEPTION 'El informe ya está % — no se pueden agregar hallazgos.', v_estado;
    END IF;

    SELECT id INTO v_inst FROM checklist_v2_instance
     WHERE informe_recepcion_id = p_informe_id
     ORDER BY created_at DESC LIMIT 1;
    IF v_inst IS NULL THEN
        RETURN jsonb_build_object('creados', 0, 'ya_existian', 0, 'total_no_ok', 0,
            'mensaje', 'Sin checklist vinculado al informe.');
    END IF;

    FOR r IN
        SELECT ii.id,
               COALESCE(ti.bloque::text, 'Checklist')                 AS seccion,
               COALESCE(ii.descripcion_custom, ti.descripcion, 'Ítem') AS descripcion,
               ii.observacion, ii.foto_url,
               COALESCE(ti.critico, false)                            AS critico
          FROM checklist_v2_instance_item ii
          LEFT JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
         WHERE ii.instance_id = v_inst AND ii.resultado = 'no_ok'
    LOOP
        v_total := v_total + 1;
        -- Idempotente: si el ítem ya tiene hallazgo (en cualquier informe), no duplicar
        IF EXISTS (SELECT 1 FROM informe_recepcion_hallazgos WHERE checklist_v2_item_id = r.id) THEN
            CONTINUE;
        END IF;
        INSERT INTO informe_recepcion_hallazgos
            (informe_id, seccion, descripcion, gravedad, atribuible_cliente, fotos, observacion, checklist_v2_item_id)
        VALUES
            (p_informe_id, r.seccion, r.descripcion,
             (CASE WHEN r.critico THEN 'critica' ELSE 'menor' END)::gravedad_hallazgo_enum,
             true,
             CASE WHEN r.foto_url IS NOT NULL THEN jsonb_build_array(r.foto_url) ELSE '[]'::jsonb END,
             r.observacion, r.id);
        v_creados := v_creados + 1;
    END LOOP;

    RETURN jsonb_build_object('creados', v_creados, 'ya_existian', v_total - v_creados, 'total_no_ok', v_total);
END $$;
GRANT EXECUTE ON FUNCTION fn_generar_hallazgos_desde_checklist(UUID) TO authenticated;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'col_vinculo', (SELECT EXISTS (SELECT 1 FROM information_schema.columns
        WHERE table_name='informe_recepcion_hallazgos' AND column_name='checklist_v2_item_id')),
    'rpc', (SELECT count(*) = 1 FROM pg_proc WHERE proname='fn_generar_hallazgos_desde_checklist')
) AS resultado;

NOTIFY pgrst, 'reload schema';
