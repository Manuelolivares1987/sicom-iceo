-- ============================================================================
-- SICOM-ICEO | 260 — La auditoría de calidad carga el V03 completo, se guarda
--                    sola y se puede anular
-- ----------------------------------------------------------------------------
-- Revisión pedida por Manuel el día en que este módulo se pone en marcha
-- (/dashboard/mantenimiento/auditoria-calidad?tab=plan).
--
-- QUÉ CHECKLIST SE CARGABA: el correcto —«Check-List Inspección y Recepción V03
-- (oficial - Excel revisado)», 188 ítems en 12 bloques— pero FILTRADO por el
-- tipo_equipamiento del equipo:
--     aljibe_agua 188 · aljibe_combustible 169 · camioneta/tracto/pluma 166
--     genérico y grúa horquilla 160
-- Los 28 que se caían en «genérico» son el bloque ALJIBE (13) y las pruebas
-- operativas (15), que incluyen las 6 PRUEBAS DE RUTA. Y hay 5 camiones de
-- verdad sin tipo asignado (FJTJ-61, RSCY-86, TRSS-13, TRSS-15, TTPC-47): hoy
-- se auditaban sin prueba de ruta.
--
-- DECISIÓN DE MANUEL: que cargue SIEMPRE el checklist completo, los 188, para
-- cualquier equipo. Lo que no aplique se marca N/A. Se conserva el dato de si
-- el ítem aplica o no al tipo del equipo (aplica_tipo) para que la pantalla lo
-- pueda sugerir, pero no se marca nada por adelantado.
--
-- Y tres cosas que iban a doler el primer día:
--   1. No había guardado parcial: 160-188 ítems vivían en la memoria del
--      navegador hasta apretar Aprobar. Una recarga borraba horas de trabajo.
--      → rpc_guardar_avance_auditoria
--   2. Dos auditorías pendientes de junio, una con la plantilla legacy de 14
--      ítems, que hoy aparecerían mezcladas con las nuevas.
--      → rpc_anular_auditoria_calidad + se anulan las dos
--   3. Los ítems llegaban planos, sin el bloque al que pertenecen: 188 filas
--      corridas. → se guarda bloque y bloque_orden en cada ítem
--
-- ADITIVA, IDEMPOTENTE. No borra datos.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_iniciar_auditoria_calidad') THEN
        RAISE EXCEPTION 'STOP — falta fn_iniciar_auditoria_calidad (MIG125).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM checklist_template_v2
                    WHERE momento_uso='recepcion_devolucion' AND activo=true) THEN
        RAISE EXCEPTION 'STOP — no hay checklist de inspección/recepción activo.';
    END IF;
END $$;


-- ── 1. Columnas nuevas ──────────────────────────────────────────────────────
ALTER TABLE public.auditoria_calidad_items
    ADD COLUMN IF NOT EXISTS bloque        TEXT,
    ADD COLUMN IF NOT EXISTS bloque_orden  INT,
    ADD COLUMN IF NOT EXISTS requiere_foto BOOLEAN NOT NULL DEFAULT false,
    -- false = el ítem no corresponde al tipo de este equipo (p.ej. ALJIBE en una
    -- camioneta). Se carga igual —el checklist va completo— pero la pantalla lo
    -- puede marcar como «no aplica a este equipo» para que se pase a N/A rápido.
    ADD COLUMN IF NOT EXISTS aplica_tipo   BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN public.auditoria_calidad_items.bloque IS
    'Bloque del checklist V03 al que pertenece el ítem, para agrupar en pantalla. MIG260.';
COMMENT ON COLUMN public.auditoria_calidad_items.aplica_tipo IS
    'false = no corresponde al tipo_equipamiento del equipo; se carga igual (checklist completo). MIG260.';

ALTER TABLE public.auditorias_calidad
    ADD COLUMN IF NOT EXISTS anulada        BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS anulada_motivo TEXT,
    ADD COLUMN IF NOT EXISTS anulada_por    UUID,
    ADD COLUMN IF NOT EXISTS anulada_at     TIMESTAMPTZ;


