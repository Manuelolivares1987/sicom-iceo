#!/usr/bin/env node
// ============================================================================
// generar-reporte-comercial-outlook.mjs
// ----------------------------------------------------------------------------
// Genera un HTML autocontenido del CIERRE COMERCIAL del mes para enviar
// MANUALMENTE desde Outlook (abrir, Ctrl+A, Ctrl+C, pegar en el correo).
// Enfoque comercial: resumen por contrato + detalle por patente (dias en
// contrato/arriendo, leasing, operativos y fuera de servicio).
//
// Uso:
//   node generar-reporte-comercial-outlook.mjs                       (mayo 2026)
//   node generar-reporte-comercial-outlook.mjs 2026-06-01 2026-06-30 "Junio 2026"
// ============================================================================

import { writeFileSync, mkdirSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })

const [argIni, argFin, argNombre] = process.argv.slice(2)
const INI = argIni || '2026-05-01'
const FIN = argFin || '2026-05-31'
const NOMBRE = argNombre || 'Mayo 2026'
const TIPOS = ['camion_cisterna', 'camion', 'camioneta', 'lubrimovil', 'equipo_menor']

const client = new pg.Client({
  connectionString: (process.env.SUPABASE_DB_URL || '').trim(),
  ssl: { rejectUnauthorized: false },
})

const esc = (s) => String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]))
const disp = (up, obs) => obs > 0 ? `${(up / obs * 100).toFixed(1)}%` : '—'

const SQL_CONTRATO = `
  SELECT COALESCE(c.codigo,'(sin contrato)') AS contrato, COALESCE(c.cliente,'—') AS cliente,
         count(DISTINCT a.id) AS patentes, count(*) AS dias_obs,
         count(*) FILTER (WHERE e.estado_codigo IN ('A','C')) AS dias_arriendo,
         count(*) FILTER (WHERE e.estado_codigo='L') AS dias_leasing,
         count(*) FILTER (WHERE e.estado_codigo NOT IN ('M','T','F')) AS dias_up,
         count(*) FILTER (WHERE e.estado_codigo IN ('M','T','F')) AS dias_down
  FROM estado_diario_flota e
  JOIN activos a ON a.id=e.activo_id
  LEFT JOIN contratos c ON c.id=a.contrato_id
  WHERE e.fecha BETWEEN $1 AND $2 AND a.tipo = ANY($3)
  GROUP BY c.codigo, c.cliente
  HAVING count(*) FILTER (WHERE e.estado_codigo IN ('A','C','L')) > 0
  ORDER BY (count(*) FILTER (WHERE e.estado_codigo IN ('A','C')) +
            count(*) FILTER (WHERE e.estado_codigo='L')) DESC`

const SQL_PATENTE = `
  SELECT a.patente, a.nombre AS equipamiento,
         COALESCE(c.codigo,'(sin contrato)') AS contrato, COALESCE(c.cliente,'—') AS cliente,
         count(*) AS dias_obs,
         count(*) FILTER (WHERE e.estado_codigo='A') AS dias_a,
         count(*) FILTER (WHERE e.estado_codigo='C') AS dias_c,
         count(*) FILTER (WHERE e.estado_codigo='L') AS dias_l,
         count(*) FILTER (WHERE e.estado_codigo NOT IN ('M','T','F')) AS dias_up,
         count(*) FILTER (WHERE e.estado_codigo IN ('M','T','F')) AS dias_down,
         count(*) FILTER (WHERE e.estado_codigo='M') AS dias_m,
         count(*) FILTER (WHERE e.estado_codigo='T') AS dias_t,
         count(*) FILTER (WHERE e.estado_codigo='F') AS dias_f
  FROM estado_diario_flota e
  JOIN activos a ON a.id=e.activo_id
  LEFT JOIN contratos c ON c.id=a.contrato_id
  WHERE e.fecha BETWEEN $1 AND $2 AND a.tipo = ANY($3)
  GROUP BY a.patente, a.nombre, c.codigo, c.cliente
  HAVING count(*) FILTER (WHERE e.estado_codigo IN ('A','C','L')) > 0
  ORDER BY contrato, a.patente`

