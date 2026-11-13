-- ============================================================================
-- SICOM-ICEO | 686 — Una sola lista de personal + inspección APR en la
--                    reportabilidad mensual
-- ============================================================================
-- Pedido de Manuel (13-11-2026), puntos 1 y 3 de la revisión de cómo «habla»
-- el control documental con el resto de prevención.
--
-- 1. UNA SOLA LISTA DE PERSONAL. En Calama había dos listas de las mismas 9
--    personas: la nómina de reportabilidad (MIG555, solo nombres, se usa para
--    marcar asistentes de charlas) y el control documental (RUT + documentos,
--    lo usa la inspección APR). Desde ahora la nómina SALE del control
--    documental: quien se da de alta (o se desactiva) ahí, aparece (o
--    desaparece) en las charlas de sus faenas. El sexo pasa a la ficha de la
--    persona, que es donde se puede corregir.
--    La tabla vieja prevencion_personal_faena queda sin uso (no se borra:
--    es el respaldo si hubiera que volver atrás).
--
-- 2. LA INSPECCIÓN CUENTA EN EL INFORME DEL MES. Cada inspección APR genera
--    sola su registro «Inspección» en prevencion_registros (con las fotos
--    principales), y si se fotografió la ART de la tarea, un registro «ART».
--    Así entra al consolidado mensual, a la PPT de evidencias y al panel de
--    reportabilidad sin cargarla dos veces. El registro «Inspección» queda
--    ABIERTO mientras la inspección tenga desviaciones abiertas y se cierra
--    solo cuando se cierra la última.
--
-- ADITIVA. No borra datos.
-- ============================================================================

BEGIN;

-- ############################################################################
-- 1. PERSONAL ÚNICO
-- ############################################################################

ALTER TABLE prevencion_personal
    ADD COLUMN IF NOT EXISTS sexo CHAR(1) NOT NULL DEFAULT 'M';

DO $$ BEGIN
    ALTER TABLE prevencion_personal
        ADD CONSTRAINT chk_prev_personal_sexo CHECK (sexo IN ('M','F'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

COMMENT ON COLUMN prevencion_personal.sexo IS
    'M/F. Lo usa la nómina de faena (y el desglose por sexo). MIG686.';

-- Trae el sexo que ya estuviera corregido en la nómina vieja.
UPDATE prevencion_personal p
   SET sexo = n.sexo
  FROM (SELECT DISTINCT ON (lower(nombre)) lower(nombre) AS nombre, sexo
          FROM prevencion_personal_faena
         ORDER BY lower(nombre), sexo DESC) n
 WHERE lower(trim(p.nombres || ' ' || COALESCE(p.apellidos, ''))) = n.nombre
   AND p.sexo <> n.sexo;

COMMENT ON TABLE prevencion_inspeccion_faenas IS
    'Faenas atendidas por un grupo de personal del control documental (CALAMA). Define dónde se hace la inspección APR (MIG685) y la nómina de cada faena (MIG686).';

-- Nómina por faena, desde el control documental. Mismas columnas que la
-- tabla vieja, así la pantalla de charlas no cambia. Corre con permisos del
-- dueño y filtra igual que la política de la tabla vieja (ver o cargar
-- reportabilidad); expone solo nombre y sexo, nunca RUT ni documentos.
CREATE OR REPLACE VIEW v_prevencion_nomina_faena AS
SELECT p.id,
       f.faena_id,
       trim(p.nombres || ' ' || COALESCE(p.apellidos, '')) AS nombre,
       p.sexo,
       p.activo,
       100 AS orden
  FROM prevencion_personal p
  JOIN prevencion_inspeccion_faenas f
    ON f.grupo_personal = p.faena_codigo AND f.activo
 WHERE p.activo
   AND (fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear());

GRANT SELECT ON v_prevencion_nomina_faena TO authenticated;

COMMENT ON VIEW v_prevencion_nomina_faena IS
    'Nómina de faena (asistentes de charlas) derivada del control documental. Reemplaza a prevencion_personal_faena. MIG686.';

COMMENT ON TABLE prevencion_personal_faena IS
    'SIN USO desde MIG686: la nómina sale de v_prevencion_nomina_faena (control documental). Se conserva como respaldo.';


-- ############################################################################
-- 2. INSPECCIÓN → REGISTROS DE REPORTABILIDAD
-- ############################################################################

ALTER TABLE prevencion_registros
    ADD COLUMN IF NOT EXISTS inspeccion_id UUID
        REFERENCES prevencion_inspecciones(id) ON DELETE CASCADE;

COMMENT ON COLUMN prevencion_registros.inspeccion_id IS
    'Registro generado por una inspección APR (MIG686). Se mantiene solo: no se edita a mano.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_prev_reg_inspeccion_tipo
    ON prevencion_registros (inspeccion_id, tipo_codigo)
    WHERE inspeccion_id IS NOT NULL;


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

    IF v_art IS NOT NULL AND jsonb_array_length(v_art) > 0 THEN
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
    'Mantiene los registros de reportabilidad (Inspección y ART) que genera una inspección APR. MIG686.';


-- El guardado de la inspección termina SIEMPRE con un UPDATE de su resultado
-- (MIG685), así que basta con escuchar los cambios de la cabecera. Cerrar una
-- desviación también resincroniza (el registro pasa a cerrado con la última).
CREATE OR REPLACE FUNCTION fn_trg_prev_insp_sync()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM fn_prevencion_inspeccion_sync_registros(NEW.id);
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_prev_insp_sync_registros ON prevencion_inspecciones;
CREATE TRIGGER trg_prev_insp_sync_registros
    AFTER INSERT OR UPDATE ON prevencion_inspecciones
    FOR EACH ROW EXECUTE FUNCTION fn_trg_prev_insp_sync();

CREATE OR REPLACE FUNCTION fn_trg_prev_desv_sync()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM fn_prevencion_inspeccion_sync_registros(NEW.inspeccion_id);
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_prev_desv_sync_registros ON prevencion_inspeccion_desviaciones;
CREATE TRIGGER trg_prev_desv_sync_registros
    AFTER UPDATE OF estado ON prevencion_inspeccion_desviaciones
    FOR EACH ROW EXECUTE FUNCTION fn_trg_prev_desv_sync();

-- Inspecciones que ya existieran.
SELECT fn_prevencion_inspeccion_sync_registros(id) FROM prevencion_inspecciones;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
SELECT
    (SELECT count(*) FROM v_prevencion_nomina_faena)                       AS nomina_filas,
    (SELECT count(DISTINCT faena_id) FROM v_prevencion_nomina_faena)       AS nomina_faenas,
    (SELECT count(*) FROM prevencion_personal_faena WHERE activo)          AS nomina_vieja_filas,
    (SELECT count(*) FROM prevencion_registros WHERE inspeccion_id IS NOT NULL) AS registros_de_inspeccion;
