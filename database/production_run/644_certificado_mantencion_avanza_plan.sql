-- MIG644 · El certificado de mantención avanza la pauta
-- ============================================================================
-- La última mantención se carga como documento «mantencion» (Control
-- Documental, ficha del equipo, bitácora), pero las bases de las pautas
-- (planes_mantenimiento.ultima_ejecucion_*) solo avanzaban al cerrar una OT
-- ligada al plan o a mano en Horas por equipo (MIG640). Resultado: equipos
-- con el servicio hecho y el papel cargado salían atrasados (DJKL-18,
-- FSLZ-67, TRDP-97…).
--
-- fn_mantencion_desde_certificado(cert):
--   · Horómetro a la fecha del papel: horometro_emision si es creíble; si no,
--     horas_uso_actual − horas GPS posteriores a esa fecha (misma escala que
--     usa v_plan_mantenimiento_estado). Sin GPS cerca de la fecha y con un
--     papel de más de 3 días, no se adivina: no se toca nada.
--   · No hace nada si las pautas ya tienen un servicio igual o posterior
--     (fecha ≥ la del papel u horómetro a menos de 30 h).
--   · Pauta hecha: la mayor de la escalera (≤ 2.400 h) vencida a ese
--     horómetro (con 50 h de adelanto); si ninguna estaba vencida, la que
--     venía. Los componentes mayores (eje, caja, overhaul, SM5/SM6) no se
--     infieren de un papel genérico.
--   · Se aplica como un cierre de OT (MIG513): la elegida y las menores con
--     base anterior parten de ese horómetro. Cada pauta movida queda en
--     plan_mantenimiento_registro_manual con certificacion_id.
-- Anular o corregir el papel deshace lo que ese papel movió (si nadie lo
-- movió después) y vuelve a calcular.
-- ============================================================================

BEGIN;

