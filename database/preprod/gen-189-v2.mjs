// Genera 189_fase01_autorizacion_p0.sql: guards fail-closed en las P0 de usuario,
// REVOKE total en las P0 internas (cron/trigger), y REVOKE-anon en P1/P2.
// Fuente de verdad de roles default = frontend/src/hooks/use-permissions.ts.
import pg from 'pg'; import dotenv from 'dotenv'
import { readFileSync, writeFileSync } from 'node:fs'
dotenv.config({ path: 'C:/Users/Manuel Olivares/sicom-iceo/.env.supabase-admin.local' })

// ── 1. Parsear PERMISSIONS del frontend ─────────────────────────────────────
const perms = readFileSync('C:/Users/Manuel Olivares/sicom-iceo/frontend/src/hooks/use-permissions.ts', 'utf8')
const permBlock = perms.slice(perms.indexOf('PERMISSIONS'), perms.indexOf('export const MODULE_CATALOG'))
const map = {} // rol -> modulo -> [acciones]
const roleRe = /^  ([a-z_]+): \{([\s\S]*?)^  \},/gm
let rm
while ((rm = roleRe.exec(permBlock))) {
  const rol = rm[1]; map[rol] = {}
  const modRe = /(\w+): \[([^\]]*)\]/g; let mm
  while ((mm = modRe.exec(rm[2]))) {
    map[rol][mm[1]] = mm[2].split(',').map(s => s.replace(/['\s]/g, '')).filter(Boolean)
  }
}
const rolesFor = (modulo, accion) =>
  Object.keys(map).filter(r => (map[r][modulo] || []).includes(accion)).sort()

// ── 2. Mapeo P0 (revisado contra el uso real) ───────────────────────────────
// grupo A = user-facing (guard + grant authenticated); B = interno (revoke total)
const P0 = {
  // A — usuario
  rpc_crear_ot:                 { grupo: 'A', modulo: 'ordenes_trabajo', accion: 'create' },
  rpc_transicion_ot:            { grupo: 'A', modulo: 'ordenes_trabajo', accion: 'edit' },
  rpc_cerrar_ot_supervisor:     { grupo: 'A', modulo: 'ordenes_trabajo', accion: 'approve' },
  rpc_registrar_salida_inventario:{ grupo: 'A', modulo: 'inventario',    accion: 'create' },
  rpc_cambiar_contrato_activo:  { grupo: 'A', modulo: 'contratos',      accion: 'edit' },
  rpc_confirmar_estado_dia:     { grupo: 'A', modulo: 'flota',          accion: 'approve' },
  rpc_actualizar_metricas_activo:{ grupo: 'A', modulo: 'activos',       accion: 'edit' },
  rpc_asignar_pauta:            { grupo: 'A', modulo: 'mantenimiento',  accion: 'edit' },
  rpc_crear_auxiliar:           { grupo: 'A', modulo: 'activos',        accion: 'create' },
  rpc_generar_qr_activo:        { grupo: 'A', modulo: 'activos',        accion: 'edit' },
  rpc_validar_sugerencia:       { grupo: 'A', modulo: 'flota',          accion: 'edit' },
  // B — interno (cron/trigger, corre como postgres): sin PostgREST
  generar_ots_preventivas:               { grupo: 'B' },
  verificar_certificaciones:             { grupo: 'B' },
  fn_auto_crear_planes_activo:           { grupo: 'B' },
  fn_generar_nc_desde_checklist_ot:      { grupo: 'B' },
  fn_generar_nc_desde_v3_ot:             { grupo: 'B' },
  fn_reconciliar_estado_ficha_desde_matriz:   { grupo: 'B' },
  fn_reconciliar_comercial_ficha_desde_matriz:{ grupo: 'B' },
}

const c = new pg.Client({ connectionString: (process.env.SUPABASE_DB_URL||'').trim(), ssl:{rejectUnauthorized:false} })
await c.connect()

async function fnInfo(name) {
  const r = await c.query(`
    SELECT p.oid, pg_get_function_identity_arguments(p.oid) AS args,
           pg_get_functiondef(p.oid) AS def, l.lanname
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    JOIN pg_language l ON l.oid=p.prolang
    WHERE p.proname=$1`, [name])
  return r.rows
}

// Inyecta el guard tras el primer BEGIN y normaliza search_path a public, pg_temp.
function guardInject(def, modulo, accion, roles) {
  let d = def
  // search_path: normalizar / insertar
  if (/ SET search_path/i.test(d)) {
    d = d.replace(/ SET search_path (TO|=)[^\n]*/i, ' SET search_path = public, pg_temp')
  } else {
    d = d.replace(/(\n?\s*SECURITY DEFINER)/i, '$1\n SET search_path = public, pg_temp')
  }
  const rolesArr = roles.length ? `ARRAY[${roles.map(r => `'${r}'`).join(',')}]::text[]` : `ARRAY[]::text[]`
  const guard =
`\n    -- [MIG189] Autorización fail-closed (${modulo}/${accion}). Deniega anon,\n` +
`    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.\n` +
`    IF NOT public.fn_tiene_permiso_modulo('${modulo}', '${accion}', ${rolesArr}) THEN\n` +
`        RAISE EXCEPTION 'No autorizado para % (%.%).', '${modulo}', '${modulo}', '${accion}' USING ERRCODE = '42501';\n` +
`    END IF;\n`
  // insertar tras el primer BEGIN del cuerpo (tras el $function$ de apertura)
  const bodyOpen = d.indexOf('$function$')
  if (bodyOpen < 0) throw new Error('sin $function$: ' + modulo)
  const rest = d.slice(bodyOpen + '$function$'.length)
  const m = /\bBEGIN\b/i.exec(rest)
  if (!m) throw new Error('sin BEGIN claro: ' + modulo)
  const at = bodyOpen + '$function$'.length + m.index + 'BEGIN'.length
  d = d.slice(0, at) + '\n' + guard + d.slice(at)
  return d
}

let sql = `-- ============================================================================
-- SICOM-ICEO | 189 — Fase 0.1: AUTORIZACIÓN REAL de funciones P0 anónimas
-- ----------------------------------------------------------------------------
-- Rediseño (rev. gate 2026-07-04). El REVOKE anon + GRANT authenticated de la
-- versión previa NO alcanza para funciones críticas: 'authenticated' es
-- cualquier sesión válida, no autorización de negocio. Aquí cada P0 queda
-- realmente autorizada:
--
--   GRUPO A (llamadas por el frontend): guard interno fail-closed
--     public.fn_tiene_permiso_modulo(modulo, accion, roles_default) — deniega
--     anon, portal cliente (sin fila en usuarios_perfil → fn_user_rol()=NULL),
--     usuarios inactivos, y autenticados sin el permiso. REVOKE anon+PUBLIC,
--     GRANT authenticated (el grant solo abre la puerta; el guard decide).
--
--   GRUPO B (solo cron/trigger, corren como 'postgres'): REVOKE EXECUTE de
--     anon, authenticated y PUBLIC. Dejan de ser invocables por PostgREST; los
--     jobs/triggers siguen operando (definer/postgres). NO se les pone guard de
--     auth.uid() porque eso rompería el cron.
--
--   P1/P2 (no P0): REVOKE anon + GRANT authenticated (cierre de superficie
--     anónima; su endurecimiento por-función queda en Fase 1). Allowlist QR
--     (rpc_guardar_checklist_publico, rpc_checklist_cliente_guardar) intacta.
--
-- Roles default de cada guard = los MISMOS que el frontend usa hoy para mostrar
-- el botón (fuente: use-permissions.ts); MIG126 puede sobreescribirlos por rol.
-- search_path = public, pg_temp (pg_temp AL FINAL; verificado que anon/
-- authenticated/PUBLIC no tienen CREATE en public ⇒ sin shadowing).
--
-- IDEMPOTENTE. Rollback: database/rollback/rollback_189_fase01.sql.
-- ============================================================================
SET client_min_messages = warning;

`

const matriz = []
// ── GRUPO A ──────────────────────────────────────────────────────────────
sql += `\n-- ═══ GRUPO A · P0 de usuario: guard fail-closed + grant authenticated ═══\n`
for (const [name, cfg] of Object.entries(P0)) {
  if (cfg.grupo !== 'A') continue
  const rows = await fnInfo(name)
  if (!rows.length) { sql += `-- (no encontrada: ${name})\n`; continue }
  const roles = rolesFor(cfg.modulo, cfg.accion)
  for (const r of rows) {
    if (r.lanname !== 'plpgsql') throw new Error(`${name} no es plpgsql (${r.lanname})`)
    const guarded = guardInject(r.def, cfg.modulo, cfg.accion, roles)
    sql += `\n-- ${name}(${r.args})  →  ${cfg.modulo}/${cfg.accion}  [default: ${roles.join(', ')||'(solo override)'}]\n`
    sql += guarded + ';\n'
    sql += `REVOKE EXECUTE ON FUNCTION public.${name}(${r.args}) FROM anon, PUBLIC;\n`
    sql += `GRANT  EXECUTE ON FUNCTION public.${name}(${r.args}) TO authenticated;\n`
    matriz.push({ fn: name, grupo: 'A', args: r.args, modulo: cfg.modulo, accion: cfg.accion, roles })
  }
}

// ── GRUPO B ──────────────────────────────────────────────────────────────
sql += `\n\n-- ═══ GRUPO B · P0 internas (cron/trigger): sin acceso PostgREST ═══\n`
for (const [name, cfg] of Object.entries(P0)) {
  if (cfg.grupo !== 'B') continue
  const rows = await fnInfo(name)
  for (const r of rows) {
    sql += `REVOKE EXECUTE ON FUNCTION public.${name}(${r.args}) FROM anon, authenticated, PUBLIC;\n`
    matriz.push({ fn: name, grupo: 'B', args: r.args, modulo: '(interno)', accion: '—', roles: [] })
  }
}

// ── P1/P2 (REVOKE anon, GRANT authenticated) salvo allowlist ────────────────
const ALLOW = new Set(['rpc_guardar_checklist_publico','rpc_checklist_cliente_guardar'])
// Llamada por la edge function GPS con SUPABASE_SERVICE_ROLE_KEY (necesidad documentada):
const SERVICE_ROLE = new Set(['rpc_ingestar_gps_batch'])
const p1p2 = (await c.query(`
  SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
  WHERE p.prosecdef AND p.prokind='f' AND p.prorettype <> 'trigger'::regtype
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND pg_get_functiondef(p.oid) ~* 'insert into|update .* set|delete from'
    AND pg_get_functiondef(p.oid) !~* 'auth\\.uid\\(\\) is null|no autenticado|fn_user_rol|fn_tiene_permiso'
    AND p.proname <> ALL($1)
  ORDER BY p.proname`, [Object.keys(P0)])).rows
sql += `\n\n-- ═══ P1/P2 · cierre de superficie anónima (endurecimiento por-fn en Fase 1) ═══\n`
for (const r of p1p2) {
  if (ALLOW.has(r.proname)) { sql += `-- (allowlist QR) ${r.proname}\n`; continue }
  if (SERVICE_ROLE.has(r.proname)) {
    // Solo la edge function (service_role): NO authenticated (ningún usuario final la llama).
    sql += `REVOKE EXECUTE ON FUNCTION public.${r.proname}(${r.args}) FROM anon, authenticated, PUBLIC;\n`
    sql += `GRANT  EXECUTE ON FUNCTION public.${r.proname}(${r.args}) TO service_role;  -- solo edge function GPS (documentado)\n`
    continue
  }
  sql += `REVOKE EXECUTE ON FUNCTION public.${r.proname}(${r.args}) FROM anon, PUBLIC;\n`
  sql += `GRANT  EXECUTE ON FUNCTION public.${r.proname}(${r.args}) TO authenticated;\n`
}

// ── Verificación ────────────────────────────────────────────────────────────
sql += `
-- ── Verificación (aborta si algo quedó abierto o mal grant) ─────────────────
DO $$
DECLARE v_anon INT; v_b_auth INT;
BEGIN
    -- Ninguna P0/P1/P2 (salvo allowlist) ejecutable por anon.
    SELECT count(*) INTO v_anon
      FROM pg_proc p JOIN pg_namespace nsp ON nsp.oid=p.pronamespace AND nsp.nspname='public'
     WHERE p.prosecdef AND p.prokind='f' AND p.prorettype <> 'trigger'::regtype
       AND has_function_privilege('anon', p.oid, 'EXECUTE')
       AND pg_get_functiondef(p.oid) ~* 'insert into|update .* set|delete from'
       AND pg_get_functiondef(p.oid) !~* 'auth\\.uid\\(\\) is null|no autenticado|fn_user_rol|fn_tiene_permiso'
       AND p.proname NOT IN ('rpc_guardar_checklist_publico','rpc_checklist_cliente_guardar');
    IF v_anon > 0 THEN RAISE EXCEPTION 'MIG189: % funciones de escritura siguen anónimas', v_anon; END IF;

    -- Grupo B no debe ser ejecutable por authenticated.
    SELECT count(*) INTO v_b_auth
      FROM pg_proc p JOIN pg_namespace nsp ON nsp.oid=p.pronamespace AND nsp.nspname='public'
     WHERE p.proname IN (${Object.entries(P0).filter(([,c])=>c.grupo==='B').map(([n])=>`'${n}'`).join(',')})
       AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
    IF v_b_auth > 0 THEN RAISE EXCEPTION 'MIG189: % funciones internas siguen ejecutables por authenticated', v_b_auth; END IF;

    RAISE NOTICE 'MIG189 OK: P0 con guard/interno, superficie anónima cerrada.';
END $$;

SELECT 'MIG189 v2 aplicada' AS resultado;
`

writeFileSync('C:/Users/Manuel Olivares/sicom-iceo/database/production_run/189_fase01_revocar_anon_escritura.sql', sql)
writeFileSync('C:/Users/Manuel Olivares/sicom-iceo/database/preprod/matriz_p0.json', JSON.stringify(matriz, null, 2))
console.log('189 v2 generada. Grupo A:', matriz.filter(m=>m.grupo==='A').length, 'Grupo B:', matriz.filter(m=>m.grupo==='B').length, 'P1/P2 revocadas:', p1p2.length - 2)
await c.end()
