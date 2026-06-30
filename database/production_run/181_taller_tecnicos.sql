-- ============================================================================
-- SICOM-ICEO | 181 — Maestro de técnicos de taller (con especialidad)
-- ============================================================================
-- Pedido Manuel (2026-06-30): registrar los técnicos de la operación Coquimbo
-- con su especialidad, para asignarlos en el Plan Taller. Hoy la "cuadrilla" del
-- plan es texto libre y la lista de mecánicos está hardcodeada en el frontend
-- (taller-grupos.ts). Estos técnicos NO necesitan cuenta de login; son etiquetas
-- asignables. Por eso una tabla liviana, no usuarios_perfil/auth.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

CREATE TABLE IF NOT EXISTS taller_tecnicos (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre             VARCHAR(120) NOT NULL,
    especialidad       VARCHAR(40)  NOT NULL DEFAULT 'MECANICO',  -- MECANICO / SOLDADURA / TRASLADOS / ...
    operacion          VARCHAR(40),                                -- Coquimbo / Calama / ...
    -- opcional: si además tiene perfil con login (no requerido)
    usuario_perfil_id  UUID REFERENCES usuarios_perfil(id),
    activo             BOOLEAN NOT NULL DEFAULT true,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE taller_tecnicos IS
    'Maestro de técnicos de taller (etiquetas asignables a la cuadrilla del plan). Sin login. MIG181.';
COMMENT ON COLUMN taller_tecnicos.especialidad IS 'MECANICO, SOLDADURA, TRASLADOS, etc. MIG181.';
COMMENT ON COLUMN taller_tecnicos.operacion IS 'Operación/zona (Coquimbo, Calama). Filtra el picker del plan. MIG181.';

CREATE INDEX IF NOT EXISTS idx_taller_tecnicos_operacion ON taller_tecnicos (operacion) WHERE activo;
CREATE UNIQUE INDEX IF NOT EXISTS uq_taller_tecnicos_nombre_op
    ON taller_tecnicos (lower(nombre), COALESCE(operacion,'')) ;

-- ── RLS: lectura para autenticados, escritura roles operacionales ────────────
ALTER TABLE taller_tecnicos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_taller_tecnicos_select ON taller_tecnicos;
CREATE POLICY pol_taller_tecnicos_select ON taller_tecnicos
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_taller_tecnicos_write ON taller_tecnicos;
CREATE POLICY pol_taller_tecnicos_write ON taller_tecnicos
    FOR ALL TO authenticated
    USING      (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor','planificador'))
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor','planificador'));

-- ── Seed: técnicos de Coquimbo ───────────────────────────────────────────────
INSERT INTO taller_tecnicos (nombre, especialidad, operacion)
SELECT v.nombre, v.especialidad, 'Coquimbo'
FROM (VALUES
    ('Felipe Rojas',  'MECANICO'),
    ('Sergio Cortes', 'MECANICO'),
    ('Yusdel Sarduy', 'MECANICO'),
    ('Joel Coo',      'MECANICO'),
    ('Danny Guerra',  'SOLDADURA'),
    ('Jorge Castro',  'TRASLADOS'),
    ('Marcos Diaz',   'MECANICO'),
    ('Felipe López',  'MECANICO')
) AS v(nombre, especialidad)
WHERE NOT EXISTS (
    SELECT 1 FROM taller_tecnicos t
     WHERE lower(t.nombre) = lower(v.nombre) AND COALESCE(t.operacion,'') = 'Coquimbo'
);

GRANT SELECT, INSERT, UPDATE ON taller_tecnicos TO authenticated;

-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'total_coquimbo', (SELECT COUNT(*) FROM taller_tecnicos WHERE operacion='Coquimbo' AND activo),
    'por_especialidad', (SELECT jsonb_object_agg(especialidad, n) FROM (
        SELECT especialidad, COUNT(*) n FROM taller_tecnicos WHERE operacion='Coquimbo' GROUP BY especialidad) s)
) AS resultado;

NOTIFY pgrst, 'reload schema';
