// ============================================================================
// Informe de recobro en Word (MIG255).
//
// Replica el formato que usa Pillado en «informe_KVWD-27 Devolucion.docx»:
//   encabezado con logo y datos del equipo → I. DESVIACIONES DETECTADAS (lista
//   numerada) → II. REGISTRO FOTOGRÁFICO DE HALLAZGOS (foto + Diagnóstico /
//   Medida Correctiva / Amerita Recobro por cada uno) → nota final → firma.
//
// Los campos que nadie llenó salen como «POR COMPLETAR», igual que en la
// plantilla original, para que se vea qué falta antes de mandarlo al cliente.
// ============================================================================
import {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  WidthType, AlignmentType, ImageRun, Header, Footer, TabStopType,
} from 'docx'

export type HallazgoWord = {
  descripcion: string
  diagnostico: string | null
  medida_correctiva: string | null
  amerita_recobro: string | null
  observacion: string | null
  fotos: string[]
}

export type InformeWord = {
  folio: string | null
  cliente_nombre: string | null
  fecha_recepcion: string | null
  ciudad: string | null
  lugar_chequeo: string | null
  tecnico_cargo: string | null
  elaborado_por: string | null
  patente: string | null
  equipo_nombre: string | null
  marca: string | null
  modelo: string | null
  n_chasis: string | null
  horometro: string | null
  kilometraje: string | null
  meter_ingreso: string | null
  meter_salida: string | null
  nota_final: string | null
  firmante_nombre: string | null
  firmante_cargo: string | null
}

const PENDIENTE = 'POR COMPLETAR'
const v = (x: string | null | undefined) => (x && x.trim() ? x.trim() : PENDIENTE)

const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']

function fechaLarga(iso?: string | null): string {
  const d = iso ? new Date(`${iso}T12:00:00`) : new Date()
  return `${d.getDate()} de ${MESES[d.getMonth()]} de ${d.getFullYear()}`
}

function fechaCorta(iso?: string | null): string {
  if (!iso) return PENDIENTE
  const d = new Date(`${iso}T12:00:00`)
  const dd = String(d.getDate()).padStart(2, '0')
  const mm = String(d.getMonth() + 1).padStart(2, '0')
  return `${dd}-${mm}-${d.getFullYear()}`
}

// Word exige declarar el formato real de la imagen: mandar un PNG rotulado como
// jpg deja la foto corrupta en el documento.
type TipoImg = 'jpg' | 'png' | 'gif' | 'bmp'
type FotoEmbebida = { data: ArrayBuffer; tipo: TipoImg }

function tipoDesdeUrl(url: string, contentType?: string | null): TipoImg {
  const s = `${contentType ?? ''} ${url.split('?')[0]}`.toLowerCase()
  if (s.includes('png')) return 'png'
  if (s.includes('gif')) return 'gif'
  if (s.includes('bmp')) return 'bmp'
  return 'jpg'
}

/** Descarga la foto para incrustarla. Si falla (permisos, 404, video) se omite. */
async function bajarImagen(url: string): Promise<FotoEmbebida | null> {
  try {
    const r = await fetch(url)
    if (!r.ok) return null
    const ct = r.headers.get('content-type')
    if (ct && !ct.startsWith('image/')) return null   // videos y adjuntos no van
    const data = await r.arrayBuffer()
    if (data.byteLength === 0) return null
    return { data, tipo: tipoDesdeUrl(url, ct) }
  } catch { return null }
}

/** Fila etiqueta/valor del encabezado (etiqueta en negrita, como la plantilla). */
function filaDato(label: string, valor: string): TableRow {
  return new TableRow({
    children: [
      new TableCell({
        width: { size: 32, type: WidthType.PERCENTAGE },
        children: [new Paragraph({ children: [new TextRun({ text: label, bold: true, size: 20 })] })],
      }),
      new TableCell({
        width: { size: 68, type: WidthType.PERCENTAGE },
        children: [new Paragraph({ children: [new TextRun({ text: valor, size: 20 })] })],
      }),
    ],
  })
}

