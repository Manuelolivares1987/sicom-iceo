-- ============================================================================
-- SICOM-ICEO | Migracion 125 — Control de Calidad: 2 Quality Gates + Diferidos
-- ----------------------------------------------------------------------------
-- Implementa el proceso de control de calidad de clase mundial (MRO aeronautico /
-- ISO 9001 8.5/8.6 / ISO 55001) sobre el taller:
--
--   GATE 1 — Chequeo cruzado de avance / fin de turno.
--     Una OT puede durar varios dias; el chequeo se ancla al AVANCE reportado.
--     Un par/supervisor (!= el mecanico que ejecuto) verifica el avance.
--     Segregacion de funciones (SoD) a nivel de datos: verificador != ejecutor
--     (regla literal FAA 14 CFR 121.371). Falla -> No Conformidad -> retrabajo.
--
--   GATE 2 — Auditoria de calidad pre-operativo (liberacion a servicio).
--     La ejecuta el rol dedicado 'auditor_calidad'. Aprueba CALIDAD TECNICA del
--     equipo + DOCUMENTACION. Su firma es la que produce el visto bueno de
--     calidad (= ready-to-rent para la compania) y crea la verificacion vigente.
--
--   DIFERIDOS (MEL) — Pendientes dejados por decision de compania.
--     Quedan en el historial del equipo con un PLAZO LIMITE =
--       MIN( proxima preventiva por horometro -> fecha estimada ,
--            vencimiento de revision tecnica ).
--     Ese minimo es el hito que "baja" el equipo. Al vencer se agrupan en una
--     OT (sin bloquear). Los pendientes CRITICOS / de seguridad NO son
--     diferibles y bloquean 'operativo' de inmediato (por severidad).
--
-- DEPENDENCIAS: activos, ordenes_trabajo, taller_ot_ejecuciones (mig 82),
--   verificaciones_disponibilidad (mig 25/45), no_conformidades (mig 25),
--   certificaciones (mig 04), planes_mantenimiento (mig 02), usuarios_perfil,
--   fn_user_rol() (mig 05).
--
-- IDEMPOTENTE: ADD VALUE IF NOT EXISTS / CREATE TABLE IF NOT EXISTS /
--   CREATE OR REPLACE / DROP ... IF EXISTS. Reentrante.
-- NOTA enum: 'auditor_calidad' se agrega al enum y solo se referencia como TEXT
--   (via fn_user_rol()) — nunca como literal casteado — para ser seguro dentro
--   de transaccion (ADD VALUE no usable en la misma tx en PG).
-- ============================================================================


-- ── 0. PRECHECKS ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_falta TEXT := NULL;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema='public' AND table_name='ordenes_trabajo') THEN
        v_falta := 'ordenes_trabajo'; END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema='public' AND table_name='taller_ot_ejecuciones') THEN
        v_falta := 'taller_ot_ejecuciones (mig 82)'; END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema='public' AND table_name='verificaciones_disponibilidad') THEN
        v_falta := 'verificaciones_disponibilidad (mig 25/45)'; END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema='public' AND table_name='no_conformidades') THEN
        v_falta := 'no_conformidades (mig 25)'; END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema='public' AND table_name='certificaciones') THEN
        v_falta := 'certificaciones (mig 04)'; END IF;
    IF v_falta IS NOT NULL THEN
        RAISE EXCEPTION 'STOP — falta dependencia: %. Aplicar migraciones previas.', v_falta;
    END IF;
END $$;


-- ── 1. ROL auditor_calidad ──────────────────────────────────────────────────
ALTER TYPE rol_usuario_enum ADD VALUE IF NOT EXISTS 'auditor_calidad';


-- ============================================================================
-- 2. GATE 1 — CHEQUEO CRUZADO DE AVANCE / FIN DE TURNO
-- ============================================================================

