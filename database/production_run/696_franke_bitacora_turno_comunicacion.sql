-- ============================================================================
-- MIG696 · Franke: bitácora del turno, pendientes que se arrastran, acuse
--          «leído y entendido» y resumen diario — comunicación entre supervisores
-- ----------------------------------------------------------------------------
-- Manuel, 15-11-2026: «tengo quejas de que los supervisores no se comunican».
-- Investigación (reports/Cambio de turno faena Franke.md): HSE UK, Energy
-- Institute, CCPS y las fallas de Piper Alpha/Texas City/Buncefield coinciden:
-- entrega escrita + verbal, contenido mínimo fijo, pendientes con dueño que se
-- arrastran hasta cerrarse, acuse del que recibe, «archivo de lectura» al
-- volver de un descanso largo, y medir. Los productos líderes (j5, Seqonis/
-- Shiftconnector, Innovapptive) copian lo mismo: acuse por ítem con nombre y
-- hora, ítems abiertos que se arrastran, escalamiento si nadie acusa.
--
-- DIAGNÓSTICO: la entrega de turno de MIG362 se usó UNA vez (24-08, prueba).
-- Es semanal, pesada y sin señal no funciona. Esto agrega el canal DIARIO y
-- liviano que faltaba (escribir una novedad = 10 segundos, sin señal), y el
-- resumen por correo para que el supervisor que está de descanso también sepa.
-- ============================================================================

-- ── 1. Quién es supervisor de qué turno ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.faena_supervisores (
    faena_id   UUID NOT NULL REFERENCES public.faenas(id) ON DELETE CASCADE,
    usuario_id UUID NOT NULL REFERENCES public.usuarios_perfil(id) ON DELETE CASCADE,
    turno      TEXT NOT NULL CHECK (turno IN ('A', 'B')),
    activo     BOOLEAN NOT NULL DEFAULT true,
    PRIMARY KEY (faena_id, usuario_id)
);
ALTER TABLE public.faena_supervisores ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS faena_sup_ver ON public.faena_supervisores;
CREATE POLICY faena_sup_ver ON public.faena_supervisores FOR SELECT TO authenticated USING (true);

INSERT INTO public.faena_supervisores (faena_id, usuario_id, turno)
SELECT '69202766-770b-4f81-ab86-35544fd3176e', u.id, x.turno
  FROM (VALUES ('jsimon@pillado.cl', 'A'), ('earqueros@pillado.cl', 'A'), ('mespinosa@pillado.cl', 'B')) AS x(email, turno)
  JOIN public.usuarios_perfil u ON u.email = x.email
ON CONFLICT (faena_id, usuario_id) DO NOTHING;

-- Puede participar: personal de la faena o jefatura.
CREATE OR REPLACE FUNCTION public.fn_faena_comunicacion_puede(p_faena_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1 FROM usuarios_perfil u WHERE u.id = auth.uid() AND coalesce(u.activo, true)
           AND (u.faena_id = p_faena_id
                OR u.rol::text IN ('administrador', 'gerencia', 'subgerente_operaciones', 'jefe_operaciones', 'jefe_mantenimiento')))
$$;

CREATE OR REPLACE FUNCTION public.fn_faena_turno_de(p_faena_id UUID, p_usuario UUID)
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT coalesce(
        (SELECT turno FROM faena_supervisores WHERE faena_id = p_faena_id AND usuario_id = p_usuario AND activo),
        (SELECT CASE WHEN cargo ILIKE '%turno A%' THEN 'A' WHEN cargo ILIKE '%turno B%' THEN 'B' END
           FROM usuarios_perfil WHERE id = p_usuario))
$$;

