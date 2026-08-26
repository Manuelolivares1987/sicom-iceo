-- ============================================================================
-- MIG411 · Fijar el vencimiento arregla también la emisión en 2099
-- ----------------------------------------------------------------------------
-- Al probar el flujo real de Control documental sobre el caso de la queja
-- —láminas del TGGF-57, propuesta 26-03-2026— reventó:
--
--     new row for relation "certificaciones" violates check constraint
--     "chk_certificaciones_fechas"     →   CHECK (fecha_vencimiento >= fecha_emision)
--
-- La causa: cuando se cargaron los archivos sin leer la fecha, se puso 2099 en
-- LAS DOS columnas. La fila del TGGF-57 dice emitido el 31-12-2099 y vence el
-- 31-12-2099. Al fijar el vencimiento real en 2026 quedaba anterior a su propia
-- emisión, y el CHECK —que está bien puesto— lo rechazaba.
--
-- ── QUÉ SE HACE CON LA EMISIÓN ──────────────────────────────────────────────
-- Las dos columnas son NOT NULL, así que no se puede dejar «no sé» en blanco.
-- El orden es:
--
--   1. La emisión que venga del lector o que escriba la persona.
--   2. Si no hay, y la que está guardada es el 2099, se usa el vencimiento
--      menos la vigencia típica del tipo —2 años, la regla acordada—.
--   3. Si la guardada es una fecha real anterior al vencimiento, se respeta.
--
-- El caso 2 es un supuesto, y queda dicho: `fecha_origen_nota` anota que la
-- emisión se dedujo. Es preferible a dejar el papel escondido en 2099 por no
-- poder llenar una casilla.
--
-- ── POR QUÉ APARECIÓ RECIÉN AHORA ───────────────────────────────────────────
-- Porque es la primera vez que algo intenta ESCRIBIR sobre esas filas. Se
-- llevan cargadas desde siempre; nadie había tratado de corregirlas.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_certificacion_fijar_fecha(
    p_certificacion_id uuid,
    p_vencimiento      date,
    p_emision          date DEFAULT NULL,
    p_origen           text DEFAULT 'manual',
    p_nota             text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_cert RECORD; v_emision DATE; v_nota TEXT; v_deducida BOOLEAN := FALSE;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento',
                     'supervisor','planificador','prevencionista','auditor_calidad') THEN
        RAISE EXCEPTION 'Tu rol (%) no puede fijar vencimientos de certificados', v_rol;
    END IF;
    IF p_origen NOT IN ('documento','regla_2_anios','manual') THEN
        RAISE EXCEPTION 'Origen de fecha desconocido: %', p_origen; END IF;
    IF p_vencimiento IS NULL THEN
        RAISE EXCEPTION 'Falta la fecha de vencimiento'; END IF;
    IF p_vencimiento >= '2099-01-01'::date THEN
        RAISE EXCEPTION 'Esa fecha es el marcador de «no vence». Si el papel no caduca, no le pongas fecha.'; END IF;

    SELECT * INTO v_cert FROM certificaciones WHERE id = p_certificacion_id;
    IF v_cert.id IS NULL THEN RAISE EXCEPTION 'El certificado no existe'; END IF;

    -- [MIG411] La emisión también quedó en 2099 al cargar los archivos. Como la
    -- columna es NOT NULL y el CHECK exige vencimiento >= emisión, hay que
    -- resolverla o la corrección no entra.
    v_emision := p_emision;
    IF v_emision IS NULL THEN
        IF v_cert.fecha_emision >= '2099-01-01'::date OR v_cert.fecha_emision > p_vencimiento THEN
            -- No se sabe cuándo se emitió: se deduce restando la vigencia
            -- acordada. Queda anotado que es un supuesto, no un dato.
            v_emision := (p_vencimiento - INTERVAL '2 years')::date;
            v_deducida := TRUE;
        ELSE
            v_emision := v_cert.fecha_emision;
        END IF;
    END IF;

    IF v_emision > p_vencimiento THEN
        RAISE EXCEPTION 'La emisión (%) no puede ser posterior al vencimiento (%)', v_emision, p_vencimiento;
    END IF;

    v_nota := p_nota;
    IF v_deducida THEN
        v_nota := COALESCE(v_nota || ' · ', '')
               || 'Fecha de emisión deducida (vencimiento menos 2 años): el archivo se cargó sin ella.';
    END IF;

    UPDATE certificaciones
       SET fecha_vencimiento  = p_vencimiento,
           fecha_emision      = v_emision,
           fecha_origen       = p_origen,
           fecha_origen_nota  = v_nota,
           updated_at         = NOW()
     WHERE id = p_certificacion_id;

    UPDATE certificacion_propuestas
       SET estado = 'aceptada', resuelto_por = v_user, resuelto_at = NOW(),
           nota_resolucion = v_nota
     WHERE certificacion_id = p_certificacion_id AND estado = 'pendiente';

    RETURN jsonb_build_object('success', true, 'vencimiento', p_vencimiento,
        'emision', v_emision, 'emision_deducida', v_deducida,
        'vencido', p_vencimiento < CURRENT_DATE, 'origen', p_origen);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_certificacion_fijar_fecha(uuid,date,date,text,text) TO authenticated;

COMMIT;