-- 2.1 Plantilla de items de chequeo cruzado
CREATE TABLE IF NOT EXISTS taller_chequeo_cruzado_plantilla_items (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    orden         INT  NOT NULL DEFAULT 0,
    categoria     VARCHAR(30) NOT NULL DEFAULT 'general',
    descripcion   TEXT NOT NULL,
    obligatorio   BOOLEAN NOT NULL DEFAULT true,
    requiere_foto BOOLEAN NOT NULL DEFAULT false,
    activo        BOOLEAN NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2.2 Cabecera del chequeo cruzado (uno por avance / cierre de turno)
CREATE TABLE IF NOT EXISTS taller_chequeos_cruzados (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ot_id               UUID NOT NULL REFERENCES ordenes_trabajo(id) ON DELETE CASCADE,
    activo_id           UUID NOT NULL REFERENCES activos(id),
    ejecucion_id        UUID REFERENCES taller_ot_ejecuciones(id) ON DELETE SET NULL,
    avance_evento_id    UUID REFERENCES taller_ot_ejecucion_eventos(id) ON DELETE SET NULL,
    fecha_turno         DATE NOT NULL DEFAULT CURRENT_DATE,
    turno               VARCHAR(10) NOT NULL DEFAULT 'dia',
    ejecutor_id         UUID NOT NULL REFERENCES usuarios_perfil(id),
    verificador_id      UUID REFERENCES usuarios_perfil(id),
    estado              VARCHAR(20) NOT NULL DEFAULT 'pendiente',
    avance_declarado    NUMERIC(5,2),
    avance_verificado   NUMERIC(5,2),
    items_total         INT NOT NULL DEFAULT 0,
    items_ok            INT NOT NULL DEFAULT 0,
    items_no_ok         INT NOT NULL DEFAULT 0,
    items_na            INT NOT NULL DEFAULT 0,
    puntaje             INT,
    observaciones       TEXT,
    no_conformidad_id   UUID REFERENCES no_conformidades(id),
    evidencias_fotos    JSONB NOT NULL DEFAULT '[]'::JSONB,
    firma_verificador_url TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by          UUID REFERENCES auth.users(id),
    verificado_at       TIMESTAMPTZ,
    CONSTRAINT chk_cc_estado CHECK (estado IN
        ('pendiente','aprobado','aprobado_con_obs','rechazado','anulado')),
    CONSTRAINT chk_cc_turno CHECK (turno IN ('dia','noche')),
    -- Segregacion de funciones: el que ejecuto el trabajo no puede verificarlo.
    CONSTRAINT chk_cc_sod CHECK (verificador_id IS NULL OR verificador_id <> ejecutor_id)
);
COMMENT ON CONSTRAINT chk_cc_sod ON taller_chequeos_cruzados IS
    'FAA 14 CFR 121.371: quien ejecuta el trabajo no puede ser quien lo verifica.';

CREATE INDEX IF NOT EXISTS idx_cc_estado     ON taller_chequeos_cruzados(estado);
CREATE INDEX IF NOT EXISTS idx_cc_ot         ON taller_chequeos_cruzados(ot_id);
CREATE INDEX IF NOT EXISTS idx_cc_activo     ON taller_chequeos_cruzados(activo_id);
CREATE INDEX IF NOT EXISTS idx_cc_fecha      ON taller_chequeos_cruzados(fecha_turno);

-- 2.3 Items del chequeo cruzado (copiados de la plantilla al crear)
CREATE TABLE IF NOT EXISTS taller_chequeo_cruzado_items (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chequeo_id    UUID NOT NULL REFERENCES taller_chequeos_cruzados(id) ON DELETE CASCADE,
    orden         INT  NOT NULL DEFAULT 0,
    categoria     VARCHAR(30) NOT NULL DEFAULT 'general',
    descripcion   TEXT NOT NULL,
    obligatorio   BOOLEAN NOT NULL DEFAULT true,
    requiere_foto BOOLEAN NOT NULL DEFAULT false,
    resultado     VARCHAR(10) NOT NULL DEFAULT 'pendiente',
    observacion   TEXT,
    foto_url      TEXT,
    completado_at TIMESTAMPTZ,
    completado_por UUID REFERENCES auth.users(id),
    CONSTRAINT chk_cci_resultado CHECK (resultado IN ('ok','no_ok','na','pendiente'))
);
CREATE INDEX IF NOT EXISTS idx_cci_chequeo ON taller_chequeo_cruzado_items(chequeo_id);


-- ============================================================================
-- 3. GATE 2 — AUDITORIA DE CALIDAD PRE-OPERATIVO
-- ============================================================================

-- 3.1 Plantilla de items de auditoria (tecnica + documentacion)
CREATE TABLE IF NOT EXISTS auditoria_calidad_plantilla_items (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    categoria   VARCHAR(20) NOT NULL DEFAULT 'tecnica',
    orden       INT  NOT NULL DEFAULT 0,
    descripcion TEXT NOT NULL,
    obligatorio BOOLEAN NOT NULL DEFAULT true,
    critico     BOOLEAN NOT NULL DEFAULT false,
    cert_tipo   TEXT,           -- si es item de documentacion: tipo de certificacion a validar
    activo      BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_acp_categoria CHECK (categoria IN ('tecnica','documentacion'))
);

-- 3.2 Cabecera de la auditoria de calidad
CREATE TABLE IF NOT EXISTS auditorias_calidad (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id           UUID NOT NULL REFERENCES activos(id),
    ot_id               UUID REFERENCES ordenes_trabajo(id),
    verificacion_id     UUID REFERENCES verificaciones_disponibilidad(id),
    auditor_id          UUID REFERENCES usuarios_perfil(id),
    iniciada_por        UUID REFERENCES usuarios_perfil(id),
    resultado           resultado_verificacion_enum NOT NULL DEFAULT 'pendiente',
    calidad_tecnica_ok  BOOLEAN,
    documentacion_ok    BOOLEAN,
    puntaje             INT,
    items_total         INT NOT NULL DEFAULT 0,
    items_ok            INT NOT NULL DEFAULT 0,
    items_no_ok         INT NOT NULL DEFAULT 0,
    items_na            INT NOT NULL DEFAULT 0,
    fecha_auditoria     TIMESTAMPTZ,
    vigente_hasta       TIMESTAMPTZ,
    dias_vigencia       INT NOT NULL DEFAULT 3,
    motivo_rechazo      TEXT,
    observaciones       TEXT,
    firma_auditor_url   TEXT,
    evidencias_fotos    JSONB NOT NULL DEFAULT '[]'::JSONB,
    no_conformidad_id   UUID REFERENCES no_conformidades(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by          UUID REFERENCES auth.users(id),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ac_activo    ON auditorias_calidad(activo_id);
CREATE INDEX IF NOT EXISTS idx_ac_resultado ON auditorias_calidad(resultado);

-- 3.3 Items de la auditoria
CREATE TABLE IF NOT EXISTS auditoria_calidad_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auditoria_id    UUID NOT NULL REFERENCES auditorias_calidad(id) ON DELETE CASCADE,
    categoria       VARCHAR(20) NOT NULL DEFAULT 'tecnica',
    orden           INT NOT NULL DEFAULT 0,
    descripcion     TEXT NOT NULL,
    obligatorio     BOOLEAN NOT NULL DEFAULT true,
    critico         BOOLEAN NOT NULL DEFAULT false,
    resultado       VARCHAR(10) NOT NULL DEFAULT 'pendiente',
    observacion     TEXT,
    foto_url        TEXT,
    referencia_cert_id UUID REFERENCES certificaciones(id),
    completado_at   TIMESTAMPTZ,
    completado_por  UUID REFERENCES auth.users(id),
    CONSTRAINT chk_aci_categoria CHECK (categoria IN ('tecnica','documentacion')),
    CONSTRAINT chk_aci_resultado CHECK (resultado IN ('ok','no_ok','na','pendiente'))
);
CREATE INDEX IF NOT EXISTS idx_aci_auditoria ON auditoria_calidad_items(auditoria_id);


-- ============================================================================
-- 4. DIFERIDOS / PENDIENTES (MEL)
-- ============================================================================

CREATE TABLE IF NOT EXISTS items_diferidos (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id            UUID NOT NULL REFERENCES activos(id),
    origen_tipo          VARCHAR(20) NOT NULL DEFAULT 'manual',
    origen_ot_id         UUID REFERENCES ordenes_trabajo(id),
    origen_auditoria_id  UUID REFERENCES auditorias_calidad(id),
    origen_chequeo_id    UUID REFERENCES taller_chequeos_cruzados(id),
    no_conformidad_id    UUID REFERENCES no_conformidades(id),
    descripcion          TEXT NOT NULL,
    sistema              VARCHAR(50),
    severidad            VARCHAR(20) NOT NULL DEFAULT 'media',
    es_seguridad         BOOLEAN NOT NULL DEFAULT false,
    diferible            BOOLEAN NOT NULL DEFAULT true,
    -- autorizacion del diferimiento (decision de compania)
    autorizado_por       UUID REFERENCES usuarios_perfil(id),
    autorizado_rol       VARCHAR(30),
    motivo_diferimiento  TEXT,
    fecha_diferimiento   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- calculo de plazo (MEL): MIN(proxima PM por horometro, vencimiento RT)
    horometro_diferimiento NUMERIC(12,1),
    pm_horometro_limite    NUMERIC(12,1),
    pm_fecha_estimada      DATE,
    rt_fecha_vencimiento   DATE,
    plazo_fecha_limite     DATE,
    plazo_origen           VARCHAR(20),   -- 'pm' | 'revision_tecnica' | 'sin_dato'
    -- resolucion
    estado               VARCHAR(20) NOT NULL DEFAULT 'pendiente',
    resuelto_ot_id       UUID REFERENCES ordenes_trabajo(id),
    resuelto_at          TIMESTAMPTZ,
    resuelto_por         UUID REFERENCES usuarios_perfil(id),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by           UUID REFERENCES auth.users(id),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_dif_severidad CHECK (severidad IN ('baja','media','alta','critica')),
    CONSTRAINT chk_dif_estado CHECK (estado IN
        ('pendiente','programado','ejecutado','vencido','cancelado')),
    CONSTRAINT chk_dif_origen CHECK (origen_tipo IN
        ('manual','ot','auditoria','chequeo_cruzado','no_conformidad'))
);
CREATE INDEX IF NOT EXISTS idx_dif_activo ON items_diferidos(activo_id);
CREATE INDEX IF NOT EXISTS idx_dif_estado ON items_diferidos(estado);
CREATE INDEX IF NOT EXISTS idx_dif_plazo  ON items_diferidos(plazo_fecha_limite);

COMMENT ON TABLE items_diferidos IS
    'Registro de pendientes/diferidos estilo MEL aeronautico. Plazo limite = '
    'MIN(proxima PM por horometro, vencimiento revision tecnica). Criticos/'
    'seguridad NO diferibles y bloquean operativo.';


-- ============================================================================
-- 5. HELPER — calculo de plazo de diferido (MEL)
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_calcular_plazo_diferido(p_activo_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
    v_horas_actual   NUMERIC;
    v_pm_limite      NUMERIC;
    v_avg_h_dia      NUMERIC;
    v_horas_rest     NUMERIC;
    v_pm_fecha       DATE;
    v_rt_fecha       DATE;
    v_plazo          DATE;
    v_origen         VARCHAR(20);
BEGIN
    SELECT COALESCE(horas_uso_actual, 0) INTO v_horas_actual
    FROM activos WHERE id = p_activo_id;

    -- Proxima preventiva por horometro. Robusto ante ultima_ejecucion_horas
    -- nula/0/desfasada (muchos planes auto-creados no la tienen): toma el
    -- SIGUIENTE multiplo de la frecuencia estrictamente por sobre el horometro
    -- actual, anclado en la ultima ejecucion conocida. Se queda con el menor
    -- entre los planes activos con frecuencia por horas.
    SELECT MIN(
        COALESCE(NULLIF(pm.ultima_ejecucion_horas, 0), 0)
        + (FLOOR((v_horas_actual - COALESCE(NULLIF(pm.ultima_ejecucion_horas, 0), 0))
                 / pm.frecuencia_horas) + 1) * pm.frecuencia_horas
    )
      INTO v_pm_limite
      FROM planes_mantenimiento pm
     WHERE pm.activo_id = p_activo_id
       AND pm.activo_plan = true
       AND pm.frecuencia_horas IS NOT NULL
       AND pm.frecuencia_horas > 0;

    -- Promedio de horas/dia ultimos 30 dias (fallback 8 h/dia).
    SELECT AVG(NULLIF(horas_operativas, 0)) INTO v_avg_h_dia
      FROM estado_diario_flota
     WHERE activo_id = p_activo_id
       AND fecha >= CURRENT_DATE - 30
       AND horas_operativas > 0;
    v_avg_h_dia := COALESCE(v_avg_h_dia, 8);
    IF v_avg_h_dia <= 0 THEN v_avg_h_dia := 8; END IF;

    IF v_pm_limite IS NOT NULL THEN
        v_horas_rest := GREATEST(v_pm_limite - v_horas_actual, 0);
        v_pm_fecha := CURRENT_DATE + CEIL(v_horas_rest / v_avg_h_dia)::INT;
    END IF;

    -- Vencimiento de revision tecnica mas proximo.
    SELECT MIN(fecha_vencimiento) INTO v_rt_fecha
      FROM certificaciones
     WHERE activo_id = p_activo_id
       AND tipo = 'revision_tecnica'
       AND fecha_vencimiento >= CURRENT_DATE;

    -- Plazo = el minimo de los dos (el que baja el equipo).
    IF v_pm_fecha IS NOT NULL AND v_rt_fecha IS NOT NULL THEN
        IF v_pm_fecha <= v_rt_fecha THEN v_plazo := v_pm_fecha; v_origen := 'pm';
        ELSE v_plazo := v_rt_fecha; v_origen := 'revision_tecnica'; END IF;
    ELSIF v_pm_fecha IS NOT NULL THEN
        v_plazo := v_pm_fecha; v_origen := 'pm';
    ELSIF v_rt_fecha IS NOT NULL THEN
        v_plazo := v_rt_fecha; v_origen := 'revision_tecnica';
    ELSE
        v_plazo := NULL; v_origen := 'sin_dato';
    END IF;

    RETURN jsonb_build_object(
        'horometro_actual',  v_horas_actual,
        'pm_horometro_limite', v_pm_limite,
        'pm_fecha_estimada', v_pm_fecha,
        'rt_fecha_vencimiento', v_rt_fecha,
        'plazo_fecha_limite', v_plazo,
        'plazo_origen', v_origen,
        'avg_horas_dia', ROUND(v_avg_h_dia, 1)
    );
END $$;


-- ============================================================================
-- 6. RPCs — GATE 1
-- ============================================================================

-- 6.1 Crear chequeo cruzado (al reportar avance / cerrar turno)
CREATE OR REPLACE FUNCTION fn_crear_chequeo_cruzado(
    p_ot_id            UUID,
    p_ejecucion_id     UUID DEFAULT NULL,
    p_avance_evento_id UUID DEFAULT NULL,
    p_avance_declarado NUMERIC DEFAULT NULL,
    p_turno            VARCHAR DEFAULT 'dia'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user      UUID := auth.uid();
    v_ot        RECORD;
    v_ejecutor  UUID;
    v_cheq_id   UUID;
    v_total     INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;

    SELECT id, activo_id, responsable_id INTO v_ot
    FROM ordenes_trabajo WHERE id = p_ot_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'OT % no existe', p_ot_id; END IF;

    -- Ejecutor = ejecutor de la ejecucion, o responsable de la OT, o usuario actual.
    v_ejecutor := NULL;
    IF p_ejecucion_id IS NOT NULL THEN
        SELECT ejecutor_id INTO v_ejecutor FROM taller_ot_ejecuciones WHERE id = p_ejecucion_id;
    END IF;
    v_ejecutor := COALESCE(v_ejecutor, v_ot.responsable_id, v_user);

    INSERT INTO taller_chequeos_cruzados (
        ot_id, activo_id, ejecucion_id, avance_evento_id, turno,
        ejecutor_id, avance_declarado, created_by
    ) VALUES (
        p_ot_id, v_ot.activo_id, p_ejecucion_id, p_avance_evento_id,
        COALESCE(p_turno,'dia'), v_ejecutor, p_avance_declarado, v_user
    ) RETURNING id INTO v_cheq_id;

    -- Copiar items activos de la plantilla.
    INSERT INTO taller_chequeo_cruzado_items
        (chequeo_id, orden, categoria, descripcion, obligatorio, requiere_foto)
    SELECT v_cheq_id, orden, categoria, descripcion, obligatorio, requiere_foto
    FROM taller_chequeo_cruzado_plantilla_items
    WHERE activo = true
    ORDER BY orden;

    GET DIAGNOSTICS v_total = ROW_COUNT;
    UPDATE taller_chequeos_cruzados SET items_total = v_total WHERE id = v_cheq_id;

    RETURN jsonb_build_object('chequeo_id', v_cheq_id, 'ejecutor_id', v_ejecutor,
                              'items_total', v_total);
END $$;

-- 6.2 Resolver chequeo cruzado (verificador != ejecutor)
CREATE OR REPLACE FUNCTION fn_resolver_chequeo_cruzado(
    p_chequeo_id       UUID,
    p_resultado        VARCHAR,       -- 'aprobado' | 'aprobado_con_obs' | 'rechazado'
    p_items            JSONB DEFAULT '[]'::JSONB,  -- [{id, resultado, observacion, foto_url}]
    p_avance_verificado NUMERIC DEFAULT NULL,
    p_observaciones    TEXT DEFAULT NULL,
    p_firma_url        TEXT DEFAULT NULL,
    p_evidencias       JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user      UUID := auth.uid();
    v_cheq      RECORD;
    v_item      JSONB;
    v_ok INT; v_no_ok INT; v_na INT; v_tot INT;
    v_nc_id     UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;

    SELECT * INTO v_cheq FROM taller_chequeos_cruzados WHERE id = p_chequeo_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Chequeo % no existe', p_chequeo_id; END IF;
    IF v_cheq.estado <> 'pendiente' THEN
        RAISE EXCEPTION 'El chequeo ya fue resuelto (estado %).', v_cheq.estado;
    END IF;

    -- SoD: el verificador no puede ser el ejecutor.
    IF v_user = v_cheq.ejecutor_id THEN
        RAISE EXCEPTION 'SEGREGACION DE FUNCIONES: el ejecutor del trabajo no puede '
            'realizar su propio chequeo cruzado (FAA 121.371).';
    END IF;
    IF p_resultado NOT IN ('aprobado','aprobado_con_obs','rechazado') THEN
        RAISE EXCEPTION 'Resultado invalido: %', p_resultado;
    END IF;

    -- Actualizar items recibidos.
    FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items,'[]'::JSONB)) LOOP
        UPDATE taller_chequeo_cruzado_items SET
            resultado     = COALESCE(v_item->>'resultado', resultado),
            observacion   = COALESCE(v_item->>'observacion', observacion),
            foto_url      = COALESCE(v_item->>'foto_url', foto_url),
            completado_at = NOW(),
            completado_por = v_user
        WHERE id = (v_item->>'id')::UUID AND chequeo_id = p_chequeo_id;
    END LOOP;

    SELECT COUNT(*) FILTER (WHERE resultado='ok'),
           COUNT(*) FILTER (WHERE resultado='no_ok'),
           COUNT(*) FILTER (WHERE resultado='na'),
           COUNT(*)
      INTO v_ok, v_no_ok, v_na, v_tot
      FROM taller_chequeo_cruzado_items WHERE chequeo_id = p_chequeo_id;

    -- Si se rechaza, abrir No Conformidad ligada.
    IF p_resultado = 'rechazado' THEN
        INSERT INTO no_conformidades (activo_id, ot_id, tipo, descripcion, fecha_evento,
                                      severidad, created_by)
        VALUES (v_cheq.activo_id, v_cheq.ot_id, 'otra',
                'Chequeo cruzado RECHAZADO (Gate 1). ' || COALESCE(p_observaciones,''),
                CURRENT_DATE, 'media', v_user)
        RETURNING id INTO v_nc_id;
    END IF;

    UPDATE taller_chequeos_cruzados SET
        verificador_id = v_user,
        estado = p_resultado,
        avance_verificado = COALESCE(p_avance_verificado, avance_verificado),
        observaciones = COALESCE(p_observaciones, observaciones),
        firma_verificador_url = COALESCE(p_firma_url, firma_verificador_url),
        evidencias_fotos = COALESCE(p_evidencias, evidencias_fotos),
        items_ok = v_ok, items_no_ok = v_no_ok, items_na = v_na, items_total = v_tot,
        puntaje = CASE WHEN v_tot > 0 THEN ROUND(100.0 * v_ok / v_tot) ELSE NULL END,
        no_conformidad_id = v_nc_id,
        verificado_at = NOW()
    WHERE id = p_chequeo_id;

    RETURN jsonb_build_object('chequeo_id', p_chequeo_id, 'estado', p_resultado,
        'items_ok', v_ok, 'items_no_ok', v_no_ok, 'no_conformidad_id', v_nc_id);
END $$;


-- ============================================================================
-- 7. RPCs — DIFERIDOS
-- ============================================================================

-- 7.1 Registrar/diferir un pendiente (autoriza auditor_calidad o jefe taller)
CREATE OR REPLACE FUNCTION fn_diferir_item(
    p_activo_id    UUID,
    p_descripcion  TEXT,
    p_sistema      VARCHAR DEFAULT NULL,
    p_severidad    VARCHAR DEFAULT 'media',
    p_es_seguridad BOOLEAN DEFAULT false,
    p_motivo       TEXT DEFAULT NULL,
    p_origen_tipo  VARCHAR DEFAULT 'manual',
    p_origen_ot_id UUID DEFAULT NULL,
    p_origen_auditoria_id UUID DEFAULT NULL,
    p_origen_chequeo_id   UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_rol    TEXT := fn_user_rol();
    v_plazo  JSONB;
    v_difble BOOLEAN;
    v_id     UUID;
    v_horas  NUMERIC;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('auditor_calidad','supervisor','administrador') THEN
        RAISE EXCEPTION 'Solo auditor de calidad o jefe de taller (supervisor) '
            'pueden diferir un item. Rol actual: %', v_rol;
    END IF;
    IF p_severidad NOT IN ('baja','media','alta','critica') THEN
        RAISE EXCEPTION 'Severidad invalida: %', p_severidad;
    END IF;

    -- Critico o de seguridad => NO diferible (bloquea operativo).
    v_difble := NOT (p_severidad = 'critica' OR p_es_seguridad);

    v_plazo := fn_calcular_plazo_diferido(p_activo_id);
    SELECT horas_uso_actual INTO v_horas FROM activos WHERE id = p_activo_id;

    INSERT INTO items_diferidos (
        activo_id, origen_tipo, origen_ot_id, origen_auditoria_id, origen_chequeo_id,
        descripcion, sistema, severidad, es_seguridad, diferible,
        autorizado_por, autorizado_rol, motivo_diferimiento,
        horometro_diferimiento, pm_horometro_limite, pm_fecha_estimada,
        rt_fecha_vencimiento, plazo_fecha_limite, plazo_origen,
        created_by
    ) VALUES (
        p_activo_id, COALESCE(p_origen_tipo,'manual'), p_origen_ot_id,
        p_origen_auditoria_id, p_origen_chequeo_id,
        p_descripcion, p_sistema, p_severidad, p_es_seguridad, v_difble,
        v_user, v_rol, p_motivo,
        v_horas,
        NULLIF(v_plazo->>'pm_horometro_limite','')::NUMERIC,
        NULLIF(v_plazo->>'pm_fecha_estimada','')::DATE,
        NULLIF(v_plazo->>'rt_fecha_vencimiento','')::DATE,
        CASE WHEN v_difble THEN NULLIF(v_plazo->>'plazo_fecha_limite','')::DATE ELSE NULL END,
        v_plazo->>'plazo_origen',
        v_user
    ) RETURNING id INTO v_id;

    RETURN jsonb_build_object('item_id', v_id, 'diferible', v_difble,
        'plazo_fecha_limite', CASE WHEN v_difble THEN v_plazo->>'plazo_fecha_limite' ELSE NULL END,
        'plazo_origen', v_plazo->>'plazo_origen',
        'bloquea_operativo', NOT v_difble);
END $$;

-- 7.2 Recalcular plazos de los diferidos de un equipo (cron/al volver el equipo)
CREATE OR REPLACE FUNCTION fn_recalcular_plazos_diferidos(p_activo_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_plazo JSONB;
    v_n     INT;
    v_venc  INT;
BEGIN
    v_plazo := fn_calcular_plazo_diferido(p_activo_id);

    UPDATE items_diferidos d SET
        pm_horometro_limite = NULLIF(v_plazo->>'pm_horometro_limite','')::NUMERIC,
        pm_fecha_estimada   = NULLIF(v_plazo->>'pm_fecha_estimada','')::DATE,
        rt_fecha_vencimiento = NULLIF(v_plazo->>'rt_fecha_vencimiento','')::DATE,
        plazo_fecha_limite  = NULLIF(v_plazo->>'plazo_fecha_limite','')::DATE,
        plazo_origen        = v_plazo->>'plazo_origen',
        updated_at = NOW()
    WHERE d.activo_id = p_activo_id AND d.estado = 'pendiente' AND d.diferible = true;
    GET DIAGNOSTICS v_n = ROW_COUNT;

    -- Marcar vencidos (plazo cumplido).
    UPDATE items_diferidos SET estado = 'vencido', updated_at = NOW()
    WHERE activo_id = p_activo_id AND estado = 'pendiente' AND diferible = true
      AND plazo_fecha_limite IS NOT NULL AND plazo_fecha_limite <= CURRENT_DATE;
    GET DIAGNOSTICS v_venc = ROW_COUNT;

    RETURN jsonb_build_object('recalculados', v_n, 'vencidos', v_venc, 'plazo', v_plazo);
END $$;

-- 7.3 Agrupar pendientes en una OT correctiva (al bajar el equipo). No bloquea.
CREATE OR REPLACE FUNCTION fn_generar_ot_pendientes(p_activo_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_act    RECORD;
    v_ot_id  UUID;
    v_lista  TEXT;
    v_n      INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;

    SELECT a.id, a.contrato_id, a.faena_id, a.patente, a.codigo
      INTO v_act FROM activos a WHERE a.id = p_activo_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Activo % no existe', p_activo_id; END IF;

    SELECT string_agg('- ' || descripcion ||
                COALESCE(' ('||sistema||')','') || ' [' || severidad || ']', E'\n'),
           COUNT(*)
      INTO v_lista, v_n
      FROM items_diferidos
     WHERE activo_id = p_activo_id AND estado IN ('pendiente','vencido');

    IF COALESCE(v_n,0) = 0 THEN
        RETURN jsonb_build_object('ot_id', NULL, 'pendientes', 0,
            'mensaje', 'No hay pendientes que agrupar.');
    END IF;
    IF v_act.contrato_id IS NULL OR v_act.faena_id IS NULL THEN
        RAISE EXCEPTION 'El activo % no tiene contrato/faena para crear OT.', p_activo_id;
    END IF;

    INSERT INTO ordenes_trabajo (
        tipo, contrato_id, faena_id, activo_id, prioridad, estado,
        observaciones, generada_automaticamente, created_by
    ) VALUES (
        'correctivo', v_act.contrato_id, v_act.faena_id, p_activo_id, 'alta', 'creada',
        'OT agrupada de pendientes/diferidos (MEL) — ' || v_n || ' item(s):' || E'\n' || v_lista,
        true, v_user
    ) RETURNING id INTO v_ot_id;

    UPDATE items_diferidos SET estado = 'programado', resuelto_ot_id = v_ot_id, updated_at = NOW()
    WHERE activo_id = p_activo_id AND estado IN ('pendiente','vencido');

    RETURN jsonb_build_object('ot_id', v_ot_id, 'pendientes', v_n);
END $$;


-- ============================================================================
-- 8. RPCs — GATE 2 (AUDITORIA)
-- ============================================================================

-- 8.1 Iniciar auditoria de calidad (crea cabecera + items; auto-evalua docs)
CREATE OR REPLACE FUNCTION fn_iniciar_auditoria_calidad(
    p_activo_id UUID,
    p_ot_id     UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_aud  UUID;
    v_tot  INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM activos WHERE id = p_activo_id) THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id; END IF;

    INSERT INTO auditorias_calidad (activo_id, ot_id, iniciada_por, created_by)
    VALUES (p_activo_id, p_ot_id, v_user, v_user)
    RETURNING id INTO v_aud;

    -- Copiar items de plantilla; auto-vincular documentacion a certificaciones.
    INSERT INTO auditoria_calidad_items
        (auditoria_id, categoria, orden, descripcion, obligatorio, critico,
         referencia_cert_id, resultado)
    SELECT
        v_aud, p.categoria, p.orden, p.descripcion, p.obligatorio, p.critico,
        c.cert_id,
        CASE
            WHEN p.categoria = 'documentacion' AND p.cert_tipo IS NOT NULL THEN
                CASE WHEN c.estado = 'vigente' THEN 'ok'
                     WHEN c.estado IS NULL THEN 'pendiente'
                     ELSE 'no_ok' END
            ELSE 'pendiente'
        END
    FROM auditoria_calidad_plantilla_items p
    LEFT JOIN LATERAL (
        SELECT cc.id AS cert_id, cc.estado AS estado
        FROM certificaciones cc
        WHERE cc.activo_id = p_activo_id
          AND p.cert_tipo IS NOT NULL
          AND cc.tipo::TEXT = p.cert_tipo
        ORDER BY cc.fecha_vencimiento DESC NULLS LAST
        LIMIT 1
    ) c ON true
    WHERE p.activo = true
    ORDER BY p.categoria, p.orden;

    GET DIAGNOSTICS v_tot = ROW_COUNT;
    UPDATE auditorias_calidad SET items_total = v_tot WHERE id = v_aud;

    RETURN jsonb_build_object('auditoria_id', v_aud, 'items_total', v_tot);
END $$;

-- 8.2 Resolver auditoria: aprobar (libera a operativo + crea verificacion) o rechazar
CREATE OR REPLACE FUNCTION fn_resolver_auditoria_calidad(
    p_auditoria_id UUID,
    p_resultado    VARCHAR,    -- 'aprobado' | 'aprobado_con_observaciones' | 'rechazado'
    p_items        JSONB DEFAULT '[]'::JSONB,
    p_motivo_rechazo TEXT DEFAULT NULL,
    p_observaciones  TEXT DEFAULT NULL,
    p_firma_url    TEXT DEFAULT NULL,
    p_evidencias   JSONB DEFAULT '[]'::JSONB,
    p_dias_vigencia INT DEFAULT 3
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_aud  RECORD;
    v_item JSONB;
    v_ok INT; v_no_ok INT; v_na INT; v_tot INT;
    v_crit_fail INT;
    v_tec_ok BOOLEAN; v_doc_ok BOOLEAN;
    v_pend_crit INT;
    v_verif_id UUID;
    v_nc_id UUID;
    v_vig TIMESTAMPTZ;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('auditor_calidad','administrador') THEN
        RAISE EXCEPTION 'Solo el rol auditor_calidad puede resolver la auditoria. Rol: %', v_rol;
    END IF;
    IF p_resultado NOT IN ('aprobado','aprobado_con_observaciones','rechazado') THEN
        RAISE EXCEPTION 'Resultado invalido: %', p_resultado;
    END IF;

    SELECT * INTO v_aud FROM auditorias_calidad WHERE id = p_auditoria_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Auditoria % no existe', p_auditoria_id; END IF;
    IF v_aud.resultado <> 'pendiente' THEN
        RAISE EXCEPTION 'La auditoria ya fue resuelta (estado %).', v_aud.resultado;
    END IF;

    -- SoD: el auditor no puede haber ejecutado trabajo en este equipo recientemente.
    IF EXISTS (
        SELECT 1 FROM taller_ot_ejecuciones e
        JOIN ordenes_trabajo o ON o.id = e.ot_id
        WHERE o.activo_id = v_aud.activo_id AND e.ejecutor_id = v_user
    ) THEN
        RAISE EXCEPTION 'SEGREGACION DE FUNCIONES: el auditor no puede haber ejecutado '
            'trabajo en este equipo. La auditoria debe ser independiente.';
    END IF;

    -- Actualizar items recibidos.
    FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items,'[]'::JSONB)) LOOP
        UPDATE auditoria_calidad_items SET
            resultado = COALESCE(v_item->>'resultado', resultado),
            observacion = COALESCE(v_item->>'observacion', observacion),
            foto_url = COALESCE(v_item->>'foto_url', foto_url),
            completado_at = NOW(), completado_por = v_user
        WHERE id = (v_item->>'id')::UUID AND auditoria_id = p_auditoria_id;
    END LOOP;

    SELECT COUNT(*) FILTER (WHERE resultado='ok'),
           COUNT(*) FILTER (WHERE resultado='no_ok'),
           COUNT(*) FILTER (WHERE resultado='na'),
           COUNT(*),
           COUNT(*) FILTER (WHERE resultado='no_ok' AND critico),
           bool_and(resultado IN ('ok','na')) FILTER (WHERE categoria='tecnica'),
           bool_and(resultado IN ('ok','na')) FILTER (WHERE categoria='documentacion')
      INTO v_ok, v_no_ok, v_na, v_tot, v_crit_fail, v_tec_ok, v_doc_ok
      FROM auditoria_calidad_items WHERE auditoria_id = p_auditoria_id;

    IF p_resultado IN ('aprobado','aprobado_con_observaciones') THEN
        -- No se puede aprobar con item critico en no_ok.
        IF COALESCE(v_crit_fail,0) > 0 THEN
            RAISE EXCEPTION 'No se puede aprobar: % item(es) CRITICO(s) en no_ok.', v_crit_fail;
        END IF;
        -- No se puede aprobar con pendientes criticos/seguridad sin resolver.
        SELECT COUNT(*) INTO v_pend_crit FROM items_diferidos
        WHERE activo_id = v_aud.activo_id AND estado='pendiente' AND diferible=false;
        IF v_pend_crit > 0 THEN
            RAISE EXCEPTION 'No se puede liberar: % pendiente(s) critico(s)/seguridad sin '
                'resolver (no diferibles).', v_pend_crit;
        END IF;

        v_vig := NOW() + (COALESCE(p_dias_vigencia,3) || ' days')::INTERVAL;

        -- Crear verificacion vigente (visto bueno de calidad = ready-to-rent).
        -- verificado_por NULL => satisface chk_doble_firma; aprobado_por = auditor.
        INSERT INTO verificaciones_disponibilidad (
            activo_id, ot_id, resultado, fecha_verificacion, vigente_hasta,
            dias_vigencia, aprobado_por, aprobado_en, firma_aprobador_url,
            items_total, items_ok, items_no_ok, items_na, puntaje_total
        ) VALUES (
            v_aud.activo_id, v_aud.ot_id, 'aprobado', NOW(), v_vig,
            COALESCE(p_dias_vigencia,3), v_user, NOW(), p_firma_url,
            v_tot, v_ok, v_no_ok, v_na,
            CASE WHEN v_tot>0 THEN ROUND(100.0*v_ok/v_tot) ELSE NULL END
        ) RETURNING id INTO v_verif_id;

        UPDATE auditorias_calidad SET
            auditor_id = v_user, resultado = p_resultado::resultado_verificacion_enum,
            calidad_tecnica_ok = COALESCE(v_tec_ok,true),
            documentacion_ok = COALESCE(v_doc_ok,true),
            items_ok=v_ok, items_no_ok=v_no_ok, items_na=v_na, items_total=v_tot,
            puntaje = CASE WHEN v_tot>0 THEN ROUND(100.0*v_ok/v_tot) ELSE NULL END,
            fecha_auditoria = NOW(), vigente_hasta = v_vig, dias_vigencia = COALESCE(p_dias_vigencia,3),
            verificacion_id = v_verif_id, observaciones = p_observaciones,
            firma_auditor_url = p_firma_url, evidencias_fotos = COALESCE(p_evidencias,evidencias_fotos),
            updated_at = NOW()
        WHERE id = p_auditoria_id;

        -- Liberar equipo a operativo (el trigger valida que no haya criticos pendientes).
        UPDATE activos SET estado = 'operativo',
            ultima_verificacion_id = v_verif_id, verificacion_vigente_hasta = v_vig,
            updated_at = NOW()
        WHERE id = v_aud.activo_id;

    ELSE  -- rechazado
        INSERT INTO no_conformidades (activo_id, ot_id, tipo, descripcion, fecha_evento,
                                      severidad, created_by)
        VALUES (v_aud.activo_id, v_aud.ot_id, 'otra',
                'Auditoria de calidad RECHAZADA (Gate 2). ' || COALESCE(p_motivo_rechazo,''),
                CURRENT_DATE, 'alta', v_user)
        RETURNING id INTO v_nc_id;

        UPDATE auditorias_calidad SET
            auditor_id = v_user, resultado = 'rechazado',
            calidad_tecnica_ok = COALESCE(v_tec_ok,false),
            documentacion_ok = COALESCE(v_doc_ok,false),
            items_ok=v_ok, items_no_ok=v_no_ok, items_na=v_na, items_total=v_tot,
            puntaje = CASE WHEN v_tot>0 THEN ROUND(100.0*v_ok/v_tot) ELSE NULL END,
            fecha_auditoria = NOW(), motivo_rechazo = p_motivo_rechazo,
            observaciones = p_observaciones, firma_auditor_url = p_firma_url,
            evidencias_fotos = COALESCE(p_evidencias,evidencias_fotos),
            no_conformidad_id = v_nc_id, updated_at = NOW()
        WHERE id = p_auditoria_id;
    END IF;

    RETURN jsonb_build_object('auditoria_id', p_auditoria_id, 'resultado', p_resultado,
        'verificacion_id', v_verif_id, 'no_conformidad_id', v_nc_id,
        'vigente_hasta', v_vig, 'items_ok', v_ok, 'items_no_ok', v_no_ok);
END $$;


-- ============================================================================
-- 9. TRIGGER — bloqueo de 'operativo' por pendiente critico/seguridad
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_validar_operativo_pendientes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_n INT;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.estado = 'operativo'
       AND OLD.estado IS DISTINCT FROM 'operativo' THEN
        SELECT COUNT(*) INTO v_n FROM items_diferidos
        WHERE activo_id = NEW.id AND estado = 'pendiente' AND diferible = false;
        IF v_n > 0 THEN
            RAISE EXCEPTION 'BLOQUEO CALIDAD: el equipo % tiene % pendiente(s) '
                'critico(s)/seguridad no diferible(s). No puede pasar a operativo.',
                COALESCE(NEW.patente, NEW.codigo, NEW.id::TEXT), v_n
            USING HINT = 'Resolver los pendientes criticos antes de liberar a servicio.';
        END IF;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_validar_operativo_pendientes ON activos;
CREATE TRIGGER trg_validar_operativo_pendientes
    BEFORE UPDATE OF estado ON activos
    FOR EACH ROW
    EXECUTE FUNCTION fn_validar_operativo_pendientes();


-- ============================================================================
-- 9b. TRIGGER — auto-generar chequeo cruzado al reportar avance / finalizar
-- ============================================================================
-- Cuando el mecanico reporta un 'avance' o 'finish' de la ejecucion (fin de
-- turno en una OT multidia), se crea automaticamente un chequeo cruzado
-- pendiente. Dedup: un solo chequeo pendiente por ejecucion a la vez. Nunca
-- bloquea el evento de ejecucion (captura cualquier error).
CREATE OR REPLACE FUNCTION fn_auto_chequeo_cruzado()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_ot       RECORD;
    v_ejecutor UUID;
    v_cheq     UUID;
    v_total    INT;
BEGIN
    IF NEW.tipo NOT IN ('finish','avance') THEN RETURN NEW; END IF;

    IF EXISTS (SELECT 1 FROM taller_chequeos_cruzados
               WHERE ejecucion_id = NEW.ejecucion_id AND estado = 'pendiente') THEN
        RETURN NEW;
    END IF;

    SELECT o.id, o.activo_id, o.responsable_id INTO v_ot
      FROM ordenes_trabajo o WHERE o.id = NEW.ot_id;
    IF NOT FOUND THEN RETURN NEW; END IF;

    SELECT ejecutor_id INTO v_ejecutor FROM taller_ot_ejecuciones WHERE id = NEW.ejecucion_id;
    v_ejecutor := COALESCE(v_ejecutor, v_ot.responsable_id, NEW.created_by);
    IF v_ejecutor IS NULL THEN RETURN NEW; END IF;

    INSERT INTO taller_chequeos_cruzados (
        ot_id, activo_id, ejecucion_id, avance_evento_id,
        ejecutor_id, avance_declarado, created_by
    ) VALUES (
        NEW.ot_id, v_ot.activo_id, NEW.ejecucion_id, NEW.id,
        v_ejecutor, NEW.avance, NEW.created_by
    ) RETURNING id INTO v_cheq;

    INSERT INTO taller_chequeo_cruzado_items
        (chequeo_id, orden, categoria, descripcion, obligatorio, requiere_foto)
    SELECT v_cheq, orden, categoria, descripcion, obligatorio, requiere_foto
    FROM taller_chequeo_cruzado_plantilla_items WHERE activo = true ORDER BY orden;
    GET DIAGNOSTICS v_total = ROW_COUNT;
    UPDATE taller_chequeos_cruzados SET items_total = v_total WHERE id = v_cheq;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RETURN NEW;  -- nunca bloquear el evento de ejecucion
END $$;

DROP TRIGGER IF EXISTS trg_auto_chequeo_cruzado ON taller_ot_ejecucion_eventos;
CREATE TRIGGER trg_auto_chequeo_cruzado
    AFTER INSERT ON taller_ot_ejecucion_eventos
    FOR EACH ROW
    EXECUTE FUNCTION fn_auto_chequeo_cruzado();


-- ============================================================================
-- 10. VISTAS
-- ============================================================================

-- 10.1 Cola Gate 1
CREATE OR REPLACE VIEW v_chequeos_cruzados_pendientes AS
SELECT cc.id, cc.ot_id, ot.folio, cc.activo_id, a.patente, a.codigo,
       cc.fecha_turno, cc.turno, cc.ejecutor_id, ue.nombre_completo AS ejecutor_nombre,
       cc.avance_declarado, cc.items_total, cc.created_at
FROM taller_chequeos_cruzados cc
JOIN ordenes_trabajo ot ON ot.id = cc.ot_id
JOIN activos a ON a.id = cc.activo_id
LEFT JOIN usuarios_perfil ue ON ue.id = cc.ejecutor_id
WHERE cc.estado = 'pendiente'
ORDER BY cc.created_at;

-- 10.2 Cola Gate 2
CREATE OR REPLACE VIEW v_auditorias_calidad_pendientes AS
SELECT ac.id, ac.activo_id, a.patente, a.codigo, ac.ot_id, ot.folio,
       ac.iniciada_por, ui.nombre_completo AS iniciada_nombre,
       ac.items_total, ac.created_at
FROM auditorias_calidad ac
JOIN activos a ON a.id = ac.activo_id
LEFT JOIN ordenes_trabajo ot ON ot.id = ac.ot_id
LEFT JOIN usuarios_perfil ui ON ui.id = ac.iniciada_por
WHERE ac.resultado = 'pendiente'
ORDER BY ac.created_at;

-- 10.3 Diferidos por equipo (con dias restantes)
CREATE OR REPLACE VIEW v_items_diferidos_activo AS
SELECT d.*, a.patente, a.codigo,
       (d.plazo_fecha_limite - CURRENT_DATE) AS dias_para_plazo,
       up.nombre_completo AS autorizado_nombre
FROM items_diferidos d
JOIN activos a ON a.id = d.activo_id
LEFT JOIN usuarios_perfil up ON up.id = d.autorizado_por
WHERE d.estado IN ('pendiente','vencido','programado');

-- 10.4 Historial de mantencion del equipo (hecho + pendiente)
CREATE OR REPLACE VIEW v_historial_mantencion_equipo AS
SELECT activo_id, 'ot'::TEXT AS tipo_registro, id AS ref_id,
       COALESCE(fecha_termino, fecha_cierre_supervisor, created_at) AS fecha,
       folio AS titulo, estado::TEXT AS estado, observaciones AS detalle
FROM ordenes_trabajo
WHERE estado IN ('ejecutada_ok','ejecutada_con_observaciones')
UNION ALL
SELECT activo_id, 'diferido'::TEXT, id,
       fecha_diferimiento, 'Pendiente: '||descripcion, estado,
       'Plazo '||COALESCE(plazo_fecha_limite::TEXT,'s/d')||' (origen '||COALESCE(plazo_origen,'s/d')||
       '), severidad '||severidad
FROM items_diferidos
UNION ALL
SELECT activo_id, 'auditoria'::TEXT, id,
       COALESCE(fecha_auditoria, created_at), 'Auditoria de calidad', resultado::TEXT,
       motivo_rechazo
FROM auditorias_calidad;

-- 10.5 KPIs de calidad de taller
CREATE OR REPLACE VIEW v_kpi_calidad_taller AS
SELECT
    (SELECT COUNT(*) FROM taller_chequeos_cruzados
        WHERE fecha_turno >= CURRENT_DATE - 30) AS cc_total_30d,
    (SELECT COUNT(*) FROM taller_chequeos_cruzados
        WHERE estado IN ('aprobado','aprobado_con_obs') AND fecha_turno >= CURRENT_DATE - 30) AS cc_aprobados_30d,
    (SELECT COUNT(*) FROM taller_chequeos_cruzados
        WHERE estado = 'rechazado' AND fecha_turno >= CURRENT_DATE - 30) AS cc_rechazados_30d,
    (SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE estado = 'aprobado')
            / NULLIF(COUNT(*) FILTER (WHERE estado IN ('aprobado','aprobado_con_obs','rechazado')),0))
        FROM taller_chequeos_cruzados WHERE fecha_turno >= CURRENT_DATE - 30) AS cc_first_time_ok_pct,
    (SELECT COUNT(*) FROM auditorias_calidad WHERE fecha_auditoria >= CURRENT_DATE - 30) AS aud_total_30d,
    (SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE resultado = 'aprobado')
            / NULLIF(COUNT(*) FILTER (WHERE resultado IN ('aprobado','aprobado_con_observaciones','rechazado')),0))
        FROM auditorias_calidad WHERE fecha_auditoria >= CURRENT_DATE - 30) AS aud_pass_rate_pct,
    (SELECT COUNT(*) FROM items_diferidos WHERE estado = 'pendiente') AS diferidos_pendientes,
    (SELECT COUNT(*) FROM items_diferidos WHERE estado = 'vencido') AS diferidos_vencidos,
    (SELECT COUNT(*) FROM items_diferidos WHERE estado = 'pendiente' AND diferible = false) AS diferidos_criticos,
    (SELECT COUNT(*) FROM no_conformidades WHERE resuelto = false) AS nc_abiertas;


-- ============================================================================
-- 11. RLS
-- ============================================================================
DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'taller_chequeo_cruzado_plantilla_items','taller_chequeos_cruzados',
        'taller_chequeo_cruzado_items','auditoria_calidad_plantilla_items',
        'auditorias_calidad','auditoria_calidad_items','items_diferidos'
    ] LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t||'_sel', t);
        EXECUTE format('CREATE POLICY %I ON %I FOR SELECT TO authenticated USING (true)', t||'_sel', t);
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I', t||'_wr', t);
        EXECUTE format('CREATE POLICY %I ON %I FOR ALL TO authenticated USING (true) WITH CHECK (true)', t||'_wr', t);
    END LOOP;
