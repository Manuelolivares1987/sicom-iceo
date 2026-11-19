-- Rollback MIG716: vuelve la PK compuesta (reintroduce el PGRST201 en la consulta del perfil
-- para clientes sin el hint !usuarios_perfil_faena_id_fkey).
ALTER TABLE public.faena_supervisores DROP CONSTRAINT IF EXISTS faena_supervisores_pkey;
ALTER TABLE public.faena_supervisores DROP CONSTRAINT IF EXISTS faena_supervisores_faena_usuario_key;
ALTER TABLE public.faena_supervisores ADD CONSTRAINT faena_supervisores_pkey PRIMARY KEY (faena_id, usuario_id);
ALTER TABLE public.faena_supervisores DROP COLUMN IF EXISTS id;
NOTIFY pgrst, 'reload schema';
