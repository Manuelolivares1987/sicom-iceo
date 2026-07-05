// Anonimización REPRODUCIBLE de la BD LOCAL restaurada (puerto 55434).
// NO se ejecuta contra producción. Reemplaza PII conservando relaciones/estructura.
import pg from 'pg'
const c = new pg.Client({ host: '127.0.0.1', port: 55435, user: 'postgres', password: 'postgres', database: 'postgres' })
await c.connect()

// Guard: negarse a correr si NO es local.
const who = (await c.query(`SELECT inet_server_addr() AS ip, current_setting('port') AS port`)).rows[0]
if (who.port !== "55435") { console.error('ABORTA: no es el puerto local esperado'); process.exit(1) }

const log = []
async function upd(sql, label) {
  try { const r = await c.query(sql); log.push(`${label}: ${r.rowCount} filas`) }
  catch (e) { log.push(`${label}: (omitido: ${e.message.slice(0,50)})`) }
}

// 1. Reemplazos deterministas por columna sensible (por id/ctid para unicidad).
await upd(`UPDATE public.usuarios_perfil SET email='user'||left(md5(id::text),8)||'@anon.local', nombre_completo='Usuario '||left(md5(id::text),6), rut=NULL, telefono=NULL, firma_url=NULL`, 'usuarios_perfil')
await upd(`UPDATE public.activos SET patente=CASE WHEN patente IS NOT NULL THEN 'AN'||upper(left(md5(id::text),6)) END, vin_chasis=CASE WHEN vin_chasis IS NOT NULL THEN 'VIN'||left(md5(id::text),14) END, numero_motor=CASE WHEN numero_motor IS NOT NULL THEN 'MOT'||left(md5(id::text),10) END, cliente_actual=CASE WHEN cliente_actual IS NOT NULL THEN 'Cliente '||left(md5(id::text),5) END, proveedor=NULL`, 'activos')
await upd(`UPDATE public.contratos SET cliente=CASE WHEN cliente IS NOT NULL THEN 'Cliente '||left(md5(id::text),5) END, nombre='Contrato '||left(md5(id::text),6)`, 'contratos')
await upd(`UPDATE public.estado_diario_flota SET cliente=CASE WHEN cliente IS NOT NULL THEN 'Cliente '||left(md5(activo_id::text),5) END, observacion=NULL`, 'estado_diario_flota')
await upd(`UPDATE public.cliente_portal_perfil SET nombre_visible='Portal '||left(md5(id::text),6), empresa='Empresa '||left(md5(id::text),5), rut_empresa=NULL, notas=NULL`, 'cliente_portal_perfil')
await upd(`UPDATE public.vehiculos_autorizados_externos SET patente='AN'||left(md5(id::text),4), empresa='Empresa '||left(md5(id::text),5)`, 'vehiculos_autorizados_externos')
await upd(`UPDATE public.combustible_kardex_valorizado SET nombre_receptor=NULL, rut_receptor=NULL, cliente_nombre_manual=NULL`, 'combustible_kardex')

// 2. Anular TODAS las columnas de tipo texto que parezcan URL/foto/firma (adjuntos).
const urlCols = (await c.query(`
  SELECT table_name, column_name FROM information_schema.columns
  WHERE table_schema='public' AND (column_name ~* '_url$|foto|firma|adjunto|documento_path')
    AND data_type IN ('text','character varying')`)).rows
for (const { table_name, column_name } of urlCols) {
  await upd(`UPDATE public."${table_name}" SET "${column_name}"=NULL WHERE "${column_name}" IS NOT NULL`, `url:${table_name}.${column_name}`)
}

// 3. Vaciar tablas de documentos/adjuntos (conservando estructura).
for (const t of ['documentos','evidencias_ot','activo_documentos','combustible_evidencias']) {
  await upd(`DELETE FROM public."${t}"`, `delete:${t}`)
}

// 4. Verificación: no debe quedar PII evidente.
const chk = (await c.query(`SELECT
  (SELECT count(*) FROM public.usuarios_perfil WHERE email NOT LIKE '%@anon.local') AS emails_reales,
  (SELECT count(*) FROM public.activos WHERE vin_chasis IS NOT NULL AND vin_chasis NOT LIKE 'VIN%') AS vin_reales`)).rows[0]
console.log(JSON.stringify({ acciones: log, verificacion: chk }, null, 2))
if (Number(chk.emails_reales) > 0 || Number(chk.vin_reales) > 0) { console.error('ADVERTENCIA: quedó PII sin anonimizar'); }
await c.end()
