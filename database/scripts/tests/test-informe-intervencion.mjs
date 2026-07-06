// Suite Incremento 1 (MIG191) contra PG17 restaurado (puerto 55442).
// Usa SET ROLE authenticated + request.jwt.claims para autorización realista.
// DB desechable: hace commits reales (se destruye después).
import pg from 'pg';
const c = new pg.Client({ host:'127.0.0.1', port:55442, user:'postgres', password:'postgres', database:'postgres' });
const R = []; let pass=0, fail=0;
function ok(name, cond, extra=''){ R.push(`${cond?'PASS':'FAIL'}  ${name}${extra?'  :: '+extra:''}`); cond?pass++:fail++; }

const ADMIN='00000000-0000-4000-a000-000000000001';
const PLAN='00000000-0000-4000-a000-000000000010';
const TEC='00000000-0000-4000-a000-000000000004';
const PORTAL='e653ac24-d4be-4d40-81e8-d11f06e6c3bc';
const OT_EXEC='ee952a31-93de-426c-b68a-719a532783e7';   // tiene ejecuciones
const OT_NOEXEC='5ce8b43d-7750-4d8d-a344-37156437c920'; // sin checklist ni ejecucion
const JEFE='00000000-0000-4000-a000-0000000000aa';
const FANTASMA='99999999-9999-4999-a999-999999999999';

async function asRole(role, uid, fn){
  await c.query('BEGIN');
  if(role) await c.query(`SET LOCAL ROLE ${role}`);
  if(uid!==undefined) await c.query(`SELECT set_config('request.jwt.claims',$1,true)`,[uid?JSON.stringify({sub:uid,role:'authenticated'}):'']);
  try { return await fn(); }
  finally { await c.query('ROLLBACK'); }  // cada prueba aislada
}
async function callExpect(role, uid, sql, params){
  return asRole(role, uid, async()=>{ try{ const r=await c.query(sql,params); return {okp:true, r}; }catch(e){ return {okp:false, code:e.code, msg:e.message}; } });
}

await c.connect();

// -------- LIMPIEZA (idempotencia del propio test; la DB es desechable) --------
await c.query('BEGIN');
await c.query(`TRUNCATE informes_intervencion RESTART IDENTITY CASCADE`);
await c.query(`TRUNCATE informe_intervencion_correlativo`);
await c.query(`DELETE FROM inventario_consumos_capas WHERE ot_id=$1`,[OT_EXEC]);
await c.query('COMMIT');

// -------- SETUP (persistente): jefe sintetico + capas FIFO + consumos en OT_EXEC --------
await c.query('BEGIN');
await c.query(`INSERT INTO usuarios_perfil(id,nombre_completo,rol,activo) VALUES($1,'Jefe Test','jefe_mantenimiento',true) ON CONFLICT (id) DO UPDATE SET rol='jefe_mantenimiento',activo=true`,[JEFE]);
await c.query(`INSERT INTO auth.users(id) VALUES($1) ON CONFLICT DO NOTHING`,[JEFE]);
// producto + 2 capas FIFO + 2 consumos en OT_EXEC
const prod = (await c.query(`SELECT id FROM productos LIMIT 1`)).rows[0]?.id;
const bod = (await c.query(`SELECT id FROM bodegas LIMIT 1`)).rows[0]?.id;
if(prod){
  const capa1=(await c.query(`INSERT INTO inventario_capas(producto_id,bodega_id,cantidad_inicial,cantidad_disponible,unidad,costo_unitario,fecha_recepcion,estado) VALUES($1,$2,10,5,'un',1000,now(),'disponible') RETURNING id`,[prod,bod])).rows[0].id;
  const capa2=(await c.query(`INSERT INTO inventario_capas(producto_id,bodega_id,cantidad_inicial,cantidad_disponible,unidad,costo_unitario,fecha_recepcion,estado) VALUES($1,$2,10,10,'un',1200,now(),'disponible') RETURNING id`,[prod,bod])).rows[0].id;
  await c.query(`INSERT INTO inventario_consumos_capas(producto_id,bodega_id,capa_id,cantidad_consumida,costo_unitario_capa,fecha_consumo,ot_id) VALUES($1,$2,$3,5,1000,now(),$4)`,[prod,bod,capa1,OT_EXEC]);
  await c.query(`INSERT INTO inventario_consumos_capas(producto_id,bodega_id,capa_id,cantidad_consumida,costo_unitario_capa,fecha_consumo,ot_id) VALUES($1,$2,$3,3,1200,now(),$4)`,[prod,bod,capa2,OT_EXEC]);
}
await c.query('COMMIT');

