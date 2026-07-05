// Grupo B (7 internas) + GPS service_role + rollback MIG189, sobre esquema completo.
import pg from 'pg'
import { readFileSync } from 'node:fs'
const PORT=55435
const admin=new pg.Client({host:'127.0.0.1',port:PORT,user:'postgres',password:'postgres',database:'postgres'}); await admin.connect()
const t=new pg.Client({host:'127.0.0.1',port:PORT,user:'authenticator',password:'authpw',database:'postgres'}); await t.connect()
const ADMIN='11111111-1111-1111-1111-111111111111'
const log=(...a)=>console.log(...a)
const DENY=/No autorizado|permission denied|42501/i
async function ctx(role,sub){ await t.query('RESET ROLE'); await t.query(`SELECT set_config('request.jwt.claims',$1,false)`,[sub?JSON.stringify({sub,role}):JSON.stringify({role:'anon'})]); if(role) await t.query(`SET ROLE ${role}`) }
async function call(sql,p){ try{ await t.query(sql,p); return {denied:false} }catch(e){ return {denied:DENY.test(e.message)||e.code==='42501', err:e.message.slice(0,60)} } }

// ── Grupo B: anon + authenticated NO pueden ejecutar (sin acceso PostgREST) ──
log('── Grupo B (internas): anon + authenticated denegados ──')
const B=['generar_ots_preventivas','verificar_certificaciones','fn_auto_crear_planes_activo','fn_generar_nc_desde_checklist_ot','fn_generar_nc_desde_v3_ot','fn_reconciliar_estado_ficha_desde_matriz','fn_reconciliar_comercial_ficha_desde_matriz']
let bOk=0
for(const fn of B){
  const n=(await admin.query(`SELECT pg_get_function_identity_arguments(p.oid) a FROM pg_proc p JOIN pg_namespace nn ON nn.oid=p.pronamespace AND nn.nspname='public' WHERE p.proname=$1`,[fn])).rows[0]
  const nn = n.a.trim()===''?0:n.a.split(',').length
  await ctx('anon'); const a=await call(`SELECT public.${fn}(${Array(nn).fill('NULL').join(',')})`)
  await ctx('authenticated',ADMIN); const au=await call(`SELECT public.${fn}(${Array(nn).fill('NULL').join(',')})`)
  const ok=a.denied&&au.denied; if(ok)bOk++
  log(`${ok?'✓':'✗'} ${fn.padEnd(42)} anon=${a.denied?'D':'!'} auth=${au.denied?'D':'!'}`)
}
log(`Grupo B denegaciones: ${bOk}/7`)

// ── Trigger real: fn_auto_crear_planes_activo se invoca por trigger (no roto) ──
{ const tg=(await admin.query(`SELECT count(*) c FROM pg_trigger WHERE tgname='trg_auto_planes_activo' AND NOT tgisinternal`)).rows[0].c
  // verificar_certificaciones ejecutable por admin (vía cron/postgres) pese al REVOKE
  let cronOk=false
  try{ await admin.query(`SELECT public.verificar_certificaciones()`); cronOk=true }catch(e){ cronOk = !/permission denied/.test(e.message) }
  log(`✓ trigger trg_auto_planes_activo presente=${tg==1?'sí':'no'}; verificar_certificaciones vía admin/cron ok=${cronOk}`)
}

// ── GPS: rpc_ingestar_gps_batch — anon/auth denegado, service_role permitido ──
log('\n── rpc_ingestar_gps_batch (edge GPS) ──')
{ const payload=JSON.stringify([])
  await ctx('anon'); const a=await call(`SELECT public.rpc_ingestar_gps_batch('Radicom',$1::jsonb)`,[payload])
  await ctx('authenticated',ADMIN); const au=await call(`SELECT public.rpc_ingestar_gps_batch('Radicom',$1::jsonb)`,[payload])
  await t.query('RESET ROLE'); await t.query(`SELECT set_config('request.jwt.claims',$1,false)`,[JSON.stringify({role:'service_role'})]); await t.query('SET ROLE service_role')
  const sv=await call(`SELECT public.rpc_ingestar_gps_batch('Radicom',$1::jsonb)`,[payload])
  log(`${a.denied?'✓':'✗'} anon denegado=${a.denied}`)
  log(`${au.denied?'✓':'✗'} authenticated denegado=${au.denied}`)
  log(`${!sv.denied?'✓':'✗'} service_role permitido=${!sv.denied} ${sv.err||''}`)
}

// ── Rollback MIG189: aplicar rollback → reabre → reaplicar → cierra ──
log('\n── Ciclo rollback MIG189 v2 ──')
const chkAnon=async()=> (await admin.query(`SELECT has_function_privilege('anon','public.rpc_cambiar_contrato_activo(uuid,uuid,text)','EXECUTE') a, (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public' WHERE proname='fn_tiene_permiso_modulo') helper`)).rows[0]
const pre=await chkAnon()
await admin.query(readFileSync('C:/Users/Manuel Olivares/sicom-iceo/database/rollback/rollback_189_fase01.sql','utf8'))
const back=await chkAnon()
await admin.query(readFileSync('C:/Users/Manuel Olivares/sicom-iceo/database/production_run/189_fase01_revocar_anon_escritura.sql','utf8'))
const re=await chkAnon()
const rbOk = pre.a===false && back.a===true && re.a===false
log(`${rbOk?'✓':'✗'} pre(anon=${pre.a}) → rollback(anon=${back.a}, reabre) → reaplicar(anon=${re.a}, cierra)`)

await t.end(); await admin.end()
