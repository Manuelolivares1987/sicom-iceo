-- MIG646 · El certificado de mantención dice a qué horómetro toca la próxima
-- ============================================================================
-- 23-10, Juan Pablo (SVBJ-55, FSLZ-67): el certificado de Pillado trae
-- «Horómetro última mantención» y «Horómetro próxima mantención», pero al
-- subirlo en Control Documental solo se pedían fechas. Para que el equipo
-- dejara de salir atrasado intentó «Cambiar próxima mantención» con el
-- horómetro de la mantención (1.619 / 2.166) en vez del de la próxima, y
-- Horas por equipo quedó en «+0 h atraso».
--
-- Ahora:
--   · rpc_certificado_mantencion_horometros(cert, h_mantencion, h_proxima)
--     guarda los dos horómetros en el papel (horometro_emision /
--     horometro_vence). El control documental ya los entiende (MIG514):
--     «vence a las 2.300 h · le quedan 134 h».
--   · fn_mantencion_desde_certificado: si el papel trae la próxima, manda
--     ella. La pauta es la de frecuencia = próxima − mantención (300 h → L1/SL);
--     si no calza ninguna, la menor de la escalera. Se reprograma con la regla
--     de «Cambiar próxima» (MIG642), ahora en fn_escalera_reprogramar_aplicar,
--     y cada pauta movida queda con certificacion_id para poder revertirla.
--   · Solo el papel de mantención más reciente del equipo reprograma.
--   · El trigger también reacciona a un cambio de horometro_vence.
-- ============================================================================

BEGIN;

-- ── 1 · El núcleo de «Cambiar próxima», sin permisos (lo llaman la RPC y el trigger)
CREATE OR REPLACE FUNCTION public.fn_escalera_reprogramar_aplicar(
    p_plan_id UUID, p_horas NUMERIC, p_nota TEXT, p_cert_id UUID DEFAULT NULL)
 RETURNS JSONB
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_plan   planes_mantenimiento;
    v_act    activos;
    v_hoy    DATE := (NOW() AT TIME ZONE 'America/Santiago')::DATE;
    v_ritmo  NUMERIC;
    F        NUMERIC;
    r        RECORD;
    v_base   NUMERIC;
    v_fecha  DATE;
    v_max    NUMERIC;
    v_n      INT := 0;
    v_cambios JSONB := '[]'::JSONB;
