-- ============================================================================
-- MIG353 · El apellido de Catalina
-- ----------------------------------------------------------------------------
-- La cuenta se creó con el nombre de pila porque era lo que se sabía. El
-- nombre completo importa: es el que aparece firmando el cierre y el que llega
-- a ESMAX en los entregables. Un documento firmado por «Catalina» no identifica
-- a nadie.
-- ============================================================================

BEGIN;

UPDATE public.usuarios_perfil
   SET nombre_completo = 'Catalina Rojas', updated_at = NOW()
 WHERE email = 'catalina@pillado.cl';

UPDATE auth.users
   SET raw_user_meta_data = jsonb_set(
         COALESCE(raw_user_meta_data, '{}'::jsonb),
         '{nombre_completo}', '"Catalina Rojas"'),
       updated_at = NOW()
 WHERE email = 'catalina@pillado.cl';

COMMIT;
