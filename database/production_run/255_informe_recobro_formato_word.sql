-- ============================================================================
-- SICOM-ICEO | 255 — Campos del informe de recobro en el formato Word de Pillado
-- ----------------------------------------------------------------------------
-- Manuel (2026-07-29): el informe de recobro debe salir como un Word descargable
-- con el formato de «informe_KVWD-27 Devolucion.docx».
--
-- Ese formato pide datos que HOY NO EXISTEN en la base:
--
--   Encabezado del informe        ¿lo teníamos?
--   ---------------------------   -------------------------------------------
--   Ciudad y fecha                no
--   CLIENTE                       sí (informes_recepcion.cliente_nombre)
--   FECHA DE RECEPCIÓN            sí (fecha_recepcion)
--   LUGAR DE CHEQUEO              no
--   TÉCNICO A CARGO               no
--   ELABORADO POR                 no
--   PPU / TIPO / MARCA-MODELO     sí (activos)
--   N° DE CHASIS                  sí, en activos.vin_chasis (no se copiaba)
--   HORÓMETRO Y KILOMETRAJE       sí, en activos (no se copiaba)
--   METER INGRESO / SALIDA        no
--
--   Por cada hallazgo             ¿lo teníamos?
--   ---------------------------   -------------------------------------------
--   Descripción + foto            sí
--   Diagnóstico                   NO
--   Medida Correctiva             NO
--   Amerita Recobro               solo como booleano atribuible_cliente
--
-- Esta MIG agrega esos campos y los PRE-LLENA con lo que el sistema ya sabe
-- (chasis, horómetro, kilometraje y lugar salen del maestro de activos; el
-- «Amerita Recobro» sale de la clasificación que hizo el jefe en la NC). Lo que
-- nadie sabe queda NULL y el Word lo imprime como «POR COMPLETAR», igual que en
-- la plantilla original.
-- ADITIVA, IDEMPOTENTE. No borra datos.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_nc_informe_recobro') THEN
        RAISE EXCEPTION 'STOP — falta MIG251/253/254.';
    END IF;
END $$;


-- ── 1. Encabezado del informe ───────────────────────────────────────────────
ALTER TABLE informes_recepcion
    ADD COLUMN IF NOT EXISTS ciudad            VARCHAR(80),
    ADD COLUMN IF NOT EXISTS lugar_chequeo     VARCHAR(160),
    ADD COLUMN IF NOT EXISTS tecnico_cargo     VARCHAR(160),
    ADD COLUMN IF NOT EXISTS elaborado_por     VARCHAR(160),
    ADD COLUMN IF NOT EXISTS n_chasis          VARCHAR(80),
    ADD COLUMN IF NOT EXISTS horometro         VARCHAR(60),
    ADD COLUMN IF NOT EXISTS kilometraje       VARCHAR(60),
    ADD COLUMN IF NOT EXISTS meter_ingreso     VARCHAR(60),
    ADD COLUMN IF NOT EXISTS meter_salida      VARCHAR(60),
    ADD COLUMN IF NOT EXISTS nota_final        TEXT;

COMMENT ON COLUMN informes_recepcion.lugar_chequeo IS
    'Dónde se revisó el equipo. Encabezado del Word de devolución. MIG255.';


-- ── 2. Cada hallazgo con su diagnóstico y medida correctiva ─────────────────
ALTER TABLE informe_recepcion_hallazgos
    ADD COLUMN IF NOT EXISTS diagnostico       TEXT,
    ADD COLUMN IF NOT EXISTS medida_correctiva TEXT,
    ADD COLUMN IF NOT EXISTS amerita_recobro   VARCHAR(60);

COMMENT ON COLUMN informe_recepcion_hallazgos.amerita_recobro IS
    'Texto tal cual sale en el Word: «Si Amerita recobro» / «N/A» / «Por evaluar». MIG255.';


-- ── 3. Backfill de lo que el sistema ya sabe ────────────────────────────────
UPDATE informes_recepcion ir
   SET n_chasis      = COALESCE(ir.n_chasis, a.vin_chasis, a.numero_serie),
       kilometraje   = COALESCE(ir.kilometraje,
                                CASE WHEN a.kilometraje_actual IS NOT NULL
                                     THEN to_char(a.kilometraje_actual, 'FM999G999G999D0') || ' km' END),
       horometro     = COALESCE(ir.horometro,
                                CASE WHEN a.horas_uso_actual IS NOT NULL
                                     THEN to_char(a.horas_uso_actual, 'FM999G999D0') || ' hrs' END),
       lugar_chequeo = COALESCE(ir.lugar_chequeo, a.ubicacion_actual)
  FROM activos a
 WHERE a.id = ir.activo_id
   AND ir.estado <> 'emitido';   -- lo emitido es inmutable

