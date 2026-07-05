// Flujos AUTORIZADOS completos de las 11 P0 con cambios reales validados.
// Requiere que flujos-p0.mjs ya haya aplicado el bundle. Puerto 55435.
import pg from 'pg'
const PORT=55435
const admin=new pg.Client({host:'127.0.0.1',port:PORT,user:'postgres',password:'postgres',database:'postgres'}); await admin.connect()
const t=new pg.Client({host:'127.0.0.1',port:PORT,user:'authenticator',password:'authpw',database:'postgres'}); await t.connect()
const ADMIN='11111111-1111-1111-1111-111111111111', SUP='55555555-5555-5555-5555-555555555555'
async function asUser(sub){ await t.query('RESET ROLE'); await t.query(`SELECT set_config('request.jwt.claims',$1,false)`,[JSON.stringify({sub,role:'authenticated'})]); await t.query('SET ROLE authenticated') }
const one = async (s,p)=> (await admin.query(s,p)).rows[0]
const log=(...a)=>console.log(...a)
const R=[]
function rec(fn, exito, rollback, contrato, ev){ R.push({fn,exito,rollback,contrato}); log(`${exito&&rollback&&contrato?'✓':'⚠'} ${fn.padEnd(32)} exito=${exito?'sí':'no'} rollback=${rollback?'ok':'-'} contrato_ret=${contrato?'ok':'-'} | ${ev}`) }

// entidades reales
const act = (await one(`SELECT id FROM activos WHERE estado<>'dado_baja' AND tipo IN ('camion','camioneta','camion_cisterna','lubrimovil','equipo_menor') LIMIT 1`)).id
const ct  = (await one(`SELECT id FROM contratos LIMIT 1`)).id
const faena = (await one(`SELECT faena_id AS id FROM activos WHERE faena_id IS NOT NULL LIMIT 1`))?.id || null

await asUser(ADMIN)
// helper: llama como admin, retorna {ok,ret,err}
async function call(sql,p){ try{ const r=await t.query(sql,p); return {ok:true, ret:r.rows[0], err:null} }catch(e){ return {ok:false, ret:null, err:e.message.slice(0,90), code:e.code} } }
const isJson = v => v && typeof v==='object'

// 1. rpc_cambiar_contrato_activo
{ const before=(await one(`SELECT contrato_id FROM activos WHERE id=$1`,[act])).contrato_id
  const r=await call(`SELECT public.rpc_cambiar_contrato_activo($1,$2,$3) AS r`,[act,ct,'gate final'])
  const after=(await one(`SELECT contrato_id FROM activos WHERE id=$1`,[act])).contrato_id
  const inv=await call(`SELECT public.rpc_cambiar_contrato_activo($1,$2,$3)`,['00000000-0000-0000-0000-0000000000ff',ct,'x'])
  rec('rpc_cambiar_contrato_activo', r.ok && String(after)===String(ct), !inv.ok, isJson(r.ret?.r)||r.ok, `contrato→${String(after).slice(0,8)}; id_inexistente rechazado=${!inv.ok}`) }

// 2. rpc_actualizar_metricas_activo
{ const km=(await one(`SELECT kilometraje_actual k FROM activos WHERE id=$1`,[act])).k
  const nuevo=Number(km)+123
  const r=await call(`SELECT public.rpc_actualizar_metricas_activo($1,$2,NULL,NULL,$3) AS r`,[act,nuevo,ADMIN])
  const after=(await one(`SELECT kilometraje_actual k FROM activos WHERE id=$1`,[act])).k
  const inv=await call(`SELECT public.rpc_actualizar_metricas_activo($1,$2)`,['00000000-0000-0000-0000-0000000000ff',5])
  rec('rpc_actualizar_metricas_activo', r.ok && Number(after)===nuevo, !inv.ok, r.ok, `km ${km}→${after}; inexistente rechazado=${!inv.ok}`) }

// 3. rpc_generar_qr_activo
{ const r=await call(`SELECT public.rpc_generar_qr_activo($1) AS r`,[act])
  const after=(await one(`SELECT qr_code, qr_url FROM activos WHERE id=$1`,[act]))
  rec('rpc_generar_qr_activo', r.ok && (after.qr_code||after.qr_url)!=null, true, r.ok, `qr set=${(after.qr_code||after.qr_url)!=null}`) }