END $$;


-- ============================================================================
-- 12. SEEDS — plantillas de checklist
-- ============================================================================

-- 12.1 Gate 1 — chequeo cruzado (solo si la plantilla esta vacia)
INSERT INTO taller_chequeo_cruzado_plantilla_items (orden, categoria, descripcion, obligatorio, requiere_foto)
SELECT * FROM (VALUES
    (1, 'alcance',   'La OT corresponde al equipo y las tareas del turno estan marcadas como ejecutadas', true, false),
    (2, 'apriete',   'Pernos/tuercas criticos (ruedas, direccion, suspension) apretados a torque y marcados con testigo', true, true),
    (3, 'fluidos',   'Aceites/refrigerante/hidraulico: tipo correcto y nivel dentro de rango, sin contaminacion', true, false),
    (4, 'fugas',     'Inspeccion visual: sin fugas en lineas de aceite, combustible, hidraulico, refrigerante, aire/frenos', true, false),
    (5, 'repuestos', 'Parte correcta instalada (N de parte), parte vieja segregada y registrada en la OT', true, false),
    (6, 'protecciones','Guardas, tapas, conectores electricos y abrazaderas reinstalados y asegurados', true, false),
    (7, 'fod',       'Conteo de herramientas completo, sin objetos extranos (FOD) en compartimientos', true, false),
    (8, 'funcional', 'Prueba funcional basica del sistema intervenido, sin nuevas alarmas en tablero', true, false),
    (9, 'orden',     'Area de trabajo y equipo limpios para permitir la siguiente inspeccion', false, false)
) AS v(orden, categoria, descripcion, obligatorio, requiere_foto)
WHERE NOT EXISTS (SELECT 1 FROM taller_chequeo_cruzado_plantilla_items);