/** Genera el .docx y lo devuelve como Blob listo para descargar. */
export async function generarInformeRecobroWord(
  informe: InformeWord,
  hallazgos: HallazgoWord[],
): Promise<Blob> {
  // Las fotos se bajan en paralelo antes de armar el documento
  const fotosPorHallazgo = await Promise.all(
    hallazgos.map(async (h) => {
      const bufs = await Promise.all((h.fotos ?? []).slice(0, 3).map(bajarImagen))
      return bufs.filter((b): b is FotoEmbebida => b !== null)
    }),
  )

  const hijos: (Paragraph | Table)[] = []

  // ── Ciudad y fecha ────────────────────────────────────────────────────────
  hijos.push(new Paragraph({
    alignment: AlignmentType.RIGHT,
    spacing: { after: 240 },
    children: [new TextRun({
      text: `${informe.ciudad?.trim() || 'Coquimbo'}; ${fechaLarga(informe.fecha_recepcion)}`,
      size: 20,
    })],
  }))

  // ── Título ────────────────────────────────────────────────────────────────
  hijos.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { after: 240 },
    children: [new TextRun({
      text: 'INFORME DE RECEPCIÓN DE EQUIPO – DEVOLUCIÓN POR TÉRMINO DE ARRIENDO',
      bold: true, size: 24,
    })],
  }))

  // ── Datos del equipo ──────────────────────────────────────────────────────
  const marcaModelo = [informe.marca, informe.modelo].filter(Boolean).join(' ')
  hijos.push(new Table({
    width: { size: 100, type: WidthType.PERCENTAGE },
    rows: [
      filaDato('CLIENTE:', v(informe.cliente_nombre)),
      filaDato('FECHA DE RECEPCIÓN:', fechaCorta(informe.fecha_recepcion)),
      filaDato('LUGAR DE CHEQUEO:', v(informe.lugar_chequeo)),
      filaDato('TÉCNICO A CARGO:', v(informe.tecnico_cargo)),
      filaDato('ELABORADO POR:', v(informe.elaborado_por)),
      filaDato('PPU:', v(informe.patente)),
      filaDato('TIPO DE EQUIPO:', v(informe.equipo_nombre)),
      filaDato('MARCA / MODELO:', marcaModelo || PENDIENTE),
      filaDato('N° DE CHASIS:', v(informe.n_chasis)),
      filaDato('HORÓMETRO Y KILOMETRAJE:',
        [informe.horometro, informe.kilometraje].filter(Boolean).join(' - ') || PENDIENTE),
      filaDato('METER INGRESO / METER SALIDA:',
        `${informe.meter_ingreso?.trim() || '---'} / ${informe.meter_salida?.trim() || '---'}`),
    ],
  }))

  // ── I. Desviaciones detectadas ────────────────────────────────────────────
  hijos.push(new Paragraph({
    spacing: { before: 360, after: 120 },
    children: [new TextRun({ text: 'I. DESVIACIONES DETECTADAS:', bold: true, size: 22 })],
  }))
  hijos.push(new Paragraph({
    spacing: { after: 120 },
    children: [new TextRun({
      text: 'La unidad fue sometida a una inspección por nuestro personal mecánico, quienes señalaron las siguientes desviaciones:',
      size: 20,
    })],
  }))
  hallazgos.forEach((h, i) => {
    hijos.push(new Paragraph({
      spacing: { after: 60 },
      children: [new TextRun({ text: `${i + 1}.- Equipo presenta ${h.descripcion}`, size: 20 })],
    }))
  })

  // ── II. Registro fotográfico ──────────────────────────────────────────────
  hijos.push(new Paragraph({
    spacing: { before: 360, after: 120 },
    children: [new TextRun({ text: 'II. REGISTRO FOTOGRÁFICO DE HALLAZGOS:', bold: true, size: 22 })],
  }))

  hallazgos.forEach((h, i) => {
    hijos.push(new Paragraph({
      spacing: { before: 240, after: 120 },
      children: [new TextRun({
        text: `Hallazgo N°${i + 1}: Equipo presenta ${h.descripcion}`,
        bold: true, size: 20,
      })],
    }))

    for (const foto of fotosPorHallazgo[i]) {
      hijos.push(new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { after: 120 },
        children: [new ImageRun({
          data: foto.data,
          transformation: { width: 380, height: 285 },
          type: foto.tipo,
        })],
      }))
    }

    hijos.push(new Table({
      width: { size: 100, type: WidthType.PERCENTAGE },
      rows: [
        filaDato('Diagnóstico:', v(h.diagnostico ?? h.observacion)),
        filaDato('Medida Correctiva:', v(h.medida_correctiva)),
        filaDato('Amerita Recobro:', v(h.amerita_recobro)),
      ],
    }))
  })

  // ── Nota final ────────────────────────────────────────────────────────────
  if (informe.nota_final?.trim()) {
    hijos.push(new Paragraph({
      spacing: { before: 240, after: 120 },
      children: [
        new TextRun({ text: 'Nota: ', bold: true, size: 20 }),
        new TextRun({ text: informe.nota_final.trim(), size: 20 }),
      ],
    }))
  }

  // ── Firma ─────────────────────────────────────────────────────────────────
  hijos.push(new Paragraph({ spacing: { before: 720 }, children: [new TextRun({ text: '___________________________', size: 20 })] }))
  hijos.push(new Paragraph({ children: [new TextRun({ text: v(informe.firmante_nombre), bold: true, size: 20 })] }))
  hijos.push(new Paragraph({ children: [new TextRun({ text: informe.firmante_cargo?.trim() || 'Jefe de Mantenimiento', size: 20 })] }))
  hijos.push(new Paragraph({ children: [new TextRun({ text: 'Pillado y Cía. Ltda.', size: 20 })] }))

  const doc = new Document({
    creator: 'SICOM-ICEO · Pillado Empresas',
    title: `Informe de recobro ${informe.folio ?? ''}`.trim(),
    sections: [{
      properties: {},
      headers: {
        default: new Header({
          children: [new Paragraph({
            alignment: AlignmentType.CENTER,
            children: [
              new TextRun({ text: 'PILLADO EMPRESAS', bold: true, size: 24 }),
              new TextRun({ text: '   Trayectoria y Compromiso', size: 18, color: '666666' }),
            ],
          })],
        }),
      },
      footers: {
        default: new Footer({
          children: [new Paragraph({
            tabStops: [
              { type: TabStopType.CENTER, position: 4500 },
              { type: TabStopType.RIGHT, position: 9000 },
            ],
            children: [new TextRun({
              text: 'Fono: 051 – 2232159\tcontacto@pilladoempresas.cl\twww.pilladoempresas.cl',
              size: 16, color: '666666',
            })],
          })],
        }),
      },
      children: hijos,
    }],
  })

  return Packer.toBlob(doc)
}

/** Dispara la descarga en el navegador. */
export function descargarBlob(blob: Blob, nombreArchivo: string) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = nombreArchivo
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}