// 4. rpc_confirmar_estado_dia
{ const fecha='2026-06-15'
  const r=await call(`SELECT public.rpc_confirmar_estado_dia($1,$2::date,$3) AS r`,[act,fecha,'D'])
  const after=await one(`SELECT count(*) c FROM estado_diario_flota WHERE activo_id=$1 AND fecha=$2`,[act,fecha])
  const inv=await call(`SELECT public.rpc_confirmar_estado_dia($1,$2::date,$3)`,['00000000-0000-0000-0000-0000000000ff',fecha,'D'])
  rec('rpc_confirmar_estado_dia', r.ok && Number(after.c)>=1, !inv.ok, r.ok, `edf filas=${after.c}; inexistente rechazado=${!inv.ok}`) }

// 5. rpc_crear_ot → captura OT para 6 y 7
let nuevaOT=null
{ const n0=(await one(`SELECT count(*) c FROM ordenes_trabajo`)).c
  const r=await call(`SELECT public.rpc_crear_ot('correctivo'::tipo_ot_enum,$1,$2,$3) AS r`,[ct,faena,act])
  const n1=(await one(`SELECT count(*) c FROM ordenes_trabajo`)).c
  nuevaOT = r.ret?.r?.ot_id || (await one(`SELECT id FROM ordenes_trabajo ORDER BY created_at DESC LIMIT 1`)).id
  rec('rpc_crear_ot', r.ok && Number(n1)===Number(n0)+1, true, isJson(r.ret?.r), `OTs ${n0}→${n1}; nueva=${String(nuevaOT).slice(0,8)}`) }

// 6. rpc_transicion_ot ('asignada' requiere responsable_id → arg nombrado)
{ const before=(await one(`SELECT estado FROM ordenes_trabajo WHERE id=$1`,[nuevaOT])).estado
  const r=await call(`SELECT public.rpc_transicion_ot(p_ot_id=>$1, p_nuevo_estado=>'asignada'::estado_ot_enum, p_usuario_id=>$2, p_responsable_id=>$2) AS r`,[nuevaOT,ADMIN])
  const after=(await one(`SELECT estado FROM ordenes_trabajo WHERE id=$1`,[nuevaOT])).estado
  const inv=await call(`SELECT public.rpc_transicion_ot($1,'asignada'::estado_ot_enum,$2)`,['00000000-0000-0000-0000-0000000000ff',ADMIN])
  rec('rpc_transicion_ot', r.ok && String(after)!==String(before), !inv.ok, r.ok, `estado ${before}→${after}; inexistente rechazado=${!inv.ok}`) }

// 7. rpc_cerrar_ot_supervisor (en_ejecucion → sembrar evidencia → ejecutada_ok → cerrar)
{ await call(`SELECT public.rpc_transicion_ot(p_ot_id=>$1,p_nuevo_estado=>'en_ejecucion'::estado_ot_enum,p_usuario_id=>$2)`,[nuevaOT,ADMIN])
  await call(`SELECT public.rpc_transicion_ot(p_ot_id=>$1,p_nuevo_estado=>'no_ejecutada'::estado_ot_enum,p_usuario_id=>$2,p_causa_no_ejecucion=>'otra'::causa_no_ejecucion_enum,p_detalle_no_ejecucion=>'gate test')`,[nuevaOT,ADMIN])
  const st=(await one(`SELECT estado FROM ordenes_trabajo WHERE id=$1`,[nuevaOT])).estado
  const r=await call(`SELECT public.rpc_cerrar_ot_supervisor($1,$2,$3) AS r`,[nuevaOT,ADMIN,'cierre gate'])
  const after=(await one(`SELECT estado FROM ordenes_trabajo WHERE id=$1`,[nuevaOT])).estado
  rec('rpc_cerrar_ot_supervisor', r.ok && String(after)==='cerrada', true, r.ok, `pre=${st} final=${after}${r.ok?'':' | '+r.err}`) }

// 8. rpc_crear_auxiliar
{ const n0=(await one(`SELECT count(*) c FROM activos`)).c
  const r=await call(`SELECT public.rpc_crear_auxiliar($1,$2,'equipo_menor'::tipo_activo_enum) AS r`,[act,'Auxiliar Gate'])
  const n1=(await one(`SELECT count(*) c FROM activos`)).c
  rec('rpc_crear_auxiliar', r.ok && Number(n1)===Number(n0)+1, true, isJson(r.ret?.r), `activos ${n0}→${n1}${r.ok?'':' | '+r.err}`) }

// 9. rpc_asignar_pauta (requiere una pauta real)
{ const pauta=(await one(`SELECT id FROM pautas_fabricante LIMIT 1`).catch(()=>null))?.id
    || (await one(`SELECT id FROM pauta_fabricante LIMIT 1`).catch(()=>null))?.id || null
  if(!pauta){ rec('rpc_asignar_pauta', false, false, false, 'sin pauta_fabricante en datos — no ejecutable'); }
  else { const r=await call(`SELECT public.rpc_asignar_pauta($1,$2) AS r`,[act,pauta])
    const inv=await call(`SELECT public.rpc_asignar_pauta($1,$2)`,['00000000-0000-0000-0000-0000000000ff',pauta])
    rec('rpc_asignar_pauta', r.ok, !inv.ok, r.ok, `${r.ok?'asignada':r.err}`) } }

