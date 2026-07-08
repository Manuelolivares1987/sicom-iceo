-- ============================================================================
-- SICOM-ICEO | 207 — Motor de pautas ENEX (checklists de mantención/calibración)
-- ============================================================================
-- Fase 2 (parte 1). Manuel (2026-07-08): pautas editables en la app. Se
-- siembra la pauta REAL de lubricantes (única con detalle ítem por ítem en la
-- carpeta) y BORRADORES de calibración y mantención (EESS/petrolera/semimóvil/
-- camión) redactados desde el método del contrato y los manuales de fabricante,
-- para que Manuel/supervisores los corrijan en el editor.
--
--   * enex_pautas (plantilla por tipo de servicio + tipos de instalación).
--   * enex_pauta_items (bloque, periodicidad, tipo de campo: ok_nook /
--     medicion con tolerancia (±50cc calibración) / si_no / texto, foto).
--   * Vínculo opcional pauta↔instalación (pauta_mantencion_id / _calibracion_id);
--     si no hay override se resuelve por tipo de instalación + servicio.
--   * RPCs CRUD para el editor.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 0. PRECHECK ──────────────────────────────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='enex_instalaciones') THEN
        RAISE EXCEPTION 'STOP — falta MIG206'; END IF;
END $$;

-- ── 1. Tablas ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS enex_pautas (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo        TEXT UNIQUE NOT NULL,
    nombre        TEXT NOT NULL,
    tipo_servicio TEXT NOT NULL CHECK (tipo_servicio IN ('mantencion','calibracion')),
    aplica_tipos  TEXT[] NOT NULL DEFAULT '{}',   -- eess/petrolera/semimovil/truck_shop/camion
    linea         TEXT CHECK (linea IN ('combustible','lubricante')),
    version       INT NOT NULL DEFAULT 1,
    es_borrador   BOOLEAN NOT NULL DEFAULT false,
    activo        BOOLEAN NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ DEFAULT now(),
    updated_at    TIMESTAMPTZ DEFAULT now()
);
COMMENT ON TABLE enex_pautas IS 'Plantillas de pauta (checklist) por tipo de servicio/instalación. MIG207.';

