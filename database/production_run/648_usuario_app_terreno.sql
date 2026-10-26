-- MIG648 · La cuenta dice a qué app de terreno entra y, en ENEX, su mundo
-- ============================================================================
-- 26-10, Manuel: los dos supervisores de ENEX tienen que hacer login y quedar
-- trabajando, sin apretar nada más. Hasta hoy caían en el panel de escritorio
-- (/dashboard) y en el celular tenían que buscar «Terreno ENEX» en el menú;
-- además cada uno elegía a mano Combustible o Lubricantes.
--
--   usuarios_perfil.app_terreno  ruta a la que entra la cuenta al abrir el
--                                sistema (/dashboard → app_terreno)
--   usuarios_perfil.enex_mundo   mundo por defecto en /m/enex
--
-- Va por persona y no por rol: un «supervisor» de otra faena sigue usando el
-- panel web.
-- ============================================================================

BEGIN;

ALTER TABLE usuarios_perfil
    ADD COLUMN IF NOT EXISTS app_terreno TEXT
        CHECK (app_terreno IS NULL OR app_terreno ~ '^/m/[a-z0-9-]+/?$'),
    ADD COLUMN IF NOT EXISTS enex_mundo TEXT
        CHECK (enex_mundo IS NULL OR enex_mundo IN ('combustible', 'lubricante'));

COMMENT ON COLUMN usuarios_perfil.app_terreno IS
    'MIG648: app móvil a la que entra la cuenta al abrir /dashboard (p. ej. /m/enex).';
COMMENT ON COLUMN usuarios_perfil.enex_mundo IS
    'MIG648: mundo por defecto en /m/enex (combustible | lubricante).';

UPDATE usuarios_perfil p
   SET app_terreno = '/m/enex',
       enex_mundo  = CASE u.email
                       WHEN 'supervisor.combustible@sicom-iceo.cl' THEN 'combustible'
                       WHEN 'supervisor.lubricantes@sicom-iceo.cl' THEN 'lubricante'
                     END,
       updated_at  = now()
  FROM auth.users u
 WHERE u.id = p.id
   AND u.email IN ('supervisor.combustible@sicom-iceo.cl', 'supervisor.lubricantes@sicom-iceo.cl');

DO $$
DECLARE n INT;
BEGIN
    SELECT count(*) INTO n FROM usuarios_perfil WHERE app_terreno = '/m/enex' AND enex_mundo IS NOT NULL;
    IF n <> 2 THEN RAISE EXCEPTION 'MIG648: se esperaban 2 supervisores ENEX, hay %', n; END IF;
END $$;

COMMIT;
