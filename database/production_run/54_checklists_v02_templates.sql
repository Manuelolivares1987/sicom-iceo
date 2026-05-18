-- ============================================================================
-- 54_checklists_v02_templates.sql
-- ----------------------------------------------------------------------------
-- Templates V02-2026 de checklists ENTREGA y RECEPCION, parametrizados por
-- tipo_equipamiento del activo, con default_cobrable_cliente por item y
-- captura de instrumento (presion, caudal, mm banda, scanner OBD, foto).
--
-- Base: V01-2026 del "Paquete Operacional Flota.xlsx" auditado contra
-- pautas oficiales fabricante (Actros Kaufmann, Mack, Volvo VAS, Renault
-- SALFA, Nissan) y 234 OS historicas. V02 extiende V01 de 53 a ~95 items
-- chequeables + ~50 entrega + tabla cobrable_cliente por item.
--
-- ADITIVA, IDEMPOTENTE. No toca checklist_templates (MIG22) ni
-- pautas_fabricante (MIG34) — los nuevos templates van en tablas paralelas.
-- ============================================================================

-- ── Precheck ───────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='activos') THEN
        RAISE EXCEPTION 'STOP - tabla activos no existe.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_user_rol') THEN
        RAISE EXCEPTION 'STOP - falta fn_user_rol().';
    END IF;
END $$;


-- ============================================================================
-- 1. ENUMS
-- ============================================================================

-- Momento en el ciclo de arriendo en que se aplica el checklist
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='momento_checklist_enum') THEN
        CREATE TYPE momento_checklist_enum AS ENUM (
            'entrega_arriendo',      -- al entregar al cliente (snapshot inicial)
            'recepcion_devolucion',  -- al recibir devuelto (base del recobro)
            'ready_to_rent',         -- verificacion disponibilidad (existente)
            'preventiva'             -- pauta preventiva (existente)
        );
    END IF;
END $$;

-- Tipo de equipamiento — define que items de B4 (sistemas) aplican
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='tipo_equipamiento_enum') THEN
        CREATE TYPE tipo_equipamiento_enum AS ENUM (
            'aljibe_agua',
            'aljibe_combustible',
            'pluma_grua',
            'ampliroll',
            'grua_horquilla',
            'camioneta',
            'tracto',
            'generico'
        );
    END IF;
END $$;

-- Bloques del checklist (7 RECEPCION + 3 ENTREGA + cierre/identificacion)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='bloque_checklist_enum') THEN
        CREATE TYPE bloque_checklist_enum AS ENUM (
            'b1_documentacion',
            'b2_estado_exterior',
            'b3_motor_niveles',
            'b4_sistema_equipo',
            'b5_seguridad_activa',
            'b6_diagnostico_electronico',
            'b7_cierre_recepcion',
            'a_trabajos_ot',
            'b_pruebas_funcionales',
            'c_estado_entrega',
            'd_cierre_entrega'
        );
    END IF;
END $$;

-- Default cobrable cliente vs empresa (regla por item, ajustable en revision)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='default_cobrable_enum') THEN
        CREATE TYPE default_cobrable_enum AS ENUM (
            'cliente',     -- atribuible cliente por defecto (parabrisas, kit, etc)
            'empresa',     -- mantenimiento empresa (filtros, correas, mecanico)
            'compartido',  -- prorrateado segun km del ciclo (pastillas, neumaticos)
            'evaluar',     -- abre flujo supervisor (no inferible)
            'na'           -- informativo, no cobrable
        );
    END IF;
END $$;

-- Instrumento/metodo de captura
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='instrumento_medicion_enum') THEN
        CREATE TYPE instrumento_medicion_enum AS ENUM (
            'check',           -- SI/NO/NA
            'visual',          -- inspeccion visual con observacion
            'numerico',        -- valor numerico (horometro, km, voltaje)
            'manometro',       -- presion kPa/psi
            'caudalimetro',    -- caudal L/min
            'profundimetro',   -- mm banda neumatico, espesor pastillas
            'termometro',      -- temperatura °C
            'multimetro',      -- voltaje/continuidad
            'scanner_obd',     -- jaltest/telligent/consult/volvo connect
            'muestra_lab',     -- muestra aceite/refrigerante a laboratorio
            'foto',            -- registro fotografico obligatorio
            'firma'            -- firma persona (operador/tecnico/cliente)
        );
    END IF;
END $$;


-- ============================================================================
-- 2. EXTENDER activos con tipo_equipamiento
-- ============================================================================
ALTER TABLE activos
    ADD COLUMN IF NOT EXISTS tipo_equipamiento tipo_equipamiento_enum NOT NULL DEFAULT 'generico';

COMMENT ON COLUMN activos.tipo_equipamiento IS
    'Define que items de B4 (sistema equipo) aplican en checklists V02. '
    'Distinto de tipo (camion/camioneta), captura el uso/carroceria.';


-- ============================================================================
-- 3. TABLAS DE TEMPLATE
-- ============================================================================

