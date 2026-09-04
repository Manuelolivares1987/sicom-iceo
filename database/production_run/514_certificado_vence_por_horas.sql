-- ============================================================================
-- MIG514 · El certificado de mantención vence POR HORAS, no por fecha
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL (04-09-2026)
-- «Se está ingresando un certificado al sistema de mantenimiento y la
-- vigencia de los certificados de mantención es por horas, tal como lo hemos
-- conversado: entonces no debo colocar fecha — para que en control documental
-- lo modifiques.»
--
-- Coherente con la definición compañía (MIG510): la mantención va cada 300
-- horas de horómetro. Un certificado que dice «la mantención está al día»
-- vale hasta la PRÓXIMA pauta — o sea, horómetro de emisión + 300 h — no
-- hasta una fecha del calendario que el camión puede alcanzar parado o
-- reventar en una semana de doble turno.
--
-- QUÉ SE HACE
--  · Al emitir: se puede declarar horómetro de emisión + vigencia en horas
--    (300 por defecto en la pantalla). La fecha «vale hasta» queda como
--    alternativa para los certificados de calendario (tacógrafo).
--  · El papel del equipo guarda horometro_vence, y el control documental
--    calcula el semáforo contra el horómetro REAL del equipo
--    (activos.horas_uso_actual): vencido si ya lo pasó, por vencer si le
--    quedan ≤ 50 h (≈ una semana de faena).
-- ============================================================================

BEGIN;

-- ── 1 · Columnas ────────────────────────────────────────────────────────────
ALTER TABLE activo_certificados
  ADD COLUMN IF NOT EXISTS horometro_emision NUMERIC,
  ADD COLUMN IF NOT EXISTS vigencia_horas    NUMERIC;
ALTER TABLE certificaciones
  ADD COLUMN IF NOT EXISTS horometro_emision NUMERIC,
  ADD COLUMN IF NOT EXISTS horometro_vence   NUMERIC;

COMMENT ON COLUMN certificaciones.horometro_vence IS
'El papel vence cuando el equipo alcanza este horómetro (vigencia por horas, MIG514). Si está, manda sobre la fecha.';

-- ── 2 · El RPC de emisión acepta la vigencia por horas ──────────────────────
DROP FUNCTION IF EXISTS public.rpc_emitir_certificado_activo(uuid, text, jsonb, text, text, text, uuid, date, text, uuid, date);

