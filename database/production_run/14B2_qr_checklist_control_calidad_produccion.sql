-- ============================================================================
-- 14B2_qr_checklist_control_calidad_produccion.sql
-- ----------------------------------------------------------------------------
-- Extension del 14B con CONTROL DE CALIDAD del checklist.
-- Reduce vulnerabilidad de "checklist rapido sin inspeccion real" mediante:
--   - Tiempo minimo por template + duracion real medida.
--   - Trazabilidad por pregunta (orden, tiempo, cambios).
--   - Evidencia obligatoria por item (foto siempre / si falla / observacion).
--   - Items de control aleatorio (selección random N por checklist).
--   - Geolocalizacion inicial+final con precision GPS.
--   - Firma/declaracion responsable + dispositivo_info.
--   - Score de calidad 0-100 con clasificacion (alta/media/baja/sospechoso).
--   - Alertas de calidad automaticas (DURACION_MUY_BAJA, TODO_OK_REPETITIVO, etc).
--   - Vista KPI por operador.
--
-- DEPENDENCIAS: 14B aplicado.
-- IDEMPOTENTE: ALTER ... ADD COLUMN IF NOT EXISTS, CREATE TABLE IF NOT EXISTS,
--              CREATE OR REPLACE para funciones/RPCs/views, UPDATE WHERE.
-- NO TOCA: mig 55/56/57. NO ejecuta migraciones futuras.
-- ============================================================================


-- ── 0. Precheck ─────────────────────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='qr_checklist_templates') THEN
        RAISE EXCEPTION 'STOP — 14B no aplicado. Ejecutar primero 14B_qr_checklist_offline_mantencion_produccion.sql.';
    END IF;
END $$;


-- ── 1. ALTER tablas (campos nuevos idempotentes) ────────────────────

-- 1.1 templates
ALTER TABLE qr_checklist_templates
    ADD COLUMN IF NOT EXISTS duracion_minima_segundos INT NOT NULL DEFAULT 90,
    ADD COLUMN IF NOT EXISTS cantidad_controles_aleatorios INT NOT NULL DEFAULT 2;

-- 1.2 template_items (evidencia obligatoria + control aleatorio + camara only)
ALTER TABLE qr_checklist_template_items
    ADD COLUMN IF NOT EXISTS requiere_foto_si_falla BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS requiere_foto_siempre BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS requiere_observacion_si_falla BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS solo_camara BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS es_control_aleatorio BOOLEAN NOT NULL DEFAULT false;

-- Permitir tipo_respuesta = 'control_aleatorio' (extiende CHECK)
DO $$ BEGIN
    BEGIN
        ALTER TABLE qr_checklist_template_items DROP CONSTRAINT IF EXISTS qr_checklist_template_items_tipo_respuesta_check;
    EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN
        ALTER TABLE qr_checklist_template_items
            ADD CONSTRAINT qr_checklist_template_items_tipo_respuesta_check
            CHECK (tipo_respuesta IN ('ok_obs_falla','si_no','numerico','texto','control_aleatorio'));
    EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

-- 1.3 respuestas (duracion + GPS + firma + score)
ALTER TABLE qr_checklist_respuestas
    ADD COLUMN IF NOT EXISTS iniciado_en TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS terminado_en TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS duracion_segundos INT,
    ADD COLUMN IF NOT EXISTS gps_inicial_lat NUMERIC(10,7),
    ADD COLUMN IF NOT EXISTS gps_inicial_lng NUMERIC(10,7),
    ADD COLUMN IF NOT EXISTS gps_inicial_precision_m NUMERIC(8,2),
    ADD COLUMN IF NOT EXISTS gps_final_lat NUMERIC(10,7),
    ADD COLUMN IF NOT EXISTS gps_final_lng NUMERIC(10,7),
    ADD COLUMN IF NOT EXISTS gps_final_precision_m NUMERIC(8,2),
    ADD COLUMN IF NOT EXISTS gps_no_disponible BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS rut_operador VARCHAR(20),
    ADD COLUMN IF NOT EXISTS firma_url TEXT,
    ADD COLUMN IF NOT EXISTS firma_declaracion TEXT,
    ADD COLUMN IF NOT EXISTS dispositivo_info JSONB,
    ADD COLUMN IF NOT EXISTS score_calidad INT,
    ADD COLUMN IF NOT EXISTS clasificacion_calidad VARCHAR(20)
        CHECK (clasificacion_calidad IS NULL OR clasificacion_calidad IN ('alta','media','baja','sospechoso')),
    ADD COLUMN IF NOT EXISTS sospechoso BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS revisado_por UUID REFERENCES usuarios_perfil(id),
    ADD COLUMN IF NOT EXISTS revisado_en TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS estado_revision VARCHAR(30) NOT NULL DEFAULT 'pendiente'
        CHECK (estado_revision IN ('pendiente','validado','requiere_reinspeccion','sin_hallazgo','escalado'));

CREATE INDEX IF NOT EXISTS idx_qr_resp_score    ON qr_checklist_respuestas (clasificacion_calidad, sospechoso);
CREATE INDEX IF NOT EXISTS idx_qr_resp_revision ON qr_checklist_respuestas (estado_revision) WHERE estado_revision = 'pendiente';

-- 1.4 respuesta_items (trazabilidad por pregunta)
ALTER TABLE qr_checklist_respuesta_items
    ADD COLUMN IF NOT EXISTS respondido_en TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS orden_respuesta INT,
    ADD COLUMN IF NOT EXISTS tiempo_desde_inicio_segundos INT,
    ADD COLUMN IF NOT EXISTS cambio_respuesta BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS respuesta_original TEXT,
    ADD COLUMN IF NOT EXISTS foto_metadata JSONB,
    ADD COLUMN IF NOT EXISTS es_control_aleatorio BOOLEAN NOT NULL DEFAULT false;