-- El «Amerita Recobro» de los hallazgos que nacieron de una NC sale de la
-- clasificación que hizo el jefe de taller.
UPDATE informe_recepcion_hallazgos h
   SET amerita_recobro = CASE v.recobro
                             WHEN 'cliente'    THEN 'Si Amerita recobro'
                             WHEN 'compartido' THEN 'Recobro compartido'
                             WHEN 'empresa'    THEN 'N/A'
                             WHEN 'evaluar'    THEN 'Por evaluar'
                             ELSE 'N/A' END
  FROM no_conformidades nc
  JOIN v_nc_recepcion v ON v.id = nc.id
 WHERE nc.recobro_hallazgo_id = h.id
   AND h.amerita_recobro IS NULL;

-- El resto, según el booleano que ya traía
UPDATE informe_recepcion_hallazgos
   SET amerita_recobro = CASE WHEN atribuible_cliente THEN 'Si Amerita recobro' ELSE 'N/A' END
 WHERE amerita_recobro IS NULL;


-- ── 4. Al armar el recobro desde las NC se llena el encabezado ──────────────
CREATE OR REPLACE FUNCTION public.rpc_nc_informe_recobro(
    p_activo_id     UUID,
    p_nc_ids        UUID[] DEFAULT NULL,
    p_tarifa_hh_id  UUID   DEFAULT NULL
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
    v_tarifa_id     UUID;
    v_tarifa_nombre TEXT;
    v_yo        TEXT;
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

    SELECT nombre_completo INTO v_yo FROM usuarios_perfil WHERE id = v_user;

    IF p_tarifa_hh_id IS NOT NULL THEN
        SELECT id, nombre INTO v_tarifa_id, v_tarifa_nombre
          FROM tarifas_hh WHERE id = p_tarifa_hh_id AND activo;
    END IF;

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
            inspector_id, estado, folio, observaciones_finales,
            -- [MIG255] encabezado del Word, con lo que el sistema ya sabe
            n_chasis, kilometraje, horometro, lugar_chequeo, elaborado_por
        ) VALUES (
            p_activo_id, fn_contrato_para_ot(p_activo_id), v_activo.cliente_actual, CURRENT_DATE,
            v_user, 'borrador', v_folio,
            'Recobro armado desde las No Conformidades del taller. Valores pendientes: los carga el planificador.',
            COALESCE(v_activo.vin_chasis, v_activo.numero_serie),
            CASE WHEN v_activo.kilometraje_actual IS NOT NULL
                 THEN to_char(v_activo.kilometraje_actual, 'FM999G999G999D0') || ' km' END,
            CASE WHEN v_activo.horas_uso_actual IS NOT NULL
                 THEN to_char(v_activo.horas_uso_actual, 'FM999G999D0') || ' hrs' END,
            v_activo.ubicacion_actual,
            v_yo
        )
        RETURNING * INTO v_informe;
        v_nuevo := true;
    END IF;

    FOR nc IN
        SELECT n.id, n.descripcion, n.severidad, n.foto_url, n.checklist_item_ref,
               n.horas_estimadas, n.grupo_trabajo, n.recobro_hallazgo_id, n.recobro_nota,
               v.recobro, v.observacion_item
          FROM no_conformidades n
          JOIN v_nc_recepcion v ON v.id = n.id
         WHERE n.activo_id = p_activo_id
           AND (p_nc_ids IS NULL OR n.id = ANY(p_nc_ids))
           AND v.recobro IN ('cliente','compartido')
           AND n.estado_planificacion <> 'descartada'
         ORDER BY n.created_at
    LOOP
        IF nc.recobro_hallazgo_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM informe_recepcion_hallazgos
             WHERE id = nc.recobro_hallazgo_id AND informe_id = v_informe.id) THEN
            v_ya := v_ya + 1;
            CONTINUE;
        END IF;

        INSERT INTO informe_recepcion_hallazgos (
            informe_id, seccion, descripcion, gravedad, atribuible_cliente,
            fotos, observacion, checklist_v2_item_id,
            -- [MIG255] el diagnóstico arranca con lo que observó el operador
            diagnostico, amerita_recobro
        ) VALUES (
            v_informe.id, 'No Conformidad del taller', nc.descripcion,
            (CASE nc.severidad WHEN 'critica' THEN 'critica'
                               WHEN 'alta'    THEN 'mayor'
                               ELSE 'menor' END)::gravedad_hallazgo_enum,
            (nc.recobro = 'cliente'),
            CASE WHEN nc.foto_url IS NOT NULL THEN jsonb_build_array(nc.foto_url) ELSE '[]'::JSONB END,
            NULLIF(concat_ws(' · ', nc.observacion_item, nc.recobro_nota), ''),
            nc.checklist_item_ref,
            nc.observacion_item,
            CASE nc.recobro WHEN 'cliente'    THEN 'Si Amerita recobro'
                            WHEN 'compartido' THEN 'Recobro compartido'
                            ELSE 'Por evaluar' END
        )
        RETURNING id INTO v_hallazgo;
        v_creados := v_creados + 1;

        UPDATE no_conformidades
           SET recobro_informe_id = v_informe.id, recobro_hallazgo_id = v_hallazgo, updated_at = NOW()
         WHERE id = nc.id;

        FOR mat IN
            SELECT descripcion, cantidad, unidad, producto_id
              FROM v_nc_insumos
             WHERE nc_id = nc.id AND estado <> 'rechazado'
        LOOP
            INSERT INTO informe_recepcion_costos (
                informe_id, tipo, producto_id, descripcion, cantidad, unidad,
                precio_unitario, cobrable_cliente, hallazgo_id
            ) VALUES (
                v_informe.id, 'repuesto'::tipo_costo_recepcion_enum, mat.producto_id,
                COALESCE(mat.descripcion, 'Material'), COALESCE(mat.cantidad, 1), mat.unidad,
                0, true, v_hallazgo
            );
            v_costos := v_costos + 1;
        END LOOP;

        IF COALESCE(nc.horas_estimadas, 0) > 0 THEN
            INSERT INTO informe_recepcion_costos (
                informe_id, tipo, tarifa_hh_id, descripcion, cantidad, unidad,
                precio_unitario, cobrable_cliente, hallazgo_id
            ) VALUES (
                v_informe.id, 'mano_obra'::tipo_costo_recepcion_enum, v_tarifa_id,
                'Mano de obra' || COALESCE(' — ' || v_tarifa_nombre, '') ||
                    COALESCE(' (' || nc.grupo_trabajo || ')', ''),
                nc.horas_estimadas, 'HH', 0, true, v_hallazgo
            );
            v_costos := v_costos + 1;
        END IF;
    END LOOP;

    SELECT * INTO v_informe FROM informes_recepcion WHERE id = v_informe.id;

    RETURN jsonb_build_object(
        'ok', true, 'informe_id', v_informe.id, 'folio', v_informe.folio,
        'informe_nuevo', v_nuevo, 'hallazgos_creados', v_creados, 'ya_estaban', v_ya,
        'costos_creados', v_costos,
        'total_cobrable', v_informe.total_cobrable_cliente, 'total', v_informe.total
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_nc_informe_recobro(UUID, UUID[], UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_nc_informe_recobro(UUID, UUID[], UUID) TO authenticated;


-- ── 5. Todo lo que el Word necesita, en una consulta ────────────────────────
CREATE OR REPLACE VIEW v_informe_recobro_word AS
SELECT ir.id, ir.folio, ir.estado::text AS estado,
       ir.cliente_nombre, ir.fecha_recepcion, ir.fecha_entrega_arriendo,
       ir.ciudad, ir.lugar_chequeo, ir.tecnico_cargo, ir.elaborado_por,
       ir.n_chasis, ir.horometro, ir.kilometraje, ir.meter_ingreso, ir.meter_salida,
       ir.observaciones_finales, ir.nota_final, ir.emitido_en, ir.pdf_url,
       a.patente, a.codigo AS activo_codigo,
       a.nombre AS equipo_nombre, a.tipo::text AS equipo_tipo,
       ma.nombre AS marca, mo.nombre AS modelo,
       insp.nombre_completo AS inspector_nombre,
       enc.nombre_completo  AS encargado_nombre
  FROM informes_recepcion ir
  JOIN activos a         ON a.id = ir.activo_id
  LEFT JOIN modelos mo   ON mo.id = a.modelo_id
  LEFT JOIN marcas  ma   ON ma.id = mo.marca_id
  LEFT JOIN usuarios_perfil insp ON insp.id = ir.inspector_id
  LEFT JOIN usuarios_perfil enc  ON enc.id  = ir.encargado_cobros_id;

GRANT SELECT ON v_informe_recobro_word TO authenticated;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE v_faltan TEXT; v_r RECORD;
BEGIN
    SELECT string_agg(c, ', ') INTO v_faltan
      FROM unnest(ARRAY['ciudad','lugar_chequeo','tecnico_cargo','elaborado_por',
                        'n_chasis','horometro','kilometraje','meter_ingreso','meter_salida']) c
     WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_name='informes_recepcion' AND column_name=c);
    IF v_faltan IS NOT NULL THEN RAISE EXCEPTION 'FALLO — faltan columnas: %', v_faltan; END IF;

    SELECT string_agg(c, ', ') INTO v_faltan
      FROM unnest(ARRAY['diagnostico','medida_correctiva','amerita_recobro']) c
     WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                        WHERE table_name='informe_recepcion_hallazgos' AND column_name=c);
    IF v_faltan IS NOT NULL THEN RAISE EXCEPTION 'FALLO — faltan columnas en hallazgos: %', v_faltan; END IF;

    FOR v_r IN SELECT folio, patente, COALESCE(n_chasis,'—') AS chasis,
                      COALESCE(kilometraje,'—') AS km, COALESCE(lugar_chequeo,'—') AS lugar
                 FROM v_informe_recobro_word ORDER BY folio LIMIT 3 LOOP
        RAISE NOTICE 'MIG255: % (%) chasis=% km=% lugar=%',
            v_r.folio, v_r.patente, v_r.chasis, v_r.km, v_r.lugar;
    END LOOP;

    RAISE NOTICE 'MIG255 OK: % hallazgo(s) con «Amerita Recobro» resuelto',
        (SELECT count(*) FROM informe_recepcion_hallazgos WHERE amerita_recobro IS NOT NULL);
END $$;

NOTIFY pgrst, 'reload schema';
