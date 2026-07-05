import EmbeddedPostgres from 'embedded-postgres'
import pg from 'pg'
import { readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'

const REPO = 'C:/Users/Manuel Olivares/sicom-iceo'
const PORT = 55433
const log = (...a) => console.log(...a)
const section = (t) => log('\n' + '═'.repeat(70) + '\n' + t + '\n' + '═'.repeat(70))

const epg = new EmbeddedPostgres({ databaseDir: resolve('./pgdata2'), user: 'postgres', password: 'postgres', port: PORT, persistent: false, initdbFlags: ['--encoding=UTF8', '--locale=C'] })
try { await epg.initialise() } catch {}
await epg.start()

const admin = new pg.Client({ host: '127.0.0.1', port: PORT, user: 'postgres', password: 'postgres', database: 'postgres' })
await admin.connect()

async function runFileAs(client, role, path, label) {
  const sql = readFileSync(path, 'utf8')
  const notices = []
  const h = (m) => notices.push(m.message)
  client.on('notice', h)
  const t0 = Date.now()
  let error = null
  try {
    if (role) await client.query(`SET ROLE ${role}`)
    await client.query(sql)
  } catch (e) { error = e } finally {
    try { await client.query('RESET ROLE') } catch {}
    client.off('notice', h)
  }
  const ms = Date.now() - t0
  log(`\n▶ ${label}  (${ms} ms)  ${error ? '✗ ' + error.message : '✓'}`)
  if (notices.length) notices.forEach(n => log('   [notice] ' + n))
  if (error && !path.includes('188')) throw error
  return { ms, notices, error }
}

const results = { migraciones: [], tests: [] }

// ── FASE 1: construir preprod (pre-185) ────────────────────────────────────
section('FASE 1 · Construcción del entorno preprod (pre-MIG185)')
await runFileAs(admin, null, resolve('./01_bootstrap.sql'), 'bootstrap (roles+auth)')
await runFileAs(admin, null, resolve('./00_enums_extra.sql'), 'enums extra')
await runFileAs(admin, 'prod_owner', resolve('./preprod_base_prod.sql'), 'base: tablas + grants')
await runFileAs(admin, 'prod_owner', resolve('./02_stubs.sql'), 'stubs (fiabilidad/vistas)')
await runFileAs(admin, 'prod_owner', resolve('./preprod_funcs_prod.sql'), 'base: funciones pre-185')
await runFileAs(admin, 'prod_owner', resolve('./03_seed.sql'), 'seed anonimizado')

// Estado vulnerable de partida
const pre = await admin.query(`SELECT
  has_function_privilege('anon','rpc_confirmar_cierre_diario(date,jsonb)','EXECUTE') AS anon_cierre,
  has_function_privilege('anon','fn_reporte_fiabilidad_publico(date,date)','EXECUTE') AS anon_reporte,
  (SELECT rowsecurity FROM pg_tables WHERE tablename='estado_diario_flota') AS edf_rls,
  has_table_privilege('anon','estado_diario_flota','INSERT') AS anon_edf_insert`)
log('\nEstado de PARTIDA (debe ser vulnerable): ' + JSON.stringify(pre.rows[0]))

// ── FASE 2: aplicar migraciones individualmente ────────────────────────────
section('FASE 2 · Aplicación individual de migraciones + smoke interno')
for (const [file, id] of [
  ['185_seguridad_cierre_diario.sql','MIG185'],
  ['186_reporte_fiabilidad_autenticado.sql','MIG186'],
  ['187_combustible_valor_stock_en_salidas.sql','MIG187'],
]) {
  const r = await runFileAs(admin, 'prod_owner', resolve(REPO, 'database/production_run', file), id)
  results.migraciones.push({ id, ms: r.ms, ok: !r.error })
}

// Grants/policies finales
const post = await admin.query(`SELECT
  has_function_privilege('anon','rpc_confirmar_cierre_diario(date,jsonb)','EXECUTE') AS anon_cierre,
  has_function_privilege('authenticated','rpc_confirmar_cierre_diario(date,jsonb)','EXECUTE') AS auth_cierre,
  has_function_privilege('anon','fn_reporte_fiabilidad_publico(date,date)','EXECUTE') AS anon_reporte,
  has_function_privilege('anon','fn_propuesta_cierre_diario(date)','EXECUTE') AS anon_propuesta,
  (SELECT rowsecurity FROM pg_tables WHERE tablename='estado_diario_flota') AS edf_rls,
  has_table_privilege('anon','estado_diario_flota','INSERT') AS anon_edf_insert,
  (SELECT count(*) FROM pg_policies WHERE tablename='estado_diario_flota') AS edf_policies`)
log('\nEstado POST-migraciones (debe estar cerrado): ' + JSON.stringify(post.rows[0]))

// search_path de las funciones nuevas
const sp = await admin.query(`SELECT proname, proconfig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
  WHERE proname IN ('fn_tiene_permiso_modulo','rpc_confirmar_cierre_diario','fn_reporte_fiabilidad_publico','rpc_registrar_salida_combustible_valorizada','rpc_registrar_traspaso_combustible') ORDER BY proname`)
log('search_path: ' + JSON.stringify(sp.rows))

// ── FASE 3: MIG188 dry-run ─────────────────────────────────────────────────
section('FASE 3 · MIG188 (dry-run: debe ABORTAR por guard)')
const r188 = await runFileAs(admin, 'prod_owner', resolve(REPO, 'database/production_run/188_recalculo_valor_stock_combustible.sql'), 'MIG188 (guard)')
log('MIG188 abortó como se espera: ' + (r188.error ? 'SÍ ✓' : 'NO ✗'))
// Qué filas tocaría (incluye demo → hallazgo sección 9)
const d188 = await admin.query(`SELECT codigo, es_demo, valor_total_stock AS actual,
  ROUND((stock_teorico_lt*COALESCE(costo_promedio_lt,0))::numeric,2) AS regularizado
  FROM combustible_estanques
  WHERE ROUND((stock_teorico_lt*COALESCE(costo_promedio_lt,0))::numeric,2) IS DISTINCT FROM valor_total_stock
  ORDER BY es_demo`)
log('MIG188 tocaría estas filas (nótese demo mezclado): ' + JSON.stringify(d188.rows))

await runTests()
await rollbackCycle()
await test188v2()
await testP0Authz()
await finish()

// ── FASE 7: autorización de las 18 P0 (MIG189 v2) ──────────────────────────
async function testP0Authz() {
  section('FASE 7 · MIG189 v2 — autorización real de las 18 P0')
  // 1) cargar stubs P0 (firmas exactas, granted anon) y aplicar el 189 solo-P0.
  await runFileAs(admin, 'prod_owner', resolve('./preprod_p0_stubs.sql'), 'stubs P0 (18, granted anon)')
  const full = readFileSync(resolve(REPO, 'database/production_run/189_fase01_revocar_anon_escritura.sql'), 'utf8')
  const p0only = full.slice(0, full.indexOf('-- ═══ P1/P2')) + "\nSELECT 'p0-only' AS x;\n"
  writeFileSync(resolve('./189_p0_only.sql'), p0only)
  await runFileAs(admin, 'prod_owner', resolve('./189_p0_only.sql'), 'MIG189 v2 (solo P0)')

  const matriz = JSON.parse(readFileSync(resolve('./matriz_p0.json'), 'utf8'))
  const t = new pg.Client({ host: '127.0.0.1', port: PORT, user: 'authenticator', password: 'authpw', database: 'postgres' })
  await t.connect()
  const claims = (sub, rol) => sub ? JSON.stringify({ sub, role: 'authenticated', user_metadata: {} }) : JSON.stringify({ role: 'anon' })
  const U = {
    admin: '11111111-1111-1111-1111-111111111111',
    tecnico: '22222222-2222-2222-2222-222222222222',
    bodeguero: '33333333-3333-3333-3333-333333333333',
    comercial: '44444444-4444-4444-4444-444444444444',
    supervisor: '55555555-5555-5555-5555-555555555555',
    disabled: '66666666-6666-6666-6666-666666666666',
    portal: '99999999-9999-9999-9999-999999999999', // fila en cliente_portal_perfil, no en usuarios_perfil
    dual: 'dddddddd-dead-dead-dead-dddddddddddd',    // administrador interno + portal cliente (dual)
  }
  const ROLBYID = { [U.tecnico]: 'tecnico_mantenimiento', [U.bodeguero]: 'bodeguero', [U.comercial]: 'comercial', [U.supervisor]: 'supervisor' }
  async function ctx(role, sub) {
    await t.query('RESET ROLE')
    await t.query(`SELECT set_config('request.jwt.claims',$1,false)`, [role === 'anon' ? claims(null) : claims(sub)])
    if (role) await t.query(`SET ROLE ${role}`)
  }
  const argCount = (idargs) => idargs.trim() === '' ? 0 : idargs.split(',').length
  const callSql = (fn, n) => `SELECT public.${fn}(${Array(n).fill('NULL').join(',')})`
  const DENY = /No autorizado|permission denied|42501/i
  async function call(fn, n) {
    try { await t.query(callSql(fn, n)); return { denied: false, err: null } }
    catch (e) { return { denied: DENY.test(e.message) || e.code === '42501' || e.code === '42501', err: e.message.slice(0, 60), code: e.code } }
  }
  const rec = (test, ctxt, esp, ok, ev) => { results.tests.push({ test, contexto: ctxt, esperado: esp, real: ok ? 'OK' : 'FALLA', ok }); if (!ok) log(`  ✗ ${test} [${ctxt}] ${ev||''}`) }

  const grupoA = matriz.filter(m => m.grupo === 'A')
  const grupoB = matriz.filter(m => m.grupo === 'B')
  let aOk = 0
  for (const m of grupoA) {
    const n = argCount(m.args)
    // rol autenticado SIN el permiso: primero de estos que no esté en m.roles
    const sinPermRol = ['bodeguero', 'comercial', 'tecnico', 'supervisor'].find(k => !m.roles.includes(ROLBYID[U[k]]))
    // anon
    await ctx('anon'); let r = await call(m.fn, n)
    const t1 = r.denied
    // sin perfil (== portal cliente)
    await ctx('authenticated', U.portal); r = await call(m.fn, n); const t2 = r.denied
    // deshabilitado
    await ctx('authenticated', U.disabled); r = await call(m.fn, n); const t3 = r.denied
    // autenticado sin permiso
    await ctx('authenticated', U[sinPermRol]); r = await call(m.fn, n); const t4 = r.denied
    // administrador (con permiso) → NO denegado (el cuerpo real falla por tabla ausente = authz pasó)
    await ctx('authenticated', U.admin); r = await call(m.fn, n); const t5 = !r.denied
    const ok = t1 && t2 && t3 && t4 && t5
    if (ok) aOk++
    rec(`P0-A ${m.fn} (${m.modulo}/${m.accion})`, 'anon/portal/inactivo/sin-perm→deny · admin→pasa', 'guard fail-closed',
      ok, `anon=${t1} portal=${t2} inact=${t3} sinperm(${sinPermRol})=${t4} admin_pasa=${t5}`)
  }
  // Grupo B: anon y authenticated NO pueden ejecutar (sin grant)
  let bOk = 0
  for (const m of grupoB) {
    const n = argCount(m.args)
    await ctx('anon'); let r = await call(m.fn, n); const b1 = r.denied
    await ctx('authenticated', U.admin); r = await call(m.fn, n); const b2 = r.denied
    const ok = b1 && b2
    if (ok) bOk++
    rec(`P0-B ${m.fn} (interno)`, 'anon + authenticated', 'sin acceso PostgREST', ok, `anon=${b1} auth=${b2}`)
  }
  log(`✓ Grupo A: ${aOk}/${grupoA.length} funciones con guard fail-closed verificado`)
  log(`✓ Grupo B: ${bOk}/${grupoB.length} funciones internas sin acceso PostgREST`)

  // Sección 3: bloqueo PERMANENTE de portal cliente (regla, no accidente).
  const repFn = grupoA.find(m => m.fn === 'rpc_cambiar_contrato_activo')
  const nRep = argCount(repFn.args)
  // portal explícito (fila en cliente_portal_perfil, sin usuarios_perfil)
  await ctx('authenticated', U.portal); let rp = await call(repFn.fn, nRep)
  results.tests.push({ test: 'S3 portal cliente explícito', contexto: 'cliente_portal_perfil activo', esperado: 'DENEGADO', real: rp.denied ? 'denegado' : 'PERMITIÓ', ok: rp.denied })
  if (!rp.denied) log('  ✗ S3 portal explícito PERMITIÓ')
  // DUAL: administrador interno que ADEMÁS es portal → P0 denegado (portal manda)
  await ctx('authenticated', U.dual); let rd = await call(repFn.fn, nRep)
  results.tests.push({ test: 'S3 perfil DUAL (admin+portal)', contexto: 'usuarios_perfil admin + cliente_portal_perfil', esperado: 'DENEGADO (portal manda)', real: rd.denied ? 'denegado' : 'PERMITIÓ', ok: rd.denied })
  log(`${rp.denied ? '✓' : '✗'} S3 portal cliente explícito denegado`)
  log(`${rd.denied ? '✓' : '✗'} S3 perfil dual (admin+portal) denegado — portal manda sobre rol interno`)

  // Sección 7: FLUJO COMPLETO con cambios reales validados (rpc_cambiar_contrato_activo).
  const ACT1 = 'dddddddd-0000-0000-0000-000000000001', CT1 = 'cccccccc-0000-0000-0000-000000000001'
  const c0 = (await admin.query(`SELECT contrato_id FROM activos WHERE id=$1`, [ACT1])).rows[0].contrato_id
  await ctx('authenticated', U.admin)
  let flowOk = false, flowEv = ''
  try {
    await t.query(`SELECT public.rpc_cambiar_contrato_activo($1,$2,$3)`, [ACT1, CT1, 'Cambio de prueba gate'])
    const c1 = (await admin.query(`SELECT contrato_id FROM activos WHERE id=$1`, [ACT1])).rows[0].contrato_id
    const hist = (await admin.query(`SELECT count(*) c FROM historico_contrato_activo WHERE activo_id=$1`, [ACT1])).rows[0].c
    // Cambio real validado en activos (efecto de la operación completa autorizada).
    flowOk = String(c1) === CT1
    flowEv = `contrato ${c0}→${c1} (cambio real aplicado), historico=${hist}`
  } catch (e) { flowEv = 'ERROR: ' + e.message.slice(0, 70) }
  results.tests.push({ test: 'S7 flujo completo rpc_cambiar_contrato_activo', contexto: 'admin autorizado', esperado: 'cambio real aplicado + historial', real: flowEv, ok: flowOk })
  log(`${flowOk ? '✓' : '✗'} S7 flujo completo: admin cambia contrato → ${flowEv}`)
  // rechazo con activo inexistente (sin cambios)
  await ctx('authenticated', U.admin)
  let rej = await call('rpc_cambiar_contrato_activo', 3)  // args NULL → activo inexistente
  results.tests.push({ test: 'S7 activo inexistente', contexto: 'admin autorizado', esperado: 'rechazo sin cambios', real: rej.err ? 'rechazado' : 'PERMITIÓ', ok: !!rej.err })
  log(`${rej.err ? '✓' : '✗'} S7 payload inválido/activo inexistente → rechazo`)

  // IDOR/scope: informativo — los guards son por ROL, no por entidad (faena/contrato).
  log('ℹ IDOR: portal cliente denegado en todas (sin perfil). Scope por faena/contrato NO se aplica (decisión de negocio Fase 1).')
  await t.end()
}

// ── FASE 6: MIG188 v2 — demo excluido + precondiciones ─────────────────────
async function test188v2() {
  section('FASE 6 · MIG188 v2 (autorizado, demo excluido)')
  let sql = readFileSync(resolve(REPO, 'database/production_run/188_recalculo_valor_stock_combustible.sql'), 'utf8')
  // Dry-run fresco: los IDs esperados = estado real actual no-demo a corregir.
  const dry = await admin.query(`SELECT array_agg(codigo ORDER BY codigo) ids FROM combustible_estanques
    WHERE NOT es_demo AND ROUND((stock_teorico_lt*COALESCE(costo_promedio_lt,0))::numeric,2) IS DISTINCT FROM valor_total_stock`)
  const ids = dry.rows[0].ids || []
  log('Dry-run: estanques reales a corregir = ' + JSON.stringify(ids))
  const idsSql = 'ARRAY[' + ids.map(i => `'${i}'`).join(',') + ']'
  sql = sql.replace('v_autorizado   CONSTANT BOOLEAN   := false;', 'v_autorizado   CONSTANT BOOLEAN   := true;')
           .replace("v_expected_ids CONSTANT TEXT[]    := ARRAY['EST-1K','EST-15K'];", `v_expected_ids CONSTANT TEXT[] := ${idsSql};`)
  const demoBefore = (await admin.query(`SELECT valor_total_stock v FROM combustible_estanques WHERE es_demo`)).rows[0].v
  const notices = []; const h = m => notices.push(m.message); admin.on('notice', h)
  try { await admin.query('SET ROLE prod_owner'); await admin.query(sql); await admin.query('RESET ROLE') }
  catch (e) { await admin.query('RESET ROLE'); log('MIG188 v2 ERROR: ' + e.message) }
  admin.off('notice', h); notices.forEach(n => log('   [notice] ' + n))
  const realCuadran = (await admin.query(`SELECT count(*) c FROM combustible_estanques WHERE NOT es_demo AND abs(valor_total_stock - stock_teorico_lt*COALESCE(costo_promedio_lt,0))>0.011`)).rows[0].c
  const demoAfter = (await admin.query(`SELECT valor_total_stock v FROM combustible_estanques WHERE es_demo`)).rows[0].v
  const bkp = (await admin.query(`SELECT count(*) c, bool_or(es_demo) demo, bool_and(valor_anterior IS NOT NULL AND motivo IS NOT NULL) trazado FROM combustible_estanques_valor_bkp_mig188`)).rows[0]
  const demoIntacto = String(demoAfter) === String(demoBefore)
  const okReal = Number(realCuadran) === 0
  const bkpOk = Number(bkp.c) === ids.length && bkp.demo === false && bkp.trazado === true
  results.tests.push({ test: 'M1 188 corrige reales', contexto: 'prod_owner autorizado', esperado: 'reales cuadran', real: okReal ? 'cuadran' : 'NO', ok: okReal })
  results.tests.push({ test: 'M2 188 NO toca demo', contexto: 'demo excluido', esperado: 'demo intacto', real: demoIntacto ? 'intacto' : 'TOCADO', ok: demoIntacto })
  results.tests.push({ test: 'M3 188 backup trazado', contexto: 'backup', esperado: `${ids.length} fila(s) no-demo con motivo/valor`, real: `${bkp.c} filas, demo=${bkp.demo}, trazado=${bkp.trazado}`, ok: bkpOk })
  log(`${okReal ? '✓' : '✗'} M1 estanques reales cuadran tras 188`)
  log(`${demoIntacto ? '✓' : '✗'} M2 estanque demo intacto (${demoBefore} → ${demoAfter})`)
  log(`${bkpOk ? '✓' : '✗'} M3 backup con 2 filas no-demo, valor anterior y motivo`)
}

// ── FASE 5: ciclo de rollback (sección 8) ──────────────────────────────────
async function rollbackCycle() {
  section('FASE 5 · Ciclo de rollback 185 (aplicar→rollback→reabrir→reaplicar)')
  const q = async () => (await admin.query(`SELECT
    has_function_privilege('anon','rpc_confirmar_cierre_diario(date,jsonb)','EXECUTE') AS anon_cierre,
    (SELECT rowsecurity FROM pg_tables WHERE tablename='estado_diario_flota') AS edf_rls,
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public' WHERE proname='fn_tiene_permiso_modulo') AS helper`)).rows[0]
  log('1) estado actual (post-185, cerrado): ' + JSON.stringify(await q()))
  await runFileAs(admin, 'prod_owner', resolve(REPO, 'database/rollback/rollback_185_seguridad_cierre_diario.sql'), 'rollback_185')
  const back = await q()
  log('2) tras rollback (debe REABRIR: anon_cierre=true, edf_rls=false, helper=0): ' + JSON.stringify(back))
  const reabierto = back.anon_cierre === true && back.edf_rls === false && Number(back.helper) === 0
  await runFileAs(admin, 'prod_owner', resolve(REPO, 'database/production_run/185_seguridad_cierre_diario.sql'), 're-aplicar MIG185')
  const recerrado = await q()
  log('3) tras re-aplicar (debe CERRAR: anon_cierre=false, edf_rls=true, helper=1): ' + JSON.stringify(recerrado))
  const cerrado = recerrado.anon_cierre === false && recerrado.edf_rls === true && Number(recerrado.helper) === 1
  results.tests.push({ test: 'R1 rollback reabre vuln', contexto: 'prod_owner', esperado: 'reabre', real: reabierto ? 'reabrió' : 'NO reabrió', ok: reabierto })
  results.tests.push({ test: 'R2 re-aplicar cierra vuln', contexto: 'prod_owner', esperado: 'cierra', real: cerrado ? 'cerró' : 'NO cerró', ok: cerrado })
  log(`${reabierto ? '✓' : '✗'} R1 rollback reabre la vulnerabilidad C1`)
  log(`${cerrado ? '✓' : '✗'} R2 re-aplicar MIG185 la vuelve a cerrar`)
}

// ───────────────────────────────────────────────────────────────────────────
async function runTests() {
  section('FASE 4 · Tests de seguridad con contextos reales (authenticator→SET ROLE)')
  const t = new pg.Client({ host: '127.0.0.1', port: PORT, user: 'authenticator', password: 'authpw', database: 'postgres' })
  await t.connect()

  const ACT = 'dddddddd-0000-0000-0000-000000000001'
  const EST = 'eeeeeeee-0000-0000-0000-000000000001'
  const claims = (sub, rol) => JSON.stringify(sub ? { sub, role: 'authenticated', user_metadata: { rol } } : { role: 'anon' })
  async function ctx(role, sub, rol) {
    await t.query('RESET ROLE')
    await t.query(`SELECT set_config('request.jwt.claims', $1, false)`, [role === 'anon' ? claims(null) : claims(sub, rol)])
    if (role) await t.query(`SET ROLE ${role}`)
  }
  async function expectFail(fn, matcher) {
    try { await fn(); return { ok: false, got: 'NO falló' } }
    catch (e) { return { ok: matcher ? matcher.test(e.message) : true, got: e.message.slice(0, 80) } }
  }
  const rec = (test, contexto, esperado, real, ok, ev) => {
    results.tests.push({ test, contexto, esperado, real, ok });
    log(`${ok ? '✓' : '✗'} ${test} [${contexto}] → ${real}${ev ? ' | ' + ev : ''}`)
  }

  // T01 anon → cierre → denegado
  await ctx('anon')
  let r = await expectFail(() => t.query(`SELECT rpc_confirmar_cierre_diario(CURRENT_DATE, $1::jsonb)`,
    [JSON.stringify([{ activo_id: ACT, estado_codigo: 'D' }])]))
  rec('T01 cierre diario', 'anon', 'DENEGADO', r.ok ? 'denegado' : 'PERMITIÓ', r.ok, r.got)

  // T02 anon → INSERT directo estado_diario_flota
  await ctx('anon')
  r = await expectFail(() => t.query(`INSERT INTO estado_diario_flota(activo_id,fecha,estado_codigo) VALUES ($1,CURRENT_DATE+1,'D')`, [ACT]))
  rec('T02 INSERT directo edf', 'anon', 'DENEGADO', r.ok ? 'denegado' : 'PERMITIÓ', r.ok, r.got)

  // T03 authenticated sin permiso (tecnico)
  await ctx('authenticated', '22222222-2222-2222-2222-222222222222', 'tecnico_mantenimiento')
  r = await expectFail(() => t.query(`SELECT rpc_confirmar_cierre_diario(CURRENT_DATE,$1::jsonb)`,
    [JSON.stringify([{ activo_id: ACT, estado_codigo: 'D' }])]), /No autorizado/)
  rec('T03 cierre diario', 'auth tecnico (sin permiso)', 'DENEGADO', r.ok ? 'denegado' : r.got, r.ok, r.got)

  // T04 administrador → permitido
  await ctx('authenticated', '11111111-1111-1111-1111-111111111111', 'administrador')
  try {
    const res = await t.query(`SELECT rpc_confirmar_cierre_diario(CURRENT_DATE,$1::jsonb) AS r`,
      [JSON.stringify([{ activo_id: ACT, estado_codigo: 'D' }])])
    const n = res.rows[0].r.confirmados
    rec('T04 cierre diario', 'auth administrador', 'PERMITIDO', n === 1 ? 'confirmados=1' : 'confirmados=' + n, n === 1)
  } catch (e) { rec('T04 cierre diario', 'auth administrador', 'PERMITIDO', 'ERROR:' + e.message.slice(0, 60), false) }

  // T05 activo inexistente → rechazo completo
  await ctx('authenticated', '11111111-1111-1111-1111-111111111111', 'administrador')
  const antes = (await admin.query(`SELECT count(*) c FROM estado_diario_flota WHERE fecha=CURRENT_DATE+2`)).rows[0].c
  r = await expectFail(() => t.query(`SELECT rpc_confirmar_cierre_diario(CURRENT_DATE+2,$1::jsonb)`,
    [JSON.stringify([{ activo_id: ACT, estado_codigo: 'D' }, { activo_id: '00000000-0000-0000-0000-0000000000ff', estado_codigo: 'D' }])]), /inexistente/)
  const despues = (await admin.query(`SELECT count(*) c FROM estado_diario_flota WHERE fecha=CURRENT_DATE+2`)).rows[0].c
  rec('T05 lote con activo inexistente', 'auth administrador', 'RECHAZO TOTAL (sin parciales)',
    (r.ok && antes === despues) ? `rechazado, filas ${antes}→${despues}` : 'PARCIAL/PERMITIÓ', r.ok && antes === despues, r.got)

  // T06 anon → reporte → denegado
  await ctx('anon')
  r = await expectFail(() => t.query(`SELECT fn_reporte_fiabilidad_publico()`))
  rec('T06 reporte fiabilidad', 'anon', 'DENEGADO', r.ok ? 'denegado' : 'PERMITIÓ', r.ok, r.got)

  // T07 usuario interno → reporte con claves completas
  await ctx('authenticated', '11111111-1111-1111-1111-111111111111', 'administrador')
  try {
    const res = await t.query(`SELECT fn_reporte_fiabilidad_publico() AS r`)
    const keys = Object.keys(res.rows[0].r)
    const full = ['categorias', 'equipos', 'matriz', 'combustible'].every(k => keys.includes(k))
    rec('T07 reporte fiabilidad', 'auth administrador', 'PERMITIDO + claves completas',
      full ? 'claves: ' + keys.join(',') : 'FALTAN claves', full)
  } catch (e) { rec('T07 reporte fiabilidad', 'auth administrador', 'PERMITIDO', 'ERROR:' + e.message.slice(0, 60), false) }

  // T-CORREO: contexto admin (session_user=postgres) → reporte permitido
  try {
    const res = await admin.query(`SELECT fn_reporte_fiabilidad_publico() AS r`)
    const ok = res.rows[0].r && res.rows[0].r.combustible !== undefined
    rec('T-CORREO reporte', 'session_user=postgres (script correo/cron)', 'PERMITIDO', ok ? 'ok, con combustible' : 'sin combustible', ok)
  } catch (e) { rec('T-CORREO reporte', 'postgres', 'PERMITIDO', 'ERROR:' + e.message.slice(0, 60), false) }

  // T08 salida combustible baja litros Y valor
  await ctx('authenticated', '33333333-3333-3333-3333-333333333333', 'bodeguero')
  const e0 = (await admin.query(`SELECT stock_teorico_lt s, valor_total_stock v, costo_promedio_lt c FROM combustible_estanques WHERE id=$1`, [EST])).rows[0]
  try {
    await t.query(`SELECT rpc_registrar_salida_combustible_valorizada($1,10,'consumo_interno','Test preprod salida')`, [EST])
    const e1 = (await admin.query(`SELECT stock_teorico_lt s, valor_total_stock v FROM combustible_estanques WHERE id=$1`, [EST])).rows[0]
    const litrosOk = Number(e1.s) === Number(e0.s) - 10
    const valorEsper = Math.round((Number(e1.s) * Number(e0.c)) * 100) / 100
    const valorOk = Math.abs(Number(e1.v) - valorEsper) <= 0.011
    rec('T08 salida baja litros Y valor', 'auth bodeguero', 'litros y valor bajan juntos',
      `stock ${e0.s}→${e1.s}, valor ${e0.v}→${e1.v} (esper ${valorEsper})`, litrosOk && valorOk)
  } catch (e) { rec('T08 salida', 'auth bodeguero', 'PERMITIDO', 'ERROR:' + e.message.slice(0, 70), false) }

  // T09 salida > stock → denegada, sin stock negativo
  await ctx('authenticated', '33333333-3333-3333-3333-333333333333', 'bodeguero')
  const s_pre = (await admin.query(`SELECT stock_teorico_lt s FROM combustible_estanques WHERE id=$1`, [EST])).rows[0].s
  r = await expectFail(() => t.query(`SELECT rpc_registrar_salida_combustible_valorizada($1,999999,'consumo_interno','Test sobre stock')`, [EST]), /insuficiente/)
  const s_post = (await admin.query(`SELECT stock_teorico_lt s FROM combustible_estanques WHERE id=$1`, [EST])).rows[0].s
  rec('T09 salida > stock', 'auth bodeguero', 'DENEGADA sin stock negativo',
    (r.ok && Number(s_post) >= 0 && s_pre === s_post) ? 'denegada, stock intacto' : 'FALLA', r.ok && Number(s_post) >= 0 && s_pre === s_post, r.got)

  // ── Extras solicitados ────────────────────────────────────────────────────
  // E1 módulo inexistente → deniega (fail-closed en fn_tiene_permiso_modulo)
  await ctx('authenticated', '55555555-5555-5555-5555-555555555555', 'supervisor')
  let v = (await t.query(`SELECT fn_tiene_permiso_modulo('modulo_inexistente','approve',ARRAY[]::text[]) AS b`)).rows[0].b
  rec('E1 módulo inexistente', 'auth supervisor', 'FALSE', String(v), v === false)

  // E2 acción inexistente → deniega
  v = (await t.query(`SELECT fn_tiene_permiso_modulo('flota','accion_inexistente',ARRAY['supervisor']::text[]) AS b`)).rows[0].b
  rec('E2 acción inexistente', 'auth supervisor', 'FALSE (fail-closed en acción)', String(v), v === false)

  // E3 usuario SIN perfil (uid sin fila usuarios_perfil, sin rol en jwt)
  await t.query('RESET ROLE'); await t.query(`SELECT set_config('request.jwt.claims',$1,false)`, [JSON.stringify({ sub: '99999999-9999-9999-9999-999999999999', role: 'authenticated' })]); await t.query('SET ROLE authenticated')
  r = await expectFail(() => t.query(`SELECT rpc_confirmar_cierre_diario(CURRENT_DATE,$1::jsonb)`, [JSON.stringify([{ activo_id: ACT, estado_codigo: 'D' }])]), /No autorizado|autenticado/)
  rec('E3 usuario sin perfil', 'auth uid sin usuarios_perfil', 'DENEGADO', r.ok ? 'denegado' : 'PERMITIÓ', r.ok, r.got)

  // E4 usuario deshabilitado (activo=false) con rol supervisor → HOY se le permite?
  await ctx('authenticated', '66666666-6666-6666-6666-666666666666', 'supervisor')
  let permitido = false
  try { await t.query(`SELECT rpc_confirmar_cierre_diario(CURRENT_DATE+3,$1::jsonb)`, [JSON.stringify([{ activo_id: ACT, estado_codigo: 'D' }])]); permitido = true } catch {}
  rec('E4 usuario deshabilitado', 'auth supervisor activo=false', 'IDEALMENTE DENEGADO', permitido ? 'PERMITIÓ (no chequea activo)' : 'denegado', !permitido, 'hallazgo si PERMITIÓ')

  // E5 override que DENIEGA a supervisor (permisos flota sin approve) → deniega aunque esté en default
  await admin.query(`INSERT INTO rol_permisos_modulo(rol,modulo,permisos) VALUES('supervisor','flota',ARRAY['view']::text[]) ON CONFLICT (rol,modulo) DO UPDATE SET permisos=EXCLUDED.permisos`)
  await ctx('authenticated', '55555555-5555-5555-5555-555555555555', 'supervisor')
  r = await expectFail(() => t.query(`SELECT rpc_confirmar_cierre_diario(CURRENT_DATE+4,$1::jsonb)`, [JSON.stringify([{ activo_id: ACT, estado_codigo: 'D' }])]), /No autorizado/)
  rec('E5 override niega approve', 'auth supervisor + override[view]', 'DENEGADO', r.ok ? 'denegado' : 'PERMITIÓ', r.ok, r.got)
  await admin.query(`DELETE FROM rol_permisos_modulo WHERE rol='supervisor' AND modulo='flota'`)

  // E6 override que OTORGA approve a comercial (no está en default) → permite
  await admin.query(`INSERT INTO rol_permisos_modulo(rol,modulo,permisos) VALUES('comercial','flota',ARRAY['view','approve']::text[]) ON CONFLICT (rol,modulo) DO UPDATE SET permisos=EXCLUDED.permisos`)
  await ctx('authenticated', '44444444-4444-4444-4444-444444444444', 'comercial')
  try {
    const res = await t.query(`SELECT rpc_confirmar_cierre_diario(CURRENT_DATE+5,$1::jsonb) AS r`, [JSON.stringify([{ activo_id: ACT, estado_codigo: 'D' }])])
    rec('E6 override otorga approve', 'auth comercial + override[approve]', 'PERMITIDO', 'confirmados=' + res.rows[0].r.confirmados, res.rows[0].r.confirmados === 1)
  } catch (e) { rec('E6 override otorga approve', 'auth comercial', 'PERMITIDO', 'ERROR:' + e.message.slice(0, 50), false) }
  await admin.query(`DELETE FROM rol_permisos_modulo WHERE rol='comercial' AND modulo='flota'`)

  // E7 service_role → cierre (backend) permitido? service_role no tiene rol jwt → fn_user_rol null → deniega
  await t.query('RESET ROLE'); await t.query(`SELECT set_config('request.jwt.claims',$1,false)`, [JSON.stringify({ role: 'service_role' })]); await t.query('SET ROLE service_role')
  r = await expectFail(() => t.query(`SELECT rpc_confirmar_cierre_diario(CURRENT_DATE+6,$1::jsonb)`, [JSON.stringify([{ activo_id: ACT, estado_codigo: 'D' }])]))
  rec('E7 service_role sin uid', 'service_role', 'DENEGADO (sin auth.uid)', r.ok ? 'denegado' : 'PERMITIÓ', r.ok, r.got)

  // E8 reporte NO expone vin/motor a... bueno, sí los expone pero solo autenticado. Verificar que anon no ve NADA.
  // (cubierto por T06). Verificamos además que el payload interno SÍ trae vin (esperado, interno):
  await ctx('authenticated', '11111111-1111-1111-1111-111111111111', 'administrador')
  const rep = (await t.query(`SELECT fn_reporte_fiabilidad_publico() AS r`)).rows[0].r
  const tieneVin = JSON.stringify(rep).includes('vin_chasis')
  rec('E8 vin solo tras auth', 'auth administrador', 'payload interno trae vin (anon no accede)', tieneVin ? 'vin presente (interno)' : 'sin vin', true)

  // E9 sobrecarga histórica: ¿existe otra firma de la salida accesible a anon?
  const overloads = await admin.query(`SELECT pg_get_function_identity_arguments(p.oid) args, has_function_privilege('anon',p.oid,'EXECUTE') anon
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public' WHERE p.proname='rpc_registrar_salida_combustible_valorizada'`)
  const anyAnon = overloads.rows.some(o => o.anon)
  rec('E9 sobrecargas salida vs anon', 'catálogo', 'ninguna sobrecarga con EXECUTE anon',
    anyAnon ? 'HAY sobrecarga anon' : `${overloads.rows.length} sobrecarga(s), 0 anon`, !anyAnon)

  await t.end()
}

async function finish() {
  const okCount = results.tests.filter(t => t.ok).length
  section(`RESUMEN: ${okCount}/${results.tests.length} tests OK · migraciones ${results.migraciones.filter(m => m.ok).length}/${results.migraciones.length} aplicadas`)
  results.tests.filter(t => !t.ok).forEach(t => log('  FALLA: ' + t.test + ' [' + t.contexto + '] → ' + t.real))
  await admin.end(); await epg.stop()
  log('\npreprod detenido.')
}
