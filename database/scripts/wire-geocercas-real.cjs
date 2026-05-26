const { Client } = require('pg')
;(async () => {
  const c = new Client({ connectionString: process.env.SUPABASE_DB_URL, ssl: { rejectUnauthorized: false }, statement_timeout: 60000, connectionTimeoutMillis: 20000 })
  await c.connect()
  await c.query('BEGIN')

  // 1. Ligar geocercas faena_cliente al contrato dominante de los equipos dentro
  const link = await c.query(`
    with dom as (
      select g.id geocerca_id, mode() within group (order by a.contrato_id) ctr
      from gps_geocercas g
      join gps_estado_actual e on e.latitud is not null and fn_punto_en_geocerca(e.latitud,e.longitud,g.id)
      join activos a on a.id = e.activo_id
      where g.activo
      group by g.id
    )
    update gps_geocercas g set contrato_id = dom.ctr, updated_at = now()
    from dom
    where g.id = dom.geocerca_id and g.tipo = 'faena_cliente' and dom.ctr is not null
    returning g.id`)
  console.log('geocercas faena ligadas a contrato:', link.rowCount)

  // 2. Registrar eventos de entrada (ocupacion) para quien esta dentro AHORA.
  //    Insert directo: NO dispara el trigger de alertas (ese es sobre gps_estado_actual).
  //    Evita duplicar si ya hay un evento del activo en esa geocerca hoy.
  const ev = await c.query(`
    insert into gps_geocerca_eventos (geocerca_id, activo_id, tipo_evento, ts, latitud, longitud, velocidad_kmh, contrato_id)
    select g.id, e.activo_id, 'entrada', now(), e.latitud, e.longitud, coalesce(e.velocidad_kmh,0), g.contrato_id
    from gps_geocercas g
    join gps_estado_actual e on e.latitud is not null and fn_punto_en_geocerca(e.latitud,e.longitud,g.id)
    where g.activo
      and not exists (
        select 1 from gps_geocerca_eventos x
        where x.geocerca_id=g.id and x.activo_id=e.activo_id and x.ts::date = now()::date
      )
    returning 1`)
  console.log('eventos de entrada registrados:', ev.rowCount)

  await c.query('COMMIT')

  // 3. Regenerar snapshot de hoy
  await c.query(`SELECT fn_guardar_reporte_diario('2026-05-25'::date)`)

  // 4. Verificar
  const oc = await c.query(`select geocerca_nombre, count(*)::int dentro from v_geocerca_ocupacion group by 1 order by 2 desc limit 8`)
  console.log('\n=== Ocupacion actual (v_geocerca_ocupacion) ==='); console.table(oc.rows)
  const p = (await c.query(`select payload->'geocercas' g from reportes_diarios_snapshot where fecha='2026-05-25'`)).rows[0].g
  console.log('\n=== Seccion geocercas del reporte ===')
  console.log('total_activas:', p.total_activas, '| en_zona_esperada:', p.en_zona_esperada, '| fuera_zona:', p.fuera_zona_esperada, '| sin_dato:', p.sin_dato_zona)
  console.log('ocupacion_actual:', JSON.stringify(p.ocupacion_actual))
  await c.end()
})().catch(async e => { console.error('FALLO:', e.message); process.exit(1) })
