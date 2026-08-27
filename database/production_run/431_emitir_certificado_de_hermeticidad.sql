-- ============================================================================
-- MIG431 · Emitir el certificado de hermeticidad desde el sistema
-- ----------------------------------------------------------------------------
-- LO QUE PIDIÓ MANUEL
-- 27-08-2026: «necesito que Control documental pueda generar el QR respectivo y
-- además pueda emitir certificados. Necesito que también haga los certificados
-- de hermeticidad, te adjunto un ejemplo, para que cuando se quiera hacer el
-- informe pida los datos necesarios».
--
-- El ejemplo es el certificado Nº 07/2024 del SVBJ-57. Son tres páginas:
-- descripción del estanque, aprobación de la prueba con la fecha de
-- vencimiento, y control fotográfico con la foto de inicio y la de término.
--
-- ── LO QUE HACE QUE ESTO VALGA LA PENA ─────────────────────────────────────
-- El certificado tiene más de treinta campos, y treinta campos en un formulario
-- es una garantía de que nadie lo llene. Pero de esos treinta, veintiocho son
-- del ESTANQUE y no cambian entre una prueba y la siguiente: serie, año de
-- fabricación, fabricante, capacidad, espesores, tipo de uniones.
--
-- Lo que cambia en cada prueba son tres cosas: la fecha, quién la hizo y las
-- fotos. Por eso el formulario se abre con los datos de la última emisión de
-- ESE camión, y renovar es confirmar, no tipear.
--
-- La primera vez de cada equipo sí hay que llenarlo. Se hace una vez.
--
-- ── LA FECHA NO SE ESCRIBE: SALE DE LA PRUEBA ──────────────────────────────
-- El vencimiento se calcula sumando a la fecha de prueba los meses que dura el
-- documento según `certificado_vigencia_estandar` — 6 para la hermeticidad.
-- Toda esta auditoría empezó porque alguien tecleó un año donde iban seis
-- meses; si el sistema es el que emite, no hay dónde equivocarse.
--
-- ── Y QUEDA REGISTRADO COMO PAPEL DEL EQUIPO ───────────────────────────────
-- Emitir crea también la fila en `certificaciones`, con `fecha_origen` =
-- 'documento' porque la fecha sale del documento que el propio sistema acaba de
-- escribir. Así aparece en Control documental, en la ficha y en el QR del
-- cliente sin que nadie tenga que cargarlo a mano después.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.certificados_emitidos (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id             UUID NOT NULL REFERENCES activos(id),
    tipo                  TEXT NOT NULL DEFAULT 'hermeticidad',
    folio                 TEXT NOT NULL,              -- «07/2024»
    folio_numero          INT  NOT NULL,
    folio_anio            INT  NOT NULL,

    -- La prueba
    fecha_prueba          DATE NOT NULL,
    fecha_vencimiento     DATE NOT NULL,
    informe               TEXT NOT NULL DEFAULT 'Aceptado sin filtraciones',

    -- Instrumento con que se midió
    instrumento_desc      TEXT,
    instrumento_marca     TEXT,

    -- El equipo
    estanque_serie        TEXT,
    anio_fabricacion      TEXT,
    propietario           TEXT,
    propietario_direccion TEXT,
    fabricante            TEXT,

    -- Características de diseño
    norma_revision        TEXT,
    tipo_estanque         TEXT,
    capacidad_nominal     TEXT,
    n_compartimientos     TEXT,
    cap_compartimientos   TEXT,
    protocolo             TEXT,
    presion_diseno        TEXT,
    presion_prueba        TEXT,
    longitud_nominal      TEXT,
    diametro_nominal      TEXT,
    ancho_nominal         TEXT,
    alto_nominal          TEXT,

    -- Mantos y cabezales
    manto_material        TEXT,
    manto_forma           TEXT,
    manto_espesor         TEXT,
    cabezal_material      TEXT,
    cabezal_forma         TEXT,
    cabezal_espesor       TEXT,
    union_longitudinal    TEXT DEFAULT 'Tope',
    union_rectangular     TEXT DEFAULT 'Tope',
    union_manto_cabezal   TEXT DEFAULT 'Tope',

    -- Cómo se hizo la prueba
    medio_deteccion       TEXT,
    rango_manometro       TEXT,
    alcance_prueba        TEXT,
    numero_plano          TEXT,
    especificacion_diseno TEXT,
    duracion_prueba       TEXT,
    metodo_prueba         TEXT,
    lugar_prueba          TEXT,

    -- Control fotográfico
    foto_inicio_url       TEXT,
    foto_termino_url      TEXT,

    -- Quién lo firma
    firmante_nombre       TEXT,
    firmante_titulo       TEXT,
    firmante_cargo        TEXT,

    certificacion_id      UUID REFERENCES certificaciones(id),
    anulado               BOOLEAN NOT NULL DEFAULT FALSE,
    anulado_motivo        TEXT,
    emitido_por           UUID REFERENCES usuarios_perfil(id),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- El folio identifica al certificado: no puede repetirse dentro del año.
-- Hoy hay tres camiones con «Certificado Nº 10/2025» porque se llevaba a mano.
CREATE UNIQUE INDEX IF NOT EXISTS uq_cert_emitido_folio
  ON public.certificados_emitidos (tipo, folio_anio, folio_numero) WHERE NOT anulado;
CREATE INDEX IF NOT EXISTS ix_cert_emitido_activo
  ON public.certificados_emitidos (activo_id, tipo, created_at DESC);

COMMENT ON TABLE public.certificados_emitidos IS
  'MIG431: certificados que emite el propio sistema. El folio es unico por tipo y anio: llevado a mano se repetia (tres camiones con el 10/2025).';

ALTER TABLE public.certificados_emitidos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "cert_emitido_lectura" ON public.certificados_emitidos;
CREATE POLICY "cert_emitido_lectura" ON public.certificados_emitidos
  FOR SELECT TO authenticated USING (true);

-- ── Con qué se abre el formulario ─────────────────────────────────────────
-- Lo último que se emitió de ESE camión. Si nunca se emitió, lo que se sabe
-- del equipo y los valores que se repiten en todos los certificados de la
-- flota. Nunca inventa medidas: si no hay dato, va vacío y lo escribe quien
-- hace la prueba.
CREATE OR REPLACE FUNCTION public.rpc_certificado_datos_previos(
    p_activo_id uuid, p_tipo text DEFAULT 'hermeticidad')
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_prev certificados_emitidos%ROWTYPE; v_a RECORD; v_meses INT;
BEGIN
    SELECT * INTO v_prev FROM certificados_emitidos
     WHERE activo_id = p_activo_id AND tipo = p_tipo AND NOT anulado
     ORDER BY created_at DESC LIMIT 1;

    SELECT COALESCE(a.patente, a.codigo) AS patente, a.nombre, a.codigo
      INTO v_a FROM activos a WHERE a.id = p_activo_id;

    SELECT meses INTO v_meses FROM certificado_vigencia_estandar WHERE tipo = p_tipo;

    RETURN jsonb_build_object(
      'patente', v_a.patente,
      'equipo',  v_a.nombre,
      'meses_vigencia', COALESCE(v_meses, 6),
      'hay_anterior', v_prev.id IS NOT NULL,
      'folio_anterior', v_prev.folio,
      'datos', CASE WHEN v_prev.id IS NULL THEN
          jsonb_build_object(
            'informe', 'Aceptado sin filtraciones',
            'instrumento_desc', 'Manómetro Análogo 0 a 15 psi (0 a 1 bar)',
            'instrumento_marca', 'Tempres EN 837-1',
            'propietario', 'PILLADO Y COMPAÑÍA LTDA.',
            'propietario_direccion', 'GERONIMO MENDEZ 2125, OF. 1, COQUIMBO',
            'norma_revision', 'DOT 406',
            'tipo_estanque', 'Sobrecamión',
            'n_compartimientos', 'UNO',
            'protocolo', 'PC 110',
            'presion_diseno', 'Atmosférica',
            'presion_prueba', '3 PSI',
            'medio_deteccion', 'Solución de Jabón',
            'rango_manometro', '0 - 15 PSI',
            'alcance_prueba', 'Estanque Completo',
            'duracion_prueba', '20 Minutos',
            'metodo_prueba', 'Aire Comprimido',
            'lugar_prueba', 'Avda. Gerónimo Mendez 2125, Coquimbo.',
            'union_longitudinal', 'Tope',
            'union_rectangular', 'Tope',
            'union_manto_cabezal', 'Tope')
        ELSE to_jsonb(v_prev) - 'id' - 'folio' - 'folio_numero' - 'folio_anio'
             - 'fecha_prueba' - 'fecha_vencimiento' - 'certificacion_id'
             - 'foto_inicio_url' - 'foto_termino_url' - 'emitido_por'
             - 'created_at' - 'anulado' - 'anulado_motivo' - 'activo_id'
      END);
END $function$;

-- ── Emitir ────────────────────────────────────────────────────────────────
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
    IF v_rol IS NULL OR v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento') THEN
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

    -- El vencimiento NO se escribe: sale de la prueba más lo que dura el papel.
    SELECT meses INTO v_meses FROM certificado_vigencia_estandar WHERE tipo = v_tipo;
    v_vence := (v_prueba + (COALESCE(v_meses, 6) || ' months')::INTERVAL)::date;

    -- Folio correlativo dentro del año, tomado bajo bloqueo para que dos
    -- personas emitiendo a la vez no se lleven el mismo número.
    v_anio := EXTRACT(YEAR FROM v_prueba)::int;
    PERFORM pg_advisory_xact_lock(hashtext('folio_cert_' || v_tipo || v_anio));
    SELECT COALESCE(max(folio_numero), 0) + 1 INTO v_num
      FROM certificados_emitidos WHERE tipo = v_tipo AND folio_anio = v_anio AND NOT anulado;
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
        firmante_nombre, firmante_titulo, firmante_cargo, emitido_por)
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
        auth.uid()
    RETURNING id INTO v_emitido_id;

    -- Y queda como papel del equipo: Control documental, la ficha y el QR del
    -- cliente lo ven sin que nadie lo cargue después.
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

