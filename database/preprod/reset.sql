SET client_min_messages=warning;
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT USAGE, CREATE ON SCHEMA public TO anon, authenticated, service_role, postgres;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
TRUNCATE auth.users;
SELECT extensions.uuid_generate_v4() IS NOT NULL AS uuid_ossp_ok;
