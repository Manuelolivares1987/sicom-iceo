-- ============================================================================
-- MIG441 · Planificar una patente con los papeles malos avisa a la jefatura
-- ============================================================================
--
-- El planificador arma la semana mirando disponibilidad y carga de taller. Los
-- papeles del equipo —revisión técnica, permiso de circulación, SOAP, seguro,
-- hermeticidad— viven en Control documental, que es otra pantalla y otra
-- persona. Así, un equipo con el permiso vencido hace 45 días entra al plan sin
-- que nadie se entere hasta que alguien lo mira.
--
-- Esto NO bloquea. El criterio es de la jefatura, no de un CHECK: un equipo con
-- la RT vencida puede entrar perfectamente a taller —de hecho es donde
-- conviene que esté— y el trabajo que se le programa puede ser justamente el
-- que arregla el papel. Lo que faltaba era que se supiera.
--
-- Va como TRIGGER sobre la tabla del plan y no dentro del RPC a propósito: al
-- plan se entra por cinco caminos distintos (patente arrastrada, preventiva
-- sugerida, NC con OT, arrastre de la semana anterior, recepción) y todos
-- terminan insertando acá. Es la misma lección de MIG437 con el kardex — el
-- candado va en la tabla, no en uno de los caminos.
--
-- Alcance del aviso (decidido con operaciones):
--   · Jefe de Taller  → siempre (su ámbito es 'todos')
--   · Jefe de Operaciones → sólo el de la operación del equipo
--   · si el equipo no tiene operación cargada, se avisa a todos: preferimos
--     ruido a silencio cuando el dato falta
-- ============================================================================

BEGIN;

-- ── 1. El tipo nuevo entra al CHECK de alertas ──────────────────────────────
-- Se parcha la definición VIVA en vez de reescribir la lista completa: así no
-- se pierde ningún tipo que se haya agregado después de esta migración.
DO $mig$
DECLARE
    v_def TEXT;
BEGIN
    SELECT pg_get_constraintdef(oid) INTO v_def
      FROM pg_constraint
     WHERE conname = 'chk_alertas_tipo' AND conrelid = 'alertas'::regclass;

    IF v_def IS NULL THEN
        RAISE EXCEPTION 'FALLO: no existe chk_alertas_tipo sobre alertas';
    END IF;

    IF v_def LIKE '%plan_papeles_equipo%' THEN
        RAISE NOTICE 'chk_alertas_tipo ya permite plan_papeles_equipo — sin cambios';
    ELSE
        IF v_def NOT LIKE '%''doc_sin_fecha''::text]%' THEN
            RAISE EXCEPTION 'FALLO: el CHECK no termina como se esperaba, revisar a mano: %', v_def;
        END IF;

        ALTER TABLE alertas DROP CONSTRAINT chk_alertas_tipo;
        EXECUTE format(
            'ALTER TABLE alertas ADD CONSTRAINT chk_alertas_tipo %s',
            replace(v_def,
                    '''doc_sin_fecha''::text]',
                    '''doc_sin_fecha''::text, ''plan_papeles_equipo''::text]')
        );
        RAISE NOTICE 'chk_alertas_tipo → plan_papeles_equipo autorizado';
    END IF;
END
$mig$;

