-- ============================================================================
-- SICOM-ICEO | 689 — La capacitación acredita el curso + una sola ART por tarea
-- ============================================================================
-- Pedido de Manuel (13-11-2026), punto 4 de lo pendiente de prevención.
--
-- A. LA CAPACITACIÓN ACTUALIZA EL CONTROL DOCUMENTAL. Al registrar una
--    capacitación/charla en una faena con nómina (Calama), se puede indicar
--    QUÉ CURSO acredita (curso ART Centinela, protocolo de emergencias,
--    diploma Pillado…). Los asistentes marcados quedan con ese curso vigente
--    en su ficha, sin cargarlo dos veces.
--    Control: si lo registra Prevención (admin del módulo) se acredita al
--    guardar; si lo registra un supervisor, se acredita cuando Prevención lo
--    marca «revisado» (MIG561). El curso habilita en la inspección APR: no
--    puede habilitarse solo con la palabra de quien dictó la charla.
--    Nunca retrocede: si la persona ya tiene una acreditación más nueva, no
--    se toca. La versión anterior pasa al historial (como una renovación).
--    Sin fecha de vencimiento = 31-12-2099 (regla de MIG685).
--
-- B. UNA SOLA ART POR TAREA. La inspección APR genera su registro «ART»
--    (MIG686). Si el supervisor sube la ART de la MISMA tarea, la vincula a
--    esa inspección (art_de_inspeccion_id) y el registro automático se retira:
--    en el mes cuenta una ART, no dos. Si borra o desvincula la suya, el
--    automático vuelve.
--
-- ADITIVA. No borra datos (hoy no hay ART ni capacitaciones cargadas).
-- ============================================================================

BEGIN;

-- ############################################################################
-- A. CAPACITACIÓN → CURSO DEL ASISTENTE
-- ############################################################################

ALTER TABLE prevencion_registros
    ADD COLUMN IF NOT EXISTS curso_codigo VARCHAR(40)
        REFERENCES prevencion_examen_tipos(codigo),
    ADD COLUMN IF NOT EXISTS curso_vence DATE,
    ADD COLUMN IF NOT EXISTS asistentes_personal_ids UUID[],
    ADD COLUMN IF NOT EXISTS curso_acreditado_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS curso_acreditados INT;

COMMENT ON COLUMN prevencion_registros.curso_codigo IS
    'Curso del control documental que acredita esta capacitación (MIG689).';
COMMENT ON COLUMN prevencion_registros.curso_vence IS
    'Vencimiento del curso acreditado. NULL = no vence (31-12-2099). MIG689.';
COMMENT ON COLUMN prevencion_registros.asistentes_personal_ids IS
    'Asistentes (prevencion_personal.id), junto a asistentes_nombres. MIG689.';
COMMENT ON COLUMN prevencion_registros.curso_acreditado_at IS
    'Cuándo se pasó el curso a la ficha de los asistentes. NULL = pendiente de revisión de Prevención. MIG689.';