CREATE FUNCTION public.rpc_emitir_certificado_activo(
    p_activo_id uuid, p_tipo_codigo text, p_datos jsonb,
    p_operador_nombre text, p_firma_operador_url text, p_firma_jefe_url text,
    p_operador_tecnico_id uuid DEFAULT NULL, p_fecha_emision date DEFAULT NULL,
    p_ciudad text DEFAULT NULL, p_ot_id uuid DEFAULT NULL,
    p_vence_el date DEFAULT NULL,
    p_horometro_emision NUMERIC DEFAULT NULL,
    p_vigencia_horas    NUMERIC DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_jefe TEXT; v_nc INT; v_numero INT; v_id UUID; v_fecha DATE;
    v_horo NUMERIC;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Rol % no autorizado para emitir certificados', v_rol;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM certificado_tipos WHERE codigo = p_tipo_codigo AND activo) THEN
        RAISE EXCEPTION 'Tipo de certificado "%" no existe', p_tipo_codigo;
    END IF;
    IF COALESCE(TRIM(p_operador_nombre),'') = '' THEN
        RAISE EXCEPTION 'Indica el operador que realizó el trabajo';
    END IF;
    IF COALESCE(TRIM(p_firma_operador_url),'') = '' OR COALESCE(TRIM(p_firma_jefe_url),'') = '' THEN
        RAISE EXCEPTION 'El certificado requiere la firma del operador Y la del jefe de taller';
    END IF;

    -- GATE: el equipo debe haber resuelto todas sus No Conformidades.
    SELECT COUNT(*) INTO v_nc FROM no_conformidades
     WHERE activo_id = p_activo_id AND COALESCE(resuelto, false) = false;
    IF v_nc > 0 THEN
        RAISE EXCEPTION 'El equipo tiene % No Conformidad(es) abiertas — deben resolverse todas antes de emitir certificados.', v_nc;
    END IF;

    v_fecha := COALESCE(p_fecha_emision, CURRENT_DATE);
    IF p_vence_el IS NOT NULL AND p_vence_el < v_fecha THEN
        RAISE EXCEPTION 'El vencimiento no puede ser anterior a la emisión.';
    END IF;

    -- [MIG514] Vigencia por horas: el horómetro de emisión es obligatorio
    -- (si no viene, se toma el del maestro — y si tampoco está, se exige).
    IF p_vigencia_horas IS NOT NULL THEN
        IF p_vigencia_horas <= 0 THEN
            RAISE EXCEPTION 'La vigencia en horas tiene que ser mayor que cero.';
        END IF;
        v_horo := COALESCE(p_horometro_emision,
                           (SELECT a.horas_uso_actual FROM activos a WHERE a.id = p_activo_id));
        IF v_horo IS NULL THEN
            RAISE EXCEPTION 'Anota el horómetro del equipo: la vigencia por horas se cuenta desde ahí.';
        END IF;
    END IF;

    SELECT nombre_completo INTO v_jefe FROM usuarios_perfil WHERE id = v_user;

    PERFORM pg_advisory_xact_lock(hashtext('cert_activo_' || p_activo_id::text));
    SELECT COALESCE(max(numero), 0) + 1 INTO v_numero
      FROM activo_certificados WHERE activo_id = p_activo_id;

    INSERT INTO activo_certificados (
        activo_id, tipo_codigo, numero, fecha_emision, ciudad, datos,
        operador_tecnico_id, operador_nombre, firma_operador_url,
        jefe_nombre, firma_jefe_url, ot_id, vence_el,
        horometro_emision, vigencia_horas, created_by)
    VALUES (
        p_activo_id, p_tipo_codigo, v_numero, v_fecha,
        COALESCE(NULLIF(TRIM(p_ciudad),''), 'Coquimbo'), COALESCE(p_datos, '{}'::jsonb),
        p_operador_tecnico_id, TRIM(p_operador_nombre), p_firma_operador_url,
        COALESCE(v_jefe, '—'), p_firma_jefe_url, p_ot_id, p_vence_el,
        v_horo, p_vigencia_horas, v_user)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'numero', v_numero,
        'horometro_vence', CASE WHEN p_vigencia_horas IS NOT NULL THEN v_horo + p_vigencia_horas END);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_emitir_certificado_activo(
    uuid, text, jsonb, text, text, text, uuid, date, text, uuid, date, NUMERIC, NUMERIC) TO authenticated;

-- ── 3 · El trigger que crea el papel entiende las horas ─────────────────────
CREATE OR REPLACE FUNCTION public.fn_certificado_activo_renueva_papel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_papel TEXT; v_meses INT; v_vence DATE; v_origen TEXT; v_nota TEXT;
        v_h_vence NUMERIC;