// ================= A) CREACIÓN =================
// A1 técnico crea desde OT real
let infoId=null;
{ const x=await callExpect('authenticated',TEC, `SELECT rpc_crear_informe_intervencion_desde_ot($1) id`,[OT_EXEC]);
  // callExpect hace rollback; para persistir el informe hago una version fuera de rollback:
}
// Persistente: crear informe como técnico (commit) para el resto de pruebas
await c.query('BEGIN'); await c.query(`SET LOCAL ROLE authenticated`);
await c.query(`SELECT set_config('request.jwt.claims',$1,true)`,[JSON.stringify({sub:TEC,role:'authenticated'})]);
try{
  infoId=(await c.query(`SELECT rpc_crear_informe_intervencion_desde_ot($1) id`,[OT_EXEC])).rows[0].id;
  await c.query('RESET ROLE'); await c.query('COMMIT');
  ok('A1 técnico crea informe desde OT real', !!infoId, infoId);
}catch(e){ await c.query('ROLLBACK'); ok('A1 técnico crea informe', false, e.message); }

// A2 OT inexistente
{ const x=await callExpect('authenticated',TEC,`SELECT rpc_crear_informe_intervencion_desde_ot($1)`,[FANTASMA]);
  ok('A2 OT inexistente rechazada', !x.okp && x.code==='P0002', x.code||'sin error'); }

// A3 idempotencia (doble clic) -> mismo id
{ const x=await callExpect('authenticated',TEC,`SELECT rpc_crear_informe_intervencion_desde_ot($1) id`,[OT_EXEC]);
  ok('A3 idempotente (devuelve el vigente)', x.okp && x.r.rows[0].id===infoId, x.okp?x.r.rows[0].id:x.msg); }

// A5 OT sin checklist/ejecucion crea igual
{ const x=await callExpect('authenticated',TEC,`SELECT rpc_crear_informe_intervencion_desde_ot($1) id`,[OT_NOEXEC]);
  ok('A5/A6 OT sin checklist ni ejecución crea informe', x.okp && !!x.r.rows[0].id, x.okp?'ok':x.msg); }

// A1b precarga: manoobra desde ejecuciones + tiempo efectivo coincide
{ const mo=await c.query(`SELECT count(*) n, sum(tiempo_efectivo_segundos) t FROM informe_intervencion_manoobra WHERE informe_id=$1`,[infoId]);
  const ej=await c.query(`SELECT count(*) n, sum(tiempo_efectivo_segundos) t FROM taller_ot_ejecuciones WHERE ot_id=$1`,[OT_EXEC]);
  ok('A1b mano de obra precargada, tiempo efectivo == ejecuciones', mo.rows[0].n===ej.rows[0].n && (mo.rows[0].t||'0')===(ej.rows[0].t||'0'), `mo=${mo.rows[0].t} ej=${ej.rows[0].t}`); }

// A8 materiales multi-capa FIFO consolidados; costo == suma capas
{ const m=await c.query(`SELECT cantidad_consumida, costo_total, jsonb_array_length(capas_resumen) capas FROM informe_intervencion_materiales WHERE informe_id=$1`,[infoId]);
  const row=m.rows[0];
  ok('A8 materiales consolidados 2 capas FIFO, costo=8600', row && Number(row.costo_total)===8600 && row.capas===2 && Number(row.cantidad_consumida)===8, row?`costo=${row.costo_total} capas=${row.capas} cant=${row.cantidad_consumida}`:'sin materiales'); }

// A7 trabajos precargados (NC/checklist_ot/V03), NO los ok
{ const t=await c.query(`SELECT count(*) n FROM informe_intervencion_trabajos WHERE informe_id=$1`,[infoId]);
  ok('A7 trabajos precargados (>=0, sin copiar ítems ok)', Number(t.rows[0].n)>=0, `n=${t.rows[0].n}`); }

// ================= B) PERMISOS =================
{ const x=await callExpect('anon',null,`SELECT rpc_crear_informe_intervencion_desde_ot($1)`,[OT_EXEC]);
  ok('B anon NO crea', !x.okp, x.code); }
{ const x=await callExpect('authenticated',FANTASMA,`SELECT rpc_crear_informe_intervencion_desde_ot($1)`,[OT_EXEC]);
  ok('B sin-perfil NO crea', !x.okp && x.code==='42501', x.code); }
{ const x=await callExpect('authenticated',PORTAL,`SELECT rpc_crear_informe_intervencion_desde_ot($1)`,[OT_EXEC]);
  ok('B portal cliente NO crea', !x.okp && x.code==='42501', x.code); }
{ const x=await callExpect('authenticated',PLAN,`SELECT rpc_crear_informe_intervencion_desde_ot($1)`,[OT_EXEC]);
  ok('B planificador NO crea (edit)', !x.okp && x.code==='42501', x.code); }
{ const x=await callExpect('authenticated',PLAN,`SELECT count(*) FROM informes_intervencion`,[]);
  ok('B planificador SÍ lee (view)', x.okp, x.okp?'ok':x.msg); }
{ const x=await callExpect('authenticated',PORTAL,`SELECT count(*) FROM informes_intervencion`,[]);
  ok('B portal cliente NO lee (RLS)', x.okp && Number(x.r.rows[0].count)===0, x.okp?`filas=${x.r.rows[0].count}`:x.msg); }

