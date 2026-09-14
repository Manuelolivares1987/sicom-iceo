// ============================================================================
// Reporte de Cumplimiento Anexo 10.2 — Lomas Bayas (MIG558)
// ----------------------------------------------------------------------------
// Replica la ESTRUCTURA EXACTA del PPT real (38 láminas, 7 secciones, 28
// subsecciones): portada, una lámina por subsección con su título de sección
// y subsección. Las evidencias del supervisor (registros tipo ANEXO102 con la
// subsección elegida) van DENTRO de la lámina: fotos directas y PDF
// rasterizados (primera página, pdfjs). Subsección sin evidencia → el texto
// constante del formato («No aplica… dotación inferior a 25», etc.).
// ============================================================================

import PptxGenJS from 'pptxgenjs'
import type { PrevencionRegistro } from '@/lib/services/prevencion-reportabilidad'
import { urlEvidencia } from '@/lib/services/prevencion-reportabilidad'

const MESES = ['ENERO', 'FEBRERO', 'MARZO', 'ABRIL', 'MAYO', 'JUNIO', 'JULIO',
  'AGOSTO', 'SEPTIEMBRE', 'OCTUBRE', 'NOVIEMBRE', 'DICIEMBRE']

const AZUL = '1F4E78'
const GRIS = '444444'

// ── La guía: estructura del formato real, sección por sección ───────────────
// `constante` = lo que va cuando el mes no trae evidencia de esa subsección
// (los "No aplica" del formato son permanentes por dotación < 25).
type Sub = { num: string; titulo: string; constante?: string; siempreConstante?: boolean }
type Seccion = { titulo: string; subs: Sub[] }

const SIN_EVIDENCIA = 'Sin actividades registradas para este punto durante el período.'
const NO_APLICA_25 = 'No aplica este punto, dado que la dotación del contrato es inferior a 25 trabajadores.'

const ESTRUCTURA: Seccion[] = [
  { titulo: '1.- Liderazgo y responsabilidad', subs: [
    { num: '1.1', titulo: 'Cumplimiento mensual programa de liderazgo' },
    { num: '1.2', titulo: 'Se evidencia actividades de liderazgo en terreno por roles' },
    { num: '1.3', titulo: 'Cumplimiento de programa de reconocimiento al personal destacado en seguridad' },
    { num: '1.4', titulo: 'Cumplimiento programa de reforzamiento Conductas que salvan vidas/aplicación de procedimiento de gestión por consecuencia' },
    { num: '1.5', titulo: 'Asistencia a las reuniones mensuales del administrador de contrato de la ESE' },
    { num: '1.6', titulo: 'Asistencia a las reuniones semanales del Asesor HS de la ESE' },
  ]},
  { titulo: '2.- Gestión de riesgos y aspectos legales', subs: [
    { num: '2.1', titulo: 'Cumplimiento y actualización QRA (controles críticos, aprendizajes y eventos)' },
    { num: '2.2', titulo: 'Programa de difusión de los riesgos y sus controles y cartillas de controles críticos' },
    { num: '2.3', titulo: 'Matriz legal actualizada (evidencia referencial del documento)' },
    { num: '2.4', titulo: 'Reglamento interno de orden y seguridad' },
  ]},
  { titulo: '3.- Competencia y entrenamiento', subs: [
    { num: '3.1', titulo: 'Registro completado y aprobado, Anexo 6 LB-RG-SHS-ALL-0013 (acreditación Competencias HS por Rol)' },
    { num: '3.2', titulo: 'Capacitaciones ingresadas a plataforma webcontrol verificables por código QR' },
    { num: '3.3', titulo: 'Cumplimiento de programa de capacitaciones según Anexo 6 LB-RG-SHS-ALL-0013' },
  ]},
  { titulo: '4.- Salud ocupacional', subs: [
    { num: '4.1', titulo: 'Aspectos y evaluación de riesgos de higiene y salud ocupacional (QRA / Matriz SO)',
      constante: 'Se tiene incorporado a QRA aspectos y evaluación de riesgos de higiene y salud ocupacional (Sílice, Ruido, etc.).' },
    { num: '4.2', titulo: 'Autoevaluación diagnóstica de protocolos MINSAL y plan de cierre de brechas' },
    { num: '4.3', titulo: 'Proceso de gestión de casos relacionados con alcohol y drogas' },
    { num: '4.4', titulo: 'Plan para gestión de casos contraindicados o con observaciones (exámenes pre y ocupacionales)' },
    { num: '4.5', titulo: 'Programa de higiene y salud ocupacional' },
  ]},
  { titulo: '5.- Seguridad operativa', subs: [
    { num: '5.1', titulo: 'Acta de constitución CPHS', constante: NO_APLICA_25, siempreConstante: true },
    { num: '5.2', titulo: 'Registro de reuniones mensuales CPHS', constante: NO_APLICA_25, siempreConstante: true },
    { num: '5.3', titulo: 'Cumplimiento de acuerdos de actas CPHS', constante: NO_APLICA_25, siempreConstante: true },
    { num: '5.4', titulo: 'Registro de asistencias a reuniones CPHS de faena',
      constante: 'No aplica este punto dado que no contamos con comité paritario de higiene y seguridad por tener una dotación inferior a la requerida.', siempreConstante: true },
    { num: '5.5', titulo: 'Registro de entrega E-200 / HH', constante: 'Se evidencia entrega de requerimiento.' },
    { num: '5.6', titulo: 'Registro de estadísticas de siniestralidad OAL', constante: 'Se evidencia certificado solicitado.' },
    { num: '5.7', titulo: 'Cumplimiento de herramientas preventivas SAFEWORK (GCOM, ART, permisos de trabajo, etc.)' },
  ]},
  { titulo: '6.- Investigación y aprendizajes de incidentes', subs: [
    { num: '6.1', titulo: 'Incidentes con lesión y/o cuasi accidentes de alto potencial y/o daño material y/o HPRI',
      constante: 'No aplica, se informa que no hubo eventos con la clasificación descrita en el requerimiento.' },
    { num: '6.2', titulo: 'Si ocurrieron incidentes: entrega a tiempo de toda la información',
      constante: 'No aplica, se informa que no hubo eventos con la clasificación descrita en el requerimiento.' },
    { num: '6.3', titulo: 'Difusión de accidentes CAP, boletines de seguridad y aprendizajes Glencore' },
  ]},
  { titulo: '7.- Proceso de aseguramiento', subs: [
    { num: '7.1', titulo: 'Cumplimiento de programa de auditorías (propias de la empresa)' },
    { num: '7.2', titulo: 'Autoevaluación del desempeño SAFEWORK',
      constante: 'Se realiza revisión de cumplimiento de actividades en plataforma.' },
    { num: '7.3', titulo: 'Seguimiento y verificación de planes de acción (auditorías, inspecciones, incidentes, otros)',
      constante: 'Sin eventos en el mes.' },
  ]},
]