BEGIN
    SELECT tipo_papel INTO v_papel
      FROM certificado_tipo_equivale WHERE tipo_codigo = NEW.tipo_codigo;
    IF v_papel IS NULL THEN RETURN NEW; END IF;

    -- [MIG514] Vigencia POR HORAS: el papel vence a un horómetro, no a una
    -- fecha. El semáforo lo calcula el control documental contra el horómetro
    -- real del equipo.
    IF NEW.vigencia_horas IS NOT NULL AND NEW.horometro_emision IS NOT NULL THEN
        v_h_vence := NEW.horometro_emision + NEW.vigencia_horas;
        INSERT INTO certificaciones (
            activo_id, tipo, fecha_emision, fecha_vencimiento, numero_certificado,
            entidad_certificadora, bloqueante, archivo_url,
            fecha_origen, fecha_origen_nota, notas,
            horometro_emision, horometro_vence, created_by)
        VALUES (
            -- fecha_vencimiento es NOT NULL: va el centinela 2099 («sin fecha»),
            -- pero el semáforo evalúa el horómetro ANTES que la fecha.
            NEW.activo_id, v_papel::tipo_certificacion_enum, NEW.fecha_emision, '2099-12-31'::date,
            lpad(NEW.numero::text, 2, '0'), 'PILLADO Y COMPAÑÍA LTDA.', FALSE,
            '/certificado/' || NEW.id,
            NULL,
            'MIG514 · certificado Nº ' || lpad(NEW.numero::text, 2, '0')
              || ': vigencia por horas — vale ' || NEW.vigencia_horas || ' h desde el horómetro '
              || NEW.horometro_emision || ' (vence a las ' || v_h_vence || ' h).',
            'Certificado emitido desde SICOM, firmado por ' || COALESCE(NEW.operador_nombre,'—')
              || ' y ' || COALESCE(NEW.jefe_nombre,'—') || '. Vigencia por horas.',
            NEW.horometro_emision, v_h_vence, NEW.created_by);
        RETURN NEW;
    END IF;

    SELECT meses INTO v_meses FROM certificado_vigencia_estandar WHERE tipo = v_papel;

    IF NEW.vence_el IS NOT NULL THEN
        v_vence  := NEW.vence_el;
        v_origen := 'manual';
        v_nota   := 'MIG436 · certificado Nº ' || lpad(NEW.numero::text, 2, '0')
                 || ': vigencia indicada por quien lo emitió, hasta '
                 || to_char(NEW.vence_el,'DD-MM-YYYY') || '.';
    ELSIF v_meses IS NOT NULL THEN
        v_vence  := (NEW.fecha_emision + (v_meses || ' months')::INTERVAL)::date;
        v_origen := 'documento';
        v_nota   := 'MIG436 · certificado Nº ' || lpad(NEW.numero::text, 2, '0')
                 || ': vence ' || to_char(v_vence,'DD-MM-YYYY')
                 || ', ' || v_meses || ' meses desde la emisión.';
    ELSE
        v_vence  := '2099-12-31'::date;
        v_origen := NULL;
        v_nota   := 'MIG436 · certificado Nº ' || lpad(NEW.numero::text, 2, '0')
                 || '. Falta indicar hasta cuándo vale: nadie lo declaró al emitirlo '
                 || 'y no consta cuánto dura este certificado.';
    END IF;

    INSERT INTO certificaciones (
        activo_id, tipo, fecha_emision, fecha_vencimiento, numero_certificado,
        entidad_certificadora, bloqueante, archivo_url,
        fecha_origen, fecha_origen_nota, notas, created_by)
    VALUES (
        NEW.activo_id, v_papel::tipo_certificacion_enum, NEW.fecha_emision, v_vence,
        lpad(NEW.numero::text, 2, '0'), 'PILLADO Y COMPAÑÍA LTDA.', FALSE,
        '/certificado/' || NEW.id,
        v_origen, v_nota,
        'Certificado emitido desde SICOM, firmado por ' || COALESCE(NEW.operador_nombre,'—')
          || ' y ' || COALESCE(NEW.jefe_nombre,'—') || '.',
        NEW.created_by);

    RETURN NEW;
END $function$;

-- ── 4 · El semáforo por horas en la vista madre ─────────────────────────────
CREATE OR REPLACE VIEW v_certificacion_actual AS
 SELECT DISTINCT ON (c.activo_id, fn_certificado_clave(c.tipo::text, c.tipo_otro))
    c.id,
    c.activo_id,
    c.tipo,
    c.numero_certificado,
    c.entidad_certificadora,
    c.fecha_emision,
    c.fecha_vencimiento,
    c.estado,
    c.archivo_url,
    c.notas,
    c.bloqueante,
    c.created_at,
    c.updated_at,
    c.created_by,
        CASE
            -- [MIG514] Vigencia por horas: manda el horómetro real del equipo.
            WHEN c.horometro_vence IS NOT NULL THEN
                CASE WHEN COALESCE(act.horas_uso_actual, 0) >= c.horometro_vence THEN 'vencido'::text
                     WHEN COALESCE(act.horas_uso_actual, 0) >= c.horometro_vence - 50 THEN 'por_vencer'::text
                     ELSE 'vigente'::text END
            WHEN c.fecha_origen = 'documento_sin_vencimiento'::text THEN 'no_aplica'::text
            WHEN c.vigencia_dudosa THEN 'sin_fecha'::text
            WHEN (c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= '2099-01-01'::date) AND c.archivo_url IS NOT NULL AND COALESCE(tv.vence, false) THEN 'sin_fecha'::text
            WHEN c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= '2099-01-01'::date THEN 'no_aplica'::text
            WHEN c.fecha_vencimiento < CURRENT_DATE THEN 'vencido'::text
            WHEN c.fecha_vencimiento <= (CURRENT_DATE + 30) THEN 'por_vencer'::text
            ELSE 'vigente'::text
        END::estado_documento_enum AS estado_real,
        CASE
            WHEN c.vigencia_dudosa THEN NULL::integer
            ELSE c.fecha_vencimiento - CURRENT_DATE
        END AS dias_restantes,
    c.tipo_otro,
    fn_certificado_etiqueta(c.tipo::text, c.tipo_otro) AS etiqueta,
    fn_certificado_clave(c.tipo::text, c.tipo_otro)    AS doc_clave,
    -- [MIG514] La vigencia por horas, publicada.
    c.horometro_emision,
    c.horometro_vence,
    CASE WHEN c.horometro_vence IS NOT NULL
         THEN round(c.horometro_vence - COALESCE(act.horas_uso_actual, 0))
    END AS horas_restantes
   FROM certificaciones c
     LEFT JOIN v_certificado_tipo_vence tv ON tv.tipo = c.tipo
     LEFT JOIN activos act ON act.id = c.activo_id
  -- [MIG486] Un papel anulado no compite por ser el vigente.
  WHERE c.anulado_at IS NULL
  ORDER BY c.activo_id, fn_certificado_clave(c.tipo::text, c.tipo_otro),
           c.created_at DESC, c.fecha_vencimiento DESC NULLS LAST;

