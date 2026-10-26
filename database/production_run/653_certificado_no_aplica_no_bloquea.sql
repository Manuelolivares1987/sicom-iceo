-- 653 — Un registro «No aplica» de mantención ya no bloquea el papel real (2026-10-26).
--
-- TGGF-58: en Control Documental se cargó el certificado del 12-08 (hecha a
-- las 1.102 h, próxima 1.502 h) y la pauta no se movió. fn_mantencion_desde_
-- certificado (MIG646) solo aplica el papel de mantención MÁS NUEVO, y el
-- equipo tenía un registro «No aplica» de julio con fecha 31-12-2099 (así se
-- marcaba «este documento no corresponde»). Por fecha, ese era «el más nuevo»
-- y el papel real se descartaba sin aviso. Hay 16 registros así en la flota;
-- hoy le pasó también a TRST-57, TRSS-16 y TTPC-47.
--
-- Ahora un registro «No aplica» o con fecha de emisión futura no cuenta como
-- certificado más nuevo. Y se reprocesan los papeles de mantención con
-- horómetro de próxima que no movieron su pauta.

DO $$
DECLARE v_def text := pg_get_functiondef('public.fn_mantencion_desde_certificado(uuid)'::regprocedure);
        v_old text := 'AND o.anulado_at IS NULL AND o.id <> c.id';
BEGIN
    IF position('o.estado::TEXT <> ''no_aplica''' IN v_def) > 0 THEN RETURN; END IF;
    IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
        RAISE EXCEPTION 'MIG653: no se encontró la condición del certificado más nuevo';
    END IF;
    EXECUTE replace(v_def, v_old,
        v_old || E'\n                      AND o.estado::TEXT <> ''no_aplica'' AND o.fecha_emision <= (NOW() AT TIME ZONE ''America/Santiago'')::DATE');
END $$;

-- Reprocesar: el papel de mantención más nuevo (válido) de cada equipo, con
-- horómetro de próxima, sin pauta movida por él y con un «No aplica» al lado.
CREATE TEMP TABLE _mig653 (patente text, cert_id uuid, proxima numeric, resultado jsonb) ON COMMIT DROP;

DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT DISTINCT ON (c.activo_id) c.id, a.patente, c.horometro_vence
          FROM certificaciones c
          JOIN activos a ON a.id = c.activo_id
         WHERE c.tipo::TEXT = 'mantencion' AND c.anulado_at IS NULL
           AND c.estado::TEXT <> 'no_aplica' AND c.fecha_emision <= CURRENT_DATE
         ORDER BY c.activo_id, c.fecha_emision DESC, c.created_at DESC
    LOOP
        CONTINUE WHEN r.horometro_vence IS NULL;
        -- Solo los que bloqueó un «No aplica» / fecha futura: el resto ya pasó
        -- por la regla y reprocesarlo podría pisar una OT cerrada después.
        CONTINUE WHEN NOT EXISTS (SELECT 1 FROM certificaciones o
                                   WHERE o.activo_id = (SELECT activo_id FROM certificaciones WHERE id = r.id)
                                     AND o.tipo::TEXT = 'mantencion' AND o.anulado_at IS NULL
                                     AND (o.estado::TEXT = 'no_aplica' OR o.fecha_emision > CURRENT_DATE));
        CONTINUE WHEN EXISTS (SELECT 1 FROM plan_mantenimiento_registro_manual m
                               WHERE m.certificacion_id = r.id AND m.revertido_at IS NULL);
        INSERT INTO _mig653 VALUES (r.patente, r.id, r.horometro_vence, fn_mantencion_desde_certificado(r.id));
    END LOOP;
END $$;

SELECT json_agg(json_build_object(
         'patente', m.patente, 'proxima_papel', m.proxima,
         'aplicado', m.resultado->>'aplicado', 'motivo', m.resultado->>'motivo', 'pauta', m.resultado->>'pauta',
         'horometro', e.horometro, 'proxima_pauta', e.proxima_pauta, 'horas_faltan', e.horas_faltan)
       ORDER BY m.patente) AS resultado
  FROM _mig653 m
  JOIN certificaciones c ON c.id = m.cert_id
  LEFT JOIN v_equipo_horas e ON e.activo_id = c.activo_id;
