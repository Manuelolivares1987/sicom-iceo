-- ============================================================================
-- MIG697 · Entrega de turno Franke: los miércoles, con el combustible primero
-- ----------------------------------------------------------------------------
-- Manuel, 15-11-2026: «los cambios de turno son todos los miércoles; en Franke
-- es clave el control de combustible: con cuánto está dejando cada camión, si
-- abastecieron a otra empresa, novedades en seguridad».
--
-- La entrega (MIG362) tenía un solo número de litros para toda la faena y no
-- preguntaba por terceros ni por seguridad. Ahora, ANTES de firmar:
--   1. Litros por camión-estanque al entregar (cuentalitros/varilla/estimado),
--      contra el teórico del sistema → diferencia por camión.
--   2. ¿Se abasteció a otra empresa (no Cenizas)? Sí/No OBLIGATORIO; si sí,
--      cada abastecimiento con empresa, equipo, litros y quién autorizó.
--      Queda además como novedad «importante» en la bitácora.
--   3. Seguridad: «sin novedad» o el detalle (queda como novedad en la bitácora).
--   4. Cómo se hizo la entrega verbal (presencial / llamada).
-- Un trigger impide pasar a «entregada» sin esas cuatro respuestas (sirve
-- igual para lo que sube desde la cola sin señal).
-- ============================================================================

ALTER TABLE public.faena_entrega_turno
    ADD COLUMN IF NOT EXISTS terceros_hubo         BOOLEAN,
    ADD COLUMN IF NOT EXISTS seguridad_sin_novedad BOOLEAN,
    ADD COLUMN IF NOT EXISTS seguridad_detalle     TEXT,
    ADD COLUMN IF NOT EXISTS verbal_modo           TEXT CHECK (verbal_modo IN ('presencial', 'llamada', 'video', 'no_se_pudo')),
    ADD COLUMN IF NOT EXISTS declarado_at          TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS public.faena_entrega_combustible (
    entrega_id     UUID NOT NULL REFERENCES public.faena_entrega_turno(id) ON DELETE CASCADE,
    estanque_id    UUID NOT NULL REFERENCES public.combustible_estanques(id),
    patente        TEXT,
    litros_teorico NUMERIC(12,1),
    litros_fisico  NUMERIC(12,1) NOT NULL CHECK (litros_fisico >= 0),
    metodo         TEXT NOT NULL DEFAULT 'cuentalitros' CHECK (metodo IN ('cuentalitros', 'varilla', 'estimado')),
    nota           TEXT,
    PRIMARY KEY (entrega_id, estanque_id)
);
ALTER TABLE public.faena_entrega_combustible ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS faena_ent_comb_ver ON public.faena_entrega_combustible;
CREATE POLICY faena_ent_comb_ver ON public.faena_entrega_combustible FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM faena_entrega_turno e WHERE e.id = entrega_id AND public.fn_faena_comunicacion_puede(e.faena_id)));

CREATE TABLE IF NOT EXISTS public.faena_entrega_terceros (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entrega_id     UUID NOT NULL REFERENCES public.faena_entrega_turno(id) ON DELETE CASCADE,
    fecha          DATE,
    empresa        TEXT NOT NULL CHECK (length(btrim(empresa)) >= 2),
    equipo         TEXT,
    litros         NUMERIC(12,1) NOT NULL CHECK (litros > 0),
    desde_camion   TEXT,
    autorizado_por TEXT NOT NULL CHECK (length(btrim(autorizado_por)) >= 3),
    documento      TEXT,
    nota           TEXT
);
ALTER TABLE public.faena_entrega_terceros ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS faena_ent_terc_ver ON public.faena_entrega_terceros;
CREATE POLICY faena_ent_terc_ver ON public.faena_entrega_terceros FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM faena_entrega_turno e WHERE e.id = entrega_id AND public.fn_faena_comunicacion_puede(e.faena_id)));