CREATE TABLE IF NOT EXISTS checklist_template_v2 (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo      VARCHAR(50)  NOT NULL,                  -- 'CL-RECEPCION-V02'
    nombre      VARCHAR(200) NOT NULL,
    momento_uso momento_checklist_enum NOT NULL,
    version     VARCHAR(20)  NOT NULL DEFAULT 'V02-2026',
    descripcion TEXT,
    activo      BOOLEAN      NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_cl_v2_codigo UNIQUE (codigo)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_cl_v2_momento_activo
    ON checklist_template_v2 (momento_uso) WHERE activo = true;


CREATE TABLE IF NOT EXISTS checklist_template_v2_item (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id     UUID         NOT NULL REFERENCES checklist_template_v2(id) ON DELETE CASCADE,
    bloque          bloque_checklist_enum NOT NULL,
    orden           INT          NOT NULL,
    codigo          VARCHAR(30)  NOT NULL,              -- 'B2.04', 'B4.AGUA.03'
    descripcion     TEXT         NOT NULL,
    ayuda           TEXT,                               -- ayuda al operador
    -- Filtros de aplicabilidad
    tipos_equipamiento tipo_equipamiento_enum[] NOT NULL DEFAULT ARRAY['generico']::tipo_equipamiento_enum[],
    modelos_aplicables UUID[],                          -- NULL = todos los modelos
    -- Captura
    instrumento     instrumento_medicion_enum NOT NULL DEFAULT 'check',
    unidad          VARCHAR(30),                        -- 'mm', 'kPa', 'L/min'
    rango_min       NUMERIC,
    rango_max       NUMERIC,
    obligatorio     BOOLEAN      NOT NULL DEFAULT false,
    requiere_foto   BOOLEAN      NOT NULL DEFAULT false,
    -- Recobro
    default_cobrable default_cobrable_enum NOT NULL DEFAULT 'evaluar',
    costo_referencial_clp NUMERIC,                      -- valor tipico repuesto+MO
    -- Trazabilidad fuente
    fuente_fabricante TEXT,                             -- 'Actros Kaufmann pag 6'
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_cl_v2_item_codigo UNIQUE (template_id, codigo)
);

CREATE INDEX IF NOT EXISTS idx_cl_v2_item_template
    ON checklist_template_v2_item (template_id, bloque, orden);
CREATE INDEX IF NOT EXISTS idx_cl_v2_item_equipo
    ON checklist_template_v2_item USING GIN (tipos_equipamiento);


-- Trigger updated_at
DROP TRIGGER IF EXISTS trg_cl_v2_updated_at ON checklist_template_v2;
CREATE TRIGGER trg_cl_v2_updated_at
    BEFORE UPDATE ON checklist_template_v2
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================================================
-- 4. RLS — solo admin/subgerente CRUD; lectura para roles operativos
-- ============================================================================
ALTER TABLE checklist_template_v2       ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_template_v2_item  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_cl_v2_select ON checklist_template_v2;
CREATE POLICY pol_cl_v2_select ON checklist_template_v2
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_cl_v2_write ON checklist_template_v2;
CREATE POLICY pol_cl_v2_write ON checklist_template_v2
    FOR ALL TO authenticated
    USING      (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'))
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'));

DROP POLICY IF EXISTS pol_cl_v2_item_select ON checklist_template_v2_item;
CREATE POLICY pol_cl_v2_item_select ON checklist_template_v2_item
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_cl_v2_item_write ON checklist_template_v2_item;
CREATE POLICY pol_cl_v2_item_write ON checklist_template_v2_item
    FOR ALL TO authenticated
    USING      (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'))
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'));


-- ============================================================================
-- 5. SEED TEMPLATE RECEPCION V02-2026
-- ============================================================================
INSERT INTO checklist_template_v2 (codigo, nombre, momento_uso, descripcion)
VALUES (
    'CL-RECEPCION-V02',
    'Check-List Recepcion V02-2026 (devolucion arriendo)',
    'recepcion_devolucion',
    'Inspeccion del activo al ser devuelto por el cliente. Base del recobro: diferencias vs checklist de entrega se cobran segun default_cobrable.'
) ON CONFLICT (codigo) DO NOTHING;


-- Helper CTE no — usar select inline en cada INSERT para evitar dependencias
-- entre rows. Usamos un DO block para reutilizar el template_id.

DO $body$
DECLARE
    v_tpl UUID;
    v_all tipo_equipamiento_enum[] := ARRAY[
        'aljibe_agua','aljibe_combustible','pluma_grua','ampliroll',
        'grua_horquilla','camioneta','tracto','generico'
    ]::tipo_equipamiento_enum[];
BEGIN
    SELECT id INTO v_tpl FROM checklist_template_v2 WHERE codigo='CL-RECEPCION-V02';

    -- ── B1 DOCUMENTACION (aplica a todos) ─────────────────────────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, obligatorio, requiere_foto, default_cobrable, fuente_fabricante)
    VALUES
        (v_tpl,'b1_documentacion', 1,'B1.01','Permiso de circulacion vigente', v_all,'check', true, true,'empresa','Cert. legal'),
        (v_tpl,'b1_documentacion', 2,'B1.02','SOAP vigente',                    v_all,'check', true, true,'empresa','Cert. legal'),
        (v_tpl,'b1_documentacion', 3,'B1.03','Revision Tecnica vigente',        v_all,'check', true, true,'empresa','Cert. legal'),
        (v_tpl,'b1_documentacion', 4,'B1.04','Certificado Hermeticidad vigente (estanque combustible)',
                                                                                ARRAY['aljibe_combustible']::tipo_equipamiento_enum[],
                                                                                'check', true, true,'empresa','Cert. SEC'),
        (v_tpl,'b1_documentacion', 5,'B1.05','Certificado TC8 vigente (estanque combustible)',
                                                                                ARRAY['aljibe_combustible']::tipo_equipamiento_enum[],
                                                                                'check', true, true,'empresa','Cert. TC8'),
        (v_tpl,'b1_documentacion', 6,'B1.06','GPS / Tacografo operativo y reportando', v_all,'check', true,false,'empresa','Ley 21.561'),
        (v_tpl,'b1_documentacion', 7,'B1.07','Certificado gancho/pertiga vigente (equipos de izaje)',
                                                                                ARRAY['pluma_grua','ampliroll','grua_horquilla']::tipo_equipamiento_enum[],
                                                                                'check', true, true,'empresa','Cert. izaje'),
        (v_tpl,'b1_documentacion', 8,'B1.08','Documentos cliente final (guia despacho, ordenes)', v_all,'check', false,false,'cliente','Operacion'),
        (v_tpl,'b1_documentacion', 9,'B1.09','Cert. mantencion aire acondicionado (NUEVO)', v_all,'check', false,false,'empresa','Estandar V10-2019'),
        (v_tpl,'b1_documentacion',10,'B1.10','Cert. operacion tacografo (NUEVO)', v_all,'check', false,false,'empresa','Estandar V10-2019');

    -- ── B2 ESTADO EXTERIOR ───────────────────────────────────────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, unidad, obligatorio, requiere_foto, default_cobrable, costo_referencial_clp, fuente_fabricante)
    VALUES
        (v_tpl,'b2_estado_exterior', 1,'B2.01','Foto frontal del vehiculo',           v_all,'foto',         NULL, true, true,'na',         NULL,'Estandar V10-2019'),
        (v_tpl,'b2_estado_exterior', 2,'B2.02','Foto lateral izquierdo',              v_all,'foto',         NULL, true, true,'na',         NULL,'Estandar V10-2019'),
        (v_tpl,'b2_estado_exterior', 3,'B2.03','Foto lateral derecho',                v_all,'foto',         NULL, true, true,'na',         NULL,'Estandar V10-2019'),
        (v_tpl,'b2_estado_exterior', 4,'B2.04','Foto trasera',                        v_all,'foto',         NULL, true, true,'na',         NULL,'Estandar V10-2019'),
        (v_tpl,'b2_estado_exterior', 5,'B2.05','Carroceria sin abolladuras / golpes', v_all,'visual',       NULL, true, true,'cliente',  150000,'V01-2026'),
        (v_tpl,'b2_estado_exterior', 6,'B2.06','Parabrisas sin trizaduras',           v_all,'visual',       NULL, true, true,'cliente',  450000,'V01-2026'),
        (v_tpl,'b2_estado_exterior', 7,'B2.07','Vidrios laterales y espejos sin danos', v_all,'visual',     NULL, true, true,'cliente',  120000,'V01-2026'),
        (v_tpl,'b2_estado_exterior', 8,'B2.08','Laminas de seguridad intactas',       v_all,'visual',       NULL, false,true,'cliente',   80000,'V01-2026'),
        (v_tpl,'b2_estado_exterior', 9,'B2.09','Logos cliente y sticker patente/CECO visibles',
                                                                                       v_all,'visual',       NULL, false,true,'cliente',   30000,'V01-2026'),
        (v_tpl,'b2_estado_exterior',10,'B2.10','Neumatico pos 1 — banda en mm (umbral mineria 5mm)',
                                                                                       v_all,'profundimetro','mm', true, true,'compartido',180000,'NUEVO'),
        (v_tpl,'b2_estado_exterior',11,'B2.11','Neumatico pos 2 — banda en mm', v_all,'profundimetro','mm', true, true,'compartido',180000,'NUEVO'),
        (v_tpl,'b2_estado_exterior',12,'B2.12','Neumatico pos 3 — banda en mm', v_all,'profundimetro','mm', true, true,'compartido',180000,'NUEVO'),
        (v_tpl,'b2_estado_exterior',13,'B2.13','Neumatico pos 4 — banda en mm', v_all,'profundimetro','mm', true, true,'compartido',180000,'NUEVO'),
        (v_tpl,'b2_estado_exterior',14,'B2.14','Neumatico pos 5 — banda en mm (6x4/8x4)',
                                                                                       ARRAY['aljibe_agua','aljibe_combustible','pluma_grua','ampliroll','tracto']::tipo_equipamiento_enum[],
                                                                                       'profundimetro','mm', true, true,'compartido',180000,'NUEVO'),
        (v_tpl,'b2_estado_exterior',15,'B2.15','Neumatico pos 6 — banda en mm (6x4/8x4)',
                                                                                       ARRAY['aljibe_agua','aljibe_combustible','pluma_grua','ampliroll','tracto']::tipo_equipamiento_enum[],
                                                                                       'profundimetro','mm', true, true,'compartido',180000,'NUEVO'),
        (v_tpl,'b2_estado_exterior',16,'B2.16','Neumatico repuesto presente y en condicion', v_all,'visual',NULL,true,true,'cliente',180000,'V01-2026'),
        (v_tpl,'b2_estado_exterior',17,'B2.17','Reapriete cintas estanque + pernos sujecion (NUEVO - Actros 00-5036)',
                                                                                       ARRAY['aljibe_agua','aljibe_combustible']::tipo_equipamiento_enum[],
                                                                                       'check',NULL,true,true,'empresa',45000,'Actros Kaufmann 00-5036'),
        (v_tpl,'b2_estado_exterior',18,'B2.18','Sin filtraciones visibles bajo el vehiculo', v_all,'visual',NULL,true,true,'evaluar',NULL,'V01-2026');

    -- ── B3 MOTOR Y NIVELES ────────────────────────────────────────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, unidad, obligatorio, requiere_foto, default_cobrable, costo_referencial_clp, fuente_fabricante)
    VALUES
        (v_tpl,'b3_motor_niveles', 1,'B3.01','Nivel aceite motor (entre min-max)',          v_all,'visual',NULL,true,false,'empresa', 25000,'V01-2026'),
        (v_tpl,'b3_motor_niveles', 2,'B3.02','Nivel refrigerante',                          v_all,'visual',NULL,true,false,'empresa', 15000,'V01-2026'),
        (v_tpl,'b3_motor_niveles', 3,'B3.03','Nivel liquido frenos',                        v_all,'visual',NULL,true,false,'empresa', 12000,'V01-2026'),
        (v_tpl,'b3_motor_niveles', 4,'B3.04','Nivel direccion hidraulica',                  v_all,'visual',NULL,true,false,'empresa', 18000,'V01-2026'),
        (v_tpl,'b3_motor_niveles', 5,'B3.05','Nivel AdBlue (Euro V/VI)',                    v_all,'visual',NULL,true,false,'cliente', 35000,'Euro V/VI - cliente consume'),
        (v_tpl,'b3_motor_niveles', 6,'B3.06','Correas: sin grietas, tension OK',            v_all,'visual',NULL,true,false,'empresa', 80000,'V01-2026'),
        (v_tpl,'b3_motor_niveles', 7,'B3.07','Mangueras radiador/intercooler sin fugas',    v_all,'visual',NULL,true,false,'empresa', 65000,'V01-2026'),
        (v_tpl,'b3_motor_niveles', 8,'B3.08','Filtro aire — saturacion visual',             v_all,'visual',NULL,true,false,'empresa', 45000,'V01-2026'),
        (v_tpl,'b3_motor_niveles', 9,'B3.09','Voltaje bateria en reposo (>12.4V)',          v_all,'multimetro','V',true,false,'compartido',95000,'V01-2026'),
        (v_tpl,'b3_motor_niveles',10,'B3.10','Voltaje bateria con cranking (>10V) (NUEVO)', v_all,'multimetro','V',true,false,'compartido',95000,'NUEVO'),
        (v_tpl,'b3_motor_niveles',11,'B3.11','Ruido motor — sin golpes anomalos',           v_all,'visual',NULL,true,false,'evaluar',NULL,'V01-2026'),
        (v_tpl,'b3_motor_niveles',12,'B3.12','Color humo escape (blanco/negro/azul indica falla)', v_all,'visual',NULL,true,true,'evaluar',NULL,'V01-2026'),
        (v_tpl,'b3_motor_niveles',13,'B3.13','Filtro racor combustible — sin agua (NUEVO)', v_all,'visual',NULL,true,false,'empresa', 18000,'NUEVO Actros/Volvo'),
        (v_tpl,'b3_motor_niveles',14,'B3.14','Cartucho granulado secador aire — purga (NUEVO causa EBS)',
                                                                                              v_all,'visual',NULL,true,false,'empresa', 35000,'NUEVO Actros 00-5036'),
        (v_tpl,'b3_motor_niveles',15,'B3.15','Filtro polvo calefaccion cabina (NUEVO)',     v_all,'visual',NULL,false,false,'empresa', 22000,'NUEVO Mercedes/Volvo'),
        (v_tpl,'b3_motor_niveles',16,'B3.16','Espesor pastillas freno delantero (mm — umbral 4mm)',
                                                                                              v_all,'profundimetro','mm',true,true,'compartido',180000,'NUEVO Actros 33-2013'),
        (v_tpl,'b3_motor_niveles',17,'B3.17','Espesor pastillas freno trasero (mm — umbral 4mm)',
                                                                                              v_all,'profundimetro','mm',true,true,'compartido',180000,'NUEVO Actros 33-2013'),
        (v_tpl,'b3_motor_niveles',18,'B3.18','Estado mangueras AdBlue + sistema SCR (NUEVO Volvo VAS)',
                                                                                              v_all,'visual',NULL,true,false,'empresa', 250000,'NUEVO Volvo VAS / Mercedes Euro V');

    -- ── B4 SISTEMA EQUIPO — ALJIBE AGUA (NUEVOS sub-items por gap historico 79 OS Bomba/PTO) ─
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, unidad, obligatorio, requiere_foto, default_cobrable, costo_referencial_clp, fuente_fabricante)
    VALUES
        (v_tpl,'b4_sistema_equipo', 1,'B4.AGUA.01','Bomba aljibe — caudal medido L/min',
                                                                                ARRAY['aljibe_agua']::tipo_equipamiento_enum[],'caudalimetro','L/min',true,false,'empresa',450000,'Hist 79 OS Bomba'),
        (v_tpl,'b4_sistema_equipo', 2,'B4.AGUA.02','Bomba aljibe — presion kPa',
                                                                                ARRAY['aljibe_agua']::tipo_equipamiento_enum[],'manometro','kPa',true,false,'empresa',450000,'Hist 79 OS Bomba'),
        (v_tpl,'b4_sistema_equipo', 3,'B4.AGUA.03','Bomba aljibe — temperatura cojinete °C (<80°C)',
                                                                                ARRAY['aljibe_agua']::tipo_equipamiento_enum[],'termometro','°C',true,false,'empresa',450000,'NUEVO causa falla'),
        (v_tpl,'b4_sistema_equipo', 4,'B4.AGUA.04','Swivel — sin fugas + empaquetadura OK',
                                                                                ARRAY['aljibe_agua']::tipo_equipamiento_enum[],'visual',NULL,true,true,'empresa',120000,'Hist falla recurrente'),
        (v_tpl,'b4_sistema_equipo', 5,'B4.AGUA.05','Pistola y manguera principal sin danos',
                                                                                ARRAY['aljibe_agua']::tipo_equipamiento_enum[],'visual',NULL,true,true,'cliente',85000,'V01 + Estandar V10'),
        (v_tpl,'b4_sistema_equipo', 6,'B4.AGUA.06','Sobrellenado optico operativo',
                                                                                ARRAY['aljibe_agua']::tipo_equipamiento_enum[],'check',NULL,true,false,'empresa',180000,'V01-2026'),
        (v_tpl,'b4_sistema_equipo', 7,'B4.AGUA.07','Aspersores delantero/lateral/trasero — flujo OK',
                                                                                ARRAY['aljibe_agua']::tipo_equipamiento_enum[],'check',NULL,true,false,'empresa',95000,'V01-2026'),
        (v_tpl,'b4_sistema_equipo', 8,'B4.AGUA.08','Linea hidraulica sin fugas + presion OK',
                                                                                ARRAY['aljibe_agua']::tipo_equipamiento_enum[],'visual',NULL,true,false,'empresa',150000,'V01-2026'),
        (v_tpl,'b4_sistema_equipo', 9,'B4.AGUA.09','Escotillas tope estanque — bisagra y cierre',
                                                                                ARRAY['aljibe_agua']::tipo_equipamiento_enum[],'visual',NULL,true,false,'cliente',75000,'NUEVO Estandar V10'),
        (v_tpl,'b4_sistema_equipo',10,'B4.AGUA.10','Lineas de vida superior — sin fisuras',
                                                                                ARRAY['aljibe_agua']::tipo_equipamiento_enum[],'visual',NULL,true,true,'empresa',280000,'NUEVO Estandar V10'),
        (v_tpl,'b4_sistema_equipo',11,'B4.AGUA.11','Escaleras y barandas — soldaduras intactas',
                                                                                ARRAY['aljibe_agua']::tipo_equipamiento_enum[],'visual',NULL,true,true,'empresa',180000,'NUEVO Estandar V10'),
        (v_tpl,'b4_sistema_equipo',12,'B4.AGUA.12','Logo capacidad estanque + altura camion visible',
                                                                                ARRAY['aljibe_agua']::tipo_equipamiento_enum[],'visual',NULL,true,true,'cliente',45000,'NUEVO NFPA');

    -- ── B4 SISTEMA EQUIPO — ALJIBE COMBUSTIBLE (Hist falta granularidad) ─
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, unidad, obligatorio, requiere_foto, default_cobrable, costo_referencial_clp, fuente_fabricante)
    VALUES
        (v_tpl,'b4_sistema_equipo',20,'B4.COMB.01','Bomba Wiggins/LC — caudal L/min medido',
                                                                                ARRAY['aljibe_combustible']::tipo_equipamiento_enum[],'caudalimetro','L/min',true,false,'empresa',650000,'NUEVO CL TC8'),
        (v_tpl,'b4_sistema_equipo',21,'B4.COMB.02','Bomba Wiggins/LC — presion surtidor kPa',
                                                                                ARRAY['aljibe_combustible']::tipo_equipamiento_enum[],'manometro','kPa',true,false,'empresa',650000,'NUEVO CL TC8'),
        (v_tpl,'b4_sistema_equipo',22,'B4.COMB.03','Meter (LC/Wiggins) — contador y ultimo registro',
                                                                                ARRAY['aljibe_combustible']::tipo_equipamiento_enum[],'numerico','L',true,true,'empresa',NULL,'NUEVO CL TC8'),
        (v_tpl,'b4_sistema_equipo',23,'B4.COMB.04','TC8 — calibracion vigente + sellos intactos',
                                                                                ARRAY['aljibe_combustible']::tipo_equipamiento_enum[],'check',NULL,true,true,'empresa',350000,'CL TC8'),
        (v_tpl,'b4_sistema_equipo',24,'B4.COMB.05','Valvula API + antichispa operativos',
                                                                                ARRAY['aljibe_combustible']::tipo_equipamiento_enum[],'check',NULL,true,true,'empresa',180000,'CL TC8 + SEC'),
        (v_tpl,'b4_sistema_equipo',25,'B4.COMB.06','Valvula de fondo opera (apertura/cierre)',
                                                                                ARRAY['aljibe_combustible']::tipo_equipamiento_enum[],'check',NULL,true,false,'empresa',220000,'CL TC8'),
        (v_tpl,'b4_sistema_equipo',26,'B4.COMB.07','Paradas de emergencia funcionan',
                                                                                ARRAY['aljibe_combustible']::tipo_equipamiento_enum[],'check',NULL,true,false,'empresa',95000,'CL TC8 + Estandar V10'),
        (v_tpl,'b4_sistema_equipo',27,'B4.COMB.08','Corta corriente principal opera',
                                                                                ARRAY['aljibe_combustible']::tipo_equipamiento_enum[],'check',NULL,true,false,'empresa',75000,'CL TC8'),
        (v_tpl,'b4_sistema_equipo',28,'B4.COMB.09','Fugas en swivel/pistola/uniones — sin gotera',
                                                                                ARRAY['aljibe_combustible']::tipo_equipamiento_enum[],'visual',NULL,true,true,'empresa',180000,'CL TC8 + ambiental'),
        (v_tpl,'b4_sistema_equipo',29,'B4.COMB.10','Pistola completa con boquilla automatica',
                                                                                ARRAY['aljibe_combustible']::tipo_equipamiento_enum[],'visual',NULL,true,true,'cliente',120000,'V01-2026'),
        (v_tpl,'b4_sistema_equipo',30,'B4.COMB.11','Rombos NFPA + numero ONU visibles + reflectantes',
                                                                                ARRAY['aljibe_combustible']::tipo_equipamiento_enum[],'visual',NULL,true,true,'cliente',65000,'NUEVO NFPA'),
        (v_tpl,'b4_sistema_equipo',31,'B4.COMB.12','Cinta reflectante perimetral conforme',
                                                                                ARRAY['aljibe_combustible']::tipo_equipamiento_enum[],'visual',NULL,true,true,'cliente',45000,'NUEVO NFPA');

    -- ── B4 SISTEMA EQUIPO — PLUMA / GRUA (IMT 20-138) ─────────────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, unidad, obligatorio, requiere_foto, default_cobrable, costo_referencial_clp, fuente_fabricante)
    VALUES
        (v_tpl,'b4_sistema_equipo',40,'B4.PLUMA.01','Cables de pluma — sin hilos rotos / corrosion',
                                                                                ARRAY['pluma_grua']::tipo_equipamiento_enum[],'visual',NULL,true,true,'compartido',450000,'V01 + Cert. izaje'),
        (v_tpl,'b4_sistema_equipo',41,'B4.PLUMA.02','Estabilizadores extienden + bloquean correctamente',
                                                                                ARRAY['pluma_grua']::tipo_equipamiento_enum[],'check',NULL,true,false,'empresa',650000,'V01'),
        (v_tpl,'b4_sistema_equipo',42,'B4.PLUMA.03','RCL5300 (sensor carga/momento) calibrado',
                                                                                ARRAY['pluma_grua']::tipo_equipamiento_enum[],'check',NULL,true,true,'empresa',280000,'V01 + seguridad'),
        (v_tpl,'b4_sistema_equipo',43,'B4.PLUMA.04','Gancho con seguro + cert. vigente',
                                                                                ARRAY['pluma_grua','ampliroll']::tipo_equipamiento_enum[],'check',NULL,true,true,'empresa',95000,'Cert. izaje'),
        (v_tpl,'b4_sistema_equipo',44,'B4.PLUMA.05','Pertiga retractil — altura, luminosidad, replegado',
                                                                                ARRAY['pluma_grua','ampliroll','grua_horquilla']::tipo_equipamiento_enum[],'check',NULL,true,true,'cliente',75000,'V01'),
        (v_tpl,'b4_sistema_equipo',45,'B4.PLUMA.06','Mando control radio/cable — botones funcionan',
                                                                                ARRAY['pluma_grua']::tipo_equipamiento_enum[],'check',NULL,true,false,'empresa',180000,'V01');

    -- ── B4 SISTEMA EQUIPO — AMPLIROLL ─────────────────────────────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, obligatorio, requiere_foto, default_cobrable, costo_referencial_clp, fuente_fabricante)
    VALUES
        (v_tpl,'b4_sistema_equipo',50,'B4.AMPL.01','Sistema de carga ampliroll — brazos sin desgaste',
                                                                                ARRAY['ampliroll']::tipo_equipamiento_enum[],'visual',true,true,'empresa',350000,'V01'),
        (v_tpl,'b4_sistema_equipo',51,'B4.AMPL.02','Linea hidraulica ampliroll — presion + sin fugas',
                                                                                ARRAY['ampliroll']::tipo_equipamiento_enum[],'manometro',true,false,'empresa',180000,'V01'),
        (v_tpl,'b4_sistema_equipo',52,'B4.AMPL.03','Ganchos de bloqueo containero — seguros operan',
                                                                                ARRAY['ampliroll']::tipo_equipamiento_enum[],'check',true,true,'empresa',95000,'V01');

    -- ── B4 SISTEMA EQUIPO — GRUA HORQUILLA ────────────────────────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, obligatorio, requiere_foto, default_cobrable, costo_referencial_clp, fuente_fabricante)
    VALUES
        (v_tpl,'b4_sistema_equipo',60,'B4.GRUA.01','Cadenas de izaje — eslabones sin fisura',
                                                                                ARRAY['grua_horquilla']::tipo_equipamiento_enum[],'visual',true,true,'compartido',280000,'V01 + Cert.'),
        (v_tpl,'b4_sistema_equipo',61,'B4.GRUA.02','Horquillas sin deformacion + tope OK',
                                                                                ARRAY['grua_horquilla']::tipo_equipamiento_enum[],'visual',true,true,'empresa',180000,'V01'),
        (v_tpl,'b4_sistema_equipo',62,'B4.GRUA.03','Mastil — rodillos y deslizamiento sin atascos',
                                                                                ARRAY['grua_horquilla']::tipo_equipamiento_enum[],'check',true,false,'empresa',220000,'V01'),
        (v_tpl,'b4_sistema_equipo',63,'B4.GRUA.04','Frenos de servicio y estacionamiento operan',
                                                                                ARRAY['grua_horquilla']::tipo_equipamiento_enum[],'check',true,false,'empresa',180000,'V01');

    -- ── B4 SISTEMA EQUIPO — TRACTO (quinta rueda) ─────────────────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, obligatorio, requiere_foto, default_cobrable, costo_referencial_clp, fuente_fabricante)
    VALUES
        (v_tpl,'b4_sistema_equipo',70,'B4.TRAC.01','Quinta rueda — engrase + mecanismo cierre (Actros 00-5036)',
                                                                                ARRAY['tracto']::tipo_equipamiento_enum[],'check',true,true,'empresa',150000,'NUEVO Actros');

    -- ── B5 SEGURIDAD ACTIVA (Mobileye + Inventario Cabina granular) ──────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, obligatorio, requiere_foto, default_cobrable, costo_referencial_clp, fuente_fabricante)
    VALUES
        (v_tpl,'b5_seguridad_activa', 1,'B5.01','Driveri / Smart Eye — sensor somnolencia operativo', v_all,'check',true,true,'empresa',850000,'V01 + cliente mineria'),
        (v_tpl,'b5_seguridad_activa', 2,'B5.02','Mobileye — sistema vision frontal operativo',         v_all,'check',true,true,'empresa',650000,'V01 + cliente mineria'),
        (v_tpl,'b5_seguridad_activa', 3,'B5.03','Camara retroceso — imagen nitida',                     v_all,'check',true,true,'empresa',180000,'V01'),
        (v_tpl,'b5_seguridad_activa', 4,'B5.04','Camara punto ciego lateral',                           v_all,'check',true,true,'empresa',180000,'V01'),
        (v_tpl,'b5_seguridad_activa', 5,'B5.05','EBS / ABS — sin testigo de falla',                     v_all,'check',true,false,'empresa',450000,'V01'),
        (v_tpl,'b5_seguridad_activa', 6,'B5.06','Balizas — todas operativas (ambar/rojo) + altura',     v_all,'check',true,true,'cliente',75000,'V01 + minera'),
        (v_tpl,'b5_seguridad_activa', 7,'B5.07','Inventario cabina — extintor presente + vigente',      v_all,'check',true,true,'cliente',45000,'V01'),
        (v_tpl,'b5_seguridad_activa', 8,'B5.08','Inventario cabina — calzos de seguridad',              v_all,'check',true,true,'cliente',25000,'V01'),
        (v_tpl,'b5_seguridad_activa', 9,'B5.09','Inventario cabina — triangulos + chaleco reflectante', v_all,'check',true,true,'cliente',18000,'V01'),
        (v_tpl,'b5_seguridad_activa',10,'B5.10','Inventario cabina — botiquin primeros auxilios',       v_all,'check',true,true,'cliente',35000,'V01'),
        (v_tpl,'b5_seguridad_activa',11,'B5.11','Cinturones seguridad — operativos, sin cortes',        v_all,'check',true,false,'cliente',95000,'V01'),
        (v_tpl,'b5_seguridad_activa',12,'B5.12','Kit invierno — sal, alcohol, plumillas, frazadas, linterna (NUEVO Estandar V10)',
                                                                                                          v_all,'check',true,true,'cliente',85000,'NUEVO Estandar V10-2019'),
        (v_tpl,'b5_seguridad_activa',13,'B5.13','Kit invierno — chuzo, pala, cadenas, tensores',        v_all,'check',true,true,'cliente',120000,'NUEVO Estandar V10-2019'),
        (v_tpl,'b5_seguridad_activa',14,'B5.14','Kit invierno — estrobo + grilletes certificados',      v_all,'check',true,true,'cliente',95000,'NUEVO Estandar V10-2019');

    -- ── B6 DIAGNOSTICO ELECTRONICO (mejorado: codigos OBD literal + muestra aceite) ──
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, obligatorio, requiere_foto, default_cobrable, costo_referencial_clp, fuente_fabricante)
    VALUES
        (v_tpl,'b6_diagnostico_electronico', 1,'B6.01','Lectura OBD / Jaltest — sin codigos activos', v_all,'scanner_obd',true,true,'evaluar',NULL,'V01'),
        (v_tpl,'b6_diagnostico_electronico', 2,'B6.02','Codigos OBD literales capturados (texto completo) (NUEVO)',
                                                                                                          v_all,'scanner_obd',true,true,'evaluar',NULL,'NUEVO trazabilidad'),
        (v_tpl,'b6_diagnostico_electronico', 3,'B6.03','Volvo Connect — lectura predictiva proxima mantencion',
                                                                                                          v_all,'scanner_obd',false,false,'empresa',NULL,'V01 Volvo VAS'),
        (v_tpl,'b6_diagnostico_electronico', 4,'B6.04','Mercedes Star Diagnosis / Telligent — Actros',     v_all,'scanner_obd',false,false,'empresa',NULL,'V01 Actros Kaufmann'),
        (v_tpl,'b6_diagnostico_electronico', 5,'B6.05','CONSULT III — Nissan NP300 (NUEVO especifico)',    v_all,'scanner_obd',false,false,'empresa',NULL,'NUEVO Nissan'),
        (v_tpl,'b6_diagnostico_electronico', 6,'B6.06','% Regeneracion DPF + ultima fecha + n° regeneraciones fallidas',
                                                                                                          v_all,'numerico',true,true,'evaluar',NULL,'NUEVO Euro VI'),
        (v_tpl,'b6_diagnostico_electronico', 7,'B6.07','Proxima pauta segun sistema fabricante (horometro objetivo)',
                                                                                                          v_all,'numerico',true,false,'na',NULL,'V01'),
        (v_tpl,'b6_diagnostico_electronico', 8,'B6.08','Muestra aceite motor enviada a laboratorio (Volvo VAS obligatorio)',
                                                                                                          v_all,'muestra_lab',true,true,'empresa',45000,'NUEVO Volvo VAS / Renault SALFA');

    -- ── B7 CIERRE RECEPCION (con re-trabajo + causa raiz) ─────────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, obligatorio, requiere_foto, default_cobrable, fuente_fabricante)
    VALUES
        (v_tpl,'b7_cierre_recepcion', 1,'B7.01','Foto horometro al recibir',                       v_all,'foto',true,true,'na','NUEVO trazabilidad'),
        (v_tpl,'b7_cierre_recepcion', 2,'B7.02','Foto odometro al recibir',                        v_all,'foto',true,true,'na','NUEVO trazabilidad'),
        (v_tpl,'b7_cierre_recepcion', 3,'B7.03','Danos no reportados detectados (descripcion)',    v_all,'visual',true,true,'cliente','V01'),
        (v_tpl,'b7_cierre_recepcion', 4,'B7.04','Observaciones del operador receptor',             v_all,'visual',false,false,'na','V01'),
        (v_tpl,'b7_cierre_recepcion', 5,'B7.05','Trabajos solicitados (texto libre)',              v_all,'visual',false,false,'evaluar','V01'),
        (v_tpl,'b7_cierre_recepcion', 6,'B7.06','Es re-trabajo de OT-XXXX? (Si=numero OT predecesora) (NUEVO)',
                                                                                                    v_all,'visual',true,false,'empresa','NUEVO 28% concentracion'),
        (v_tpl,'b7_cierre_recepcion', 7,'B7.07','Causa raiz hipotetica (si re-trabajo) (NUEVO)',   v_all,'visual',false,false,'na','NUEVO causa raiz'),
        (v_tpl,'b7_cierre_recepcion', 8,'B7.08','Proximo horometro pauta + tipo OT siguiente',     v_all,'numerico',true,false,'na','V01'),
        (v_tpl,'b7_cierre_recepcion', 9,'B7.09','HH estimadas trabajos detectados',                v_all,'numerico',false,false,'na','V01'),
        (v_tpl,'b7_cierre_recepcion',10,'B7.10','Fecha entrega proyectada',                        v_all,'numerico',true,false,'na','V01'),
        (v_tpl,'b7_cierre_recepcion',11,'B7.11','Firma operador receptor (Pillado) — RUT',         v_all,'firma',true,false,'na','V01'),
        (v_tpl,'b7_cierre_recepcion',12,'B7.12','Firma representante cliente — RUT',               v_all,'firma',true,false,'na','V01 — proteccion recobro');

