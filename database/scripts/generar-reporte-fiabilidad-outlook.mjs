#!/usr/bin/env node
// ============================================================================
// generar-reporte-fiabilidad-outlook.mjs
// ----------------------------------------------------------------------------
// HTML para enviar MANUALMENTE desde Outlook el Analisis de Fiabilidad:
// resumen (KPIs + por categoria + equipos de menor disponibilidad) + un BOTON
// con el link a la pagina INTERACTIVA /reporte-fiabilidad, donde la
// organizacion hace click en cada patente y ve su historial.
//
// Uso:
//   node generar-reporte-fiabilidad-outlook.mjs                       (mes actual)
//   node generar-reporte-fiabilidad-outlook.mjs 2026-06-01 2026-06-30 "Junio 2026"
// ============================================================================

import { writeFileSync, mkdirSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })

const hoy = '2026-06-01'  // referencia; el rango real va por args
const [argIni, argFin, argNombre] = process.argv.slice(2)
const INI = argIni || `${hoy.slice(0, 7)}-01`
const FIN = argFin || hoy
const NOMBRE = argNombre || 'Mes actual'
const BASE_URL = process.env.REPORTE_BASE_URL || 'https://pilladoiceo.netlify.app'
const LINK = `${BASE_URL}/reporte-fiabilidad?desde=${INI}&hasta=${FIN}`

const client = new pg.Client({ connectionString: (process.env.SUPABASE_DB_URL || '').trim(), ssl: { rejectUnauthorized: false } })
const esc = (s) => String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]))
const pct = (v) => v == null ? '—' : `${(Number(v) * 100).toFixed(1)}%`
const CAT = { arriendo_comercial: 'Arriendo comercial', leasing_operativo: 'Leasing operativo', uso_interno: 'Uso interno', venta: 'Venta' }

