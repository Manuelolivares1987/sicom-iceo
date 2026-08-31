-- ============================================================================
-- MIG467 · La firma de quien firma, en el certificado
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- «Necesito que en el certificado de hermeticidad salga mi firma, dado que
-- firmo yo como Manuel Olivares».
--
-- Hoy el certificado dibuja una raya y debajo el nombre, el título y el cargo:
-- se imprime y se firma a mano. Para un papel que se presenta ante terceros eso
-- funciona, pero obliga a imprimir y escanear cada vez que lo piden en digital.
--
-- LO QUE YA EXISTÍA, Y QUE CASI DUPLICO
-- La primera versión de esta migración creó una columna, un RPC para guardar la
-- firma y dos políticas de storage. Al verificarla apareció que TODO eso ya
-- estaba desde MIG396, para que el vale de bodega saliera firmado:
--
--     usuarios_perfil.firma_url          la columna, ya existía
--     rpc_guardar_mi_firma(p_firma_url)  el que guarda, ya existía
--     subirFirmaTicket()                 la subida al bucket de firmas
--
-- Dejar dos puertas para lo mismo es peor que no tener ninguna: la mitad del
-- sistema guardaría la firma en un lado y la otra mitad la buscaría en otro. Se
-- borra lo que agregué de más y se usa lo que ya estaba.
--
-- LO QUE SÍ FALTABA
-- Nadie leía la firma de vuelta. Había cómo guardarla y ningún modo de
-- preguntarla. Eso es lo único que agrega esta migración, más la fecha en que
-- se actualizó —una firma sin fecha no se puede auditar—.
-- ============================================================================

BEGIN;

-- ── 1 · Sólo faltaba saber desde cuándo ─────────────────────────────────────
ALTER TABLE usuarios_perfil
  ADD COLUMN IF NOT EXISTS firma_actualizada_at TIMESTAMPTZ;

COMMENT ON COLUMN usuarios_perfil.firma_url IS
    'Firma manuscrita de la persona, para los documentos que emite (vale de '
    'bodega desde MIG396, certificados desde MIG467). La sube cada uno sobre su '
    'propia cuenta: la firma de otro no la carga nadie más.';

-- ── 2 · Borrar la puerta de más que abrí ────────────────────────────────────
DROP FUNCTION IF EXISTS rpc_set_mi_firma(TEXT);
DROP POLICY IF EXISTS storage_firma_propia_insert ON storage.objects;
DROP POLICY IF EXISTS storage_firma_propia_update ON storage.objects;

-- ── 3 · El que ya guardaba, ahora deja fecha ────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_guardar_mi_firma(p_firma_url TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_url  TEXT := NULLIF(TRIM(COALESCE(p_firma_url,'')),'');
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    -- Sólo sobre la propia cuenta: la firma de otro no se carga por nadie más,
    -- o deja de ser una firma.
    UPDATE usuarios_perfil
       SET firma_url = v_url,
           -- [MIG467] Una firma sin fecha no se puede auditar: si mañana alguien
           -- discute un certificado, hay que poder decir desde cuándo es ésa.
           firma_actualizada_at = CASE WHEN v_url IS NULL THEN NULL ELSE NOW() END
     WHERE id = v_user;
    IF NOT FOUND THEN RAISE EXCEPTION 'El perfil no existe'; END IF;
    RETURN jsonb_build_object('success', true, 'guardada', v_url IS NOT NULL);
END;
$$;

-- ── 4 · Y ahora se puede preguntar ──────────────────────────────────────────
--
-- Con esto el certificado se abre sabiendo quién firma y con qué firma, sin que
-- nadie tipee su nombre ni su cargo.
CREATE OR REPLACE FUNCTION rpc_mi_firma()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'nombre',         up.nombre_completo,
        'cargo',          up.cargo,
        'firma_url',      up.firma_url,
        'actualizada_at', up.firma_actualizada_at)
      FROM usuarios_perfil up WHERE up.id = auth.uid();
$$;