-- ── 2. Qué papeles de un equipo están con problema ──────────────────────────
-- Se lee de v_certificacion_actual y NO de la tabla: la vista es la que sabe
-- cuál es el papel vigente de cada tipo y cuántos días le quedan.
--
-- 'sin_fecha' cuenta como problema. Un papel sin vencimiento anotado no es un
-- papel bueno: es un papel del que no sabemos nada.
CREATE OR REPLACE FUNCTION fn_activo_papeles_problema(p_activo_id UUID)
RETURNS TABLE (
    tipo              TEXT,
    estado            TEXT,
    fecha_vencimiento DATE,
    dias_restantes    INT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT c.tipo::TEXT,
           c.estado_real::TEXT,
           c.fecha_vencimiento,
           c.dias_restantes
      FROM v_certificacion_actual c
     WHERE c.activo_id = p_activo_id
       AND c.estado_real IN ('vencido', 'por_vencer', 'sin_fecha')
     ORDER BY CASE c.estado_real
                  WHEN 'vencido'    THEN 0
                  WHEN 'por_vencer' THEN 1
                  ELSE 2
              END,
              c.dias_restantes NULLS LAST,
              c.tipo;
$$;

COMMENT ON FUNCTION fn_activo_papeles_problema IS
'Papeles vencidos, por vencer o sin fecha de un equipo. Fuente: v_certificacion_actual (MIG441).';

-- El nombre del papel como lo dice la gente. El aviso lo leen el jefe de taller
-- y el de operaciones en la campanita, y 'laminas_seguridad' no es un nombre:
-- es una llave de base de datos. Las etiquetas están copiadas de TIPO_DOC_LABEL
-- del frontend; lo que no esté cae en un formato legible en vez de romperse.
CREATE OR REPLACE FUNCTION fn_papel_tipo_label(p_tipo TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT coalesce(
      (SELECT l.label FROM (VALUES
        ('revision_tecnica',     'Revisión Técnica'),
        ('soap',                 'SOAP'),
        ('permiso_circulacion',  'Permiso de Circulación'),
        ('permiso_municipal',    'Permiso Municipal'),
        ('hermeticidad',         'Hermeticidad'),
        ('tc8_sec',              'TC8 SEC'),
        ('inscripcion_sec',      'Inscripción SEC'),
        ('sec',                  'SEC'),
        ('seremi',               'SEREMI'),
        ('siss',                 'SISS'),
        ('seguro_rc',            'Póliza de Seguro'),
        ('fops_rops',            'FOPS/ROPS'),
        ('cert_gancho',          'Certificación Gancho'),
        ('calibracion',          'Cert. Calibración Surtidor'),
        ('licencia_especial',    'Licencia Especial'),
        ('analisis_gases',       'Análisis de Gases'),
        ('padron',               'Padrón'),
        ('inscripcion_rnvm',     'Inscripción RNVM'),
        ('homologacion',         'Cert. Homologación'),
        ('optico_sobrellenado',  'Cert. Sist. Óptico Sobrellenado'),
        ('flujo_descarga',       'Cert. Flujo y Descarga'),
        ('sist_riego',           'Cert. Sist. Riego'),
        ('cert_cabina',          'Cert. Cabina'),
        ('laminas_seguridad',    'Cert. Láminas de Seguridad'),
        ('barra_antivuelco',     'Cert. Barra Antivuelco'),
        ('operatividad',         'Cert. Operatividad'),
        ('grilletes_eslingas',   'Cert. Grilletes y Eslingas'),
        ('mant_hidraulico',      'Cert. Mant. Sist. Hidráulico'),
        ('mantencion',           'Cert. Mantención'),
        ('aire_acondicionado',   'Cert. Mant. Aire Acondicionado'),
        ('tacografo',            'Cert. Tacógrafo'),
        ('torque_ruedas',        'Cert. Torque Ruedas'),
        ('ausencia_falla_ecm',   'Cert. Ausencia Falla ECM'),
        ('gps',                  'Cert. GPS'),
        ('inventario_neumaticos','Inventario Neumáticos'),
        ('ficha_tecnica',        'Ficha Técnica'),
        ('factura_compra',       'Factura de Compra'),
        ('manual',               'Manual'),
        ('otra',                 'Otro')
      ) AS l(clave, label) WHERE l.clave = p_tipo),
      initcap(replace(p_tipo, '_', ' '))
    );
$$;

COMMENT ON FUNCTION fn_papel_tipo_label IS
'Nombre legible de un tipo de papel, para los avisos que lee una persona (MIG441).';

-- Lo mismo, para que el planificador lo vea ANTES de soltar la patente.
CREATE OR REPLACE FUNCTION rpc_activo_papeles_problema(p_activo_id UUID)
RETURNS TABLE (
    tipo              TEXT,
    estado            TEXT,
    fecha_vencimiento DATE,
    dias_restantes    INT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT * FROM fn_activo_papeles_problema(p_activo_id);
$$;

REVOKE ALL ON FUNCTION rpc_activo_papeles_problema(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION rpc_activo_papeles_problema(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION rpc_activo_papeles_problema(UUID) TO authenticated;

-- ── 3. El aviso, al entrar al plan ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_alertar_papeles_plan_taller()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_activo_id  UUID;
    v_patente    TEXT;
    v_codigo     TEXT;
    v_operacion  TEXT;
    v_folio      TEXT;
    v_fecha      DATE;
    v_vencidos   INT;
    v_total      INT;
    v_detalle    TEXT;
    v_sev        TEXT;
    v_equipo     TEXT;
    v_n          INT;
BEGIN
    -- Las tareas libres no tienen OT ni equipo: no hay papeles que mirar.
    IF NEW.ot_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT ot.activo_id, ot.folio INTO v_activo_id, v_folio
      FROM ordenes_trabajo ot WHERE ot.id = NEW.ot_id;

    IF v_activo_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Un plan multidía inserta una fila por día. El aviso es del equipo, no del
    -- día: mientras la jefatura no lo haya leído, no se repite.
    IF EXISTS (
        SELECT 1 FROM alertas
         WHERE tipo = 'plan_papeles_equipo'
           AND entidad_id = NEW.ot_id
           AND NOT leida
    ) THEN
        RETURN NEW;
    END IF;

    SELECT count(*) FILTER (WHERE p.estado = 'vencido'),
           count(*)
      INTO v_vencidos, v_total
      FROM fn_activo_papeles_problema(v_activo_id) p;

    IF coalesce(v_total, 0) = 0 THEN
        RETURN NEW;
    END IF;

    SELECT a.patente, a.codigo, a.operacion
      INTO v_patente, v_codigo, v_operacion
      FROM activos a WHERE a.id = v_activo_id;

    v_equipo := coalesce(v_patente, v_codigo, 'equipo');

    SELECT d.fecha INTO v_fecha
      FROM taller_plan_semanal_dias d WHERE d.id = NEW.plan_dia_id;

    -- Detalle legible: los tres peores, y cuántos quedan fuera.
    SELECT string_agg(linea, E'\n' ORDER BY orden)
      INTO v_detalle
      FROM (
        SELECT row_number() OVER () AS orden,
               format('· %s: %s',
                      fn_papel_tipo_label(p.tipo),
                      CASE p.estado
                          WHEN 'vencido'    THEN format('vencido hace %s días', abs(p.dias_restantes))
                          WHEN 'por_vencer' THEN format('vence en %s días', p.dias_restantes)
                          ELSE 'sin fecha de vencimiento'
                      END) AS linea
          FROM fn_activo_papeles_problema(v_activo_id) p
         LIMIT 3
      ) t;

    v_n := v_total - least(v_total, 3);
    IF v_n > 0 THEN
        v_detalle := v_detalle || format(E'\n· y %s más', v_n);
    END IF;

    v_sev := CASE WHEN coalesce(v_vencidos, 0) > 0 THEN 'critical' ELSE 'warning' END;

    INSERT INTO alertas (
        tipo, titulo, mensaje, severidad,
        entidad_tipo, entidad_id, destinatario_id, requiere_accion
    )
    SELECT
        'plan_papeles_equipo',
        format('%s entró al plan del taller con %s papel%s con problema',
               v_equipo, v_total, CASE WHEN v_total = 1 THEN '' ELSE 'es' END),
        format(E'La OT %s quedó planificada para el %s.\n\n%s\n\nSe puede trabajar igual; el aviso es para que la jefatura lo sepa y decida.',
               coalesce(v_folio, 's/folio'),
               coalesce(v_fecha::TEXT, 'esta semana'),
               coalesce(v_detalle, '')),
        v_sev,
        'orden_trabajo',
        NEW.ot_id,
        up.id,
        TRUE
      FROM usuarios_perfil up
     WHERE coalesce(up.activo, TRUE)
       AND up.rol IN ('jefe_mantenimiento', 'jefe_operaciones')
       -- El jefe de taller tiene ámbito 'todos' y recibe siempre. El de
       -- operaciones, sólo lo de su operación. Si el equipo no tiene operación
       -- cargada nadie queda fuera: preferimos ruido a silencio.
       AND (coalesce(up.ambito, 'todos') = 'todos'
            OR v_operacion IS NULL
            OR lower(v_operacion) = lower(up.ambito));

    RETURN NEW;
END
$$;

COMMENT ON FUNCTION fn_alertar_papeles_plan_taller IS
'Avisa a jefe de taller y jefe de operaciones cuando entra al plan un equipo con papeles vencidos, por vencer o sin fecha. No bloquea (MIG441).';

DROP TRIGGER IF EXISTS trg_alertar_papeles_plan_taller ON taller_plan_semanal_ots;
CREATE TRIGGER trg_alertar_papeles_plan_taller
    AFTER INSERT ON taller_plan_semanal_ots
    FOR EACH ROW EXECUTE FUNCTION fn_alertar_papeles_plan_taller();

-- ── 4. Verificación ─────────────────────────────────────────────────────────
DO $mig$
DECLARE
    v_activo   UUID;
    v_patente  TEXT;
    v_papeles  INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_alertar_papeles_plan_taller') THEN
        RAISE EXCEPTION 'FALLO: el trigger no quedó creado';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'chk_alertas_tipo'
           AND pg_get_constraintdef(oid) LIKE '%plan_papeles_equipo%'
    ) THEN
        RAISE EXCEPTION 'FALLO: chk_alertas_tipo no admite plan_papeles_equipo';
    END IF;

    -- Un equipo real con papeles malos, para que la función no quede sin probar.
    SELECT c.activo_id INTO v_activo
      FROM v_certificacion_actual c
     WHERE c.estado_real = 'vencido'
     LIMIT 1;

    IF v_activo IS NULL THEN
        RAISE NOTICE 'No hay ningún equipo con papeles vencidos; no se pudo probar la función.';
    ELSE
        SELECT count(*) INTO v_papeles FROM fn_activo_papeles_problema(v_activo);
        SELECT a.patente INTO v_patente FROM activos a WHERE a.id = v_activo;
        RAISE NOTICE 'fn_activo_papeles_problema OK: % tiene % papel(es) con problema',
                     coalesce(v_patente, v_activo::TEXT), v_papeles;
    END IF;
END
$mig$;

COMMIT;
