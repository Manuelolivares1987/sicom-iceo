-- ============================================================================
-- MIG716 — faena_supervisores con PK propia (19-11-2026)
-- ----------------------------------------------------------------------------
-- MIG696 creó faena_supervisores con PRIMARY KEY (faena_id, usuario_id).
-- PostgREST trata una tabla así como "puente" muchos-a-muchos entre
-- usuarios_perfil y faenas, y desde el 15-11 la consulta del perfil
--   usuarios_perfil?select=*,faena:faenas(...)
-- falla para TODOS con PGRST201 «more than one relationship was found for
-- 'usuarios_perfil' and 'faenas'». Quien tenía el perfil guardado en el equipo
-- no lo notó; quien entró en un equipo nuevo quedó sin perfil (menú general a
-- nombre de «Usuario», ruedita eterna: Yohan y Edison, Franke).
--
-- El frontend ya usa la relación explícita (PR #521), pero los teléfonos con
-- la versión vieja siguen pidiendo la consulta ambigua: esto los arregla sin
-- que tengan que actualizarse.
--
-- PK surrogate + UNIQUE (faena_id, usuario_id): la unicidad se mantiene (el
-- ON CONFLICT (faena_id, usuario_id) de MIG696 sigue válido) y PostgREST deja
-- de inferir el muchos-a-muchos. No borra datos. Autorizado por Manuel 19-11.
-- ============================================================================

ALTER TABLE public.faena_supervisores
    ADD COLUMN IF NOT EXISTS id UUID NOT NULL DEFAULT gen_random_uuid();

ALTER TABLE public.faena_supervisores DROP CONSTRAINT IF EXISTS faena_supervisores_pkey;
ALTER TABLE public.faena_supervisores ADD CONSTRAINT faena_supervisores_pkey PRIMARY KEY (id);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'faena_supervisores_faena_usuario_key') THEN
        ALTER TABLE public.faena_supervisores
            ADD CONSTRAINT faena_supervisores_faena_usuario_key UNIQUE (faena_id, usuario_id);
    END IF;
END $$;

NOTIFY pgrst, 'reload schema';

SELECT conname, pg_get_constraintdef(oid) AS def,
       (SELECT count(*) FROM public.faena_supervisores) AS filas
FROM pg_constraint WHERE conrelid = 'public.faena_supervisores'::regclass AND contype IN ('p', 'u');
