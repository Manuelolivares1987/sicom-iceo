-- ============================================================================
-- SICOM-ICEO | 280 — Rol para el operador del camión de combustible
-- ============================================================================
-- La cuenta del camión de Romeral es COMPARTIDA: la usan los operadores que se
-- turnan, y cada uno escribe su nombre en la app al empezar. Es el mismo
-- criterio que ya se usa con `operador_taller` para los mecánicos.
--
-- Por eso el rol tiene que ser MÍNIMO: esa credencial vive en un teléfono en
-- faena y va a circular. Sin acceso al dashboard, sin contratos, sin flota, sin
-- costos: solo la app de despacho /m/romeral.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
         WHERE enumtypid = 'rol_usuario_enum'::regtype AND enumlabel = 'operador_combustible'
    ) THEN
        ALTER TYPE rol_usuario_enum ADD VALUE 'operador_combustible';
        RAISE NOTICE 'MIG280: rol operador_combustible agregado';
    ELSE
        RAISE NOTICE 'MIG280: el rol ya existía';
    END IF;
END $$;

SELECT 'MIG280 OK' AS resultado,
       (SELECT string_agg(enumlabel, ', ' ORDER BY enumsortorder)
          FROM pg_enum WHERE enumtypid = 'rol_usuario_enum'::regtype) AS roles;