BEGIN
    SELECT * INTO v_plan FROM planes_mantenimiento WHERE id = p_plan_id AND activo_plan;
    IF NOT FOUND OR v_plan.frecuencia_horas IS NULL OR v_plan.frecuencia_horas <= 0 THEN
        RAISE EXCEPTION 'La pauta no existe o no es por horas.' USING ERRCODE = 'P0001';
    END IF;
    SELECT * INTO v_act FROM activos WHERE id = v_plan.activo_id;
    IF coalesce(v_act.horas_uso_actual, 0) <= 0 THEN
        RAISE EXCEPTION 'El equipo no tiene horómetro.' USING ERRCODE = 'P0001';
    END IF;
    F := v_plan.frecuencia_horas;
    IF p_horas IS NULL OR p_horas <= 0 THEN
        RAISE EXCEPTION 'Indica a qué horómetro toca.' USING ERRCODE = 'P0001';
    END IF;

    -- La base más alta (la menor pauta que se mueve) no puede quedar sobre el horómetro.
    SELECT max(CASE WHEN pm.id = p_plan_id THEN p_horas - F
                    WHEN pm.frecuencia_horas < F AND mod(F, pm.frecuencia_horas) = 0 THEN p_horas - pm.frecuencia_horas
                    WHEN pm.frecuencia_horas > F AND mod(pm.frecuencia_horas, F) = 0 THEN p_horas - F END)
      INTO v_max
      FROM planes_mantenimiento pm
     WHERE pm.activo_id = v_plan.activo_id AND pm.activo_plan
       AND pm.frecuencia_horas IS NOT NULL AND pm.frecuencia_horas > 0;
    IF v_max > v_act.horas_uso_actual THEN
        RAISE EXCEPTION 'La próxima puede tocar a lo más a las % h (horómetro actual % h).',
            round(v_act.horas_uso_actual + (p_horas - v_max), 1), round(v_act.horas_uso_actual, 1)
            USING ERRCODE = 'P0001';
    END IF;

    SELECT least(greatest(coalesce(horas_por_dia, 8), 2), 20) INTO v_ritmo
      FROM v_equipo_horas WHERE activo_id = v_plan.activo_id;
    v_ritmo := coalesce(v_ritmo, 8);

    FOR r IN
        SELECT pm.* FROM planes_mantenimiento pm
         WHERE pm.activo_id = v_plan.activo_id AND pm.activo_plan
           AND pm.frecuencia_horas IS NOT NULL AND pm.frecuencia_horas > 0
    LOOP
        v_base := CASE WHEN r.id = p_plan_id THEN p_horas - F
                       WHEN r.frecuencia_horas < F AND mod(F, r.frecuencia_horas) = 0 THEN p_horas - r.frecuencia_horas
                       WHEN r.frecuencia_horas > F AND mod(r.frecuencia_horas, F) = 0 THEN p_horas - F END;
        CONTINUE WHEN v_base IS NULL;
        v_fecha := v_hoy - ceil(greatest(v_act.horas_uso_actual - v_base, 0) / v_ritmo)::INT;

        INSERT INTO plan_mantenimiento_registro_manual
               (plan_id, activo_id, fecha, horas, km, nota, antes, absorbidos, certificacion_id)
        VALUES (r.id, r.activo_id, v_fecha, v_base, NULL,
                format('Escalera: próxima %s a las %s h · %s', v_plan.nombre, p_horas, btrim(p_nota)),
                jsonb_build_object('fecha', r.ultima_ejecucion_fecha, 'horas', r.ultima_ejecucion_horas,
                                   'km', r.ultima_ejecucion_km), 0, p_cert_id);

        UPDATE planes_mantenimiento
           SET ultima_ejecucion_horas = v_base,
               ultima_ejecucion_fecha = v_fecha,
               proxima_ejecucion_fecha = v_fecha + coalesce(frecuencia_dias, 30),
               updated_at = NOW()
         WHERE id = r.id;
        v_n := v_n + 1;
        v_cambios := v_cambios || jsonb_build_object('pauta', r.nombre, 'base', v_base, 'fecha', v_fecha);
    END LOOP;

    RETURN jsonb_build_object('pautas', v_n, 'pauta', v_plan.nombre, 'proxima_horas', p_horas,
                              'cambios', v_cambios);
END $function$;

REVOKE ALL ON FUNCTION fn_escalera_reprogramar_aplicar(UUID, NUMERIC, TEXT, UUID) FROM PUBLIC, anon, authenticated;

