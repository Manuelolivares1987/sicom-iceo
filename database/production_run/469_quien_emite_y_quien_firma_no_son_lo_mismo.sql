-- ============================================================================
-- MIG469 · Quién emite y quién firma no son lo mismo
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- «Necesito que pueda también hacer el certificado el jefe de operaciones, pero
-- firmo yo, como Manuel Olivares».
--
-- Emitir ya podía: el jefe de operaciones está en el gate desde antes. Lo que
-- faltaba es separar las dos cosas. Hasta MIG467 el certificado asumía que
-- quien emite es quien firma, así que le proponía su propio nombre y su propia
-- firma. Con el jefe de operaciones emitiendo, saldría su nombre y ninguna
-- firma.
--
-- UN AGUJERO QUE ABRÍ YO EN MIG467, Y QUE HAY QUE CERRAR ANTES
-- La pantalla mandaba `firmante_firma_url` dentro de los datos, y el RPC lo
-- guardaba tal cual. O sea: cualquiera con la sesión abierta podía emitir un
-- certificado con la URL de la firma de otro. En un papel que se presenta ante
-- terceros eso es una falsificación a un clic de distancia.
--
-- Desde acá la firma NO viene de la pantalla. La pantalla dice A QUIÉN se le
-- pide firmar; el servidor va a buscar el nombre, el cargo y la firma al perfil
-- de esa persona. Lo que mande el cliente en `firmante_firma_url` se ignora.
--
-- Y NO CUALQUIERA PUEDE FIGURAR COMO FIRMANTE
-- Sólo quien esté designado. La designación la hace un administrador, queda con
-- su nombre y su fecha, y se puede quitar. Que la firma de alguien aparezca en
-- un documento es una delegación con peso: tiene que ser un acto explícito y no
-- el efecto lateral de tener cuenta en el sistema.
--
-- LO QUE QUEDA TRAZADO
-- El certificado ya guardaba `emitido_por`. Con esto, la fila dice las dos
-- cosas: quién lo emitió y con la firma de quién salió. Si mañana alguien
-- pregunta por un certificado, el sistema puede responder ambas.
-- ============================================================================

BEGIN;

-- ── 1 · Quién está autorizado a figurar como firmante ───────────────────────
CREATE TABLE IF NOT EXISTS certificado_firmante_autorizado (
    usuario_perfil_id UUID NOT NULL REFERENCES usuarios_perfil(id) ON DELETE CASCADE,
    tipo              TEXT NOT NULL DEFAULT 'hermeticidad',
    titulo            TEXT,
    autorizado_por    UUID REFERENCES usuarios_perfil(id),
    autorizado_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    nota              TEXT,
    PRIMARY KEY (usuario_perfil_id, tipo)
);

COMMENT ON TABLE certificado_firmante_autorizado IS
    'Personas cuya firma puede aparecer en un certificado, por tipo. Que la '
    'firma de alguien salga en un documento es una delegación: se designa a '
    'mano, queda con quién y cuándo, y se puede quitar.';

ALTER TABLE certificado_firmante_autorizado ENABLE ROW LEVEL SECURITY;
-- Sin políticas: se llega sólo por los RPC de abajo, que son SECURITY DEFINER.

-- Manuel firma los certificados de hermeticidad. El título no está en el perfil
-- —el perfil tiene cargo, no profesión— así que se guarda acá.
INSERT INTO certificado_firmante_autorizado (usuario_perfil_id, tipo, titulo, nota)
SELECT up.id, 'hermeticidad', 'Ing. Civil Industrial',
       'Firma los certificados aunque los emita otra persona (indicación de Manuel, 31-08-2026).'
  FROM usuarios_perfil up
 WHERE up.nombre_completo = 'Manuel Olivares'
ON CONFLICT (usuario_perfil_id, tipo) DO UPDATE
   SET titulo = EXCLUDED.titulo, nota = EXCLUDED.nota;

-- ── 2 · La firma se guarda con el certificado, y de quién es ────────────────
ALTER TABLE certificados_emitidos
  ADD COLUMN IF NOT EXISTS firmante_id UUID REFERENCES usuarios_perfil(id);

COMMENT ON COLUMN certificados_emitidos.firmante_id IS
    'Persona con cuya firma salió el certificado. Junto a emitido_por deja las '
    'dos preguntas respondidas: quién lo hizo y quién lo firma.';