-- ── 2. Tabla qr_checklist_alertas_calidad ───────────────────────────
CREATE TABLE IF NOT EXISTS qr_checklist_alertas_calidad (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    checklist_respuesta_id   UUID NOT NULL REFERENCES qr_checklist_respuestas(id) ON DELETE CASCADE,
    activo_id                UUID NOT NULL REFERENCES activos(id),
    operador_nombre          VARCHAR(200),
    tipo_alerta              VARCHAR(40) NOT NULL CHECK (tipo_alerta IN (
        'DURACION_MUY_BAJA','TODO_OK_REPETITIVO','SIN_EVIDENCIA_CRITICA',
        'GPS_NO_DISPONIBLE','FUERA_DE_ZONA','RESPUESTAS_MASIVAS_RAPIDAS',
        'OPERADOR_REINCIDENTE','FOTO_NO_CAPTURADA_EN_CAMARA','CHECKLIST_DUPLICADO',
        'EVIDENCIA_OBLIGATORIA_FALTANTE','SIN_FIRMA_DECLARACION','SCORE_BAJO'
    )),
    severidad                VARCHAR(10) NOT NULL CHECK (severidad IN ('baja','media','alta','critica')),
    detalle                  TEXT NOT NULL,
    estado                   VARCHAR(20) NOT NULL DEFAULT 'abierta'
                             CHECK (estado IN ('abierta','en_revision','confirmada','descartada')),
    revisada_por             UUID REFERENCES usuarios_perfil(id),
    revisada_en              TIMESTAMPTZ,
    accion_revision          TEXT,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_qr_alertas_cal_activo ON qr_checklist_alertas_calidad (activo_id, estado, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_qr_alertas_cal_resp   ON qr_checklist_alertas_calidad (checklist_respuesta_id);
CREATE INDEX IF NOT EXISTS idx_qr_alertas_cal_op     ON qr_checklist_alertas_calidad (operador_nombre, created_at DESC);

ALTER TABLE qr_checklist_alertas_calidad ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_qr_alertas_cal_select ON qr_checklist_alertas_calidad;
CREATE POLICY pol_qr_alertas_cal_select ON qr_checklist_alertas_calidad FOR SELECT TO authenticated
    USING (fn_qr_es_rol_mantencion());
DROP POLICY IF EXISTS pol_qr_alertas_cal_update ON qr_checklist_alertas_calidad;
CREATE POLICY pol_qr_alertas_cal_update ON qr_checklist_alertas_calidad FOR UPDATE TO authenticated
    USING (fn_qr_es_rol_mantencion()) WITH CHECK (fn_qr_es_rol_mantencion());


-- ── 3. UPDATE templates: duracion minima por familia ────────────────
UPDATE qr_checklist_templates SET duracion_minima_segundos = 60,  cantidad_controles_aleatorios = 2 WHERE codigo = 'CL_UNIVERSAL';
UPDATE qr_checklist_templates SET duracion_minima_segundos = 90,  cantidad_controles_aleatorios = 2 WHERE codigo = 'CL_CAMIONETA_LIVIANO';
UPDATE qr_checklist_templates SET duracion_minima_segundos = 90,  cantidad_controles_aleatorios = 2 WHERE codigo = 'CL_TOYOTA_HILUX';
UPDATE qr_checklist_templates SET duracion_minima_segundos = 120, cantidad_controles_aleatorios = 3 WHERE codigo = 'CL_FURGON_TALLER';
UPDATE qr_checklist_templates SET duracion_minima_segundos = 150, cantidad_controles_aleatorios = 3 WHERE codigo = 'CL_GRUA_HORQUILLA';
UPDATE qr_checklist_templates SET duracion_minima_segundos = 180, cantidad_controles_aleatorios = 3 WHERE codigo = 'CL_CAMION_PESADO';
UPDATE qr_checklist_templates SET duracion_minima_segundos = 180, cantidad_controles_aleatorios = 3 WHERE codigo = 'CL_CAMION_TOLVA';
UPDATE qr_checklist_templates SET duracion_minima_segundos = 180, cantidad_controles_aleatorios = 3 WHERE codigo = 'CL_CAMION_CARRETERA';
UPDATE qr_checklist_templates SET duracion_minima_segundos = 240, cantidad_controles_aleatorios = 4 WHERE codigo = 'CL_CAMION_ALJIBE';
UPDATE qr_checklist_templates SET duracion_minima_segundos = 240, cantidad_controles_aleatorios = 4 WHERE codigo IN ('CL_MB_ACTROS_3336K','CL_MB_ACTROS_3341');
UPDATE qr_checklist_templates SET duracion_minima_segundos = 240, cantidad_controles_aleatorios = 4 WHERE codigo IN ('CL_MACK_GR64BX','CL_SCANIA_P450B','CL_VOLVO_VM');


-- ── 4. UPDATE items criticos con flags de evidencia obligatoria ─────
-- Items rojos siempre requieren foto si falla + observacion si falla
UPDATE qr_checklist_template_items
   SET requiere_foto_si_falla = true,
       requiere_observacion_si_falla = true
 WHERE criticidad_si_falla = 'rojo';

-- Items relacionados a neumaticos / tablero / fugas / suspension / aljibe / horometro:
-- foto SIEMPRE obligatoria (no solo si falla) + solo camara
UPDATE qr_checklist_template_items
   SET requiere_foto_siempre = true,
       solo_camara = true
 WHERE codigo_item IN (
    'NEUM_GRAL','NEUM_DELANT','NEUM_TRAS','NEUM_12R225','NEUM_PRESION','NEUM_REPUESTO','NEUM_ESTADO',
    'TESTIGOS','TABLERO',
    'PRESION_AIRE',
    'FUGAS','FUGAS_VISIBLES','FUGAS_BAJO',
    'PAQ_RESORTES','PAQ_RESORTES_MB','PAQ_RESORTES_MACK','SUSP_ESTADO',
    'VALVULAS','BOMBA','MANGUERAS','MEDIDOR',
    'IDENT_KM','IDENT_HOROM'
 );


-- ── 5. INSERT items de control aleatorio (transversales) ────────────
-- Se insertan en TODOS los templates seed (es_control_aleatorio=true).
-- La RPC selecciona N de estos al azar segun cantidad_controles_aleatorios.

DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT id, codigo FROM qr_checklist_templates WHERE activo=true LOOP
        INSERT INTO qr_checklist_template_items (
            template_id, seccion, orden, codigo_item, descripcion,
            tipo_respuesta, criticidad_si_falla,
            requiere_foto_si_falla, requiere_foto_siempre, requiere_observacion_si_falla,
            solo_camara, es_control_aleatorio, obligatorio
        )
        SELECT r.id, x.seccion, x.orden, x.codigo, x.descr,
               x.tipo, x.crit, x.foto_falla, x.foto_siempre, x.obs_falla, x.camara, true, true
        FROM (VALUES
          ('Control Aleatorio', 901, 'AR_HOROM_3DIG',     'Ingrese los ULTIMOS 3 DIGITOS del horometro/odometro visible.',                       'numerico',          NULL,       false, false, false, false),
          ('Control Aleatorio', 902, 'AR_FOTO_NEUM_DI',   'Fotografie el NEUMATICO DELANTERO IZQUIERDO (toma cercana, banda visible).',         'control_aleatorio', 'amarillo', false, true,  false, true ),
          ('Control Aleatorio', 903, 'AR_FOTO_TABLERO',   'Fotografie el TABLERO con el motor encendido (testigos visibles).',                  'control_aleatorio', 'naranja',  false, true,  false, true ),
          ('Control Aleatorio', 904, 'AR_BALIZA',         'Estado de la BALIZA tras probarla (selecciona OK/observacion/falla).',                'ok_obs_falla',      'amarillo', true,  false, false, false),
          ('Control Aleatorio', 905, 'AR_FOTO_EXTINTOR',  'Fotografie el EXTINTOR mostrando sello/manometro.',                                   'control_aleatorio', 'rojo',     false, true,  false, true ),
          ('Control Aleatorio', 906, 'AR_FUGAS_CONTEO',   'Cuente fugas visibles bajo cabina/motor (numero entero).',                            'numerico',          'amarillo', true,  false, true,  false),
          ('Control Aleatorio', 907, 'AR_VARILLA',        'Color del aceite motor en varilla (claro/oscuro/quemado).',                           'texto',             NULL,       false, false, true,  false)
        ) AS x(seccion, orden, codigo, descr, tipo, crit, foto_falla, foto_siempre, obs_falla, camara)
        ON CONFLICT (template_id, codigo_item) DO NOTHING;
    END LOOP;
END $$;


-- ── 6. Funcion: calcular score de calidad (0-100) ───────────────────
CREATE OR REPLACE FUNCTION fn_qr_calcular_score_calidad_checklist(p_respuesta_id UUID)
RETURNS INT
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_resp RECORD;
    v_score INT := 100;
    v_total_items INT;
    v_items_falla INT;
    v_items_obs INT;
    v_items_req_foto_siempre_sin INT;
    v_items_falla_sin_foto INT;
    v_tiempo_promedio NUMERIC;
    v_items_criticos_falla_historial INT;
BEGIN
    SELECT r.*, t.duracion_minima_segundos AS dur_min
      INTO v_resp
      FROM qr_checklist_respuestas r
      JOIN qr_checklist_templates t ON t.id = r.template_id
     WHERE r.id = p_respuesta_id;
    IF v_resp.id IS NULL THEN RETURN 0; END IF;

    -- 1. Duracion vs minima
    IF v_resp.duracion_segundos IS NULL THEN
        v_score := v_score - 10;
    ELSIF v_resp.duracion_segundos < (v_resp.dur_min / 2) THEN
        v_score := v_score - 50;
    ELSIF v_resp.duracion_segundos < v_resp.dur_min THEN
        v_score := v_score - 30;
    END IF;

    -- 2. Foto SIEMPRE obligatoria pero faltante
    SELECT COUNT(*) INTO v_items_req_foto_siempre_sin
      FROM qr_checklist_respuesta_items ri
      JOIN qr_checklist_template_items ti ON ti.id = ri.template_item_id
     WHERE ri.respuesta_id = p_respuesta_id
       AND ti.requiere_foto_siempre = true
       AND (ri.foto_url IS NULL OR ri.foto_url = '');
    v_score := v_score - LEAST(30, v_items_req_foto_siempre_sin * 10);

    -- 3. Foto si FALLA pero faltante
    SELECT COUNT(*) INTO v_items_falla_sin_foto
      FROM qr_checklist_respuesta_items ri
      JOIN qr_checklist_template_items ti ON ti.id = ri.template_item_id
     WHERE ri.respuesta_id = p_respuesta_id
       AND ri.es_falla = true
       AND ti.requiere_foto_si_falla = true
       AND (ri.foto_url IS NULL OR ri.foto_url = '');
    v_score := v_score - LEAST(30, v_items_falla_sin_foto * 10);

    -- 4. GPS no disponible
    IF v_resp.gps_no_disponible = true OR
       (v_resp.gps_inicial_lat IS NULL AND v_resp.gps_final_lat IS NULL) THEN
        v_score := v_score - 5;
    END IF;

    -- 5. Patron "todo OK" sin observaciones
    SELECT COUNT(*) INTO v_total_items FROM qr_checklist_respuesta_items WHERE respuesta_id = p_respuesta_id;
    SELECT COUNT(*) FILTER (WHERE es_falla=true OR es_observacion=true) INTO v_items_obs
      FROM qr_checklist_respuesta_items WHERE respuesta_id = p_respuesta_id;
    IF v_total_items >= 8 AND v_items_obs = 0 THEN
        -- Si el activo tiene historial de fallas en ultimos 90 dias, descontar mas
        SELECT COUNT(*) INTO v_items_criticos_falla_historial
          FROM qr_checklist_respuesta_items ri2
          JOIN qr_checklist_respuestas r2 ON r2.id = ri2.respuesta_id
         WHERE r2.activo_id = v_resp.activo_id
           AND ri2.es_falla = true
           AND r2.sincronizado_at >= NOW() - INTERVAL '90 days'
           AND r2.id <> p_respuesta_id;
        IF v_items_criticos_falla_historial >= 3 THEN
            v_score := v_score - 15; -- equipo con historial de fallas pero hoy todo OK
        ELSE
            v_score := v_score - 5;
        END IF;
    END IF;

    -- 6. Velocidad anormal (promedio < 2s/item)
    IF v_resp.duracion_segundos IS NOT NULL AND v_total_items > 0 THEN
        v_tiempo_promedio := v_resp.duracion_segundos::NUMERIC / v_total_items;
        IF v_tiempo_promedio < 2 THEN v_score := v_score - 15;
        ELSIF v_tiempo_promedio < 4 THEN v_score := v_score - 5;
        END IF;
    END IF;

    -- 7. Sin firma_declaracion
    IF v_resp.firma_declaracion IS NULL OR LENGTH(TRIM(v_resp.firma_declaracion)) < 5 THEN
        v_score := v_score - 5;
    END IF;

    -- 8. Bonus: foto en items criticos rojos
    IF EXISTS (
        SELECT 1 FROM qr_checklist_respuesta_items ri
        JOIN qr_checklist_template_items ti ON ti.id = ri.template_item_id
        WHERE ri.respuesta_id = p_respuesta_id
          AND ti.criticidad_si_falla = 'rojo'
          AND ri.foto_url IS NOT NULL AND ri.foto_url <> ''
    ) THEN
        v_score := v_score + 5;
    END IF;

    RETURN GREATEST(0, LEAST(100, v_score));
END; $$;

-- Helper de clasificacion
CREATE OR REPLACE FUNCTION fn_qr_clasificar_calidad(p_score INT, p_duracion INT, p_dur_min INT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
      WHEN p_score IS NULL THEN 'baja'
      WHEN p_duracion IS NOT NULL AND p_dur_min IS NOT NULL
           AND p_duracion < (p_dur_min / 2) THEN 'sospechoso'
      WHEN p_score < 50 THEN 'sospechoso'
      WHEN p_score < 60 THEN 'baja'
      WHEN p_score < 80 THEN 'media'
      ELSE 'alta'
    END;
$$;


-- ── 7. Funcion: evaluar y crear alertas de calidad ──────────────────
CREATE OR REPLACE FUNCTION fn_qr_evaluar_alertas_calidad(p_respuesta_id UUID)
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_resp RECORD;
    v_alertas INT := 0;
    v_total INT;
    v_avg NUMERIC;
    v_consec INT;
BEGIN
    SELECT r.*, t.duracion_minima_segundos AS dur_min
      INTO v_resp
      FROM qr_checklist_respuestas r
      JOIN qr_checklist_templates t ON t.id = r.template_id
     WHERE r.id = p_respuesta_id;
    IF v_resp.id IS NULL THEN RETURN 0; END IF;

    -- DURACION_MUY_BAJA
    IF v_resp.duracion_segundos IS NOT NULL
       AND v_resp.duracion_segundos < (v_resp.dur_min / 2) THEN
        INSERT INTO qr_checklist_alertas_calidad (
            checklist_respuesta_id, activo_id, operador_nombre,
            tipo_alerta, severidad, detalle
        ) VALUES (
            v_resp.id, v_resp.activo_id, v_resp.operador_nombre,
            'DURACION_MUY_BAJA', 'alta',
            'Checklist completado en ' || v_resp.duracion_segundos::TEXT || 's. Minimo esperado: '
              || v_resp.dur_min::TEXT || 's.'
        );
        v_alertas := v_alertas + 1;
    END IF;

    -- TODO_OK_REPETITIVO (5 checklists del mismo operador todos OK en 30 dias)
    IF v_resp.items_falla_count = 0 AND v_resp.items_observacion_count = 0
       AND v_resp.operador_nombre IS NOT NULL THEN
        SELECT COUNT(*) INTO v_consec
          FROM qr_checklist_respuestas r2
         WHERE LOWER(r2.operador_nombre) = LOWER(v_resp.operador_nombre)
           AND r2.items_falla_count = 0 AND r2.items_observacion_count = 0
           AND r2.sincronizado_at >= NOW() - INTERVAL '30 days';
        IF v_consec >= 5 THEN
            INSERT INTO qr_checklist_alertas_calidad (
                checklist_respuesta_id, activo_id, operador_nombre, tipo_alerta, severidad, detalle
            ) VALUES (
                v_resp.id, v_resp.activo_id, v_resp.operador_nombre,
                'TODO_OK_REPETITIVO', 'media',
                'Operador con ' || v_consec::TEXT || ' checklists 100% OK seguidos en ultimos 30 dias.'
            );
            v_alertas := v_alertas + 1;
        END IF;
    END IF;

    -- SIN_EVIDENCIA_CRITICA (item rojo con falla pero sin foto)
    IF EXISTS (
        SELECT 1 FROM qr_checklist_respuesta_items ri
        JOIN qr_checklist_template_items ti ON ti.id = ri.template_item_id
        WHERE ri.respuesta_id = v_resp.id
          AND ri.es_falla = true
          AND ti.criticidad_si_falla = 'rojo'
          AND (ri.foto_url IS NULL OR ri.foto_url = '')
    ) THEN
        INSERT INTO qr_checklist_alertas_calidad (
            checklist_respuesta_id, activo_id, operador_nombre, tipo_alerta, severidad, detalle
        ) VALUES (
            v_resp.id, v_resp.activo_id, v_resp.operador_nombre,
            'SIN_EVIDENCIA_CRITICA', 'critica',
            'Falla critica reportada SIN foto adjunta.'
        );
        v_alertas := v_alertas + 1;
    END IF;

    -- EVIDENCIA_OBLIGATORIA_FALTANTE (item con requiere_foto_siempre sin foto)
    IF EXISTS (
        SELECT 1 FROM qr_checklist_respuesta_items ri
        JOIN qr_checklist_template_items ti ON ti.id = ri.template_item_id
        WHERE ri.respuesta_id = v_resp.id
          AND ti.requiere_foto_siempre = true
          AND (ri.foto_url IS NULL OR ri.foto_url = '')
    ) THEN
        INSERT INTO qr_checklist_alertas_calidad (
            checklist_respuesta_id, activo_id, operador_nombre, tipo_alerta, severidad, detalle
        ) VALUES (
            v_resp.id, v_resp.activo_id, v_resp.operador_nombre,
            'EVIDENCIA_OBLIGATORIA_FALTANTE', 'alta',
            'Items con foto siempre obligatoria llegaron sin foto.'
        );
        v_alertas := v_alertas + 1;
    END IF;

    -- GPS_NO_DISPONIBLE
    IF v_resp.gps_no_disponible = true OR
       (v_resp.gps_inicial_lat IS NULL AND v_resp.gps_final_lat IS NULL) THEN
        INSERT INTO qr_checklist_alertas_calidad (
            checklist_respuesta_id, activo_id, operador_nombre, tipo_alerta, severidad, detalle
        ) VALUES (
            v_resp.id, v_resp.activo_id, v_resp.operador_nombre,
            'GPS_NO_DISPONIBLE', 'baja',
            'Sin GPS al inicio ni al final. Aceptable en precordillera, registrado para auditoria.'
        );
        v_alertas := v_alertas + 1;
    END IF;

    -- RESPUESTAS_MASIVAS_RAPIDAS (promedio < 2s/item)
    SELECT COUNT(*) INTO v_total FROM qr_checklist_respuesta_items WHERE respuesta_id = v_resp.id;
    IF v_resp.duracion_segundos IS NOT NULL AND v_total > 0 THEN
        v_avg := v_resp.duracion_segundos::NUMERIC / v_total;
        IF v_avg < 2 THEN
            INSERT INTO qr_checklist_alertas_calidad (
                checklist_respuesta_id, activo_id, operador_nombre, tipo_alerta, severidad, detalle
            ) VALUES (
                v_resp.id, v_resp.activo_id, v_resp.operador_nombre,
                'RESPUESTAS_MASIVAS_RAPIDAS', 'alta',
                'Promedio ' || ROUND(v_avg, 2)::TEXT || 's por pregunta para ' || v_total::TEXT || ' items.'
            );
            v_alertas := v_alertas + 1;
        END IF;
    END IF;

    -- CHECKLIST_DUPLICADO (mismo activo + mismo operador en < 1h)
    IF v_resp.operador_nombre IS NOT NULL AND EXISTS (
        SELECT 1 FROM qr_checklist_respuestas r2
         WHERE r2.activo_id = v_resp.activo_id
           AND LOWER(COALESCE(r2.operador_nombre,'')) = LOWER(COALESCE(v_resp.operador_nombre,''))
           AND r2.id <> v_resp.id
           AND r2.sincronizado_at >= NOW() - INTERVAL '1 hour'
           AND r2.sincronizado_at < v_resp.sincronizado_at
    ) THEN
        INSERT INTO qr_checklist_alertas_calidad (
            checklist_respuesta_id, activo_id, operador_nombre, tipo_alerta, severidad, detalle
        ) VALUES (
            v_resp.id, v_resp.activo_id, v_resp.operador_nombre,
            'CHECKLIST_DUPLICADO', 'media',
            'Mismo operador respondio otro checklist al mismo activo en la ultima hora.'
        );
        v_alertas := v_alertas + 1;
    END IF;

    -- FOTO_NO_CAPTURADA_EN_CAMARA (item solo_camara con foto_metadata.origen != 'camera')
    IF EXISTS (
        SELECT 1 FROM qr_checklist_respuesta_items ri
        JOIN qr_checklist_template_items ti ON ti.id = ri.template_item_id
        WHERE ri.respuesta_id = v_resp.id
          AND ti.solo_camara = true
          AND ri.foto_url IS NOT NULL AND ri.foto_url <> ''
          AND COALESCE(ri.foto_metadata->>'origen','') NOT IN ('camera','camara')
    ) THEN
        INSERT INTO qr_checklist_alertas_calidad (
            checklist_respuesta_id, activo_id, operador_nombre, tipo_alerta, severidad, detalle
        ) VALUES (
            v_resp.id, v_resp.activo_id, v_resp.operador_nombre,
            'FOTO_NO_CAPTURADA_EN_CAMARA', 'alta',
            'Item exige captura por camara y la foto fue subida desde galeria.'
        );
        v_alertas := v_alertas + 1;
    END IF;

    -- SIN_FIRMA_DECLARACION
    IF v_resp.firma_declaracion IS NULL OR LENGTH(TRIM(v_resp.firma_declaracion)) < 5 THEN
        INSERT INTO qr_checklist_alertas_calidad (
            checklist_respuesta_id, activo_id, operador_nombre, tipo_alerta, severidad, detalle
        ) VALUES (
            v_resp.id, v_resp.activo_id, v_resp.operador_nombre,
            'SIN_FIRMA_DECLARACION', 'media',
            'Operador no acepto la declaracion de inspeccion fisica.'
        );
        v_alertas := v_alertas + 1;
    END IF;

    -- SCORE_BAJO (< 60)
    IF v_resp.score_calidad IS NOT NULL AND v_resp.score_calidad < 60 THEN
        INSERT INTO qr_checklist_alertas_calidad (
            checklist_respuesta_id, activo_id, operador_nombre, tipo_alerta, severidad, detalle
        ) VALUES (
            v_resp.id, v_resp.activo_id, v_resp.operador_nombre,
            'SCORE_BAJO', CASE WHEN v_resp.score_calidad < 50 THEN 'critica' ELSE 'alta' END,
            'Score calidad: ' || v_resp.score_calidad::TEXT || '/100. Clasificacion: ' || COALESCE(v_resp.clasificacion_calidad,'-') || '.'
        );
        v_alertas := v_alertas + 1;
    END IF;

    -- OPERADOR_REINCIDENTE (>= 3 alertas calidad propias en 30 dias)
    IF v_resp.operador_nombre IS NOT NULL THEN
        SELECT COUNT(*) INTO v_consec
          FROM qr_checklist_alertas_calidad
         WHERE LOWER(operador_nombre) = LOWER(v_resp.operador_nombre)
           AND created_at >= NOW() - INTERVAL '30 days'
           AND tipo_alerta IN ('DURACION_MUY_BAJA','RESPUESTAS_MASIVAS_RAPIDAS','SCORE_BAJO',
                               'EVIDENCIA_OBLIGATORIA_FALTANTE','SIN_EVIDENCIA_CRITICA');
        IF v_consec >= 3 THEN
            INSERT INTO qr_checklist_alertas_calidad (
                checklist_respuesta_id, activo_id, operador_nombre, tipo_alerta, severidad, detalle
            ) VALUES (
                v_resp.id, v_resp.activo_id, v_resp.operador_nombre,
                'OPERADOR_REINCIDENTE', 'alta',
                'Operador acumula ' || v_consec::TEXT || ' alertas calidad en 30 dias. Escalar a supervisor.'
            );
            v_alertas := v_alertas + 1;
        END IF;
    END IF;

    RETURN v_alertas;
END; $$;
GRANT EXECUTE ON FUNCTION fn_qr_calcular_score_calidad_checklist(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_qr_clasificar_calidad(INT, INT, INT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION fn_qr_evaluar_alertas_calidad(UUID) TO authenticated;


-- ── 8. REPLACE: rpc_obtener_checklist_publico_por_qr ────────────────
-- Devuelve template + duracion_minima_segundos + items normales
-- + N items aleatorios (random) segun cantidad_controles_aleatorios.

CREATE OR REPLACE FUNCTION rpc_obtener_checklist_publico_por_qr(p_activo_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_template_id UUID;
    v_nivel       TEXT;
    v_activo      RECORD;
    v_template    RECORD;
    v_items_norm  JSONB;
    v_items_rand  JSONB;
BEGIN
    SELECT a.id, a.codigo, a.nombre, a.tipo, a.criticidad,
           a.kilometraje_actual, a.horas_uso_actual,
           m.nombre AS modelo_nombre, mk.nombre AS marca_nombre
      INTO v_activo
      FROM activos a
      LEFT JOIN modelos m ON m.id = a.modelo_id
      LEFT JOIN marcas mk ON mk.id = m.marca_id
     WHERE a.id = p_activo_id AND a.fecha_baja IS NULL;
    IF v_activo.id IS NULL THEN
        RETURN jsonb_build_object('error','activo_no_encontrado_o_baja');
    END IF;

    SELECT template_id, nivel_asignacion
      INTO v_template_id, v_nivel
      FROM fn_qr_resolver_template_para_activo(p_activo_id);
    IF v_template_id IS NULL THEN
        RETURN jsonb_build_object('error','sin_checklist_ni_universal');
    END IF;

    SELECT id, codigo, nombre, descripcion, es_universal,
           duracion_minima_segundos, cantidad_controles_aleatorios
      INTO v_template
      FROM qr_checklist_templates WHERE id = v_template_id;

    -- Items normales (NO control aleatorio)
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', i.id, 'seccion', i.seccion, 'orden', i.orden,
        'codigo_item', i.codigo_item, 'descripcion', i.descripcion,
        'tipo_respuesta', i.tipo_respuesta, 'criticidad_si_falla', i.criticidad_si_falla,
        'requiere_foto', i.requiere_foto,
        'requiere_foto_si_falla', i.requiere_foto_si_falla,
        'requiere_foto_siempre', i.requiere_foto_siempre,
        'requiere_observacion_si_falla', i.requiere_observacion_si_falla,
        'solo_camara', i.solo_camara,
        'es_control_aleatorio', false,
        'obligatorio', i.obligatorio,
        'valor_min', i.valor_min, 'valor_max', i.valor_max, 'unidad', i.unidad
    ) ORDER BY i.seccion, i.orden), '[]'::jsonb)
      INTO v_items_norm
      FROM qr_checklist_template_items i
     WHERE i.template_id = v_template_id AND i.es_control_aleatorio = false;

    -- Items aleatorios: seleccion random por checklist
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', i.id, 'seccion', i.seccion, 'orden', i.orden,
        'codigo_item', i.codigo_item, 'descripcion', i.descripcion,
        'tipo_respuesta', i.tipo_respuesta, 'criticidad_si_falla', i.criticidad_si_falla,
        'requiere_foto', i.requiere_foto,
        'requiere_foto_si_falla', i.requiere_foto_si_falla,
        'requiere_foto_siempre', i.requiere_foto_siempre,
        'requiere_observacion_si_falla', i.requiere_observacion_si_falla,
        'solo_camara', i.solo_camara,
        'es_control_aleatorio', true,
        'obligatorio', i.obligatorio,
        'valor_min', i.valor_min, 'valor_max', i.valor_max, 'unidad', i.unidad
    )), '[]'::jsonb)
      INTO v_items_rand
      FROM (
        SELECT * FROM qr_checklist_template_items
         WHERE template_id = v_template_id AND es_control_aleatorio = true
         ORDER BY random()
         LIMIT GREATEST(0, COALESCE(v_template.cantidad_controles_aleatorios, 2))
      ) i;

    RETURN jsonb_build_object(
        'activo', jsonb_build_object(
            'id', v_activo.id, 'codigo', v_activo.codigo, 'nombre', v_activo.nombre,
            'tipo', v_activo.tipo, 'criticidad', v_activo.criticidad,
            'kilometraje_actual', v_activo.kilometraje_actual,
            'horometro_actual', v_activo.horas_uso_actual,
            'modelo', v_activo.modelo_nombre, 'marca', v_activo.marca_nombre
        ),
        'template', jsonb_build_object(
            'id', v_template.id, 'codigo', v_template.codigo, 'nombre', v_template.nombre,
            'descripcion', v_template.descripcion, 'es_universal', v_template.es_universal,
            'duracion_minima_segundos', v_template.duracion_minima_segundos,
            'cantidad_controles_aleatorios', v_template.cantidad_controles_aleatorios,
            'nivel_asignacion', v_nivel,
            'declaracion_obligatoria', 'Declaro que inspeccione fisicamente el equipo antes de enviarlo.'
        ),
        'items', v_items_norm,
        'items_aleatorios', v_items_rand
    );