ALTER TABLE plan_mantenimiento_registro_manual
    ADD COLUMN IF NOT EXISTS certificacion_id UUID REFERENCES certificaciones(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS revertido_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS ix_plan_registro_manual_cert
    ON plan_mantenimiento_registro_manual (certificacion_id) WHERE certificacion_id IS NOT NULL;

-- Deshace lo que movió un certificado, solo en pautas que siguen tal cual.
CREATE OR REPLACE FUNCTION public.fn_mantencion_certificado_revertir(p_cert_id UUID)
 RETURNS INT
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    r   RECORD;
    v_n INT := 0;
BEGIN
    FOR r IN
        SELECT * FROM plan_mantenimiento_registro_manual
         WHERE certificacion_id = p_cert_id AND revertido_at IS NULL
    LOOP
        UPDATE planes_mantenimiento
           SET ultima_ejecucion_fecha = (r.antes->>'fecha')::DATE,
               ultima_ejecucion_horas = (r.antes->>'horas')::NUMERIC,
               ultima_ejecucion_km    = (r.antes->>'km')::NUMERIC,
               proxima_ejecucion_fecha = (r.antes->>'fecha')::DATE + coalesce(frecuencia_dias, 30),
               updated_at = NOW()
         WHERE id = r.plan_id
           AND ultima_ejecucion_fecha::DATE = r.fecha
           AND ultima_ejecucion_horas IS NOT DISTINCT FROM r.horas;
        IF FOUND THEN v_n := v_n + 1; END IF;
        UPDATE plan_mantenimiento_registro_manual SET revertido_at = NOW() WHERE id = r.id;
    END LOOP;
    RETURN v_n;
END $function$;

CREATE OR REPLACE FUNCTION public.fn_mantencion_desde_certificado(p_cert_id UUID)
 RETURNS JSONB
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    c        certificaciones;
    a        activos;
    v_hoy    DATE := (NOW() AT TIME ZONE 'America/Santiago')::DATE;
    F        DATE;
    H        NUMERIC;
    K        NUMERIC;
    v_gps    BOOLEAN;
    v_max_h  NUMERIC;
    v_max_f  DATE;
    v_plan   planes_mantenimiento;
    r        RECORD;
    v_nota   TEXT;
    v_movidas JSONB := '[]'::JSONB;
BEGIN
    SELECT * INTO c FROM certificaciones WHERE id = p_cert_id;
    IF NOT FOUND OR c.tipo::TEXT <> 'mantencion' OR c.anulado_at IS NOT NULL
       OR c.fecha_emision IS NULL OR c.fecha_emision > v_hoy THEN
        RETURN jsonb_build_object('aplicado', false, 'motivo', 'no aplica');
    END IF;
    F := c.fecha_emision;
    SELECT * INTO a FROM activos WHERE id = c.activo_id;
    IF coalesce(a.horas_uso_actual, 0) <= 0 THEN
        RETURN jsonb_build_object('aplicado', false, 'motivo', 'equipo sin horómetro');
    END IF;

    -- Horómetro y km a la fecha del papel.
    SELECT EXISTS (SELECT 1 FROM activo_horas_dia d
                    WHERE d.activo_id = a.id AND d.fecha BETWEEN F - 3 AND F + 3)
      INTO v_gps;
    IF v_gps THEN
        SELECT a.horas_uso_actual - coalesce(sum(greatest(d.horas, 0)), 0),
               CASE WHEN coalesce(a.kilometraje_actual, 0) > 0
                    THEN a.kilometraje_actual - coalesce(sum(greatest(d.km, 0)), 0) END
          INTO H, K
          FROM v_activo_horas_dia d
         WHERE d.activo_id = a.id AND d.fecha > F;
    ELSIF F >= v_hoy - 3 THEN
        H := a.horas_uso_actual;
        K := nullif(a.kilometraje_actual, 0);
    END IF;
    IF c.horometro_emision IS NOT NULL
       AND c.horometro_emision <= a.horas_uso_actual + 1
       AND (H IS NULL OR c.horometro_emision >= H - 100) THEN
        H := c.horometro_emision;
    END IF;
    IF H IS NULL THEN
        RETURN jsonb_build_object('aplicado', false, 'motivo', 'sin horómetro para esa fecha');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM planes_mantenimiento
                    WHERE activo_id = a.id AND activo_plan AND frecuencia_horas > 0) THEN
        RETURN jsonb_build_object('aplicado', false, 'motivo', 'sin pautas por horas');
    END IF;

    -- ¿Las pautas ya tienen ese servicio (o uno posterior)?
    SELECT max(nullif(ultima_ejecucion_horas, 0)), max(ultima_ejecucion_fecha::DATE)
      INTO v_max_h, v_max_f
      FROM planes_mantenimiento
     WHERE activo_id = a.id AND activo_plan AND frecuencia_horas > 0;
    IF v_max_f >= F OR H <= coalesce(v_max_h, 0) + 30 THEN
        RETURN jsonb_build_object('aplicado', false, 'motivo', 'las pautas ya tienen un servicio igual o posterior');
    END IF;

    -- La mayor vencida a ese horómetro; si ninguna, la que venía.
    SELECT pm.* INTO v_plan
      FROM planes_mantenimiento pm
     WHERE pm.activo_id = a.id AND pm.activo_plan
       AND pm.frecuencia_horas > 0 AND pm.frecuencia_horas <= 2400
       AND coalesce(nullif(pm.ultima_ejecucion_horas, 0), 0) + pm.frecuencia_horas <= H + 50
     ORDER BY pm.frecuencia_horas DESC
     LIMIT 1;
    IF NOT FOUND THEN
        SELECT pm.* INTO v_plan
          FROM planes_mantenimiento pm
         WHERE pm.activo_id = a.id AND pm.activo_plan
           AND pm.frecuencia_horas > 0 AND pm.frecuencia_horas <= 2400
         ORDER BY round(coalesce(nullif(pm.ultima_ejecucion_horas, 0), 0) + pm.frecuencia_horas), pm.frecuencia_horas DESC
         LIMIT 1;
    END IF;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('aplicado', false, 'motivo', 'sin pautas de escalera');
    END IF;

    v_nota := format('Certificado de mantención%s del %s (cargado en documentos): %s a las %s h',
                     CASE WHEN nullif(btrim(c.numero_certificado), '') IS NOT NULL
                          THEN ' N° ' || btrim(c.numero_certificado) ELSE '' END,
                     to_char(F, 'DD-MM-YYYY'), v_plan.nombre, round(H, 1));

    -- La elegida y las menores con base anterior (absorción MIG513).
    FOR r IN
        SELECT pm.* FROM planes_mantenimiento pm
         WHERE pm.activo_id = a.id AND pm.activo_plan
           AND (pm.id = v_plan.id
                OR (pm.tipo_plan IN ('por_horas','mixto') AND pm.frecuencia_horas > 0
                    AND pm.frecuencia_horas < v_plan.frecuencia_horas
                    AND coalesce(pm.ultima_ejecucion_horas, 0) < H))
    LOOP
        INSERT INTO plan_mantenimiento_registro_manual
               (plan_id, activo_id, fecha, horas, km, nota, antes, absorbidos, certificacion_id)
        VALUES (r.id, a.id, F, round(H, 1), round(K), v_nota,
                jsonb_build_object('fecha', r.ultima_ejecucion_fecha, 'horas', r.ultima_ejecucion_horas,
                                   'km', r.ultima_ejecucion_km),
                0, c.id);
        UPDATE planes_mantenimiento
           SET ultima_ejecucion_fecha = F,
               ultima_ejecucion_horas = round(H, 1),
               ultima_ejecucion_km    = coalesce(round(K), ultima_ejecucion_km),
               proxima_ejecucion_fecha = F + coalesce(frecuencia_dias, 30),
               updated_at = NOW()
         WHERE id = r.id;
        v_movidas := v_movidas || to_jsonb(r.nombre);
    END LOOP;

    RETURN jsonb_build_object('aplicado', true, 'pauta', v_plan.nombre, 'horas', round(H, 1),
                              'fecha', F, 'movidas', v_movidas);