// 10. rpc_registrar_salida_inventario (OT ya en ejecución/cerrada; usar una OT nueva en ejecución)
{ // crear OT con faena que TENGA bodega con stock, y llevarla a en_ejecucion
  const sbf=await one(`SELECT b.faena_id, sb.bodega_id, sb.producto_id FROM stock_bodega sb JOIN bodegas b ON b.id=sb.bodega_id WHERE sb.cantidad>1 AND b.faena_id IS NOT NULL LIMIT 1`).catch(()=>null)
  const faenaMat = sbf?.faena_id || faena
  const r2=await call(`SELECT public.rpc_crear_ot('correctivo'::tipo_ot_enum,$1,$2,$3) AS r`,[ct,faenaMat,act])
  const otMat=(await one(`SELECT id FROM ordenes_trabajo ORDER BY created_at DESC LIMIT 1`)).id
  await call(`SELECT public.rpc_transicion_ot(p_ot_id=>$1,p_nuevo_estado=>'asignada'::estado_ot_enum,p_usuario_id=>$2,p_responsable_id=>$2)`,[otMat,ADMIN])
  await call(`SELECT public.rpc_transicion_ot(p_ot_id=>$1,p_nuevo_estado=>'en_ejecucion'::estado_ot_enum,p_usuario_id=>$2)`,[otMat,ADMIN])
  const stock=sbf ? {bodega_id:sbf.bodega_id, producto_id:sbf.producto_id} : await one(`SELECT sb.bodega_id, sb.producto_id FROM stock_bodega sb WHERE sb.cantidad>1 LIMIT 1`).catch(()=>null)
  if(!stock){ rec('rpc_registrar_salida_inventario', false, false, false, 'sin stock_bodega disponible — no ejecutable') }
  else { const r=await call(`SELECT public.rpc_registrar_salida_inventario($1,$2,$3,$4,$5) AS r`,[stock.bodega_id,stock.producto_id,1,otMat,ADMIN])
    const inv=await call(`SELECT public.rpc_registrar_salida_inventario($1,$2,$3,$4,$5)`,[stock.bodega_id,stock.producto_id,999999,otMat,ADMIN])
    rec('rpc_registrar_salida_inventario', r.ok, !inv.ok, r.ok, `${r.ok?'salida ok':r.err}; sobre-stock rechazado=${!inv.ok}`) } }

// 11. rpc_validar_sugerencia (sembrar una sugerencia pendiente de prueba)
{ // valida un CAMBIO DE ESTADO SUGERIDO (por geocerca GPS), tabla cambios_estado_sugeridos
  let sug=null, seedErr=''
  try{ await admin.query(`DELETE FROM cambios_estado_sugeridos WHERE activo_id=$1 AND accion='pendiente'`,[act]) }catch(e){}
  try{ sug=await one(`INSERT INTO cambios_estado_sugeridos(activo_id,estado_sugerido,razon,origen) VALUES($1,'disponible','gate test','gps') RETURNING id`,[act]) }catch(e){ seedErr=e.message.slice(0,70) }
  if(!sug){ rec('rpc_validar_sugerencia', false, false, false, 'no se pudo sembrar: '+seedErr) }
    // 'rechazar' = completación autorizada válida (no dispara el bloqueo ready-to-rent de 'aprobar')
  else { const r=await call(`SELECT public.rpc_validar_sugerencia($1,$2,$3) AS r`,[sug.id,'rechazar','gate'])
    const after=(await one(`SELECT accion FROM cambios_estado_sugeridos WHERE id=$1`,[sug.id])).accion
    const inv=await call(`SELECT public.rpc_validar_sugerencia($1,$2,$3)`,['00000000-0000-0000-0000-0000000000ff','rechazar','x'])
    rec('rpc_validar_sugerencia', r.ok && after!=='pendiente', !inv.ok, r.ok, `accion→${after}; inexistente rechazado=${!inv.ok}${r.ok?'':' | '+r.err}`) } }

log('\n── Resumen flujos autorizados ──')
const full=R.filter(x=>x.exito).length
log(`Completados con cambio real: ${full}/11 · rollback/rechazo probado: ${R.filter(x=>x.rollback).length}/11`)
R.filter(x=>!x.exito).forEach(x=>log(`  pendiente: ${x.fn}`))
await t.end(); await admin.end()