END; $$;
GRANT EXECUTE ON FUNCTION rpc_obtener_checklist_publico_por_qr(UUID) TO anon, authenticated;


-- ── 9. REPLACE: rpc_guardar_checklist_publico (con calidad) ─────────
CREATE OR REPLACE FUNCTION rpc_guardar_checklist_publico(p_payload jsonb)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_cliente_uuid UUID;
    v_activo_id    UUID;
    v_template_id  UUID;
    v_resp_id      UUID;
    v_existente    UUID;
    v_iniciado     TIMESTAMPTZ;
    v_terminado    TIMESTAMPTZ;
    v_dur_seg      INT;
    v_item         JSONB;
    v_items_falla  INT := 0;
    v_items_obs    INT := 0;
    v_semaforo     TEXT;
    v_alertas_t    INT;
    v_alertas_c    INT;
    v_score        INT;
    v_clasif       TEXT;
    v_dur_min      INT;
    v_sospechoso   BOOLEAN;
BEGIN
    v_cliente_uuid := (p_payload->>'cliente_uuid')::UUID;
    v_activo_id    := (p_payload->>'activo_id')::UUID;
    v_template_id  := (p_payload->>'template_id')::UUID;
    IF v_cliente_uuid IS NULL OR v_activo_id IS NULL OR v_template_id IS NULL THEN
        RAISE EXCEPTION 'payload invalido: cliente_uuid/activo_id/template_id obligatorios';
    END IF;

    -- Idempotencia
    SELECT id INTO v_existente FROM qr_checklist_respuestas WHERE cliente_uuid = v_cliente_uuid;
    IF v_existente IS NOT NULL THEN
        RETURN jsonb_build_object('success', true, 'ya_existia', true, 'respuesta_id', v_existente);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM activos WHERE id = v_activo_id AND fecha_baja IS NULL) THEN
        RAISE EXCEPTION 'activo no encontrado o dado de baja';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM qr_checklist_templates WHERE id = v_template_id AND activo = true) THEN
        RAISE EXCEPTION 'template no encontrado o inactivo';
    END IF;

    v_iniciado  := NULLIF(p_payload->>'iniciado_en','')::TIMESTAMPTZ;
    v_terminado := NULLIF(p_payload->>'terminado_en','')::TIMESTAMPTZ;
    IF v_iniciado IS NOT NULL AND v_terminado IS NOT NULL THEN
        v_dur_seg := EXTRACT(EPOCH FROM (v_terminado - v_iniciado))::INT;
    END IF;

    INSERT INTO qr_checklist_respuestas (
        cliente_uuid, activo_id, template_id,
        operador_nombre, operador_telefono, operador_email, operador_empresa,
        rut_operador, kilometraje_reportado, horometro_reportado,
        observacion_general, scan_lat, scan_lng, created_offline_at,
        iniciado_en, terminado_en, duracion_segundos,
        gps_inicial_lat, gps_inicial_lng, gps_inicial_precision_m,
        gps_final_lat, gps_final_lng, gps_final_precision_m,
        gps_no_disponible, firma_url, firma_declaracion, dispositivo_info
    ) VALUES (
        v_cliente_uuid, v_activo_id, v_template_id,
        NULLIF(p_payload->>'operador_nombre',''),
        NULLIF(p_payload->>'operador_telefono',''),
        NULLIF(p_payload->>'operador_email',''),
        NULLIF(p_payload->>'operador_empresa',''),
        NULLIF(p_payload->>'rut_operador',''),
        NULLIF(p_payload->>'kilometraje_reportado','')::NUMERIC,
        NULLIF(p_payload->>'horometro_reportado','')::NUMERIC,
        NULLIF(p_payload->>'observacion_general',''),
        NULLIF(p_payload->>'scan_lat','')::NUMERIC,
        NULLIF(p_payload->>'scan_lng','')::NUMERIC,
        NULLIF(p_payload->>'created_offline_at','')::TIMESTAMPTZ,
        v_iniciado, v_terminado, v_dur_seg,
        NULLIF(p_payload->>'gps_inicial_lat','')::NUMERIC,
        NULLIF(p_payload->>'gps_inicial_lng','')::NUMERIC,
        NULLIF(p_payload->>'gps_inicial_precision_m','')::NUMERIC,
        NULLIF(p_payload->>'gps_final_lat','')::NUMERIC,
        NULLIF(p_payload->>'gps_final_lng','')::NUMERIC,
        NULLIF(p_payload->>'gps_final_precision_m','')::NUMERIC,
        COALESCE((p_payload->>'gps_no_disponible')::BOOLEAN, false),
        NULLIF(p_payload->>'firma_url',''),
        NULLIF(p_payload->>'firma_declaracion',''),
        CASE WHEN p_payload ? 'dispositivo_info' THEN p_payload->'dispositivo_info' ELSE NULL END
    ) RETURNING id INTO v_resp_id;

    -- Items con metadatos
    IF jsonb_typeof(p_payload->'items') = 'array' THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_payload->'items') LOOP
            INSERT INTO qr_checklist_respuesta_items (
                respuesta_id, template_item_id, seccion, orden, codigo_item, descripcion,
                respuesta_tipo, respuesta_valor, es_falla, es_observacion, motivo, foto_url,
                respondido_en, orden_respuesta, tiempo_desde_inicio_segundos,
                cambio_respuesta, respuesta_original, foto_metadata, es_control_aleatorio
            ) VALUES (
                v_resp_id,
                NULLIF(v_item->>'template_item_id','')::UUID,
                COALESCE(v_item->>'seccion','SinSeccion'),
                COALESCE((v_item->>'orden')::INT, 0),
                COALESCE(v_item->>'codigo_item','sin_codigo'),
                v_item->>'descripcion',
                COALESCE(v_item->>'respuesta_tipo','ok_obs_falla'),
                v_item->>'respuesta_valor',
                COALESCE((v_item->>'es_falla')::BOOLEAN, false),
                COALESCE((v_item->>'es_observacion')::BOOLEAN, false),
                v_item->>'motivo',
                v_item->>'foto_url',
                NULLIF(v_item->>'respondido_en','')::TIMESTAMPTZ,
                NULLIF(v_item->>'orden_respuesta','')::INT,
                NULLIF(v_item->>'tiempo_desde_inicio_segundos','')::INT,
                COALESCE((v_item->>'cambio_respuesta')::BOOLEAN, false),
                v_item->>'respuesta_original',
                CASE WHEN v_item ? 'foto_metadata' THEN v_item->'foto_metadata' ELSE NULL END,
                COALESCE((v_item->>'es_control_aleatorio')::BOOLEAN, false)
            );
            IF COALESCE((v_item->>'es_falla')::BOOLEAN, false) THEN v_items_falla := v_items_falla + 1; END IF;
            IF COALESCE((v_item->>'es_observacion')::BOOLEAN, false) THEN v_items_obs := v_items_obs + 1; END IF;
        END LOOP;
    END IF;

    UPDATE qr_checklist_respuestas
       SET items_falla_count = v_items_falla,
           items_observacion_count = v_items_obs
     WHERE id = v_resp_id;

    -- Semaforo tecnico (14B)
    v_semaforo := fn_qr_evaluar_semaforo_respuesta(v_resp_id);
    -- Score calidad
    v_score := fn_qr_calcular_score_calidad_checklist(v_resp_id);
    SELECT duracion_minima_segundos INTO v_dur_min FROM qr_checklist_templates WHERE id = v_template_id;
    v_clasif := fn_qr_clasificar_calidad(v_score, v_dur_seg, v_dur_min);
    v_sospechoso := (v_clasif = 'sospechoso');

    UPDATE qr_checklist_respuestas
       SET semaforo = v_semaforo,
           score_calidad = v_score,
           clasificacion_calidad = v_clasif,
           sospechoso = v_sospechoso
     WHERE id = v_resp_id;

    -- Alertas tempranas tecnicas (14B)
    v_alertas_t := (rpc_generar_alerta_temprana(v_resp_id)->>'alertas_creadas')::INT;
    -- Alertas de calidad (14B2)
    v_alertas_c := fn_qr_evaluar_alertas_calidad(v_resp_id);

    INSERT INTO sync_queue_offline (cliente_uuid, evento_tipo, payload_resumen, procesado_at)
    VALUES (v_cliente_uuid, 'checklist_guardado',
            jsonb_build_object('respuesta_id', v_resp_id, 'semaforo', v_semaforo,
                               'score', v_score, 'clasificacion', v_clasif,
                               'sospechoso', v_sospechoso, 'duracion_segundos', v_dur_seg,
                               'alertas_tecnicas', v_alertas_t, 'alertas_calidad', v_alertas_c),
            NOW());

    RETURN jsonb_build_object(
        'success', true, 'ya_existia', false, 'respuesta_id', v_resp_id,
        'semaforo', v_semaforo,
        'score_calidad', v_score, 'clasificacion_calidad', v_clasif, 'sospechoso', v_sospechoso,
        'duracion_segundos', v_dur_seg, 'duracion_minima_segundos', v_dur_min,
        'items_falla', v_items_falla, 'items_observacion', v_items_obs,
        'alertas_tecnicas_generadas', v_alertas_t, 'alertas_calidad_generadas', v_alertas_c
    );
