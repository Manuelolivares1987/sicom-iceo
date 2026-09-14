// ============================================================================
// Presentación de evidencias del mes (PPTX, MIG547)
// ----------------------------------------------------------------------------
// El entregable que Lomas Bayas pide como PPT (Anexo 10.2 Lubricantes y
// Combustible, actividades HS para SAFEWORK) y Franke como documentación
// ambiental: una lámina por actividad con sus fotos, título, fecha y
// responsable. Sale un .pptx EDITABLE — prevención le ajusta el texto si el
// mandante pide algo puntual, pero ya no arma 30 láminas a mano.
// Las fotos ya vienen comprimidas del upload (1600px), así que armar el PPT
// no recomprime nada (lección del informe ENEX de 212 MB).
// ============================================================================

// pptxgenjs importa node:fs/node:https (solo se usan en Node): el manejo del
// esquema `node:` para el navegador vive en next.config.js — acá se importa
// normal.
import PptxGenJS from 'pptxgenjs'
import type { FaenaConfigDatos, PrevencionRegistro } from '@/lib/services/prevencion-reportabilidad'
import { urlEvidencia } from '@/lib/services/prevencion-reportabilidad'

const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
  'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']

const AZUL = '1F4E78'

async function fotoADataUrl(path: string): Promise<string | null> {
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
  } catch {
    return null
  }
}

export async function generarPptEvidencias(params: {
  config: FaenaConfigDatos
  registros: PrevencionRegistro[]   // ya filtrados por mes (y tipo si aplica)
  titulo: string                    // nombre del entregable (p.ej. Anexo 10.2)
  faenaNombre: string
  anio: number
  mes: number
  onProgreso?: (hecho: number, total: number) => void
}): Promise<Blob> {
  const { config, registros, titulo, faenaNombre, anio, mes, onProgreso } = params
  const empresa = (config.empresa as any)?.razon_social ?? 'Pillado y Cía. Ltda.'
  const periodo = `${MESES[mes - 1]} ${anio}`

  const pptx = new PptxGenJS()
  pptx.defineLayout({ name: 'W', width: 13.33, height: 7.5 })
  pptx.layout = 'W'

  // ── Portada ──
  const portada = pptx.addSlide()
  portada.background = { color: AZUL }
  portada.addText(titulo, {
    x: 0.6, y: 2.2, w: 12.1, h: 1.4, fontSize: 40, bold: true, color: 'FFFFFF',
  })
  portada.addText(`${empresa} · Faena ${faenaNombre}`, {
    x: 0.6, y: 3.7, w: 12.1, h: 0.6, fontSize: 20, color: 'D9E2F3',
  })
  portada.addText(`${periodo} · Prevención de Riesgos`, {
    x: 0.6, y: 4.3, w: 12.1, h: 0.6, fontSize: 16, color: 'D9E2F3',
  })

  // ── Resumen ──
  const resumen = pptx.addSlide()
  resumen.addText('Resumen del período', {
    x: 0.5, y: 0.3, w: 12.3, h: 0.6, fontSize: 24, bold: true, color: AZUL,
  })
  const porTipo = new Map<string, number>()
  for (const r of registros) porTipo.set(r.tipo_codigo, (porTipo.get(r.tipo_codigo) ?? 0) + 1)
  const filasTabla: PptxGenJS.TableRow[] = [
    [
      { text: 'Actividad', options: { bold: true, fill: { color: AZUL }, color: 'FFFFFF' } },
      { text: 'Cantidad', options: { bold: true, fill: { color: AZUL }, color: 'FFFFFF' } },
    ],
    ...Array.from(porTipo.entries()).map(([t, n]) => [{ text: t }, { text: String(n) }] as PptxGenJS.TableRow),
    [{ text: 'TOTAL', options: { bold: true } }, { text: String(registros.length), options: { bold: true } }],
  ]
  resumen.addTable(filasTabla, { x: 0.5, y: 1.1, w: 5.5, fontSize: 14, border: { pt: 0.5, color: 'BFBFBF' } })

  // ── Una lámina por actividad con evidencia ──
  const conEvidencia = registros.filter((r) => (r.evidencias ?? []).length > 0)
  let hecho = 0
  for (const r of conEvidencia) {
    const slide = pptx.addSlide()
    slide.addShape('rect', { x: 0, y: 0, w: 13.33, h: 0.85, fill: { color: AZUL } })
    slide.addText(`${r.tipo_codigo} · ${r.titulo}`, {
      x: 0.4, y: 0.08, w: 12.5, h: 0.7, fontSize: 18, bold: true, color: 'FFFFFF',
    })
    slide.addText(
      `Fecha: ${r.fecha_actividad}   ·   Responsable: ${r.supervisor_nombre ?? '—'}` +
      (r.area_sector ? `   ·   Área: ${r.area_sector}` : ''),
      { x: 0.4, y: 0.95, w: 12.5, h: 0.4, fontSize: 12, color: '444444' },
    )
    if (r.descripcion) {
      slide.addText(r.descripcion.slice(0, 400), {
        x: 0.4, y: 1.4, w: 12.5, h: 0.7, fontSize: 11, color: '555555',
      })
    }

    // Hasta 2 fotos por lámina, lado a lado.
    const imagenes = (r.evidencias ?? [])
      .filter((e) => e.content_type.startsWith('image/'))
      .slice(0, 2)
    let x = imagenes.length === 1 ? 3.6 : 0.9
    for (const ev of imagenes) {
      const data = await fotoADataUrl(ev.path)
      if (data) {
        slide.addImage({ data, x, y: 2.2, w: 5.9, h: 4.6, sizing: { type: 'contain', w: 5.9, h: 4.6 } })
      }
      x += 6.1
    }
    hecho++
    onProgreso?.(hecho, conEvidencia.length)
  }

  if (conEvidencia.length === 0) {
    const vacia = pptx.addSlide()
    vacia.addText('Sin actividades con evidencia fotográfica en el período.', {
      x: 0.5, y: 3, w: 12.3, h: 1, fontSize: 18, color: '888888', align: 'center',
    })
  }

  const out = await pptx.write({ outputType: 'blob' })
  return out as Blob
}
