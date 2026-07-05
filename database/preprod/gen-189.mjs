// Genera 189_fase01_revocar_anon_escritura.sql desde la clasificación real de prod.
import pg from 'pg'; import dotenv from 'dotenv'; import { writeFileSync } from 'node:fs'
dotenv.config({ path: 'C:/Users/Manuel Olivares/sicom-iceo/.env.supabase-admin.local' })
const c = new pg.Client({ connectionString: (process.env.SUPABASE_DB_URL||'').trim(), ssl:{rejectUnauthorized:false} })
await c.connect()

// Allowlist: funciones que DEBEN seguir siendo anónimas (escritura pública por QR).
const ALLOW = new Set(['rpc_guardar_checklist_publico','rpc_checklist_cliente_guardar'])

const rows = (await c.query(`
  SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
  WHERE p.prosecdef AND p.prokind='f' AND p.prorettype <> 'trigger'::regtype
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND pg_get_functiondef(p.oid) ~* 'insert into|update .* set|delete from'
    AND pg_get_functiondef(p.oid) !~* 'auth\\.uid\\(\\) is null|no autenticado|fn_user_rol|fn_tiene_permiso'
  ORDER BY p.proname`)).rows

let sql = `-- ============================================================================
-- SICOM-ICEO | 189 — Fase 0.1: cerrar escritura ANÓNIMA no validada
-- ----------------------------------------------------------------------------
-- La auditoría encontró funciones SECURITY DEFINER en public, ejecutables por
-- 'anon' (por el EXECUTE default de PUBLIC nunca revocado), que ESCRIBEN sin
-- validar sesión/rol. Verificado explotable, p.ej. rpc_cambiar_contrato_activo
-- (cambia el contrato de cualquier activo por su ID, sin login).
--
-- Estrategia SEGURA y quirúrgica (sin tocar la lógica de cada función):
--   REVOKE EXECUTE FROM anon, PUBLIC  +  GRANT EXECUTE TO authenticated.
-- Así 'anon' pierde el acceso y los flujos autenticados del frontend siguen
-- funcionando. Los jobs de pg_cron/triggers ejecutan como 'postgres' y NO se
-- ven afectados (no dependen del grant de anon).
--
-- Allowlist (siguen siendo anónimas, son escrituras públicas por QR;
-- su rate-limit es un pendiente P1 aparte):
--   ${[...ALLOW].join(', ')}
--
-- Esta migración NO reemplaza la validación por-función (defensa en profundidad),
-- que queda como endurecimiento posterior. Cierra la exposición anónima YA.
-- IDEMPOTENTE. Rollback: GRANT EXECUTE ... TO anon en las funciones listadas
-- (reabre el agujero; ver database/rollback/rollback_189_*.sql).
-- ============================================================================
SET client_min_messages = warning;

`
let n = 0
for (const r of rows) {
  if (ALLOW.has(r.proname)) { sql += `-- (allowlist, se mantiene anon) ${r.proname}\n`; continue }
  const sig = `public.${r.proname}(${r.args})`
  sql += `REVOKE EXECUTE ON FUNCTION ${sig} FROM anon, PUBLIC;\nGRANT  EXECUTE ON FUNCTION ${sig} TO authenticated;\n`
  n++
}

sql += `\n-- Verificación: 0 de las funciones cerradas debe quedar ejecutable por anon.\nDO $$\nDECLARE v_abiertas INT;\nBEGIN\n    SELECT count(*) INTO v_abiertas\n      FROM pg_proc p JOIN pg_namespace nsp ON nsp.oid=p.pronamespace AND nsp.nspname='public'\n     WHERE p.prosecdef AND p.prokind='f' AND p.prorettype <> 'trigger'::regtype\n       AND has_function_privilege('anon', p.oid, 'EXECUTE')\n       AND pg_get_functiondef(p.oid) ~* 'insert into|update .* set|delete from'\n       AND pg_get_functiondef(p.oid) !~* 'auth\\\\.uid\\\\(\\\\) is null|no autenticado|fn_user_rol|fn_tiene_permiso'\n       AND p.proname NOT IN (${[...ALLOW].map(a=>`'${a}'`).join(',')});\n    IF v_abiertas > 0 THEN\n        RAISE EXCEPTION 'MIG189 incompleta: % funciones de escritura siguen anónimas', v_abiertas;\n    END IF;\n    RAISE NOTICE 'MIG189 OK: escritura anónima no validada cerrada (allowlist QR intacta).';\nEND $$;\n\nSELECT '${n} funciones cerradas a anon' AS resultado;\n`

writeFileSync('C:/Users/Manuel Olivares/sicom-iceo/database/production_run/189_fase01_revocar_anon_escritura.sql', sql)
console.log(`189 generada: ${n} funciones cerradas, ${ALLOW.size} en allowlist`)
await c.end()
