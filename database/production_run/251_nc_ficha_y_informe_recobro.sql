-- ============================================================================
-- SICOM-ICEO | 251 — Ficha de la NC y paso al informe de recobros
-- ----------------------------------------------------------------------------
-- Pedido de Manuel (2026-07-27), sobre la MIG250: «ahora las ve, pero la idea
-- es que le pueda asignar recursos y planificar. En cada NC se abre un modal,
-- el jefe la ve, le asigna recursos, clasifica si es recobrable o no y, después
-- de ese análisis, gestiona el informe de recobros».
--
-- Hoy los recursos SOLO se asignan por equipo completo (MIG209). El motor por
-- NC ya existe desde la MIG138 (fn_asignar_recursos_nc / fn_planificar_nc) y
-- estaba sin usar en la UI. El informe de recobro también existe completo
-- (informes_recepcion + hallazgos + costos + emisión con firma y PDF), pero
-- solo se alimentaba desde una recepción de arriendo: las 34 NC que nacen en la
-- ejecución de OT del taller no tenían cómo llegar a un recobro.
--
-- Esta MIG cierra ese puente:
--   1. no_conformidades.recobro_informe_id / recobro_hallazgo_id: la NC sabe si
--      ya está en un informe de recobro (y la bandeja lo muestra).
--   2. rpc_nc_informe_recobro(activo, ncs, tarifa): toma las NC clasificadas
--      como recobrables (cliente/compartido), las vuelca como hallazgos de un
--      informe IR — reusando el informe abierto del equipo o creando uno nuevo
--      en 'borrador' — y PRE-VALORIZA el recobro con lo que el jefe ya cargó:
--      materiales (costo unitario de bodega) + mano de obra (horas x tarifa HH).
--      El encargado de cobros lo termina y emite en /dashboard/flota/recepcion.
--      Idempotente: una NC no entra dos veces al mismo informe.
--   3. La vista de la bandeja expone el folio del informe y el costo estimado
--      de materiales, para decidir sin abrir nada.
-- ADITIVA, IDEMPOTENTE. No borra datos.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='no_conformidades' AND column_name='recobro_override') THEN
        RAISE EXCEPTION 'STOP — falta MIG250 (recobro en no_conformidades).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='informe_recepcion_costos') THEN
        RAISE EXCEPTION 'STOP — falta el informe de recepción/recobro (MIG191 y anteriores).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_asignar_recursos_nc') THEN
        RAISE EXCEPTION 'STOP — falta fn_asignar_recursos_nc (MIG138).';
    END IF;
END $$;