GRANT EXECUTE ON FUNCTION public.rpc_certificado_datos_previos(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_emitir_certificado(jsonb) TO authenticated;

-- ── Los emitidos de un equipo, para poder reimprimir ──────────────────────
CREATE OR REPLACE VIEW public.v_certificados_emitidos AS
SELECT e.*, COALESCE(a.patente, a.codigo) AS patente, a.nombre AS equipo_nombre,
       u.nombre_completo AS emitido_por_nombre,
       (e.fecha_vencimiento < CURRENT_DATE) AS vencido
  FROM certificados_emitidos e
  JOIN activos a ON a.id = e.activo_id
  LEFT JOIN usuarios_perfil u ON u.id = e.emitido_por;

GRANT SELECT ON public.v_certificados_emitidos TO authenticated;

DO $r$
DECLARE v_m INT;
BEGIN
    SELECT meses INTO v_m FROM certificado_vigencia_estandar WHERE tipo='hermeticidad';
    RAISE NOTICE 'Listo. La hermeticidad se emite con % meses de vigencia, calculados desde la fecha de prueba.', v_m;
    RAISE NOTICE 'Proximo folio del ano %: %/%',
      EXTRACT(YEAR FROM CURRENT_DATE)::int,
      lpad((COALESCE((SELECT max(folio_numero) FROM certificados_emitidos
                       WHERE tipo='hermeticidad' AND folio_anio=EXTRACT(YEAR FROM CURRENT_DATE)::int), 0)+1)::text,2,'0'),
      EXTRACT(YEAR FROM CURRENT_DATE)::int;
END
$r$;

COMMIT;
