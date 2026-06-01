#!/usr/bin/env node
// ============================================================================
// generar-reporte-outlook.mjs
// ----------------------------------------------------------------------------
// Genera un HTML autocontenido del reporte de flota (Cierre de mes + Status
// actual) para enviarlo MANUALMENTE desde Outlook: abrir el archivo, Ctrl+A,
// Ctrl+C y pegar en un correo nuevo (mantiene el formato), o adjuntarlo.
//
// Uso:
//   node generar-reporte-outlook.mjs                 (mes anterior por defecto)
//   node generar-reporte-outlook.mjs 2026-05-01 2026-05-31 "Mayo 2026"
// ============================================================================

import { writeFileSync, mkdirSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })

const [argIni, argFin, argNombre] = process.argv.slice(2)
const MES_INI = argIni || '2026-05-01'
const MES_FIN = argFin || '2026-05-31'
const MES_NOMBRE = argNombre || 'Mayo 2026'

const client = new pg.Client({
  connectionString: (process.env.SUPABASE_DB_URL || '').trim(),
  ssl: { rejectUnauthorized: false },
})

const ESTADO = {
  A: ['Arrendado', '#16A34A'], C: ['En contrato', '#15803D'], D: ['Disponible', '#2563EB'],
  L: ['Leasing', '#4F46E5'], U: ['Uso interno', '#0891B2'], R: ['Recepción', '#06B6D4'],
  H: ['Habilitación', '#A855F7'], M: ['Mantención', '#F59E0B'], T: ['Taller', '#FB923C'],
  F: ['Fuera de servicio', '#DC2626'], V: ['Venta', '#9333EA'],
}
const CAT = {
  arriendo_comercial: 'Arriendo comercial', leasing_operativo: 'Leasing operativo',
  uso_interno: 'Uso interno', venta: 'Venta',
}
const pct = (v) => v == null ? '—' : `${(Number(v) * 100).toFixed(1)}%`
const esc = (s) => String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]))