CREATE TABLE IF NOT EXISTS enex_pauta_items (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pauta_id      UUID NOT NULL REFERENCES enex_pautas(id) ON DELETE CASCADE,
    bloque        TEXT NOT NULL DEFAULT 'General',
    bloque_orden  INT NOT NULL DEFAULT 1,
    orden         INT NOT NULL DEFAULT 1,
    codigo        TEXT,                              -- 1.1, 2.3
    descripcion   TEXT NOT NULL,
    periodicidad  TEXT DEFAULT 'trimestral'
                     CHECK (periodicidad IN ('trimestral','mensual','anual','semestral','requerimiento')),
    tipo_campo    TEXT NOT NULL DEFAULT 'ok_nook'
                     CHECK (tipo_campo IN ('ok_nook','medicion','si_no','texto')),
    unidad        TEXT,                              -- cc, V, A, °C, L
    valor_referencia NUMERIC,                        -- p.ej. 20000 (20 L en cc)
    tolerancia_min NUMERIC,                          -- p.ej. -50 (cc)
    tolerancia_max NUMERIC,                          -- p.ej. +50 (cc)
    requiere_foto BOOLEAN NOT NULL DEFAULT false,
    obligatorio   BOOLEAN NOT NULL DEFAULT true,
    activo        BOOLEAN NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_enex_pauta_items_pauta ON enex_pauta_items(pauta_id) WHERE activo;
COMMENT ON TABLE enex_pauta_items IS 'Ítems de una pauta. tipo_campo medicion usa valor_referencia + tolerancia (±50cc calibración). MIG207.';

ALTER TABLE enex_instalaciones
    ADD COLUMN IF NOT EXISTS pauta_mantencion_id  UUID REFERENCES enex_pautas(id),
    ADD COLUMN IF NOT EXISTS pauta_calibracion_id UUID REFERENCES enex_pautas(id);

-- ── 2. RLS ───────────────────────────────────────────────────────────────────
ALTER TABLE enex_pautas       ENABLE ROW LEVEL SECURITY;
ALTER TABLE enex_pauta_items  ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
    DROP POLICY IF EXISTS pol_enex_pautas_sel ON enex_pautas;
    CREATE POLICY pol_enex_pautas_sel ON enex_pautas FOR SELECT TO authenticated USING (fn_user_rol() IS NOT NULL);
    DROP POLICY IF EXISTS pol_enex_pauta_items_sel ON enex_pauta_items;
    CREATE POLICY pol_enex_pauta_items_sel ON enex_pauta_items FOR SELECT TO authenticated USING (fn_user_rol() IS NOT NULL);
END $$;

-- ── 3. RPCs del editor ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_enex_pauta_guardar(
    p_id UUID, p_codigo TEXT, p_nombre TEXT, p_tipo_servicio TEXT,
    p_aplica_tipos TEXT[], p_linea TEXT DEFAULT NULL, p_es_borrador BOOLEAN DEFAULT true
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID := p_id;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    IF p_id IS NULL THEN
        INSERT INTO enex_pautas (codigo, nombre, tipo_servicio, aplica_tipos, linea, es_borrador)
        VALUES (p_codigo, p_nombre, p_tipo_servicio, COALESCE(p_aplica_tipos,'{}'), p_linea, p_es_borrador)
        RETURNING id INTO v_id;
    ELSE
        UPDATE enex_pautas SET codigo=p_codigo, nombre=p_nombre, tipo_servicio=p_tipo_servicio,
            aplica_tipos=COALESCE(p_aplica_tipos,'{}'), linea=p_linea, es_borrador=p_es_borrador, updated_at=NOW()
         WHERE id=p_id;
    END IF;
    RETURN jsonb_build_object('success', true, 'pauta_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_pauta_guardar(UUID,TEXT,TEXT,TEXT,TEXT[],TEXT,BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION rpc_enex_pauta_item_guardar(
    p_id UUID, p_pauta_id UUID, p_bloque TEXT, p_bloque_orden INT, p_orden INT,
    p_codigo TEXT, p_descripcion TEXT, p_periodicidad TEXT, p_tipo_campo TEXT,
    p_unidad TEXT DEFAULT NULL, p_valor_referencia NUMERIC DEFAULT NULL,
    p_tolerancia_min NUMERIC DEFAULT NULL, p_tolerancia_max NUMERIC DEFAULT NULL,
    p_requiere_foto BOOLEAN DEFAULT false, p_obligatorio BOOLEAN DEFAULT true
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID := p_id;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    IF p_id IS NULL THEN
        INSERT INTO enex_pauta_items (pauta_id, bloque, bloque_orden, orden, codigo, descripcion,
            periodicidad, tipo_campo, unidad, valor_referencia, tolerancia_min, tolerancia_max,
            requiere_foto, obligatorio)
        VALUES (p_pauta_id, COALESCE(NULLIF(TRIM(p_bloque),''),'General'), COALESCE(p_bloque_orden,1),
            COALESCE(p_orden,1), p_codigo, p_descripcion, COALESCE(p_periodicidad,'trimestral'),
            COALESCE(p_tipo_campo,'ok_nook'), p_unidad, p_valor_referencia, p_tolerancia_min,
            p_tolerancia_max, COALESCE(p_requiere_foto,false), COALESCE(p_obligatorio,true))
        RETURNING id INTO v_id;
    ELSE
        UPDATE enex_pauta_items SET bloque=COALESCE(NULLIF(TRIM(p_bloque),''),'General'),
            bloque_orden=COALESCE(p_bloque_orden,bloque_orden), orden=COALESCE(p_orden,orden),
            codigo=p_codigo, descripcion=p_descripcion, periodicidad=COALESCE(p_periodicidad,periodicidad),
            tipo_campo=COALESCE(p_tipo_campo,tipo_campo), unidad=p_unidad, valor_referencia=p_valor_referencia,
            tolerancia_min=p_tolerancia_min, tolerancia_max=p_tolerancia_max,
            requiere_foto=COALESCE(p_requiere_foto,requiere_foto), obligatorio=COALESCE(p_obligatorio,obligatorio)
         WHERE id=p_id;
    END IF;
    RETURN jsonb_build_object('success', true, 'item_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_pauta_item_guardar(UUID,UUID,TEXT,INT,INT,TEXT,TEXT,TEXT,TEXT,TEXT,NUMERIC,NUMERIC,NUMERIC,BOOLEAN,BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION rpc_enex_pauta_item_eliminar(p_item_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    UPDATE enex_pauta_items SET activo=false WHERE id=p_item_id;
    RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_pauta_item_eliminar(UUID) TO authenticated;

-- Vincular pauta a una instalación (override)
CREATE OR REPLACE FUNCTION rpc_enex_instalacion_set_pauta(
    p_instalacion_id UUID, p_tipo_servicio TEXT, p_pauta_id UUID
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    IF p_tipo_servicio = 'mantencion' THEN
        UPDATE enex_instalaciones SET pauta_mantencion_id=p_pauta_id, updated_at=NOW() WHERE id=p_instalacion_id;
    ELSE
        UPDATE enex_instalaciones SET pauta_calibracion_id=p_pauta_id, updated_at=NOW() WHERE id=p_instalacion_id;
    END IF;
    RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_instalacion_set_pauta(UUID,TEXT,UUID) TO authenticated;

-- ── 4. Helper de seed + siembra ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_enex_seed_pauta(
    p_codigo TEXT, p_nombre TEXT, p_tipo_servicio TEXT, p_aplica TEXT[], p_linea TEXT,
    p_borrador BOOLEAN, p_items JSONB
) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_pid UUID; it JSONB; v_bo INT := 0; v_prev_bloque TEXT := ''; v_ord INT := 0;
BEGIN
    IF EXISTS (SELECT 1 FROM enex_pautas WHERE codigo=p_codigo) THEN RETURN; END IF;
    INSERT INTO enex_pautas (codigo, nombre, tipo_servicio, aplica_tipos, linea, es_borrador)
    VALUES (p_codigo, p_nombre, p_tipo_servicio, p_aplica, p_linea, p_borrador) RETURNING id INTO v_pid;
    FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        IF (it->>'bloque') IS DISTINCT FROM v_prev_bloque THEN
            v_bo := v_bo + 1; v_prev_bloque := it->>'bloque'; v_ord := 0;
        END IF;
        v_ord := v_ord + 1;
        INSERT INTO enex_pauta_items (pauta_id, bloque, bloque_orden, orden, codigo, descripcion,
            periodicidad, tipo_campo, unidad, valor_referencia, tolerancia_min, tolerancia_max, requiere_foto)
        VALUES (v_pid, it->>'bloque', v_bo, v_ord, it->>'codigo', it->>'desc',
            COALESCE(it->>'per','trimestral'), COALESCE(it->>'campo','ok_nook'),
            it->>'unidad', (it->>'ref')::NUMERIC, (it->>'tmin')::NUMERIC, (it->>'tmax')::NUMERIC,
            COALESCE((it->>'foto')::BOOLEAN,false));
    END LOOP;
END $$;

-- 4.1 LUBRICANTES (real, del PDF) — no borrador
SELECT fn_enex_seed_pauta('PAUTA-LUB','Pauta Lubricantes (Truck Shops)','mantencion',
  ARRAY['truck_shop'],'lubricante', false, $j$[
  {"bloque":"1. Housekeeping de instalaciones","codigo":"1.1","desc":"Limpieza exterior de líneas de lubricantes","per":"trimestral"},
  {"bloque":"1. Housekeeping de instalaciones","codigo":"1.2","desc":"Limpieza exterior de equipos de filtrado","per":"trimestral"},
  {"bloque":"1. Housekeeping de instalaciones","codigo":"1.3","desc":"Limpieza de bocatomas de carga de lubricantes","per":"trimestral"},
  {"bloque":"1. Housekeeping de instalaciones","codigo":"1.4","desc":"Revisión y limpieza de piso interior pretil","per":"trimestral"},
  {"bloque":"1. Housekeeping de instalaciones","codigo":"1.5","desc":"Lavado exterior TK lubricantes","per":"requerimiento"},
  {"bloque":"1. Housekeeping de instalaciones","codigo":"1.6","desc":"Lavado interior pretil","per":"requerimiento"},
  {"bloque":"1. Housekeeping de instalaciones","codigo":"1.7","desc":"Pintado interior pretil","per":"requerimiento"},
  {"bloque":"1. Housekeeping de instalaciones","codigo":"1.8","desc":"Limpieza interior pretil unidad de bombeo","per":"requerimiento"},
  {"bloque":"1. Housekeeping de instalaciones","codigo":"1.9","desc":"Limpieza losa estacionamiento descarga camión","per":"requerimiento"},
  {"bloque":"2. Sala de microfiltrado","codigo":"2.1","desc":"Toma / retiro de muestras (Cód. ISO)","per":"requerimiento"},
  {"bloque":"2. Sala de microfiltrado","codigo":"2.2","desc":"Cambio de filtros unidades de microfiltrado","per":"requerimiento"},
  {"bloque":"2. Sala de microfiltrado","codigo":"2.3","desc":"Cambio de filtros de venteo","per":"requerimiento"},
  {"bloque":"2. Sala de microfiltrado","codigo":"2.4","desc":"Inspección de manómetros de presión","per":"trimestral"},
  {"bloque":"2. Sala de microfiltrado","codigo":"2.5","desc":"Inspección sensores de temperatura","per":"trimestral"},
  {"bloque":"2. Sala de microfiltrado","codigo":"2.6","desc":"Inspección de calefactores","per":"trimestral"},
  {"bloque":"2. Sala de microfiltrado","codigo":"2.7","desc":"Mantención calefactores","per":"trimestral"},
  {"bloque":"2. Sala de microfiltrado","codigo":"2.8","desc":"Inspección de electroválvulas","per":"requerimiento"},
  {"bloque":"2. Sala de microfiltrado","codigo":"2.9","desc":"Eliminación de fugas","per":"requerimiento"},
  {"bloque":"3. Mantención Mecánica","codigo":"3.1","desc":"Alineamiento de motores","per":"requerimiento"},
  {"bloque":"3. Mantención Mecánica","codigo":"3.2","desc":"Mantención bombas de diafragma 2\"","per":"trimestral"},
  {"bloque":"3. Mantención Mecánica","codigo":"3.3","desc":"Mantención de electroválvulas","per":"trimestral"},
  {"bloque":"3. Mantención Mecánica","codigo":"3.4","desc":"Inspección vibraciones","per":"requerimiento"},
  {"bloque":"3. Mantención Mecánica","codigo":"3.5","desc":"Medición de niveles de TK","per":"requerimiento"},
  {"bloque":"3. Mantención Mecánica","codigo":"3.6","desc":"Mantención unidades de microfiltrado","per":"trimestral"},
  {"bloque":"3. Mantención Mecánica","codigo":"3.7","desc":"Mantención unidad de trasvasije","per":"trimestral"},
  {"bloque":"3. Mantención Mecánica","codigo":"3.8","desc":"Inspección de TK de refrigerante","per":"trimestral"},
  {"bloque":"3. Mantención Mecánica","codigo":"3.9","desc":"Inspección de TK de aceite residual","per":"trimestral"},
  {"bloque":"4. Mantención Eléctrica","codigo":"4.1","desc":"Medición de tierras","per":"anual","campo":"medicion","unidad":"Ω"},
  {"bloque":"4. Mantención Eléctrica","codigo":"4.2","desc":"Medición de voltaje por unidad","per":"trimestral","campo":"medicion","unidad":"V"},
  {"bloque":"4. Mantención Eléctrica","codigo":"4.3","desc":"Medición de amperaje por unidad","per":"trimestral","campo":"medicion","unidad":"A"},
  {"bloque":"4. Mantención Eléctrica","codigo":"4.4","desc":"Medición de temperatura del motor eléctrico","per":"trimestral","campo":"medicion","unidad":"°C"},
  {"bloque":"4. Mantención Eléctrica","codigo":"4.5","desc":"Inspección parada de emergencia","per":"trimestral"},
  {"bloque":"4. Mantención Eléctrica","codigo":"4.6","desc":"Revisión puesta a tierra tablero","per":"trimestral"},
  {"bloque":"4. Mantención Eléctrica","codigo":"4.7","desc":"Revisión estado de rotulación y diagrama eléctrico","per":"trimestral"},
  {"bloque":"5. Mantención Lubricanteras","codigo":"5.1","desc":"Inspección estaciones de carrete","per":"trimestral"},
  {"bloque":"5. Mantención Lubricanteras","codigo":"5.2","desc":"Eliminación de fugas","per":"requerimiento"},
  {"bloque":"5. Mantención Lubricanteras","codigo":"5.3","desc":"Inspección de ductos de lubricantes","per":"trimestral"},
  {"bloque":"5. Mantención Lubricanteras","codigo":"5.4","desc":"Inspección de válvulas manuales","per":"trimestral"},
  {"bloque":"5. Mantención Lubricanteras","codigo":"5.5","desc":"Limpieza de lubricanteras","per":"requerimiento"},
  {"bloque":"5. Mantención Lubricanteras","codigo":"5.6","desc":"Inspección estado y/o cambio de test point","per":"requerimiento"},
  {"bloque":"5. Mantención Lubricanteras","codigo":"5.7","desc":"Inspección estado y/o cambio de carretes","per":"requerimiento"},
  {"bloque":"5. Mantención Lubricanteras","codigo":"5.8","desc":"Inspección estado y/o cambio de pistolas","per":"requerimiento"}
  ]$j$);

-- 4.2 CALIBRACIÓN EESS (BORRADOR — método ±50cc Norma Chilena)
SELECT fn_enex_seed_pauta('PAUTA-CAL-EESS','Pauta Calibración EESS (BORRADOR)','calibracion',
  ARRAY['eess'],'combustible', true, $j$[
  {"bloque":"1. Preparación","codigo":"1.1","desc":"Segregación del área y EPP obligatorio verificado","per":"trimestral"},
  {"bloque":"1. Preparación","codigo":"1.2","desc":"Autorización de carga / enclavamiento sistema automatizado","per":"trimestral"},
  {"bloque":"1. Preparación","codigo":"1.3","desc":"Matraz certificado nivelado; registro de numerales de inicio y sellos","per":"trimestral","foto":true},
  {"bloque":"2. Prueba volumétrica (por surtidor/pistola)","codigo":"2.1","desc":"Despacho 20 L al matraz — diferencia respecto al patrón","per":"trimestral","campo":"medicion","unidad":"cc","ref":0,"tmin":-50,"tmax":50,"foto":true},
  {"bloque":"2. Prueba volumétrica (por surtidor/pistola)","codigo":"2.2","desc":"Resultado dentro de tolerancia Norma Chilena (±50 cc)","per":"trimestral","campo":"si_no"},
  {"bloque":"3. Cierre","codigo":"3.1","desc":"Registro de numerales de término","per":"trimestral"},
  {"bloque":"3. Cierre","codigo":"3.2","desc":"Instalación de sellos metrológicos y registro","per":"trimestral","foto":true}
  ]$j$);

-- 4.3 CALIBRACIÓN PETROLERAS / TKS VERTICALES (BORRADOR — máster meter)
SELECT fn_enex_seed_pauta('PAUTA-CAL-PET','Pauta Calibración Petroleras/Tks Verticales (BORRADOR)','calibracion',
  ARRAY['petrolera','semimovil'],'combustible', true, $j$[
  {"bloque":"1. Preparación","codigo":"1.1","desc":"Segregación, EPP y medidor patrón (máster meter) certificado","per":"trimestral"},
  {"bloque":"2. Verificación","codigo":"2.1","desc":"Comparación medidor instalado vs máster meter","per":"trimestral","campo":"medicion","unidad":"cc","ref":0,"tmin":-50,"tmax":50,"foto":true},
  {"bloque":"2. Verificación","codigo":"2.2","desc":"Conformidad frente al patrón certificado","per":"trimestral","campo":"si_no"},
  {"bloque":"3. Cierre","codigo":"3.1","desc":"Sellos y registro","per":"trimestral","foto":true}
  ]$j$);

-- 4.4 CALIBRACIÓN CAMIONES TANQUE (BORRADOR)
SELECT fn_enex_seed_pauta('PAUTA-CAL-CAM','Pauta Calibración Camiones Tanque (BORRADOR)','calibracion',
  ARRAY['camion'],'combustible', true, $j$[
  {"bloque":"1. Preparación","codigo":"1.1","desc":"Segregación, EPP y patrón de aforo certificado","per":"trimestral"},
  {"bloque":"2. Aforo por compartimento","codigo":"2.1","desc":"Verificación de volumen nominal por compartimento","per":"trimestral","campo":"medicion","unidad":"L","foto":true},
  {"bloque":"2. Aforo por compartimento","codigo":"2.2","desc":"Diferencia dentro de tolerancia","per":"trimestral","campo":"si_no"},
  {"bloque":"3. Cierre","codigo":"3.1","desc":"Sellos y certificado","per":"trimestral","foto":true}
  ]$j$);

-- 4.5 MANTENIMIENTO EESS (BORRADOR — surtidores Wayne/Gilbarco)
SELECT fn_enex_seed_pauta('PAUTA-MANT-EESS','Pauta Mantenimiento EESS (BORRADOR)','mantencion',
  ARRAY['eess'],'combustible', true, $j$[
  {"bloque":"1. Surtidores","codigo":"1.1","desc":"Revisión display, teclado y totalizadores","per":"trimestral"},
  {"bloque":"1. Surtidores","codigo":"1.2","desc":"Revisión sistema de control de venta","per":"trimestral"},
  {"bloque":"1. Surtidores","codigo":"1.3","desc":"Estado de calcomanías y rotulación","per":"trimestral"},
  {"bloque":"2. Pistolas y mangueras","codigo":"2.1","desc":"Estado de pistolas, gatillo y corte automático","per":"trimestral"},
  {"bloque":"2. Pistolas y mangueras","codigo":"2.2","desc":"Estado de mangueras, swivel y breakaway","per":"trimestral"},
  {"bloque":"2. Pistolas y mangueras","codigo":"2.3","desc":"Verificación de fugas","per":"trimestral","foto":true},
  {"bloque":"3. Filtros y sistema","codigo":"3.1","desc":"Estado / cambio de filtros","per":"trimestral"},
  {"bloque":"3. Filtros y sistema","codigo":"3.2","desc":"Prueba de hermeticidad","per":"trimestral"},
  {"bloque":"4. Seguridad","codigo":"4.1","desc":"Parada de emergencia y aterrizado operativos","per":"trimestral"}
  ]$j$);

-- 4.6 MANTENIMIENTO PETROLERAS (BORRADOR — estanques verticales)
SELECT fn_enex_seed_pauta('PAUTA-MANT-PET','Pauta Mantenimiento Petroleras (BORRADOR)','mantencion',
  ARRAY['petrolera'],'combustible', true, $j$[
  {"bloque":"1. Estanque y contención","codigo":"1.1","desc":"Estado del estanque vertical y pretil de contención","per":"trimestral","foto":true},
  {"bloque":"1. Estanque y contención","codigo":"1.2","desc":"Venteos y válvulas de alivio","per":"trimestral"},
  {"bloque":"2. Sistema de bombeo","codigo":"2.1","desc":"Bombas: estado, fugas, presión","per":"trimestral"},
  {"bloque":"2. Sistema de bombeo","codigo":"2.2","desc":"Válvulas manuales y de control","per":"trimestral"},
  {"bloque":"3. Medición","codigo":"3.1","desc":"Sistema de medición / nivel","per":"trimestral"},
  {"bloque":"4. Seguridad","codigo":"4.1","desc":"Parada de emergencia y puesta a tierra","per":"trimestral"}
  ]$j$);

-- 4.7 MANTENIMIENTO SEMIMÓVIL (BORRADOR — manuales Rafer)
SELECT fn_enex_seed_pauta('PAUTA-MANT-SM','Pauta Mantenimiento Semimóvil (BORRADOR)','mantencion',
  ARRAY['semimovil'],'combustible', true, $j$[
  {"bloque":"1. Estructura y contención","codigo":"1.1","desc":"Estado de plataforma, estanque y pretil","per":"trimestral","foto":true},
  {"bloque":"2. Sistema de bombeo","codigo":"2.1","desc":"Sala de bombas: bombas, mangueras y fugas","per":"trimestral"},
  {"bloque":"2. Sistema de bombeo","codigo":"2.2","desc":"Válvulas de control (adaptador, válvula de fondo)","per":"trimestral"},
  {"bloque":"3. Medición y despacho","codigo":"3.1","desc":"Medidores y brazos de carga/descarga","per":"trimestral"},
  {"bloque":"4. Seguridad","codigo":"4.1","desc":"Sistema de extinción de incendio operativo","per":"trimestral","foto":true},
  {"bloque":"4. Seguridad","codigo":"4.2","desc":"Parada de emergencia, aterrizado y señalética","per":"trimestral"}
  ]$j$);

DROP FUNCTION fn_enex_seed_pauta(TEXT,TEXT,TEXT,TEXT[],TEXT,BOOLEAN,JSONB);

-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'tablas', (SELECT array_agg(table_name ORDER BY table_name) FROM information_schema.tables
        WHERE table_name IN ('enex_pautas','enex_pauta_items')),
    'pautas', (SELECT jsonb_agg(jsonb_build_object('codigo', codigo, 'items',
        (SELECT COUNT(*) FROM enex_pauta_items i WHERE i.pauta_id=p.id), 'borrador', es_borrador) ORDER BY codigo)
        FROM enex_pautas p),
    'rpcs', (SELECT COUNT(*) FROM pg_proc WHERE proname LIKE 'rpc_enex_pauta%' OR proname='rpc_enex_instalacion_set_pauta')
) AS resultado;

NOTIFY pgrst, 'reload schema';