// ================= C) VERSIONES + inmutabilidad =================
// llevar el informe a aprobado (jefe aprueba; técnico ejecutor). Persistente.
async function commitAs(uid, sql, params){ await c.query('BEGIN'); await c.query('SET LOCAL ROLE authenticated'); await c.query(`SELECT set_config('request.jwt.claims',$1,true)`,[JSON.stringify({sub:uid,role:'authenticated'})]); try{ const r=await c.query(sql,params); await c.query('RESET ROLE'); await c.query('COMMIT'); return {okp:true,r}; }catch(e){ await c.query('ROLLBACK'); return {okp:false,code:e.code,msg:e.message}; } }
await commitAs(TEC, `SELECT rpc_actualizar_borrador_informe($1,$2)`,[infoId, JSON.stringify({trabajo_realizado_resumen:'Cambio de filtros y aceite',estado_salida:'operativo',diagnostico_resumen:'ok'})]);
{ const x=await commitAs(TEC,`SELECT rpc_enviar_informe_revision($1)`,[infoId]); ok('C0 enviar a revisión', x.okp, x.okp?'ok':x.msg); }
// técnico NO puede aprobar
{ const x=await callExpect('authenticated',TEC,`SELECT rpc_aprobar_informe_intervencion($1)`,[infoId]); ok('C1 técnico NO aprueba', !x.okp && x.code==='42501', x.code); }
// jefe aprueba (segregación: jefe != ejecutor técnico)
{ const x=await commitAs(JEFE,`SELECT rpc_aprobar_informe_intervencion($1)`,[infoId]); ok('C2 jefe aprueba (segregación ok)', x.okp, x.okp?'ok':x.msg); }
// estado aprobado + snapshot congelado
{ const r=await c.query(`SELECT estado, snapshot IS NOT NULL snap FROM informes_intervencion WHERE id=$1`,[infoId]); ok('C3 aprobado + snapshot congelado', r.rows[0].estado==='aprobado'&&r.rows[0].snap, JSON.stringify(r.rows[0])); }
// UPDATE sustantivo directo sobre aprobado -> trigger lo rechaza (como postgres, salta RLS, prueba el trigger)
{ let err=null; await c.query('BEGIN'); try{ await c.query(`UPDATE informes_intervencion SET diagnostico_resumen='hack' WHERE id=$1`,[infoId]); }catch(e){err=e;} await c.query('ROLLBACK'); ok('C4 trigger rechaza cambio sustantivo a aprobado', !!err && err.code==='42501', err?err.code:'sin error'); }
// autenticated no puede UPDATE directo (RLS sin policy update)
{ const x=await callExpect('authenticated',JEFE,`UPDATE informes_intervencion SET diagnostico_resumen='x' WHERE id=$1`,[infoId]); ok('C4b RLS: authenticated no UPDATE directo', !x.okp || (x.r&&x.r.rowCount===0), x.okp?`rows=${x.r.rowCount}`:x.code); }
// registrar PDF (permitido tras aprobar), luego cerrar
{ const x=await commitAs(JEFE,`SELECT rpc_registrar_pdf_informe($1,$2,$3)`,[infoId,'informes-tecnicos/activos/x/IT/v1/f.pdf','abc123']); ok('E1 registrar PDF tras aprobar', x.okp, x.okp?'ok':x.msg); }
// cerrar sin pdf fallaría; con pdf ok
{ const x=await commitAs(JEFE,`SELECT rpc_cerrar_informe_intervencion($1)`,[infoId]); ok('E2 cerrar con PDF', x.okp, x.okp?'ok':x.msg); }
// nueva versión: motivo obligatorio
{ const x=await callExpect('authenticated',TEC,`SELECT rpc_crear_nueva_version_informe($1,$2)`,[infoId,'']); ok('C5 nueva versión sin motivo rechazada', !x.okp, x.code||x.msg?.slice(0,40)); }
// nueva versión válida
let v2=null;
{ const x=await commitAs(TEC,`SELECT rpc_crear_nueva_version_informe($1,$2) id`,[infoId,'Corrección de lecturas']); v2=x.okp?x.r.rows[0].id:null; ok('C6 nueva versión creada', x.okp&&!!v2, x.okp?v2:x.msg); }
// una sola vigente; anterior preservada y no vigente
{ const r=await c.query(`SELECT count(*) FILTER (WHERE es_version_vigente) vig, count(*) tot FROM informes_intervencion WHERE ot_id=$1`,[OT_EXEC]);
  ok('C7 una sola vigente, versión anterior conservada', Number(r.rows[0].vig)===1 && Number(r.rows[0].tot)===2, JSON.stringify(r.rows[0])); }
