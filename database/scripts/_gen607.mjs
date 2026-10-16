// Genera los parches por línea de MIG607: donde la base define "la flota" con
// estado <> 'dado_baja', se agrega «y no es un equipo externo».
// Uso: node _gen607.mjs <salida.sql>
import { writeFileSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })
const client = new pg.Client({ connectionString: process.env.SUPABASE_DB_URL.trim(), ssl: { rejectUnauthorized: false } })
await client.connect()

const FNS = [
  'calcular_kpi_a4', 'calcular_kpi_b1', 'calcular_kpi_b4', 'calcular_kpi_c1', 'calcular_kpi_c6',
  'calcular_oee_flota', 'fn_aplicar_estado_geocerca', 'fn_aplicar_estados_diarios_automaticos',
  'fn_auto_crear_planes_activo', 'fn_calcular_fiabilidad_flota', 'fn_certificados_escalar_sin_fecha',
  'fn_comercial_equipos', 'fn_flota_en_mantenimiento', 'fn_generar_reporte_diario',
  'fn_kpi_disponibilidad_flota_movil', 'fn_kpi_mttr_moviles', 'fn_kpi_oee_fiabilidad_moviles',
  'fn_panel_disponibilidad', 'fn_panel_equipos_detenidos', 'fn_panel_excepciones', 'fn_panel_taller',
  'fn_propuesta_cierre_diario', 'fn_reporte_fiabilidad_publico', 'fn_reporte_flota_publico',
  'fn_sugerencias_estado_gps', 'fn_verificar_antiguedad_flota', 'fn_verificar_certificaciones_flota',
  'fn_verificar_disponibilidad_vigente', 'fn_verificar_planes_preventivos',
  'rpc_admin_sembrar_planes_faltantes', 'rpc_confirmar_cierre_diario',
]
const VIEWS = [
  'v_control_documental', 'v_documentos_equipo_estado', 'v_equipos_pendientes_verificacion',
  'v_flota_posiciones', 'v_mantenimiento_cobertura_resumen', 'v_flota_dashboard_unificado',
]

const RE = /\b(?:(\w+)\.)?estado\s*(?:<>|!=)\s*'dado_baja'(?:::estado_activo_enum)?/g

function aliasEsActivos(text, alias, idx) {
  if (alias) {
    return new RegExp(`\\bactivos\\s+(?:AS\\s+)?${alias}\\b`, 'i').test(text)
  }
  // Sin alias: el FROM más cercano hacia atrás debe ser `FROM activos` sin alias
  // (o con un alias que no se use, caso que no cubrimos: se reporta).
  const antes = text.slice(Math.max(0, idx - 400), idx)
  const froms = [...antes.matchAll(/\bFROM\s+(\w+)(\s+(?:AS\s+)?(\w+))?/gi)]
  const ult = froms[froms.length - 1]
  if (!ult || ult[1].toLowerCase() !== 'activos') return false
  const al = ult[3]?.toLowerCase()
  return !al || ['where', 'join', 'left', 'inner', 'group', 'order', 'limit'].includes(al)
}

function parchar(nombre, text) {
  const log = []
  let n = 0
  const out = text.replace(RE, (m, alias, off) => {
    if (!aliasEsActivos(text, alias, off)) {
      log.push(`  SALTADO (alias no es activos): ${m}`)
      return m
    }
    n++
    const col = alias ? `${alias}.es_externo` : 'es_externo'
    log.push(`  ${m}  →  + NOT ${col}`)
    return `(${m} AND NOT COALESCE(${col}, false))`
  })
  return { out, n, log }
}

let sql = ''
const resumen = []
for (const f of FNS) {
  const r = await client.query(
    `SELECT p.oid::regprocedure::text sig, pg_get_functiondef(p.oid) d FROM pg_proc p
      WHERE proname=$1 AND prokind='f' AND pronamespace='public'::regnamespace`, [f])
  for (const row of r.rows) {
    const { out, n, log } = parchar(f, row.d)
    resumen.push(`${row.sig}: ${n} parche(s)\n${log.join('\n')}`)
    if (n > 0) sql += `-- ${row.sig}\n${out.replace(/\s+$/, '')};\n\n`
  }
}
for (const v of VIEWS) {
  const r = await client.query(
    `SELECT pg_get_viewdef($1::regclass) d,
            (SELECT reloptions FROM pg_class WHERE oid=$1::regclass) o`, [v])
  const { out, n, log } = parchar(v, r.rows[0].d)
  const opts = r.rows[0].o ? ` WITH (${r.rows[0].o.join(', ')})` : ''
  resumen.push(`VIEW ${v}${opts}: ${n} parche(s)\n${log.join('\n')}`)
  if (n > 0) sql += `-- VIEW ${v}\nCREATE OR REPLACE VIEW public.${v}${opts} AS\n${out.replace(/;\s*$/, '')};\n\n`
}
await client.end()
writeFileSync(process.argv[2], sql)
console.log(resumen.join('\n'))