-- 12.2 Gate 2 — auditoria (tecnica + documentacion)
INSERT INTO auditoria_calidad_plantilla_items (categoria, orden, descripcion, obligatorio, critico, cert_tipo)
SELECT * FROM (VALUES
    ('tecnica', 1,  'Frenos: servicio, estacionamiento y emergencia eficaces; sin fugas de aire/aceite', true, true, NULL),
    ('tecnica', 2,  'Direccion: juego dentro de tolerancia, sin fugas hidraulicas, topes y articulaciones OK', true, true, NULL),
    ('tecnica', 3,  'Sistema hidraulico: presiones de trabajo OK, mangueras sin abrasion/fuga, cilindros sin deriva', true, false, NULL),
    ('tecnica', 4,  'Neumaticos/ruedas: presion, profundidad, daños; torque de tuercas verificado y marcado', true, true, NULL),
    ('tecnica', 5,  'Estructura/chasis: sin grietas en chasis/tolva/soportes; pasadores y bujes OK', true, true, NULL),
    ('tecnica', 6,  'Motor/transmision: niveles OK, sin fugas, sin codigos de falla activos, temperatura/presion normales', true, false, NULL),
    ('tecnica', 7,  'Sistema electrico: luces, alarma de retroceso, bocina, baterias aseguradas, arnes sin daño', true, false, NULL),
    ('tecnica', 8,  'Seguridad/cabina: cinturon, extintor/supresion vigente, espejos/camaras, parada de emergencia, ROPS/FOPS', true, true, NULL),
    ('tecnica', 9,  'GPS/telemetria operativo y reportando', false, false, NULL),
    ('tecnica', 10, 'OT cerradas y No Conformidades del equipo resueltas', true, false, NULL),
    ('documentacion', 11, 'Revision tecnica vigente', true, true, 'revision_tecnica'),
    ('documentacion', 12, 'SOAP vigente', true, true, 'soap'),
    ('documentacion', 13, 'Permiso de circulacion vigente', true, false, 'permiso_circulacion'),
    ('documentacion', 14, 'Certificaciones criticas del equipo vigentes (FOPS/ROPS, gancho, etc.)', false, false, NULL)
) AS v(categoria, orden, descripcion, obligatorio, critico, cert_tipo)
WHERE NOT EXISTS (SELECT 1 FROM auditoria_calidad_plantilla_items);


-- ── 13. VALIDACION ──────────────────────────────────────────────────────────
SELECT
    (SELECT COUNT(*) FROM taller_chequeo_cruzado_plantilla_items) AS cc_plantilla_items,
    (SELECT COUNT(*) FROM auditoria_calidad_plantilla_items)      AS aud_plantilla_items,
    (SELECT 1 FROM pg_proc WHERE proname='fn_resolver_auditoria_calidad' LIMIT 1) AS rpc_auditoria_ok,
    (SELECT 1 FROM pg_proc WHERE proname='fn_resolver_chequeo_cruzado'  LIMIT 1) AS rpc_chequeo_ok,
    (SELECT 1 FROM pg_proc WHERE proname='fn_calcular_plazo_diferido'   LIMIT 1) AS rpc_plazo_ok;