async function main() {
  await client.connect()

  const may = (await client.query(
    `SELECT to_jsonb(k) j FROM fn_calcular_fiabilidad_flota($1,$2) k`, [MES_INI, MES_FIN],
  )).rows.map((r) => r.j)

  const rep = (await client.query(`SELECT fn_reporte_flota_publico() j`)).rows[0].j
  const mant = (await client.query(`SELECT to_jsonb(m) j FROM fn_flota_en_mantenimiento() m`)).rows.map((r) => r.j)

  const comb = (await client.query(
    `SELECT estanque_codigo, estanque_nombre, capacidad_lt, stock_actual, stock_minimo,
            dias_cobertura, fecha_agotamiento_estimada, severidad
       FROM v_combustible_proyeccion_stock ORDER BY severidad, estanque_codigo`,
  )).rows

  await client.end()

  // ── Agregados del mes ──
  const sum = (k) => may.reduce((a, c) => a + Number(c[k] || 0), 0)
  const diasEq = sum('dias_equipo'), diasUp = sum('dias_up'), diasDn = sum('dias_down')
  const eventos = sum('eventos_falla_total'), equipos = sum('total_equipos')
  const dispMes = diasEq > 0 ? diasUp / diasEq : 0
  const utilMes = diasEq > 0 ? (may.reduce((a, c) => a + Number(c.utilizacion_bruta || 0) * Number(c.dias_equipo || 0), 0) / diasEq) : 0
  const mtbfMes = eventos > 0 ? diasUp / eventos : diasUp
  const mttrMes = eventos > 0 ? diasDn / eventos : 0

  // ── Snapshot actual (status) ──
  const porEstado = rep.por_estado || {}
  const ordenEstado = ['A', 'C', 'L', 'U', 'D', 'R', 'H', 'M', 'T', 'F', 'V']
  const disponibles = (rep.equipos || []).filter((e) => e.estado === 'D')

  const kpi = (label, val, sub) => `
    <td style="padding:10px;border:1px solid #e5e7eb;border-radius:8px;text-align:center;background:#f8fafc">
      <div style="font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:.04em">${label}</div>
      <div style="font-size:22px;font-weight:700;color:#0b2a4a;margin-top:2px">${val}</div>
      ${sub ? `<div style="font-size:10px;color:#94a3b8">${sub}</div>` : ''}
    </td>`

  const SEV = {
    agotado: ['Agotado', '#7f1d1d', '#fef2f2'], critico: ['Crítico', '#dc2626', '#fef2f2'],
    urgente: ['Urgente', '#ea580c', '#fff7ed'], atencion: ['Atención', '#d97706', '#fffbeb'],
    ok: ['OK', '#16a34a', '#f0fdf4'],
  }
  const fdate = (d) => d ? String(d).slice(0, 10) : '—'
  const combTot = comb.reduce((a, e) => ({
    cap: a.cap + Number(e.capacidad_lt || 0),
    st: a.st + Number(e.stock_actual || 0),
    min: a.min + Number(e.stock_minimo || 0),
  }), { cap: 0, st: 0, min: 0 })
  const lt = (v) => Math.round(Number(v || 0)).toLocaleString('es-CL')

  const estadoBadge = (c, n) => `
    <span style="display:inline-block;margin:2px 4px 2px 0;padding:3px 8px;border-radius:6px;font-size:12px;
      color:#fff;background:${ESTADO[c] ? ESTADO[c][1] : '#6b7280'}">
      ${c} · ${ESTADO[c] ? ESTADO[c][0] : c}: <b>${n}</b>
    </span>`

  const html = `<!doctype html><html lang="es"><head><meta charset="utf-8">
<title>Reporte de Flota — Cierre ${MES_NOMBRE}</title></head>
<body style="margin:0;background:#f1f5f9;font-family:Segoe UI,Arial,sans-serif;color:#1f2937">
<div style="max-width:780px;margin:0 auto;background:#fff">

  <div style="background:linear-gradient(90deg,#0b2a4a,#155e9c);color:#fff;padding:22px 26px">
    <div style="font-size:20px;font-weight:700">Reporte de Flota — Pillado</div>
    <div style="font-size:13px;opacity:.85;margin-top:3px">
      Cierre de ${MES_NOMBRE} &nbsp;·&nbsp; Status de flota al ${esc(rep.fecha)}
    </div>
  </div>

  <!-- ── Cierre de mes ── -->
  <div style="padding:20px 26px">
    <div style="font-size:16px;font-weight:700;color:#0b2a4a;border-bottom:2px solid #e5e7eb;padding-bottom:6px">
      1 · Cierre de ${MES_NOMBRE}
    </div>
    <table style="width:100%;border-collapse:separate;border-spacing:6px;margin-top:12px"><tr>
      ${kpi('Equipos', equipos)}
      ${kpi('Días-equipo', diasEq)}
      ${kpi('Disponibilidad', pct(dispMes), 'física')}
      ${kpi('Utilización', pct(utilMes), 'bruta')}
      ${kpi('MTBF', mtbfMes.toFixed(1) + ' d')}
      ${kpi('MTTR', mttrMes.toFixed(1) + ' d')}
    </tr></table>

    <table style="width:100%;border-collapse:collapse;margin-top:14px;font-size:13px">
      <thead><tr style="background:#f1f5f9;text-align:left;color:#475569">
        <th style="padding:8px;border:1px solid #e5e7eb">Categoría</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">Equipos</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">Disp. física</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">Utilización</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">N° fallas</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">MTBF</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">MTTR</th>
      </tr></thead><tbody>
      ${may.map((c) => `<tr>
        <td style="padding:8px;border:1px solid #e5e7eb">${CAT[c.categoria] || c.categoria || 'Sin categoría'}</td>
        <td style="padding:8px;border:1px solid #e5e7eb;text-align:right">${c.total_equipos}</td>
        <td style="padding:8px;border:1px solid #e5e7eb;text-align:right">${pct(c.disponibilidad_fisica)}</td>
        <td style="padding:8px;border:1px solid #e5e7eb;text-align:right">${pct(c.utilizacion_bruta)}</td>
        <td style="padding:8px;border:1px solid #e5e7eb;text-align:right">${c.eventos_falla_total}</td>
        <td style="padding:8px;border:1px solid #e5e7eb;text-align:right">${Number(c.mtbf_agregado).toFixed(1)}</td>
        <td style="padding:8px;border:1px solid #e5e7eb;text-align:right">${Number(c.mttr_agregado).toFixed(1)}</td>
      </tr>`).join('')}
      </tbody>
    </table>
  </div>

  <!-- ── Status actual ── -->
  <div style="padding:6px 26px 24px">
    <div style="font-size:16px;font-weight:700;color:#0b2a4a;border-bottom:2px solid #e5e7eb;padding-bottom:6px">
      2 · Status de flota entrando a Junio <span style="font-weight:400;font-size:12px;color:#94a3b8">(foto al ${esc(rep.fecha)}, último día cerrado)</span>
    </div>
    <table style="width:100%;border-collapse:separate;border-spacing:6px;margin-top:12px"><tr>
      ${kpi('Equipos', rep.total)}
      ${kpi('Disponibilidad', pct((rep.disponibilidad ?? 0) / 100))}
      ${kpi('Utilización', pct((rep.utilizacion ?? 0) / 100))}
      ${kpi('Coquimbo', (rep.por_operacion || {}).Coquimbo ?? 0)}
      ${kpi('Calama', (rep.por_operacion || {}).Calama ?? 0)}
    </tr></table>

    <div style="margin-top:14px;font-size:13px;font-weight:600;color:#334155">Distribución por estado</div>
    <div style="margin-top:6px">
      ${ordenEstado.filter((c) => porEstado[c]).map((c) => estadoBadge(c, porEstado[c])).join('')}
    </div>

    <div style="margin-top:18px;font-size:13px;font-weight:600;color:#334155">
      Equipos disponibles sin arriendo (${disponibles.length}) — oportunidad comercial
    </div>
    <table style="width:100%;border-collapse:collapse;margin-top:6px;font-size:13px">
      <thead><tr style="background:#f1f5f9;text-align:left;color:#475569">
        <th style="padding:7px;border:1px solid #e5e7eb">Patente</th>
        <th style="padding:7px;border:1px solid #e5e7eb">Equipamiento</th>
        <th style="padding:7px;border:1px solid #e5e7eb">Último cliente</th>
      </tr></thead><tbody>
      ${disponibles.length ? disponibles.map((e) => `<tr>
        <td style="padding:7px;border:1px solid #e5e7eb;font-family:monospace">${esc(e.patente)}</td>
        <td style="padding:7px;border:1px solid #e5e7eb">${esc(e.equipamiento)}</td>
        <td style="padding:7px;border:1px solid #e5e7eb;color:#64748b">${esc(e.ultimo_cliente) || '—'}</td>
      </tr>`).join('') : `<tr><td colspan="3" style="padding:10px;border:1px solid #e5e7eb;color:#94a3b8;text-align:center">Sin equipos disponibles</td></tr>`}
      </tbody>
    </table>

    <div style="margin-top:18px;font-size:13px;font-weight:600;color:#334155">
      Equipos en mantención / fuera de servicio (${mant.length})
    </div>
    <table style="width:100%;border-collapse:collapse;margin-top:6px;font-size:13px">
      <thead><tr style="background:#f1f5f9;text-align:left;color:#475569">
        <th style="padding:7px;border:1px solid #e5e7eb">Patente</th>
        <th style="padding:7px;border:1px solid #e5e7eb">Equipamiento</th>
        <th style="padding:7px;border:1px solid #e5e7eb;text-align:right">Días</th>
        <th style="padding:7px;border:1px solid #e5e7eb">Contrato</th>
      </tr></thead><tbody>
      ${mant.length ? mant.map((m) => `<tr>
        <td style="padding:7px;border:1px solid #e5e7eb;font-family:monospace">${esc(m.patente)}</td>
        <td style="padding:7px;border:1px solid #e5e7eb">${esc(m.equipamiento)}</td>
        <td style="padding:7px;border:1px solid #e5e7eb;text-align:right">${m.dias_mantencion ?? '—'}</td>
        <td style="padding:7px;border:1px solid #e5e7eb;color:#64748b">${esc(m.ultimo_contrato) || '—'}</td>
      </tr>`).join('') : `<tr><td colspan="4" style="padding:10px;border:1px solid #e5e7eb;color:#94a3b8;text-align:center">Sin equipos en mantención</td></tr>`}
      </tbody>
    </table>
  </div>

  <!-- ── Stock de combustible ── -->
  <div style="padding:6px 26px 24px">
    <div style="font-size:16px;font-weight:700;color:#0b2a4a;border-bottom:2px solid #e5e7eb;padding-bottom:6px">
      3 · Stock de combustible
    </div>
    <table style="width:100%;border-collapse:collapse;margin-top:12px;font-size:13px">
      <thead><tr style="background:#f1f5f9;text-align:left;color:#475569">
        <th style="padding:8px;border:1px solid #e5e7eb">Estanque</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">Capacidad</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">Stock actual</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">% lleno</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">Mínimo</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:right">Cobertura</th>
        <th style="padding:8px;border:1px solid #e5e7eb">Agotamiento est.</th>
        <th style="padding:8px;border:1px solid #e5e7eb;text-align:center">Estado</th>
      </tr></thead><tbody>
      ${comb.map((e) => {
        const cap = Number(e.capacidad_lt || 0), st = Number(e.stock_actual || 0)
        const llen = cap > 0 ? Math.round(st / cap * 100) : 0
        const sev = SEV[e.severidad] || SEV.ok
        const fmt = (v) => Math.round(Number(v || 0)).toLocaleString('es-CL')
        return `<tr style="background:${sev[2]}">
          <td style="padding:8px;border:1px solid #e5e7eb"><b>${esc(e.estanque_codigo)}</b><div style="font-size:10px;color:#94a3b8">${esc(e.estanque_nombre)}</div></td>
          <td style="padding:8px;border:1px solid #e5e7eb;text-align:right">${fmt(cap)} L</td>
          <td style="padding:8px;border:1px solid #e5e7eb;text-align:right"><b>${fmt(st)} L</b></td>
          <td style="padding:8px;border:1px solid #e5e7eb;text-align:right">${llen}%</td>
          <td style="padding:8px;border:1px solid #e5e7eb;text-align:right;color:#94a3b8">${fmt(e.stock_minimo)} L</td>
          <td style="padding:8px;border:1px solid #e5e7eb;text-align:right">${e.dias_cobertura != null ? Number(e.dias_cobertura).toFixed(1) + ' d' : '—'}</td>
          <td style="padding:8px;border:1px solid #e5e7eb">${fdate(e.fecha_agotamiento_estimada)}</td>
          <td style="padding:8px;border:1px solid #e5e7eb;text-align:center">
            <span style="display:inline-block;padding:3px 8px;border-radius:6px;font-size:11px;font-weight:600;color:#fff;background:${sev[1]}">${sev[0]}</span>
          </td>
        </tr>`
      }).join('')}
      </tbody>
      <tfoot><tr style="background:#0b2a4a;color:#fff;font-weight:700">
        <td style="padding:9px;border:1px solid #0b2a4a">CONSOLIDADO (${comb.length} estanques)</td>
        <td style="padding:9px;border:1px solid #0b2a4a;text-align:right">${lt(combTot.cap)} L</td>
        <td style="padding:9px;border:1px solid #0b2a4a;text-align:right">${lt(combTot.st)} L</td>
        <td style="padding:9px;border:1px solid #0b2a4a;text-align:right">${combTot.cap > 0 ? Math.round(combTot.st / combTot.cap * 100) : 0}%</td>
        <td style="padding:9px;border:1px solid #0b2a4a;text-align:right">${lt(combTot.min)} L</td>
        <td style="padding:9px;border:1px solid #0b2a4a;text-align:center" colspan="3">Stock total disponible en sistema</td>
      </tr></tfoot>
    </table>
    <div style="font-size:11px;color:#94a3b8;margin-top:8px">
      Cobertura = días estimados de stock al ritmo de consumo reciente. "Agotamiento est." proyecta cuándo se llega al stock mínimo.
    </div>
  </div>

  <div style="background:#0b2a4a;color:#cbd5e1;padding:14px 26px;font-size:11px">
    Generado el ${esc(rep.fecha)} · SICOM-ICEO Pillado · Indicadores: Disp.física = días operativos ÷ días-equipo · MTBF/MTTR en días.
  </div>
</div></body></html>`

  const outDir = resolve(__dirname, '../../reportes')
  mkdirSync(outDir, { recursive: true })
  const outPath = resolve(outDir, `Reporte_Flota_Cierre_${MES_NOMBRE.replace(/\s+/g, '_')}.html`)
  writeFileSync(outPath, html, 'utf8')
  console.log(`OK -> ${outPath}`)
  console.log(`Mes: ${MES_NOMBRE} (${MES_INI}..${MES_FIN}) | Status al: ${rep.fecha}`)
}

main().catch((e) => { console.error('ERROR:', e.message); process.exit(1) })