REVOKE ALL ON FUNCTION rpc_guardar_mi_firma(TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_mi_firma() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_guardar_mi_firma(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_mi_firma() TO authenticated;

-- ── 5 · La firma se guarda CON el certificado ───────────────────────────────
--
-- No basta con tenerla en el perfil. Si el año que viene la persona cambia su
-- firma, el certificado ya emitido tiene que seguir mostrando la que usó ese
-- día: es un documento, no una pantalla. Así que se congela en la fila, igual
-- que el nombre y el cargo del firmante.
ALTER TABLE certificados_emitidos
  ADD COLUMN IF NOT EXISTS firmante_firma_url TEXT;

CREATE OR REPLACE FUNCTION public.rpc_emitir_certificado(p_datos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_rol TEXT; v_activo UUID; v_tipo TEXT; v_prueba DATE; v_meses INT;
    v_vence DATE; v_anio INT; v_num INT; v_folio TEXT;
    v_cert_id UUID; v_emitido_id UUID; v_patente TEXT;
BEGIN
    SELECT rol INTO v_rol FROM usuarios_perfil WHERE id = auth.uid();
    IF v_rol IS NULL OR v_rol NOT IN ('administrador','jefe_operaciones','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'No tienes permiso para emitir certificados.';
    END IF;

    v_activo := (p_datos->>'activo_id')::uuid;
    v_tipo   := COALESCE(p_datos->>'tipo', 'hermeticidad');
    v_prueba := (p_datos->>'fecha_prueba')::date;
    IF v_activo IS NULL OR v_prueba IS NULL THEN
        RAISE EXCEPTION 'Falta el equipo o la fecha de la prueba.';
    END IF;
    IF v_prueba > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de la prueba no puede estar en el futuro.';
    END IF;

    SELECT COALESCE(patente, codigo) INTO v_patente FROM activos WHERE id = v_activo;
    IF v_patente IS NULL THEN RAISE EXCEPTION 'No se encontró el equipo.'; END IF;

    SELECT meses INTO v_meses FROM certificado_vigencia_estandar WHERE tipo = v_tipo;
    v_vence := (v_prueba + (COALESCE(v_meses, 6) || ' months')::INTERVAL)::date;

    v_anio := EXTRACT(YEAR FROM v_prueba)::int;
    PERFORM pg_advisory_xact_lock(hashtext('folio_cert_' || v_tipo || v_anio));
    -- [MIG432] Salta también los folios que se emitieron en papel.
    v_num   := fn_proximo_folio(v_tipo, v_anio);
    v_folio := lpad(v_num::text, 2, '0') || '/' || v_anio;

    INSERT INTO certificados_emitidos (
        activo_id, tipo, folio, folio_numero, folio_anio, fecha_prueba, fecha_vencimiento,
        informe, instrumento_desc, instrumento_marca, estanque_serie, anio_fabricacion,
        propietario, propietario_direccion, fabricante, norma_revision, tipo_estanque,
        capacidad_nominal, n_compartimientos, cap_compartimientos, protocolo,
        presion_diseno, presion_prueba, longitud_nominal, diametro_nominal,
        ancho_nominal, alto_nominal, manto_material, manto_forma, manto_espesor,
        cabezal_material, cabezal_forma, cabezal_espesor, union_longitudinal,
        union_rectangular, union_manto_cabezal, medio_deteccion, rango_manometro,
        alcance_prueba, numero_plano, especificacion_diseno, duracion_prueba,
        metodo_prueba, lugar_prueba, foto_inicio_url, foto_termino_url,
        firmante_nombre, firmante_titulo, firmante_cargo, firmante_firma_url, emitido_por)
    SELECT v_activo, v_tipo, v_folio, v_num, v_anio, v_prueba, v_vence,
        COALESCE(p_datos->>'informe','Aceptado sin filtraciones'),
        p_datos->>'instrumento_desc', p_datos->>'instrumento_marca',
        p_datos->>'estanque_serie', p_datos->>'anio_fabricacion',
        p_datos->>'propietario', p_datos->>'propietario_direccion', p_datos->>'fabricante',
        p_datos->>'norma_revision', p_datos->>'tipo_estanque',
        p_datos->>'capacidad_nominal', p_datos->>'n_compartimientos',
        p_datos->>'cap_compartimientos', p_datos->>'protocolo',
        p_datos->>'presion_diseno', p_datos->>'presion_prueba',
        p_datos->>'longitud_nominal', p_datos->>'diametro_nominal',
        p_datos->>'ancho_nominal', p_datos->>'alto_nominal',
        p_datos->>'manto_material', p_datos->>'manto_forma', p_datos->>'manto_espesor',
        p_datos->>'cabezal_material', p_datos->>'cabezal_forma', p_datos->>'cabezal_espesor',
        COALESCE(p_datos->>'union_longitudinal','Tope'),
        COALESCE(p_datos->>'union_rectangular','Tope'),
        COALESCE(p_datos->>'union_manto_cabezal','Tope'),
        p_datos->>'medio_deteccion', p_datos->>'rango_manometro',
        p_datos->>'alcance_prueba', p_datos->>'numero_plano',
        p_datos->>'especificacion_diseno', p_datos->>'duracion_prueba',
        p_datos->>'metodo_prueba', p_datos->>'lugar_prueba',
        p_datos->>'foto_inicio_url', p_datos->>'foto_termino_url',
        p_datos->>'firmante_nombre', p_datos->>'firmante_titulo', p_datos->>'firmante_cargo',
        -- [MIG467] La firma se CONGELA con el certificado. Si la persona cambia
        -- su firma el año que viene, el papel ya emitido sigue mostrando la que
        -- usó ese día: es un documento, no una pantalla.
        p_datos->>'firmante_firma_url',
        auth.uid()
    RETURNING id INTO v_emitido_id;

    INSERT INTO certificaciones (activo_id, tipo, fecha_emision, fecha_vencimiento,
                                 numero_certificado, entidad_certificadora, bloqueante,
                                 fecha_origen, fecha_origen_nota, notas, created_by)
    VALUES (v_activo, v_tipo::tipo_certificacion_enum, v_prueba, v_vence,
            v_folio, COALESCE(p_datos->>'propietario','PILLADO Y COMPAÑÍA LTDA.'), TRUE,
            'documento',
            'MIG431 · emitido por el sistema, certificado Nº ' || v_folio
              || ': prueba ' || to_char(v_prueba,'DD-MM-YYYY')
              || ', vence ' || to_char(v_vence,'DD-MM-YYYY')
              || ' (' || COALESCE(v_meses,6) || ' meses).',
            'Certificado emitido desde SICOM.', auth.uid())
    RETURNING id INTO v_cert_id;

    UPDATE certificados_emitidos SET certificacion_id = v_cert_id WHERE id = v_emitido_id;

    RETURN jsonb_build_object('success', true, 'id', v_emitido_id, 'folio', v_folio,
                              'patente', v_patente, 'fecha_prueba', v_prueba,
                              'fecha_vencimiento', v_vence, 'certificacion_id', v_cert_id);
END $function$;

CREATE OR REPLACE VIEW v_certificados_emitidos AS
 SELECT e.id,
    e.activo_id,
    e.tipo,
    e.folio,
    e.folio_numero,
    e.folio_anio,
    e.fecha_prueba,
    e.fecha_vencimiento,
    e.informe,
    e.instrumento_desc,
    e.instrumento_marca,
    e.estanque_serie,
    e.anio_fabricacion,
    e.propietario,
    e.propietario_direccion,
    e.fabricante,
    e.norma_revision,
    e.tipo_estanque,
    e.capacidad_nominal,
    e.n_compartimientos,
    e.cap_compartimientos,
    e.protocolo,
    e.presion_diseno,
    e.presion_prueba,
    e.longitud_nominal,
    e.diametro_nominal,
    e.ancho_nominal,
    e.alto_nominal,
    e.manto_material,
    e.manto_forma,
    e.manto_espesor,
    e.cabezal_material,
    e.cabezal_forma,
    e.cabezal_espesor,
    e.union_longitudinal,
    e.union_rectangular,
    e.union_manto_cabezal,
    e.medio_deteccion,
    e.rango_manometro,
    e.alcance_prueba,
    e.numero_plano,
    e.especificacion_diseno,
    e.duracion_prueba,
    e.metodo_prueba,
    e.lugar_prueba,
    e.foto_inicio_url,
    e.foto_termino_url,
    e.firmante_nombre,
    e.firmante_titulo,
    e.firmante_cargo,
    e.certificacion_id,
    e.anulado,
    e.anulado_motivo,
    e.emitido_por,
    e.created_at,
    COALESCE(a.patente, a.codigo) AS patente,
    a.nombre AS equipo_nombre,
    u.nombre_completo AS emitido_por_nombre,
    e.fecha_vencimiento < CURRENT_DATE AS vencido,
    e.firmante_firma_url
   FROM certificados_emitidos e
     JOIN activos a ON a.id = e.activo_id
     LEFT JOIN usuarios_perfil u ON u.id = e.emitido_por;
 SELECT e.id,
    e.activo_id,
    e.tipo,
    e.folio,
    e.folio_numero,
    e.folio_anio,
    e.fecha_prueba,
    e.fecha_vencimiento,
    e.informe,
    e.instrumento_desc,
    e.instrumento_marca,
    e.estanque_serie,
    e.anio_fabricacion,
    e.propietario,
    e.propietario_direccion,
    e.fabricante,
    e.norma_revision,
    e.tipo_estanque,
    e.capacidad_nominal,
    e.n_compartimientos,
    e.cap_compartimientos,
    e.protocolo,
    e.presion_diseno,
    e.presion_prueba,
    e.longitud_nominal,
    e.diametro_nominal,
    e.ancho_nominal,
    e.alto_nominal,
    e.manto_material,
    e.manto_forma,
    e.manto_espesor,
    e.cabezal_material,
    e.cabezal_forma,
    e.cabezal_espesor,
    e.union_longitudinal,
    e.union_rectangular,
    e.union_manto_cabezal,
    e.medio_deteccion,
    e.rango_manometro,
    e.alcance_prueba,
    e.numero_plano,
    e.especificacion_diseno,
    e.duracion_prueba,
    e.metodo_prueba,
    e.lugar_prueba,
    e.foto_inicio_url,
    e.foto_termino_url,
    e.firmante_nombre,
    e.firmante_titulo,
    e.firmante_cargo,
    e.certificacion_id,
    e.anulado,
    e.anulado_motivo,
    e.emitido_por,
    e.created_at,
    COALESCE(a.patente, a.codigo) AS patente,
    a.nombre AS equipo_nombre,
    u.nombre_completo AS emitido_por_nombre,
    e.fecha_vencimiento < CURRENT_DATE AS vencido,
    e.firmante_firma_url
   FROM certificados_emitidos e
     JOIN activos a ON a.id = e.activo_id
     LEFT JOIN usuarios_perfil u ON u.id = e.emitido_por;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_n INT; r RECORD;
BEGIN
    -- Una sola puerta para guardar la firma.
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname IN ('rpc_set_mi_firma');
    IF v_n <> 0 THEN RAISE EXCEPTION 'FALLO: quedó la función duplicada'; END IF;

    SELECT count(*) INTO v_n FROM pg_policies
     WHERE schemaname='storage' AND tablename='objects'
       AND policyname LIKE 'storage_firma_propia%';
    IF v_n <> 0 THEN RAISE EXCEPTION 'FALLO: quedaron políticas de storage sin uso'; END IF;
    RAISE NOTICE 'sin duplicados: se guarda con rpc_guardar_mi_firma, como desde MIG396';

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname = 'rpc_mi_firma';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FALLO: falta el lector de la firma'; END IF;

    SELECT count(*) INTO v_n FROM usuarios_perfil WHERE firma_url IS NOT NULL;
    RAISE NOTICE 'personas con firma cargada hoy: %', v_n;

    -- El cargo del perfil es el que va a proponer el certificado.
    FOR r IN SELECT nombre_completo, cargo FROM usuarios_perfil
              WHERE rol::TEXT IN ('administrador','subgerente_operaciones')
              ORDER BY nombre_completo LOOP
        RAISE NOTICE '   %  ·  cargo en el perfil: %',
            rpad(r.nombre_completo,28), COALESCE(r.cargo,'(vacío)');
    END LOOP;
END
$mig$;

COMMIT;