-- ── 2. Iniciar: el checklist COMPLETO, sin filtrar por tipo ─────────────────
CREATE OR REPLACE FUNCTION public.fn_iniciar_auditoria_calidad(
    p_activo_id uuid,
    p_ot_id     uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_aud  UUID;
    v_tot  INT;
    v_tipo tipo_equipamiento_enum;
    v_tpl  UUID;
    v_tpl_nombre TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM activos WHERE id = p_activo_id) THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id; END IF;

    SELECT COALESCE(tipo_equipamiento,'generico') INTO v_tipo FROM activos WHERE id = p_activo_id;
    SELECT id, nombre INTO v_tpl, v_tpl_nombre
      FROM checklist_template_v2
     WHERE momento_uso='recepcion_devolucion' AND activo=true
     ORDER BY version DESC LIMIT 1;

    INSERT INTO auditorias_calidad (activo_id, ot_id, iniciada_por, created_by)
    VALUES (p_activo_id, p_ot_id, v_user, v_user)
    RETURNING id INTO v_aud;

    IF v_tpl IS NOT NULL THEN
        -- [MIG260] TODOS los ítems del template. Antes se filtraba por
        -- tipo_equipamiento y un equipo sin tipo perdía 28 ítems, entre ellos
        -- las pruebas de ruta.
        INSERT INTO auditoria_calidad_items
            (auditoria_id, categoria, orden, descripcion, obligatorio, critico,
             referencia_cert_id, resultado, bloque, bloque_orden, requiere_foto, aplica_tipo)
        SELECT
            v_aud,
            ti.categoria_calidad,
            ti.bloque_orden * 1000 + ti.orden,
            ti.descripcion, ti.obligatorio, ti.critico,
            c.cert_id,
            CASE
                WHEN ti.categoria_calidad = 'documentacion' AND ti.cert_tipo IS NOT NULL THEN
                    CASE WHEN c.estado = 'vigente' THEN 'ok'
                         WHEN c.estado IS NULL THEN 'pendiente'
                         ELSE 'no_ok' END
                ELSE 'pendiente'
            END,
            ti.bloque, ti.bloque_orden, COALESCE(ti.requiere_foto, false),
            (v_tipo = ANY(ti.tipos_equipamiento))
        FROM checklist_template_v2_item ti
        LEFT JOIN LATERAL (
            SELECT cc.id AS cert_id, cc.estado AS estado
            FROM certificaciones cc
            WHERE cc.activo_id = p_activo_id
              AND ti.cert_tipo IS NOT NULL
              AND cc.tipo::TEXT = ti.cert_tipo
            ORDER BY cc.fecha_vencimiento DESC NULLS LAST
            LIMIT 1
        ) c ON true
        WHERE ti.template_id = v_tpl
          AND ti.categoria_calidad IS NOT NULL
        ORDER BY ti.bloque_orden, ti.orden;

        GET DIAGNOSTICS v_tot = ROW_COUNT;
    ELSE
        v_tot := 0;
    END IF;

    -- Fallback: plantilla legacy si el template no aportó ítems
    IF v_tot = 0 THEN
        INSERT INTO auditoria_calidad_items
            (auditoria_id, categoria, orden, descripcion, obligatorio, critico,
             referencia_cert_id, resultado, bloque, bloque_orden)
        SELECT
            v_aud, p.categoria, p.orden, p.descripcion, p.obligatorio, p.critico,
            c.cert_id,
            CASE
                WHEN p.categoria = 'documentacion' AND p.cert_tipo IS NOT NULL THEN
                    CASE WHEN c.estado = 'vigente' THEN 'ok'
                         WHEN c.estado IS NULL THEN 'pendiente'
                         ELSE 'no_ok' END
                ELSE 'pendiente'
            END,
            'Plantilla base', 1
        FROM auditoria_calidad_plantilla_items p
        LEFT JOIN LATERAL (
            SELECT cc.id AS cert_id, cc.estado AS estado
            FROM certificaciones cc
            WHERE cc.activo_id = p_activo_id
              AND p.cert_tipo IS NOT NULL
              AND cc.tipo::TEXT = p.cert_tipo
            ORDER BY cc.fecha_vencimiento DESC NULLS LAST
            LIMIT 1
        ) c ON true
        WHERE p.activo = true
        ORDER BY p.categoria, p.orden;
        GET DIAGNOSTICS v_tot = ROW_COUNT;
        v_tpl_nombre := 'plantilla legacy';
    END IF;

    UPDATE auditorias_calidad SET items_total = v_tot WHERE id = v_aud;
    RETURN jsonb_build_object(
        'auditoria_id', v_aud,
        'items_total', v_tot,
        'fuente', COALESCE(v_tpl_nombre, 'plantilla legacy'),
        'no_aplican_al_tipo', (SELECT count(*) FROM auditoria_calidad_items
                                WHERE auditoria_id = v_aud AND aplica_tipo = false));
END $function$;

COMMENT ON FUNCTION public.fn_iniciar_auditoria_calidad(UUID, UUID) IS
    'Abre la auditoría de calidad con el checklist V03 COMPLETO (sin filtrar por tipo de equipo). MIG125 + MIG260.';

