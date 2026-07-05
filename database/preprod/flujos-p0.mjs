// Gate final: bundle + flujos completos de las 11 P0 sobre el ESQUEMA COMPLETO
// restaurado (datos reales anonimizados). Puerto 55435.
import pg from 'pg'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
const REPO = 'C:/Users/Manuel Olivares/sicom-iceo'
const PORT = 55435
const admin = new pg.Client({ host: '127.0.0.1', port: PORT, user: 'postgres', password: 'postgres', database: 'postgres' })
await admin.connect()
const log = (...a) => console.log(...a)
const results = []

// ── 1. Seed usuarios de prueba (auth.users + usuarios_perfil + portal + dual) ──
const U = { admin:'11111111-1111-1111-1111-111111111111', tecnico:'22222222-2222-2222-2222-222222222222',
  bodeguero:'33333333-3333-3333-3333-333333333333', comercial:'44444444-4444-4444-4444-444444444444',
  supervisor:'55555555-5555-5555-5555-555555555555', disabled:'66666666-6666-6666-6666-666666666666',
  planificador:'77777777-7777-7777-7777-777777777777', portal:'99999999-9999-9999-9999-999999999999',
  noperfil:'a0000000-0000-0000-0000-0000000000ff', dual:'dddddddd-dead-dead-dead-dddddddddddd' }
const ROL = { [U.admin]:'administrador',[U.tecnico]:'tecnico_mantenimiento',[U.bodeguero]:'bodeguero',
  [U.comercial]:'comercial',[U.supervisor]:'supervisor',[U.disabled]:'supervisor',[U.planificador]:'planificador',[U.dual]:'administrador' }
for (const [k,id] of Object.entries(U)) await admin.query(`INSERT INTO auth.users(id,email) VALUES($1,$2) ON CONFLICT DO NOTHING`,[id,`${k}@test.local`])
for (const [id,rol] of Object.entries(ROL)) {
  const activo = id===U.disabled ? false : true
  await admin.query(`INSERT INTO public.usuarios_perfil(id,email,nombre_completo,rol,activo) VALUES($1,$2,$3,$4::rol_usuario_enum,$5)
    ON CONFLICT (id) DO UPDATE SET rol=EXCLUDED.rol, activo=EXCLUDED.activo`,[id,`${id.slice(0,8)}@test.local`,'Test',rol,activo])
}
await admin.query(`INSERT INTO public.cliente_portal_perfil(user_id,nombre_visible,empresa,activo) VALUES($1,'Portal','X',true),($2,'Dual','X',true) ON CONFLICT DO NOTHING`,[U.portal,U.dual])
log('Seed usuarios OK')

// ── 2. Aplicar bundle 185/186/187/189 (como postgres) con postvalidación ──
const BUNDLE = ['185_seguridad_cierre_diario.sql','186_reporte_fiabilidad_autenticado.sql','187_combustible_valor_stock_en_salidas.sql','189_fase01_revocar_anon_escritura.sql']
for (const f of BUNDLE) {
  const sql = readFileSync(resolve(REPO,'database/production_run',f),'utf8')
  await admin.query('BEGIN');
  try { await admin.query(sql); await admin.query('COMMIT'); log('▶ aplicada', f.slice(0,3)) }
  catch(e){ await admin.query('ROLLBACK'); log('✗ FALLO', f, e.message.slice(0,120)); process.exit(1) }
}
// postvalidación agregada
const pv = (await admin.query(`SELECT
  NOT has_function_privilege('anon','public.rpc_confirmar_cierre_diario(date,jsonb)','EXECUTE') AS cierre_cerrado,
  NOT has_function_privilege('anon','public.rpc_cambiar_contrato_activo(uuid,uuid,text)','EXECUTE') AS p0_cerrada,
  has_function_privilege('service_role','public.rpc_ingestar_gps_batch(text,jsonb)','EXECUTE') AS gps_svc,
  (SELECT rowsecurity FROM pg_tables WHERE tablename='estado_diario_flota') AS edf_rls`)).rows[0]
log('Postvalidación bundle:', JSON.stringify(pv))

// ── 3. Contexto de prueba (authenticator → SET ROLE) ──
const t = new pg.Client({ host:'127.0.0.1', port:PORT, user:'authenticator', password:'authpw', database:'postgres' })
await t.connect()
async function ctx(role, sub){ await t.query('RESET ROLE'); await t.query(`SELECT set_config('request.jwt.claims',$1,false)`,[sub?JSON.stringify({sub,role:'authenticated'}):JSON.stringify({role:'anon'})]); if(role) await t.query(`SET ROLE ${role}`) }
const DENY=/No autorizado|permission denied|42501/i
async function callRaw(sql, params){ try{ await t.query(sql,params); return {denied:false,err:null} } catch(e){ return {denied:DENY.test(e.message)||e.code==='42501', err:e.message.slice(0,70), code:e.code } } }
const nulls = n => Array(n).fill('NULL').join(',')

// arg counts de las 11 P0
const P0 = ['rpc_cambiar_contrato_activo','rpc_crear_ot','rpc_transicion_ot','rpc_cerrar_ot_supervisor','rpc_registrar_salida_inventario','rpc_confirmar_estado_dia','rpc_actualizar_metricas_activo','rpc_asignar_pauta','rpc_crear_auxiliar','rpc_generar_qr_activo','rpc_validar_sugerencia']
const argc = {}
for (const fn of P0){ const r=await admin.query(`SELECT pg_get_function_identity_arguments(p.oid) a FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public' WHERE p.proname=$1`,[fn]); argc[fn]= r.rows[0].a.trim()===''?0:r.rows[0].a.split(',').length }

// ── 4. Denegaciones (6 contextos) para las 11 P0 ──
log('\n── Denegaciones por función (anon/noperfil/inactivo/portal/dual/sin-permiso) ──')
const noPermRole = { rpc_cambiar_contrato_activo:'bodeguero', rpc_crear_ot:'bodeguero', rpc_transicion_ot:'bodeguero', rpc_cerrar_ot_supervisor:'tecnico', rpc_registrar_salida_inventario:'comercial', rpc_confirmar_estado_dia:'bodeguero', rpc_actualizar_metricas_activo:'bodeguero', rpc_asignar_pauta:'bodeguero', rpc_crear_auxiliar:'bodeguero', rpc_generar_qr_activo:'bodeguero', rpc_validar_sugerencia:'bodeguero' }
for (const fn of P0){
  const n=argc[fn]; const call=()=>callRaw(`SELECT public.${fn}(${nulls(n)})`)
  const ctxs=[['anon',null],['authenticated',U.noperfil],['authenticated',U.disabled],['authenticated',U.portal],['authenticated',U.dual],['authenticated',U[noPermRole[fn]]]]
  let allDenied=true, detail=[]
  for (const [role,sub] of ctxs){ await ctx(role,sub); const r=await call(); if(!r.denied) allDenied=false; detail.push(r.denied?'D':'!'+ (r.err||'')) }
  results.push({fn, dim:'denegaciones', ok:allDenied})
  log(`${allDenied?'✓':'✗'} ${fn.padEnd(32)} [${detail.join(' ')}]`)
}
await t.end(); await admin.end()
log('\nDenegaciones completas. (Flujos autorizados en flujos-p0-parte2)')