async function main() {
  await client.connect()
  const contratos = (await client.query(SQL_CONTRATO, [INI, FIN, TIPOS])).rows
  const patentes = (await client.query(SQL_PATENTE, [INI, FIN, TIPOS])).rows
  await client.end()

  const n = (v) => Number(v || 0)
  const totPat = patentes.length
  const totArriendo = contratos.reduce((a, c) => a + n(c.dias_arriendo), 0)
  const totLeasing = contratos.reduce((a, c) => a + n(c.dias_leasing), 0)
  const totUp = contratos.reduce((a, c) => a + n(c.dias_up), 0)
  const totObs = contratos.reduce((a, c) => a + n(c.dias_obs), 0)
  const totDown = contratos.reduce((a, c) => a + n(c.dias_down), 0)
  const nContratos = contratos.filter((c) => c.contrato !== '(sin contrato)').length

  const kpi = (label, val, sub) => `
    <td style="padding:10px;border:1px solid #e5e7eb;border-radius:8px;text-align:center;background:#f8fafc">
      <div style="font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:.04em">${label}</div>
      <div style="font-size:22px;font-weight:700;color:#0b2a4a;margin-top:2px">${val}</div>
      ${sub ? `<div style="font-size:10px;color:#94a3b8">${sub}</div>` : ''}
    </td>`
  const th = (t, r) => `<th style="padding:8px;border:1px solid #e5e7eb;text-align:${r ? 'right' : 'left'}">${t}</th>`
  const td = (t, r, extra = '') => `<td style="padding:7px;border:1px solid #e5e7eb;text-align:${r ? 'right' : 'left'};${extra}">${t}</td>`

  const html = `<!doctype html><html lang="es"><head><meta charset="utf-8">
<title>Cierre Comercial — ${NOMBRE}</title></head>
<body style="margin:0;background:#f1f5f9;font-family:Segoe UI,Arial,sans-serif;color:#1f2937">
<div style="max-width:820px;margin:0 auto;background:#fff">

  <div style="background:linear-gradient(90deg,#0b2a4a,#155e9c);color:#fff;padding:22px 26px">
    <div style="font-size:20px;font-weight:700">Cierre Comercial de Flota — Pillado</div>
    <div style="font-size:13px;opacity:.85;margin-top:3px">Período: ${NOMBRE} &nbsp;(${esc(INI)} a ${esc(FIN)})</div>
  </div>

  <div style="padding:20px 26px">
    <table style="width:100%;border-collapse:separate;border-spacing:6px"><tr>
      ${kpi('Contratos', nContratos)}
      ${kpi('Patentes en contrato/leasing', totPat)}
      ${kpi('Días arriendo', totArriendo, 'A + C')}
      ${kpi('Días leasing', totLeasing, 'L')}
      ${kpi('Días fuera', totDown, 'M/T/F')}
      ${kpi('Disponibilidad', disp(totUp, totObs))}
    </tr></table>

    <!-- ── Resumen por contrato ── -->
    <div style="font-size:16px;font-weight:700;color:#0b2a4a;border-bottom:2px solid #e5e7eb;padding-bottom:6px;margin-top:18px">
      1 · Resumen por contrato
    </div>
    <table style="width:100%;border-collapse:collapse;margin-top:10px;font-size:13px">
      <thead><tr style="background:#f1f5f9;color:#475569">
        ${th('Contrato')}${th('Cliente')}${th('Patentes', 1)}${th('Días arriendo', 1)}
        ${th('Días leasing', 1)}${th('Días operativos', 1)}${th('Días fuera', 1)}${th('Disp.', 1)}
      </tr></thead><tbody>
      ${contratos.map((c) => `<tr>
        ${td(`<b>${esc(c.contrato)}</b>`)}${td(esc(c.cliente), false, 'color:#64748b')}
        ${td(c.patentes, 1)}${td(c.dias_arriendo, 1)}${td(c.dias_leasing, 1)}
        ${td(`<span style="color:#16a34a">${c.dias_up}</span>`, 1)}
        ${td(`<span style="color:${n(c.dias_down) > 0 ? '#dc2626' : '#94a3b8'}">${c.dias_down}</span>`, 1)}
        ${td(disp(n(c.dias_up), n(c.dias_obs)), 1)}
      </tr>`).join('')}
      </tbody>
    </table>

    <!-- ── Detalle por patente ── -->
    <div style="font-size:16px;font-weight:700;color:#0b2a4a;border-bottom:2px solid #e5e7eb;padding-bottom:6px;margin-top:22px">
      2 · Detalle por patente (en contrato / leasing)
    </div>
    <table style="width:100%;border-collapse:collapse;margin-top:10px;font-size:12.5px">
      <thead><tr style="background:#f1f5f9;color:#475569">
        ${th('Patente')}${th('Equipamiento')}${th('Contrato / Cliente')}
        ${th('A', 1)}${th('C', 1)}${th('L', 1)}${th('Operativos', 1)}${th('Fuera', 1)}${th('Disp.', 1)}
      </tr></thead><tbody>
      ${patentes.map((p) => `<tr>
        ${td(`<b style="font-family:monospace">${esc(p.patente)}</b>`)}
        ${td(esc(p.equipamiento), false, 'color:#475569')}
        ${td(`${esc(p.contrato)}<div style="font-size:10px;color:#94a3b8">${esc(p.cliente)}</div>`)}
        ${td(p.dias_a, 1)}${td(p.dias_c, 1)}${td(p.dias_l, 1)}
        ${td(`<span style="color:#16a34a">${p.dias_up}</span>`, 1)}
        ${td(`<span style="color:${n(p.dias_down) > 0 ? '#dc2626' : '#94a3b8'}" title="M:${p.dias_m} T:${p.dias_t} F:${p.dias_f}">${p.dias_down}</span>`, 1)}
        ${td(disp(n(p.dias_up), n(p.dias_obs)), 1)}
      </tr>`).join('')}
      </tbody>
    </table>
    <div style="font-size:11px;color:#94a3b8;margin-top:8px">
      A = Arrendado · C = En contrato · L = Leasing · Operativos = días no-fuera · Fuera = Mantención/Taller/Fuera de servicio (M/T/F).
      Disponibilidad = días operativos ÷ días observados.
    </div>
  </div>

  <div style="background:#0b2a4a;color:#cbd5e1;padding:14px 26px;font-size:11px">
    Cierre comercial ${NOMBRE} · SICOM-ICEO Pillado · Generado desde estado_diario_flota.
  </div>
</div></body></html>`

  const outDir = resolve(__dirname, '../../reportes')
  mkdirSync(outDir, { recursive: true })
  const outPath = resolve(outDir, `Reporte_Comercial_${NOMBRE.replace(/\s+/g, '_')}.html`)
  writeFileSync(outPath, html, 'utf8')
  console.log(`OK -> ${outPath}`)
  console.log(`Contratos: ${nContratos} | Patentes en contrato/leasing: ${totPat} | Días arriendo: ${totArriendo} | leasing: ${totLeasing} | fuera: ${totDown}`)
}

main().catch((e) => { console.error('ERROR:', e.message); process.exit(1) })
