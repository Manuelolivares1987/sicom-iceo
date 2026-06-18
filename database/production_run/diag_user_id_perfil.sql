WITH tpl AS (SELECT id FROM checklist_template_v2 WHERE momento_uso='recepcion_devolucion' AND activo=true ORDER BY version DESC LIMIT 1)
SELECT jsonb_build_object(
  'items_aljibe_agua', (SELECT COUNT(*) FROM checklist_template_v2_item i, tpl
        WHERE i.template_id=tpl.id AND 'aljibe_agua' = ANY(i.tipos_equipamiento)),
  'items_aljibe_combustible', (SELECT COUNT(*) FROM checklist_template_v2_item i, tpl
        WHERE i.template_id=tpl.id AND 'aljibe_combustible' = ANY(i.tipos_equipamiento)),
  'tipos_equip_en_template', (SELECT jsonb_object_agg(te,n) FROM (
        SELECT te, COUNT(*) n FROM checklist_template_v2_item i, tpl, unnest(i.tipos_equipamiento) te
        WHERE i.template_id=tpl.id GROUP BY te ORDER BY te) s)
) AS r;