END $function$;

CREATE OR REPLACE FUNCTION public.fn_certificacion_mantencion_avanza_plan()
 RETURNS TRIGGER
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.tipo IS NOT DISTINCT FROM OLD.tipo
           AND NEW.fecha_emision IS NOT DISTINCT FROM OLD.fecha_emision
           AND NEW.horometro_emision IS NOT DISTINCT FROM OLD.horometro_emision
           AND NEW.anulado_at IS NOT DISTINCT FROM OLD.anulado_at
           AND NEW.activo_id IS NOT DISTINCT FROM OLD.activo_id THEN
            RETURN NULL;
        END IF;
        PERFORM fn_mantencion_certificado_revertir(NEW.id);
    END IF;
    IF NEW.tipo::TEXT = 'mantencion' AND NEW.anulado_at IS NULL THEN
        PERFORM fn_mantencion_desde_certificado(NEW.id);
    END IF;
    RETURN NULL;
END $function$;

DROP TRIGGER IF EXISTS trg_certificacion_mantencion_avanza_plan ON certificaciones;
CREATE TRIGGER trg_certificacion_mantencion_avanza_plan
    AFTER INSERT OR UPDATE ON certificaciones
    FOR EACH ROW EXECUTE FUNCTION fn_certificacion_mantencion_avanza_plan();

REVOKE ALL ON FUNCTION fn_mantencion_desde_certificado(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_mantencion_certificado_revertir(UUID) FROM PUBLIC, anon, authenticated;

-- Papeles ya cargados: del más antiguo al más nuevo (cada uno ve lo que dejó el anterior).
DO $$
DECLARE r RECORD; v JSONB;
BEGIN
    FOR r IN
        SELECT c.id, coalesce(a.patente, a.codigo) pat
          FROM certificaciones c JOIN activos a ON a.id = c.activo_id
         WHERE c.tipo::TEXT = 'mantencion' AND c.anulado_at IS NULL
           AND c.fecha_emision >= CURRENT_DATE - 180
         ORDER BY c.fecha_emision, c.created_at
    LOOP
        v := fn_mantencion_desde_certificado(r.id);
        IF (v->>'aplicado')::BOOLEAN THEN
            RAISE NOTICE '% → %', r.pat, v;
        END IF;
    END LOOP;
END $$;

COMMIT;
