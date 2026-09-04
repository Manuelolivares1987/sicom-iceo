-- ============================================================================
-- MIG511 · El papel del equipo acepta una DESCRIPCIÓN editable
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL (04-09-2026, reenviando a un usuario)
-- «En el control documental, que el tipo de documento se pueda modificar o
-- agregar la descripción. Al modificar sale una lista desplegable y no puedo
-- corregir el nombre del documento.»
--
-- LO QUE PASA
-- En el modal «Corregir», el nombre libre solo existe cuando el tipo es
-- «Otra» (regla MIG484: un otro sin nombre se confunde). Para cualquier tipo
-- del catálogo el nombre ES la etiqueta del catálogo y no hay dónde escribir
-- nada más. El usuario quiere precisar el documento («Certificado de
-- mantención — grúa pluma», «póliza flota liviana»...).
--
-- QUÉ SE HACE
-- La columna `certificaciones.notas` (ya existe y ya viaja en
-- v_certificacion_actual) pasa a ser la DESCRIPCIÓN del papel:
-- rpc_certificacion_editar gana p_descripcion, y la pantalla la muestra bajo
-- el nombre. El tipo sigue siendo el catálogo (eso ordena el control
-- documental); la descripción es libre y no cambia la categoría.
--
-- Firma nueva → DROP de la vieja (regla MIG471).
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS rpc_certificacion_editar(UUID, tipo_certificacion_enum, TEXT, DATE, DATE, TEXT, TEXT, BOOLEAN, TEXT, TEXT);

CREATE FUNCTION rpc_certificacion_editar(
    p_certificacion_id  UUID,
    p_tipo              tipo_certificacion_enum DEFAULT NULL,
    p_tipo_otro         TEXT    DEFAULT NULL,
    p_fecha_emision     DATE    DEFAULT NULL,
    p_fecha_vencimiento DATE    DEFAULT NULL,
    p_numero            TEXT    DEFAULT NULL,
    p_entidad           TEXT    DEFAULT NULL,
    p_bloqueante        BOOLEAN DEFAULT NULL,
    p_archivo_url       TEXT    DEFAULT NULL,
    p_motivo            TEXT    DEFAULT NULL,
    p_descripcion       TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user  UUID := auth.uid();
    v_rol   TEXT := fn_user_rol();
    v_antes JSONB;
    v_desp  JSONB;
    v_tipo  tipo_certificacion_enum;
    v_otro  TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_operaciones',
                     'jefe_mantenimiento','planificador','auditor_calidad') THEN
        RAISE EXCEPTION 'Sin permiso para corregir documentación de equipos. Rol: %', v_rol;
    END IF;

    SELECT to_jsonb(c) INTO v_antes FROM certificaciones c WHERE c.id = p_certificacion_id;
    IF v_antes IS NULL THEN RAISE EXCEPTION 'Ese documento no existe.'; END IF;
    IF (v_antes ->> 'anulado_at') IS NOT NULL THEN
        RAISE EXCEPTION 'Ese documento está anulado. Restáuralo antes de corregirlo.';
    END IF;

    v_tipo := COALESCE(p_tipo, (v_antes ->> 'tipo')::tipo_certificacion_enum);
    v_otro := COALESCE(NULLIF(btrim(COALESCE(p_tipo_otro,'')), ''), v_antes ->> 'tipo_otro');

    -- [MIG484] Sigue valiendo acá: un «otro» sin nombre se confunde con los demás.
    IF v_tipo = 'otra' AND length(btrim(COALESCE(v_otro,''))) < 3 THEN
        RAISE EXCEPTION 'Escribe qué certificado es. «Otro» sin nombre se confunde con los demás.';
    END IF;
    IF v_tipo <> 'otra' THEN v_otro := NULL; END IF;

    IF COALESCE(p_fecha_vencimiento, (v_antes ->> 'fecha_vencimiento')::date)
       < COALESCE(p_fecha_emision, (v_antes ->> 'fecha_emision')::date) THEN
        RAISE EXCEPTION 'El vencimiento no puede ser anterior a la emisión.';
    END IF;

    UPDATE certificaciones c
       SET tipo = v_tipo,
           tipo_otro = v_otro,
           fecha_emision       = COALESCE(p_fecha_emision, c.fecha_emision),
           fecha_vencimiento   = COALESCE(p_fecha_vencimiento, c.fecha_vencimiento),
           numero_certificado  = COALESCE(NULLIF(btrim(COALESCE(p_numero,'')),''), c.numero_certificado),
           entidad_certificadora = COALESCE(NULLIF(btrim(COALESCE(p_entidad,'')),''), c.entidad_certificadora),
           bloqueante          = COALESCE(p_bloqueante, c.bloqueante),
           archivo_url         = COALESCE(NULLIF(btrim(COALESCE(p_archivo_url,'')),''), c.archivo_url),
           -- [MIG511] La descripción del papel. NULL = no la tocó; texto vacío
           -- = la quiso borrar.
           notas               = CASE WHEN p_descripcion IS NULL THEN c.notas
                                      ELSE NULLIF(btrim(p_descripcion), '') END,
           fecha_origen        = CASE WHEN p_fecha_vencimiento IS NOT NULL
                                      THEN 'manual' ELSE c.fecha_origen END,
           vigencia_dudosa     = CASE WHEN p_fecha_vencimiento IS NOT NULL
                                      THEN FALSE ELSE c.vigencia_dudosa END,
           estado = (CASE WHEN COALESCE(p_fecha_vencimiento, c.fecha_vencimiento) <= CURRENT_DATE THEN 'vencido'
                          WHEN COALESCE(p_fecha_vencimiento, c.fecha_vencimiento) <= CURRENT_DATE + 30 THEN 'por_vencer'
                          ELSE 'vigente' END)::estado_documento_enum,
           updated_at = NOW()
     WHERE c.id = p_certificacion_id;

    SELECT to_jsonb(c) INTO v_desp FROM certificaciones c WHERE c.id = p_certificacion_id;

    INSERT INTO certificacion_ediciones (certificacion_id, accion, antes, despues, motivo, hecho_por)
    VALUES (p_certificacion_id, 'editar', v_antes, v_desp,
            NULLIF(btrim(COALESCE(p_motivo,'')),''), v_user);

    RETURN jsonb_build_object('success', TRUE,
        'etiqueta', fn_certificado_etiqueta(v_desp ->> 'tipo', v_desp ->> 'tipo_otro'));
END;
$$;

REVOKE ALL ON FUNCTION rpc_certificacion_editar(UUID, tipo_certificacion_enum, TEXT, DATE, DATE, TEXT, TEXT, BOOLEAN, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_certificacion_editar(UUID, tipo_certificacion_enum, TEXT, DATE, DATE, TEXT, TEXT, BOOLEAN, TEXT, TEXT, TEXT) TO authenticated;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_certificacion_editar';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: rpc_certificacion_editar quedó con % firmas', v_n; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='public' AND p.proname='rpc_certificacion_editar'
                      AND p.prosrc LIKE '%p_descripcion%') THEN
        RAISE EXCEPTION 'FALLO: la descripción no quedó en el RPC';
    END IF;
    RAISE NOTICE 'MIG511 OK · el papel acepta descripción editable (notas)';
END
$mig$;

COMMIT;