-- ── 3 · A quién se le puede pedir la firma ──────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_certificado_firmantes(p_tipo TEXT DEFAULT 'hermeticidad')
RETURNS TABLE (
    id        UUID,
    nombre    TEXT,
    cargo     TEXT,
    titulo    TEXT,
    firma_url TEXT,
    tiene_firma BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    RETURN QUERY
    SELECT up.id, up.nombre_completo::TEXT, up.cargo::TEXT, fa.titulo,
           up.firma_url, up.firma_url IS NOT NULL
      FROM certificado_firmante_autorizado fa
      JOIN usuarios_perfil up ON up.id = fa.usuario_perfil_id
     WHERE fa.tipo = p_tipo
     ORDER BY up.nombre_completo;
END;
$$;

-- ── 4 · Emitir: la firma la resuelve el servidor ────────────────────────────
CREATE OR REPLACE FUNCTION fn_certificado_datos_firmante(
    p_firmante_id UUID,
    p_tipo        TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v JSONB;
BEGIN
    IF p_firmante_id IS NULL THEN RETURN NULL; END IF;

    SELECT jsonb_build_object(
             'nombre', up.nombre_completo,
             'cargo',  up.cargo,
             'titulo', fa.titulo,
             'firma_url', up.firma_url)
      INTO v
      FROM certificado_firmante_autorizado fa
      JOIN usuarios_perfil up ON up.id = fa.usuario_perfil_id
     WHERE fa.usuario_perfil_id = p_firmante_id AND fa.tipo = p_tipo;

    IF v IS NULL THEN
        RAISE EXCEPTION 'Esa persona no está autorizada a firmar certificados de %. '
                        'La autorización se da en Admin, no se elige al emitir.', p_tipo;
    END IF;
    RETURN v;
END;
$$;

REVOKE ALL ON FUNCTION rpc_certificado_firmantes(TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_certificado_datos_firmante(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_certificado_firmantes(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_certificado_datos_firmante(UUID, TEXT) TO authenticated;

-- ── 5 · El RPC de emisión, con el firmante resuelto en el servidor ─────

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
    v_firmante UUID; v_fdatos JSONB;
BEGIN
    SELECT rol INTO v_rol FROM usuarios_perfil WHERE id = auth.uid();
    IF v_rol IS NULL OR v_rol NOT IN ('administrador','jefe_operaciones','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'No tienes permiso para emitir certificados.';
    END IF;

    -- [MIG469] La firma NO viene de la pantalla. La pantalla dice a quién se le
    -- pide firmar; el servidor va a buscar nombre, cargo y firma al perfil de
    -- esa persona, y sólo si está designada como firmante. Lo que venga en
    -- `firmante_firma_url` se ignora: era una falsificación a un clic.
    v_firmante := NULLIF(p_datos->>'firmante_id','')::uuid;
    v_fdatos   := fn_certificado_datos_firmante(v_firmante, COALESCE(p_datos->>'tipo','hermeticidad'));

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
        firmante_nombre, firmante_titulo, firmante_cargo, firmante_firma_url,
        firmante_id, emitido_por)
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
        -- Si hay firmante designado, manda su perfil; si no, el texto libre de
        -- siempre, que sigue sirviendo para el certificado que se firma a mano.
        COALESCE(v_fdatos->>'nombre', p_datos->>'firmante_nombre'),
        COALESCE(v_fdatos->>'titulo', p_datos->>'firmante_titulo'),
        COALESCE(v_fdatos->>'cargo',  p_datos->>'firmante_cargo'),
        -- [MIG467] La firma se CONGELA con el certificado: si la persona cambia
        -- la suya el año que viene, el papel ya emitido sigue mostrando la que
        -- usó ese día. [MIG469] Y sale del perfil, nunca del cliente.
        v_fdatos->>'firma_url',
        v_firmante,
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
    e.firmante_firma_url,
    e.firmante_id
   FROM certificados_emitidos e
     JOIN activos a ON a.id = e.activo_id
     LEFT JOIN usuarios_perfil u ON u.id = e.emitido_por;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
--
-- La prueba de verdad —el jefe de operaciones emitiendo con la firma de Manuel—
-- emite un certificado real y consume un folio, así que NO va acá: un RAISE al
-- final para deshacerla haría rollback de la migración entera. Va aparte, en un
-- guion de prueba con rollback propio.
DO $mig$
DECLARE r RECORD; v_n INT; v_j UUID;
BEGIN
    SELECT count(*) INTO v_n FROM certificado_firmante_autorizado;
    IF v_n = 0 THEN RAISE EXCEPTION 'FALLO: no quedó nadie designado como firmante'; END IF;

    FOR r IN
        SELECT up.nombre_completo n, up.cargo c, fa.titulo t, up.firma_url IS NOT NULL f
          FROM certificado_firmante_autorizado fa
          JOIN usuarios_perfil up ON up.id = fa.usuario_perfil_id
         WHERE fa.tipo = 'hermeticidad'
    LOOP
        RAISE NOTICE 'firmante autorizado: % · % · % · firma cargada: %',
            r.n, COALESCE(r.c,'(sin cargo)'), COALESCE(r.t,'(sin título)'), r.f;
    END LOOP;

    -- Nadie que no esté designado puede figurar como firmante.
    SELECT id INTO v_j FROM usuarios_perfil WHERE rol::TEXT = 'jefe_operaciones' LIMIT 1;
    BEGIN
        PERFORM fn_certificado_datos_firmante(v_j, 'hermeticidad');
        RAISE EXCEPTION 'FALLO: aceptó como firmante a alguien no designado';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'FALLO%' THEN RAISE; END IF;
        RAISE NOTICE 'no designado, rechazado: %', left(SQLERRM, 92);
    END;

    -- El emisor puede ser cualquiera de los cuatro roles; el firmante, sólo el
    -- designado. Son dos listas distintas y eso es el punto de la migración.
    SELECT count(*) INTO v_n FROM usuarios_perfil
     WHERE rol::TEXT IN ('administrador','jefe_operaciones','subgerente_operaciones','jefe_mantenimiento');
    RAISE NOTICE 'cuentas que pueden EMITIR: %  ·  personas que pueden FIRMAR: %',
        v_n, (SELECT count(*) FROM certificado_firmante_autorizado WHERE tipo='hermeticidad');
END
$mig$;

COMMIT;