END; $$;
GRANT EXECUTE ON FUNCTION rpc_guardar_checklist_publico(jsonb) TO anon, authenticated;


-- ── 10. RPCs nuevas para mantenedor ─────────────────────────────────

-- 10.1 Marcar checklist como revisado / requiere reinspeccion / sin hallazgo / escalado
CREATE OR REPLACE FUNCTION rpc_marcar_checklist_revisado(
    p_respuesta_id UUID, p_estado_revision TEXT, p_observacion TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_qr_es_rol_mantencion() THEN RAISE EXCEPTION 'Rol no autorizado'; END IF;
    IF p_estado_revision NOT IN ('validado','requiere_reinspeccion','sin_hallazgo','escalado') THEN
        RAISE EXCEPTION 'estado_revision invalido';
    END IF;

    UPDATE qr_checklist_respuestas
       SET estado_revision = p_estado_revision,
           revisado_por = v_uid,
           revisado_en = NOW(),
           observacion_general = COALESCE(observacion_general,'') ||
                                 CASE WHEN p_observacion IS NOT NULL
                                      THEN E'\n[REVISION ' || NOW()::DATE::TEXT || '] ' || p_observacion
                                      ELSE '' END
     WHERE id = p_respuesta_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'checklist no encontrado'; END IF;
    RETURN jsonb_build_object('success', true, 'estado_revision', p_estado_revision);
END; $$;
GRANT EXECUTE ON FUNCTION rpc_marcar_checklist_revisado(UUID, TEXT, TEXT) TO authenticated;

-- 10.2 Revisar alerta de calidad (cerrar / confirmar / descartar)
CREATE OR REPLACE FUNCTION rpc_revisar_alerta_calidad(
    p_alerta_id UUID, p_nuevo_estado TEXT, p_accion TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_qr_es_rol_mantencion() THEN RAISE EXCEPTION 'Rol no autorizado'; END IF;
    IF p_nuevo_estado NOT IN ('en_revision','confirmada','descartada') THEN
        RAISE EXCEPTION 'estado invalido';
    END IF;
    IF p_accion IS NULL OR LENGTH(TRIM(p_accion)) < 5 THEN
        RAISE EXCEPTION 'accion debe tener al menos 5 caracteres';
    END IF;

    UPDATE qr_checklist_alertas_calidad
       SET estado = p_nuevo_estado,
           revisada_por = v_uid,
           revisada_en = NOW(),
           accion_revision = TRIM(p_accion)
     WHERE id = p_alerta_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'alerta calidad no encontrada'; END IF;
    RETURN jsonb_build_object('success', true, 'alerta_id', p_alerta_id, 'estado', p_nuevo_estado);
END; $$;
GRANT EXECUTE ON FUNCTION rpc_revisar_alerta_calidad(UUID, TEXT, TEXT) TO authenticated;


-- ── 11. Vista KPIs por operador (gamificacion responsable) ──────────
-- Refactor: CTE base agrupa, SELECT externo agrega subqueries correlacionadas
-- usando b.operador_norm (columna no agrupada del CTE). Evita error 42803.
CREATE OR REPLACE VIEW v_qr_checklist_kpi_operador AS
WITH base AS (
    SELECT
        LOWER(COALESCE(r.operador_nombre,'(sin nombre)'))                            AS operador_norm,
        COALESCE(r.operador_nombre, '(sin nombre)')                                  AS operador_nombre,
        COUNT(*)::int                                                                AS total_checklists,
        COUNT(*) FILTER (WHERE r.semaforo = 'verde')::int                            AS total_verde,
        COUNT(*) FILTER (WHERE r.semaforo IN ('amarillo','naranja','rojo'))::int     AS total_con_hallazgo,
        ROUND(AVG(r.score_calidad)::numeric, 1)                                      AS score_promedio,
        ROUND(AVG(r.duracion_segundos)::numeric, 0)                                  AS duracion_promedio_seg,
        COUNT(*) FILTER (WHERE r.sospechoso = true)::int                             AS sospechosos,
        COUNT(*) FILTER (WHERE r.clasificacion_calidad = 'baja')::int                AS calidad_baja,
        COUNT(*) FILTER (WHERE r.clasificacion_calidad = 'media')::int               AS calidad_media,
        COUNT(*) FILTER (WHERE r.clasificacion_calidad = 'alta')::int                AS calidad_alta,
        MAX(r.sincronizado_at)                                                       AS ultimo_checklist_at
    FROM qr_checklist_respuestas r
    WHERE r.sincronizado_at >= NOW() - INTERVAL '90 days'
    GROUP BY LOWER(COALESCE(r.operador_nombre,'(sin nombre)')),
             COALESCE(r.operador_nombre, '(sin nombre)')
)
SELECT
    b.operador_norm,
    b.operador_nombre,
    b.total_checklists,
    b.total_verde,
    b.total_con_hallazgo,
    b.score_promedio,
    b.duracion_promedio_seg,
    b.sospechosos,
    b.calidad_baja,
    b.calidad_media,
    b.calidad_alta,
    (SELECT COUNT(*)::int FROM qr_checklist_alertas_calidad ac
       WHERE LOWER(COALESCE(ac.operador_nombre,'')) = b.operador_norm
         AND ac.created_at >= NOW() - INTERVAL '30 days')                            AS alertas_calidad_30d,
    (SELECT COUNT(*)::int FROM qr_checklist_alertas_calidad ac
       WHERE LOWER(COALESCE(ac.operador_nombre,'')) = b.operador_norm
         AND ac.estado = 'confirmada')                                               AS alertas_calidad_confirmadas,
    b.ultimo_checklist_at
FROM base b;
GRANT SELECT ON v_qr_checklist_kpi_operador TO authenticated;


-- ── 12. Bitacora ────────────────────────────────────────────────────
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema='public' AND table_name='operacion_migraciones_log') THEN
        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'PROD_MIG14B2_QR_CALIDAD',
            'Modulo QR Checklist Control de Calidad (paso 14B2).',
            current_user, NOW(), NOW(), 'ok',
            'Score 0-100 + alertas calidad + items aleatorios + duracion minima + GPS + firma + KPIs operador.'
        );
    END IF;