DO $$ BEGIN
    ALTER TABLE prevencion_registros ADD CONSTRAINT chk_prev_reg_curso_tipo
        CHECK (curso_codigo IS NULL OR tipo_codigo IN ('CAPACITACION','CHARLA'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE OR REPLACE FUNCTION fn_prevencion_capacitacion_acreditar(p_registro_id UUID)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    r       prevencion_registros%ROWTYPE;
    v_pid   UUID;
    v_ex    prevencion_examenes%ROWTYPE;
    v_vence DATE;
    v_obs   TEXT;
    v_n     INT := 0;
BEGIN
    SELECT * INTO r FROM prevencion_registros WHERE id = p_registro_id;
    IF NOT FOUND OR r.curso_codigo IS NULL
       OR COALESCE(array_length(r.asistentes_personal_ids, 1), 0) = 0 THEN
        RETURN 0;
    END IF;

    v_vence := COALESCE(r.curso_vence, DATE '2099-12-31');
    v_obs := left(format('Acreditado por %s «%s» del %s (reportabilidad).',
                         CASE r.tipo_codigo WHEN 'CHARLA' THEN 'charla' ELSE 'capacitación' END,
                         r.titulo, to_char(r.fecha_actividad, 'DD-MM-YYYY')), 500);

    FOREACH v_pid IN ARRAY r.asistentes_personal_ids LOOP
        CONTINUE WHEN NOT EXISTS (SELECT 1 FROM prevencion_personal WHERE id = v_pid);

        SELECT * INTO v_ex FROM prevencion_examenes
         WHERE personal_id = v_pid AND tipo_codigo = r.curso_codigo;

        IF NOT FOUND THEN
            INSERT INTO prevencion_examenes (
                personal_id, tipo_codigo, fecha_emision_real, fecha_vencimiento,
                aplica, observacion, actualizado_por, renovado_at, renovado_por)
            VALUES (v_pid, r.curso_codigo, r.fecha_actividad, v_vence,
                    true, v_obs, auth.uid(), now(), auth.uid());
            v_n := v_n + 1;
            CONTINUE;
        END IF;

        -- Ya acreditado con esta misma capacitación o con una más nueva:
        -- no se retrocede.
        CONTINUE WHEN v_ex.fecha_vencimiento IS NOT NULL
                  AND v_ex.fecha_emision_real IS NOT NULL
                  AND v_ex.fecha_emision_real >= r.fecha_actividad;

        IF v_ex.fecha_vencimiento IS NOT NULL OR v_ex.archivo_path IS NOT NULL THEN
            INSERT INTO prevencion_examen_historial (
                examen_id, personal_id, tipo_codigo, laboratorio,
                fecha_vencimiento, observacion, archivo_path, reemplazado_por, motivo)
            VALUES (v_ex.id, v_ex.personal_id, v_ex.tipo_codigo, v_ex.laboratorio,
                    v_ex.fecha_vencimiento, v_ex.observacion, v_ex.archivo_path,
                    auth.uid(), 'Capacitación');
        END IF;

        UPDATE prevencion_examenes SET
            fecha_vencimiento      = v_vence,
            fecha_emision_real     = r.fecha_actividad,
            observacion            = v_obs,
            observacion_bloqueante = false,
            aplica                 = true,
            motivo_no_aplica       = NULL,
            actualizado_por        = auth.uid(),
            renovado_at            = now(),
            renovado_por           = auth.uid()
         WHERE id = v_ex.id;

        DELETE FROM prevencion_alertas_enviadas WHERE examen_id = v_ex.id;
        v_n := v_n + 1;
    END LOOP;

    UPDATE prevencion_registros
       SET curso_acreditado_at = now(),
           curso_acreditados   = COALESCE(curso_acreditados, 0) + v_n
     WHERE id = p_registro_id;
    RETURN v_n;
END $$;

COMMENT ON FUNCTION fn_prevencion_capacitacion_acreditar(UUID) IS
    'Pasa el curso de una capacitación a la ficha (prevencion_examenes) de cada asistente. Nunca retrocede. MIG689.';

REVOKE ALL ON FUNCTION fn_prevencion_capacitacion_acreditar(UUID) FROM PUBLIC, anon, authenticated;

-- Se acredita al guardar si lo carga Prevención; si lo carga un supervisor,
-- cuando Prevención lo marca revisado. Cambios posteriores (asistentes,
-- fecha) se vuelven a aplicar si ya estaba acreditado.
--
-- Candado: la revisión (MIG561) y la acreditación son de Prevención. Hasta
-- hoy el autor podía marcar «revisado» su propio registro dentro de las 24 h
-- (la política de UPDATE no distingue columnas); ahora eso acreditaría un
-- curso, así que esas columnas solo las cambia un admin del módulo. Sin
-- sesión (migraciones, funciones internas) no se toca nada.
CREATE OR REPLACE FUNCTION fn_trg_prev_reg_guard_revision()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF auth.uid() IS NULL OR fn_prevencion_reporta_puede_admin() THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'INSERT' THEN
        NEW.revisado := false; NEW.revisado_por := NULL; NEW.revisado_at := NULL;
        NEW.revision_observacion := NULL;
        NEW.curso_acreditado_at := NULL; NEW.curso_acreditados := NULL;
    ELSE
        NEW.revisado := OLD.revisado; NEW.revisado_por := OLD.revisado_por;
        NEW.revisado_at := OLD.revisado_at; NEW.revision_observacion := OLD.revision_observacion;
        NEW.curso_acreditado_at := OLD.curso_acreditado_at;
        NEW.curso_acreditados := OLD.curso_acreditados;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_prev_reg_guard_revision ON prevencion_registros;
CREATE TRIGGER trg_prev_reg_guard_revision
    BEFORE INSERT OR UPDATE ON prevencion_registros
    FOR EACH ROW EXECUTE FUNCTION fn_trg_prev_reg_guard_revision();

CREATE OR REPLACE FUNCTION fn_trg_prev_reg_curso()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW.curso_codigo IS NULL THEN RETURN NULL; END IF;
    -- Solo acredita Prevención: al guardar lo suyo, al revisar lo de un
    -- supervisor, o al corregir uno ya acreditado.
    IF fn_prevencion_reporta_puede_admin()
       AND (TG_OP = 'INSERT' OR NEW.revisado OR OLD.curso_acreditado_at IS NOT NULL) THEN
        PERFORM fn_prevencion_capacitacion_acreditar(NEW.id);
    END IF;
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_prev_reg_curso_ins ON prevencion_registros;
CREATE TRIGGER trg_prev_reg_curso_ins
    AFTER INSERT ON prevencion_registros
    FOR EACH ROW WHEN (NEW.curso_codigo IS NOT NULL)
    EXECUTE FUNCTION fn_trg_prev_reg_curso();

-- UPDATE OF: el UPDATE de curso_acreditado_at no lo vuelve a disparar.
DROP TRIGGER IF EXISTS trg_prev_reg_curso_upd ON prevencion_registros;
CREATE TRIGGER trg_prev_reg_curso_upd
    AFTER UPDATE OF revisado, curso_codigo, curso_vence, asistentes_personal_ids, fecha_actividad
    ON prevencion_registros
    FOR EACH ROW WHEN (NEW.curso_codigo IS NOT NULL)
    EXECUTE FUNCTION fn_trg_prev_reg_curso();

-- Cursos que una capacitación puede acreditar (selector del formulario).
CREATE OR REPLACE VIEW v_prevencion_cursos_acreditables AS
SELECT codigo, nombre, categoria, orden
  FROM prevencion_examen_tipos
 WHERE activo AND categoria IN ('curso','competencia');
GRANT SELECT ON v_prevencion_cursos_acreditables TO authenticated;


-- ############################################################################
-- B. UNA SOLA ART POR TAREA INSPECCIONADA
-- ############################################################################

ALTER TABLE prevencion_registros
    ADD COLUMN IF NOT EXISTS art_de_inspeccion_id UUID
        REFERENCES prevencion_inspecciones(id) ON DELETE SET NULL;

COMMENT ON COLUMN prevencion_registros.art_de_inspeccion_id IS
    'ART del supervisor que es de la tarea de esa inspección APR: reemplaza el registro ART automático (MIG689).';

DO $$ BEGIN
    ALTER TABLE prevencion_registros ADD CONSTRAINT chk_prev_reg_art_insp
        CHECK (art_de_inspeccion_id IS NULL OR (tipo_codigo = 'ART' AND inspeccion_id IS NULL));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_prev_reg_art_de_inspeccion
    ON prevencion_registros (art_de_inspeccion_id)
    WHERE art_de_inspeccion_id IS NOT NULL;

-- Inspecciones del día en la faena, para que el supervisor diga «es esta».
-- El supervisor no ve inspecciones ajenas por RLS: se expone solo lo
-- necesario para reconocer la tarea.
CREATE OR REPLACE FUNCTION fn_prevencion_inspecciones_del_dia(p_faena_id UUID, p_fecha DATE)
RETURNS TABLE (id UUID, trabajo TEXT, inspector_nombre TEXT, lugar TEXT, ya_vinculada BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT i.id, i.trabajo::text, i.inspector_nombre::text,
           NULLIF(concat_ws(' · ', i.instalacion, i.area_sector), ''),
           EXISTS (SELECT 1 FROM prevencion_registros r WHERE r.art_de_inspeccion_id = i.id)
      FROM prevencion_inspecciones i
     WHERE i.faena_id = p_faena_id AND i.fecha = p_fecha
       AND (fn_prevencion_reporta_puede_crear() OR fn_prevencion_reporta_puede_ver())
     ORDER BY i.created_at;
$$;
GRANT EXECUTE ON FUNCTION fn_prevencion_inspecciones_del_dia(UUID, DATE) TO authenticated;

CREATE OR REPLACE FUNCTION fn_prevencion_inspeccion_sync_registros(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    i            prevencion_inspecciones%ROWTYPE;
    v_abiertas   INT;
    v_fotos      JSONB;
    v_art        JSONB;
    v_art_cierre JSONB;
    v_lugar      TEXT;
BEGIN
    SELECT * INTO i FROM prevencion_inspecciones WHERE id = p_id;
    IF NOT FOUND THEN RETURN; END IF;

    SELECT count(*) INTO v_abiertas
      FROM prevencion_inspeccion_desviaciones
     WHERE inspeccion_id = p_id AND estado = 'abierta';

    -- Fotos del registro «Inspección». La PPT de evidencias muestra las dos
    -- primeras: van primero la segregación del área y el trabajo en
    -- ejecución, que son las que mejor cuentan la inspección.
    SELECT COALESCE(jsonb_agg(e ORDER BY
               array_position(ARRAY['A2','J1','F1','A1','T1','D3','D2','D6','F2'], it.item_codigo),
               it.item_codigo), '[]'::jsonb)
      INTO v_fotos
      FROM prevencion_inspeccion_items it,
           jsonb_array_elements(it.evidencias) e
     WHERE it.inspeccion_id = p_id
       AND it.item_codigo <> 'R1';

    v_lugar := NULLIF(concat_ws(' · ', i.instalacion, i.area_sector), '');

    INSERT INTO prevencion_registros (
        faena_id, tipo_codigo, fecha_actividad, titulo, descripcion, area_sector,
        estado, evidencias, creado_por, supervisor_nombre, inspeccion_id)
    VALUES (
        i.faena_id, 'INSPECCION', i.fecha,
        left('Inspección de terreno APR — ' || i.trabajo, 200),
        format('Resultado: %s. Cumplimiento: %s. %s punto(s) no cumple, %s desviación(es) abierta(s)%s.',
               CASE i.resultado WHEN 'conforme' THEN 'conforme'
                                WHEN 'con_desviaciones' THEN 'con desviaciones'
                                ELSE 'CRÍTICO' END,
               COALESCE(i.pct_cumplimiento::text || '%', 'sin evaluar'),
               i.items_no_cumple, v_abiertas,
               CASE WHEN i.personas_no_habilitadas > 0
                    THEN format(', %s trabajador(es) no habilitado(s)', i.personas_no_habilitadas)
                    ELSE '' END),
        left(v_lugar, 120),
        CASE WHEN v_abiertas > 0 THEN 'abierto' ELSE 'cerrado' END,
        v_fotos, i.inspector_id, i.inspector_nombre, p_id)
    ON CONFLICT (inspeccion_id, tipo_codigo) WHERE inspeccion_id IS NOT NULL
    DO UPDATE SET
        faena_id = EXCLUDED.faena_id,
        fecha_actividad = EXCLUDED.fecha_actividad,
        titulo = EXCLUDED.titulo,
        descripcion = EXCLUDED.descripcion,
        area_sector = EXCLUDED.area_sector,
        estado = EXCLUDED.estado,
        evidencias = EXCLUDED.evidencias,
        cierre_observacion = CASE WHEN EXCLUDED.estado = 'cerrado'
                                  THEN 'Desviaciones de la inspección cerradas.' END;

    -- Registro «ART»: solo si la ART de la tarea se verificó con foto.
    SELECT COALESCE(it.evidencias, '[]'::jsonb) INTO v_art
      FROM prevencion_inspeccion_items it
     WHERE it.inspeccion_id = p_id AND it.item_codigo = 'D3' AND it.respuesta = 'cumple';
    SELECT COALESCE(jsonb_agg(e), '[]'::jsonb) INTO v_art_cierre
      FROM prevencion_inspeccion_items it, jsonb_array_elements(it.evidencias) e
     WHERE it.inspeccion_id = p_id AND it.item_codigo IN ('C1','R1');

    -- [MIG689] Si el supervisor ya subió la ART de esta tarea, esa es la que
    -- cuenta: el registro automático se retira.
    IF v_art IS NOT NULL AND jsonb_array_length(v_art) > 0
       AND NOT EXISTS (SELECT 1 FROM prevencion_registros
                        WHERE art_de_inspeccion_id = p_id) THEN
        INSERT INTO prevencion_registros (
            faena_id, tipo_codigo, fecha_actividad, titulo, descripcion, area_sector,
            estado, evidencias, creado_por, supervisor_nombre, inspeccion_id)
        VALUES (
            i.faena_id, 'ART', i.fecha,
            left('ART — ' || i.trabajo, 200),
            'ART de la tarea, verificada en la inspección de terreno APR.' ||
              CASE WHEN EXISTS (SELECT 1 FROM prevencion_inspeccion_items
                                 WHERE inspeccion_id = p_id AND item_codigo = 'R1' AND respuesta = 'cumple')
                   THEN ' Cerrada en Calama y archivada.'
                   ELSE ' Cierre en Calama pendiente.' END,
            left(v_lugar, 120), 'cerrado', v_art || v_art_cierre,
            i.inspector_id, i.inspector_nombre, p_id)
        ON CONFLICT (inspeccion_id, tipo_codigo) WHERE inspeccion_id IS NOT NULL
        DO UPDATE SET
            faena_id = EXCLUDED.faena_id,
            fecha_actividad = EXCLUDED.fecha_actividad,
            titulo = EXCLUDED.titulo,
            descripcion = EXCLUDED.descripcion,
            area_sector = EXCLUDED.area_sector,
            evidencias = EXCLUDED.evidencias;
    ELSE
        DELETE FROM prevencion_registros WHERE inspeccion_id = p_id AND tipo_codigo = 'ART';
    END IF;
END $$;

COMMENT ON FUNCTION fn_prevencion_inspeccion_sync_registros(UUID) IS
    'Mantiene los registros de reportabilidad (Inspección y ART) que genera una inspección APR. MIG686; MIG689: no crea ART si el supervisor vinculó la suya.';

CREATE OR REPLACE FUNCTION fn_trg_prev_reg_art_vinculo()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF TG_OP IN ('UPDATE','DELETE') AND OLD.art_de_inspeccion_id IS NOT NULL THEN
        PERFORM fn_prevencion_inspeccion_sync_registros(OLD.art_de_inspeccion_id);
    END IF;
    IF TG_OP IN ('INSERT','UPDATE') AND NEW.art_de_inspeccion_id IS NOT NULL THEN
        PERFORM fn_prevencion_inspeccion_sync_registros(NEW.art_de_inspeccion_id);
    END IF;
    RETURN NULL;
END $$;

-- Los registros automáticos llevan art_de_inspeccion_id NULL: no recursan.
DROP TRIGGER IF EXISTS trg_prev_reg_art_vinculo_ins ON prevencion_registros;
CREATE TRIGGER trg_prev_reg_art_vinculo_ins
    AFTER INSERT ON prevencion_registros
    FOR EACH ROW WHEN (NEW.art_de_inspeccion_id IS NOT NULL)
    EXECUTE FUNCTION fn_trg_prev_reg_art_vinculo();

DROP TRIGGER IF EXISTS trg_prev_reg_art_vinculo_upd ON prevencion_registros;
CREATE TRIGGER trg_prev_reg_art_vinculo_upd
    AFTER UPDATE OF art_de_inspeccion_id ON prevencion_registros
    FOR EACH ROW WHEN (OLD.art_de_inspeccion_id IS DISTINCT FROM NEW.art_de_inspeccion_id)
    EXECUTE FUNCTION fn_trg_prev_reg_art_vinculo();

DROP TRIGGER IF EXISTS trg_prev_reg_art_vinculo_del ON prevencion_registros;
CREATE TRIGGER trg_prev_reg_art_vinculo_del
    AFTER DELETE ON prevencion_registros
    FOR EACH ROW WHEN (OLD.art_de_inspeccion_id IS NOT NULL)
    EXECUTE FUNCTION fn_trg_prev_reg_art_vinculo();

COMMIT;

SELECT
    (SELECT count(*) FROM v_prevencion_cursos_acreditables) AS cursos_acreditables,
    (SELECT count(*) FROM information_schema.columns
      WHERE table_name = 'prevencion_registros'
        AND column_name IN ('curso_codigo','curso_vence','asistentes_personal_ids',
                            'curso_acreditado_at','curso_acreditados','art_de_inspeccion_id')) AS columnas_nuevas;
