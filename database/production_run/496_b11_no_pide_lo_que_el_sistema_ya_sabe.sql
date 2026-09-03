-- ============================================================================
-- MIG496 · El cierre de recepción (B11) deja de pedir lo que el sistema ya sabe
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 03-09-2026, mirando el checklist de una OT en /m/taller: «el punto B11,
-- Cierre y responsabilidades, sea rediseñado». En concreto:
--
--   · B11.01 daños no reportados, B11.02 observaciones del operador y B11.03
--     trabajos solicitados: «para ello tenemos la sección notas/anexos».
--     Son texto libre que duplica una sección que ya existe y funciona.
--   · B11.04 próximo horómetro de pauta: «se debería calcular solo dado que es
--     siempre cada 300 horas, yo colocando las horas al principio».
--   · B11.06 tiempo estimado + fecha comprometida: «es un dato ya entregado y
--     que debería salir al principio como dato». Lo fija el planificador
--     (MIG493) — preguntárselo al mecánico es pedirle que adivine lo que otro
--     ya decidió.
--   · B11.07 firmas + RUT: «debería dar el espacio para firmar y colocar el
--     RUT». Eso es pantalla (va en el mismo PR); acá no cambia nada.
--
-- QUÉ SE HACE
--   1. La plantilla aprende a jubilar ítems: `vigente`. Borrarlos no se puede
--      (las instancias históricas los referencian) y `excluido` es por
--      instancia. B11.01/02/03/06 quedan no vigentes: los checklists nuevos ya
--      no los traen.
--   2. En los checklists abiertos, esos ítems se excluyen — sólo donde nadie
--      escribió nada. Lo respondido se respeta.
--   3. `rpc_taller_registrar_medidores` llena B11.04 solo: horómetro + 300 h,
--      cada vez que una persona guarda los medidores. Queda editable por si
--      una pauta específica dice otra cosa.
--   4. `v_taller_mecanico_ots` publica las horas comprometidas (MIG493,
--      horas_planificadas de las jornadas) y la fecha de entrega (el último
--      día planificado), para que la pantalla las muestre como dato.
--
-- POR QUÉ B08.05 NO SE TOCA
-- «Próxima pauta del sistema» es una lectura del recordatorio del propio
-- vehículo, no un cálculo nuestro. Se sigue anotando a mano.
-- ============================================================================

BEGIN;

-- ── 1 · La plantilla aprende a jubilar ítems ────────────────────────────────
ALTER TABLE checklist_template_v2_item
  ADD COLUMN IF NOT EXISTS vigente BOOLEAN NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN checklist_template_v2_item.vigente IS
'FALSE = ítem jubilado: los checklists nuevos no lo traen. No se borra porque '
'las instancias históricas lo referencian (MIG496).';

UPDATE checklist_template_v2_item
   SET vigente = FALSE
 WHERE codigo IN ('B11.01','B11.02','B11.03','B11.06');