END $$;


-- ── 13. Verificacion estructural ────────────────────────────────────
SELECT 'COL_RESP_DURACION' AS check_name,
       (SELECT COUNT(*) FROM information_schema.columns
         WHERE table_name='qr_checklist_respuestas'
           AND column_name IN ('iniciado_en','terminado_en','duracion_segundos',
                               'score_calidad','clasificacion_calidad','sospechoso',
                               'gps_inicial_lat','gps_final_lat','firma_declaracion',
                               'dispositivo_info','estado_revision'))::int AS encontradas
       /* esperado: 11 */;

SELECT 'COL_TPL_ITEM_FLAGS' AS check_name,
       (SELECT COUNT(*) FROM information_schema.columns
         WHERE table_name='qr_checklist_template_items'
           AND column_name IN ('requiere_foto_si_falla','requiere_foto_siempre',
                               'requiere_observacion_si_falla','solo_camara','es_control_aleatorio'))::int AS encontradas
       /* esperado: 5 */;

SELECT 'TABLA_ALERTAS_CALIDAD' AS check_name,
       (SELECT COUNT(*) FROM information_schema.tables
         WHERE table_schema='public' AND table_name='qr_checklist_alertas_calidad')::int AS existe;

SELECT 'FN_SCORE_CALIDAD' AS check_name,
       (CASE WHEN to_regprocedure('public.fn_qr_calcular_score_calidad_checklist(uuid)') IS NOT NULL
             THEN 1 ELSE 0 END)::int AS existe;