REVOKE ALL ON FUNCTION public.fn_iniciar_auditoria_calidad(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_iniciar_auditoria_calidad(UUID, UUID) TO authenticated;


-- ── 3. Guardado parcial: que no se pierda el trabajo ────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_guardar_avance_auditoria(
    p_auditoria_id UUID,
    p_items        JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_aud  RECORD;
    v_item JSONB;
    v_n    INT := 0;
    v_marcados INT;
    v_total    INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('auditor_calidad','administrador') THEN
        RAISE EXCEPTION 'Solo el rol auditor_calidad puede auditar. Rol: %', v_rol;
    END IF;

    SELECT * INTO v_aud FROM auditorias_calidad WHERE id = p_auditoria_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'La auditoría no existe.'; END IF;
    IF v_aud.resultado <> 'pendiente' THEN
        RAISE EXCEPTION 'La auditoría ya fue resuelta (%): no admite más cambios.', v_aud.resultado;
    END IF;
    IF v_aud.anulada THEN RAISE EXCEPTION 'La auditoría está anulada.'; END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items,'[]'::JSONB)) LOOP
        UPDATE auditoria_calidad_items SET
            resultado   = COALESCE(v_item->>'resultado', resultado),
            observacion = COALESCE(v_item->>'observacion', observacion),
            foto_url    = COALESCE(v_item->>'foto_url', foto_url),
            completado_at = NOW(), completado_por = v_user
        WHERE id = (v_item->>'id')::UUID AND auditoria_id = p_auditoria_id;
        IF FOUND THEN v_n := v_n + 1; END IF;
    END LOOP;

    SELECT count(*) FILTER (WHERE resultado <> 'pendiente'), count(*)
      INTO v_marcados, v_total
      FROM auditoria_calidad_items WHERE auditoria_id = p_auditoria_id;

    UPDATE auditorias_calidad SET updated_at = NOW() WHERE id = p_auditoria_id;

    RETURN jsonb_build_object('guardados', v_n, 'marcados', v_marcados, 'total', v_total);
END;
$function$;

COMMENT ON FUNCTION public.rpc_guardar_avance_auditoria(UUID, JSONB) IS
    'Guarda el avance de una auditoría sin resolverla: una recarga ya no borra el trabajo. MIG260.';