// ── Evidencias: foto directa, PDF rasterizado con pdfjs ─────────────────────

async function blobEvidencia(path: string): Promise<Blob | null> {
  const url = await urlEvidencia(path)
  if (!url) return null
  try {
    const res = await fetch(url)
    return res.ok ? await res.blob() : null
  } catch { return null }
}

function blobADataUrl(blob: Blob): Promise<string | null> {
  return new Promise((resolve) => {
    const fr = new FileReader()
    fr.onload = () => resolve(fr.result as string)
    fr.onerror = () => resolve(null)
    fr.readAsDataURL(blob)
  })
}

async function pdfPrimeraPagina(blob: Blob): Promise<string | null> {
  try {
    const pdfjs = await import('pdfjs-dist')
    pdfjs.GlobalWorkerOptions.workerSrc = '/plantillas/pdf.worker.min.mjs'
    const doc = await pdfjs.getDocument({ data: await blob.arrayBuffer() }).promise
    const page = await doc.getPage(1)
    const viewport = page.getViewport({ scale: 1.6 })
    const canvas = document.createElement('canvas')
    canvas.width = viewport.width
    canvas.height = viewport.height
    const ctx = canvas.getContext('2d')
    if (!ctx) return null
    await page.render({ canvasContext: ctx, viewport } as any).promise
    const data = canvas.toDataURL('image/jpeg', 0.85)
    await doc.destroy()
    return data
  } catch {
    return null
  }
}

// ── El PPT ──────────────────────────────────────────────────────────────────