async function main() {
  await client.connect()
  const rep = (await client.query(`SELECT fn_reporte_fiabilidad_publico($1,$2) j`, [INI, FIN])).rows[0].j
  await client.end()

  const cats = rep.categorias || []
  const equipos = rep.equipos || []
  const n = (v) => Number(v || 0)
  const s = cats.reduce((a, c) => ({
    eq: a.eq + n(c.total_equipos), dias: a.dias + n(c.dias_equipo),
    up: a.up + n(c.dias_up), down: a.down + n(c.dias_down), ev: a.ev + n(c.eventos_falla_total),
  }), { eq: 0, dias: 0, up: 0, down: 0, ev: 0 })
  const dispFis = s.dias > 0 ? s.up / s.dias : 0
  const mtbf = s.ev > 0 ? s.up / s.ev : s.up
  const mttr = s.ev > 0 ? s.down / s.ev : 0
  const dispInh = mtbf + mttr > 0 ? mtbf / (mtbf + mttr) : 1

  // 5 de menor disponibilidad inherente (peor confiabilidad)
  const peores = [...equipos].sort((a, b) => n(a.disponibilidad_inherente) - n(b.disponibilidad_inherente)).slice(0, 5)

  const kpi = (label, val) => `
    <td style="padding:10px;border:1px solid #e5e7eb;border-radius:8px;text-align:center;background:#f8fafc">
      <div style="font-size:11px;color:#64748b;text-transform:uppercase">${label}</div>
      <div style="font-size:22px;font-weight:700;color:#0b2a4a;margin-top:2px">${val}</div>
    </td>`

  const html = `<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Análisis de Fiabilidad — ${esc(NOMBRE)}</title></head>
<body style="margin:0;background:#f1f5f9;font-family:Segoe UI,Arial,sans-serif;color:#1f2937">
<div style="max-width:780px;margin:0 auto;background:#fff">
  <div style="background:linear-gradient(90deg,#0b2a4a,#155e9c);color:#fff;padding:22px 26px">
    <div style="font-size:20px;font-weight:700">Análisis de Fiabilidad de Flota — Pillado</div>
    <div style="font-size:13px;opacity:.85;margin-top:3px">MTBF · MTTR · Disponibilidad Inherente · ${esc(NOMBRE)} (${esc(INI)} a ${esc(FIN)})</div>
  </div>

  <div style="padding:20px 26px">
    <table style="width:100%;border-collapse:separate;border-spacing:6px"><tr>
      ${kpi('Equipos', s.eq)}${kpi('Días-equipo', s.dias)}${kpi('Disp. física', pct(dispFis))}
      ${kpi('Disp. inherente', pct(dispInh))}${kpi('MTBF', mtbf.toFixed(1) + ' d')}${kpi('MTTR', mttr.toFixed(1) + ' d')}
    </tr></table>

    <!-- Botón al reporte interactivo -->
    <div style="text-align:center;margin:20px 0 8px">
      <a href="${LINK}" style="display:inline-block;background:#16a34a;color:#fff;text-decoration:none;font-weight:700;font-size:15px;padding:13px 26px;border-radius:10px">
        ▶ Ver reporte interactivo — click en cada patente para su historial
      </a>
      <div style="font-size:11px;color:#94a3b8;margin-top:6px">${esc(LINK)}</div>
    </div>

    <div style="font-size:16px;font-weight:700;color:#0b2a4a;border-bottom:2px solid #e5e7eb;padding-bottom:6px;margin-top:18px">KPIs por categoría</div>
    <table style="width:100%;border-collapse:collapse;margin-top:10px;font-size:13px">
      <thead><tr style="background:#f1f5f9;text-align:left;color:#475569">
        <th style="padding:8px;border:1px solid #e5e7eb">Categoría</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">Equipos</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">Disp. física</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">N° fallas</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">MTBF</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">MTTR</th>
      </tr></thead><tbody>
      ${cats.map((c) => `<tr>
        <td style="padding:8px;border:1px solid #e5e7eb">${CAT[c.categoria] || c.categoria || 'Sin categoría'}</td>
        <td style="padding:8px;border:1px solid #e5e7eb;text-align:right">${c.total_equipos}</td>
        <td style="padding:8px;border:1px solid #e5e7eb;text-align:right">${pct(c.disponibilidad_fisica)}</td>
        <td style="padding:8px;border:1px solid #e5e7eb;text-align:right">${c.eventos_falla_total}</td>
        <td style="padding:8px;border:1px solid #e5e7eb;text-align:right">${Number(c.mtbf_agregado).toFixed(1)}</td>
        <td style="padding:8px;border:1px solid #e5e7eb;text-align:right">${Number(c.mttr_agregado).toFixed(1)}</td>
      </tr>`).join('')}
      </tbody>
    </table>

    <div style="font-size:16px;font-weight:700;color:#0b2a4a;border-bottom:2px solid #e5e7eb;padding-bottom:6px;margin-top:20px">Menor disponibilidad inherente</div>
    <table style="width:100%;border-collapse:collapse;margin-top:10px;font-size:13px">
      <thead><tr style="background:#f1f5f9;text-align:left;color:#475569">
        <th style="padding:8px;border:1px solid #e5e7eb">Patente</th>
        <th style="padding:8px;border:1px solid #e5e7eb">Equipo</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">Días fuera</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">Disp. inherente</th>
      </tr></thead><tbody>
      ${peores.map((e) => `<tr>
        <td style="padding:8px;border:1px solid #e5e7eb;font-family:monospace"><b>${esc(e.patente)}</b></td>
        <td style="padding:8px;border:1px solid #e5e7eb;color:#475569">${esc(e.equipamiento)}</td>
        <td style="padding:8px;border:1px solid #e5e7eb;text-align:right;color:#dc2626">${e.dias_down}</td>
        <td style="padding:8px;border:1px solid #e5e7eb;text-align:right;font-weight:700">${pct(e.disponibilidad_inherente)}</td>
      </tr>`).join('')}
      </tbody>
    </table>
    <div style="font-size:11px;color:#94a3b8;margin-top:10px">
      Disp. inherente = MTBF ÷ (MTBF + MTTR). El detalle por patente y el historial diario están en el reporte interactivo (botón verde).
    </div>
  </div>

  <div style="background:#0b2a4a;color:#cbd5e1;padding:14px 26px;font-size:11px">Análisis de Fiabilidad ${esc(NOMBRE)} · SICOM-ICEO Pillado</div>
</div></body></html>`

  const outDir = resolve(__dirname, '../../reportes')
  mkdirSync(outDir, { recursive: true })
  const outPath = resolve(outDir, `Reporte_Fiabilidad_${NOMBRE.replace(/\s+/g, '_')}.html`)
  writeFileSync(outPath, html, 'utf8')
  console.log(`OK -> ${outPath}`)
  console.log(`Equipos: ${equipos.length} | Disp.inh: ${pct(dispInh)} | Link: ${LINK}`)
}

main().catch((e) => { console.error('ERROR:', e.message); process.exit(1) })