SELECT 'TPL_DUR_MIN' AS check_name,
       (SELECT COUNT(*) FROM qr_checklist_templates
         WHERE activo=true AND duracion_minima_segundos > 0)::int AS templates_con_dur_min;

SELECT 'ITEMS_CONTROL_ALEATORIO' AS check_name,
       (SELECT COUNT(*) FROM qr_checklist_template_items WHERE es_control_aleatorio=true)::int AS total;


-- ============================================================================
-- ROLLBACK (manual)
-- DROP FUNCTION IF EXISTS rpc_revisar_alerta_calidad(UUID,TEXT,TEXT) CASCADE;
-- DROP FUNCTION IF EXISTS rpc_marcar_checklist_revisado(UUID,TEXT,TEXT) CASCADE;
-- DROP FUNCTION IF EXISTS fn_qr_evaluar_alertas_calidad(UUID) CASCADE;
-- DROP FUNCTION IF EXISTS fn_qr_clasificar_calidad(INT,INT,INT) CASCADE;
-- DROP FUNCTION IF EXISTS fn_qr_calcular_score_calidad_checklist(UUID) CASCADE;
-- DROP VIEW  IF EXISTS v_qr_checklist_kpi_operador;
-- DROP TABLE IF EXISTS qr_checklist_alertas_calidad CASCADE;
-- DELETE FROM qr_checklist_template_items WHERE es_control_aleatorio = true;
-- ALTER TABLE qr_checklist_respuesta_items
--   DROP COLUMN IF EXISTS respondido_en, DROP COLUMN IF EXISTS orden_respuesta,
--   DROP COLUMN IF EXISTS tiempo_desde_inicio_segundos, DROP COLUMN IF EXISTS cambio_respuesta,
--   DROP COLUMN IF EXISTS respuesta_original, DROP COLUMN IF EXISTS foto_metadata,
--   DROP COLUMN IF EXISTS es_control_aleatorio;
-- ALTER TABLE qr_checklist_respuestas
--   DROP COLUMN IF EXISTS iniciado_en, DROP COLUMN IF EXISTS terminado_en,
--   DROP COLUMN IF EXISTS duracion_segundos, DROP COLUMN IF EXISTS gps_inicial_lat,
--   DROP COLUMN IF EXISTS gps_inicial_lng, DROP COLUMN IF EXISTS gps_inicial_precision_m,
--   DROP COLUMN IF EXISTS gps_final_lat, DROP COLUMN IF EXISTS gps_final_lng,
--   DROP COLUMN IF EXISTS gps_final_precision_m, DROP COLUMN IF EXISTS gps_no_disponible,
--   DROP COLUMN IF EXISTS rut_operador, DROP COLUMN IF EXISTS firma_url,
--   DROP COLUMN IF EXISTS firma_declaracion, DROP COLUMN IF EXISTS dispositivo_info,
--   DROP COLUMN IF EXISTS score_calidad, DROP COLUMN IF EXISTS clasificacion_calidad,
--   DROP COLUMN IF EXISTS sospechoso, DROP COLUMN IF EXISTS revisado_por,
--   DROP COLUMN IF EXISTS revisado_en, DROP COLUMN IF EXISTS estado_revision;
-- ALTER TABLE qr_checklist_template_items
--   DROP COLUMN IF EXISTS requiere_foto_si_falla, DROP COLUMN IF EXISTS requiere_foto_siempre,
--   DROP COLUMN IF EXISTS requiere_observacion_si_falla, DROP COLUMN IF EXISTS solo_camara,
--   DROP COLUMN IF EXISTS es_control_aleatorio;
-- ALTER TABLE qr_checklist_templates
--   DROP COLUMN IF EXISTS duracion_minima_segundos,
--   DROP COLUMN IF EXISTS cantidad_controles_aleatorios;
-- ============================================================================