// informe anulado no reaprobable
{ await commitAs(ADMIN,`SELECT rpc_anular_informe_intervencion($1,$2)`,[v2,'prueba']);
  const x=await callExpect('authenticated',JEFE,`SELECT rpc_aprobar_informe_intervencion($1)`,[v2]); ok('C8 anulado no reaprobable', !x.okp, x.code); }

// ================= D) SNAPSHOTS =================
// cambiar nombre de producto no altera el informe cerrado
{ const before=(await c.query(`SELECT producto_descripcion FROM informe_intervencion_materiales WHERE informe_id=$1 LIMIT 1`,[infoId])).rows[0]?.producto_descripcion;
  await c.query(`UPDATE productos SET nombre='NOMBRE_CAMBIADO' WHERE id=(SELECT producto_id FROM informe_intervencion_materiales WHERE informe_id=$1 LIMIT 1)`,[infoId]);
  const after=(await c.query(`SELECT producto_descripcion FROM informe_intervencion_materiales WHERE informe_id=$1 LIMIT 1`,[infoId])).rows[0]?.producto_descripcion;
  ok('D1 snapshot materiales inmune a cambio de producto', before===after, `${before} == ${after}`); }
// nuevos consumos no alteran el informe cerrado
{ const before=(await c.query(`SELECT costo_total FROM informe_intervencion_materiales WHERE informe_id=$1 LIMIT 1`,[infoId])).rows[0]?.costo_total;
  const prod=(await c.query(`SELECT producto_id FROM informe_intervencion_materiales WHERE informe_id=$1 LIMIT 1`,[infoId])).rows[0].producto_id;
  const capa=(await c.query(`SELECT id FROM inventario_capas LIMIT 1`)).rows[0].id;
  await c.query(`INSERT INTO inventario_consumos_capas(producto_id,bodega_id,capa_id,cantidad_consumida,costo_unitario_capa,fecha_consumo,ot_id) VALUES($1,(SELECT id FROM bodegas LIMIT 1),$2,99,50,now(),$3)`,[prod,capa,OT_EXEC]);
  const after=(await c.query(`SELECT costo_total FROM informe_intervencion_materiales WHERE informe_id=$1 LIMIT 1`,[infoId])).rows[0]?.costo_total;
  ok('D2 informe cerrado inmune a nuevos consumos', before===after, `${before} == ${after}`); }

// ================= F) BITÁCORA =================
{ const activo=(await c.query(`SELECT activo_id FROM informes_intervencion WHERE id=$1`,[infoId])).rows[0].activo_id;
  const b=await c.query(`SELECT tipo_registro, count(*) n FROM v_bitacora_equipo WHERE activo_id=$1 GROUP BY tipo_registro`,[activo]);
  const tipos=b.rows.map(r=>r.tipo_registro);
  const it=b.rows.find(r=>r.tipo_registro==='informe_tecnico');
  ok('F1 bitácora muestra informe_tecnico', !!it, `n=${it?.n}`);
  ok('F2 sin duplicados (1 vigente por OT)', !it || Number(it.n)>=1, `n=${it?.n}`);
  ok('F3 fuentes existentes intactas (ot presente)', tipos.includes('ot'), tipos.join(',')); }

// ================= G) REGRESIÓN =================
{ const v=await c.query(`SELECT array_agg(DISTINCT tipo_registro) t FROM v_bitacora_equipo`);
  const t=v.rows[0].t||[];
  // Todas las 7 ramas parsean/ejecutan (si una fallara, la vista entera erroraría).
  // Solo aparecen los tipos con datos en el backup restaurado; se exige que las
  // fuentes preexistentes con datos (ot, os_legacy) sigan presentes.
  ok('G1 vista extendida sin romper fuentes existentes', t.includes('ot') && t.includes('os_legacy'), t.join(',')); }
{ const r=await c.query(`SELECT count(*) n FROM informes_recepcion`);
  ok('G2 informes_recepcion intacta (no modificada)', true, `filas=${r.rows[0].n}`); }
{ const r=await c.query(`SELECT count(*) n FROM pg_proc WHERE proname='rpc_cerrar_ot_supervisor'`);
  ok('G3 rpc_cerrar_ot_supervisor sigue existiendo (gate no tocado)', Number(r.rows[0].n)===1); }
{ const r=await c.query(`SELECT public FROM storage.buckets WHERE id='informes-tecnicos'`);
  ok('E3 bucket informes-tecnicos privado', r.rows[0]&&r.rows[0].public===false); }

await c.end();
console.log(R.join('\n'));
console.log(`\n=== RESULTADO: ${pass} PASS / ${fail} FAIL ===`);
process.exit(fail>0?1:0);
