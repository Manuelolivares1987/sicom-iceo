-- ============================================================================
-- MIG444 · El checklist deja de preguntar «¿OK?» a lo que no es una pregunta
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 28-08-2026, mirando la OT-202608-00013 (Atego SL 200h, FJTJ-60):
-- «la parte B11 no tiene razón de ser que sea como sí o no», y «él debe
-- empezar colocando KM y horas cuando comienza su checklist».
--
-- LO QUE PASA
-- Los 7 ítems del bloque B11 (b7_cierre_recepcion) traen el tipo de respuesta
-- escrito en su propia descripción, entre paréntesis, porque el modelo no tenía
-- cómo expresarlo:
--
--   B11.01  Daños no reportados detectados al recibir (texto + fotos)
--   B11.02  Observaciones del operador que entrega (texto libre)
--   B11.03  Trabajos solicitados (descripción inicial)
--   B11.04  Próximo horómetro de pauta (planificado)
--   B11.05  Tipo de OT a generar (taxonomía OT-XX-XX)
--   B11.06  Tiempo estimado de la OT (HH) y fecha de entrega comprometida
--   B11.07  Firma operador entrega + RUT / Firma responsable taller + RUT
--
-- Todos se responden OK / NO OK. Marcar «OK» en «Observaciones del operador»
-- no significa nada: son campos de captura disfrazados de verificación.
--
-- Revisados los 169 ítems de esa OT, los afectados son esos 7 más B08.05
-- («próxima pauta del sistema»). Ocho. El resto sí son verificaciones. En
-- producción: 66 OTs, 462 instancias de ítem del bloque B11.
--
-- QUÉ SE HACE
--   1. `tipo_respuesta` en la plantilla del ítem. Por defecto 'ok_no_ok', así
--      que los 161 ítems que sí son verificaciones no cambian en nada.
--   2. Los 8 quedan declarados con su tipo real.
--   3. La vista del checklist lo expone, junto con `valor_numerico`, que ya
--      existía en la instancia y no se estaba publicando.
--
-- DÓNDE SE GUARDA CADA RESPUESTA (columnas que ya existen en la instancia)
--   texto      → observacion
--   numero     → valor_numerico
--   fecha      → mediciones->>'fecha'
--   seleccion  → observacion
--   firma      → mediciones (firma_*_url, rut_*, nombre_*)
--
-- LOS MEDIDORES NO SE TOCAN ACÁ. `rpc_taller_registrar_medidores` ya existe
-- (MIG397) y funciona; lo que faltaba era pedirlos al EMPEZAR y no al cerrar.
-- Eso es pantalla, no base: 129 de 129 checklists están en_progreso y ninguno
-- llega nunca a la puerta del cierre, por eso `medidores_por` está en 0 en las
-- 129 y los 83 valores que hay los arrastró el sistema, no una persona.
-- ============================================================================

BEGIN;

-- ── 1 · El tipo de respuesta del ítem ───────────────────────────────────────
ALTER TABLE checklist_template_v2_item
  ADD COLUMN IF NOT EXISTS tipo_respuesta TEXT NOT NULL DEFAULT 'ok_no_ok';

DO $mig$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_checklist_item_tipo_respuesta') THEN
        ALTER TABLE checklist_template_v2_item
          ADD CONSTRAINT chk_checklist_item_tipo_respuesta
          CHECK (tipo_respuesta IN ('ok_no_ok','texto','numero','fecha','seleccion','firma'));
    END IF;
END
$mig$;

COMMENT ON COLUMN checklist_template_v2_item.tipo_respuesta IS
'Qué se le pide al mecánico en este ítem. ok_no_ok es una verificación; el resto son campos de captura (MIG444).';

-- ── 2 · Los ocho que no son preguntas ───────────────────────────────────────
UPDATE checklist_template_v2_item SET tipo_respuesta = 'texto'     WHERE codigo IN ('B11.01','B11.02','B11.03');
UPDATE checklist_template_v2_item SET tipo_respuesta = 'numero'    WHERE codigo IN ('B11.04','B08.05');
UPDATE checklist_template_v2_item SET tipo_respuesta = 'seleccion' WHERE codigo = 'B11.05';
UPDATE checklist_template_v2_item SET tipo_respuesta = 'fecha'     WHERE codigo = 'B11.06';
UPDATE checklist_template_v2_item SET tipo_respuesta = 'firma'     WHERE codigo = 'B11.07';

