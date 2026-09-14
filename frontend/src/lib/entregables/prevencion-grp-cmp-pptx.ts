// ============================================================================
// Informe GRP mensual CMP — PPTX (MIG557)
// ----------------------------------------------------------------------------
// El formato real de Romeral es una presentación («8. <mes> - REPORTE GESTIÓN
// MENSUAL PILLADO Y CIA.pptx», 4 láminas). Se replica editable con pptxgenjs:
//   1 Portada · 2 Descripción del programa (fija, del formato CMP) ·
//   3 LA lámina de datos (indicadores + VCT + GRP + emergencia + CPHS + SSO +
//     campañas + fotos) · 4 Cierre.
// Reemplaza al PDF de MIG547: prevención lo puede retocar antes de enviar.
// ============================================================================

import PptxGenJS from 'pptxgenjs'
import type {
  FaenaConfigDatos, GestionMensualFila, IndicadoresFila, PrevencionRegistro,
} from '@/lib/services/prevencion-reportabilidad'
import { urlEvidencia } from '@/lib/services/prevencion-reportabilidad'

const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
  'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']

const AZUL = '1F4E78'
const GRISC = 'F2F2F2'

type Fila = GestionMensualFila | undefined
const val = (x: Fila, k: 'meta' | 'realizados' | 'abiertos' | 'cerrados') => String(x?.[k] ?? 0)
const pct = (x: Fila) => !x || x.pct_cumplimiento === null
  ? (x && x.realizados > 0 ? 'extra' : '—')
  : `${x.pct_cumplimiento}%`

function cab(texto: string, cols: number): PptxGenJS.TableRow {
  return [{
    text: texto,
    options: { bold: true, color: 'FFFFFF', fill: { color: AZUL }, colspan: cols, align: 'center', fontSize: 8 },
  }]
}

function encabezados(cols: string[]): PptxGenJS.TableRow {
  return cols.map((c) => ({ text: c, options: { bold: true, fill: { color: GRISC }, fontSize: 7 } }))
}

async function fotoDataUrl(path: string): Promise<string | null> {
  const url = await urlEvidencia(path)
  if (!url) return null
  try {
    const res = await fetch(url)
    if (!res.ok) return null
    const blob = await res.blob()
    return await new Promise((resolve) => {
      const fr = new FileReader()
      fr.onload = () => resolve(fr.result as string)
      fr.onerror = () => resolve(null)
      fr.readAsDataURL(blob)
    })
  } catch { return null }
}