END $body$;


-- ============================================================================
-- 6. SEED TEMPLATE ENTREGA V02-2026 (al entregar al cliente)
-- ============================================================================
INSERT INTO checklist_template_v2 (codigo, nombre, momento_uso, descripcion)
VALUES (
    'CL-ENTREGA-V02',
    'Check-List Entrega V02-2026 (inicio arriendo)',
    'entrega_arriendo',
    'Snapshot tecnico al entregar el activo al cliente. Requiere firma cliente para que el recobro sea defendible. Es el lado A de la comparacion con recepcion.'
) ON CONFLICT (codigo) DO NOTHING;


DO $body$
DECLARE
    v_tpl UUID;
    v_all tipo_equipamiento_enum[] := ARRAY[
        'aljibe_agua','aljibe_combustible','pluma_grua','ampliroll',
        'grua_horquilla','camioneta','tracto','generico'
    ]::tipo_equipamiento_enum[];
BEGIN
    SELECT id INTO v_tpl FROM checklist_template_v2 WHERE codigo='CL-ENTREGA-V02';

    -- ── B PRUEBAS FUNCIONALES (comunes) ──────────────────────────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, obligatorio, requiere_foto, default_cobrable, fuente_fabricante)
    VALUES
        (v_tpl,'b_pruebas_funcionales', 1,'EB.01','Arranque en frio — sin demora ni humo anomalo', v_all,'check',true,false,'empresa','V01'),
        (v_tpl,'b_pruebas_funcionales', 2,'EB.02','Marcha + cambios — caja opera sin saltos',      v_all,'check',true,false,'empresa','V01'),
        (v_tpl,'b_pruebas_funcionales', 3,'EB.03','Retardador opera (Voith/integrado)',            v_all,'check',true,false,'empresa','V01 + Actros'),
        (v_tpl,'b_pruebas_funcionales', 4,'EB.04','Freno motor opera',                              v_all,'check',true,false,'empresa','V01'),
        (v_tpl,'b_pruebas_funcionales', 5,'EB.05','Frenos de servicio — frena recto sin tirones',  v_all,'check',true,false,'empresa','V01'),
        (v_tpl,'b_pruebas_funcionales', 6,'EB.06','Freno estacionamiento sostiene en pendiente',   v_all,'check',true,false,'empresa','V01'),
        (v_tpl,'b_pruebas_funcionales', 7,'EB.07','Direccion sin holgura ni vibracion',            v_all,'check',true,false,'empresa','V01'),
        (v_tpl,'b_pruebas_funcionales', 8,'EB.08','Suspension — sin ruidos al pasar lomo de toro', v_all,'check',true,false,'empresa','V01'),
        (v_tpl,'b_pruebas_funcionales', 9,'EB.09','Aire acondicionado opera (frio + ventilacion)', v_all,'check',true,false,'empresa','V01'),
        (v_tpl,'b_pruebas_funcionales',10,'EB.10','Luces — altas, bajas, niebla, freno, reversa',  v_all,'check',true,false,'empresa','V01'),
        (v_tpl,'b_pruebas_funcionales',11,'EB.11','Bocina + intermitentes',                         v_all,'check',true,false,'empresa','V01'),
        (v_tpl,'b_pruebas_funcionales',12,'EB.12','GPS transmitiendo en plataforma Navixy',         v_all,'check',true,false,'empresa','V01 + Navixy'),
        (v_tpl,'b_pruebas_funcionales',13,'EB.13','Tacografo registra correctamente',               v_all,'check',true,false,'empresa','V01 + Ley 21.561'),
        (v_tpl,'b_pruebas_funcionales',14,'EB.14','Sin codigos de falla post-arranque (OBD limpio)',v_all,'scanner_obd',true,true,'empresa','V01 + B6');

    -- ── B PRUEBAS FUNCIONALES (especificas por tipo equipamiento) ─────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, unidad, obligatorio, requiere_foto, default_cobrable, fuente_fabricante)
    VALUES
        (v_tpl,'b_pruebas_funcionales',20,'EB.AGUA.01','Bomba aljibe agua — caudal medido L/min OK',
                                                                                ARRAY['aljibe_agua']::tipo_equipamiento_enum[],'caudalimetro','L/min',true,false,'empresa','V01'),
        (v_tpl,'b_pruebas_funcionales',21,'EB.AGUA.02','Sobrellenado optico corta a tope',
                                                                                ARRAY['aljibe_agua']::tipo_equipamiento_enum[],'check',NULL,true,false,'empresa','V01'),
        (v_tpl,'b_pruebas_funcionales',22,'EB.COMB.01','Bomba Wiggins/LC opera + sin filtraciones',
                                                                                ARRAY['aljibe_combustible']::tipo_equipamiento_enum[],'check',NULL,true,true,'empresa','V01'),
        (v_tpl,'b_pruebas_funcionales',23,'EB.COMB.02','TC8 verificada — calibracion OK',
                                                                                ARRAY['aljibe_combustible']::tipo_equipamiento_enum[],'check',NULL,true,true,'empresa','V01 + TC8'),
        (v_tpl,'b_pruebas_funcionales',24,'EB.PLUMA.01','Pluma — operacion completa + RCL5300 alarmas',
                                                                                ARRAY['pluma_grua']::tipo_equipamiento_enum[],'check',NULL,true,true,'empresa','V01');

    -- ── C ESTADO ENTREGA ─────────────────────────────────────────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, unidad, obligatorio, requiere_foto, default_cobrable, fuente_fabricante)
    VALUES
        (v_tpl,'c_estado_entrega', 1,'EC.01','Aseo interior cabina',                 v_all,'check',  NULL,true,true,'na','V01'),
        (v_tpl,'c_estado_entrega', 2,'EC.02','Aseo exterior + carroceria',           v_all,'check',  NULL,true,true,'na','V01'),
        (v_tpl,'c_estado_entrega', 3,'EC.03','Combustible >= 25%',                   v_all,'numerico','%',true,true,'cliente','V01'),
        (v_tpl,'c_estado_entrega', 4,'EC.04','AdBlue >= 50%',                        v_all,'numerico','%',true,true,'cliente','V01'),
        (v_tpl,'c_estado_entrega', 5,'EC.05','Nivel aceite motor OK',                v_all,'visual', NULL,true,false,'empresa','V01'),
        (v_tpl,'c_estado_entrega', 6,'EC.06','Documentos en cabina (5 docs)',         v_all,'check',  NULL,true,true,'empresa','V01'),
        (v_tpl,'c_estado_entrega', 7,'EC.07','Sticker proxima pauta visible (cabina)', v_all,'check', NULL,true,true,'empresa','V01 + Memo'),
        (v_tpl,'c_estado_entrega', 8,'EC.08','Llaves entregadas N° + duplicado',     v_all,'check',  NULL,true,false,'cliente','V01'),
        (v_tpl,'c_estado_entrega', 9,'EC.09','Sin cargos pendientes en bodega',      v_all,'check',  NULL,true,false,'empresa','V01'),
        (v_tpl,'c_estado_entrega',10,'EC.10','Foto frontal al entregar',             v_all,'foto',   NULL,true,true,'na','NUEVO'),
        (v_tpl,'c_estado_entrega',11,'EC.11','Foto trasera al entregar',             v_all,'foto',   NULL,true,true,'na','NUEVO'),
        (v_tpl,'c_estado_entrega',12,'EC.12','Foto horometro al entregar',           v_all,'foto',   NULL,true,true,'na','NUEVO');

    -- ── D CIERRE ENTREGA ─────────────────────────────────────────────────
    INSERT INTO checklist_template_v2_item
        (template_id, bloque, orden, codigo, descripcion, tipos_equipamiento,
         instrumento, obligatorio, requiere_foto, default_cobrable, fuente_fabricante)
    VALUES
        (v_tpl,'d_cierre_entrega', 1,'ED.01','Trabajos no realizados (lista)',                v_all,'visual',  false,false,'na','V01'),
        (v_tpl,'d_cierre_entrega', 2,'ED.02','Repuestos pendientes / garantia',               v_all,'visual',  false,false,'empresa','V01'),
        (v_tpl,'d_cierre_entrega', 3,'ED.03','Proxima OT programada (horometro objetivo)',    v_all,'numerico',true,false,'na','V01'),
        (v_tpl,'d_cierre_entrega', 4,'ED.04','Recomendaciones operador (manejo/ruta)',         v_all,'visual',  false,false,'na','V01'),
        (v_tpl,'d_cierre_entrega', 5,'ED.05','% Cumplimiento OT',                              v_all,'numerico',true,false,'na','V01'),
        (v_tpl,'d_cierre_entrega', 6,'ED.06','HH totales ejecutadas',                          v_all,'numerico',true,false,'na','V01'),
        (v_tpl,'d_cierre_entrega', 7,'ED.07','Dias calendario taller',                         v_all,'numerico',true,false,'na','V01'),
        (v_tpl,'d_cierre_entrega', 8,'ED.08','Firma tecnico Pillado entrega — RUT',            v_all,'firma',   true,false,'na','V01'),
        (v_tpl,'d_cierre_entrega', 9,'ED.09','Firma representante cliente acepta entrega — RUT (OBLIGATORIA para recobro)',
                                                                                                v_all,'firma',   true,false,'na','V01 + proteccion legal');