-- La RPC de «Cambiar próxima» queda como antes: permisos + motivo, y el núcleo.
CREATE OR REPLACE FUNCTION public.rpc_escalera_reprogramar(p_plan_id UUID, p_horas NUMERIC, p_nota TEXT)
 RETURNS JSONB
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT public.fn_tiene_permiso_modulo('mantenimiento', 'edit',
            ARRAY['administrador','auditor_calidad','jefe_mantenimiento','planificador']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para reprogramar mantenciones.' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_nota, ''))) < 5 THEN
        RAISE EXCEPTION 'Escribe el motivo (mínimo 5 caracteres).' USING ERRCODE = 'P0001';
    END IF;
    RETURN fn_escalera_reprogramar_aplicar(p_plan_id, p_horas, p_nota, NULL);
END $function$;

-- ── 2 · El certificado con «próxima mantención» reprograma la escalera ───────
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
    v_res    JSONB;
BEGIN
    SELECT * INTO c FROM certificaciones WHERE id = p_cert_id;
    IF NOT FOUND OR c.tipo::TEXT <> 'mantencion' OR c.anulado_at IS NOT NULL THEN
        RETURN jsonb_build_object('aplicado', false, 'motivo', 'no aplica');
    END IF;
    SELECT * INTO a FROM activos WHERE id = c.activo_id;

    -- [MIG646] El papel dice a qué horómetro toca la próxima: manda él.
    IF c.horometro_vence IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM certificaciones o
                    WHERE o.activo_id = c.activo_id AND o.tipo::TEXT = 'mantencion'
                      AND o.anulado_at IS NULL AND o.id <> c.id
                      AND (o.fecha_emision, o.created_at) > (c.fecha_emision, c.created_at)) THEN
            RETURN jsonb_build_object('aplicado', false, 'motivo', 'hay un certificado de mantención más nuevo');
        END IF;

        -- La pauta del período del papel (300 h → L1/SL); si no calza, la menor.
        SELECT pm.* INTO v_plan
          FROM planes_mantenimiento pm
         WHERE pm.activo_id = a.id AND pm.activo_plan
           AND pm.frecuencia_horas > 0 AND pm.frecuencia_horas <= 2400
         ORDER BY (c.horometro_emision IS NOT NULL
                   AND abs(pm.frecuencia_horas - (c.horometro_vence - c.horometro_emision)) <= 5) DESC,
                  pm.frecuencia_horas
         LIMIT 1;
        IF NOT FOUND THEN
            RETURN jsonb_build_object('aplicado', false, 'motivo', 'sin pautas de escalera');
        END IF;

        BEGIN
            v_res := fn_escalera_reprogramar_aplicar(
                v_plan.id, c.horometro_vence,
                format('certificado de mantención del %s%s', to_char(c.fecha_emision, 'DD-MM-YYYY'),
                       CASE WHEN c.horometro_emision IS NOT NULL
                            THEN ' (hecha a las ' || round(c.horometro_emision, 1) || ' h)' ELSE '' END),
                c.id);
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            RETURN jsonb_build_object('aplicado', false, 'motivo', SQLERRM);
        END;
        RETURN jsonb_build_object('aplicado', true) || v_res;
    END IF;

    -- ── Sin «próxima» en el papel: se infiere (MIG644, sin cambios) ──────────
    IF c.fecha_emision IS NULL OR c.fecha_emision > v_hoy THEN
        RETURN jsonb_build_object('aplicado', false, 'motivo', 'no aplica');
    END IF;
    F := c.fecha_emision;
    IF coalesce(a.horas_uso_actual, 0) <= 0 THEN
        RETURN jsonb_build_object('aplicado', false, 'motivo', 'equipo sin horómetro');
    END IF;

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

    SELECT max(nullif(ultima_ejecucion_horas, 0)), max(ultima_ejecucion_fecha::DATE)
      INTO v_max_h, v_max_f
      FROM planes_mantenimiento
     WHERE activo_id = a.id AND activo_plan AND frecuencia_horas > 0;
    IF v_max_f >= F OR H <= coalesce(v_max_h, 0) + 30 THEN
        RETURN jsonb_build_object('aplicado', false, 'motivo', 'las pautas ya tienen un servicio igual o posterior');
    END IF;

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

-- ── 3 · El trigger también mira horometro_vence ──────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_certificacion_mantencion_avanza_plan()
 RETURNS TRIGGER
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.tipo IS NOT DISTINCT FROM OLD.tipo
           AND NEW.fecha_emision IS NOT DISTINCT FROM OLD.fecha_emision
           AND NEW.horometro_emision IS NOT DISTINCT FROM OLD.horometro_emision
           AND NEW.horometro_vence IS NOT DISTINCT FROM OLD.horometro_vence
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

