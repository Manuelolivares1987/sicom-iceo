-- Bootstrap del entorno preprod: reproduce el modelo de conexión de Supabase.
SET client_min_messages = warning;

-- Roles (como en Supabase): authenticator hace LOGIN y SET ROLE a los demás.
DO $$ BEGIN CREATE ROLE anon          NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE authenticated NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE service_role  NOLOGIN NOINHERIT BYPASSRLS; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE authenticator LOGIN PASSWORD 'authpw' NOINHERIT NOSUPERUSER NOBYPASSRLS; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
GRANT anon, authenticated, service_role TO authenticator;

-- prod_owner reproduce al 'postgres' de prod: NOSUPERUSER + BYPASSRLS + dueño de todo.
DO $$ BEGIN CREATE ROLE prod_owner NOLOGIN NOSUPERUSER BYPASSRLS CREATEROLE; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
GRANT prod_owner TO postgres;               -- el superusuario del harness puede SET ROLE prod_owner
GRANT anon, authenticated, service_role TO postgres;  -- para poder simular contextos en tests admin

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role, authenticator, prod_owner;
GRANT CREATE ON SCHEMA public TO prod_owner;
ALTER SCHEMA public OWNER TO prod_owner;

-- Esquema auth con los shims que usa el código (auth.uid / auth.role).
CREATE SCHEMA IF NOT EXISTS auth;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role, authenticator, prod_owner;

CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true)::jsonb->>'sub', '')::uuid;
$$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT current_setting('request.jwt.claims', true)::jsonb->>'role';
$$;
GRANT EXECUTE ON FUNCTION auth.uid(), auth.role() TO anon, authenticated, service_role, authenticator, prod_owner;

-- Tipo faltante usado por columnas de activos.
DO $$ BEGIN CREATE TYPE categoria_uso_enum AS ENUM ('arriendo_comercial','leasing_operativo','uso_interno','venta'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