-- ── 2 · Los checklists nuevos no traen ítems jubilados ──────────────────────
CREATE OR REPLACE FUNCTION fn_inicializar_checklist_v2(
    p_template_id   UUID,
    p_activo_id     UUID,
    p_contrato_id   UUID DEFAULT NULL,
    p_operador_id   UUID DEFAULT NULL,
    p_horometro     NUMERIC DEFAULT NULL,
    p_kilometraje   NUMERIC DEFAULT NULL,
    p_informe_id    UUID DEFAULT NULL,
    p_entrega_ref   UUID DEFAULT NULL  -- referencia al instance entrega si es recepcion
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_instance_id UUID;
    v_momento     momento_checklist_enum;
    v_tipo_eq     tipo_equipamiento_enum;
BEGIN
    SELECT momento_uso INTO v_momento
      FROM checklist_template_v2 WHERE id = p_template_id;

    SELECT tipo_equipamiento INTO v_tipo_eq
      FROM activos WHERE id = p_activo_id;

    IF v_momento IS NULL THEN
        RAISE EXCEPTION 'Template % no encontrado', p_template_id;
    END IF;
    IF v_tipo_eq IS NULL THEN
        RAISE EXCEPTION 'Activo % no encontrado', p_activo_id;
    END IF;

    INSERT INTO checklist_v2_instance (
        template_id, momento_uso, activo_id, contrato_id,
        informe_recepcion_id, instance_entrega_id,
        horometro, kilometraje, operador_id, estado
    ) VALUES (
        p_template_id, v_momento, p_activo_id, p_contrato_id,
        p_informe_id, p_entrega_ref,
        p_horometro, p_kilometraje, p_operador_id, 'en_progreso'
    )
    RETURNING id INTO v_instance_id;

    -- [MIG496] Sólo los ítems vigentes: los jubilados no viajan a instancias nuevas.
    INSERT INTO checklist_v2_instance_item (instance_id, template_item_id, resultado)
    SELECT v_instance_id, ti.id, 'pendiente'
      FROM checklist_template_v2_item ti
     WHERE ti.template_id = p_template_id
       AND v_tipo_eq = ANY(ti.tipos_equipamiento)
       AND ti.vigente;

    RETURN v_instance_id;
END;
$$;

-- ── 3 · Los checklists abiertos sueltan los jubilados (sólo si están en blanco)
UPDATE checklist_v2_instance_item ii
   SET excluido = TRUE
  FROM checklist_v2_instance i, checklist_template_v2_item ti
 WHERE i.id = ii.instance_id
   AND ti.id = ii.template_item_id
   AND i.estado = 'en_progreso'
   AND ti.codigo IN ('B11.01','B11.02','B11.03','B11.06')
   AND COALESCE(ii.excluido, FALSE) = FALSE
   AND (ii.resultado IS NULL OR ii.resultado = 'pendiente')
   AND NULLIF(TRIM(COALESCE(ii.observacion,'')), '') IS NULL
   AND ii.foto_url IS NULL
   AND ii.mediciones IS NULL
   AND ii.valor_numerico IS NULL;

-- ── 4 · B11.04 se llena solo al guardar los medidores ───────────────────────
-- Mismo cuerpo que MIG471 + el bloque del próximo horómetro de pauta. La firma
-- no cambia, así que CREATE OR REPLACE basta (una sola firma, la regla MIG471).
CREATE OR REPLACE FUNCTION rpc_taller_registrar_medidores(
    p_ot_id        UUID,
    p_horometro    NUMERIC DEFAULT NULL,
    p_kilometraje  NUMERIC DEFAULT NULL,
    p_confirmado   BOOLEAN DEFAULT FALSE,
    p_cuenta_litros NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_inst RECORD; v_activo UUID; v_exige_km BOOLEAN; v_exige_cl BOOLEAN;
    v_hm_ant NUMERIC; v_km_ant NUMERIC; v_cl_ant NUMERIC;
    v_retro TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('operador_taller','tecnico_mantenimiento','jefe_mantenimiento',
                     'supervisor','planificador','administrador','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Sin permiso para anotar medidores (rol: %)', v_rol; END IF;

    SELECT i.id, i.activo_id, i.horometro, i.kilometraje, i.cuenta_litros
      INTO v_inst
      FROM checklist_v2_instance i
     WHERE i.ot_id = p_ot_id
     ORDER BY i.created_at DESC
     LIMIT 1;
    IF v_inst.id IS NULL THEN
        RAISE EXCEPTION 'Esta OT no tiene checklist: no hay dónde anotar los medidores'; END IF;

    v_activo   := v_inst.activo_id;
    v_exige_km := fn_activo_exige_kilometraje(v_activo);
    v_exige_cl := fn_activo_exige_cuenta_litros(v_activo);

    IF p_horometro IS NOT NULL AND p_horometro < 0 THEN
        RAISE EXCEPTION 'El horómetro no puede ser negativo'; END IF;
    IF p_kilometraje IS NOT NULL AND p_kilometraje < 0 THEN
        RAISE EXCEPTION 'El kilometraje no puede ser negativo'; END IF;
    IF p_cuenta_litros IS NOT NULL AND p_cuenta_litros < 0 THEN
        RAISE EXCEPTION 'El cuenta litros no puede ser negativo'; END IF;

    -- El cuenta litros sólo se guarda donde existe: si el equipo no lo tiene, se
    -- ignora en vez de dejar un número suelto que nadie sabe de dónde salió.
    IF p_cuenta_litros IS NOT NULL AND NOT v_exige_cl THEN
        p_cuenta_litros := NULL;
    END IF;

    SELECT max(i.horometro), max(i.kilometraje), max(i.cuenta_litros)
      INTO v_hm_ant, v_km_ant, v_cl_ant
      FROM checklist_v2_instance i
     WHERE i.activo_id = v_activo AND i.id <> v_inst.id;
    v_hm_ant := GREATEST(COALESCE(v_hm_ant, 0),
                         COALESCE((SELECT a.horas_uso_actual FROM activos a WHERE a.id = v_activo), 0));
    v_km_ant := GREATEST(COALESCE(v_km_ant, 0),
                         COALESCE((SELECT a.kilometraje_actual FROM activos a WHERE a.id = v_activo), 0));
    v_cl_ant := GREATEST(COALESCE(v_cl_ant, 0),
                         COALESCE((SELECT a.cuenta_litros_actual FROM activos a WHERE a.id = v_activo), 0));

    IF p_horometro IS NOT NULL AND v_hm_ant > 0 AND p_horometro < v_hm_ant THEN
        v_retro := array_append(v_retro,
            format('horómetro (antes %s h, ahora %s h)', v_hm_ant, p_horometro)::TEXT);
    END IF;
    IF p_kilometraje IS NOT NULL AND v_km_ant > 0 AND p_kilometraje < v_km_ant THEN
        v_retro := array_append(v_retro,
            format('kilometraje (antes %s km, ahora %s km)', v_km_ant, p_kilometraje)::TEXT);
    END IF;
    IF p_cuenta_litros IS NOT NULL AND v_cl_ant > 0 AND p_cuenta_litros < v_cl_ant THEN
        v_retro := array_append(v_retro,
            format('cuenta litros (antes %s L, ahora %s L)', v_cl_ant, p_cuenta_litros)::TEXT);
    END IF;

    IF array_length(v_retro, 1) > 0 AND NOT p_confirmado THEN
        RETURN jsonb_build_object(
            'success', FALSE, 'requiere_confirmacion', TRUE,
            'motivo', 'El número es menor que la última lectura: ' || array_to_string(v_retro, ' y ') ||
                      '. Si el medidor se cambió, confirma; si no, corrige el número.');
    END IF;

    UPDATE checklist_v2_instance
       SET horometro     = COALESCE(p_horometro, horometro),
           kilometraje   = COALESCE(p_kilometraje, kilometraje),
           cuenta_litros = COALESCE(p_cuenta_litros, cuenta_litros),
           medidores_por = v_user,
           medidores_at  = NOW(),
           observaciones = CASE
               WHEN array_length(v_retro, 1) > 0
               THEN COALESCE(observaciones || ' · ', '')
                    || 'Medidor confirmado a mano pese a retroceder: ' || array_to_string(v_retro, ' y ')
               ELSE observaciones END,
           updated_at    = NOW()
     WHERE id = v_inst.id;

    -- [MIG496] El próximo horómetro de pauta no se pregunta: la pauta es cada
    -- 300 horas, así que es la lectura que la persona acaba de anotar + 300.
    -- Se recalcula cada vez que se guardan medidores (es un derivado) y el ítem
    -- queda respondido; en pantalla sigue editable por si una pauta específica
    -- dice otra cosa.
    IF p_horometro IS NOT NULL THEN
        UPDATE checklist_v2_instance_item ii
           SET valor_numerico = p_horometro + 300,
               resultado      = 'ok',
               respondido_at  = NOW()
          FROM checklist_template_v2_item ti
         WHERE ii.instance_id = v_inst.id
           AND ti.id = ii.template_item_id
           AND ti.codigo = 'B11.04'
           AND COALESCE(ii.excluido, FALSE) = FALSE;
    END IF;

    -- [MIG399] El maestro, con las lecturas. Sólo hacia adelante.
    IF p_horometro IS NOT NULL THEN
        UPDATE activos SET horas_uso_actual = p_horometro, updated_at = NOW()
         WHERE id = v_activo AND COALESCE(horas_uso_actual, 0) < p_horometro;
    END IF;
    IF p_kilometraje IS NOT NULL THEN
        UPDATE activos SET kilometraje_actual = p_kilometraje, updated_at = NOW()
         WHERE id = v_activo AND COALESCE(kilometraje_actual, 0) < p_kilometraje;
    END IF;
    IF p_cuenta_litros IS NOT NULL THEN
        UPDATE activos SET cuenta_litros_actual = p_cuenta_litros, updated_at = NOW()
         WHERE id = v_activo AND COALESCE(cuenta_litros_actual, 0) < p_cuenta_litros;
    END IF;

    RETURN jsonb_build_object('success', TRUE,
        'horometro', COALESCE(p_horometro, v_inst.horometro),
        'kilometraje', COALESCE(p_kilometraje, v_inst.kilometraje),
        'cuenta_litros', COALESCE(p_cuenta_litros, v_inst.cuenta_litros),
        'exige_kilometraje', v_exige_km,
        'exige_cuenta_litros', v_exige_cl,
        'proximo_horometro_pauta', CASE WHEN p_horometro IS NOT NULL THEN p_horometro + 300 END);
END;
$$;

REVOKE ALL ON FUNCTION rpc_taller_registrar_medidores(UUID, NUMERIC, NUMERIC, BOOLEAN, NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_registrar_medidores(UUID, NUMERIC, NUMERIC, BOOLEAN, NUMERIC) TO authenticated;

-- ── 5 · La vista del mecánico publica el compromiso del plan ────────────────
-- Columnas nuevas AL FINAL (CREATE OR REPLACE VIEW no deja reordenar).
CREATE OR REPLACE VIEW v_taller_mecanico_ots AS
 SELECT ot.id AS ot_id,
    ot.folio AS ot_folio,
    ot.tipo AS ot_tipo,
    ot.estado AS ot_estado,
    ot.prioridad AS ot_prioridad,
    ot.preparacion_ok_at,
    ot.fecha_programada,
    ot.activo_id,
    a.codigo AS activo_codigo,
    a.nombre AS activo_nombre,
    a.patente AS activo_patente,
    ( SELECT string_agg(n.nombre, ', '::text ORDER BY n.nombre)
           FROM ( SELECT DISTINCT TRIM(BOTH FROM x.nombre) AS nombre
                    FROM taller_plan_semanal_ots t,
                         LATERAL unnest(string_to_array(t.cuadrilla, ','::text)) AS x(nombre)
                   WHERE t.ot_id = ot.id
                     AND NULLIF(TRIM(BOTH FROM x.nombre), ''::text) IS NOT NULL) n) AS cuadrilla,
    ot.responsable_id,
    COALESCE(tt.nombre, up.nombre_completo) AS responsable,
    fn_taller_ot_asignada_al_usuario(ot.id) AS asignada_a_mi,
    ( SELECT count(*) AS count
           FROM v_taller_ot_checklist_v3 v
          WHERE v.ot_id = ot.id AND v.excluido = false) AS checklist_total,
    ( SELECT count(*) AS count
           FROM v_taller_ot_checklist_v3 v
          WHERE v.ot_id = ot.id AND v.excluido = false AND v.resultado IS NOT NULL AND v.resultado <> 'pendiente'::resultado_item_enum) AS checklist_completados,
    ( SELECT COALESCE(sum(v.tiempo_min), 0::numeric) AS "coalesce"
           FROM v_taller_ot_checklist_v3 v
          WHERE v.ot_id = ot.id AND v.excluido = false) AS tiempo_estimado_total_min,
    -- [MIG496] Lo que el planificador comprometió (MIG493): total HH de la
    -- visita (vive en la primera jornada) y el último día planificado.
    ( SELECT sum(po.horas_planificadas)
           FROM taller_plan_semanal_ots po
          WHERE po.ot_id = ot.id
            AND COALESCE(po.estado_plan, 'planificada') <> 'cancelada') AS horas_planificadas,
    ( SELECT max(d.fecha)
           FROM taller_plan_semanal_ots po
           JOIN taller_plan_semanal_dias d ON d.id = po.plan_dia_id
          WHERE po.ot_id = ot.id
            AND COALESCE(po.estado_plan, 'planificada') <> 'cancelada') AS fecha_entrega_plan
   FROM ordenes_trabajo ot
     JOIN activos a ON a.id = ot.activo_id
     LEFT JOIN taller_tecnicos tt ON tt.id = ot.tecnico_id
     LEFT JOIN usuarios_perfil up ON up.id = ot.responsable_id
  WHERE ot.preparacion_ok_at IS NOT NULL AND (ot.estado = ANY (ARRAY['asignada'::estado_ot_enum, 'en_ejecucion'::estado_ot_enum, 'pausada'::estado_ot_enum]))
  ORDER BY (
        CASE ot.estado
            WHEN 'en_ejecucion'::estado_ot_enum THEN 1
            WHEN 'pausada'::estado_ot_enum THEN 2
            ELSE 3
        END), (
        CASE ot.prioridad
            WHEN 'emergencia'::prioridad_enum THEN 1
            WHEN 'urgente'::prioridad_enum THEN 2
            WHEN 'alta'::prioridad_enum THEN 3
            WHEN 'normal'::prioridad_enum THEN 4
            ELSE 5
        END), ot.fecha_programada;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_n INT; v_txt TEXT; r RECORD;
BEGIN
    SELECT string_agg(codigo, ', ' ORDER BY codigo) INTO v_txt
      FROM checklist_template_v2_item WHERE NOT vigente;
    IF v_txt IS DISTINCT FROM 'B11.01, B11.02, B11.03, B11.06' THEN
        RAISE EXCEPTION 'FALLO: quedaron jubilados [%], se esperaban B11.01/02/03/06', v_txt;
    END IF;
    RAISE NOTICE 'ítems jubilados de la plantilla: %', v_txt;

    SELECT count(*) INTO v_n
      FROM checklist_v2_instance_item ii
      JOIN checklist_v2_instance i ON i.id = ii.instance_id
      JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
     WHERE i.estado = 'en_progreso' AND ti.codigo IN ('B11.01','B11.02','B11.03','B11.06')
       AND ii.excluido;
    RAISE NOTICE 'instancias abiertas: % ítems jubilados quedaron excluidos', v_n;

    SELECT count(*) INTO v_n
      FROM checklist_v2_instance_item ii
      JOIN checklist_v2_instance i ON i.id = ii.instance_id
      JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
     WHERE i.estado = 'en_progreso' AND ti.codigo IN ('B11.01','B11.02','B11.03','B11.06')
       AND NOT COALESCE(ii.excluido, FALSE);
    RAISE NOTICE 'ítems jubilados que SIGUEN visibles por tener algo escrito: %', v_n;

    -- Una sola firma del RPC de medidores (la regla de MIG471).
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_taller_registrar_medidores';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: el RPC de medidores quedó con % firmas', v_n; END IF;

    -- La vista publica las columnas nuevas.
    PERFORM horas_planificadas, fecha_entrega_plan FROM v_taller_mecanico_ots LIMIT 1;
    RAISE NOTICE 'la vista publica horas_planificadas y fecha_entrega_plan';

    FOR r IN SELECT ot_folio, horas_planificadas, fecha_entrega_plan
               FROM v_taller_mecanico_ots
              WHERE horas_planificadas IS NOT NULL OR fecha_entrega_plan IS NOT NULL
              ORDER BY ot_folio LIMIT 5 LOOP
        RAISE NOTICE '   % · % HH · entrega %', r.ot_folio,
            COALESCE(r.horas_planificadas::TEXT, '—'), COALESCE(r.fecha_entrega_plan::TEXT, '—');
    END LOOP;
END
$mig$;

COMMIT;