-- ── 2. Bitácora: novedades del turno ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.faena_novedades (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id     UUID NOT NULL REFERENCES public.faenas(id) ON DELETE CASCADE,
    turno        TEXT,
    fecha_hora   TIMESTAMPTZ NOT NULL DEFAULT NOW(),     -- cuándo pasó (puede venir de la cola sin señal)
    autor_id     UUID REFERENCES public.usuarios_perfil(id),
    autor_nombre TEXT,
    categoria    TEXT NOT NULL CHECK (categoria IN ('seguridad', 'equipo', 'operacion', 'combustible', 'bodega', 'personal', 'mandante', 'otro')),
    severidad    TEXT NOT NULL DEFAULT 'normal' CHECK (severidad IN ('normal', 'importante', 'critica')),
    texto        TEXT NOT NULL CHECK (length(btrim(texto)) >= 3),
    activo_id    UUID REFERENCES public.activos(id) ON DELETE SET NULL,
    foto_url     TEXT,
    client_uuid  UUID UNIQUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_faena_novedades_faena_fecha ON public.faena_novedades (faena_id, fecha_hora DESC);
ALTER TABLE public.faena_novedades ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS faena_nov_ver ON public.faena_novedades;
CREATE POLICY faena_nov_ver ON public.faena_novedades FOR SELECT TO authenticated USING (public.fn_faena_comunicacion_puede(faena_id));

CREATE TABLE IF NOT EXISTS public.faena_novedad_acuses (
    novedad_id UUID NOT NULL REFERENCES public.faena_novedades(id) ON DELETE CASCADE,
    usuario_id UUID NOT NULL REFERENCES public.usuarios_perfil(id) ON DELETE CASCADE,
    acuse_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (novedad_id, usuario_id)
);
ALTER TABLE public.faena_novedad_acuses ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS faena_nov_acu_ver ON public.faena_novedad_acuses;
CREATE POLICY faena_nov_acu_ver ON public.faena_novedad_acuses FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM faena_novedades n WHERE n.id = novedad_id AND public.fn_faena_comunicacion_puede(n.faena_id)));

-- ── 3. Pendientes con dueño que se arrastran hasta cerrarse ─────────────────
CREATE TABLE IF NOT EXISTS public.faena_pendientes (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id        UUID NOT NULL REFERENCES public.faenas(id) ON DELETE CASCADE,
    titulo          TEXT NOT NULL CHECK (length(btrim(titulo)) >= 3),
    detalle         TEXT,
    prioridad       TEXT NOT NULL DEFAULT 'media' CHECK (prioridad IN ('alta', 'media', 'baja')),
    responsable_turno TEXT CHECK (responsable_turno IN ('A', 'B', 'ambos')),
    vence           DATE,
    contingencia    TEXT,          -- «si pasa X, hacer Y» (I-PASS)
    activo_id       UUID REFERENCES public.activos(id) ON DELETE SET NULL,
    estado          TEXT NOT NULL DEFAULT 'abierto' CHECK (estado IN ('abierto', 'cerrado')),
    creado_por      UUID REFERENCES public.usuarios_perfil(id),
    creado_nombre   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cerrado_por     UUID REFERENCES public.usuarios_perfil(id),
    cerrado_nombre  TEXT,
    cerrado_at      TIMESTAMPTZ,
    cierre_nota     TEXT,
    client_uuid     UUID UNIQUE
);
CREATE INDEX IF NOT EXISTS ix_faena_pend_abiertos ON public.faena_pendientes (faena_id) WHERE estado = 'abierto';
ALTER TABLE public.faena_pendientes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS faena_pend_ver ON public.faena_pendientes;
CREATE POLICY faena_pend_ver ON public.faena_pendientes FOR SELECT TO authenticated USING (public.fn_faena_comunicacion_puede(faena_id));

CREATE TABLE IF NOT EXISTS public.faena_pendiente_notas (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pendiente_id UUID NOT NULL REFERENCES public.faena_pendientes(id) ON DELETE CASCADE,
    autor_id     UUID REFERENCES public.usuarios_perfil(id),
    autor_nombre TEXT,
    texto        TEXT NOT NULL CHECK (length(btrim(texto)) >= 2),
    client_uuid  UUID UNIQUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.faena_pendiente_notas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS faena_pend_nota_ver ON public.faena_pendiente_notas;
CREATE POLICY faena_pend_nota_ver ON public.faena_pendiente_notas FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM faena_pendientes p WHERE p.id = pendiente_id AND public.fn_faena_comunicacion_puede(p.faena_id)));