-- ── 1. La NC sabe en qué informe de recobro quedó ────────────────────────────
ALTER TABLE no_conformidades
    ADD COLUMN IF NOT EXISTS recobro_informe_id  UUID REFERENCES informes_recepcion(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS recobro_hallazgo_id UUID REFERENCES informe_recepcion_hallazgos(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_nc_recobro_informe ON no_conformidades(recobro_informe_id)
    WHERE recobro_informe_id IS NOT NULL;

COMMENT ON COLUMN no_conformidades.recobro_informe_id IS
    'Informe de recobro (informes_recepcion) donde se cobró esta NC. MIG251.';


-- ── 2. Volcar las NC recobrables del equipo a un informe de recobro ──────────
CREATE OR REPLACE FUNCTION public.rpc_nc_informe_recobro(
    p_activo_id     UUID,
    p_nc_ids        UUID[] DEFAULT NULL,   -- NULL = todas las recobrables del equipo
    p_tarifa_hh_id  UUID   DEFAULT NULL    -- NULL = la tarifa activa más barata
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user      UUID := auth.uid();
    v_rol       TEXT := public.fn_user_rol();
    v_activo    RECORD;
    v_informe   RECORD;
    v_folio     VARCHAR;
    v_periodo   VARCHAR(6);
    v_sec       INTEGER;
    v_tarifa    RECORD;
    v_nuevo     BOOLEAN := false;
    v_hallazgo  UUID;
    v_creados   INT := 0;
    v_ya        INT := 0;
    v_costos    INT := 0;
    nc          RECORD;
    mat         RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol IS NULL OR v_rol NOT IN (
        'administrador','gerencia','subgerente_operaciones','jefe_operaciones',
        'jefe_mantenimiento','planificador','supervisor') THEN
        RAISE EXCEPTION 'No autorizado para armar el informe de recobro (rol: %)', COALESCE(v_rol,'?')
            USING ERRCODE='42501';
    END IF;

    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Equipo % no existe', p_activo_id; END IF;

    -- Tarifa de mano de obra para pre-valorizar (la elige el jefe o la más barata)
    SELECT * INTO v_tarifa FROM tarifas_hh
     WHERE activo AND (p_tarifa_hh_id IS NULL OR id = p_tarifa_hh_id)
     ORDER BY (id = p_tarifa_hh_id) DESC, tarifa_clp ASC LIMIT 1;

    -- ¿Hay un informe abierto del equipo? Se reutiliza; si no, se crea en borrador.
    SELECT * INTO v_informe FROM informes_recepcion
     WHERE activo_id = p_activo_id AND estado IN ('en_inspeccion','borrador')
     ORDER BY created_at DESC LIMIT 1;

    IF NOT FOUND THEN
        PERFORM pg_advisory_xact_lock(hashtext('ir_folio_lock'));
        v_periodo := TO_CHAR(NOW(), 'YYYYMM');
        SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)), 0) + 1
          INTO v_sec FROM informes_recepcion WHERE folio LIKE 'IR-' || v_periodo || '-%';
        v_folio := 'IR-' || v_periodo || '-' || LPAD(v_sec::TEXT, 5, '0');

        INSERT INTO informes_recepcion (
            activo_id, contrato_id, cliente_nombre, fecha_recepcion,
            inspector_id, estado, folio, observaciones_finales
        ) VALUES (
            p_activo_id, v_activo.contrato_id, v_activo.cliente_actual, CURRENT_DATE,
            v_user, 'borrador', v_folio,
            'Recobro armado desde las No Conformidades del taller.'
        )
        RETURNING * INTO v_informe;
        v_nuevo := true;
    END IF;

    -- Las NC a cobrar: recobrables (cliente/compartido) y no descartadas.
    FOR nc IN
        SELECT n.id, n.descripcion, n.severidad, n.foto_url, n.checklist_item_ref,
               n.horas_estimadas, n.grupo_trabajo, n.recobro_hallazgo_id, n.recobro_nota,
               v.recobro, v.observacion_item, n.plan_ot_id
          FROM no_conformidades n
          JOIN v_nc_recepcion v ON v.id = n.id
         WHERE n.activo_id = p_activo_id
           AND (p_nc_ids IS NULL OR n.id = ANY(p_nc_ids))
           AND v.recobro IN ('cliente','compartido')
           AND n.estado_planificacion <> 'descartada'
         ORDER BY n.created_at
    LOOP
        -- Idempotente: si ya está en ESTE informe, no se duplica.
        IF nc.recobro_hallazgo_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM informe_recepcion_hallazgos
             WHERE id = nc.recobro_hallazgo_id AND informe_id = v_informe.id) THEN
            v_ya := v_ya + 1;
            CONTINUE;
        END IF;

        INSERT INTO informe_recepcion_hallazgos (
            informe_id, seccion, descripcion, gravedad, atribuible_cliente,
            fotos, observacion, checklist_v2_item_id
        ) VALUES (
            v_informe.id,
            'No Conformidad del taller',
            nc.descripcion,
            (CASE nc.severidad WHEN 'critica' THEN 'critica'
                               WHEN 'alta'    THEN 'mayor'
                               ELSE 'menor' END)::gravedad_hallazgo_enum,
            (nc.recobro = 'cliente'),   -- 'compartido' entra pero se reparte al valorizar
            CASE WHEN nc.foto_url IS NOT NULL THEN jsonb_build_array(nc.foto_url) ELSE '[]'::JSONB END,
            NULLIF(concat_ws(' · ', nc.observacion_item, nc.recobro_nota), ''),
            nc.checklist_item_ref
        )
        RETURNING id INTO v_hallazgo;
        v_creados := v_creados + 1;

        UPDATE no_conformidades
           SET recobro_informe_id = v_informe.id, recobro_hallazgo_id = v_hallazgo, updated_at = NOW()
         WHERE id = nc.id;

        -- Pre-valorización: materiales que el jefe ya cargó en la NC
        FOR mat IN
            SELECT m.cantidad, m.descripcion, m.producto_id,
                   p.nombre AS producto_nombre, p.unidad_medida,
                   COALESCE(p.costo_unitario_actual, 0) AS costo
              FROM nc_materiales m
              LEFT JOIN productos p ON p.id = m.producto_id
             WHERE m.no_conformidad_id = nc.id
        LOOP
            INSERT INTO informe_recepcion_costos (
                informe_id, tipo, producto_id, descripcion, cantidad, unidad,
                precio_unitario, cobrable_cliente, hallazgo_id
            ) VALUES (
                v_informe.id, 'repuesto'::tipo_costo_recepcion_enum, mat.producto_id,
                COALESCE(mat.producto_nombre, mat.descripcion, 'Material'),
                COALESCE(mat.cantidad, 1), mat.unidad_medida,
                mat.costo, true, v_hallazgo
            );
            v_costos := v_costos + 1;
        END LOOP;

        -- Pre-valorización: mano de obra estimada de la NC
        IF COALESCE(nc.horas_estimadas, 0) > 0 AND v_tarifa.id IS NOT NULL THEN
            INSERT INTO informe_recepcion_costos (
                informe_id, tipo, tarifa_hh_id, descripcion, cantidad, unidad,
                precio_unitario, cobrable_cliente, hallazgo_id
            ) VALUES (
                v_informe.id, 'mano_obra'::tipo_costo_recepcion_enum, v_tarifa.id,
                'Mano de obra — ' || v_tarifa.nombre ||
                    COALESCE(' (' || nc.grupo_trabajo || ')', ''),
                nc.horas_estimadas, 'HH', v_tarifa.tarifa_clp, true, v_hallazgo
            );
            v_costos := v_costos + 1;
        END IF;
    END LOOP;

    SELECT * INTO v_informe FROM informes_recepcion WHERE id = v_informe.id;

    RETURN jsonb_build_object(
        'ok', true,
        'informe_id', v_informe.id,
        'folio', v_informe.folio,
        'informe_nuevo', v_nuevo,
        'hallazgos_creados', v_creados,
        'ya_estaban', v_ya,
        'costos_creados', v_costos,
        'total_cobrable', v_informe.total_cobrable_cliente,
        'total', v_informe.total
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_nc_informe_recobro(UUID, UUID[], UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_nc_informe_recobro(UUID, UUID[], UUID) TO authenticated;


-- ── 3. La bandeja muestra el informe y el costo ya cargado ───────────────────
-- OJO: esta vista se ha recreado varias veces perdiendo columnas (la MIG220
-- borró las de la MIG199). Si la vuelves a tocar, PARTE DE ESTA DEFINICIÓN.
DROP VIEW IF EXISTS v_nc_recepcion;
CREATE VIEW v_nc_recepcion AS
SELECT nc.id, nc.activo_id, a.patente, a.codigo, a.nombre AS equipo,
       nc.descripcion, nc.severidad, nc.origen, nc.estado_planificacion,
       nc.grupo_trabajo, nc.horas_estimadas, nc.tiempo_estimado_dias,
       nc.informe_recepcion_id, nc.plan_ot_id, nc.resuelto, nc.created_at,
       (SELECT count(*) FROM nc_materiales m WHERE m.no_conformidad_id = nc.id) AS n_materiales,
       nc.ot_id,

       -- [MIG199] evidencia y vínculo con el hallazgo del checklist
       nc.foto_url,
       nc.checklist_item_ref,
       (SELECT count(*) FROM ot_recursos_solicitados r
         WHERE r.instance_item_id = nc.checklist_item_ref) AS n_recursos_operador,

       -- [MIG250] contexto para leer la NC sin abrir nada más
       ii.observacion              AS observacion_item,
       ot.folio                    AS ot_folio,
       up.nombre_completo          AS registrada_por_nombre,

       -- [MIG250] ¿se le recobra al cliente?
       COALESCE(
           nc.recobro_override,
           ii.cobrable_override,
           ti.default_cobrable,
           CASE WHEN h.atribuible_cliente IS TRUE  THEN 'cliente'::default_cobrable_enum
                WHEN h.atribuible_cliente IS FALSE THEN 'empresa'::default_cobrable_enum END
       )                           AS recobro,
       CASE WHEN nc.recobro_override  IS NOT NULL THEN 'jefe'
            WHEN ii.cobrable_override IS NOT NULL THEN 'terreno'
            WHEN ti.default_cobrable  IS NOT NULL THEN 'pauta'
            WHEN h.atribuible_cliente IS NOT NULL THEN 'informe'
            ELSE 'sin_definir' END  AS recobro_fuente,
       nc.recobro_nota,

       -- [MIG250] notas/anexos que dejó el operador en la(s) OT de esta NC
       (SELECT count(*) FROM evidencias_ot e
         WHERE e.tipo = 'nota'
           AND (e.ot_id = nc.ot_id OR e.ot_id = nc.plan_ot_id)) AS n_notas_operador,

       -- [MIG251] estado del recobro y plata ya comprometida en materiales
       nc.recobro_informe_id,
       ir.folio                    AS recobro_informe_folio,
       ir.estado::text             AS recobro_informe_estado,
       COALESCE((SELECT sum(m.cantidad * COALESCE(p.costo_unitario_actual, 0))
                   FROM nc_materiales m
                   LEFT JOIN productos p ON p.id = m.producto_id
                  WHERE m.no_conformidad_id = nc.id), 0) AS costo_materiales_estimado

FROM no_conformidades nc
JOIN activos a ON a.id = nc.activo_id
LEFT JOIN checklist_v2_instance_item ii ON ii.id = nc.checklist_item_ref
LEFT JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
LEFT JOIN informe_recepcion_hallazgos h  ON h.id = nc.hallazgo_id
LEFT JOIN ordenes_trabajo ot             ON ot.id = COALESCE(nc.plan_ot_id, nc.ot_id)
LEFT JOIN usuarios_perfil up             ON up.id = nc.registrada_por
LEFT JOIN informes_recepcion ir          ON ir.id = nc.recobro_informe_id
WHERE nc.origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot','ejecucion_ot','manual');

GRANT SELECT ON v_nc_recepcion TO authenticated;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_faltan TEXT;
    v_activo UUID; v_user UUID; v_res JSONB; v_ncs INT;
BEGIN
    SELECT string_agg(c, ', ') INTO v_faltan
      FROM unnest(ARRAY['foto_url','checklist_item_ref','n_recursos_operador','recobro',
                        'recobro_fuente','n_notas_operador','recobro_informe_id',
                        'recobro_informe_folio','costo_materiales_estimado']) c
     WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_name='v_nc_recepcion' AND column_name=c);
    IF v_faltan IS NOT NULL THEN
        RAISE EXCEPTION 'FALLO — v_nc_recepcion sin columnas: %', v_faltan;
    END IF;

    -- Smoke: el jefe arma el informe de recobro de un equipo con NC recobrables
    SELECT activo_id, count(*) INTO v_activo, v_ncs
      FROM v_nc_recepcion WHERE recobro IN ('cliente','compartido')
     GROUP BY activo_id ORDER BY count(*) DESC LIMIT 1;
    SELECT id INTO v_user FROM usuarios_perfil WHERE rol='jefe_mantenimiento' LIMIT 1;
    IF v_activo IS NULL OR v_user IS NULL THEN
        RAISE NOTICE 'MIG251: sin datos para smoke (ok)'; RETURN;
    END IF;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    v_res := public.rpc_nc_informe_recobro(v_activo, NULL, NULL);
    IF NOT (v_res->>'ok')::boolean THEN RAISE EXCEPTION 'FALLO smoke rpc_nc_informe_recobro'; END IF;
    IF (v_res->>'hallazgos_creados')::int <> v_ncs THEN
        RAISE EXCEPTION 'FALLO — se esperaban % hallazgos y se crearon %', v_ncs, v_res->>'hallazgos_creados';
    END IF;
    RAISE NOTICE 'MIG251 OK: informe % con % hallazgos, % costos, total cobrable %',
        v_res->>'folio', v_res->>'hallazgos_creados', v_res->>'costos_creados', v_res->>'total_cobrable';

    -- Segunda pasada: NO debe duplicar
    v_res := public.rpc_nc_informe_recobro(v_activo, NULL, NULL);
    IF (v_res->>'hallazgos_creados')::int <> 0 THEN
        RAISE EXCEPTION 'FALLO idempotencia — la segunda pasada creó % hallazgos', v_res->>'hallazgos_creados';
    END IF;
    RAISE NOTICE 'MIG251 OK: idempotente (segunda pasada no duplicó nada)';

    RAISE EXCEPTION 'rollback-smoke';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'rollback-smoke' THEN RAISE NOTICE 'Smoke revertido (ok)';
    ELSE RAISE; END IF;
END $$;

NOTIFY pgrst, 'reload schema';