export async function generarAnexo102Pptx(params: {
  registros: PrevencionRegistro[]   // registros del mes de la faena
  faenaNombre: string               // «Lomas Bayas — Lubricantes» / «— Combustible»
  anio: number
  mes: number
  onProgreso?: (msg: string) => void
}): Promise<Blob> {
  const { registros, faenaNombre, anio, mes, onProgreso } = params
  const servicio = faenaNombre.toLowerCase().includes('lubricante') ? 'LUBRICANTES' : 'COMBUSTIBLE'

  // Evidencias por subsección: registros ANEXO102 cuyo título empieza con el
  // número («1.1.- …»). Otros registros con evidencia no entran: la guía manda.
  const porSub = new Map<string, PrevencionRegistro[]>()
  for (const r of registros) {
    if (r.tipo_codigo !== 'ANEXO102') continue
    const m = r.titulo.match(/^(\d+\.\d+)/)
    if (!m) continue
    if (!porSub.has(m[1])) porSub.set(m[1], [])
    porSub.get(m[1])!.push(r)
  }

  const pptx = new PptxGenJS()
  pptx.defineLayout({ name: 'W', width: 13.33, height: 7.5 })
  pptx.layout = 'W'

  // Portada — como la real
  const p = pptx.addSlide()
  p.background = { color: 'FFFFFF' }
  p.addShape('rect', { x: 0, y: 5.0, w: 13.33, h: 2.5, fill: { color: AZUL } })
  p.addText(`REPORTE DE CUMPLIMIENTO ANEXO 10.2 ${MESES[mes - 1]} ${anio}`, {
    x: 1.0, y: 2.1, w: 11.3, h: 1.3, fontSize: 32, bold: true, color: AZUL, align: 'center',
  })
  p.addText(`FAENA LOMAS BAYAS\n${servicio}`, {
    x: 3.8, y: 3.6, w: 5.7, h: 1.0, fontSize: 18, color: GRIS, align: 'center',
  })
  p.addText('Pillado y Cía. Ltda. · Prevención de Riesgos', {
    x: 1.0, y: 5.9, w: 11.3, h: 0.5, fontSize: 14, color: 'FFFFFF', align: 'center',
  })

  // Una lámina por subsección (láminas extra si hay más de 3 evidencias)
  let totalEv = 0
  for (const sec of ESTRUCTURA) for (const sub of sec.subs) totalEv += (porSub.get(sub.num) ?? []).length
  let hechas = 0

  for (const sec of ESTRUCTURA) {
    for (const sub of sec.subs) {
      const regs = sub.siempreConstante ? [] : (porSub.get(sub.num) ?? [])

      // dataURLs de todas las evidencias de la subsección
      const imagenes: string[] = []
      for (const r of regs) {
        for (const ev of r.evidencias ?? []) {
          onProgreso?.(`Sección ${sub.num} · evidencia ${++hechas} de ${totalEv}…`)
          const blob = await blobEvidencia(ev.path)
          if (!blob) continue
          const data = ev.content_type === 'application/pdf' || ev.nombre.toLowerCase().endsWith('.pdf')
            ? await pdfPrimeraPagina(blob)
            : await blobADataUrl(blob)
          if (data) imagenes.push(data)
        }
      }

      const porLamina = 3
      const laminas = Math.max(1, Math.ceil(imagenes.length / porLamina))
      for (let li = 0; li < laminas; li++) {
        const s = pptx.addSlide()
        s.addShape('rect', { x: 0, y: 0, w: 13.33, h: 0.75, fill: { color: AZUL } })
        s.addText(sec.titulo, {
          x: 0.5, y: 0.05, w: 12.4, h: 0.65, fontSize: 18, bold: true, color: 'FFFFFF',
        })
        s.addText(`${sub.num}.- ${sub.titulo}${laminas > 1 ? ` (${li + 1}/${laminas})` : ''}`, {
          x: 0.5, y: 0.95, w: 12.4, h: 0.8, fontSize: 13, bold: true, color: GRIS,
        })

        const lote = imagenes.slice(li * porLamina, (li + 1) * porLamina)
        if (lote.length) {
          const w = lote.length === 1 ? 7.5 : lote.length === 2 ? 5.6 : 3.9
          const h = 4.6
          let x = (13.33 - (w * lote.length + 0.4 * (lote.length - 1))) / 2
          for (const data of lote) {
            s.addImage({ data, x, y: 2.0, w, h, sizing: { type: 'contain', w, h } })
            x += w + 0.4
          }
          const desc = regs.map((r) => r.descripcion).filter(Boolean)[0]
          if (li === 0 && desc) {
            s.addText(String(desc).slice(0, 220), { x: 0.5, y: 6.8, w: 12.4, h: 0.5, fontSize: 10, color: '666666' })
          }
        } else {
          s.addText(sub.constante ?? SIN_EVIDENCIA, {
            x: 0.8, y: 2.6, w: 11.7, h: 1.4, fontSize: 14, color: '555555', italic: !sub.constante,
          })
        }
      }
    }
  }

  const out = await pptx.write({ outputType: 'blob' })
  return out as Blob
}