-- ── 4. Escribir (todo idempotente por client_uuid: la cola sin señal reintenta) ──
CREATE OR REPLACE FUNCTION public.rpc_faena_novedad_crear(
    p_faena_id UUID, p_categoria TEXT, p_severidad TEXT, p_texto TEXT, p_activo_id UUID,
    p_foto_url TEXT, p_fecha_hora TIMESTAMPTZ, p_client_uuid UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id UUID;
BEGIN
    IF NOT fn_faena_comunicacion_puede(p_faena_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    SELECT id INTO v_id FROM faena_novedades WHERE client_uuid = p_client_uuid;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;
    INSERT INTO faena_novedades (faena_id, turno, fecha_hora, autor_id, autor_nombre, categoria, severidad, texto,
                                 activo_id, foto_url, client_uuid)
    VALUES (p_faena_id, fn_faena_turno_de(p_faena_id, auth.uid()), least(coalesce(p_fecha_hora, NOW()), NOW()),
            auth.uid(), (SELECT nombre_completo FROM usuarios_perfil WHERE id = auth.uid()),
            p_categoria, coalesce(p_severidad, 'normal'), btrim(p_texto), p_activo_id, p_foto_url, p_client_uuid)
    RETURNING id INTO v_id;
    -- Quien escribe ya la leyó.
    INSERT INTO faena_novedad_acuses (novedad_id, usuario_id) VALUES (v_id, auth.uid()) ON CONFLICT DO NOTHING;
    RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.rpc_faena_novedad_crear(UUID, TEXT, TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_faena_novedad_crear(UUID, TEXT, TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ, UUID) TO authenticated;

-- «Leído y entendido»: una o varias novedades.
CREATE OR REPLACE FUNCTION public.rpc_faena_novedad_acusar(p_ids UUID[])
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_n INT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    INSERT INTO faena_novedad_acuses (novedad_id, usuario_id)
    SELECT n.id, auth.uid() FROM faena_novedades n
     WHERE n.id = ANY(p_ids) AND fn_faena_comunicacion_puede(n.faena_id)
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.rpc_faena_novedad_acusar(UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_faena_novedad_acusar(UUID[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_faena_pendiente_crear(
    p_faena_id UUID, p_titulo TEXT, p_detalle TEXT, p_prioridad TEXT, p_responsable_turno TEXT,
    p_vence DATE, p_contingencia TEXT, p_activo_id UUID, p_client_uuid UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id UUID;
BEGIN
    IF NOT fn_faena_comunicacion_puede(p_faena_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    SELECT id INTO v_id FROM faena_pendientes WHERE client_uuid = p_client_uuid;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;
    INSERT INTO faena_pendientes (faena_id, titulo, detalle, prioridad, responsable_turno, vence, contingencia, activo_id,
                                  creado_por, creado_nombre, client_uuid)
    VALUES (p_faena_id, btrim(p_titulo), nullif(btrim(p_detalle), ''), coalesce(p_prioridad, 'media'),
            coalesce(p_responsable_turno, 'ambos'), p_vence, nullif(btrim(p_contingencia), ''), p_activo_id,
            auth.uid(), (SELECT nombre_completo FROM usuarios_perfil WHERE id = auth.uid()), p_client_uuid)
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.rpc_faena_pendiente_crear(UUID, TEXT, TEXT, TEXT, TEXT, DATE, TEXT, UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_faena_pendiente_crear(UUID, TEXT, TEXT, TEXT, TEXT, DATE, TEXT, UUID, UUID) TO authenticated;

-- Nota de avance o cierre. Cerrar exige decir cómo se resolvió.
CREATE OR REPLACE FUNCTION public.rpc_faena_pendiente_nota(p_pendiente_id UUID, p_texto TEXT, p_cerrar BOOLEAN, p_client_uuid UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_p faena_pendientes; v_nombre TEXT;
BEGIN
    SELECT * INTO v_p FROM faena_pendientes WHERE id = p_pendiente_id;
    IF v_p.id IS NULL OR NOT fn_faena_comunicacion_puede(v_p.faena_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    IF EXISTS (SELECT 1 FROM faena_pendiente_notas WHERE client_uuid = p_client_uuid) THEN RETURN; END IF;
    IF p_cerrar AND length(btrim(coalesce(p_texto, ''))) < 5 THEN RAISE EXCEPTION 'Para cerrar, diga cómo se resolvió.'; END IF;
    SELECT nombre_completo INTO v_nombre FROM usuarios_perfil WHERE id = auth.uid();
    INSERT INTO faena_pendiente_notas (pendiente_id, autor_id, autor_nombre, texto, client_uuid)
    VALUES (p_pendiente_id, auth.uid(), v_nombre, CASE WHEN p_cerrar THEN 'CERRADO: ' ELSE '' END || btrim(p_texto), p_client_uuid);
    IF p_cerrar AND v_p.estado = 'abierto' THEN
        UPDATE faena_pendientes SET estado = 'cerrado', cerrado_por = auth.uid(), cerrado_nombre = v_nombre,
               cerrado_at = NOW(), cierre_nota = btrim(p_texto)
         WHERE id = p_pendiente_id;
    END IF;
END $$;
REVOKE ALL ON FUNCTION public.rpc_faena_pendiente_nota(UUID, TEXT, BOOLEAN, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_faena_pendiente_nota(UUID, TEXT, BOOLEAN, UUID) TO authenticated;

-- ── 5. Leer: la bitácora, los pendientes y el «archivo de lectura» ──────────
-- Lo que importa leer: críticas e importantes que YO no he acusado.
CREATE OR REPLACE FUNCTION public.rpc_faena_comunicacion(p_faena_id UUID, p_dias INT DEFAULT 7)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_desde TIMESTAMPTZ := NOW() - make_interval(days => greatest(1, least(coalesce(p_dias, 7), 60)));
BEGIN
    IF NOT fn_faena_comunicacion_puede(p_faena_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    RETURN jsonb_build_object(
        'generado_at', NOW(),
        'mi_turno', fn_faena_turno_de(p_faena_id, auth.uid()),
        'ciclo', (SELECT jsonb_build_object('turno', c.turno, 'fecha_inicio', c.fecha_inicio, 'fecha_fin', c.fecha_fin)
                    FROM faena_ciclo c WHERE c.faena_id = p_faena_id AND c.estado = 'abierto' LIMIT 1),
        'novedades', (SELECT coalesce(jsonb_agg(x ORDER BY x->>'fecha_hora' DESC), '[]'::jsonb) FROM (
            SELECT jsonb_build_object(
                     'id', n.id, 'fecha_hora', n.fecha_hora, 'turno', n.turno, 'autor', n.autor_nombre, 'autor_id', n.autor_id,
                     'categoria', n.categoria, 'severidad', n.severidad, 'texto', n.texto, 'foto_url', n.foto_url,
                     'equipo', a.patente,
                     'leida_por_mi', EXISTS (SELECT 1 FROM faena_novedad_acuses x WHERE x.novedad_id = n.id AND x.usuario_id = auth.uid()),
                     'acuses', (SELECT coalesce(jsonb_agg(jsonb_build_object('nombre', u.nombre_completo, 'at', x.acuse_at) ORDER BY x.acuse_at), '[]'::jsonb)
                                  FROM faena_novedad_acuses x JOIN usuarios_perfil u ON u.id = x.usuario_id
                                 WHERE x.novedad_id = n.id AND x.usuario_id IS DISTINCT FROM n.autor_id)) AS x
              FROM faena_novedades n LEFT JOIN activos a ON a.id = n.activo_id
             WHERE n.faena_id = p_faena_id AND n.fecha_hora >= v_desde
             ORDER BY n.fecha_hora DESC LIMIT 300) q),
        -- Las críticas sin leer no caducan con la ventana: se arrastran.
        'por_leer', (SELECT coalesce(jsonb_agg(n.id), '[]'::jsonb) FROM faena_novedades n
                      WHERE n.faena_id = p_faena_id AND n.severidad IN ('critica', 'importante')
                        AND n.fecha_hora >= NOW() - interval '30 days'
                        AND NOT EXISTS (SELECT 1 FROM faena_novedad_acuses x WHERE x.novedad_id = n.id AND x.usuario_id = auth.uid())),
        'pendientes', (SELECT coalesce(jsonb_agg(x ORDER BY (x->>'orden')::int, x->>'vence' NULLS LAST, x->>'created_at'), '[]'::jsonb) FROM (
            SELECT jsonb_build_object(
                     'id', p.id, 'titulo', p.titulo, 'detalle', p.detalle, 'prioridad', p.prioridad,
                     'responsable_turno', p.responsable_turno, 'vence', p.vence, 'contingencia', p.contingencia,
                     'equipo', a.patente, 'estado', p.estado, 'creado_nombre', p.creado_nombre, 'created_at', p.created_at,
                     'cerrado_nombre', p.cerrado_nombre, 'cerrado_at', p.cerrado_at, 'cierre_nota', p.cierre_nota,
                     'vencido', p.estado = 'abierto' AND p.vence < (NOW() AT TIME ZONE 'America/Santiago')::date,
                     'orden', CASE WHEN p.estado = 'cerrado' THEN 9 WHEN p.prioridad = 'alta' THEN 1 WHEN p.prioridad = 'media' THEN 2 ELSE 3 END,
                     'notas', (SELECT coalesce(jsonb_agg(jsonb_build_object('autor', t.autor_nombre, 'texto', t.texto, 'at', t.created_at) ORDER BY t.created_at), '[]'::jsonb)
                                 FROM faena_pendiente_notas t WHERE t.pendiente_id = p.id)) AS x
              FROM faena_pendientes p LEFT JOIN activos a ON a.id = p.activo_id
             WHERE p.faena_id = p_faena_id AND (p.estado = 'abierto' OR p.cerrado_at >= v_desde)) q),
        'equipos', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'patente', a.patente) ORDER BY a.patente), '[]'::jsonb)
                      FROM activos a WHERE a.patente IN ('HHWB-44', 'LCSX-78', 'HHWB-42', 'LLBP-96')),
        'resumen', jsonb_build_object(
            'novedades', (SELECT count(*) FROM faena_novedades WHERE faena_id = p_faena_id AND fecha_hora >= v_desde),
            'criticas', (SELECT count(*) FROM faena_novedades WHERE faena_id = p_faena_id AND fecha_hora >= v_desde AND severidad = 'critica'),
            'pendientes_abiertos', (SELECT count(*) FROM faena_pendientes WHERE faena_id = p_faena_id AND estado = 'abierto'),
            'pendientes_cerrados', (SELECT count(*) FROM faena_pendientes WHERE faena_id = p_faena_id AND cerrado_at >= v_desde),
            'bodega_bajo_minimo', (SELECT count(*) FROM bodega_alertas_stock a JOIN bodegas b ON b.id = a.bodega_id
                                    WHERE b.faena_id = p_faena_id AND a.estado = 'abierta'),
            'combustible_lt', (SELECT round(sum(stock_teorico_lt)) FROM v_comb_faena_estanque_ahora WHERE faena_id = p_faena_id AND activo)));
END $$;
REVOKE ALL ON FUNCTION public.rpc_faena_comunicacion(UUID, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_faena_comunicacion(UUID, INT) TO authenticated;

-- ── 6. Indicadores para jefatura (uso y calidad de la comunicación) ─────────
CREATE OR REPLACE FUNCTION public.rpc_faena_comunicacion_indicadores(p_faena_id UUID, p_dias INT DEFAULT 30)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_desde TIMESTAMPTZ := NOW() - make_interval(days => greatest(1, least(coalesce(p_dias, 30), 180)));
BEGIN
    IF NOT fn_faena_comunicacion_puede(p_faena_id) THEN RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501'; END IF;
    RETURN jsonb_build_object(
        'dias', p_dias,
        'por_persona', (SELECT coalesce(jsonb_agg(x ORDER BY x->>'turno', x->>'nombre'), '[]'::jsonb) FROM (
            SELECT jsonb_build_object(
                     'nombre', u.nombre_completo, 'cargo', u.cargo, 'turno', fn_faena_turno_de(p_faena_id, u.id),
                     'novedades', (SELECT count(*) FROM faena_novedades n WHERE n.autor_id = u.id AND n.faena_id = p_faena_id AND n.fecha_hora >= v_desde),
                     'dias_con_novedad', (SELECT count(DISTINCT (n.fecha_hora AT TIME ZONE 'America/Santiago')::date) FROM faena_novedades n
                                           WHERE n.autor_id = u.id AND n.faena_id = p_faena_id AND n.fecha_hora >= v_desde),
                     'pendientes_creados', (SELECT count(*) FROM faena_pendientes p WHERE p.creado_por = u.id AND p.faena_id = p_faena_id AND p.created_at >= v_desde),
                     'pendientes_cerrados', (SELECT count(*) FROM faena_pendientes p WHERE p.cerrado_por = u.id AND p.faena_id = p_faena_id AND p.cerrado_at >= v_desde),
                     'criticas_sin_leer', (SELECT count(*) FROM faena_novedades n WHERE n.faena_id = p_faena_id AND n.severidad = 'critica'
                                            AND n.fecha_hora >= v_desde AND n.autor_id IS DISTINCT FROM u.id
                                            AND NOT EXISTS (SELECT 1 FROM faena_novedad_acuses x WHERE x.novedad_id = n.id AND x.usuario_id = u.id)),
                     'horas_promedio_acuse', (SELECT round(avg(extract(epoch FROM x.acuse_at - n.fecha_hora)) / 3600, 1)
                                               FROM faena_novedad_acuses x JOIN faena_novedades n ON n.id = x.novedad_id
                                              WHERE x.usuario_id = u.id AND n.autor_id IS DISTINCT FROM u.id AND n.faena_id = p_faena_id
                                                AND n.severidad IN ('critica', 'importante') AND n.fecha_hora >= v_desde),
                     'entregas_firmadas', (SELECT count(*) FROM faena_entrega_turno e WHERE e.faena_id = p_faena_id AND e.entrega_por = u.id AND e.entregado_at >= v_desde),
                     'entregas_recibidas', (SELECT count(*) FROM faena_entrega_turno e WHERE e.faena_id = p_faena_id AND e.recibe_por = u.id AND e.recibido_at >= v_desde)) AS x
              FROM usuarios_perfil u
             WHERE u.faena_id = p_faena_id AND coalesce(u.activo, true)
               AND u.rol::text IN ('supervisor', 'tecnico_mantenimiento', 'operador_combustible')) q),
        'pendientes', jsonb_build_object(
            'abiertos', (SELECT count(*) FROM faena_pendientes WHERE faena_id = p_faena_id AND estado = 'abierto'),
            'vencidos', (SELECT count(*) FROM faena_pendientes WHERE faena_id = p_faena_id AND estado = 'abierto'
                          AND vence < (NOW() AT TIME ZONE 'America/Santiago')::date),
            'dias_promedio_cierre', (SELECT round(avg(extract(epoch FROM cerrado_at - created_at)) / 86400, 1) FROM faena_pendientes
                                      WHERE faena_id = p_faena_id AND cerrado_at >= v_desde),
            'mas_antiguo_dias', (SELECT extract(day FROM NOW() - min(created_at))::int FROM faena_pendientes
                                  WHERE faena_id = p_faena_id AND estado = 'abierto')),
        'dias_sin_novedad', (SELECT count(*) FROM generate_series((v_desde AT TIME ZONE 'America/Santiago')::date,
                                                                   (NOW() AT TIME ZONE 'America/Santiago')::date, '1 day') d
                              WHERE NOT EXISTS (SELECT 1 FROM faena_novedades n WHERE n.faena_id = p_faena_id
                                                  AND (n.fecha_hora AT TIME ZONE 'America/Santiago')::date = d::date)));
END $$;
REVOKE ALL ON FUNCTION public.rpc_faena_comunicacion_indicadores(UUID, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_faena_comunicacion_indicadores(UUID, INT) TO authenticated;

-- ── 7. Resumen diario por correo (07:00 Chile) ──────────────────────────────
-- A los supervisores de AMBOS turnos (el que descansa también se entera) + Manuel.
CREATE OR REPLACE FUNCTION public.fn_faena_resumen_diario_cron(p_secreto TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_f UUID := '69202766-770b-4f81-ab86-35544fd3176e';
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501';
    END IF;
    RETURN jsonb_build_object(
        'faena', (SELECT nombre FROM faenas WHERE id = v_f),
        'para', (SELECT coalesce(jsonb_agg(DISTINCT u.email), '[]') FROM faena_supervisores s JOIN usuarios_perfil u ON u.id = s.usuario_id
                  WHERE s.faena_id = v_f AND s.activo AND u.email IS NOT NULL),
        'cc', jsonb_build_array('manuel.olivares@pilladoempresas.cl'),
        'ciclo', (SELECT jsonb_build_object('turno', c.turno, 'fecha_inicio', c.fecha_inicio, 'fecha_fin', c.fecha_fin)
                    FROM faena_ciclo c WHERE c.faena_id = v_f AND c.estado = 'abierto' LIMIT 1),
        'novedades_24h', (SELECT coalesce(jsonb_agg(jsonb_build_object('fecha_hora', n.fecha_hora, 'autor', n.autor_nombre, 'turno', n.turno,
                              'categoria', n.categoria, 'severidad', n.severidad, 'texto', n.texto, 'equipo', a.patente) ORDER BY n.fecha_hora), '[]'::jsonb)
                             FROM faena_novedades n LEFT JOIN activos a ON a.id = n.activo_id
                            WHERE n.faena_id = v_f AND n.fecha_hora >= NOW() - interval '24 hours'),
        -- Críticas de más de 12 h que algún supervisor (distinto del autor) no ha leído.
        -- Las 12 h corren desde que LLEGÓ al servidor (created_at), no desde que se
        -- escribió sin señal: si no, una novedad de ayer sincronizada hoy escalaría al tiro.
        'criticas_sin_acuse', (SELECT coalesce(jsonb_agg(jsonb_build_object('texto', n.texto, 'autor', n.autor_nombre, 'fecha_hora', n.fecha_hora,
                                   'faltan', (SELECT jsonb_agg(u.nombre_completo) FROM faena_supervisores s JOIN usuarios_perfil u ON u.id = s.usuario_id
                                               WHERE s.faena_id = v_f AND s.activo AND s.usuario_id IS DISTINCT FROM n.autor_id
                                                 AND NOT EXISTS (SELECT 1 FROM faena_novedad_acuses x WHERE x.novedad_id = n.id AND x.usuario_id = s.usuario_id)))), '[]'::jsonb)
                                 FROM faena_novedades n
                                WHERE n.faena_id = v_f AND n.severidad = 'critica'
                                  AND n.created_at BETWEEN NOW() - interval '14 days' AND NOW() - interval '12 hours'
                                  AND EXISTS (SELECT 1 FROM faena_supervisores s WHERE s.faena_id = v_f AND s.activo
                                                AND s.usuario_id IS DISTINCT FROM n.autor_id
                                                AND NOT EXISTS (SELECT 1 FROM faena_novedad_acuses x WHERE x.novedad_id = n.id AND x.usuario_id = s.usuario_id))),
        'pendientes', (SELECT coalesce(jsonb_agg(jsonb_build_object('titulo', p.titulo, 'prioridad', p.prioridad, 'vence', p.vence,
                           'responsable_turno', p.responsable_turno, 'equipo', a.patente, 'creado_nombre', p.creado_nombre,
                           'dias', extract(day FROM NOW() - p.created_at)::int,
                           'vencido', p.vence < (NOW() AT TIME ZONE 'America/Santiago')::date)
                           ORDER BY (p.vence < (NOW() AT TIME ZONE 'America/Santiago')::date) DESC NULLS LAST,
                                    CASE p.prioridad WHEN 'alta' THEN 1 WHEN 'media' THEN 2 ELSE 3 END, p.created_at), '[]'::jsonb)
                         FROM faena_pendientes p LEFT JOIN activos a ON a.id = p.activo_id
                        WHERE p.faena_id = v_f AND p.estado = 'abierto'),
        'cerrados_24h', (SELECT count(*) FROM faena_pendientes WHERE faena_id = v_f AND cerrado_at >= NOW() - interval '24 hours'),
        'bodega_bajo_minimo', (SELECT coalesce(jsonb_agg(pr.nombre), '[]'::jsonb) FROM bodega_alertas_stock al
                                 JOIN bodegas b ON b.id = al.bodega_id JOIN productos pr ON pr.id = al.producto_id
                                WHERE b.faena_id = v_f AND al.estado = 'abierta'));
END $$;
REVOKE ALL ON FUNCTION public.fn_faena_resumen_diario_cron(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_faena_resumen_diario_cron(TEXT) TO anon, authenticated;

DO $$
DECLARE v_cmd TEXT;
BEGIN
    SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'documentos-flota-diario';
    IF v_cmd IS NULL OR position('/api/notificaciones/documentos-flota/' IN v_cmd) = 0 THEN
        RAISE EXCEPTION 'No encuentro el cron documentos-flota-diario para copiar su configuración.';
    END IF;
    PERFORM cron.unschedule(jobname) FROM cron.job WHERE jobname = 'franke-resumen-diario';
    PERFORM cron.schedule('franke-resumen-diario', '0 10 * * *',
        replace(v_cmd, '/api/notificaciones/documentos-flota/', '/api/notificaciones/faena-resumen/'));
END $$;

SELECT 'MIG696 OK' AS resultado;
