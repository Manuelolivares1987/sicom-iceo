// Crea geocercas agrupando los equipos por su posición GPS REAL (clustering).
// Cada cluster -> 1 geocerca (centro=centroide, radio=spread+buffer), nombrada
// por la faena/cliente dominante. Uso: node crear-geocercas-gps.mjs
import pg from 'pg'

const UMBRAL_KM = 12      // equipos a <12km se agrupan en la misma zona
const BUFFER_M = 2000     // margen sobre el spread del cluster
const RADIO_MIN_M = 2000

function haversineKm(aLat, aLng, bLat, bLng) {
  const R = 6371, toRad = (d) => d * Math.PI / 180
  const dLat = toRad(bLat - aLat), dLng = toRad(bLng - aLng)
  const x = Math.sin(dLat/2)**2 + Math.cos(toRad(aLat))*Math.cos(toRad(bLat))*Math.sin(dLng/2)**2
  return R * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1-x))
}
function moda(arr) {
  const m = {}; let best = null, bn = 0
  for (const v of arr) { if (!v || v === '?') continue; m[v] = (m[v]||0)+1; if (m[v] > bn) { bn = m[v]; best = v } }
  return best
}

const c = new pg.Client({ connectionString: process.env.SUPABASE_DB_URL, ssl: { rejectUnauthorized: false }, statement_timeout: 60000, connectionTimeoutMillis: 20000 })
await c.connect()
console.log('conectado')

const { rows: pts } = await c.query(`
  with ult as (
    select distinct on (activo_id) activo_id, cliente, ubicacion, operacion
    from estado_diario_flota where fecha=(select max(fecha) from estado_diario_flota) order by activo_id
  )
  select g.activo_id, g.latitud::float lat, g.longitud::float lng,
         u.cliente, u.ubicacion, u.operacion, a.patente
  from gps_estado_actual g
  join activos a on a.id=g.activo_id
  left join ult u on u.activo_id=g.activo_id
  where g.latitud is not null`)
console.log(`Puntos GPS: ${pts.length}`)

// Clustering greedy por cercanía geográfica
const clusters = []
for (const p of pts) {
  let best = null, bestD = Infinity
  for (const cl of clusters) {
    const d = haversineKm(p.lat, p.lng, cl.lat, cl.lng)
    if (d < UMBRAL_KM && d < bestD) { best = cl; bestD = d }
  }
  if (best) {
    best.pts.push(p)
    best.lat = best.pts.reduce((s,x)=>s+x.lat,0)/best.pts.length
    best.lng = best.pts.reduce((s,x)=>s+x.lng,0)/best.pts.length
  } else {
    clusters.push({ lat: p.lat, lng: p.lng, pts: [p] })
  }
}
console.log(`Clusters: ${clusters.length}`)

let creadas = 0
for (const cl of clusters) {
  const maxKm = Math.max(...cl.pts.map(p => haversineKm(p.lat, p.lng, cl.lat, cl.lng)))
  const radio = Math.max(RADIO_MIN_M, Math.round(maxKm*1000 + BUFFER_M))
  const ubic = moda(cl.pts.map(p=>p.ubicacion))
  const cliente = moda(cl.pts.map(p=>p.cliente))
  const oper = moda(cl.pts.map(p=>p.operacion))
  const esTaller = /taller|fenix|pillado/i.test(ubic || '')
  const tipo = esTaller ? 'base_pillado' : 'faena_cliente'
  const nombre = (ubic || cliente || `Zona ${oper||''}`).slice(0,80)
  const desc = `Auto-generada del GPS (${cl.pts.length} equipos: ${cl.pts.map(p=>p.patente).join(', ')}). Cliente: ${cliente||'varios'}. Operación: ${oper||'?'}.`
  const color = esTaller ? '#F59E0B' : (oper==='Calama' ? '#8B5CF6' : '#10B981')
  await c.query(`insert into gps_geocercas (nombre, tipo, centro_lat, centro_lng, radio_m, descripcion, color, activo)
                 values ($1,$2,$3,$4,$5,$6,$7,true)`,
    [nombre, tipo, cl.lat.toFixed(6), cl.lng.toFixed(6), radio, desc, color])
  creadas++
  console.log(`  + ${nombre} [${tipo}] ${cl.pts.length}eq r=${radio}m (${cl.lat.toFixed(4)},${cl.lng.toFixed(4)})`)
}
console.log(`\nGeocercas creadas: ${creadas}`)
await c.end()