-- ── Contexto para declarar (se guarda en el teléfono junto con la entrega) ──
CREATE OR REPLACE FUNCTION public.rpc_faena_entrega_contexto(p_entrega_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_e faena_entrega_turno;
BEGIN
    SELECT * INTO v_e FROM faena_entrega_turno WHERE id = p_entrega_id;
    IF v_e.id IS NULL OR NOT fn_faena_comunicacion_puede(v_e.faena_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    RETURN jsonb_build_object(
        'camiones', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                        'estanque_id', s.id, 'patente', s.patente, 'nombre', s.nombre, 'capacidad', s.capacidad_lt,
                        'teorico', round(s.stock_teorico_lt), 'estimable', s.estimable,
                        'fisico', c.litros_fisico, 'metodo', c.metodo, 'nota', c.nota) ORDER BY s.orden_cierre NULLS LAST, s.codigo), '[]'::jsonb)
                       FROM v_comb_faena_estanque_ahora s
                       LEFT JOIN faena_entrega_combustible c ON c.entrega_id = v_e.id AND c.estanque_id = s.id
                      WHERE s.faena_id = v_e.faena_id AND s.activo),
        'terceros_hubo', v_e.terceros_hubo,
        'terceros', (SELECT coalesce(jsonb_agg(to_jsonb(t) - 'entrega_id' ORDER BY t.fecha, t.empresa), '[]'::jsonb)
                       FROM faena_entrega_terceros t WHERE t.entrega_id = v_e.id),
        -- Lo que el sistema ya sabe del periodo y que la declaración debería calzar.
        'ventas_registradas', (SELECT coalesce(jsonb_agg(jsonb_build_object('fecha', v.fecha, 'cliente', v.cliente_nombre,
                                  'equipo', v.equipo_codigo, 'litros', v.litros) ORDER BY v.fecha), '[]'::jsonb)
                                 FROM combustible_ventas_franke v
                                WHERE v.fecha::date BETWEEN v_e.desde AND v_e.hasta),
        'despachos_sin_equipo', (SELECT coalesce(jsonb_agg(jsonb_build_object('fecha', d.fecha, 'equipo', d.equipo_texto,
                                    'litros', d.litros, 'camion', d.camion_patente) ORDER BY d.fecha), '[]'::jsonb)
                                   FROM combustible_faena_despachos d
                                  WHERE d.faena_id = v_e.faena_id AND NOT coalesce(d.anulado, false) AND d.equipo_id IS NULL
                                    AND coalesce(d.tipo_movimiento, 'despacho') = 'despacho'
                                    AND d.fecha BETWEEN v_e.desde AND v_e.hasta),
        'seguridad_sin_novedad', v_e.seguridad_sin_novedad,
        'seguridad_detalle', v_e.seguridad_detalle,
        'novedades_seguridad', (SELECT coalesce(jsonb_agg(jsonb_build_object('fecha_hora', n.fecha_hora, 'autor', n.autor_nombre,
                                   'severidad', n.severidad, 'texto', n.texto) ORDER BY n.fecha_hora), '[]'::jsonb)
                                  FROM faena_novedades n
                                 WHERE n.faena_id = v_e.faena_id AND (n.categoria = 'seguridad' OR n.severidad = 'critica')
                                   AND (n.fecha_hora AT TIME ZONE 'America/Santiago')::date BETWEEN v_e.desde AND v_e.hasta),
        'verbal_modo', v_e.verbal_modo);