-- ── 5 · Y en la vista del control documental ────────────────────────────────
CREATE OR REPLACE VIEW v_control_documental AS
 SELECT a.id AS activo_id,
    COALESCE(a.patente, a.codigo) AS patente,
    a.codigo AS activo_codigo,
    a.nombre AS activo_nombre,
    a.tipo::text AS activo_tipo,
    a.estado::text AS activo_estado,
    v.id AS certificacion_id,
    v.tipo::text AS tipo,
    v.numero_certificado,
    v.entidad_certificadora,
    v.fecha_emision,
    v.fecha_vencimiento,
    v.estado_real::text AS estado,
    v.dias_restantes,
    v.archivo_url,
    v.bloqueante,
    c.fecha_origen,
    p.id AS propuesta_id,
    p.vencimiento_propuesto,
    p.emision_propuesta,
    p.confianza AS propuesta_confianza,
    p.regla AS propuesta_regla,
    p.evidencia AS propuesta_evidencia,
    p.vencimiento_propuesto IS NOT NULL AND p.vencimiento_propuesto < CURRENT_DATE AS propuesta_vencida,
    fn_certificado_tipo_permanente(v.tipo::text) AS tipo_no_caduca,
    c.vigencia_observacion,
    c.vigencia_dudosa_nota,
    c.tipo_otro,
    fn_certificado_etiqueta(v.tipo::text, c.tipo_otro) AS etiqueta,
    c.notas AS descripcion,
    -- [MIG514] Vigencia por horas.
    v.horometro_emision,
    v.horometro_vence,
    v.horas_restantes
   FROM v_certificacion_actual v
     JOIN activos a ON a.id = v.activo_id
     JOIN certificaciones c ON c.id = v.id
     LEFT JOIN certificacion_propuestas p ON p.certificacion_id = v.id AND p.estado = 'pendiente'::text
  WHERE a.estado <> 'dado_baja'::estado_activo_enum;

-- ── Verificación (con emisión de prueba, que se borra) ──────────────────────
DO $mig$
DECLARE v_activo UUID; v_id UUID; v_estado TEXT; v_hr NUMERIC;
BEGIN
    SELECT id INTO v_activo FROM activos
     WHERE horas_uso_actual IS NOT NULL AND horas_uso_actual > 100 AND fecha_baja IS NULL LIMIT 1;

    INSERT INTO activo_certificados (activo_id, tipo_codigo, numero, fecha_emision, ciudad, datos,
                                     operador_nombre, firma_operador_url, jefe_nombre, firma_jefe_url,
                                     horometro_emision, vigencia_horas, created_by)
    SELECT v_activo, 'ultima_mantencion', 997, CURRENT_DATE, 'Coquimbo', '{}'::jsonb,
           'prueba', 'x', 'prueba', 'x', a.horas_uso_actual, 300,
           (SELECT id FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1)
      FROM activos a WHERE a.id = v_activo
    RETURNING id INTO v_id;

    SELECT estado, horas_restantes INTO v_estado, v_hr
      FROM v_control_documental
     WHERE certificacion_id = (SELECT id FROM certificaciones WHERE archivo_url = '/certificado/' || v_id);
    RAISE NOTICE 'certificado por horas de prueba → estado=% · le quedan % h (esperado: vigente, ~300)', v_estado, v_hr;
    IF v_estado IS DISTINCT FROM 'vigente' OR v_hr IS NULL OR v_hr < 240 THEN
        RAISE EXCEPTION 'FALLO: el semáforo por horas no calzó (estado=%, restantes=%)', v_estado, v_hr;
    END IF;

    DELETE FROM certificaciones WHERE archivo_url = '/certificado/' || v_id;
    DELETE FROM activo_certificados WHERE id = v_id;
    RAISE NOTICE 'MIG514 OK · certificado de mantención vence por horas';
END
$mig$;

COMMIT;