REVOKE ALL ON FUNCTION public.rpc_guardar_avance_auditoria(UUID, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_guardar_avance_auditoria(UUID, JSONB) TO authenticated;


-- ── 4. Anular una auditoría que ya no sirve ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_anular_auditoria_calidad(
    p_auditoria_id UUID,
    p_motivo       TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_aud  RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('auditor_calidad','administrador','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Tu perfil no puede anular auditorías. Rol: %', v_rol;
    END IF;
    IF COALESCE(length(trim(p_motivo)),0) < 5 THEN
        RAISE EXCEPTION 'Indica el motivo de la anulación (mínimo 5 caracteres).';
    END IF;

    SELECT * INTO v_aud FROM auditorias_calidad WHERE id = p_auditoria_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'La auditoría no existe.'; END IF;
    IF v_aud.resultado <> 'pendiente' THEN
        RAISE EXCEPTION 'La auditoría ya fue resuelta (%): no se anula.', v_aud.resultado;
    END IF;

    UPDATE auditorias_calidad
       SET anulada = true, anulada_motivo = trim(p_motivo),
           anulada_por = v_user, anulada_at = NOW(), updated_at = NOW()
     WHERE id = p_auditoria_id;

    RETURN jsonb_build_object('auditoria_id', p_auditoria_id, 'anulada', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_anular_auditoria_calidad(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_anular_auditoria_calidad(UUID, TEXT) TO authenticated;


-- La cola de pendientes no muestra las anuladas, y avisa cuánto lleva marcado.
CREATE OR REPLACE VIEW public.v_auditorias_calidad_pendientes AS
SELECT ac.id,
       ac.activo_id,
       a.patente,
       a.codigo,
       ac.ot_id,
       ot.folio,
       ac.iniciada_por,
       ui.nombre_completo AS iniciada_nombre,
       ac.items_total,
       ac.created_at,
       -- columna nueva al final: CREATE OR REPLACE VIEW no admite reordenar
       (SELECT count(*) FROM auditoria_calidad_items i
         WHERE i.auditoria_id = ac.id AND i.resultado <> 'pendiente')::int AS items_marcados
  FROM auditorias_calidad ac
  JOIN activos a ON a.id = ac.activo_id
  LEFT JOIN ordenes_trabajo ot ON ot.id = ac.ot_id
  LEFT JOIN usuarios_perfil ui ON ui.id = ac.iniciada_por
 WHERE ac.resultado = 'pendiente'::resultado_verificacion_enum
   AND ac.anulada = false
 ORDER BY ac.created_at;

GRANT SELECT ON public.v_auditorias_calidad_pendientes TO authenticated;


-- ── 5. Las dos auditorías de junio quedan fuera ─────────────────────────────
UPDATE auditorias_calidad
   SET anulada = true,
       anulada_motivo = 'MIG260: auditoría de prueba de junio. La de GCHT-12 traía la '
                        'plantilla legacy de 14 ítems, no el V03. Se anula para partir '
                        'limpio con el checklist completo.',
       anulada_at = NOW(), updated_at = NOW()
 WHERE resultado = 'pendiente'
   AND anulada = false
   AND created_at < date_trunc('month', CURRENT_DATE);


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_user UUID; v_activo UUID; v_pat TEXT; v_r JSONB;
    v_items INT; v_bloques INT; v_sin_bloque INT; v_no_aplican INT;
    v_id UUID; v_item UUID; v_av JSONB; v_res TEXT;
BEGIN
    IF (SELECT count(*) FROM v_auditorias_calidad_pendientes) > 0 THEN
        RAISE NOTICE 'MIG260: quedan % auditorías pendientes (revisar si son de hoy)',
            (SELECT count(*) FROM v_auditorias_calidad_pendientes);
    ELSE
        RAISE NOTICE 'MIG260: cola de auditorías pendientes limpia';
    END IF;

    SELECT id INTO v_user FROM usuarios_perfil
     WHERE rol IN ('auditor_calidad','administrador') ORDER BY rol LIMIT 1;
    IF v_user IS NULL THEN RAISE NOTICE 'MIG260: sin auditor para el smoke'; RETURN; END IF;

    -- Un equipo SIN tipo_equipamiento: el caso que perdía las pruebas de ruta.
    SELECT id, COALESCE(patente, codigo) INTO v_activo, v_pat
      FROM activos WHERE tipo_equipamiento IS NULL AND fecha_baja IS NULL
      AND patente IS NOT NULL LIMIT 1;
    IF v_activo IS NULL THEN
        SELECT id, COALESCE(patente, codigo) INTO v_activo, v_pat FROM activos WHERE fecha_baja IS NULL LIMIT 1;
    END IF;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_user, 'role','authenticated')::text, true);

    v_r  := fn_iniciar_auditoria_calidad(v_activo, NULL);
    v_id := (v_r->>'auditoria_id')::uuid;
    v_items := (v_r->>'items_total')::int;

    SELECT count(DISTINCT bloque), count(*) FILTER (WHERE bloque IS NULL),
           count(*) FILTER (WHERE aplica_tipo = false)
      INTO v_bloques, v_sin_bloque, v_no_aplican
      FROM auditoria_calidad_items WHERE auditoria_id = v_id;

    IF v_items < 188 THEN
        RAISE EXCEPTION 'FALLO — se cargaron % ítems, se esperaban los 188 del V03', v_items;
    END IF;
    IF v_sin_bloque > 0 THEN
        RAISE EXCEPTION 'FALLO — % ítems sin bloque: la pantalla no los puede agrupar', v_sin_bloque;
    END IF;
    -- Las pruebas de ruta tienen que estar aunque el equipo no tenga tipo.
    IF NOT EXISTS (SELECT 1 FROM auditoria_calidad_items
                    WHERE auditoria_id = v_id AND descripcion ILIKE '%prueba de ruta%') THEN
        RAISE EXCEPTION 'FALLO — la auditoría de % quedó sin pruebas de ruta', v_pat;
    END IF;

    -- Guardado parcial
    SELECT id INTO v_item FROM auditoria_calidad_items WHERE auditoria_id = v_id LIMIT 1;
    v_av := rpc_guardar_avance_auditoria(v_id,
        jsonb_build_array(jsonb_build_object('id', v_item, 'resultado', 'ok')));
    IF (v_av->>'guardados')::int <> 1 THEN
        RAISE EXCEPTION 'FALLO — el guardado parcial no grabó el ítem: %', v_av;
    END IF;
    SELECT resultado INTO v_res FROM auditoria_calidad_items WHERE id = v_item;
    IF v_res <> 'ok' THEN RAISE EXCEPTION 'FALLO — el ítem no quedó en ok (%)', v_res; END IF;

    -- Anular
    PERFORM rpc_anular_auditoria_calidad(v_id, 'Smoke MIG260');
    IF EXISTS (SELECT 1 FROM v_auditorias_calidad_pendientes WHERE id = v_id) THEN
        RAISE EXCEPTION 'FALLO — la auditoría anulada sigue en la cola de pendientes';
    END IF;

    RAISE NOTICE 'MIG260 OK — % (sin tipo): % ítems en % bloques, % no aplican al tipo. '
                 'Guardado parcial y anulación verificados.',
        v_pat, v_items, v_bloques, v_no_aplican;

    RAISE EXCEPTION 'rollback-smoke';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'rollback-smoke' THEN RAISE NOTICE 'Smoke revertido (ok)';
    ELSE RAISE; END IF;
END $$;

NOTIFY pgrst, 'reload schema';