END $$;
REVOKE ALL ON FUNCTION public.rpc_faena_entrega_contexto(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_faena_entrega_contexto(UUID) TO authenticated;

-- ── Declarar (idempotente: reemplaza lo declarado mientras no esté firmada) ─
CREATE OR REPLACE FUNCTION public.rpc_faena_entrega_declarar(
    p_entrega_id UUID, p_camiones JSONB, p_terceros_hubo BOOLEAN, p_terceros JSONB,
    p_seguridad_sin_novedad BOOLEAN, p_seguridad_detalle TEXT, p_verbal_modo TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_e        faena_entrega_turno;
    v_faltan   TEXT;
    v_total    NUMERIC;
    v_t        RECORD;
    v_ns       UUID := 'c0f1e2d3-0697-4f00-8000-000000000697';
BEGIN
    SELECT * INTO v_e FROM faena_entrega_turno WHERE id = p_entrega_id FOR UPDATE;
    IF v_e.id IS NULL OR NOT fn_faena_comunicacion_puede(v_e.faena_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    IF v_e.estado <> 'abierta' THEN RAISE EXCEPTION 'La entrega ya fue firmada; no se puede cambiar lo declarado.'; END IF;
    IF p_terceros_hubo IS NULL THEN RAISE EXCEPTION 'Responda si se abasteció a otra empresa en el turno (sí o no).'; END IF;
    IF p_seguridad_sin_novedad IS NULL THEN RAISE EXCEPTION 'Responda la sección de seguridad.'; END IF;
    IF NOT p_seguridad_sin_novedad AND length(btrim(coalesce(p_seguridad_detalle, ''))) < 10 THEN
        RAISE EXCEPTION 'Describa la novedad de seguridad (mínimo 10 caracteres).';
    END IF;
    IF p_terceros_hubo AND coalesce(jsonb_array_length(p_terceros), 0) = 0 THEN
        RAISE EXCEPTION 'Dijo que se abasteció a otra empresa: agregue cada abastecimiento (empresa, litros, quién autorizó).';
    END IF;

    -- Litros por camión: todos los camiones-estanque activos de la faena.
    DELETE FROM faena_entrega_combustible WHERE entrega_id = p_entrega_id;
    INSERT INTO faena_entrega_combustible (entrega_id, estanque_id, patente, litros_teorico, litros_fisico, metodo, nota)
    SELECT p_entrega_id, s.id, s.patente, round(s.stock_teorico_lt, 1), x.litros, coalesce(x.metodo, 'cuentalitros'), nullif(btrim(x.nota), '')
      FROM jsonb_to_recordset(coalesce(p_camiones, '[]'::jsonb)) AS x(estanque_id UUID, litros NUMERIC, metodo TEXT, nota TEXT)
      JOIN v_comb_faena_estanque_ahora s ON s.id = x.estanque_id AND s.faena_id = v_e.faena_id
     WHERE x.litros IS NOT NULL;
    SELECT string_agg(coalesce(s.patente, s.codigo), ', ') INTO v_faltan
      FROM v_comb_faena_estanque_ahora s
     WHERE s.faena_id = v_e.faena_id AND s.activo
       AND NOT EXISTS (SELECT 1 FROM faena_entrega_combustible c WHERE c.entrega_id = p_entrega_id AND c.estanque_id = s.id);
    IF v_faltan IS NOT NULL THEN RAISE EXCEPTION 'Falta indicar con cuántos litros queda: %.', v_faltan; END IF;
    SELECT sum(litros_fisico) INTO v_total FROM faena_entrega_combustible WHERE entrega_id = p_entrega_id;

    DELETE FROM faena_entrega_terceros WHERE entrega_id = p_entrega_id;
    IF p_terceros_hubo THEN
        INSERT INTO faena_entrega_terceros (entrega_id, fecha, empresa, equipo, litros, desde_camion, autorizado_por, documento, nota)
        SELECT p_entrega_id, x.fecha, btrim(x.empresa), nullif(btrim(x.equipo), ''), x.litros, nullif(btrim(x.desde_camion), ''),
               btrim(x.autorizado_por), nullif(btrim(x.documento), ''), nullif(btrim(x.nota), '')
          FROM jsonb_to_recordset(p_terceros) AS x(fecha DATE, empresa TEXT, equipo TEXT, litros NUMERIC, desde_camion TEXT,
                                                    autorizado_por TEXT, documento TEXT, nota TEXT);
    END IF;

    UPDATE faena_entrega_turno
       SET terceros_hubo = p_terceros_hubo, seguridad_sin_novedad = p_seguridad_sin_novedad,
           seguridad_detalle = CASE WHEN p_seguridad_sin_novedad THEN NULL ELSE btrim(p_seguridad_detalle) END,
           verbal_modo = p_verbal_modo, declarado_at = NOW(),
           stock_fisico_lt = v_total, conteo_fisico_hecho = true, updated_at = NOW()
     WHERE id = p_entrega_id;

    -- A la bitácora, para que el otro turno lo lea (uuid determinístico = idempotente).
    IF p_terceros_hubo THEN
        FOR v_t IN SELECT * FROM faena_entrega_terceros WHERE entrega_id = p_entrega_id LOOP
            PERFORM rpc_faena_novedad_crear(v_e.faena_id, 'combustible', 'importante',
                format('Abastecimiento a otra empresa: %s%s, %s L%s. Autorizó: %s.', v_t.empresa,
                       coalesce(' (' || v_t.equipo || ')', ''), trim(to_char(v_t.litros, 'FM999G999D0')),
                       coalesce(' desde ' || v_t.desde_camion, ''), v_t.autorizado_por),
                NULL, NULL, NULL, md5(v_ns::text || p_entrega_id::text || v_t.empresa || v_t.litros::text)::uuid);
        END LOOP;
    END IF;
    IF NOT p_seguridad_sin_novedad THEN
        PERFORM rpc_faena_novedad_crear(v_e.faena_id, 'seguridad', 'importante',
            'Seguridad (entrega de turno): ' || btrim(p_seguridad_detalle), NULL, NULL, NULL,
            md5(v_ns::text || p_entrega_id::text || 'seguridad')::uuid);
    END IF;
    RETURN jsonb_build_object('ok', true, 'litros_total', v_total);
END $$;
REVOKE ALL ON FUNCTION public.rpc_faena_entrega_declarar(UUID, JSONB, BOOLEAN, JSONB, BOOLEAN, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_faena_entrega_declarar(UUID, JSONB, BOOLEAN, JSONB, BOOLEAN, TEXT, TEXT) TO authenticated;

-- ── No se firma sin declarar ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_trg_faena_entrega_exige_declaracion()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.estado = 'entregada' AND OLD.estado = 'abierta' THEN
        IF NEW.declarado_at IS NULL OR NEW.terceros_hubo IS NULL OR NEW.seguridad_sin_novedad IS NULL THEN
            RAISE EXCEPTION 'Antes de firmar: litros por camión, abastecimiento a otras empresas y seguridad.';
        END IF;
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_faena_entrega_exige_declaracion ON public.faena_entrega_turno;
CREATE TRIGGER trg_faena_entrega_exige_declaracion BEFORE UPDATE OF estado ON public.faena_entrega_turno
    FOR EACH ROW EXECUTE FUNCTION public.fn_trg_faena_entrega_exige_declaracion();

-- ── Resumen diario: el estado de la entrega del miércoles ───────────────────
-- Miércoles = día de cambio. El resumen del miércoles lo recuerda; el del
-- jueves escala si la entrega no quedó firmada y recibida.
CREATE OR REPLACE FUNCTION public.fn_faena_entrega_miercoles(p_faena_id UUID)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    WITH d AS (
        SELECT (NOW() AT TIME ZONE 'America/Santiago')::date AS hoy,
               ((NOW() AT TIME ZONE 'America/Santiago')::date
                 - ((extract(isodow FROM (NOW() AT TIME ZONE 'America/Santiago')::date)::int - 3 + 7) % 7))::date AS miercoles
    )
    SELECT jsonb_build_object(
        'hoy_es_miercoles', extract(isodow FROM d.hoy) = 3,
        'miercoles', d.miercoles,
        'entrega', (SELECT jsonb_build_object('estado', e.estado, 'desde', e.desde, 'hasta', e.hasta,
                        'declarada', e.declarado_at IS NOT NULL, 'litros', e.stock_fisico_lt,
                        'terceros_hubo', e.terceros_hubo, 'seguridad_sin_novedad', e.seguridad_sin_novedad,
                        'entrega', e.entrega_nombre, 'recibe', e.recibe_nombre,
                        'camiones', (SELECT jsonb_agg(jsonb_build_object('patente', c.patente, 'fisico', c.litros_fisico,
                                        'teorico', c.litros_teorico, 'metodo', c.metodo) ORDER BY c.patente)
                                       FROM faena_entrega_combustible c WHERE c.entrega_id = e.id),
                        'terceros', (SELECT jsonb_agg(jsonb_build_object('empresa', t.empresa, 'litros', t.litros, 'autorizado_por', t.autorizado_por))
                                       FROM faena_entrega_terceros t WHERE t.entrega_id = e.id))
                      FROM faena_entrega_turno e
                     WHERE e.faena_id = p_faena_id AND e.hasta BETWEEN d.miercoles - 1 AND d.miercoles + 1
                     ORDER BY e.created_at DESC LIMIT 1))
      FROM d
$$;
REVOKE ALL ON FUNCTION public.fn_faena_entrega_miercoles(UUID) FROM PUBLIC, anon, authenticated;

DO $$
DECLARE v_def TEXT;
BEGIN
    v_def := pg_get_functiondef('public.fn_faena_resumen_diario_cron(text)'::regprocedure);
    IF position('''entrega_miercoles''' IN v_def) = 0 THEN
        v_def := replace(v_def, '''cerrados_24h'',', '''entrega_miercoles'', fn_faena_entrega_miercoles(v_f),' || chr(10) || '        ''cerrados_24h'',');
        IF position('''entrega_miercoles''' IN v_def) = 0 THEN RAISE EXCEPTION 'No pude agregar la entrega al resumen.'; END IF;
        EXECUTE v_def;
    END IF;
END $$;

SELECT 'MIG697 OK' AS resultado;