-- ── 4 · Escribir los horómetros del papel ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_certificado_mantencion_horometros(
    p_cert_id UUID, p_horas_mantencion NUMERIC, p_horas_proxima NUMERIC)
 RETURNS JSONB
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    c     certificaciones;
    v_rol TEXT := fn_user_rol();
    v_eq  RECORD;
    v_n   INT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_operaciones',
                     'jefe_mantenimiento','planificador','auditor_calidad') THEN
        RAISE EXCEPTION 'Sin permiso para actualizar documentación de equipos. Rol: %', v_rol;
    END IF;
    SELECT * INTO c FROM certificaciones WHERE id = p_cert_id;
    IF NOT FOUND OR c.anulado_at IS NOT NULL THEN
        RAISE EXCEPTION 'El documento no existe o está anulado.' USING ERRCODE = 'P0001';
    END IF;
    IF c.tipo::TEXT <> 'mantencion' THEN
        RAISE EXCEPTION 'Solo los certificados de mantención llevan horómetro de próxima.' USING ERRCODE = 'P0001';
    END IF;
    IF p_horas_proxima IS NULL OR p_horas_proxima <= 0 THEN
        RAISE EXCEPTION 'Escribe el horómetro de la próxima mantención.' USING ERRCODE = 'P0001';
    END IF;
    IF p_horas_mantencion IS NOT NULL AND p_horas_mantencion <= 0 THEN
        RAISE EXCEPTION 'El horómetro de la mantención no puede ser cero.' USING ERRCODE = 'P0001';
    END IF;
    IF p_horas_mantencion IS NOT NULL
       AND (p_horas_proxima <= p_horas_mantencion OR p_horas_proxima - p_horas_mantencion > 5000) THEN
        RAISE EXCEPTION 'La próxima (% h) tiene que ser mayor que la mantención (% h) y a menos de 5.000 h.',
            p_horas_proxima, p_horas_mantencion USING ERRCODE = 'P0001';
    END IF;

    UPDATE certificaciones
       SET horometro_emision = p_horas_mantencion,
           horometro_vence   = p_horas_proxima,
           updated_at = NOW()
     WHERE id = p_cert_id;

    SELECT count(*) INTO v_n FROM plan_mantenimiento_registro_manual
     WHERE certificacion_id = p_cert_id AND revertido_at IS NULL;
    SELECT proxima_pauta, horas_faltan, horometro INTO v_eq
      FROM v_equipo_horas WHERE activo_id = c.activo_id;

    RETURN jsonb_build_object('success', true, 'pautas_movidas', v_n,
                              'proxima_pauta', v_eq.proxima_pauta,
                              'horas_faltan', v_eq.horas_faltan,
                              'horometro', v_eq.horometro);
END $function$;

REVOKE ALL ON FUNCTION rpc_certificado_mantencion_horometros(UUID, NUMERIC, NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_certificado_mantencion_horometros(UUID, NUMERIC, NUMERIC) TO authenticated;

-- ── 5 · Los dos papeles que destaparon el problema ───────────────────────────
-- SVBJ-55: mantención 14-07-2026 a las 2.000,1 h → próxima 2.300 h.
-- FSLZ-67: mantención 20-10-2026 a las 1.619 h   → próxima 1.919 h.
UPDATE certificaciones c
   SET horometro_emision = v.h, horometro_vence = v.p, updated_at = NOW()
  FROM (VALUES ('SVBJ-55', DATE '2026-07-14', 2000.1, 2300),
               ('FSLZ-67', DATE '2026-10-20', 1619.0, 1919)) v(pat, f, h, p),
       activos a
 WHERE a.patente = v.pat AND c.activo_id = a.id AND c.tipo::TEXT = 'mantencion'
   AND c.anulado_at IS NULL AND c.fecha_emision = v.f;

SELECT patente, proxima_pauta, horometro, horas_faltan, estado_preventiva, fecha_estimada
  FROM v_equipo_horas WHERE patente IN ('SVBJ-55', 'FSLZ-67');

COMMIT;