END $body$;


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'enum_momento',          (SELECT EXISTS(SELECT 1 FROM pg_type WHERE typname='momento_checklist_enum')),
    'enum_tipo_equipamiento',(SELECT EXISTS(SELECT 1 FROM pg_type WHERE typname='tipo_equipamiento_enum')),
    'enum_bloque',           (SELECT EXISTS(SELECT 1 FROM pg_type WHERE typname='bloque_checklist_enum')),
    'enum_cobrable',         (SELECT EXISTS(SELECT 1 FROM pg_type WHERE typname='default_cobrable_enum')),
    'enum_instrumento',      (SELECT EXISTS(SELECT 1 FROM pg_type WHERE typname='instrumento_medicion_enum')),
    'col_tipo_equipamiento', (SELECT EXISTS(SELECT 1 FROM information_schema.columns
                                            WHERE table_name='activos' AND column_name='tipo_equipamiento')),
    'tabla_template_v2',     (SELECT to_regclass('public.checklist_template_v2') IS NOT NULL),
    'tabla_template_v2_item',(SELECT to_regclass('public.checklist_template_v2_item') IS NOT NULL),
    'tpl_recepcion_seed',    (SELECT COUNT(*) FROM checklist_template_v2_item i
                              JOIN checklist_template_v2 t ON t.id=i.template_id
                              WHERE t.codigo='CL-RECEPCION-V02'),
    'tpl_entrega_seed',      (SELECT COUNT(*) FROM checklist_template_v2_item i
                              JOIN checklist_template_v2 t ON t.id=i.template_id
                              WHERE t.codigo='CL-ENTREGA-V02')
) AS resultado;

NOTIFY pgrst, 'reload schema';