export async function generarGrpCmpPptx(params: {
  config: FaenaConfigDatos
  indicadores: IndicadoresFila | null
  gestion: GestionMensualFila[]
  registros: PrevencionRegistro[]
  anio: number
  mes: number
}): Promise<Blob> {
  const { config, indicadores, gestion, registros, anio, mes } = params
  const g = (c: string) => gestion.find((x) => x.tipo_codigo === c)
  const vct = g('VCT'); const vat = g('VAT'); const rit = g('RIT')
  const epf = g('EPF'); const cap = g('CAPACITACION')

  const pptx = new PptxGenJS()
  pptx.defineLayout({ name: 'W', width: 13.33, height: 7.5 })
  pptx.layout = 'W'

  // ── 1. Portada ──
  const s1 = pptx.addSlide()
  s1.background = { color: 'FFFFFF' }
  s1.addShape('rect', { x: 0, y: 0, w: 0.35, h: 7.5, fill: { color: AZUL } })
  s1.addText('GESTION GRP MENSUAL\nEMPRESAS COLABORADORAS', {
    x: 0.7, y: 1.9, w: 8.2, h: 1.6, fontSize: 34, bold: true, color: AZUL,
  })
  s1.addText(`${(config.empresa as any)?.razon_social ?? 'Pillado y Cía. Ltda.'} · ${MESES[mes - 1]} ${anio}`, {
    x: 0.7, y: 3.6, w: 8.2, h: 0.5, fontSize: 16, color: '444444',
  })
  s1.addText('GERENCIA DE SEGURIDAD Y SALUD OCUPACIONAL\nGestión de Riesgos · Seguridad · Salud Ocupacional · Protección Industrial · Emergencias', {
    x: 0.7, y: 6.1, w: 9, h: 0.8, fontSize: 10, color: AZUL,
  })

  // ── 2. Descripción del programa (texto fijo del formato CMP) ──
  const s2 = pptx.addSlide()
  s2.addShape('rect', { x: 0.4, y: 0.15, w: 12.5, h: 0.5, fill: { color: AZUL } })
  s2.addText('GESTION MENSUAL EMPRESAS COLABORADORAS', {
    x: 0.4, y: 0.15, w: 12.5, h: 0.5, fontSize: 14, bold: true, color: 'FFFFFF', align: 'center',
  })
  s2.addText('Objetivos:\n✓ Verificación de actividades críticas y rutinarias de la faena.\n✓ Reforzamiento y verificación herramientas GRP.\n✓ Verificación requisitos legales Procesos.', {
    x: 0.6, y: 0.8, w: 8, h: 1.1, fontSize: 10,
  })
  s2.addTable([
    encabezados(['ACTIVIDAD', 'TAREA', 'FRECUENCIA', 'DIRIGIDO', 'RESPONSABLE EJECUCIÓN', 'KPI']),
    [{ text: 'VERIFICACIÓN SEMANAL ACTIVIDADES CRITICAS Y RUTINARIAS', options: { fontSize: 7 } },
     { text: 'VCT semanal actividades críticas de la operación asegurando la aplicación de la caja 1, 2 y 3 según roles.', options: { fontSize: 7 } },
     { text: 'SEMANAL', options: { fontSize: 7, align: 'center' } },
     { text: 'PROCESOS CMP-EECC', options: { fontSize: 7, align: 'center', rowspan: 5 } },
     { text: 'APR EMPRESAS COLABORADORAS', options: { fontSize: 7, align: 'center', rowspan: 5 } },
     { text: '100% DE ADHERENCIA', options: { fontSize: 7, align: 'center', rowspan: 5 } }],
    [{ text: 'ACOMPAÑAMIENTO EN HERRAMIENTAS GRP', options: { fontSize: 7 } },
     { text: 'Acompañamiento a administradores y supervisores de EECC en la correcta ejecución de las herramientas GRP: RIT/VAT/VCT/INSTRUCTIVOS/EPF.', options: { fontSize: 7 } },
     { text: 'MENSUAL', options: { fontSize: 7, align: 'center', rowspan: 4 } }],
    [{ text: 'VERIFICACIÓN PROTOCOLOS MINSAL', options: { fontSize: 7 } },
     { text: 'VCT a las pautas establecidas por el MINSAL para evitar la detención de los procesos por incumplimientos de aspectos legales (JSO-APR-EXPERTO MUTUAL).', options: { fontSize: 7 } }],
    [{ text: 'VERIFICACIÓN CPHS Y/O CPHSF', options: { fontSize: 7 } },
     { text: 'VCT de documentación legal (DS N°54) para evitar la detención de los procesos por incumplimientos de aspectos legales.', options: { fontSize: 7 } }],
    [{ text: 'VERIFICACIÓN ACCIDENTES GRAVES Y/O FATALES DE LA INDUSTRIA', options: { fontSize: 7 } },
     { text: 'VCT a las pautas establecidas por la SUSESO, SNGM, SEREMI de Salud y Dirección del Trabajo.', options: { fontSize: 7 } }],
  ], { x: 0.4, y: 2.1, w: 12.5, border: { pt: 0.5, color: '999999' }, autoPage: false })

  // ── 3. LA lámina de datos ──
  const s3 = pptx.addSlide()
  s3.addShape('rect', { x: 0.4, y: 0.1, w: 12.5, h: 0.45, fill: { color: AZUL } })
  s3.addText(`GESTION MENSUAL EMPRESAS COLABORADORAS — ${MESES[mes - 1]} ${anio}`, {
    x: 0.4, y: 0.1, w: 12.5, h: 0.45, fontSize: 13, bold: true, color: 'FFFFFF', align: 'center',
  })

  // Indicadores de seguridad (izquierda)
  const indRows: PptxGenJS.TableRow[] = [
    cab('INDICADORES DE SEGURIDAD', 2),
    ...([['DOTACION', indicadores?.dotacion_total], ['HH', indicadores?.hh_total],
      ['ACCIDENTE CTP', indicadores?.accidentes_ctp], ['DIAS PERDIDOS', indicadores?.dias_perdidos],
      ['INDICE DE FRECUENCIA', indicadores?.indice_frecuencia], ['INDICE GRAVEDAD', indicadores?.indice_gravedad],
      ['ACCIDENTE STP', indicadores?.accidentes_stp], ['ALTO POTENCIAL', indicadores?.incidentes_alto_potencial],
      ['ACCIDENTE DE TRAYECTO', indicadores?.accidentes_trayecto]] as Array<[string, unknown]>)
      .map(([l, v]) => [
        { text: String(l), options: { fontSize: 7.5, fill: { color: GRISC } } },
        { text: v === undefined || v === null ? 'S/D' : String(v), options: { fontSize: 8, bold: true, align: 'center' } },
      ] as PptxGenJS.TableRow),
  ]
  s3.addTable(indRows, { x: 0.4, y: 0.7, w: 2.3, border: { pt: 0.5, color: '999999' } })

  // VCT (centro arriba)
  s3.addTable([
    cab('GESTION VCT MENSUAL', 6),
    encabezados(['GESTION', 'PLANIFICADO', 'REAL', '% CUMPL.', 'ABIERTOS', 'CERRADOS']),
    [{ text: 'VCT GESTOR DE RIESGOS', options: { fontSize: 7 } },
     ...['N/A', 'N/A', 'N/A', 'N/A', 'N/A'].map((t) => ({ text: t, options: { fontSize: 7, align: 'center' as const } }))],
    [{ text: 'VCT EMPRESA COLABORADORA', options: { fontSize: 7 } },
     { text: val(vct, 'meta'), options: { fontSize: 7, align: 'center' } },
     { text: val(vct, 'realizados'), options: { fontSize: 7, align: 'center' } },
     { text: pct(vct), options: { fontSize: 7, align: 'center' } },
     { text: val(vct, 'abiertos'), options: { fontSize: 7, align: 'center' } },
     { text: val(vct, 'cerrados'), options: { fontSize: 7, align: 'center' } }],
  ], { x: 2.85, y: 0.7, w: 3.9, border: { pt: 0.5, color: '999999' } })

  // GRP (centro abajo)
  s3.addTable([
    cab('GESTION GRP MENSUAL', 4),
    encabezados(['GESTION', 'PLANIFICADO', 'REAL', '% CUMPLIMIENTO']),
    ...([['VAT MENSUALES', vat], ['RIT MENSUALES', rit], ['CHECK LIST EPF', epf],
      ['CAPACITACIONES', cap]] as Array<[string, Fila]>).map(([n, x]) => [
      { text: n, options: { fontSize: 7 } },
      { text: val(x, 'meta'), options: { fontSize: 7, align: 'center' as const } },
      { text: val(x, 'realizados'), options: { fontSize: 7, align: 'center' as const } },
      { text: pct(x), options: { fontSize: 7, align: 'center' as const } },
    ] as PptxGenJS.TableRow),
  ], { x: 2.85, y: 2.75, w: 3.9, border: { pt: 0.5, color: '999999' } })

  // Emergencia + CPHS (derecha arriba)
  s3.addTable([
    cab('EMERGENCIA', 4),
    encabezados(['AMBITO', 'PLANIF.', 'REAL', '% CUMPL.']),
    [{ text: 'SIMULACROS', options: { fontSize: 7 } },
     { text: val(g('SIMULACRO'), 'meta'), options: { fontSize: 7, align: 'center' } },
     { text: val(g('SIMULACRO'), 'realizados'), options: { fontSize: 7, align: 'center' } },
     { text: pct(g('SIMULACRO')), options: { fontSize: 7, align: 'center' } }],
  ], { x: 6.9, y: 0.7, w: 3.0, border: { pt: 0.5, color: '999999' } })

  s3.addTable([
    cab('CPHS', 4),
    encabezados(['AMBITO', 'PLANIF.', 'REAL', '% CUMPL.']),
    [{ text: 'ACTIVIDADES PROGRAMA MENSUAL', options: { fontSize: 7 } },
     ...['N/A', 'N/A', 'N/A'].map((t) => ({ text: t, options: { fontSize: 7, align: 'center' as const } }))],
  ], { x: 10.05, y: 0.7, w: 2.85, border: { pt: 0.5, color: '999999' } })

  // SSO + campañas (derecha abajo)
  s3.addTable([
    cab('GESTION DE SSO', 4),
    encabezados(['ÁMBITO', 'PLANIF.', 'REAL', '% CUMPL.']),
    [{ text: 'PROTOCOLOS MINSAL', options: { fontSize: 7 } },
     ...['', '', ''].map((t) => ({ text: t, options: { fontSize: 7, align: 'center' as const } }))],
    [{ text: 'EXAMEN PRE-OCUPACIONALES', options: { fontSize: 7 } },
     ...['', '', ''].map((t) => ({ text: t, options: { fontSize: 7, align: 'center' as const } }))],
    [{ text: 'EXAMEN PSICOSENSOTECNICOS', options: { fontSize: 7 } },
     ...['', '', ''].map((t) => ({ text: t, options: { fontSize: 7, align: 'center' as const } }))],
  ], { x: 6.9, y: 2.75, w: 3.0, border: { pt: 0.5, color: '999999' } })

  const camp = g('CAMPANA')
  s3.addTable([
    cab('CAMPAÑAS', 4),
    encabezados(['ÁMBITO', 'PLANIF.', 'REAL', '% CUMPL.']),
    [{ text: 'CAMPAÑAS', options: { fontSize: 7 } },
     { text: val(camp, 'meta'), options: { fontSize: 7, align: 'center' } },
     { text: val(camp, 'realizados'), options: { fontSize: 7, align: 'center' } },
     { text: pct(camp), options: { fontSize: 7, align: 'center' } }],
  ], { x: 10.05, y: 2.75, w: 2.85, border: { pt: 0.5, color: '999999' } })

  // Iniciativas / fotos (franja inferior)
  s3.addTable([
    [{ text: 'INICIATIVAS', options: { bold: true, color: 'FFFFFF', fill: { color: AZUL }, fontSize: 8, align: 'center' } },
     { text: 'FOTOGRAFIAS ACTIVIDADES RELEVANTES', options: { bold: true, color: 'FFFFFF', fill: { color: AZUL }, fontSize: 8, align: 'center' } }],
  ], { x: 0.4, y: 4.75, w: 12.5, colW: [6.25, 6.25], border: { pt: 0.5, color: '999999' } })

  const conFoto = registros
    .filter((r) => (r.evidencias?.length ?? 0) > 0)
    .sort((a) => (a.tipo_codigo === 'CAMPANA' ? -1 : 1))
    .slice(0, 3)
  let fx = 6.9
  for (const r of conFoto) {
    const ev = (r.evidencias ?? []).find((e) => e.content_type.startsWith('image/'))
    if (!ev) continue
    const data = await fotoDataUrl(ev.path)
    if (data) {
      s3.addImage({ data, x: fx, y: 5.2, w: 1.9, h: 1.7, sizing: { type: 'contain', w: 1.9, h: 1.7 } })
      s3.addText(`${r.tipo_codigo} · ${r.titulo}`.slice(0, 60), { x: fx, y: 6.9, w: 1.9, h: 0.3, fontSize: 6, color: '555555' })
      fx += 2.05
    }
  }
  s3.addText(`Elaborado: ${(config.experto as any)?.nombre ?? ''} · ${new Date().toLocaleDateString('es-CL')}`, {
    x: 0.5, y: 5.2, w: 5.9, h: 0.4, fontSize: 8, color: '555555',
  })

  // ── 4. Cierre ──
  const s4 = pptx.addSlide()
  s4.background = { color: AZUL }
  s4.addText('GRP', { x: 4.6, y: 3, w: 4, h: 1.4, fontSize: 54, bold: true, color: 'FFFFFF', align: 'center' })

  const out = await pptx.write({ outputType: 'blob' })
  return out as Blob
}
