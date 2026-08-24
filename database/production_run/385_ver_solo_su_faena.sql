-- ============================================================================
-- MIG385 · Quien responde por una faena ve su faena
-- ----------------------------------------------------------------------------
-- Catalina es planificadora de Romeral y al entrar ve el sistema completo: las
-- 121 OT de todas las faenas, los 68 equipos, el taller de Coquimbo, Calama,
-- ENEX. Lo suyo son 3 equipos, 5 OT y el combustible de una faena. Los cuatro
-- supervisores de Romeral están igual.
--
-- POR PERSONA, NO POR ROL
-- La tentación es colgarlo del rol —«planificador con faena»— y sería un error:
-- Eduardo también es planificador con faena, pero la suya es el taller de
-- Coquimbo y él sí necesita ver todo. Por eso la marca va en la persona y se
-- prende desde Admin. Agregar o sacar a alguien no vuelve a tocar código.
--
-- LA MARCA NECESITA UNA FAENA
-- «Ver sólo lo mío» sin decir cuál es lo mío deja a la persona sin nada. El
-- CHECK lo impide: si se prende la marca, el perfil tiene que tener faena.
--
-- EL PANEL DE LA FAENA, COMO LA APP DE LA FAENA
-- MIG361 puso `app_movil` en la faena para que el guard de terreno no
-- preguntara por el rol. Acá pasa lo mismo con el panel web: la faena declara
-- cuál es su pantalla de control, y el menú se arma solo. Cuando Franke tenga
-- el suyo, se llena la columna y funciona sin tocar el código.
--
-- ESTO NO ES SEGURIDAD DE BASE DE DATOS
-- Recorta el menú y bloquea la navegación: resuelve el problema real, que es
-- una planificadora perdida entre pantallas que no le tocan. No es una barrera
-- contra alguien que quiera consultar la API a mano — eso sería RLS por faena
-- en cada tabla, que es otro trabajo y otra conversación.
-- ============================================================================

BEGIN;

-- ── 1. La marca ───────────────────────────────────────────────────────────
ALTER TABLE public.usuarios_perfil
    ADD COLUMN IF NOT EXISTS solo_su_faena BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.usuarios_perfil.solo_su_faena IS
    '[MIG385] TRUE = el menú y la navegación quedan acotados a su faena. Se prende por persona desde Admin, no por rol: hay planificadores de faena que sí necesitan ver todo.';

DO $ck$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_solo_su_faena_tiene_faena') THEN
        ALTER TABLE public.usuarios_perfil
            ADD CONSTRAINT chk_solo_su_faena_tiene_faena
            CHECK (NOT solo_su_faena OR faena_id IS NOT NULL);
    END IF;
END
$ck$;

-- ── 2. La faena declara su panel web ──────────────────────────────────────
ALTER TABLE public.faenas
    ADD COLUMN IF NOT EXISTS panel_web TEXT;

COMMENT ON COLUMN public.faenas.panel_web IS
    '[MIG385] Pantalla de control de la faena en el panel web, como app_movil lo es en terreno (MIG361). Si está vacía, la faena no ofrece panel propio.';

UPDATE public.faenas
   SET panel_web = '/dashboard/combustible/romeral'
 WHERE codigo = 'FAE-CMP-ROMERAL' AND panel_web IS DISTINCT FROM '/dashboard/combustible/romeral';

UPDATE public.faenas
   SET panel_web = '/dashboard/combustible/franke'
 WHERE codigo = 'FAE-FRANCKE' AND panel_web IS DISTINCT FROM '/dashboard/combustible/franke';

-- ── 3. Los cinco de Romeral ───────────────────────────────────────────────
-- Catalina (planificadora) y los cuatro supervisores de la faena.
UPDATE public.usuarios_perfil up
   SET solo_su_faena = TRUE,
       updated_at = NOW()
  FROM public.faenas f
 WHERE f.id = up.faena_id
   AND f.codigo = 'FAE-CMP-ROMERAL'
   AND up.activo
   AND up.rol IN ('planificador', 'supervisor');

-- ── 4. Lo que quedó ───────────────────────────────────────────────────────
DO $r$
DECLARE v_lista TEXT; v_otros INT;
BEGIN
    SELECT string_agg(up.nombre_completo || ' (' || up.rol || ')', ', ' ORDER BY up.nombre_completo)
      INTO v_lista
      FROM public.usuarios_perfil up
     WHERE up.solo_su_faena AND up.activo;
    RAISE NOTICE 'Acotados a su faena: %', COALESCE(v_lista, 'nadie');

    -- El control de que no se coló quien no debía.
    SELECT count(*) INTO v_otros
      FROM public.usuarios_perfil up
      LEFT JOIN public.faenas f ON f.id = up.faena_id
     WHERE up.solo_su_faena AND up.activo AND COALESCE(f.codigo, '') <> 'FAE-CMP-ROMERAL';
    IF v_otros > 0 THEN
        RAISE EXCEPTION 'Se marcaron % perfiles fuera de Romeral. Revisar antes de seguir.', v_otros;
    END IF;
END
$r$;

COMMIT;