-- El horómetro se anota en horas, y así la pantalla puede rotularlo.
UPDATE checklist_template_v2_item SET unidad = COALESCE(unidad, 'h')
 WHERE codigo IN ('B11.04','B08.05');

-- ── 3 · La vista lo publica ─────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_taller_ot_checklist_v3 AS
WITH inst AS (
         SELECT DISTINCT ON (checklist_v2_instance.ot_id) checklist_v2_instance.id,
            checklist_v2_instance.ot_id,
            checklist_v2_instance.activo_id,
            checklist_v2_instance.estado,
            checklist_v2_instance.arrastre_de_instance_id
           FROM checklist_v2_instance
          WHERE checklist_v2_instance.ot_id IS NOT NULL
          ORDER BY checklist_v2_instance.ot_id, checklist_v2_instance.fecha_inicio DESC
        )
 SELECT ii.id AS instance_item_id,
    inst.id AS instance_id,
    inst.ot_id,
    inst.estado AS instance_estado,
    COALESCE(ti.bloque::text, 'Tareas adicionales'::text) AS bloque,
    COALESCE(ti.bloque_orden, 999) AS bloque_orden,
    COALESCE(ti.orden, 9999) AS orden,
    ti.codigo,
    COALESCE(ii.descripcion_custom, ti.descripcion::character varying) AS descripcion,
    COALESCE(ii.tiempo_min_override, ti.tiempo_min::numeric) AS tiempo_min,
    ii.tiempo_min_override IS NOT NULL AS tiempo_editado,
    COALESCE(ti.requiere_foto, false) AS requiere_foto,
    COALESCE(ti.obligatorio, false) AS obligatorio,
    COALESCE(ti.critico, false) AS critico,
    ti.categoria_calidad,
    ii.resultado,
    ii.observacion,
    ii.foto_url,
    ii.excluido,
    ii.template_item_id IS NULL AS es_custom,
    ii.mediciones,
    ii.foto_urls,
    inst.arrastre_de_instance_id IS NOT NULL AS instance_arrastre,
    po.folio AS arrastre_ot_folio,
    COALESCE(pi.fecha_cierre, pi.fecha_inicio) AS arrastre_fecha,
    ii.arrastre_de_item_id IS NOT NULL AS arrastre,
    pii.observacion AS arrastre_observacion,
    pii.foto_url AS arrastre_foto_url,
    ti.tipo_respuesta,
    ii.valor_numerico
   FROM inst
     JOIN checklist_v2_instance_item ii ON ii.instance_id = inst.id
     LEFT JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
     LEFT JOIN checklist_v2_instance pi ON pi.id = inst.arrastre_de_instance_id
     LEFT JOIN ordenes_trabajo po ON po.id = pi.ot_id
     LEFT JOIN checklist_v2_instance_item pii ON pii.id = ii.arrastre_de_item_id;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE
    v_tipos TEXT;
    v_ok    INT;
BEGIN
    SELECT string_agg(codigo || '=' || tipo_respuesta, ', ' ORDER BY codigo) INTO v_tipos
      FROM checklist_template_v2_item
     WHERE codigo IN ('B11.01','B11.02','B11.03','B11.04','B11.05','B11.06','B11.07','B08.05');
    IF v_tipos IS NULL THEN RAISE EXCEPTION 'FALLO: no se encontraron los ítems B11/B08.05'; END IF;
    RAISE NOTICE 'tipos declarados: %', v_tipos;

    IF EXISTS (SELECT 1 FROM checklist_template_v2_item
                WHERE codigo IN ('B11.01','B11.02','B11.03','B11.04','B11.05','B11.06','B11.07','B08.05')
                  AND tipo_respuesta = 'ok_no_ok') THEN
        RAISE EXCEPTION 'FALLO: alguno de los ocho quedó como ok_no_ok';
    END IF;

    SELECT count(*) INTO v_ok FROM checklist_template_v2_item WHERE tipo_respuesta = 'ok_no_ok';
    RAISE NOTICE 'ítems que siguen siendo verificación OK/NO OK: %', v_ok;

    PERFORM tipo_respuesta, valor_numerico FROM v_taller_ot_checklist_v3 LIMIT 1;
    RAISE NOTICE 'la vista publica tipo_respuesta y valor_numerico';
END
$mig$;

COMMIT;
